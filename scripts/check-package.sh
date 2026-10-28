#!/bin/bash
set -euo pipefail
usage() { echo 'Usage: bash scripts/check-package.sh ["path/App.app" path/archive.zip]' >&2; exit 2; }
[[ $# == 0 || $# == 2 ]] || usage
cd "$(dirname "$0")/.."
app=${1:-dist/Endfield Charge.app}
archive=${2:-dist/Endfield-Charge-macOS.zip}
fail() { echo "FAIL: $*" >&2; exit 1; }
check_app() {
  local bundle=$1 binary="$1/Contents/MacOS/EndfieldCharge" plist="$1/Contents/Info.plist" resource arch floor signature
  [[ -d "$bundle" && -x "$binary" && -f "$plist" ]] || fail "Missing application structure: $bundle"
  [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist") == EndfieldCharge ]] || fail 'Unexpected bundle executable'
  [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist") == com.markyang.endfieldcharge ]] || fail 'Unexpected bundle identifier'
  [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$plist") == APPL ]] || fail 'Expected APPL bundle'
  floor=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")
  [[ "$floor" == 13.0 || "$floor" == 13.0.0 ]] || fail "Expected macOS 13.0 plist floor, found $floor"
  for arch in arm64 x86_64; do
    lipo "$binary" -verify_arch "$arch" || fail "Application is missing $arch"
    floor=$(otool -arch "$arch" -l "$binary" | awk '
      $1 == "cmd" { build = ($2 == "LC_BUILD_VERSION"); legacy = ($2 == "LC_VERSION_MIN_MACOSX") }
      build && $1 == "minos" { print $2 }
      legacy && $1 == "version" { print $2 }')
    [[ "$floor" == 13.0 || "$floor" == 13.0.0 ]] || fail "Expected macOS 13.0 $arch binary floor, found $floor"
  done
  for resource in AppIcon.icns MenuBarIcon.png endfield-industries.svg PrivacyInfo.xcprivacy LICENSE THIRD_PARTY_NOTICES.md zmd-charge-plus-MIT.txt; do
    [[ -s "$bundle/Contents/Resources/$resource" ]] || fail "Missing/empty resource: $resource"
  done
  codesign --verify --deep --strict "$bundle" || fail 'Strict signature verification failed'
  signature=$(codesign -d --verbose=4 "$bundle" 2>&1)
  [[ "$signature" == *"Signature=adhoc"* ]] || fail 'Expected ad-hoc signature'
}
check_app "$app"
[[ -f "$archive" ]] || fail "Missing archive: $archive"
unzip -tq "$archive" || fail 'ZIP integrity failed'
# Reject unrelated distributions and unsafe paths before extraction. ditto metadata is allowed.
while IFS= read -r entry; do
  case "$entry" in
    *\\*|/*|../*|*/../*|*/..|*/./*) fail "Unsafe archive member: $entry" ;;
  esac
  case "$entry" in
    'Endfield Charge.app'|'Endfield Charge.app/'*|'__MACOSX/'|'__MACOSX/Endfield Charge.app/'*|'__MACOSX/._Endfield Charge.app') ;;
    *) fail "Unexpected archive member: $entry" ;;
  esac
done < <(unzip -Z1 "$archive")
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/endfield-package-check.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
ditto -x -k "$archive" "$check_dir"
check_app "$check_dir/Endfield Charge.app"
diff -rq "$app" "$check_dir/Endfield Charge.app" || fail 'Archive app differs from built app'
echo 'PASS: universal arm64+x86_64 app, macOS 13.0 floor, resources, strict ad-hoc signature and matching ZIP'
