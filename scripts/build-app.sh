#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app="dist/Endfield Charge.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
build_flags=(--disable-sandbox --build-system native --cache-path "$PWD/.build/swift-cache" -c release)

if [[ "${1:-}" == "--universal" ]]; then
  for architecture in arm64 x86_64; do
    swift build "${build_flags[@]}" --triple "${architecture}-apple-macosx13.0"
    binary_dir=$(swift build "${build_flags[@]}" --triple "${architecture}-apple-macosx13.0" --show-bin-path)
    cp "$binary_dir/EndfieldCharge" "dist/EndfieldCharge-$architecture"
  done
  lipo -create dist/EndfieldCharge-arm64 dist/EndfieldCharge-x86_64 -output "$app/Contents/MacOS/EndfieldCharge"
else
  swift build "${build_flags[@]}"
  binary_dir=$(swift build "${build_flags[@]}" --show-bin-path)
  cp "$binary_dir/EndfieldCharge" "$app/Contents/MacOS/EndfieldCharge"
fi

# Strip only the packaged copy; SwiftPM products keep their symbols for diagnostics.
strip -x "$app/Contents/MacOS/EndfieldCharge"

iconset="dist/EndfieldCharge.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
cp Resources/MenuBarIcon.png Resources/endfield-industries.svg "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Endfield Charge</string>
<key>CFBundleDisplayName</key><string>Endfield Charge</string>
<key>CFBundleIdentifier</key><string>com.markyang.endfieldcharge</string>
<key>CFBundleExecutable</key><string>EndfieldCharge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>1.0.2</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
codesign --verify --strict "$app"
ditto -c -k --keepParent "$app" dist/Endfield-Charge-macOS.zip
printf 'App: %s\nArchive: %s\n' "$PWD/$app" "$PWD/dist/Endfield-Charge-macOS.zip"
