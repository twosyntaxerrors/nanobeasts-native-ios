import SwiftUI

/// Replays the opening demo for users who skipped it before onboarding.
struct OnboardingDailyLoopPreview: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnScreen = false
    @State private var videoState = DemoVideoState.loading
    @State private var secondsRemaining: Int?

    private var reduceMotion: Bool { systemReduceMotion || store.reduceMotion }

    var body: some View {
        RemoteLoopingVideoView(
            url: OnboardingDemoMedia.url,
            isPlaying: isOnScreen && scenePhase == .active && !reduceMotion,
            state: $videoState,
            onSecondsRemaining: { secondsRemaining = $0 }
        )
            .aspectRatio(OnboardingDemoMedia.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if videoState == .loading {
                    ProgressView().tint(NanoTheme.teal)
                } else if videoState == .ready, let secondsRemaining, !reduceMotion {
                    DemoCountdownOverlay(seconds: secondsRemaining)
                }
            }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Nanobeasts core loop demo")
        .accessibilityHint("Walk to hatch an egg, unlock its Field Dex entry, and earn badges.")
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }
}

struct OnboardingPlanView: View {
    @Binding var page: WalkingPlanPage
    let comparison: WalkingPlanComparison
    let selectedGoals: Set<String>
    let primaryGoal: String?
    let selectedBlockers: Set<String>
    let playerName: String
    let evolutionChallenge: WalkingEvolutionChallenge?
    var journey: WalkingJourneyProjection? = nil
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var replayID = 0

    private var motionDisabled: Bool { reduceMotion || store.reduceMotion }
    private var firstName: String { playerName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "" }
    private var copy: OnboardingCopy { .forGoals(selectedGoals, primaryGoal: primaryGoal, blockers: selectedBlockers) }
    private var opening: (headline: String, detail: String) {
        copy.planOpening(blockers: selectedBlockers)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: goBack) {
                    SolarImage(.left)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.06), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel(page == .target ? "Back to your answers" : "Back to your daily target")
                Spacer()
                Text("YOUR WALKING PLAN").font(NanoFont.aldrich(10)).tracking(1.6).foregroundStyle(NanoTheme.teal)
                Spacer()
                Button { replayID += 1 } label: {
                    SolarImage(.replay).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("Replay your plan animation").disabled(motionDisabled)
            }.padding(.horizontal, 20).padding(.vertical, 8)

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 10) {
                            Text(firstName.isEmpty || firstName == "Researcher" ? "Built around your answers" : "Built for \(firstName)")
                                .font(.caption.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text("\(page.position + 1) OF \(WalkingPlanPage.allCases.count)")
                                .font(.caption2.monospacedDigit()).foregroundStyle(NanoTheme.teal)
                        }
                        FinitePlanReveal(replayID: replayID, reduceMotion: motionDisabled) { elapsed in
                            WalkingPlanPageContent(page: page, comparison: comparison, headline: opening.headline,
                                detail: opening.detail, comparisonHeadline: copy.comparisonTitle,
                                tint: NanoTheme.teal, elapsed: elapsed, benefits: copy.paywallBenefits,
                                evolutionChallenge: evolutionChallenge, comparisonDetail: copy.comparisonDetail,
                                journey: journey, emphasizesBody: copy.emphasizesBody,
                                milestoneArtwork: milestoneArtwork)
                        }
                        .id(page)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 18)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                }
                .id(page)
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(page == .target ? "SEE WHERE THIS TAKES YOU" : "LET’S MAKE IT HAPPEN", action: advance)
                    .font(NanoFont.aldrich(13)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(LinearGradient(colors: [NanoTheme.teal, NanoTheme.cyan], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 18))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
                    .background(NanoTheme.background)
            }
        }
        .background(NanoTheme.background)
    }
    /// Real creatures you'll meet at each milestone, kept as silhouettes so they stay a surprise.
    private func milestoneArtwork(_ creature: Int) -> AnyView? {
        let creatures = store.catalog.discoveredCreatures
        guard creature > 0, creature <= creatures.count else { return nil }
        return AnyView(CreatureArtworkView(stage: creatures[creature - 1], isLocked: true))
    }

    private func advance() {
        if let next = page.next { setPage(next) } else { onContinue() }
    }

    private func goBack() {
        if let previous = page.previous { setPage(previous) } else { onBack() }
    }

    private func setPage(_ next: WalkingPlanPage) {
        withAnimation(motionDisabled ? nil : .easeOut(duration: 0.22)) { page = next }
    }

}

struct OnboardingPreparationView: View {
    let playerName: String
    let goal: String?
    let onBack: () -> Void
    let onComplete: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var elapsed: TimeInterval = 0
    @State private var completed = false

    private struct Run: Equatable {
        let active: Bool
        let reduceMotion: Bool
    }
    private var run: Run { .init(active: scenePhase == .active, reduceMotion: reduceMotion || store.reduceMotion) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    SolarImage(.left).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Back to your answers")
                Spacer()
                Text("BUILDING YOUR PLAN").font(NanoFont.aldrich(10)).tracking(1.6)
                    .foregroundStyle(NanoTheme.teal)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }.padding(.horizontal, 20)
            GeometryReader { geometry in
                ScrollView {
                    WalkingPlanPreparationContent(playerName: playerName,
                        goal: goal, tint: NanoTheme.teal,
                        elapsed: elapsed, reduceMotion: run.reduceMotion)
                        .padding(24)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }.scrollIndicators(.hidden)
            }
        }
        .background(NanoTheme.background)
        .task(id: run) {
            guard run.active, !completed else { return }
            let finished = await WalkingPlanPreparation.play(from: elapsed, reduceMotion: run.reduceMotion) { elapsed = $0 }
            guard finished, !Task.isCancelled, scenePhase == .active, !completed else { return }
            completed = true
            onComplete()
        }
    }
}

private struct FinitePlanReveal<Content: View>: View {
    let replayID: Int
    let reduceMotion: Bool
    @ViewBuilder let content: (TimeInterval) -> Content
    @Environment(\.scenePhase) private var scenePhase
    // A view which hasn't started its task displays valid results, never zeros.
    @State private var elapsed = WalkingPlanReveal.duration

    private struct Run: Equatable {
        let replay: Int
        let immediate: Bool
    }

    var body: some View {
        content(reduceMotion ? WalkingPlanReveal.duration : elapsed)
            .task(id: Run(replay: replayID, immediate: reduceMotion || scenePhase != .active)) {
                await WalkingPlanReveal.play(reduceMotion: reduceMotion || scenePhase != .active) { elapsed = $0 }
            }
    }
}
