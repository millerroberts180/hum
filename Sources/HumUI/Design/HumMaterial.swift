import AppKit
import HumCore
import SwiftUI

/// Hum's materials (DESIGN.md §3.6). Content (artwork) sits at the bottom, one
/// translucent layer of controls above it, and nothing stacks beyond that.
nonisolated enum HumMaterial: Hashable, Sendable {
    /// Art Only's hover controls without Liquid Glass: the bottom-up gradient
    /// (`Scrim`).
    case controlsScrim
    /// Art Only's hover controls with Liquid Glass: clear glass over a dimming
    /// layer (`ControlsPlatter`).
    case controlsPlatter
    /// Title's and Strip's windows; the HUD.
    case glassCard
    /// Text's window.
    case glassCapsule
    /// Menus, the hover time tag, the device picker, the Menu Bar popover.
    case popover
    case sidebar
}

/// Whether Hum draws Liquid Glass (DESIGN.md §3.6.1): only on macOS 26, and
/// only while Appearance › Material is Liquid Glass. Everywhere else every
/// material takes its macOS 15 form, and nothing imitates glass.
nonisolated enum LiquidGlass {
    static func isOn(_ material: GlassMaterial) -> Bool {
        material.effective == .liquidGlass
    }

    /// For the settings in the environment; without any, the default
    /// (Liquid Glass where macOS has it).
    @MainActor static func isOn(_ settings: SettingsStore?) -> Bool {
        isOn(settings?.appearance.material ?? AppearanceSettings().material)
    }
}

/// Renders a `HumMaterial` in a shape: Liquid Glass on macOS 26 with the
/// Liquid Glass material, a visual-effect material otherwise, an opaque fill
/// with Reduce Transparency. Liquid Glass draws its own edge, so nothing goes
/// over it; the others get a 1-pt inner stroke and nothing else.
///
/// Inside the player these usually blend within the window, because they sit
/// over the artwork. A style whose whole window is the material (Title, Text,
/// Strip) blends with the desktop behind it instead.
struct MaterialBackground<S: InsettableShape>: ViewModifier {
    var material: HumMaterial
    var shape: S
    var behindWindow = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.humMaterialsStayInWindow) private var staysInWindow
    @Environment(\.isInWindowGlass) private var isInWindowGlass
    @Environment(SettingsStore.self) private var settings: SettingsStore?

    @ViewBuilder
    func body(content: Content) -> some View {
        if isInWindowGlass, !reduceTransparency {
            // The window is the glass; nothing inside it is glass again.
            content.background(HumColor.fillQuaternary, in: shape)
        } else if #available(macOS 26, *), !reduceTransparency, LiquidGlass.isOn(settings) {
            switch material {
            case .sidebar:
                // The system draws a sidebar's own material (§3.6), and nothing
                // goes over it.
                content
            case .glassCapsule:
                content.glassEffect(.regular, in: .capsule)
            case .controlsPlatter:
                content.glassEffect(.clear, in: shape)
            case .controlsScrim, .glassCard, .popover:
                content.glassEffect(.regular, in: shape)
            }
        } else {
            surface(content)
                .overlay {
                    shape.strokeBorder(HumColor.glassStroke, lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
    }

    @ViewBuilder
    private func surface(_ content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
        } else {
            content.background {
                VisualEffectBackground(material: material.visualEffect, behindWindow: behindWindow && !staysInWindow)
                    .clipShape(shape)
            }
        }
    }
}

extension HumMaterial {
    /// The macOS 15 form. The two controls materials aren't drawn as a visual
    /// effect (`ControlsBackground`); they answer with the HUD's.
    fileprivate var visualEffect: NSVisualEffectView.Material {
        switch self {
        case .controlsScrim, .controlsPlatter, .glassCard: .hudWindow
        case .glassCapsule, .popover: .popover
        case .sidebar: .sidebar
        }
    }
}

extension View {
    func humMaterial<S: InsettableShape>(_ material: HumMaterial, in shape: S, behindWindow: Bool = false) -> some View {
        modifier(MaterialBackground(material: material, shape: shape, behindWindow: behindWindow))
    }

    /// Glass for something that floats over content (DESIGN.md §3.6): the HUD,
    /// the page indicator. Liquid Glass on macOS 26 with the Liquid Glass
    /// material, interactive when the shape is itself a control; `fallback`
    /// otherwise, and an opaque fill under Reduce Transparency.
    /// Inside the window's own glass (`isInWindowGlass`) it's a
    /// `fillQuaternary` fill, so glass never sits on glass.
    func floatingGlass<S: InsettableShape>(in shape: S, interactive: Bool = false, fallback: HumMaterial = .glassCard) -> some View {
        modifier(FloatingGlass(shape: shape, isInteractive: interactive, fallback: fallback))
    }

    /// `material` as the background of a style whose whole window is the
    /// material (Title, Text, Strip), telling the content whether it now sits
    /// inside the window's own glass.
    func windowMaterial(_ material: HumMaterial) -> some View {
        modifier(WindowMaterial(material: material))
    }
}

private struct FloatingGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var isInteractive: Bool
    var fallback: HumMaterial

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isInWindowGlass) private var isInWindowGlass
    @Environment(SettingsStore.self) private var settings: SettingsStore?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency, !isInWindowGlass, LiquidGlass.isOn(settings) {
            content.glassEffect(isInteractive ? .regular.interactive() : .regular, in: shape)
        } else {
            // `MaterialBackground` handles window glass and Reduce Transparency.
            content.humMaterial(fallback, in: shape)
        }
    }
}

private struct WindowMaterial: ViewModifier {
    var material: HumMaterial

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.humMaterialsStayInWindow) private var staysInWindow
    @Environment(SettingsStore.self) private var settings: SettingsStore?

    func body(content: Content) -> some View {
        content
            .environment(\.isInWindowGlass, WindowMaterialBackground.usesWindowGlass(
                reduceTransparency: reduceTransparency,
                staysInWindow: staysInWindow,
                liquidGlass: LiquidGlass.isOn(settings)
            ))
            .background { WindowMaterialBackground(material: material) }
    }
}

/// Liquid Glass shapes that float near each other, rendered in one pass so they
/// never sample one another and can blend or morph (a `GlassEffectContainer` on
/// macOS 26). Before that it's just its content.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// The background of a style whose whole window is the material (Title, Text,
/// Strip). With Liquid Glass the window draws it: the player's content view
/// hosts the SwiftUI content in an `NSGlassEffectView`, so the glass samples
/// the desktop behind the borderless window and nothing inside it is glass.
/// Otherwise, and in a player drawn inside another window, it's the macOS 15
/// material blending with whatever is behind the window.
struct WindowMaterialBackground: View {
    var material: HumMaterial

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.humMaterialsStayInWindow) private var staysInWindow
    @Environment(SettingsStore.self) private var settings: SettingsStore?

    /// Whether the window itself is the glass: macOS 26 with the Liquid Glass
    /// material, with transparency on, in the player's own window.
    static func usesWindowGlass(reduceTransparency: Bool, staysInWindow: Bool, liquidGlass: Bool = true) -> Bool {
        guard #available(macOS 26, *) else { return false }
        return liquidGlass && !reduceTransparency && !staysInWindow
    }

    var body: some View {
        if Self.usesWindowGlass(
            reduceTransparency: reduceTransparency,
            staysInWindow: staysInWindow,
            liquidGlass: LiquidGlass.isOn(settings)
        ) {
            Color.clear
                .preference(key: WindowGlassKey.self, value: true)
        } else {
            Color.clear
                .humMaterial(material, in: Rectangle(), behindWindow: true)
        }
    }
}

/// Whether the content asks for the window's own glass behind it.
nonisolated struct WindowGlassKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// An `NSVisualEffectView` that blends with the window's content behind it (or
/// with the desktop), in the SwiftUI color scheme rather than the window's
/// (controls over artwork are always dark).
private struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var behindWindow = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = behindWindow ? .behindWindow : .withinWindow
        let isDark = context.environment.colorScheme == .dark
        let increased = context.environment.colorSchemeContrast == .increased
        let name: NSAppearance.Name = switch (isDark, increased) {
        case (true, false): .darkAqua
        case (true, true): .accessibilityHighContrastDarkAqua
        case (false, false): .aqua
        case (false, true): .accessibilityHighContrastAqua
        }
        view.appearance = NSAppearance(named: name)
    }
}

private nonisolated struct MaterialsStayInWindowKey: EnvironmentKey {
    static let defaultValue = false
}

private nonisolated struct InWindowGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Materials that would show the desktop through the window blend with the
    /// window's own content instead, for a player drawn inside another window
    /// (the Settings preview).
    nonisolated var humMaterialsStayInWindow: Bool {
        get { self[MaterialsStayInWindowKey.self] }
        set { self[MaterialsStayInWindowKey.self] = newValue }
    }

    /// The content sits inside the window's own Liquid Glass: Title, Text and
    /// Strip on macOS 26 with Liquid Glass, whose window is an
    /// `NSGlassEffectView`. Nothing in
    /// it is glass again (DESIGN.md §3.6); `humMaterial` and `floatingGlass`
    /// draw a `fillQuaternary` fill instead. The styles set it for their own
    /// content and the player's root for its top chrome and HUD.
    nonisolated var isInWindowGlass: Bool {
        get { self[InWindowGlassKey.self] }
        set { self[InWindowGlassKey.self] = newValue }
    }
}
