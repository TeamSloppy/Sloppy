import Foundation

/// Portable streaming content identity shared by journal blobs and plugin archives.
public enum ContentDigest {
    private static let constants: [UInt32] = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]

    public static func sha256(_ data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data)
        return hasher.finalize()
    }

    public static func sha256(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty { hasher.update(chunk) }
        return hasher.finalize()
    }

    public struct SHA256: Sendable {
        private var h: [UInt32] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
        private var tail: [UInt8] = []
        private var count: UInt64 = 0
        public init() {}

        public mutating func update(_ data: Data) {
            count &+= UInt64(data.count)
            var offset = data.startIndex
            if !tail.isEmpty {
                let length = min(64 - tail.count, data.count)
                tail.append(contentsOf: data[offset..<(offset + length)])
                offset += length
                if tail.count == 64 { compress(tail); tail.removeAll(keepingCapacity: true) }
            }
            while data.endIndex - offset >= 64 {
                compress(Array(data[offset..<(offset + 64)]))
                offset += 64
            }
            tail.append(contentsOf: data[offset..<data.endIndex])
        }

        public func finalize() -> String {
            var copy = self
            let length = count &* 8
            var padding = Data([0x80])
            while (Int(count % 64) + padding.count) % 64 != 56 { padding.append(0) }
            withUnsafeBytes(of: length.bigEndian) { padding.append(contentsOf: $0) }
            copy.update(padding)
            return copy.h.map { String(format: "%08x", $0) }.joined()
        }

        private mutating func compress(_ bytes: [UInt8]) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 { let j = i * 4; w[i] = UInt32(bytes[j]) << 24 | UInt32(bytes[j+1]) << 16 | UInt32(bytes[j+2]) << 8 | UInt32(bytes[j+3]) }
            for i in 16..<64 { let s0 = ContentDigest.rotate(w[i-15], 7) ^ ContentDigest.rotate(w[i-15], 18) ^ (w[i-15] >> 3); let s1 = ContentDigest.rotate(w[i-2], 17) ^ ContentDigest.rotate(w[i-2], 19) ^ (w[i-2] >> 10); w[i] = w[i-16] &+ s0 &+ w[i-7] &+ s1 }
            var a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],hh=h[7]
            for i in 0..<64 { let s1=ContentDigest.rotate(e,6)^ContentDigest.rotate(e,11)^ContentDigest.rotate(e,25); let ch=(e&f)^((~e)&g); let t1=hh&+s1&+ch&+ContentDigest.constants[i]&+w[i]; let s0=ContentDigest.rotate(a,2)^ContentDigest.rotate(a,13)^ContentDigest.rotate(a,22); let maj=(a&b)^(a&c)^(b&c); let t2=s0&+maj; hh=g;g=f;f=e;e=d&+t1;d=c;c=b;b=a;a=t1&+t2 }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d
            h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
    }
    private static func rotate(_ value: UInt32, _ amount: UInt32) -> UInt32 { (value >> amount) | (value << (32 - amount)) }
}
