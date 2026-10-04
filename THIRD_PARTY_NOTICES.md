# Upstream attribution

This independent macOS implementation follows the visual design of
[QinAnze/zmd-charge](https://github.com/QinAnze/zmd-charge), inspected at commit
`1e3e0611af340753af8163e4c36ece3eeeeec3ee`.

Upstream authors and contributors: QinAnze, Lenkmat, YacaiTofu,
programming666, and other contributors listed by that repository.

The double-parallelogram bolt coordinates in HUDView.swift derive from
Styles/Geometries.axaml. HUD color values, dimensions, and baseline animation
cues follow Styles/HudTheme.axaml, Views/HudWindow.axaml, and
Animations/HudAnimations.cs. Resources/AppIcon.png is the upstream
Assets/tray_bolt.png, preserved without modification. macOS service and UI code
is a new implementation.

The upstream README declares MIT. The inspected checkout contains no separate
LICENSE or copyright header, so no additional upstream copyright wording was
available to reproduce. The MIT permission and warranty text is reproduced in
LICENSE; that file's Mark Yang copyright applies to the new implementation,
not to upstream contributions. Keep this attribution with redistributed builds.

Resources/endfield-industries.svg is the Endfield logo artwork supplied by the
user. Resources/MenuBarIcon.png is its transparent raster export, used only as
the macOS menu bar template image. The supplied SVG contains no license notice;
the project's MIT license does not grant rights to this brand artwork. Artwork
and trademark rights remain with their respective owners.

Arknights: Endfield is referenced only as visual inspiration. This utility is
unofficial and is not affiliated with or endorsed by the game developer.
