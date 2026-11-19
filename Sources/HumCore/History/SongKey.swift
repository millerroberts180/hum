import Foundation

/// Groups listens of the same song even when sources give it different ids.
///
/// The key is the artist and title, folded for case, accents, and width, with
/// punctuation and repeated spaces dropped. "Café Nights" by "Ana" and "cafe nights"
/// by "ANA" are the same song.
public enum SongKey {
    public static func make(artist: String, title: String) -> String {
        normalize(artist) + "\u{1F}" + normalize(title)
    }

    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var result = ""
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSpace, !result.isEmpty { result.append(" ") }
                pendingSpace = false
                result.unicodeScalars.append(scalar)
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) || CharacterSet.punctuationCharacters.contains(scalar) {
                pendingSpace = true
            }
        }
        return result
    }
}
