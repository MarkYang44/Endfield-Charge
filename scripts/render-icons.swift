#!/usr/bin/env swift
// Developer-only artwork exporter. Run from the repository root:
// swift scripts/render-icons.swift
import AppKit

// Top-left coordinates throughout, shared by native PNG and SVG exports.
enum Command {
    case move(CGPoint), line(CGPoint), curve(CGPoint, CGPoint, CGPoint), close
}
struct VectorPath {
    let commands: [Command]
    func transformed(scale: CGFloat, offset: CGPoint) -> VectorPath {
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * scale + offset.x, y: p.y * scale + offset.y)
        }
        return VectorPath(commands: commands.map {
            switch $0 {
            case .move(let p): return .move(point(p))
            case .line(let p): return .line(point(p))
            case .curve(let a, let b, let p): return .curve(point(a), point(b), point(p))
            case .close: return .close
            }
        })
    }
    var native: NSBezierPath {
        let path = NSBezierPath()
        for command in commands {
            switch command {
            case .move(let p): path.move(to: p)
            case .line(let p): path.line(to: p)
            case .curve(let a, let b, let p): path.curve(to: p, controlPoint1: a, controlPoint2: b)
            case .close: path.close()
            }
        }
        return path
    }
    var svg: String {
        func number(_ n: CGFloat) -> String { String(format: "%.3f", Double(n)) }
        func point(_ p: CGPoint) -> String { "\(number(p.x)) \(number(p.y))" }
        return commands.map {
            switch $0 {
            case .move(let p): return "M\(point(p))"
            case .line(let p): return "L\(point(p))"
            case .curve(let a, let b, let p): return "C\(point(a)) \(point(b)) \(point(p))"
            case .close: return "Z"
            }
        }.joined(separator: " ")
    }
}
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
func polygon(_ points: [CGPoint]) -> VectorPath {
    VectorPath(commands: [.move(points[0])] + points.dropFirst().map(Command.line) + [.close])
}
func roundedSquare() -> VectorPath {
    let lo: CGFloat = 64, hi: CGFloat = 960, r: CGFloat = 194
    let k = r * 0.5522847498307936
    return VectorPath(commands: [
        .move(p(lo + r, lo)), .line(p(hi - r, lo)),
        .curve(p(hi - r + k, lo), p(hi, lo + r - k), p(hi, lo + r)),
        .line(p(hi, hi - r)), .curve(p(hi, hi - r + k), p(hi - r + k, hi), p(hi - r, hi)),
        .line(p(lo + r, hi)), .curve(p(lo + r - k, hi), p(lo, hi - r + k), p(lo, hi - r)),
        .line(p(lo, lo + r)), .curve(p(lo, lo + r - k), p(lo + r - k, lo), p(lo + r, lo)), .close
    ])
}

// A simplified Endfield silhouette: gaps replace the original wordmark band.
let triangle = VectorPath(commands: [
    .move(p(265, 236)), .line(p(185, 236)), .line(p(307, 451)),
    .move(p(345, 236)), .line(p(839, 236)), .line(p(717, 451)),
    .move(p(372, 564)), .line(p(512, 810)), .line(p(652, 564))
])
// Thirteen terrain contours flow in two groups inside the triangle silhouette.
// Control points also stay inside it, keeping the cubic curves bounded.
let contours = [
    VectorPath(commands: [.move(p(246, 278)),
        .curve(p(275, 318), p(313, 344), p(319, 383)),
        .curve(p(325, 423), p(349, 435), p(365, 477)),
        .curve(p(380, 518), p(384, 555), p(436, 619))]),
    VectorPath(commands: [.move(p(270, 275)),
        .curve(p(289, 306), p(338, 326), p(338, 373)),
        .curve(p(338, 411), p(364, 426), p(382, 471)),
        .curve(p(403, 514), p(410, 568), p(460, 639))]),
    VectorPath(commands: [.move(p(294, 274)),
        .curve(p(314, 303), p(359, 311), p(358, 360)),
        .curve(p(357, 405), p(383, 415), p(399, 461)),
        .curve(p(415, 507), p(430, 568), p(481, 654))]),
    VectorPath(commands: [.move(p(319, 273)),
        .curve(p(335, 293), p(381, 302), p(379, 350)),
        .curve(p(377, 390), p(400, 416), p(418, 456)),
        .curve(p(437, 498), p(445, 560), p(497, 662))]),
    VectorPath(commands: [.move(p(343, 273)),
        .curve(p(362, 290), p(400, 300), p(400, 337)),
        .curve(p(399, 381), p(417, 404), p(438, 449)),
        .curve(p(457, 491), p(470, 562), p(516, 655))]),
    VectorPath(commands: [.move(p(367, 274)),
        .curve(p(387, 290), p(421, 296), p(420, 329)),
        .curve(p(419, 373), p(438, 397), p(456, 436)),
        .curve(p(478, 482), p(491, 554), p(535, 632))]),
    VectorPath(commands: [.move(p(765, 280)),
        .curve(p(709, 252), p(650, 263), p(637, 299)),
        .curve(p(625, 336), p(678, 353), p(692, 379)),
        .curve(p(709, 414), p(669, 452), p(656, 488)),
        .curve(p(644, 523), p(635, 548), p(618, 591))]),
    VectorPath(commands: [.move(p(753, 303)),
        .curve(p(705, 275), p(665, 283), p(660, 309)),
        .curve(p(654, 336), p(702, 345), p(713, 376)),
        .curve(p(723, 407), p(691, 441), p(675, 478))]),
    VectorPath(commands: [.move(p(741, 326)),
        .curve(p(708, 300), p(681, 305), p(681, 321)),
        .curve(p(681, 339), p(727, 349), p(730, 376)),
        .curve(p(733, 400), p(714, 423), p(698, 446))]),
    VectorPath(commands: [.move(p(620, 276)),
        .curve(p(594, 317), p(623, 348), p(654, 371)),
        .curve(p(686, 397), p(647, 433), p(640, 477)),
        .curve(p(634, 525), p(613, 567), p(604, 614))]),
    VectorPath(commands: [.move(p(598, 275)),
        .curve(p(570, 319), p(593, 351), p(625, 379)),
        .curve(p(660, 410), p(628, 443), p(620, 488)),
        .curve(p(610, 537), p(594, 582), p(580, 647))]),
    VectorPath(commands: [.move(p(575, 275)),
        .curve(p(548, 318), p(567, 358), p(596, 388)),
        .curve(p(629, 422), p(606, 450), p(599, 495)),
        .curve(p(592, 543), p(569, 592), p(555, 671))]),
    VectorPath(commands: [.move(p(552, 275)),
        .curve(p(527, 316), p(542, 360), p(569, 395)),
        .curve(p(594, 428), p(586, 457), p(579, 501)),
        .curve(p(570, 550), p(548, 600), p(533, 690))])
]
// Exact Geo.Bolt points from HUDView.boltPath, QinAnze/zmd-charge (MIT).
let boltPolygons = [
    [p(13, 2), p(4, 13), p(12, 13), p(18, 2)],
    [p(13, 11), p(20, 11), p(13, 22), p(4, 22)]
].map { polygon($0).transformed(scale: 340 / 24, offset: p(342, 260)) }

// Exact glyph outlines from the first five children of g#svg-def-game-logo
// and its I rectangle in Resources/endfield-industries.svg. Relative SVG and
// smooth cubic commands are expanded to absolute commands, preserving winding.
let endfieldWordmark = [
    // Original wordmark child 1.
    VectorPath(commands: [
        .move(p(104.5, 239.2)),
        .line(p(104.5, 279.9)),
        .line(p(83.2, 279.9)),
        .line(p(83.2, 203)),
        .line(p(104.9, 203)),
        .line(p(134.1, 243.1)),
        .line(p(134.5, 243)),
        .line(p(134.5, 203)),
        .line(p(136.1, 203)),
        .curve(p(147.7, 203), p(159.3, 202.9), p(170.9, 203)),
        .curve(p(182.5, 203.1), p(192.4, 207.1), p(200.4, 215.5)),
        .curve(p(206.4, 221.7), p(209.5, 229.3), p(210.3, 237.9)),
        .curve(p(211.1, 246.5), p(209.9, 253), p(206.1, 259.9)),
        .curve(p(200.8, 270), p(192.2, 275.9), p(181.2, 278.6)),
        .curve(p(177.7, 279.4), p(174.2, 279.9), p(170.6, 279.9)),
        .curve(p(158.9, 280), p(147.1, 280), p(135.4, 280)),
        .line(p(134, 280)),
        .line(p(104.8, 239)),
        .line(p(104.5, 239.2)),
        .move(p(156.5, 260.3)),
        .curve(p(162.4, 260.1), p(168.1, 260.7), p(173.9, 259.7)),
        .curve(p(183, 258.1), p(188.1, 252.7), p(188.9, 243.5)),
        .curve(p(189.5, 236.8), p(187.6, 231), p(182, 226.8)),
        .curve(p(179, 224.5), p(175.3, 223.1), p(171.5, 222.9)),
        .curve(p(166.8, 222.6), p(162.2, 222.8), p(157.6, 222.7)),
        .line(p(156.6, 222.9)),
        .line(p(156.5, 260.3)),
        .close
    ]),
    // Original wordmark child 2.
    VectorPath(commands: [
        .move(p(364.4, 280)),
        .line(p(364.4, 203.1)),
        .line(p(385.6, 203.1)),
        .line(p(385.6, 260.2)),
        .line(p(416.2, 260.2)),
        .line(p(416.2, 203)),
        .line(p(418, 203)),
        .curve(p(429.4, 203), p(440.8, 202.9), p(452.1, 203)),
        .curve(p(463.5, 203.1), p(474.3, 207.3), p(482.3, 216.2)),
        .curve(p(488.3, 222.9), p(491.3, 230.8), p(491.7, 239.7)),
        .curve(p(492.1, 246.3), p(490.8, 253), p(488, 259)),
        .curve(p(482.7, 269.5), p(473.9, 275.8), p(462.6, 278.7)),
        .curve(p(459.1, 279.6), p(455.6, 280), p(452, 280)),
        .curve(p(423.3, 280.1), p(394.5, 280.1), p(365.8, 280.1)),
        .line(p(364.3, 280.1)),
        .move(p(437.9, 260.5)),
        .line(p(446.6, 260.5)),
        .curve(p(449.6, 260.5), p(452.6, 260.2), p(455.5, 259.8)),
        .curve(p(462.6, 258.4), p(467.9, 254.6), p(469.7, 247.2)),
        .curve(p(470.2, 245), p(470.4, 242.8), p(470.2, 240.5)),
        .curve(p(469.9, 233.3), p(466.4, 228.1), p(459.9, 225)),
        .curve(p(457.5, 223.8), p(454.8, 223.1), p(452, 223.1)),
        .curve(p(447.7, 223), p(443.5, 223), p(439.2, 223)),
        .line(p(437.9, 223.2)),
        .line(p(437.9, 260.5)),
        .close
    ]),
    // Original wordmark child 3.
    VectorPath(commands: [
        .move(p(42, 222.8)),
        .curve(p(42, 223.5), p(41.9, 224.1), p(41.9, 224.7)),
        .line(p(41.9, 232.5)),
        .line(p(68.1, 232.5)),
        .line(p(68.1, 250.4)),
        .line(p(42.1, 250.4)),
        .line(p(42.1, 260.3)),
        .line(p(78.8, 260.3)),
        .line(p(78.8, 280)),
        .line(p(20.6, 280)),
        .line(p(20.6, 203.1)),
        .line(p(78.1, 203.1)),
        .line(p(78.1, 222.8)),
        .line(p(42, 222.8)),
        .close
    ]),
    // Original wordmark child 4.
    VectorPath(commands: [
        .move(p(301.7, 279.9)),
        .line(p(301.7, 203)),
        .line(p(359.3, 203)),
        .line(p(359.3, 222.7)),
        .line(p(323.3, 222.7)),
        .line(p(323.3, 232.4)),
        .line(p(349.2, 232.4)),
        .line(p(349.2, 250.3)),
        .line(p(323.3, 250.3)),
        .line(p(323.3, 260.3)),
        .line(p(360, 260.3)),
        .line(p(360, 279.9)),
        .close
    ]),
    // Original wordmark child 5.
    VectorPath(commands: [
        .move(p(271.2, 222.8)),
        .line(p(236.2, 222.8)),
        .line(p(236.2, 234)),
        .line(p(263.1, 234)),
        .line(p(263.1, 253.9)),
        .line(p(236.1, 253.9)),
        .line(p(236.1, 280)),
        .line(p(214.8, 280)),
        .line(p(214.8, 203.1)),
        .line(p(271.2, 203.1)),
        .close
    ]),
    // Original I rectangle: x=275, y=203.1, width=21.2, height=76.9.
    polygon([p(275, 203.1), p(296.2, 203.1), p(296.2, 280), p(275, 280)])
]

struct Shape {
    let path: VectorPath
    let color: UInt32
    var width: CGFloat = 0
    var opacity: CGFloat = 1
    var nativeColor: NSColor {
        NSColor(srgbRed: CGFloat((color >> 16) & 255) / 255,
                green: CGFloat((color >> 8) & 255) / 255,
                blue: CGFloat(color & 255) / 255, alpha: opacity)
    }
    var svg: String {
        let paint = String(format: "#%06X", color)
        let style = width == 0 ? "fill=\"\(paint)\"" :
            "fill=\"none\" stroke=\"\(paint)\" stroke-width=\"\(width)\" stroke-linecap=\"butt\" stroke-linejoin=\"miter\""
        return "  <path d=\"\(path.svg)\" \(style) opacity=\"\(opacity)\"/>"
    }
}
// App-only layout leaves a clear band below the triangle for the original logo.
// The menu artwork continues to use the unmodified triangle and Geo.Bolt above.
let appScale: CGFloat = 0.95
let appOffset = p(25.6, -60)
let appShapes = [Shape(path: roundedSquare(), color: 0x262425),
                 Shape(path: triangle.transformed(scale: appScale, offset: appOffset),
                       color: 0xE9E7E4, width: 26 * appScale)] +
    contours.map { Shape(path: $0.transformed(scale: appScale, offset: appOffset),
                         color: 0xE9E7E4, width: 6.5 * appScale, opacity: 0.36) } +
    boltPolygons.map { Shape(path: $0.transformed(scale: appScale, offset: appOffset), color: 0xC6CA4C) } +
    endfieldWordmark.map { Shape(path: $0.transformed(scale: 1.4, offset: p(153.8, 490.8)), color: 0xE9E7E4) }
let menuScale: CGFloat = 1.22
let menuOffset = p(512 * (1 - menuScale), 512 * (1 - menuScale))
let menuShapes = [Shape(path: triangle.transformed(scale: menuScale, offset: menuOffset),
                        color: 0, width: 54)] +
    boltPolygons.map { Shape(path: $0.transformed(scale: menuScale, offset: menuOffset), color: 0) }

func draw(_ shapes: [Shape], in rect: CGRect, tint: NSColor? = nil) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: rect.minX, yBy: rect.minY)
    transform.scaleX(by: rect.width / 1024, yBy: rect.height / 1024)
    transform.concat()
    for shape in shapes {
        let path = shape.path.native
        (tint ?? shape.nativeColor).set()
        if shape.width == 0 { path.fill() }
        else {
            path.lineWidth = shape.width
            path.lineCapStyle = .butt
            path.lineJoinStyle = .miter
            path.stroke()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
}
func bitmap(width: Int, height: Int, drawing: () -> Void) -> NSBitmapImageRep {
    // Explicit sRGB keeps the approved hex palette identical in SVG and PNG.
    let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let context = NSGraphicsContext(cgContext: canvas, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true
    context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.cgContext.translateBy(x: 0, y: CGFloat(height))
    context.cgContext.scaleBy(x: 1, y: -1)
    drawing()
    NSGraphicsContext.restoreGraphicsState()
    return NSBitmapImageRep(cgImage: canvas.makeImage()!)
}
func writePNG(_ image: NSBitmapImageRep, _ path: String) throws {
    try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func export(_ shapes: [Shape], size: Int, name: String) throws {
    try writePNG(bitmap(width: size, height: size) {
        draw(shapes, in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
    }, "Resources/\(name).png")
}
func exportSVG(_ shapes: [Shape], name: String) throws {
    let svg = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
    \(shapes.map(\.svg).joined(separator: "\n"))
    </svg>

    """
    try svg.write(toFile: "Resources/\(name).svg", atomically: true, encoding: .utf8)
}
func label(_ text: String, at point: CGPoint, size: CGFloat = 18, color: NSColor = .white) {
    // NSString text uses the flipped context explicitly, keeping preview labels upright.
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color
    ]
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: point.x, yBy: point.y)
    transform.scaleX(by: 1, yBy: -1)
    transform.concat()
    (text as NSString).draw(at: p(0, -size * 1.25), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
}

try export(appShapes, size: 1024, name: "AppIcon")
try export(menuShapes, size: 144, name: "MenuBarIcon")
try exportSVG(appShapes, name: "ChargeIcon")
try exportSVG(menuShapes, name: "ChargeMenuIcon")
// Preview the exported raster bytes at native sizes, matching packaged resizing.
let appRaster = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: "Resources/AppIcon.png")))!.cgImage!
let menuRaster = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: "Resources/MenuBarIcon.png")))!.cgImage!
func drawRaster(_ image: CGImage, in rect: CGRect, tint: NSColor? = nil) {
    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    let localRect = CGRect(origin: .zero, size: rect.size)
    if let tint = tint {
        context.clip(to: localRect, mask: image)
        context.setFillColor(tint.cgColor)
        context.fill(localRect)
    } else {
        context.draw(image, in: localRect)
    }
    context.restoreGState()
}
try FileManager.default.createDirectory(atPath: "docs/images", withIntermediateDirectories: true)
let preview = bitmap(width: 1440, height: 1040) {
    NSColor(srgbRed: 0.10, green: 0.11, blue: 0.12, alpha: 1).setFill()
    CGRect(x: 0, y: 0, width: 1440, height: 1040).fill()
    label("ENDFIELD CHARGE / ICON ARTWORK", at: p(64, 40), size: 26)
    label("App icon", at: p(64, 104))
    draw(appShapes, in: CGRect(x: 64, y: 140, width: 480, height: 480))
    for (y, background, tint, title) in [
        (CGFloat(150), NSColor(srgbRed: 0.94, green: 0.94, blue: 0.94, alpha: 1), NSColor.black, "Template / light menu bar"),
        (CGFloat(385), NSColor(srgbRed: 0.19, green: 0.20, blue: 0.21, alpha: 1), NSColor.white, "Template / dark menu bar")
    ] {
        label(title, at: p(640, y - 38))
        background.setFill()
        NSBezierPath(roundedRect: CGRect(x: 624, y: y, width: 752, height: 192), xRadius: 20, yRadius: 20).fill()
        var x: CGFloat = 652
        for size in [16, 18, 32, 64, 128] {
            drawRaster(menuRaster, in: CGRect(x: x, y: y + 20, width: CGFloat(size), height: CGFloat(size)), tint: tint)
            label("\(size) pt", at: p(x, y + 154), size: 14, color: tint)
            x += CGFloat(size) + 68
        }
    }
    label("App icon / native sizes", at: p(64, 674))
    var x: CGFloat = 72
    for size in [16, 18, 32, 64, 128, 256] {
        drawRaster(appRaster, in: CGRect(x: x, y: 725, width: CGFloat(size), height: CGFloat(size)))
        label("\(size) pt", at: p(x, 990), size: 16)
        x += CGFloat(size) + 80
    }
}
try writePNG(preview, "docs/images/charge-icon-preview.png")
print("Exported AppIcon.png (1024×1024), MenuBarIcon.png (144×144), two SVGs and preview.")
