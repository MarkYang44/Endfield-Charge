English | [简体中文](DEVELOPMENT.zh-CN.md)

# Developer guide

## Build and verify

Use a Swift 6 toolchain with Xcode or Apple Command Line Tools. Deployment targets macOS 13; Swift Testing checks are best run on macOS 14+. No third-party packages are required.

```bash
bash scripts/test.sh
bash scripts/check-runtime.sh # graphical macOS session required
bash scripts/build-app.sh --universal
open "dist/Endfield Charge.app"
```

Omit `--universal` to build only the host architecture. Outputs are `dist/Endfield Charge.app` and `dist/Endfield-Charge-macOS.zip`. The test script handles Swift Testing framework paths in Command Line Tools environments. Native runtime checks use isolated preference domains; CI runs the desktop-independent core suite.

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

See [performance records](PERFORMANCE.md) for profiling commands, metrics and historical results. Python 3 and Command Line Tools are needed only for those developer measurements, not the installed app.

Pushing `main` runs core tests and creates a universal archive. Pushing a `v*` tag publishes the archive using `docs/releases/<tag>.md` when present. Builds currently use ad-hoc signing, without Developer ID notarization. Preserve bundled licenses, third-party notices and privacy metadata when distributing.


## v1.2.0 configuration verification / 配置验证

The [configuration guide](configuration-sharing.md) ([中文](configuration-sharing.zh-CN.md)) defines sharing scope, safety defaults and playback behavior. Share validation is strict and versioned; legacy Preferences migration stays tolerant. Resident-side ConfigurationTransactionService owns validation, atomic backup and one commit; helpers only request and receive authoritative revisions. Undo restores one full snapshot without changing SMAppService registration. CapsulePlaybackScheduler is deterministic; one native coordinator owns the HUD/deadline, while static compact holds stop the animation timer.

`bash scripts/test.sh` builds ChargeCore first; `bash scripts/check-runtime.sh` then exercises actual controls, pipes and child processes, including expanded UTF-8 configurations. For isolated synthetic exports:

```bash
ENDFIELD_EDITORS_ONLY=1 ENDFIELD_EDITOR_SCREENSHOTS=/tmp/endfield-demo bash scripts/check-runtime.sh
```

This exports actual English/Chinese settings content and production palette/thermal/memory HUDs from temporary preferences, not user readings. `ENDFIELD_SHARING_ONLY=1` isolates sharing checks; see Tests/RuntimeChecks/SharingChecks.swift for its screenshot fixture. `--render-settings --scroll-bottom` exports the bottom of a scrollable page. The original battery regression uses `--render /tmp/battery.png --demo --stage 1.55`, stage 3, and stage 0.15 with `--reduce-motion`; do not change artwork to update these expectations.

[Versioned validation](capsule-sharing-validation.md) records commands, physical-footprint aggregates, package hashes and limitations. Raw live preference backups and telemetry samples belong outside the repository. The profiling tools are development-only; no Python, .NET, font or other runtime is bundled.
