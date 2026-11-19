// Draws Hum's app icon in code and builds Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift                         the chosen design
//   swift scripts/make-icon.swift --design disc           another candidate
//   swift scripts/make-icon.swift --contact-sheet FILE    every candidate side by side
//   swift scripts/make-icon.swift --out FILE.icns         somewhere other than Resources
//
// Every size is drawn from the vectors, not scaled down from 1024. The chosen
// design, vibrato, is Hum's mark from design/logo, built the way Pulse's and
// Tuck's icons are: an 824-px body with corner radius 186 centered on the
// 1024-px macOS grid, one flat color, a soft shadow, and the symbol as one
// round-capped line. At 32 px and below it switches to the mark's small-size
// cut. The earlier candidates stay below for comparison. Their bodies have
// continuous corners and are lit from above, and their strokes thicken at the
// smallest sizes.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: Geometry

/// The 1024-px design canvas. Everything below is drawn in these units.
let canvas: CGFloat = 1024
/// The icon body: 824 px square, 100 px in from every edge.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)

/// A rounded rectangle whose corners ease into the straight edges with no jump
/// in curvature, the way Apple's continuous corners do.
///
/// Each corner is a superellipse quadrant spanning `extent` along both edges.
/// With an exponent above 2 the curvature falls to zero where it meets the edge,
/// so the outline never shows the kink a circular arc leaves.
func continuousRect(_ rect: CGRect, extent: CGFloat, exponent: CGFloat = 3.26) -> CGPath {
    let path = CGMutablePath()
    let e = min(extent, rect.width / 2, rect.height / 2)
    let steps = 48
    // Corner centers, walked counterclockwise starting at the bottom right.
    let corners: [(center: CGPoint, start: CGFloat)] = [
        (CGPoint(x: rect.maxX - e, y: rect.minY + e), -.pi / 2),
        (CGPoint(x: rect.maxX - e, y: rect.maxY - e), 0),
        (CGPoint(x: rect.minX + e, y: rect.maxY - e), .pi / 2),
        (CGPoint(x: rect.minX + e, y: rect.minY + e), .pi),
    ]
    path.move(to: CGPoint(x: rect.minX + e, y: rect.minY))
    for corner in corners {
        for step in 0...steps {
            let angle = corner.start + CGFloat(step) / CGFloat(steps) * (.pi / 2)
            let c = cos(angle), s = sin(angle)
            let x = copysign(pow(abs(c), 2 / exponent), c) * e
            let y = copysign(pow(abs(s), 2 / exponent), s) * e
            path.addLine(to: CGPoint(x: corner.center.x + x, y: corner.center.y + y))
        }
    }
    path.closeSubpath()
    return path
}

/// The body outline. The corner extent matches the macOS grid's roughly 185-px
/// radius at the diagonal.
let bodyPath = continuousRect(body, extent: 0.3435 * body.width)

// MARK: Color

struct RGB {
    var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1

    init(_ hex: UInt32, alpha: CGFloat = 1) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
        a = alpha
    }

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func gradient(_ stops: [(RGB, CGFloat)]) -> CGGradient {
    CGGradient(
        colorsSpace: sRGB,
        colors: stops.map(\.0.cgColor) as CFArray,
        locations: stops.map(\.1)
    )!
}

// MARK: Drawing helpers

/// What every design shares: the drop shadow, the body's top-lit gradient, and
/// a faint light edge along the top, like light catching a rounded rim.
func drawBody(in context: CGContext, fill: CGGradient, scale: CGFloat) {
    // Two shadows, a tight contact one and a soft ambient one, both straight
    // down and well inside the canvas.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 28 * scale, color: RGB(0x000000, alpha: 0.30).cgColor)
    context.addPath(bodyPath)
    context.setFillColor(RGB(0x000000).cgColor)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -2 * scale), blur: 4 * scale, color: RGB(0x000000, alpha: 0.22).cgColor)
    context.addPath(bodyPath)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    context.drawLinearGradient(fill, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    // The rim: a thin light stroke that is strongest at the top and gone by
    // the middle.
    context.addPath(bodyPath)
    context.setLineWidth(5)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        gradient([(RGB(0xFFFFFF, alpha: 0.38), 0), (RGB(0xFFFFFF, alpha: 0), 0.5)]),
        start: CGPoint(x: 0, y: body.maxY),
        end: CGPoint(x: 0, y: body.minY),
        options: []
    )
    context.restoreGState()
}

/// How much heavier strokes get at small pixel sizes, so they keep about the
/// same visual weight a person sees at 1024.
func strokeBoost(pixels: Int) -> CGFloat {
    switch pixels {
    case ...16: 2.0
    case ...32: 1.55
    case ...64: 1.2
    default: 1
    }
}

/// A sustained tone: a sine whose swing is widest in the middle and narrows
/// to nothing at both ends, so it reads as one sound rather than a signal.
func wavePath(width: CGFloat, amplitude: CGFloat, cycles: CGFloat, center: CGPoint) -> CGPath {
    let path = CGMutablePath()
    let steps = 400
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps)
        // A half-sine envelope: zero at the ends, one in the middle, with no
        // flat stretch at either end.
        let envelope = sin(.pi * t)
        let x = center.x - width / 2 + t * width
        let y = center.y + amplitude * envelope * sin(2 * .pi * cycles * t)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    return path
}

/// Strokes the tone with a gradient. The stroke is drawn into its own layer and
/// the gradient laid over it, so the round caps blend into the line without a
/// seam, and the layer casts one shadow.
func strokeWave(in context: CGContext, pixels: Int, fill: CGGradient, from start: CGPoint, to end: CGPoint, shadow: RGB?) {
    let scale = CGFloat(pixels) / canvas
    let wave = wavePath(width: 620, amplitude: 150, cycles: 2, center: CGPoint(x: 512, y: 512))
    context.saveGState()
    if let shadow {
        context.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: 22 * scale, color: shadow.cgColor)
    }
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.addPath(wave)
    context.setLineWidth(46 * strokeBoost(pixels: pixels))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(RGB(0xFFFFFF).cgColor)
    context.strokePath()
    context.setBlendMode(.sourceAtop)
    context.drawLinearGradient(fill, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.endTransparencyLayer()
    context.restoreGState()
}

/// Hum's mark, Vibrato: a flat line that breaks into two even ripples and
/// settles, a sustained hum. It's drawn on the same 256-unit grid as the SVG
/// masters in design/logo (y down), as one 24-unit line with round caps and
/// joins.
func vibratoPath(small: Bool) -> CGPath {
    let path = CGMutablePath()
    if small {
        // The small-size cut: shorter tails and taller ripples (stroke 32).
        path.move(to: CGPoint(x: 40, y: 128))
        path.addLine(to: CGPoint(x: 58, y: 128))
        path.addCurve(to: CGPoint(x: 86, y: 96), control1: CGPoint(x: 72, y: 128), control2: CGPoint(x: 72, y: 96))
        path.addCurve(to: CGPoint(x: 114, y: 160), control1: CGPoint(x: 96, y: 96), control2: CGPoint(x: 104, y: 160))
        path.addCurve(to: CGPoint(x: 142, y: 96), control1: CGPoint(x: 124, y: 160), control2: CGPoint(x: 132, y: 96))
        path.addCurve(to: CGPoint(x: 170, y: 160), control1: CGPoint(x: 152, y: 96), control2: CGPoint(x: 160, y: 160))
        path.addCurve(to: CGPoint(x: 198, y: 128), control1: CGPoint(x: 184, y: 160), control2: CGPoint(x: 184, y: 128))
        path.addLine(to: CGPoint(x: 216, y: 128))
    } else {
        path.move(to: CGPoint(x: 28, y: 126))
        path.addLine(to: CGPoint(x: 48, y: 126))
        path.addCurve(to: CGPoint(x: 80, y: 100), control1: CGPoint(x: 64, y: 126), control2: CGPoint(x: 64, y: 100))
        path.addCurve(to: CGPoint(x: 112, y: 152), control1: CGPoint(x: 92, y: 100), control2: CGPoint(x: 100, y: 152))
        path.addCurve(to: CGPoint(x: 144, y: 100), control1: CGPoint(x: 124, y: 152), control2: CGPoint(x: 132, y: 100))
        path.addCurve(to: CGPoint(x: 176, y: 152), control1: CGPoint(x: 156, y: 100), control2: CGPoint(x: 164, y: 152))
        path.addCurve(to: CGPoint(x: 208, y: 126), control1: CGPoint(x: 192, y: 152), control2: CGPoint(x: 192, y: 126))
        path.addLine(to: CGPoint(x: 228, y: 126))
    }
    return path
}

// MARK: Designs

struct Design {
    let name: String
    let summary: String
    let draw: (CGContext, Int) -> Void
}

let designs: [Design] = [
    Design(name: "vibrato", summary: "Two even ripples in white on Hum Crimson") { context, pixels in
        let scale = CGFloat(pixels) / canvas
        let small = pixels <= 32
        context.saveGState()
        // The mark's grid is y down, like the SVG masters; the context is y up.
        context.translateBy(x: 0, y: canvas)
        context.scaleBy(x: 1, y: -1)
        let flatBody = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
        context.saveGState()
        // Shadows ignore the context's transform, so they're sized in pixels.
        context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale, color: RGB(0x000000, alpha: 0.28).cgColor)
        context.addPath(flatBody)
        context.setFillColor(RGB(0xB81D45).cgColor)
        context.fillPath()
        context.restoreGState()
        // The symbol spans 62 % of the canvas, centered 2 % above the middle.
        // The small-size cut spans 75 %.
        let mark: CGFloat = small ? 3.0 : 2.48
        context.translateBy(x: 512, y: 496)
        context.scaleBy(x: mark, y: mark)
        context.translateBy(x: -128, y: small ? -128 : -126)
        context.addPath(vibratoPath(small: small))
        context.setStrokeColor(RGB(0xFFFFFF).cgColor)
        context.setLineWidth(small ? 32 : 24)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    },
    Design(name: "wave", summary: "A single white tone on indigo") { context, pixels in
        let scale = CGFloat(pixels) / canvas
        drawBody(in: context, fill: gradient([(RGB(0x6C74F5), 0), (RGB(0x4A3FD6), 0.55), (RGB(0x2E2193), 1)]), scale: scale)
        // White, with a whisper of cool tint toward the bottom, as light from above.
        strokeWave(
            in: context,
            pixels: pixels,
            fill: gradient([(RGB(0xFFFFFF), 0), (RGB(0xFFFFFF), 0.45), (RGB(0xE2E3FF), 1)]),
            from: CGPoint(x: 0, y: 680),
            to: CGPoint(x: 0, y: 344),
            shadow: RGB(0x120A4A, alpha: 0.45)
        )
    },
    Design(name: "wave-night", summary: "The same tone in color on graphite") { context, pixels in
        let scale = CGFloat(pixels) / canvas
        drawBody(in: context, fill: gradient([(RGB(0x3A3A40), 0), (RGB(0x1C1C21), 0.6), (RGB(0x0E0E12), 1)]), scale: scale)
        strokeWave(
            in: context,
            pixels: pixels,
            fill: gradient([(RGB(0x5AC8FA), 0), (RGB(0x7D6BFF), 0.5), (RGB(0xFF5FA2), 1)]),
            from: CGPoint(x: 202, y: 0),
            to: CGPoint(x: 822, y: 0),
            shadow: nil
        )
    },
    Design(name: "disc", summary: "A record seen from above, on deep teal") { context, pixels in
        let scale = CGFloat(pixels) / canvas
        drawBody(in: context, fill: gradient([(RGB(0x2FB6C9), 0), (RGB(0x1A7F9E), 0.55), (RGB(0x0F4C6E), 1)]), scale: scale)
        let center = CGPoint(x: 512, y: 512)
        let radius: CGFloat = 300
        let disc = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 30 * scale, color: RGB(0x00141F, alpha: 0.5).cgColor)
        context.addPath(disc)
        context.setFillColor(RGB(0x16181C).cgColor)
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(disc)
        context.clip()
        // Grooves: faint rings, too fine to count, skipped at small sizes.
        if pixels >= 128 {
            var r: CGFloat = 130
            var lighter = true
            while r < radius - 10 {
                context.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                context.setStrokeColor(RGB(0xFFFFFF, alpha: lighter ? 0.05 : 0.02).cgColor)
                context.setLineWidth(3)
                context.strokePath()
                r += 9
                lighter.toggle()
            }
        }
        // The sheen: two opposite soft wedges of light.
        for start in [CGFloat.pi * 0.15, CGFloat.pi * 1.15] {
            let wedge = CGMutablePath()
            wedge.move(to: center)
            wedge.addArc(center: center, radius: radius, startAngle: start, endAngle: start + .pi * 0.22, clockwise: false)
            wedge.closeSubpath()
            context.addPath(wedge)
            context.setFillColor(RGB(0xFFFFFF, alpha: 0.07).cgColor)
            context.fillPath()
        }
        context.restoreGState()
        // The label and the spindle hole.
        let label: CGFloat = 104
        context.saveGState()
        context.addEllipse(in: CGRect(x: center.x - label, y: center.y - label, width: label * 2, height: label * 2))
        context.clip()
        context.drawLinearGradient(gradient([(RGB(0xFFD27A), 0), (RGB(0xFF9F43), 1)]), start: CGPoint(x: 0, y: center.y + label), end: CGPoint(x: 0, y: center.y - label), options: [])
        context.restoreGState()
        let hole: CGFloat = 14 * max(1, strokeBoost(pixels: pixels))
        context.addEllipse(in: CGRect(x: center.x - hole, y: center.y - hole, width: hole * 2, height: hole * 2))
        context.setFillColor(RGB(0x16181C).cgColor)
        context.fillPath()
    },
    Design(name: "tile", summary: "The player itself: a square of art with a line of progress") { context, pixels in
        let scale = CGFloat(pixels) / canvas
        drawBody(in: context, fill: gradient([(RGB(0xF4F4F7), 0), (RGB(0xDCDCE2), 1)]), scale: scale)
        let art = CGRect(x: 262, y: 262, width: 500, height: 500)
        let artPath = continuousRect(art, extent: 0.3435 * 0.16 * art.width / 0.225)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 36 * scale, color: RGB(0x000000, alpha: 0.28).cgColor)
        context.addPath(artPath)
        context.setFillColor(RGB(0x000000).cgColor)
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(artPath)
        context.clip()
        context.drawLinearGradient(
            gradient([(RGB(0xFFB15C), 0), (RGB(0xF2557B), 0.5), (RGB(0x5B3FD9), 1)]),
            start: CGPoint(x: art.minX, y: art.maxY),
            end: CGPoint(x: art.maxX, y: art.minY),
            options: []
        )
        // The progress hairline, a third of the way along, near the bottom.
        let lineWidth = 12 * strokeBoost(pixels: pixels)
        let track = CGRect(x: art.minX + 56, y: art.minY + 60, width: art.width - 112, height: lineWidth)
        context.addPath(CGPath(roundedRect: track, cornerWidth: lineWidth / 2, cornerHeight: lineWidth / 2, transform: nil))
        context.setFillColor(RGB(0xFFFFFF, alpha: 0.35).cgColor)
        context.fillPath()
        let played = CGRect(x: track.minX, y: track.minY, width: track.width * 0.38, height: lineWidth)
        context.addPath(CGPath(roundedRect: played, cornerWidth: lineWidth / 2, cornerHeight: lineWidth / 2, transform: nil))
        context.setFillColor(RGB(0xFFFFFF).cgColor)
        context.fillPath()
        context.restoreGState()
    },
]

/// The design that ships. The others stay here to compare against, or to
/// choose instead.
let chosenDesign = "vibrato"

// MARK: Rendering

func render(_ design: Design, pixels: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    let scale = CGFloat(pixels) / canvas
    context.scaleBy(x: scale, y: scale)
    design.draw(context, pixels)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw ScriptError("Couldn't write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ScriptError("Couldn't write \(url.path)")
    }
}

struct ScriptError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// The iconset's file names and the pixel size of each.
let iconsetEntries: [(name: String, pixels: Int)] = [16, 32, 128, 256, 512].flatMap { points in
    [("icon_\(points)x\(points).png", points), ("icon_\(points)x\(points)@2x.png", points * 2)]
}

func buildIcns(_ design: Design, to output: URL) throws {
    let iconset = FileManager.default.temporaryDirectory
        .appendingPathComponent("hum-\(UUID().uuidString).iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconset) }
    for entry in iconsetEntries {
        try writePNG(render(design, pixels: entry.pixels), to: iconset.appendingPathComponent(entry.name))
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        throw ScriptError("iconutil failed with status \(iconutil.terminationStatus)")
    }
}

/// Every candidate at 512, 128, 64, 32, and 16 px, on a light and a dark
/// backdrop, labeled, for choosing between them.
func writeContactSheet(to url: URL) throws {
    let column: CGFloat = 600
    let row: CGFloat = 840
    let width = Int(column * CGFloat(designs.count))
    let height = Int(row * 2)
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    for (backdrop, index) in [(RGB(0xF5F5F7), 1), (RGB(0x1E1E20), 0)] {
        let isDark = index == 0
        context.setFillColor(backdrop.cgColor)
        context.fill(CGRect(x: 0, y: CGFloat(index) * row, width: CGFloat(width), height: row))
        for (position, design) in designs.enumerated() {
            let x = CGFloat(position) * column
            let top = CGFloat(index) * row + row
            context.draw(render(design, pixels: 512), in: CGRect(x: x + 44, y: top - 556, width: 512, height: 512))
            var smallX = x + 44
            for pixels in [128, 64, 32, 16] {
                context.draw(render(design, pixels: pixels), in: CGRect(x: smallX, y: top - 556 - 24 - CGFloat(pixels), width: CGFloat(pixels), height: CGFloat(pixels)))
                smallX += CGFloat(pixels) + 28
            }
            let marker = design.name == chosenDesign ? "  (chosen)" : ""
            drawLabel("\(design.name)\(marker)", detail: design.summary, at: CGPoint(x: x + 44, y: top - 556 - 24 - 128 - 52), dark: isDark, in: context)
        }
    }
    try writePNG(context.makeImage()!, to: url)
}

func drawLabel(_ title: String, detail: String, at origin: CGPoint, dark: Bool, in context: CGContext) {
    let color = dark ? RGB(0xFFFFFF).cgColor : RGB(0x1D1D1F).cgColor
    let secondary = dark ? RGB(0xFFFFFF, alpha: 0.6).cgColor : RGB(0x1D1D1F, alpha: 0.6).cgColor
    for (text, size, fill, offset) in [(title, CGFloat(26), color, CGFloat(0)), (detail, CGFloat(18), secondary, CGFloat(-30))] {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): fill,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: origin.x, y: origin.y + offset)
        CTLineDraw(line, context)
    }
}

// MARK: Main

let arguments = Array(CommandLine.arguments.dropFirst())

func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

let scriptDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repository = scriptDirectory.deletingLastPathComponent()

do {
    if let sheet = value(after: "--contact-sheet") {
        try writeContactSheet(to: URL(fileURLWithPath: sheet))
        print("Wrote \(sheet)")
    } else {
        let name = value(after: "--design") ?? chosenDesign
        guard let design = designs.first(where: { $0.name == name }) else {
            throw ScriptError("No design called \(name). Choose from: \(designs.map(\.name).joined(separator: ", "))")
        }
        let output = value(after: "--out").map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("Resources/AppIcon.icns")
        try buildIcns(design, to: output)
        print("Wrote \(output.path) (\(design.name))")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
