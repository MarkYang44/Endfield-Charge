import AppKit
import ChargeCore

func runPreferencesAndIPCChecks(settings: AppSettings, defaults: UserDefaults) throws {
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
    withExtendedLifetime(lock) {}
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

    // Use real pipes and the production channel: neither pre-split lines nor a substitute parser.
    do {
        let incoming = Pipe(), outgoing = Pipe()
        let channel = SettingsChannel(input: incoming.fileHandleForReading, output: outgoing.fileHandleForWriting)
        var messages: [SettingsMessage] = []
        channel.onMessage = { messages.append($0) }
        func line(_ message: SettingsMessage) throws -> Data { try JSONEncoder().encode(message) + Data([10]) }
        func write(_ bytes: Data, fragmentSize: Int = 8192) throws {
            for offset in stride(from: 0, to: bytes.count, by: fragmentSize) {
                try incoming.fileHandleForWriting.write(contentsOf: bytes[offset..<min(offset + fragmentSize, bytes.count)])
                spin(0.01)
            }
            spin(0.03)
        }
        let maximum = maximumUnicodePreferences()
        let unicodeFrame = try line(SettingsMessage(.changed, preferences: maximum, revision: 1))
        check(unicodeFrame.count > 16_384, "Unicode regression exercises the former incomplete-frame cap")
        try write(unicodeFrame)
        check(messages.count == 1 && messages[0].preferences == maximum,
            "Maximum Unicode 12-profile/four-color/mixed-16-rule/12-queue configuration survives actual 8192-byte pipe fragments")
        // Each frame is valid even when their combined write is larger than one frame's budget.
        let coalesced = try (2...7).reduce(into: Data()) { $0.append(try line(SettingsMessage(.changed, preferences: maximum, revision: $1))) }
        try write(coalesced, fragmentSize: coalesced.count)
        check(messages.compactMap(\.revision) == Array(1...7), "Coalesced valid frames are budgeted individually")
        let budget = SettingsMessage.maximumPayloadBytes
        var exact = SettingsMessage(.screen, frame: "")
        exact.frame = String(repeating: "x", count: budget - (try JSONEncoder().encode(exact)).count)
        let exactFrame = try line(exact)
        check(exactFrame.count == budget + 1, "Boundary frame payload excludes its newline")
        try write(exactFrame)
        check(messages.count == 8 && messages.last?.frame == exact.frame, "Exactly budget-sized inbound frame is accepted")
        let oversized = try line(SettingsMessage(.screen, frame: String(repeating: "x", count: budget + 1)))
        try write(oversized + line(SettingsMessage(.preview, revision: 8)), fragmentSize: oversized.count + 100)
        check(messages.count == 9 && messages.last?.revision == 8, "Complete oversized frame is rejected and following valid frame recovers")
        try write(oversized.dropLast())
        check(messages.count == 9, "Fragmented oversized frame remains discarded before its terminator")
        try write(Data([10]) + line(SettingsMessage(.preview, revision: 9)))
        check(messages.count == 10 && messages.last?.revision == 9, "Fragmented oversized frame drains through newline then resumes")
        let returnChannel = SettingsChannel(input: outgoing.fileHandleForReading, output: incoming.fileHandleForWriting)
        var outbound: [SettingsMessage] = []
        returnChannel.onMessage = { outbound.append($0) }
        channel.send(SettingsMessage(.screen, frame: String(repeating: "x", count: budget + 1)))
        channel.send(exact)
        channel.send(SettingsMessage(.closed, revision: 10))
        var flushed = false
        channel.flush { flushed = true }
        awaitCondition({ flushed && outbound.last?.revision == 10 }, "Outbound oversize rejection preserves ordered final-close flush")
        check(outbound.count == 2 && outbound[0].frame == exact.frame, "Outbound queue rejects overbudget payload and accepts exact limit")
    }
    print("PASS: maximum Unicode pipe configuration, coalescing, exact wire boundary, oversized drain/recovery and outbound budget")
}
