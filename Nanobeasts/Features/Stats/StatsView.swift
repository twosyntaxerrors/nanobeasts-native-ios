import SwiftUI

struct StatsView: View {
    @Environment(AppStore.self) private var store
    @State private var calendarScope: StatsCalendarScope = .month
    @State private var monthOffset = 0
    @State private var presentation = StatsPresentationSnapshot.empty

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    StatsScreenHeader()

                    LifetimeMovementCard(
                        steps: presentation.totalSteps,
                        activeDays: presentation.activeDays,
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
                        distanceUnit: store.distanceUnit
                    )

                    ActionableInsightsCard(
                        analyticsRecords: store.analyticsHistory,
                        hourlyRecords: store.hourlyAnalyticsHistory,
                        journeyRecords: store.badgeEvaluationHistory,
                        goalHistory: store.dailyGoalHistory,
                        currentGoal: store.dailyGoal,
                        stepsRemaining: max(
                            store.currentTarget - store.hatchProgressSteps,
                            0
                        ),
                        creatureName: store.currentStage.name
                    )

                    RecentAchievementsRow(sections: presentation.badgeSections)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await store.refreshHealthData()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(
            id: "\(store.badgeEvaluationID.uuidString)-\(store.distanceUnit.rawValue)"
        ) {
            let input = StatsPresentationInput(
                analyticsRecords: store.analyticsHistory,
                journeyRecords: store.badgeEvaluationHistory,
                dailyGoal: store.dailyGoal,
                discoveredStages: store.catalog.creatureStages.filter {
                    store.isDiscovered($0) || store.isCurrent($0)
                },
                rangeLabel: store.analyticsRangeLabel,
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

private struct StatsPresentationInput: Sendable {
    let analyticsRecords: [DailyStepRecord]
    let journeyRecords: [DailyStepRecord]
    let dailyGoal: Int
    let discoveredStages: [CreatureStage]
    let rangeLabel: String
    let distanceUnit: DistanceUnitPreference
}

private struct StatsPresentationSnapshot {
    let totalSteps: Int
    let activeDays: Int
    let unlockedBadgeCount: Int
    let totalBadgeCount: Int
    let rangeLabel: String
    let badgeSections: [StatsBadgeSection]

    static let empty = StatsPresentationSnapshot(
        totalSteps: 0,
        activeDays: 0,
        unlockedBadgeCount: 0,
        totalBadgeCount: 0,
        rangeLabel: "YOUR JOURNEY",
        badgeSections: []
    )

    init(input: StatsPresentationInput) {
        let badgeSections = StatsBadgeCatalog.make(
            records: input.journeyRecords,
            dailyGoal: input.dailyGoal,
            discoveredStages: input.discoveredStages,
            distanceUnit: input.distanceUnit
        )
        let allBadges = badgeSections.flatMap(\.badges)

        totalSteps = input.analyticsRecords.reduce(0) { $0 + $1.steps }
        activeDays = input.analyticsRecords.lazy.filter { $0.steps > 0 }.count
        unlockedBadgeCount = allBadges.lazy.filter(\.unlocked).count
        totalBadgeCount = allBadges.count
        rangeLabel = input.rangeLabel
        self.badgeSections = badgeSections
    }

    private init(
        totalSteps: Int,
        activeDays: Int,
        unlockedBadgeCount: Int,
        totalBadgeCount: Int,
        rangeLabel: String,
        badgeSections: [StatsBadgeSection]
    ) {
        self.totalSteps = totalSteps
        self.activeDays = activeDays
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
