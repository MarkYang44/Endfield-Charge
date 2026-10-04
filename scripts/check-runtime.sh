#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Requires a graphical macOS session. Run scripts/test.sh first to compile ChargeCore.
binary_dir=$(swift build --disable-sandbox --build-system native --show-bin-path)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/endfield-runtime-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -I "$binary_dir/Modules" \
  Sources/EndfieldCharge/AppSettings.swift Sources/EndfieldCharge/HotKey.swift \
  Sources/EndfieldCharge/SettingsChannel.swift Sources/EndfieldCharge/ResidentInstance.swift \
  Sources/EndfieldCharge/SettingsProcessController.swift Sources/EndfieldCharge/SettingsApplicationDelegate.swift \
  Sources/EndfieldCharge/TelemetryReader.swift Sources/EndfieldCharge/TelemetryMonitor.swift \
  Sources/EndfieldCharge/BatteryReader.swift Sources/EndfieldCharge/TelemetryApplicationDelegate.swift \
  Sources/EndfieldCharge/TelemetryView.swift Sources/EndfieldCharge/TelemetryWindowController.swift \
  Sources/EndfieldCharge/HUDView.swift Sources/EndfieldCharge/HUDController.swift \
  Sources/EndfieldCharge/SettingsControls.swift Sources/EndfieldCharge/SettingsPages.swift \
  Sources/EndfieldCharge/SettingsWindowController.swift Tests/RuntimeChecks/main.swift \
  "$binary_dir"/ChargeCore.build/*.o -o "$check_dir/check-runtime"
"$check_dir/check-runtime"
