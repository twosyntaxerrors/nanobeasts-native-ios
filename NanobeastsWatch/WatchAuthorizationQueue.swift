import Foundation

/// Home and workout setup may overlap while a system sheet is open. Serialize
/// requests and discard cancelled requests before they can present another sheet.
@MainActor
final class WatchAuthorizationQueue {
    static let shared = WatchAuthorizationQueue()
    private var pending: Task<Void, Error>?
    private var latestID: UUID?

    func perform(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let previous = pending
        let id = UUID()
        let task = Task { @MainActor in
            if let previous { _ = try? await previous.value }
            try Task.checkCancellation()
            try await operation()
        }
        pending = task
        latestID = id
        defer {
            if latestID == id { pending = nil; latestID = nil }
        }
        try await withTaskCancellationHandler {
            try await task.value
            try Task.checkCancellation()
        } onCancel: {
            task.cancel()
        }
    }
}
