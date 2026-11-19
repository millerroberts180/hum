#if DEBUG
import HumCore
import SwiftUI

// Previews of the device picker and Echo's menus add a demo library to the
// preview player (DESIGN.md §12.4), so there are devices to list and songs
// to save.
//
//     PreviewGallery(cases: [.largeLight, .largeDark], isSquare: false) {
//         DevicePicker().libraryPreview()
//     }

/// A demo library: every song takes the preview cover, and two devices.
final class PreviewLibrary: LibraryProvider {
    let sourceID = SourceID.demo
    let displayName = "Demo"
    let capabilities: SourceCapabilities = [.playItems, .saveItems, .devices, .deviceSwitching]
    var onChange: (@MainActor () -> Void)?

    func devices() async throws(LibraryError) -> [PlaybackDevice] {
        [
            PlaybackDevice(id: "preview:mac", name: "Studio MacBook Pro", kind: .computer, isActive: true, isThisMac: true),
            PlaybackDevice(id: "preview:speaker", name: "Kitchen", kind: .speaker, isActive: false),
        ]
    }

    func play(_ request: PlayRequest) async throws(LibraryError) {}

    func artworkData(for artwork: LibraryArtwork) async -> Data? {
        PreviewSource.coverData
    }
}

extension View {
    /// This view with the demo library in its environment, following its own
    /// preview player.
    func libraryPreview() -> some View {
        modifier(LibraryPreviewHost())
    }
}

private struct LibraryPreviewHost: ViewModifier {
    @State private var library: LibraryStore = {
        let nowPlaying = NowPlayingStore(sources: [PreviewSource(isPlaying: true)], preferredSourceID: .demo)
        let library = LibraryStore(nowPlaying: nowPlaying, providers: [PreviewLibrary()])
        nowPlaying.start()
        return library
    }()

    func body(content: Content) -> some View {
        content.environment(library)
    }
}
#endif
