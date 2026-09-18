import Darwin
import Foundation

/// Blocking receive loop for a bound (never connected) UDP socket.
///
/// Calls `onDatagram` for every non-empty datagram. Zero-length datagrams are
/// valid on a datagram socket (not EOF) and are skipped. Transient errors
/// (EINTR, EAGAIN/EWOULDBLOCK) are retried. Returns only on a fatal error,
/// e.g. EBADF after the socket was closed by `stopListening()`.
nonisolated func runUDPReceiveLoop(fd: Int32, label: String, onDatagram: (Data) -> Void) {
    var buffer = [UInt8](repeating: 0, count: 65536)

    while true {
        let bytesRead = buffer.withUnsafeMutableBytes { ptr -> Int in
            recvfrom(fd, ptr.baseAddress, ptr.count, 0, nil, nil)
        }

        if bytesRead > 0 {
            onDatagram(Data(bytes: buffer, count: bytesRead))
        } else if bytesRead < 0 {
            let err = errno
            if err == EINTR || err == EAGAIN || err == EWOULDBLOCK { continue }
            if err != EBADF {
                print("\(label): recvfrom failed: \(String(cString: strerror(err)))")
            }
            return
        }
        // bytesRead == 0: empty datagram, keep listening
    }
}
