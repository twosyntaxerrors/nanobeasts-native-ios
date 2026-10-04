import SwiftUI

/// This presentation never owns or stops a workout recorder.
struct WorkoutMilestoneAction: View {
    enum Source {
        case phone(paused: Bool)
        case watch
    }

    @Environment(AppStore.self) private var store
    @State private var presentedEvent: CreatureDiscoveryEvent?
    let source: Source

    var body: some View {
        VStack(spacing: 7) {
            if let event = store.workoutMilestoneEvent {
                Button {
                    presentedEvent = event
                } label: {
                    Label(title(for: event), systemImage: event.kind == .maturity ? "crown.fill" : "sparkles")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(NanoTheme.background)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(NanoTheme.teal, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the celebration. Your workout stays open.")

                Text(event.kind == .maturity
                     ? "\(store.bankedProgressionSteps.formatted()) steps saved for your next egg"
                     : "Celebrate now or after your walk.")
                    .font(.caption)
                    .foregroundStyle(NanoTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Keep the presentation mounted even when choosing an egg consumes
        // the old event and creates another one from carried-over steps.
        .fullScreenCover(item: $presentedEvent) { event in
            WorkoutLifecycleCover(event: event, source: source)
                .environment(store)
        }
        .onChange(of: store.workoutMilestoneEvent?.id) { _, eventID in
            if eventID != nil, presentedEvent == nil, store.hapticsEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func title(for event: CreatureDiscoveryEvent) -> String {
        switch event.kind {
        case .hatch: "Hatch"
        case .evolution: "Evolve"
        case .maturity: "Choose next egg"
        case .eggAcquired: "Meet your egg"
        }
    }
}

private struct WorkoutLifecycleCover: View {
    @Environment(AppStore.self) private var store
    @StateObject private var bridge = WorkoutWatchBridge.shared
    let event: CreatureDiscoveryEvent
    let source: WorkoutMilestoneAction.Source

    var body: some View {
        EvolutionLifecycleExperience(
            catalog: store.catalog, event: event, nextEggs: store.nextEggCandidates,
            allowsDismissal: true,
            onChooseEgg: { store.chooseNextEgg($0) },
            returnButtonTitle: "BACK TO WORKOUT", workoutContext: true,
            onCompleted: { store.acknowledgeLifecycleEvent(event.id) }
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 4) {
                Label(recordingStatus, systemImage: recordingSymbol)
                    .font(.caption.weight(.semibold))
                if event.kind == .maturity, store.awaitingEggSelection,
                   store.pendingLifecycleEvents.contains(where: { $0.id == event.id }) {
                    Text("\(store.bankedProgressionSteps.formatted()) steps saved for your next egg")
                        .font(.caption2).monospacedDigit()
                }
            }
            .foregroundStyle(NanoTheme.teal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(NanoTheme.background)
        }
    }

    private var recordingSymbol: String {
        switch source {
        case .phone(let paused): paused ? "pause.circle" : "figure.walk"
        case .watch: "applewatch"
        }
    }

    private var recordingStatus: String {
        switch source {
        case .phone(let paused):
            return paused ? "Workout paused" : "Your workout is still recording"
        case .watch:
            guard let snapshot = bridge.snapshot else { return "Apple Watch workout" }
            switch snapshot.phase {
            case .running: return "Your Watch is still recording"
            case .paused: return "Watch workout paused"
            case .saving: return "Saving your Watch workout"
            case .finished: return "Watch workout finished"
            case .failed: return "Check your Watch for workout details"
            }
        }
    }
}
