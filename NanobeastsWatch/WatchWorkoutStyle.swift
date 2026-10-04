import SwiftUI
import Combine

// Appearance is cached separately so the last phone selection works offline.
@MainActor
final class WatchAppearanceStore: ObservableObject {
    static let shared = WatchAppearanceStore()
    @Published private(set) var appearance: WatchInterfaceAppearance?
    private let defaults: UserDefaults

    var color: Color {
        appearance.flatMap { NanoAccent(rawValue: $0.accentName) }?.color
            ?? NanoAccent.mint.secondaryColor
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.data(forKey: WatchInterfaceAppearance.cacheKey)
            .flatMap { try? JSONDecoder().decode(WatchInterfaceAppearance.self, from: $0) }
    }

    func receive(_ data: Data) {
        guard let next = try? JSONDecoder().decode(WatchInterfaceAppearance.self, from: data),
              next.supersedes(appearance) else { return }
        appearance = next
        defaults.set(data, forKey: WatchInterfaceAppearance.cacheKey)
    }
}

private struct WatchAccentKey: EnvironmentKey {
    static let defaultValue = NanoAccent.mint.secondaryColor
}

extension EnvironmentValues {
    var watchAccent: Color {
        get { self[WatchAccentKey.self] }
        set { self[WatchAccentKey.self] = newValue }
    }
}

enum WatchNanoStyle {
    static let surface = Color(red: 0.094, green: 0.094, blue: 0.106)
}

struct WatchCurrentCreature: View {
    @Environment(\.watchAccent) private var accent
    let image: UIImage?
    var size: CGFloat = 48
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2).foregroundStyle(accent.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
    }
}

struct WatchMilestoneView: View {
    @Environment(\.watchAccent) private var accent
    let milestone: WatchWorkoutMilestone
    var image: UIImage? = nil
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    @State private var appeared = false
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 25

    var body: some View {
        Button(action: dismiss) {
            GeometryReader { geometry in
                let artworkSize = min(80, max(48, geometry.size.height * 0.36))
                VStack(spacing: 5) {
                    ZStack {
                        Circle().stroke(accent.opacity(0.35), lineWidth: 2)
                            .frame(width: artworkSize, height: artworkSize)
                            .scaleEffect(appeared ? 1.12 : 0.8)
                        WatchCurrentCreature(image: image, size: artworkSize)
                            .accessibilityHidden(true)
                    }.frame(height: artworkSize + 8)
                    Text(milestone.title).font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(.white)
                    Text(milestone.detail).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Text("Tap to continue").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(6).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WatchNanoStyle.surface)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(milestone.title) \(milestone.detail)")
        .accessibilityHint("Dismiss milestone")
        .onAppear {
            withAnimation(reduceMotion || dimmed ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.24)) { appeared = true }
        }
    }
}
