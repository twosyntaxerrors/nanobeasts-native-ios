import SwiftUI

enum NanoAccentPreference {
    private static let key = "nanobeasts.interface-accent.v1"

    static var current: NanoAccent {
        get {
            UserDefaults.standard.string(forKey: key)
                .flatMap(NanoAccent.init(rawValue:))
                ?? .mint
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

/// The user's Appearance choice. Dark is the original look and the default.
enum NanoAppearance: String, CaseIterable, Identifiable {
    case dark, light, system

    static let storageKey = "nanobeasts.appearance.v1"

    var id: Self { self }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        }
    }

    /// `nil` follows the iPhone's own setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

#if canImport(UIKit)
typealias NanoPlatformColor = UIColor
#else
typealias NanoPlatformColor = NSColor
#endif

extension NanoPlatformColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// A deeper, slightly richer tone of the same hue, so bright accents stay
    /// readable on the light palette.
    func deepened(_ factor: CGFloat = 0.58) -> NanoPlatformColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        #if canImport(UIKit)
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        #else
        guard let rgb = usingColorSpace(.deviceRGB) else { return self }
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        #endif
        return NanoPlatformColor(hue: hue, saturation: min(saturation * 1.12, 1),
                                 brightness: brightness * factor, alpha: alpha)
    }
}

extension Color {
    /// Resolves per view: forced-dark screens keep dark values inside a light app.
    static func nano(dark: NanoPlatformColor, light: NanoPlatformColor) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { $0.userInterfaceStyle == .light ? light : dark })
        #else
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .aqua ? light : dark })
        #endif
    }

    /// Bright in Dark; a deeper tone of the same hue in Light.
    static func nanoVivid(_ color: Color, lightFactor: CGFloat = 0.58) -> Color {
        let base = NanoPlatformColor(color)
        return nano(dark: base, light: base.deepened(lightFactor))
    }
}

enum NanoTheme {
    // Light palette: Japanese colours for UI (nuevo.tokyo) — no pure white or black.
    // Shironeri page, Gofuniro cards, Shiraumenezu insets, Shironezu borders, sumi ink.
    static let background = Color.nano(dark: NanoPlatformColor(red: 0.035, green: 0.035, blue: 0.043, alpha: 1),
                                       light: NanoPlatformColor(hex: 0xF3F3F2))
    static let surface = Color.nano(dark: NanoPlatformColor(red: 0.094, green: 0.094, blue: 0.106, alpha: 1),
                                    light: NanoPlatformColor(hex: 0xFFFFFC))
    /// Cards and panels that sit on the page.
    static let panel = Color.nano(dark: NanoPlatformColor(red: 0.063, green: 0.063, blue: 0.075, alpha: 1),
                                  light: NanoPlatformColor(hex: 0xFFFFFC))
    static let elevated = Color.nano(dark: NanoPlatformColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1),
                                     light: NanoPlatformColor(hex: 0xE5E4E6))
    static let border = Color.nano(dark: NanoPlatformColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1),
                                   light: NanoPlatformColor(hex: 0xDCDDDD))
    /// Primary text.
    static let text = Color.nano(dark: .white, light: NanoPlatformColor(hex: 0x1D1E22))
    /// The contrasting base for hairlines, tints and inset fills (use with opacity).
    static let ink = Color.nano(dark: .white, light: NanoPlatformColor(hex: 0x1D1E22))
    static let secondaryText = Color.nano(dark: NanoPlatformColor(red: 0.631, green: 0.631, blue: 0.667, alpha: 1),
                                          light: NanoPlatformColor(hex: 0x5D5F67))
    static let mutedText = Color.nano(dark: NanoPlatformColor(red: 0.322, green: 0.322, blue: 0.357, alpha: 1),
                                      light: NanoPlatformColor(hex: 0x8B8D95))
    /// Shadows read heavy on a light page, so they soften there.
    static let shadow = Color.nano(dark: .black, light: NanoPlatformColor(white: 0.25, alpha: 0.45))

    static var teal: Color { .nanoVivid(NanoAccentPreference.current.color) }
    static var cyan: Color { .nanoVivid(NanoAccentPreference.current.secondaryColor) }
    /// Text and icons placed on an accent fill.
    static let onAccent = Color.nano(dark: .black, light: NanoPlatformColor(hex: 0xFFFFFC))

    static let pink = Color.nanoVivid(Color(red: 0.957, green: 0.447, blue: 0.714), lightFactor: 0.72)
    static let green = Color.nanoVivid(Color(red: 0.525, green: 0.937, blue: 0.675), lightFactor: 0.6)
    static let orange = Color.nanoVivid(Color(red: 0.984, green: 0.467, blue: 0.086), lightFactor: 0.85)
    static let purple = Color.nanoVivid(Color(red: 0.655, green: 0.545, blue: 0.980), lightFactor: 0.72)
    static let danger = Color.nanoVivid(Color(red: 0.937, green: 0.267, blue: 0.267), lightFactor: 0.85)
    static var glow: Color { teal.opacity(0.22) }

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                background,
                NanoAccentPreference.current.backgroundGlow,
                background,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum NanoFont {
    static func aldrich(_ size: CGFloat) -> Font {
        .custom("Aldrich-Regular", size: size)
    }

    static func pixel(_ size: CGFloat) -> Font {
        .custom("PressStart2P-Regular", size: size)
    }

    static func spaceMono(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "SpaceMono-Bold" : "SpaceMono-Regular", size: size)
    }
}

struct NanoCardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(NanoTheme.surface.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(NanoTheme.border, lineWidth: 1)
                    )
            )
    }
}

struct NanoHUDCardModifier: ViewModifier {
    var tint: Color = NanoTheme.teal
    var radius: CGFloat = 22
    var padding: CGFloat = 16
    var illuminated = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: illuminated
                                ? [tint.opacity(0.24), NanoTheme.surface.opacity(0.98), NanoTheme.surface]
                                : [NanoTheme.surface.opacity(0.98), NanoTheme.surface.opacity(0.94)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(tint.opacity(illuminated ? 0.50 : 0.24), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func nanoCard(padding: CGFloat = 18) -> some View {
        modifier(NanoCardModifier(padding: padding))
    }

    func nanoHUDCard(
        tint: Color = NanoTheme.teal,
        radius: CGFloat = 22,
        padding: CGFloat = 16,
        illuminated: Bool = false
    ) -> some View {
        modifier(
            NanoHUDCardModifier(
                tint: tint,
                radius: radius,
                padding: padding,
                illuminated: illuminated
            )
        )
    }
}

struct LabGridBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                var path = Path()
                let spacing: CGFloat = 24

                for x in stride(from: 0, through: size.width, by: spacing) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0, through: size.height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(NanoTheme.teal.opacity(0.035)), lineWidth: 0.7)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
    }
}
