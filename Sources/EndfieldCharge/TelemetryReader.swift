import Foundation
import Darwin
import IOKit
import ChargeCore

final class TelemetryReader {
    private let host = mach_host_self()
    private var cpu = CPUTickSampler()
    private var discharge = RecentDischargeAverage()

    /// Start/wake and re-enabling a module must not integrate stale counters or power.
    func reset() { cpu.reset(); discharge.reset() }

    func read(battery: BatterySnapshot, powerEnabled: Bool, computeEnabled: Bool,
              thermalEnabled: Bool) -> TelemetrySnapshot {
        let uptime = ProcessInfo.processInfo.systemUptime
        let power: PowerTelemetry?
        if powerEnabled { power = readPower(battery: battery, at: uptime) }
        else { discharge.reset(); power = nil }
        let compute: ComputeTelemetry?
        if computeEnabled { compute = readCompute() }
        else { cpu.reset(); compute = nil }
        return TelemetrySnapshot(sampledAt: uptime, battery: battery, power: power,
            compute: compute, thermal: thermalEnabled ? Self.thermalLevel() : nil)
    }

    private func readPower(battery: BatterySnapshot, at uptime: Double) -> PowerTelemetry {
        let registry = batteryRegistry()
        let data = registry["BatteryData"] as? [String: Any] ?? [:]
        let current = TelemetryMath.signedMilliamps(registry["InstantAmperage"] as? NSNumber)
            ?? TelemetryMath.signedMilliamps(registry["Amperage"] as? NSNumber)
            ?? TelemetryMath.signedMilliamps(data["InstantAmperage"] as? NSNumber)
        // Voltage and current come from the same registry reading, not a stale capacity estimate.
        let voltage = nonnegativeInteger(registry["Voltage"]).flatMap { $0 > 0 ? $0 : nil }
        let watts = battery.hasBattery ? TelemetryMath.batteryWatts(voltageMV: voltage, currentMA: current) : nil
        let adapter = registry["AdapterDetails"] as? [String: Any] ?? [:]
        let adapterWatts = nonnegativeInteger(adapter["Watts"]).flatMap { $0 > 0 ? $0 : nil }
        let cycles = nonnegativeInteger(registry["CycleCount"]) ?? nonnegativeInteger(data["CycleCount"])
        let average = discharge.sample(watts: watts, at: uptime,
            discharging: battery.hasBattery && !battery.externalPower && !battery.isCharging)
        return PowerTelemetry(batteryWatts: watts, averageDischargeWatts: average,
            adapterWatts: battery.externalPower ? adapterWatts : nil, cycleCount: battery.hasBattery ? cycles : nil)
    }

    private func nonnegativeInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)), number.int64Value >= 0,
              number.uint64Value <= UInt64(Int.max) else { return nil }
        return number.intValue
    }

    private func batteryRegistry() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS
        else { return [:] }
        return properties?.takeRetainedValue() as? [String: Any] ?? [:]
    }

    private func readCompute() -> ComputeTelemetry {
        var cpuInfo = host_cpu_load_info_data_t()
        var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let cpuStatus = withUnsafeMutablePointer(to: &cpuInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &cpuCount)
            }
        }
        let cpuFraction: Double?
        if cpuStatus == KERN_SUCCESS {
            cpuFraction = cpu.sample(CPUTicks(user: UInt64(cpuInfo.cpu_ticks.0), system: UInt64(cpuInfo.cpu_ticks.1),
                idle: UInt64(cpuInfo.cpu_ticks.2), nice: UInt64(cpuInfo.cpu_ticks.3)))
        } else { cpu.reset(); cpuFraction = nil }

        var vm = vm_statistics64_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let vmStatus = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &vmCount)
            }
        }
        var pageSize: vm_size_t = 0
        let pageStatus = host_page_size(host, &pageSize)
        let compressed: UInt64?, used: UInt64?
        if vmStatus == KERN_SUCCESS, pageStatus == KERN_SUCCESS, pageSize > 0 {
            compressed = UInt64(vm.compressor_page_count) * UInt64(pageSize)
            used = (UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * UInt64(pageSize)
        } else { compressed = nil; used = nil }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapStatus = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        var pressure: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        let pressureStatus = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0)
        let pressureLevel: MemoryPressureLevel
        if pressureStatus == 0, pressureSize == MemoryLayout<Int32>.size {
            switch pressure {
            case 1: pressureLevel = .normal
            case 2: pressureLevel = .warning
            case 4: pressureLevel = .critical
            default: pressureLevel = .unknown
            }
        } else { pressureLevel = .unknown }
        return ComputeTelemetry(cpuFraction: cpuFraction, memoryUsedBytes: used,
            memoryTotalBytes: ProcessInfo.processInfo.physicalMemory, compressedBytes: compressed,
            swapUsedBytes: swapStatus == 0 && swapSize == MemoryLayout<xsw_usage>.size ? swap.xsu_used : nil,
            pressure: pressureLevel)
    }

    private static func thermalLevel() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }

    deinit { mach_port_deallocate(mach_task_self_, host) }
}
