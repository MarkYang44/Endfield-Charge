# Codex quota capsules

Approved scope: the user requests selectable 5-hour/weekly Codex quotas and then explicitly requests an OpenAI/Codex logo inside the right ring and quota reset countdown in the middle. Keep Endfield styling and the battery capsule's visuals/timing unchanged.

## UI

Offer two opt-in entries in the existing Active Capsule menu: Codex · 5 hours and Codex · Weekly. Selecting an absent preset explicitly creates a normal custom profile with the chosen quota as primary/ring metric and maximum100; subsequently select its existing profile. Do not append to old saved arrays or change the five existing defaults or12-profile capacity. Preserve custom edits/deletion, persistence, sharing, carousel and optional persistence. Disable new creation at capacity. Add localized quota metric names/hints and gracefully handle no login/window/data.

Codex capsules show remaining percent on the left, localized reset countdown in the middle, original official white OpenAI Blossom inside the right lime remaining-percentage ring. Unknown values/countdown use an em dash. Keep original secondary-metric rendering for non-Codex capsules. Derive countdown from resetsAt with an injectable time for deterministic checks; show compact d/h/m, <1m, or reset-due text without negative or stale zero claims. Existing on-demand sampler redraws update it; no extra countdown timer.

## Source / lifecycle

Use documented local Codex app-server JSON-RPC initialize → initialized → account/rateLimits/read. No inference, threads, login/logout/reset/credits mutations, cookies, transcript parsing or direct credential reading. This host's signed-in CLI was successfully probed in0.996s; proxy mode had no running daemon, so standalone stdio is the supported implementation. CLI found at /Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex; also discover ordinary CLI and Codex app bundle paths.

Prefer rateLimitsByLimitId.codex, fallback only to a compatible legacy codex bucket; never display another model/feature bucket. Match windows by windowDurationMins300/10080 rather than primary/secondary order. Remaining=clamp(100-usedPercent,0...100); absent/nonfinite data is unavailable. Optional resetsAt is Unix seconds.

Add a small pure Codable snapshot model and two remaining-percent metric cases. Missing new snapshot fields decode compatibly. Preserve wire budget and strict-vs-forgiving configuration policies.

Fetch only while requested by a visible/active quota profile, a quota color condition, or an explicitly enabled quota rule. Integrate demand with the existing shared sampler. A dedicated bounded asynchronous reader returns cached data immediately; external CLI must not block normal CPU/network/storage collection or the main thread. At most one owned CLI request, bounded output256KiB and timeout8s, all owned pipes/processes close on completion/cancel/deinit. Refresh at most once per5minutes (earlier at a known reset, with minimum60s retry spacing). Keep only two small quota windows in memory, no disk cache, no persistent CLI daemon/new recurring timer. Preserve cache across carousel gaps to avoid a CLI launch each rotation; clear it on wake/reset. Canceled/old generations must not publish or retain owners; unavailable refresh cannot be shown as fresh data.

## Assets and compatibility

Official logo source https://cdn.openai.com/brand/OpenAI-Logos-2025.zip, members OpenAI-logos(new)/PNGs/OpenAI-white-monoblossom.png (SHA256622bfd33c52cf8229165bb10ea23906ddd680813e5a4feaec82b16fa5d17cf0e), SVG counterpart b94ea61d860fae6f82f43571f36f17111fcf5d348e8e9cc22ae4b441c7560011. Preserve unmodified files; bundle PNG only, draw proportionally with official white and clear space, identify quota source only. Attribution links https://openai.com/brand/; no endorsement/trademark ownership claim. App/menu icons unchanged. Native PNG loading needs no new runtime or dependency.

macOS13+, Swift tools5.9, no new libraries. Current project is0595ffc; existing scene design, power>alert>preview>ambient priority, sharing safety and history cap300 unchanged. Bilingual user/developer docs explain local login/CLI requirement, remaining-vs-used, approximate refresh and unsupported windows.

## Focused verification

Only Codex quota parser/countdown/demand/compatibility core checks; focused native Codex group for actual preset selection, cache/coalescing/cancellation/nonblocking/error paths and rendering. Reuse prior unrelated suite evidence; no full24-group rerun. One universal build/package check and representative pre/post battery PNG equality plus two quota exports. Live read-only account smoke once; never publish live quota/account data in demos/docs. One read-only final review, no duplicated task/branch reviews. User explicitly requests not spending effort on repeated broad tests.

Official protocol documentation: https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt . No platform API key is used: this is an authenticated local Codex account read, not a model API request.
