# Maintainability Implementation Plan

> **For agentic workers:** Use subagent-driven-development to implement this plan task by task with review gates. The user approved this refactor; continue without another design approval.

**Goal:** Apply the four approved lecture-based improvements without changing user-visible behavior or adding resident work.

**Architecture:** Keep ChargeCore pure and native AppKit owners focused. Consolidate domain knowledge, extract value projections, retain one production playback scheduler and split tests by domain.

**Tech Stack:** Swift 5.9 tools, SwiftPM, Foundation, AppKit, bash, GitHub Actions; macOS 13+.

## Global Constraints

- macOS 13+, Swift tools 5.9; no new dependencies or generic plugin framework.
- Maximum 12 capsule profiles, 16 rules, 4 color conditions per profile; playback references share the profile limit. Other unrelated limits remain independent.
- Configuration schema, defaults, persisted keys and all import/legacy policies remain compatible. File/IPC payload budget remains 131072 bytes excluding frame newline.
- Preserve English/Chinese copy, units, precision, disabled/missing-value behavior, accessibility, all original artwork, palette, geometry and animation timing.
- Keep one resident sampler and one HUD. Preserve power > alert > preview > ambient priority, finite rotation, optional persistence, reduced motion, sleep/wake and owner cleanup.
- Retain the 300-sample on-demand telemetry history cap. No new resident timer, cache, data collector or helper.

### Task 1: Domain constraint authority

Files: create Sources/ChargeCore/ConfigurationLimits.swift; modify ConfigurationShare.swift, Preferences.swift, CapsuleProfile.swift, CapsulePlayback.swift and native settings editors where the same domain limits are duplicated. Extend Tests/ChargeCoreTests/ConfigurationShareTests.swift and PreferencesTests.swift or a focused ConfigurationLimitsTests.swift.

Produces: public ConfigurationLimits.maximumProfiles = 12, maximumRules = 16, maximumColorConditions = 4. Playback ID capacity uses maximumProfiles. Import remains strict; legacy saved settings remain forgiving.

- [ ] Add behavior characterization for exact and over-limit profile/rule/condition/playback counts; strict import rejection versus legacy normalization, including required battery insertion and reference pruning. Use literal boundary expectations in tests so incorrect constants cannot make both sides pass.
- [ ] Run focused tests before the refactor; existing valid behavior must pass. If adding new API assertions, verify their expected compile failure before implementing.
- [ ] Replace matching domain literals with the constants in validation, normalization, bounded decoders and editor capacity checks. Keep localized error text accurate. Do not merge strict and forgiving policy or unrelated numeric limits.
- [ ] Run bash scripts/test.sh, inspect diff and commit refactor. Report boundary results and unchanged semantics.

### Task 2: Native test responsibilities

Files: Tests/RuntimeChecks/main.swift, existing EditorChecks.swift/SharingChecks.swift/PlaybackChecks.swift, new focused fixtures, child-role, IPC/lifecycle, telemetry and HUD scenario files under Tests/RuntimeChecks; scripts/check-runtime.sh.

Consumes: existing global check/spin/awaitCondition helpers and private UserDefaults suites; may replace globals with explicit fixture arguments where that improves clarity. Produces named run functions and a short main that dispatches child roles first, then named check groups.

- [ ] Inspect existing check groups/child-role branch and record baseline PASS groups. Preserve ENDFIELD_EDITORS_ONLY and ENDFIELD_SHARING_ONLY fast paths.
- [ ] Extract reusable fixtures and child-role handling, then separate settings/IPC, telemetry sampler/view, and HUD scenarios. Move existing assertions without inventing a testing framework; functions may throw where existing checks throw.
- [ ] Ensure settings are isolated, child processes naturally close/ACK, native windows/timers are released, environment/defaults cleanup runs, all existing assertions still execute in full mode and failure exits nonzero.
- [ ] Update compile inputs in scripts/check-runtime.sh to include all check files deterministically. Keep source inputs explicit or well-scoped globs, avoid silently including the app main.swift.
- [ ] Run bash scripts/check-runtime.sh, compare group coverage with baseline, inspect diff and commit.

### Task 3: Pure telemetry page presentation

Files: create Sources/ChargeCore/TelemetryPagePresentation.swift and Tests/ChargeCoreTests/TelemetryPagePresentationTests.swift; modify Sources/EndfieldCharge/TelemetryView.swift. Keep domain data independent of AppKit, AppSettings, native windows, clocks and system readers.

Produces: a pure value projection selected by page index (0 power, 1 compute, 2 thermal, 3 network, 4 storage; invalid => power), consuming Preferences, optional TelemetrySnapshot, language boolean, history samples and demo flag. Use a typed sample containing timestamp/primary/secondary optional values. Rows carry localized label and formatted value together, with status/caption/footer/range/alert/accessibility text as needed. History stores only existing plotted fields; do not store full snapshots just for convenience.

- [ ] Add deterministic tests first for all five pages in English/Chinese, empty/missing/disabled metrics, NaN handling, bytes/rate/percent/Wh formatting, network observation baseline gating, thermal/pressure states, auto/fixed ranges and alert color, demo suffix and graph timestamp/value association. Run focused tests to see expected missing-API failure.
- [ ] Move the existing formatting/projection logic verbatim where possible; preserve exact rendered copy and precision. Keep graph drawing, layout and control actions in AppKit. Use one graph sample array instead of zip of separate time/value arrays; preserve gap breaks at nonincreasing time or >60s and nil/nonfinite readings.
- [ ] Make rebuilding rows and refreshing values consume the same projection. Preserve history reset on clock regression, duplicate timestamps filtering and 300-item cap; maintain on-demand ownership and no new timers.
- [ ] Run focused tests and bash scripts/test.sh; run native view checks and deterministic render comparison through existing CLI. Commit once behavior is characterized and verified.

### Task 4: Single HUD scheduling path and verification tiers

Files: Sources/EndfieldCharge/HUDController.swift, CapsulePlaybackController.swift only if required by legitimate migration; focused native HUD/playback check files created in Task 2; scripts/check-runtime.sh; new scripts/check-package.sh and scripts/verify.sh; .github/workflows/build.yml and a manually dispatched desktop-checks workflow; bilingual developer verification docs.

Consumes: production CapsulePlaybackController and pure CapsulePlaybackScheduler; renderer render/dismiss/completion API. Produces one scheduler, no standalone compatibility queue or show/showProfile/showRule entry points.

- [ ] Migrate old standalone HUD tests to production playback paths. Preserve meaningful assertions for static hold/queue ordering, power interruption, profile demand and live updates, disabled metrics, deleted rule release, repeated lifecycle, owner deallocation and synchronous demand-release reentrancy. Renderer-specific tests may call render() directly with completion. Do not change production priority to satisfy old tests.
- [ ] Run migrated tests while compatibility code remains, then remove unused compatibility queue, freshness checks used only by it and entry points. Simplify present/finished to renderer ownership/completion only. Preserve reentrancy by completing teardown before callbacks.
- [ ] Add scripts/verify.sh with core (core tests), desktop (core+native) and release (desktop+universal build+package verification) tiers; unknown/missing modes fail with usage before executing work. Add check-package.sh that checks both architectures, macOS 13 floor, strict signature, expected resources and ZIP integrity. Test negative/missing-asset cases with temporary copies, never by corrupting the real dist output.
- [ ] Cloud build workflow runs core tests and universal package verification. Desktop workflow is workflow_dispatch only on [self-hosted, macOS, endfield-desktop]; no pull-request/push trigger. Document graphical session setup and that no runner is assumed provisioned. Do not dispatch this workflow during implementation.
- [ ] Document commands, scope/limitations, stage selection and measurement method in English/Chinese; no unsupported memory-saving promises.
- [ ] Run core, native and universal package checks, preserve artwork hashes, inspect diff and commit. Controller performs final performance/render comparison and independent whole-branch review before integration.
