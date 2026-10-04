# Custom shortcut and Endfield menu icon

User-approved scope: allow modifier selection and A–Z keys, set this Mac to Command + Shift + E, and use the supplied Endfield Industries SVG for the menu bar icon.

Keep Carbon registration and automatic settings persistence. Preserve old preferences by decoding the newly added modifiers with Control + Option as the fallback. Keep existing defaults for other installations. Require Command, Control or Option when a global shortcut is enabled; use exclusive registration and report unavailable combinations in settings.

Keep the supplied SVG unchanged. Export a high-resolution transparent PNG from it and include both source SVG and PNG in the app resources. Render it as an 18 pt template image so macOS controls its light/dark appearance. HUD bolt artwork remains part of the existing animation. The checked-in PNG avoids an additional conversion dependency in CI or at runtime.

- [x] Add regression tests for legacy preference migration and custom shortcut persistence.
- [x] Implement modifier selection, A–Z key registration and configuration feedback.
- [x] Package the supplied logo and replace the menu bar image.
- [x] Run tests, build the universal app, inspect settings/icon, and confirm Command + Shift + E persists and registers. Record the automated-input limit and the user's subsequent successful physical-keyboard test.
- [x] Verify the ZIP and document asset provenance.
- [x] Push the update to GitHub (implementation commit `8d705aa6db2c5bfe27a6c6069270ae5179b91620`).
