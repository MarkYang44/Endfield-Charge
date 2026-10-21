# Upstream attribution

This independent macOS implementation follows the visual design of
[QinAnze/zmd-charge](https://github.com/QinAnze/zmd-charge), inspected at commit
`1e3e0611af340753af8163e4c36ece3eeeeec3ee`.

Upstream authors and contributors: QinAnze, Lenkmat, YacaiTofu,
programming666, and other contributors listed by that repository.

The double-parallelogram bolt coordinates in HUDView.swift and the developer-only
scripts/render-icons.swift derive from Styles/Geometries.axaml. HUD color values, dimensions, and baseline animation
cues follow Styles/HudTheme.axaml, Views/HudWindow.axaml, and
Animations/HudAnimations.cs. The macOS service and UI code and the simplified
inverted-triangle icon composition are new implementations.

The upstream README declares MIT. The inspected checkout contains no separate
LICENSE or copyright header, so no additional upstream copyright wording was
available to reproduce. The MIT permission and warranty text is reproduced in
LICENSE; that file's Mark Yang copyright applies to the new implementation,
not to upstream contributions. Keep this attribution with redistributed builds.

Resources/endfield-industries.svg is the Endfield logo artwork supplied by the
user and remains unchanged. Resources/ChargeIcon.svg and ChargeMenuIcon.svg
are derived compositions: the HUD bolt replaces the original nail. The App
composition reuses the original outlined ENDFIELD lettering below its triangle
and adds denser contour curves; the unchanged menu composition omits lettering
and contours. AppIcon.png and MenuBarIcon.png are their static raster exports.
The supplied SVG contains no license notice;
the project's MIT license does not grant rights to this brand artwork. Artwork
and trademark rights remain with their respective owners.

Arknights: Endfield is referenced only as visual inspiration. This utility is
unofficial and is not affiliated with or endorsed by the game developer.

## Endfield Charge Plus for macOS

Network interface counter collection/differencing, APFS Data volume capacity
semantics, bounded profile configuration and threshold-rule/cooldown ideas are
adapted from GlacierGlimmer/zmd-charge-plus-for-macos at commit
`b743c59d871ead486c840167d2d4cb0e159f0f6f`:

- native/ecpmac.m (network and disk collectors)
- Customization/MacVariableProvider.cs (counter differencing)
- Customization/HudTriggerRule.cs (rule baseline and cooldown)
- Customization/Models.cs (profile/configuration concepts)

Copyright (c) 2026 GlacierGlimmer_冰川雪貓. These contributions use MIT; the full
copyright, permission and warranty text is retained in
LICENSES/zmd-charge-plus-MIT.txt and packaged as zmd-charge-plus-MIT.txt.
This native Swift adaptation does not bundle that project's Avalonia/.NET
runtime, LibreHardwareMonitor, fonts, or additional game assets. Existing
upstream and brand-art notices above remain applicable.


## Windows Endfield Charge Plus concepts

Local configuration sharing, bounded color/state rules and carousel concepts
also reference [GlacierGlimmer/zmd-charge-plus](https://github.com/GlacierGlimmer/zmd-charge-plus)
at commit `dd17813e682215f3b91d17b40963c34cb8c64a95`, including
Settings/SettingsManager.cs, Customization/HudColorRuleParser.cs,
Customization/HudTriggerRule.cs and its
carousel behavior. This is a bounded native Swift reimplementation, not JSON
compatibility with arbitrary upstream files. Its MIT notice is the same
Copyright (c) 2026 GlacierGlimmer_冰川雪貓 retained in
LICENSES/zmd-charge-plus-MIT.txt and the packaged notice. No Windows/.NET
runtime, fonts or additional artwork are distributed.
