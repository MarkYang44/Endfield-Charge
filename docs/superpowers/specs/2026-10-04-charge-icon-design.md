# Endfield Charge icon identity

The user approved a simplified Endfield mark with the central nail replaced by a geometric lightning bolt. Implement this approved design without another confirmation gate.

## Artwork

- App icon: 1024×1024 transparent canvas, inset charcoal rounded-square base, off-white broken inverted-triangle outline, three restrained contour curves, and a lime (#C6CA4C) bolt.
- Preserve the angular, double-parallelogram bolt geometry already used by the upstream-derived HUD. Keep the bolt visually separated from the contour lines.
- Remove all text, the original nail, fine topographic detail, glow, percentage and battery graphics. Respect the inverted-triangle silhouette and sharp industrial edges.
- Menu-bar variant: transparent monochrome broken inverted triangle and bolt, with thicker strokes and no contour curves. Retain the existing 18 pt native template rendering for light/dark appearance.
- The supplied Resources/endfield-industries.svg remains byte-for-byte unchanged.

## Implementation and delivery

Keep vector sources and a deterministic developer-only native renderer in the repository. Export Resources/AppIcon.png (1024×1024) and Resources/MenuBarIcon.png (144×144), plus vector SVGs and a preview sheet showing large and small sizes. No new dependency, runtime drawing loop or network activity.

Release as v1.0.1 (bundle version 2), update About and attribution, include useful release notes, build a universal macOS 13+ app, and update the installed /Applications/Endfield Charge.app. Preserve all preferences, especially Command + Shift + E. Publish source and a new public Release; retain v1.0.0.

## Acceptance

Visually inspect 16/18/32/64/128/256 pt artwork, including a menu-bar preview on light and dark backgrounds. Verify transparent corners/background, source-logo fingerprint, original HUD source unchanged, package icon inclusion, universal architecture, strict signature, ZIP integrity, preserved preferences and the installed resident path. Verify the public v1.0.1 asset by downloading it and comparing its GitHub SHA256 digest.

## Approved v1.0.2 amendment

The user subsequently requested denser App-icon contour lines and the original ENDFIELD wordmark below the inverted triangle, while explicitly retaining the menu-bar icon. This supersedes the App-only three-curve/text-removal requirements above. See [the refinement plan](../plans/2026-10-04-charge-icon-wordmark.md); v1.0.1 verification remains a historical record.
