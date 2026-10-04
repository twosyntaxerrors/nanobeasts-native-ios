import Combine
import HealthKit

/// Reads today's Health totals while the home screen is visible. Never starts a workout.
@MainActor
final class WatchDailyActivityStore: ObservableObject {
    @Published private(set) var snapshot: WatchDailyActivity?
    @Published private(set) var isLoading = true
    @Published private(set) var notice: String?
    private let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []
    private var generation = UUID()
    private var isObserving = false
    private var isRefreshing = false

    func run() async {
        stopObservers()
        let token = UUID()
        generation = token
        isRefreshing = false
        defer {
            if generation == token {
                stopObservers()
                isLoading = false
            }
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            notice = "Apple Health is unavailable. You can still choose a workout below."
            return
        }
        let types = [HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning),
                     HKQuantityType(.activeEnergyBurned), HKQuantityType(.appleExerciseTime)]
        do {
            let read = Set<HKObjectType>(types)
            try await WatchAuthorizationQueue.shared.perform { [store] in
                let status = try await store.statusForAuthorizationRequest(toShare: [], read: read)
                try Task.checkCancellation()
                if status == .shouldRequest {
                    try await store.requestAuthorization(toShare: [], read: read)
                }
            }
            try Task.checkCancellation()
            guard generation == token else { return }
            isObserving = true
            for type in types {
                let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                    Task { @MainActor in
                        defer { completion() }
                        guard error == nil, let self, self.generation == token else { return }
                        await self.refresh()
                    }
                }
                observers.append(query)
                store.execute(query)
            }
            // Foreground refresh also handles midnight and timezone changes when no sample arrives.
            while !Task.isCancelled, generation == token {
                await refresh()
                try await Task.sleep(for: .seconds(30))
            }
        } catch is CancellationError {
            // Leaving Home stops its queries; the workout recorder has its own lifecycle.
        } catch {
            if generation == token { notice = "Couldn't load today's activity. Reopen Nano to retry." }
        }
    }

    private func refresh() async {
        guard isObserving, !isRefreshing else { return }
        isRefreshing = true
        let token = generation
        defer {
            if generation == token { isRefreshing = false; isLoading = false }
        }
        let now = Date()
        let day = Calendar.autoupdatingCurrent.startOfDay(for: now)
        if snapshot?.isCurrent(at: now) != true { snapshot = nil }
        do {
            async let steps = sum(.stepCount, unit: .count(), from: day, to: now)
            async let distance = sum(.distanceWalkingRunning, unit: .mile(), from: day, to: now)
            async let calories = sum(.activeEnergyBurned, unit: .kilocalorie(), from: day, to: now)
            async let exercise = sum(.appleExerciseTime, unit: .minute(), from: day, to: now)
            let week = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -6, to: day) ?? day
            async let weekly = stepHistory(from: week, to: now, interval: DateComponents(day: 1))
            async let hourly = stepHistory(from: day, to: now, interval: DateComponents(hour: 1))
            let totals = try await (steps, distance, calories, exercise, weekly, hourly)
            guard generation == token, isObserving,
                  Calendar.autoupdatingCurrent.isDateInToday(day) else { return }
            snapshot = WatchDailyActivity(day: day, steps: totals.0.map { Int($0.rounded()) },
                distanceMiles: totals.1, activeCalories: totals.2, exerciseMinutes: totals.3,
                weeklySteps: totals.4, hourlySteps: totals.5)
            // HealthKit does not disclose denied read permissions. Missing samples remain unknown.
            notice = totals.0 == nil && totals.1 == nil && totals.2 == nil
                ? "No activity available yet. Check Nano's access to Steps, Walking + Running Distance, and Active Energy in Health."
                : nil
        } catch {
            if generation == token { notice = "Couldn't refresh today's activity. Reopen Nano to retry." }
        }
    }

    private func stepHistory(from start: Date, to end: Date, interval: DateComponents) async throws -> [WatchStepInterval] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: HKQuantityType(.stepCount),
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .cumulativeSum, anchorDate: start, intervalComponents: interval)
            query.initialResultsHandler = { [store] query, collection, error in
                defer { store.stop(query) }
                if let error { continuation.resume(throwing: error); return }
                var result: [WatchStepInterval] = []
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard statistics.startDate < end else { return }
                    let value = statistics.sumQuantity()?.doubleValue(for: .count())
                    result.append(WatchStepInterval(start: statistics.startDate, end: statistics.endDate,
                        steps: value.flatMap { $0.isFinite ? max(0, Int($0.rounded())) : nil }))
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private func sum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: HKQuantityType(identifier),
                quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error { continuation.resume(throwing: error); return }
                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value.flatMap { $0.isFinite ? max(0, $0) : nil })
            }
            store.execute(query)
        }
    }

    private func stopObservers() {
        isObserving = false
        observers.forEach { store.stop($0) }
        observers.removeAll()
    }
}
