import HumCore
import SwiftUI

/// The view for each surface. Each surface owns its folder; this is the only place
/// that knows about all three.
struct SurfaceView: View {
    var surface: Surface

    var body: some View {
        switch surface {
        case .now: NowSurface()
        case .echo: EchoSurface()
        case .status: StatusSurface()
        }
    }
}
