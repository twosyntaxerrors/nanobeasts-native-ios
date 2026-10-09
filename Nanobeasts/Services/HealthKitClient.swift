import Foundation
import CoreMotion
import HealthKit

enum HealthKitClientError: LocalizedError {
    case unavailable
    case stepTypeUnavailable
    case authorizationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple Health is not available on this device."
        case .stepTypeUnavailable:
            "Step-count data is not available."
        case .authorizationFailed:
            "Nanobeasts could not request Apple Health access."
        }
    }
}

final class HealthKitClient: @unchecked Sendable {
    private let store = HKHealthStore()
    private var observerQuery: HKObserverQuery?

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var stepType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .stepCount)
    }

    func requestStepAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitClientError.unavailable
        }
        guard let stepType else {
            throw HealthKitClientError.stepTypeUnavailable
        }

        let granted = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Bool, Error>) in
            store.requestAuthorization(toShare: [], read: [stepType]) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }

        guard granted else {
            throw HealthKitClientError.authorizationFailed
        }
    }

    /// `excludingUserEntered` drops steps typed into the Health app by hand, so
    /// the friends leaderboard only counts recorded walking.
    func fetchDailySteps(
        startingAt journeyStart: Date,
        excludingUserEntered: Bool = false
    ) async throws -> [DailyStepRecord] {
        guard isAvailable else {
            throw HealthKitClientError.unavailable
        }
        guard let stepType else {
            throw HealthKitClientError.stepTypeUnavailable
        }

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let start = min(max(journeyStart, calendar.startOfDay(for: journeyStart)), Date())
        let end = Date()
        var predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        if excludingUserEntered {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate,
                NSPredicate(format: "metadata.%K != YES", HKMetadataKeyWasUserEntered),
            ])
        }

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[DailyStepRecord], Error>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: today,
                intervalComponents: DateComponents(day: 1)
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }

                var records: [DailyStepRecord] = []
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let value = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    records.append(
                        DailyStepRecord(
                            day: calendar.startOfDay(for: statistics.startDate),
                            steps: max(0, Int(value.rounded()))
                        )
                    )
                }
                continuation.resume(returning: records)
            }

            store.execute(query)
        }
    }

    func fetchHourlySteps(startingAt startDate: Date) async throws -> [HourlyStepRecord] {
        guard isAvailable else {
            throw HealthKitClientError.unavailable
        }
        guard let stepType else {
            throw HealthKitClientError.stepTypeUnavailable
        }

        let calendar = Calendar.autoupdatingCurrent
        let start = min(startDate, Date())
        let end = Date()
        let anchor = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HourlyStepRecord], Error>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(hour: 1)
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }

                var records: [HourlyStepRecord] = []
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let value = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    records.append(
                        HourlyStepRecord(
                            start: statistics.startDate,
                            steps: max(0, Int(value.rounded()))
                        )
                    )
                }
                continuation.resume(returning: records)
            }

            store.execute(query)
        }
    }

    func startObservingSteps(onChange: @escaping @Sendable () async -> Void) {
        guard observerQuery == nil, let stepType else { return }

        let query = HKObserverQuery(sampleType: stepType, predicate: nil) {
            _, completion, error in
            guard error == nil else {
                completion()
                return
            }

            Task {
                await onChange()
                completion()
            }
        }

        observerQuery = query
        store.execute(query)
        store.enableBackgroundDelivery(for: stepType, frequency: .hourly) { _, _ in }
    }

    func stopObservingSteps() {
        if let observerQuery {
            store.stop(observerQuery)
        }
        observerQuery = nil
    }
}

enum PedometerClientError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Step counting is not available on this iPhone."
    }
}

final class PedometerClient: @unchecked Sendable {
    private let pedometer = CMPedometer()

    var isAvailable: Bool {
        CMPedometer.isStepCountingAvailable()
    }

    /// Core Motion keeps a rolling window of historical activity. Older days are
    /// retained by AppStore after their first query rather than requested again.
    func fetchRecentDailySteps(startingAt journeyStart: Date) async throws -> [DailyStepRecord] {
        guard isAvailable else { throw PedometerClientError.unavailable }

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let earliestMotionDay = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let firstDay = max(calendar.startOfDay(for: journeyStart), earliestMotionDay)
        guard firstDay <= today else { return [] }

        var records: [DailyStepRecord] = []
        var day = firstDay
        while day <= today {
            let dayEnd = min(
                calendar.date(byAdding: .day, value: 1, to: day) ?? Date(),
                Date()
            )
            let queryStart = max(day, journeyStart)
            let steps = try await querySteps(from: queryStart, to: dayEnd)
            records.append(DailyStepRecord(day: day, steps: steps))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        return records
    }

    func startObservingSteps(
        startingAt journeyStart: Date,
        onChange: @escaping @Sendable (DailyStepRecord) async -> Void
    ) {
        guard isAvailable else { return }
        pedometer.stopUpdates()

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let start = max(today, journeyStart)
        pedometer.startUpdates(from: start) { data, error in
            guard error == nil, let data else { return }
            let record = DailyStepRecord(
                day: today,
                steps: max(0, data.numberOfSteps.intValue)
            )
            Task { await onChange(record) }
        }
    }

    func stopObservingSteps() {
        pedometer.stopUpdates()
    }

    private func querySteps(from start: Date, to end: Date) async throws -> Int {
        guard end > start else { return 0 }
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Int, Error>) in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: max(0, data?.numberOfSteps.intValue ?? 0))
                }
            }
        }
    }
}
