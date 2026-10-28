import AppKit
import ChargeCore

// Exercise the actual bounded asynchronous pipeline with a deliberately blocked collector.
final class BlockingCollector {
    let lock = NSLock()
    let release = DispatchSemaphore(value: 0)
    private var count = 0
    private var active = 0
    private var maximum = 0
    private var readOnMain = false
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    var activeCount: Int { lock.lock(); defer { lock.unlock() }; return active }
    var maximumActive: Int { lock.lock(); defer { lock.unlock() }; return maximum }
    var touchedMain: Bool { lock.lock(); defer { lock.unlock() }; return readOnMain }
    func read(_ battery: BatterySnapshot, _ demand: TelemetryDemand) -> TelemetrySnapshot {
        lock.lock(); count += 1; active += 1; maximum = max(maximum, active)
        readOnMain = readOnMain || Thread.isMainThread
        let index = count; lock.unlock()
        _ = release.wait(timeout: .now() + 10)
        lock.lock(); active -= 1; lock.unlock()
        return TelemetrySnapshot(sampledAt: Double(index), battery: battery,
            power: nil, compute: nil, thermal: nil,
            network: NetworkTelemetry(downloadBytesPerSecond: 100, uploadBytesPerSecond: 0,
                receivedBytes: 0, sentBytes: 0, interfaces: ["en0"]))
    }
}

func runTelemetryAsyncChecks(defaults: UserDefaults) throws {
    let asyncSettings = AppSettings(defaults: defaults)
    asyncSettings.value = Preferences()
    let blocker = BlockingCollector()
    var batteryReadOnMain = true
    var asyncMonitor: TelemetryMonitor? = TelemetryMonitor(settings: asyncSettings, battery: {
        batteryReadOnMain = batteryReadOnMain && Thread.isMainThread
        return telemetrySample.battery
    }, asyncRead: { battery, demand, _ in blocker.read(battery, demand) })
    weak var releasedAsyncMonitor: TelemetryMonitor?
    releasedAsyncMonitor = asyncMonitor
    var asyncPublications: [Double] = []
    var publishedOnMain = true
    asyncMonitor?.onSnapshot = {
        publishedOnMain = publishedOnMain && Thread.isMainThread
        asyncPublications.append($0.sampledAt)
    }
    asyncMonitor?.start()
    var mainContinued = false
    DispatchQueue.main.async { mainContinued = true }
    awaitCondition({ mainContinued && blocker.calls == 1 }, "Main loop continues while collector is blocked")
    check(!blocker.touchedMain && batteryReadOnMain, "Read runs on worker while battery capture stays on main")
    for _ in 0..<100 { asyncMonitor?.refresh() }
    asyncSettings.value.networkTelemetryEnabled = false
    asyncMonitor?.preferencesChanged()
    spin(0.05)
    check(blocker.calls == 1, "Rapid refreshes never enqueue overlapping collector work")
    blocker.release.signal()
    awaitCondition({ blocker.calls == 2 }, "Blocked refreshes coalesce into one latest request")
    check(asyncPublications.isEmpty, "Preference change discards the inflight stale completion")
    blocker.release.signal()
    awaitCondition({ asyncPublications == [2] }, "Only latest coalesced preference request publishes")
    check(asyncMonitor?.latestSnapshot?.network == nil, "Latest preference snapshot gates worker fields")
    asyncMonitor?.refresh()
    awaitCondition({ blocker.calls == 3 }, "Next blocked read begins")
    asyncMonitor?.setPanelVisible(true)
    blocker.release.signal()
    awaitCondition({ blocker.calls == 4 }, "Changed demand replaces blocked request")
    check(asyncPublications == [2], "Demand change discards old completion")
    blocker.release.signal()
    awaitCondition({ asyncPublications == [2, 4] }, "Latest demand publishes")
    asyncMonitor?.refresh()
    awaitCondition({ blocker.calls == 5 }, "Pre-wake read begins")
    asyncMonitor?.resetAfterWake()
    blocker.release.signal()
    awaitCondition({ blocker.calls == 6 }, "Wake schedules latest reset request")
    check(asyncPublications == [2, 4], "Wake rejects pre-wake completion")
    blocker.release.signal()
    awaitCondition({ asyncPublications == [2, 4, 6] }, "Post-wake reset request publishes")
    asyncMonitor?.refresh()
    awaitCondition({ blocker.calls == 7 }, "Pre-stop read begins")
    asyncMonitor?.stop()
    blocker.release.signal()
    awaitCondition({ blocker.activeCount == 0 }, "Stopped read finishes without blocking main")
    spin(0.05)
    check(asyncPublications == [2, 4, 6] && asyncMonitor?.latestSnapshot == nil, "Stop rejects inflight completion")
    asyncMonitor?.start()
    awaitCondition({ blocker.calls == 8 }, "Restart uses serial worker")
    asyncMonitor?.stop(); asyncMonitor = nil
    check(releasedAsyncMonitor == nil, "Blocked collector closures do not retain monitor owner")
    blocker.release.signal()
    awaitCondition({ blocker.activeCount == 0 }, "Released owner's worker finishes safely")
    check(blocker.maximumActive == 1 && publishedOnMain, "One serial collector and main-only publication")
    // Wrap the real production reader to prove a coalesced disable/re-enable still resets its baseline.
    let nativeGate = BlockingCollector()
    let resetSettings = AppSettings(defaults: defaults)
    resetSettings.value = Preferences()
    let resetMonitor = TelemetryMonitor(settings: resetSettings, battery: { telemetrySample.battery },
        asyncRead: { battery, demand, collect in
            _ = nativeGate.read(battery, demand)
            return collect()
        })
    var resetSnapshots: [TelemetrySnapshot] = []
    resetMonitor.onSnapshot = { resetSnapshots.append($0) }
    resetMonitor.setCapsuleMetrics([.networkDownloadBytesPerSecond])
    resetMonitor.start()
    awaitCondition({ nativeGate.calls == 1 }, "Real reader waits off-main before initial baseline")
    resetMonitor.setCapsuleMetrics([])
    resetMonitor.setCapsuleMetrics([.networkDownloadBytesPerSecond])
    nativeGate.release.signal()
    awaitCondition({ nativeGate.calls == 2 }, "Real latest request follows coalesced demand changes")
    check(resetSnapshots.isEmpty, "Old real-reader baseline is not published")
    nativeGate.release.signal()
    awaitCondition({ resetSnapshots.count == 1 }, "Real collector publishes the latest reenabled demand")
    check(resetSnapshots[0].network?.downloadBytesPerSecond == nil && resetSnapshots[0].network?.receivedBytes == 0,
        "Coalesced disabled network still resets rates and observation-session totals")
    resetMonitor.stop()
    print("PASS: blocked asynchronous collector responsiveness, bounded coalescing, stale generations and owner release")
}
