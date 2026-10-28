import AppKit
import ChargeCore

// Child dispatch precedes fixtures and all parent-only checks.
app.setActivationPolicy(.accessory)
runChildRoleIfRequested()

let domain = "com.markyang.endfieldcharge.runtime-checks.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: domain)!
defer { defaults.removePersistentDomain(forName: domain) }
let settings = AppSettings(defaults: defaults)

let arguments = Array(CommandLine.arguments.dropFirst())
let group = arguments.count == 2 && arguments[0] == "--group" ? arguments[1] : "all"
let groups = ["all", "hud", "telemetry", "sharing", "editors", "ipc", "codex"]
guard (arguments.isEmpty || arguments.count == 2 && arguments[0] == "--group"), groups.contains(group) else {
    fputs("Usage: check-runtime [--group all|hud|telemetry|sharing|editors|ipc|codex]\n", stderr)
    exit(2)
}
// Keep the existing screenshot/legacy entry points and their original ordering.
let environment = ProcessInfo.processInfo.environment
if environment["ENDFIELD_EDITORS_ONLY"] == "1" { try runEditorChecks(); exit(0) }
if environment["ENDFIELD_SHARING_ONLY"] == "1" {
    try runEditorChecks(); try runSharingChecks(); exit(0)
}
if group == "all" || group == "editors" { try runEditorChecks() }
if group == "all" || group == "sharing" { try runSharingChecks() }
if group == "all" || group == "ipc" {
    try runPreferencesAndIPCChecks(settings: settings, defaults: defaults)
    try runWindowLifecycleChecks(settings: settings, domain: domain)
}
if group == "all" || group == "editors" { try runNativeEditorChecks(domain: domain) }
if group == "all" || group == "telemetry" {
    try runTelemetryViewChecks(settings: settings)
    try runTelemetrySamplerChecks(defaults: defaults)
    try runTelemetryAsyncChecks(defaults: defaults)
}
if group == "all" || group == "hud" { try runHUDChecks(settings: settings) }
if group == "all" || group == "ipc" { try runSubprocessLifecycleChecks(settings: settings) }
if group == "all" || group == "codex" { try runCodexQuotaChecks(defaults: defaults) }
print(group == "all" ? "All 25 native runtime check groups passed" : "Native \(group) checks passed")
