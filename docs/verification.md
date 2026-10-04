# Verification record

## Confirmed locally

- Native Apple Silicon Mac running macOS 27 with Apple Command Line Tools Swift 6.4.
- `bash scripts/test.sh`: 16 tests passed. Coverage includes normalized IOPS percentage, physical capacity pairs including empty batteries, missing data, AC connection independent of charging, threshold crossings, full-charge hysteresis, low-power transitions, Codable and normal/reduced-motion HUD timelines.
- Core work used red/green verification. Four depleted-capacity regressions failed before the paired-capacity fix; completion and reduced-motion regressions failed before their fixes.
- `bash scripts/build-app.sh --universal`: arm64 and x86_64 executables compiled and combined. `lipo -info` confirms both architectures. The local CLT linker warned that one Swift compatibility archive lacks x86_64; it still linked successfully. Native Intel runtime behavior was not tested on this Apple Silicon machine.
- `codesign --verify --strict` succeeds; the app is locally ad-hoc signed. Info.plist passes `plutil -lint`; packaged zip passes `unzip -t`.
- Built app launched through LaunchServices and showed the native settings window. General and HUD/Animation pages were inspected through accessibility and a screenshot. Defaults include 80% scale, 6s duration, centered placement, active shortcut and disabled launch at login.
- AppKit exported both mode-title stages and the numeric stage. Visual inspection checked capsule dimensions, dark palette, double-parallelogram bolt, lime ring, laptop screen/base/electrode and capacity-unit label. README previews use explicitly simulated data.
- A live snapshot reported 74% and 364 minutes; `pmset -g batt` independently reported 74% and 6:04 remaining. Its header reported AC Power while AppleSmartBattery.ExternalConnected reported false. The app prioritizes the physical registry connection flag and keeps it independent of the IOPS charging flag; this discrepancy was not silently treated as a match.
- Independent whole-project review raised four findings: completion semantics, reduced-motion alert meaning, badge geometry/color and same-name display identity. All were fixed and the reviewer confirmed resolution.

## Environment restrictions encountered

Sandboxed `iconutil` rejected a dimensionally valid iconset, and sandboxed LaunchServices/AppKit process registration failed. The same authorized packaging, launch and preview export operations succeeded outside the execution sandbox. The product does not require users to disable macOS security protections. SwiftPM native build mode currently produces a deprecation warning; the test framework has a macOS 14 minimum, while the application has a macOS 13 deployment target.

## Verification limits

Physical charger insertion/removal, a real full-battery/low-battery cycle, sleep/wake, multiple real displays, a real subsequent login, macOS 13 runtime behavior and Intel runtime behavior were not independently exercised. Event reducers and visual demos cover their logic but do not prove the corresponding physical system transitions. Apple Developer ID signing and notarization were not performed.

The public GitHub repository was created and confirmed through the authenticated connector. Remote source and CI verification are recorded after upload; this local record does not by itself claim a completed hosted build.
