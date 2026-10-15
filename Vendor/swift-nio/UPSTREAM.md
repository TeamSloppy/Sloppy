# SwiftNIO for Windows

Source: https://github.com/apple/swift-nio, tag `2.101.0`,
revision `77b84ac2cd2ac9e4ac67d19f045fd5b434f56967`
(Apache 2.0; see LICENSE.txt and NOTICE.txt).

The root package uses this copy on Windows. Apple and Linux builds continue to use
the upstream dependency. Only library sources are included; the upstream manifest's
example and test targets are omitted.

Windows patches:

- Wrap thread handles in a Sendable value, retain the handle returned by `_beginthreadex`,
  and close it after joining. The upstream implementation discarded the created handle.
- Convert WinSDK's `IPPROTO_UDP` enum through its raw value.
- Complete WSAPoll registration updates and removal, lifecycle initialization and loop callbacks.
  Use a nonblocking loopback UDP socket to wake a blocked poll from another thread.
- Snapshot ready registrations before callbacks and reject stale registration IDs.
- Use real duplicated thread handles and Windows thread IDs for cross-thread operations.
- Normalize Winsock error codes for the existing errno-based socket state machines.
- Treat nonblocking accept/read/write/connect results as pending I/O, preserving listeners and channels.
- Supply Windows scatter/gather I/O limits and shutdown constants used by channel writes and closes.
- Round up adapter-enumeration storage to fit the full byte count returned by Windows.
