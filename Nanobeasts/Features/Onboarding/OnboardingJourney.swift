import Foundation

/// Raw values preserve choices saved by earlier versions of onboarding.
enum WalkingMotivation: String, CaseIterable, Identifiable {
    case habit = "Walk More"
    case weight = "Lose Weight"
    case fitness = "Get Fit"
    case collection = "Collect Creatures"

    /// "Have Fun" was folded into collecting; answers saved under it map here.
    private static let retired = ["Have Fun": Self.collection]

    static func canonical(_ value: String) -> String { retired[value]?.rawValue ?? value }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .habit: "Build a daily walking habit"
        case .weight: "Lose weight"
        case .fitness: "Lose body fat, keep muscle"
        case .collection: "Collect Nanobeasts"
        }
    }

    var detail: String {
        switch self {
        case .habit: "Make movement part of my everyday routine"
        case .weight: "Support my weight-loss goal with more movement"
        case .fitness: "Add walking alongside my strength training"
        case .collection: "Turn every walk into an adventure of new creatures"
        }
    }

    static func selected(in values: Set<String>) -> [Self] {
        let current = Set(values.map(canonical))
        return allCases.filter { current.contains($0.rawValue) }
    }
}

struct WalkingGoalSelection {
    let values: Set<String>
    let preferred: String?
    var choices: [WalkingMotivation] { WalkingMotivation.selected(in: values) }
    var needsChoice: Bool { choices.count > 1 }
    var primary: WalkingMotivation? {
        if let preferred, let goal = WalkingMotivation(rawValue: WalkingMotivation.canonical(preferred)),
           choices.contains(goal) { return goal }
        return choices.count == 1 ? choices.first : nil
    }
    var secondary: [WalkingMotivation] { choices.filter { $0 != primary } }
}

/// Daily goal rules that keep goal-based streaks and badges meaningful.
enum DailyGoalPolicy {
    /// The lowest goal anyone can set by hand. Lower starting goals from
    /// onboarding are allowed but ramp up to this automatically.
    static let manualMinimum = 5_000
    static let maximum = 20_000
    static let rampStep = 500
    static let rampIntervalDays = 7

    /// Weeks until a below-minimum goal reaches the minimum by ramping.
    static func rampWeeks(from goal: Int) -> Int {
        guard goal < manualMinimum else { return 0 }
        return Int(ceil(Double(manualMinimum - goal) / Double(rampStep)))
    }

    struct State: Equatable {
        var goal: Int
        var scheduledGoal: Int?
        var scheduledOn: Date?
        var rampAnchor: Date?
    }

    /// Advances goal state to `now`: a goal scheduled on an earlier day takes
    /// effect, then a below-minimum goal rises one step per completed week.
    static func advance(_ state: State, to now: Date, calendar: Calendar = .autoupdatingCurrent) -> State {
        var next = state
        let today = calendar.startOfDay(for: now)
        if let scheduled = next.scheduledGoal, let setOn = next.scheduledOn,
           calendar.startOfDay(for: setOn) < today {
            next.goal = scheduled
            next.scheduledGoal = nil
            next.scheduledOn = nil
            next.rampAnchor = scheduled < manualMinimum ? today : nil
        }
        guard next.goal < manualMinimum else {
            next.rampAnchor = nil
            return next
        }
        guard let anchor = next.rampAnchor else {
            next.rampAnchor = today
            return next
        }
        let start = calendar.startOfDay(for: anchor)
        let weeks = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) / rampIntervalDays
        if weeks > 0 {
            next.goal = min(manualMinimum, next.goal + weeks * rampStep)
            next.rampAnchor = next.goal < manualMinimum
                ? calendar.date(byAdding: .day, value: weeks * rampIntervalDays, to: start)
                : nil
        }
        return next
    }
}

struct WalkingPlanComparison {
    static let days = 30
    let baselineSteps: Int
    let targetSteps: Int
    var baselineTotal: Int { baselineSteps * Self.days }
    var targetTotal: Int { targetSteps * Self.days }
    var additionalTotal: Int { max(0, targetTotal - baselineTotal) }
    var dailyIncrease: Int { max(0, targetSteps - baselineSteps) }
    var isExperiencedWalker: Bool { baselineSteps >= 6_500 }

    // Compare additional walking, rather than erasing the user's existing steps.
    // Maintaining the current routine contributes zero *extra* steps.
    var withoutAdditionalSteps: Int { 0 }
    func additionalSteps(atDay day: Double) -> Int {
        Int((Double(dailyIncrease) * min(Double(Self.days), max(0, day))).rounded())
    }
}

/// One answer supplies the starting step range and its walking-activity profile.
enum WalkingRoutine: String, CaseIterable, Identifiable {
    case starting = "Under 2,000"
    case occasional = "2,000 – 5,000"
    case regular = "5,000 – 8,000"
    case daily = "8,000 – 10,000"
    case longWalks = "10,000 – 15,000"
    case alwaysMoving = "15,000+"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .starting: "I’m mostly sitting"
        case .occasional: "I take occasional walks"
        case .regular: "I walk regularly"
        case .daily: "Walking is a daily habit"
        case .longWalks: "I take long walks most days"
        case .alwaysMoving: "I’m on my feet all day"
        }
    }
    var detail: String { "\(rawValue) steps a day" }
    var activity: String {
        switch self {
        case .starting: "Sedentary"
        case .occasional: "Lightly Active"
        case .regular: "Moderately Active"
        case .daily: "Very Active"
        case .longWalks, .alwaysMoving: "Everyday Walker"
        }
    }
}

/// A challenge, not a promise of a particular creature unlocking on a date.
/// The budget includes eggs and maturity, not just the evolution transition.
struct WalkingEvolutionChallenge {
    let dailyTarget: Int
    let averageStepsPerEvolution: Int
    var daysPerEvolution: Int { max(2, Int(ceil(Double(max(1, averageStepsPerEvolution)) / Double(max(1, dailyTarget))))) }
    var evolutionsIn30Days: Int { WalkingPlanComparison.days / daysPerEvolution }
    var cadence: String {
        daysPerEvolution == 2 ? "Aim for an evolution every other day" : "Aim for an evolution every \(daysPerEvolution) days"
    }
}

/// The user's first month at their daily target: Field Dex discoveries, miles,
/// and the energy their extra walking adds up to. Pure arithmetic, verifiable offline.
struct WalkingJourneyProjection {
    /// A month is easy to picture, and results show up inside it.
    static let horizonDays = 30
    /// A factual milestone (three straight weeks at target), not a habit-science claim.
    static let streakMilestoneDay = 21
    static let stepsPerMile = 2_000.0
    /// Net calories per walking step for lighter to heavier adults, so the
    /// estimate needs no body weight. 3,500 kcal approximates 1 lb of body fat.
    static let kcalPerStepLow = 0.03
    static let kcalPerStepHigh = 0.05
    static let kcalPerPoundOfFat = 3_500.0

    let comparison: WalkingPlanComparison
    /// Cumulative steps needed to discover each creature, in Dex order.
    let discoverySteps: [Int]

    var isAvailable: Bool { !discoverySteps.isEmpty && comparison.targetSteps > 0 }

    /// The goal in effect on a given day (1-based). Goals under the manual minimum
    /// rise one step after each completed week, exactly as `DailyGoalPolicy` ramps them.
    func dailyGoal(onDay day: Int) -> Int {
        let target = comparison.targetSteps
        guard target < DailyGoalPolicy.manualMinimum else { return target }
        let weeks = max(day - 1, 0) / DailyGoalPolicy.rampIntervalDays
        return min(DailyGoalPolicy.manualMinimum, target + weeks * DailyGoalPolicy.rampStep)
    }

    /// Total steps by the end of a day when every day's goal is met.
    func stepsWalked(byDay day: Int) -> Int {
        guard day > 0 else { return 0 }
        return (1...day).reduce(0) { $0 + dailyGoal(onDay: $1) }
    }

    func creaturesDiscovered(byDay day: Int) -> Int {
        let walked = stepsWalked(byDay: day)
        return discoverySteps.prefix { $0 <= walked }.count
    }

    var creaturesInHorizon: Int { creaturesDiscovered(byDay: Self.horizonDays) }

    func day(forCreature creature: Int) -> Int {
        guard creature > 0, creature <= discoverySteps.count, comparison.targetSteps > 0 else { return 0 }
        let cost = discoverySteps[creature - 1]
        var day = 1
        while stepsWalked(byDay: day) < cost { day += 1 }
        return day
    }

    /// One row of the month timeline: what the game shows and what the body did.
    struct Checkpoint: Identifiable, Equatable {
        let day: Int
        let creatures: Int
        let miles: Int
        /// Calories burned walking at the daily target, rounded for display.
        let calories: Int
        var id: Int { day }
    }

    static let checkpointDays = [1, 7, 14, 21]

    var checkpoints: [Checkpoint] {
        guard isAvailable else { return [] }
        return Self.checkpointDays.map { day in
            Checkpoint(day: day, creatures: creaturesDiscovered(byDay: day),
                       miles: milesWalked(byDay: day),
                       calories: Int((walkingCalories(byDay: day) / 50).rounded()) * 50)
        }
    }

    func milesWalked(byDay day: Int) -> Int {
        Int((Double(stepsWalked(byDay: day)) / Self.stepsPerMile).rounded())
    }

    /// Calories burned by all the walking at the daily target (midpoint estimate).
    func walkingCalories(byDay day: Int) -> Double {
        Double(stepsWalked(byDay: day)) * (Self.kcalPerStepLow + Self.kcalPerStepHigh) / 2
    }

    /// The energy those calories represent in body fat. An equivalence, not a weight-loss promise.
    func fatEnergyPounds(byDay day: Int) -> Double {
        walkingCalories(byDay: day) / Self.kcalPerPoundOfFat
    }

    static let marathonMiles = 26.2

    func marathons(byDay day: Int) -> Int {
        Int((Double(milesWalked(byDay: day)) / Self.marathonMiles).rounded(.down))
    }

    func date(forDay day: Int, from start: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: start)) ?? start
    }
}

/// A finite walkthrough of the calculations, using the same answers as the result.
struct WalkingPlanPreparation {
    static let duration: TimeInterval = 4.2
    let elapsed: TimeInterval
    var progress: Double { min(1, max(0, elapsed / 3.8)) }
    var stage: Int { min(3, Int(progress * 3)) }
    func target(for comparison: WalkingPlanComparison) -> Int {
        let fraction = min(1, max(0, (progress - 0.25) / 0.42))
        return comparison.baselineSteps + Int((Double(comparison.dailyIncrease) * fraction).rounded())
    }

    @MainActor
    static func play(from elapsed: TimeInterval, reduceMotion: Bool,
                     update: (TimeInterval) -> Void) async -> Bool {
        guard !Task.isCancelled else { return false }
        if reduceMotion {
            update(duration)
            do { try await Task.sleep(for: .milliseconds(800)) }
            catch { return false }
            return !Task.isCancelled
        }
        let clock = ContinuousClock()
        let start = clock.now
        while !Task.isCancelled {
            let time = start.duration(to: clock.now).components
            let value = min(duration, elapsed + Double(time.seconds) + Double(time.attoseconds) / 1e18)
            update(value)
            if value >= duration { return true }
            do { try await Task.sleep(for: .milliseconds(33)) }
            catch { return false }
        }
        return false
    }
}

/// One finite reveal drives the numbers and the chart from the same comparison.
/// This presents arithmetic from the answers; it doesn't simulate a health scan.
struct WalkingPlanReveal {
    static let duration: TimeInterval = 3.6
    let elapsed: TimeInterval

    private func fraction(start: Double, duration: Double) -> Double {
        min(1, max(0, (elapsed - start) / duration))
    }

    var targetProgress: Double {
        let t = fraction(start: 0, duration: 1.4)
        return 1 - pow(1 - t, 3)
    }
    var chartProgress: Double { fraction(start: 0.8, duration: 2.8) }
    var day: Int { Int((chartProgress * Double(WalkingPlanComparison.days)).rounded()) }

    func dailyTarget(for comparison: WalkingPlanComparison) -> Int {
        comparison.baselineSteps + Int((Double(comparison.targetSteps - comparison.baselineSteps) * targetProgress).rounded())
    }

    func total(dailySteps: Int) -> Int {
        Int((Double(dailySteps * WalkingPlanComparison.days) * chartProgress).rounded())
    }

    /// Own the clock instead of depending on preferences crossing a TimelineView.
    /// Cancellation also settles on valid totals, never an unfinished zero chart.
    @MainActor
    static func play(reduceMotion: Bool, update: (TimeInterval) -> Void) async {
        guard !reduceMotion, !Task.isCancelled else { update(duration); return }
        let clock = ContinuousClock()
        let start = clock.now
        update(0)
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(33)) }
            catch { break }
            let time = start.duration(to: clock.now).components
            let elapsed = min(duration, Double(time.seconds) + Double(time.attoseconds) / 1e18)
            update(elapsed)
            if elapsed >= duration { return }
        }
        update(duration)
    }
}

enum WalkingPlanPage: String, Codable, CaseIterable {
    case target, comparison
    var position: Int { Self.allCases.firstIndex(of: self)! }
    var next: Self? { self == .target ? .comparison : nil }
    var previous: Self? { self == .comparison ? .target : nil }
}

enum OnboardingPhase: String, Codable {
    // Retain old raw values so an in-progress install can migrate without losing answers.
    case demo, chat, profile, projection, building, preparing, plan, connections, commitment

    var current: Self {
        switch self {
        case .profile, .projection, .building: .plan
        default: self
        }
    }
}

enum ChatStep: Int, CaseIterable, Codable {
    // These integers are already stored on devices. Presentation order is separate.
    case welcome, goal, blocker, name, reminders, activity, steps, health, plan
    case specimen, evolution, research, location
    case focus

    static let questions: [Self] = [.goal, .blocker, .activity]
    static let journey: [Self] = [.welcome, .goal, .focus, .blocker, .activity, .specimen, .evolution, .research, .name, .plan, .health]
    var isStory: Bool { [.welcome, .specimen, .evolution, .research].contains(self) }
    var current: Self {
        switch self {
        case .steps: .activity
        case .location, .reminders: .health
        default: self
        }
    }
    var position: Int { Self.journey.firstIndex(of: current)! }
    var next: Self? { Self.journey.dropFirst(position + 1).first }
    var previous: Self? { position > 0 ? Self.journey[position - 1] : nil }

    func next(needsFocus: Bool) -> Self? { self == .goal && !needsFocus ? .blocker : next }
    func previous(needsFocus: Bool) -> Self? { self == .blocker && !needsFocus ? .goal : previous }

    var chapter: String {
        switch self {
        case .welcome: "MEET NANOBEASTS"
        case .specimen, .evolution, .research: "PROFESSOR NANO’S RESEARCH"
        case .goal, .focus, .blocker, .activity, .steps: "YOUR WALKING LIFE"
        case .name, .plan: "MADE FOR YOU"
        case .health, .location, .reminders: "READY FOR YOUR FIRST WALK"
        }
    }

    var title: String {
        switch self {
        case .welcome: "WELCOME"
        case .name: "NAME"
        case .goal: "GOAL"
        case .focus: "YOUR MAIN GOAL"
        case .blocker: "BLOCKER"
        case .activity: "ACTIVITY"
        case .steps: "STEPS"
        case .health: "HEALTH"
        case .reminders: "REMINDERS"
        case .plan: "PLAN"
        case .specimen: "NANOBEASTS"
        case .evolution: "EVOLUTION"
        case .research: "FIELD RESEARCH"
        case .location: "OUTDOOR WORKOUTS"
        }
    }

    var progress: Double { Double(position + 1) / Double(Self.journey.count) }

    func progress(needsFocus: Bool) -> Double {
        let visible = Self.journey.filter { needsFocus || $0 != .focus }
        guard let index = visible.firstIndex(of: current) else { return progress }
        return Double(index + 1) / Double(visible.count)
    }
}

/// A local draft survives termination without marking the journey as purchased or started.
struct OnboardingDraft: Codable, Equatable {
    static let storageKey = "nanobeasts.onboarding.draft.v1"
    var phase: OnboardingPhase = .demo
    var chatStep: ChatStep = .welcome
    var playerName = ""
    var selectedGoals: Set<String> = []
    var primaryGoal: String?
    var planPage: WalkingPlanPage?
    var selectedBlockers: Set<String> = []
    var activity: String?
    var currentSteps: String?
    var wantsHealth = true
    var wantsReminders = false
    var reachedPaywall = false
    var completedConnections: Bool?
    var wantsGPSRoutes: Bool?

    var goalSelection: WalkingGoalSelection { .init(values: selectedGoals, preferred: primaryGoal) }
    var displayName: String {
        let clean = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Researcher" : clean
    }

    static func load(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: storageKey),
              var draft = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        // Old analysis/building screens resume at the single result, before checkout.
        draft.phase = draft.reachedPaywall ? .plan : draft.phase.current
        if draft.currentSteps == "8,000+" { draft.currentSteps = "8,000 – 10,000" }
        draft.selectedGoals = Set(draft.selectedGoals.map(WalkingMotivation.canonical))
        draft.primaryGoal = draft.primaryGoal.map(WalkingMotivation.canonical)
        // Health now belongs to the first Home visit. Retain existing choices,
        // but never resume an old permissions question inside setup.
        if draft.phase == .connections {
            draft.completedConnections = true
            draft.phase = .commitment
        }
        draft.chatStep = draft.chatStep.current
        if draft.activity == nil, let steps = draft.currentSteps {
            draft.activity = WalkingRoutine(rawValue: steps)?.activity
        }
        if draft.reachedPaywall { draft.planPage = .target }
        if draft.phase == .chat {
            // Older versions asked name/notifications before activity. Resume the
            // first unanswered walking question instead of skipping those answers.
            if [.name, .reminders, .health, .plan].contains(draft.chatStep) {
                if let missing = draft.firstUnansweredQuestion {
                    draft.chatStep = missing
                } else if draft.chatStep != .name {
                    draft.phase = .plan
                }
            }
        }
        return draft
    }

    var firstUnansweredQuestion: ChatStep? {
        if selectedGoals.isEmpty { return .goal }
        if goalSelection.needsChoice && goalSelection.primary == nil { return .focus }
        if selectedBlockers.isEmpty { return .blocker }
        if activity == nil || currentSteps == nil { return .activity }
        return nil
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func clear(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: storageKey) }

    var baselineSteps: Int {
        switch currentSteps {
        case "Under 2,000": 1_500
        case "2,000 – 5,000": 3_500
        case "5,000 – 8,000": 6_500
        case "8,000+": 9_000
        case "8,000 – 10,000": 9_000
        case "10,000 – 15,000": 12_500
        case "15,000+": 17_500
        default: 1_500
        }
    }

    var recommendedGoal: Int {
        // Experienced walkers get an explicit stretch target, not a chart-only
        // increase. Their range midpoint remains the honest comparison baseline.
        if baselineSteps >= 6_500 {
            let increase = activity == "Everyday Walker" || baselineSteps >= 12_500 ? 2_500
                : activity == "Very Active" || baselineSteps >= 9_000 ? 2_000 : 1_500
            return min(baselineSteps + increase, 20_000)
        }
        var base: Int
        switch activity {
        case "Sedentary": base = 3_500
        case "Moderately Active": base = 5_500
        case "Very Active", "Everyday Walker": base = 7_500
        default: base = 4_500
        }
        if selectedGoals.contains("Lose Weight") || selectedGoals.contains("Get Fit") { base += 750 }
        else if selectedGoals.contains("Walk More") { base += 500 }
        switch currentSteps {
        case "Under 2,000": base = min(base, 4_000)
        case "2,000 – 5,000": base = min(max(base, 4_000), 5_500)
        case "5,000 – 8,000": base = min(max(base, 7_000), 8_000)
        case "8,000+": base = 10_000
        default: break
        }
        return min(max(Int((Double(base) / 500).rounded()) * 500, baselineSteps + 500), 20_000)
    }
}

enum OnboardingReminderPolicy {
    static let interval: TimeInterval = 2 * 24 * 60 * 60
    static let count = 5

    static func shouldSchedule(consented: Bool, enabled: Bool, authorized: Bool,
                               completed: Bool, premium: Bool) -> Bool {
        consented && enabled && authorized && !completed && !premium
    }

    static func messages(name: String, planReady: Bool) -> [(title: String, body: String)] {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        let greeting = clean.isEmpty || clean == "Researcher" ? "" : "\(clean), "
        return [
            ("\(greeting)your adventure is waiting", planReady
                ? "Your evolution plan is saved. Come back and take the next step."
                : "Pick up where you left off and find your starting step target."),
            ("\(greeting)give your next walk a little purpose", "Hatch an egg, grow a Nanobeast, and see what your everyday steps can become."),
            ("\(greeting)meet your next walking companion", "Your first egg is waiting in Nanobeasts. Finish setting up to begin your collection."),
            ("\(greeting)take the scenic route", "Track your walks and reveal the map as you go. Your saved setup is ready when you are."),
            ("\(greeting)your field journey is still here", "Return to your saved setup whenever you’re ready. This is your last setup reminder.")
        ]
    }
}
