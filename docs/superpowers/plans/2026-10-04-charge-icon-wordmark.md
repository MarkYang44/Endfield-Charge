# App icon contour and wordmark refinement

User-approved amendment to the v1.0.1 icon design: increase contour density and place the original ENDFIELD wordmark below the inverted triangle. This supersedes the previous app-icon omission of lettering; the menu-bar design stays unchanged.

## Global constraints
- Only the App icon gains denser contours and the ENDFIELD wordmark, positioned below the inverted triangle.
- Reuse the six original outlined wordmark elements from Resources/endfield-industries.svg; do not substitute an installed font.
- Preserve charcoal #262425, off-white #E9E7E4, lime #C6CA4C, transparent rounded-square corners and the existing HUD-derived bolt.
- MenuBarIcon.png must retain SHA256 d5be9d72656c7e7b733c3cb67a1e7caa90892f0fc72d790ba7ed02a14cedcacf; ChargeMenuIcon.svg must retain SHA256 b0c3efa6bb7957c82785d62b099fa84b4bf9bd9192704983d4eefe1dd69bc7d1.
- Preserve the supplied original SVG, HUD artwork/animations, telemetry, shortcut behavior and stored preferences.
- Keep the artwork exporter developer-only and dependency-free at runtime.

## Tasks
- [x] 1. Extend native vector artwork, regenerate the App PNG/SVG and size preview, verify deterministic export and unchanged menu hashes.
- [x] 2. Update version/build to 1.0.2/3, current documentation, attribution and release notes. Build and verify the universal archive.
- [x] 3. Independently review artwork and branch, install locally preserving preferences, publish v1.0.2, inspect the actual downloadable archive and record evidence.

## Verification
Use existing core/runtime checks and universal packaging. Inspect native-size previews; check exact original glyph outlines, palette, alpha corners, ICNS source pixels, menu/original SVG hashes, signatures, architectures, ZIP contents, local installed files, preserved settings and Release notes. Avoid implementation-mirroring tests for static artwork.

## Completed evidence

Source/tag `4ce8adc8ef86e8d5e7fe6349997b42a9e2c751e1`; both independent reviews passed. Universal local/public packages, installed resources, unchanged menu hashes and preserved preferences verified. Public Release and downloadable ICNS checked. See [v1.0.2 verification](../../charge-icon-v1.0.2-validation.md).
