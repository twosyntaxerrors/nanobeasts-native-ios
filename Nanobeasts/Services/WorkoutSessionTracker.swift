import Combine
import CoreMotion
import Foundation
import HealthKit
import UIKit

@MainActor
final class WorkoutSessionTracker: ObservableObject {
    static let shared = WorkoutSessionTracker()

    @Published private(set) var steps = 0
    @Published private(set) var motionDistanceMiles = 0.0
    @Published private(set) var healthAuthorizationReady = false
    @Published private(set) var saveError: String?
    @Published private(set) var savedToHealth = false

    private let pedometer = CMPedometer()
    private let healthStore = HKHealthStore()
    private var ledger: WorkoutMotionLedger?
    private var latestSessionID: UUID?
    private let queryPedometer = CMPedometer()
    private var workoutStart: Date? { ledger?.startedAt }
    private var events: [HKWorkoutEvent] = []
    private var lifecycleObservers: [NSObjectProtocol] = []
    /// iOS 26 workout session used only for background runtime, so step
    /// callbacks and the Live Activity keep flowing while the phone is locked.
    /// It never saves samples; `stopAndSave` still owns the Health export.
    private var runtimeSession: AnyObject?
    private static let recoveryKey = "nanobeasts.phone-workout.motion.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.recoveryKey),
           let saved = try? JSONDecoder().decode(WorkoutMotionLedger.self, from: data) {
            ledger = saved
            latestSessionID = saved.id
            publishMotion()
            if let segment = saved.segments.last, segment.end == nil { startLiveUpdates(segment: segment) }
            startRuntimeSession()
        }
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.reconcileMotion() }
        })
    }
    var elapsedSeconds: Int {
        Int(ledger?.elapsed(at: Date()) ?? 0)
    }

    var motionAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    func requestWorkoutAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workout = HKObjectType.workoutType()
        let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        let walkingDistance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)
        let steps = HKObjectType.quantityType(forIdentifier: .stepCount)
        let cyclingDistance = HKObjectType.quantityType(forIdentifier: .distanceCycling)
        let route = HKSeriesType.workoutRoute()
        let share = Set([workout, energy, walkingDistance, cyclingDistance, route].compactMap { $0 })
        let read = Set([workout, energy, walkingDistance, cyclingDistance, steps].compactMap { $0 })

        do {
            let granted = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Bool, Error>) in
                healthStore.requestAuthorization(toShare: share, read: read) { success, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: success) }
                }
            }
            healthAuthorizationReady = granted
        } catch {
            saveError = error.localizedDescription
        }
    }

    func start() {
        pedometer.stopUpdates()
        let now = Date()
        ledger = WorkoutMotionLedger(startedAt: now)
        ledger?.resume(at: now)
        latestSessionID = ledger?.id
        events = []
        savedToHealth = false
        saveError = nil
        publishMotion()
        if let segment = ledger?.segments.last { startLiveUpdates(segment: segment) }
        startRuntimeSession()
    }

    func restore(startedAt: Date, steps: Int, distanceMiles: Double,
                 isPaused: Bool, elapsed: TimeInterval? = nil) {
        // Keep the original intervals across view recreation/process recovery.
        // Never count a pause, or restart the counter at the foreground timestamp.
        if let ledger, abs(ledger.startedAt.timeIntervalSince(startedAt)) < 10 {
            if isPaused { pause() }
            else if ledger.segments.isEmpty || ledger.segments.last?.end != nil { resume() }
            startRuntimeSession()
            publishMotion()
            Task { await reconcileMotion() }
            return
        }
        pedometer.stopUpdates()
        ledger = WorkoutMotionLedger(startedAt: startedAt, baselineSteps: max(0, steps),
            baselineMeters: max(0, distanceMiles) * 1_609.344,
            baselineDuration: max(0, elapsed ?? Date().timeIntervalSince(startedAt)))
        latestSessionID = ledger?.id
        if !isPaused { ledger?.resume(at: Date()) }
        events = []
        savedToHealth = false
        saveError = nil
        publishMotion()
        if let segment = ledger?.segments.last, segment.end == nil { startLiveUpdates(segment: segment) }
        startRuntimeSession()
    }

    func pause() {
        guard ledger?.segments.last?.end == nil, ledger?.segments.isEmpty == false else { return }
        let now = Date()
        ledger?.pause(at: now)
        pedometer.stopUpdates()
        events.append(HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: now, duration: 0), metadata: nil))
        publishMotion()
        Task { await reconcileMotion() }
    }

    func resume() {
        guard let current = ledger, current.segments.isEmpty || current.segments.last?.end != nil else { return }
        let now = Date()
        ledger?.resume(at: now)
        events.append(HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: now, duration: 0), metadata: nil))
        publishMotion()
        if let segment = ledger?.segments.last { startLiveUpdates(segment: segment) }
    }

    /// Core Motion keeps recording while app callbacks are suspended. Query each
    /// active interval, replacing its cumulative total instead of adding it twice.
    func reconcileMotion() async {
        guard motionAvailable, let snapshot = ledger else { return }
        let now = Date()
        for segment in snapshot.segments {
            let end = segment.end ?? now
            guard end > segment.start, segment.start > now.addingTimeInterval(-7 * 86_400) else { continue }
            let data = await Self.queryMotion(from: segment.start, to: end, using: queryPedometer)
            guard ledger?.id == snapshot.id else { return }
            guard let data else { continue }
            ledger?.update(segmentID: segment.id, through: end,
                steps: data.numberOfSteps.intValue, meters: data.distance?.doubleValue ?? 0)
        }
        guard ledger?.id == snapshot.id else { return }
        publishMotion()
    }

    static func queryMotion(from start: Date, to end: Date, using pedometer: CMPedometer) async -> CMPedometerData? {
        await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    func finishMotion() async {
        pause()
        await reconcileMotion()
    }

    func activeIntervals(endingAt end: Date) -> [DateInterval]? {
        guard let ledger, ledger.baselineDuration == 0 else { return nil }
        return ledger.segments.compactMap { segment in
            let stop = min(segment.end ?? end, end)
            return stop > segment.start ? DateInterval(start: segment.start, end: stop) : nil
        }
    }

    /// Snapshot before awaiting Health so a new workout cannot replace the
    /// previous session's dates/events while its export is being saved.
    func detachCompletedSession() -> WorkoutMotionLedger? {
        let completed = ledger
        pedometer.stopUpdates()
        endRuntimeSession()
        ledger = nil
        UserDefaults.standard.removeObject(forKey: Self.recoveryKey)
        return completed
    }

    func stopAndSave(
        session: WorkoutMotionLedger?,
        workoutID: String,
        indoor: Bool,
        distanceMiles: Double,
        calories: Double,
        historyRecordID: UUID? = nil,
        healthTotals: WorkoutHealthTotals? = nil,
        locations: [WorkoutRecordedLocation] = [],
        routeBreaks: [Int] = [],
        finishedAt: Date? = nil
    ) async -> UUID? {
        guard let session else { return nil }
        let workoutStart = session.startedAt
        guard WorkoutActivityPolicy.hasActivity(steps: session.steps, distanceMiles: distanceMiles, calories: calories) else { return nil }
        guard UserDefaults.standard.object(forKey: "nanobeasts.workouts.saveToHealth") as? Bool ?? true else {
            if latestSessionID == session.id { saveError = "Saved in Nanobeasts. Apple Health saving is turned off." }
            return nil
        }
        guard healthAuthorizationReady else { return nil }

        let end = finishedAt ?? Date()
        let workoutEvents = (session.segments.enumerated().flatMap { index, segment -> [HKWorkoutEvent] in
            var result: [HKWorkoutEvent] = []
            if index > 0 {
                result.append(HKWorkoutEvent(type: .resume,
                    dateInterval: DateInterval(start: segment.start, duration: 0), metadata: nil))
            }
            if let stop = segment.end, stop < end {
                result.append(HKWorkoutEvent(type: .pause,
                    dateInterval: DateInterval(start: stop, duration: 0), metadata: nil))
            }
            return result
        }).filter { $0.dateInterval.start >= workoutStart && $0.dateInterval.start <= end }
        let activityType: HKWorkoutActivityType = switch workoutID {
        case "outdoor-run", "indoor-run": .running
        case "hiit": .highIntensityIntervalTraining
        case "cycling": .cycling
        case "hiking", "nordic-walk": .hiking
        case "elliptical": .elliptical
        case "stair-stepper": .stairClimbing
        default: .walking
        }

        do {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = activityType
            configuration.locationType = indoor ? .indoor : .outdoor
            let builder = HKWorkoutBuilder(
                healthStore: healthStore,
                configuration: configuration,
                device: .local()
            )
            try await builder.beginCollection(at: workoutStart)
            if !workoutEvents.isEmpty { try await builder.addWorkoutEvents(workoutEvents) }

            var samples: [HKSample] = []
            if let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
                samples.append(
                    HKQuantitySample(
                        type: energyType,
                        quantity: HKQuantity(unit: .kilocalorie(), doubleValue: max(0, calories)),
                        start: workoutStart,
                        end: end
                    )
                )
            }
            let distanceIdentifier: HKQuantityTypeIdentifier = activityType == .cycling
                ? .distanceCycling
                : .distanceWalkingRunning
            if let distanceType = HKObjectType.quantityType(forIdentifier: distanceIdentifier) {
                samples.append(
                    HKQuantitySample(
                        type: distanceType,
                        quantity: HKQuantity(unit: .mile(), doubleValue: max(0, distanceMiles)),
                        start: workoutStart,
                        end: end
                    )
                )
            }
            if !samples.isEmpty {
                try await add(samples, to: builder)
            }
            var metadata: [String: Any] = [HKMetadataKeyIndoorWorkout: indoor]
            metadata["NanobeastsMetricsSource"] = healthTotals?.hasValues == true ? "Apple Health" : "Device estimates"
            if let historyRecordID {
                metadata["NanobeastsWorkoutRecordID"] = historyRecordID.uuidString
            }
            try await builder.addMetadata(metadata)
            try await builder.endCollection(at: end)
            guard let savedWorkout = try await builder.finishWorkout() else {
                throw WorkoutSessionSaveError.failed
            }
            if latestSessionID == session.id { savedToHealth = true }
            do {
                try await WorkoutHealthRouteWriter.save(locations, breaks: routeBreaks, workout: savedWorkout, store: healthStore)
            } catch {
                if latestSessionID == session.id { saveError = "Workout saved to Health. Its route remains in Nanobeasts but could not be added to Health." }
            }
            return savedWorkout.uuid
        } catch {
            if latestSessionID == session.id { saveError = error.localizedDescription }
            return nil
        }
    }

    func cancel() {
        pedometer.stopUpdates()
        ledger = nil
        events = []
        UserDefaults.standard.removeObject(forKey: Self.recoveryKey)
        steps = 0
        motionDistanceMiles = 0
        savedToHealth = false
        saveError = nil
    }

    private func startLiveUpdates(segment: WorkoutMotionLedger.Segment) {
        guard motionAvailable, let sessionID = ledger?.id else { return }
        pedometer.startUpdates(from: segment.start) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor in
                guard let self, self.ledger?.id == sessionID else { return }
                self.ledger?.update(segmentID: segment.id, through: data.endDate,
                    steps: data.numberOfSteps.intValue, meters: data.distance?.doubleValue ?? 0)
                self.publishMotion()
            }
        }
    }

    private func publishMotion() {
        guard let ledger else { return }
        steps = ledger.steps
        motionDistanceMiles = ledger.meters / 1_609.344
        if let data = try? JSONEncoder().encode(ledger) {
            UserDefaults.standard.set(data, forKey: Self.recoveryKey)
        }
    }

    private func startRuntimeSession() {
        guard #available(iOS 26.0, *), runtimeSession == nil, HKHealthStore.isHealthDataAvailable() else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .unknown
        guard let session = try? HKWorkoutSession(healthStore: healthStore, configuration: configuration) else { return }
        session.startActivity(with: Date())
        runtimeSession = session
    }

    private func endRuntimeSession() {
        guard #available(iOS 26.0, *), let session = runtimeSession as? HKWorkoutSession else { return }
        session.end()
        runtimeSession = nil
    }

    private func add(_ samples: [HKSample], to builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            builder.add(samples) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: WorkoutSessionSaveError.failed) }
            }
        }
    }

}

private enum WorkoutSessionSaveError: LocalizedError {
    case failed

    var errorDescription: String? {
        "The workout could not be saved to Apple Health."
    }
}

/// Cumulative motion totals belong to an active interval, not a UI lifetime.
/// Pure value model so background, pause, stale callback and recovery cases can be tested.
struct WorkoutMotionLedger: Codable {
    struct Segment: Codable {
        var id = UUID()
        let start: Date
        var end: Date?
        var steps = 0
        var meters = 0.0
    }
    var id = UUID()
    let startedAt: Date
    var baselineSteps = 0
    var baselineMeters = 0.0
    var baselineDuration: TimeInterval = 0
    var segments: [Segment] = []

    var steps: Int { baselineSteps + segments.reduce(0) { $0 + $1.steps } }
    var meters: Double { baselineMeters + segments.reduce(0) { $0 + $1.meters } }
    func elapsed(at date: Date) -> TimeInterval {
        baselineDuration + segments.reduce(0) { $0 + max(0, ($1.end ?? date).timeIntervalSince($1.start)) }
    }
    mutating func resume(at date: Date) {
        guard segments.isEmpty || segments.last?.end != nil else { return }
        segments.append(Segment(start: date))
    }
    mutating func pause(at date: Date) {
        guard let index = segments.indices.last, segments[index].end == nil else { return }
        segments[index].end = max(segments[index].start, date)
    }
    mutating func update(segmentID: UUID, through date: Date, steps: Int, meters: Double) {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }),
              date >= segments[index].start,
              date <= (segments[index].end ?? .distantFuture) else { return }
        segments[index].steps = max(segments[index].steps, steps)
        if meters.isFinite { segments[index].meters = max(segments[index].meters, meters) }
    }
}
