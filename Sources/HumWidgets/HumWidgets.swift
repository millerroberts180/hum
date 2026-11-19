import HumCore
import SwiftUI
import WidgetKit

/// Hum's widgets: Art Only, Title and Text, each named after its display
/// (DESIGN.md §7.3). The extension's entry point is the bundle's `main()`,
/// which hands the process to WidgetKit.
@main
struct HumWidgetBundle: WidgetBundle {
    var body: some Widget {
        ArtOnlyWidget()
        TitleWidget()
        TextWidget()
    }
}

/// The displays with a widget (DESIGN.md §7.3, §13.33). The other styles have
/// none.
enum WidgetDisplay: CaseIterable {
    case artOnly, title, text

    /// The player style the widget is named after.
    var style: PlayerStyleID {
        switch self {
        case .artOnly: .artOnly
        case .title: .title
        case .text: .text
        }
    }
}

/// The parts of a display's widget: its kind, name, one-line description, and
/// sizes.
@MainActor
enum DisplayWidget {
    /// Named by the style's stored value, so a placed widget keeps its place
    /// across builds.
    static func kind(_ display: WidgetDisplay) -> String {
        "com.millerroberts.hum.widget." + display.style.rawValue
    }

    static func families(_ display: WidgetDisplay) -> [WidgetFamily] {
        switch display {
        case .artOnly: [.systemSmall, .systemLarge]
        case .title: [.systemMedium]
        case .text: [.systemSmall]
        }
    }

    static func description(_ display: WidgetDisplay) -> String {
        switch display {
        case .artOnly: "The cover, with the song’s controls in the large size."
        case .title: "The cover, the song’s title, and its controls."
        case .text: "The song’s title and artist, in words alone."
        }
    }

    /// A display's widget.
    static func configuration(_ display: WidgetDisplay) -> some WidgetConfiguration {
        StaticConfiguration(kind: kind(display), provider: HumProvider()) { entry in
            DisplayView(display: display, entry: entry)
        }
        .configurationDisplayName(display.style.title)
        .description(description(display))
        .supportedFamilies(families(display))
    }
}

// Art Only's cover runs to the widget's edge, so it draws its own margins.

struct ArtOnlyWidget: Widget {
    var body: some WidgetConfiguration { DisplayWidget.configuration(.artOnly).contentMarginsDisabled() }
}

struct TitleWidget: Widget {
    var body: some WidgetConfiguration { DisplayWidget.configuration(.title) }
}

struct TextWidget: Widget {
    var body: some WidgetConfiguration { DisplayWidget.configuration(.text) }
}
