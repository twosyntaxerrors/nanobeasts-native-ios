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

enum NanoTheme {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.043)
    static let surface = Color(red: 0.094, green: 0.094, blue: 0.106)
    static let elevated = Color(red: 0.153, green: 0.153, blue: 0.165)
    static var teal: Color { NanoAccentPreference.current.color }
    static var cyan: Color { NanoAccentPreference.current.secondaryColor }
    static let pink = Color(red: 0.957, green: 0.447, blue: 0.714)
    static let green = Color(red: 0.525, green: 0.937, blue: 0.675)
    static let orange = Color(red: 0.984, green: 0.467, blue: 0.086)
    static let purple = Color(red: 0.655, green: 0.545, blue: 0.980)
    static let danger = Color(red: 0.937, green: 0.267, blue: 0.267)
    static let secondaryText = Color(red: 0.631, green: 0.631, blue: 0.667)
    static let mutedText = Color(red: 0.322, green: 0.322, blue: 0.357)
    static let border = elevated
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
