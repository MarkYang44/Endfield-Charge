import Foundation
import Darwin
import ChargeCore

/// NET_RT_IFLIST2 collection adapted from GlacierGlimmer/zmd-charge-plus-for-macos
/// b743c59, native/ecpmac.m (MIT). Reads only 64-bit physical-interface counters; no addresses/probes.
final class NetworkReader {
    private var sampler = NetworkRateSampler()
    func reset() { sampler.reset() }
    func read(at uptime: Double) -> NetworkTelemetry? { sampler.sample(Self.readCounters(), at: uptime) }

    private static func readCounters() -> [NetworkInterfaceCounter]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0,
              size > 0, size <= 16 * 1024 * 1024 else { return nil }
        let capacity = size
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: MemoryLayout<if_msghdr2>.alignment)
        defer { buffer.deallocate() }
        guard sysctl(&mib, u_int(mib.count), buffer, &size, nil, 0) == 0,
              size > 0, size <= capacity else { return nil }
        return parseCounters(UnsafeRawBufferPointer(start: buffer, count: size))
    }

    // Every route record shares only this four-byte prefix; address records may be smaller
    // than if_msghdr. Inspect their prefix without loading either if_data layout.
    static func parseCounters(_ buffer: UnsafeRawBufferPointer) -> [NetworkInterfaceCounter]? {
        let size = buffer.count
        var offset = 0, counters: [NetworkInterfaceCounter] = []
        while offset < size {
            guard size - offset >= 4 else { return nil }
            let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            let version = buffer.load(fromByteOffset: offset + 2, as: UInt8.self)
            let type = buffer.load(fromByteOffset: offset + 3, as: UInt8.self)
            guard length >= 4, length <= size - offset, version == RTM_VERSION else { return nil }
            if type == RTM_IFINFO2 {
                guard length >= MemoryLayout<if_msghdr2>.size else { return nil }
                let message = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                if message.ifm_flags & IFF_UP != 0, message.ifm_flags & IFF_LOOPBACK == 0,
                   if_indextoname(UInt32(message.ifm_index), &nameBuffer) != nil {
                    let name = String(cString: nameBuffer)
                    // macOS physical Ethernet/Wi-Fi interfaces use en<N>; exclude utun/loopback/bridges.
                    if name.hasPrefix("en"), !name.dropFirst(2).isEmpty,
                       name.dropFirst(2).allSatisfy({ $0.isASCII && $0.isNumber }) {
                        counters.append(NetworkInterfaceCounter(name: name, index: UInt32(message.ifm_index),
                            receivedBytes: message.ifm_data.ifi_ibytes, sentBytes: message.ifm_data.ifi_obytes))
                    }
                }
            }
            offset += length
        }
        return counters
    }
}
