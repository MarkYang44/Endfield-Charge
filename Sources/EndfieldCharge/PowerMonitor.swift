import AppKit
import IOKit.ps
import ChargeCore
import os

final class PowerMonitor {
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var wakeObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.markyang.endfieldcharge", category: "power")
    var onSnapshot: ((BatterySnapshot) -> Void)?

    func start() {
        refresh()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.scheduleRefresh()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 5
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleRefresh() })
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleRefresh() }
        log.info("Power source observer started; fallback interval 30 seconds")
    }

    func scheduleRefresh() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func refresh() { onSnapshot?(BatteryReader.read()) }

    deinit {
        pending?.cancel()
        timer?.invalidate()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
