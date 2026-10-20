# Capsule sharing and presentation implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Deliver the approved sharing, conditional colors/state alerts, carousel and persistent HUD in the native macOS app.

**Architecture:** Pure bounded models and deterministic evaluators in ChargeCore; one native presentation coordinator and existing HUD/sampler. The resident owns import/backup commits, UI helpers own native panels and editors.

**Tech Stack:** Swift 6 toolchain, SwiftPM, AppKit, Foundation, existing Mach/IOKit collectors, Swift Testing; no external dependencies.

## Global Constraints

- Binding spec: `docs/superpowers/specs/2026-10-20-capsule-sharing-presentation-design.md` (approved 2026-10-20).
- macOS 13+, universal arm64/x86_64, native-only, existing icon/artwork and unconfigured battery rendering preserved.
- All new user-facing text English/Simplified Chinese. Existing preferences and shortcut preserved.
- At most 12 profiles, 16 rules, 4 color conditions/profile; names 32 Characters/1024 UTF-8 bytes, IDs 64 Characters/256 bytes.
- Share file and IPC frame at most 131072 bytes; IPC excludes trailing newline. Strict share decode distinct from forgiving legacy decode.
- New features default off/empty. One HUD, shared 2s visible/30s background sampler, no static 60Hz timer, bounded pending events.
- Worktree: `/Users/markyang/.codex/worktrees/capsule-sharing/Endfield-Charge`, branch `codex/capsule-sharing`; no edits to main or installed app until delivery.
- Follow test-first for meaningful behavior; capture RED/GREEN in reports, focused tests while iterating and full suite before commit. No code or tests asserting implementation details alone.

## Task 1: Typed colors, state rules and presentation preferences

**Files:** create `Sources/ChargeCore/CapsuleAppearance.swift`, `Sources/ChargeCore/TelemetryState.swift`, `Sources/ChargeCore/CapsulePlayback.swift`; modify `CapsuleProfile.swift`, `TelemetryAlertRule.swift`, `Preferences.swift`; create `Tests/ChargeCoreTests/CapsulePresentationConfigurationTests.swift`.

**Interfaces:** `CapsuleAccent: String, Codable, CaseIterable` with theme/lime/amber/red; `CapsuleColorCondition` typed numeric metric/comparison/threshold/accent; `CapsuleProfile.colorConditions`; `resolvedAccent(in:)`. State rule condition with enum for threshold/stateChange, finite `TelemetryStateSource` (thermal/memoryPressure), optional target state; no numeric magic enums. `TelemetryRuleEvaluator.evaluate(rules:snapshot:at:)` handles both and retains existing values-only threshold evaluation. `CapsulePlayback` Codable preferences with persistent, rotationEnabled, profileIDs, intervalSeconds; normalize against profiles. Add Preferences.playback defaults.

- [ ] Write tests before implementation: legacy JSON retains CmdShiftE and new defaults off; first matching known color wins; missing metric skips; thresholds keep existing semantics; first state baseline quiet, hold cancels on transition, cooldown does not replay stale changes, unknown/time gap resets baseline without evading cooldown; invalid queue IDs removed, dedup, 10–600 interval, one/empty fallback.
- [ ] Run `bash scripts/test.sh` to observe RED for missing interfaces/behavior; implement focused pure models. Preserve original `isDefaultBattery` distinction without making palette-only customization lose battery layout.
- [ ] Run focused/full core tests, `swift build --disable-sandbox --build-system native`; report exact API and migration decisions to task 2–4; commit.

## Task 2: Strict share codec, preview/merge and atomic resident backup

**Files:** create `Sources/ChargeCore/ConfigurationShare.swift`, `Sources/EndfieldCharge/ConfigurationBackupStore.swift`; modify `SettingsMessage.swift`; tests `Tests/ChargeCoreTests/ConfigurationShareTests.swift`.

**Interfaces:** `ConfigurationShare` versioned export of profiles/rules/selected ID/playback (excluding global local preferences), `ConfigurationImportMode.merge/replace`, strict decode/encode bytes, deterministic preview/application result with summaries. Merge maps conflicts to fresh IDs/references; overflow rejects. Reuse identical values; modified builtin becomes custom. Import disables new rules; replace turns playback switches off; merge preserves local active switches and old rules. `ConfigurationBackupStore` saves exactly one validated previous Preferences atomically and restores via explicit request; injectable directory for tests. Add correlated import/restore request/result private IPC payloads, bounded and rejecting stale revision.

- [ ] Test actual JSON roundtrip, unknown version/enum, finite numbers, duplicate IDs, Unicode and file maximum size, count limits/invalid references, merge ID mapping, overflow, local preference preservation and imported rules off.
- [ ] Example acceptance: export local A, modify receiving shortcut to E, merge A with colliding differing ID; result keeps E, both profiles survive with correct queue references; malformed file leaves original value untouched.
- [ ] Observe RED, implement strict validators separately from legacy normalization, verify largest valid configuration still fits whole IPC message, run full core suite/build, commit.
- [ ] Backup file errors must propagate; test temp-directory save/read/replace/malformed/restore without touching real preferences in native checks (task 5).

## Task 3: Single-HUD presentation coordinator and live demand

**Files:** create `Sources/ChargeCore/CapsulePlaybackScheduler.swift`, `Sources/EndfieldCharge/CapsulePlaybackController.swift`; modify `HUDController.swift`, `HUDView.swift`, `CapsulePresentation.swift`, `AppDelegate.swift`, `StatusMenuController.swift`, `TelemetryMonitor.swift`; tests `Tests/ChargeCoreTests/CapsulePlaybackTests.swift`.

**Interfaces:** scheduler injects monotonic uptime and emits actions for show/hold/hide/next; renderer retains original transient behavior and exposes completion. Controller accepts settings, latest snapshots, power/alert/preview events, suspend/wake/hide/resume and owns one next-deadline timer. Preserve queue bound4/age30s, priority power > alerts > preview > ambient. Core decisions and native event plumbing are separately testable.

- [ ] Add failing deterministic tests: transient off default, finite one-cycle queue, persistent compact hold and wrap, interval at least whole transient cycle, one item no rotation timer, power interruption/resume full dwell, preview replacement/wait during power, expired events discarded, hidden demand released, sleep baseline reset, config deletion stops invalid selection.
- [ ] Implement scheduler and native integration; AppDelegate routes all presentations through coordinator, avoids direct calls bypassing power priority; differentiate forced dismiss and completion to avoid recursive restoration.
- [ ] Persisted battery compact hold updates from actual new BatterySnapshot; palette calculation adds dependencies and disabled modules remain unavailable. Status rule alert text/severity and thermal built-in dedup wired to same delivery queue.
- [ ] Static hold has no 60Hz timer. Reduce Motion immediately switches compact states but keeps dwell. Wake waits fresh snapshot before restoring. Run full core/build and focused native tests after adding compiled sources to check-runtime list; commit.

## Task 4: Native sharing, condition/state editors and playback controls

**Files:** create `SettingsSharing.swift`, `SettingsAppearance.swift`, `SettingsPlayback.swift` in Sources/EndfieldCharge; modify `SettingsCapsules.swift`, `SettingsRules.swift`, `SettingsPages.swift`, `SettingsControls.swift`, `SettingsWindowController.swift`, `SettingsApplicationDelegate.swift`, `SettingsProcessController.swift`, `AppSettings.swift`; modify runtime-check source list.

**Interfaces:** reuse task1/2 models; native NSOpenPanel/NSSavePanel, dedicated import preview with merge/replace and clear localized warning/confirmation. Helper sends validated correlated import/restore with current revision; resident revalidates, writes backup, persists once, acknowledges authoritative preferences/revision. Reject stale requests, disable controls while pending; newer edits cannot be overwritten by late result. Normal helper writes must respect resident revision transaction. Close/import/reopen cannot replay stale helper preferences.

- [ ] Runtime checks first for settings editor callbacks, status rule target/hold/cooldown, playback queue order/delete/interval normalization; use injected backup directory and private pipe requests for import/restore/cancel/failure/stale/close races.
- [ ] Add palette condition editor maximum4, numeric localized units, explicit add/remove/move and current match preview; invalid text kept as drafts as existing editors do, not silently clamped by UI.
- [ ] Add playback queue editor and off-by-default persistent toggle; ephemeral menu hide/resume independent from saved mode; keep seven tabs readable via scrolling/subwindows, no hidden retained view trees.
- [ ] Add native sharing UI with import summaries, failure messages and restore confirmation; file read prechecks128KiB and keeps all mutations in resident. All labels/errors in English/Chinese.
- [ ] Run core + runtime checks, export every affected settings page in en/zh and inspect screenshot for overflow, commit.

## Task 5: Full review, regression, measurements and delivery

**Files:** `Tests/RuntimeChecks/main.swift`, `scripts/check-runtime.sh`, `scripts/build-app.sh`, `README.md`, `README.zh-CN.md`, `docs/DEVELOPMENT*.md`, `docs/PERFORMANCE.md`, `THIRD_PARTY_NOTICES.md`, new versioned validation docs.

- [ ] Add native lifecycle/max UTF8 frame tests covering expanded config, fragmented/coalesced pipe, authoritative import revision, backup failure, hold exit, fresh wake, rule invalidation and collector demand. Run `bash scripts/test.sh`, `bash scripts/check-runtime.sh`, universal build.
- [ ] Run task-scoped reviews then final whole-branch review from merge-base to final head; fix important/critical findings and rerun covering tests, keep minor findings visible in ledger.
- [ ] Verify unchanged original artwork SHA and battery stage exports against v1.1.0. Render actual demo exports of new en/zh editors and playback/alert examples, visually inspect.
- [ ] Measure cold baseline and new idle/UI/transient-carousel/persistent-single/persistent-carousel resident+UI physical footprint/CPU using existing profiling tools, bounded runs; record environment and limitations. Validate no static animation timer and UI-helper close exit independently.
- [ ] Bump next appropriate release to1.2.0/build5 after passing checks; document defaults, scope, migration, limits and recovery in both READMEs. Package license notices and no new runtime deps.
- [ ] Merge verified branch to main without rewriting unrelated history, push/tag/publish via existing workflow, independently download and verify release archive, install tested app preserving preferences, confirm release/link/version and clean local/remote state, archive worktree after preserving artifacts.

## Progress

- Baseline/spec: approved. Worktree created at c35777f; baseline test in progress.
- Tasks 1–5: pending. Detailed per-task reports and reviews live in `/private/tmp/endfield-capsule-sharing/`.
