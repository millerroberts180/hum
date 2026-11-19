import AppKit

/// Where Settings and Listening History open: where AppKit centers a window,
/// unless the player is there, since it floats over other windows. Then the
/// window opens just clear of the player, on whichever side keeps it nearest
/// the middle of the screen. With no room on any side, it stays centered.
enum ClearOfPlayer {
    /// Centers `window` on its screen, then moves it out from under the player.
    @MainActor
    static func center(_ window: NSWindow) {
        window.center()
        guard let visible = window.screen?.visibleFrame else { return }
        let player = NSApp.windows.first { $0 is PlayerPanel && $0.isVisible }?.frame
        let placed = frame(centered: window.frame, player: player, in: visible)
        if placed != window.frame { window.setFrameOrigin(placed.origin) }
    }

    /// `centered` left where it is when it's clear of `player`; otherwise the
    /// nearest frame of its size beside, above or below the player, a gap
    /// away, that fits in `visible`.
    nonisolated static func frame(centered: CGRect, player: CGRect?, in visible: CGRect, gap: CGFloat = Spacing.l) -> CGRect {
        guard let player, centered.intersects(player) else { return centered }
        let size = centered.size
        let x = min(max(centered.minX, visible.minX), visible.maxX - size.width)
        let y = min(max(centered.minY, visible.minY), visible.maxY - size.height)
        let beside = [
            CGPoint(x: player.minX - gap - size.width, y: y),
            CGPoint(x: player.maxX + gap, y: y),
            CGPoint(x: x, y: player.maxY + gap),
            CGPoint(x: x, y: player.minY - gap - size.height),
        ]
        .map { CGRect(origin: $0, size: size) }
        .filter { visible.contains($0) && !$0.intersects(player) }
        return beside.min { distance($0, centered) < distance($1, centered) } ?? centered
    }

    private nonisolated static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        hypot(a.midX - b.midX, a.midY - b.midY)
    }
}
