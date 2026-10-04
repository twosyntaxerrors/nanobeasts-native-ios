import SwiftUI

enum NanoAccent: String, Codable, CaseIterable, Identifiable, Sendable {
    case mint
    case pink
    case violet
    case gold
    case green
    case blue

    var id: Self { self }

    var displayName: String {
        switch self {
        case .mint: "Mint"
        case .pink: "Pink"
        case .violet: "Violet"
        case .gold: "Gold"
        case .green: "Green"
        case .blue: "Blue"
        }
    }

    var color: Color {
        switch self {
        case .mint: Color(red: 0.369, green: 0.918, blue: 0.831)
        case .pink: Color(red: 0.957, green: 0.447, blue: 0.714)
        case .violet: Color(red: 0.655, green: 0.545, blue: 0.980)
        case .gold: Color(red: 1.000, green: 0.756, blue: 0.180)
        case .green: Color(red: 0.290, green: 0.855, blue: 0.506)
        case .blue: Color(red: 0.376, green: 0.647, blue: 0.957)
        }
    }

    var secondaryColor: Color {
        switch self {
        case .mint: Color(red: 0.133, green: 0.827, blue: 0.933)
        case .pink: Color(red: 0.804, green: 0.431, blue: 0.980)
        case .violet: Color(red: 0.435, green: 0.600, blue: 1.000)
        case .gold: Color(red: 0.984, green: 0.467, blue: 0.086)
        case .green: Color(red: 0.369, green: 0.918, blue: 0.831)
        case .blue: Color(red: 0.133, green: 0.827, blue: 0.933)
        }
    }

    var backgroundGlow: Color {
        color.opacity(0.11)
    }
}

