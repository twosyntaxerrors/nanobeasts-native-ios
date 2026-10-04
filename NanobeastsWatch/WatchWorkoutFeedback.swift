import Foundation

/// Each bar covers one existing 1,000-step workout milestone, independent of alerts.
/// Crossing a milestone starts the next interval; this is not daily or evolution progress.
struct WatchStepProgress {
    let steps: Int
    init(steps: Int) { self.steps = max(0, steps) }
    var remaining: Int { 1_000 - steps % 1_000 }
    var target: Int { steps + remaining }
    var fraction: Double { Double(steps % 1_000) / 1_000 }
}

/// Uses positive motion evidence; missing GPS or delayed step samples never mean "stopped".
struct WatchAutoPausePolicy {
    enum Motion { case stationary, moving, unknown }
    enum Action { case pause, resume }
    private var motion = Motion.unknown
    private var since: Date?
    private var lastObservation = Date.distantPast

    mutating func observe(_ value: Motion, at date: Date) {
        guard date >= lastObservation else { return }
        lastObservation = date
        if value != motion { since = date; motion = value }
    }

    mutating func reset() { self = Self() }

    func action(at date: Date, running: Bool, automaticallyPaused: Bool) -> Action? {
        guard let since else { return nil }
        if running, motion == .stationary, date.timeIntervalSince(since) >= 15 { return .pause }
        if !running, automaticallyPaused, motion == .moving, date.timeIntervalSince(since) >= 3 { return .resume }
        return nil
    }
}

struct WatchWorkoutMilestone: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
}

/// High-water marks prevent repeated alerts after pauses, delayed data, or recovery.
struct WatchMilestonePolicy {
    var stepMark = 0
    var mileMark = 0
    var lastMileElapsed: TimeInterval = 0
    var previousMiles: Double = 0
    var previousElapsed: TimeInterval = 0

    mutating func update(steps: Int, miles: Double, elapsed: TimeInterval) -> [WatchWorkoutMilestone] {
        guard miles.isFinite, elapsed.isFinite, miles >= 0, elapsed >= 0 else { return [] }
        var events: [WatchWorkoutMilestone] = []
        let newStepMark = max(0, steps) / 1_000
        if newStepMark > stepMark {
            stepMark = newStepMark
            events.append(.init(id: "steps-\(stepMark)", title: "\((stepMark * 1_000).formatted()) steps!",
                                detail: "Keep going!", symbol: "shoeprints.fill"))
        }
        let newMileMark = Int(miles.rounded(.down))
        if newMileMark > mileMark {
            // Interpolate the crossing between real distance samples, using active time only.
            // A batch spanning several miles produces one catch-up alert for the latest mile.
            let delta = miles - previousMiles
            var latestSplit: TimeInterval = 0
            for mile in (mileMark + 1)...newMileMark {
                let fraction = delta > 0 ? min(1, max(0, (Double(mile) - previousMiles) / delta)) : 1
                let crossing = previousElapsed + fraction * max(0, elapsed - previousElapsed)
                latestSplit = max(0, crossing - lastMileElapsed)
                lastMileElapsed = crossing
            }
            mileMark = newMileMark
            events.append(.init(id: "mile-\(mileMark)", title: "Mile \(mileMark)!",
                                detail: "Split \(WorkoutMetricsFormat.time(latestSplit)) /mi", symbol: "flag.checkered"))
        }
        if miles >= previousMiles {
            previousMiles = miles
            previousElapsed = elapsed
        }
        return events
    }
}
