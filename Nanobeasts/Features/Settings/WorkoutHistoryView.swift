import Charts
import Combine
import HealthKit
import MapKit
import SwiftUI

enum WorkoutHubSection: String, CaseIterable, Identifiable {
    case start = "Start"
    case history = "History"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .start: "pawprint.fill"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct WorkoutCompanionSnapshot: Codable, Hashable {
    let familyID: String
    let name: String
    let imageKey: String
    let stage: Int
    let types: [String]
    let description: String

    init(stage: CreatureStage) {
        familyID = stage.familyID
        name = stage.name
        imageKey = stage.imageKey
        self.stage = stage.stage
        types = stage.types
        description = stage.description
    }

    var creatureStage: CreatureStage {
        CreatureStage(
            familyID: familyID,
            name: name,
            imageKey: imageKey,
            stage: stage,
            types: types,
            description: description
        )
    }

    var roleTitle: String {
        stage == 0 ? "HATCHING" : "WALKED WITH"
    }
}

struct WorkoutHistoryRecord: Codable, Hashable, Identifiable {
    enum Source: String, Codable {
        case nanobeasts
        case appleHealth
    }

    let id: UUID
    let workoutID: String
    let name: String
    let symbol: String
    let startedAt: Date
    let endedAt: Date
    var duration: TimeInterval
    var steps: Int
    var distanceMiles: Double
    var calories: Double
    let indoor: Bool
    let source: Source
    let sourceName: String
    let companion: WorkoutCompanionSnapshot?
    var discoveries: [CreatureDiscoveryEvent]?
    // Optional so existing local history remains decodable.
    var healthWorkoutIDs: [UUID]? = nil
    var sourceBundleIdentifier: String? = nil
    var nanobeastsWorkoutID: UUID? = nil

    var activeIntervals: [DateInterval]? = nil
    var healthTotals: WorkoutHealthTotals? = nil

    var totalsSourceLabel: String {
        guard let healthTotals else { return "Device estimates · awaiting Apple Health" }
        return healthTotals.steps != nil && healthTotals.distanceMiles != nil && healthTotals.calories != nil
            ? "Totals from Apple Health" : "Apple Health · some device estimates"
    }

    mutating func applyHealthTotals(_ totals: WorkoutHealthTotals) {
        // A source correction may lower a value. Never max() Health against estimates.
        var merged = healthTotals ?? WorkoutHealthTotals()
        if let value = totals.steps, value >= 0 { steps = value; merged.steps = value }
        if let value = totals.distanceMiles, value.isFinite, value >= 0 {
            distanceMiles = value; merged.distanceMiles = value
        }
        if let value = totals.calories, value.isFinite, value >= 0 { calories = value; merged.calories = value }
        if let value = totals.duration, value.isFinite, value >= 0 { duration = value; merged.duration = value }
        guard merged.hasValues else { return }
        merged.checkedAt = totals.checkedAt
        healthTotals = merged
    }

    var paceMinutesPerMile: Double? {
        guard distanceMiles > 0.005 else { return nil }
        return (duration / 60) / distanceMiles
    }
}

struct WorkoutHealthTotals: Codable, Hashable {
    var steps: Int? = nil
    var distanceMiles: Double? = nil
    var calories: Double? = nil
    var duration: TimeInterval? = nil
    var checkedAt = Date()
    var hasValues: Bool { steps != nil || distanceMiles != nil || calories != nil || duration != nil }
}

enum WorkoutHealthWindowPolicy {
    struct Boundary { let date: Date; let paused: Bool }

    static func activeIntervals(start: Date, end: Date, boundaries: [Boundary]) -> [DateInterval] {
        guard end > start else { return [] }
        var activeStart: Date? = start
        var result: [DateInterval] = []
        let ordered = boundaries.enumerated().sorted {
            $0.element.date == $1.element.date ? $0.offset < $1.offset : $0.element.date < $1.element.date
        }
        for (_, boundary) in ordered where boundary.date >= start && boundary.date <= end {
            if boundary.paused, let began = activeStart {
                if boundary.date > began { result.append(DateInterval(start: began, end: boundary.date)) }
                activeStart = nil
            } else if !boundary.paused, activeStart == nil { activeStart = boundary.date }
        }
        if let began = activeStart, end > began { result.append(DateInterval(start: began, end: end)) }
        return result
    }

    static func normalized(_ intervals: [DateInterval], start: Date, end: Date) -> [DateInterval] {
        guard end > start else { return [] }
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            let lower = max(start, interval.start), upper = min(end, interval.end)
            guard upper > lower else { continue }
            if let last = result.last, lower <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, upper))
            } else { result.append(DateInterval(start: lower, end: upper)) }
        }
        return result
    }

    static func overlapFraction(bucket: DateInterval, interval: DateInterval) -> Double {
        guard bucket.duration > 0 else { return 0 }
        return max(0, min(bucket.end, interval.end).timeIntervalSince(max(bucket.start, interval.start))) / bucket.duration
    }
}

/// One history row per physical session, keeping the local companion/stats and
/// every Health identity needed to find the Watch route. Never sum metrics.
enum WorkoutHistoryReconciler {
    static func activity(for id: String) -> String {
        switch id {
        case "outdoor-walk", "indoor-walk", "japanese-walk-outdoor", "japanese-walk-indoor", "health-walk": "walking"
        case "outdoor-run", "indoor-run", "health-run": "running"
        case "hiking", "nordic-walk", "health-hike": "hiking"
        case "cycling", "health-cycle": "cycling"
        case "elliptical", "health-elliptical": "elliptical"
        case "stair-stepper", "health-stairs": "stairs"
        case "hiit", "health-hiit": "hiit"
        default: id
        }
    }

    static func reconcile(_ records: [WorkoutHistoryRecord]) -> [WorkoutHistoryRecord] {
        var result: [WorkoutHistoryRecord] = []
        // Local records always win, regardless of import order. In their
        // absence, prefer our exported copy so future imports stay stable.
        let ordered = records.sorted {
            if priority($0) != priority($1) { return priority($0) < priority($1) }
            if $0.startedAt != $1.startedAt { return $0.startedAt > $1.startedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        for record in ordered {
            let exact = result.indices.first {
                !identities(result[$0]).isDisjoint(with: identities(record))
            }
            let matching = exact ?? result.indices.filter {
                isSameSession(result[$0], record)
            }.min {
                timeDifference(result[$0], record) < timeDifference(result[$1], record)
            }
            guard let index = matching else {
                result.append(record)
                continue
            }
            if let totals = record.healthTotals,
               result[index].healthTotals.map({ $0.checkedAt <= totals.checkedAt }) ?? true {
                result[index].applyHealthTotals(totals)
            }
            if result[index].activeIntervals == nil { result[index].activeIntervals = record.activeIntervals }
            var identifiers = Set(result[index].healthWorkoutIDs ?? [])
            identifiers.formUnion(record.healthWorkoutIDs ?? [])
            if record.source == .appleHealth { identifiers.insert(record.id) }
            identifiers.remove(result[index].id)
            result[index].healthWorkoutIDs = identifiers.isEmpty ? nil
                : identifiers.sorted { $0.uuidString < $1.uuidString }
            var discoveries = result[index].discoveries ?? []
            let existingIDs = Set(discoveries.map(\.id))
            discoveries.append(contentsOf: (record.discoveries ?? []).filter { !existingIDs.contains($0.id) })
            if !discoveries.isEmpty { result[index].discoveries = discoveries }
        }
        return result.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt > $1.startedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func identities(_ record: WorkoutHistoryRecord) -> Set<UUID> {
        var values = Set(record.healthWorkoutIDs ?? [])
        values.insert(record.id)
        if let localID = record.nanobeastsWorkoutID { values.insert(localID) }
        return values
    }

    private static func origin(_ record: WorkoutHistoryRecord) -> String {
        if record.source == .nanobeasts || record.sourceName == "Nanobeasts"
            || record.sourceName == "Nanobeasts Native"
            || record.sourceBundleIdentifier == "com.twosyntaxerrors.nanobeasts.native" {
            return "nanobeasts"
        }
        return record.sourceBundleIdentifier ?? record.sourceName
    }

    private static func priority(_ record: WorkoutHistoryRecord) -> Int {
        record.source == .nanobeasts ? 0 : origin(record) == "nanobeasts" ? 1 : 2
    }

    private static func timeDifference(_ lhs: WorkoutHistoryRecord, _ rhs: WorkoutHistoryRecord) -> TimeInterval {
        abs(lhs.startedAt.timeIntervalSince(rhs.startedAt)) + abs(lhs.endedAt.timeIntervalSince(rhs.endedAt))
    }

    private static func isSameSession(_ lhs: WorkoutHistoryRecord, _ rhs: WorkoutHistoryRecord) -> Bool {
        guard activity(for: lhs.workoutID) == activity(for: rhs.workoutID), lhs.indoor == rhs.indoor else { return false }
        // Two independent sessions recorded by one source remain separate.
        // A local row and its own exported Health copy are the one exception.
        if origin(lhs) == origin(rhs) {
            guard lhs.source != rhs.source else { return false }
            return abs(lhs.startedAt.timeIntervalSince(rhs.startedAt)) <= 8
                && abs(lhs.endedAt.timeIntervalSince(rhs.endedAt)) <= 30
        }
        let lhsSpan = lhs.endedAt.timeIntervalSince(lhs.startedAt)
        let rhsSpan = rhs.endedAt.timeIntervalSince(rhs.startedAt)
        guard lhsSpan > 0, rhsSpan > 0,
              abs(lhs.startedAt.timeIntervalSince(rhs.startedAt)) <= 180,
              abs(lhs.endedAt.timeIntervalSince(rhs.endedAt)) <= 180 else { return false }
        let overlap = min(lhs.endedAt, rhs.endedAt).timeIntervalSince(max(lhs.startedAt, rhs.startedAt))
        // Both recordings must cover substantially the same interval. Merely
        // sharing a date, touching endpoints, or nesting a short walk is insufficient.
        return overlap / lhsSpan >= 0.85 && overlap / rhsSpan >= 0.85
    }
}

@MainActor
final class WorkoutHistoryStore: ObservableObject {
    static let didChangeNotification = Notification.Name(
        "nanobeasts.workout-history.did-change"
    )

    @Published private(set) var workouts: [WorkoutHistoryRecord]
    @Published private(set) var isImporting = false
    @Published private(set) var lastImportCount: Int?
    @Published private(set) var importError: String?

    private var historyChanges: AnyCancellable?
    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults
    private let storageKey = "nanobeasts.native.workout-history.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        workouts = []
        reload()
        historyChanges = NotificationCenter.default.publisher(for: Self.didChangeNotification)
            .sink { [weak self] notification in
                guard notification.object as? WorkoutHistoryStore !== self else { return }
                Task { @MainActor [weak self] in self?.reload() }
            }
    }

    func reload() {
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([WorkoutHistoryRecord].self, from: data) else {
            workouts = []
            return
        }
        let reconciled = Self.sortedAndLimited(saved)
        if workouts != reconciled { workouts = reconciled }
        if workouts != saved {
            let backupKey = storageKey + ".before-reconciliation"
            if defaults.data(forKey: backupKey) == nil { defaults.set(data, forKey: backupKey) }
            persist()
        }
    }

    /// The same saved GPS archives power both replays and permanent map reveals.
    func savedTerritoryRoutes() -> [UUID: [[CLLocationCoordinate2D]]] {
        Self.savedTerritoryRoutes(for: workouts)
    }

    func loadSavedTerritoryRoutes() async -> [UUID: [[CLLocationCoordinate2D]]] {
        let records = workouts
        return await Task.detached(priority: .utility) {
            Self.savedTerritoryRoutes(for: records)
        }.value
    }

    nonisolated private static func savedTerritoryRoutes(for workouts: [WorkoutHistoryRecord]) -> [UUID: [[CLLocationCoordinate2D]]] {
        var result: [UUID: [[CLLocationCoordinate2D]]] = [:]
        for workout in workouts where !workout.indoor {
            let identifiers = [workout.id] + (workout.healthWorkoutIDs ?? [])
                + (workout.nanobeastsWorkoutID.map { [$0] } ?? [])
            let candidates = identifiers.map { id in
                (id: id, route: WorkoutHistoryRouteArchive.load(for: id))
            }
            guard let best = candidates.max(by: { $0.route.count < $1.route.count }),
                  best.route.count > 1 else { continue }
            result[workout.id] = WorkoutRouteSegments.split(
                best.route, at: WorkoutHistoryRouteArchive.loadBreakIndices(for: best.id)
            ).filter { $0.count > 1 }
        }
        return result
    }

    @discardableResult
    func record(
        workoutID: String,
        name: String,
        symbol: String,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        steps: Int,
        distanceMiles: Double,
        calories: Double,
        indoor: Bool,
        companion: CreatureStage,
        discoveries: [CreatureDiscoveryEvent],
        route: [CLLocationCoordinate2D],
        routeBreakIndices: [Int] = [],
        activeIntervals: [DateInterval]? = nil
    ) -> UUID {
        reload()
        let recordID = UUID()
        guard WorkoutActivityPolicy.hasActivity(steps: steps, distanceMiles: distanceMiles, calories: calories) else { return recordID }
        WorkoutHistoryRouteArchive.save(route, breakIndices: routeBreakIndices, for: recordID)
        workouts.append(
            WorkoutHistoryRecord(
                id: recordID,
                workoutID: workoutID,
                name: name,
                symbol: symbol,
                startedAt: startedAt,
                endedAt: endedAt,
                duration: max(duration, 0),
                steps: max(steps, 0),
                distanceMiles: max(distanceMiles, 0),
                calories: max(calories, 0),
                indoor: indoor,
                source: .nanobeasts,
                sourceName: "Nanobeasts",
                companion: WorkoutCompanionSnapshot(stage: companion),
                discoveries: discoveries,
                activeIntervals: activeIntervals
            )
        )
        workouts = Self.sortedAndLimited(workouts)
        persist()
        return recordID
    }

    /// Finalized history follows Health, with recorded device values kept only
    /// when Health has not supplied that metric. No history repair writes to Health.
    func refreshHealthTotals(for workoutID: UUID? = nil, force: Bool = false) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let candidates = workouts.filter { record in
            if let workoutID { return record.id == workoutID }
            let recent = Date().timeIntervalSince(record.endedAt) < 14 * 86_400
            guard recent || record.healthTotals == nil else { return false }
            if force { return true }
            return record.healthTotals.map { Date().timeIntervalSince($0.checkedAt) > 60 } ?? true
        }
        for record in candidates {
            if Task.isCancelled { return }
            do {
                let result = try await WorkoutHealthTotalsReader.shared.read(record)
                guard result.totals.hasValues else { continue }
                reload()
                guard let index = workouts.firstIndex(where: { $0.id == record.id }) else { continue }
                let backupKey = storageKey + ".before-health-totals." + record.id.uuidString
                if defaults.data(forKey: backupKey) == nil,
                   let backup = try? JSONEncoder().encode(workouts[index]) { defaults.set(backup, forKey: backupKey) }
                var updated = workouts[index]
                updated.applyHealthTotals(result.totals)
                if let intervals = result.intervals { updated.activeIntervals = intervals }
                workouts[index] = updated
                persist()
            } catch {
                // Locked Health data, missing permissions or an interrupted sync
                // never becomes a fabricated zero or erases a confirmed total.
                continue
            }
        }
    }

    func updateDiscoveries(_ discoveries: [CreatureDiscoveryEvent], for workoutID: UUID) {
        reload()
        guard let index = workouts.firstIndex(where: { $0.id == workoutID }) else { return }
        workouts[index].discoveries = discoveries
        persist()
    }

    func linkHealthWorkout(_ healthID: UUID, to workoutID: UUID) {
        reload()
        guard let index = workouts.firstIndex(where: { $0.id == workoutID }) else { return }
        var identifiers = Set(workouts[index].healthWorkoutIDs ?? [])
        identifiers.insert(healthID)
        workouts[index].healthWorkoutIDs = identifiers.sorted { $0.uuidString < $1.uuidString }
        workouts = Self.sortedAndLimited(workouts)
        persist()
    }

    func receiveWatchWorkout(_ result: WatchWorkoutResult, companion: WorkoutCompanionSnapshot?) {
        let state = result.snapshot
        guard !state.isActive, state.hasRecordedActivity else { return }
        reload()
        // A final metrics snapshot arrives immediately; the full route follows
        // by durable file transfer. Neither retries nor empty snapshots erase it.
        if !result.locations.isEmpty,
           result.locations.count >= WorkoutHistoryRouteArchive.load(for: state.id).count {
            WorkoutHistoryRouteArchive.save(result.locations.map { $0.location.coordinate },
                breakIndices: result.breakIndices, for: state.id)
        }
        let existing = workouts.first(where: { $0.id == state.id })
        var healthIDs = Set(existing?.healthWorkoutIDs ?? [])
        if let healthID = state.healthWorkoutID { healthIDs.insert(healthID) }
        workouts.removeAll { $0.id == state.id }
        workouts.append(WorkoutHistoryRecord(id: state.id, workoutID: state.workoutID, name: state.name,
                symbol: state.workoutID.contains("run") ? "figure.run" : state.workoutID == "hiking" ? "figure.hiking" : "figure.walk",
                startedAt: state.startedAt, endedAt: max(existing?.endedAt ?? state.updatedAt, state.updatedAt),
                duration: max(existing?.duration ?? 0, state.elapsed),
                steps: max(existing?.steps ?? 0, state.steps),
                distanceMiles: max(existing?.distanceMiles ?? 0, state.distanceMiles),
                calories: max(existing?.calories ?? 0, state.calories),
                indoor: state.indoor, source: .nanobeasts, sourceName: "Nanobeasts · Apple Watch",
                companion: existing?.companion ?? companion, discoveries: existing?.discoveries,
                healthWorkoutIDs: healthIDs.isEmpty ? nil : healthIDs.sorted { $0.uuidString < $1.uuidString }))
        if let totals = existing?.healthTotals,
           let index = workouts.firstIndex(where: { $0.id == state.id }) {
            workouts[index].applyHealthTotals(totals)
            workouts[index].activeIntervals = existing?.activeIntervals
        }
        workouts = Self.sortedAndLimited(workouts)
        persist()
        Task { await self.refreshHealthTotals(for: state.id) }
    }

    func importFromAppleHealth(requestAccess: Bool = true, forceHealthTotals: Bool = false) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            importError = "Apple Health is not available on this device."
            return
        }

        guard !isImporting else { return }
        isImporting = true
        importError = nil
        lastImportCount = nil
        defer { isImporting = false }

        do {
            if requestAccess {
                try await requestAuthorization()
                UserDefaults.standard.set(true, forKey: WorkoutHealthSync.enabledKey)
                WorkoutHealthSync.shared.start()
            }
            let imported = try await fetchHealthWorkouts()
                .map(Self.makeRecord)

            // A phone workout or Watch transfer may finish while Health is queried.
            reload()
            let previous = WorkoutHistoryReconciler.reconcile(workouts)
            let reconciled = Self.sortedAndLimited(previous + imported)
            lastImportCount = max(0, reconciled.count - previous.count)
            workouts = Array(reconciled.prefix(300))
            persist()
            await refreshHealthTotals(force: forceHealthTotals)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func requestAuthorization() async throws {
        let workoutType = HKObjectType.workoutType()
        let success = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Bool, Error>) in
            healthStore.requestAuthorization(toShare: [], read: [workoutType, HKSeriesType.workoutRoute(), HKQuantityType(.stepCount),
                HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.activeEnergyBurned)]) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
        guard success else { throw WorkoutHistoryError.authorizationFailed }
    }

    private func fetchHealthWorkouts() async throws -> [HKWorkout] {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.date(byAdding: .year, value: -1, to: Date())
            ?? Date().addingTimeInterval(-365 * 24 * 60 * 60)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: Date(),
            options: .strictStartDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKWorkout] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(workouts) else { return }
        defaults.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static func sortedAndLimited(
        _ records: [WorkoutHistoryRecord]
    ) -> [WorkoutHistoryRecord] {
        Array(WorkoutHistoryReconciler.reconcile(records).filter {
            WorkoutActivityPolicy.hasActivity(steps: $0.steps, distanceMiles: $0.distanceMiles, calories: $0.calories)
        }.prefix(300))
    }

    private static func makeRecord(_ workout: HKWorkout) -> WorkoutHistoryRecord {
        let presentation = presentation(for: workout.workoutActivityType)
        return WorkoutHistoryRecord(
            id: workout.uuid,
            workoutID: presentation.id,
            name: presentation.name,
            symbol: presentation.symbol,
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            duration: workout.duration,
            steps: 0,
            distanceMiles: workout.totalDistance?.doubleValue(for: .mile()) ?? 0,
            calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
            indoor: workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false,
            source: .appleHealth,
            sourceName: workout.sourceRevision.source.name,
            companion: nil,
            discoveries: nil,
            sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
            nanobeastsWorkoutID: (workout.metadata?["NanobeastsWorkoutRecordID"] as? String).flatMap(UUID.init(uuidString:))
        )
    }

    private static func presentation(
        for activity: HKWorkoutActivityType
    ) -> (id: String, name: String, symbol: String) {
        switch activity {
        case .walking: ("health-walk", "Walk", "figure.walk")
        case .running: ("health-run", "Run", "figure.run")
        case .hiking: ("health-hike", "Hike", "figure.hiking")
        case .cycling: ("health-cycle", "Cycling", "bicycle")
        case .elliptical: ("health-elliptical", "Elliptical", "figure.elliptical")
        case .stairClimbing: ("health-stairs", "Stair Climbing", "figure.stair.stepper")
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            ("health-strength", "Strength Training", "dumbbell.fill")
        case .highIntensityIntervalTraining:
            ("health-hiit", "HIIT", "figure.highintensity.intervaltraining")
        case .yoga: ("health-yoga", "Yoga", "figure.yoga")
        default: ("health-workout-\(activity.rawValue)", "Workout", "figure.mixed.cardio")
        }
    }
}

private enum WorkoutHistoryError: LocalizedError {
    case authorizationFailed

    var errorDescription: String? {
        "Nanobeasts could not access workout history in Apple Health."
    }
}

enum WorkoutHistoryRouteArchive {
    static let didChangeNotification = Notification.Name("nanobeasts.workout-route.did-change")
    private struct StoredRoute: Codable {
        static let currentVersion = 1

        let version: Int
        let points: [StoredCoordinate]
        var breakIndices: [Int]? = nil
    }

    private struct StoredCoordinate: Codable {
        let latitude: Double
        let longitude: Double
    }

    static func save(_ route: [CLLocationCoordinate2D], breakIndices: [Int], for workoutID: UUID) {
        let points = route.compactMap { coordinate -> StoredCoordinate? in
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            return StoredCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
        guard points.count > 1, let url = routeURL(for: workoutID) else { return }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = StoredRoute(
                version: StoredRoute.currentVersion,
                points: points,
                breakIndices: breakIndices
            )
            try JSONEncoder().encode(payload).write(to: url, options: .atomic)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
#if DEBUG
            print("Could not persist workout route: \(error)")
#endif
        }
    }

    static func load(for workoutID: UUID) -> [CLLocationCoordinate2D] {
        guard
            let url = routeURL(for: workoutID),
            let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(StoredRoute.self, from: data),
            payload.version == StoredRoute.currentVersion
        else {
            return []
        }

        return payload.points.compactMap { point in
            let coordinate = CLLocationCoordinate2D(
                latitude: point.latitude,
                longitude: point.longitude
            )
            return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
        }
    }

    static func loadBreakIndices(for workoutID: UUID) -> [Int] {
        guard let url = routeURL(for: workoutID),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(StoredRoute.self, from: data)
        else { return [] }
        return payload.breakIndices ?? []
    }

    private static func routeURL(for workoutID: UUID) -> URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("Nanobeasts", isDirectory: true)
            .appendingPathComponent("workout-routes-v1", isDirectory: true)
            .appendingPathComponent("\(workoutID.uuidString.lowercased()).json")
    }
}

struct WorkoutHubHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    @Binding var selection: WorkoutHubSection
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NanoTheme.text)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(NanoTheme.surface.opacity(0.94)))
                    .overlay(Circle().stroke(NanoTheme.elevated, lineWidth: 1))
            }
            .buttonStyle(WorkoutHistoryPressStyle())
            .accessibilityLabel("Close workouts")

            HStack(spacing: 3) {
                ForEach(WorkoutHubSection.allCases) { section in
                    Button {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .timingCurve(0.23, 1, 0.32, 1, duration: 0.2)) {
                            selection = section
                        }
                    } label: {
                        Label(section.rawValue, systemImage: section.symbol)
                            .font(NanoFont.aldrich(10))
                            .foregroundStyle(
                                selection == section
                                    ? NanoTheme.background
                                    : NanoTheme.secondaryText
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background {
                                if selection == section {
                                    if reduceMotion {
                                        Capsule().fill(NanoTheme.teal)
                                    } else {
                                        Capsule().fill(NanoTheme.teal)
                                            .matchedGeometryEffect(id: "workout-section", in: selectionNamespace)
                                    }
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(WorkoutHistoryPressStyle())
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Capsule().fill(NanoTheme.surface.opacity(0.94)))
            .overlay(Capsule().stroke(NanoTheme.elevated, lineWidth: 1))

            Color.clear
                .frame(width: 46, height: 46)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

struct WorkoutHistoryScreen: View {
    @ObservedObject var historyStore: WorkoutHistoryStore
    let distanceUnit: DistanceUnitPreference
    let selectWorkout: (WorkoutHistoryRecord) -> Void

    private var monthGroups: [WorkoutHistoryMonthGroup] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: historyStore.workouts) { workout in
            calendar.date(
                from: calendar.dateComponents([.year, .month], from: workout.startedAt)
            ) ?? calendar.startOfDay(for: workout.startedAt)
        }
        return grouped
            .map { WorkoutHistoryMonthGroup(month: $0.key, workouts: $0.value) }
            .sorted { $0.month > $1.month }
    }

    private var thisWeek: [WorkoutHistoryRecord] {
        let calendar = Calendar.autoupdatingCurrent
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return []
        }
        return historyStore.workouts.filter { interval.contains($0.startedAt) }
    }

    private var trend: [WorkoutHistoryTrendPoint] {
        let calendar = Calendar.autoupdatingCurrent
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start)
            else { return nil }
            let minutes = historyStore.workouts
                .filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
                .reduce(0.0) { $0 + ($1.duration / 60) }
            return WorkoutHistoryTrendPoint(day: day, minutes: minutes)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("WORKOUT LOG")
                        .font(NanoFont.aldrich(12))
                        .tracking(1.4)
                        .foregroundStyle(NanoTheme.teal)
                    Text("Every step has a story.")
                        .font(NanoFont.aldrich(25))
                        .foregroundStyle(NanoTheme.text)
                }

                weekSummary
                if !monthGroups.isEmpty { compactImportAction }

                if monthGroups.isEmpty {
                    importCard
                    emptyState
                } else {
                    ForEach(monthGroups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.month.formatted(.dateTime.month(.wide).year()))
                                .font(NanoFont.aldrich(13))
                                .foregroundStyle(NanoTheme.text)

                            ForEach(group.workouts) { workout in
                                Button {
                                    selectWorkout(workout)
                                } label: {
                                    WorkoutHistoryRow(
                                        workout: workout,
                                        distanceUnit: distanceUnit
                                    )
                                }
                                .buttonStyle(WorkoutHistoryPressStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 88)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
    }

    private var weekSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("THIS WEEK")
                        .font(NanoFont.aldrich(10))
                        .foregroundStyle(NanoTheme.secondaryText)
                    Text(historyDuration(thisWeek.reduce(0) { $0 + $1.duration }))
                        .font(NanoFont.spaceMono(25, bold: true))
                        .foregroundStyle(NanoTheme.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("SESSIONS")
                        .font(NanoFont.aldrich(10))
                        .foregroundStyle(NanoTheme.secondaryText)
                    Text(thisWeek.count.formatted())
                        .font(NanoFont.spaceMono(25, bold: true))
                        .foregroundStyle(NanoTheme.teal)
                }
            }

            Chart(trend) { point in
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Minutes", point.minutes)
                )
                .foregroundStyle(
                    Calendar.autoupdatingCurrent.isDateInToday(point.day)
                        ? NanoTheme.teal
                        : NanoTheme.cyan.opacity(0.46)
                )
                .cornerRadius(5)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .foregroundStyle(NanoTheme.secondaryText)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 92)

            HStack(spacing: 10) {
                WorkoutHistorySummaryMetric(
                    label: "DISTANCE",
                    value: formattedDistance(
                        thisWeek.reduce(0) { $0 + $1.distanceMiles },
                        unit: distanceUnit
                    ),
                    symbol: "arrow.right"
                )
                WorkoutHistorySummaryMetric(
                    label: "ENERGY",
                    value: "\(Int(thisWeek.reduce(0) { $0 + $1.calories })) kcal",
                    symbol: "flame.fill"
                )
            }
        }
        .padding(17)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(NanoTheme.surface)
                .stroke(NanoTheme.teal.opacity(0.42), lineWidth: 1)
        )
    }

    private var compactImportAction: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("Apple Health", systemImage: "heart.fill")
                    .font(NanoFont.aldrich(12))
                    .foregroundStyle(NanoTheme.secondaryText)
                Spacer()
                Button {
                    Task { await historyStore.importFromAppleHealth() }
                } label: {
                    HStack(spacing: 6) {
                        if historyStore.isImporting { ProgressView().tint(NanoTheme.teal) }
                        else { Image(systemName: "arrow.clockwise") }
                        Text(historyStore.isImporting ? "Importing" : "Import")
                    }
                    .font(NanoFont.aldrich(12))
                    .foregroundStyle(NanoTheme.teal)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(NanoTheme.teal.opacity(0.09)))
                }
                .buttonStyle(WorkoutHistoryPressStyle())
                .disabled(historyStore.isImporting)
                .accessibilityLabel("Import Apple Health workouts")
            }
            if historyStore.importError != nil || historyStore.lastImportCount != nil {
                Text(importMessage)
                    .font(NanoFont.aldrich(11))
                    .foregroundStyle(historyStore.importError == nil ? NanoTheme.secondaryText : NanoTheme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 2)
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(NanoTheme.text)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(NanoTheme.pink)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("APPLE HEALTH WORKOUTS")
                        .font(NanoFont.aldrich(11))
                        .foregroundStyle(NanoTheme.text)
                    Text(importMessage)
                        .font(NanoFont.aldrich(9))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button {
                Task { await historyStore.importFromAppleHealth() }
            } label: {
                HStack(spacing: 8) {
                    if historyStore.isImporting {
                        ProgressView()
                            .tint(NanoTheme.background)
                    } else {
                        Image(systemName: "square.and.arrow.down.fill")
                    }
                    Text(historyStore.isImporting ? "IMPORTING" : "IMPORT HISTORY")
                }
                .font(NanoFont.aldrich(11))
                .foregroundStyle(NanoTheme.background)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(NanoTheme.pink))
            }
            .buttonStyle(WorkoutHistoryPressStyle())
            .disabled(historyStore.isImporting)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(NanoTheme.pink.opacity(0.09))
                .stroke(NanoTheme.pink.opacity(0.34), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(NanoTheme.teal)
            Text("NO WORKOUTS YET")
                .font(NanoFont.aldrich(14))
                .foregroundStyle(NanoTheme.text)
            Text("Start a session with your Nanobeast or import your recent Apple Health workouts.")
                .font(NanoFont.aldrich(10))
                .foregroundStyle(NanoTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 22)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(NanoTheme.surface)
                .stroke(NanoTheme.elevated, lineWidth: 1)
        )
    }

    private var importMessage: String {
        if let error = historyStore.importError { return error }
        if let count = historyStore.lastImportCount {
            return count == 0
                ? "Everything from the last year is already here."
                : "Added \(count) workout\(count == 1 ? "" : "s") from the last year."
        }
        return "Bring in walks, runs, hikes, and other sessions from the last year."
    }
}

@MainActor
private enum WorkoutHealthRouteReader {
    static func load(for record: WorkoutHistoryRecord) async throws
        -> (coordinates: [CLLocationCoordinate2D], breakIndices: [Int]) {
        let healthStore = HKHealthStore()
        let routeType = HKSeriesType.workoutRoute()
        try await healthStore.requestAuthorization(
            toShare: [], read: [HKObjectType.workoutType(), routeType]
        )
        var identifiers = record.healthWorkoutIDs ?? []
        if record.source == .appleHealth { identifiers.insert(record.id, at: 0) }
        // Use saved Health identities; never infer a route from distance or
        // attach a different walk merely because it happened on the same day.
        for identifier in Set(identifiers) {
            let workouts: [HKWorkout] = try await samples(
                type: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForObject(with: identifier), store: healthStore
            )
            guard let workout = workouts.first else { continue }
            let routes: [HKWorkoutRoute] = try await samples(
                type: routeType,
                predicate: HKQuery.predicateForObjects(from: workout), store: healthStore
            )
            var series: [[CLLocation]] = []
            for route in routes.sorted(by: { $0.startDate < $1.startDate }) {
                var locations: [CLLocation] = []
                for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: healthStore) {
                    try Task.checkCancellation()
                    locations.append(location)
                }
                series.append(locations)
            }
            let recorded = WorkoutRouteSegments.recorded(series)
            if WorkoutRouteSegments.split(recorded.coordinates, at: recorded.breakIndices)
                .contains(where: { $0.count > 1 }) {
                return recorded
            }
        }
        return ([], [])
    }

    private static func samples<Sample: HKSample>(
        type: HKSampleType, predicate: NSPredicate, store: HKHealthStore
    ) async throws -> [Sample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [Sample] ?? []) }
            }
            store.execute(query)
        }
    }
}

struct WorkoutHistoryDetailView: View {
#if targetEnvironment(simulator)
    static func cachePreviewRoute(_ route: [CLLocationCoordinate2D], for id: UUID) {
        WorkoutHistoryRouteArchive.save(route, breakIndices: [], for: id)
    }
#endif
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var route: [CLLocationCoordinate2D] = []
    @State private var routeBreakIndices: [Int] = []
    @State private var sharePayload: WorkoutSharePayload?
    @State private var replayPayload: WorkoutSharePayload?
    @State private var isLoadingHealthRoute = false
    @State private var routeMessage: String?

    @State private var workout: WorkoutHistoryRecord
    let distanceUnit: DistanceUnitPreference

    init(workout: WorkoutHistoryRecord, distanceUnit: DistanceUnitPreference) {
        _workout = State(initialValue: workout)
        self.distanceUnit = distanceUnit
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sessionHeader
                    sessionSummary
                    if route.count > 1 {
                        WorkoutHistoryRouteCard(route: route, breakIndices: routeBreakIndices) {
                            replayPayload = makeWorkoutPayload()
                        }
                    } else if !workout.indoor {
                        missingRouteCard
                    }
                    if let discoveries = workout.discoveries, !discoveries.isEmpty {
                        WorkoutHistoryDiscoveriesCard(discoveries: discoveries)
                    }
                    Text(workout.totalsSourceLabel)
                        .font(NanoFont.aldrich(10))
                        .foregroundStyle(NanoTheme.secondaryText)
                    Label(workout.sourceName, systemImage: "heart.fill")
                        .font(NanoFont.aldrich(11))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: shareWorkout) {
                Label("Share workout", systemImage: "square.and.arrow.up")
                    .font(NanoFont.aldrich(15))
                    .foregroundStyle(NanoTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(NanoTheme.teal))
            }
            .buttonStyle(WorkoutHistoryPressStyle())
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(NanoTheme.background.opacity(0.97))
        }

        .task(id: workout.id) {
            let history = WorkoutHistoryStore()
            await history.refreshHealthTotals(for: workout.id)
            if let current = history.workouts.first(where: { $0.id == workout.id }) { workout = current }
            // Consolidation keeps the original archives under their Health
            // identities, so a route already downloaded from the Watch survives.
            for identifier in [workout.id] + (workout.healthWorkoutIDs ?? []) {
                let saved = WorkoutHistoryRouteArchive.load(for: identifier)
                if saved.count > 1 {
                    route = saved
                    routeBreakIndices = WorkoutHistoryRouteArchive.loadBreakIndices(for: identifier)
                    break
                }
            }
            if route.count < 2, !workout.indoor,
               UserDefaults.standard.bool(forKey: WorkoutHealthSync.enabledKey),
               workout.source == .appleHealth || workout.healthWorkoutIDs?.isEmpty == false {
                await loadHealthRoute()
            }
        }
        .fullScreenCover(item: $replayPayload) { payload in
            WorkoutRouteReplayView(payload: payload, distanceUnit: distanceUnit)
        }
        .sheet(item: $sharePayload) { payload in
            WorkoutShareComposer(payload: payload)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                Label(workout.indoor ? "INDOOR ADVENTURE" : "OUTDOOR ADVENTURE", systemImage: workout.symbol)
                    .font(NanoFont.aldrich(10))
                    .tracking(0.8)
                    .foregroundStyle(NanoTheme.teal)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NanoTheme.text)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(NanoTheme.surface))
                }
                .buttonStyle(WorkoutHistoryPressStyle())
                .accessibilityLabel("Close workout details")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(workout.name)
                    .font(NanoFont.aldrich(28))
                    .foregroundStyle(NanoTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(NanoFont.aldrich(12))
                    .foregroundStyle(NanoTheme.secondaryText)
            }
        }
    }

    private var sessionSummary: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.steps > 0 ? workout.steps.formatted() : formattedDistance(workout.distanceMiles, unit: distanceUnit))
                        .font(NanoFont.spaceMono(40, bold: true))
                        .foregroundStyle(NanoTheme.teal)
                        .lineLimit(1).minimumScaleFactor(0.65)
                    Text(workout.steps > 0 ? "STEPS TOGETHER" : "DISTANCE COVERED")
                        .font(NanoFont.aldrich(10))
                        .tracking(1.2)
                        .foregroundStyle(NanoTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let companion = workout.companion {
                    CreatureArtworkView(stage: companion.creatureStage)
                        .frame(width: 88, height: 88)
                        .accessibilityLabel(companion.name)
                }
            }
            if let companion = workout.companion {
                HStack(spacing: 7) {
                    Image(systemName: "pawprint.fill").foregroundStyle(NanoTheme.teal)
                    Text(companion.stage == 0 ? "Helping \(companion.name) hatch" : "Explored with \(companion.name)")
                        .foregroundStyle(NanoTheme.text)
                }
                .font(NanoFont.aldrich(12))
                .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(NanoTheme.elevated).frame(height: 1)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 20) {
                summaryMetric("ACTIVE TIME", WorkoutMetricsFormat.time(workout.duration))
                summaryMetric(workout.steps > 0 ? "DISTANCE" : "STEPS", workout.steps > 0
                    ? formattedDistance(workout.distanceMiles, unit: distanceUnit)
                    : workout.source == .appleHealth ? "—" : "0")
                summaryMetric("AVG PACE", formattedPace(workout.paceMinutesPerMile, unit: distanceUnit))
                summaryMetric("ACTIVE ENERGY", "\(Int(workout.calories)) kcal")
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(NanoTheme.surface)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(NanoTheme.teal.opacity(0.25), lineWidth: 1)
                }
        }
    }

    private func summaryMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(NanoFont.aldrich(9)).tracking(0.5).foregroundStyle(NanoTheme.secondaryText)
            Text(value).font(NanoFont.spaceMono(16, bold: true)).foregroundStyle(NanoTheme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func shareWorkout() {
        sharePayload = makeWorkoutPayload()
    }

    private func makeWorkoutPayload() -> WorkoutSharePayload {
        WorkoutSharePayload(
            workoutName: workout.name,
            workoutSymbol: workout.symbol,
            elapsedSeconds: max(0, Int(workout.duration.rounded())),
            steps: workout.steps,
            distanceMiles: workout.distanceMiles,
            calories: workout.calories,
            isIndoor: workout.indoor,
            route: route,
            territoryTiles: 0,
            companion: workout.companion?.creatureStage ?? store.currentStage,
            rewards: workout.discoveries ?? [],
            routeBreakIndices: routeBreakIndices
        )
    }

    private var missingRouteCard: some View {
        VStack(spacing: 12) {
            Label(isLoadingHealthRoute ? "Finding your route" : "No saved route", systemImage: "location.slash")
                .font(NanoFont.aldrich(14))
            Text(isLoadingHealthRoute ? "Checking Apple Health for this workout’s recorded path." : routeMessage ?? "A GPS route wasn’t saved for this workout. Your activity is still recorded here.")
                .font(NanoFont.aldrich(11))
                .foregroundStyle(NanoTheme.secondaryText)
                .multilineTextAlignment(.center)
            if workout.source == .appleHealth || workout.healthWorkoutIDs?.isEmpty == false {
                Button {
                    Task { await loadHealthRoute() }
                } label: {
                    HStack {
                        if isLoadingHealthRoute { ProgressView() }
                        Text(isLoadingHealthRoute ? "Loading route…" : "Load route from Apple Health")
                    }
                }
                .disabled(isLoadingHealthRoute)
                .buttonStyle(.bordered)
                .tint(NanoTheme.teal)
            } else {
                Text("If your Apple Watch recorded this walk, import it from Apple Health in History to share its route.")
                    .font(.footnote)
                    .foregroundStyle(NanoTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20).fill(NanoTheme.surface))
    }

    @MainActor
    private func loadHealthRoute() async {
        guard !isLoadingHealthRoute else { return }
        isLoadingHealthRoute = true
        defer { isLoadingHealthRoute = false }
        do {
            let recorded = try await WorkoutHealthRouteReader.load(for: workout)
            guard !recorded.coordinates.isEmpty else {
                routeMessage = "No route is available from Apple Health yet. Allow Workout Routes access, let your Watch sync with your iPhone, then try again."
                return
            }
            WorkoutHistoryRouteArchive.save(recorded.coordinates, breakIndices: recorded.breakIndices, for: workout.id)
            route = recorded.coordinates
            routeBreakIndices = recorded.breakIndices
            routeMessage = nil
        } catch {
            routeMessage = "The route could not be loaded: \(error.localizedDescription)"
        }
    }
}

private struct WorkoutHistoryRouteCard: View {
    let route: [CLLocationCoordinate2D]
    let breakIndices: [Int]
    let watchRoute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NanoTheme.teal)
                Text("RECORDED ROUTE")
                    .font(NanoFont.aldrich(11))
                    .tracking(1.1)
                    .foregroundStyle(NanoTheme.text)
                Spacer()
                Text("START → FINISH")
                    .font(NanoFont.aldrich(8))
                    .tracking(0.7)
                    .foregroundStyle(NanoTheme.secondaryText)
                    .lineLimit(1)
            }

            WorkoutHistoryRouteMap(route: route, breakIndices: breakIndices)
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(NanoTheme.teal.opacity(0.28), lineWidth: 1)
                )
                .accessibilityLabel("Recorded workout route from start to finish")
                .accessibilityHint("The map can be panned and zoomed")
            if WorkoutRouteReplayTrack(route: route, breakIndices: breakIndices).canReplay {
                WorkoutRouteReplayButton(action: watchRoute)
            }

        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(NanoTheme.surface)
                .stroke(NanoTheme.teal.opacity(0.24), lineWidth: 1)
        )
    }
}

private struct WorkoutHistoryRouteMap: UIViewRepresentable {
    let route: [CLLocationCoordinate2D]
    let breakIndices: [Int]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.overrideUserInterfaceStyle = .dark
        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.isPitchEnabled = false
        mapView.pointOfInterestFilter = .excludingAll

        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.emphasisStyle = .muted
        configuration.showsTraffic = false
        mapView.preferredConfiguration = configuration
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(route, breakIndices: breakIndices, on: mapView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var signature: RouteSignature?
        private var previousBreakIndices: [Int] = []

        func update(_ route: [CLLocationCoordinate2D], breakIndices: [Int], on mapView: MKMapView) {
            guard route.count > 1 else { return }
            let incomingSignature = RouteSignature(route: route)
            guard incomingSignature != signature || previousBreakIndices != breakIndices else { return }
            signature = incomingSignature
            previousBreakIndices = breakIndices

            mapView.removeOverlays(mapView.overlays)
            mapView.removeAnnotations(mapView.annotations)

            let polyline = MKPolyline(coordinates: route, count: route.count)
            for segment in WorkoutRouteSegments.split(route, at: breakIndices) where segment.count > 1 {
                mapView.addOverlay(MKPolyline(coordinates: segment, count: segment.count))
            }

            if let first = route.first, let last = route.last {
                let start = MKPointAnnotation()
                start.coordinate = first
                start.title = "Start"
                let finish = MKPointAnnotation()
                finish.coordinate = last
                finish.title = "Finish"
                mapView.addAnnotations([start, finish])
            }

            mapView.setVisibleMapRect(
                polyline.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 54, left: 42, bottom: 54, right: 42),
                animated: false
            )
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(NanoTheme.teal)
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let identifier = "workout-route-marker"
            let marker = mapView.dequeueReusableAnnotationView(
                withIdentifier: identifier
            ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(
                annotation: annotation,
                reuseIdentifier: identifier
            )
            marker.annotation = annotation
            marker.canShowCallout = true
            marker.markerTintColor = annotation.title == "Finish"
                ? UIColor(NanoTheme.orange)
                : UIColor(NanoTheme.teal)
            marker.glyphImage = UIImage(
                systemName: annotation.title == "Finish" ? "flag.fill" : "figure.walk"
            )
            return marker
        }
    }

    private struct RouteSignature: Equatable {
        let count: Int
        let firstLatitude: Double
        let firstLongitude: Double
        let lastLatitude: Double
        let lastLongitude: Double

        init(route: [CLLocationCoordinate2D]) {
            count = route.count
            firstLatitude = route.first?.latitude ?? 0
            firstLongitude = route.first?.longitude ?? 0
            lastLatitude = route.last?.latitude ?? 0
            lastLongitude = route.last?.longitude ?? 0
        }
    }
}

private struct WorkoutHistoryMonthGroup: Identifiable {
    let month: Date
    let workouts: [WorkoutHistoryRecord]

    var id: Date { month }
}

private struct WorkoutHistoryTrendPoint: Identifiable {
    let day: Date
    let minutes: Double

    var id: Date { day }
}

private struct WorkoutHistoryRow: View {
    let workout: WorkoutHistoryRecord
    let distanceUnit: DistanceUnitPreference

    var body: some View {
        HStack(spacing: 13) {
            WorkoutHistoryLeadingArtwork(workout: workout)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(workout.name)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .font(NanoFont.aldrich(13))
                        .foregroundStyle(NanoTheme.text)
                    Spacer()
                    Text(workout.startedAt.formatted(.dateTime.day().month(.abbreviated)))
                        .fixedSize(horizontal: true, vertical: false)
                        .font(NanoFont.aldrich(9))
                        .foregroundStyle(NanoTheme.secondaryText)
                }

                HStack(spacing: 8) {
                    Text(historyDuration(workout.duration))
                    if workout.steps > 0 {
                        Text("\(workout.steps.formatted()) steps")
                    } else if workout.distanceMiles > 0 {
                        Text(formattedDistance(workout.distanceMiles, unit: distanceUnit))
                    }
                    if workout.calories > 0 {
                        Text("\(Int(workout.calories)) kcal")
                    }
                }
                .font(NanoFont.aldrich(9))
                .foregroundStyle(NanoTheme.teal)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Label(workout.sourceName == "Nanobeasts" ? "iPhone" : workout.sourceName.contains("Apple Watch") ? "Apple Watch" : workout.sourceName,
                      systemImage: workout.sourceName.contains("Apple Watch") ? "applewatch" : workout.source == .nanobeasts ? "iphone" : "heart.fill")
                    .font(NanoFont.aldrich(8))
                    .foregroundStyle(NanoTheme.secondaryText)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NanoTheme.secondaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(NanoTheme.surface)
                .stroke(NanoTheme.elevated, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct WorkoutHistoryLeadingArtwork: View {
    let workout: WorkoutHistoryRecord

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let companion = workout.companion {
                    CreatureArtworkView(stage: companion.creatureStage)
                        .padding(4)
                } else {
                    Image(systemName: workout.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(NanoTheme.teal)
                }
            }
            .frame(width: 52, height: 52)
            .background(Circle().fill(NanoTheme.teal.opacity(0.16)))
            .overlay(Circle().stroke(NanoTheme.teal.opacity(0.46), lineWidth: 1))

            if workout.companion != nil {
                Image(systemName: workout.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NanoTheme.background)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(NanoTheme.teal))
                    .overlay(Circle().stroke(NanoTheme.background, lineWidth: 2))
            }
        }
        .frame(width: 56, height: 56)
    }
}

private struct WorkoutHistoryDiscoveriesCard: View {
    let discoveries: [CreatureDiscoveryEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GROWTH MILESTONES FROM THIS WORKOUT")
                .font(NanoFont.aldrich(9))
                .tracking(0.8)
                .foregroundStyle(NanoTheme.orange)

            ForEach(discoveries) { event in
                HStack(spacing: 12) {
                    CreatureArtworkView(stage: event.creatureStage)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Label(event.kind.title, systemImage: event.kind.symbol)
                            .font(NanoFont.aldrich(8))
                            .foregroundStyle(NanoTheme.orange)
                        Text(event.name)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .font(NanoFont.aldrich(12))
                            .foregroundStyle(NanoTheme.text)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(NanoTheme.background.opacity(0.52))
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(NanoTheme.orange.opacity(0.08))
                .stroke(NanoTheme.orange.opacity(0.36), lineWidth: 1)
        )
    }
}

private struct WorkoutHistorySummaryMetric: View {
    let label: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(label, systemImage: symbol)

                .font(NanoFont.aldrich(8))
                .foregroundStyle(NanoTheme.secondaryText)
            Text(value)
                .font(NanoFont.spaceMono(13, bold: true))
                .foregroundStyle(NanoTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(NanoTheme.background.opacity(0.54))
        )
    }
}

private struct WorkoutHistoryPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: configuration.isPressed ? 0.1 : 0.16), value: configuration.isPressed)
    }
}

private func historyDuration(_ duration: TimeInterval) -> String {
    let totalMinutes = max(0, Int(duration.rounded()) / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    if minutes > 0 { return "\(minutes)m" }
    return "<1m"
}

private func formattedDistance(
    _ miles: Double,
    unit: DistanceUnitPreference
) -> String {
    let value = unit == .miles ? miles : miles * 1.609_344
    return value.formatted(.number.precision(.fractionLength(value < 10 ? 2 : 1)))
        + " \(unit.abbreviation.lowercased())"
}

private func formattedPace(
    _ minutesPerMile: Double?,
    unit: DistanceUnitPreference
) -> String {
    guard var pace = minutesPerMile, pace.isFinite, pace > 0 else { return "—" }
    if unit == .kilometers { pace /= 1.609_344 }
    let minutes = Int(pace)
    let seconds = Int((pace - Double(minutes)) * 60)
    return String(
        format: "%d'%02d\"/%@",
        minutes,
        seconds,
        unit.abbreviation.lowercased()
    )
}
