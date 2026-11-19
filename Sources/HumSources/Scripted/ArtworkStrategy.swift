import HumCore
/// How a scriptable app hands over cover art for the current track.
public enum ArtworkStrategy: Sendable {
    /// A script returning an `https` URL string; Hum downloads the image.
    case remoteURL(script: String)
    /// A script returning the image bytes directly.
    case rawData(script: String)
}
