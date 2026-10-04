import ActivityKit
import AppIntents
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var timerAnchor: Date
        var elapsedSeconds: Int
        var steps: Int
        var distanceMiles: Double
        var calories: Int
        var goalProgress: Double
        var isPaused: Bool
        var goalReached: Bool
        var isComplete: Bool
    }

    let sessionID: String
    let workoutName: String
    let symbolName: String
    let goalDescription: String
    let workoutID: String?
    let indoor: Bool?
    let goalKind: String?
    let goalTarget: Double?
    let companionID: String?
    var workoutSource: String? = nil
}

struct WorkoutActivityCommand: Codable, Hashable {
    let token: String
    let sessionID: String
    let isPaused: Bool
}

enum WorkoutActivityCommandStore {
    private static let appGroupID = "group.com.twosyntaxerrors.nanobeasts.native"
    private static let commandKey = "nanobeasts.workout.live-activity-command.v1"

    static func save(sessionID: String, isPaused: Bool) {
        let command = WorkoutActivityCommand(
            token: UUID().uuidString,
            sessionID: sessionID,
            isPaused: isPaused
        )
        guard let data = try? JSONEncoder().encode(command) else { return }
        UserDefaults(suiteName: appGroupID)?.set(data, forKey: commandKey)
    }

    static func load() -> WorkoutActivityCommand? {
        guard
            let data = UserDefaults(suiteName: appGroupID)?.data(forKey: commandKey),
            let command = try? JSONDecoder().decode(WorkoutActivityCommand.self, from: data)
        else {
            return nil
        }
        return command
    }

    static func clear() {
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: commandKey)
    }
}

struct ToggleWorkoutActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Workout"
    static let description = IntentDescription(
        "Pauses or resumes the active Nanobeasts workout from the Lock Screen."
    )

    @Parameter(title: "Session ID")
    var sessionID: String

    @Parameter(title: "Pause Workout")
    var shouldPause: Bool

    init() {}

    init(sessionID: String, shouldPause: Bool) {
        self.sessionID = sessionID
        self.shouldPause = shouldPause
    }

    func perform() async throws -> some IntentResult {
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(
            where: { $0.attributes.sessionID == sessionID }
        ) else {
            return .result()
        }

        var state = activity.content.state
        guard !state.isComplete, activity.attributes.workoutSource != "watch" else { return .result() }
        let now = Date()

        if shouldPause, !state.isPaused {
            state.elapsedSeconds = max(
                state.elapsedSeconds,
                Int(now.timeIntervalSince(state.timerAnchor))
            )
            state.isPaused = true
        } else if !shouldPause, state.isPaused {
            state.timerAnchor = now.addingTimeInterval(-Double(state.elapsedSeconds))
            state.isPaused = false
        }

        WorkoutActivityCommandStore.save(sessionID: sessionID, isPaused: state.isPaused)
        await activity.update(
            ActivityContent(
                state: state,
                staleDate: now.addingTimeInterval(90)
            )
        )
        return .result()
    }
}
