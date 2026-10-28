English | [简体中文](DEVELOPMENT.zh-CN.md)

# Developer guide

## Build and verify

Use a Swift 6 toolchain with Xcode or Apple Command Line Tools. Deployment targets macOS 13; Swift Testing checks are best run on macOS 14+. No third-party packages are required.

```bash
bash scripts/verify.sh core --filter CapsulePlayback # affected core suite
bash scripts/verify.sh desktop hud                  # affected native group, fresh core build
bash scripts/verify.sh package                      # existing dist only; no rebuild
# Explicit broad verification when needed:
bash scripts/verify.sh core
bash scripts/verify.sh desktop all
bash scripts/verify.sh release # full desktop + universal build + package
```

For daily changes, select the affected checks; do not rerun unrelated suites. `scripts/test.sh` forwards quoted arguments to `swift test` (for example `--filter 'CapsulePlayback|ConfigurationLimits'`). `scripts/check-runtime.sh --group all|hud|telemetry|sharing|editors|ipc` builds fresh ChargeCore objects without running all core tests, then compiles and runs the selected native checks. `verify.sh desktop <group>` does the same; `desktop all` explicitly runs all core and native checks; bare `desktop` fails with usage. The `ENDFIELD_EDITORS_ONLY` and `ENDFIELD_SHARING_ONLY` legacy flags remain available. Invalid/missing group values and unknown verification modes fail with usage before compiling.

Use `core --filter` for relevant pure models, limits, sharing or scheduler suites; `desktop hud` for playback/render ownership, `telemetry` for native telemetry, `editors` for controls, `sharing` for native transactions, and `ipc` for pipes/windows/child lifecycle. Native checks use isolated preference domains and real windows, pipes, child processes and timers. They do not establish hardware sensor accuracy on every Mac. Full `release` verification is an explicit distribution gate, not a daily default.

`bash scripts/build-app.sh --universal` produces `dist/Endfield Charge.app` and `dist/Endfield-Charge-macOS.zip`; omit `--universal` for a host-only build. `bash scripts/verify.sh package` checks the existing app/archive without rebuilding: arm64/x86_64 slices, the macOS 13.0 floor in both slices and Info.plist, expected resources, strict ad-hoc signing, ZIP integrity and extracted-app equality. `check-package.sh` also accepts explicit app/archive paths together for temporary-copy negative checks. A valid unrelated ZIP cannot pass. This does not establish notarization or execution on Intel hardware.

Cloud CI runs `verify.sh core`, builds the universal app and verifies its package. Native checks run only through manually dispatched `desktop-checks.yml` on `[self-hosted, macOS, endfield-desktop]`. The manual choice defaults to `hud`; `all` explicitly adds the full core suite. No runner is assumed provisioned. An administrator must provide a trusted Mac with the toolchain above, register those labels and run the runner in a logged-in graphical user session with WindowServer access. Dispatch only trusted revisions; there is no PR/push trigger. A headless service is insufficient. Running the workflow is a separate operator action.

## CLI and exports

Call the executable directly when forwarding an action to an already-running app. `open --args` does not reliably deliver new arguments to an existing instance.

```bash
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --settings
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --telemetry
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --preview
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --capsule-preview
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --demo
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --preview-unplug
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --snapshot
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --telemetry-snapshot
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --render /tmp/hud.png --demo --stage 1.55
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --render /tmp/network-hud.png --capsule network --demo
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --render-telemetry /tmp/network.png --tab network --demo
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --render-settings /tmp/rules.png --tab rules --demo --zh
```

- `--snapshot` outputs actual battery JSON; `--telemetry-snapshot` takes two actual samples one second apart and outputs all five modules.
- `--render-telemetry --tab power|compute|thermal|network|storage` supports `--stage seconds`, `--reduce-motion`, and explicitly marked `--demo` data.
- `--render --capsule` resolves an existing profile ID or a builtin name: `battery|cpu|memory|network|storage`. Default rendering retains the original battery path.
- `--render-settings --tab general|display|alerts|telemetry|capsules|rules|about` exports actual AppKit content without the system title bar or toolbar. `--zh` selects Chinese; the default export language is English.
- Export and snapshot modes do not enter the resident event loop. Normal relaunch previews the actual battery; the selected-capsule action is distinct.

## Module boundaries

| Location | Responsibility |
| --- | --- |
| `Sources/ChargeCore/` | Pure battery/telemetry models, counter differences, rule state, profiles, preferences, IPC and animation timeline |
| `Sources/EndfieldCharge/` | Native collectors, shared monitor, HUD presentation, AppKit editors/telemetry, menu and shortcut |
| `Tests/ChargeCoreTests/` | Desktop-independent behavior and migration checks |
| `Tests/RuntimeChecks/` | Native window/editor ownership, IPC, async demand and alert checks |
| `Resources/` | Original and derived vector/raster artwork, privacy manifest |
| `scripts/` | Test, build, icon export and development-only profiling tools |
| `.github/workflows/` | Universal CI builds and tagged releases |

Profiles and rules store thresholds/reference maxima in base units. Editors convert to Wh, percent, GiB and MiB/s. Titles/rule names allow up to 32 characters and 1,024 UTF-8 bytes; IDs allow 64 characters and 256 bytes, retaining whole graphemes. The private IPC payload budget is 128 KiB per newline-delimited frame, enforced at both send and receive boundaries. Oversized frames are drained before the next valid frame is read. New collectors share one bounded serial worker and the resident demand scheduler. UI helpers receive snapshots through a private pipe; they do not create collectors.

Re-export the repository's vector icon source with `swift scripts/render-icons.swift`. Keep the menu icon contract separate from the app icon.

## Performance and release

See [performance records](PERFORMANCE.md) for profiling commands, metrics and historical results. Compare idle, settings and telemetry scenarios on the same host/compiler with the same physical-footprint metric, warm-up and sample windows; repeat runs and report noise. Refactoring alone does not guarantee lower memory. Deterministic render comparisons use the same demo payload, language, stage and Reduce Motion setting; retain original artwork hashes. Python 3 and Command Line Tools are needed only for those developer measurements, not the installed app.

Pushing `main` runs core tests and creates and verifies a universal archive. Pushing a `v*` tag publishes the archive using `docs/releases/<tag>.md` when present. Builds currently use ad-hoc signing, without Developer ID notarization. Preserve bundled licenses, third-party notices and privacy metadata when distributing.


## v1.2.0 configuration verification / 配置验证

The [configuration guide](configuration-sharing.md) ([中文](configuration-sharing.zh-CN.md)) defines sharing scope, safety defaults and playback behavior. Share validation is strict and versioned; legacy Preferences migration stays tolerant. Resident-side ConfigurationTransactionService owns validation, atomic backup and one commit; helpers only request and receive authoritative revisions. Undo restores one full snapshot without changing SMAppService registration. CapsulePlaybackScheduler is deterministic; one native coordinator owns the HUD/deadline, while static compact holds stop the animation timer.

Select the affected group: `bash scripts/verify.sh desktop sharing` for configuration transactions, `desktop editors` for controls, or `desktop ipc` for pipes and child processes, including expanded UTF-8 configurations. The native entry point automatically builds fresh ChargeCore objects; no separate core-test run is required. Use `desktop all` only when explicitly selecting the full suite. For isolated synthetic exports:

```bash
ENDFIELD_EDITORS_ONLY=1 ENDFIELD_EDITOR_SCREENSHOTS=/tmp/endfield-demo bash scripts/check-runtime.sh
```

This exports actual English/Chinese settings content and production palette/thermal/memory HUDs from temporary preferences, not user readings. `ENDFIELD_SHARING_ONLY=1` isolates sharing checks; see Tests/RuntimeChecks/SharingChecks.swift for its screenshot fixture. `--render-settings --scroll-bottom` exports the bottom of a scrollable page. The original battery regression uses `--render /tmp/battery.png --demo --stage 1.55`, stage 3, and stage 0.15 with `--reduce-motion`; do not change artwork to update these expectations.

[Versioned validation](capsule-sharing-validation.md) records commands, physical-footprint aggregates, package hashes and limitations. Raw live preference backups and telemetry samples belong outside the repository. The profiling tools are development-only; no Python, .NET, font or other runtime is bundled.
