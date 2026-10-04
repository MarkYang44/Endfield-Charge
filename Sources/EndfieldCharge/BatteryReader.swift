import Foundation
import IOKit
import IOKit.ps
import ChargeCore

enum BatteryReader {
    static func read() -> BatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatterySnapshot(hasBattery: false, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
        let description = sources.compactMap { source -> [String: Any]? in
            guard let dict = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  dict[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  dict[kIOPSIsPresentKey] as? Bool != false else { return nil }
            return dict
        }.first
        guard let description else {
            return BatterySnapshot(hasBattery: false, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
        var registry: [String: Any] = [:]
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS {
                registry = properties?.takeRetainedValue() as? [String: Any] ?? [:]
            }
        }
        return .from(description: description, registry: registry,
                     lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}
