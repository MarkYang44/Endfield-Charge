import Foundation
import Darwin

/// Only the resident role takes this advisory lock. The settings child never inherits it.
final class ResidentInstance {
    enum LockError: Error { case alreadyRunning(Int32), unavailable(Int32) }
    private let descriptor: Int32

    init(path: String = FileManager.default.temporaryDirectory.appendingPathComponent("Endfield-Charge-resident.lock").path) throws {
        let fd = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw LockError.unavailable(errno) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            var bytes = [UInt8](repeating: 0, count: 32)
            let count = bytes.withUnsafeMutableBytes { pread(fd, $0.baseAddress, $0.count, 0) }
            close(fd)
            if failure == EWOULDBLOCK {
                let text = String(decoding: bytes.prefix(max(0, count)), as: UTF8.self)
                throw LockError.alreadyRunning(Int32(text) ?? 0)
            }
            throw LockError.unavailable(failure)
        }
        descriptor = fd
        ftruncate(fd, 0)
        let bytes = Array(String(getpid()).utf8)
        _ = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
    }

    deinit { close(descriptor) }
}
