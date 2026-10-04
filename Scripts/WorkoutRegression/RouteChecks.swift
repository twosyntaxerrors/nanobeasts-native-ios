// Compiled with the production filter, segment splitter, and route shape by
// Scripts/verify_workout_routes.py. Runs on macOS without a simulator.
let now = Date()
func fix(_ latitude: Double, _ longitude: Double, seconds: Double = 0,
         accuracy: Double = 5, speed: Double = 1.2) -> CLLocation {
    CLLocation(coordinate: .init(latitude: latitude, longitude: longitude), altitude: 0,
               horizontalAccuracy: accuracy, verticalAccuracy: 5, course: 0,
               speed: speed, timestamp: now.addingTimeInterval(seconds))
}
func decision(_ next: CLLocation, _ previous: CLLocation? = nil,
              after: Date? = nil) -> WorkoutRouteFilter.Decision {
    WorkoutRouteFilter.evaluate(next, previous: previous, after: after,
                                now: now, maximumSpeed: 4)
}
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), name)
    print("PASS: \(name)")
}
let start = fix(40, -73, seconds: -10)
check(decision(start) == .startSegment, "accurate first fix starts a segment")
check(decision(fix(40.00005, -73, seconds: -5), start) == .append, "walking movement is retained")
check(decision(fix(40.00005, -72.99995), fix(40.00005, -73, seconds: -5)) == .append, "walking corner is retained")
check(decision(fix(40.000005, -73), start) == .reject, "stationary jitter is rejected")
check(decision(fix(41, -73), start) == .reject, "GPS teleport is rejected")
check(decision(fix(40, -73, accuracy: 100)) == .reject, "coarse GPS fix is rejected")
check(decision(fix(40, -73, accuracy: -1)) == .reject, "invalid accuracy is rejected")
check(decision(fix(91, -73)) == .reject, "invalid coordinate is rejected")
check(decision(fix(40, -73, seconds: 20)) == .reject, "future fix is rejected")
check(decision(start, start) == .reject, "duplicate timestamp is rejected")
check(decision(fix(40.0001, -73, seconds: -11), start) == .reject, "out of order fix is rejected")
check(decision(start, after: now) == .reject, "cached pre-resume fix is rejected")
check(decision(fix(40.0001, -73), fix(40, -73, seconds: -60)) == .startSegment, "GPS outage starts a separate segment")
check(decision(fix(40.0001, -73), nil, after: now.addingTimeInterval(-1)) == .startSegment, "resume with no baseline does not add gap distance")
check(decision(fix(40, -73, speed: 30)) == .reject, "implausible reported speed rejected even for first fix")
check(decision(fix(40.0001, -73, speed: -1), start) == .append, "unavailable speed still accepts plausible displacement")
check(decision(fix(40.00005, -73, seconds: -600), fix(40, -73, seconds: -605)) == .append,
      "batched background locations use capture timestamps, not delivery time")
let route = [fix(40,-73), fix(40.001,-73), fix(40.001,-72.999), fix(40.002,-72.999)].map(\.coordinate)
let segments = WorkoutRouteSegments.split(route, at: [2])
check(segments.map(\.count) == [2,2], "pause boundaries preserve both recorded segments")
check(WorkoutRouteSegments.split(route, at: []).count == 1, "legacy continuous routes remain supported")
let broken = [route[0], CLLocationCoordinate2D(latitude: .nan, longitude: 0), route[2]]
check(WorkoutRouteSegments.split(broken, at: []).map(\.count) == [1,1], "invalid point creates a gap instead of connecting through it")
let bounds = CGRect(x: 22, y: 22, width: 600, height: 400)
let path = WorkoutRouteShape(coordinates: route, breakIndices: [2]).path(in: bounds)
var moves = 0
path.forEach { if case .move = $0 { moves += 1 } }
check(moves == 2, "export path does not bridge a pause")
check(bounds.insetBy(dx: -0.001, dy: -0.001).contains(path.boundingRect), "route stays inside padded export bounds")
let equatorial = [CLLocationCoordinate2D(latitude: 0, longitude: 0), .init(latitude: 0.001, longitude: 0.001)]
let northern = [CLLocationCoordinate2D(latitude: 60, longitude: 0), .init(latitude: 60.001, longitude: 0.001)]
let square = CGRect(x: 0, y: 0, width: 500, height: 500)
let eq = WorkoutRouteShape(coordinates: equatorial).path(in: square).boundingRect
let north = WorkoutRouteShape(coordinates: northern).path(in: square).boundingRect
check(abs(eq.width / eq.height - 1) < 0.01, "equatorial map proportions")
check(abs(north.width / north.height - 0.5) < 0.01, "latitude correction matches map proportions")
let acrossDateLine = [CLLocationCoordinate2D(latitude: 0, longitude: 179.999), .init(latitude: 0.002, longitude: -179.999)]
let wrapped = WorkoutRouteShape(coordinates: acrossDateLine).path(in: square).boundingRect
check(abs(wrapped.width / wrapped.height - 1) < 0.01, "date line route takes the short way around")
for (name, coordinates) in [("horizontal", [route[1], route[2]]), ("vertical", [route[0], route[1]]), ("duplicate", [route[0], route[0]])] {
    let rect = WorkoutRouteShape(coordinates: coordinates).path(in: square).boundingRect
    check(rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite, "\(name) route has finite geometry")
}
check(WorkoutRouteShape(coordinates: []).path(in: square).isEmpty, "empty route has no invented path")
// Health routes arrive in batches and are historical, so they must not be
// rejected by the live recorder's freshness window or joined across outages.
let healthRoute = WorkoutRouteSegments.recorded([
    [fix(40.0001, -73, seconds: -1790), fix(40, -73, seconds: -1800),
     fix(40.0002, -73, seconds: -1780), fix(40.0003, -73, seconds: -1700),
     fix(40.0004, -73, seconds: -1690)],
    [fix(40.0005, -73, seconds: -1685), fix(40.0006, -73, seconds: -1675)]
])
check(healthRoute.coordinates.count == 7, "historical Watch route retains all recorded points")
check(healthRoute.coordinates.first?.latitude == 40, "Health route batches are ordered by timestamp")
check(healthRoute.breakIndices == [3, 5], "Health route keeps GPS gaps and separate route series")
let damagedHealthRoute = WorkoutRouteSegments.recorded([[
    fix(40, -73, seconds: -30), fix(40, -73, seconds: -30),
    fix(40.0001, -73, seconds: -20, accuracy: 100),
    fix(40.0002, -73, seconds: -10), fix(40.0003, -73)
]])
check(damagedHealthRoute.coordinates.count == 3, "Health route discards duplicate and inaccurate fixes")
check(damagedHealthRoute.breakIndices == [1], "discarded Health fixes create gaps instead of invented shortcuts")
let savedWorkoutID = UUID()
let longWalk = (0..<1800).map { index in
    CLLocationCoordinate2D(latitude: 40 + Double(index) * 0.00001,
                           longitude: -73 + sin(Double(index) / 100) * 0.001)
}
WorkoutHistoryRouteArchive.save(longWalk, breakIndices: [900], for: savedWorkoutID)
let restoredWalk = WorkoutHistoryRouteArchive.load(for: savedWorkoutID)
check(restoredWalk.count == 1800, "full 30-minute route survives saving and reloading")
check(zip(longWalk, restoredWalk).allSatisfy {
    $0.latitude == $1.latitude && $0.longitude == $1.longitude
}, "history keeps every original route coordinate for sharing")
check(WorkoutHistoryRouteArchive.loadBreakIndices(for: savedWorkoutID) == [900], "saved route retains pause boundary")
check(WorkoutHistoryRouteArchive.load(for: UUID()).isEmpty, "missing archive never supplies a different workout's route")
print("All route regression checks passed.")
