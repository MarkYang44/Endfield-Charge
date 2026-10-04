# Telemetry Implementation Plan

> For agentic workers: use subagent-driven-development for the independent collection/UI tasks and review each delivery before final integration.

**Goal:** implement the approved power, CPU/memory and thermal terminal while retaining the reference art, animation and lightweight resident.

**Architecture:** ChargeCore owns telemetry data and deterministic math; one native monitor samples resident data. Existing private pipe lifecycle hosts a second UI role; the header reuses the exact HUD renderer and timing, then sleeps. No graph history crosses the pipe.

**Tech stack:** Swift, Foundation, AppKit, Mach, IOKit, Darwin sysctl, existing Swift Testing/runtime checks.

## Global Constraints

- macOS 13+, arm64/x86_64, no third-party package/runtime or ordinary network access.
- Preserve original power animations, supplied SVG/menu icon, approximate Wh semantics, all legacy JSON preferences and ⌘⇧E.
- Original 560×60→90→60 silhouette, Geo.Bolt, charcoal/off-white/lime/red, fixed visible top and 2 pt menu-bar gap.
- Unknown data remains unknown; adapter-reported power is distinct from estimated signed battery-side W.
- One added resident timer: 2 s visible / 30 s background; disabled module collection off; graph buffer max 300 in on-demand UI only.
- Follow exact model/controller/monitor signatures in approved spec. Parent does not apply child telemetry preferences; parent-to-child snapshot contains one sample.
- Parent alone handles commits, packaging, app restarts and publication; implementers own disjoint files.

### Task 1: Telemetry collection and deterministic math

**Files:** create Sources/ChargeCore/Telemetry.swift; Tests/ChargeCoreTests/TelemetryTests.swift; Sources/EndfieldCharge/TelemetryReader.swift; Sources/EndfieldCharge/TelemetryMonitor.swift.

**Interfaces:** model types and TelemetryMonitor signatures are defined in the approved spec. Reader exposes `read(battery: BatterySnapshot, powerEnabled: Bool, computeEnabled: Bool, thermalEnabled: Bool) -> TelemetrySnapshot`, CPU reader state retained inside reader/monitor. Monitor refers to the three Preferences toggles which parent adds in Task 3.

- [x] Write focused tests first. For example tick totals `(user:10,system:10,idle:80,nice:0)`→`(20,20,160,0)` produce 0.2; first sample/reset returns nil. Raw 32/64-bit unsigned representations of negative amperage decode to signed current. 12,000 mV × −1,000 mA gives −12 W. Missing/invalid voltage stays nil.
- [x] Run `bash scripts/test.sh` and record expected failures before implementing math. Bounded average tests must check elapsed-time weighting, charging/gap reset and sample cap, not mirror internal array operations.
- [x] Implement typed math/snapshots. Read CPU with HOST_CPU_LOAD_INFO, memory with HOST_VM_INFO64/page size, Swap via vm.swapusage, pressure via event/sysctl with unknown fallback, thermal via ProcessInfo. For battery current parse actual registry widths safely; adapter detail keys are optional. Do not mix unrelated capacity units or fabricate battery health/temperature.
- [x] Implement one monitor timer and resource cleanup; no per-sample shell process. Start/wake establish new CPU baseline; no alerts from initial thermal state. Emit only useful snapshots and apply changed preferences promptly.
- [x] Run focused/core tests, inspect real sample, self-review semantics/ownership. Report files/tests and concerns; no commits or live app mutation.

### Task 2: Endfield telemetry window

**Files:** create Sources/EndfieldCharge/TelemetryView.swift; TelemetryWindowController.swift; TelemetryApplicationDelegate.swift.

**Interfaces:** consume Task 1 model, AppSettings, HUDView/HUDFrame, SettingsChannel/SettingsMessage. Use exact controller interface in spec. Parent adds `SettingsMessage.Command.telemetry` and optional telemetry payload in Task 3.

- [x] Implement POWER/COMPUTE/THERMAL native pages with actual data, module-disabled and unknown states, thermal translated captions and approximate memory/power labels.
- [x] Header contains existing HUDView with real snapshot/preferences. Advance original timeline at 60 Hz until 2.52 s (0.15 s Reduce Motion), then stop timer. No modification of existing power renderer is needed for the panel header.
- [x] Use native accessible page/preview controls, terminal separators, original colors/type/bolt/rounded geometry. Allocate a bounded graph only while panel exists; no permanent animation when settled or hidden.
- [x] Implement child `.ready/.show/.screen/.closed/.closeAck/.reopen/.preview` protocol and `.telemetry` reception. Closing flushes writes, awaits ack with 2 s fallback, then exits; stdin EOF exits. No battery listener, menu item or exclusive hotkey in child.
- [x] Provide deterministic render method matching HUD PNG exporter for all pages; honor language/Reduce Motion and preserve tab/frame. Self-review lifetime; parent adds/runs native checks and visual inspection. No commits/restarts.

### Task 3: Resident integration, controls and verification

**Files:** modify Preferences.swift, SettingsMessage.swift, SettingsProcessController.swift, AppDelegate.swift, SettingsWindowController.swift, SettingsPages.swift, HUDView.swift, main.swift, scripts/check-runtime.sh, Tests/RuntimeChecks/main.swift; add/update telemetry docs and README.

- [x] Add missing-field defaults `powerTelemetryEnabled`, `computeTelemetryEnabled`, `thermalTelemetryEnabled`, `thermalAlert` = true and migration tests. Persist without changing prior values.
- [x] Add `.telemetry` payload to private message; parameterize existing UI-process controller role (settings default, telemetry explicit), use 5 settings tabs / 3 telemetry tabs. Preserve EOF/exit/rapid-reopen tests. Telemetry-ready must never overwrite resident preferences.
- [x] Add native settings telemetry tab, menu and `--telemetry` entry. Parent owns monitor, caches latest sample, accelerates only while child present, sends snapshots plus updated preferences to telemetry role. Thermal warnings reuse existing HUD with titles/alert color and bounded queue/hysteresis.
- [x] Add `--telemetry-snapshot` (two CPU readings, 1 s apart) and `--render-telemetry output --tab power|compute|thermal [--demo] [--stage seconds]` for reproducible real/demo export. Demo exports visibly identify fixture data.
- [x] Extend meaningful native checks for pages, header settle/release, actual child role and module toggles. Run core/native checks, universal build, lipo/codesign/ZIP/resource equality, real JSON vs OS tools.
- [x] Inspect every telemetry page and opening stages plus Reduce Motion. Compare baseline power renders byte-for-byte; fix any fidelity or clipping issue.
- [x] Measure idle/telemetry-open/telemetry-closed whole-process memory, sampling cost and original settings flow. Resolve final independent review, update evidence/limits, publish source and leave final app resident.
