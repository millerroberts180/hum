/// Every SF Symbol Hum uses. Hierarchical rendering by default, weight matched to
/// neighboring text; sizes come from `ControlSize`.
nonisolated enum HumIcon {
    static let play = "play.fill"
    static let pause = "pause.fill"
    static let playCircle = "play.circle"
    static let next = "forward.fill"
    static let previous = "backward.fill"
    static let shuffle = "shuffle"
    static let repeatAll = "repeat"
    static let repeatOne = "repeat.1"
    /// Save: Favorite.
    static let favorite = "star"
    static let favoriteOn = "star.fill"
    static let devices = "hifispeaker.2"
    static let more = "ellipsis"
    static let nowPlaying = "waveform"
    static let noSource = "waveform.slash"
    static let musicNote = "music.note"
    static let dismiss = "xmark"
    static let warning = "exclamationmark.triangle.fill"
    static let permission = "exclamationmark.shield"

    /// The speaker glyph for a volume level, 0...1.
    static func volume(_ level: Double) -> String {
        switch level {
        case ...0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    static let volumeLow = "speaker.fill"
    static let volumeMuted = "speaker.slash.fill"
    static let volumeHigh = "speaker.wave.3.fill"
}
