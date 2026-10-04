# Endfield Charge Implementation Plan

> Execute inline with executing-plans. Use requesting-code-review for an independent final review.

**Goal:** A working native battery HUD on this Mac and a public MarkYang44/Endfield-Charge repository.

**Architecture:** A Swift package separates deterministic battery/event/animation logic from AppKit system integration. AppKit draws the reference-faithful HUD; SwiftUI presents settings. IOKit supplies snapshots and notifications.

**Tech Stack:** Swift 5.9 language mode, macOS 13+, AppKit, SwiftUI, IOKit, Carbon, ServiceManagement, XCTest.

## Constraints

- Source lives in /Users/markyang/Projects/Endfield-Charge.
- Match upstream charcoal capsule, lime progress ring, laptop badge, double-parallelogram bolt and three-stage sequence.
- Actual external-power state and charging state remain separate; unknown readings stay unknown.
- No runtime dependencies, accessibility permission, or automatic network requests. Launch-at-login is opt-in.

## Task 1 — Battery and event semantics

- [ ] Create Package.swift, Tests/ChargeCoreTests/ChargeCoreTests.swift. Verify expected missing-type failures with `swift test --disable-sandbox`.
- [ ] Implement Sources/ChargeCore/BatterySnapshot.swift and PowerEventReducer.swift: normalize percentage, preserve nils, derive optional approximate Wh from physical registry capacities, charger connect/disconnect and threshold-crossing alerts. Interfaces: `BatterySnapshot.from(description:registry:lowPower:)`, `PowerEventReducer.consume(_:lowThreshold:) -> [PowerEvent]`.
- [ ] Run the same tests; require zero failures. Include AC-connected-but-not-charging and initial/no-battery cases.

## Task 2 — Reference HUD

- [ ] Add assertions for `HUDFrame.at(seconds:duration:reduceMotion:)` to verify invisible beginning/end, expanded title stage, contracted numeric stage and constant intro timing across durations.
- [ ] Implement Sources/ChargeCore/HUDFrame.swift and Sources/EndfieldCharge/HUDView.swift. Use upstream geometry and documented six-second normalized cues; interpolate with cubic curves and clip ripples inside rounded capsule.
- [ ] Implement HUDController.swift: one nonactivating mouse-transparent panel, visible-only timer, screen selection/position, screen changes, reduce motion, and queued power transitions. Add static render CLI for reproducible PNG QA.

## Task 3 — macOS integration

- [ ] Implement BatteryReader.swift and PowerMonitor.swift: IOPS callback source, 400ms cancellable debounce, 30s fallback, workspace wake refresh. Only filter internal batteries.
- [ ] Implement AppSettings.swift, SettingsView.swift, HotKey.swift and AppDelegate.swift: persist settings, menu percentage, native shortcut, launch login status/errors and CN/EN labels. Add `--snapshot`, `--demo`, `--preview-unplug`, `--preview`, `--render` modes.
- [ ] `swift test --disable-sandbox` and `swift build --disable-sandbox -c release`; compare `--snapshot` with `pmset -g batt`.

## Task 4 — Packaging and release

- [ ] Add scripts/build-app.sh, scripts/make-icon.swift, README.md, LICENSE, THIRD_PARTY_NOTICES.md, .gitignore and .github/workflows/build.yml. Package a signed local .app and zip, plus GitHub Actions artifact/release workflow.
- [ ] Render animation-stage PNGs, visually inspect them; launch app and verify settings, menu, and preview. Record unobserved physical charger transitions accurately.
- [ ] Request independent code review, resolve material findings, re-run affected checks, update docs/verification.md with evidence.
- [ ] Create public GitHub repository using the existing signed-in session, upload reviewed source via GitHub connector or authenticated Git, then verify remote tree/content and local origin link. No further approval gate: user explicitly authorized creation and upload.
