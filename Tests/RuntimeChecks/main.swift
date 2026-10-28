import AppKit
import ChargeCore

// Child dispatch precedes fixtures and all parent-only checks.
app.setActivationPolicy(.accessory)
runChildRoleIfRequested()

let domain = "com.markyang.endfieldcharge.runtime-checks.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: domain)!
defer { defaults.removePersistentDomain(forName: domain) }
let settings = AppSettings(defaults: defaults)

try runEditorChecks()
if ProcessInfo.processInfo.environment["ENDFIELD_EDITORS_ONLY"] == "1" { exit(0) }
try runSharingChecks()
if ProcessInfo.processInfo.environment["ENDFIELD_SHARING_ONLY"] == "1" { exit(0) }
try runPreferencesAndIPCChecks(settings: settings, defaults: defaults)
try runWindowLifecycleChecks(settings: settings, domain: domain)
try runNativeEditorChecks(domain: domain)
try runTelemetryViewChecks(settings: settings)
try runTelemetrySamplerChecks(defaults: defaults)
try runTelemetryAsyncChecks(defaults: defaults)
try runHUDChecks(settings: settings)
try runSubprocessLifecycleChecks(settings: settings)
print("All 24 native runtime check groups passed")
