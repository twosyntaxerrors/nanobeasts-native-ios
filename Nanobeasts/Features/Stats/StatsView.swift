import Charts
import Combine
import SwiftUI

struct StatsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTourFocus) private var tourFocus
    @StateObject private var workoutHistoryStore: WorkoutHistoryStore
    @State private var calendarScope: StatsCalendarScope = .month
    @State private var monthOffset = 0
    @State private var presentation = StatsPresentationSnapshot.empty

    init(historyDefaults: UserDefaults = .standard) {
        _workoutHistoryStore = StateObject(wrappedValue: WorkoutHistoryStore(defaults: historyDefaults))
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StatsScreenHeader()

                        LifetimeMovementCard(
                            steps: presentation.totalSteps,
                            trackedDays: presentation.trackedDays,
                            unlockedBadges: presentation.unlockedBadgeCount,
                            totalBadges: presentation.totalBadgeCount,
                            rangeLabel: presentation.rangeLabel,
                            distanceUnit: store.distanceUnit
                        )

                        ActivityConsistencyHeader(scope: $calendarScope)

                        ActivityCalendarCard(
                            scope: calendarScope,
                            monthOffset: $monthOffset,
                            records: store.analyticsHistory,
                            dailyGoal: store.dailyGoal,
                            discoveryEvents: store.discoveryEvents,
                            workouts: workoutHistoryStore.workouts,
                            importedHistoryRange: store.appleHealthImportedHistoryRange,
                            distanceUnit: store.distanceUnit
                        )
                        .appTourTarget(.stats)
                        .id(AppTourTarget.stats)

                        SimpleStepInsightsCard(
                            records: store.analyticsHistory,
                            hourlyRecords: store.hourlyAnalyticsHistory,
                            todaySteps: store.displayedTodaySteps,
                            dailyGoal: store.dailyGoal
                        )
                        .id("actionable-insights")

                        RecentAchievementsRow(sections: presentation.badgeSections)
                            .appTourTarget(.badges)
                            .id(AppTourTarget.badges)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .task(id: tourFocus) {
                    guard let tourFocus, tourFocus == .stats || tourFocus == .badges else { return }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(tourFocus, anchor: tourFocus == .badges ? .bottom : .top)
                }
                .refreshable {
                    await store.refreshHealthData()
                }
                .task {
                    switch AppScreenshotScenario.active {
                    case .insights:
                        try? await Task.sleep(for: .milliseconds(420))
                        guard !Task.isCancelled else { return }
                        proxy.scrollTo("actionable-insights", anchor: .top)
                    case .featureTourStats:
                        try? await Task.sleep(for: .seconds(1.3))
                        guard !Task.isCancelled else { return }
                        calendarScope = .week
                        try? await Task.sleep(for: .seconds(1.3))
                        guard !Task.isCancelled else { return }
                        calendarScope = .month
                        try? await Task.sleep(for: .seconds(0.9))
                        guard !Task.isCancelled else { return }
                        withAnimation(.smooth(duration: 1.1)) {
                            proxy.scrollTo("actionable-insights", anchor: .top)
                        }
                    default:
                        return
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            workoutHistoryStore.reload()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: WorkoutHistoryStore.didChangeNotification
            )
        ) { _ in
            workoutHistoryStore.reload()
        }
        .task(
            id: StatsPresentationRefreshID(
                badgeEvaluationID: store.badgeEvaluationID,
                evolutionEventID: store.evolutionEventID,
                distanceUnit: store.distanceUnit.rawValue,
                dailyGoal: store.dailyGoal,
                dailyGoalHistory: store.dailyGoalHistory,
                journeyDayCount: store.journeyDayCount
            )
        ) {
            let input = StatsPresentationInput(
                journeyRecords: store.badgeEvaluationHistory,
                journeyDayCount: store.journeyDayCount,
                dailyGoal: store.dailyGoal,
                dailyGoalHistory: store.dailyGoalHistory,
                discoveredStages: store.catalog.creatureStages.filter {
                    store.isDiscovered($0) || store.isCurrent($0)
                },
                discoveryEvents: store.discoveryEvents,
                rangeLabel: store.journeyRangeLabel,
                distanceUnit: store.distanceUnit
            )

            // Commit the tab transition first, then calculate the badge catalog
            // away from the main actor. The retained snapshot makes repeat
            // visits immediate while fresh Health data is processed.
            await Task.yield()
            let prepared = await Task.detached(priority: .userInitiated) {
                StatsPresentationSnapshot(input: input)
            }.value
            guard !Task.isCancelled else { return }
            presentation = prepared
        }
    }
}

private struct StatsPresentationRefreshID: Equatable {
    let badgeEvaluationID: UUID
    let evolutionEventID: UUID
    let distanceUnit: String
    let dailyGoal: Int
    let dailyGoalHistory: [DailyGoalRecord]
    let journeyDayCount: Int
}

private struct StatsPresentationInput: Sendable {
    let journeyRecords: [DailyStepRecord]
    let journeyDayCount: Int
    let dailyGoal: Int
    let dailyGoalHistory: [DailyGoalRecord]
    let discoveredStages: [CreatureStage]
    let discoveryEvents: [CreatureDiscoveryEvent]
    let rangeLabel: String
    let distanceUnit: DistanceUnitPreference
}

private struct StatsPresentationSnapshot {
    let totalSteps: Int
    let trackedDays: Int
    let unlockedBadgeCount: Int
    let totalBadgeCount: Int
    let rangeLabel: String
    let badgeSections: [StatsBadgeSection]

    static let empty = StatsPresentationSnapshot(
        totalSteps: 0,
        trackedDays: 0,
        unlockedBadgeCount: 0,
        totalBadgeCount: 0,
        rangeLabel: "YOUR JOURNEY",
        badgeSections: []
    )

    init(input: StatsPresentationInput) {
        let badgeSections = StatsBadgeCatalog.make(
            records: input.journeyRecords,
            dailyGoal: input.dailyGoal,
            dailyGoalHistory: input.dailyGoalHistory,
            discoveredStages: input.discoveredStages,
            distanceUnit: input.distanceUnit,
            discoveryEvents: input.discoveryEvents
        )
        let allBadges = badgeSections.flatMap(\.badges)

        totalSteps = input.journeyRecords.reduce(0) { $0 + $1.steps }
        trackedDays = input.journeyDayCount
        unlockedBadgeCount = allBadges.lazy.filter(\.unlocked).count
        totalBadgeCount = allBadges.count
        rangeLabel = input.rangeLabel
        self.badgeSections = badgeSections
    }

    private init(
        totalSteps: Int,
        trackedDays: Int,
        unlockedBadgeCount: Int,
        totalBadgeCount: Int,
        rangeLabel: String,
        badgeSections: [StatsBadgeSection]
    ) {
        self.totalSteps = totalSteps
        self.trackedDays = trackedDays
        self.unlockedBadgeCount = unlockedBadgeCount
        self.totalBadgeCount = totalBadgeCount
        self.rangeLabel = rangeLabel
        self.badgeSections = badgeSections
    }
}

enum StatsCalendarScope: String, CaseIterable, Identifiable {
    case month = "MONTH"
    case week = "WEEK"

    var id: String { rawValue }
}

private struct SimpleStepInsightsCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let records: [DailyStepRecord]
    let hourlyRecords: [HourlyStepRecord]
    let todaySteps: Int
    let dailyGoal: Int
    @State private var range: SimpleInsightRange = .week
    @AppStorage("nanobeasts.stats.insightsExpanded")
    private var isExpanded = true

    private var snapshot: SimpleInsightSnapshot {
        SimpleInsightSnapshot(records: records, range: range, dailyGoal: dailyGoal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            disclosureHeader

            Group {
                if isExpanded {
                    expandedInsights
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .offset(y: -8))
                        )
                } else {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        collapsedPace(
                            TimeOfDayPaceSnapshot(
                                hourlyRecords: hourlyRecords,
                                todaySteps: todaySteps,
                                dailyGoal: dailyGoal,
                                now: context.date
                            )
                        )
                    }
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .offset(y: 6))
                    )
                }
            }
            .padding(.top, 16)
        }
        .padding(16)
        .nanoHUDCard(tint: NanoTheme.teal, padding: 0, illuminated: true)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.10)
                : .timingCurve(0.23, 1, 0.32, 1, duration: 0.20),
            value: range
        )
        .animation(disclosureAnimation, value: isExpanded)
        .task {
            guard AppScreenshotScenario.active == .featureTourStats else { return }
            isExpanded = true
            range = .week
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            range = .month
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            range = .year
        }
    }

    private var disclosureAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.10)
            : .timingCurve(0.23, 1, 0.32, 1, duration: 0.24)
    }

    private var disclosureHeader: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step insights")
                        .font(NanoFont.aldrich(18))
                        .foregroundStyle(.white)
                    Text(
                        isExpanded
                            ? "Your movement trends and goal history."
                            : "Today compared with your goal pace."
                    )
                    .font(NanoFont.spaceMono(10))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .contentTransition(.opacity)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NanoTheme.teal)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(NanoTheme.teal.opacity(0.10))
                            .stroke(NanoTheme.teal.opacity(0.34), lineWidth: 1)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SimpleInsightPressStyle())
        .accessibilityLabel(isExpanded ? "Collapse step insights" : "Expand step insights")
        .accessibilityHint(
            isExpanded
                ? "Shows today's goal pace chart"
                : "Shows the complete step trend charts"
        )
    }

    private var expandedInsights: some View {
        VStack(alignment: .leading, spacing: 18) {
            rangePicker

            VStack(alignment: .leading, spacing: 2) {
                Text("DAILY AVERAGE")
                    .font(NanoFont.aldrich(9))
                    .tracking(0.8)
                    .foregroundStyle(NanoTheme.secondaryText)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(snapshot.averageSteps.formatted())
                        .font(NanoFont.aldrich(34))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("steps")
                        .font(NanoFont.aldrich(11))
                        .foregroundStyle(NanoTheme.secondaryText)
                }

                Text(range.periodLabel)
                    .font(NanoFont.spaceMono(9))
                    .foregroundStyle(NanoTheme.mutedText)
            }

            simpleChart

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: snapshot.comparisonSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(snapshot.comparisonTint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(snapshot.comparisonTint.opacity(0.12)))

                Text(snapshot.comparisonText)
                    .font(NanoFont.spaceMono(11))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                SimpleInsightMetric(
                    title: "TOTAL STEPS",
                    value: snapshot.totalSteps.formatted(),
                    detail: range.periodLabel
                )
                SimpleInsightMetric(
                    title: "GOAL DAYS",
                    value: "\(snapshot.goalDays) of \(snapshot.dayCount)",
                    detail: "Reached \(dailyGoal.formatted()) steps"
                )
            }

            if let bestDayText = snapshot.bestDayText {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(NanoTheme.orange)
                    Text(bestDayText)
                        .font(NanoFont.spaceMono(10))
                        .foregroundStyle(NanoTheme.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func collapsedPace(_ pace: TimeOfDayPaceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: pace.statusSymbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(pace.tint)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(pace.tint.opacity(0.13)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(pace.statusTitle)
                        .font(NanoFont.aldrich(11))
                        .tracking(0.7)
                        .foregroundStyle(pace.tint)
                    Text(pace.statusDetail)
                        .font(NanoFont.spaceMono(9))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Chart {
                ForEach(pace.goalPoints) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Goal pace", point.steps),
                        series: .value("Series", "Goal pace")
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(NanoTheme.secondaryText.opacity(0.58))
                    .lineStyle(StrokeStyle(lineWidth: 1.3, dash: [4, 4]))
                }

                ForEach(pace.actualPoints) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Today's steps", point.steps),
                        series: .value("Series", "Today")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(pace.tint)
                    .lineStyle(
                        StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                }

                if let latest = pace.actualPoints.last {
                    PointMark(
                        x: .value("Current time", latest.date),
                        y: .value("Current steps", latest.steps)
                    )
                    .foregroundStyle(pace.tint)
                    .symbolSize(42)
                }
            }
            .chartXScale(domain: pace.chartStart...pace.chartEnd)
            .chartYScale(domain: 0...pace.chartMaximum)
            .chartXAxis {
                AxisMarks(values: pace.axisValues) { value in
                    AxisGridLine().foregroundStyle(NanoTheme.elevated.opacity(0.52))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.hour(.defaultDigits(amPM: .narrow))))
                                .font(NanoFont.aldrich(7))
                                .foregroundStyle(NanoTheme.mutedText)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(NanoTheme.elevated.opacity(0.52))
                    AxisValueLabel {
                        if let steps = value.as(Int.self) {
                            Text(steps.formatted(.number.notation(.compactName)))
                                .font(NanoFont.aldrich(7))
                                .foregroundStyle(NanoTheme.mutedText)
                        }
                    }
                }
            }
            .frame(height: 145)

            HStack(spacing: 16) {
                PaceLegend(color: pace.tint, title: "TODAY")
                PaceLegend(
                    color: NanoTheme.secondaryText,
                    title: "GOAL PACE",
                    dashed: true
                )
                Spacer()
                Text(pace.currentTimeLabel)
                    .font(NanoFont.aldrich(7))
                    .foregroundStyle(NanoTheme.mutedText)
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(pace.tint.opacity(0.055))
                .stroke(pace.tint.opacity(0.30), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pace.statusTitle). \(pace.statusDetail)")
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(SimpleInsightRange.allCases) { option in
                Button {
                    range = option
                } label: {
                    Text(option.rawValue)
                        .font(NanoFont.aldrich(10))
                        .foregroundStyle(
                            range == option ? NanoTheme.background : NanoTheme.secondaryText
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            Capsule()
                                .fill(range == option ? NanoTheme.teal : .clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(SimpleInsightPressStyle())
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(NanoTheme.background.opacity(0.78))
                .stroke(NanoTheme.elevated, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trend range")
    }

    @ViewBuilder
    private var simpleChart: some View {
        if snapshot.totalSteps == 0 {
            ContentUnavailableView(
                "No steps yet",
                systemImage: "chart.bar.fill",
                description: Text("Your step history will appear here.")
            )
            .frame(height: 190)
            .foregroundStyle(NanoTheme.secondaryText)
        } else {
            Chart {
                ForEach(snapshot.points) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: range.calendarUnit),
                        y: .value("Steps", point.steps),
                        width: .ratio(range == .week ? 0.58 : 0.68)
                    )
                    .foregroundStyle(
                        point.steps >= dailyGoal
                            ? NanoTheme.teal
                            : NanoTheme.teal.opacity(0.42)
                    )
                    .cornerRadius(4)
                }

                RuleMark(y: .value("Daily goal", dailyGoal))
                    .foregroundStyle(NanoTheme.orange.opacity(0.72))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("GOAL")
                            .font(NanoFont.aldrich(7))
                            .foregroundStyle(NanoTheme.orange)
                    }
            }
            .chartYScale(domain: 0...snapshot.chartMaximum)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                        .foregroundStyle(NanoTheme.elevated.opacity(0.6))
                    AxisValueLabel {
                        if let steps = value.as(Int.self) {
                            Text(steps.formatted(.number.notation(.compactName)))
                                .font(NanoFont.aldrich(8))
                                .foregroundStyle(NanoTheme.mutedText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: range.axisLabelCount)) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel(format: range.axisFormat)
                        .font(NanoFont.aldrich(8))
                        .foregroundStyle(NanoTheme.mutedText)
                }
            }
            .frame(height: 190)
            .accessibilityLabel(
                "\(range.periodLabel). Daily average \(snapshot.averageSteps) steps."
            )
        }
    }
}

private struct SimpleInsightMetric: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(NanoFont.aldrich(8))
                .tracking(0.65)
                .foregroundStyle(NanoTheme.secondaryText)
            Text(value)
                .font(NanoFont.aldrich(18))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(detail)
                .font(NanoFont.spaceMono(8))
                .foregroundStyle(NanoTheme.mutedText)
                .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(NanoTheme.background.opacity(0.54))
                .stroke(NanoTheme.elevated.opacity(0.9), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value), \(detail)")
    }
}

private struct PaceLegend: View {
    let color: Color
    let title: String
    var dashed = false

    var body: some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: 18, height: 2)
                .overlay {
                    if dashed {
                        HStack(spacing: 3) {
                            Color.clear.frame(width: 3)
                            NanoTheme.background.frame(width: 3)
                            Color.clear.frame(width: 3)
                            NanoTheme.background.frame(width: 3)
                            Color.clear.frame(width: 3)
                        }
                        .clipShape(Capsule())
                    }
                }

            Text(title)
                .font(NanoFont.aldrich(7))
                .tracking(0.55)
                .foregroundStyle(NanoTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TimeOfDayPacePoint: Identifiable {
    let date: Date
    let steps: Int

    var id: Date { date }
}

private struct TimeOfDayPaceSnapshot {
    let actualPoints: [TimeOfDayPacePoint]
    let goalPoints: [TimeOfDayPacePoint]
    let chartStart: Date
    let chartEnd: Date
    let axisValues: [Date]
    let chartMaximum: Int
    let currentSteps: Int
    let expectedSteps: Int
    let difference: Int
    let tint: Color
    let statusTitle: String
    let statusDetail: String
    let statusSymbol: String
    let currentTimeLabel: String

    init(
        hourlyRecords: [HourlyStepRecord],
        todaySteps: Int,
        dailyGoal: Int,
        now: Date
    ) {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: today)
            ?? today
        let end = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: today)
            ?? today.addingTimeInterval(22 * 60 * 60)
        let marker = min(max(now, start), end)
        let goal = max(dailyGoal, 1)
        let activeDuration = max(end.timeIntervalSince(start), 1)
        let elapsed = min(max(marker.timeIntervalSince(start), 0), activeDuration)
        let scheduledSteps = Int(
            (Double(goal) * elapsed / activeDuration).rounded()
        )

        let todayHourly = hourlyRecords
            .filter { calendar.isDate($0.start, inSameDayAs: today) }
            .sorted { $0.start < $1.start }
        let hourlyTotal = todayHourly.reduce(0) { $0 + max($1.steps, 0) }
        let resolvedTodaySteps = max(max(todaySteps, 0), hourlyTotal)

        var cumulative = todayHourly
            .filter { $0.start < start }
            .reduce(0) { $0 + max($1.steps, 0) }
        var resolvedActualPoints = [
            TimeOfDayPacePoint(date: start, steps: cumulative)
        ]

        for record in todayHourly where record.start >= start && record.start < end {
            guard record.start <= now else { break }
            cumulative += max(record.steps, 0)
            let hourEnd = calendar.date(byAdding: .hour, value: 1, to: record.start)
                ?? record.start
            let pointDate = min(max(hourEnd, start), marker)
            Self.append(
                TimeOfDayPacePoint(date: pointDate, steps: cumulative),
                to: &resolvedActualPoints
            )
        }
        Self.append(
            TimeOfDayPacePoint(date: marker, steps: resolvedTodaySteps),
            to: &resolvedActualPoints
        )

        let resolvedGoalPoints = stride(from: 0, through: 16, by: 2).compactMap { offset
            -> TimeOfDayPacePoint? in
            guard let date = calendar.date(byAdding: .hour, value: offset, to: start)
            else { return nil }
            let progress = Double(offset) / 16
            return TimeOfDayPacePoint(
                date: date,
                steps: Int((Double(goal) * progress).rounded())
            )
        }

        currentSteps = resolvedTodaySteps
        expectedSteps = scheduledSteps
        difference = resolvedTodaySteps - scheduledSteps
        chartStart = start
        chartEnd = end
        actualPoints = resolvedActualPoints
        goalPoints = resolvedGoalPoints
        axisValues = [6, 12, 18, 22].compactMap { hour in
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: today)
        }
        chartMaximum = max(
            Int((Double(max(goal, resolvedTodaySteps)) * 1.12).rounded(.up)),
            1
        )

        let isAhead = difference >= 0
        tint = isAhead ? NanoTheme.green : NanoTheme.orange
        if difference > 0 {
            statusTitle = "\(difference.formatted()) STEPS AHEAD"
            statusSymbol = "arrow.up.right.circle.fill"
        } else if difference < 0 {
            statusTitle = "\(abs(difference).formatted()) STEPS BEHIND"
            statusSymbol = "arrow.down.right.circle.fill"
        } else {
            statusTitle = "RIGHT ON GOAL PACE"
            statusSymbol = "checkmark.circle.fill"
        }

        let time = now.formatted(.dateTime.hour().minute())
        statusDetail =
            "By \(time), goal pace is \(scheduledSteps.formatted()) steps. You have \(resolvedTodaySteps.formatted())."
        currentTimeLabel = "UPDATED \(time.uppercased())"
    }

    private static func append(
        _ point: TimeOfDayPacePoint,
        to points: inout [TimeOfDayPacePoint]
    ) {
        if let lastIndex = points.indices.last,
           points[lastIndex].date == point.date {
            points[lastIndex] = point
        } else {
            points.append(point)
        }
    }
}

private struct SimpleInsightPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private enum SimpleInsightRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: Self { self }

    var dayCount: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .year: 365
        }
    }

    var periodLabel: String {
        switch self {
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .year: "Last 12 months"
        }
    }

    var comparisonPeriod: String {
        switch self {
        case .week: "the week before"
        case .month: "the previous 30 days"
        case .year: "the previous year"
        }
    }

    var calendarUnit: Calendar.Component {
        self == .year ? .month : .day
    }

    var axisLabelCount: Int {
        switch self {
        case .week: 7
        case .month: 5
        case .year: 6
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .week: .dateTime.weekday(.narrow)
        case .month: .dateTime.month(.abbreviated).day()
        case .year: .dateTime.month(.abbreviated)
        }
    }
}

private struct SimpleStepPoint: Identifiable {
    let date: Date
    let steps: Int

    var id: Date { date }
}

private struct SimpleInsightSnapshot {
    let points: [SimpleStepPoint]
    let averageSteps: Int
    let totalSteps: Int
    let goalDays: Int
    let dayCount: Int
    let comparisonText: String
    let comparisonSymbol: String
    let comparisonTint: Color
    let bestDayText: String?
    let chartMaximum: Int

    init(records: [DailyStepRecord], range: SimpleInsightRange, dailyGoal: Int) {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let currentStart: Date
        let previousStart: Date
        let previousEnd: Date

        switch range {
        case .week, .month:
            currentStart = calendar.date(
                byAdding: .day,
                value: -(range.dayCount - 1),
                to: today
            ) ?? today
            previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart) ?? currentStart
            previousStart = calendar.date(
                byAdding: .day,
                value: -range.dayCount,
                to: currentStart
            ) ?? currentStart
        case .year:
            let thisMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
            currentStart = calendar.date(byAdding: .month, value: -11, to: thisMonth) ?? thisMonth
            previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart) ?? currentStart
            previousStart = calendar.date(byAdding: .month, value: -12, to: currentStart) ?? currentStart
        }

        var totalsByDay: [Date: Int] = [:]
        for record in records {
            totalsByDay[calendar.startOfDay(for: record.day), default: 0] += record.steps
        }

        let currentDays = Self.dailyPoints(
            from: currentStart,
            through: today,
            totalsByDay: totalsByDay,
            calendar: calendar
        )
        let previousDays = Self.dailyPoints(
            from: previousStart,
            through: previousEnd,
            totalsByDay: totalsByDay,
            calendar: calendar
        )

        totalSteps = currentDays.reduce(0) { $0 + $1.steps }
        dayCount = currentDays.count
        averageSteps = dayCount > 0 ? totalSteps / dayCount : 0
        let previousTotal = previousDays.reduce(0) { $0 + $1.steps }
        let previousAverage = previousDays.isEmpty ? 0 : previousTotal / previousDays.count
        goalDays = currentDays.filter { $0.steps >= dailyGoal }.count

        if range == .year {
            let grouped = Dictionary(grouping: currentDays) { point in
                calendar.dateInterval(of: .month, for: point.date)?.start ?? point.date
            }
            points = grouped.map { month, values in
                SimpleStepPoint(
                    date: month,
                    steps: values.reduce(0) { $0 + $1.steps } / max(values.count, 1)
                )
            }
            .sorted { $0.date < $1.date }
        } else {
            points = currentDays
        }

        let difference = averageSteps - previousAverage
        let similarThreshold = max(200, Int(Double(max(previousAverage, 1)) * 0.05))
        if totalSteps == 0 {
            comparisonText = "Take a few steps to start building your trend."
            comparisonSymbol = "figure.walk"
            comparisonTint = NanoTheme.teal
        } else if previousTotal == 0 {
            comparisonText = "Keep walking and your first comparison will appear here."
            comparisonSymbol = "chart.bar.fill"
            comparisonTint = NanoTheme.cyan
        } else if abs(difference) <= similarThreshold {
            comparisonText = "You're moving about the same as \(range.comparisonPeriod)."
            comparisonSymbol = "equal"
            comparisonTint = NanoTheme.cyan
        } else if difference > 0 {
            comparisonText = "You're averaging \(difference.formatted()) more steps per day than \(range.comparisonPeriod)."
            comparisonSymbol = "arrow.up.right"
            comparisonTint = NanoTheme.teal
        } else {
            comparisonText = "You're averaging \(abs(difference).formatted()) fewer steps per day than \(range.comparisonPeriod)."
            comparisonSymbol = "arrow.down.right"
            comparisonTint = NanoTheme.orange
        }

        if let best = currentDays.max(by: { $0.steps < $1.steps }), best.steps > 0 {
            let day = best.date.formatted(.dateTime.weekday(.wide))
            bestDayText = "Your best day was \(day) with \(best.steps.formatted()) steps."
        } else {
            bestDayText = nil
        }

        let highestValue = max(points.map(\.steps).max() ?? 0, dailyGoal)
        chartMaximum = max(Int((Double(highestValue) * 1.15).rounded(.up)), 1)
    }

    private static func dailyPoints(
        from start: Date,
        through end: Date,
        totalsByDay: [Date: Int],
        calendar: Calendar
    ) -> [SimpleStepPoint] {
        guard start <= end else { return [] }
        var result: [SimpleStepPoint] = []
        var day = start
        while day <= end {
            result.append(SimpleStepPoint(date: day, steps: totalsByDay[day, default: 0]))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}
