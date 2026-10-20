import Testing
@testable import ChargeCore

struct CapsulePlaybackTests {
    private final class Clock { var now = 0.0 }
    private func preferences(persistent: Bool = false, rotation: Bool = false) -> Preferences {
        var p = Preferences()
        p.playback = CapsulePlayback(persistent: persistent, rotationEnabled: rotation,
            profileIDs: [CapsuleProfile.cpuID, CapsuleProfile.networkID], intervalSeconds: 10)
        p.selectedCapsuleID = CapsuleProfile.cpuID
        return p
    }
    private func finish(_ scheduler: inout CapsulePlaybackScheduler) -> [CapsulePlaybackScheduler.Action] {
        scheduler.completed(serial: scheduler.current!.serial)
    }
    @Test func defaultsStayIdleAndOneManualCycleEnds() {
        let clock = Clock(); var s = CapsulePlaybackScheduler(clock: { clock.now })
        #expect(s.configure(Preferences()).isEmpty)
        #expect(s.receivedFreshSnapshot().isEmpty)
        #expect(s.current == nil && s.nextDeadline == nil)
        _ = s.startCycle()
        #expect(s.current?.request.profileID == CapsuleProfile.batteryID)
        #expect(s.nextDeadline == nil)
        _ = finish(&s)
        #expect(s.current == nil && s.nextDeadline == nil)
    }
    @Test func transientRoundStartsSelectedWrapsOnceAndHonorsFullCycleGap() {
        let clock = Clock(); var s = CapsulePlaybackScheduler(clock: { clock.now })
        var p = preferences(rotation: true); p.duration = 10; p.selectedCapsuleID = CapsuleProfile.networkID
        _ = s.configure(p); _ = s.receivedFreshSnapshot(); _ = s.startCycle()
        #expect(s.current?.request.profileID == CapsuleProfile.networkID)
        clock.now = 10; _ = finish(&s)
        #expect(s.current == nil && s.nextDeadline == 10.25)
        clock.now = 10.24; #expect(s.advance().isEmpty)
        clock.now = 10.25; _ = s.advance()
        #expect(s.current?.request.profileID == CapsuleProfile.cpuID)
        clock.now = 20.25; _ = finish(&s)
        #expect(s.current == nil && s.nextDeadline == nil)
    }
    @Test func selectedOutsideQueueIsPrependedWithoutDuplicates() {
        var s = CapsulePlaybackScheduler(clock: { 0 })
        var p = preferences(rotation: true); p.selectedCapsuleID = CapsuleProfile.batteryID
        _ = s.configure(p); _ = s.startCycle()
        #expect(s.cycleProfileIDs == [CapsuleProfile.batteryID, CapsuleProfile.cpuID, CapsuleProfile.networkID])
    }
    @Test func persistentWaitsForFreshDataHoldsAndWrapsWithoutCatchup() {
        let clock = Clock(); var s = CapsulePlaybackScheduler(clock: { clock.now })
        _ = s.configure(preferences(persistent: true, rotation: true))
        #expect(s.current == nil)
        _ = s.receivedFreshSnapshot()
        #expect(s.current?.holding == true && s.current?.compactTransition == false)
        #expect(s.nextDeadline == 10)
        clock.now = 40; _ = s.advance()
        #expect(s.current?.request.profileID == CapsuleProfile.networkID)
        #expect(s.current?.compactTransition == true && s.nextDeadline == 50)
        clock.now = 50; _ = s.advance()
        #expect(s.current?.request.profileID == CapsuleProfile.cpuID && s.nextDeadline == 60)
    }
    @Test func singlePersistentProfileNeverSchedulesRotation() {
        var s = CapsulePlaybackScheduler(clock: { 0 })
        var p = preferences(persistent: true, rotation: true); p.playback.profileIDs = [CapsuleProfile.cpuID]
        _ = s.configure(p); _ = s.receivedFreshSnapshot()
        #expect(s.current?.holding == true && s.nextDeadline == nil)
    }
    @Test func powerInterruptsAndResumesSameAmbientWithFullDwell() {
        let clock = Clock(); var s = CapsulePlaybackScheduler(clock: { clock.now })
        _ = s.configure(preferences(persistent: true, rotation: true)); _ = s.receivedFreshSnapshot()
        let oldSerial = s.current!.serial
        clock.now = 8; _ = s.submit(.init(id: "power", priority: .power))
        #expect(s.current?.request.id == "power" && s.nextDeadline == nil)
        #expect(s.completed(serial: oldSerial).isEmpty)
        clock.now = 14; _ = finish(&s)
        #expect(s.current?.request.profileID == CapsuleProfile.cpuID && s.nextDeadline == 24)
    }
    @Test func priorityQueueAndPreviewReplacement() {
        var s = CapsulePlaybackScheduler(clock: { 0 })
        _ = s.configure(preferences()); _ = s.submit(.init(id: "power", priority: .power))
        _ = s.submit(.init(id: "preview-old", priority: .preview))
        _ = s.submit(.init(id: "preview-new", priority: .preview))
        _ = s.submit(.init(id: "alert", priority: .alert))
        #expect(s.current?.request.id == "power")
        _ = finish(&s); #expect(s.current?.request.id == "alert")
        _ = finish(&s); #expect(s.current?.request.id == "preview-new")
        _ = finish(&s); #expect(s.current == nil)
    }
    @Test func alertsInterruptPreviewButQueueBehindOtherAlertsAndRemainBounded() {
        var s = CapsulePlaybackScheduler(clock: { 0 })
        _ = s.configure(preferences()); _ = s.submit(.init(id: "preview", priority: .preview))
        for i in 0..<8 { _ = s.submit(.init(id: "a\(i)", priority: .alert)) }
        #expect(s.current?.request.id == "a0" && s.pendingAlertCount == 4)
        #expect(s.retainedRequestIDs.count == 6)
        _ = finish(&s); #expect(s.current?.request.id == "a1")
    }
    @Test func configurationCancellationRemovesInvalidRequestsBeforeRestoringQueue() {
        var s = CapsulePlaybackScheduler(clock: { 0 })
        var p = preferences()
        _ = s.configure(p)
        _ = s.submit(.init(id: "active-invalid", priority: .alert))
        _ = s.submit(.init(id: "queued-invalid", priority: .alert))
        _ = s.submit(.init(id: "queued-valid", priority: .alert))
        p.duration = 7
        let actions = s.configure(p, canceling: ["active-invalid", "queued-invalid"])
        let shown = actions.compactMap { action -> String? in
            if case .show(let presentation) = action { return presentation.request.id }
            return nil
        }
        #expect(shown == ["queued-valid"])
        #expect(s.current?.request.id == "queued-valid" && s.pendingAlertCount == 0)
    }
    @Test func oldAlertsAndWaitingPreviewExpire() {
        let clock = Clock(); var s = CapsulePlaybackScheduler(clock: { clock.now })
        _ = s.submit(.init(id: "power", priority: .power))
        _ = s.submit(.init(id: "alert", priority: .alert)); _ = s.submit(.init(id: "preview", priority: .preview))
        clock.now = 30.01; _ = finish(&s)
        #expect(s.current == nil && s.pendingAlertCount == 0 && s.retainedRequestIDs.isEmpty)
    }
    @Test func hideReleasesAmbientButAllowsIndependentAlerts() {
        let clock = Clock(); var s = CapsulePlaybackScheduler(clock: { clock.now })
        _ = s.configure(preferences(persistent: true, rotation: true)); _ = s.receivedFreshSnapshot()
        #expect(s.setHidden(true) == [.hide])
        #expect(s.current == nil && s.nextDeadline == nil)
        _ = s.submit(.init(id: "alert", priority: .alert)); #expect(s.current?.request.id == "alert")
        _ = finish(&s); #expect(s.current == nil)
        clock.now = 100; _ = s.setHidden(false); #expect(s.nextDeadline == 110)
    }
    @Test func hidePausesFirstTransientCarouselItemAndResumeRestartsIt() {
        let clock = Clock(); var s = CapsulePlaybackScheduler(clock: { clock.now })
        _ = s.configure(preferences(rotation: true)); _ = s.startCycle()
        #expect(s.current?.request.beginsCycle == true)
        #expect(s.setHidden(true) == [.hide])
        #expect(s.current == nil && s.nextDeadline == nil)
        clock.now = 20; _ = s.setHidden(false)
        #expect(s.current?.request.profileID == CapsuleProfile.cpuID)
        #expect(s.current?.request.priority == .ambient)
        clock.now = 26; _ = finish(&s)
        #expect(s.nextDeadline == 30)
    }
    @Test func hidePausesCarouselWaitingBehindPowerUntilResume() {
        let clock = Clock(); var s = CapsulePlaybackScheduler(clock: { clock.now })
        _ = s.configure(preferences(rotation: true))
        _ = s.submit(.init(id: "power", priority: .power)); _ = s.startCycle()
        _ = s.setHidden(true)
        #expect(s.current?.request.id == "power")
        clock.now = 6; _ = finish(&s)
        #expect(s.current == nil && s.nextDeadline == nil)
        clock.now = 40; _ = s.setHidden(false)
        #expect(s.current?.request.profileID == CapsuleProfile.cpuID)
        #expect(s.current?.request.priority == .ambient)
    }
    @Test func hidingAmbientDoesNotCancelIndependentManualPreview() {
        var s = CapsulePlaybackScheduler(clock: { 0 })
        _ = s.configure(preferences(rotation: true))
        _ = s.submit(.init(id: "explicit-preview", priority: .preview, profileID: CapsuleProfile.cpuID))
        #expect(s.setHidden(true).isEmpty)
        #expect(s.current?.request.id == "explicit-preview")
    }
    @Test func sleepClearsEventsAndWakeRequiresNewSnapshot() {
        let clock = Clock(); var s = CapsulePlaybackScheduler(clock: { clock.now })
        _ = s.configure(preferences(persistent: true, rotation: true)); _ = s.receivedFreshSnapshot()
        _ = s.submit(.init(id: "power", priority: .power)); _ = s.submit(.init(id: "alert", priority: .alert))
        _ = s.suspend()
        #expect(s.current == nil && s.retainedRequestIDs.isEmpty && s.nextDeadline == nil)
        #expect(s.receivedFreshSnapshot().isEmpty)
        clock.now = 100; #expect(s.wake().isEmpty && s.current == nil)
        _ = s.receivedFreshSnapshot()
        #expect(s.current?.request.profileID == CapsuleProfile.cpuID && s.nextDeadline == 110)
    }
    @Test func transientCycleWaitsForFreshWakeSnapshotAfterIndependentPower() {
        let clock = Clock(); var s = CapsulePlaybackScheduler(clock: { clock.now })
        _ = s.configure(preferences(rotation: true)); _ = s.startCycle()
        _ = s.suspend(); _ = s.wake()
        _ = s.submit(.init(id: "fresh-power", priority: .power))
        clock.now = 6; _ = finish(&s)
        #expect(s.current == nil && s.nextDeadline == nil)
        _ = s.setHidden(true); _ = s.setHidden(false)
        #expect(s.current == nil)
        _ = s.receivedFreshSnapshot()
        #expect(s.current?.request.profileID == CapsuleProfile.cpuID)
    }
    @Test func deletingActiveProfileInvalidatesSelectionAndFallsBack() {
        var s = CapsulePlaybackScheduler(clock: { 0 }); var p = preferences(persistent: true, rotation: true)
        _ = s.configure(p); _ = s.receivedFreshSnapshot()
        p.capsuleProfiles.removeAll { $0.id == CapsuleProfile.cpuID || $0.id == CapsuleProfile.networkID }
        _ = s.configure(p)
        #expect(s.current?.request.profileID == CapsuleProfile.batteryID && s.nextDeadline == nil)
    }
    @Test func transientInterruptedDuringGapResumesNextItemWithoutCatchup() {
        let clock = Clock(); var s = CapsulePlaybackScheduler(clock: { clock.now })
        _ = s.configure(preferences(rotation: true)); _ = s.startCycle()
        clock.now = 6; _ = finish(&s)
        clock.now = 8; _ = s.submit(.init(id: "power", priority: .power))
        clock.now = 14; _ = finish(&s)
        #expect(s.current?.request.profileID == CapsuleProfile.networkID)
        #expect(s.nextDeadline == nil)
    }
    @Test func queuedManualCycleReplacesPreviousManualPreviewAndExpires() {
        let clock = Clock(); var s = CapsulePlaybackScheduler(clock: { clock.now })
        _ = s.configure(preferences(rotation: true))
        _ = s.submit(.init(id: "power", priority: .power))
        _ = s.submit(.init(id: "old-preview", priority: .preview))
        _ = s.startCycle()
        #expect(!s.retainedRequestIDs.contains("old-preview"))
        clock.now = 31; _ = finish(&s)
        #expect(s.current == nil && s.nextDeadline == nil)
    }
    @Test func manualCycleStartsAtPreviewPriorityAndPowerRestartsItsFirstItem() {
        let clock = Clock(); var s = CapsulePlaybackScheduler(clock: { clock.now })
        _ = s.configure(preferences(rotation: true)); _ = s.startCycle()
        #expect(s.current?.request.priority == .preview)
        clock.now = 2; _ = s.submit(.init(id: "power", priority: .power))
        clock.now = 8; _ = finish(&s)
        #expect(s.current?.request.profileID == CapsuleProfile.cpuID)
        clock.now = 14; _ = finish(&s)
        #expect(s.nextDeadline == 18)
    }

}
