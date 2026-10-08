import Foundation

/// Outcome-led copy, grounded in the user's goal and the app's walking loop.
struct OnboardingCopy {
    let paywallHeadline: String
    var paywallDetail: String
    let planHeadline: String
    var planDetail: String
    var paywallBenefits: [Benefit]
    var motivation: WalkingMotivation? = nil
    var secondaryMotivations: [WalkingMotivation] = []

    static let transition = "That’s everything. Let’s put your walking plan together."
    static let seePlan = "Build my plan"
    static let meetStarter = "Commit to your goal"
    static let eggDetail = "Press and hold the egg to make your promise."
    static let eggInstruction = "Hold the egg for 2 seconds"
    static let eggConfirmed = "Your goal. Your commitment."
    static let targetNote = "Adjust anytime in Settings."

    struct Benefit: Identifiable {
        let symbol: String
        let title: String
        var detail: String = ""
        var id: String { symbol }
    }

    /// Keep the chosen outcome first; explain the obstacle through a real mechanism.
    func planOpening(blockers: Set<String>) -> (headline: String, detail: String) {
        if blockers.contains("Walking feels boring") {
            let detail = motivation == .weight || motivation == .fitness
                ? "Here’s how we’ll help you add calorie-burning walks and turn them into a creature-collection adventure."
                : "Here’s how we’ll turn everyday walking into a creature-collection adventure you want to keep playing."
            return (planHeadline, detail)
        }
        return (planHeadline, planDetail)
    }

    func commitmentPromise(name: String) -> String {
        let firstName = name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let opening = firstName.isEmpty || firstName.caseInsensitiveCompare("Researcher") == .orderedSame
            ? "I promise" : "I, \(firstName), promise"
        let goal: String = switch motivation {
        case .weight: "lose weight"
        case .fitness: "lose fat and keep muscle"
        case .habit: "build a daily walking habit"
        case .collection: "grow my Nanobeasts collection"
        case nil: "work toward my goals"
        }
        return "\(opening) to walk more to \(goal)."
    }

    /// Connect the user's chosen outcome to Nano's Field Dex research.
    var researchInvitation: String {
        let purpose: String = switch motivation {
        case .weight:
            "You want to walk more to lose weight."
        case .fitness:
            "You want to walk more to lose fat and keep muscle."
        case .habit:
            "You want to make walking a daily habit."
        case .collection:
            "You want to walk more and collect Nanobeasts."
        case nil:
            "You want to walk more toward your goals."
        }
        return "\(purpose) As your Nanobeasts evolve, you’ll unlock Field Dex entries that help my research."
    }

    var comparisonTitle: String {
        switch motivation {
        case .weight: "Here’s you in 30 days"
        case .fitness: "Your next 30 days"
        case .habit: "Watch walking become routine"
        case .collection: "Your first month of discoveries"
        case nil: "Here’s you in 30 days"
        }
    }

    var comparisonDetail: String { "Within weeks, you’ll see and feel the difference." }

    /// Body-focused goals lead the long-term projection with the energy estimate.
    var emphasizesBody: Bool { motivation == .weight || motivation == .fitness }

    var paywallAccent: String {
        switch motivation {
        case .weight: "your weight goal"
        case .fitness: "your momentum"
        case .habit: "your everyday"
        case .collection: "new discoveries"
        case nil: "come to life"
        }
    }

    func personalizedPaywallHeadline(name: String) -> String {
        let firstName = name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard !firstName.isEmpty, firstName.caseInsensitiveCompare("Researcher") != .orderedSame else {
            return paywallHeadline
        }
        return "\(firstName), \(paywallHeadline.prefix(1).lowercased())\(paywallHeadline.dropFirst())"
    }

    static func forGoals(_ goals: Set<String>, primaryGoal: String? = nil,
                         blockers: Set<String> = []) -> Self {
        let selection = WalkingGoalSelection(values: goals, preferred: primaryGoal)
        // Only the user's explicit main goal can lead a multi-goal selection.
        var copy: Self = switch selection.primary {
        case .weight:
            Self(paywallHeadline: "Evolve your habits. Walk toward your weight goal.",
                paywallDetail: "Make each walk a step toward your weight goal. Keep hatching and evolving creatures as you go.",
                planHeadline: "Small walks. A step toward the body you want.",
                planDetail: "Build a walking routine that supports your weight goal, with visible progress and a reason to keep going.",
                paywallBenefits: [
                    .init(symbol: "figure.walk", title: "Burn more calories with daily walks", detail: "A personal step target helps you add movement to each day."),
                    .init(symbol: "chart.xyaxis.line", title: "Track progress beyond the scale", detail: "See your steps and estimated calories burned on recorded walks."),
                    .init(symbol: "pawprint.fill", title: "Make it easier to keep going", detail: "Grow creatures with every walk you take toward your weight-loss goal.")])
        case .fitness:
            Self(paywallHeadline: "Evolve your routine. Find your momentum.",
                paywallDetail: "Keep walking alongside your strength training, and turn those steps into new hatches and evolutions.",
                planHeadline: "Make walking part of a stronger routine.",
                planDetail: "Keep your strength routine and add walks toward your body-composition goal. Your daily target gives you a place to start.",
                paywallBenefits: [
                    .init(symbol: "figure.walk", title: "Add calorie-burning walks between workouts", detail: "Your adjustable step target fits alongside your existing strength training."),
                    .init(symbol: "chart.xyaxis.line", title: "See what your walks burn", detail: "Record time, distance, and estimated active calories with each workout."),
                    .init(symbol: "pawprint.fill", title: "Build your routine toward a leaner body", detail: "Your steps grow creatures as you work toward the body you want.")])
        case .habit:
            Self(paywallHeadline: "Evolve your habits. Change your everyday.",
                paywallDetail: "Keep your walking habit growing, with new creatures and evolutions to look forward to.",
                planHeadline: "Make tomorrow’s walk something to look forward to.",
                planDetail: "Start with a target that fits your routine. See your consistency grow, one day and one creature at a time.",
                paywallBenefits: [
                    .init(symbol: "figure.walk", title: "Build from your current routine", detail: "Your personal daily step target starts from your current activity."),
                    .init(symbol: "chart.xyaxis.line", title: "See the days you show up", detail: "A weekly calendar and streaks make your consistency visible."),
                    .init(symbol: "pawprint.fill", title: "Look forward to tomorrow’s walk", detail: "Your steps hatch and evolve creatures as your walking habit grows.")])
        case .collection:
            Self(paywallHeadline: "Real steps. A world of new discoveries.",
                paywallDetail: "Keep hatching, evolving, and discovering new creatures as your daily steps add up.",
                planHeadline: "Your next discovery starts with a walk.",
                planDetail: "We’ll turn your daily steps into hatching, evolution, and new entries in your Field Dex.",
                paywallBenefits: [
                    .init(symbol: "figure.walk", title: "Walk your way to new creatures", detail: "Reach step milestones to hatch eggs and evolve your Nanobeasts."),
                    .init(symbol: "chart.xyaxis.line", title: "See your collection fill up", detail: "Your Field Dex records each species you unlock through walking."),
                    .init(symbol: "pawprint.fill", title: "Take your creature on an adventure", detail: "Paint your streets together, then share your route replay and stats.")])
        case nil:
            Self(paywallHeadline: "Evolve your habits. Watch progress come to life.",
                paywallDetail: "Keep the adventure going. Turn your daily steps into new hatches and evolutions.",
                planHeadline: "Small steps. Something to look forward to.",
                planDetail: "We’ll set a daily target, track your walks, and turn your steps into a creature-collection adventure.",
                paywallBenefits: [
                    .init(symbol: "figure.walk", title: "Start with a target built for you", detail: "Your daily step goal starts from your current walking routine."),
                    .init(symbol: "chart.xyaxis.line", title: "See the walking you’re getting done", detail: "Track daily steps, workout distance, and estimated calories burned."),
                    .init(symbol: "pawprint.fill", title: "Give tomorrow’s walk a purpose", detail: "Hatch and evolve creatures as your daily steps add up.")])
        }
        copy.motivation = selection.primary
        copy.secondaryMotivations = selection.secondary
        copy.includeSecondaryGoals()
        copy.includeBlockers(blockers)
        return copy
    }

    private mutating func includeSecondaryGoals() {
        if motivation == .weight, secondaryMotivations.contains(.fitness) {
            planDetail = "Keep your strength training. We’ll help you add calorie-burning walks and make them easier to repeat."
            paywallBenefits[0].detail = "An adjustable walking target adds movement alongside your strength training."
        }
        if motivation == .collection, secondaryMotivations.contains(.habit) {
            paywallBenefits[2] = .init(symbol: "pawprint.fill", title: "Make adventure a daily habit", detail: "Grow creatures with your steps and build streaks for daily goals.")
        }
    }

    private mutating func includeBlockers(_ blockers: Set<String>) {
        // Three stable roles: goal mechanism, evidence, and the obstacle to repeating it.
        // Several obstacles shape these rows together instead of adding more rows.
        let missesProgress = blockers.contains("No way to track progress")
        let impatient = blockers.contains("Don’t see results fast enough")
        let forgets = blockers.contains("Forget to move")
        if missesProgress || impatient {
            let title = motivation == .weight ? "Track progress beyond the scale"
                : impatient ? "See the effort you put in today" : "Know whether you’re walking more"
            paywallBenefits[1] = .init(symbol: "chart.xyaxis.line", title: title,
                detail: "Daily steps and weekly trends make your effort visible from day one.")
        } else if forgets {
            paywallBenefits[1] = .init(symbol: "chart.xyaxis.line", title: "Keep your steps on your Home Screen",
                detail: "Add a Nanobeasts widget to check your steps without opening the app.")
        }
        if blockers.contains("Walking feels boring") {
            let gameIndex = motivation == .collection ? 0 : 2
            paywallBenefits[gameIndex] = .init(symbol: paywallBenefits[gameIndex].symbol,
                title: "Turn boring walks into an adventure",
                detail: motivation == .weight || motivation == .fitness
                    ? "Grow Nanobeasts while you walk toward the body you want."
                    : "Hatch and evolve Nanobeasts with your steps, so walking feels like playing.")
        } else if blockers.contains("Hard to stay consistent") {
            paywallBenefits[2] = .init(symbol: "pawprint.fill", title: "Keep going when motivation fades",
                detail: motivation == .fitness
                    ? "Grow creatures as you build a walking routine for a leaner body."
                    : motivation == .weight
                    ? "Grow creatures as you build the walking habit behind your weight-loss goal."
                    : "Daily-goal streaks and creature milestones give repeat walks something to earn.")
        }
    }
}
