#!/usr/bin/env python3
"""Exercise production Live Activity orchestration using a deterministic ActivityKit double.

Runs on macOS; does not build, install, launch, or change app/device data.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
controller = (root / 'Nanobeasts/Services/WorkoutLiveActivityController.swift').read_text()
controller = controller[controller.index('@MainActor\nfinal class WorkoutLiveActivityController'):]
attributes = (root / 'NanobeastsShared/WorkoutActivityAttributes.swift').read_text()
attributes = attributes[attributes.index('struct WorkoutActivityAttributes:'):attributes.index('struct WorkoutActivityCommand:')]
bridge = (root / 'Nanobeasts/Services/WorkoutWatchBridge.swift').read_text()
mapping = bridge[bridge.index('extension WatchWorkoutSnapshot {'):]
messages = (root / 'NanobeastsShared/WatchWorkoutMessage.swift').read_text()
stubs = r'''
import Foundation
import Combine
import OSLog
protocol ActivityAttributes {}
enum ActivityState { case active, stale, ended, dismissed }
struct ActivityContent<S> { var state: S; var staleDate: Date? }
enum DismissalPolicy { case immediate; case after(Date) }
@MainActor enum ActivityRegistry {
    static var entries: [Activity<WorkoutActivityAttributes>] = []
    static var allowed = true
    static var failRequest = false
}
@MainActor struct ActivityAuthorizationInfo {
    var areActivitiesEnabled: Bool { ActivityRegistry.allowed }
}
@MainActor final class Activity<A> {
    let attributes: WorkoutActivityAttributes
    var content: ActivityContent<WorkoutActivityAttributes.ContentState>
    var activityState = ActivityState.active
    init(_ attributes: WorkoutActivityAttributes, _ content: ActivityContent<WorkoutActivityAttributes.ContentState>) {
        self.attributes = attributes; self.content = content
    }
    static var activities: [Activity<WorkoutActivityAttributes>] { ActivityRegistry.entries }
    static func request(attributes: A,
                        content: ActivityContent<WorkoutActivityAttributes.ContentState>, pushType: String?) throws -> Activity<WorkoutActivityAttributes> {
        if ActivityRegistry.failRequest { throw NSError(domain: "Test", code: 1) }
        let activity = Activity<WorkoutActivityAttributes>(attributes as! WorkoutActivityAttributes, content)
        ActivityRegistry.entries.append(activity)
        return activity
    }
    func update(_ content: ActivityContent<WorkoutActivityAttributes.ContentState>) async { self.content = content }
    func end(_ content: ActivityContent<WorkoutActivityAttributes.ContentState>?, dismissalPolicy: DismissalPolicy) async {
        if let content { self.content = content }; activityState = .ended
    }
}
@MainActor final class UIApplication {
    enum State { case active, background }
    static let shared = UIApplication()
    static let didBecomeActiveNotification = Notification.Name("TestForeground")
    var applicationState = State.active
}
enum WorkoutActivityCommandStore {
    struct Command { let sessionID: String }
    static func load() -> Command? { nil }
    static func clear() {}
}
'''
checks = r'''
@main struct Checks {
    @MainActor static func main() async {
        var count = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message); count += 1
        }
        let sampleDate = Date(timeIntervalSince1970: 1000)
        var sample = WatchWorkoutSnapshot(id: UUID(), workoutID: "outdoor-walk", name: "Outdoor Walk",
            indoor: false, startedAt: sampleDate.addingTimeInterval(-120), updatedAt: sampleDate,
            elapsed: 120, steps: 220, distanceMiles: 0.12, calories: 14, phase: .running)
        let initial = sample.workoutActivityState
        expect(initial.timerAnchor == sampleDate.addingTimeInterval(-120), "Watch timer uses the measurement date")
        expect(initial.steps == 220 && initial.calories == 14 && !initial.isPaused, "Watch metrics are authoritative")
        sample.phase = .paused
        expect(sample.workoutActivityState.isPaused && !sample.workoutActivityState.isComplete, "Pause keeps activity alive")
        sample.phase = .saving
        expect(sample.workoutActivityState.isPaused && !sample.workoutActivityState.isComplete, "Saving freezes the timer")
        sample.phase = .finished
        let final = sample.workoutActivityState
        expect(final.isComplete, "Finish ends the activity")
        let phone = WorkoutLiveActivityController()
        let watch = WorkoutLiveActivityController()
        func start(_ controller: WorkoutLiveActivityController, _ id: String, _ source: String) async {
            await controller.start(workoutID: "outdoor-walk", workoutName: "Outdoor Walk", symbolName: "figure.walk",
                indoor: false, goalDescription: "Open", goalKind: "Open Goal", goalTarget: nil, companionID: "egg",
                sessionID: id, workoutSource: source, state: initial)
        }
        await start(phone, "phone", "phone")
        let phoneActivity = ActivityRegistry.entries[0]
        expect(phone.sessionID == "phone" && phoneActivity.activityState == .active, "Foreground phone start")
        UIApplication.shared.applicationState = .background
        await start(watch, "watch-session", "watch")
        expect(ActivityRegistry.entries.count == 1 && watch.startFailure != nil, "Background start is deferred without crashing")
        var updated = initial; updated.steps = 330
        await watch.update(updated)
        UIApplication.shared.applicationState = .active
        await watch.update(updated)
        let watchActivity = ActivityRegistry.entries[1]
        expect(watchActivity.content.state.steps == 330, "Retry uses newest metrics")
        expect(phoneActivity.activityState == .active, "Watch start never ends phone activity")
        let restored = WorkoutLiveActivityController()
        expect(restored.restore(sessionID: "watch-session") != nil, "Reattach by stable session ID")
        await restored.update(updated)
        expect(ActivityRegistry.entries.count == 2, "Restore and updates don't duplicate activities")
        watchActivity.activityState = .dismissed
        await watch.update(updated)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()
        expect(ActivityRegistry.entries.count == 2, "User dismissal is respected")
        await phone.end(with: final)
        expect(phoneActivity.activityState == .ended && phone.sessionID == nil, "Completion clears session")
        let abandoned = WorkoutLiveActivityController()
        UIApplication.shared.applicationState = .background
        await start(abandoned, "ended-before-unlock", "watch")
        await abandoned.end(with: final)
        UIApplication.shared.applicationState = .active
        await abandoned.update(final)
        expect(ActivityRegistry.entries.count == 2, "Finished deferred request cannot reappear")
        ActivityRegistry.allowed = false
        let denied = WorkoutLiveActivityController()
        await start(denied, "denied", "phone")
        expect(denied.startFailure != nil && denied.sessionID == "denied", "Disabled activities preserve recording identity")
        ActivityRegistry.allowed = true
        ActivityRegistry.failRequest = true
        await denied.update(initial)
        expect(denied.startFailure != nil, "Request errors are recoverable")
        ActivityRegistry.failRequest = false
        await denied.update(initial)
        expect(denied.startFailure == nil && ActivityRegistry.entries.count == 3, "Retry after request failure")
        let encoded = try! JSONEncoder().encode(watchActivity.attributes)
        var legacy = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "workoutSource")
        let decoded = try! JSONDecoder().decode(WorkoutActivityAttributes.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        expect(decoded.workoutSource == nil, "Existing activities decode without source field")
        print("PASS: \(count) Live Activity lifecycle, Watch payload, recovery and compatibility checks")
    }
}
'''
# Real ActivityAttributes supplies Codable/Hashable via the SDK protocol.
attributes = attributes.replace(': ActivityAttributes {', ': ActivityAttributes, Codable {')
with tempfile.TemporaryDirectory(prefix='nano-live-activity-checks-') as temp:
    temp = Path(temp)
    source = temp / 'Checks.swift'
    source.write_text(stubs + attributes + messages + controller + mapping + checks)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path',
                    str(temp / 'ModuleCache'), str(source), '-o', str(temp / 'checks')], check=True)
    subprocess.run([str(temp / 'checks')], check=True)
