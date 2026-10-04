# Endfield Charge Icon Implementation Plan

> For agentic workers: use subagent-driven-development for vector artwork and independent review, then complete packaging and publication in the parent task. The user has approved the design and execution.

**Goal:** deliver the approved simplified Endfield/lightning identity in the app, menu bar, local installation and v1.0.1 Release.

**Architecture:** a developer-only AppKit renderer owns vector geometry and exports SVG/PNG assets; the existing runtime continues loading static PNGs and native template images.

**Tech stack:** Swift/AppKit, SVG, existing Swift package and GitHub Actions.

## Global constraints

- Follow docs/superpowers/specs/2026-10-04-charge-icon-design.md; no changes to HUD geometry, animation, telemetry, preferences, app identifier or shortcut behavior.
- No third-party library/runtime; supplied logo unchanged; no new tests that merely duplicate low-impact artwork geometry.
- Parent owns commits, installation, process restarts, tags and publication. Implementer edits only assigned artwork/renderer/preview files.

### Task 1: Vector artwork and deterministic exports

**Files:** create scripts/render-icons.swift, Resources/ChargeIcon.svg, Resources/ChargeMenuIcon.svg and docs/images/charge-icon-preview.png; update Resources/AppIcon.png and Resources/MenuBarIcon.png.

- [ ] Create native drawing/export code with one geometry definition per artwork; derive both SVG and PNG output from those definitions. Run `swift scripts/render-icons.swift` in the project root.
- [ ] Export the two PNG sizes and transparent SVGs. Create a preview sheet containing the icon at large/small sizes and the monochrome mark on light/dark menu backgrounds.
- [ ] Inspect the preview; adjust spacing and stroke weights where needed while keeping the approved silhouette and HUD bolt. Check PNG dimensions/transparency and original supplied SVG hash `3e2af120ec6c86d2132448e7fbd4264b50e7258276c1beabb2bf3fa666200025`.
- [ ] Independently review design fidelity, small-size readability, generator correctness and dependency/runtime footprint; resolve concrete findings.

### Task 2: Package and document v1.0.1

**Files:** update scripts/build-app.sh, Sources/EndfieldCharge/SettingsPages.swift, THIRD_PARTY_NOTICES.md, README.md and .github/workflows/build.yml; create docs/releases/v1.0.1.md.

- [ ] Set CFBundleShortVersionString/About to 1.0.1 and CFBundleVersion to 2. Keep the existing package icon conversion and PNG resource loading.
- [ ] Correct attribution for the new derived vector artwork; add a preview and direct latest-release download in README.
- [ ] Add concise release notes. In the release job, check out the tagged source and prefer `--notes-file docs/releases/$GITHUB_REF_NAME.md` when present, otherwise keep `--generate-notes`.
- [ ] Run `bash scripts/test.sh`, `bash scripts/check-runtime.sh`, `bash scripts/build-app.sh --universal`, `git diff --check`, signature/lipo/ZIP checks and visual preview review.

### Task 3: Install and publish

- [ ] Preserve a preference fingerprint and the prior installed bundle. Replace the installed app only after verification; register only this application with Launch Services/Spotlight, restart only its owned resident and confirm the installed path and unchanged preferences.
- [ ] Complete independent whole-change review, commit source and push main. Create v1.0.1 only after source checks pass; wait for the tag build and Release publication.
- [ ] Download the public asset; check digest, ZIP integrity, version, architecture, signature, icon/resource bytes and release-note content. Record validation and mark the plan complete.
