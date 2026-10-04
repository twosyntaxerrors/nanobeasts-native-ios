var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}
let start = Date(timeIntervalSince1970: 1_000)
let firstSteps = WatchStepProgress(steps: 0)
check(firstSteps.target == 1_000 && firstSteps.fraction == 0, "New walk starts an empty first milestone")
let nearlyThere = WatchStepProgress(steps: 999)
check(nearlyThere.remaining == 1 && nearlyThere.fraction == 0.999, "Last step before a milestone")
let reached = WatchStepProgress(steps: 1_000)
check(reached.target == 2_000 && reached.fraction == 0 && reached.remaining == 1_000,
      "Crossing a milestone advances the target and resets the bar together")
let laterSteps = WatchStepProgress(steps: 6_221)
check(laterSteps.target == 7_000 && laterSteps.remaining == 779 && laterSteps.fraction == 0.221,
      "Bar measures the current interval while count shows all workout steps")
check(WatchStepProgress(steps: -1).steps == 0, "Invalid negative count cannot show negative progress")
var pause = WatchAutoPausePolicy()
check(pause.action(at: start.addingTimeInterval(120), running: true, automaticallyPaused: false) == nil,
      "Missing sensor callbacks must never pause a workout")
pause.observe(.stationary, at: start)
check(pause.action(at: start.addingTimeInterval(14), running: true, automaticallyPaused: false) == nil, "Brief stop")
check(pause.action(at: start.addingTimeInterval(15), running: true, automaticallyPaused: false) == .pause, "Stationary pause")
pause.observe(.moving, at: start.addingTimeInterval(16))
check(pause.action(at: start.addingTimeInterval(18), running: false, automaticallyPaused: true) == nil, "Resume debounce")
check(pause.action(at: start.addingTimeInterval(19), running: false, automaticallyPaused: true) == .resume, "Automatic resume")
check(pause.action(at: start.addingTimeInterval(50), running: false, automaticallyPaused: false) == nil, "Manual pause stays paused")
pause.observe(.stationary, at: start.addingTimeInterval(10))
check(pause.action(at: start.addingTimeInterval(50), running: true, automaticallyPaused: false) == nil, "Ignore stale stop")
pause.observe(.unknown, at: start.addingTimeInterval(51))
check(pause.action(at: start.addingTimeInterval(90), running: false, automaticallyPaused: true) == nil, "Uncertain motion cannot resume")
pause.reset()
check(pause.action(at: start.addingTimeInterval(120), running: true, automaticallyPaused: false) == nil, "Reset drops old sensor evidence")
pause.observe(.stationary, at: start.addingTimeInterval(121))
pause.observe(.moving, at: start.addingTimeInterval(130))
check(pause.action(at: start.addingTimeInterval(140), running: true, automaticallyPaused: false) == nil, "Walking cancels a short stop")

var miles = WatchMilestonePolicy()
check(miles.update(steps: 999, miles: 0.99, elapsed: 594).isEmpty, "No premature milestone")
let simultaneous = miles.update(steps: 1_002, miles: 1.01, elapsed: 606)
check(simultaneous.count == 2, "Simultaneous step and mile alerts both survive")
check(simultaneous.last?.detail == "Split 10:00 /mi", "Interpolated first mile split")
check(miles.update(steps: 1_002, miles: 1.01, elapsed: 606).isEmpty, "No duplicate after pause or repeated metrics")
check(miles.update(steps: 950, miles: 0.98, elapsed: 610).isEmpty, "Regressing data cannot repeat a milestone")
let second = miles.update(steps: 2_250, miles: 2.01, elapsed: 1_206)
check(second.last?.detail == "Split 10:00 /mi", "Active-time second split")
check(second.first?.id == "steps-2", "Step threshold independent of distance")
var recovered = WatchMilestonePolicy(stepMark: miles.stepMark, mileMark: miles.mileMark,
    lastMileElapsed: miles.lastMileElapsed, previousMiles: 2.01, previousElapsed: 1_206)
check(recovered.update(steps: 2_250, miles: 2.01, elapsed: 1_206).isEmpty, "Recovery cannot repeat alerts")
check(recovered.update(steps: 3_010, miles: 3.01, elapsed: 1_806).last?.detail == "Split 10:00 /mi", "Recovery preserves split timing")
var batch = WatchMilestonePolicy()
let catchUp = batch.update(steps: 5_200, miles: 3.5, elapsed: 2_100)
check(catchUp.count == 2, "Bounded catch-up alerts")
check(catchUp.last?.title == "Mile 3!", "Latest crossed mile")
check(catchUp.last?.detail == "Split 10:00 /mi", "Batched mile splits")
check(batch.update(steps: 5_300, miles: .nan, elapsed: 2_200).isEmpty, "Invalid sensor values")

// Optional snapshot additions retain compatibility with already queued workout data.
let state = WatchWorkoutSnapshot(id: UUID(), workoutID: "outdoor-walk", name: "Outdoor Walk", indoor: false,
    startedAt: start, updatedAt: start, elapsed: 600, steps: 1_000, distanceMiles: 1, calories: 50, phase: .paused)
let encoded = try JSONEncoder().encode(state)
let decoded = try JSONDecoder().decode(WatchWorkoutSnapshot.self, from: encoded)
check(decoded.routeEnabled == nil && decoded.automaticallyPaused == nil, "Legacy-compatible decoding")
var checkpoint = state
checkpoint.automaticallyPaused = true
checkpoint.routeEnabled = false
checkpoint.milestoneStepMark = 1
checkpoint.milestoneMileMark = 1
checkpoint.lastMileElapsed = 600
let restored = try JSONDecoder().decode(WatchWorkoutSnapshot.self, from: JSONEncoder().encode(checkpoint))
check(restored.automaticallyPaused == true && restored.routeEnabled == false, "Recovery preserves pause and route settings")
check(restored.lastMileElapsed == 600 && restored.milestoneMileMark == 1, "Recovery preserves milestone checkpoint")
// Creature updates can arrive through both foreground replies and queued context.
let originalCreature = WatchCompanionArtwork(stageID: "first-stage", name: "First", updatedAt: start,
    pngData: Data([1, 2, 3]))
let nextCreature = WatchCompanionArtwork(stageID: "next-stage", name: "Next", updatedAt: start.addingTimeInterval(1))
check(nextCreature.supersedes(originalCreature), "A new creature clears the previous creature's image while loading")
check(!originalCreature.supersedes(nextCreature), "Delayed replies cannot restore an old creature")
var readyCreature = nextCreature
readyCreature.pngData = Data([4, 5, 6])
check(readyCreature.supersedes(nextCreature), "Artwork may enrich the same creature revision")
check(!nextCreature.supersedes(readyCreature), "Metadata-only delivery cannot erase ready artwork")
check(!readyCreature.supersedes(readyCreature), "Repeated delivery does not reload artwork")
let cachedCreature = try JSONDecoder().decode(WatchCompanionArtwork.self, from: JSONEncoder().encode(readyCreature))
check(cachedCreature.stageID == readyCreature.stageID && cachedCreature.pngData == readyCreature.pngData,
      "Offline cache preserves creature identity and PNG bytes together")
check(cachedCreature.dailyStepGoal == nil, "Older artwork payloads remain compatible without a daily goal")
let goalUpdate = WatchCompanionArtwork(stageID: readyCreature.stageID, name: readyCreature.name,
    updatedAt: start.addingTimeInterval(2), pngData: readyCreature.pngData, dailyStepGoal: 8_000)
check(goalUpdate.supersedes(readyCreature) && !readyCreature.supersedes(goalUpdate),
      "A goal update supersedes stale companion context without changing the creature")
let cachedGoal = try JSONDecoder().decode(WatchCompanionArtwork.self, from: JSONEncoder().encode(goalUpdate))
check(cachedGoal.dailyStepGoal == 8_000 && cachedGoal.pngData == readyCreature.pngData,
      "Offline companion cache retains the personal daily goal and image together")
var animatedCreature = readyCreature
animatedCreature.animationData = Data([71, 73, 70])
check(animatedCreature.supersedes(readyCreature), "Animation can arrive after the still frame")
check(!readyCreature.supersedes(animatedCreature), "A delayed still frame cannot remove the animation")
check(!animatedCreature.supersedes(animatedCreature), "Repeated context does not restart arrival motion")
let animationCache = try JSONDecoder().decode(WatchCompanionArtwork.self, from: JSONEncoder().encode(animatedCreature))
check(animationCache.animationData == animatedCreature.animationData, "Animation survives an offline relaunch")
check(cachedCreature.animationData == nil, "Old phone payloads without animation remain compatible")
let newerStage = WatchCompanionArtwork(stageID: "evolved", name: "Evolved", updatedAt: start.addingTimeInterval(100))
check(newerStage.supersedes(animatedCreature) && !animatedCreature.supersedes(newerStage), "A late animation cannot bring back a creature after evolution")
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let day = calendar.startOfDay(for: start)
let today = WatchDailyActivity(day: day, steps: 6_221, distanceMiles: 2.64, activeCalories: 318)
check(today.isCurrent(at: day.addingTimeInterval(86_399), calendar: calendar), "Home uses the current calendar day's totals")
check(!today.isCurrent(at: day.addingTimeInterval(86_400), calendar: calendar), "Yesterday's totals cannot appear as today's")
check(today.goalProgress(target: 10_000) == 0.6221, "Home bar uses daily steps and the personal daily goal")
check(today.goalProgress(target: 5_000) == 1, "Daily bar stays full after the goal is reached")
check(today.goalProgress(target: nil) == nil && today.goalProgress(target: 0) == nil,
      "Unsynced or invalid daily goals cannot invent progress")
let unavailable = WatchDailyActivity(day: day, steps: nil, distanceMiles: nil, activeCalories: nil)
check(unavailable.goalProgress(target: 10_000) == nil, "Missing Health data remains unknown instead of fabricated zero activity")
print("Passed \(checks) watch feedback checks")
