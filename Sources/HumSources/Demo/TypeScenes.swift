import AppKit
import CoreGraphics
import CoreText

/// A cover that is mostly type: the title set large on printed paper, or over
/// a picture, with the artist's name small at the foot.
struct TypeCover {
    enum Face {
        /// New York.
        case serif
        /// SF Pro.
        case sans
    }

    enum Layout {
        /// Large lines flush left from the top margin, the byline at the foot
        /// under a hairline rule.
        case stacked
        /// Capitals centered on the cover, the byline above them.
        case centered
        /// Over a picture: the title at the lower left, the byline above it.
        case corner
    }

    var title: String
    var byline: String
    /// A small catalog mark at the lower right, or empty for none.
    var mark = ""
    var paper: ArtColor
    var ink: ArtColor
    var face: Face
    var layout: Layout
    var seed: UInt64

    /// Paints the cover. With `picture`, the picture is the ground instead of
    /// paper and the type is set in `ink` over a soft shade for legibility.
    func paint(_ canvas: ArtCanvas, picture: ((ArtCanvas) -> Void)? = nil) {
        if let picture {
            picture(canvas)
            // Darken the corner the type sits in, the way a designer would
            // burn in a photograph under a caption.
            let shade = paper.scaled(0.25)
            canvas.layer(.multiply, alpha: 0.55) {
                canvas.linearGradient([(shade, 0), (ArtColor.white, 0.55)], from: (0.5, 0), to: (0.5, 1))
            }
        } else {
            paintPaper(canvas)
        }

        guard let text = ArtCanvas(side: canvas.side) else { return }
        text.fill(.black)
        text.context.setFillColor(CGColor(gray: 1, alpha: 1))
        switch layout {
        case .stacked: setStacked(on: text)
        case .centered: setCentered(on: text)
        case .corner: setCorner(on: text)
        }
        // Ink spreads a hair into the paper.
        if picture == nil { text.blur(0.0007) }
        guard let mask = text.maskImage() else { return }
        canvas.fill(ink, through: mask)
        if picture == nil { inkTexture(canvas, mask: mask) }
    }

    // MARK: Paper and ink

    private func paintPaper(_ canvas: ArtCanvas) {
        let noise = ValueNoise(seed: seed)
        var random = ArtRandom(seed: seed ^ 0xA5A5)
        canvas.fill(paper)
        // Uneven fiber density, and the faint grain of the paper's machine
        // direction.
        let mottle = ArtField.gray(width: 72, height: 72) { u, v in
            noise.fractal(u * 3.5 + 11, v * 3.5, octaves: 5)
        }
        canvas.draw(mottle, blend: .overlay, alpha: 0.16)
        let fibers = ArtField.gray(width: 220, height: 220) { u, v in
            noise.fractal(u * 70 + 3, v * 12, octaves: 2)
        }
        canvas.draw(fibers, blend: .overlay, alpha: 0.07)
        // Flecks of ash and dust pressed into the sheet.
        let dark = paper.luma > 0.5
        let fleck = dark ? ink.mixed(with: paper, 0.35) : paper.mixed(with: .white, 0.5)
        for index in 0..<70 {
            let radius = (index < 8 ? random.range(0.002...0.005) : random.range(0.0006...0.0018)) * canvas.size
            let center = canvas.point(random.unit(), random.unit())
            canvas.context.setFillColor(fleck.cgColor(random.range(0.15...0.6)))
            let path = CGMutablePath()
            for corner in 0..<6 {
                let angle = Double(corner) / 6 * 2 * .pi + random.range(-0.3...0.3)
                let reach = radius * random.range(0.5...1.3)
                let point = CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach)
                if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            canvas.context.addPath(path)
            canvas.solid { $0.fillPath() }
        }
        // Light falling across the sheet from the upper left.
        canvas.layer(.softLight, alpha: 0.5) {
            canvas.linearGradient([(ArtColor.white, 0), (ArtColor.black, 1)], from: (0.1, 1), to: (0.9, 0))
        }
    }

    /// Ink that took unevenly, thinner in places, as in letterpress.
    private func inkTexture(_ canvas: ArtCanvas, mask: CGImage) {
        let noise = ValueNoise(seed: seed ^ 0x1A2B)
        let thin = ArtField.gray(width: 200, height: 200) { u, v in
            smoothstep(0.5, 0.9, noise.fractal(u * 40, v * 40, octaves: 3))
        }
        canvas.context.saveGState()
        canvas.context.clip(to: canvas.bounds, mask: mask)
        canvas.fill(paper, through: thin, alpha: 0.16)
        canvas.context.restoreGState()
    }

    // MARK: Layouts

    private func setStacked(on canvas: ArtCanvas) {
        let margin = 0.08
        let lines = Self.lines(title)
        let width = (1 - margin * 2) * canvas.size
        let height = 0.6 * canvas.size
        let size = fitSize(lines, width: width, height: height, leading: 0.9, tracking: -0.025, weight: .medium, canvas: canvas)
        var baseline = canvas.size * (1 - margin) - size * 0.78
        for line in lines {
            drawLine(line, size: size, weight: .medium, tracking: -0.025, at: margin * canvas.size, baseline: baseline, canvas: canvas)
            baseline -= size * 0.9
        }
        // The foot: a hairline rule, the byline, and the catalog mark.
        let foot = margin * canvas.size
        let small = max(7, canvas.size * 0.03)
        canvas.solid { $0.fill(CGRect(x: foot, y: foot + small * 1.9, width: canvas.size - foot * 2, height: max(1, canvas.size * 0.0018))) }
        drawCaption(byline.uppercased(), size: small, at: foot, baseline: foot + small * 0.2, canvas: canvas)
        if !mark.isEmpty {
            drawCaption(mark.uppercased(), size: small, at: nil, baseline: foot + small * 0.2, trailing: canvas.size - foot, canvas: canvas)
        }
    }

    private func setCentered(on canvas: ArtCanvas) {
        let lines = Self.lines(title).map { $0.uppercased() }
        let width = 0.78 * canvas.size
        let height = 0.46 * canvas.size
        let size = fitSize(lines, width: width, height: height, leading: 0.94, tracking: 0.02, weight: .heavy, canvas: canvas)
        let block = size * 0.94 * Double(lines.count - 1) + size * 0.72
        var baseline = (canvas.size + block) / 2 - size * 0.72
        for line in lines {
            drawLine(line, size: size, weight: .heavy, tracking: 0.02, at: nil, baseline: baseline, canvas: canvas)
            baseline -= size * 0.94
        }
        let small = max(7, canvas.size * 0.032)
        drawCaption(byline.uppercased(), size: small, at: nil, baseline: (canvas.size + block) / 2 + small * 2.2, canvas: canvas)
        if !mark.isEmpty {
            drawCaption(mark.uppercased(), size: small * 0.85, at: nil, baseline: canvas.size * 0.08, canvas: canvas)
        }
    }

    private func setCorner(on canvas: ArtCanvas) {
        let margin = 0.075
        let lines = Self.lines(title)
        let width = (1 - margin * 2) * canvas.size
        let height = 0.4 * canvas.size
        var size = fitSize(lines, width: width, height: height, leading: 0.92, tracking: -0.02, weight: .bold, canvas: canvas)
        size = min(size, canvas.size * 0.16)
        var baseline = margin * canvas.size + size * 0.92 * Double(lines.count - 1)
        let top = baseline + size * 0.74
        for line in lines {
            drawLine(line, size: size, weight: .bold, tracking: -0.02, at: margin * canvas.size, baseline: baseline, canvas: canvas)
            baseline -= size * 0.92
        }
        if !byline.isEmpty {
            let small = max(7, canvas.size * 0.034)
            drawCaption(byline.uppercased(), size: small, at: margin * canvas.size, baseline: top + small * 1.2, canvas: canvas)
        }
    }

    // MARK: Setting type

    /// Breaks a title into display lines: one word per line, with short
    /// joining words kept with the word after them.
    static func lines(_ title: String) -> [String] {
        let joiners: Set<String> = ["&", "and", "of", "the", "a", "an", "in", "to", "for", "on"]
        var lines: [String] = []
        var pending = ""
        for word in title.split(separator: " ").map(String.init) {
            if joiners.contains(word.lowercased()) {
                pending = pending.isEmpty ? word : pending + " " + word
                continue
            }
            lines.append(pending.isEmpty ? word : pending + " " + word)
            pending = ""
        }
        if !pending.isEmpty {
            if lines.isEmpty { lines.append(pending) } else { lines[lines.count - 1] += " " + pending }
        }
        return lines.isEmpty ? [title] : lines
    }

    /// The largest size at which every line fits `width` and the block fits
    /// `height`.
    private func fitSize(_ lines: [String], width: Double, height: Double, leading: Double, tracking: Double, weight: NSFont.Weight, canvas: ArtCanvas) -> Double {
        let probe = 100.0
        let widest = lines.map { inkBounds(self.line($0, size: probe, weight: weight, tracking: tracking), canvas: canvas).width }.max() ?? probe
        var size = min(width / max(widest, 1) * probe, height / (leading * Double(lines.count - 1) + 0.9))
        // Optical sizes change the widths a little; check at the real size.
        for _ in 0..<3 {
            let actual = lines.map { inkBounds(self.line($0, size: size, weight: weight, tracking: tracking), canvas: canvas).width }.max() ?? 0
            guard actual > width else { break }
            size *= width / actual * 0.995
        }
        return size
    }

    private func drawLine(_ text: String, size: Double, weight: NSFont.Weight, tracking: Double, at left: Double?, baseline: Double, canvas: ArtCanvas) {
        let line = line(text, size: size, weight: weight, tracking: tracking)
        let bounds = inkBounds(line, canvas: canvas)
        // Align the ink, not the advance, so round letters sit on the margin.
        let x = left.map { $0 - bounds.minX } ?? (canvas.size - bounds.width) / 2 - bounds.minX
        canvas.context.textPosition = CGPoint(x: x, y: baseline)
        canvas.solid { CTLineDraw(line, $0) }
    }

    private func drawCaption(_ text: String, size: Double, at left: Double?, baseline: Double, trailing: Double? = nil, canvas: ArtCanvas) {
        let font = Self.font(.sans, size: size, weight: .semibold)
        let line = Self.line(text, font: font, italicFont: nil, tracking: 0.14 * size)
        let bounds = inkBounds(line, canvas: canvas)
        let x: Double
        if let trailing {
            x = trailing - bounds.maxX
        } else if let left {
            x = left - bounds.minX
        } else {
            x = (canvas.size - bounds.width) / 2 - bounds.minX
        }
        canvas.context.textPosition = CGPoint(x: x, y: baseline)
        canvas.solid { CTLineDraw(line, $0) }
    }

    private func line(_ text: String, size: Double, weight: NSFont.Weight, tracking: Double) -> CTLine {
        let font = Self.font(face, size: size, weight: weight)
        // An ampersand in the serif face is set from the italic, which is
        // where the beautiful one lives.
        let italic = face == .serif ? Self.font(.serif, size: size, weight: .regular, italic: true) : nil
        return Self.line(text, font: font, italicFont: italic, tracking: tracking * size)
    }

    private static func line(_ text: String, font: CTFont, italicFont: CTFont?, tracking: Double) -> CTLine {
        let string = NSMutableAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking,
        ])
        if let italicFont {
            let characters = text as NSString
            var search = NSRange(location: 0, length: characters.length)
            while true {
                let found = characters.range(of: "&", range: search)
                guard found.location != NSNotFound else { break }
                string.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String), value: italicFont, range: found)
                // The italic leans into the next word; give it room.
                string.addAttribute(NSAttributedString.Key(kCTKernAttributeName as String), value: tracking + CTFontGetSize(italicFont) * 0.05, range: found)
                search = NSRange(location: found.upperBound, length: characters.length - found.upperBound)
            }
        }
        // No tracking after the last letter, so centering is true.
        if string.length > 0 {
            string.addAttribute(NSAttributedString.Key(kCTKernAttributeName as String), value: 0, range: NSRange(location: string.length - 1, length: 1))
        }
        return CTLineCreateWithAttributedString(string)
    }

    private func inkBounds(_ line: CTLine, canvas: ArtCanvas) -> CGRect {
        // Image bounds are measured from the current text position, which
        // drawing a line moves.
        canvas.context.textPosition = .zero
        return CTLineGetImageBounds(line, canvas.context)
    }

    static func font(_ face: Face, size: Double, weight: NSFont.Weight, italic: Bool = false) -> CTFont {
        var descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        if face == .serif, let serif = descriptor.withDesign(.serif) {
            descriptor = serif
        }
        if italic {
            descriptor = descriptor.withSymbolicTraits(.italic)
        }
        return (NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)) as CTFont
    }
}

extension ArtColor {
    /// Rough perceived lightness, 0...1.
    var luma: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
