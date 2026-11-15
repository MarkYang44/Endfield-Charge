import Testing
@testable import ChargeCore

struct HUDSchedulingTests {
    @Test func staticHoldSleepsUntilClosingWithoutChangingFrame() {
        #expect(abs((HUDFrame.redrawDelay(after: 3, duration: 6) ?? 0) - 2.65) < 1e-9)
        #expect(HUDFrame.at(seconds: 2.52) == HUDFrame.at(seconds: 5.65))
        #expect(HUDFrame.redrawDelay(after: 2.51, duration: 6) == 1.0 / 60)
        #expect(HUDFrame.redrawDelay(after: 5.65, duration: 6) == 1.0 / 60)
        #expect(HUDFrame.redrawDelay(after: 6, duration: 6) == nil)
    }

    @Test func reducedMotionSleepsAfterFadeAndKeepsExitAnimation() {
        #expect(HUDFrame.redrawDelay(after: 0.15, duration: 3, reduceMotion: true) == 2.5)
        #expect(HUDFrame.redrawDelay(after: 0.14, duration: 3, reduceMotion: true) == 1.0 / 60)
        #expect(HUDFrame.redrawDelay(after: 2.66, duration: 3, reduceMotion: true) == 1.0 / 60)
        #expect(HUDFrame.at(seconds: 0.15, duration: 3, reduceMotion: true)
            == HUDFrame.at(seconds: 2.65, duration: 3, reduceMotion: true))
    }

    @Test func durationAndInvalidTimeFollowTheRenderedTimeline() {
        #expect(HUDFrame.redrawDelay(after: 3, duration: 1) == nil)
        #expect(HUDFrame.redrawDelay(after: 10, duration: 100) == nil)
        #expect(HUDFrame.redrawDelay(after: .nan) == nil)
        #expect(abs((HUDFrame.redrawDelay(after: 3, duration: .infinity) ?? 0) - 2.65) < 1e-9)
    }

    @Test func compactSwapNeverScalesFromZeroAndExitsFasterThanItEnters() {
        #expect(CompactSwap.frame(at: 0) == CompactSwap.Frame(scale: 1, opacity: 1, showsIncoming: false))
        let handoff = CompactSwap.frame(at: CompactSwap.exitDuration)
        #expect(handoff.showsIncoming && handoff.opacity == 0 && abs(handoff.scale - 0.96) < 1e-12)
        #expect(CompactSwap.frame(at: CompactSwap.duration) == CompactSwap.Frame(scale: 1, opacity: 1, showsIncoming: true))
        #expect(CompactSwap.frame(at: .infinity) == CompactSwap.frame(at: CompactSwap.duration))
        #expect(CompactSwap.exitDuration < CompactSwap.duration - CompactSwap.exitDuration)
        var previous = CompactSwap.frame(at: 0)
        for step in 1...72 {
            let frame = CompactSwap.frame(at: Double(step) * 0.005)
            #expect(frame.scale >= 0.96 - 1e-12 && frame.scale <= 1 && (0...1).contains(frame.opacity))
            // Ease-out: each phase moves most in its first frames, so opacity changes direction only at the handoff.
            if frame.showsIncoming == previous.showsIncoming {
                #expect(frame.showsIncoming ? frame.opacity >= previous.opacity : frame.opacity <= previous.opacity)
            }
            previous = frame
        }
        #expect(CompactSwap.easeOut(0.2) > 0.6 && CompactSwap.easeOut(0) == 0 && CompactSwap.easeOut(1) == 1)
    }
}
