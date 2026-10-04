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
}
