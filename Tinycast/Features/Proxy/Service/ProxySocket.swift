import Foundation
import Synchronization

/// One controller connection, whose blocking reads a cancellation can interrupt at any moment.
final class ProxySocket: Sendable {
    enum Failure: Error, Equatable, Sendable {
        case unreachable(Int32)
        case timedOut
        case closed
    }

    private enum State: Sendable {
        case waiting
        case open(Int32)
        case interrupted(Int32?)
        case closed
    }

    private let state = Mutex(State.waiting)

    init() {}

    /// Owns `descriptor` from now on, closing it at once when the caller has already given up.
    func adopt(_ descriptor: Int32) throws {
        let adopted = state.withLock { state in
            guard case .waiting = state else { return false }
            state = .open(descriptor)
            return true
        }
        guard adopted else {
            Darwin.close(descriptor)
            throw CancellationError()
        }
    }

    /// Shuts the socket down rather than closing it, so its number cannot be reused under a reader.
    func interrupt() {
        state.withLock { state in
            switch state {
            case .waiting: state = .interrupted(nil)
            case .open(let descriptor):
                Darwin.shutdown(descriptor, SHUT_RDWR)
                state = .interrupted(descriptor)
            case .interrupted, .closed: break
            }
        }
    }

    func close() {
        state.withLock { state in
            switch state {
            case .open(let descriptor), .interrupted(.some(let descriptor)): Darwin.close(descriptor)
            case .waiting, .interrupted(.none), .closed: break
            }
            state = .closed
        }
    }

    func setTimeout(_ duration: Duration) {
        guard let descriptor else { return }
        let (seconds, attoseconds) = duration.components
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32(attoseconds / 1_000_000_000_000))
        let size = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &value, size)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &value, size)
    }

    func write(_ data: Data) throws(Failure) {
        guard let descriptor else { throw .closed }
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { bytes in
                Darwin.write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
            }
            if written > 0 {
                offset += written
            } else if written < 0, errno == EINTR {
                continue
            } else {
                throw errno == EAGAIN ? .timedOut : .closed
            }
        }
    }

    /// The number of bytes read, zero once the peer has closed or the socket was interrupted.
    func read(into buffer: inout [UInt8]) throws(Failure) -> Int {
        guard let descriptor else { throw .closed }
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count >= 0 { return count }
            if errno == EINTR { continue }
            throw errno == EAGAIN ? .timedOut : .closed
        }
    }

    private var descriptor: Int32? {
        state.withLock { state in
            switch state {
            case .open(let descriptor), .interrupted(.some(let descriptor)): descriptor
            case .waiting, .interrupted(.none), .closed: nil
            }
        }
    }

    /// A stream socket connected to `path`, which must fit the 104 bytes `sockaddr_un` holds.
    static func connect(path: String) throws(Failure) -> Int32 {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw .unreachable(ENAMETOOLONG)
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw .unreachable(errno) }
        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw .unreachable(code)
        }
        return descriptor
    }

    /// A stream socket connected to `port` on 127.0.0.1, and the local port it was given.
    static func connect(loopbackPort port: Int) throws(Failure) -> (descriptor: Int32, localPort: Int) {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_port = in_port_t(UInt16(clamping: port).bigEndian)
        address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw .unreachable(errno) }
        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                Darwin.connect(descriptor, address, size) == 0 ? getsockname(descriptor, address, &size) : -1
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw .unreachable(code)
        }
        return (descriptor, Int(UInt16(bigEndian: address.sin_port)))
    }
}
