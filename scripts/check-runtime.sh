#!/bin/bash
set -euo pipefail
usage() { echo 'Usage: bash scripts/check-runtime.sh [--group all|hud|telemetry|sharing|editors|ipc]' >&2; exit 2; }
group=all
if [[ $# != 0 ]]; then
  [[ $# == 2 && "$1" == --group ]] || usage
  group=$2
fi
case "$group" in all|hud|telemetry|sharing|editors|ipc) ;; *) usage ;; esac
cd "$(dirname "$0")/.."
# Build fresh core objects without running unrelated core tests. Requires a graphical macOS session.
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
build_flags=(--disable-sandbox --build-system native --cache-path "$PWD/.build/swift-cache")
swift build "${build_flags[@]}" --target ChargeCore
binary_dir=$(swift build "${build_flags[@]}" --show-bin-path)
# Compile only the native check directory, in a stable locale-defined order.
export LC_ALL=C
runtime_checks=(Tests/RuntimeChecks/*.swift)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/endfield-runtime-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -I "$binary_dir/Modules" \
  Sources/EndfieldCharge/AppSettings.swift Sources/EndfieldCharge/HotKey.swift \
  Sources/EndfieldCharge/ConfigurationBackupStore.swift Sources/EndfieldCharge/ConfigurationTransactionService.swift \
  Sources/EndfieldCharge/SettingsSharing.swift Sources/EndfieldCharge/SettingsChannel.swift Sources/EndfieldCharge/ResidentInstance.swift \
  Sources/EndfieldCharge/SettingsProcessController.swift Sources/EndfieldCharge/SettingsApplicationDelegate.swift \
  Sources/EndfieldCharge/NetworkReader.swift Sources/EndfieldCharge/StorageReader.swift \
  Sources/EndfieldCharge/CapsulePresentation.swift Sources/EndfieldCharge/TelemetryReader.swift Sources/EndfieldCharge/TelemetryMonitor.swift \
  Sources/EndfieldCharge/BatteryReader.swift Sources/EndfieldCharge/TelemetryApplicationDelegate.swift \
  Sources/EndfieldCharge/TelemetryView.swift Sources/EndfieldCharge/TelemetryWindowController.swift \
  Sources/EndfieldCharge/HUDView.swift Sources/EndfieldCharge/HUDController.swift Sources/EndfieldCharge/CapsulePlaybackController.swift \
  Sources/EndfieldCharge/SettingsControls.swift Sources/EndfieldCharge/SettingsPages.swift \
  Sources/EndfieldCharge/SettingsAppearance.swift Sources/EndfieldCharge/SettingsPlayback.swift Sources/EndfieldCharge/SettingsCapsules.swift Sources/EndfieldCharge/SettingsRules.swift \
  Sources/EndfieldCharge/SettingsWindowController.swift "${runtime_checks[@]}" \
  "$binary_dir"/ChargeCore.build/*.o -o "$check_dir/check-runtime"
"$check_dir/check-runtime" --group "$group"
