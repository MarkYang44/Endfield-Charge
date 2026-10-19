# Telemetry Plus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Add low-overhead network/storage telemetry, configurable capsule profiles and generic threshold alerts to the native macOS HUD.

**Architecture:** Extend ChargeCore with optional snapshots, pure counter differencing and rule state machines. Keep native collectors separate; share resident demand scheduling, bounded child UI history and existing HUD animation.

**Tech Stack:** Swift, AppKit, Darwin sysctl/statfs, existing Swift Testing. No new external dependencies.

## Global Constraints
- macOS 13+, arm64/x86_64; native Swift/AppKit, no third-party runtime or shell polling.
- Preserve menu/app image bytes, HUD geometry/three-stage timing, power semantics and old preferences/hotkeys.
- Network/storage are demand-driven within shared 2 s visible/30 s background scheduling, no active probes/uploads.
- Physical-interface traffic is distinct from internet reachability; APFS shared-container capacity is distinct from SSD hardware capacity.
- Unknown/reset/wake/disabled data stays unknown; histories and rule/profile counts remain bounded.
- Generic rules default disabled, baseline without replay, hold/cooldown/rearm, power-event priority.
- Preserve upstream MIT attribution; new release 1.1.0/build 4.

### Task 1: Data models, pure state machines and native collectors
**Files:** Sources/ChargeCore/{Telemetry.swift,NetworkTelemetry.swift,StorageTelemetry.swift,CapsuleProfile.swift,TelemetryAlertRule.swift,Preferences.swift}; Sources/EndfieldCharge/{NetworkReader.swift,StorageReader.swift,TelemetryReader.swift}; Tests/ChargeCoreTests/{NetworkTelemetryTests.swift,TelemetryPlusPreferenceTests.swift,TelemetryAlertTests.swift}; scripts/check-runtime.sh only for added collector source inclusion.
**Interfaces:** Optional network/storage fields on TelemetrySnapshot with nil defaults; existing reader call sites stay source compatible. Typed finite metric/profile/rule models with stable default IDs. Report exact APIs for Task 2/3.
- [x] Add meaningful failing tests for first/rate/reset/long-gap/interface-change network samples, storage bounds, old preference migration, profile/rule roundtrip/sanitization, startup/hold/cooldown/rearm/missing-data alerts.
- [x] Implement pure types and logic, for example two samples en0:(1000,500) then (2000,600) one second apart yield 1000/100 bytes/s; a new en1 counter must not add old traffic.
- [x] Implement Swift Darwin 64-bit counters and APFS statfs collection with proper buffer lifetime, finite/overflow guards and reset. Extend read(...networkEnabled:Bool=false,storageEnabled:Bool=false) without changing old API consumers.
- [x] Run bash scripts/test.sh and actual --telemetry-snapshot/native collector smoke (temporary validation harness if CLI not yet wired); inspect diff and commit owned files. Report command outputs and API contract.
- [x] Independent task review, resolve findings and record ledger.

### Task 2: Demand scheduling, profiles and rule/HUD integration
**Files:** Sources/EndfieldCharge/{TelemetryMonitor.swift,AppDelegate.swift,HUDController.swift,HUDView.swift,StatusMenuController.swift}; optional focused CapsulePresentation.swift helper; Tests/RuntimeChecks/main.swift, scripts/check-runtime.sh for new sources.
**Interfaces:** Consume Task 1 snapshot/profile/rule types; add explicit profile preview and HUD-demand lifecycle. Deliver native settings-facing actions used by Task 3.
- [x] Add native regression checks for collector demands, rule reset/disabled state, profile presentation without affecting battery animation and release after dismissal; confirm failures before implementation.
- [x] Extend one shared scheduler: active terminal/HUD demand -> 2 s; hidden only rule-required network/storage -> 30 s; no rules/new HUD -> no new hidden collection. Existing power/compute/thermal behavior retained.
- [x] Render configurable primary/secondary/ring data with original geometry and static-hold scheduling; keep explicit battery preview; selected profile hotkey preview, power events interrupt queued telemetry; bounded alert queue with stale snapshot avoidance.
- [x] Run core/native checks, inspect lifecycle and commit owned files; report API additions for Task 3.
- [x] Independent task review, resolve findings and record ledger.

### Task 3: Native settings, telemetry pages and render coverage
**Files:** Sources/EndfieldCharge/{SettingsWindowController.swift,SettingsPages.swift,SettingsControls.swift,TelemetryView.swift,TelemetryWindowController.swift,TelemetryApplicationDelegate.swift,main.swift}; new focused SettingsCapsules.swift/SettingsRules.swift/TelemetryPages.swift as needed; Tests/RuntimeChecks/main.swift and scripts/check-runtime.sh.
**Interfaces:** Consume Task 1 model IDs/metrics and Task 2 preview/snapshot delivery; preserve existing private pipe behavior and actual preference direction.
- [x] Add regression checks for five telemetry tabs, additional lazy settings pages, complete profile/rule editing roundtrips and reopen/close behavior.
- [x] Provide add/edit/duplicate/delete/select/preview profile controls and add/edit/delete/enable rule controls, finite numeric validation, clear disabled/unavailable labels and scrollable layouts without clipping. All labels Chinese/English.
- [x] Extend NETWORK/STORAGE cards and bounded time graphs; update CLI snapshot/render tabs and capsule demo renders. Mark demonstration data in exported telemetry scenes.
- [x] Run core/native checks and render all new pages plus original three stages at normal/reduced motion. Parent visually inspects screenshots before release. Commit and independent review.

### Task 4: Integration, measurements and release
**Files:** README.md, THIRD_PARTY_NOTICES.md, LICENSES/zmd-charge-plus-MIT.txt, scripts/build-app.sh, docs/releases/v1.1.0.md, docs/telemetry-plus-validation.{md,json}, documentation/progress ledger.
- [x] Record source provenance and full MIT text; package attribution file; About/bundle 1.1.0/build 4.
- [x] Run complete core/native checks and universal build; compare immutable image hashes, sample real collector outputs without publishing personal addresses, verify signatures and ZIP files.
- [ ] Measure comparable baseline/new physical footprint and process CPU/wakeup proxies, including idle, terminal and after UI exit. Inspect screenshots and independent final review; fix findings and rerun affected checks.
- [ ] Fast-forward main, preserve artifacts, install/restart only the owned app, verify old preferences, push source/tag, inspect successful CI/public Release and actual downloaded ZIP. Save verified evidence, clean/archive worktree.
