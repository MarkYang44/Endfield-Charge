# Lightweight runtime implementation plan

**Goal:** reduce measured memory and installed size without dropping existing behavior.

**Architecture:** retain framework-independent ChargeCore, AppKit vector HUD and native system services. Replace SwiftUI settings with lazy AppKit pages in an on-demand role of the same executable, connected to the resident through private pipes. Drain final writes, require close acknowledgment and wait for pipe EOF plus process exit. Separate status-menu presentation from AppDelegate and release closed HUD surfaces. No additional dependencies or package targets.

**Constraints:** macOS 13+, universal arm64/x86_64; unchanged artwork, 60 Hz moving animation, all four settings pages, languages, persisted preference schema, exclusive global shortcuts, launch-at-login, bounded alert queue, battery safety and 2 pt menu-bar gap. Preserve this machine's saved preferences and in-session settings tab/window position.

## 1. Comparable baseline

- [x] Back up the running universal app and archive outside the repository.
- [x] Record physical footprint with settings open/closed; inspect vmmap and linkage.
- [x] Repeat cold idle, settings and animation scenarios three times with identical arguments, preferences and sampling windows. Keep physical footprint separate from RSS, virtual mappings and developer build cache. Count the entire parent/child group.

## 2. Settings and menu lifecycle

Files: AppSettings.swift, SettingsWindowController.swift, SettingsControls.swift, StatusMenuController.swift, AppDelegate.swift; remove SettingsView.swift.

- [x] Remove ObservableObject/@Published and SwiftUI imports. Keep separate application and UI callbacks, guard unchanged preferences, query SMAppService status only when settings are needed.
- [x] Implement native controls for every existing option. Keep modifier accessibility names, feedback, disabled controls, numeric display IDs, stepped sliders, previews, links and exact persisted key/domain. Restore approval instructions from current system status on reopen.
- [x] Store only tab index/window frame on close, release controller/content. Rebuild only the selected page; update controls in place for slider changes. Exit the settings role to release system caches too.
- [x] Create the menu once; update existing titles/state/time items after refresh, including while tracked.
- [x] Exercise all pages and persistence through native UI; reopen and check saved geometry/tab and preferences. Real child regression excludes the timeout fallback and checks both child PIDs have disappeared.

## 3. HUD wakeups and surfaces

Files: ChargeCore/HUDFrame.swift, HUDController.swift, Tests/ChargeCoreTests/HUDSchedulingTests.swift.

- [x] Write a failing static-hold scheduling test before implementing the scheduler. Check unchanged frame during holds, close/expiry boundaries, duration limits and Reduce Motion.
- [x] Continue 60 Hz through motion, replace the static hold with one close-deadline timer. Keep presentation state independent of timer type so queued alerts remain queued.
- [x] Allocate panel/view only when showing; release surfaces after the last queued animation. Preserve all geometry and focus behavior.
- [x] Compare baseline/optimized PNG pixels at identical demo stages and native placement. Verify repeated previews and static-hold queued alerts.

## 4. Packaging and delivery

Files: scripts/build-app.sh, docs/verification.md, README.md, docs/design.md, docs/memory-audit.md.

- [x] Strip nonessential symbols from the copied universal executable before signing. Keep both architectures and all original assets/notices.
- [x] Run `bash scripts/test.sh`, build universal, verify architecture/signature, snapshot CLI, PNG renders, launch and extracted ZIP binary equality.
- [x] Run the same baseline benchmark against the final app; record medians and sampled peaks with limitations. Verify settings teardown, idle CPU and repeated animation lifecycle. Explicitly report higher settings-open total footprint.
- [x] Request independent code review and resolve material findings; prepare verified source and app for publication to the existing authorized public repository.
- [x] Publish the implementation, confirm remote commit/tree and successful GitHub universal build/artifact upload, and restore the optimized app through LaunchServices with settings closed.

## Audit decisions

Full AppleSmartBattery property reads remain intact: narrowing to separate IOKit reads could lose capacity-pair coherence. Assets and persisted JSON are already small. Removing artwork, reducing animation quality, disabling reminders, reducing architecture support or adding a generalized event bus would violate the request or add needless complexity.
