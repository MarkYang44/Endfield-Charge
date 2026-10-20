import Foundation
import ChargeCore

/// The resident is the only configuration writer. UI edits form an ordered digest chain;
/// imports additionally require a correlated revision and save a backup before the commit.
final class ConfigurationTransactionService {
    private let settings: AppSettings
    private let backupStore: ConfigurationBackupStore
    private var baseline: Preferences
    private(set) var revision = 0

    init(settings: AppSettings, backupStore: ConfigurationBackupStore = ConfigurationBackupStore()) {
        self.settings = settings; self.backupStore = backupStore; baseline = settings.value
    }

    private func observeResidentChanges() {
        if baseline != settings.value { baseline = settings.value; revision += 1 }
    }

    func state(_ command: SettingsMessage.Command = .state) -> SettingsMessage {
        observeResidentChanges()
        return SettingsMessage(command, preferences: settings.value, revision: revision, shortcutMessage: settings.shortcutMessage)
    }

    func receive(_ message: SettingsMessage) -> SettingsMessage? {
        observeResidentChanges()
        switch message.command {
        case .ready: return state(.ready)
        case .changed, .closed:
            guard let incoming = message.revision, let preferences = message.preferences else { return nil }
            // An unchanged final close is only a lifecycle event, never a second commit.
            if incoming == revision && preferences == settings.value { return feedback() }
            guard incoming > revision, let digest = message.baselineDigest,
                  digest == (try? ConfigurationTransactionRequest.digest(settings.value)),
                  (try? ConfigurationTransactionRequest.canonicalPreferences(preferences)) != nil else {
                // Advance past the rejected write; any following stale pipelined snapshots also fail their digest.
                revision = max(revision, min(incoming, Int.max - 1)) + 1
                return state()
            }
            baseline = preferences; revision = incoming
            settings.value = preferences
            return feedback()
        case .configurationRequest:
            guard let request = message.transactionRequest else { return nil }
            return transact(request)
        default: return nil
        }
    }

    private func feedback() -> SettingsMessage {
        // A normal ACK must never roll a newer helper edit back to an earlier snapshot.
        SettingsMessage(.state, revision: revision, shortcutMessage: settings.shortcutMessage)
    }

    private func transact(_ request: ConfigurationTransactionRequest) -> SettingsMessage {
        func result(_ status: ConfigurationTransactionStatus, _ failure: ConfigurationTransactionFailure? = nil) -> SettingsMessage {
            var message = state(.configurationResult)
            message.transactionResult = ConfigurationTransactionResult(requestID: request.requestID, status: status, failure: failure)
            return message
        }
        do {
            guard try request.matches(preferences: settings.value, revision: revision) else { return result(.stale) }
        } catch { return result(.rejected, .invalidConfiguration) }
        let next: Preferences
        switch request.action {
        case .importShare(let share, let mode):
            do { next = try share.preview(mode: mode, local: settings.value).preferences }
            catch { return result(.rejected, .invalidConfiguration) }
            do { try backupStore.save(settings.value) }
            catch { return result(.rejected, .storageFailure) }
        case .restoreBackup:
            do { next = try backupStore.load() }
            catch { return result(.rejected, .backupUnavailable) }
        }
        baseline = next; revision += 1
        settings.value = next
        return result(.applied)
    }
}

/// Shared by the real helper and pipe regression checks. Applying authoritative preferences
/// suppresses outgoing onChange, while preserving onUIChange for the visible editors.
final class SettingsConfigurationSession {
    enum SessionError: Error { case unavailable, pending }
    private let settings: AppSettings
    private let send: (SettingsMessage) -> Void
    private var outgoingBaseline: Preferences
    private var applying = false
    private var pendingRequest: (id: String, revision: Int, baseline: Preferences)?
    private(set) var initialized = false
    private(set) var revision = 0
    var pending: Bool { pendingRequest != nil }
    var onBusyChange: ((Bool) -> Void)?
    var onResult: ((ConfigurationTransactionResult) -> Void)?

    init(settings: AppSettings, send: @escaping (SettingsMessage) -> Void) {
        self.settings = settings; self.send = send; outgoingBaseline = settings.value
        settings.onChange = { [weak self] in self?.changed() }
    }

    func start() { send(SettingsMessage(.ready)) }

    private func changed() {
        guard initialized, !applying else { return }
        revision += 1
        let message = SettingsMessage(.changed, preferences: settings.value, revision: revision,
            baselineDigest: try? ConfigurationTransactionRequest.digest(outgoingBaseline))
        outgoingBaseline = settings.value
        send(message)
    }

    func submit(_ action: ConfigurationTransactionAction) throws {
        guard initialized else { throw SessionError.unavailable }
        guard !pending else { throw SessionError.pending }
        let request = try ConfigurationTransactionRequest(requestID: UUID().uuidString,
            expectedRevision: revision, baseline: settings.value, action: action)
        let message = SettingsMessage(.configurationRequest, transactionRequest: request)
        _ = try message.encodedBounded()
        pendingRequest = (request.requestID, revision, settings.value)
        onBusyChange?(true)
        // SettingsChannel serializes this after every preceding ordinary .changed write.
        send(message)
    }

    func receive(_ message: SettingsMessage) {
        settings.shortcutMessage = message.shortcutMessage ?? settings.shortcutMessage
        if message.command == .configurationResult {
            guard let result = message.transactionResult, let pendingRequest,
                  result.requestID == pendingRequest.id else { return }
            self.pendingRequest = nil
            if revision == pendingRequest.revision && settings.value == pendingRequest.baseline {
                apply(message)
            }
            onBusyChange?(false)
            onResult?(result)
        } else if message.command == .ready || (message.command == .state && message.preferences != nil) {
            guard (message.revision ?? -1) >= revision else { return }
            apply(message)
        }
    }

    private func apply(_ message: SettingsMessage) {
        guard let value = message.preferences, let revision = message.revision else { return }
        applying = true
        self.revision = revision; outgoingBaseline = value; initialized = true
        settings.applyFromPeer(value)
        applying = false
        onBusyChange?(pending)
    }

    func closed(tab: Int, frame: String) -> SettingsMessage {
        SettingsMessage(.closed, preferences: initialized && !pending ? settings.value : nil,
            revision: revision, tab: tab, frame: frame,
            baselineDigest: try? ConfigurationTransactionRequest.digest(outgoingBaseline))
    }

    func disconnect() {
        pendingRequest = nil; initialized = false
        onBusyChange?(false)
    }
}
