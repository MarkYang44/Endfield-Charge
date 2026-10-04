import AppKit
import ChargeCore

// In-process checks of actual native owners and timers; never touches the user's preferences.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// The same executable hosts the real child role, allowing an actual pipe/exit/reopen regression.
if let index = CommandLine.arguments.firstIndex(of: "--settings-ui") {
    let args = CommandLine.arguments
    let parent = Int32(args[index + 1])!, tab = Int(args[index + 2])!
    let delegate = SettingsApplicationDelegate(parentPID: parent, tab: tab, frame: args[index + 3])
    app.delegate = delegate
    var closedAt: Double?
    let exitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
        object: app, queue: .main) { _ in
        guard let closedAt, let path = ProcessInfo.processInfo.environment["ENDFIELD_RUNTIME_EXITS"],
              let file = FileHandle(forWritingAtPath: path) else { return }
        let record: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "tab": tab,
            "close_seconds": ProcessInfo.processInfo.systemUptime - closedAt]
        var bytes = try! JSONSerialization.data(withJSONObject: record)
        bytes.append(0x0A)
        _ = try? file.seekToEnd(); try? file.write(contentsOf: bytes); try? file.close()
    }
    _ = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
        guard let window = app.windows.first(where: { $0.isVisible && $0.toolbar != nil }) else {
            fputs("FAIL: child settings window missing\n", stderr); exit(1)
        }
        if tab == 0 {
            guard let tabs = window.toolbar?.items.compactMap({ $0.view as? NSSegmentedControl }).first else {
                fputs("FAIL: child settings tabs missing\n", stderr); exit(1)
            }
            tabs.selectedSegment = 3
            app.sendAction(tabs.action!, to: tabs.target, from: tabs)
            window.setFrameOrigin(NSPoint(x: 100, y: 200))
        } else if tab != 3 || window.frame.origin != NSPoint(x: 100, y: 200) {
            fputs("FAIL: child reopen lost tab/position\n", stderr); exit(1)
        }
        _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: true)
        closedAt = ProcessInfo.processInfo.systemUptime
        window.close()
    }
    withExtendedLifetime((delegate, exitObserver)) { app.run() }
    exit(0)
}
let domain = "com.markyang.endfieldcharge.runtime-checks.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: domain)!
defer { defaults.removePersistentDomain(forName: domain) }
let settings = AppSettings(defaults: defaults)
func spin(_ seconds: Double) { autoreleasepool { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) } }
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
var appChanges = 0, uiChanges = 0
settings.onChange = { appChanges += 1 }
settings.onUIChange = { uiChanges += 1 }
let original = settings.value
settings.value = original
check(appChanges == 0 && uiChanges == 0, "Unchanged preferences must not notify/write")
settings.value.showPercentage = false
check(appChanges == 1 && uiChanges == 1, "App and UI notifications are independent")
let restored = AppSettings(defaults: defaults)
check(restored.value == settings.value, "All preferences survive saving/reloading")
let savedData = defaults.data(forKey: "preferences")
var peer = settings.value; peer.duration = 7
settings.applyFromPeer(peer)
check(settings.value.duration == 7 && defaults.data(forKey: "preferences") == savedData, "Peer updates apply without duplicate persistence")
print("PASS: preference guard, peer updates and independent app/UI callbacks")

let lockPath = FileManager.default.temporaryDirectory.appendingPathComponent("endfield-lock-check-\(UUID().uuidString)").path
var lock: ResidentInstance? = try ResidentInstance(path: lockPath)
do {
    _ = try ResidentInstance(path: lockPath)
    check(false, "Second resident must fail to acquire the lock")
} catch ResidentInstance.LockError.alreadyRunning(let pid) {
    check(pid == ProcessInfo.processInfo.processIdentifier, "Lock identifies the resident, not settings")
}
lock = nil
lock = try ResidentInstance(path: lockPath)
lock = nil
try FileManager.default.removeItem(atPath: lockPath)
print("PASS: resident-only locking and release")

let forward = Pipe(), backward = Pipe()
var parentChannel: SettingsChannel? = SettingsChannel(input: backward.fileHandleForReading, output: forward.fileHandleForWriting)
var childChannel: SettingsChannel? = SettingsChannel(input: forward.fileHandleForReading, output: backward.fileHandleForWriting)
var received: [Int] = []
parentChannel?.onMessage = { message in received.append(message.revision ?? -1) }
for revision in 0..<200 { childChannel?.send(SettingsMessage(.changed, preferences: peer, revision: revision)) }
let deadline = Date(timeIntervalSinceNow: 3)
while received.count < 200 && Date() < deadline { spin(0.05) }
check(received == Array(0..<200), "Rapid changes must arrive in order without loss")
var fragment = try JSONEncoder().encode(SettingsMessage(.closed, preferences: peer, revision: 200, tab: 2, frame: "{{100,200},{620,520}}"))
fragment.append(0x0A)
let split = fragment.count / 2
try backward.fileHandleForWriting.write(contentsOf: fragment.prefix(split))
spin(0.05)
check(received.count == 200, "Partial pipe frames must wait for completion")
try backward.fileHandleForWriting.write(contentsOf: fragment.suffix(fragment.count - split))
spin(0.1)
check(received.last == 200, "Fragmented final preferences/close state must decode")
var pipeEnded = false
parentChannel?.onEnd = { pipeEnded = true }
childChannel?.send(SettingsMessage(.closed, revision: 201))
childChannel?.flush { childChannel = nil }
let endDeadline = Date(timeIntervalSinceNow: 2)
while !pipeEnded && Date() < endDeadline { spin(0.05) }
check(pipeEnded && received.last == 201, "Final queued write must arrive before pipe EOF")
parentChannel = nil
print("PASS: 200 ordered pipe messages, fragmented frame and flushed final write before EOF")

var owner: SettingsWindowController?
var savedTab = -1
var savedFrame = NSRect.zero
weak var releasedController: SettingsWindowController?
weak var releasedWindow: NSWindow?
autoreleasepool {
    owner = SettingsWindowController(settings: settings, selectedTab: 2, frame: nil, onPreview: { _ in }, onClose: { tab, frame in
        savedTab = tab; savedFrame = frame; owner = nil
    })
    releasedController = owner
    releasedWindow = owner?.window
    owner?.present()
    owner?.window?.setFrameOrigin(NSPoint(x: 100, y: 200))
    owner?.window?.close()
}
spin(0.1)
check(savedTab == 2 && savedFrame.origin == NSPoint(x: 100, y: 200), "Close preserves tab and position")
check(releasedController == nil && releasedWindow == nil, "Closed settings controller/window must deallocate")
check(settings.onUIChange == nil && settings.onChange != nil, "Closing UI detaches only the UI callback")
print("PASS: settings window release and preserved reopen state")

for tab in 0..<4 {
    autoreleasepool {
        let controller = SettingsWindowController(settings: settings, selectedTab: tab, frame: savedFrame,
            onPreview: { _ in }, onClose: { _, _ in })
        controller.present()
        check(controller.window?.frame == savedFrame, "Reopened frame remains identical")
        check(!controller.bindings.isEmpty || tab == 3, "Current page controls are bound")
        controller.window?.close()
    }
}
spin(0.1)
print("PASS: all four lazy settings pages can open/close")

settings.value.duration = 4
let hud = HUDController(settings: settings)
let initial = BatterySnapshot(hasBattery: true, percent: 76, externalPower: true, isCharging: true)
let alert = BatterySnapshot(hasBattery: true, percent: 19)
func visibleHUD() -> HUDView? {
    autoreleasepool {
        app.windows.first(where: { $0.isVisible && $0.contentView is HUDView })?.contentView as? HUDView
    }
}
weak var releasedHUD: HUDView?
autoreleasepool {
hud.show(initial)
spin(2.75)
check(visibleHUD()?.kind == .power, "Initial HUD reaches static hold")
hud.show(alert, kind: .lowBattery, queued: true)
spin(0.1)
check(visibleHUD()?.kind == .power, "Alert queues instead of interrupting the static hold")
spin(1.3)
check(visibleHUD()?.kind == .lowBattery, "Queued alert plays after the first HUD closes")
let interrupted = BatterySnapshot(hasBattery: true, percent: 50)
hud.show(interrupted)
check(visibleHUD()?.snapshot.percent == 50, "Nonqueued preview interrupts immediately")
releasedHUD = visibleHUD()
spin(4.2)
check(visibleHUD() == nil, "Finished HUD is no longer visible")
}
check(releasedHUD == nil, "Finished HUD view/backing owner deallocates")
print("PASS: static-hold queue, preview interruption and HUD release")

settings.value.duration = 3
for _ in 0..<3 {
    autoreleasepool { hud.show(initial) }
    spin(3.2)
    check(visibleHUD() == nil, "Repeated HUD has no lingering visible panel")
}
print("PASS: repeated animation lifecycle")

// A bare test executable has a separate defaults domain from the installed application.
let standardPreferences = UserDefaults.standard.data(forKey: "preferences")
var fixture = Preferences()
fixture.scale = 0.85; fixture.duration = 3; fixture.showPercentage = false
UserDefaults.standard.set(try JSONEncoder().encode(fixture), forKey: "preferences")
UserDefaults.standard.synchronize()
var previews = 0
var settingsProcess: SettingsProcessController?
var displayContext: UInt32?
let exitsURL = FileManager.default.temporaryDirectory.appendingPathComponent("endfield-runtime-exits-\(UUID().uuidString)")
FileManager.default.createFile(atPath: exitsURL.path, contents: Data())
let previousExitsPath = ProcessInfo.processInfo.environment["ENDFIELD_RUNTIME_EXITS"]
setenv("ENDFIELD_RUNTIME_EXITS", exitsURL.path, 1)
settingsProcess = SettingsProcessController(settings: settings, onPreview: { _ in
    previews += 1
    // Child has queued preview then close; parent sends show then acknowledgment.
    // The closing child must flush its reopen request and parent must drain EOF before release.
    if previews == 1 { settingsProcess?.open() }
}, onScreen: { displayContext = $0 })
settingsProcess?.open()
let reopenDeadline = Date(timeIntervalSinceNow: 7)
while previews < 2 && Date() < reopenDeadline { spin(0.05) }
spin(0.3)
check(previews == 2, "Immediate show/closeAck must reopen a fresh settings process")
check(settings.value == fixture, "Child preferences survive ready/close/reopen without stale overwrite")
check(displayContext == nil, "Closed child clears context for future previews")
let exits = try String(contentsOf: exitsURL).split(separator: "\n").map {
    try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
}
check(exits.count == 2, "Both settings children terminate naturally before the test stops them")
for record in exits {
    check((record["close_seconds"] as! Double) < 1.5, "Close acknowledgment exits before the 2-second fallback")
    check(kill((record["pid"] as! NSNumber).int32Value, 0) == -1 && errno == ESRCH, "Closed child is no longer a process")
}
settingsProcess?.stop(); settingsProcess = nil
if let previousExitsPath { setenv("ENDFIELD_RUNTIME_EXITS", previousExitsPath, 1) } else { unsetenv("ENDFIELD_RUNTIME_EXITS") }
try FileManager.default.removeItem(at: exitsURL)
UserDefaults.standard.set(standardPreferences, forKey: "preferences")
print("PASS: actual child process, preview, close acknowledgment, rapid reopen and tab/frame preservation")
print("All 8 native runtime check groups passed")
