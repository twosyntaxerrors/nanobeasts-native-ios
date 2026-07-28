import SwiftUI

private enum AppTab: Hashable {
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

struct AppRootView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("nanobeasts.didCompleteAppTour") private var didCompleteAppTour = false
    @State private var selectedTab: AppTab = .lab
    @State private var activeSheet: AppSheet?
    @State private var completesOnboardingAfterPaywall = false
    @State private var showsOnboardingPaywall = false
    @State private var activeEvolutionEvent: CreatureDiscoveryEvent?
    @State private var presentedLifecycleEventID: UUID?
    @State private var activeBadgeAward: StatsBadge?
    @State private var queuedBadgeAwards: [StatsBadge] = []
    @State private var showsAppTour = false
    @State private var appTourPendingAfterHealth = false
    @State private var onboardingContinuationPending = false
    @State private var showsLaunchSplash = true

    var body: some View {
        ZStack {
            MainTabView(selectedTab: $selectedTab)
                .opacity(store.onboardingCompleted ? 1 : 0)
                .allowsHitTesting(store.onboardingCompleted)

            if !store.onboardingCompleted {
                OnboardingFlowView(onFinished: showOnboardingPaywall)
                    .transition(.opacity)
            }

            if store.onboardingCompleted, showsAppTour {
                AppTourOverlay(
                    selectedTab: $selectedTab,
                    onFinished: {
                        didCompleteAppTour = true
                        withAnimation(.easeOut(duration: 0.24)) {
                            showsAppTour = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(20)
            }

            if showsLaunchSplash {
                NanobeastsLaunchSplash {
                    withAnimation(.easeOut(duration: 0.34)) {
                        showsLaunchSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: store.onboardingCompleted)
        .task {
            await bootstrap()
        }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "nanobeasts" else { return }
            switch url.host?.lowercased() {
            case "stats":
                selectedTab = .stats
            case "dex":
                selectedTab = .dex
            case "settings":
                selectedTab = .settings
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
            activeBadgeAward = nil
            queuedBadgeAwards.removeAll()
            didCompleteAppTour = false
            showsLaunchSplash = true
        }
        .onChange(of: store.evolutionEventID) {
            presentNextLifecycleEventIfPossible()
        }
        .onChange(of: store.badgeEvaluationID) {
            queueNewBadgeAwards()
        }
        .fullScreenCover(isPresented: $showsOnboardingPaywall, onDismiss: handlePaywallDismissed) {
            RevenueCatPaywallScreen(playerName: store.playerName)
        }
        .fullScreenCover(item: $activeEvolutionEvent, onDismiss: lifecyclePresentationDismissed) { event in
            EvolutionLifecycleExperience(
                catalog: store.catalog,
                event: event,
                nextEggs: store.nextEggCandidates,
                onChooseEgg: { egg in
                    store.chooseNextEgg(egg)
                }
            )
            .environment(store)
        }
        .fullScreenCover(item: $activeBadgeAward, onDismiss: presentNextQueuedExperience) { badge in
            BadgeAwardCelebrationView(
                badge: badge,
                sections: currentBadgeSections
            )
        }
        .sheet(item: $activeSheet, onDismiss: presentPendingAppTour) { sheet in
            switch sheet {
            case .onboardingPaywall:
                EmptyView()
            case .health:
                HealthAccessView()
                    .environment(store)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func showOnboardingPaywall(_ profile: OnboardingProfile) {
        store.saveOnboardingProfile(
            playerName: profile.playerName,
            dailyGoal: profile.dailyGoal,
            wantsHealth: profile.wantsHealth,
            wantsReminders: profile.wantsReminders
        )
        completesOnboardingAfterPaywall = true
        didCompleteAppTour = false
        showsOnboardingPaywall = true
    }

    private func handlePaywallDismissed() {
        guard completesOnboardingAfterPaywall else { return }
        completesOnboardingAfterPaywall = false
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
        appTourPendingAfterHealth = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
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
        guard !didCompleteAppTour else { return }
        selectedTab = .lab
        withAnimation(.easeOut(duration: 0.28)) {
            showsAppTour = true
        }
    }

    private func bootstrap() async {
        await store.bootstrap()
        if
            store.onboardingCompleted,
            !didCompleteAppTour,
            store.pendingLifecycleEvents.first?.kind == .eggAcquired
        {
            onboardingContinuationPending = true
        }
        presentNextLifecycleEventIfPossible()
        queueNewBadgeAwards()

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

    private var currentBadgeSections: [StatsBadgeSection] {
        let discoveredStages = store.catalog.creatureStages.filter {
            store.isDiscovered($0) || store.isCurrent($0)
        }
        return StatsBadgeCatalog.make(
            records: store.dailyHistory,
            dailyGoal: store.dailyGoal,
            discoveredStages: discoveredStages
        )
    }

    private func presentNextLifecycleEventIfPossible() {
        guard
            store.onboardingCompleted,
            activeEvolutionEvent == nil,
            activeBadgeAward == nil,
            !showsOnboardingPaywall,
            activeSheet == nil,
            let event = store.pendingLifecycleEvents.first
        else {
            return
        }
        presentedLifecycleEventID = event.id
        activeEvolutionEvent = event
    }

    private func lifecyclePresentationDismissed() {
        let completedInitialEggAssignment =
            activeEvolutionEvent?.kind == .eggAcquired && !didCompleteAppTour
        if let presentedLifecycleEventID {
            store.acknowledgeLifecycleEvent(presentedLifecycleEventID)
        }
        presentedLifecycleEventID = nil
        activeEvolutionEvent = nil
        if
            (onboardingContinuationPending || completedInitialEggAssignment),
            store.pendingLifecycleEvents.isEmpty
        {
            onboardingContinuationPending = false
            continueAfterInitialEggAssignment()
            return
        }
        presentNextQueuedExperience()
    }

    private func queueNewBadgeAwards() {
        guard store.onboardingCompleted else { return }
        let alreadyQueued = Set(queuedBadgeAwards.map(\.id))
            .union(activeBadgeAward.map { [$0.id] } ?? [])
        let newBadges = currentBadgeSections
            .flatMap(\.badges)
            .filter {
                $0.unlocked
                    && !store.awardedBadgeIDs.contains($0.id)
                    && !alreadyQueued.contains($0.id)
            }

        for badge in newBadges {
            store.markBadgeAwardPresented(badge.id)
            queuedBadgeAwards.append(badge)
        }
        presentNextQueuedExperience()
    }

    private func presentNextQueuedExperience() {
        if !store.pendingLifecycleEvents.isEmpty {
            presentNextLifecycleEventIfPossible()
            return
        }
        guard
            activeEvolutionEvent == nil,
            activeBadgeAward == nil,
            !showsOnboardingPaywall,
            activeSheet == nil,
            !queuedBadgeAwards.isEmpty
        else {
            return
        }
        activeBadgeAward = queuedBadgeAwards.removeFirst()
    }
}

private struct AppTourOverlay: View {
    @Binding var selectedTab: AppTab
    let onFinished: () -> Void

    @State private var step = 0

    private let pages = [
        (
            tab: AppTab.lab,
            symbol: "house.fill",
            eyebrow: "EVOLUTION CHAMBER",
            title: "This living ring turns steps into growth.",
            copy: "The animated specimen in the center comes directly from the R2 archive. Tap the EXP capsule to reveal the exact steps remaining, or tap the creature to open its profile."
        ),
        (
            tab: AppTab.lab,
            symbol: "figure.walk.motion",
            eyebrow: "TODAY’S FIELD SIGNAL",
            title: "Your whole day is summarized on Home.",
            copy: "The weekly strip records consistency. Today’s steps, distance, calories, and active time show the movement feeding your current Nanobeast."
        ),
        (
            tab: AppTab.stats,
            symbol: "chart.bar.fill",
            eyebrow: "ACTIVITY STATS",
            title: "See the movement behind your progress.",
            copy: "Review days and weeks, open a date’s field report, explore insights, and track the achievements you have earned."
        ),
        (
            tab: AppTab.dex,
            symbol: "book.closed.fill",
            eyebrow: "FIELD DEX",
            title: "Every discovery joins your archive.",
            copy: "Found creatures remain fully visible and animated. Locked specimens stay encrypted until your walking reveals them."
        ),
        (
            tab: AppTab.settings,
            symbol: "gearshape.fill",
            eyebrow: "FIELD SETTINGS",
            title: "Tune Nanobeasts to fit your life.",
            copy: "Turn movement reminders on when you want a nudge, and adjust your daily step goal whenever your routine changes."
        )
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.64)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Image(systemName: pages[step].symbol)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(NanoTheme.teal)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(NanoTheme.teal.opacity(0.12)))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("QUICK FIELD TOUR")
                                .font(NanoFont.aldrich(9))
                                .tracking(1.5)
                                .foregroundStyle(NanoTheme.secondaryText)
                            Text(pages[step].eyebrow)
                                .font(NanoFont.aldrich(13))
                                .tracking(1.1)
                                .foregroundStyle(NanoTheme.teal)
                        }

                        Spacer()

                        Text("\(step + 1)/\(pages.count)")
                            .font(NanoFont.aldrich(10))
                            .foregroundStyle(NanoTheme.secondaryText)
                    }

                    Text(pages[step].title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text(pages[step].copy)
                        .font(NanoFont.aldrich(12))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .lineSpacing(4)

                    HStack(spacing: 10) {
                        if step > 0 {
                            Button("BACK") {
                                move(to: step - 1)
                            }
                            .buttonStyle(.bordered)
                            .tint(NanoTheme.secondaryText)
                        }

                        Button {
                            if step == pages.count - 1 {
                                selectedTab = .lab
                                onFinished()
                            } else {
                                move(to: step + 1)
                            }
                        } label: {
                            Text(step == pages.count - 1 ? "START EXPLORING" : "NEXT")
                                .font(NanoFont.aldrich(12))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NanoTheme.teal)
                        .foregroundStyle(.black)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(NanoTheme.surface.opacity(0.97))
                        .stroke(NanoTheme.teal.opacity(0.52), lineWidth: 1)
                )
                .shadow(color: NanoTheme.teal.opacity(0.20), radius: 24)

                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(NanoTheme.teal)
                    .offset(x: indicatorOffset)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 74)
        }
        .onAppear {
            selectedTab = pages[step].tab
        }
    }

    private var indicatorOffset: CGFloat {
        switch pages[step].tab {
        case .lab: -132
        case .stats: -45
        case .dex: 44
        case .settings: 132
        }
    }

    private func move(to next: Int) {
        withAnimation(.snappy(duration: 0.36, extraBounce: 0.04)) {
            step = next
            selectedTab = pages[next].tab
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private struct NanobeastsLaunchSplash: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var illuminatedLetters = 0
    @State private var coreScale = 0.72
    @State private var coreOpacity = 0.0

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
                    Circle()
                        .stroke(NanoTheme.teal.opacity(0.22), lineWidth: 1)
                        .frame(width: 112, height: 112)
                    Circle()
                        .stroke(
                            NanoTheme.teal,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [32, 12])
                        )
                        .frame(width: 88, height: 88)
                        .rotationEffect(.degrees(Double(illuminatedLetters) * 18))
                        .shadow(color: NanoTheme.teal.opacity(0.70), radius: 12)
                    Text("NB")
                        .font(NanoFont.aldrich(28))
                        .tracking(2)
                        .foregroundStyle(.white)
                }
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
                                    ? NanoTheme.teal.opacity(0.92)
                                    : .clear,
                                radius: 9
                            )
                            .scaleEffect(index == illuminatedLetters - 1 ? 1.08 : 1)
                    }
                }

                Text("MOVEMENT POWERS EVOLUTION")
                    .font(NanoFont.aldrich(9))
                    .tracking(2)
                    .foregroundStyle(NanoTheme.teal)
                    .opacity(illuminatedLetters == letters.count ? 1 : 0)
            }
        }
        .task {
            if accessibilityReduceMotion {
                illuminatedLetters = letters.count
                coreScale = 1
                coreOpacity = 1
                try? await Task.sleep(for: .milliseconds(650))
                onFinished()
                return
            }

            withAnimation(.spring(response: 0.52, dampingFraction: 0.72)) {
                coreScale = 1
                coreOpacity = 1
            }

            try? await Task.sleep(for: .milliseconds(180))
            for index in letters.indices {
                guard !Task.isCancelled else { return }
                withAnimation(.snappy(duration: 0.24, extraBounce: 0.08)) {
                    illuminatedLetters = index + 1
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.28)
                try? await Task.sleep(for: .milliseconds(105))
            }

            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}

private struct MainTabView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LabView()
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(AppTab.lab)

            NavigationStack {
                StatsView()
            }
            .tabItem {
                Label("Stats", systemImage: "chart.bar.fill")
            }
            .tag(AppTab.stats)

            NavigationStack {
                DexView()
            }
            .tabItem {
                Label("Dex", systemImage: "book.closed.fill")
            }
            .tag(AppTab.dex)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
        .tint(NanoTheme.teal)
        .background(NanoTheme.background.ignoresSafeArea())
    }
}
