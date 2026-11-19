import Foundation

extension NowPlayingStore {
    /// Saves the playing song, or unsaves it if it's saved, and confirms in the
    /// HUD once the source has it: "Added to Favorites" (DESIGN.md §5.2). For
    /// ⌥⇧B and the More and right-click menus, where Save's button may be out
    /// of sight. The button itself sends `.setFavorite`, because its glyph
    /// shows the result.
    ///
    /// Nothing is confirmed when the source turns the change down or the song
    /// changes meanwhile. Does nothing without a song, or when its source
    /// can't save it, as Spotify's can't (DESIGN.md §1.3).
    ///
    /// - Returns: The work, for tests to wait on.
    @discardableResult
    public func toggleSaveAndConfirm() -> Task<Void, Never>? {
        guard let track, let source = activeSourceID else { return nil }
        let saved = !(snapshot.isFavorite ?? false)
        let command = PlaybackCommand.setFavorite(saved)
        guard capabilities.supports(command) else { return nil }
        return Task { [weak self] in
            guard let self else { return }
            await self.perform(command)
            // A refusal puts the source's own answer back on display.
            guard self.snapshot.track?.id == track.id, self.snapshot.isFavorite == saved else { return }
            LibraryStore.attached(to: self)?.post(LibraryNotice(saved ? .saved : .unsaved, source: source))
        }
    }
}
