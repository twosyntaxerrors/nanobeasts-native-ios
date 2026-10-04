import CoreLocation
import Foundation

@main
struct WatchPermissionChecks {
    @MainActor
    static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        let allowed = WatchLocationAccess(status: .authorizedWhenInUse, accuracy: .fullAccuracy)
        check(!allowed.needsAuthorization, "Previously accepted When In Use never requests permission again")
        check(allowed.canRecordRoute, "Persistent When In Use is sufficient; Always is not required")
        check(allowed.shouldResumeRoute(running: true, indoor: false, routeEnabled: true, saving: false),
              "Returning to a running outdoor workout restores an interrupted GPS stream")
        check(!allowed.shouldResumeRoute(running: false, indoor: false, routeEnabled: true, saving: false),
              "Foreground return cannot restart GPS for a paused or finished workout")
        check(!allowed.shouldResumeRoute(running: true, indoor: true, routeEnabled: true, saving: false), "Indoor workout never records a route")
        check(!allowed.shouldResumeRoute(running: true, indoor: false, routeEnabled: false, saving: false), "Saved route-off choice is respected")
        check(!allowed.shouldResumeRoute(running: true, indoor: false, routeEnabled: true, saving: true), "Saving never restarts route capture")
        check(allowed.notice == nil, "Allowed location does not display a re-enable warning")
        let reduced = WatchLocationAccess(status: .authorizedWhenInUse, accuracy: .reducedAccuracy)
        check(!reduced.needsAuthorization && !reduced.canRecordRoute, "Reduced precision is not missing location authorization")
        check(reduced.notice?.contains("Precise Location") == true, "Reduced precision has its own explanation")
        for status: CLAuthorizationStatus in [.denied, .restricted] {
            let access = WatchLocationAccess(status: status, accuracy: .fullAccuracy)
            check(!access.needsAuthorization && !access.canRecordRoute, "Denied/restricted authorization cannot re-prompt or restart GPS")
        }
        let undetermined = WatchLocationAccess(status: .notDetermined, accuracy: .fullAccuracy)
        check(undetermined.needsAuthorization && !undetermined.canRecordRoute,
              "A real first request or expired Allow Once still requires system permission")

        let queue = WatchAuthorizationQueue()
        var events: [String] = []
        var firstRelease: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            try await queue.perform {
                events.append("home started")
                await withCheckedContinuation { firstRelease = $0 }
                events.append("home finished")
            }
        }
        while firstRelease == nil { await Task.yield() }
        let second = Task { @MainActor in
            try await queue.perform { events.append("workout started") }
        }
        for _ in 0..<10 { await Task.yield() }
        check(events == ["home started"], "Workout permission sheet waits for the existing home sheet")
        firstRelease?.resume()
        try await first.value
        try await second.value
        check(events == ["home started", "home finished", "workout started"], "Health sheets are serialized in arrival order")

        var blockerRelease: CheckedContinuation<Void, Never>?
        let blocker = Task { @MainActor in
            try await queue.perform { await withCheckedContinuation { blockerRelease = $0 } }
        }
        while blockerRelease == nil { await Task.yield() }
        var cancelledSheetAppeared = false
        let cancelled = Task { @MainActor in
            try await queue.perform { cancelledSheetAppeared = true }
        }
        for _ in 0..<10 { await Task.yield() }
        cancelled.cancel()
        blockerRelease?.resume()
        try await blocker.value
        do { try await cancelled.value; preconditionFailure("Cancelled request must report cancellation") }
        catch is CancellationError {}
        check(!cancelledSheetAppeared, "Leaving a screen prevents its queued permission request appearing later")
        var subsequentRequestRan = false
        try await queue.perform { subsequentRequestRan = true }
        check(subsequentRequestRan, "Cancelled setup cannot block a subsequent explicit request")
        print("Passed \(checks) watch permission checks")
    }
}
