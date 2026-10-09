import Charts
import Combine
import SwiftUI

struct StatsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTourFocus) private var tourFocus
    @StateObject private var workoutHistoryStore: WorkoutHistoryStore
    @State private var monthOffset = 0
    // Start from the last computed results (or the launch prewarm) so the tab
    // never opens on an empty first frame.
    @State private var presentation = StatsWarmCache.presentation ?? .empty
    @State private var insights = StatsWarmCache.insights ?? .empty
    @State private var showsRecap = false
    /// Live step ticks land here while a finger is on the page, so a refresh
    /// never rebuilds the chart mid-scroll.
    @State private var isScrolling = false
    @State private var pendingInsights: StatsInsights?

    init(historyDefaults: UserDefaults = .standard) {
        _workoutHistoryStore = StateObject(wrappedValue: WorkoutHistoryStore(defaults: historyDefaults))
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    // Eager on purpose: the page is a handful of cards, and a lazy
                    // stack built (and tore down) the chart and artwork mid-scroll.
                    VStack(alignment: .leading, spacing: 16) {
                        StatsScreenHeader()

                        StatsSectionHeader(number: 1, title: "ACTIVITY LOG")
                        ActivityCalendarCard(
                            monthOffset: $monthOffset,
                            records: store.analyticsHistory,
                            dailyGoal: store.dailyGoal,
                            discoveryEvents: store.discoveryEvents,
                            workouts: workoutHistoryStore.workouts,
                            importedHistoryRange: store.appleHealthImportedHistoryRange,
                            distanceUnit: store.distanceUnit,
                            currentStreak: insights.streak.current,
                            bestStreak: insights.streak.best
                        )
                        .appTourTarget(.stats)
                        .id(AppTourTarget.stats)

                        StatsSectionHeader(number: 2, title: "TRENDS")
                        StatsTrendsCard(trends: insights.trends, dailyGoal: store.dailyGoal)
                            .id("trends")

                        StatsSectionHeader(number: 3, title: "RHYTHM")
                        StatsRhythmCard(rhythm: insights.rhythm)

                        StatsSectionHeader(number: 4, title: "PERSONAL RECORDS")
                        StatsRecordsGrid(records: insights.records)

                        RecentAchievementsRow(
                            sections: presentation.badgeSections,
                            sectionNumber: 5,
                            unlockedCount: presentation.unlockedBadgeCount,
                            totalCount: presentation.totalBadgeCount
                        )
                            .appTourTarget(.badges)
                            .id(AppTourTarget.badges)

                        StatsSectionHeader(number: 6, title: "MONTHLY RECAP")
                        if let recap = insights.recap {
                            StatsRecapCard(recap: recap, fallbackStage: store.currentStage) {
                                showsRecap = true
                            }
                        } else {
                            StatsRecapTeaser(companion: store.currentStage)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .onScrollPhaseChangeIfAvailable { isScrolling = $0 }
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
                        // Clear of the status bar, so the section header stays visible.
                        proxy.scrollTo("trends", anchor: UnitPoint(x: 0.5, y: 0.1))
                    case .featureTourStats:
                        try? await Task.sleep(for: .seconds(2.2))
                        guard !Task.isCancelled else { return }
                        withAnimation(.smooth(duration: 1.1)) {
                            proxy.scrollTo("trends", anchor: .top)
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
            let input = Self.presentationInput(store)

            // Commit the tab transition first, then calculate the badge catalog
            // away from the main actor. The retained snapshot makes repeat
            // visits immediate while fresh Health data is processed.
            await Task.yield()
            let prepared = await Task.detached(priority: .userInitiated) {
                StatsPresentationSnapshot(input: input)
            }.value
            guard !Task.isCancelled else { return }
            StatsWarmCache.presentation = prepared
            presentation = prepared
        }
        .task(id: insightRefreshID) {
            let input = Self.insightInput(store)
            await Task.yield()
            let prepared = await Task.detached(priority: .userInitiated) {
                StatsInsights(input: input)
            }.value
            guard !Task.isCancelled else { return }
            StatsWarmCache.insights = prepared
            if isScrolling {
                pendingInsights = prepared
            } else {
                insights = prepared
            }
        }
        .onChange(of: isScrolling) {
            guard !isScrolling, let pendingInsights else { return }
            insights = pendingInsights
            self.pendingInsights = nil
        }
        .fullScreenCover(isPresented: $showsRecap) {
            if let recap = insights.recap {
                StatsRecapStoryView(recap: recap, companion: store.currentStage,
                                    distanceUnit: store.distanceUnit)
            }
        }
    }

    private var insightRefreshID: StatsInsightRefreshID {
        StatsInsightRefreshID(
            analyticsCount: store.analyticsHistory.count,
            latestDay: store.analyticsHistory.last,
            hourlyCount: store.hourlyAnalyticsHistory.count,
            todaySteps: store.displayedTodaySteps,
            dailyGoal: store.dailyGoal,
            goalHistoryCount: store.dailyGoalHistory.count,
            discoveryCount: store.discoveryEvents.count,

            distanceUnit: store.distanceUnit.rawValue
        )
    }
}

extension StatsView {
    fileprivate static func presentationInput(_ store: AppStore) -> StatsPresentationInput {
        StatsPresentationInput(
            journeyRecords: store.badgeEvaluationHistory,
            dailyGoal: store.dailyGoal,
            dailyGoalHistory: store.dailyGoalHistory,
            discoveredStages: store.catalog.creatureStages.filter {
                store.isDiscovered($0) || store.isCurrent($0)
            },
            discoveryEvents: store.discoveryEvents,
            distanceUnit: store.distanceUnit
        )
    }

    fileprivate static func insightInput(_ store: AppStore) -> StatsInsightInput {
        StatsInsightInput(
            records: store.analyticsHistory,
            journeyRecords: store.badgeEvaluationHistory,
            hourly: store.hourlyAnalyticsHistory,
            todaySteps: store.displayedTodaySteps,
            dailyGoal: store.dailyGoal,
            goalHistory: store.dailyGoalHistory,
            journeyDayCount: store.journeyDayCount,
            journeyRangeLabel: store.journeyRangeLabel,
            discoveries: store.discoveryEvents,
            distanceUnit: store.distanceUnit,
            now: .now
        )
    }

    /// Computes the Stats tab's data in the background before it's opened.
    @MainActor
    static func prewarm(_ store: AppStore) async {
        guard StatsWarmCache.insights == nil || StatsWarmCache.presentation == nil else { return }
        let presentationInput = presentationInput(store)
        let insightInput = insightInput(store)
        let (presentation, insights) = await Task.detached(priority: .utility) {
            (StatsPresentationSnapshot(input: presentationInput), StatsInsights(input: insightInput))
        }.value
        if StatsWarmCache.presentation == nil { StatsWarmCache.presentation = presentation }
        if StatsWarmCache.insights == nil { StatsWarmCache.insights = insights }
    }
}

private extension View {
    /// Reports whether the scroll view is moving (iOS 18+; a no-op before).
    @ViewBuilder
    func onScrollPhaseChangeIfAvailable(_ action: @escaping (Bool) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onScrollPhaseChange { _, phase in action(phase.isScrolling) }
        } else {
            self
        }
    }
}

@MainActor
private enum StatsWarmCache {
    static var presentation: StatsPresentationSnapshot?
    static var insights: StatsInsights?
}

private struct StatsInsightRefreshID: Equatable {
    let analyticsCount: Int
    let latestDay: DailyStepRecord?
    let hourlyCount: Int
    let todaySteps: Int
    let dailyGoal: Int
    let goalHistoryCount: Int
    let discoveryCount: Int
    let distanceUnit: String
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
    let dailyGoal: Int
    let dailyGoalHistory: [DailyGoalRecord]
    let discoveredStages: [CreatureStage]
    let discoveryEvents: [CreatureDiscoveryEvent]
    let distanceUnit: DistanceUnitPreference
}

private struct StatsPresentationSnapshot {
    let unlockedBadgeCount: Int
    let totalBadgeCount: Int
    let badgeSections: [StatsBadgeSection]

    static let empty = StatsPresentationSnapshot(
        unlockedBadgeCount: 0,
        totalBadgeCount: 0,
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

        unlockedBadgeCount = allBadges.lazy.filter(\.unlocked).count
        totalBadgeCount = allBadges.count
        self.badgeSections = badgeSections
    }

    private init(
        unlockedBadgeCount: Int,
        totalBadgeCount: Int,
        badgeSections: [StatsBadgeSection]
    ) {
        self.unlockedBadgeCount = unlockedBadgeCount
        self.totalBadgeCount = totalBadgeCount
        self.badgeSections = badgeSections
    }
}
