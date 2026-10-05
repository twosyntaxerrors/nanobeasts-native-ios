import SwiftUI
import UIKit

struct LabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTourFocus) private var tourFocus
    var onReplayNameTap: (() -> Void)? = nil
    /// The replay opens its own scripted paywall instead of the live one.
    var onReplayUpgradeTap: (() -> Void)? = nil
    var defersCelebrations = false
    var onPresentationStateChanged: (Bool) -> Void = { _ in }

    @State private var showStepsRemaining = false
    @State private var activeSheet: LabSheet?
    @State private var animatedTodaySteps = 0.0
    @State private var animatedHatchProgress = 0.0
    @State private var hasInitializedActivityAnimation = false
    @State private var stepAnimationEnergy = 0.0
    @State private var goalConfettiID: UUID?
    @State private var showsDailyGoalCard = false
    @State private var pendingDailyGoalCelebration = false
    @State private var showsProgressionPaywall = false
    @AppStorage("nanobeasts.lastDailyGoalCelebration")
    private var lastDailyGoalCelebration = ""

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            GeometryReader { proxy in
                let usesCompactHeight = proxy.size.height < 760
                let heroDiameter = min(
                    proxy.size.width - 76,
                    min(280, max(196, proxy.size.height * 0.32))
                )
                let headerToWeekSpacing: CGFloat = usesCompactHeight ? 8 : 11
                let bottomScrollClearance: CGFloat = 8

                ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 0) {
                        LabHeader(
                            greeting: greeting,
                            playerName: store.playerName,
                            streak: store.displayedCurrentStreak,
                            onStreakTap: { activeSheet = .streak },
                            onNameTap: onReplayNameTap
                        )
                        .id(AppTourTarget.streak)

                        Color.clear
                            .frame(height: headerToWeekSpacing)
                            .accessibilityHidden(true)

                        Button {
                            activeSheet = .streak
                        } label: {
                            WeekProgressStrip(
                                records: store.displayedRecentWeek,
                                dailyGoal: store.dailyGoal
                            )
                        }
                        .buttonStyle(.plain)
                        .appTourTarget(.week)

                        Color.clear
                            .frame(height: usesCompactHeight ? 24 : 28)
                            .accessibilityHidden(true)

                        CreatureResearchHero(
                            stage: homeCreatureStage,
                            progress: animatedHatchProgress,
                            stepsRemaining: max(
                                store.currentTarget - store.hatchProgressSteps,
                                0
                            ),
                            nextMilestone: homeCreatureNextMilestone,
                            isSyncingSteps: store.isSyncingSteps,
                            isEvolutionLocked: store.isEvolutionLocked,
                            uncountedSteps: store.uncountedTodaySteps,
                            animationEnergy: stepAnimationEnergy,
                            showStepsRemaining: $showStepsRemaining,
                            ringDiameter: heroDiameter,
                            onEXPBadgeTap: {
                                if store.isEvolutionLocked {
                                    if let onReplayUpgradeTap { onReplayUpgradeTap() }
                                    else { showsProgressionPaywall = true }
                                } else {
                                    withAnimation(
                                        .easeInOut(duration: store.reduceMotion ? 0 : 0.24)
                                    ) {
                                        showStepsRemaining.toggle()
                                    }
                                }
                            },
                            onCreatureTap: { activeSheet = .creature },
                            onNameTap: onReplayNameTap
                        )
                        .id(AppTourTarget.ring)

                        Color.clear
                            .frame(height: usesCompactHeight ? 18 : 22)
                            .accessibilityHidden(true)

                        TodayStepsSection(
                            steps: animatedTodaySteps,
                            dailyGoal: store.dailyGoal,
                            animationEnergy: stepAnimationEnergy
                        )
                        .appTourTarget(.todaySteps)
                        .id(AppTourTarget.todaySteps)

                        Color.clear
                            .frame(height: 22)
                            .accessibilityHidden(true)

                        DailyMetricsPanel(
                            distanceKilometers: store.distanceKilometersToday,
                            distanceUnit: store.distanceUnit,
                            calories: store.caloriesToday,
                            activeMinutes: store.activeMinutesToday
                        )
                        .appTourTarget(.metrics)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 2)
                    .padding(.bottom, bottomScrollClearance)
                    .frame(minHeight: max(proxy.size.height - 4, 0), alignment: .top)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .refreshable {
                    await refresh()
                }
                .task(id: tourFocus) {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    switch tourFocus {
                    case .ring: scroll.scrollTo(AppTourTarget.ring, anchor: .center)
                    case .expBadge: scroll.scrollTo(AppTourTarget.expBadge, anchor: .center)
                    case .streak, .none: scroll.scrollTo(AppTourTarget.streak, anchor: .top)
                    case .todaySteps: scroll.scrollTo(AppTourTarget.todaySteps, anchor: .top)
                    default: break
                    }
                }
                }
            }

            if let goalConfettiID {
                MaturityConfettiBurst()
                    .id(goalConfettiID)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .zIndex(50)
            }

            if showsDailyGoalCard {
                Color.black.opacity(0.56)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(51)

                DailyGoalCompletionCard(
                    goal: store.dailyGoal,
                    creatureName: homeCreatureStage.name,
                    evolutionLocked: store.isEvolutionLocked
                ) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        showsDailyGoalCard = false
                    }
                }
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(52)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !hasInitializedActivityAnimation else { return }
            animatedTodaySteps = Double(store.displayedTodaySteps)
            animatedHatchProgress = store.hatchProgress
            hasInitializedActivityAnimation = true
        }
        .onChange(of: store.evolutionEventID) {
            guard store.hapticsEnabled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .onChange(of: homeCreatureStage.id) {
            animatedHatchProgress = store.hatchProgress
            showStepsRemaining = false
            stepAnimationEnergy = 0
        }
        .task(id: expBadgeCycleID) {
            guard !store.isSyncingSteps, !store.isEvolutionLocked else {
                return
            }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: store.reduceMotion ? 0 : 0.24)) {
                showStepsRemaining.toggle()
            }
        }
        .task {
            guard AppScreenshotScenario.active == .featureTourHome else { return }

            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            activeSheet = .streak

            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            activeSheet = nil

            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            for _ in 0..<12 {
                await store.addTestingSteps(1_200)
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
        }
        .task(id: store.stepSyncAnimationID) {
            guard store.consumeStepSyncAnimationIfNeeded() else {
                animatedTodaySteps = Double(store.displayedTodaySteps)
                animatedHatchProgress = store.hatchProgress
                hasInitializedActivityAnimation = true
                stepAnimationEnergy = 0
                return
            }

            animatedTodaySteps = Double(store.stepSyncFromTodaySteps)
            animatedHatchProgress = store.stepSyncFromHatchProgress
            hasInitializedActivityAnimation = true
            stepAnimationEnergy = 1
            await Task.yield()
            withAnimation(.smooth(duration: store.stepSyncDuration)) {
                animatedTodaySteps = Double(store.displayedTodaySteps)
                animatedHatchProgress = store.hatchProgress
            }
            try? await Task.sleep(for: .seconds(store.stepSyncDuration * 0.72))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.46)) {
                stepAnimationEnergy = 0
            }
        }
        .task(id: store.dailyGoalCelebrationID) {
            guard store.dailyGoalCelebrationID != nil else { return }
            let revealDelay = max(store.stepSyncDuration * 0.72, 0.2)
            try? await Task.sleep(for: .seconds(revealDelay))
            guard !Task.isCancelled else { return }
            presentDailyGoalCelebrationIfNeeded()
        }
        .onChange(of: store.pendingLifecycleEvents.count) {
            guard pendingDailyGoalCelebration, store.pendingLifecycleEvents.isEmpty else {
                return
            }
            pendingDailyGoalCelebration = false
            presentDailyGoalCelebrationIfNeeded()
        }
        .onChange(of: activeSheet != nil || showsDailyGoalCard || showsProgressionPaywall, initial: true) {
            onPresentationStateChanged(activeSheet != nil || showsDailyGoalCard || showsProgressionPaywall)
        }
        .onChange(of: defersCelebrations) {
            if !defersCelebrations, pendingDailyGoalCelebration {
                pendingDailyGoalCelebration = false
                presentDailyGoalCelebrationIfNeeded()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .streak:
                StreakSummaryView(
                    records: store.badgeEvaluationHistory,
                    dailyGoal: store.dailyGoal,
                    dailyGoalHistory: store.dailyGoalHistory,
                    hapticsEnabled: store.hapticsEnabled,
                    reducesMotion: store.reduceMotion
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            case .creature:
                CreatureDetailView(stage: homeCreatureStage, isLocked: false)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
        }
        .fullScreenCover(isPresented: $showsProgressionPaywall) {
            RevenueCatPaywallScreen(playerName: store.playerName, selectedGoals: store.onboardingGoals, primaryGoal: store.onboardingPrimaryGoal, selectedBlockers: store.onboardingBlockers)
        }
    }

    private var greeting: String {
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// Progression advances the persisted stage before SwiftUI can present the
    /// lifecycle cover. Keep Home on the previous form until that event is
    /// acknowledged so the reveal only happens inside the hatch/evolution flow.
    private var homeCreatureStage: CreatureStage {
        guard
            let event = store.pendingLifecycleEvents.first,
            event.kind == .hatch || event.kind == .evolution,
            let family = store.catalog.families.first(where: {
                $0.id == event.familyID
            }),
            let previousStage = family.stages
                .filter({ $0.stage < event.stage })
                .max(by: { $0.stage < $1.stage })
        else {
            return store.currentStage
        }

        return previousStage
    }

    private var homeCreatureNextMilestone: ProgressMilestone {
        if homeCreatureStage.isEgg {
            return .hatch
        }
        if homeCreatureStage.id == store.currentFamily.stages.last?.id {
            return .mature
        }
        return .evolve
    }

    private var expBadgeCycleID: String {
        [
            showStepsRemaining.description,
            store.isSyncingSteps.description,
            store.isEvolutionLocked.description,
            homeCreatureStage.id,
        ].joined(separator: "-")
    }

    private func refresh() async {
        await store.refreshHealthData()
    }

    private func presentDailyGoalCelebrationIfNeeded() {
        guard !defersCelebrations, store.pendingLifecycleEvents.isEmpty else {
            pendingDailyGoalCelebration = true
            return
        }

        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day],
            from: Date()
        )
        let celebrationKey = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        guard lastDailyGoalCelebration != celebrationKey else { return }

        if !store.hasTestingActivityPreview {
            lastDailyGoalCelebration = celebrationKey
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if !store.reduceMotion {
            goalConfettiID = UUID()
        }
        withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
            showsDailyGoalCard = true
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: "Daily step goal complete. \(store.dailyGoal.formatted()) steps."
        )
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            goalConfettiID = nil
        }
    }
}

private struct DailyGoalCompletionCard: View {
    let goal: Int
    let creatureName: String
    let evolutionLocked: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(NanoTheme.teal.opacity(0.12))
                    .frame(width: 74, height: 74)
                    .overlay {
                        Circle()
                            .stroke(NanoTheme.teal.opacity(0.48), lineWidth: 1)
                    }
                Image(systemName: "checkmark")
                    .font(.system(size: 31, weight: .black))
                    .foregroundStyle(NanoTheme.background)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(NanoTheme.teal))
                    .shadow(color: NanoTheme.teal.opacity(0.55), radius: 18)
            }

            VStack(spacing: 8) {
                Text("DAILY GOAL COMPLETE")
                    .font(NanoFont.aldrich(12))
                    .tracking(1.6)
                    .foregroundStyle(NanoTheme.teal)

                Text("\(goal.formatted()) steps reached")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(
                    evolutionLocked
                        ? "Today counts toward your streak. Upgrade to Pro to put your steps toward \(creatureName)’s evolution."
                        : "Today counts toward your streak. Every extra step still powers \(creatureName)’s evolution."
                )
                .font(NanoFont.aldrich(10))
                .foregroundStyle(NanoTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            }

            Button(action: onDismiss) {
                Text("KEEP MOVING")
                    .font(NanoFont.aldrich(12))
                    .tracking(1)
                    .foregroundStyle(NanoTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Capsule()
                            .fill(NanoTheme.teal)
                            .shadow(color: NanoTheme.teal.opacity(0.34), radius: 14)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(NanoTheme.surface.opacity(0.97))
                .stroke(NanoTheme.teal.opacity(0.62), lineWidth: 1)
                .shadow(color: .black.opacity(0.55), radius: 30, y: 14)
        )
        .accessibilityElement(children: .combine)
    }
}

private enum LabSheet: String, Identifiable {
    case streak
    case creature

    var id: String { rawValue }
}

// Hallmark · component: streak readout · genre: atmospheric · theme: Nanobeasts
// Pre-emit critique: P5 H4 E5 S5 R5 V4 · contrast: pass · touch target: 44pt
struct LabHeader: View {
    let greeting: String
    let playerName: String
    let streak: Int
    let onStreakTap: () -> Void
    var onNameTap: (() -> Void)? = nil

    @State private var flameAnimationTrigger = 0

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(greeting),")
                    .font(.system(size: 13, weight: .regular))
                    .tracking(1.4)
                    .foregroundStyle(NanoTheme.secondaryText)
                if let onNameTap {
                    Button(action: onNameTap) { researcherName }
                        .buttonStyle(.plain)
                        .accessibilityHint("Adds 100 simulated steps")
                } else {
                    researcherName
                }
                Text("Let's evolve today.")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(0.4)
                    .foregroundStyle(NanoTheme.secondaryText)
            }

            Spacer(minLength: 4)

            Button {
                flameAnimationTrigger &+= 1
                onStreakTap()
            } label: {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("STREAK")
                        .font(NanoFont.aldrich(8))
                        .tracking(1.4)
                        .foregroundStyle(NanoTheme.secondaryText)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        StreakFlameMark(
                            size: 15,
                            animationTrigger: flameAnimationTrigger
                        )

                        Text(streak.formatted())
                            .font(NanoFont.spaceMono(16, bold: true))
                            .monospacedDigit()
                            .foregroundStyle(.white)

                        Text(streak == 1 ? "DAY" : "DAYS")
                            .font(NanoFont.aldrich(8))
                            .tracking(0.8)
                            .foregroundStyle(NanoTheme.secondaryText)
                    }

                    HStack(spacing: 3) {
                        Rectangle()
                            .fill(NanoTheme.orange.opacity(0.30))
                            .frame(width: 24, height: 1)
                        Rectangle()
                            .fill(NanoTheme.orange.opacity(0.82))
                            .frame(width: 5, height: 2)
                    }
                }
                .frame(minWidth: 78, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(StreakReadoutButtonStyle())
            .appTourTarget(.streak)
            .accessibilityLabel(
                "\(streak) \(streak == 1 ? "day" : "days") streak. Show weekly streak details."
            )
        }
        .onAppear {
            flameAnimationTrigger &+= 1
        }
        .onChange(of: streak) {
            flameAnimationTrigger &+= 1
        }
    }

    private var researcherName: some View {
        Text(playerName.isEmpty ? "RESEARCHER" : playerName.uppercased())
            .font(.system(size: 25, weight: .bold))
            .tracking(2.2)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .contentShape(Rectangle())
    }
}

private struct StreakReadoutButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.62 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct StreakFlameMark: View {
    let size: CGFloat
    let animationTrigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                flame
            } else {
                KeyframeAnimator(
                    initialValue: AnimationValues(),
                    trigger: animationTrigger
                ) { values in
                    flame
                        .scaleEffect(
                            x: values.scaleX,
                            y: values.scaleY,
                            anchor: .bottom
                        )
                } keyframes: { _ in
                    KeyframeTrack(\.scaleX) {
                        LinearKeyframe(0.93, duration: 0.08)
                        CubicKeyframe(1.05, duration: 0.11)
                        CubicKeyframe(0.98, duration: 0.10)
                        CubicKeyframe(1, duration: 0.12)
                    }
                    KeyframeTrack(\.scaleY) {
                        LinearKeyframe(1.12, duration: 0.08)
                        CubicKeyframe(0.96, duration: 0.11)
                        CubicKeyframe(1.04, duration: 0.10)
                        CubicKeyframe(1, duration: 0.12)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }

    private var flame: some View {
        Image(systemName: "flame.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(NanoTheme.orange)
            .frame(width: size * 0.78, height: size)
    }

    private struct AnimationValues {
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
    }
}

struct WeekProgressStrip: View {
    let records: [DailyStepRecord]
    let dailyGoal: Int

    private struct Day: Identifiable {
        let date: Date
        let steps: Int

        var id: Date { date }
    }

    private var week: [Day] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
        let stepsByDay = Dictionary(
            records.map { (calendar.startOfDay(for: $0.day), $0.steps) },
            uniquingKeysWith: { _, latest in latest }
        )

        return (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: start) else {
                return nil
            }
            return Day(date: date, steps: stepsByDay[date] ?? 0)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(week) { day in
                VStack(spacing: 4) {
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.black))
                        .foregroundStyle(
                            Calendar.autoupdatingCurrent.isDateInToday(day.date)
                                ? NanoTheme.teal
                                : NanoTheme.secondaryText
                        )

                    Circle()
                        .fill(day.steps >= dailyGoal ? NanoTheme.teal.opacity(0.20) : .clear)
                        .stroke(
                            Calendar.autoupdatingCurrent.isDateInToday(day.date)
                                ? NanoTheme.teal
                                : NanoTheme.teal.opacity(day.steps > 0 ? 0.35 : 0.14),
                            lineWidth: 2
                        )
                        .overlay {
                            if day.steps >= dailyGoal {
                                Image(systemName: "checkmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(NanoTheme.teal)
                            }
                        }
                        .frame(width: 30, height: 30)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NanoTheme.teal.opacity(0.055))
                .stroke(NanoTheme.teal.opacity(0.35), lineWidth: 1.1)
        )
    }
}

enum ProgressMilestone: String {
    case hatch = "HATCH"
    case evolve = "EVOLVE"
    case mature = "MATURE"

    var accessibilityName: String {
        rawValue.lowercased()
    }
}

struct CreatureResearchHero: View {
    let stage: CreatureStage
    let progress: Double
    let stepsRemaining: Int
    let nextMilestone: ProgressMilestone
    let isSyncingSteps: Bool
    let isEvolutionLocked: Bool
    /// Shown while locked: today's steps since evolution locked.
    var uncountedSteps = 0
    let animationEnergy: Double
    @Binding var showStepsRemaining: Bool
    let ringDiameter: CGFloat
    let onEXPBadgeTap: () -> Void
    let onCreatureTap: () -> Void
    var onNameTap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ProgressRing(
                    progress: progress,
                    stage: stage,
                    energy: animationEnergy
                )
                    .frame(width: ringDiameter, height: ringDiameter)
                    .appTourTarget(.ring)
                    .contentShape(Circle())
                    .onTapGesture(perform: onCreatureTap)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Open \(stage.name) specimen profile")

                VStack(spacing: 3) {
                    Text("STAGE \(stage.stage)")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.9)
                        .foregroundStyle(NanoTheme.secondaryText)

                    Button(action: onEXPBadgeTap) {
                        HStack(spacing: 7) {
                            if isSyncingSteps {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(NanoTheme.teal)
                            } else if isEvolutionLocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11, weight: .black))
                            }

                            Text(
                                isSyncingSteps
                                    ? "SYNCING STEPS"
                                    : isEvolutionLocked
                                        ? "UPGRADE TO EVOLVE"
                                    : showStepsRemaining
                                        ? "\(stepsRemaining.formatted()) TO \(nextMilestone.rawValue)"
                                        : "\(Int(progress * 100))% EXP"
                            )
                            .font(
                                .system(
                                    size: isEvolutionLocked ? 12 : 14,
                                    weight: .bold,
                                    design: .rounded
                                )
                                .monospacedDigit()
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        }
                        .tracking(1.0)
                        .foregroundStyle(isEvolutionLocked ? NanoTheme.orange : NanoTheme.teal)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(NanoTheme.background.opacity(0.90))
                                .stroke(
                                    (isEvolutionLocked ? NanoTheme.orange : NanoTheme.teal)
                                        .opacity(0.62),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .appTourTarget(.expBadge)
                    .id(AppTourTarget.expBadge)
                    .accessibilityLabel(
                        isEvolutionLocked
                            ? "Evolution is locked. Upgrade to Pro to evolve \(stage.name)."
                            : "\(stepsRemaining) steps to \(nextMilestone.accessibilityName)"
                    )
                }
                .offset(y: 20)
            }
            .padding(.bottom, 24)

            if let onNameTap {
                Button(action: onNameTap) { creatureName }
                    .buttonStyle(.plain)
                    .accessibilityHint("Adds 100 simulated steps")
            } else {
                creatureName
            }
            if isEvolutionLocked {
                // One line that never wraps, so it can't push Home down.
                Text(uncountedSteps > 0
                     ? "\(uncountedSteps.formatted()) steps aren’t counting toward evolution."
                     : "Upgrade so your steps count toward evolution.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NanoTheme.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.numericText(value: Double(uncountedSteps)))
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var creatureName: some View {
        Text(stage.name)
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

struct TodayStepsSection: View {
    let steps: Double
    let dailyGoal: Int
    let animationEnergy: Double

    private var progress: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(steps / Double(dailyGoal), 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("TODAY'S STEPS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2.7)
                .foregroundStyle(NanoTheme.teal.opacity(0.88))

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                EnergizedStepCounter(
                    value: steps,
                    energy: animationEnergy
                )
                    .font(.system(size: 52, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("/ \(dailyGoal.formatted())")
                    .font(.system(size: 18, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(NanoTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NanoTheme.teal.opacity(0.10))
                        .stroke(NanoTheme.teal.opacity(0.30), lineWidth: 1)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [NanoTheme.teal, NanoTheme.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * progress)
                        .shadow(color: NanoTheme.teal.opacity(0.55), radius: 8)
                }
            }
            .frame(height: 8)
            .padding(.top, 14)
        }
    }
}

private struct EnergizedStepCounter: View {
    let value: Double
    let energy: Double

    var body: some View {
        ZStack {
            CountingStepText(value: value)

            CountingStepText(value: value)
                .foregroundStyle(NanoTheme.cyan)
                .opacity(energy * 0.24)
                .blur(radius: 5 + 5 * energy)
                .blendMode(.plusLighter)
        }
        .scaleEffect(1 + 0.018 * energy)
        .shadow(
            color: NanoTheme.teal.opacity(0.46 * energy),
            radius: 8 + 10 * energy
        )
    }
}

private struct CountingStepText: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(max(0, Int(value.rounded(.down))).formatted())
    }
}

struct DailyMetricsPanel: View {
    let distanceKilometers: Double
    let distanceUnit: DistanceUnitPreference
    let calories: Int
    let activeMinutes: Int

    var body: some View {
        HStack(spacing: 0) {
            MetricColumn(
                icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                value: distanceUnit.value(fromKilometers: distanceKilometers)
                    .formatted(.number.precision(.fractionLength(1))),
                unit: distanceUnit.abbreviation,
                title: "DISTANCE",
                color: NanoTheme.teal
            )
            Divider().overlay(NanoTheme.teal.opacity(0.22)).frame(height: 62)
            MetricColumn(
                icon: "flame.fill",
                value: calories.formatted(),
                unit: "KCAL",
                title: "CALORIES",
                color: NanoTheme.orange
            )
            Divider().overlay(NanoTheme.teal.opacity(0.22)).frame(height: 62)
            MetricColumn(
                icon: "timer",
                value: activeMinutes.formatted(),
                unit: "MIN",
                title: "ACTIVE TIME",
                color: NanoTheme.green
            )
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NanoTheme.teal.opacity(0.05))
                .stroke(NanoTheme.teal.opacity(0.35), lineWidth: 1.1)
        )
    }
}

private struct MetricColumn: View {
    let icon: String
    let value: String
    let unit: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .lineLimit(1).minimumScaleFactor(0.75)
                .font(.system(size: 21, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.62), value: value)
            Text(unit)
                .lineLimit(1).minimumScaleFactor(0.75)
                .font(.system(size: 8, weight: .black))
                .tracking(1.1)
                .foregroundStyle(NanoTheme.secondaryText)
            Text(title)
                .font(.system(size: 7, weight: .black))
                .tracking(0.9)
                .foregroundStyle(NanoTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }
}
