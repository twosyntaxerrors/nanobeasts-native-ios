import Combine
import ActivityKit
import SwiftUI
import StoreKit

enum AppTab: Hashable {
    case lab
    case stats
    case dex
    case settings
}

private enum AppSheet: Identifiable {
    case onboardingPaywall
    case health

    var id: String {
        switch self {
        case .onboardingPaywall: "onboarding-paywall"
        case .health: "health"
        }
    }
}

private enum AppWorkoutPresentation: Identifiable {
    case new
    case resume(sessionID: String)

    var id: String {
        switch self {
        case .new: "new-workout"
        case let .resume(sessionID): "active-workout-\(sessionID)"
        }
    }

    var sessionID: String? {
        guard case let .resume(sessionID) = self else { return nil }
        return sessionID
    }
}

struct AppRootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @AppStorage("nanobeasts.didCompleteAppTour") private var didCompleteAppTour = false
    @State private var selectedTab: AppTab = .lab
    @State private var activeSheet: AppSheet?
    @State private var workoutPresentation: AppWorkoutPresentation?
    @State private var completesOnboardingAfterPaywall = false
    @State private var showsOnboardingPaywall = false
    @State private var onboardingResumeID = UUID()
    @State private var paywallWasBackgrounded = false
    private var subscriptionIsReady: Bool {
        store.hasResolvedInitialSubscription || AppScreenshotScenario.active != nil
    }
    private var hasAppAccess: Bool {
        subscriptionIsReady && store.onboardingCompleted && store.isPremium
    }
    @State private var activeEvolutionEvent: CreatureDiscoveryEvent?
    @State private var presentedLifecycleEventID: UUID?
    @State private var presentedLifecycleEventKind: CreatureDiscoveryKind?
    @State private var activeBadgeAward: StatsBadge?
    @State private var requestedBadgeID: String?
    @State private var homePresentationIsBusy = false
    @State private var showsAppTour = false
    @State private var appTourPendingAfterHealth = false
    @State private var onboardingContinuationPending = false
    @State private var showsLaunchSplash = true
    @State private var reviewRequestPending = false
    @State private var showsScreenshotBadgeCollection =
        AppScreenshotScenario.active == .badges
            || AppScreenshotScenario.active == .collectionBadges
            || AppScreenshotScenario.active == .featureTourBadges

    init() {
        switch AppScreenshotScenario.active {
        case .badges, .collectionBadges, .featureTourBadges, .featureTourStats,
             .stats, .insights:
            _selectedTab = State(initialValue: .stats)
        case .dex, .dexDetail, .featureTourDex:
            _selectedTab = State(initialValue: .dex)
        case .evolution, .finalEvolution, .eggSelection, .tutorialLoop,
             .featureTourHome, nil:
            break
        }
        if AppScreenshotScenario.active != nil {
            _showsLaunchSplash = State(initialValue: false)
        }
    }

    var body: some View {
        ZStack {
            MainTabView(
                selectedTab: $selectedTab,
                openWorkouts: { if hasAppAccess { workoutPresentation = .new } },
                defersHomeCelebrations: activeBadgeAward != nil || activeEvolutionEvent != nil,
                onHomePresentationChanged: { homePresentationIsBusy = $0 },
                showsTour: hasAppAccess && showsAppTour,
                onTourFinished: {
                    didCompleteAppTour = true
                    showsAppTour = false
                }
            )
                .id(store.interfaceAccent)
                .opacity(hasAppAccess ? 1 : 0)
                .allowsHitTesting(hasAppAccess)
                .accessibilityHidden(!hasAppAccess)

            if !store.onboardingCompleted {
                OnboardingFlowView(onFinished: showOnboardingPaywall)
                    .id(onboardingResumeID)
                    .transition(.opacity)
            }

            if store.onboardingCompleted, !subscriptionIsReady {
                ZStack {
                    NanoTheme.background.ignoresSafeArea()
                    ProgressView("Checking subscription…")
                        .tint(NanoTheme.teal)
                }
            }

            if store.onboardingCompleted, subscriptionIsReady, !store.isPremium {
                SubscriptionReturnView { showsOnboardingPaywall = true }
                    .transition(.opacity)
            }

            if showsLaunchSplash {
                NanobeastsLaunchSplash {
                    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)) {
                        showsLaunchSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: store.onboardingCompleted)
        .task {
            // Repair older Watch/Health routes before opening any workout UI.
            // This also makes the recovered territory durable on first launch.
            WorkoutLocationTracker.shared.restoreSavedTerritory(await WorkoutHistoryStore().loadSavedTerritoryRoutes())
            await bootstrap()
            WorkoutWatchBridge.shared.updateCompanion(store.workoutCompanionStage, dailyGoal: store.dailyGoal, evolution: store.workoutCompanionProgress)
            presentPendingWorkoutNotificationIfNeeded()
            presentActiveWorkoutIfNeeded()
            await WorkoutHistoryStore().refreshHealthTotals()
        }
        .task { await store.observeSubscriptionUpdates() }
        .task(id: rewardPresentationState) {
            guard rewardPresentationState.isReady else { return }
            // Native dismissals finish before another presentation is requested.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, rewardPresentationState.isReady else { return }
            queueNewBadgeAwards()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: WorkoutInactivityResponseStore.didChangeNotification
            )
        ) { _ in
            presentPendingWorkoutNotificationIfNeeded()
        }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "nanobeasts" else { return }
            guard hasAppAccess else { return }
            switch url.host?.lowercased() {
            case "stats":
                selectedTab = .stats
            case "dex":
                selectedTab = .dex
            case "settings":
                selectedTab = .settings
            case "badge":
                selectedTab = .lab
                requestedBadgeID = url.pathComponents.dropFirst().first
                scheduleNextQueuedExperience()
            case "workout":
                let components = Array(url.pathComponents.dropFirst())
                guard components.first == "session", components.count > 1 else {
                    selectedTab = .lab
                    workoutPresentation = .new
                    return
                }
                selectedTab = .lab
                showsLaunchSplash = false
                workoutPresentation = .resume(sessionID: components[1])
            default:
                selectedTab = .lab
            }
        }
        .onChange(of: store.onboardingCompleted) {
            guard !store.onboardingCompleted else { return }
            selectedTab = .lab
            showsAppTour = false
            appTourPendingAfterHealth = false
            onboardingContinuationPending = false
            activeSheet = nil
            activeEvolutionEvent = nil
            presentedLifecycleEventID = nil
            presentedLifecycleEventKind = nil
            activeBadgeAward = nil
            requestedBadgeID = nil
            reviewRequestPending = false
            didCompleteAppTour = false
            showsLaunchSplash = true
        }
        .onChange(of: store.dailyGoal) {
            WorkoutWatchBridge.shared.updateCompanion(store.workoutCompanionStage, dailyGoal: store.dailyGoal, evolution: store.workoutCompanionProgress)
            queueNewBadgeAwards()
        }
        .onChange(of: store.currentStage.id) {
            WorkoutWatchBridge.shared.updateCompanion(store.workoutCompanionStage, dailyGoal: store.dailyGoal, evolution: store.workoutCompanionProgress)
            queueNewBadgeAwards()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                paywallWasBackgrounded = showsOnboardingPaywall
                let draft = OnboardingDraft.load()
                Task { await NanoNotifications.shared.scheduleOnboardingReminders(
                    name: draft.playerName, planReady: draft.reachedPaywall,
                    completed: store.onboardingCompleted, premium: store.isPremium) }
            }
            if phase == .active {
                if paywallWasBackgrounded, !store.isPremium {
                    showsOnboardingPaywall = false
                    onboardingResumeID = UUID()
                }
                paywallWasBackgrounded = false
                Task { await store.refreshSubscriptionStatus(forceRefresh: true) }
                WorkoutWatchBridge.shared.updateCompanion(store.workoutCompanionStage, dailyGoal: store.dailyGoal, evolution: store.workoutCompanionProgress)
                Task { await WorkoutHealthSync.shared.refresh() }
                if !store.isLoading, !store.isSyncingSteps {
                    Task { await store.refreshHealthData() }
                }
            }
        }
        .onReceive(WorkoutWatchBridge.shared.$snapshot) { snapshot in
            guard let snapshot, snapshot.phase != .failed else { return }
            store.creditRecordedWorkoutSteps(snapshot.steps, anchor: snapshot.evolutionAnchor,
                startedAt: snapshot.startedAt, observedAt: snapshot.updatedAt)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            Task { await store.refreshSubscriptionStatus() }
        }
        .onChange(of: store.isPremium) {
            if store.isPremium {
                NanoNotifications.shared.cancelOnboardingReminders()
                if !store.onboardingCompleted, OnboardingDraft.load().reachedPaywall {
                    completesOnboardingAfterPaywall = true
                    if showsOnboardingPaywall { showsOnboardingPaywall = false }
                    else { handlePaywallDismissed() }
                }
            } else {
                showsAppTour = false
                activeEvolutionEvent = nil
                activeBadgeAward = nil
            }
        }
        .onChange(of: store.evolutionEventID) {
            presentNextLifecycleEventIfPossible()
        }
        .onChange(of: store.badgeEvaluationID) {
            queueNewBadgeAwards()
        }
        .fullScreenCover(isPresented: $showsOnboardingPaywall, onDismiss: handlePaywallDismissed) {
            RevenueCatPaywallScreen(playerName: store.playerName, selectedGoals: store.onboardingGoals, primaryGoal: store.onboardingPrimaryGoal, selectedBlockers: store.onboardingBlockers)
        }
        .fullScreenCover(item: $workoutPresentation) { presentation in
            WorkoutView(resumingSessionID: presentation.sessionID)
                .environment(store)
        }
        .fullScreenCover(item: $activeEvolutionEvent, onDismiss: lifecyclePresentationDismissed) { event in
            EvolutionLifecycleExperience(
                catalog: store.catalog,
                event: event,
                nextEggs: store.nextEggCandidates,
                allowsDismissal: false,
                onChooseEgg: { egg in
                    store.chooseNextEgg(egg)
                },
                automaticallyAdvances:
                    AppScreenshotScenario.active == .tutorialLoop
                    || AppScreenshotScenario.active == .featureTourHome
            )
            .environment(store)
        }
        .fullScreenCover(item: $activeBadgeAward, onDismiss: badgePresentationDismissed) { badge in
            BadgeAwardCelebrationView(
                badge: badge,
                onAcknowledged: {
                    store.markBadgeAwardPresented(badge.id)
                    // Dismiss through the binding as well as the environment
                    // dismiss action so the parent cannot immediately present
                    // the same award again while the cover is winding down.
                    activeBadgeAward = nil
                }
            )
            .environment(store)
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $showsScreenshotBadgeCollection) {
            BadgeCollectionView(
                sections: screenshotBadgeSections,
                highlightBadgeID:
                    AppScreenshotScenario.active == .featureTourBadges
                        ? "collection-25"
                        : nil
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $activeSheet, onDismiss: presentPendingAppTour) { sheet in
            switch sheet {
            case .onboardingPaywall:
                EmptyView()
            case .health:
                HealthAccessView()
                    .environment(store)
            }
        }
    }

    private func showOnboardingPaywall(_ profile: OnboardingProfile) {
        store.saveOnboardingProfile(
            playerName: profile.playerName,
            selectedGoals: profile.selectedGoals,
            primaryGoal: profile.primaryGoal,
            selectedBlockers: profile.selectedBlockers,
            dailyGoal: profile.dailyGoal,
            wantsHealth: profile.wantsHealth,
            wantsReminders: profile.wantsReminders
        )
        completesOnboardingAfterPaywall = true
        didCompleteAppTour = false
        if store.isPremium { handlePaywallDismissed() }
        else { showsOnboardingPaywall = true }
    }

    private func handlePaywallDismissed() {
        guard completesOnboardingAfterPaywall else { return }
        completesOnboardingAfterPaywall = false
        guard store.isPremium else {
            onboardingResumeID = UUID()
            return
        }
        guard !store.onboardingCompleted else { return }
        store.completeOnboarding()
        onboardingContinuationPending = store.awardInitialResearchEggIfNeeded()

        guard onboardingContinuationPending else {
            continueAfterInitialEggAssignment()
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            presentNextLifecycleEventIfPossible()
        }
    }

    private func continueAfterInitialEggAssignment() {
        guard store.onboardingWantsHealth, !store.hasRequestedHealthAccess else {
            Task { await store.activateJourneyTracking() }
            presentAppTourIfNeeded()
            return
        }
        selectedTab = .lab
        appTourPendingAfterHealth = true
        Task { @MainActor in
            // Let Home and the tutorial egg settle before explaining step access.
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, hasAppAccess, !store.hasRequestedHealthAccess else { return }
            activeSheet = .health
        }
    }

    private func presentPendingAppTour() {
        guard appTourPendingAfterHealth else { return }
        appTourPendingAfterHealth = false
        Task { await store.activateJourneyTracking() }
        presentAppTourIfNeeded()
    }

    private func presentAppTourIfNeeded() {
        guard hasAppAccess, !didCompleteAppTour else { return }
        selectedTab = .lab
        withAnimation(.easeOut(duration: 0.28)) {
            showsAppTour = true
        }
    }

    private func bootstrap() async {
        await store.bootstrap()
        if store.isPremium, !store.onboardingCompleted, OnboardingDraft.load().reachedPaywall {
            completesOnboardingAfterPaywall = true
            handlePaywallDismissed()
        }
        guard hasAppAccess else { return }
        if
            store.onboardingCompleted,
            !didCompleteAppTour,
            store.pendingLifecycleEvents.first?.kind == .eggAcquired
        {
            onboardingContinuationPending = true
        }
        presentNextLifecycleEventIfPossible()
        queueNewBadgeAwards()

        if AppScreenshotScenario.active == .tutorialLoop {
            await runTutorialLoopRecording()
            return
        }

        guard !onboardingContinuationPending else { return }
        guard
            store.onboardingCompleted,
            store.onboardingWantsHealth,
            !store.hasRequestedHealthAccess,
            store.healthState != .unavailable
        else {
            return
        }
        activeSheet = .health
    }

    private func presentPendingWorkoutNotificationIfNeeded() {
        guard
            hasAppAccess,
            workoutPresentation == nil,
            let response = WorkoutInactivityResponseStore.load()
        else { return }
        selectedTab = .lab
        showsLaunchSplash = false
        workoutPresentation = .resume(sessionID: response.sessionID)
    }

    private func presentActiveWorkoutIfNeeded() {
        guard hasAppAccess, workoutPresentation == nil else { return }
        let liveSessionID = Activity<WorkoutActivityAttributes>.activities.first(where: {
            !$0.content.state.isComplete
        })?.attributes.sessionID
        guard let sessionID = liveSessionID
                ?? WorkoutLocationTracker.persistedActiveSessionID
        else { return }

        selectedTab = .lab
        showsLaunchSplash = false
        workoutPresentation = .resume(sessionID: sessionID)
    }

    private var currentBadgeSections: [StatsBadgeSection] {
        let discoveredStages = store.catalog.creatureStages.filter {
            store.isDiscovered($0) || store.isCurrent($0)
        }
        return StatsBadgeCatalog.make(
            records: store.badgeEvaluationHistory,
            dailyGoal: store.dailyGoal,
            dailyGoalHistory: store.dailyGoalHistory,
            discoveredStages: discoveredStages,
            distanceUnit: store.distanceUnit,
            discoveryEvents: store.discoveryEvents
        )
    }

    private var screenshotBadgeSections: [StatsBadgeSection] {
        guard
            AppScreenshotScenario.active == .collectionBadges
                || AppScreenshotScenario.active == .featureTourBadges
        else {
            return currentBadgeSections
        }
        guard let collection = currentBadgeSections.first(where: { $0.id == "collection" })
        else {
            return currentBadgeSections
        }
        return [collection] + currentBadgeSections.filter { $0.id != "collection" }
    }

    private func runTutorialLoopRecording() async {
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }

        for _ in 0..<10 {
            await store.addTestingSteps(25)
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
        }
        await waitForRecordedLifecycleToFinish()

        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }

        for _ in 0..<20 {
            await store.addTestingSteps(25)
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
        }
        await waitForRecordedLifecycleToFinish()
    }

    private func waitForRecordedLifecycleToFinish() async {
        var observedLifecycle = false
        for _ in 0..<240 {
            if !store.pendingLifecycleEvents.isEmpty || activeEvolutionEvent != nil {
                observedLifecycle = true
            }
            if
                observedLifecycle,
                store.pendingLifecycleEvents.isEmpty,
                activeEvolutionEvent == nil
            {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
    }

    private func presentNextLifecycleEventIfPossible() {
        guard
            rewardPresentationState.isReady,
            let event = store.pendingLifecycleEvents.first
        else {
            return
        }
        presentedLifecycleEventID = event.id
        presentedLifecycleEventKind = event.kind
        activeEvolutionEvent = event
    }

    private func lifecyclePresentationDismissed() {
        if presentedLifecycleEventKind == .maturity,
           store.pendingLifecycleEvents.contains(where: { $0.id == presentedLifecycleEventID }) {
            // Selection consumes its specific maturity event atomically. A new
            // lineage may already be mature after releasing saved steps.
            presentedLifecycleEventID = nil
            presentedLifecycleEventKind = nil
            activeEvolutionEvent = nil
            scheduleNextQueuedExperience()
            return
        }

        let completedInitialEggAssignment =
            presentedLifecycleEventKind == .eggAcquired && !didCompleteAppTour
        if let presentedLifecycleEventKind,
           store.recordLifecycleCompletionForReview(presentedLifecycleEventKind) {
            reviewRequestPending = true
        }
        if let presentedLifecycleEventID {
            store.acknowledgeLifecycleEvent(presentedLifecycleEventID)
        }
        presentedLifecycleEventID = nil
        presentedLifecycleEventKind = nil
        activeEvolutionEvent = nil
        if
            (onboardingContinuationPending || completedInitialEggAssignment),
            store.pendingLifecycleEvents.isEmpty
        {
            onboardingContinuationPending = false
            continueAfterInitialEggAssignment()
            return
        }
        scheduleNextQueuedExperience()
    }

    private func queueNewBadgeAwards() {
        // Derive pending awards from earned badges and persisted acknowledgements.
        // A failed/blocked presentation can no longer consume an in-memory queue.
        presentNextQueuedExperience()
    }

    private var rewardPresentationState: RewardPresentationState {
        RewardPresentationState(
            hasAccess: hasAppAccess, isHome: selectedTab == .lab,
            isActive: scenePhase == .active, isLoading: store.isLoading,
            showsSplash: showsLaunchSplash, showsTour: showsAppTour,
            showsWorkout: workoutPresentation != nil, showsSheet: activeSheet != nil,
            homeIsBusy: homePresentationIsBusy, showsPaywall: showsOnboardingPaywall,
            showsEvolution: activeEvolutionEvent != nil, showsBadge: activeBadgeAward != nil
        )
    }

    private func badgePresentationDismissed() {
        // Clear the item binding before scheduling another reward. Keeping the
        // dismissed badge in the item binding can immediately re-present the
        // same full-screen cover on iOS, trapping the user on Home.
        activeBadgeAward = nil
        scheduleNextQueuedExperience()
    }

    private func scheduleNextQueuedExperience() {
        Task { @MainActor in
            // Let the outgoing full-screen cover finish before presenting the
            // next queued lifecycle or achievement experience.
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            presentNextQueuedExperience()
        }
    }

    private func presentNextQueuedExperience() {
        guard rewardPresentationState.isReady else { return }
        if !store.pendingLifecycleEvents.isEmpty {
            presentNextLifecycleEventIfPossible()
            return
        }
        let badges = currentBadgeSections.flatMap(\.badges)
        store.repairLegacyBadgeAcknowledgements(unlockedIDs: Set(badges.filter(\.unlocked).map(\.id)))
        if let requestedBadgeID {
            self.requestedBadgeID = nil
            if let badge = badges.first(where: { $0.id == requestedBadgeID && $0.unlocked }) {
                activeBadgeAward = badge
                return
            }
        }
        let pendingIDs = BadgeAwardDelivery.pendingIDs(badges.map {
            .init(id: $0.id, completedAt: $0.completedAt, unlocked: $0.unlocked,
                  acknowledged: store.hasPresentedBadgeAward($0.id))
        })
        if AppScreenshotScenario.active == nil, let nextID = pendingIDs.first,
           let badge = badges.first(where: { $0.id == nextID }) {
            activeBadgeAward = badge
            return
        }
        guard reviewRequestPending else { return }
        reviewRequestPending = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            guard store.onboardingCompleted else { return }
            requestReview()
        }
    }
}

enum AppTourTarget: Hashable {
    case ring, expBadge, streak, week, todaySteps, metrics, workout, stats, badges, dex, settingsGoal
    case statsTab, dexTab, settingsTab

    var navigationTabTarget: Self? {
        switch self {
        case .stats, .badges: .statsTab
        case .dex: .dexTab
        case .settingsGoal: .settingsTab
        default: nil
        }
    }
}

struct AppTourAnchors: PreferenceKey {
    static var defaultValue: [AppTourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [AppTourTarget: Anchor<CGRect>],
                       nextValue: () -> [AppTourTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct AppTourFocusKey: EnvironmentKey {
    static let defaultValue: AppTourTarget? = nil
}

extension EnvironmentValues {
    var appTourFocus: AppTourTarget? {
        get { self[AppTourFocusKey.self] }
        set { self[AppTourFocusKey.self] = newValue }
    }
}

extension View {
    func appTourTarget(_ target: AppTourTarget?) -> some View {
        anchorPreference(key: AppTourAnchors.self, value: .bounds) { anchor in
            target.map { [$0: anchor] } ?? [:]
        }
    }
}

/// Place the card in the larger clear region, never over the highlighted content.
struct AppTourPlacement {
    let card: CGRect
    let target: CGRect

    init(viewport: CGSize, targets: [CGRect], preferredHeight: CGFloat, avoiding: [CGRect] = []) {
        let margin: CGFloat = 16
        let gap: CGFloat = 14
        guard !targets.isEmpty else { target = .zero; card = .zero; return }
        target = targets.reduce(CGRect.null) { $0.union($1) }
        if !avoiding.isEmpty {
            // The tab is a separate highlight, not part of the component's pointer target.
            // Find room between the component and tab as well as above or below them.
            let obstacles = (targets + avoiding).sorted { $0.minY < $1.minY }
            var cursor = margin
            var spaces: [CGRect] = []
            let width = max(0, viewport.width - margin * 2)
            for obstacle in obstacles {
                let end = min(obstacle.minY - gap, viewport.height - margin)
                if end > cursor {
                    spaces.append(CGRect(x: margin, y: cursor, width: width, height: end - cursor))
                }
                cursor = max(cursor, obstacle.maxY + gap)
            }
            if cursor < viewport.height - margin {
                spaces.append(CGRect(x: margin, y: cursor, width: width,
                                     height: viewport.height - margin - cursor))
            }
            let targetBottom = target.maxY
            let space = spaces.first(where: { $0.minY >= targetBottom && $0.height >= preferredHeight })
                ?? spaces.max(by: { $0.height < $1.height })
                ?? .zero
            let height = min(preferredHeight, space.height)
            let y = space.maxY <= target.minY ? space.maxY - height : space.minY
            card = CGRect(x: space.minX, y: y, width: space.width, height: height)
            return
        }
        let above = max(0, target.minY - margin - gap)
        let below = max(0, viewport.height - margin - target.maxY - gap)
        let goesBelow = below >= preferredHeight || below >= above
        let height = min(preferredHeight, goesBelow ? below : above)
        let y = goesBelow ? target.maxY + gap : target.minY - gap - height
        card = CGRect(x: margin, y: y, width: max(0, viewport.width - margin * 2), height: height)
    }
}

private struct AppTourScrim: Shape {
    let holes: [CGRect]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect.insetBy(dx: -100, dy: -100))
        for hole in holes {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: 16, height: 16))
        }
        return path
    }
}

private struct AppTourPointer: Shape {
    let card: CGRect
    let target: CGRect
    func path(in rect: CGRect) -> Path {
        let above = card.maxY < target.minY
        let x = min(max(target.midX, card.minX + 22), card.maxX - 22)
        let start = CGPoint(x: x, y: above ? card.maxY : card.minY)
        let tip = CGPoint(x: x, y: above ? target.minY - 2 : target.maxY + 2)
        let direction: CGFloat = above ? -1 : 1
        var path = Path()
        path.move(to: start)
        path.addLine(to: tip)
        path.move(to: CGPoint(x: x - 4, y: tip.y + direction * 5))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: x + 4, y: tip.y + direction * 5))
        return path
    }
}

struct AppTourOverlay: View {
    @Binding var selectedTab: AppTab
    let frames: [AppTourTarget: CGRect]
    let onFocusChanged: (AppTourTarget?) -> Void
    let onFinished: () -> Void
    var highlightsNavigationTabs = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var cardHasFocus: Bool
    @State private var step = 0

    private struct Page {
        let tab: AppTab
        let targets: [AppTourTarget]
        let label: String
        let title: String
        let copy: String
    }

    private let pages: [Page] = [
        .init(tab: .lab, targets: [.ring], label: "YOUR NANOBEAST",
              title: "Your steps help it grow.",
              copy: "This ring fills as you walk toward your Nanobeast’s next hatch or evolution."),
        .init(tab: .lab, targets: [.expBadge], label: "EXP & NEXT MILESTONE",
              title: "See how close you are.",
              copy: "This badge alternates between EXP and steps remaining. Try tapping the highlighted badge to switch it."),
        .init(tab: .lab, targets: [.streak, .week], label: "GOALS & STREAKS",
              title: "Build your daily streak.",
              copy: "Reach today’s step goal to earn a checkmark in this week’s circles and keep your streak going."),
        .init(tab: .lab, targets: [.todaySteps, .metrics], label: "TODAY’S MOVEMENT",
              title: "Your day, at a glance.",
              copy: "Your steps and daily goal are here, with distance, calories, and active time just below."),
        .init(tab: .lab, targets: [.workout], label: "WORKOUT TRACKER",
              title: "Take your Nanobeast outside.",
              copy: "Use this walking button to start a workout. Your steps power growth while outdoor sessions uncover your map."),
        .init(tab: .stats, targets: [.stats], label: "STATS & INSIGHTS",
              title: "Explore your movement history.",
              copy: "This calendar shows your daily activity. Open a date for its field report and compare your progress over time."),
        .init(tab: .stats, targets: [.badges], label: "BADGES & ACHIEVEMENTS",
              title: "Find your next achievement.",
              copy: "Earn badges for walking milestones, streaks, and creature discoveries. Tap View All here to browse every badge and see how to earn it, even before your first unlock."),
        .init(tab: .dex, targets: [.dex], label: "FIELD DEX",
              title: "Meet your discoveries here.",
              copy: "Open a discovered specimen to view it again. Locked specimens stay hidden until you hatch or evolve them."),
        .init(tab: .settings, targets: [.settingsGoal], label: "YOUR DAILY GOAL",
              title: "Choose a goal that fits you.",
              copy: "Adjust your daily step target here. You can also change units, Apple Health, and reminders in Settings.")
    ]

    var body: some View {
        GeometryReader { geometry in
            let viewport = CGRect(origin: .zero, size: geometry.size)
            let navigationTargets = highlightsNavigationTabs
                ? pages[step].targets.compactMap(\.navigationTabTarget) : []
            let navigationHoles = navigationTargets.compactMap { target -> CGRect? in
                guard let frame = frames[target] else { return nil }
                let visible = frame.insetBy(dx: -7, dy: -7).intersection(viewport.insetBy(dx: 4, dy: 4))
                return visible.isNull || visible.isEmpty ? nil : visible
            }
            // Clip scrolled content above the tab spotlight so the two scrim cutouts never overlap.
            let contentBottom = navigationHoles.map(\.minY).min().map { $0 - 8 } ?? viewport.maxY
            let contentViewport = CGRect(x: 4, y: 4, width: viewport.width - 8,
                                         height: max(0, min(contentBottom, viewport.maxY - 4) - 4))
            let componentHoles = pages[step].targets.compactMap { target -> CGRect? in
                guard let frame = frames[target] else { return nil }
                let visible = frame.insetBy(dx: -7, dy: -7).intersection(contentViewport)
                return visible.isNull || visible.isEmpty ? nil : visible
            }
            let holes = componentHoles + navigationHoles
            let ready = componentHoles.count == pages[step].targets.count
                && navigationHoles.count == navigationTargets.count
            let placement = AppTourPlacement(viewport: geometry.size, targets: componentHoles,
                                             preferredHeight: dynamicTypeSize.isAccessibilitySize ? 330 : 218,
                                             avoiding: navigationHoles)
            ZStack(alignment: .topLeading) {
                AppTourScrim(holes: ready ? holes : [])
                    .fill(.black.opacity(0.72), style: FillStyle(eoFill: true))
                    .contentShape(AppTourScrim(holes: ready ? holes : []), eoFill: true)
                    .onTapGesture {}
                    .accessibilityHidden(true)

                if ready {
                    ForEach(Array(holes.enumerated()), id: \.offset) { _, hole in
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(NanoTheme.teal, lineWidth: 2)
                            .frame(width: hole.width, height: hole.height)
                            .position(x: hole.midX, y: hole.midY)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        // Only the EXP badge is interactive during its demonstration.
                        if pages[step].targets != [.expBadge] {
                            Color.clear
                                .frame(width: hole.width, height: hole.height)
                                .contentShape(Rectangle())
                                .onTapGesture {}
                                .position(x: hole.midX, y: hole.midY)
                                .accessibilityHidden(true)
                        }
                    }
                    AppTourPointer(card: placement.card, target: placement.target)
                        .stroke(NanoTheme.teal, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    tourCard
                        .frame(width: placement.card.width, height: placement.card.height)
                        .background(RoundedRectangle(cornerRadius: 22).fill(NanoTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(NanoTheme.teal.opacity(0.55)))
                        .position(x: placement.card.midX, y: placement.card.midY)
                } else {
                    ProgressView().tint(NanoTheme.teal)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .accessibilityLabel("Finding the next tour highlight")
                }
            }
        }
        .onAppear { focusCurrentPage() }
    }

    private var tourCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(pages[step].label)
                    .font(NanoFont.aldrich(10)).tracking(0.8)
                    .foregroundStyle(NanoTheme.teal)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text("\(step + 1)/\(pages.count)")
                    .font(.caption).foregroundStyle(NanoTheme.secondaryText)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    Text(pages[step].title).font(.headline)
                    Text(pages[step].copy)
                        .font(.subheadline).foregroundStyle(NanoTheme.secondaryText)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityElement(children: .combine)
            .accessibilityFocused($cardHasFocus)

            HStack(spacing: 10) {
                if step > 0 {
                    Button("Back") { move(to: step - 1) }
                        .frame(minWidth: 54, minHeight: 44)
                        .tint(NanoTheme.secondaryText)
                }
                Button {
                    if step == pages.count - 1 {
                        onFocusChanged(nil)
                        selectedTab = .lab
                        onFinished()
                    } else { move(to: step + 1) }
                } label: {
                    Text(step == pages.count - 1 ? "Start Walking" : "Next")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.black)
                        .background(NanoTheme.teal, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private func focusCurrentPage() {
        selectedTab = pages[step].tab
        onFocusChanged(pages[step].targets.first)
        cardHasFocus = true
    }

    private func move(to next: Int) {
        step = next
        focusCurrentPage()
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private struct NanobeastsLaunchSplash: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var illuminatedLetters = 0
    @State private var coreScale = 0.96
    @State private var coreOpacity = 0.0
    @State private var moleculeProgress: CGFloat = 0
    @State private var orbitRotation = -8.0

    private let letters = Array("NANOBEASTS")

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LabGridBackground()
                .opacity(0.28)
                .ignoresSafeArea()

            RadialGradient(
                colors: [NanoTheme.teal.opacity(0.16), .clear],
                center: .center,
                startRadius: 4,
                endRadius: 260
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    SplashOrbitRing()
                        .fill(NanoTheme.teal.opacity(0.52))
                        .rotationEffect(.degrees(orbitRotation))

                    EvolutionMoleculeMark(progress: moleculeProgress)
                }
                .frame(width: 144, height: 144)
                .scaleEffect(coreScale)
                .opacity(coreOpacity)

                HStack(spacing: 2) {
                    ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                        Text(String(letter))
                            .font(NanoFont.aldrich(24))
                            .foregroundStyle(
                                index < illuminatedLetters
                                    ? Color.white
                                    : Color.white.opacity(0.13)
                            )
                            .shadow(
                                color: index < illuminatedLetters
                                    ? NanoTheme.teal.opacity(0.45)
                                    : .clear,
                                radius: 5
                            )
                    }
                }

                Text("MOVEMENT POWERS EVOLUTION")
                    .font(NanoFont.aldrich(9))
                    .tracking(2)
                    .foregroundStyle(NanoTheme.teal)
                    .opacity(illuminatedLetters == letters.count ? 1 : 0)
            }
        }
        .task { await playIntroduction() }
    }

    @MainActor
    private func playIntroduction() async {
        do {
            if accessibilityReduceMotion {
                illuminatedLetters = letters.count
                coreScale = 1
                coreOpacity = 1
                moleculeProgress = EvolutionMoleculeMark.finalPhase
                orbitRotation = 0
                try await Task.sleep(for: .milliseconds(350))
            } else {
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)) {
                    coreScale = 1
                    coreOpacity = 1
                }
                // The circular ring moves at constant speed, independently of the morphs.
                withAnimation(.linear(duration: 1.5)) { orbitRotation = 28 }
                try await Task.sleep(for: .milliseconds(180))
                async let wordmark: Void = illuminateWordmark()
                // All four stages finish; the sequence is not coupled to the letter count.
                for phase in 1...Int(EvolutionMoleculeMark.finalPhase) {
                    try Task.checkCancellation()
                    withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.24)) {
                        moleculeProgress = CGFloat(phase)
                    }
                    try await Task.sleep(for: .milliseconds(300))
                }
                try await wordmark
                try await Task.sleep(for: .milliseconds(120))
            }
            try Task.checkCancellation()
            onFinished()
        } catch {
            // A dismissed splash must not fire a delayed completion into a newer screen.
        }
    }

    @MainActor
    private func illuminateWordmark() async throws {
        for index in letters.indices {
            try Task.checkCancellation()
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)) {
                illuminatedLetters = index + 1
            }
            try await Task.sleep(for: .milliseconds(70))
        }
    }
}

/// Separate, closed dots avoid arc-joining chords and a mismatched dash seam.
/// Every dot center shares one radius, including under non-square proposals.
private struct SplashOrbitRing: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let radius = side * 0.43
        let dotRadius = side * 0.009
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for index in 0..<48 {
            let angle = Double(index) * 2 * .pi / 48
            let point = CGPoint(x: center.x + radius * cos(angle),
                                y: center.y + radius * sin(angle))
            path.addEllipse(in: CGRect(x: point.x - dotRadius, y: point.y - dotRadius,
                                       width: dotRadius * 2, height: dotRadius * 2))
        }
        return path
    }
}

/// A tiny procedural evolution story: atom → chain → egg → paw → energized organism.
/// It is vector-only, so it remains crisp and starts immediately without decoding media.
private struct EvolutionMoleculeMark: View, Animatable {
    static let finalPhase: CGFloat = 4

    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private static let frames: [[CGPoint]] = [
        // Atom
        [
            .init(x: 0, y: 0),
            .init(x: -0.62, y: -0.32),
            .init(x: 0.64, y: -0.24),
            .init(x: -0.48, y: 0.48),
            .init(x: 0.50, y: 0.52),
            .init(x: -0.82, y: 0.08),
            .init(x: 0.84, y: 0.12)
        ],
        // Mutating molecular chain
        [
            .init(x: 0, y: 0),
            .init(x: -0.54, y: -0.68),
            .init(x: 0.50, y: -0.44),
            .init(x: -0.44, y: -0.08),
            .init(x: 0.46, y: 0.18),
            .init(x: -0.48, y: 0.52),
            .init(x: 0.54, y: 0.70)
        ],
        // Egg / incubating form
        [
            .init(x: 0, y: 0.10),
            .init(x: -0.40, y: -0.62),
            .init(x: 0.40, y: -0.62),
            .init(x: -0.64, y: 0.02),
            .init(x: 0.64, y: 0.02),
            .init(x: -0.34, y: 0.66),
            .init(x: 0.34, y: 0.66)
        ],
        // First creature signal / paw
        [
            .init(x: 0, y: 0.34),
            .init(x: -0.62, y: -0.22),
            .init(x: -0.22, y: -0.64),
            .init(x: 0.22, y: -0.64),
            .init(x: 0.62, y: -0.22),
            .init(x: -0.24, y: 0.24),
            .init(x: 0.24, y: 0.24)
        ],
        // Fully energized organism
        [
            .init(x: 0, y: 0),
            .init(x: 0, y: -0.78),
            .init(x: 0.68, y: -0.38),
            .init(x: 0.68, y: 0.38),
            .init(x: 0, y: 0.78),
            .init(x: -0.68, y: 0.38),
            .init(x: -0.68, y: -0.38)
        ]
    ]

    var body: some View {
        Canvas { context, size in
            let points = interpolatedPoints(in: size)
            // Smooth at stage boundaries; fractional progress previously snapped to zero.
            let energy = CGFloat(pow(sin(Double(progress) * .pi), 2))

            context.drawLayer { layer in
                layer.addFilter(
                    .shadow(
                        color: NanoTheme.teal.opacity(0.46),
                        radius: 6
                    )
                )

                var bonds = Path()
                for index in 1..<points.count {
                    bonds.move(to: points[0])
                    bonds.addLine(to: points[index])
                }
                layer.stroke(
                    bonds,
                    with: .color(NanoTheme.teal.opacity(0.62)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )

                for (index, point) in points.enumerated() {
                    let baseRadius: CGFloat = index == 0 ? 10 : 6
                    let pulse = energy * (index == 0 ? 0.8 : 0.35)
                    let radius = baseRadius + pulse
                    let nodeRect = CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    let color = index == 0
                        ? Color.white
                        : (index.isMultiple(of: 2) ? NanoTheme.teal : Color.cyan)

                    layer.fill(
                        Path(ellipseIn: nodeRect),
                        with: .radialGradient(
                            Gradient(colors: [.white, color, color.opacity(0.72)]),
                            center: CGPoint(
                                x: point.x - (radius * 0.24),
                                y: point.y - (radius * 0.28)
                            ),
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }

        }
        .accessibilityHidden(true)
    }

    private func interpolatedPoints(in size: CGSize) -> [CGPoint] {
        let clamped = min(max(progress, 0), Self.finalPhase)
        let lowerIndex = Int(floor(clamped))
        let upperIndex = min(lowerIndex + 1, Self.frames.count - 1)
        let rawT = clamped - CGFloat(lowerIndex)
        let t = rawT
        let radius = min(size.width, size.height) * 0.40
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let angle = Double(progress) * .pi / 18
        let cosine = cos(angle)
        let sine = sin(angle)

        return zip(Self.frames[lowerIndex], Self.frames[upperIndex]).map { start, end in
            let x = (start.x + ((end.x - start.x) * t)) * radius
            let y = (start.y + ((end.y - start.y) * t)) * radius
            return CGPoint(
                x: center.x + (x * cosine) - (y * sine),
                y: center.y + (x * sine) + (y * cosine)
            )
        }
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Binding var selectedTab: AppTab
    let openWorkouts: () -> Void
    let defersHomeCelebrations: Bool
    let onHomePresentationChanged: (Bool) -> Void
    var onReplayNameTap: (() -> Void)? = nil
    var onExitReplay: (() -> Void)? = nil
    var showsTour = false
    var onTourFinished: () -> Void = {}
    @State private var tourFocus: AppTourTarget?

    private var homeTabIconName: String {
        let isHatching = store.pendingLifecycleEvents.first?.kind == .hatch
        return store.currentStage.isEgg || isHatching
            ? "HomeEggTabIcon"
            : "HomeEvolutionTabIcon"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LabView(onReplayNameTap: onReplayNameTap,
                        defersCelebrations: defersHomeCelebrations,
                        onPresentationStateChanged: onHomePresentationChanged)
            }
            .tabItem {
                Label("Home", image: homeTabIconName)
                    .id(homeTabIconName)
            }
            .tag(AppTab.lab)

            NavigationStack {
                StatsView(historyDefaults: store.isOnboardingReplay ? store.replayPreferences : .standard)
            }
            .tabItem {
                Label("Stats", systemImage: "chart.bar.fill")
            }
            .tag(AppTab.stats)

            NavigationStack {
                DexView()
            }
            .tabItem {
                Label("Dex", systemImage: "square.grid.2x2.fill")
            }
            .tag(AppTab.dex)

            NavigationStack {
                SettingsView(isTourPreview: store.isOnboardingReplay, onExitReplay: onExitReplay)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
        .accessibilityHidden(showsTour)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NanobeastsTabBar(
                selectedTab: $selectedTab,
                homeIconName: homeTabIconName,
                reduceMotion: accessibilityReduceMotion,
                hapticsEnabled: store.hapticsEnabled,
                accent: store.interfaceAccent.color,
                openWorkouts: openWorkouts
            )
            .accessibilityHidden(showsTour)
        }
        .environment(\.appTourFocus, showsTour ? tourFocus : nil)
        .overlayPreferenceValue(AppTourAnchors.self) { anchors in
            if showsTour {
                GeometryReader { geometry in
                    AppTourOverlay(selectedTab: $selectedTab,
                        frames: anchors.mapValues { geometry[$0] },
                        onFocusChanged: { tourFocus = $0 }, onFinished: onTourFinished,
                        highlightsNavigationTabs: store.isOnboardingReplay)
                }
            }
        }
        .tint(store.interfaceAccent.color)
        .background(NanoTheme.background.ignoresSafeArea())
    }
}

struct NanobeastsTabBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selectedTab: AppTab
    let homeIconName: String
    let reduceMotion: Bool
    let hapticsEnabled: Bool
    let accent: Color
    let openWorkouts: () -> Void

    private var railHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 68 : 52
    }

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(NanoTheme.surface.opacity(0.98))
                .overlay {
                    Capsule()
                        .stroke(NanoTheme.teal.opacity(0.20), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.36), radius: 18, y: 8)
                .frame(height: railHeight)
                .padding(.top, 12)

            HStack(spacing: 0) {
                tabButton(.lab, title: "Home", imageName: homeIconName)
                tabButton(.stats, title: "Stats", systemImage: "chart.bar.fill")
                    .appTourTarget(.statsTab)

                Color.clear
                    .frame(width: 64, height: railHeight)
                    .accessibilityHidden(true)

                tabButton(.dex, title: "Dex", systemImage: "square.grid.2x2.fill")
                    .appTourTarget(.dexTab)
                tabButton(.settings, title: "Settings", systemImage: "gearshape.fill")
                    .appTourTarget(.settingsTab)
            }
            .frame(height: railHeight)
            .padding(.top, 12)

            WorkoutTabActionButton(
                accent: accent,
                reduceMotion: reduceMotion,
                action: startWorkout
            )
            .appTourTarget(.workout)
        }
        .frame(height: railHeight + 12)
        .padding(.horizontal, 14)
        .background(NanoTheme.background.opacity(0.96).ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder
    private func tabButton(
        _ tab: AppTab,
        title: String,
        systemImage: String? = nil,
        imageName: String? = nil
    ) -> some View {
        let isSelected = selectedTab == tab

        Button {
            select(tab)
        } label: {
            VStack(spacing: 3) {
                Group {
                    if let imageName {
                        Image(imageName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                    } else if let systemImage {
                        Image(systemName: systemImage)
                    }
                }
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 22, height: 22)

                Text(title)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }
            .foregroundStyle(isSelected ? NanoTheme.teal : NanoTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ tab: AppTab) {
        guard selectedTab != tab else { return }
        if hapticsEnabled {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            selectedTab = tab
        }
    }

    private func startWorkout() {
        if hapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium)
                .impactOccurred(intensity: 0.62)
        }
        openWorkouts()
    }
}

private struct WorkoutTabActionButton: View {
    let accent: Color
    let reduceMotion: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                liquidGlassButton
            } else {
                fallbackGlassButton
            }
        }
        .accessibilityLabel("Start workout")
        .accessibilityHint("Choose a walk, run, or HIIT workout")
    }

    @available(iOS 26.0, *)
    private var liquidGlassButton: some View {
        Button(action: action) {
            workoutGlyph
                .background {
                    Circle()
                        .fill(accent.opacity(0.12))
                }
                .glassEffect(
                    .regular
                        .tint(accent.opacity(0.50))
                        .interactive(),
                    in: .circle
                )
                .shadow(color: Color.black.opacity(0.34), radius: 9, y: 5)
                .modifier(WorkoutButtonCradle(accent: accent))
        }
        .buttonStyle(.plain)
    }

    private var fallbackGlassButton: some View {
        Button(action: action) {
            workoutGlyph
                .background { fallbackGlassSurface }
                .overlay { lensRim }
                .shadow(color: Color.black.opacity(0.34), radius: 9, y: 5)
                .modifier(WorkoutButtonCradle(accent: accent))
        }
        .buttonStyle(
            WorkoutGlassPressStyle(reduceMotion: reduceMotion)
        )
    }

    private var workoutGlyph: some View {
        Image(systemName: "figure.walk.motion")
            .font(.system(size: 21, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.white)
            .frame(width: 50, height: 50)
            .contentShape(Circle())
    }

    @ViewBuilder
    private var fallbackGlassSurface: some View {
        ZStack {
            if reduceTransparency {
                Circle()
                    .fill(NanoTheme.elevated)
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.34),
                            accent.opacity(0.15),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var lensRim: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.58),
                        accent.opacity(0.48),
                        Color.white.opacity(0.10),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
    }
}

private struct WorkoutButtonCradle: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .padding(4)
            .background(
                Circle()
                    .fill(NanoTheme.background.opacity(0.92))
            )
            .overlay {
                Circle()
                    .stroke(accent.opacity(0.20), lineWidth: 1)
            }
    }
}

private struct WorkoutGlassPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(
                        duration: configuration.isPressed ? 0.12 : 0.10
                    ),
                value: configuration.isPressed
            )
    }
}
