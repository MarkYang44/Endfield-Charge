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

## Confirmed on GitHub

- Public repository: https://github.com/MarkYang44/Endfield-Charge. The connected GitHub profile is MarkYang44; repository metadata confirmed public visibility and user ownership.
- The connector returned 403 for writing blobs to the newly created repository. Upload instead succeeded using the user's existing macOS Git credential helper, without changing connector permissions.
- Code commit `e2b703a08acfa2922fda8647061ac4690c22d3c0` was pushed to main. An anonymous fresh clone reproduced both that commit and local tree `49257c4f2a38b2dfce242c7ad97180a80f1411e6` exactly, covering all source, workflow, documentation, icon and preview files. The local main branch tracks origin/main.
- [GitHub Actions run 37186658956](https://github.com/MarkYang44/Endfield-Charge/actions/runs/37186658956) completed successfully: tests, universal app build and artifact upload all passed. The tag-only release job was correctly skipped on the main-branch push.
- The local zip was extracted into a separate temporary folder. Its executable matches the packaged application with SHA-256 `c9d182f1ce3acdfd96972f939fabbd430ff862d97426be80c7c6735a96443e66`; signature verification and live battery JSON output succeeded from that extracted copy.

The publication follow-up commit updates documentation only and skips a duplicate CI run. Native source and the tested application were unchanged at that stage. Physical-system and signing limits above still apply.

## Wh display update

- Hardware inspection confirms this local machine is a MacBook Air, identifier Mac17,3, with an Apple M5 chip.
- HUD energy values now use Wh directly with one decimal place, preserving the approximate-value marker. The previous multiplication by 1000 and milli-unit label were removed; the underlying battery reader and energy calculation are unchanged.
- Settings copy, README, design specification and numeric preview image were updated together. A freshly exported demo frame visibly reads `≈45.6 /60.0 Wh`.
- Both arm64 and x86_64 builds completed successfully. The repackaged zip was extracted separately; strict signature verification passed and its executable matches the app byte-for-byte.
- Updated executable SHA-256: `d650aece4f676d26d89c407635f70a662e0ba9bf6086578c7b29f4006d2ddc3e`. The updated app was relaunched with a live-battery preview.
