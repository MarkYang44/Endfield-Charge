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
let contours = [
    VectorPath(commands: [.move(p(268, 299)),
        .curve(p(291, 341), p(338, 365), p(338, 405)),
        .curve(p(338, 440), p(350, 466), p(365, 482))]),
    VectorPath(commands: [.move(p(753, 300)),
        .curve(p(693, 264), p(635, 276), p(638, 321)),
        .curve(p(641, 370), p(723, 345), p(710, 402))]),
    VectorPath(commands: [.move(p(732, 328)),
        .curve(p(690, 301), p(660, 307), p(664, 333)),
        .curve(p(668, 356), p(733, 362), p(688, 429))])
]
// Exact Geo.Bolt points from HUDView.boltPath, QinAnze/zmd-charge (MIT).
let boltPolygons = [
    [p(13, 2), p(4, 13), p(12, 13), p(18, 2)],
    [p(13, 11), p(20, 11), p(13, 22), p(4, 22)]
].map { polygon($0).transformed(scale: 340 / 24, offset: p(342, 260)) }

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
let appShapes = [Shape(path: roundedSquare(), color: 0x262425),
                 Shape(path: triangle, color: 0xE9E7E4, width: 26)] +
    contours.map { Shape(path: $0, color: 0xE9E7E4, width: 10, opacity: 0.46) } +
    boltPolygons.map { Shape(path: $0, color: 0xC6CA4C) }
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
