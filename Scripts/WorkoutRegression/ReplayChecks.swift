func check(_ value: @autoclosure () -> Bool, _ name: String) {
    precondition(value(), name)
    print("PASS: \(name)")
}
func point(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
    .init(latitude: lat, longitude: lon)
}
func near(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D, meters: Double = 0.1) -> Bool {
    guard let a else { return false }
    return CLLocation(latitude: a.latitude, longitude: a.longitude)
        .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) < meters
}
let start = point(0, 0)
let turn = point(0, 0.001)
let finish = point(0, 0.004)
let track = WorkoutRouteReplayTrack(route: [start, turn, finish], breakIndices: [])
check(track.canReplay, "recorded walking route can replay")
check(near(track.frame(at: 0).marker, start), "recap begins at the recorded start")
check(near(track.frame(at: 0.5).marker, point(0, 0.002)), "uneven GPS samples advance by distance, not sample count")
check(near(track.frame(at: 1).marker, finish), "recap ends at the recorded finish")
check(track.frame(at: 1).coordinates.count == 3, "completion retains exact recorded vertices")
check(near(track.frame(at: -2).marker, start), "negative scrub position clamps to start")
check(near(track.frame(at: 3).marker, finish), "overshoot clamps to finish")
check(near(track.frame(at: .nan).marker, start), "non-finite progress safely resets to start")
_ = track.frame(at: 0.9)
check(near(track.frame(at: 0.1).marker, point(0, 0.0004)), "backward scrubbing restores an earlier path")
let gap = WorkoutRouteReplayTrack(route: [start, turn, point(0, 1), point(0, 1.001)], breakIndices: [2])
check(gap.distance < 250, "GPS outage does not add teleport distance")
let gapFrame = gap.frame(at: 0.75)
check(near(gapFrame.marker, point(0, 1.0005)), "playback resumes inside the next recorded segment")
let segments = WorkoutRouteSegments.split(gapFrame.coordinates, at: gapFrame.breakIndices)
check(segments.count == 2 && segments.allSatisfy { $0.count == 2 }, "reveal retains separate paths across a GPS gap")
let invalid = WorkoutRouteReplayTrack(route: [start, turn, point(100, 0), point(0, 1), point(0, 1.001)], breakIndices: [])
check(invalid.frame(at: 1).breakIndices == [2] && invalid.distance < 250, "invalid coordinates never create a connecting route")
check(!WorkoutRouteReplayTrack(route: [], breakIndices: []).canReplay, "no GPS means no replay")
check(!WorkoutRouteReplayTrack(route: [start], breakIndices: []).canReplay, "a lone GPS fix cannot invent movement")
check(!WorkoutRouteReplayTrack(route: [start, start], breakIndices: []).canReplay, "stationary fixes cannot create a replay")
let duplicate = WorkoutRouteReplayTrack(route: [start, start, turn, turn], breakIndices: [])
check(near(duplicate.frame(at: 0.5).marker, point(0, 0.0005)), "duplicate fixes do not stall or divide by zero")
let wrap = WorkoutRouteReplayTrack(route: [point(0, 179.999), point(0, -179.999)], breakIndices: [])
check(abs(wrap.frame(at: 0.5).marker!.longitude) > 179.99, "date-line interpolation stays near the recorded walk")
check(track.coordinates.count == 3 && track.breakIndices.isEmpty, "scrubbing leaves the source route unchanged")
