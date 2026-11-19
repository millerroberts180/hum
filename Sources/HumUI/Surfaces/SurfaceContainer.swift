import HumCore
import SwiftUI

/// Lays the three surfaces side by side and slides them by the pager's position.
///
/// Only the surfaces on screen are built: the current one at rest, and its
/// neighbor while a swipe or spring is between them. Under Reduce Motion there is
/// no sliding; the current surface crossfades with the next.
struct SurfaceContainer: View {
    @Environment(SurfacePager.self) private var pager
    @State private var width: CGFloat = PlayerMetrics.defaultSide

    var body: some View {
        ZStack {
            if pager.reduceMotion {
                SurfaceView(surface: pager.current)
                    .id(pager.current)
                    .transition(.opacity)
            } else {
                ForEach(visibleSurfaces) { surface in
                    SurfaceView(surface: surface)
                        .environment(\.surfaceIsActive, surface == pager.current && !pager.isMoving)
                        .offset(x: (Double(surface.index) - pager.position) * width)
                        .accessibilityHidden(surface != pager.current)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
            pager.pageWidth = newWidth
        }
    }

    private var visibleSurfaces: [Surface] {
        Surface.allCases.filter { surface in
            surface == pager.current || abs(Double(surface.index) - pager.position) < 1
        }
    }
}
