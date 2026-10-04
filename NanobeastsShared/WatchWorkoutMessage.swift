import Foundation
import CoreLocation

/// Appearance travels independently of creature artwork and workout history.
struct WatchInterfaceAppearance: Codable, Sendable {
    static let contextKey = "nanoInterfaceAppearance"
    static let cacheKey = "nanobeasts.watch.appearance.v1"
    let accentName: String
    let updatedAt: Date

    func supersedes(_ previous: Self?) -> Bool {
        previous.map { updatedAt > $0.updatedAt } ?? true
    }
}

/// Elapsed time alone does not make an accidental recording an activity.
enum WorkoutActivityPolicy {
    static func hasActivity(steps: Int, distanceMiles: Double, calories: Double) -> Bool {
        steps > 0 || (distanceMiles.isFinite && distanceMiles > 0)
            || (calories.isFinite && calories > 0)
    }
}

/// A small, durable snapshot of the current creature, independent of workout data.
struct WatchCompanionArtwork: Codable, Sendable {
    static let contextKey = "nanoCompanionArtwork"
    static let cacheKey = "nanobeasts.watch.artwork.v1"
    let stageID: String
    let name: String
    let updatedAt: Date
    var pngData: Data?
    var dailyStepGoal: Int? = nil
    var animationData: Data? = nil
    var evolution: WorkoutEvolutionProgress? = nil

    func supersedes(_ previous: Self?) -> Bool {
        guard let previous else { return true }
        return updatedAt > previous.updatedAt
            || (updatedAt == previous.updatedAt && stageID == previous.stageID
                && ((previous.pngData == nil && pngData != nil)
                    || (previous.animationData == nil && animationData != nil)))
    }
}

/// Workout progress shared by iPhone and Watch. The anchor subtracts steps
/// already credited from Health or a recording, avoiding duplicate progress.
struct WorkoutEvolutionProgress: Codable, Equatable, Sendable {
    enum Milestone: String, Codable, Sendable {
        case hatch, evolve, mature, complete
    }
    let stageID: String
    var steps: Int
    let target: Int
    let totalCreditedSteps: Int
    let milestone: Milestone
    var allowsProgress = true
    var readyEventID: UUID?
    var bankedSteps: Int?

    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, Double(steps) / Double(target)))
    }
    var remaining: Int { max(0, target - max(0, steps)) }
    var caption: String {
        if milestone == .complete { return "Fully grown" }
        if remaining == 0 { return "Ready to \(milestone.rawValue)" }
        return "\(remaining.formatted()) to \(milestone.rawValue)"
    }
    var accessibilityValue: String {
        if milestone == .complete { return "Fully grown" }
        return "\(Int(fraction * 100)) percent. \(remaining.formatted()) steps to \(milestone.rawValue)."
    }

    func duringWorkout(steps workoutSteps: Int, anchor: WorkoutEvolutionAnchor?) -> Self {
        guard allowsProgress, milestone != .complete, let anchor else { return self }
        let pending = anchor.uncreditedSteps(recordedSteps: workoutSteps, totalCreditedSteps: totalCreditedSteps)
        var result = self
        result.steps = min(max(target, 0), max(steps, 0) + pending)
        return result
    }
}

struct WorkoutEvolutionAnchor: Codable, Sendable {
    let totalCreditedSteps: Int
    var workoutSteps = 0

    func uncreditedSteps(recordedSteps: Int, totalCreditedSteps currentCredits: Int) -> Int {
        let recorded = max(0, recordedSteps - workoutSteps)
        let alreadyCredited = max(0, currentCredits - totalCreditedSteps)
        return max(0, recorded - alreadyCredited)
    }
}

/// Daily Health totals are separate from a recording and never become workout data.
struct WatchDailyActivity: Sendable {
    let day: Date
    let steps: Int?
    let distanceMiles: Double?
    let activeCalories: Double?
    var exerciseMinutes: Double? = nil
    var weeklySteps: [WatchStepInterval] = []
    var hourlySteps: [WatchStepInterval] = []

    func isCurrent(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        calendar.isDate(day, inSameDayAs: date)
    }

    func goalProgress(target: Int?) -> Double? {
        guard let steps, let target, target > 0 else { return nil }
        return min(1, max(0, Double(steps) / Double(target)))
    }
}

struct WatchStepInterval: Identifiable, Sendable {
    var id: Date { start }
    let start: Date
    let end: Date
    let steps: Int?
}

struct WorkoutRecordedLocation: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let accuracy: Double
    let speed: Double
    let timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        accuracy = location.horizontalAccuracy
        speed = location.speed
        timestamp = location.timestamp
    }

    var location: CLLocation {
        CLLocation(coordinate: .init(latitude: latitude, longitude: longitude), altitude: altitude,
                   horizontalAccuracy: accuracy, verticalAccuracy: -1, course: -1, speed: speed, timestamp: timestamp)
    }
}

/// A bounded overlap lets a late-opening phone catch up without resending an
/// ever-growing workout through HealthKit's live mirroring channel.
struct WatchWorkoutRouteWindow: Codable, Sendable {
    let startIndex: Int
    let locations: [WorkoutRecordedLocation]
    let breakIndices: [Int]

    init(locations: [WorkoutRecordedLocation], breakIndices: [Int]) {
        let startIndex = max(0, locations.count - 24)
        self.startIndex = startIndex
        self.locations = Array(locations.suffix(24))
        self.breakIndices = breakIndices.filter { $0 >= startIndex }
    }
}

struct WatchWorkoutLiveRoute: Sendable {
    private(set) var sessionID: UUID?
    private(set) var locations: [WorkoutRecordedLocation] = []
    private(set) var breakIndices: [Int] = []
    private var nextIndex = 0
    private var sourceIndices: [Int] = []

    mutating func receive(_ snapshot: WatchWorkoutSnapshot) {
        if sessionID != snapshot.id {
            self = Self()
            sessionID = snapshot.id
        }
        guard !snapshot.indoor, snapshot.routeEnabled != false,
              let window = snapshot.liveRoute, window.startIndex >= 0 else { return }
        for (offset, point) in window.locations.enumerated() {
            let index = window.startIndex + offset
            guard index >= nextIndex else { continue }
            // Missing packets, pauses and invalid fixes must never clear a
            // straight line across territory that was not actually visited.
            let startsSegment = index > nextIndex || window.breakIndices.contains(index)
            guard CLLocationCoordinate2DIsValid(point.location.coordinate),
                  point.accuracy >= 0, point.accuracy <= 50 else { continue }
            if startsSegment, !locations.isEmpty { breakIndices.append(locations.count) }
            locations.append(point)
            sourceIndices.append(index)
            nextIndex = index + 1
        }
    }

    mutating func receiveFullRoute(_ result: WatchWorkoutResult) {
        guard sessionID == result.snapshot.id, !result.snapshot.indoor,
              result.snapshot.routeEnabled != false, !result.locations.isEmpty,
              result.locations.allSatisfy({ CLLocationCoordinate2DIsValid($0.location.coordinate)
                  && $0.accuracy >= 0 && $0.accuracy <= 50 }) else { return }
        let tailStart = sourceIndices.firstIndex { $0 >= result.locations.count } ?? locations.count
        let tail = Array(locations.dropFirst(tailStart))
        let tailIndices = Array(sourceIndices.dropFirst(tailStart))
        var mergedBreaks = result.breakIndices.filter { $0 > 0 && $0 < result.locations.count }
        if let first = tailIndices.first, first > result.locations.count {
            mergedBreaks.append(result.locations.count)
        }
        mergedBreaks += breakIndices.filter { $0 >= tailStart && $0 < locations.count }
            .map { result.locations.count + $0 - tailStart }
        locations = result.locations + tail
        sourceIndices = Array(result.locations.indices) + tailIndices
        breakIndices = Array(Set(mergedBreaks)).sorted()
        nextIndex = (sourceIndices.last ?? -1) + 1
    }
}

struct WatchWorkoutSnapshot: Codable, Sendable, Identifiable {
    enum Phase: String, Codable { case running, paused, saving, finished, failed }
    let id: UUID
    var workoutID: String
    var name: String
    var indoor: Bool
    var startedAt: Date
    var updatedAt: Date
    var elapsed: TimeInterval
    var steps: Int
    var distanceMiles: Double
    var calories: Double
    var heartRate: Double?
    var phase: Phase
    var healthWorkoutID: UUID?
    var error: String?
    var heartRateMeasuredAt: Date?
    // Optional for compatibility with already queued workouts and older companions.
    var routeEnabled: Bool?
    var automaticallyPaused: Bool?
    var milestoneStepMark: Int?
    var milestoneMileMark: Int?
    var lastMileElapsed: TimeInterval?
    var evolutionAnchor: WorkoutEvolutionAnchor?
    var liveRoute: WatchWorkoutRouteWindow?

    var hasRecordedActivity: Bool {
        WorkoutActivityPolicy.hasActivity(steps: steps, distanceMiles: distanceMiles, calories: calories)
    }

    var isActive: Bool { phase == .running || phase == .paused || phase == .saving }

    /// Completion is irreversible. Delayed packets from the live channel must
    /// not restart a stopped timer, even if they arrive with a later timestamp.
    func supersedes(_ previous: Self?) -> Bool {
        guard let previous else { return true }
        guard id == previous.id else { return startedAt > previous.startedAt }
        if !previous.isActive && isActive { return false }
        if previous.phase == .finished && phase == .failed { return false }
        if previous.phase == .saving && (phase == .running || phase == .paused) { return false }
        if previous.isActive && !isActive { return true }
        if previous.phase != .saving && phase == .saving { return true }
        if previous.phase == .failed && phase == .finished { return true }
        return updatedAt >= previous.updatedAt
    }

    func changingPhase(to phase: Phase, at date: Date) -> Self {
        var updated = self
        updated.elapsed = elapsed(at: date)
        updated.updatedAt = date
        updated.phase = phase
        return updated
    }

    /// Interpolate only the visible clock between authoritative HealthKit updates.
    func elapsed(at date: Date) -> TimeInterval {
        max(0, elapsed) + (phase == .running ? max(0, date.timeIntervalSince(updatedAt)) : 0)
    }

    func currentHeartRate(at date: Date) -> Double? {
        guard let heartRate, heartRate.isFinite, heartRate > 0 else { return nil }
        if !isActive { return heartRate }
        guard let heartRateMeasuredAt, date.timeIntervalSince(heartRateMeasuredAt) <= 30 else { return nil }
        return heartRate
    }
}

enum WorkoutMetricsFormat {
    static func time(_ elapsed: TimeInterval, subseconds: Bool = false) -> String {
        let safe = elapsed.isFinite ? max(0, elapsed) : 0
        let whole = Int(safe)
        let main = whole >= 3600
            ? String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
            : String(format: "%02d:%02d", whole / 60, whole % 60)
        return subseconds ? main + String(format: ".%02d", Int((safe * 100 + 0.0000001).rounded(.down)) % 100) : main
    }

    static func pace(elapsed: TimeInterval, miles: Double) -> String {
        guard elapsed.isFinite, miles.isFinite, elapsed > 0, miles >= 0.01 else { return "—′—″" }
        let seconds = Int((elapsed / miles).rounded())
        return String(format: "%d′%02d″", seconds / 60, seconds % 60)
    }

    static func distance(_ miles: Double) -> (value: String, unit: String) {
        let safe = miles.isFinite ? max(0, miles) : 0
        return safe < 0.1 ? ("\(Int((safe * 5280).rounded()))", "FT")
            : (String(format: "%.2f", safe), "MI")
    }
}

struct WatchWorkoutResult: Codable {
    let snapshot: WatchWorkoutSnapshot
    let locations: [WorkoutRecordedLocation]
    let breakIndices: [Int]
}


/// Finish requests are scoped to a recording, so a retry cannot stop a new walk.
struct WatchWorkoutFinishRequest: Codable {
    static let messageKey = "nanobeasts.workout.finish.v1"
    static let snapshotKey = "nanobeasts.workout.snapshot.v1"
    let sessionID: UUID
    let requestedAt: Date
    var displayElapsed: TimeInterval? = nil

    func applies(to snapshot: WatchWorkoutSnapshot?) -> Bool {
        snapshot?.id == sessionID
    }

    func displaySnapshot(_ snapshot: WatchWorkoutSnapshot) -> WatchWorkoutSnapshot {
        guard applies(to: snapshot), snapshot.phase == .running || snapshot.phase == .paused else { return snapshot }
        var display = snapshot.changingPhase(to: .saving, at: requestedAt)
        display.elapsed = displayElapsed ?? display.elapsed
        return display
    }
}
