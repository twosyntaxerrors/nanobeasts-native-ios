import SwiftUI

/// Solar Icon Set by 480 Design, CC BY 4.0.
/// Original paths are preserved in Assets.xcassets/Solar; the app applies its tint.
/// https://github.com/480-Design/Solar-Icon-Set
enum SolarIcon: String, CaseIterable {
    case walking, dumbbell, paw, map, stars, target, user, bolt, health, bell
    case magic, book, location, left, right, replay, more, checkCircle
    case closeCircle, clock, danger, play, graph
}

/// Small local vector controls load immediately, including without a connection.
/// Character artwork and animations continue to load from R2.
struct SolarImage: View {
    let icon: SolarIcon
    @ScaledMetric private var size: CGFloat

    init(_ icon: SolarIcon, size: CGFloat = 20) {
        self.icon = icon
        self._size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        Image("Solar-\(icon.rawValue)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
