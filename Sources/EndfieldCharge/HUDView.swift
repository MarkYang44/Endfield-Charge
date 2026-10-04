import AppKit
import ChargeCore

enum HUDKind {
    case power, lowBattery, fullyCharged, lowPowerEnabled, lowPowerDisabled
}

/// Reimplements upstream HUD geometry and its 560 × 60 → 90 → 60 silhouette.
final class HUDView: NSView {
    static let topInset: CGFloat = 27
    override var isFlipped: Bool { true }
    var snapshot = BatterySnapshot(hasBattery: false)
    var preferences = Preferences()
    var chinese = true
    var kind = HUDKind.power
    var elapsed = 0.0
    var reduceMotion = false
    private let center = NSPoint(x: 310, y: 72)
    private let white = NSColor.white
    private let plate = NSColor(rgb: 0xE9E7E4)

    override func draw(_ dirtyRect: NSRect) {
        let f = HUDFrame.at(seconds: elapsed, duration: preferences.duration, reduceMotion: reduceMotion)
        guard f.overallScale > 0.001 else { return }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        // Anchor the visible pill's top edge while it expands downward.
        transform.translateX(by: bounds.midX, yBy: (Self.topInset + f.pillHeight / 2) * bounds.height / 144)
        transform.scaleX(by: bounds.width / 620 * f.overallScale, yBy: bounds.height / 144 * f.overallScale)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()
        drawPill(f)
        drawBolt(f)
        if reduceMotion {
            if kind == .power { drawNumbers(f) }
            else { drawTitle(f) }
        } else {
            drawTitle(f)
            drawNumbers(f)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawPill(_ f: HUDFrame) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.scale(by: f.pillScale)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()
        let rect = NSRect(x: 30, y: center.y - f.pillHeight / 2, width: 560, height: f.pillHeight)
        let pill = NSBezierPath(roundedRect: rect, xRadius: f.cornerRadius, yRadius: f.cornerRadius)
        NSColor(rgb: 0x312F30, alpha: f.pillOpacity).setFill()
        pill.fill()
        pill.addClip()
        if preferences.ripplesEnabled && f.rippleOpacity > 0 {
            let progress = snapshot.externalPower ? f.rippleProgress : 1 - f.rippleProgress
            let origin = NSPoint(x: center.x + f.boltX, y: center.y + 16 * (1 - f.rippleProgress))
            for (radius, thickness) in [(80.0, 0.0), (110.0, 5.0), (140.0, 3.5)] {
                let r = max(0.5, radius * progress * 3.0)
                let circle = NSBezierPath(ovalIn: NSRect(x: origin.x - r, y: origin.y - r, width: r * 2, height: r * 2))
                NSColor(rgb: 0x656363, alpha: f.rippleOpacity * (thickness == 0 ? 0.6 : 0.8)).set()
                if thickness == 0 { circle.fill() }
                else { circle.lineWidth = thickness; circle.stroke() }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBolt(_ f: HUDFrame) {
        guard f.boltOpacity > 0 else { return }
        let mix = f.squareMix
        let size = (32 - 14 * mix) * f.boltScale
        let x = center.x + f.boltX
        let rect = NSRect(x: x - size / 2, y: center.y - size / 2, width: size, height: size)
        plate.withAlphaComponent(f.boltOpacity).setFill()
        let radius = (16 - 11.5 * mix) * f.boltScale
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let glyphSize = (18 - 6 * mix) * f.boltScale
        Self.boltPath(in: NSRect(x: x - glyphSize / 2, y: center.y - glyphSize / 2,
                                width: glyphSize, height: glyphSize)).fill(with: NSColor(rgb: 0x141313, alpha: f.boltOpacity))
    }

    static func boltPath(in rect: NSRect) -> NSBezierPath {
        // Geo.Bolt from QinAnze/zmd-charge, Styles/Geometries.axaml (MIT).
        let path = NSBezierPath()
        for points in [[(13.0, 2.0), (4, 13), (12, 13), (18, 2)],
                       [(13.0, 11.0), (20, 11), (13, 22), (4, 22)]] {
            for (i, point) in points.enumerated() {
                let p = NSPoint(x: rect.minX + point.0 / 24 * rect.width,
                                y: rect.minY + point.1 / 24 * rect.height)
                if i == 0 { path.move(to: p) } else { path.line(to: p) }
            }
            path.close()
        }
        return path
    }

    private var titles: (String, String) {
        switch kind {
        case .lowBattery: return ("/// LOW POWER RESERVE", chinese ? "能源储备不足" : "LOW BATTERY")
        case .fullyCharged: return ("/// CHARGE COMPLETE", chinese ? "充能完成" : "CHARGE COMPLETE")
        case .lowPowerEnabled: return ("/// ENERGY SAVING MODE", chinese ? "节能模式" : "ENERGY SAVING")
        case .lowPowerDisabled: return ("/// STANDARD POWER MODE", chinese ? "标准供能模式" : "STANDARD POWER")
        case .power:
            if !snapshot.hasBattery { return ("/// POWER SOURCE", chinese ? "未检测到电池" : "NO BATTERY") }
            if snapshot.isCharged { return ("/// CHARGE COMPLETE", chinese ? "充能完成" : "CHARGE COMPLETE") }
            if snapshot.externalPower {
                return snapshot.isCharging
                    ? ("/// SUPER CHARGE MODE", chinese ? "超充模式" : "SUPER CHARGE MODE")
                    : ("/// EXTERNAL POWER MODE", chinese ? "外部供电模式" : "EXTERNAL POWER")
            }
            return ("/// BATTERY MODE", chinese ? "电池模式" : "BATTERY MODE")
        }
    }

    private func drawTitle(_ f: HUDFrame) {
        guard f.titleOpacity > 0 else { return }
        drawText(titles.0, at: NSPoint(x: center.x, y: 45), size: 9, alpha: f.titleOpacity * 0.4,
                 centered: true, spacing: 2)
        drawText(titles.1, at: NSPoint(x: center.x, y: 62), size: 26, alpha: f.titleOpacity,
                 weight: .bold, centered: true, spacing: 2)
    }

    private func drawNumbers(_ f: HUDFrame) {
        guard f.numbersOpacity > 0 else { return }
        let alpha = f.numbersOpacity
        let current = snapshot.energyWh.map { String(format: "≈%.1f", $0) } ?? "—"
        let full = snapshot.fullEnergyWh.map { String(format: "/%.1f", $0) } ?? "/—"
        let currentWidth = drawText(current, at: NSPoint(x: 94, y: 56), size: 26, alpha: alpha)
        let fullWidth = drawText(full, at: NSPoint(x: 98 + currentWidth, y: 64), size: 14, alpha: alpha * 0.55)
        drawText("Wh", at: NSPoint(x: 103 + currentWidth + fullWidth, y: 67), size: 10, alpha: alpha * 0.4)
        let percentage = snapshot.percent.map(String.init) ?? "—"
        let numberWidth = textWidth(percentage, size: 22)
        drawText(percentage, at: NSPoint(x: 491 - numberWidth, y: 59), size: 22, alpha: alpha)
        drawText("%", at: NSPoint(x: 493, y: 65), size: 13, alpha: alpha * 0.55)
        let badgeCenter = NSPoint(x: 562, y: 72)
        NSColor(rgb: 0x262425, alpha: alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: 539, y: 49, width: 46, height: 46)).fill()
        let accent = NSColor(rgb: (snapshot.percent ?? 100) < 20 ? 0xFF4D4F : 0xC6CA4C, alpha: alpha)
        if let percent = snapshot.percent, percent > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: badgeCenter, radius: 20.75, startAngle: -90,
                          endAngle: -90 + CGFloat(percent) * 3.6, clockwise: false)
            accent.setStroke()
            arc.lineWidth = 4.5
            arc.lineCapStyle = .round
            arc.stroke()
        }
        let laptop = NSBezierPath(roundedRect: NSRect(x: 553.5, y: 63.5, width: 17, height: 11.5), xRadius: 1.5, yRadius: 1.5)
        accent.setStroke()
        laptop.lineWidth = 2
        laptop.stroke()
        accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: 550, y: 77.5, width: 24, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
        NSBezierPath(roundedRect: NSRect(x: 557.5, y: 63.5, width: 9, height: 3), xRadius: 1, yRadius: 1).fill()
    }

    private func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)]).width
    }

    @discardableResult private func drawText(_ text: String, at point: NSPoint, size: CGFloat,
        alpha: Double, weight: NSFont.Weight = .medium, centered: Bool = false, spacing: CGFloat = 0) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: white.withAlphaComponent(alpha), .kern: spacing
        ]
        let width = (text as NSString).size(withAttributes: attributes).width
        (text as NSString).draw(at: NSPoint(x: centered ? point.x - width / 2 : point.x, y: point.y), withAttributes: attributes)
        return width
    }

    func writePNG(to url: URL) throws {
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else {
            throw NSError(domain: "EndfieldCharge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create HUD bitmap"])
        }
        cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "EndfieldCharge", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot encode HUD bitmap"])
        }
        try png.write(to: url)
    }
}

private extension NSBezierPath {
    func fill(with color: NSColor) { color.setFill(); fill() }
}
