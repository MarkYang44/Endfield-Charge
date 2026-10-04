# Approved telemetry extension

User approved power details + CPU/memory + thermal state, with strict fidelity to Endfield and QinAnze/zmd-charge. Preserve lightweight modular runtime and existing preferences/shortcuts. Network and long-term history are later work.

## Behavior

Menu adds “遥测终端… / Telemetry Terminal…”. `--telemetry` opens it. A same-executable `--telemetry-ui parentPID tab frame` role owns its native window and exits on close. Reuse the existing private pipe and acknowledged close/reopen lifecycle. Ordinary battery previews, charger animations and ⌘⇧E remain intact.

Three telemetry pages: POWER, COMPUTE, THERMAL. POWER shows current battery Wh/percent, signed approximate battery-side W, adapter-reported W, cycles and recent average discharge. COMPUTE shows CPU usage from tick differences, an explicitly approximate active+wired+compressed memory estimate, compressed memory, Swap and system memory pressure. THERMAL shows the four public system states, without inventing a temperature. Unknown fields show —. Disabled modules stop their additional collection. New settings toggles control three modules and thermal alerts, with missing-field defaults preserving legacy JSON.

Thermal alerts reuse the existing HUD: skip startup state, alert on entering serious/critical, avoid downgrade/repeat spam and rearm after cooling. Thermal events cannot substitute for exact CPU-temperature or frequency measurements.

## Visual contract

Use the existing 620×144 HUD canvas as the terminal header, its original 560×60→90→60 pill, Geo.Bolt, plate #E9E7E4, body #312F30/#262425, white type, lime #C6CA4C and alert red #FF4D4F. Reuse HUDView/HUDFrame directly; let the opening timeline settle at 2.52 seconds and stop its timer. Honor Reduce Motion. No new gradients, unrelated icons, or replacement artwork. Native metric rows, ring/bar/short curves and thin separators follow the existing terminal typography and geometry. Keep all power-HUD PNGs identical at the previously verified demo stages.

## Runtime and interfaces

ChargeCore adds Codable/Equatable `TelemetrySnapshot`, `PowerTelemetry`, `ComputeTelemetry`; enums `ThermalLevel` and `MemoryPressureLevel`; tested CPU tick sampling, signed current decoding/power math and bounded recent discharge average. Snapshot carries one sample only, not graph history. Telemetry UI holds a bounded 300-point graph buffer and releases it on exit.

`TelemetrySnapshot(sampledAt: Double, battery: BatterySnapshot, power: PowerTelemetry?, compute: ComputeTelemetry?, thermal: ThermalLevel?)`. `sampledAt` is system uptime. `PowerTelemetry` fields: batteryWatts: Double?, averageDischargeWatts: Double?, adapterWatts: Int?, cycleCount: Int?. `ComputeTelemetry` fields: cpuFraction: Double?, memoryUsedBytes: UInt64?, memoryTotalBytes: UInt64, compressedBytes: UInt64?, swapUsedBytes: UInt64?, pressure: MemoryPressureLevel. Thermal cases nominal/fair/serious/critical/unknown; memory pressure normal/warning/critical/unknown.

`TelemetryMonitor` is the sole extra resident sampler. `init(settings: AppSettings, battery: @escaping () -> BatterySnapshot)`, `onSnapshot: ((TelemetrySnapshot)->Void)?`, `onThermalAlert: ((ThermalLevel)->Void)?`, `start()`, `preferencesChanged()`, `setPanelVisible(_ visible: Bool)`, `stop()`. Use one timer, 2 seconds with panel visible, 30 seconds otherwise, appropriate tolerance and wake refresh. No subprocess pollers, privileged services, network, extra packages or filesystem logs in normal use. Collect with Mach/Foundation/IOKit/sysctl; release all returned resources. Existing PowerMonitor remains responsible for battery source transitions.

UI entry: `TelemetryWindowController(settings: AppSettings, selectedTab: Int, frame: NSRect?, onPreview: @escaping ()->Void, onClose: @escaping (Int,NSRect)->Void, onScreenChange: (() -> Void)? = nil)`, `present()`, `update(_ snapshot: TelemetrySnapshot)`, `selectedTab`, `window`, `view: TelemetryView`. `TelemetryView` supports deterministic PNG export and selectable page. UI delegate consumes `.telemetry` snapshots plus preferences; it never sends preference state back to overwrite the resident.

## Acceptance

Meaningful red/green unit tests for counter differences/reset, signed current and unavailable data, bounded power history, thermal alert hysteresis and legacy preferences. Native checks for each page, header timer stopping, actual close/reopen/EOF lifecycle and child ownership. Universal build, strict signing/extraction, real telemetry JSON validation against OS tools, normal/demo/reduced-motion visual exports, unchanged existing HUD pixels, whole-process footprint measurements, final independent review and publication to the already authorized public repository.
