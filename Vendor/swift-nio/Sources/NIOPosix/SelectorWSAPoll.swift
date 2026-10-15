//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2025 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if !os(WASI)

#if os(Windows)
import CNIOWindows
import NIOCore
import NIOConcurrencyHelpers
import WinSDK

extension SelectorEventSet {
    // Use this property to create pollfd's event field. Reset and errors are (hopefully) always included.
    // According to the docs we don't need to listen for them explicitly.
    // Source: https://learn.microsoft.com/en-us/windows/win32/api/winsock2/ns-winsock2-wsapollfd
    var wsaPollEvent: Int16 {
        var result: Int16 = 0
        if self.contains(.read) {
            result |= Int16(WinSDK.POLLRDNORM)
        }
        if self.contains(.write) || self.contains(.writeEOF) {
            result |= Int16(WinSDK.POLLWRNORM)
        }
        return result
    }

    // Use this initializer to create a EventSet from the wsa pollfd's revent field
    @usableFromInline
    init(revents: Int16) {
        // Event Constant   Meaning	                What to do (Typical Socket API)
        // POLLRDNORM       Normal data readable    Use recv, WSARecv, or ReadFile
        // POLLRDBAND       Priority data readable  Use recv, WSARecv (with MSG_OOB for out-of-band)
        // POLLWRNORM       Normal data writable    Use send, WSASend, or WriteFile
        // POLLWRBAND       Priority data writable  Use send (with MSG_OOB for out-of-band data)
        // POLLERR          Error condition         Use getsockopt with SO_ERROR; may need closesocket
        // POLLHUP          Closed                  Usually just cleanup: closesocket
        // POLLNVAL         Invalid fd (not open)   Fix your code; close and remove fd
        self.rawValue = 0
        let mapped = Int32(revents)
        if mapped & WinSDK.POLLRDNORM != 0 {
            self.formUnion(.read)
        }
        if mapped & WinSDK.POLLWRNORM != 0 {
            self.formUnion(.write)
        }
        if mapped & WinSDK.POLLERR != 0 {
            self.formUnion(.error)
        }
        if mapped & WinSDK.POLLHUP != 0 {
            self.formUnion([.read, .readEOF])
        }
        if mapped & WinSDK.POLLNVAL != 0 {
            preconditionFailure("Invalid fd supplied.")
        }
    }
}

extension Selector: _SelectorBackendProtocol {

    func initialiseState0() throws {
        self.pollFDs.reserveCapacity(16)
        let reader = socket(AF_INET, SOCK_DGRAM, Int32(IPPROTO_UDP.rawValue))
        guard reader != INVALID_SOCKET else { throw IOError(winsock: WSAGetLastError(), reason: "wakeup socket") }
        var succeeded = false
        defer { if !succeeded { closesocket(reader) } }
        var address = sockaddr_in()
        address.sin_family = ADDRESS_FAMILY(AF_INET)
        address.sin_addr.S_un.S_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(reader, $0, Int32(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw IOError(winsock: WSAGetLastError(), reason: "wakeup bind") }
        var size = Int32(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(reader, $0, &size) }
        }
        guard named == 0 else { throw IOError(winsock: WSAGetLastError(), reason: "wakeup address") }
        let writer = socket(AF_INET, SOCK_DGRAM, Int32(IPPROTO_UDP.rawValue))
        guard writer != INVALID_SOCKET else { throw IOError(winsock: WSAGetLastError(), reason: "wakeup socket") }
        defer { if !succeeded { closesocket(writer) } }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(writer, $0, size) }
        }
        guard connected == 0 else { throw IOError(winsock: WSAGetLastError(), reason: "wakeup connect") }
        var nonblocking: u_long = 1
        guard ioctlsocket(reader, FIONBIO, &nonblocking) == 0, ioctlsocket(writer, FIONBIO, &nonblocking) == 0 else {
            throw IOError(winsock: WSAGetLastError(), reason: "wakeup nonblocking")
        }
        self.wakeupRead = reader
        self.wakeupWrite = writer
        self.pollFDs.append(pollfd(fd: reader, events: Int16(POLLRDNORM), revents: 0))
        self.selectorFD = 0
        self.lifecycleState = .open
        succeeded = true
    }

    func deinitAssertions0() {
        // no global state. nothing to check
    }

    @inlinable
    func whenReady0(
        strategy: SelectorStrategy,
        onLoopBegin: () -> Void,
        _ body: (SelectorEvent<R>) throws -> Void
    ) throws {
        let time: Int32 =
            switch strategy {
            case .now:
                0

            case .block:
                -1

            case .blockUntilTimeout(let timeAmount):
                Int32(clamping: timeAmount.nanoseconds / 1_000_000)
            }

        let result = self.pollFDs.withUnsafeMutableBufferPointer { pointer in
            WSAPoll(pointer.baseAddress!, UInt32(pointer.count), time)
        }
        if result == SOCKET_ERROR {
            throw IOError(winsock: WSAGetLastError(), reason: "WSAPoll")
        }
        // Callbacks can deregister sockets or reuse their descriptors. Snapshot readiness and
        // registration IDs before executing any callbacks, then revalidate each registration.
        let ready = self.pollFDs.filter { $0.revents != 0 }.map {
            ($0, self.registrations[Int($0.fd)]?.registrationID)
        }
        for index in self.pollFDs.indices { self.pollFDs[index].revents = 0 }
        onLoopBegin()
        for (descriptor, registrationID) in ready {
            if descriptor.fd == self.wakeupRead {
                var bytes = [CChar](repeating: 0, count: 256)
                while recv(self.wakeupRead, &bytes, Int32(bytes.count), 0) > 0 {}
                continue
            }
            guard let registration = self.registrations[Int(descriptor.fd)],
                  registration.registrationID == registrationID else { continue }
            let events = SelectorEventSet(revents: descriptor.revents).intersection(registration.interested)
            if events != ._none { try body(SelectorEvent(io: events, registration: registration)) }
        }
    }

    func register0(
        selectableFD: NIOBSDSocket.Handle,
        fileDescriptor: NIOBSDSocket.Handle,
        interested: SelectorEventSet,
        registrationID: SelectorRegistrationID
    ) throws {
        // TODO (@fabian): We need to replace the pollFDs array with something
        //                 that will allow O(1) access here.
        let poll = pollfd(fd: UInt64(fileDescriptor), events: interested.wsaPollEvent, revents: 0)
        self.pollFDs.append(poll)
    }

    func reregister0(
        selectableFD: NIOBSDSocket.Handle,
        fileDescriptor: NIOBSDSocket.Handle,
        oldInterested: SelectorEventSet,
        newInterested: SelectorEventSet,
        registrationID: SelectorRegistrationID
    ) throws {
        if let index = self.pollFDs.firstIndex(where: { $0.fd == fileDescriptor }) {
            self.pollFDs[index].events = newInterested.wsaPollEvent
        }
    }

    func deregister0(
        selectableFD: NIOBSDSocket.Handle,
        fileDescriptor: NIOBSDSocket.Handle,
        oldInterested: SelectorEventSet,
        registrationID: SelectorRegistrationID
    ) throws {
        self.pollFDs.removeAll { $0.fd == fileDescriptor }
    }

    func wakeup0() throws {
        try self.externalSelectorFDLock.withLock {
            guard self.wakeupWrite != INVALID_SOCKET else { return }
            var byte: CChar = 1
            let sent = send(self.wakeupWrite, &byte, 1, 0)
            if sent == SOCKET_ERROR {
                let error = WSAGetLastError()
                // A full queue already guarantees a wakeup.
                if error != WSAEWOULDBLOCK { throw IOError(winsock: error, reason: "selector wakeup") }
            }
        }
    }

    func close0() throws {
        self.externalSelectorFDLock.withLock {
            closesocket(self.wakeupRead)
            closesocket(self.wakeupWrite)
            self.wakeupRead = INVALID_SOCKET
            self.wakeupWrite = INVALID_SOCKET
            self.selectorFD = -1
        }
        self.pollFDs.removeAll()
    }
}

#endif
#endif  // !os(WASI)
