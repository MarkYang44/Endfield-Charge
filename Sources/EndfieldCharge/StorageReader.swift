import Foundation
import Darwin
import ChargeCore

/// Data-volume statfs accounting adapted from GlacierGlimmer/zmd-charge-plus-for-macos
/// b743c59, native/ecpmac.m (MIT). APFS free space is shared; available excludes reserved blocks.
enum StorageReader {
    static func read() -> StorageTelemetry? {
        var info = statfs()
        var path = "/System/Volumes/Data"
        if statfs(path, &info) != 0 {
            path = "/"
            guard statfs(path, &info) == 0 else { return nil }
        }
        guard info.f_bsize > 0 else { return nil }
        let blockSize = UInt64(info.f_bsize)
        let total = info.f_blocks.multipliedReportingOverflow(by: blockSize)
        let free = info.f_bfree.multipliedReportingOverflow(by: blockSize)
        let available = info.f_bavail.multipliedReportingOverflow(by: blockSize)
        guard !total.overflow, !free.overflow, !available.overflow else { return nil }
        let fileSystem = withUnsafeBytes(of: info.f_fstypename) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return StorageTelemetry(totalBytes: total.partialValue, freeBytes: free.partialValue,
            availableBytes: available.partialValue, path: path, fileSystem: fileSystem)
    }
}
