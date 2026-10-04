let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
let companion = CreatureStage(familyID: "test", name: "Companion", imageKey: "test", stage: 1, types: [], description: "")
func workout(_ type: String = "outdoor-walk", source: WorkoutHistoryRecord.Source = .nanobeasts,
             name: String? = nil, start: Double = 104, span: Double = 2455,
             indoor: Bool = false, id: UUID = UUID()) -> WorkoutHistoryRecord {
    WorkoutHistoryRecord(id: id, workoutID: type, name: type, symbol: "figure.walk",
        startedAt: base.addingTimeInterval(start), endedAt: base.addingTimeInterval(start + span),
        duration: span, steps: source == .nanobeasts ? 4433 : 0,
        distanceMiles: source == .nanobeasts ? 2.51 : 2.33, calories: 213, indoor: indoor,
        source: source, sourceName: name ?? (source == .nanobeasts ? "Nanobeasts" : "Apple Watch"),
        companion: source == .nanobeasts ? .init(stage: companion) : nil,
        discoveries: source == .nanobeasts ? [.init(stage: companion, kind: .evolution, timestamp: base)] : nil)
}
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), name)
    print("PASS: \(name)")
}
let local = workout()
let exported = workout("health-walk", source: .appleHealth, name: "Nanobeasts Native", span: 2455.1)
let watch = workout("health-walk", source: .appleHealth, start: 0, span: 2541)
let triple = [local, exported, watch]
let merged = WorkoutHistoryReconciler.reconcile(triple)
check(merged.count == 1, "local, exported copy, and Watch recording become one session")
check(merged[0].id == local.id && merged[0].companion == local.companion, "local identity and companion survive")
check(merged[0].steps == local.steps && merged[0].distanceMiles == local.distanceMiles && merged[0].calories == local.calories, "overlapping metrics are never added together")
check(Set(merged[0].healthWorkoutIDs ?? []) == Set([exported.id, watch.id]), "both Health identities remain available for route recovery")
check(merged[0].discoveries == local.discoveries, "creature discoveries survive without duplication")
check(WorkoutHistoryReconciler.reconcile(merged + triple) == merged, "repeated import is idempotent")
check(WorkoutHistoryReconciler.reconcile(Array(triple.reversed())) == merged, "import order does not affect the canonical record")
check(WorkoutHistoryReconciler.reconcile([local, workout()]).count == 2, "distinct local recordings remain separate")
check(WorkoutHistoryReconciler.reconcile([watch, workout("health-walk", source: .appleHealth, start: 0, span: 2541)]).count == 2, "distinct same-source Health recordings remain separate")
check(WorkoutHistoryReconciler.reconcile([local, workout("health-walk", source: .appleHealth, start: 2559)]).count == 2, "adjacent walks are not merged")
check(WorkoutHistoryReconciler.reconcile([local, workout("health-walk", source: .appleHealth, start: 150, span: 600)]).count == 2, "a short nested recording does not collapse a long walk")
check(WorkoutHistoryReconciler.reconcile([local, workout("health-walk", source: .appleHealth, start: 500)]).count == 2, "partial overlap with distant starts stays separate")
check(WorkoutHistoryReconciler.reconcile([local, workout("health-run", source: .appleHealth)]).count == 2, "different activity types stay separate")
check(WorkoutHistoryReconciler.reconcile([local, workout("health-walk", source: .appleHealth, indoor: true)]).count == 2, "indoor and outdoor activities stay separate")
check(WorkoutHistoryReconciler.reconcile([local, workout("health-walk", source: .appleHealth, start: 10000)]).count == 2, "same-day workouts at different times stay separate")
check(WorkoutHistoryReconciler.reconcile([workout(start: 0, span: 20), workout("health-walk", source: .appleHealth, name: "Nanobeasts Native", start: 0, span: 23)]).count == 1, "short workout and its own Health copy reconcile")
check(WorkoutHistoryReconciler.reconcile([exported, watch]).count == 1, "overlapping Health recordings reconcile without a local row")
check(WorkoutHistoryReconciler.reconcile([workout("japanese-walk-outdoor"), watch]).count == 1, "walking variants match Health walking")
var linked = workout("health-walk", source: .appleHealth, start: 20000)
linked.nanobeastsWorkoutID = local.id
check(WorkoutHistoryReconciler.reconcile([local, linked]).count == 1, "saved local UUID links the export without guessing from timestamps")
var withArchivedRoute = watch
let archivedRouteID = UUID()
withArchivedRoute.healthWorkoutIDs = [archivedRouteID]
check(WorkoutHistoryReconciler.reconcile([local, withArchivedRoute])[0].healthWorkoutIDs?.contains(archivedRouteID) == true, "previous route archive identities survive migration")
let solo = WorkoutHistoryReconciler.reconcile([watch])
check(WorkoutHistoryReconciler.reconcile(solo + [watch]) == solo, "reimporting a standalone Health workout leaves it unchanged")
let encoded = try JSONEncoder().encode(merged)
let decoded = try JSONDecoder().decode([WorkoutHistoryRecord].self, from: encoded)
check(decoded == merged, "consolidated history survives serialization")
if CommandLine.arguments.count > 1 {
    let original = try JSONDecoder().decode([WorkoutHistoryRecord].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
    let repaired = WorkoutHistoryReconciler.reconcile(original)
    check(WorkoutHistoryReconciler.reconcile(Array(original.prefix(3))).count == 1, "device: today's three recordings resolve to one walk")
    check(repaired.count < original.count, "device: already-imported duplicates are repaired")
    check(WorkoutHistoryReconciler.reconcile(repaired + original) == repaired, "device: importing the same history again adds no duplicates")
    for record in original where record.source == .nanobeasts {
        check(repaired.contains { $0.id == record.id && $0.steps == record.steps && $0.companion == record.companion }, "device: local session and companion retained")
    }
    let beforeIDs = Set(original.filter { $0.source == .appleHealth }.map(\.id))
    let afterIDs = Set(repaired.flatMap { record in (record.source == .appleHealth ? [record.id] : []) + (record.healthWorkoutIDs ?? []) })
    check(beforeIDs.isSubset(of: afterIDs), "device: every imported Health identity retained")
    print("Device history: \(original.count) rows → \(repaired.count) sessions")
    if CommandLine.arguments.count > 2 {
        try JSONEncoder().encode(repaired).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
print("All history regression checks passed.")

check(!WorkoutActivityPolicy.hasActivity(steps: 0, distanceMiles: 0, calories: 0), "empty accidental sessions are discarded")
check(WorkoutActivityPolicy.hasActivity(steps: 1, distanceMiles: 0, calories: 0), "steps alone preserve a workout")
check(WorkoutActivityPolicy.hasActivity(steps: 0, distanceMiles: 0.1, calories: 0), "cycling distance preserves a workout without steps")
check(WorkoutActivityPolicy.hasActivity(steps: 0, distanceMiles: 0, calories: 10), "stationary exercise calories preserve a workout")
check(!WorkoutActivityPolicy.hasActivity(steps: 0, distanceMiles: .nan, calories: .infinity), "invalid sensor values do not count as activity")

var authoritative = local
let originalIdentity = authoritative.id
let originalCompanion = authoritative.companion
let checked = Date()
authoritative.applyHealthTotals(WorkoutHealthTotals(steps: 500, distanceMiles: 0.25, calories: 20,
                                                    duration: 300, checkedAt: checked))
check(authoritative.steps == 500 && authoritative.distanceMiles == 0.25 && authoritative.calories == 20,
      "Health replaces higher device estimates rather than selecting the maximum")
check(authoritative.duration == 300 && authoritative.id == originalIdentity && authoritative.companion == originalCompanion,
      "Health duration updates without changing session identity or companion")
authoritative.applyHealthTotals(WorkoutHealthTotals(steps: 0, checkedAt: checked.addingTimeInterval(1)))
check(authoritative.steps == 0 && authoritative.distanceMiles == 0.25 && authoritative.calories == 20,
      "confirmed zero is valid while unavailable metrics preserve previous confirmed values")
authoritative.applyHealthTotals(WorkoutHealthTotals(distanceMiles: .nan, calories: -.infinity))
check(authoritative.distanceMiles == 0.25 && authoritative.calories == 20, "invalid Health quantities are rejected")
var linkedOlder = exported
linkedOlder.healthTotals = nil
let authoritativeMerge = WorkoutHistoryReconciler.reconcile([authoritative, linkedOlder])
check(authoritativeMerge.count == 1 && authoritativeMerge[0].steps == 0 && authoritativeMerge[0].distanceMiles == 0.25,
      "reimporting the old Health export cannot overwrite corrected totals")
let authoritativeRoundTrip = try JSONDecoder().decode(WorkoutHistoryRecord.self, from: JSONEncoder().encode(authoritative))
check(authoritativeRoundTrip == authoritative, "Health provenance survives persistent history reload")
let windowStart = Date(timeIntervalSince1970: 1_800_000_000)
let windowEnd = windowStart.addingTimeInterval(1800)
let intervals = WorkoutHealthWindowPolicy.activeIntervals(start: windowStart, end: windowEnd, boundaries: [
    .init(date: windowStart.addingTimeInterval(600), paused: true),
    .init(date: windowStart.addingTimeInterval(600), paused: true),
    .init(date: windowStart.addingTimeInterval(900), paused: false)
])
check(intervals.map(\.duration) == [600, 900], "Health totals exclude pauses, including duplicate pause events")
check(WorkoutHealthWindowPolicy.activeIntervals(start: windowStart, end: windowEnd, boundaries: [
    .init(date: windowStart.addingTimeInterval(600), paused: true)
]).map(\.duration) == [600], "a workout finished while paused excludes the paused tail")
let normalized = WorkoutHealthWindowPolicy.normalized([
    DateInterval(start: windowStart.addingTimeInterval(-10), end: windowStart.addingTimeInterval(30)),
    DateInterval(start: windowStart.addingTimeInterval(20), end: windowStart.addingTimeInterval(60)),
    DateInterval(start: windowStart.addingTimeInterval(90), end: windowStart.addingTimeInterval(100))
], start: windowStart, end: windowStart.addingTimeInterval(95))
check(normalized.map(\.duration) == [60, 5], "overlapping intervals are merged and clipped without counting gaps")
check(abs(WorkoutHealthWindowPolicy.overlapFraction(
    bucket: DateInterval(start: windowStart, duration: 1),
    interval: DateInterval(start: windowStart, duration: 0.25)) - 0.25) < 0.00001,
    "fractional final second cannot include time after workout end")
print("All Health authority and pause-boundary regression checks passed.")
