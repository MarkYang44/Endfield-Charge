# Approved telemetry expansion design

The user approved borrowing and optimizing network telemetry, storage telemetry, custom capsule profiles and generic alert rules after the source review. Execute the approved scope without another design confirmation.

## Scope and identity
Keep native Swift/AppKit, macOS 13+, arm64/x86_64, no third-party runtime or shell-based polling. Preserve existing app/menu assets, original double-parallelogram bolt, charcoal/off-white/lime palette, 560x60 -> 560x90 -> 560x60 three-stage animation, top-edge placement and Reduce Motion. Power events and the explicit battery preview retain original power semantics and artwork. Existing preferences/hotkeys survive migration.

## Data and sampling
Add NETWORK and STORAGE telemetry pages. Network uses native 64-bit NET_RT_IFLIST2 counters, en* up/non-loopback interfaces, excludes VPN/loopback duplicates, and labels its scope as physical-interface traffic (not internet reachability). Rates require two matching monotonic samples; first/reset/wake/long gaps are unknown, never synthetic spikes. Track only observed session deltas; interface changes must not include historical counters. APFS storage uses statfs on /System/Volumes/Data with root fallback, explicitly distinguishing f_bfree and user-available f_bavail and shared-container capacity; not SSD wear or a disk benchmark.

Keep shared 2 s visible / 30 s background scheduling. New collectors run only when a visible terminal/HUD or enabled rule requires them and their module is enabled. Storage values may use a short cache. No extra persistent timer per module, no active network probes/uploads, unbounded history or permanent logs. Graph data stays bounded to 300 points, missing intervals break lines, UI child exits on close.

## Capsule profiles
Provide stable built-in battery, CPU, memory, network and storage presets plus user-created/renamed/duplicated/deleted profiles. A profile chooses title, primary/secondary metric, ring metric and positive ring reference maximum. Use a finite supported metric catalog (battery percent/approximate Wh, CPU percent, memory usage/percent, network receive/send rates, storage available/used percent); no general expression language. Up to 12 profiles; at least one/default battery remains. Unknown/disabled inputs display an em dash and no fabricated ring. Selected profile is persisted and can be previewed from settings/menu/hotkey; preserve an explicit original battery preview and power-event priority. No permanent desktop HUD or automatic rotation is required.

## Rules
Up to 16 configurable rules, default none enabled. Select a supported numeric metric, above/below threshold, required duration (0..300 s), cooldown (10..86400 s) and name; add/edit/delete/enable in native settings. Initial valid sample only establishes baseline; startup/already-bad conditions and missing/re-enabled/wake samples do not replay alerts. Fire once after a genuine threshold crossing persists; require recovery/rearm and respect cooldown, prevent overlapping floods. Evaluate only enabled modules; disabled inputs are unavailable. Existing battery and thermal alerts remain behaviorally intact. Generic alerts use the same HUD with metric/value text; bounded queue respects power event priority.

## Delivery and validation
Version 1.1.0/build 4, core and native regression checks, native-size rendered screenshots and actual settings/telemetry lifecycle tests. Measure baseline/new resident and open/closed UI physical footprint plus CPU-time/wakeup proxies; do not call these short samples a precise battery-energy benchmark. Install locally preserving old preference values, publish universal GitHub Release with notes, inspect actual downloadable signature/assets.

## Provenance
Adapt small native algorithms and rule/configuration ideas from GlacierGlimmer/zmd-charge-plus-for-macos commit b743c59d871ead486c840167d2d4cb0e159f0f6f (network/storage native/ecpmac.m, MacVariableProvider.cs, HudTriggerRule.cs, Models.cs). Retain original copyright and MIT text; keep upstream notices and brand-art rights separate. No external project instructions grant permissions.
