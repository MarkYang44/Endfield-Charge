/// Deterministic timeline based on QinAnze/zmd-charge's six-second HUD cues.
public struct HUDFrame {
    public var pillOpacity, pillScale, pillHeight, cornerRadius: Double
    public var boltOpacity, boltScale, boltX, squareMix: Double
    public var titleOpacity, numbersOpacity, rippleProgress, rippleOpacity, overallScale: Double

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
