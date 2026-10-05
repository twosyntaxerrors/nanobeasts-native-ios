import Foundation
import Observation
import RevenueCat
import StoreKit

enum AppScreenshotScenario: String {
    case badges
    case collectionBadges = "collection-badges"
    case stats
    case insights
    case dex
    case dexDetail = "dex-detail"
    case evolution
    case finalEvolution = "final-evolution"
    case eggSelection = "egg-selection"
    case tutorialLoop = "tutorial-loop"
    case featureTourHome = "feature-tour-home"
    case featureTourDex = "feature-tour-dex"
    case featureTourBadges = "feature-tour-badges"
    case featureTourStats = "feature-tour-stats"

    static let goldieScenarioDefaultsKey = "nanobeasts.goldie.screenshot-scenario"

    static var active: AppScreenshotScenario? {
#if targetEnvironment(simulator)
        if let rawValue = UserDefaults.standard.string(forKey: goldieScenarioDefaultsKey),
           let scenario = AppScreenshotScenario(rawValue: rawValue)
        {
            return scenario
        }
#endif
#if targetEnvironment(simulator)
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let value = arguments
            .first(where: { $0.hasPrefix("--screenshot-scenario=") })?
            .split(separator: "=", maxSplits: 1)
            .last
        {
            return AppScreenshotScenario(rawValue: String(value))
        }

        guard
            let flagIndex = arguments.firstIndex(of: "--screenshot-scenario"),
            arguments.indices.contains(flagIndex + 1)
        else {
            return nil
        }
        return AppScreenshotScenario(rawValue: arguments[flagIndex + 1])
#else
        return nil
#endif
#endif
        return nil
    }
}

enum DistanceUnitPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case miles
    case kilometers

    var id: String { rawValue }

    var abbreviation: String {
        switch self {
        case .miles: "MI"
        case .kilometers: "KM"
        }
    }

    var displayName: String {
        switch self {
        case .miles: "Miles"
        case .kilometers: "Kilometers"
        }
    }

    var pluralName: String {
        displayName.lowercased()
    }

    func value(forSteps steps: Int) -> Double {
        value(fromKilometers: Double(max(steps, 0)) * 0.000762)
    }

    func value(fromKilometers kilometers: Double) -> Double {
        switch self {
        case .miles: kilometers * 0.621371
        case .kilometers: kilometers
        }
    }
}

@MainActor
@Observable
final class AppStore {
    static let premiumMonthlyProductID = "nanobeasts_native_premium_monthly"
    static let premiumYearlyProductID = "nanobeasts_native_premium_yearly"
    static let premiumProductIDs: Set<String> = [
        premiumMonthlyProductID,
        premiumYearlyProductID,
    ]

    private struct PersistedState: Codable {
        var familyIndex = 0
        var stageIndex = 0
        var progressionSteps = 0
        var bankedProgressionSteps: Int?
        var discoveredStageIDs: [String] = []
        var dailyGoal = 10_000
        var hasRequestedHealthAccess = false
        var lastHealthDateKey: String?
        var lastHealthTodaySteps = 0
        var hapticsEnabled = true
        var reduceMotion = false
        var distanceUnit: DistanceUnitPreference?
        var onboardingCompleted: Bool?
        var playerName: String?
        var onboardingGoals: [String]?
        var onboardingPrimaryGoal: String?
        var onboardingBlockers: [String]?
        var onboardingWantsHealth: Bool?
        var onboardingWantsReminders: Bool?
        var awaitingEggSelection = false
        var journeyStartedAt: Date?
        var lastCountedJourneySteps: Int?
        var dailyHistory: [DailyStepRecord]?
        var analyticsHistory: [DailyStepRecord]?
        var hourlyAnalyticsHistory: [HourlyStepRecord]?
        var dailyGoalHistory: [DailyGoalRecord]?
        var scheduledDailyGoal: Int?
        var scheduledDailyGoalSetOn: Date?
        var goalRampAnchor: Date?
        var pendingLifecycleEvents: [CreatureDiscoveryEvent]?
        var awardedBadgeIDs: [String]?
        var eggDiscoveryOrder: [String]?
        var progressionCreditHistory: [DailyStepRecord]?
        var testingStepHistory: [DailyStepRecord]?
        var isPremium: Bool?
        var reviewEligibleLifecycleCount: Int?
        var lastReviewRequestLifecycleCount: Int?
    }

    let catalog: CreatureCatalog
    private let healthClient: HealthKitClient
    private let pedometerClient: PedometerClient
    private let defaults: UserDefaults
    let isOnboardingReplay: Bool
    var replayPreferences: UserDefaults { defaults }
    private let stateKey = "nanobeasts.native.game-state.v1"
    private let discoveryStateKey = "nanobeasts.native.discovery-events.v1"
    private static let premiumStateKey = "nanobeasts.native.last-verified-premium.v1"
#if DEBUG
    private static let testStorePremiumUnlockKey =
        "nanobeasts.debug.test-store-premium-unlocked.v1"
#endif

    private var familyIndex: Int
    private var stageIndex: Int
    private var progressionSteps: Int
    private(set) var bankedProgressionSteps: Int
    private var discoveredStageIDs: Set<String>
    private var lastHealthDateKey: String?
    private var lastHealthTodaySteps: Int
    private var journeyStartedAt: Date?
    private var lastCountedJourneySteps: Int
    private var eggDiscoveryOrder: [String]
    private var progressionCreditHistory: [DailyStepRecord]
    private var testingStepHistory: [DailyStepRecord]
    private var reviewEligibleLifecycleCount: Int
    private var lastReviewRequestLifecycleCount: Int
    private(set) var awaitingEggSelection: Bool

    var dailyGoal: Int {
        didSet {
            recordCurrentDailyGoal()
            persist()
        }
    }
    var hasRequestedHealthAccess: Bool {
        didSet { persist() }
    }
    var hapticsEnabled: Bool {
        didSet { persist() }
    }
    var reduceMotion: Bool {
        didSet { persist() }
    }
    var interfaceAccent: NanoAccent {
        didSet {
            guard !isOnboardingReplay else { return }
            NanoAccentPreference.current = interfaceAccent
            WorkoutWatchBridge.shared.updateInterfaceAccent()
        }
    }
    var distanceUnit: DistanceUnitPreference {
        didSet { persist() }
    }
    var onboardingCompleted: Bool {
        didSet { persist() }
    }
    var playerName: String {
        didSet { persist() }
    }
    var onboardingGoals: Set<String> {
        didSet { persist() }
    }
    var onboardingBlockers: Set<String> {
        didSet { persist() }
    }
    var onboardingPrimaryGoal: String? {
        didSet { persist() }
    }
    var onboardingWantsHealth: Bool {
        didSet { persist() }
    }
    var onboardingWantsReminders: Bool {
        didSet {
            if !isOnboardingReplay { NanoNotifications.shared.setPreference(onboardingWantsReminders) }
            persist()
        }
    }

    private(set) var healthState: HealthConnectionState = .notRequested
    private(set) var dailyHistory: [DailyStepRecord] = []
    private(set) var analyticsHistory: [DailyStepRecord] = []
    private(set) var hourlyAnalyticsHistory: [HourlyStepRecord] = []
    private(set) var dailyGoalHistory: [DailyGoalRecord] = []
    /// A goal change waiting for tomorrow. Today's goal never moves mid-day, so
    /// lowering it can't rescue a streak or farm goal badges.
    private(set) var scheduledDailyGoal: Int?
    private var scheduledDailyGoalSetOn: Date?
    /// Start of the current week of a below-minimum goal's ramp toward 5,000.
    private var goalRampAnchor: Date?
    private(set) var isLoading = false
    private(set) var lastHealthSync: Date?
    private(set) var evolutionEventID = UUID()
    private(set) var discoveryEvents: [CreatureDiscoveryEvent]
    private(set) var pendingLifecycleEvents: [CreatureDiscoveryEvent]
    private(set) var awardedBadgeIDs: Set<String>
    private(set) var badgeEvaluationID = UUID()
    private(set) var isSyncingSteps = false
    private(set) var stepSyncAnimationID = UUID()
    private(set) var dailyGoalCelebrationID: UUID?
    private(set) var isPremium: Bool
    private(set) var hasResolvedInitialSubscription = false
    private(set) var stepSyncFromTodaySteps = 0
    private(set) var stepSyncFromHatchProgress = 0.0
    private(set) var stepSyncDuration = 1.0
    private(set) var testingActivityPreviewSteps = 0
    private(set) var testingProgressionPreviewSteps = 0
    private(set) var testingProgressionCreditSteps = 0
    private(set) var replayEvolutionLocked = false
    private(set) var replayUncountedSteps = 0
    private var testingPresentedBadgeIDs: Set<String> = []
    @ObservationIgnored private var lastConsumedStepSyncAnimationID: UUID?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?

    init(
        catalog: CreatureCatalog = .load(),
        healthClient: HealthKitClient = HealthKitClient(),
        pedometerClient: PedometerClient = PedometerClient(),
        defaults: UserDefaults = .standard,
        isOnboardingReplay: Bool = false
    ) {
        self.catalog = catalog
        self.healthClient = healthClient
        self.pedometerClient = pedometerClient
        self.defaults = defaults
        self.isOnboardingReplay = isOnboardingReplay

        let screenshotFixture = (isOnboardingReplay ? nil : AppScreenshotScenario.active).map {
            Self.makeScreenshotFixture(for: $0, catalog: catalog)
        }
        let restored: PersistedState
        if let screenshotFixture {
            restored = screenshotFixture.state
        } else if
            let data = defaults.data(forKey: stateKey),
            let decoded = try? JSONDecoder().decode(PersistedState.self, from: data)
        {
            restored = decoded
        } else {
            restored = PersistedState()
        }

        let restoredFamilyIndex = min(
            max(restored.familyIndex, 0),
            max(catalog.families.count - 1, 0)
        )
        familyIndex = restoredFamilyIndex
        stageIndex = min(
            max(restored.stageIndex, 0),
            max(catalog.families[restoredFamilyIndex].stages.count - 1, 0)
        )
        progressionSteps = max(restored.progressionSteps, 0)
        bankedProgressionSteps = max(restored.bankedProgressionSteps ?? 0, 0)
        discoveredStageIDs = Set(restored.discoveredStageIDs)
        dailyGoal = restored.dailyGoal
        hasRequestedHealthAccess = restored.hasRequestedHealthAccess
        lastHealthDateKey = restored.lastHealthDateKey
        lastHealthTodaySteps = restored.lastHealthTodaySteps
        hapticsEnabled = restored.hapticsEnabled
        reduceMotion = restored.reduceMotion
        interfaceAccent = screenshotFixture == nil ? NanoAccentPreference.current : .mint
        distanceUnit = restored.distanceUnit ?? .miles
        onboardingCompleted = restored.onboardingCompleted ?? false
        playerName = restored.playerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        onboardingGoals = Set(restored.onboardingGoals ?? [])
        onboardingPrimaryGoal = restored.onboardingPrimaryGoal
        onboardingBlockers = Set(restored.onboardingBlockers ?? [])
        onboardingWantsHealth = restored.onboardingWantsHealth ?? true
        onboardingWantsReminders = restored.onboardingWantsReminders ?? true
        awaitingEggSelection = restored.awaitingEggSelection
        journeyStartedAt = restored.journeyStartedAt
        let restoredLastCountedJourneySteps = max(
            restored.lastCountedJourneySteps ?? 0,
            0
        )
        let legacyTestingHistory = restored.testingStepHistory ?? []
        let calendar = Calendar.autoupdatingCurrent
        let legacyTestingByDay = Dictionary(
            legacyTestingHistory.map {
                (calendar.startOfDay(for: $0.day), max($0.steps, 0))
            },
            uniquingKeysWith: +
        )
        let removeLegacyTestingSteps: ([DailyStepRecord]) -> [DailyStepRecord] = {
            records in
            records.map { record in
                let day = calendar.startOfDay(for: record.day)
                return DailyStepRecord(
                    day: day,
                    steps: max(record.steps - (legacyTestingByDay[day] ?? 0), 0)
                )
            }
        }
        let restoredJourneyHistory = removeLegacyTestingSteps(
            restored.dailyHistory ?? []
        )
        dailyHistory = restoredJourneyHistory
        progressionCreditHistory =
            restored.progressionCreditHistory
            ?? restoredJourneyHistory.map {
                DailyStepRecord(
                    day: $0.day,
                    steps: max($0.steps, 0)
                )
            }
        // Testing increments now simulate lifecycle progression only. Strip
        // offsets persisted by older builds from real activity ledgers.
        testingStepHistory = []
        analyticsHistory = removeLegacyTestingSteps(
            restored.analyticsHistory ?? restoredJourneyHistory
        )
        hourlyAnalyticsHistory = (restored.hourlyAnalyticsHistory ?? []).filter {
            legacyTestingByDay[calendar.startOfDay(for: $0.start)] == nil
        }
        lastCountedJourneySteps = max(
            restoredLastCountedJourneySteps
                - legacyTestingByDay.values.reduce(0, +),
            0
        )
        dailyGoalHistory = restored.dailyGoalHistory ?? []
        scheduledDailyGoal = restored.scheduledDailyGoal
        scheduledDailyGoalSetOn = restored.scheduledDailyGoalSetOn
        goalRampAnchor = restored.goalRampAnchor
        discoveryEvents = screenshotFixture?.discoveryEvents
            ?? defaults.data(forKey: discoveryStateKey)
                .flatMap { try? JSONDecoder().decode([CreatureDiscoveryEvent].self, from: $0) }
            ?? []
        pendingLifecycleEvents = restored.pendingLifecycleEvents ?? []
        awardedBadgeIDs = Set(restored.awardedBadgeIDs ?? [])
        var restoredPremium = screenshotFixture == nil
            ? (defaults.object(forKey: Self.premiumStateKey) as? Bool
                ?? restored.isPremium
                ?? false)
            : (restored.isPremium ?? false)
        // Development access must never become a paid entitlement when a
        // production build replaces a local development install.
        if screenshotFixture == nil,
           let data = defaults.data(forKey: NanoSubscriptionAccess.cacheKey),
           let access = try? JSONDecoder().decode(NanoSubscriptionAccess.self, from: data),
           !access.permitsCurrentBuild {
            restoredPremium = false
        }
#if DEBUG
        if screenshotFixture == nil, Self.isUsingRevenueCatTestStore {
            let testStoreUnlocked =
                defaults.bool(forKey: Self.testStorePremiumUnlockKey)
                || restoredPremium
            isPremium = testStoreUnlocked
            if testStoreUnlocked {
                defaults.set(true, forKey: Self.testStorePremiumUnlockKey)
            }
        } else {
            isPremium = restoredPremium
        }
#else
        isPremium = restoredPremium
#endif
        reviewEligibleLifecycleCount = restored.reviewEligibleLifecycleCount ?? 0
        lastReviewRequestLifecycleCount = restored.lastReviewRequestLifecycleCount ?? 0
        let eligibleFamilyIDs = Array(catalog.families.dropFirst().map(\.id))
        let restoredOrder = restored.eggDiscoveryOrder ?? []
        eggDiscoveryOrder =
            Set(restoredOrder) == Set(eligibleFamilyIDs)
                ? restoredOrder
                : eligibleFamilyIDs.shuffled()

        if screenshotFixture == nil, !isOnboardingReplay {
            defaults.set(isPremium, forKey: Self.premiumStateKey)
        }

        // Existing installs predate the journey boundary. Start their activity
        // ledger now so the next Health query cannot backfill older movement.
        if onboardingCompleted, journeyStartedAt == nil {
            journeyStartedAt = Date()
            dailyHistory = []
            lastCountedJourneySteps = 0
        }
        if onboardingCompleted, dailyGoalHistory.isEmpty {
            recordCurrentDailyGoal()
        }
        if !isOnboardingReplay { NanoAccentPreference.current = interfaceAccent }
        lastConsumedStepSyncAnimationID = stepSyncAnimationID
        if screenshotFixture == nil {
            if !isOnboardingReplay { NanoNotifications.shared.setPreference(onboardingWantsReminders) }
        }
    }

    /// A fresh, non-persisting profile for the Settings walkthrough. Never bootstrap it.
    static func makeOnboardingReplay() -> AppStore {
        AppStore(defaults: UserDefaults(suiteName: "nanobeasts.onboarding-replay.\(UUID().uuidString)")!,
                 isOnboardingReplay: true)
    }

    /// Drives the production screens with the walkthrough's simulated activity.
    /// The paywall journey owns the checkpoint; the creature remains an egg until revealed.
    func updateOnboardingReplay(steps: Int, revealed: Bool, purchased: Bool,
                                familyIndex replayFamilyIndex: Int = 0,
                                stageIndex replayStageIndex: Int? = nil,
                                stageSteps: Int? = nil,
                                tutorialMatured: Bool = false,
                                evolutionLocked: Bool = false,
                                uncountedSteps: Int = 0) {
        guard isOnboardingReplay else { return }
        replayEvolutionLocked = evolutionLocked
        replayUncountedSteps = max(uncountedSteps, 0)
        guard catalog.families.indices.contains(replayFamilyIndex) else { return }
        let nextStageIndex = replayStageIndex ?? (revealed ? 1 : 0)
        guard catalog.families[replayFamilyIndex].stages.indices.contains(nextStageIndex) else { return }
        let previousToday = displayedTodaySteps
        let previousProgress = hatchProgress
        familyIndex = replayFamilyIndex
        stageIndex = nextStageIndex
        awaitingEggSelection = tutorialMatured && replayFamilyIndex == 0
        let hatchTarget = CreatureProgressionRules.steps(familyIndex: 0, stage: 0)
        progressionSteps = stageSteps ?? (revealed ? max(steps - hatchTarget, 0) : min(steps, hatchTarget))
        isPremium = purchased
        let today = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        dailyHistory = [DailyStepRecord(day: today, steps: steps)]
        analyticsHistory = dailyHistory
        progressionCreditHistory = dailyHistory
        // Preserve both companions in the Dex; do not reveal the next stage at its paywall.
        let tutorialStages = replayFamilyIndex > 0 ? Array(catalog.families[0].stages.prefix(2)) : []
        for stage in tutorialStages + Array(currentFamily.stages.prefix(nextStageIndex + 1)) {
            discoveredStageIDs.insert(stage.id)
            guard !discoveryEvents.contains(where: { $0.creatureStage.id == stage.id }) else { continue }
            let kind: CreatureDiscoveryKind = stage.stage == 0 ? .eggAcquired : stage.stage == 1 ? .hatch : .evolution
            discoveryEvents.append(CreatureDiscoveryEvent(stage: stage, kind: kind))
            if stage.stage > 0 { evolutionEventID = UUID() }
        }
        if tutorialMatured, let tutorial = catalog.families[0].stages.dropFirst().first,
           !discoveryEvents.contains(where: { $0.kind == .maturity && $0.creatureStage.id == tutorial.id }) {
            discoveryEvents.append(CreatureDiscoveryEvent(stage: tutorial, kind: .maturity))
            evolutionEventID = UUID()
        }
        if previousToday != steps {
            stepSyncFromTodaySteps = previousToday
            stepSyncFromHatchProgress = previousProgress
            stepSyncDuration = 0.88
            stepSyncAnimationID = UUID()
        }
        badgeEvaluationID = UUID()
    }

    private static func makeScreenshotFixture(
        for scenario: AppScreenshotScenario,
        catalog: CreatureCatalog
    ) -> (state: PersistedState, discoveryEvents: [CreatureDiscoveryEvent]) {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let history = (0..<180).compactMap { offset -> DailyStepRecord? in
            guard let day = calendar.date(byAdding: .day, value: offset - 179, to: today)
            else { return nil }
            let steps = offset.isMultiple(of: 11)
                ? 32_800 + ((offset % 5) * 1_100)
                : 14_200 + ((offset % 7) * 640)
            return DailyStepRecord(day: day, steps: steps)
        }
        let goalHistory = history.map { DailyGoalRecord(day: $0.day, goal: 10_000) }

        let allStages = catalog.families.flatMap(\.stages)
        var discoveryEvents = allStages
            .filter { !$0.isEgg }
            .enumerated()
            .map { index, stage in
                let kind: CreatureDiscoveryKind = stage.stage == 1 ? .hatch : .evolution
                let timestamp = calendar.date(
                    byAdding: .day,
                    value: -min(index * 2, 178),
                    to: today
                ) ?? today
                return CreatureDiscoveryEvent(stage: stage, kind: kind, timestamp: timestamp)
            }

        let preferredFamilyIndex = catalog.families.firstIndex(where: { family in
            family.stages.contains(where: { $0.name == "Devicore" })
        }) ?? min(1, max(catalog.families.count - 1, 0))
        let preferredFamily = catalog.families[preferredFamilyIndex]
        let destinationName =
            scenario == .finalEvolution || scenario == .eggSelection
                ? "Overnode"
                : "Devicore"
        let preferredStageIndex = preferredFamily.stages.firstIndex(where: {
            $0.name == destinationName
        }) ?? max(preferredFamily.stages.count - 1, 0)
        let preferredStage = preferredFamily.stages[preferredStageIndex]
        let evolutionEvent = CreatureDiscoveryEvent(
            stage: preferredStage,
            kind: .evolution,
            timestamp: Date()
        )
        if scenario == .eggSelection {
            discoveryEvents.append(
                CreatureDiscoveryEvent(
                    stage: preferredStage,
                    kind: .maturity,
                    timestamp: Date()
                )
            )
        }

        let allBadgeIDs = [
            "distance-1", "distance-5", "distance-10", "distance-15",
            "distance-25", "distance-50", "distance-75", "distance-100",
            "distance-150", "distance-200", "distance-300", "distance-350",
            "distance-400", "distance-450", "distance-500", "distance-750",
            "distance-1000", "distance-sprint", "collection-first",
            "collection-3", "collection-5", "collection-10", "collection-15",
            "collection-25", "species-3", "species-5", "species-10",
            "species-15", "species-20", "species-25", "species-35",
            "species-50", "evolve-first", "evolve-3", "evolve-5",
            "evolve-10", "final-first", "final-3", "streak-3", "streak-5",
            "streak-7", "streak-10", "streak-14", "streak-21", "streak-30",
            "streak-45", "streak-60", "streak-90", "streak-120", "streak-180",
            "weekend-warrior", "monthly-marathon", "goal-1", "goal-3", "goal-7",
            "goal-15", "goal-30", "goal-50", "double-goal", "triple-goal",
            "steps-5k", "steps-10k", "steps-15k", "steps-20k",
        ]

        if scenario == .tutorialLoop {
            let tutorialFamilyIndex = 0
            let tutorialFamily = catalog.families[tutorialFamilyIndex]
            let tutorialEggIndex = tutorialFamily.stages.firstIndex(where: \.isEgg) ?? 0
            let tutorialEgg = tutorialFamily.stages[tutorialEggIndex]
            let emptyToday = DailyStepRecord(day: today, steps: 0)

            var state = PersistedState()
            state.familyIndex = tutorialFamilyIndex
            state.stageIndex = tutorialEggIndex
            state.progressionSteps = 0
            state.discoveredStageIDs = [tutorialEgg.id]
            state.dailyGoal = 6_500
            state.hasRequestedHealthAccess = false
            state.hapticsEnabled = false
            state.reduceMotion = false
            state.distanceUnit = .miles
            state.onboardingCompleted = true
            state.playerName = "NOVA"
            state.onboardingWantsHealth = false
            state.onboardingWantsReminders = false
            state.awaitingEggSelection = false
            state.journeyStartedAt = today
            state.lastCountedJourneySteps = 0
            state.dailyHistory = [emptyToday]
            state.analyticsHistory = [emptyToday]
            state.hourlyAnalyticsHistory = []
            state.dailyGoalHistory = [DailyGoalRecord(day: today, goal: 6_500)]
            state.pendingLifecycleEvents = []
            state.awardedBadgeIDs = []
            state.eggDiscoveryOrder = Array(catalog.families.dropFirst().map(\.id))
            state.progressionCreditHistory = []
            state.testingStepHistory = []
            state.isPremium = true
            state.reviewEligibleLifecycleCount = 0
            state.lastReviewRequestLifecycleCount = 0
            return (
                state,
                [CreatureDiscoveryEvent(stage: tutorialEgg, kind: .eggAcquired)]
            )
        }

        var state = PersistedState()
        state.familyIndex = preferredFamilyIndex
        state.stageIndex = preferredStageIndex
        state.progressionSteps = max(0, 1_840)
        state.discoveredStageIDs = allStages.map(\.id)
        state.dailyGoal = 10_000
        state.hasRequestedHealthAccess = false
        state.hapticsEnabled = false
        state.reduceMotion = false
        state.distanceUnit = .miles
        state.onboardingCompleted = true
        state.playerName = "NOVA"
        state.onboardingWantsHealth = false
        state.onboardingWantsReminders = false
        state.awaitingEggSelection = scenario == .eggSelection
        state.journeyStartedAt = history.first?.day ?? today
        state.lastCountedJourneySteps = history.reduce(0) { $0 + $1.steps }
        state.dailyHistory = history
        state.analyticsHistory = history
        state.hourlyAnalyticsHistory = []
        state.dailyGoalHistory = goalHistory
        state.pendingLifecycleEvents =
            scenario == .evolution || scenario == .finalEvolution
                ? [evolutionEvent]
                : []
        state.awardedBadgeIDs = allBadgeIDs
        state.eggDiscoveryOrder = Array(catalog.families.dropFirst().map(\.id))
        state.progressionCreditHistory = []
        state.testingStepHistory = []
        state.isPremium = true
        state.reviewEligibleLifecycleCount = 18
        state.lastReviewRequestLifecycleCount = 18
        return (state, discoveryEvents)
    }

    var currentFamily: CreatureFamily {
        catalog.families[familyIndex]
    }

    var currentStage: CreatureStage {
        currentFamily.stages[stageIndex]
    }

    var currentTarget: Int {
        if awaitingEggSelection {
            return 1
        }

        return CreatureProgressionRules.steps(familyIndex: familyIndex, stage: currentStage.stage)
    }

    var hatchProgress: Double {
        if awaitingEggSelection {
            return 1
        }
        guard currentTarget > 0 else { return 0 }
        return min(Double(hatchProgressSteps) / Double(currentTarget), 1)
    }

    var hatchProgressSteps: Int {
        progressionSteps + testingProgressionPreviewSteps
    }

    var workoutEvolutionProgress: WorkoutEvolutionProgress {
        WorkoutEvolutionProgress(
            stageID: currentStage.id,
            steps: awaitingEggSelection ? currentTarget : hatchProgressSteps,
            target: currentTarget,
            totalCreditedSteps: progressionCreditHistory.reduce(0) { $0 + $1.steps }
                + testingProgressionCreditSteps,
            milestone: awaitingEggSelection ? .complete : currentStage.isEgg ? .hatch
                : stageIndex + 1 < currentFamily.stages.count ? .evolve : .mature,
            allowsProgress: isPremium && onboardingCompleted
        )
    }

    /// Keep the unrevealed creature visible until its queued celebration is seen.
    var workoutMilestoneEvent: CreatureDiscoveryEvent? {
        pendingLifecycleEvents.first(where: { $0.kind != .eggAcquired })
    }

    var workoutCompanionStage: CreatureStage {
        guard let event = workoutMilestoneEvent else { return currentStage }
        if event.kind == .maturity { return event.creatureStage }
        return catalog.families.first(where: { $0.id == event.familyID })?.stages
            .filter { $0.stage < event.stage }.max(by: { $0.stage < $1.stage })
            ?? currentStage
    }

    var workoutCompanionProgress: WorkoutEvolutionProgress {
        guard let event = workoutMilestoneEvent else { return workoutEvolutionProgress }
        let stage = workoutCompanionStage
        let index = catalog.families.firstIndex(where: { $0.id == stage.familyID }) ?? familyIndex
        let target = CreatureProgressionRules.steps(familyIndex: index, stage: stage.stage)
        return WorkoutEvolutionProgress(
            stageID: stage.id, steps: target, target: target,
            totalCreditedSteps: workoutEvolutionProgress.totalCreditedSteps,
            milestone: event.kind == .maturity ? .complete : event.kind == .hatch ? .hatch : .evolve,
            allowsProgress: false, readyEventID: event.id,
            bankedSteps: bankedProgressionSteps)
    }

    /// Real workout steps can arrive before the daily Health query. Advance the
    /// same monotonic credit ledger, so later Health delivery cannot double them.
    /// Historical or overnight snapshots defer to Health's daily reconciliation.
    func creditRecordedWorkoutSteps(_ steps: Int, anchor: WorkoutEvolutionAnchor?,
                                    startedAt: Date, observedAt: Date = Date()) {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        guard onboardingCompleted, isPremium, let journeyStartedAt,
              startedAt >= journeyStartedAt, startedAt <= observedAt,
              observedAt <= now.addingTimeInterval(60),
              calendar.isDate(observedAt, inSameDayAs: now),
              calendar.isDate(startedAt, inSameDayAs: observedAt),
              let anchor, anchor.totalCreditedSteps >= 0, anchor.workoutSteps >= 0,
              anchor.totalCreditedSteps <= workoutEvolutionProgress.totalCreditedSteps else { return }
        let pending = anchor.uncreditedSteps(recordedSteps: steps,
            totalCreditedSteps: workoutEvolutionProgress.totalCreditedSteps)
        guard pending > 0 else { return }
        let today = calendar.startOfDay(for: observedAt)
        if let index = progressionCreditHistory.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: today) }) {
            progressionCreditHistory[index] = DailyStepRecord(day: today,
                steps: progressionCreditHistory[index].steps + pending)
        } else {
            progressionCreditHistory.append(DailyStepRecord(day: today, steps: pending))
            progressionCreditHistory.sort { $0.day < $1.day }
        }
        applyProgress(pending)
        persist()
    }

    /// Free users keep step tracking, streaks, and badges, but their steps don't
    /// move the creature: evolution progress is a Pro feature. The onboarding
    /// replay drives this explicitly so its paywall timing stays scripted.
    var isEvolutionLocked: Bool {
        isOnboardingReplay ? replayEvolutionLocked : onboardingCompleted && !isPremium
    }

    /// Today's steps walked since evolution locked: everything today minus what
    /// already counted toward evolution (all of it for a free user, only the
    /// steps after a mid-day lapse for a former subscriber).
    var uncountedTodaySteps: Int {
        guard isEvolutionLocked else { return 0 }
        if isOnboardingReplay { return replayUncountedSteps }
        let calendar = Calendar.autoupdatingCurrent
        let credited = progressionCreditHistory.first { calendar.isDateInToday($0.day) }?.steps ?? 0
        return max(displayedTodaySteps - credited, 0)
    }


    var todaySteps: Int {
        let calendar = Calendar.autoupdatingCurrent
        return dailyHistory.first(where: { calendar.isDateInToday($0.day) })?.steps ?? 0
    }

    /// Home-only activity preview used by the hidden testing shortcut. The
    /// offset is deliberately memory-only and is cleared by the next real
    /// HealthKit or pedometer update.
    var displayedTodaySteps: Int {
        todaySteps + testingActivityPreviewSteps
    }

    var hasTestingActivityPreview: Bool {
        testingActivityPreviewSteps > 0 || testingProgressionPreviewSteps > 0
    }

    /// Badge calculations may include the hidden recording preview, while the
    /// persisted Health-backed journey ledger remains untouched.
    var badgeEvaluationHistory: [DailyStepRecord] {
        guard testingActivityPreviewSteps > 0 else { return dailyHistory }

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        var records = dailyHistory
        if let index = records.firstIndex(where: {
            calendar.isDate($0.day, inSameDayAs: today)
        }) {
            records[index] = DailyStepRecord(day: today, steps: displayedTodaySteps)
        } else {
            records.append(DailyStepRecord(day: today, steps: displayedTodaySteps))
            records.sort { $0.day < $1.day }
        }
        return records
    }

    func hasPresentedBadgeAward(_ badgeID: String) -> Bool {
        awardedBadgeIDs.contains(badgeID)
            || testingPresentedBadgeIDs.contains(badgeID)
    }

    var recentWeek: [DailyStepRecord] {
        Array(dailyHistory.suffix(7))
    }

    var displayedRecentWeek: [DailyStepRecord] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        var records = recentWeek

        if let index = records.firstIndex(where: {
            calendar.isDate($0.day, inSameDayAs: today)
        }) {
            records[index] = DailyStepRecord(
                day: today,
                steps: displayedTodaySteps
            )
        } else if testingActivityPreviewSteps > 0 {
            records.append(
                DailyStepRecord(day: today, steps: displayedTodaySteps)
            )
            records.sort { $0.day < $1.day }
            records = Array(records.suffix(7))
        }

        return records
    }

    var recentFourWeeks: [DailyStepRecord] {
        Array(dailyHistory.suffix(28))
    }

    var analyticsTodaySteps: Int {
        let calendar = Calendar.autoupdatingCurrent
        return analyticsHistory.first(where: { calendar.isDateInToday($0.day) })?.steps ?? 0
    }

    var analyticsRangeLabel: String {
        guard let first = analyticsHistory.first?.day else { return "YOUR JOURNEY" }
        let calendar = Calendar.autoupdatingCurrent
        let days = max(
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: first),
                to: calendar.startOfDay(for: Date())
            ).day ?? 0,
            0
        )
        return days >= 330 ? "PAST 12 MONTHS" : "\(max(days + 1, 1)) DAYS OF HISTORY"
    }

    var journeyDayCount: Int {
        guard let journeyStartedAt else { return 0 }
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: journeyStartedAt)
        let today = calendar.startOfDay(for: Date())
        guard start <= today else { return 1 }
        let elapsed = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return max(elapsed + 1, 1)
    }

    var journeyRangeLabel: String {
        guard let journeyStartedAt else { return "YOUR NANO JOURNEY" }
        return "SINCE \(journeyStartedAt.formatted(.dateTime.month(.abbreviated).day().year()).uppercased())"
    }

    var appleHealthImportedHistoryRange: DateInterval? {
        guard hasRequestedHealthAccess, let journeyStartedAt else { return nil }

        let calendar = Calendar.autoupdatingCurrent
        let journeyStartDay = calendar.startOfDay(for: journeyStartedAt)
        let importedStartDay = analyticsHistory.lazy
            .map { calendar.startOfDay(for: $0.day) }
            .filter { $0 < journeyStartDay }
            .min()

        guard let importedStartDay else { return nil }
        return DateInterval(start: importedStartDay, end: journeyStartDay)
    }

    var lastThirtyDaysSteps: Int {
        dailyHistory.suffix(30).reduce(0) { $0 + $1.steps }
    }

    var distanceKilometersToday: Double {
        Double(displayedTodaySteps) * 0.000762
    }

    var caloriesToday: Int {
        Int((Double(displayedTodaySteps) * 0.048).rounded())
    }

    var activeMinutesToday: Int {
        displayedTodaySteps / 100
    }

    var currentStreak: Int {
        StreakHistorySummary(records: dailyHistory, dailyGoal: dailyGoal,
                             goalHistory: dailyGoalHistory).current
    }

    var displayedCurrentStreak: Int {
        StreakHistorySummary(records: badgeEvaluationHistory, dailyGoal: dailyGoal,
                             goalHistory: dailyGoalHistory).current
    }

    var discoveredCreatureCount: Int {
        catalog.creatureStages.filter { discoveredStageIDs.contains($0.id) }.count
    }

    var nextEggCandidates: [CreatureStage] {
        guard !eggDiscoveryOrder.isEmpty else {
            return catalog.families.compactMap { $0.stages.first(where: \.isEgg) }
        }

        let orderedEggs = eggDiscoveryOrder.compactMap { familyID in
            catalog.families
                .first(where: { $0.id == familyID })?
                .stages.first(where: \.isEgg)
        }
        let undiscovered = orderedEggs.filter {
            !discoveredStageIDs.contains($0.id) && $0.familyID != currentFamily.id
        }
        let previouslyDiscovered = orderedEggs.filter {
            discoveredStageIDs.contains($0.id) && $0.familyID != currentFamily.id
        }
        return Array((undiscovered + previouslyDiscovered).prefix(3))
    }

    func isDiscovered(_ stage: CreatureStage) -> Bool {
        discoveredStageIDs.contains(stage.id)
    }

    func isCurrent(_ stage: CreatureStage) -> Bool {
        stage.id == currentStage.id
    }

    func bootstrap() async {
        guard !isOnboardingReplay else { return }
        isLoading = true
        defer { isLoading = false }

        restoreMandatoryEggSelectionEventIfNeeded()

        if AppScreenshotScenario.active != nil {
            healthState = .unavailable
            publishWidgetSnapshot()
            return
        }

        await refreshSubscriptionStatus()

        guard onboardingCompleted else {
            healthState = healthClient.isAvailable ? .notRequested : .unavailable
            return
        }

        ensureJourneyStarted()
        publishWidgetSnapshot()

        guard healthClient.isAvailable, hasRequestedHealthAccess else {
            healthState = healthClient.isAvailable ? .notRequested : .unavailable
            await refreshPedometerData()
            observePedometerChanges()
            return
        }

        healthState = .connected
        await refreshHealthData()
        if healthState == .connected {
            observeHealthChanges()
        }
    }

    func requestHealthAccess() async {
        if isOnboardingReplay {
            hasRequestedHealthAccess = true
            healthState = .connected
            return
        }
        healthState = .connecting
        ensureJourneyStarted()
        do {
            try await healthClient.requestStepAuthorization()
            hasRequestedHealthAccess = true
            healthState = .connected
            pedometerClient.stopObservingSteps()
            await refreshHealthData()
            if healthState == .connected {
                observeHealthChanges()
            }
        } catch {
            healthState = .failed(error.localizedDescription)
            await refreshPedometerData()
            observePedometerChanges()
        }
    }

    func refreshHealthData() async {
        guard !isOnboardingReplay else { return }
        guard onboardingCompleted else { return }
        applyDailyGoalScheduleIfNeeded()
        ensureJourneyStarted()
        guard let journeyStartedAt else { return }

        guard healthClient.isAvailable, hasRequestedHealthAccess else {
            healthState = healthClient.isAvailable ? .notRequested : .unavailable
            await refreshPedometerData()
            return
        }

        beginStepSync()
        do {
            let calendar = Calendar.autoupdatingCurrent
            let analyticsStart = calendar.date(
                byAdding: .year,
                value: -1,
                to: calendar.startOfDay(for: Date())
            ) ?? journeyStartedAt
            let hourlyStart = calendar.date(
                byAdding: .day,
                value: -28,
                to: calendar.startOfDay(for: Date())
            ) ?? analyticsStart

            async let journeyRequest = healthClient.fetchDailySteps(startingAt: journeyStartedAt)
            async let analyticsRequest = healthClient.fetchDailySteps(startingAt: analyticsStart)
            async let hourlyRequest = healthClient.fetchHourlySteps(startingAt: hourlyStart)

            let (journey, analytics, hourly) = try await (
                journeyRequest,
                analyticsRequest,
                hourlyRequest
            )
            applyAnalyticsHistory(analytics, hourly: hourly, merging: false)
            applyActivityHistory(journey, merging: false, showsSyncStatus: true)
            lastHealthSync = Date()
            healthState = .connected
        } catch {
            healthState = .failed(error.localizedDescription)
            finishStepSyncImmediately()
            await refreshPedometerData()
            observePedometerChanges()
        }
    }

    func activateJourneyTracking() async {
        guard !isOnboardingReplay else { return }
        guard onboardingCompleted else { return }
        ensureJourneyStarted()
        if healthClient.isAvailable, hasRequestedHealthAccess {
            await refreshHealthData()
            observeHealthChanges()
        } else {
            await refreshPedometerData()
            observePedometerChanges()
        }
    }

    func resetGameProgress() {
        healthClient.stopObservingSteps()
        pedometerClient.stopObservingSteps()
        familyIndex = 0
        stageIndex = 0
        progressionSteps = 0
        discoveredStageIDs.removeAll()
        progressionCreditHistory.removeAll()
        testingStepHistory.removeAll()
        dailyHistory.removeAll()
        analyticsHistory.removeAll()
        hourlyAnalyticsHistory.removeAll()
        dailyGoalHistory.removeAll()
        journeyStartedAt = nil
        lastCountedJourneySteps = 0
        lastHealthDateKey = nil
        lastHealthTodaySteps = 0
        hasRequestedHealthAccess = false
        healthState = healthClient.isAvailable ? .notRequested : .unavailable
        lastHealthSync = nil
        isSyncingSteps = false
        stepSyncFromTodaySteps = 0
        stepSyncFromHatchProgress = 0
        testingActivityPreviewSteps = 0
        testingProgressionPreviewSteps = 0
        testingProgressionCreditSteps = 0
        testingPresentedBadgeIDs.removeAll()
        stepSyncAnimationID = UUID()
        dailyGoalCelebrationID = nil
        lastConsumedStepSyncAnimationID = stepSyncAnimationID
        evolutionEventID = UUID()
        discoveryEvents.removeAll()
        pendingLifecycleEvents.removeAll()
        awardedBadgeIDs.removeAll()
        reviewEligibleLifecycleCount = 0
        lastReviewRequestLifecycleCount = 0
        badgeEvaluationID = UUID()
        awaitingEggSelection = false
        bankedProgressionSteps = 0
        eggDiscoveryOrder = Array(catalog.families.dropFirst().map(\.id)).shuffled()
        defaults.removeObject(forKey: discoveryStateKey)
        defaults.set(false, forKey: "nanobeasts.didCompleteAppTour")
        defaults.set(false, forKey: "nanobeasts.testing.stepButtonEnabled")
        defaults.removeObject(forKey: "nanobeasts.lastDailyGoalCelebration")
        if !isOnboardingReplay {
            OnboardingDraft.clear()
            NanoNotifications.shared.cancelOnboardingReminders()
        }
        defaults.set(false, forKey: "nanobeasts.didCompleteWorkoutControlsTour.v2")
        playerName = "Researcher"
        onboardingGoals = []
        onboardingPrimaryGoal = nil
        onboardingBlockers = []
        dailyGoal = 6_500
        scheduledDailyGoal = nil
        scheduledDailyGoalSetOn = nil
        goalRampAnchor = nil
        onboardingWantsHealth = true
        onboardingWantsReminders = false
        distanceUnit = .miles
        onboardingCompleted = false
        persist()
    }

    func saveOnboardingProfile(
        playerName: String,
        selectedGoals: Set<String>,
        primaryGoal: String? = nil,
        selectedBlockers: Set<String> = [],
        dailyGoal: Int,
        wantsHealth: Bool,
        wantsReminders: Bool
    ) {
        let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.playerName = trimmedName.isEmpty ? "Researcher" : trimmedName
        onboardingGoals = selectedGoals
        onboardingBlockers = selectedBlockers
        onboardingPrimaryGoal = WalkingGoalSelection(values: selectedGoals, preferred: primaryGoal).primary?.rawValue
        self.dailyGoal = min(max(dailyGoal, 2_000), DailyGoalPolicy.maximum)
        scheduledDailyGoal = nil
        scheduledDailyGoalSetOn = nil
        goalRampAnchor = nil
        onboardingWantsHealth = wantsHealth
        onboardingWantsReminders = wantsReminders
        persist()
    }

    func completeOnboarding() {
        if !isOnboardingReplay {
            OnboardingDraft.clear()
            NanoNotifications.shared.cancelOnboardingReminders()
        }
        if journeyStartedAt == nil {
            journeyStartedAt = Date()
            lastCountedJourneySteps = 0
            dailyHistory = []
            analyticsHistory = []
            hourlyAnalyticsHistory = []
            dailyGoalHistory = []
            lastHealthDateKey = nil
            lastHealthTodaySteps = 0
        }
        recordCurrentDailyGoal()
        onboardingCompleted = true
        // Notification authorization belongs to the explicit Settings toggle,
        // including for legacy profiles that saved a reminder preference.
        persist()
    }

    @discardableResult
    func awardInitialResearchEggIfNeeded() -> Bool {
        guard currentStage.isEgg else { return false }
        guard !discoveryEvents.contains(where: {
            $0.creatureStage.id == currentStage.id && $0.kind == .eggAcquired
        }) else {
            return false
        }

        discoveredStageIDs.insert(currentStage.id)
        let event = CreatureDiscoveryEvent(stage: currentStage, kind: .eggAcquired)
        discoveryEvents.append(event)
        pendingLifecycleEvents.append(event)
        evolutionEventID = UUID()
        persistDiscoveryEvents()
        persist()
        return true
    }

    func restartOnboarding() {
        if !isOnboardingReplay {
            OnboardingDraft.clear()
            NanoNotifications.shared.cancelOnboardingReminders()
        }
        defaults.set(false, forKey: "nanobeasts.didCompleteAppTour")
        onboardingCompleted = false
        persist()
    }

    @discardableResult
    func chooseNextEgg(_ egg: CreatureStage) -> Bool {
        guard
            awaitingEggSelection,
            egg.isEgg,
            let nextFamilyIndex = catalog.families.firstIndex(where: { $0.id == egg.familyID }),
            let nextStageIndex = catalog.families[nextFamilyIndex].stages.firstIndex(where: { $0.id == egg.id })
        else {
            return false
        }

        // Commit selection and consume this maturity together. Banked steps may
        // immediately mature the next lineage, which is a separate queued event.
        if let maturity = pendingLifecycleEvents.first(where: {
            $0.kind == .maturity && $0.familyID == currentFamily.id
        }) {
            pendingLifecycleEvents.removeAll { $0.id == maturity.id }
        }
        familyIndex = nextFamilyIndex
        stageIndex = nextStageIndex
        progressionSteps = 0
        awaitingEggSelection = false
        stepSyncFromHatchProgress = 0
        discoveredStageIDs.insert(egg.id)
        discoveryEvents.append(
            CreatureDiscoveryEvent(stage: egg, kind: .eggAcquired)
        )
        // These steps already exist in the credit ledger. Release them once,
        // without crediting them a second time when Health catches up.
        let savedSteps = bankedProgressionSteps
        bankedProgressionSteps = 0
        applyProgress(savedSteps)
        evolutionEventID = UUID()
        persistDiscoveryEvents()
        persist()
        return true
    }

    func consumeStepSyncAnimationIfNeeded() -> Bool {
        guard lastConsumedStepSyncAnimationID != stepSyncAnimationID else {
            return false
        }
        lastConsumedStepSyncAnimationID = stepSyncAnimationID
        return true
    }

    func addTestingSteps(_ amount: Int = 100) async {
        guard onboardingCompleted, amount > 0 else { return }

        // Progress is intentionally paused at full maturity. If an older app
        // version allowed the mandatory chooser to close, use the testing
        // shortcut as another recovery trigger instead of silently doing
        // nothing behind the awaiting-egg lock.
        if restoreMandatoryEggSelectionEventIfNeeded() {
            return
        }

        // A purchase can complete while Home still has the last cached free
        // entitlement. Resolve that state before applying a testing increment
        // so an active Pro member is never evaluated against the free cap.
        if !isPremium {
            await refreshSubscriptionStatus()
        }

        addTestingStepsImmediately(amount)
    }

    private func addTestingStepsImmediately(_ amount: Int) {
        guard onboardingCompleted, amount > 0 else { return }
        ensureJourneyStarted()

        let previousToday = displayedTodaySteps
        let previousProgress = hatchProgress

        // Show a recording-friendly activity preview without modifying any
        // Health-backed ledger. The next HealthKit/pedometer update clears it.
        testingActivityPreviewSteps += amount
        creditTestingProgress(amount)
        stepSyncFromTodaySteps = previousToday
        stepSyncFromHatchProgress = previousProgress
        stepSyncDuration = 0.88
        stepSyncAnimationID = UUID()
        recordDailyGoalCrossing(
            from: previousToday,
            to: displayedTodaySteps
        )
        badgeEvaluationID = UUID()
        persist()
    }

    private func creditTestingProgress(_ amount: Int) {
        guard amount > 0, !awaitingEggSelection else { return }

        let creditedAmount = isPremium ? amount : 0

        guard creditedAmount > 0 else { return }
        testingProgressionCreditSteps += creditedAmount
        applyTestingProgress(creditedAmount)
    }

    func acknowledgeLifecycleEvent(_ eventID: UUID) {
        pendingLifecycleEvents.removeAll { $0.id == eventID }
        evolutionEventID = UUID()
        persist()
    }

    @discardableResult
    private func restoreMandatoryEggSelectionEventIfNeeded() -> Bool {
        guard awaitingEggSelection else { return false }

        let alreadyQueued = pendingLifecycleEvents.contains(where: {
            $0.kind == .maturity && $0.familyID == currentFamily.id
        })
        if !alreadyQueued {
            let maturityEvent = discoveryEvents.last(where: {
                $0.kind == .maturity && $0.familyID == currentFamily.id
            }) ?? CreatureDiscoveryEvent(stage: currentStage, kind: .maturity)

            if !discoveryEvents.contains(where: { $0.id == maturityEvent.id }) {
                discoveryEvents.append(maturityEvent)
                persistDiscoveryEvents()
            }
            pendingLifecycleEvents.append(maturityEvent)
            persist()
        }

        // Notify AppRoot even when the event was already queued. This covers
        // an interrupted presentation without duplicating the maturity event.
        evolutionEventID = UUID()
        return true
    }

    func markBadgeAwardPresented(_ badgeID: String) {
        if hasTestingActivityPreview {
            testingPresentedBadgeIDs.insert(badgeID)
            return
        }
        awardedBadgeIDs.insert(badgeID)
        persist()
    }

    func repairLegacyBadgeAcknowledgements(unlockedIDs: Set<String>) {
        let migrationKey = "nanobeasts.badge-acknowledgements.v2"
        guard !defaults.bool(forKey: migrationKey), !hasTestingActivityPreview,
              !dailyHistory.isEmpty, AppScreenshotScenario.active == nil else { return }
        // Older previews and badge rules could acknowledge thresholds the real
        // journey has not earned. Those IDs must not suppress a future award.
        awardedBadgeIDs = BadgeAwardDelivery.validAcknowledgements(
            awardedBadgeIDs, unlockedIDs: unlockedIDs
        )
        defaults.set(true, forKey: migrationKey)
        persist()
    }

    @ObservationIgnored private var subscriptionRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var latestCustomerInfoDate: Date?
    @ObservationIgnored private var hasSyncedPurchasesThisSession = false

    private var cachedSubscriptionAccess: NanoSubscriptionAccess? {
        defaults.data(forKey: NanoSubscriptionAccess.cacheKey)
            .flatMap { try? JSONDecoder().decode(NanoSubscriptionAccess.self, from: $0) }
    }

    private var cachedSubscriptionExpired: Bool {
        guard let access = cachedSubscriptionAccess else { return false }
        return !access.permitsCurrentBuild || (access.expiresAt.map { $0 <= Date() } ?? false)
    }

    private func expireSubscriptionIfNeeded() {
        if isPremium, cachedSubscriptionExpired { updatePremiumStatus(false) }
    }

    func refreshSubscriptionStatus(forceRefresh: Bool = false) async {
        guard !isOnboardingReplay, AppScreenshotScenario.active == nil else { return }
        // Launch and foreground can overlap. Both callers must await the same
        // result, rather than letting bootstrap continue with an unresolved gate.
        if let subscriptionRefreshTask {
            await subscriptionRefreshTask.value
            return
        }
        let task = Task { @MainActor in
            await reconcileSubscriptionStatus(forceRefresh: forceRefresh)
            hasResolvedInitialSubscription = true
        }
        subscriptionRefreshTask = task
        await task.value
        subscriptionRefreshTask = nil
    }

    private func reconcileSubscriptionStatus(forceRefresh: Bool) async {
        let needsCurrentInfo = forceRefresh || !hasResolvedInitialSubscription
            || !isPremium || cachedSubscriptionExpired
        // The signed App Store record can already contain a renewal that has
        // not reached RevenueCat yet. Recover it without an account prompt.
        let appleAccess = await verifiedAppleSubscriptionAccess()
        if let appleAccess {
            saveSubscriptionAccess(appleAccess)
            hasResolvedInitialSubscription = true
        } else if isPremium, cachedSubscriptionAccess?.allowsAccess(at: Date()) == true {
            // A verified, unexpired cache can open Home while the network checks
            // run. A saved denial or expired record must wait for reconciliation.
            hasResolvedInitialSubscription = true
        }
        guard Purchases.isConfigured else {
            expireSubscriptionIfNeeded()
            return
        }

        do {
            var customerInfo = try await Purchases.shared.customerInfo(
                fetchPolicy: needsCurrentInfo ? .fetchCurrent : .notStaleCachedOrFetched)
            if !revenueCatHasCurrentAccess(customerInfo),
               !hasSyncedPurchasesThisSession || forceRefresh {
                // Fetching CustomerInfo only reads the server's record. Sync
                // the receipt too before declaring a returning subscriber lapsed.
                customerInfo = try await Purchases.shared.syncPurchases()
                hasSyncedPurchasesThisSession = true
            }
            await applyRevenueCatCustomerInfo(customerInfo)
        } catch {
            // Network failure isn't evidence of cancellation. Retain verified
            // access only through its paid or billing-grace deadline.
            expireSubscriptionIfNeeded()
        }
    }

    func observeSubscriptionUpdates() async {
        guard !isOnboardingReplay, AppScreenshotScenario.active == nil,
              Purchases.isConfigured else { return }
        for await customerInfo in Purchases.shared.customerInfoStream {
            guard !Task.isCancelled else { return }
            // The refresh owns the final reconciled result while in flight.
            guard subscriptionRefreshTask == nil else { continue }
            if revenueCatHasCurrentAccess(customerInfo) {
                await applyRevenueCatCustomerInfo(customerInfo)
            } else {
                await refreshSubscriptionStatus()
            }
        }
    }

    private func revenueCatHasCurrentAccess(_ customerInfo: CustomerInfo) -> Bool {
        if let entitlement = customerInfo.entitlements["premium"], entitlement.isActive {
            let expiration = NanoSubscriptionAccess.accessExpiration(
                paidThrough: entitlement.expirationDate,
                graceThrough: customerInfo.subscriptionsByProductIdentifier[entitlement.productIdentifier]?.gracePeriodExpiresDate)
            return expiration.map { $0 > Date() } ?? true
        }
        return customerInfo.activeSubscriptions.intersection(Self.premiumProductIDs).contains {
            guard let subscription = customerInfo.subscriptionsByProductIdentifier[$0] else { return false }
            let expiration = NanoSubscriptionAccess.accessExpiration(
                paidThrough: subscription.expiresDate, graceThrough: subscription.gracePeriodExpiresDate)
            return expiration.map { $0 > Date() } ?? true
        }
    }

    private func verifiedAppleSubscriptionAccess() async -> NanoSubscriptionAccess? {
#if DEBUG
        guard !Self.isUsingRevenueCatTestStore else { return nil }
        if let access = await verifiedDevelopmentSubscriptionAccess() { return access }
#endif
        var latestExpiration: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  Self.premiumProductIDs.contains(transaction.productID),
                  transaction.revocationDate == nil, !transaction.isUpgraded,
                  let paidThrough = transaction.expirationDate else { continue }
            var expiration = paidThrough
            if paidThrough <= Date(),
               let status = await transaction.subscriptionStatus,
               status.state == .inGracePeriod,
               case let .verified(renewal) = status.renewalInfo,
               let graceThrough = renewal.gracePeriodExpirationDate {
                expiration = max(paidThrough, graceThrough)
            }
            guard expiration > Date() else { continue }
            latestExpiration = max(latestExpiration ?? expiration, expiration)
        }
        guard let latestExpiration else { return nil }
        return NanoSubscriptionAccess(premium: true, onboardingCompleted: onboardingCompleted,
            expiresAt: latestExpiration, updatedAt: Date())
    }

#if DEBUG
    private func verifiedDevelopmentSubscriptionAccess() async -> NanoSubscriptionAccess? {
        // Apple's accelerated test renewals eventually stop. A signed sandbox
        // purchase keeps this local Debug install usable without renewing it.
        // This code is absent from App Store / TestFlight Release builds.
        for productID in Self.premiumProductIDs {
            guard let result = await StoreKit.Transaction.latest(for: productID),
                  case let .verified(transaction) = result,
                  Self.premiumProductIDs.contains(transaction.productID),
                  transaction.environment == .sandbox,
                  transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
            return NanoSubscriptionAccess(premium: true, onboardingCompleted: onboardingCompleted,
                expiresAt: nil, updatedAt: Date(), isDevelopmentOnly: true)
        }
        return nil
    }
#endif

    private func saveSubscriptionAccess(_ access: NanoSubscriptionAccess) {
        if let data = try? JSONEncoder().encode(access) {
            defaults.set(data, forKey: NanoSubscriptionAccess.cacheKey)
        }
        updatePremiumStatus(access.premium)
    }

    func applyRevenueCatCustomerInfo(_ customerInfo: CustomerInfo) async {
        guard !isOnboardingReplay else { return }
        let appleAccess = await verifiedAppleSubscriptionAccess()
        // An older fetch must not overwrite a purchase or renewal received while
        // awaiting StoreKit. CustomerInfo timestamps come from RevenueCat.
        guard latestCustomerInfoDate.map({ customerInfo.requestDate >= $0 }) ?? true else { return }
        latestCustomerInfoDate = customerInfo.requestDate
        let hasPremiumEntitlement = revenueCatHasCurrentAccess(customerInfo)

#if DEBUG
        let resolvedPremium = hasPremiumEntitlement
            || (Self.isUsingRevenueCatTestStore
                && defaults.bool(forKey: Self.testStorePremiumUnlockKey))
#else
        let resolvedPremium = hasPremiumEntitlement
#endif

        var expiration: Date?
        if let entitlement = customerInfo.entitlements["premium"], entitlement.isActive {
            expiration = NanoSubscriptionAccess.accessExpiration(
                paidThrough: entitlement.expirationDate,
                graceThrough: customerInfo.subscriptionsByProductIdentifier[entitlement.productIdentifier]?.gracePeriodExpiresDate)
        } else {
            let subscriptions = customerInfo.activeSubscriptions
                .intersection(Self.premiumProductIDs)
                .compactMap { customerInfo.subscriptionsByProductIdentifier[$0] }
            if !subscriptions.contains(where: { $0.expiresDate == nil }) {
                expiration = subscriptions.compactMap {
                    NanoSubscriptionAccess.accessExpiration(
                        paidThrough: $0.expiresDate, graceThrough: $0.gracePeriodExpiresDate)
                }.max()
            }
        }
#if DEBUG
        if Self.isUsingRevenueCatTestStore,
           defaults.bool(forKey: Self.testStorePremiumUnlockKey) { expiration = nil }
#endif
        var access = NanoSubscriptionAccess(premium: resolvedPremium,
            onboardingCompleted: onboardingCompleted, expiresAt: expiration, updatedAt: Date())
#if DEBUG
        if Self.isUsingRevenueCatTestStore,
           defaults.bool(forKey: Self.testStorePremiumUnlockKey) { access.isDevelopmentOnly = true }
#endif
        if let appleAccess, appleAccess.isDevelopmentOnly == true || !resolvedPremium
            || (expiration.map { (appleAccess.expiresAt ?? .distantPast) > $0 } ?? false) {
            saveSubscriptionAccess(appleAccess)
        } else {
            saveSubscriptionAccess(access)
        }
    }

    func applyRevenueCatPurchase(_ customerInfo: CustomerInfo) async {
#if DEBUG
        if Self.isUsingRevenueCatTestStore {
            // Test Store subscriptions are intentionally temporary. A
            // successful non-billable purchase should remain unlocked for this
            // installed development build until the app is deleted.
            defaults.set(true, forKey: Self.testStorePremiumUnlockKey)
        }
#endif
        await applyRevenueCatCustomerInfo(customerInfo)
    }

    private func updatePremiumStatus(_ hasPremiumEntitlement: Bool) {
        let wasPremium = isPremium
        let previousProgress = hatchProgress
        isPremium = hasPremiumEntitlement
        if isPremium && !isOnboardingReplay { NanoNotifications.shared.cancelOnboardingReminders() }
        defaults.set(isPremium, forKey: Self.premiumStateKey)
        creditProgressionForToday()
        if !wasPremium, isPremium, abs(hatchProgress - previousProgress) > 0.000_1 {
            stepSyncFromTodaySteps = todaySteps
            stepSyncFromHatchProgress = previousProgress
            stepSyncDuration = 1.1
            stepSyncAnimationID = UUID()
        }
        persist()
    }

#if DEBUG
    private static var isUsingRevenueCatTestStore: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String)?
            .hasPrefix("test_") == true
    }
#endif

    @discardableResult
    func recordLifecycleCompletionForReview(_ kind: CreatureDiscoveryKind) -> Bool {
        guard !isOnboardingReplay else { return false }
        guard kind == .hatch || kind == .evolution else { return false }
        reviewEligibleLifecycleCount += 1
        let shouldRequest =
            reviewEligibleLifecycleCount.isMultiple(of: 2)
            && reviewEligibleLifecycleCount > lastReviewRequestLifecycleCount
        if shouldRequest {
            lastReviewRequestLifecycleCount = reviewEligibleLifecycleCount
        }
        persist()
        return shouldRequest
    }

    private func applyProgress(_ delta: Int) {
        guard delta > 0 else { return }
        if awaitingEggSelection {
            bankedProgressionSteps += delta
            return
        }
        progressionSteps += delta

        var transitions = 0
        while progressionSteps >= currentTarget && transitions < 100 {
            progressionSteps -= currentTarget
            let previousStage = currentStage
            discoveredStageIDs.insert(currentStage.id)

            if stageIndex + 1 >= currentFamily.stages.count {
                awaitingEggSelection = true
                bankedProgressionSteps += progressionSteps
                progressionSteps = 0
                let event = CreatureDiscoveryEvent(stage: previousStage, kind: .maturity)
                discoveryEvents.append(event)
                pendingLifecycleEvents.append(event)
                transitions += 1
                break
            } else {
                advanceStage()
                let newStage = currentStage
                let discoveryKind: CreatureDiscoveryKind = previousStage.isEgg ? .hatch : .evolution
                let event = CreatureDiscoveryEvent(stage: newStage, kind: discoveryKind)
                discoveryEvents.append(event)
                pendingLifecycleEvents.append(event)
                transitions += 1
            }
        }

        if transitions > 0 {
            evolutionEventID = UUID()
            persistDiscoveryEvents()
        }
    }

    /// Advances the visible lifecycle for the hidden recording tool without
    /// writing synthetic step credits into the Health-backed progression
    /// ledger. A later Health or pedometer update clears any unconsumed
    /// preview steps and returns the ring to authoritative progress.
    private func applyTestingProgress(_ delta: Int) {
        guard delta > 0, !awaitingEggSelection else { return }
        testingProgressionPreviewSteps += delta

        var transitions = 0
        while
            progressionSteps + testingProgressionPreviewSteps >= currentTarget,
            transitions < 100
        {
            let previewNeeded = max(currentTarget - progressionSteps, 0)
            testingProgressionPreviewSteps = max(
                testingProgressionPreviewSteps - previewNeeded,
                0
            )
            progressionSteps = 0

            let previousStage = currentStage
            discoveredStageIDs.insert(previousStage.id)
            if stageIndex + 1 >= currentFamily.stages.count {
                awaitingEggSelection = true
                testingProgressionPreviewSteps = 0
                let event = CreatureDiscoveryEvent(
                    stage: previousStage,
                    kind: .maturity
                )
                discoveryEvents.append(event)
                pendingLifecycleEvents.append(event)
                transitions += 1
                break
            }

            advanceStage()
            let newStage = currentStage
            let kind: CreatureDiscoveryKind =
                previousStage.isEgg ? .hatch : .evolution
            let event = CreatureDiscoveryEvent(stage: newStage, kind: kind)
            discoveryEvents.append(event)
            pendingLifecycleEvents.append(event)
            transitions += 1
        }

        if transitions > 0 {
            evolutionEventID = UUID()
            persistDiscoveryEvents()
        }
    }

    private func advanceStage() {
        if stageIndex + 1 < currentFamily.stages.count {
            stageIndex += 1
        } else {
            familyIndex = (familyIndex + 1) % catalog.families.count
            stageIndex = 0
        }
    }

    private func observeHealthChanges() {
        pedometerClient.stopObservingSteps()
        healthClient.startObservingSteps { [weak self] in
            await self?.refreshHealthData()
        }
    }

    private func refreshPedometerData() async {
        guard onboardingCompleted else { return }
        applyDailyGoalScheduleIfNeeded()
        ensureJourneyStarted()
        guard let journeyStartedAt, pedometerClient.isAvailable else { return }

        do {
            let history = try await pedometerClient.fetchRecentDailySteps(startingAt: journeyStartedAt)
            applyAnalyticsHistory(history, hourly: [], merging: true)
            applyActivityHistory(history, merging: true, showsSyncStatus: false)
        } catch {
            // A denied Motion permission leaves the journey at zero without
            // importing any other source or presenting stale progress.
        }
    }

    private func observePedometerChanges() {
        guard let journeyStartedAt, pedometerClient.isAvailable else { return }
        healthClient.stopObservingSteps()
        pedometerClient.startObservingSteps(startingAt: journeyStartedAt) { [weak self] record in
            await self?.applyPedometerUpdate(record)
        }
    }

    private func applyPedometerUpdate(_ record: DailyStepRecord) {
        applyAnalyticsHistory([record], hourly: [], merging: true)
        applyActivityHistory([record], merging: true, showsSyncStatus: false)
    }

    private func applyAnalyticsHistory(
        _ incoming: [DailyStepRecord],
        hourly: [HourlyStepRecord],
        merging: Bool
    ) {
        let calendar = Calendar.autoupdatingCurrent
        let normalized = incoming.map {
            let day = calendar.startOfDay(for: $0.day)
            return DailyStepRecord(
                day: day,
                steps: max(0, $0.steps)
            )
        }

        if merging {
            var byDay = Dictionary(
                analyticsHistory.map { (calendar.startOfDay(for: $0.day), $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            for record in normalized {
                byDay[record.day] = record
            }
            analyticsHistory = byDay.values.sorted { $0.day < $1.day }
        } else {
            let byDay = Dictionary(
                normalized.map { ($0.day, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            analyticsHistory = byDay.values.sorted { $0.day < $1.day }
        }

        if !hourly.isEmpty {
            hourlyAnalyticsHistory = hourly
                .map {
                    HourlyStepRecord(
                        start: $0.start,
                        steps: max(0, $0.steps)
                    )
                }
                .sorted { $0.start < $1.start }
        }
    }

    private func applyActivityHistory(
        _ incoming: [DailyStepRecord],
        merging: Bool,
        showsSyncStatus: Bool
    ) {
        guard let journeyStartedAt else { return }
        let calendar = Calendar.autoupdatingCurrent
        let boundaryDay = calendar.startOfDay(for: journeyStartedAt)
        let filtered = incoming.filter { $0.day >= boundaryDay }
        let oldToday = displayedTodaySteps
        let oldProgress = hatchProgress

        if merging {
            var byDay = Dictionary(
                dailyHistory.map { (calendar.startOfDay(for: $0.day), $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            for record in filtered {
                let day = calendar.startOfDay(for: record.day)
                byDay[day] = DailyStepRecord(
                    day: day,
                    steps: max(0, record.steps)
                )
            }
            dailyHistory = byDay.values.sorted { $0.day < $1.day }
        } else {
            let byDay = Dictionary(
                filtered.map {
                    let day = calendar.startOfDay(for: $0.day)
                    return DailyStepRecord(
                        day: day,
                        steps: max(0, $0.steps)
                    )
                }.map { ($0.day, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            dailyHistory = byDay.values.sorted { $0.day < $1.day }
        }

        // A successful HealthKit/pedometer result is authoritative. Remove the
        // recording preview before calculating the destination animation.
        testingActivityPreviewSteps = 0
        testingProgressionPreviewSteps = 0
        testingProgressionCreditSteps = 0
        testingPresentedBadgeIDs.removeAll()
        let journeyTotal = dailyHistory.reduce(0) { $0 + $1.steps }
        lastCountedJourneySteps = max(lastCountedJourneySteps, journeyTotal)
        creditProgressionForToday()

        let changedSteps = abs(displayedTodaySteps - oldToday)
        let activityChanged =
            changedSteps > 0
            || abs(hatchProgress - oldProgress) > 0.000_1

        if activityChanged {
            stepSyncFromTodaySteps = oldToday
            stepSyncFromHatchProgress = oldProgress
            stepSyncDuration = min(
                max(0.75 + Double(changedSteps) / 6_000, 0.85),
                1.65
            )
            stepSyncAnimationID = UUID()
            recordDailyGoalCrossing(
                from: oldToday,
                to: displayedTodaySteps
            )
        }
        badgeEvaluationID = UUID()

        if showsSyncStatus {
            if activityChanged {
                scheduleStepSyncFinish(after: stepSyncDuration)
            } else {
                finishStepSyncImmediately()
            }
        }
        persist()
    }

    private func recordDailyGoalCrossing(from previousSteps: Int, to currentSteps: Int) {
        guard previousSteps < dailyGoal, currentSteps >= dailyGoal else {
            return
        }
        dailyGoalCelebrationID = UUID()
    }

    private func creditProgressionForToday() {
        guard onboardingCompleted else { return }
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let eligibleTotal = isPremium ? todaySteps : 0
        let existingIndex = progressionCreditHistory.firstIndex {
            calendar.isDate($0.day, inSameDayAs: today)
        }
        let previouslyCredited = existingIndex.map {
            progressionCreditHistory[$0].steps
        } ?? 0
        let newlyEligible = max(eligibleTotal - previouslyCredited, 0)

        if let existingIndex {
            progressionCreditHistory[existingIndex] = DailyStepRecord(
                day: today,
                steps: max(previouslyCredited, eligibleTotal)
            )
        } else {
            progressionCreditHistory.append(
                DailyStepRecord(day: today, steps: eligibleTotal)
            )
            progressionCreditHistory.sort { $0.day < $1.day }
        }

        if newlyEligible > 0 {
            applyProgress(newlyEligible)
        }
    }

    private func ensureJourneyStarted() {
        guard journeyStartedAt == nil else { return }
        journeyStartedAt = Date()
        lastCountedJourneySteps = 0
        dailyHistory = []
        dailyGoalHistory = []
        recordCurrentDailyGoal()
        persist()
    }

    func goal(for day: Date) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        let normalized = calendar.startOfDay(for: day)
        return dailyGoalHistory
            .filter { calendar.startOfDay(for: $0.day) <= normalized }
            .max { $0.day < $1.day }?
            .goal ?? dailyGoal
    }

    /// Saves a goal for tomorrow. Below-minimum goals (assigned by onboarding)
    /// can be raised but never lowered; everyone else stays at 5,000 or more.
    func scheduleDailyGoal(_ goal: Int) {
        let floor = min(dailyGoal, DailyGoalPolicy.manualMinimum)
        let clamped = min(max(goal, floor), DailyGoalPolicy.maximum)
        scheduledDailyGoal = clamped == dailyGoal ? nil : clamped
        scheduledDailyGoalSetOn = scheduledDailyGoal == nil ? nil : Date()
        persist()
    }

    /// The goal Settings should show: tomorrow's if one is pending, otherwise today's.
    var upcomingDailyGoal: Int { scheduledDailyGoal ?? dailyGoal }

    var isDailyGoalRamping: Bool { upcomingDailyGoal < DailyGoalPolicy.manualMinimum }

    /// Runs at each refresh. On a new day it applies a scheduled goal, then
    /// advances any below-minimum goal by 500 per completed week.
    func applyDailyGoalScheduleIfNeeded(now: Date = Date()) {
        guard onboardingCompleted else { return }
        let current = DailyGoalPolicy.State(goal: dailyGoal, scheduledGoal: scheduledDailyGoal,
                                            scheduledOn: scheduledDailyGoalSetOn, rampAnchor: goalRampAnchor)
        let next = DailyGoalPolicy.advance(current, to: now)
        guard next != current else { return }
        scheduledDailyGoal = next.scheduledGoal
        scheduledDailyGoalSetOn = next.scheduledOn
        goalRampAnchor = next.rampAnchor
        if next.goal != dailyGoal {
            dailyGoal = next.goal // Records today's goal and persists.
        } else {
            persist()
        }
    }

    private func recordCurrentDailyGoal() {
        guard journeyStartedAt != nil else { return }
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        if let index = dailyGoalHistory.firstIndex(where: {
            calendar.isDate($0.day, inSameDayAs: today)
        }) {
            dailyGoalHistory[index] = DailyGoalRecord(day: today, goal: dailyGoal)
        } else {
            dailyGoalHistory.append(DailyGoalRecord(day: today, goal: dailyGoal))
            dailyGoalHistory.sort { $0.day < $1.day }
        }
    }

    private func beginStepSync() {
        isSyncingSteps = true
    }

    private func finishStepSyncImmediately() {
        isSyncingSteps = false
    }

    private func scheduleStepSyncFinish(after duration: Double) {
        let animationID = stepSyncAnimationID
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard self?.stepSyncAnimationID == animationID else { return }
            self?.isSyncingSteps = false
        }
    }

    private func persist() {
        guard !isOnboardingReplay else { return }
        persistenceTask?.cancel()
        persistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            await self.writePersistedState()
        }
    }

    private func writePersistedState() async {
        let state = PersistedState(
            familyIndex: familyIndex,
            stageIndex: stageIndex,
            progressionSteps: progressionSteps,
            bankedProgressionSteps: bankedProgressionSteps,
            discoveredStageIDs: Array(discoveredStageIDs),
            dailyGoal: dailyGoal,
            hasRequestedHealthAccess: hasRequestedHealthAccess,
            lastHealthDateKey: lastHealthDateKey,
            lastHealthTodaySteps: lastHealthTodaySteps,
            hapticsEnabled: hapticsEnabled,
            reduceMotion: reduceMotion,
            distanceUnit: distanceUnit,
            onboardingCompleted: onboardingCompleted,
            playerName: playerName,
            onboardingGoals: onboardingGoals.sorted(),
            onboardingPrimaryGoal: onboardingPrimaryGoal,
            onboardingBlockers: onboardingBlockers.sorted(),
            onboardingWantsHealth: onboardingWantsHealth,
            onboardingWantsReminders: onboardingWantsReminders,
            awaitingEggSelection: awaitingEggSelection,
            journeyStartedAt: journeyStartedAt,
            lastCountedJourneySteps: lastCountedJourneySteps,
            dailyHistory: dailyHistory,
            analyticsHistory: analyticsHistory,
            hourlyAnalyticsHistory: hourlyAnalyticsHistory,
            dailyGoalHistory: dailyGoalHistory,
            scheduledDailyGoal: scheduledDailyGoal,
            scheduledDailyGoalSetOn: scheduledDailyGoalSetOn,
            goalRampAnchor: goalRampAnchor,
            pendingLifecycleEvents: pendingLifecycleEvents,
            awardedBadgeIDs: Array(awardedBadgeIDs),
            eggDiscoveryOrder: eggDiscoveryOrder,
            progressionCreditHistory: progressionCreditHistory,
            testingStepHistory: testingStepHistory,
            isPremium: isPremium,
            reviewEligibleLifecycleCount: reviewEligibleLifecycleCount,
            lastReviewRequestLifecycleCount: lastReviewRequestLifecycleCount
        )
        let data = await Task.detached(priority: .utility) {
            try? JSONEncoder().encode(state)
        }.value
        guard !Task.isCancelled else { return }
        if let data {
            defaults.set(data, forKey: stateKey)
        }

        publishWidgetSnapshot()
        await NanoNotifications.shared.updateProgress(
            stageID: currentStage.id, name: currentStage.name, isEgg: currentStage.isEgg,
            remaining: max(0, currentTarget - progressionSteps), target: currentTarget,
            journey: journeyStartedAt,
            eligible: onboardingCompleted && isPremium && !awaitingEggSelection
                && !hasTestingActivityPreview && AppScreenshotScenario.active == nil
        )
    }

    private func publishWidgetSnapshot() {
        guard !isOnboardingReplay else { return }
        WorkoutWatchBridge.shared.updateCompanion(workoutCompanionStage, dailyGoal: dailyGoal,
                                                   evolution: workoutCompanionProgress)
        let cached = defaults.data(forKey: NanoSubscriptionAccess.cacheKey)
            .flatMap { try? JSONDecoder().decode(NanoSubscriptionAccess.self, from: $0) }
        let access = NanoSubscriptionAccess(premium: isPremium,
            onboardingCompleted: onboardingCompleted, expiresAt: cached?.expiresAt, updatedAt: Date(),
            isDevelopmentOnly: cached?.isDevelopmentOnly)
        WorkoutWatchBridge.shared.updateSubscriptionAccess(access)
        if onboardingCompleted, isPremium {
            WidgetSnapshotWriter.shared.update(
                stage: currentStage,
                todaySteps: displayedTodaySteps,
                dailyGoal: dailyGoal,
                evolutionProgress: hatchProgress,
                stepsRemaining: max(currentTarget - hatchProgressSteps, 0),
                streak: displayedCurrentStreak
            )
        } else {
            WidgetSnapshotWriter.shared.clear()
        }
    }

    private func persistDiscoveryEvents() {
        guard !isOnboardingReplay else { return }
        guard let data = try? JSONEncoder().encode(discoveryEvents) else { return }
        defaults.set(data, forKey: discoveryStateKey)
    }

    private static func dateKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
