import SwiftUI

/// The same open ring as Home, sized for the workout header.
struct WorkoutCreatureProgressView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppStore.self) private var store
    let stage: CreatureStage
    let progress: WorkoutEvolutionProgress
    var diameter: CGFloat = 84
    var isPlaying = true

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(NanoTheme.teal.opacity(0.18), style: stroke)
                    .rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: 0.75 * progress.fraction)
                    .stroke(NanoTheme.teal, style: stroke)
                    .rotationEffect(.degrees(135))
                    .animation(reduceMotion || store.reduceMotion ? nil : .easeOut(duration: 0.3),
                               value: progress.fraction)
                if reduceMotion || store.reduceMotion {
                    CreatureArtworkView(stage: stage).padding(diameter * 0.13)
                } else {
                    AnimatedCreatureArtworkView(stage: stage, isPlaying: isPlaying, preloadsAllFrames: false)
                        .padding(diameter * 0.13)
                }
            }
            Text("\(Int(progress.fraction * 100))%")
                .font(.system(size: diameter < 75 ? 10 : 12, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(NanoTheme.teal)
                .padding(.horizontal, 3)
                .background(NanoTheme.background, in: Capsule())
                .offset(y: 2)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage.name)
        .accessibilityValue(progress.accessibilityValue)
    }

    private var stroke: StrokeStyle {
        StrokeStyle(lineWidth: diameter < 75 ? 3.5 : 4.5, lineCap: .round)
    }
}

/// Keep the workout's display anchor across app termination, without changing
/// the Health progression ledger. Only the most recent phone session is kept.
private struct SavedWorkoutEvolutionAnchor: Codable {
    let sessionID: String
    let anchor: WorkoutEvolutionAnchor
}

enum WorkoutEvolutionAnchorStore {
    private static let key = "nanobeasts.workout.evolution-anchor.v1"

    static func save(_ anchor: WorkoutEvolutionAnchor, sessionID: String) {
        if let data = try? JSONEncoder().encode(SavedWorkoutEvolutionAnchor(sessionID: sessionID, anchor: anchor)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load(sessionID: String) -> WorkoutEvolutionAnchor? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(SavedWorkoutEvolutionAnchor.self, from: data),
              saved.sessionID == sessionID else { return nil }
        return saved.anchor
    }
}
