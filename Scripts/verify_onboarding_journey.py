#!/usr/bin/env python3
"""Exercise production draft persistence, target choices, and reminder eligibility."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
checks = r'''
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
let suite = "nanobeasts.onboarding.checks.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
var draft = OnboardingDraft()
check(draft.phase == .demo, "New installs start at the demo")
check(ChatStep.journey == [.welcome, .goal, .focus, .blocker, .activity, .specimen, .evolution, .research, .name, .plan, .health], "One welcome and Health-only connections keep the journey short")
check(ChatStep.questions.count == 3 && ChatStep.activity.next == .specimen, "No duplicate routine question or progress-count slot")
check(ChatStep.steps.rawValue == 6 && ChatStep.steps.position == ChatStep.activity.position, "Legacy steps position remains decodable and maps safely to the combined question")
for routine in WalkingRoutine.allCases {
    var combined = OnboardingDraft()
    combined.currentSteps = routine.rawValue; combined.activity = routine.activity
    check(combined.baselineSteps > 0 && combined.recommendedGoal > combined.baselineSteps, "Every combined choice sets a real starting estimate and positive challenge")
    check(combined.recommendedGoal <= 20000, "Combined choices respect the goal limit")
    let comparison = WalkingPlanComparison(baselineSteps: combined.baselineSteps, targetSteps: combined.recommendedGoal)
    check(comparison.additionalSteps(atDay: 0) == 0 && comparison.additionalSteps(atDay: 30) == comparison.additionalTotal, "The added-walking comparison starts at zero and ends at the real difference")
    check(comparison.withoutAdditionalSteps == 0 && comparison.baselineTotal > 0, "A flat red line means no additional walking, not no existing activity")
    check(comparison.additionalSteps(atDay: -5) == 0 && comparison.additionalSteps(atDay: 40) == comparison.additionalTotal, "Comparison clamps to the displayed thirty-day window")
    combined.phase = .chat; combined.chatStep = .steps
    combined.save(defaults: defaults)
    let migrated = OnboardingDraft.load(defaults: defaults)
    check(migrated.chatStep == .activity && migrated.currentSteps == routine.rawValue && migrated.activity == routine.activity, "An old steps screen resumes the combined question with its answers intact")
    check(migrated.recommendedGoal == combined.recommendedGoal, "Migration does not alter an already-chosen target")
    combined.activity = nil; combined.save(defaults: defaults)
    check(OnboardingDraft.load(defaults: defaults).activity == routine.activity, "A range-only draft recovers its activity from the same combined choice")
}
check(ChatStep.name.rawValue == 3 && ChatStep.reminders.rawValue == 4 && ChatStep.activity.rawValue == 5, "Serialized step IDs do not change when presentation order changes")
for (index, step) in ChatStep.journey.enumerated() {
    check(step.position == index, "Presentation position is independent of persisted raw value")
    if let next = step.next { check(next.previous == step, "Back reverses the displayed sequence") }
}
check(ChatStep.welcome.previous == nil && ChatStep.health.next == nil, "Flow boundaries terminate at Health")
for needsFocus in [true, false] {
    var prior = 0.0
    for step in ChatStep.journey where needsFocus || step != .focus {
        let progress = step.progress(needsFocus: needsFocus)
        check(progress > prior && progress <= 1, "Visible progress advances for both single and multiple goals")
        prior = progress
    }
    check(prior == 1, "Health finishes the progress indicator")
}
for step in ChatStep.allCases {
    check(ChatStep.journey.contains(step.current), "Every persisted step has a safe current position")
    check(step.position >= 0 && step.progress <= 1, "Legacy positions never crash or overflow")
}
for name in ["", "  \n ", "Sam", "  Élodie  "] {
    var named = OnboardingDraft(); named.playerName = name
    named.save(defaults: defaults)
    let restored = OnboardingDraft.load(defaults: defaults)
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    check(restored.displayName == (trimmed.isEmpty ? "Researcher" : trimmed), "Optional name survives persistence with a neutral fallback")
}
for oldStep in [ChatStep.location, .reminders] {
    for health in [true, false] {
        var old = OnboardingDraft()
        old.phase = .connections; old.chatStep = oldStep
        old.wantsHealth = health; old.wantsReminders = true; old.wantsGPSRoutes = true
        old.playerName = "Sam"; old.selectedGoals = ["Walk More"]
        old.selectedBlockers = ["Walking feels boring"]
        old.activity = WalkingRoutine.regular.activity; old.currentSteps = WalkingRoutine.regular.rawValue
        old.save(defaults: defaults)
        let migrated = OnboardingDraft.load(defaults: defaults)
        check(migrated.phase == .commitment && migrated.completedConnections == true, "Removed connections resume after the already answered Health choice")
        check(migrated.chatStep == .health && migrated.wantsHealth == health, "Health acceptance and refusal survive migration")
        check(migrated.playerName == old.playerName && migrated.selectedGoals == old.selectedGoals && migrated.recommendedGoal == old.recommendedGoal, "Migration keeps answers and target")
        migrated.save(defaults: defaults)
        check(OnboardingDraft.load(defaults: defaults) == migrated, "Migration is idempotent")
        old.phase = .chat; old.save(defaults: defaults)
        check(OnboardingDraft.load(defaults: defaults).phase == .plan, "Old early permissions return to the plan when answers are complete")
        old.currentSteps = nil; old.save(defaults: defaults)
        check(OnboardingDraft.load(defaults: defaults).chatStep == .activity, "Old early permissions recover missing answers")
    }
}
var unfinishedHealth = OnboardingDraft()
unfinishedHealth.phase = .connections; unfinishedHealth.chatStep = .health
unfinishedHealth.save(defaults: defaults)
check(OnboardingDraft.load(defaults: defaults).phase == .commitment, "An unanswered legacy Health choice moves past setup; access is requested on Home")
var welcome = OnboardingDraft(); welcome.phase = .chat
welcome.save(defaults: defaults)
check(OnboardingDraft.load(defaults: defaults).chatStep == .welcome && ChatStep.welcome.next == .goal, "Welcome resumes as one screen and advances directly to goals")
let animatedComparison = WalkingPlanComparison(baselineSteps: 3500, targetSteps: 5000)
var lastTarget = 0
var lastTotal = 0
for tick in -10...150 {
    let motion = WalkingPlanReveal(elapsed: Double(tick) / 30)
    let target = motion.dailyTarget(for: animatedComparison)
    let total = motion.total(dailySteps: animatedComparison.targetSteps)
    check(target >= lastTarget && target >= 3500 && target <= 5000, "Target counts toward the real goal without overshoot")
    check(total >= lastTotal && total <= animatedComparison.targetTotal, "Chart and total move forward together")
    check(motion.day >= 0 && motion.day <= 30, "Reveal never extends the comparison beyond thirty days")
    lastTarget = target; lastTotal = total
}
let complete = WalkingPlanReveal(elapsed: WalkingPlanReveal.duration)
check(complete.dailyTarget(for: animatedComparison) == animatedComparison.targetSteps, "Reveal finishes on the saved daily target")
check(complete.total(dailySteps: 5000) == 150000 && complete.total(dailySteps: 3500) == 105000, "Finished animation and Reduce Motion show the correct totals")
var legacy = OnboardingDraft()
legacy.phase = .chat; legacy.chatStep = .reminders; legacy.playerName = "Sam"
legacy.selectedGoals = ["Walk More"]; legacy.selectedBlockers = ["Walking feels boring"]
legacy.save(defaults: defaults)
let resumed = OnboardingDraft.load(defaults: defaults)
check(resumed.chatStep == .activity && resumed.playerName == "Sam", "Legacy early notifications resume missing walking questions with name preserved")
legacy.activity = "Very Active"; legacy.currentSteps = "8,000+"; legacy.save(defaults: defaults)
check(OnboardingDraft.load(defaults: defaults).phase == .plan, "Completed legacy questionnaire opens the single plan")
// Old JSON has no completedConnections field.
var oldJSON = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
oldJSON.removeValue(forKey: "completedConnections")
oldJSON.removeValue(forKey: "primaryGoal")
oldJSON.removeValue(forKey: "planPage")
defaults.set(try! JSONSerialization.data(withJSONObject: oldJSON), forKey: OnboardingDraft.storageKey)
check(OnboardingDraft.load(defaults: defaults).playerName == "Sam", "Adding connection completion keeps old drafts decodable")
for activity in ["Sedentary", "Lightly Active", "Moderately Active", "Very Active", "Everyday Walker"] {
    for steps in ["Under 2,000", "2,000 – 5,000", "5,000 – 8,000", "8,000+", "8,000 – 10,000", "10,000 – 15,000", "15,000+"] {
        for goal in ["Walk More", "Lose Weight", "Get Fit", "Have Fun", "Collect Creatures"] {
            draft.activity = activity; draft.currentSteps = steps; draft.selectedGoals = [goal]
            check(draft.recommendedGoal > draft.baselineSteps, "Suggested goal must exceed its displayed baseline")
            check(draft.recommendedGoal <= 20_000, "Respect editable goal bounds")
            let comparison = WalkingPlanComparison(baselineSteps: draft.baselineSteps, targetSteps: draft.recommendedGoal)
            check(comparison.baselineTotal == draft.baselineSteps * 30, "Baseline series uses the stated average for thirty days")
            check(comparison.targetTotal == draft.recommendedGoal * 30, "Target series agrees with the actual daily goal")
            check(comparison.additionalTotal > 0, "Regular walkers still see a positive comparison")
            check(comparison.additionalTotal == comparison.targetTotal - comparison.baselineTotal, "Highlight matches the gap between plotted totals")
        }
    }
}
for steps in ["5,000 – 8,000", "8,000+"] {
    draft.activity = "Moderately Active"; draft.currentSteps = steps; draft.selectedGoals = ["Walk More"]
    let comparison = WalkingPlanComparison(baselineSteps: draft.baselineSteps, targetSteps: draft.recommendedGoal)
    check(comparison.isExperiencedWalker, "Average and above-average ranges show the experienced-walker explanation")
    check(comparison.dailyIncrease >= 1500 && comparison.additionalTotal >= 45000, "Experienced walkers see actual additional steps")
}
for motivation in WalkingMotivation.allCases {
    let copy = OnboardingCopy.forGoals([motivation.rawValue])
    check(copy.motivation == motivation, "Paywall benefits use the selected goal")
    check(copy.paywallBenefits.count == 3 && Set(copy.paywallBenefits.map(\.id)).count == 3, "Three distinct, concise benefit rows")
    check(!copy.paywallBenefits.contains { $0.title == "A growing creature collection" }, "Benefits explain the connection to the goal")
    check(copy.planOpening(blockers: ["No way to track progress"]).headline == copy.planHeadline, "The chosen outcome stays ahead of the obstacle")
}
let obstacles = ["No way to track progress", "Don’t see results fast enough", "Hard to stay consistent", "Walking feels boring", "Forget to move"]
for goal in WalkingMotivation.allCases {
    for mask in 0..<(1 << obstacles.count) {
        let answers = Set(obstacles.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
        let copy = OnboardingCopy.forGoals([goal.rawValue], blockers: answers)
        check(copy.motivation == goal, "Obstacles never change the main goal")
        check(copy.paywallBenefits.count == 3 && Set(copy.paywallBenefits.map(\.id)).count == 3,
              "Every obstacle combination retains exactly three distinct benefit roles")
        if answers.contains("Walking feels boring") {
            check(copy.paywallBenefits.contains { $0.title.contains("boring") && $0.detail.contains("Nanobeasts") }, "Boredom connects the game to repeat walking")
            check(copy.planOpening(blockers: answers).detail.contains("adventure"), "The plan acknowledges boredom with the app's mechanism")
        }
        if goal == .weight || goal == .fitness || goal == .habit {
            check(!copy.paywallBenefits[0].detail.contains(where: { $0.isNumber }), "Paywall explains the benefit without repeating the numeric step target")
        }
        for benefit in copy.paywallBenefits {
            check(benefit.title.split(separator: " ").count <= 8, "Personalized benefit titles remain scannable")
            check(benefit.detail.split(separator: " ").count <= 13, "Personalized proof lines remain short")
            check(!benefit.title.contains("—") && !benefit.detail.contains("—"), "Personalized copy has no em dashes")
        }
    }
}
check(!OnboardingCopy.eggDetail.contains("hatching"), "Commitment art does not promise an assigned first egg")
let commitmentGoals: [(WalkingMotivation, String)] = [(.weight, "lose weight"), (.fitness, "lose fat and keep muscle"), (.habit, "build a daily walking habit"), (.collection, "grow my Nanobeasts collection"), (.fun, "make every day an adventure")]
for (goal, outcome) in commitmentGoals {
    let copy = OnboardingCopy.forGoals(Set(WalkingMotivation.allCases.map(\.rawValue)), primaryGoal: goal.rawValue)
    check(copy.commitmentPromise(name: " Sinatra Noel ") == "I, Sinatra, promise to walk more to \(outcome).", "All-goals commitment follows the explicit primary goal and first name")
    check(copy.researchInvitation.contains("Field Dex entries") && copy.researchInvitation.contains("my research"), "Research invitation explains the Professor's role in the Field Dex")
    check(!copy.commitmentPromise(name: "Researcher").contains("Researcher") && copy.commitmentPromise(name: "  ").hasPrefix("I promise"), "Missing names never appear as placeholders in the promise")
    check(copy.commitmentPromise(name: "Anne-Marie Smith").hasPrefix("I, Anne-Marie, promise"), "Hyphenated first names are preserved")
    check(copy.commitmentPromise(name: "美咲").hasPrefix("I, 美咲, promise"), "Unicode names are preserved")
    check(!copy.commitmentPromise(name: "Sinatra").contains("—"), "Commitment has no em dashes")
}
check(ChatStep.health.next == nil && ChatStep.location.current == .health && ChatStep.reminders.current == .health, "Location and notifications are legacy IDs only")

check(ChatStep.focus.rawValue == 13 && ChatStep.location.rawValue == 12, "New focus step preserves every previous stored ID")
check(ChatStep.goal.next(needsFocus: false) == .blocker && ChatStep.blocker.previous(needsFocus: false) == .goal, "A sole reason skips the focus question in both directions")
check(ChatStep.goal.next(needsFocus: true) == .focus && ChatStep.blocker.previous(needsFocus: true) == .focus, "Multiple reasons include the main-goal question in both directions")
let allReasons = WalkingMotivation.allCases
var chosenVariants = 0
for mask in 1..<(1 << allReasons.count) {
    let selected = allReasons.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
    let values = Set(selected.map(\.rawValue))
    let unresolved = WalkingGoalSelection(values: values, preferred: nil)
    check(unresolved.needsChoice == (selected.count > 1), "Only multiple reasons need a focus question")
    check(unresolved.primary == (selected.count == 1 ? selected.first : nil), "Do not silently prioritize a goal the user has not chosen")
    let invalid = WalkingGoalSelection(values: values, preferred: "Unknown Goal")
    check(invalid.primary == unresolved.primary, "Invalid stored preferences never lead copy")
    for preferred in selected {
        let selection = WalkingGoalSelection(values: values, preferred: preferred.rawValue)
        check(selection.primary == preferred, "Every selected reason can lead, including fun when every body goal is also selected")
        check(Set(selection.secondary.map(\.rawValue)) == values.subtracting([preferred.rawValue]), "Keep the remaining reasons without duplicating the primary")
        let copy = OnboardingCopy.forGoals(values, primaryGoal: preferred.rawValue)
        check(copy.motivation == preferred, "Main goal reaches the plan, lore, and paywall copy")
        check(copy.paywallHeadline == OnboardingCopy.forGoals([preferred.rawValue]).paywallHeadline, "Secondary reasons never override the main goal's headline")
        check(copy.secondaryMotivations == selection.secondary, "Secondary preferences survive copy selection")
        check(copy.paywallBenefits.count == 3, "Selecting every reason still gives three benefits")
        for obstacle in ["No way to track progress", "Don’t see results fast enough", "Hard to stay consistent", "Walking feels boring", "Forget to move"] {
            let opening = copy.planOpening(blockers: [obstacle])
            check(opening.headline == copy.planHeadline, "Obstacles don't replace the actual goal")
            if (preferred == .weight || preferred == .fitness) && obstacle != "Walking feels boring" {
                for term in ["hatch", "milestone"] {
                    check(!opening.detail.contains(term), "Body-goal plans explain walking rather than game milestones")
                }
            }
        }
        for text in [copy.paywallHeadline, copy.paywallDetail, copy.planHeadline, copy.planDetail, copy.researchInvitation, copy.comparisonTitle] + copy.paywallBenefits.flatMap({ [$0.title, $0.detail] }) {
            check(!text.contains("—"), "User-facing copy has no em dashes")
        }
        for benefit in copy.paywallBenefits {
            check(benefit.title.split(separator: " ").count <= 11, "Checkout benefits remain scannable")
            check(!benefit.detail.isEmpty && benefit.detail.split(separator: " ").count <= 13, "Each benefit has one brief concrete proof line")
        }
        check(copy.paywallDetail.split(separator: " ").count <= 24, "Checkout supporting copy stays concise")
        for activity in ["Sedentary", "Lightly Active", "Moderately Active", "Very Active", "Everyday Walker"] {
            for steps in ["Under 2,000", "2,000 – 5,000", "5,000 – 8,000", "8,000+", "8,000 – 10,000", "10,000 – 15,000", "15,000+"] {
                var unchosen = OnboardingDraft()
                unchosen.selectedGoals = values; unchosen.activity = activity; unchosen.currentSteps = steps
                var chosen = unchosen; chosen.primaryGoal = preferred.rawValue
                check(chosen.recommendedGoal == unchosen.recommendedGoal, "Focus picks the explanation, not an inflated target for each checked box")
                check(chosen.recommendedGoal > chosen.baselineSteps, "Every selection has positive additional walking, including experienced walkers")
            }
        }
        chosenVariants += 1
    }
}
check(chosenVariants == 80, "Exercised all valid primary-goal choices across all 31 nonempty selections")
let allWeight = OnboardingCopy.forGoals(Set(allReasons.map(\.rawValue)), primaryGoal: WalkingMotivation.weight.rawValue)
check(allWeight.paywallHeadline.contains("weight goal"), "All reasons with weight primary leads with the weight goal")
check(allWeight.paywallDetail.contains("walking plan") && allWeight.paywallDetail.contains("weight goal"), "Daily walking serves the chosen outcome")
check(allWeight.planDetail.contains("strength training"), "The selected secondary training goal shapes the plan mechanism")
check(OnboardingCopy.forGoals([]).motivation == nil, "Missing answers use general copy")
check(OnboardingCopy.forGoals(["Future Goal"]).motivation == nil, "Unknown answers never invent a motivation")
check(OnboardingCopy.forGoals(Set(allReasons.map(\.rawValue))).motivation == nil, "Legacy multiple-choice profiles receive neutral copy instead of a guessed priority")
var unansweredFocus = OnboardingDraft()
unansweredFocus.selectedGoals = ["Get Fit", "Have Fun"]
check(unansweredFocus.firstUnansweredQuestion == .focus, "Resume an unfinished main-goal question before unrelated questions")
unansweredFocus.primaryGoal = "Have Fun"
check(unansweredFocus.firstUnansweredQuestion == .blocker, "Continue after an explicit focus choice")
unansweredFocus.selectedGoals.remove("Have Fun")
check(unansweredFocus.goalSelection.primary == .fitness, "Removing a main goal resolves the remaining sole reason")
let fitnessCopy = OnboardingCopy.forGoals(["Get Fit"])
check(fitnessCopy.personalizedPaywallHeadline(name: "  Sam Jones \n").hasPrefix("Sam, evolve"), "Checkout uses the first name and natural sentence casing")
check(fitnessCopy.personalizedPaywallHeadline(name: "Anne-Marie Smith").hasPrefix("Anne-Marie, "), "Hyphenated first names stay intact")
check(fitnessCopy.personalizedPaywallHeadline(name: "Élodie").hasPrefix("Élodie, "), "Preserve accented names")
check(fitnessCopy.personalizedPaywallHeadline(name: "Researcher") == fitnessCopy.paywallHeadline, "Do not address a user by an automatic placeholder")
check(fitnessCopy.personalizedPaywallHeadline(name: " \n ") == fitnessCopy.paywallHeadline, "Blank names have no stray comma")
let legacyGoals: Set<String> = ["Walk More", "Lose Weight", "Get Fit", "Have Fun", "Collect Creatures"]
check(Set(WalkingMotivation.selected(in: legacyGoals).map(\.rawValue)) == legacyGoals, "Every previously saved goal still maps to a visible motivation")
check(WalkingMotivation.selected(in: ["Get Fit", "Unknown Future Goal"]) == [.fitness], "Unknown choices do not invent a motivation or hide recognized ones")
draft.selectedGoals = ["Get Fit", "Have Fun"]; draft.primaryGoal = "Have Fun"
draft.phase = .connections; draft.chatStep = .health; draft.playerName = "Ervenst"
draft.selectedBlockers = ["Walking feels boring"]; draft.save(defaults: defaults)
var expectedDraft = draft
expectedDraft.phase = .commitment
expectedDraft.completedConnections = true
if expectedDraft.currentSteps == "8,000+" { expectedDraft.currentSteps = "8,000 – 10,000" }
let restoredDraft = OnboardingDraft.load(defaults: defaults)
check(restoredDraft == expectedDraft, "Keep answers and position after app termination; normalize the old top range label")
check(restoredDraft.baselineSteps == draft.baselineSteps && restoredDraft.recommendedGoal == draft.recommendedGoal, "Old range migration preserves estimated steps and target")
draft.reachedPaywall = true; draft.phase = .commitment; draft.save(defaults: defaults)
let returning = OnboardingDraft.load(defaults: defaults)
check(returning.phase == .plan, "Paywall return goes to recap, before commitment and checkout")
check(returning.playerName == "Ervenst" && returning.selectedBlockers == draft.selectedBlockers, "Recap preserves personalization")
check(returning.primaryGoal == "Have Fun", "Chosen main goal survives relaunch and paywall return")
check(returning.selectedGoals == ["Get Fit", "Have Fun"], "Multiple motivations survive relaunch and the paywall return")
draft.reachedPaywall = false
for oldPhase in [OnboardingPhase.profile, .projection, .building] {
    draft.phase = oldPhase; draft.save(defaults: defaults)
    let migrated = OnboardingDraft.load(defaults: defaults)
    check(migrated.phase == .plan, "Legacy analysis screens migrate to the single plan")
    check(migrated.selectedGoals == draft.selectedGoals && migrated.playerName == draft.playerName, "Migration preserves personalization")
}
check(WalkingPlanPage.target.next == .comparison && WalkingPlanPage.comparison.previous == .target, "The same plan advances from daily target to its graph")
check(WalkingPlanPage.comparison.next == nil && WalkingPlanPage.target.previous == nil, "Plan page boundaries return to questions or continue to connections")
var paged = OnboardingDraft()
paged.phase = .plan; paged.planPage = .comparison; paged.selectedGoals = ["Lose Weight"]
paged.save(defaults: defaults)
check(OnboardingDraft.load(defaults: defaults).planPage == .comparison, "An unfinished graph page survives app termination")
paged.reachedPaywall = true; paged.save(defaults: defaults)
check(OnboardingDraft.load(defaults: defaults).planPage == .target, "Return from checkout begins with the user's goal and daily target")
for currentPhase in [OnboardingPhase.demo, .chat, .preparing, .plan, .connections, .commitment] {
    check(currentPhase.current == currentPhase, "Current flow positions remain stable")
}

var heavy = OnboardingDraft()
heavy.activity = "Everyday Walker"; heavy.currentSteps = "10,000 – 15,000"
check(heavy.baselineSteps == 12500 && heavy.recommendedGoal == 15000, "Everyday walker gets a real 2500-step challenge")
let heavyChart = WalkingPlanComparison(baselineSteps: heavy.baselineSteps, targetSteps: heavy.recommendedGoal)
check(heavyChart.additionalTotal == 75000, "Heavy walker graph truthfully shows 75000 extra steps at the target")
heavy.currentSteps = "15,000+"
check(heavy.recommendedGoal == 20000 && heavy.baselineSteps == 17500, "Highest range stays within the editable goal limit")
heavy.phase = .preparing; heavy.save(defaults: defaults)
check(OnboardingDraft.load(defaults: defaults).phase == .preparing, "Interrupted preparation resumes before showing the plan")
heavy.reachedPaywall = true; heavy.save(defaults: defaults)
check(OnboardingDraft.load(defaults: defaults).phase == .plan, "Returning from paywall does not rebuild the plan")
var previousProgress = 0.0
for tick in 0...150 {
    let preparation = WalkingPlanPreparation(elapsed: Double(tick) / 30)
    check(preparation.progress >= previousProgress && preparation.progress <= 1, "Preparation moves forward and stops at 100 percent")
    check(preparation.target(for: heavyChart) >= 12500 && preparation.target(for: heavyChart) <= 15000, "Crunching numbers stay between the chosen estimate and target")
    previousProgress = preparation.progress
}
check(WalkingPlanPreparation(elapsed: 4.2).target(for: heavyChart) == 15000, "Loading finishes with the exact plan target")
check(fitnessCopy.paywallHeadline == "Evolve your routine. Find your momentum." && fitnessCopy.paywallDetail.contains("body-composition goal"), "Fitness copy invites progress without promising fat loss")
for goal in WalkingMotivation.allCases {
    let copy = OnboardingCopy.forGoals([goal.rawValue])
    check(copy.paywallHeadline.contains(copy.paywallAccent), "Each goal's emotional headline retains its intended accent")
    check(copy.paywallDetail.contains("Unlock"), "The visible subhead explains the value of subscribing")
    for text in [copy.paywallHeadline, copy.paywallDetail, copy.planHeadline, copy.planDetail, copy.comparisonDetail] {
        check(!text.contains("Transform your body") && !text.contains("fat-burning") && !text.contains("20 miles"), "No guaranteed transformation or arbitrary fat-burning distance")
    }
}

OnboardingDraft.clear(defaults: defaults)
check(OnboardingDraft.load(defaults: defaults).phase == .demo, "Deliberate reset clears only the draft")
for consent in [true, false] { for enabled in [true, false] { for authorized in [true, false] {
    for completed in [true, false] { for premium in [true, false] {
        check(OnboardingReminderPolicy.shouldSchedule(consented: consent, enabled: enabled,
            authorized: authorized, completed: completed, premium: premium)
              == (consent && enabled && authorized && !completed && !premium), "Respect consent, subscription and completion")
    }}
}}}
for name in ["", "Researcher", "Sam", "  Sam  "] {
    for ready in [true, false] {
        let copy = OnboardingReminderPolicy.messages(name: name, planReady: ready)
        check(copy.count == 5, "Five messages then stop")
        check(Set(copy.map { $0.body }).count == 5, "No duplicate campaign bodies")
        check(!copy.contains { $0.body.contains("discount") }, "Never advertise an unconfigured discount")
        if name == "" || name == "Researcher" {
            check(!copy.contains { $0.title.hasPrefix(",") || $0.title.contains("Researcher,") }, "Natural copy without a name")
        }
    }
}
check(OnboardingReminderPolicy.interval == 172_800, "Two days between reminders")
print("PASS: flow ordering and legacy migration; 161 animation frames; 175 target/chart combinations; all 31 reason combinations and 80 valid primary choices; legacy and multiple goal persistence; saved progress and paywall return; 160 goal/obstacle combinations; 32 reminder eligibility states; five unique messages and name fallback.")
'''
# Integration guards for actual authorization entry points and screen wiring.
flow = (root/'Nanobeasts/Features/Onboarding/OnboardingFlowView.swift').read_text()
store = (root/'Nanobeasts/Models/AppStore.swift').read_text()
settings = (root/'Nanobeasts/Features/Settings/SettingsView.swift').read_text()
workout = (root/'Nanobeasts/Services/WorkoutLocationTracker.swift').read_text()
paywall = (root/'Nanobeasts/Features/Paywall/PaywallIntroduction.swift').read_text()
progress = (root/'Nanobeasts/Features/Onboarding/OnboardingProgressViews.swift').read_text()
assert 'welcomePage' not in flow, 'Welcome must not hide a second page'
assert 'OnboardingLocationPermission()' not in flow and 'requestAuthorizationIfNeeded' not in flow
completion = store.split('    func completeOnboarding() {', 1)[1].split('    @discardableResult', 1)[0]
assert 'requestAuthorization' not in completion, 'Legacy reminder choices cannot prompt on completion'
assert 'draft.chatStep = .health; transition(to: .connections)' not in flow
assert 'case .connections:' in flow and 'transition(to: .commitment)' in flow
assert 'OnboardingDailyLoopPreview()' in flow and 'if step == .research' in flow
research = flow.split('if step == .research {', 1)[1].split('} else {', 1)[0]
assert 'Text("Here’s how it works")' in research and 'OnboardingDailyLoopPreview()' in research
assert 'questionPrompt' not in research and 'questionHero' not in research
preview = progress.split('struct OnboardingDailyLoopPreview: View {', 1)[1].split('struct OnboardingPlanView:', 1)[0]
assert 'Text(' not in preview and '.clipShape(' not in preview and '.background(' not in preview
assert '.border(' not in preview and '.stroke(' not in preview
assert 'if step == .research { return .research }' not in flow, 'Research page should lead with the demo, not Professor Nano artwork'
assert 'url: OnboardingDemoMedia.url' in flow and 'url: OnboardingDemoMedia.url' in progress
assert 'Nanobeasts-Core-Loop-Streaming' not in progress and 'loopDuration:' not in progress
assert 'THE NANOBEASTS LOOP' not in progress, 'Core-loop video should not be wrapped in redundant label chrome'
assert 'Text(copy.paywallDetail)' in paywall, 'Outcome subhead must actually render'
assert 'Your name (optional)' in flow and 'case .name: true' in flow
assert 'requestAuthorizationIfNeeded()' in settings, 'Keep the later notification toggle'
assert 'manager.requestWhenInUseAuthorization()' in workout, 'Keep outdoor workout authorization'
print('PASS: single welcome, Health deferred to Home, contextual permissions, optional name, daily-loop recap, visible paywall subhead.')
with tempfile.TemporaryDirectory(prefix='nano-onboarding-checks-') as temp:
    temp=Path(temp)
    (temp/'main.swift').write_text((root/'Nanobeasts/Features/Onboarding/OnboardingJourney.swift').read_text()+'\n'+(root/'Nanobeasts/Features/Onboarding/OnboardingCopy.swift').read_text()+'\n'+checks)
    subprocess.run(['xcrun','swiftc','-module-cache-path',str(temp/'ModuleCache'),str(temp/'main.swift'),'-o',str(temp/'checks')],check=True)
    subprocess.run([str(temp/'checks')],check=True)
