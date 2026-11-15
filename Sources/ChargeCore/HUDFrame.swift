/// Deterministic timeline based on QinAnze/zmd-charge's six-second HUD cues.
public struct HUDFrame: Equatable {
    public var pillOpacity, pillScale, pillHeight, cornerRadius: Double
    public var boltOpacity, boltScale, boltX, squareMix: Double
    public var titleOpacity, numbersOpacity, rippleProgress, rippleOpacity, overallScale: Double

    public static func redrawDelay(after seconds: Double, duration: Double = 6, reduceMotion: Bool = false) -> Double? {
        let duration = duration.isFinite ? min(10, max(3, duration)) : 6
        guard seconds.isFinite, seconds < duration else { return nil }
        let settled = reduceMotion ? 0.15 : 2.52
        let closing = duration - 0.35
        return seconds >= settled && seconds < closing ? closing - seconds : 1.0 / 60
    }

    public static func at(seconds: Double, duration: Double = 6, reduceMotion: Bool = false) -> HUDFrame {
        let duration = duration.isFinite ? min(10, max(3, duration)) : 6
        let t = seconds.isFinite ? max(0, seconds) : duration
        func progress(_ start: Double, _ end: Double) -> Double { min(1, max(0, (t - start) / (end - start))) }
        func smooth(_ start: Double, _ end: Double) -> Double {
            let x = progress(start, end)
            return x < 0.5 ? 4*x*x*x : 1 - pow3(-2*x + 2)/2
        }
        let close = smooth(duration - 0.35, duration)
        if reduceMotion {
            let opacity = smooth(0, 0.15) * (1 - close)
            return HUDFrame(pillOpacity: opacity, pillScale: 1, pillHeight: 60, cornerRadius: 30,
                boltOpacity: opacity, boltScale: 1, boltX: -245, squareMix: 1, titleOpacity: opacity,
                numbersOpacity: opacity, rippleProgress: 0, rippleOpacity: 0, overallScale: t >= duration ? 0 : 1)
        }
        let expand = smooth(0.42, 0.72), contract = smooth(1.8, 2.16)
        let visible = t < duration ? 1.0 : 0.0
        let boltPop = smooth(0.24, 0.6)
        return HUDFrame(pillOpacity: smooth(0.42, 0.54) * visible,
            pillScale: 0.6 + 0.4*smooth(0.42, 0.54), pillHeight: 60 + 30*expand*(1-contract),
            cornerRadius: 30 - 12*expand*(1-contract), boltOpacity: boltPop*visible,
            boltScale: 0.4 + 0.72*boltPop - 0.12*smooth(0.6, 0.72),
            boltX: -179*smooth(0.72, 1.2) - 66*contract, squareMix: contract,
            titleOpacity: smooth(1.2, 1.5)*(1-contract)*visible,
            numbersOpacity: smooth(2.28, 2.52)*visible, rippleProgress: smooth(0.72, 1.8),
            rippleOpacity: smooth(0.72, 0.84)*(1-contract)*visible, overallScale: 1-close)
    }
    private static func pow3(_ x: Double) -> Double { x*x*x }
}

/// Carousel swap between two held compact capsules. The outgoing capsule fades while settling to 96 %, then the
/// incoming one rises from 96 % to full size and opacity. Nothing scales from zero, the exit (0.14 s) is quicker
/// than the entry (0.22 s), and both use a strong ease-out so motion starts at once. The total stays 0.36 s.
public enum CompactSwap {
    public static let exitDuration = 0.14
    public static let duration = 0.36
    public static let restingScale = 0.96

    public struct Frame: Equatable {
        public let scale: Double
        public let opacity: Double
        public let showsIncoming: Bool
    }

    public static func frame(at seconds: Double) -> Frame {
        let t = seconds.isFinite ? max(0, seconds) : duration
        if t < exitDuration {
            let eased = easeOut(t / exitDuration)
            return Frame(scale: 1 - (1 - restingScale) * eased, opacity: 1 - eased, showsIncoming: false)
        }
        let eased = easeOut((t - exitDuration) / (duration - exitDuration))
        return Frame(scale: restingScale + (1 - restingScale) * eased, opacity: eased, showsIncoming: true)
    }

    /// Quintic ease-out, a close match for cubic-bezier(0.23, 1, 0.32, 1).
    public static func easeOut(_ x: Double) -> Double {
        let remaining = 1 - min(1, max(0, x))
        return 1 - remaining * remaining * remaining * remaining * remaining
    }
}
