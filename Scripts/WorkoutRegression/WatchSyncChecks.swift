@MainActor
func runChecks() async throws {
    func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        precondition(condition(), label)
        print("PASS: \(label)")
    }
    let anchor = Date(timeIntervalSinceReferenceDate: 700_000_000)
    var live = WatchWorkoutSnapshot(id: UUID(), workoutID: "outdoor-walk", name: "Outdoor Walk", indoor: false,
        startedAt: anchor.addingTimeInterval(-30), updatedAt: anchor, elapsed: 30, steps: 0, distanceMiles: 0, calories: 0, phase: .running)
    check(live.elapsed(at: anchor.addingTimeInterval(90)) == 120, "visible clock catches up after screen inactivity without counting timer ticks")
    live.phase = .paused
    check(live.elapsed(at: anchor.addingTimeInterval(90)) == 30, "paused clock remains frozen while the screen is inactive")
    live.phase = .saving
    check(live.elapsed(at: anchor.addingTimeInterval(90)) == 30, "finishing does not add Health save or sync time to duration")
    live.phase = .running; live.updatedAt = anchor.addingTimeInterval(90)
    check(live.elapsed(at: anchor.addingTimeInterval(95)) == 35, "resume anchor excludes time spent paused")
    check(WorkoutMetricsFormat.pace(elapsed: 600, miles: 0.5) == "20′00″", "average pace uses active workout duration and measured distance")
    check(WorkoutMetricsFormat.pace(elapsed: 2, miles: 0) == "—′—″", "pace waits for measured distance instead of inventing a value")
    check(WorkoutMetricsFormat.time(2455.89, subseconds: true) == "40:55.89" && WorkoutMetricsFormat.time(3661) == "1:01:01", "clock handles hundredths and hour boundaries")
    check(WorkoutMetricsFormat.distance(0.05).unit == "FT" && WorkoutMetricsFormat.distance(0.1).unit == "MI", "short distances transition from feet to miles")
    live.heartRate = 110; live.heartRateMeasuredAt = anchor
    check(live.currentHeartRate(at: anchor.addingTimeInterval(31)) == nil, "stale heart rate becomes unavailable instead of appearing live")
    check(live.currentHeartRate(at: anchor.addingTimeInterval(5)) == 110, "fresh measured heart rate is displayed")
    live.phase = .running
    let click = live.updatedAt.addingTimeInterval(5)
    let finish = WatchWorkoutFinishRequest(sessionID: live.id, requestedAt: click,
        displayElapsed: live.elapsed(at: click))
    check(finish.displaySnapshot(live).elapsed(at: click.addingTimeInterval(120)) == 35,
          "Finish freezes the timer at confirmation before remote acknowledgement")
    var lateLive = live
    lateLive.updatedAt = click.addingTimeInterval(10); lateLive.elapsed = 45
    check(finish.displaySnapshot(lateLive).elapsed(at: click.addingTimeInterval(120)) == 35,
          "Live packets arriving during finish cannot move the frozen display")
    let stopping = live.changingPhase(to: .saving, at: click)
    check(stopping.elapsed == 35 && stopping.supersedes(live), "Stop acknowledgement captures the last active second")
    check(!lateLive.supersedes(stopping), "Late running packets cannot restart a stopped workout")
    var complete = stopping
    complete.phase = .finished; complete.updatedAt = click.addingTimeInterval(-1)
    check(complete.supersedes(stopping), "Authoritative final stats win over a slightly later mirrored stop callback")
    check(!lateLive.supersedes(complete), "A completed workout cannot become active again")
    var latePaused = lateLive; latePaused.phase = .paused
    check(!latePaused.supersedes(complete), "Delayed pause callbacks cannot undo completion")
    let newer = WatchWorkoutSnapshot(id: UUID(), workoutID: live.workoutID, name: live.name, indoor: true,
        startedAt: click.addingTimeInterval(60), updatedAt: click.addingTimeInterval(60),
        elapsed: 0, steps: 0, distanceMiles: 0, calories: 0, phase: .running)
    check(!finish.applies(to: newer) && finish.applies(to: complete), "Finish retries target only the original recording")
    check(!complete.supersedes(newer) && newer.supersedes(complete), "Delayed completion cannot replace a newer live walk")
    live.phase = .paused
    check(live.changingPhase(to: .saving, at: click).elapsed == 30, "Finishing a paused walk does not add pause time")
    let suite = "nanobeasts.watch-regression.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = WorkoutHistoryStore(defaults: defaults)
    let staleStore = WorkoutHistoryStore(defaults: defaults)
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let points = (0..<12000).map { index in
        WorkoutRecordedLocation(CLLocation(coordinate: .init(latitude: 40 + Double(index) * 0.000001, longitude: -73),
            altitude: 12, horizontalAccuracy: 5, verticalAccuracy: 8, course: -1, speed: 1,
            timestamp: start.addingTimeInterval(Double(index))))
    }
    let state = WatchWorkoutSnapshot(id: UUID(), workoutID: "outdoor-walk", name: "Outdoor Walk", indoor: false,
        startedAt: start, updatedAt: start.addingTimeInterval(12000), elapsed: 11900, steps: 15000,
        distanceMiles: 6.3, calories: 430, phase: .finished, healthWorkoutID: UUID())
    let result = WatchWorkoutResult(snapshot: state, locations: points, breakIndices: [6000])
    var routeState = live
    routeState.liveRoute = WatchWorkoutRouteWindow(locations: Array(points.prefix(125)), breakIndices: [110])
    var route = WatchWorkoutLiveRoute()
    route.receive(routeState)
    check(route.locations.count == 24 && route.breakIndices == [9],
          "late-opening live map receives bounded GPS history and preserves pauses")
    route.receive(routeState)
    check(route.locations.count == 24, "overlapping or repeated route packets do not duplicate points")
    routeState.liveRoute = WatchWorkoutRouteWindow(locations: Array(points.prefix(135)), breakIndices: [110])
    route.receive(routeState)
    check(route.locations.count == 34, "new live GPS samples extend the fog-clearing route")
    routeState.liveRoute = WatchWorkoutRouteWindow(locations: Array(points.prefix(300)), breakIndices: [110, 280])
    route.receive(routeState)
    check(route.breakIndices == [9, 34, 38], "connection gaps and pauses cannot clear unvisited territory")
    let catchup = WatchWorkoutResult(snapshot: routeState, locations: Array(points.prefix(290)), breakIndices: [110, 280])
    route.receiveFullRoute(catchup)
    check(route.locations.count == 300 && route.breakIndices == [110, 280],
          "full route catch-up restores the earlier walk while retaining newer live samples")
    route.receiveFullRoute(catchup)
    check(route.locations.count == 300, "repeated route catch-up is idempotent")
    let encodedLive = try JSONEncoder().encode(routeState)
    check(encodedLive.count < 8_000, "long workouts keep live mirroring payloads bounded")
    let decodedLive = try JSONDecoder().decode(WatchWorkoutSnapshot.self, from: encodedLive)
    check(decodedLive.liveRoute?.locations.count == 24, "live routes survive Watch-to-phone serialization")
    route.receive(newer)
    check(route.locations.isEmpty && route.breakIndices.isEmpty, "new indoor workouts cannot reuse an outdoor route")
    var legacy = live
    legacy.liveRoute = nil
    let legacyDecoded = try JSONDecoder().decode(WatchWorkoutSnapshot.self, from: JSONEncoder().encode(legacy))
    check(legacyDecoded.liveRoute == nil, "older companions remain compatible without live GPS payloads")
    let decoded = try JSONDecoder().decode(WatchWorkoutResult.self, from: JSONEncoder().encode(result))
    check(decoded.locations.count == 12000 && decoded.locations.last?.timestamp == points.last?.timestamp,
          "long Watch route retains every GPS sample and original timestamp")
    check(decoded.breakIndices == [6000] && decoded.snapshot.id == state.id && decoded.snapshot.healthWorkoutID == state.healthWorkoutID,
          "transfer preserves pause boundaries and both session identities")
    store.receiveWatchWorkout(decoded, companion: nil)
    store.receiveWatchWorkout(decoded, companion: nil)
    let revealed = store.savedTerritoryRoutes()
    check(revealed[state.id]?.map(\.count) == [6000, 6000],
          "permanent fog uses the full replay route and retains its pause boundary")
    check(revealed.count == 1, "repeated history sync reveals one saved route per workout")
    check(store.workouts.count == 1 && store.workouts[0].steps == 15000, "retried Watch transfer creates one session without adding steps")
    try await Task.sleep(for: .milliseconds(30))
    check(staleStore.workouts.contains(where: { $0.id == state.id }),
          "An already-open History store refreshes automatically after a Watch save")
    store.receiveWatchWorkout(.init(snapshot: state, locations: [], breakIndices: []), companion: nil)

    check(WorkoutHistoryRouteArchive.load(for: state.id).count == 12000 && WorkoutHistoryRouteArchive.loadBreakIndices(for: state.id) == [6000],
          "received route is available to workout history and sharing")
    let companion = CreatureStage(familyID: "test", name: "Test", imageKey: "test", stage: 1, types: [], description: "")
    let phoneID = staleStore.record(workoutID: "outdoor-walk", name: "Outdoor Walk", symbol: "figure.walk",
        startedAt: start.addingTimeInterval(20000), endedAt: start.addingTimeInterval(21000), duration: 1000,
        steps: 2000, distanceMiles: 1, calories: 80, indoor: false, companion: companion, discoveries: [], route: [])
    check(staleStore.workouts.count == 2, "phone save from an older screen preserves incoming Watch workouts")
    let anotherStore = WorkoutHistoryStore(defaults: defaults)
    var otherState = state
    otherState.startedAt = start.addingTimeInterval(30000); otherState.updatedAt = start.addingTimeInterval(42000)
    let anotherID = UUID()
    let another = WatchWorkoutSnapshot(id: anotherID, workoutID: otherState.workoutID, name: otherState.name, indoor: false,
        startedAt: otherState.startedAt, updatedAt: otherState.updatedAt, elapsed: 1000, steps: 1000, distanceMiles: 1, calories: 50, phase: .finished)
    anotherStore.receiveWatchWorkout(.init(snapshot: another, locations: [], breakIndices: []), companion: nil)
    staleStore.linkHealthWorkout(UUID(), to: phoneID)
    staleStore.updateDiscoveries([], for: phoneID)
    check(staleStore.workouts.count == 3, "delayed phone Health save and discoveries preserve a newer Watch transfer")
    var active = state; active.phase = .saving
    store.receiveWatchWorkout(.init(snapshot: active, locations: [], breakIndices: []), companion: nil)
    store.reload()
    check(store.workouts.count == 3, "unfinished Watch save cannot replace completed history")
    let instantID = UUID()
    var instant = WatchWorkoutSnapshot(id: instantID, workoutID: "outdoor-walk", name: "Outdoor Walk", indoor: false,
        startedAt: start.addingTimeInterval(50000), updatedAt: start.addingTimeInterval(51000),
        elapsed: 1000, steps: 1800, distanceMiles: 1, calories: 100, phase: .finished)
    store.receiveWatchWorkout(.init(snapshot: instant, locations: [], breakIndices: []), companion: nil)
    check(store.workouts.contains(where: { $0.id == instantID }), "Final metrics enter History before route transfer")
    let healthID = UUID()
    instant.healthWorkoutID = healthID
    store.receiveWatchWorkout(.init(snapshot: instant, locations: points, breakIndices: [6000]), companion: nil)
    check(store.workouts.filter { $0.id == instantID }.count == 1
          && store.workouts.first(where: { $0.id == instantID })?.healthWorkoutIDs == [healthID],
          "Full transfer enriches the same immediate row with Health identity")
    instant.phase = .failed; instant.steps = 1700; instant.elapsed = 900; instant.healthWorkoutID = nil
    store.receiveWatchWorkout(.init(snapshot: instant, locations: [], breakIndices: []), companion: nil)
    check(store.workouts.first(where: { $0.id == instantID })?.steps == 1800
          && store.workouts.first(where: { $0.id == instantID })?.duration == 1000
          && WorkoutHistoryRouteArchive.load(for: instantID).count == 12000,
          "Delayed partial results cannot regress final metrics or erase a route")

}
try await runChecks()
