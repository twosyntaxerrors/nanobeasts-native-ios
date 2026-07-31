import SwiftUI
import StoreKit

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
    @Environment(\.requestReview) private var requestReview
    @AppStorage("nanobeasts.didCompleteAppTour") private var didCompleteAppTour = false
    @State private var selectedTab: AppTab = .lab
    @State private var activeSheet: AppSheet?
    @State private var completesOnboardingAfterPaywall = false
    @State private var showsOnboardingPaywall = false
    @State private var activeEvolutionEvent: CreatureDiscoveryEvent?
    @State private var presentedLifecycleEventID: UUID?
    @State private var presentedLifecycleEventKind: CreatureDiscoveryKind?
    @State private var activeBadgeAward: StatsBadge?
    @State private var queuedBadgeAwards: [StatsBadge] = []
    @State private var showsAppTour = false
    @State private var appTourPendingAfterHealth = false
    @State private var onboardingContinuationPending = false
    @State private var showsLaunchSplash = true
    @State private var reviewRequestPending = false

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
            presentedLifecycleEventKind = nil
            activeBadgeAward = nil
            queuedBadgeAwards.removeAll()
            reviewRequestPending = false
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
        .fullScreenCover(item: $activeBadgeAward, onDismiss: badgePresentationDismissed) { badge in
            BadgeAwardCelebrationView(
                badge: badge,
                sections: currentBadgeSections,
                onPresented: {
                    store.markBadgeAwardPresented(badge.id)
                }
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
            records: store.badgeEvaluationHistory,
            dailyGoal: store.dailyGoal,
            discoveredStages: discoveredStages,
            distanceUnit: store.distanceUnit
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
        presentedLifecycleEventKind = event.kind
        activeEvolutionEvent = event
    }

    private func lifecyclePresentationDismissed() {
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
        guard store.onboardingCompleted else { return }
        let alreadyQueued = Set(queuedBadgeAwards.map(\.id))
            .union(activeBadgeAward.map { [$0.id] } ?? [])
        let newBadges = currentBadgeSections
            .flatMap(\.badges)
            .filter {
                $0.unlocked
                    && !store.hasPresentedBadgeAward($0.id)
                    && !alreadyQueued.contains($0.id)
            }

        for badge in newBadges {
            queuedBadgeAwards.append(badge)
        }
        presentNextQueuedExperience()
    }

    private func badgePresentationDismissed() {
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
        if !store.pendingLifecycleEvents.isEmpty {
            presentNextLifecycleEventIfPossible()
            return
        }
        guard
            activeEvolutionEvent == nil,
            activeBadgeAward == nil,
            !showsOnboardingPaywall,
            activeSheet == nil
        else {
            return
        }
        if !queuedBadgeAwards.isEmpty {
            activeBadgeAward = queuedBadgeAwards.removeFirst()
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

private struct AppTourOverlay: View {
    @Binding var selectedTab: AppTab
    let onFinished: () -> Void

    @State private var step = 0

    private let pages = [
        (
            tab: AppTab.lab,
            symbol: "house.fill",
            eyebrow: "YOUR NANOBEAST",
            title: "Your steps power the creature in the ring.",
            copy: "The ring fills as your Nanobeast grows. Tap the creature to open its profile, or tap the EXP badge to see how many evolution steps remain."
        ),
        (
            tab: AppTab.lab,
            symbol: "flame.fill",
            eyebrow: "GOALS & STREAKS",
            title: "Reach your daily goal to build a streak.",
            copy: "The circles show this week at a glance. Complete today’s goal to earn the checkmark, celebrate the day, and keep your streak alive."
        ),
        (
            tab: AppTab.lab,
            symbol: "figure.walk.motion",
            eyebrow: "TODAY’S MOVEMENT",
            title: "Home shows the activity that matters today.",
            copy: "See your steps, distance, calories, and active time together. Your total steps are always recorded, even when evolution progress has reached a daily plan limit."
        ),
        (
            tab: AppTab.stats,
            symbol: "chart.bar.fill",
            eyebrow: "STATS & INSIGHTS",
            title: "Understand your movement over time.",
            copy: "Open any date for its field report, compare trends, and tap an achievement to view or share the badge you earned."
        ),
        (
            tab: AppTab.dex,
            symbol: "book.closed.fill",
            eyebrow: "FIELD DEX",
            title: "Every creature you discover is saved here.",
            copy: "Found creatures can be viewed, scanned, and replayed. Locked specimens stay hidden until you hatch or evolve them."
        ),
        (
            tab: AppTab.settings,
            symbol: "gearshape.fill",
            eyebrow: "SETTINGS",
            title: "Make your daily plan work for you.",
            copy: "Adjust your step goal, choose miles or kilometers, manage Apple Health, and turn gentle evolution reminders on or off whenever you like."
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
    @State private var moleculeProgress: CGFloat = 0

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
                    EvolutionMoleculeMark(progress: moleculeProgress)
                        .frame(width: 136, height: 136)

                    Circle()
                        .stroke(NanoTheme.teal.opacity(0.10), lineWidth: 1)
                        .frame(width: 118, height: 118)
                        .scaleEffect(0.92 + (moleculeProgress.truncatingRemainder(dividingBy: 1) * 0.08))
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
                moleculeProgress = EvolutionMoleculeMark.finalPhase
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
                if index == 0 || index == 3 || index == 6 || index == 9 {
                    let nextPhase = min(
                        EvolutionMoleculeMark.finalPhase,
                        CGFloat((index / 3) + 1)
                    )
                    withAnimation(.smooth(duration: 0.46)) {
                        moleculeProgress = nextPhase
                    }
                }
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
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let localProgress = progress - floor(progress)
            let energy = CGFloat(0.5 + (0.5 * sin(Double(progress) * .pi * 2)))

            context.drawLayer { layer in
                layer.addFilter(
                    .shadow(
                        color: NanoTheme.teal.opacity(0.74),
                        radius: 8 + (energy * 4)
                    )
                )

                var bonds = Path()
                for index in 1..<points.count {
                    bonds.move(to: points[0])
                    bonds.addLine(to: points[index])
                }
                layer.stroke(
                    bonds,
                    with: .color(NanoTheme.teal.opacity(0.70)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )

                for (index, point) in points.enumerated() {
                    let baseRadius: CGFloat = index == 0 ? 11 : 6.5
                    let pulse = index == 0 ? CGFloat(energy * 1.8) : localProgress * 1.2
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

            var orbit = Path()
            orbit.addArc(
                center: center,
                radius: min(size.width, size.height) * 0.43,
                startAngle: .degrees(-66 + (Double(progress) * 24)),
                endAngle: .degrees(48 + (Double(progress) * 24)),
                clockwise: false
            )
            orbit.addArc(
                center: center,
                radius: min(size.width, size.height) * 0.43,
                startAngle: .degrees(112 + (Double(progress) * 24)),
                endAngle: .degrees(214 + (Double(progress) * 24)),
                clockwise: false
            )
            context.stroke(
                orbit,
                with: .color(NanoTheme.teal.opacity(0.48)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 8])
            )
        }
        .accessibilityHidden(true)
    }

    private func interpolatedPoints(in size: CGSize) -> [CGPoint] {
        let clamped = min(max(progress, 0), Self.finalPhase)
        let lowerIndex = Int(floor(clamped))
        let upperIndex = min(lowerIndex + 1, Self.frames.count - 1)
        let rawT = clamped - CGFloat(lowerIndex)
        let t = rawT * rawT * (3 - (2 * rawT))
        let radius = min(size.width, size.height) * 0.40
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let angle = Double(progress) * .pi / 18
        let cosine = cos(angle)
        let sine = sin(angle)
        let warp = 1 + (0.08 * sin(Double(rawT) * .pi))

        return zip(Self.frames[lowerIndex], Self.frames[upperIndex]).map { start, end in
            let x = (start.x + ((end.x - start.x) * t)) * radius * warp
            let y = (start.y + ((end.y - start.y) * t)) * radius / warp
            return CGPoint(
                x: center.x + (x * cosine) - (y * sine),
                y: center.y + (x * sine) + (y * cosine)
            )
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
