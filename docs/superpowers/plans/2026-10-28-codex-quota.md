# Codex quota capsule implementation plan

> Execute one cohesive feature task with subagent-driven-development and one final read-only review. User has specified both functionality and layout; no further design gate or repeated broad test loop.

**Goal:** Select 5-hour or weekly remaining Codex quota, OpenAI ring logo and reset countdown in the existing HUD.
**Architecture:** Pure quota snapshot/parser + finite metric extensions, one asynchronous cached native CLI reader wired to current demand, opt-in preset menu entries, small Codex-only renderer branch.
**Stack:** existing Swift/Foundation/AppKit/IOKit/macOS13; no new dependencies.

## Global constraints

- Preserve five existing defaults, saved preferences,12-profile/16-rule/4-color limits,131072-byte wire budget and old snapshot decoding.
- Preserve Endfield art, charcoal/lime palette, battery layout and animation timing, app/menu icons, one HUD/sampler, priorities, carousel/persistence and history300.
- Only read documented Codex account limits using installed CLI; no inference, credential/cookie/transcript reads, login/logout/reset/purchase or account mutations.
- Match codex bucket and300/10080minute windows; show remaining percent and matching reset countdown; missing data is—.
- Reader is asynchronous, output bounded256KiB, timeout8s, single owned request, minimum60s spacing and normal300s refresh; cache two windows only, no disk cache/daemon/new recurring timer. Cancel/teardown safely; carousel gaps reuse cached success.
- Two opt-in entries create/select ordinary custom quota profiles, no automatic migration/default insertion.
- Official unmodified white mark only for Codex ring center; no battery/app/menu icon change.
- Run only relevant quota core/native checks; no broad24-group regression and no repeated performance matrix.

### Task1: Complete quota integration

Files create Sources/ChargeCore/CodexQuota.swift, Sources/EndfieldCharge/CodexQuotaReader.swift, focused core/native quota checks; modify existing metric/snapshot/demand/collector/filter/UI/renderer/CLI export locations and explicit runtime/build package input lists. Add official Resources/OpenAIMark.png/.svg (supplied privately) and attribution. Update bilingual README/developer guide only as needed.

- [ ] Write a handful of focused failing quota tests: codex bucket/window selection/clamp/unknowns, optional snapshot compatibility, reset countdown, demand. Run `bash scripts/test.sh --filter CodexQuota` to confirm missing new API, then implement parser/models and all exhaustive metric switches.
- [ ] Implement read-only protocol client and lazy asynchronous cached reader; integrate demand/reader lifecycle without blocking existing collector. Inject clock/fetch for deterministic concurrency checks; one focused native Codex group exercises selection, cache/oneflight/cancel/unknown/owner cleanup. Avoid a test framework or exhaustive duplicate cases.
- [ ] Add the two opt-in choices to the existing capsule menu and local hints. Preserve current profiles/defaults/maxcount and pending editor fence. Add quota reset metadata/pure countdown helper to presentation and a Codex-only ring logo/countdown branch. Main CLI supports explicit synthetic5h/week quota export using fixture data, not live account samples.
- [ ] Copy exact provided official assets, bundlePNG/checkpresence, update notices. Only affected native source input list and group lists gain Codex files/case.
- [ ] Run relevant core filter/native Codex group once per meaningful fix, one universal package build/check. Export two quota demos and three original battery stages; controller compares battery PNG hashes to prior validated original fixtures. No unrelated full regression.
- [ ] Self-review, commit, full report `.superpowers/sdd/codex-quota-report.md` with exact commands/results, protocol/assets, lifecycle proof and limitations. Controller performs one independent read-only review and final integration/delivery. Scope any later doc fix to diff checking only.
