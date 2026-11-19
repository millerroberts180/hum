import AppKit
import HumCore

/// The Menu Bar style's status item (DESIGN.md §7.1): the cover, the song's
/// title, then play/pause and next as bare template glyphs. It sits inside the
/// status item's button, which carries its VoiceOver label.
///
/// Clicks on the cover or title go through to the button, which highlights
/// as any status item does and opens the popover or the menu.
public final class MenuBarPlayerItemView: NSView {
    /// What the item shows.
    public struct Content: Equatable {
        public var title: String
        public var artist: String
        public var isPlaying: Bool
        public var canPlayPause: Bool
        public var canSkip: Bool

        public init(title: String, artist: String, isPlaying: Bool, canPlayPause: Bool, canSkip: Bool) {
            self.title = title
            self.artist = artist
            self.isPlaying = isPlaying
            self.canPlayPause = canPlayPause
            self.canSkip = canSkip
        }
    }

    public var onPlayPause: () -> Void = {}
    public var onNext: () -> Void = {}

    private let cover = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let playPauseButton = NSButton()
    private let nextButton = NSButton()
    private var content: Content?

    public init() {
        super.init(frame: .zero)
        cover.imageScaling = .scaleProportionallyUpOrDown
        cover.wantsLayer = true
        cover.layer?.cornerRadius = Layout.coverRadius
        cover.layer?.cornerCurve = .continuous
        cover.layer?.masksToBounds = true
        cover.setAccessibilityElement(false)
        titleField.font = Layout.titleFont
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.maximumNumberOfLines = 1
        titleField.setAccessibilityElement(false)
        for (button, action) in [(playPauseButton, #selector(playPause)), (nextButton, #selector(next))] {
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.target = self
            button.action = action
            button.refusesFirstResponder = true
        }
        nextButton.image = Self.glyph("forward.fill")
        nextButton.setAccessibilityLabel("Next Track")
        for view in [cover, titleField, playPauseButton, nextButton] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public var isFlipped: Bool { true }

    /// Fill the status item's `button` and keep filling it as the item's
    /// length changes. It starts at the button's size: autoresizing only adds
    /// the change in size, so from zero it would stay zero high and draw the
    /// cover half above the bar.
    public func embed(in button: NSView) {
        frame = button.bounds
        autoresizingMask = [.width, .height]
        button.addSubview(self)
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    /// Show `content` with `artwork` (or the missing-artwork placeholder).
    public func update(_ content: Content, artwork: CGImage?) {
        let side = Layout.coverSide
        cover.image = artwork.map { NSImage(cgImage: $0, size: NSSize(width: side, height: side)) } ?? Self.placeholder
        guard content != self.content else { return }
        self.content = content
        titleField.stringValue = content.title
        playPauseButton.image = Self.glyph(content.isPlaying ? "pause.fill" : "play.fill")
        playPauseButton.setAccessibilityLabel(content.isPlaying ? "Pause" : "Play")
        playPauseButton.isHidden = !content.canPlayPause
        nextButton.isHidden = !content.canSkip
        needsLayout = true
    }

    /// The width the item needs for what it shows.
    public var preferredWidth: CGFloat {
        frames(height: Layout.coverSide).width
    }

    override public func layout() {
        super.layout()
        let frames = frames(height: bounds.height)
        cover.frame = frames.cover
        // The frames are where the text goes. A label draws its text 2 pt in
        // from each side of its frame, so the frame reaches past them.
        titleField.frame = titleField.frame(forAlignmentRect: frames.title)
        playPauseButton.frame = frames.playPause ?? .zero
        nextButton.frame = frames.next ?? .zero
    }

    private func frames(height: CGFloat) -> Layout.Frames {
        Layout.frames(
            titleWidth: ceil(titleField.intrinsicContentSize.width),
            height: height,
            showsPlayPause: !playPauseButton.isHidden,
            showsNext: !nextButton.isHidden
        )
    }

    // MARK: Clicks

    /// Only the two glyphs take clicks themselves; the rest belongs to the
    /// status item's button underneath.
    override public func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit is NSButton ? hit : nil
    }

    @objc private func playPause() { onPlayPause() }
    @objc private func next() { onNext() }

    // MARK: Drawing

    /// A bare template glyph, which the menu bar tints for its appearance.
    private static func glyph(_ name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: Layout.glyphPointSize, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    /// The missing-artwork placeholder at the cover's size: a `fillQuaternary`
    /// square with the music note in `quaternaryLabel`.
    private static let placeholder: NSImage = {
        let side = Layout.coverSide
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.quaternarySystemFill.setFill()
            rect.fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
                .applying(.init(paletteColors: [.quaternaryLabelColor]))
            if let note = NSImage(systemSymbolName: HumIcon.musicNote, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                let size = note.size
                note.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            }
            return true
        }
    }()

    // MARK: Metrics

    /// The item's metrics (DESIGN.md §7.1).
    nonisolated enum Layout {
        static let coverSide: CGFloat = 18
        static let coverRadius: CGFloat = 4
        static let titleMaxWidth: CGFloat = 160
        /// Each glyph's hit area is this wide, the item's full height.
        static let buttonWidth: CGFloat = 22
        static let gap: CGFloat = 6
        /// Clear of the item's leading edge, as the system's items keep their
        /// images.
        static let leading: CGFloat = Spacing.xs
        static let glyphPointSize: CGFloat = 13

        @MainActor static var titleFont: NSFont { NSFont.menuBarFont(ofSize: 0) }

        struct Frames: Equatable {
            var cover: CGRect
            var title: CGRect
            var playPause: CGRect?
            var next: CGRect?
            var width: CGFloat
        }

        /// Where each piece goes in an item `height` tall (y down), with a
        /// title `titleWidth` wide before truncation, and the width it adds up to.
        static func frames(titleWidth: CGFloat, height: CGFloat, showsPlayPause: Bool, showsNext: Bool) -> Frames {
            var x = leading
            let cover = CGRect(x: x, y: ((height - coverSide) / 2).rounded(), width: coverSide, height: coverSide)
            x = cover.maxX + gap
            let width = min(max(titleWidth, 0), titleMaxWidth)
            let titleHeight = min(height, coverSide)
            let title = CGRect(x: x, y: ((height - titleHeight) / 2).rounded(), width: width, height: titleHeight)
            x = title.maxX
            func button() -> CGRect {
                x += gap
                defer { x += buttonWidth }
                return CGRect(x: x, y: 0, width: buttonWidth, height: height)
            }
            let playPause = showsPlayPause ? button() : nil
            let next = showsNext ? button() : nil
            return Frames(cover: cover, title: title, playPause: playPause, next: next, width: x)
        }
    }

    /// The status item's VoiceOver label: "Hum, Title by Artist", or
    /// "Hum, Title" when the source names no artist.
    public nonisolated static func accessibilityLabel(title: String, artist: String) -> String {
        artist.isEmpty ? "Hum, \(title)" : "Hum, \(title) by \(artist)"
    }
}
