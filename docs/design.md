# Endfield Charge for macOS

## Purpose

Build a native macOS counterpart to QinAnze/zmd-charge: a menu bar utility that presents an Endfield-inspired battery HUD when a charger connects or disconnects. Keep all source and build scripts in this repository and publish it as Endfield-Charge under the user's GitHub account.

## Recommended implementation

Swift + AppKit for vector HUD drawing, the nonactivating floating panel, menu bar and native settings; IOKit for battery snapshots and power-source notifications. Target macOS 13+; support Apple Silicon and Intel builds. No third-party runtime or network access during ordinary use.

ChargeCore owns battery interpretation, event reduction, animation timing, preferences and the small settings-message schema. The resident application owns monitoring, exclusive shortcuts, reusable menu items and lazy HUD surfaces. Settings use an on-demand role of the same executable: only the current page is constructed, and the process exits on close to release AppKit caches. Private stdin/stdout pipes carry ordered changes, previews, screen context and close acknowledgment; the parent drains pending messages before releasing the child. A resident-only advisory lock avoids confusing the settings process with the resident instance. Closing settings clears future screen context without moving a HUD already displayed.

Alternatives considered: porting Avalonia preserves framework familiarity but adds .NET and replaces all Windows-native services anyway; an Electron utility adds a large runtime for a small HUD. A native utility best matches the requested local macOS system.

## Behavior and appearance

- A dark capsule near the top of the selected display. Three stages: bolt appears, capsule expands to show a power-mode title, capsule contracts to show actual battery percentage and capacity, then dismisses.
- Charger connection uses outward ripples; disconnection uses inward ripples. Match the reference's charcoal, off-white, lime (#C6CA4C), and low-battery red (#FF4D4F).
- Distinguish external power from actual charging. Optimized charging, full charge, and external power while discharging must not be falsely labeled fast charging. “Super charge mode” is a visual theme, not a measured charging capability.
- Keep the visible pill's top edge 2 pt below the menu bar/notch at every configured scale; expand downward with that edge fixed. Compensate for the transparent canvas inset when positioning the panel. Do not take focus or intercept clicks. Honor Reduce Motion.
- App/menu identity: simplified broken inverted triangle with the HUD bolt replacing the original nail. App artwork uses charcoal/off-white/lime and three contour curves; the monochrome menu template omits contours. The supplied SVG remains unchanged. Menu bar: actual percentage, preview, charging/battery demos, settings, quit. A configurable native global shortcut previews actual state without accessibility permission. Select Command/Control/Option/Shift modifiers and A–Z; Carbon uses exclusive registration and reports occupied combinations. Existing preferences retain their previous shortcut and all other values.
- Settings: display, top-left/center/right, scale, duration, Chinese/English/system language, low-battery/full-charge alerts, low-power-mode alerts, and opt-in launch at login.
- Use debounced IOKit change events with a slow fallback refresh, recover after sleep, avoid duplicate alert storms, and handle Macs without batteries.
- Display mAh only when that unit is actually available. An energy value in Wh derived from capacity and current voltage must be marked approximate and displayed with one decimal place. Unknown data must remain unknown rather than using invented capacities.

## Delivery and verification

Provide a Swift package, focused battery/event tests, reproducible app packaging scripts, local .app and zip artifacts, a screenshot, Chinese setup instructions, attribution, and GitHub Actions build/test packaging. Build and launch on this Mac; compare reported battery data with pmset; inspect both animation modes and settings. Simulated previews cannot prove physical charger events, which must be recorded as a verification limit unless observed.

Use a new public repository named MarkYang44/Endfield-Charge. The user approved this native design and public visibility. Preserve upstream attribution and MIT notice where upstream-derived geometry or animation timing is used. Document local ad-hoc signing; do not claim Apple notarization.

## Reference

- https://github.com/QinAnze/zmd-charge
- Inspected upstream commit: 1e3e0611af340753af8163e4c36ece3eeeeec3ee
- The upstream README states MIT, but the inspected checkout contains no standalone LICENSE. Credit the upstream author and document which visual concepts were reimplemented.
