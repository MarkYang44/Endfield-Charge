/// One deterministic owner for presentation priority, bounded events, and ambient playback.
/// Time is monotonic and injected; the native bridge owns the single deadline timer.
public struct CapsulePlaybackScheduler {
    public enum Priority: Int, Equatable { case ambient, preview, alert, power }
    public struct Request: Equatable {
        public var id: String
        public var priority: Priority
        public var profileID: String?
        public var ruleID: String?
        public fileprivate(set) var beginsCycle = false
        public init(id: String, priority: Priority, profileID: String? = nil, ruleID: String? = nil) {
            self.id = id; self.priority = priority; self.profileID = profileID; self.ruleID = ruleID
        }
    }
    public struct Presentation: Equatable {
        public let serial: UInt64
        public let request: Request
        public let holding: Bool
        public let compactTransition: Bool
    }
    public enum Action: Equatable { case show(Presentation), hide }
    private struct Pending { let request: Request; let createdAt: Double }
    private let clock: () -> Double
    private var preferences = Preferences()
    private var pendingAlerts: [Pending] = []
    private var pendingPreview: Pending?
    private var currentEvent: Pending?
    private var serial: UInt64 = 0
    private var startedAt = 0.0
    private var ambientIndex = 0
    private var cycleActive = false
    private var ambientIntroduced = false
    private var hasFreshSnapshot = false
    private var awaitingWakeSnapshot = false
    private var sleeping = false
    public private(set) var isHidden = false
    public private(set) var current: Presentation?
    public private(set) var nextDeadline: Double?
    public private(set) var cycleProfileIDs: [String] = []
    public var pendingAlertCount: Int { pendingAlerts.count }
    public var retainedRequestIDs: Set<String> {
        Set(pendingAlerts.map { $0.request.id } + [pendingPreview?.request.id, current?.request.id].compactMap { $0 })
    }
    public init(clock: @escaping () -> Double) { self.clock = clock }

    public mutating func configure(_ value: Preferences, canceling requestIDs: Set<String> = []) -> [Action] {
        let old = preferences
        preferences = value
        preferences.playback.normalize(profiles: preferences.capsuleProfiles)
        let changed = old.playback != preferences.playback || old.selectedCapsuleID != value.selectedCapsuleID
            || old.capsuleProfiles != value.capsuleProfiles || old.duration != value.duration
        var actions = removeRequests(requestIDs)
        if changed {
            cycleProfileIDs = preferences.playback.effectiveProfileIDs(selectedID: preferences.selectedCapsuleID,
                profiles: preferences.capsuleProfiles)
            ambientIndex = 0; ambientIntroduced = false
            // Settings changes do not spontaneously launch a transient round.
            cycleActive = preferences.playback.persistent
            nextDeadline = nil
            if current?.request.priority == .ambient || current?.request.beginsCycle == true { actions += clearCurrent() }
            if pendingPreview?.request.beginsCycle == true { pendingPreview = nil }
        }
        prune(at: clock())
        if let request = current?.request, !valid(request) { actions += clearCurrent() }
        actions += restore(at: clock())
        return actions
    }

    /// Explicit invocation: selected first, then each queued profile exactly once.
    public mutating func startCycle() -> [Action] {
        guard !sleeping else { return [] }
        cycleProfileIDs = preferences.playback.effectiveProfileIDs(selectedID: preferences.selectedCapsuleID,
            profiles: preferences.capsuleProfiles)
        let selected = preferences.capsuleProfiles.contains { $0.id == preferences.selectedCapsuleID }
            ? preferences.selectedCapsuleID : cycleProfileIDs.first
        if let selected {
            if let index = cycleProfileIDs.firstIndex(of: selected) {
                cycleProfileIDs = Array(cycleProfileIDs[index...]) + Array(cycleProfileIDs[..<index])
            } else { cycleProfileIDs.insert(selected, at: 0) }
        }
        cycleProfileIDs = Array(cycleProfileIDs.prefix(ConfigurationLimits.maximumProfiles))
        ambientIndex = 0; cycleActive = false; ambientIntroduced = false; nextDeadline = nil
        guard let first = cycleProfileIDs.first else { return [] }
        var request = Request(id: "cycle.start", priority: .preview, profileID: first)
        request.beginsCycle = true
        return submit(request)
    }

    public mutating func submit(_ request: Request) -> [Action] {
        guard !sleeping, request.priority != .ambient, valid(request) else { return [] }
        let now = clock(); prune(at: now)
        let event = Pending(request: request, createdAt: now)
        if request.priority == .preview {
            pendingPreview = event
            if let current, current.request.priority.rawValue > Priority.preview.rawValue { return [] }
        } else if request.priority == .alert,
                  let current, current.request.priority.rawValue >= Priority.alert.rawValue {
            if pendingAlerts.count < 4 { pendingAlerts.append(event) }
            return []
        }
        // Interrupted one-shot content can finish later, with the original freshness deadline.
        if let previous = currentEvent {
            if previous.request.priority == .alert, pendingAlerts.count < 4 { pendingAlerts.insert(previous, at: 0) }
            if previous.request.priority == .preview && request.priority != .preview && pendingPreview == nil {
                pendingPreview = previous
            }
        }
        if request.priority == .preview { pendingPreview = nil }
        nextDeadline = nil // Ambient resumes from its current item with a whole new dwell.
        return show(event, at: now)
    }

    public mutating func completed(serial: UInt64) -> [Action] {
        guard let current, current.serial == serial, !current.holding else { return [] }
        let now = clock()
        let wasAmbient = current.request.priority == .ambient || current.request.beginsCycle
        var actions = clearCurrent()
        if wasAmbient {
            ambientIndex += 1
            if ambientIndex >= cycleProfileIDs.count { cycleActive = false; nextDeadline = nil }
            else { nextDeadline = max(now + 0.25, startedAt + max(interval, duration + 0.25)) }
        }
        actions += restore(at: now)
        return actions
    }

    public mutating func advance() -> [Action] {
        let now = clock(); prune(at: now)
        guard let deadline = nextDeadline, now >= deadline, !sleeping, !isHidden else { return [] }
        nextDeadline = nil
        if current?.request.priority == .ambient && preferences.playback.persistent {
            ambientIndex = (ambientIndex + 1) % max(1, cycleProfileIDs.count)
            current = nil; currentEvent = nil
        }
        return restore(at: now)
    }
    public mutating func cancel(requestIDs: Set<String>) -> [Action] {
        let actions = removeRequests(requestIDs)
        return actions + restore(at: clock())
    }
    private mutating func removeRequests(_ requestIDs: Set<String>) -> [Action] {
        pendingAlerts.removeAll { requestIDs.contains($0.request.id) }
        if let p = pendingPreview, requestIDs.contains(p.request.id) { pendingPreview = nil }
        if let current, requestIDs.contains(current.request.id) { return clearCurrent() }
        return []
    }
    public mutating func setHidden(_ hidden: Bool) -> [Action] {
        guard isHidden != hidden else { return [] }
        isHidden = hidden; nextDeadline = nil
        var actions: [Action] = []
        if hidden, pendingPreview?.request.beginsCycle == true {
            pendingPreview = nil; cycleActive = true
        }
        if hidden, current?.request.priority == .ambient || current?.request.beginsCycle == true { actions += clearCurrent() }
        return actions + restore(at: clock())
    }
    public mutating func suspend() -> [Action] {
        sleeping = true; hasFreshSnapshot = false; awaitingWakeSnapshot = true; nextDeadline = nil
        pendingAlerts.removeAll(); pendingPreview = nil; ambientIntroduced = false
        return clearCurrent()
    }
    public mutating func wake() -> [Action] {
        let actions = suspend()
        sleeping = false
        return actions
    }
    public mutating func receivedFreshSnapshot() -> [Action] {
        guard !sleeping else { return [] }
        hasFreshSnapshot = true; awaitingWakeSnapshot = false
        return restore(at: clock())
    }
    private var duration: Double { preferences.duration.isFinite ? min(10, max(3, preferences.duration)) : 6 }
    private var interval: Double { preferences.playback.intervalSeconds }
    private func valid(_ request: Request) -> Bool {
        if let id = request.profileID, !preferences.capsuleProfiles.contains(where: { $0.id == id }) { return false }
        if let id = request.ruleID, !preferences.telemetryAlertRules.contains(where: { $0.id == id && $0.enabled }) { return false }
        return true
    }
    private mutating func prune(at now: Double) {
        pendingAlerts = pendingAlerts.filter { now - $0.createdAt <= 30 && now >= $0.createdAt && valid($0.request) }
        if let event = pendingPreview, now - event.createdAt > 30 || now < event.createdAt || !valid(event.request) {
            if event.request.beginsCycle { cycleActive = false }
            pendingPreview = nil
        }
    }
    private mutating func clearCurrent() -> [Action] {
        let visible = current != nil
        current = nil; currentEvent = nil
        return visible ? [.hide] : []
    }
    private mutating func show(_ event: Pending, at now: Double, holding: Bool = false, compact: Bool = false) -> [Action] {
        if event.request.beginsCycle { cycleActive = true }
        serial &+= 1; startedAt = now; currentEvent = event
        let presentation = Presentation(serial: serial, request: event.request, holding: holding, compactTransition: compact)
        current = presentation
        return [.show(presentation)]
    }
    private mutating func restore(at now: Double) -> [Action] {
        guard current == nil, !sleeping else { return [] }
        prune(at: now)
        if !pendingAlerts.isEmpty { nextDeadline = nil; return show(pendingAlerts.removeFirst(), at: now) }
        if let event = pendingPreview { pendingPreview = nil; nextDeadline = nil; return show(event, at: now) }
        guard !isHidden, !awaitingWakeSnapshot, cycleActive, !cycleProfileIDs.isEmpty,
              !preferences.playback.persistent || hasFreshSnapshot else { return [] }
        if let deadline = nextDeadline, now < deadline { return [] }
        nextDeadline = nil
        ambientIndex = min(ambientIndex, cycleProfileIDs.count - 1)
        let id = cycleProfileIDs[ambientIndex]
        let holding = preferences.playback.persistent
        let compact = holding && ambientIntroduced
        ambientIntroduced = true
        let actions = show(Pending(request: Request(id: "ambient.\(id)", priority: .ambient, profileID: id), createdAt: now),
            at: now, holding: holding, compact: compact)
        if holding && cycleProfileIDs.count > 1 { nextDeadline = now + interval }
        return actions
    }
}
