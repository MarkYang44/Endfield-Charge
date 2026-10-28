# Maintainability refactor

The user approved applying the four recommendations from the COMP2013 lecture review. This is a behavior-preserving refactor of the existing native macOS app, not a new telemetry feature or visual redesign.

## Boundaries

1. Share domain limits between strict sharing validation, forgiving saved-preference migration, and native editors. Keep these policies separate: imports reject malformed/overflowing input; legacy preferences normalize it.
2. Organize native checks by responsibility, with a small entry point and shared test fixtures. Preserve real child-process/IPC, timer, renderer, sampling, editor, sharing, and lifecycle coverage.
3. Extract a pure telemetry page projection with localized rows, status, captions, graph samples/range and accessibility text. The native view owns drawing, controls and its bounded on-demand history. Represent time and both graph values in one sample, avoiding parallel arrays.
4. Migrate old standalone HUD checks to the production playback coordinator, then remove the test-only compatibility queue/APIs from the renderer. Preserve renderer lifecycle/reentrancy coverage. Add tiered checks: fast core checks in cloud CI, native checks only on an explicitly selected graphical desktop runner, and full package validation for release builds.

## Contracts

- macOS 13+, Swift tools 5.9; no new dependencies or generic plugin framework.
- Maximum 12 capsule profiles, 16 rules, 4 color conditions per profile; playback references share the profile limit. Other unrelated limits remain independent.
- Configuration schema, defaults, persisted keys and all import/legacy policies remain compatible. File/IPC payload budget remains 131072 bytes excluding frame newline.
- Preserve English/Chinese copy, units, precision, disabled/missing-value behavior, accessibility, all original artwork, palette, geometry and animation timing.
- Keep one resident sampler and one HUD. Preserve power > alert > preview > ambient priority, finite rotation, optional persistence, reduced motion, sleep/wake and owner cleanup.
- Retain the 300-sample on-demand telemetry history cap. No new resident timer, cache, data collector or helper.
- Measure costs using the same host, compiler, scenario and physical-footprint metric. Report noise and limits; do not claim refactoring guarantees lower memory.

## Chosen approach

Use small value types and focused files within the existing ChargeCore/AppKit split. Closure injection and finite enums remain idiomatic Swift. This avoids a large inheritance/protocol rewrite and avoids merely splitting files without clarifying responsibilities.

## Validation

Run baseline core/native checks before edits. Preserve and add characterization tests at domain boundaries, localization/formatting and graph gaps; run focused checks while editing. Complete core/native suites, compare deterministic telemetry render output against the baseline, verify universal architecture/macOS floor/ad-hoc signature/resources and compare idle/settings/telemetry physical footprint. Desktop checks must be manually dispatched to a trusted graphical runner and must not execute untrusted pull-request code automatically.

## Task 4 verification steering (2026-10-28)

Daily verification selects affected checks: core filters, native groups (all/hud/telemetry/sharing/editors/ipc), or existing-package validation. Native groups build fresh ChargeCore objects without forcing all core tests. Bare `verify.sh desktop` fails with usage; full native verification requires `desktop all`. Manual workflow group choice defaults to hud and is passed through a quoted environment argument. Full desktop/release gates remain explicit; preserve useful legacy suites and ONLY flags. Reuse already-passed full-suite/package-negative evidence rather than repeating it after unrelated selector/documentation changes. Retain one meaningful repeated-lifecycle check, unique priority/owner/reentrancy coverage, and no automatic changed-path framework. This user steering supersedes any interpretation that every edit requires another full regression.
