import HumCore
import SwiftUI

/// The cover the widget gallery shows: a low sun over a calm sea at dusk, drawn
/// in code (Hum ships no image assets).
struct DemoCover: View {
    nonisolated static let palette = ArtworkPalette(
        background: PaletteColor(red: 0.13, green: 0.12, blue: 0.27),
        primary: .white,
        secondary: PaletteColor(red: 0.98, green: 0.82, blue: 0.74),
        tertiary: PaletteColor(red: 0.62, green: 0.58, blue: 0.70),
        accent: PaletteColor(red: 1.0, green: 0.55, blue: 0.42),
        isDark: true,
        average: PaletteColor(red: 0.42, green: 0.26, blue: 0.38)
    )

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let horizon = size.height * 0.62
            let sky = Path(CGRect(x: 0, y: 0, width: size.width, height: horizon))
            context.fill(sky, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.16, green: 0.13, blue: 0.36),
                    Color(red: 0.62, green: 0.25, blue: 0.45),
                    Color(red: 0.98, green: 0.56, blue: 0.40),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: horizon)
            ))
            let sunRadius = side * 0.17
            let sun = Path(ellipseIn: CGRect(
                x: size.width * 0.58 - sunRadius,
                y: horizon - sunRadius * 1.2,
                width: sunRadius * 2,
                height: sunRadius * 2
            ))
            context.drawLayer { layer in
                layer.clip(to: sky)
                layer.fill(sun, with: .color(Color(red: 1.0, green: 0.86, blue: 0.62)))
            }
            let sea = Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon))
            context.fill(sea, with: .linearGradient(
                Gradient(colors: [Color(red: 0.20, green: 0.15, blue: 0.34), Color(red: 0.07, green: 0.07, blue: 0.16)]),
                startPoint: CGPoint(x: 0, y: horizon),
                endPoint: CGPoint(x: 0, y: size.height)
            ))
            // The sun's path on the water: short bands that narrow toward the shore.
            for band in 0..<6 {
                let t = CGFloat(band) / 6
                let width = sunRadius * (1.6 - t * 1.1)
                let y = horizon + side * 0.03 + t * (size.height - horizon) * 0.8
                let rect = CGRect(x: size.width * 0.58 - width / 2, y: y, width: width, height: side * 0.018)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: rect.height / 2),
                    with: .color(Color(red: 1.0, green: 0.78, blue: 0.58).opacity(0.75 - Double(t) * 0.5))
                )
            }
        }
        .accessibilityHidden(true)
    }
}

extension WidgetSnapshot {
    /// The gallery's song: a demo song, playing.
    static func demo(at date: Date) -> WidgetSnapshot {
        WidgetSnapshot(
            song: Song(title: "Low Tide Radio", artist: "Marlow Fields", album: "Coastline Hours", duration: 214),
            isPlaying: true,
            position: 62,
            positionDate: date,
            shuffle: false,
            repeatMode: .all,
            actions: Set(HumURLAction.allCases),
            palette: DemoCover.palette
        )
    }
}
