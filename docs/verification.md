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

## Placement next to the menu bar

- Compensated for the transparent canvas inset and anchored the visible pill's top while expanding downward. The target gap below the selected screen's visible top is 2 pt, independent of the HUD scale.
- Runtime coordinate inspection caught AppKit constraining the transparent panel to the menu bar's bottom. The borderless HUD panel now retains its explicitly calculated frame; visible content remains below the menu bar and ignores mouse events.
- On this MacBook at 80% scale, the menu bar ends at screen Y=34 pt and the updated panel starts at Y=14 pt. Adding its 27 × 0.8 pt transparent inset places the visible pill at approximately Y=35.6 pt: a 1.6 pt gap after window pixel rounding. Before removing AppKit's constraint, the panel was forced down to Y=34 pt.
- PNGs rendered at 1.55 s (expanded) and 3 s (collapsed) both have their first visible center pixel at Y=54 in a 2× bitmap, confirming a shared 27 pt top inset. The expanded title and collapsed live-battery HUD were visually inspected.
- Universal arm64/x86_64 build and strict signature verification passed. The final ZIP was extracted separately and its executable matches the running app byte-for-byte. Executable SHA-256: `e39677d8bb2f32a78fac86ac5d9f32da27348c1354cc28efde18ff0d3a68e654`.

## Custom modifiers and Endfield menu bar logo

- All 18 tests passed, including new regression coverage for legacy preference migration (disabled percentage display, scale, language and alerts) and saving/reloading Command + Shift + E. The new Codable model defaults only missing fields rather than resetting all preferences when upgrading.
- The native settings window was inspected after restarting: Command and Shift remain selected and highlighted, Control and Option remain off, and E remains selected. This Mac's pre-existing 60% scale and disabled menu bar percentage were preserved.
- Exclusive Carbon registration was independently verified by attempting to register the same key from a temporary helper: while Endfield Charge is enabled, the helper returns `eventHotKeyExistsErr` (-9878); while disabled, it returns `noErr` (0) and immediately unregisters. Re-enabling restores -9878. The final app remains enabled with Command + Shift + E.
- CUA-generated Command + Shift + E did not produce an observed HUD. A positive control using the settings preview button did show it (screen bounds approximately 373 × 87 pt at 60% scale). The user then tested Command + Shift + E on the physical keyboard and explicitly confirmed that the HUD appeared normally. Persistence, operating-system registration and user-observed physical triggering are verified; the CUA input limitation remains separate.
- The supplied SVG was copied byte-for-byte. The menu icon is a 144 × 144 RGBA export with genuine transparency, displayed as an 18 pt AppKit template image. The artwork was inspected on a light backdrop and both original SVG and PNG are bundled. Runtime and CI require no new dependency.
- Final universal build and strict signature verification passed. A separate extraction of the ZIP matches the app executable and both logo resources byte-for-byte. Executable SHA-256: `77ed35d90bcc005d2a69f8f20f6a8aef1afca62bcd459d82026af61b096d31ef`.
- Implementation commit `8d705aa6db2c5bfe27a6c6069270ae5179b91620` was successfully pushed to the public repository's main branch. This publication follow-up changes documentation only and skips a duplicate CI build.

## Memory, lifecycle and modularization update

- Fresh `bash scripts/test.sh`: all 21 core tests passed, including the added static-hold scheduling tests. Fresh `bash scripts/check-runtime.sh`: all 8 native check groups passed in a graphical session. The native script is a local-only check, not a claimed CI result.
- Native checks cover no-op preference notifications, peer updates without duplicate persistence, resident lock acquisition/release, 200 ordered messages, fragmented close state, flushing before EOF, actual weak window/controller/view release, all four lazy pages, queued alerts during the hold, interrupting previews and repeated HUD lifecycles.
- The real settings-process regression launches the same check executable in the actual child role, requests show while close is pending, and verifies fresh-child preview plus preserved tab/frame. Both children naturally terminate in under 1.5 seconds after closing and their PIDs disappear, excluding the 2-second fallback as the success path.
- Review fixes include flushing reopen messages before child termination, waiting for both process exit and pipe EOF before clearing the parent channel, keeping a read owner alive while reading available bytes, avoiding HUD movement when clearing closed-window screen context, and restoring login approval instructions from current SMAppService status.
- The user clicked the new settings preview on this Mac and explicitly confirmed the battery capsule appeared. CUA selected the resident process instead of the separate settings UI; that tool limitation was supplemented with the user check and real child-process regression.
- Two final demo PNG exports at 1.55 seconds and 3 seconds are byte-for-byte identical to exports from the pre-optimization universal app. Geometry, artwork, Wh formatting and animation remain unchanged. Native runtime placement was also inspected during the refactor at the existing 60% scale; the visible pill remained approximately 2 pt below the menu bar.
- Final universal build completed; lipo confirms arm64 and x86_64, strict codesign and Info.plist checks succeed, and ZIP integrity succeeds. Independent extraction verifies the executable, SVG, menu PNG and app icon are identical. Snapshot CLI succeeds. Final executable SHA-256: `9716755b789de1a26de142e758bb794233822af16fb33d1d67499d019da2103b`.
- Preferences exported before and after the final build/profile cycle compare identically as decoded JSON. Existing ⌘⇧E, language, display/scale, duration, menu and reminder values are preserved; tests did not toggle real launch-at-login registration.
- Three independent cold runs per scenario use whole-process-group physical footprint, including the settings child. Each run's final sample, three-run medians and sampled peaks are published in [memory-measurements.json](memory-measurements.json), with method, tradeoff and limitations in [memory-audit.md](memory-audit.md). Opening settings is temporarily heavier; the main improvement is releasing its process and caches afterward. No claim of a large cold-idle or animation-memory reduction is made.
- Packaged executable: 726,576 bytes, down from 1,359,024. App disk allocation measured by du: 888 KiB, down from 1,504 KiB; ZIP: 376,787 bytes, down from 460,499. Both architectures and original artwork/attribution remain present. Developer .build caches were kept separate from runtime and app-size measurements.
- A separate unchanged-settings process-exit measurement kept the same resident PID throughout: 42.52 MiB with settings open, 11.20 MiB after SIGTERM of the settings child, and 14.56 MiB after a live preview finished. This measures child-exit cache release, not a user-confirmed physical close-button action; normal window close and acknowledged natural exit are covered by the native process regression.

Physical event, real login, multiple-display, older macOS and Intel runtime limits from the earlier record still apply. Signing remains ad-hoc. The new source and packaged app were locally verified; the status of any subsequently triggered GitHub Actions run must be checked separately.

## Optimization publication

- Implementation commit `599642c69af01b537d0a1552151c429eb0f72366` was pushed to the existing public repository's main branch. A fresh remote reference matches the local commit; the GitHub API also reports the same source tree `3c3e534875fd3998422a5c3c730f1f9db6100ec4`.
- [GitHub Actions run 37199548497](https://github.com/MarkYang44/Endfield-Charge/actions/runs/37199548497) passed core tests, universal app compilation and artifact upload. The tag-only release job was skipped as expected. These CI checks do not include the local graphical runtime script.
- The optimized app was restored through LaunchServices and remains resident at the project dist path with settings closed. This publication follow-up updates verification/planning documentation only and skips a duplicate CI run; the tested source and packaged executable are unchanged.
