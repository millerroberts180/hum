/// Saving a song in Hum's words: Favorite and a star. Only sources that can
/// save offer it (DESIGN.md §1.3).
nonisolated enum SaveVocabulary {
    static func symbol(isSaved: Bool) -> String {
        isSaved ? HumIcon.favoriteOn : HumIcon.favorite
    }

    /// The action, as a menu item or button label.
    static func title(isSaved: Bool) -> String {
        isSaved ? "Remove from Favorites" : "Favorite"
    }
}
