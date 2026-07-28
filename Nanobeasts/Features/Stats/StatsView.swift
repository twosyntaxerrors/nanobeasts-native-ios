import SwiftUI

struct StatsView: View {
    @Environment(AppStore.self) private var store
    @State private var calendarScope: StatsCalendarScope = .month
    @State private var monthOffset = 0

    var body: some View {
        let discoveredStages = store.catalog.creatureStages.filter {
            store.isDiscovered($0) || store.isCurrent($0)
        }
        let badgeSections = StatsBadgeCatalog.make(
            records: store.dailyHistory,
            dailyGoal: store.dailyGoal,
            discoveredStages: discoveredStages
        )
        let allBadges = badgeSections.flatMap(\.badges)

        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    StatsScreenHeader()

                    LifetimeMovementCard(
                        steps: store.analyticsHistory.reduce(0) { $0 + $1.steps },
                        activeDays: store.analyticsHistory.filter { $0.steps > 0 }.count,
                        unlockedBadges: allBadges.filter(\.unlocked).count,
                        totalBadges: allBadges.count,
                        rangeLabel: store.analyticsRangeLabel
                    )

                    ActivityConsistencyHeader(scope: $calendarScope)

                    ActivityCalendarCard(
                        scope: calendarScope,
                        monthOffset: $monthOffset,
                        records: store.analyticsHistory,
                        dailyGoal: store.dailyGoal,
                        discoveryEvents: store.discoveryEvents
                    )

                    ActionableInsightsCard(
                        analyticsRecords: store.analyticsHistory,
                        hourlyRecords: store.hourlyAnalyticsHistory,
                        journeyRecords: store.dailyHistory,
                        goalHistory: store.dailyGoalHistory,
                        currentGoal: store.dailyGoal,
                        stepsRemaining: max(
                            store.currentTarget - store.hatchProgressSteps,
                            0
                        ),
                        creatureName: store.currentStage.name
                    )

                    RecentAchievementsRow(sections: badgeSections)
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
    }
}

enum StatsCalendarScope: String, CaseIterable, Identifiable {
    case month = "MONTH"
    case week = "WEEK"

    var id: String { rawValue }
}
