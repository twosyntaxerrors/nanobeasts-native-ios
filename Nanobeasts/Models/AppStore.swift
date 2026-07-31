import Foundation
import Observation
import RevenueCat

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
        var onboardingWantsHealth: Bool?
        var onboardingWantsReminders: Bool?
        var awaitingEggSelection = false
        var journeyStartedAt: Date?
        var lastCountedJourneySteps: Int?
        var dailyHistory: [DailyStepRecord]?
        var analyticsHistory: [DailyStepRecord]?
        var hourlyAnalyticsHistory: [HourlyStepRecord]?
        var dailyGoalHistory: [DailyGoalRecord]?
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
    private let stateKey = "nanobeasts.native.game-state.v1"
    private let discoveryStateKey = "nanobeasts.native.discovery-events.v1"

    private var familyIndex: Int
    private var stageIndex: Int
    private var progressionSteps: Int
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
    var distanceUnit: DistanceUnitPreference {
        didSet { persist() }
    }
    var onboardingCompleted: Bool {
        didSet { persist() }
    }
    var playerName: String {
        didSet { persist() }
    }
    var onboardingWantsHealth: Bool {
        didSet { persist() }
    }
    var onboardingWantsReminders: Bool {
        didSet { persist() }
    }

    private(set) var healthState: HealthConnectionState = .notRequested
    private(set) var dailyHistory: [DailyStepRecord] = []
    private(set) var analyticsHistory: [DailyStepRecord] = []
    private(set) var hourlyAnalyticsHistory: [HourlyStepRecord] = []
    private(set) var dailyGoalHistory: [DailyGoalRecord] = []
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
    private(set) var stepSyncFromTodaySteps = 0
    private(set) var stepSyncFromHatchProgress = 0.0
    private(set) var stepSyncDuration = 1.0
    private(set) var testingActivityPreviewSteps = 0
    private(set) var testingProgressionPreviewSteps = 0
    private(set) var testingProgressionCreditSteps = 0
    private var testingPresentedBadgeIDs: Set<String> = []
    @ObservationIgnored private var lastConsumedStepSyncAnimationID: UUID?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?

    init(
        catalog: CreatureCatalog = .load(),
        healthClient: HealthKitClient = HealthKitClient(),
        pedometerClient: PedometerClient = PedometerClient(),
        defaults: UserDefaults = .standard
    ) {
        self.catalog = catalog
        self.healthClient = healthClient
        self.pedometerClient = pedometerClient
        self.defaults = defaults

        let restored: PersistedState
        if
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
        discoveredStageIDs = Set(restored.discoveredStageIDs)
        dailyGoal = restored.dailyGoal
        hasRequestedHealthAccess = restored.hasRequestedHealthAccess
        lastHealthDateKey = restored.lastHealthDateKey
        lastHealthTodaySteps = restored.lastHealthTodaySteps
        hapticsEnabled = restored.hapticsEnabled
        reduceMotion = restored.reduceMotion
        distanceUnit = restored.distanceUnit ?? .miles
        onboardingCompleted = restored.onboardingCompleted ?? false
        playerName = restored.playerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
        discoveryEvents = defaults.data(forKey: discoveryStateKey)
            .flatMap { try? JSONDecoder().decode([CreatureDiscoveryEvent].self, from: $0) }
            ?? []
        pendingLifecycleEvents = restored.pendingLifecycleEvents ?? []
        awardedBadgeIDs = Set(restored.awardedBadgeIDs ?? [])
        isPremium = restored.isPremium ?? false
        reviewEligibleLifecycleCount = restored.reviewEligibleLifecycleCount ?? 0
        lastReviewRequestLifecycleCount = restored.lastReviewRequestLifecycleCount ?? 0
        let eligibleFamilyIDs = Array(catalog.families.dropFirst().map(\.id))
        let restoredOrder = restored.eggDiscoveryOrder ?? []
        eggDiscoveryOrder =
            Set(restoredOrder) == Set(eligibleFamilyIDs)
                ? restoredOrder
                : eligibleFamilyIDs.shuffled()

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
        lastConsumedStepSyncAnimationID = stepSyncAnimationID
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

        if familyIndex == 0 {
            return currentStage.stage == 0 ? 250 : 500
        }

        let base = 10_000 + 1_500 * max(familyIndex - 1, 0)
        let multiplier: Double = switch min(max(currentStage.stage, 0), 3) {
        case 0: 0.30
        case 1: 0.55
        case 2: 0.75
        default: 1
        }
        let rounded = Int((Double(base) * multiplier / 100).rounded()) * 100
        return min(max(rounded, 500), 15_000)
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

    static let freeDailyProgressionCap = 2_500

    var progressionStepsCreditedToday: Int {
        let calendar = Calendar.autoupdatingCurrent
        return progressionCreditHistory.first(where: {
            calendar.isDateInToday($0.day)
        })?.steps ?? 0
    }

    var freeProgressionCapReached: Bool {
        !isPremium
            && progressionStepsCreditedToday + testingProgressionCreditSteps
                >= Self.freeDailyProgressionCap
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
        var streak = 0
        for record in dailyHistory.reversed() {
            if record.steps >= goal(for: record.day) {
                streak += 1
            } else if Calendar.autoupdatingCurrent.isDateInToday(record.day) && record.steps > 0 {
                continue
            } else {
                break
            }
        }
        return streak
    }

    var displayedCurrentStreak: Int {
        var streak = 0
        for record in displayedRecentWeek.reversed() {
            if record.steps >= goal(for: record.day) {
                streak += 1
            } else if Calendar.autoupdatingCurrent.isDateInToday(record.day)
                        && record.steps > 0 {
                continue
            } else {
                break
            }
        }
        return streak
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
        isLoading = true
        defer { isLoading = false }

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
        guard onboardingCompleted else { return }
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
        eggDiscoveryOrder = Array(catalog.families.dropFirst().map(\.id)).shuffled()
        defaults.removeObject(forKey: discoveryStateKey)
        defaults.set(false, forKey: "nanobeasts.didCompleteAppTour")
        defaults.set(false, forKey: "nanobeasts.testing.stepButtonEnabled")
        defaults.removeObject(forKey: "nanobeasts.lastDailyGoalCelebration")
        playerName = "Researcher"
        dailyGoal = 6_500
        onboardingWantsHealth = true
        onboardingWantsReminders = false
        distanceUnit = .miles
        onboardingCompleted = false
        persist()
    }

    func saveOnboardingProfile(
        playerName: String,
        dailyGoal: Int,
        wantsHealth: Bool,
        wantsReminders: Bool
    ) {
        let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.playerName = trimmedName.isEmpty ? "Researcher" : trimmedName
        self.dailyGoal = min(max(dailyGoal, 2_000), 20_000)
        onboardingWantsHealth = wantsHealth
        onboardingWantsReminders = wantsReminders
        persist()
    }

    func completeOnboarding() {
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
        defaults.set(false, forKey: "nanobeasts.didCompleteAppTour")
        onboardingCompleted = false
        persist()
    }

    func chooseNextEgg(_ egg: CreatureStage) {
        guard
            egg.isEgg,
            let nextFamilyIndex = catalog.families.firstIndex(where: { $0.id == egg.familyID }),
            let nextStageIndex = catalog.families[nextFamilyIndex].stages.firstIndex(where: { $0.id == egg.id })
        else {
            return
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
        persistDiscoveryEvents()
        persist()
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

        let previouslyCredited =
            progressionStepsCreditedToday + testingProgressionCreditSteps
        let creditedAmount = isPremium
            ? amount
            : min(
                amount,
                max(Self.freeDailyProgressionCap - previouslyCredited, 0)
            )

        guard creditedAmount > 0 else { return }
        testingProgressionCreditSteps += creditedAmount
        applyTestingProgress(creditedAmount)
    }

    func acknowledgeLifecycleEvent(_ eventID: UUID) {
        pendingLifecycleEvents.removeAll { $0.id == eventID }
        evolutionEventID = UUID()
        persist()
    }

    func markBadgeAwardPresented(_ badgeID: String) {
        if hasTestingActivityPreview {
            testingPresentedBadgeIDs.insert(badgeID)
            return
        }
        awardedBadgeIDs.insert(badgeID)
        persist()
    }

    func refreshSubscriptionStatus() async {
        guard Purchases.isConfigured else {
            isPremium = false
            persist()
            return
        }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            applyRevenueCatCustomerInfo(customerInfo)
        } catch {
            // Keep the last verified state while temporarily offline. RevenueCat
            // maintains its own CustomerInfo cache for subsequent launches.
        }
    }

    func applyRevenueCatCustomerInfo(_ customerInfo: CustomerInfo) {
        let hasPremiumEntitlement =
            customerInfo.entitlements["premium"]?.isActive == true
            || !customerInfo.activeSubscriptions.isDisjoint(with: Self.premiumProductIDs)

        let wasPremium = isPremium
        let previousProgress = hatchProgress
        isPremium = hasPremiumEntitlement
        creditProgressionForToday()
        if !wasPremium, isPremium, abs(hatchProgress - previousProgress) > 0.000_1 {
            stepSyncFromTodaySteps = todaySteps
            stepSyncFromHatchProgress = previousProgress
            stepSyncDuration = 1.1
            stepSyncAnimationID = UUID()
        }
        persist()
    }

    @discardableResult
    func recordLifecycleCompletionForReview(_ kind: CreatureDiscoveryKind) -> Bool {
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
        guard delta > 0, !awaitingEggSelection else { return }
        progressionSteps += delta

        var transitions = 0
        while progressionSteps >= currentTarget && transitions < 100 {
            progressionSteps -= currentTarget
            let previousStage = currentStage
            discoveredStageIDs.insert(currentStage.id)

            if stageIndex + 1 >= currentFamily.stages.count {
                awaitingEggSelection = true
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
        let eligibleTotal = isPremium
            ? todaySteps
            : min(todaySteps, Self.freeDailyProgressionCap)
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
            onboardingWantsHealth: onboardingWantsHealth,
            onboardingWantsReminders: onboardingWantsReminders,
            awaitingEggSelection: awaitingEggSelection,
            journeyStartedAt: journeyStartedAt,
            lastCountedJourneySteps: lastCountedJourneySteps,
            dailyHistory: dailyHistory,
            analyticsHistory: analyticsHistory,
            hourlyAnalyticsHistory: hourlyAnalyticsHistory,
            dailyGoalHistory: dailyGoalHistory,
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
    }

    private func publishWidgetSnapshot() {
        if onboardingCompleted {
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
