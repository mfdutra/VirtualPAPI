import Darwin
import Foundation

/// A UDP socket bound to a port, with a dedicated thread running a blocking
/// receive loop.
///
/// The receiver owns its descriptors for their whole lifetime. `stop()` wakes
/// the loop by writing to a self-pipe it waits on alongside the socket, waits
/// for the thread to exit, and only then closes anything. Closing a descriptor
/// does not reliably interrupt a `recvfrom()` already blocked on it on Darwin,
/// so closing first could leave the thread parked on a descriptor number the
/// kernel has since handed to something else.
///
/// `open`/`start`/`stop` are meant to be called from the owner's actor (the
/// readers call them from the main actor); the receive loop itself never
/// touches that state.
nonisolated final class UDPReceiver: @unchecked Sendable {
    let port: UInt16
    private let label: String
    private let socketFD: Int32
    private let wakeReadFD: Int32
    private let wakeWriteFD: Int32
    /// Signalled by the receive thread right before it finishes.
    private let threadExited = DispatchSemaphore(value: 0)
    private var didStart = false
    private var didStop = false

    /// Safety net for `stop()`: the loop only has to come back from `poll()`,
    /// so waiting this long should never actually happen.
    private static let stopTimeout: TimeInterval = 2.0

    private init(port: UInt16, label: String, socketFD: Int32, wakeReadFD: Int32, wakeWriteFD: Int32)
    {
        self.port = port
        self.label = label
        self.socketFD = socketFD
        self.wakeReadFD = wakeReadFD
        self.wakeWriteFD = wakeWriteFD
    }

    /// Opens a UDP socket bound to `INADDR_ANY:port` plus the pipe used to wake
    /// its receive loop. Returns nil (after logging) if any step fails.
    static func open(port: UInt16, label: String) -> UDPReceiver? {
        guard let fd = openSocket(port: port, label: label) else { return nil }

        var wake: [Int32] = [-1, -1]
        guard pipe(&wake) == 0 else {
            print("\(label): failed to create wake pipe: \(String(cString: strerror(errno)))")
            close(fd)
            return nil
        }

        return UDPReceiver(
            port: port, label: label, socketFD: fd, wakeReadFD: wake[0], wakeWriteFD: wake[1])
    }

    private static func openSocket(port: UInt16, label: String) -> Int32? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            print("\(label): failed to create socket for port \(port): \(String(cString: strerror(errno)))")
            return nil
        }

        // Never call connect() on this socket: a "connected" socket takes
        // priority over other apps' plain listening sockets for matching
        // packets, which would steal broadcast traffic from them.
        var reuseAddr: Int32 = 1
        setsockopt(
            fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr,
            socklen_t(MemoryLayout<Int32>.size))
        var reusePort: Int32 = 1
        setsockopt(
            fd, SOL_SOCKET, SO_REUSEPORT, &reusePort,
            socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            print("\(label): bind to port \(port) failed: \(String(cString: strerror(errno)))")
            close(fd)
            return nil
        }

        return fd
    }

    /// Starts the receive thread. `onDatagram` runs on that thread for every
    /// non-empty datagram. `onUnexpectedExit` also runs there, but only when
    /// the loop ended on its own (a socket error) rather than through `stop()`.
    ///
    /// The thread holds a strong reference to the receiver, so the descriptors
    /// stay valid for as long as the loop can use them.
    func start(
        onDatagram: @escaping @Sendable (Data) -> Void,
        onUnexpectedExit: @escaping @Sendable () -> Void
    ) {
        guard !didStart, !didStop else { return }
        didStart = true

        let thread = Thread {
            let stoppedOnRequest = self.receiveLoop(onDatagram: onDatagram)
            // Signal before reporting, so a stop() waiting on the main actor
            // is never blocked by work that needs the main actor itself.
            self.threadExited.signal()
            if !stoppedOnRequest {
                onUnexpectedExit()
            }
        }
        thread.name = "\(label.lowercased())-udp-receive-\(port)"
        thread.start()
    }

    /// Blocking loop. Returns true when woken by `stop()`, false when it ended
    /// on its own after a fatal socket error.
    ///
    /// Zero-length datagrams are valid on a datagram socket (not EOF) and are
    /// skipped; transient errors (EINTR, EAGAIN/EWOULDBLOCK) are retried.
    private func receiveLoop(onDatagram: (Data) -> Void) -> Bool {
        var buffer = [UInt8](repeating: 0, count: 65536)
        var fds = [
            pollfd(fd: socketFD, events: Int16(POLLIN), revents: 0),
            pollfd(fd: wakeReadFD, events: Int16(POLLIN), revents: 0),
        ]

        while true {
            let ready = poll(&fds, nfds_t(fds.count), -1)
            if ready < 0 {
                let err = errno
                if err == EINTR || err == EAGAIN { continue }
                print("\(label): poll on port \(port) failed: \(String(cString: strerror(err)))")
                return false
            }

            // stop() wrote to the pipe. Return without touching the socket: the
            // thread waiting for us closes it once we're gone.
            if fds[1].revents != 0 { return true }

            guard fds[0].revents & Int16(POLLIN) != 0 else {
                // Nothing to read and no error: spurious wakeup, poll again.
                if fds[0].revents == 0 { continue }
                print("\(label): socket on port \(port) failed: poll revents \(fds[0].revents)")
                return false
            }

            let bytesRead = buffer.withUnsafeMutableBytes { ptr -> Int in
                recvfrom(socketFD, ptr.baseAddress, ptr.count, 0, nil, nil)
            }

            if bytesRead > 0 {
                onDatagram(Data(bytes: buffer, count: bytesRead))
            } else if bytesRead < 0 {
                let err = errno
                if err == EINTR || err == EAGAIN || err == EWOULDBLOCK { continue }
                print("\(label): recvfrom on port \(port) failed: \(String(cString: strerror(err)))")
                return false
            }
            // bytesRead == 0: empty datagram, keep listening
        }
    }

    /// Wakes the receive loop, waits for its thread to exit, then closes the
    /// descriptors. Idempotent. In the unreachable case where the thread does
    /// not exit in time the descriptors are left open, since leaking them is
    /// better than having their numbers recycled under a live loop.
    func stop() {
        guard !didStop else { return }
        didStop = true

        if didStart {
            var token: UInt8 = 1
            _ = write(wakeWriteFD, &token, 1)

            guard threadExited.wait(timeout: .now() + Self.stopTimeout) == .success else {
                print("\(label): receive thread on port \(port) did not exit; leaking its sockets")
                return
            }
        }

        close(socketFD)
        close(wakeReadFD)
        close(wakeWriteFD)
    }

    deinit {
        // Only reachable once the receive thread has released its reference,
        // i.e. after the loop returned, so this never waits.
        stop()
    }
}
