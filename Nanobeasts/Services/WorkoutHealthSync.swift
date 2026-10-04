import Foundation
import HealthKit

@MainActor
final class WorkoutHealthSync {
    static let shared = WorkoutHealthSync()
    private let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []
    private var refreshing = false
    private var refreshAgain = false
    static let enabledKey = "nanobeasts.workouts.healthSyncEnabled"

    func start() {
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            let history = WorkoutHistoryStore().workouts
            if history.contains(where: { $0.source == .appleHealth }) {
                UserDefaults.standard.set(true, forKey: Self.enabledKey)
            }
        }
        guard observers.isEmpty, UserDefaults.standard.bool(forKey: Self.enabledKey), HKHealthStore.isHealthDataAvailable() else { return }
        let types: [HKSampleType] = [HKObjectType.workoutType(), HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.activeEnergyBurned)]
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor in
                    await self?.refresh()
                    completion()
                }
            }
            observers.append(query)
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    func refresh() async {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true
        repeat {
            refreshAgain = false
            await WorkoutHistoryStore().importFromAppleHealth(requestAccess: false, forceHealthTotals: true)
        } while refreshAgain
        refreshing = false
    }
}

/// Health is authoritative for completed sessions. Reads never manufacture
/// quantity samples or include this phone app's own exported estimates.
@MainActor
final class WorkoutHealthTotalsReader {
    static let shared = WorkoutHealthTotalsReader()
    struct Result {
        var totals = WorkoutHealthTotals()
        var intervals: [DateInterval]?
    }
    private let store = HKHealthStore()
    private var inFlight: [UUID: Task<Result, Error>] = [:]

    func read(_ record: WorkoutHistoryRecord) async throws -> Result {
        if let task = inFlight[record.id] { return try await task.value }
        let task = Task { try await self.load(record) }
        inFlight[record.id] = task
        defer { inFlight[record.id] = nil }
        return try await task.value
    }

    private func load(_ record: WorkoutHistoryRecord) async throws -> Result {
        let ids = Set((record.healthWorkoutIDs ?? []) + (record.source == .appleHealth ? [record.id] : []))
        var linked: [HKWorkout] = []
        if !ids.isEmpty {
            linked = try await samples(type: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForObjects(with: ids)).compactMap { $0 as? HKWorkout }
        }
        let phoneBundle = Bundle.main.bundleIdentifier ?? "com.twosyntaxerrors.nanobeasts.native"
        // An actual Watch/third-party Health workout wins over our phone export.
        let workout = linked.sorted {
            let leftIsPhone = $0.sourceRevision.source.bundleIdentifier == phoneBundle
            let rightIsPhone = $1.sourceRevision.source.bundleIdentifier == phoneBundle
            if leftIsPhone != rightIsPhone { return !leftIsPhone }
            return abs($0.startDate.timeIntervalSince(record.startedAt)) < abs($1.startDate.timeIntervalSince(record.startedAt))
        }.first
        var result = Result()
        var intervals = record.activeIntervals
        let distanceType = HKQuantityType(WorkoutHistoryReconciler.activity(for: record.workoutID) == "cycling"
                                         ? .distanceCycling : .distanceWalkingRunning)
        if let workout {
            result.totals.duration = workout.duration
            let boundaries = (workout.workoutEvents ?? []).compactMap { event -> WorkoutHealthWindowPolicy.Boundary? in
                switch event.type {
                case .pause, .motionPaused: return .init(date: event.dateInterval.start, paused: true)
                case .resume, .motionResumed: return .init(date: event.dateInterval.start, paused: false)
                default: return nil
                }
            }
            let healthIntervals = WorkoutHealthWindowPolicy.activeIntervals(start: workout.startDate,
                end: workout.endDate, boundaries: boundaries)
            // If an older export omits its pauses, don't guess where they occurred.
            if abs(healthIntervals.reduce(0) { $0 + $1.duration } - workout.duration) < 1 {
                intervals = healthIntervals
            }
            if workout.sourceRevision.source.bundleIdentifier != phoneBundle {
                result.totals.distanceMiles = workout.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .mile())
                    ?? workout.totalDistance?.doubleValue(for: .mile())
                result.totals.calories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
                    ?? workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
            }
        }
        if intervals == nil, abs(record.endedAt.timeIntervalSince(record.startedAt) - record.duration) < 1,
           record.endedAt > record.startedAt {
            intervals = [DateInterval(start: record.startedAt, end: record.endedAt)]
        }
        guard let intervals else { return result }
        let normalized = WorkoutHealthWindowPolicy.normalized(intervals,
            start: min(record.startedAt, workout?.startDate ?? record.startedAt),
            end: max(record.endedAt, workout?.endDate ?? record.endedAt))
        guard !normalized.isEmpty else { return result }
        result.intervals = normalized
        async let steps = try? sum(type: HKQuantityType(.stepCount), unit: .count(), intervals: normalized)
        async let distance = try? sum(type: distanceType, unit: .mile(), intervals: normalized)
        async let energy = try? sum(type: HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), intervals: normalized)
        let values = await (steps, distance, energy)
        result.totals.steps = values.0.map { Int($0.rounded()) }
        if result.totals.distanceMiles == nil { result.totals.distanceMiles = values.1 }
        if result.totals.calories == nil { result.totals.calories = values.2 }
        return result
    }

    private func sum(type: HKQuantityType, unit: HKUnit, intervals: [DateInterval]) async throws -> Double? {
        var total = 0.0
        for interval in intervals {
            guard let value = try await intervalSum(type: type, unit: unit, interval: interval) else { return nil }
            total += value
        }
        return total.isFinite ? total : nil
    }

    private func intervalSum(type: HKQuantityType, unit: HKUnit, interval: DateInterval) async throws -> Double? {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: []),
            NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))
        ])
        // One-second buckets respect arbitrary pause timestamps. Health handles
        // source priority/overlap; only the final fractional second is apportioned.
        // A coarse overlap-only query would count a whole sample outside the walk.
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                options: .cumulativeSum, anchorDate: interval.start, intervalComponents: DateComponents(second: 1))
            query.initialResultsHandler = { [store] _, collection, error in
                defer { store.stop(query) }
                if let error { continuation.resume(throwing: error); return }
                guard let collection else { continuation.resume(returning: nil); return }
                var total = 0.0
                var hasData = false
                collection.enumerateStatistics(from: interval.start, to: interval.end) { statistic, _ in
                    guard let quantity = statistic.sumQuantity() else { return }
                    let fraction = WorkoutHealthWindowPolicy.overlapFraction(
                        bucket: DateInterval(start: statistic.startDate, end: statistic.endDate), interval: interval)
                    guard fraction > 0 else { return }
                    total += quantity.doubleValue(for: unit) * fraction
                    hasData = true
                }
                continuation.resume(returning: hasData ? total : nil)
            }
            store.execute(query)
        }
    }

    private func samples(type: HKSampleType, predicate: NSPredicate) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                     sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }
}
