import SwiftUI

// Value-only preview state: no AppStore, HealthKit, defaults, or purchase writes.
struct TutorialPaywallJourney {
    enum Timing: String, CaseIterable, Identifiable {
        case beforeNextEvolution = "At the next creature’s evolution"
        case afterReveal = "After the reveal"
        case beforeReveal = "Before the reveal"
        var id: Self { self }
        var detail: String {
            switch self {
            case .beforeNextEvolution: "Hatch and mature your tutorial companion, choose a new egg, and hatch its stage-one creature. Its next evolution begins, then pauses before the stage-two reveal for the paywall."
            case .afterReveal: "Meet your first creature, then see the paywall."
            case .beforeReveal: "The video begins, then pauses before your creature appears. Subscribe to reveal it."
            }
        }
    }

    enum Phase: Equatable {
        case walking, charging, paywall, revealing, choosingEgg, receivingEgg, complete
        /// Walking after closing the paywall: steps count for the day and bank,
        /// but the creature waits, ready to evolve, until Pro unlocks it.
        case lockedWalking
    }

    enum Milestone { case tutorialHatch, tutorialMaturity, nextHatch, firstEvolution }

    // The tutorial creature starts appearing shortly after this glowing-egg frame.
    static let videoCheckpoint: TimeInterval = 1.25
    static let evolutionVideoCheckpoint: TimeInterval = 1

    let timing: Timing
    let hatchTarget: Int
    let tutorialMaturityTarget: Int
    private(set) var steps = 0
    private(set) var hasRevealed = false
    private(set) var hasPurchased = false
    private(set) var hasReachedVideoCheckpoint = false
    private(set) var phase: Phase = .walking
    private(set) var milestone: Milestone = .tutorialHatch
    private(set) var familyIndex = 0
    private(set) var stageSteps = 0
    private(set) var hasHatchedNextEgg = false
    private(set) var hasMaturedTutorial = false
    private(set) var hasEvolved = false
    /// Today's steps walked while locked. Like the live app, upgrading the same day
    /// credits them; there is no multi-day bank.
    private(set) var uncountedSteps = 0
    var isEvolutionLocked: Bool { phase == .lockedWalking }
    private var nextHatchTarget = 0
    private var evolutionTarget = 0

    init(timing: Timing, hatchTarget: Int, tutorialMaturityTarget: Int = 500) {
        self.timing = timing
        self.hatchTarget = hatchTarget
        self.tutorialMaturityTarget = tutorialMaturityTarget
    }

    var isLaterTiming: Bool { timing == .beforeNextEvolution }
    var stageIndex: Int {
        switch milestone {
        case .tutorialHatch: hasRevealed ? 1 : 0
        case .tutorialMaturity: 1
        case .nextHatch: 0
        case .firstEvolution: hasEvolved ? 2 : 1
        }
    }
    var target: Int {
        switch milestone {
        case .tutorialHatch: hatchTarget
        case .tutorialMaturity: tutorialMaturityTarget
        case .nextHatch: nextHatchTarget
        case .firstEvolution: evolutionTarget
        }
    }

    mutating func addSteps() {
        if phase == .lockedWalking {
            steps += 1_000
            uncountedSteps += 1_000
            return
        }
        guard phase == .walking else { return }
        let increment = milestone == .tutorialHatch ? 100
            : min(milestone == .tutorialMaturity ? 100 : 1_000, target - stageSteps)
        steps += increment
        stageSteps = min(stageSteps + increment, target)
        if stageSteps >= target {
            phase = .charging
        }
    }

    mutating func finishCharging() {
        guard phase == .charging else { return }
        if isLaterTiming, milestone == .tutorialMaturity {
            hasMaturedTutorial = true
            stageSteps = 0
            phase = .choosingEgg
            return
        }
        phase = .revealing
    }

    mutating func reachVideoCheckpoint() {
        guard timing == .beforeReveal || (isLaterTiming && milestone == .firstEvolution),
              phase == .revealing,
              !hasPurchased, !hasReachedVideoCheckpoint else { return }
        hasReachedVideoCheckpoint = true
        phase = .paywall
    }

    mutating func finishReveal() {
        if isLaterTiming {
            guard phase == .revealing else { return }
            switch milestone {
            case .tutorialHatch:
                hasRevealed = true
                milestone = .tutorialMaturity
                stageSteps = max(steps - hatchTarget, 0)
                phase = .walking
            case .tutorialMaturity:
                return
            case .nextHatch:
                hasHatchedNextEgg = true
                milestone = .firstEvolution
                stageSteps = 0
                phase = .walking
            case .firstEvolution:
                guard hasPurchased else { return }
                hasEvolved = true
                // Upgrading credits today's steps, so they carry into the new stage.
                stageSteps = min(uncountedSteps, max(target - 1, 0))
                uncountedSteps = 0
                phase = .complete
            }
            return
        }
        guard phase == .revealing, timing == .afterReveal || hasPurchased else { return }
        hasRevealed = true
        phase = hasPurchased ? .complete : .paywall
    }

    mutating func purchase() {
        guard phase == .paywall else { return }
        hasPurchased = true
        phase = isLaterTiming ? .revealing : (hasRevealed ? .complete : .revealing)
    }

    mutating func chooseEgg(familyIndex: Int, hatchTarget: Int, evolutionTarget: Int) {
        guard isLaterTiming, hasMaturedTutorial, phase == .choosingEgg, familyIndex > 0,
              hatchTarget > 0, evolutionTarget > 0 else { return }
        self.familyIndex = familyIndex
        nextHatchTarget = hatchTarget
        self.evolutionTarget = evolutionTarget
        milestone = .nextHatch
        stageSteps = 0
        phase = .receivingEgg
    }

    mutating func finishEggArrival() {
        guard phase == .receivingEgg else { return }
        phase = .walking
    }

    /// Closing the paywall goes straight back to walking, with evolution locked.
    mutating func closePaywall() {
        guard phase == .paywall else { return }
        phase = .lockedWalking
    }

    /// The orange badge on Home reopens the paywall from the locked state.
    mutating func openUpgrade() {
        guard phase == .lockedWalking else { return }
        phase = .paywall
    }
}

/// Runs the shipping onboarding and hatch screens against an isolated preview journey.
struct OnboardingReplayView: View {
    private enum Screen { case options, onboarding, app }
    private enum Presentation: String, Identifiable {
        case egg, hatch
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var replayStore = AppStore.makeOnboardingReplay()
    @State private var screen: Screen = .options
    @State private var timing: TutorialPaywallJourney.Timing = .beforeNextEvolution
    @State private var draft = OnboardingDraft()
    @State private var journey = TutorialPaywallJourney(timing: .beforeNextEvolution, hatchTarget: 250)
    @State private var sessionID = UUID()
    @State private var playsFullOnboarding = false
    @State private var selectedTab: AppTab = .lab
    @State private var presentation: Presentation?
    @State private var pendingTour = false
    @State private var showsTour = false
    @State private var showsHealth = false
    @State private var pendingHomeHealth = false
    @State private var showsWorkoutNotice = false

    private var egg: CreatureStage { replayStore.catalog.families[0].stages[0] }
    private var creature: CreatureStage { replayStore.catalog.families[0].stages[1] }
    private var replayFamily: CreatureFamily { replayStore.catalog.families[journey.familyIndex] }
    private var replayRevealStage: CreatureStage {
        replayFamily.stages[journey.milestone == .firstEvolution ? 2 : 1]
    }
    private var replayEggs: [CreatureStage] {
        let eligibleFamilies = replayStore.catalog.families.dropFirst().filter { $0.stages.count > 2 }
        let preferred = replayStore.nextEggCandidates.filter { egg in
            eligibleFamilies.contains { $0.id == egg.familyID }
        }
        let remaining = eligibleFamilies.compactMap { $0.stages.first }.filter { egg in
            !preferred.contains { $0.id == egg.id }
        }
        return Array((preferred + remaining).prefix(3))
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()
            switch screen {
            case .options:
                VStack(spacing: 0) {
                    HStack {
                        Text("ONBOARDING LAB").font(.caption.weight(.semibold))
                        Spacer()
                        Button("Done") { dismiss() }.frame(minHeight: 44)
                    }.padding(.horizontal, 24)
                    options
                }
            case .onboarding:
                OnboardingFlowView(previewDraft: draft, onDraftChanged: { draft = $0 }) { profile in
                    replayStore.saveOnboardingProfile(playerName: profile.playerName,
                        selectedGoals: profile.selectedGoals, primaryGoal: profile.primaryGoal,
                        selectedBlockers: profile.selectedBlockers, dailyGoal: profile.dailyGoal,
                        wantsHealth: profile.wantsHealth, wantsReminders: profile.wantsReminders)
                    beginEggArrival()
                }
                .id(sessionID)
            case .app:
                MainTabView(selectedTab: $selectedTab,
                    openWorkouts: { showsWorkoutNotice = true },
                    defersHomeCelebrations: showsTour || presentation != nil,
                    onHomePresentationChanged: { _ in },
                    onReplayNameTap: addSteps, onReplayUpgradeTap: openUpgrade,
                    onExitReplay: { dismiss() },
                    showsTour: showsTour, onTourFinished: { showsTour = false })
                    .allowsHitTesting(!pendingHomeHealth)
            }
        }
        .environment(replayStore)
        .defaultAppStorage(replayStore.replayPreferences)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .modifier(OnboardingReplayControls(restart: restart, finish: { dismiss() }))
        .fullScreenCover(item: $presentation, onDismiss: continueAfterPresentation) { item in
            Group {
                switch item {
                case .egg:
                    EvolutionLifecycleExperience(catalog: replayStore.catalog,
                        event: CreatureDiscoveryEvent(stage: egg, kind: .eggAcquired),
                        nextEggs: [], allowsDismissal: false, onChooseEgg: nil,
                        dismissesOnCompletion: false,
                        onCompleted: { presentation = nil })
                case .hatch:
                    if journey.isLaterTiming { laterJourney }
                    else { tutorial }
                }
            }
            .environment(replayStore)
            .defaultAppStorage(replayStore.replayPreferences)
            .interactiveDismissDisabled()
            .modifier(OnboardingReplayControls(restart: restart, finish: { dismiss() }))
        }
        .sheet(isPresented: $showsHealth, onDismiss: {
            if screen == .app { showsTour = playsFullOnboarding }
        }) {
            HealthAccessView(onPreviewCompletion: {
                Task {
                    await replayStore.requestHealthAccess()
                    showsHealth = false
                }
            }, onPreviewSkip: { showsHealth = false })
            .environment(replayStore)
            .modifier(OnboardingReplayControls(restart: restart, finish: { dismiss() }))
        }
        .task(id: pendingHomeHealth) {
            guard pendingHomeHealth else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, screen == .app, presentation == nil else { return }
            pendingHomeHealth = false
            showsHealth = true
        }
        .task(id: journey.phase) {
            guard journey.phase == .charging else { return }
            try? await Task.sleep(for: .milliseconds(880))
            guard !Task.isCancelled else { return }
            journey.finishCharging()
            syncProfile()
            presentation = .hatch
        }
        .alert("Onboarding replay", isPresented: $showsWorkoutNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Use your name to simulate walking during this onboarding replay. Workout recording is outside this walkthrough.")
        }
    }

    private var options: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Play first.\nThen decide.")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Compare the first-hatch paywalls with a longer journey to your next creature’s evolution.")
                        .font(.subheadline).foregroundStyle(NanoTheme.secondaryText)
                }
                ForEach(TutorialPaywallJourney.Timing.allCases) { option in
                    Button { timing = option } label: {
                        HStack(spacing: 14) {
                            Image(systemName: timing == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(NanoTheme.teal).font(.title2)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(option.rawValue).font(.headline)
                                Text(option.detail).font(.subheadline)
                                    .foregroundStyle(NanoTheme.secondaryText)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .stroke(timing == option ? NanoTheme.teal : NanoTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(timing == option ? .isSelected : [])
                }
                Label("Tap your name or the creature’s name to add steps: 100 per tap through the tutorial hatch and maturity, then up to 1,000 per tap for your next egg and its stage-two evolution.", systemImage: "hand.tap")
                    .font(.subheadline).foregroundStyle(NanoTheme.secondaryText)
                VStack(spacing: 12) {
                    Button { start(fullOnboarding: true) } label: {
                        Text("Play full onboarding")
                            .font(.headline).frame(maxWidth: .infinity).frame(height: 54)
                            .foregroundStyle(.black).background(NanoTheme.teal, in: Capsule())
                    }.buttonStyle(.plain)
                    Button("Skip setup and start with the tutorial egg") { start(fullOnboarding: false) }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        .tint(NanoTheme.teal)
                    Text("Fresh profile, complete setup, Health introduction, guided tour, and Dex unlocks. Payments and permissions are simulated. Hold anywhere for two seconds to end or restart the replay.")
                        .font(.caption).foregroundStyle(NanoTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
    }



    @ViewBuilder
    private var tutorial: some View {
        switch journey.phase {
        case .revealing:
            EvolutionLifecycleExperience(
                catalog: replayStore.catalog,
                event: CreatureDiscoveryEvent(stage: creature, kind: .hatch),
                nextEggs: [], allowsDismissal: false, onChooseEgg: nil,
                playsPrelude: !journey.hasReachedVideoCheckpoint,
                previewVideoStartTime: journey.hasReachedVideoCheckpoint ? TutorialPaywallJourney.videoCheckpoint : 0,
                previewVideoPauseTime: timing == .beforeReveal && !journey.hasPurchased
                    ? TutorialPaywallJourney.videoCheckpoint : nil,
                onPreviewVideoPause: { journey.reachVideoCheckpoint() },
                previewFinishesAtReveal: timing == .afterReveal,
                dismissesOnCompletion: false,
                onCompleted: {
                    if timing == .beforeReveal {
                        if journey.hasPurchased { presentation = nil }
                        else { journey.reachVideoCheckpoint() }
                    } else { journey.finishReveal(); syncProfile() }
                }
            )
        case .paywall:
            RevenueCatPaywallScreen(playerName: replayStore.playerName,
                selectedGoals: replayStore.onboardingGoals,
                primaryGoal: replayStore.onboardingPrimaryGoal,
                selectedBlockers: replayStore.onboardingBlockers,
                isPreview: true,
                onPreviewPurchase: { journey.purchase(); syncProfile() },
                onPreviewClose: closePaywall,
                previewMilestone: journey.hasRevealed
                    ? "YOU BROUGHT \(creature.name.uppercased()) TO LIFE"
                    : "YOUR FIRST COMPANION IS READY TO HATCH")
        case .complete:
            if timing == .afterReveal {
                EvolutionLifecycleExperience(catalog: replayStore.catalog,
                    event: CreatureDiscoveryEvent(stage: creature, kind: .hatch),
                    nextEggs: [], allowsDismissal: false, onChooseEgg: nil,
                    previewStartsAtDex: true, dismissesOnCompletion: false,
                    onCompleted: { presentation = nil })
            } else {
                Color.clear
            }
        case .walking, .charging, .choosingEgg, .receivingEgg, .lockedWalking:
            Color.clear
        }
    }

    @ViewBuilder
    private var laterJourney: some View {
        switch journey.phase {
        case .revealing:
            EvolutionLifecycleExperience(catalog: replayStore.catalog,
                event: CreatureDiscoveryEvent(stage: replayRevealStage,
                    kind: journey.milestone == .firstEvolution ? .evolution : .hatch),
                nextEggs: [], allowsDismissal: false, onChooseEgg: nil,
                playsPrelude: !journey.hasReachedVideoCheckpoint,
                previewVideoStartTime: journey.hasReachedVideoCheckpoint
                    ? TutorialPaywallJourney.evolutionVideoCheckpoint : 0,
                previewVideoPauseTime: journey.milestone == .firstEvolution && !journey.hasPurchased
                    ? TutorialPaywallJourney.evolutionVideoCheckpoint : nil,
                onPreviewVideoPause: { journey.reachVideoCheckpoint() },
                dismissesOnCompletion: false,
                onCompleted: {
                    if journey.milestone == .firstEvolution, !journey.hasPurchased {
                        journey.reachVideoCheckpoint()
                        return
                    }
                    journey.finishReveal()
                    syncProfile()
                    if journey.phase != .choosingEgg { presentation = nil }
                })
                .id("\(journey.familyIndex)-\(String(describing: journey.milestone))")
        case .choosingEgg, .receivingEgg:
            // Keep the normal maturity → selection → confirmed assignment view mounted
            // while its selection callback updates the isolated replay profile.
            EvolutionLifecycleExperience(catalog: replayStore.catalog,
                event: CreatureDiscoveryEvent(stage: creature, kind: .maturity),
                nextEggs: replayEggs, allowsDismissal: false, onChooseEgg: chooseNextEgg,
                previewEggSelectionDetail: "Choose your next specimen and walk to hatch a new creature. Its identity stays a mystery until it hatches.",
                dismissesOnCompletion: false,
                onCompleted: {
                    journey.finishEggArrival()
                    presentation = nil
                })
                .id("tutorial-maturity")
        case .paywall:
            RevenueCatPaywallScreen(playerName: replayStore.playerName,
                selectedGoals: replayStore.onboardingGoals,
                primaryGoal: replayStore.onboardingPrimaryGoal,
                selectedBlockers: replayStore.onboardingBlockers,
                isPreview: true,
                onPreviewPurchase: { journey.purchase(); syncProfile() },
                onPreviewClose: closePaywall,
                previewMilestone: journey.uncountedSteps > 0
                    ? "TODAY’S \(journey.uncountedSteps.formatted()) STEPS CAN STILL COUNT"
                    : "\(replayFamily.stages[1].name.uppercased()) IS READY TO EVOLVE")
        case .walking, .charging, .complete, .lockedWalking:
            Color.clear
        }
    }

    private func chooseNextEgg(_ egg: CreatureStage) -> Bool {
        guard journey.phase == .choosingEgg,
              let index = replayStore.catalog.families.firstIndex(where: { $0.id == egg.familyID }),
              index > 0, replayStore.catalog.families[index].stages.count > 2 else { return false }
        journey.chooseEgg(familyIndex: index,
            hatchTarget: CreatureProgressionRules.steps(familyIndex: index, stage: 0),
            evolutionTarget: CreatureProgressionRules.steps(familyIndex: index, stage: 1))
        syncProfile()
        return journey.phase == .receivingEgg
    }

    private func syncProfile() {
        replayStore.updateOnboardingReplay(steps: journey.steps,
            revealed: journey.hasRevealed, purchased: journey.hasPurchased,
            familyIndex: journey.familyIndex,
            stageIndex: journey.isLaterTiming ? journey.stageIndex : nil,
            stageSteps: journey.isLaterTiming ? journey.stageSteps : nil,
            tutorialMatured: journey.hasMaturedTutorial,
            evolutionLocked: journey.isEvolutionLocked,
            uncountedSteps: journey.uncountedSteps)
    }

    private func closePaywall() {
        journey.closePaywall()
        syncProfile()
        presentation = nil
    }

    private func openUpgrade() {
        journey.openUpgrade()
        syncProfile()
        presentation = .hatch
    }

    private func addSteps() {
        guard !showsTour, !pendingHomeHealth, !showsHealth, presentation == nil else { return }
        journey.addSteps()
        syncProfile()
    }

    private func beginEggArrival() {
        replayStore.completeOnboarding()
        syncProfile()
        selectedTab = .lab
        pendingTour = playsFullOnboarding
        screen = .app
        presentation = .egg
    }

    private func continueAfterPresentation() {
        if timing == .beforeReveal, journey.phase == .revealing, journey.hasPurchased {
            journey.finishReveal()
            syncProfile()
        }
        guard pendingTour else { return }
        pendingTour = false
        if replayStore.onboardingWantsHealth { pendingHomeHealth = true }
        else { showsTour = true }
    }

    private func restart() {
        journey = TutorialPaywallJourney(timing: timing, hatchTarget: 250)
        pendingTour = false
        pendingHomeHealth = false
        showsTour = false
        showsHealth = false
        presentation = nil
        screen = .options
    }

    private func start(fullOnboarding: Bool) {
        playsFullOnboarding = fullOnboarding
        sessionID = UUID()
        replayStore = AppStore.makeOnboardingReplay()
        journey = TutorialPaywallJourney(timing: timing,
            hatchTarget: CreatureProgressionRules.steps(familyIndex: 0, stage: 0),
            tutorialMaturityTarget: CreatureProgressionRules.steps(familyIndex: 0, stage: 1))
        draft = OnboardingDraft()
        if fullOnboarding { screen = .onboarding }
        else {
            replayStore.saveOnboardingProfile(playerName: "Researcher", selectedGoals: [],
                dailyGoal: draft.recommendedGoal, wantsHealth: false, wantsReminders: false)
            beginEggArrival()
        }
    }
}

/// Hidden replay controls preserve the production viewport and normal button layout.
private struct OnboardingReplayControls: ViewModifier {
    let restart: () -> Void
    let finish: () -> Void
    @State private var showsControls = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(LongPressGesture(minimumDuration: 2).onEnded { _ in
                showsControls = true
            })
            .confirmationDialog("Onboarding replay", isPresented: $showsControls, titleVisibility: .visible) {
                Button("Restart replay", action: restart)
                Button("End replay", action: finish)
                Button("Keep going", role: .cancel) {}
            }
    }
}
