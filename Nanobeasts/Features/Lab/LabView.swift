import SwiftUI
import UIKit

struct LabView: View {
    @Environment(AppStore.self) private var store
    @State private var showStepsRemaining = false
    @State private var activeSheet: LabSheet?
    @State private var animatedTodaySteps = 0.0
    @State private var animatedHatchProgress = 0.0
    @State private var hasInitializedActivityAnimation = false
    @State private var stepAnimationEnergy = 0.0
    @State private var goalConfettiID: UUID?
    @State private var showsDailyGoalCard = false
    @State private var pendingDailyGoalCelebration = false
    @AppStorage("nanobeasts.testing.stepButtonEnabled")
    private var testingStepButtonEnabled = false
    @AppStorage("nanobeasts.lastDailyGoalCelebration")
    private var lastDailyGoalCelebration = ""

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            GeometryReader { proxy in
                let heroDiameter = min(252, max(220, proxy.size.height * 0.30))

                ScrollView {
                    VStack(spacing: 0) {
                        LabHeader(
                            greeting: greeting,
                            playerName: store.playerName,
                            streak: store.currentStreak,
                            onStreakTap: { activeSheet = .streak }
                        )

                        Spacer(minLength: 14)

                        Button {
                            activeSheet = .streak
                        } label: {
                            WeekProgressStrip(
                                records: store.recentWeek,
                                dailyGoal: store.dailyGoal
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 22)

                        CreatureResearchHero(
                            stage: store.currentStage,
                            progress: animatedHatchProgress,
                            stepsRemaining: max(
                                store.currentTarget - store.hatchProgressSteps,
                                0
                            ),
                            isSyncingSteps: store.isSyncingSteps,
                            animationEnergy: stepAnimationEnergy,
                            showStepsRemaining: $showStepsRemaining,
                            ringDiameter: heroDiameter,
                            onCreatureTap: { activeSheet = .creature }
                        )

                        Spacer(minLength: 18)

                        TodayStepsSection(
                            steps: animatedTodaySteps,
                            dailyGoal: store.dailyGoal,
                            animationEnergy: stepAnimationEnergy
                        )

                        Spacer(minLength: 24)

                        DailyMetricsPanel(
                            distanceKilometers: store.distanceKilometersToday,
                            distanceUnit: store.distanceUnit,
                            calories: store.caloriesToday,
                            activeMinutes: store.activeMinutesToday
                        )
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                    .frame(minHeight: max(proxy.size.height - 4, 0))
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .refreshable {
                    await refresh()
                }
            }

            if testingStepButtonEnabled {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            let wasAlreadyComplete =
                                store.todaySteps >= store.dailyGoal
                            store.addTestingSteps()
                            if wasAlreadyComplete {
                                presentDailyGoalCelebrationIfNeeded()
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            Label("+100", systemImage: "figure.walk.motion")
                                .font(NanoFont.aldrich(10))
                                .tracking(0.8)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 15)
                                .frame(height: 44)
                                .background(
                                    Capsule()
                                        .fill(NanoTheme.teal)
                                        .shadow(color: NanoTheme.teal.opacity(0.40), radius: 12)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add 100 test steps")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
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
                    creatureName: store.currentStage.name
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
            animatedTodaySteps = Double(store.todaySteps)
            animatedHatchProgress = store.hatchProgress
            hasInitializedActivityAnimation = true
        }
        .onChange(of: store.evolutionEventID) {
            guard store.hapticsEnabled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .onChange(of: store.currentStage.id) {
            animatedHatchProgress = store.hatchProgress
            showStepsRemaining = false
            stepAnimationEnergy = 0
        }
        .task(id: showStepsRemaining) {
            guard showStepsRemaining else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            showStepsRemaining = false
        }
        .task(id: store.stepSyncAnimationID) {
            guard store.consumeStepSyncAnimationIfNeeded() else {
                animatedTodaySteps = Double(store.todaySteps)
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
                animatedTodaySteps = Double(store.todaySteps)
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .streak:
                StreakSummaryView(
                    streak: store.currentStreak,
                    records: store.recentWeek,
                    dailyGoal: store.dailyGoal
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            case .creature:
                CreatureDetailView(stage: store.currentStage, isLocked: false)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
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

    private func refresh() async {
        await store.refreshHealthData()
    }

    private func presentDailyGoalCelebrationIfNeeded() {
        guard store.pendingLifecycleEvents.isEmpty else {
            pendingDailyGoalCelebration = true
            return
        }

        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day],
            from: Date()
        )
        let celebrationKey = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        guard lastDailyGoalCelebration != celebrationKey else { return }

        lastDailyGoalCelebration = celebrationKey
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
                    "Today counts toward your streak. Every extra step still powers \(creatureName)’s evolution."
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

private struct LabHeader: View {
    let greeting: String
    let playerName: String
    let streak: Int
    let onStreakTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(greeting),")
                    .font(.system(size: 13, weight: .regular))
                    .tracking(1.4)
                    .foregroundStyle(NanoTheme.secondaryText)
                Text(playerName.isEmpty ? "RESEARCHER" : playerName.uppercased())
                    .font(.system(size: 25, weight: .bold))
                    .tracking(2.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("Let's evolve today.")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(0.4)
                    .foregroundStyle(NanoTheme.secondaryText)
            }

            Spacer(minLength: 4)

            Button(action: onStreakTap) {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.title3)
                        .foregroundStyle(NanoTheme.orange)
                        .shadow(color: NanoTheme.orange.opacity(0.45), radius: 7)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(streak.formatted())
                            .font(.title3.monospacedDigit().bold())
                        Text("DAY\nSTREAK")
                            .font(.system(size: 7, weight: .black))
                            .tracking(1.1)
                            .foregroundStyle(NanoTheme.secondaryText)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NanoTheme.secondaryText.opacity(0.75))
                }
                .frame(width: 118)
                .frame(minHeight: 60)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(NanoTheme.teal.opacity(0.07))
                        .stroke(NanoTheme.teal.opacity(0.42), lineWidth: 1.2)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(streak) day streak. Show weekly streak details.")
        }
    }
}

private struct WeekProgressStrip: View {
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

private struct CreatureResearchHero: View {
    let stage: CreatureStage
    let progress: Double
    let stepsRemaining: Int
    let isSyncingSteps: Bool
    let animationEnergy: Double
    @Binding var showStepsRemaining: Bool
    let ringDiameter: CGFloat
    let onCreatureTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ProgressRing(
                    progress: progress,
                    stage: stage,
                    energy: animationEnergy
                )
                    .frame(width: ringDiameter, height: ringDiameter)
                    .contentShape(Circle())
                    .onTapGesture(perform: onCreatureTap)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Open \(stage.name) specimen profile")

                VStack(spacing: 3) {
                    Text("STAGE \(stage.stage)")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.9)
                        .foregroundStyle(NanoTheme.secondaryText)

                    Button {
                        showStepsRemaining = true
                    } label: {
                        HStack(spacing: 7) {
                            if isSyncingSteps {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(NanoTheme.teal)
                            }
                            Text(
                                isSyncingSteps
                                    ? "SYNCING STEPS"
                                    : showStepsRemaining
                                        ? "\(stepsRemaining.formatted()) TO GO"
                                        : "\(Int(progress * 100))% EXP"
                            )
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                        .tracking(1.0)
                        .foregroundStyle(NanoTheme.teal)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(NanoTheme.background.opacity(0.90))
                                .stroke(NanoTheme.teal.opacity(0.62), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(stepsRemaining) steps remaining until evolution")
                }
                .offset(y: 20)
            }
            .padding(.bottom, 24)

            Text(stage.name)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StreakSummaryView: View {
    let streak: Int
    let records: [DailyStepRecord]
    let dailyGoal: Int

    @Environment(\.dismiss) private var dismiss

    private var days: [(date: Date, steps: Int)] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let start = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        let lookup = Dictionary(
            records.map { (calendar.startOfDay(for: $0.day), $0.steps) },
            uniquingKeysWith: { _, latest in latest }
        )
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            return (date, lookup[date] ?? 0)
        }
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            VStack(spacing: 24) {
                HStack(spacing: 14) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(NanoTheme.orange)
                        .frame(width: 54, height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 17)
                                .fill(NanoTheme.orange.opacity(0.10))
                                .stroke(NanoTheme.orange.opacity(0.42), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("STREAK STATUS")
                            .font(NanoFont.aldrich(10))
                            .tracking(1.4)
                            .foregroundStyle(NanoTheme.orange)
                        Text("\(streak) DAY\(streak == 1 ? "" : "S")")
                            .font(NanoFont.aldrich(26))
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                }

                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 8) {
                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(NanoFont.aldrich(10))
                                .foregroundStyle(NanoTheme.secondaryText)
                            Circle()
                                .fill(
                                    day.steps >= dailyGoal
                                        ? NanoTheme.orange
                                        : NanoTheme.elevated
                                )
                                .overlay {
                                    if day.steps >= dailyGoal {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.bold())
                                            .foregroundStyle(NanoTheme.background)
                                    }
                                }
                                .frame(width: 34, height: 34)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Text(
                    streak > 0
                        ? "Keep reaching your daily step goal to protect your research streak."
                        : "Reach your daily step goal to ignite a new research streak."
                )
                .font(NanoFont.aldrich(11))
                .foregroundStyle(NanoTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            }
            .padding(22)
        }
    }
}

private struct TodayStepsSection: View {
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
                .font(.system(size: 10, weight: .black))
                .tracking(2.1)
                .foregroundStyle(NanoTheme.teal.opacity(0.78))

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                EnergizedStepCounter(
                    value: steps,
                    energy: animationEnergy
                )
                    .font(.system(size: 46, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("/ \(dailyGoal.formatted())")
                    .font(.system(size: 17, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(NanoTheme.secondaryText)
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

private struct DailyMetricsPanel: View {
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
                .font(.system(size: 21, weight: .semibold, design: .rounded).monospacedDigit())
            Text(unit)
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
