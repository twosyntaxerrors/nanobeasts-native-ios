import Combine
import CoreLocation
import Foundation
import UIKit

struct WorkoutTerritoryCell: Hashable, Identifiable {
    static let span = 0.00045

    let latitudeIndex: Int
    let longitudeIndex: Int

    var id: String { "\(latitudeIndex):\(longitudeIndex)" }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (Double(latitudeIndex) + 0.5) * Self.span,
            longitude: (Double(longitudeIndex) + 0.5) * Self.span
        )
    }

    init(coordinate: CLLocationCoordinate2D) {
        latitudeIndex = Int(floor(coordinate.latitude / Self.span))
        longitudeIndex = Int(floor(coordinate.longitude / Self.span))
    }
}

struct WorkoutRouteResumeState {
    let sessionID: String
    let startedAt: Date
    let distanceMiles: Double
    let isPaused: Bool
}

final class WorkoutLocationTracker: NSObject, ObservableObject {
    static let shared = WorkoutLocationTracker()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var hasPreciseLocation: Bool
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    private(set) var recordedLocations: [WorkoutRecordedLocation] = []
    @Published private(set) var routeBreakIndices: [Int] = []
    @Published private(set) var distanceMiles = 0.0
    @Published private(set) var locationError: String?
    @Published private(set) var isTracking = false
    @Published private(set) var clearedTerritory: Set<WorkoutTerritoryCell> = []
    @Published private(set) var exploredRoutes: [[CLLocationCoordinate2D]] = []
    @Published private(set) var lastMeaningfulMovementAt: Date?

    private let manager = CLLocationManager()
    private var backgroundActivitySession: CLBackgroundActivitySession?
    private var authorizationSession: AnyObject?
    private var backgroundDiagnostics: Task<Void, Never>?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var isPreparingForWorkout = false
    private var wantsWorkoutTracking = false
    private var workoutIsPaused = false
    private var currentRouteCommitted = false
    private var activeSessionID: String?
    private var workoutStartedAt: Date?
    private var lastAcceptedLocation: CLLocation?
    private var acceptsLocationsAfter: Date?
    private var lastActiveArchiveWriteAt = Date.distantPast
    private var maximumExpectedSpeed: CLLocationSpeed = 12
    private var importedWatchSessionIDs: Set<UUID> = []
    private var legacyExploredRoutes: [[CLLocationCoordinate2D]] = []
    private var savedHistoryRoutes: [String: [StoredRoute]] = [:]

    override init() {
        authorizationStatus = manager.authorizationStatus
        hasPreciseLocation = manager.accuracyAuthorization == .fullAccuracy
        let legacyRoutes = Self.loadExploredRoutes()
        exploredRoutes = legacyRoutes
        legacyExploredRoutes = legacyRoutes
        if let url = Self.territoryArchiveURL,
           let data = try? Data(contentsOf: url),
           let archive = try? JSONDecoder().decode(TerritoryArchive.self, from: data) {
            importedWatchSessionIDs = Set(archive.watchSessionIDs ?? [])
            let historyRoutes = archive.historyRoutes ?? [:]
            savedHistoryRoutes = historyRoutes
            exploredRoutes = legacyRoutes + historyRoutes.keys.sorted().flatMap { key in
                historyRoutes[key, default: []].map(\.coordinates)
            }
        }
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false

        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.wantsWorkoutTracking, !self.workoutIsPaused else { return }
            // Reassert an interrupted stream without resetting its route or baseline.
            self.beginUpdates()
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.checkpointWorkout() })

        if let archive = Self.loadActiveWorkout() {
            wantsWorkoutTracking = true
            workoutIsPaused = archive.isPaused ?? false
            activeSessionID = archive.sessionID
            maximumExpectedSpeed = archive.maximumExpectedSpeed ?? 12
            restore(archive: archive)

            // Apple requires an active background session and location service
            // to be recreated immediately when iOS relaunches an app in the
            // background. The shared tracker is initialized by the app delegate.
            if !workoutIsPaused, isAuthorized {
                beginUpdates()
            }
        }
    }

    static var persistedActiveSessionID: String? {
        loadActiveWorkout()?.sessionID
    }

    func resumeState(sessionID: String) -> WorkoutRouteResumeState? {
        guard let archive = Self.loadActiveWorkout(), archive.sessionID == sessionID else {
            return nil
        }
        return WorkoutRouteResumeState(
            sessionID: archive.sessionID,
            startedAt: archive.startedAt,
            distanceMiles: max(archive.distanceMiles, 0),
            isPaused: archive.isPaused ?? false
        )
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var needsPermission: Bool {
        authorizationStatus == .notDetermined
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    var needsPreciseLocation: Bool {
        isAuthorized && !hasPreciseLocation
    }

    var hasExploredTerritory: Bool {
        !exploredRoutes.isEmpty
    }

    var hasWorkoutQualityLocation: Bool {
        guard hasPreciseLocation, let currentLocation else { return false }
        return currentLocation.horizontalAccuracy >= 0
            && currentLocation.horizontalAccuracy <= 35
            && currentLocation.timestamp >= Date().addingTimeInterval(-10)
    }

    func requestAccess() {
        locationError = nil
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestPreciseLocationIfNeeded()
            manager.requestLocation()
        case .denied, .restricted:
            locationError = "Location access is off. Enable it in iPhone Settings to center the workout map."
        @unknown default:
            break
        }
    }

    func resetWorkout() {
        clearActiveWorkoutArchive()
        isPreparingForWorkout = false
        wantsWorkoutTracking = false
        workoutIsPaused = false
        isTracking = false
        manager.stopUpdatingLocation()
        endBackgroundActivitySession()
        route = []
        recordedLocations = []
        routeBreakIndices = []
        acceptsLocationsAfter = nil
        distanceMiles = 0
        clearedTerritory = []
        currentRouteCommitted = false
        activeSessionID = nil
        workoutStartedAt = nil
        lastAcceptedLocation = nil
        lastMeaningfulMovementAt = nil
        locationError = nil
    }

#if targetEnvironment(simulator)
    /// App Store screenshot fixture: a finished walk plus earlier walks in the same zone.
    func seedSummaryDemo(route: [CLLocationCoordinate2D], earlierWalks: [[CLLocationCoordinate2D]]) {
        self.route = route
        routeBreakIndices = []
        exploredRoutes = earlierWalks
        distanceMiles = zip(route, route.dropFirst()).reduce(0) { total, pair in
            total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)) / 1_609.344
        }
        currentLocation = route.last.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        isTracking = false
        locationError = nil
    }

    func seedTerritoryDemo() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 40.6990, longitude: -73.9255),
            CLLocationCoordinate2D(latitude: 40.6997, longitude: -73.9242),
            CLLocationCoordinate2D(latitude: 40.7005, longitude: -73.9233),
            CLLocationCoordinate2D(latitude: 40.7012, longitude: -73.9220),
            CLLocationCoordinate2D(latitude: 40.7010, longitude: -73.9207),
            CLLocationCoordinate2D(latitude: 40.7003, longitude: -73.9196),
            CLLocationCoordinate2D(latitude: 40.6994, longitude: -73.9201),
            CLLocationCoordinate2D(latitude: 40.6988, longitude: -73.9190),
            CLLocationCoordinate2D(latitude: 40.6981, longitude: -73.9178),
        ]

        route = coordinates
        clearedTerritory = []
        distanceMiles = 0
        for (start, end) in zip(coordinates, coordinates.dropFirst()) {
            let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
            let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
            let distance = endLocation.distance(from: startLocation)
            distanceMiles += distance / 1_609.344
            registerTerritory(from: start, to: end, distance: distance)
        }
        if let last = coordinates.last {
            currentLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
        }
        isTracking = true
        locationError = nil
    }
#endif

    func startWorkout(
        sessionID: String,
        maximumExpectedSpeed: CLLocationSpeed = 12
    ) {
        clearActiveWorkoutArchive()
        route = []
        recordedLocations = []
        routeBreakIndices = []
        acceptsLocationsAfter = nil
        distanceMiles = 0
        clearedTerritory = []
        currentRouteCommitted = false
        activeSessionID = sessionID
        let startedAt = Date()
        workoutStartedAt = startedAt
        acceptsLocationsAfter = startedAt.addingTimeInterval(-8)
        lastAcceptedLocation = nil
        lastMeaningfulMovementAt = nil
        locationError = nil
        wantsWorkoutTracking = true
        workoutIsPaused = false
        self.maximumExpectedSpeed = max(3, maximumExpectedSpeed)

        // Reuse the accurate foreground fix gathered during the countdown so
        // the recorded route does not begin with a coarse GPS acquisition jump.
        if let currentLocation,
           currentLocation.horizontalAccuracy >= 0,
           currentLocation.horizontalAccuracy <= 35,
           currentLocation.timestamp >= startedAt.addingTimeInterval(-8) {
            append(currentLocation)
        }
        isPreparingForWorkout = false
        persistActiveWorkout(force: true)

        guard isAuthorized else {
            requestAccess()
            return
        }
        beginUpdates()
    }

    func restoreWorkout(sessionID: String, isPaused: Bool) {
        locationError = nil
        wantsWorkoutTracking = true
        workoutIsPaused = isPaused
        activeSessionID = sessionID
        restoreActiveWorkout(sessionID: sessionID)

        guard !isPaused else {
            isTracking = false
            return
        }
        guard isAuthorized else {
            requestAccess()
            return
        }
        beginUpdates()
    }

    func stopWorkout(commitRoute: Bool = true) {
        persistActiveWorkout(force: true)
        wantsWorkoutTracking = false
        workoutIsPaused = false
        isTracking = false
        manager.stopUpdatingLocation()
        endBackgroundActivitySession()
        if commitRoute {
            commitCurrentRouteIfNeeded()
        }
        clearActiveWorkoutArchive()
        activeSessionID = nil
        workoutStartedAt = nil
        lastAcceptedLocation = nil
    }

    func historyRouteSnapshot() -> [CLLocationCoordinate2D] {
        route.filter(CLLocationCoordinate2DIsValid)
    }

    func pauseWorkout() {
        guard wantsWorkoutTracking else { return }
        workoutIsPaused = true
        lastAcceptedLocation = nil
        persistActiveWorkout(force: true)
        isTracking = false
        manager.stopUpdatingLocation()
        endBackgroundActivitySession()
    }

    func resumeWorkout() {
        guard wantsWorkoutTracking, isAuthorized else { return }
        workoutIsPaused = false
        lastAcceptedLocation = nil
        acceptsLocationsAfter = Date()
        persistActiveWorkout(force: true)
        beginUpdates()
    }

    func checkpointWorkout() {
        guard wantsWorkoutTracking else { return }
        persistActiveWorkout(force: true)
    }

    func prepareForWorkout() {
        guard !wantsWorkoutTracking else { return }
        isPreparingForWorkout = true
        guard isAuthorized else {
            requestAccess()
            return
        }
        requestPreciseLocationIfNeeded()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.startUpdatingLocation()
    }

    func stopPreparingForWorkout() {
        guard isPreparingForWorkout, !wantsWorkoutTracking else { return }
        isPreparingForWorkout = false
        manager.stopUpdatingLocation()
    }

    private func beginUpdates() {
        guard !workoutIsPaused else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            locationError = "Location Services are unavailable."
            return
        }
        requestPreciseLocationIfNeeded()
        if #available(iOS 18.0, *), authorizationSession == nil {
            authorizationSession = CLServiceSession(authorization: .whenInUse)
        }
        if backgroundActivitySession == nil {
            let session = CLBackgroundActivitySession()
            backgroundActivitySession = session
            if #available(iOS 18.0, *) {
                backgroundDiagnostics = Task { @MainActor [weak self] in
                    do {
                        for try await diagnostic in session.diagnostics {
                            guard !Task.isCancelled, let self else { return }
                            let blocked = diagnostic.authorizationDenied || diagnostic.authorizationDeniedGlobally
                                || diagnostic.authorizationRestricted || diagnostic.insufficientlyInUse
                                || diagnostic.serviceSessionRequired
                            // Keep a small diagnostic snapshot so a missing route
                            // can be diagnosed without inventing GPS coordinates.
                            UserDefaults.standard.set([
                                "at": Date().timeIntervalSince1970,
                                "insufficientlyInUse": diagnostic.insufficientlyInUse,
                                "authorizationDenied": diagnostic.authorizationDenied,
                                "authorizationDeniedGlobally": diagnostic.authorizationDeniedGlobally,
                                "serviceSessionRequired": diagnostic.serviceSessionRequired
                            ], forKey: "nanobeasts.workout.background-location-diagnostic")
                            if blocked {
                                self.locationError = "Route recording is interrupted. Open Nanobeasts and check Location access."
                            }
                        }
                    } catch { /* A cancelled session is expected at pause/finish. */ }
                }
            }
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        isTracking = true
    }

    private func endBackgroundActivitySession() {
        backgroundDiagnostics?.cancel()
        backgroundDiagnostics = nil
        if #available(iOS 18.0, *) { (authorizationSession as? CLServiceSession)?.invalidate() }
        authorizationSession = nil
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
    }

    private func requestPreciseLocationIfNeeded() {
        guard manager.accuracyAuthorization == .reducedAccuracy else { return }
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "WorkoutRoute")
    }
}

extension WorkoutLocationTracker: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            authorizationStatus = manager.authorizationStatus
            hasPreciseLocation = manager.accuracyAuthorization == .fullAccuracy
            if wantsWorkoutTracking, !workoutIsPaused, isAuthorized {
                beginUpdates()
            } else if isPreparingForWorkout, isAuthorized {
                prepareForWorkout()
            } else if isDenied {
                locationError = "Location access is off. Enable it in iPhone Settings to record your route."
            }
        }
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        guard wantsWorkoutTracking, !workoutIsPaused else { return }
        beginUpdates()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let orderedLocations = locations.sorted { $0.timestamp < $1.timestamp }

            if let latest = orderedLocations.last(where: isUsableMapLocation),
               latest.timestamp >= Date().addingTimeInterval(-10),
               latest.timestamp >= (currentLocation?.timestamp ?? .distantPast) {
                currentLocation = latest
            }
            guard wantsWorkoutTracking, !workoutIsPaused else { return }
            var acceptedAnyLocation = false

            for location in orderedLocations {
                let decision = WorkoutRouteFilter.evaluate(
                    location,
                    previous: lastAcceptedLocation,
                    after: acceptsLocationsAfter,
                    now: Date(),
                    maximumSpeed: maximumExpectedSpeed
                )
                guard decision != .reject else { continue }
                if decision == .startSegment { lastAcceptedLocation = nil }
                append(location)
                locationError = nil
                acceptedAnyLocation = true
            }

            if acceptedAnyLocation {
                persistActiveWorkout(force: false)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        DispatchQueue.main.async { [weak self] in
            self?.locationError = error.localizedDescription
        }
    }

    private func registerTerritory(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        distance: CLLocationDistance
    ) {
        let sampleCount = max(1, Int(ceil(distance / 18)))
        for step in 0...sampleCount {
            let progress = Double(step) / Double(sampleCount)
            let coordinate = CLLocationCoordinate2D(
                latitude: start.latitude + (end.latitude - start.latitude) * progress,
                longitude: start.longitude + (end.longitude - start.longitude) * progress
            )
            clearedTerritory.insert(WorkoutTerritoryCell(coordinate: coordinate))
        }
    }

    private func isUsableMapLocation(_ location: CLLocation) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy >= 0
            && location.timestamp <= Date().addingTimeInterval(10)
    }

    private func append(_ location: CLLocation) {
        if let previous = lastAcceptedLocation {
            let segmentDistance = location.distance(from: previous)
            distanceMiles += segmentDistance / 1_609.344
            registerTerritory(
                from: previous.coordinate,
                to: location.coordinate,
                distance: segmentDistance
            )

            let time = max(location.timestamp.timeIntervalSince(previous.timestamp), 0.25)
            let measuredSpeed = location.speed >= 0
                ? location.speed
                : segmentDistance / time
            if location.horizontalAccuracy <= 30,
               measuredSpeed >= 0.35,
               measuredSpeed <= 25 {
                lastMeaningfulMovementAt = location.timestamp
            }
        } else {
            if !route.isEmpty { routeBreakIndices.append(route.count) }
            clearedTerritory.insert(WorkoutTerritoryCell(coordinate: location.coordinate))
        }

        route.append(location.coordinate)
        recordedLocations.append(WorkoutRecordedLocation(location))
        lastAcceptedLocation = location
    }

    private func restoreActiveWorkout(sessionID: String) {
        guard let archive = Self.loadActiveWorkout(),
              archive.sessionID == sessionID
        else {
            workoutStartedAt = Date()
            persistActiveWorkout(force: true)
            return
        }

        maximumExpectedSpeed = archive.maximumExpectedSpeed ?? maximumExpectedSpeed
        restore(archive: archive)
    }

    private func restore(archive: ActiveWorkoutArchive) {

        let restoredRoute = archive.points.compactMap { point -> CLLocationCoordinate2D? in
            let coordinate = CLLocationCoordinate2D(
                latitude: point.latitude,
                longitude: point.longitude
            )
            return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
        }
        route = restoredRoute
        recordedLocations = archive.recordedLocations ?? []
        routeBreakIndices = archive.routeBreakIndices ?? []
        acceptsLocationsAfter = archive.acceptsLocationsAfter ?? archive.startedAt.addingTimeInterval(-8)
        distanceMiles = max(archive.distanceMiles, 0)
        workoutStartedAt = archive.startedAt
        lastMeaningfulMovementAt = archive.lastMeaningfulMovementAt
        currentRouteCommitted = false
        clearedTerritory = []

        for segment in WorkoutRouteSegments.split(restoredRoute, at: routeBreakIndices) {
            for (start, end) in zip(segment, segment.dropFirst()) {
                let distance = CLLocation(latitude: end.latitude, longitude: end.longitude)
                    .distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude))
                registerTerritory(from: start, to: end, distance: distance)
            }
        }
        if let first = restoredRoute.first {
            clearedTerritory.insert(WorkoutTerritoryCell(coordinate: first))
        }

        if let last = archive.lastLocation?.location {
            lastAcceptedLocation = last
            currentLocation = last
        } else {
            // No timestamped fix means no trustworthy distance baseline.
            lastAcceptedLocation = nil
            if let last = restoredRoute.last {
                currentLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
            }
        }
    }

    private func persistActiveWorkout(force: Bool) {
        guard let activeSessionID else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastActiveArchiveWriteAt) >= 5 else { return }

        let archive = ActiveWorkoutArchive(
            version: ActiveWorkoutArchive.currentVersion,
            sessionID: activeSessionID,
            startedAt: workoutStartedAt ?? now,
            distanceMiles: distanceMiles,
            lastMeaningfulMovementAt: lastMeaningfulMovementAt,
            lastLocation: lastAcceptedLocation.map(StoredActiveLocation.init),
            isPaused: workoutIsPaused,
            maximumExpectedSpeed: maximumExpectedSpeed,
            routeBreakIndices: routeBreakIndices,
            acceptsLocationsAfter: acceptsLocationsAfter,
            recordedLocations: recordedLocations,
            points: route.map {
                StoredCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            }
        )
        guard let url = Self.activeWorkoutArchiveURL else { return }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(archive).write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
            lastActiveArchiveWriteAt = now
        } catch {
#if DEBUG
            print("Could not checkpoint active workout route: \(error)")
#endif
        }
    }

    private func clearActiveWorkoutArchive() {
        guard let url = Self.activeWorkoutArchiveURL else { return }
        try? FileManager.default.removeItem(at: url)
        lastActiveArchiveWriteAt = .distantPast
    }

    private static func loadActiveWorkout() -> ActiveWorkoutArchive? {
        guard let url = activeWorkoutArchiveURL,
              let data = try? Data(contentsOf: url),
              let archive = try? JSONDecoder().decode(ActiveWorkoutArchive.self, from: data),
              archive.version == ActiveWorkoutArchive.currentVersion
        else { return nil }
        return archive
    }

    private func commitCurrentRouteIfNeeded() {
        guard !currentRouteCommitted, route.count > 1 else { return }
        let segments = WorkoutRouteSegments.split(route, at: routeBreakIndices)
            .map(Self.simplified).filter { $0.count > 1 }
        guard !segments.isEmpty else { return }

        legacyExploredRoutes.append(contentsOf: segments)
        currentRouteCommitted = true
        publishTerritory()
    }

    func importWatchTerritory(_ result: WatchWorkoutResult) {
        guard !result.snapshot.isActive, !result.snapshot.indoor,
              result.snapshot.hasRecordedActivity,
              !importedWatchSessionIDs.contains(result.snapshot.id) else { return }
        let segments = WorkoutRouteSegments.split(
            result.locations.map { $0.location.coordinate }, at: result.breakIndices
        ).map(Self.simplified).filter { $0.count > 1 }
        guard !segments.isEmpty else { return }
        legacyExploredRoutes.append(contentsOf: segments)
        importedWatchSessionIDs.insert(result.snapshot.id)
        publishTerritory()
    }

    func restoreSavedTerritory(_ routes: [UUID: [[CLLocationCoordinate2D]]]) {
        var changed = false
        for (id, segments) in routes {
            let saved = segments.filter { $0.count > 1 }.map { segment in
                StoredRoute(points: segment.map {
                    StoredCoordinate(latitude: $0.latitude, longitude: $0.longitude)
                })
            }
            guard !saved.isEmpty, savedHistoryRoutes[id.uuidString] != saved else { continue }
            // Replace a partial route when the complete Watch/Health archive
            // arrives. Reopening the map must never append the same walk again.
            savedHistoryRoutes[id.uuidString] = saved
            changed = true
        }
        if changed { publishTerritory() }
    }

    private func publishTerritory() {
        exploredRoutes = legacyExploredRoutes + savedHistoryRoutes.keys.sorted().flatMap { key in
            savedHistoryRoutes[key, default: []].map(\.coordinates)
        }
        Self.persist(exploredRoutes: legacyExploredRoutes,
                     watchSessionIDs: importedWatchSessionIDs, historyRoutes: savedHistoryRoutes)
        let routes = exploredRoutes
        Task { @MainActor in WorkoutZoneCelebrations.shared.territoryChanged(routes) }
    }

    private static func simplified(
        _ route: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        guard let first = route.first, let last = route.last else { return [] }
        let minimumSpacing: CLLocationDistance = 8
        var result = [first]
        var previous = CLLocation(latitude: first.latitude, longitude: first.longitude)

        for coordinate in route.dropFirst().dropLast() {
            let location = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            guard location.distance(from: previous) >= minimumSpacing else { continue }
            result.append(coordinate)
            previous = location
        }

        if abs((result.last?.latitude ?? first.latitude) - last.latitude) > 0.000_000_1
            || abs((result.last?.longitude ?? first.longitude) - last.longitude) > 0.000_000_1
        {
            result.append(last)
        }
        return result
    }

    private static func loadExploredRoutes() -> [[CLLocationCoordinate2D]] {
        guard
            let url = territoryArchiveURL,
            let data = try? Data(contentsOf: url),
            let archive = try? JSONDecoder().decode(TerritoryArchive.self, from: data),
            archive.version == TerritoryArchive.currentVersion
        else {
            return []
        }

        return archive.routes.compactMap { storedRoute in
            let route = storedRoute.points.compactMap { point -> CLLocationCoordinate2D? in
                let coordinate = CLLocationCoordinate2D(
                    latitude: point.latitude,
                    longitude: point.longitude
                )
                return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
            }
            return route.count > 1 ? route : nil
        }
    }

    private static func persist(exploredRoutes: [[CLLocationCoordinate2D]], watchSessionIDs: Set<UUID>,
                                historyRoutes: [String: [StoredRoute]]) {
        guard let url = territoryArchiveURL else { return }
        let archive = TerritoryArchive(
            version: TerritoryArchive.currentVersion,
            routes: exploredRoutes.map { route in
                StoredRoute(
                    points: route.map {
                        StoredCoordinate(latitude: $0.latitude, longitude: $0.longitude)
                    }
                )
            },
            watchSessionIDs: Array(watchSessionIDs),
            historyRoutes: historyRoutes
        )

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(archive)
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
#if DEBUG
            print("Could not persist explored workout territory: \(error)")
#endif
        }
    }

    private static var territoryArchiveURL: URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("Nanobeasts", isDirectory: true)
            .appendingPathComponent("explored-territory-v1.json", isDirectory: false)
    }

    private static var activeWorkoutArchiveURL: URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("Nanobeasts", isDirectory: true)
            .appendingPathComponent("active-workout-route-v1.json", isDirectory: false)
    }

    private struct ActiveWorkoutArchive: Codable {
        static let currentVersion = 1

        let version: Int
        let sessionID: String
        let startedAt: Date
        let distanceMiles: Double
        let lastMeaningfulMovementAt: Date?
        let lastLocation: StoredActiveLocation?
        let isPaused: Bool?
        let maximumExpectedSpeed: Double?
        let routeBreakIndices: [Int]?
        let acceptsLocationsAfter: Date?
        let recordedLocations: [WorkoutRecordedLocation]?
        let points: [StoredCoordinate]
    }

    private struct StoredActiveLocation: Codable {
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let horizontalAccuracy: Double
        let verticalAccuracy: Double
        let course: Double
        let speed: Double
        let timestamp: Date

        init(_ location: CLLocation) {
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            altitude = location.altitude
            horizontalAccuracy = location.horizontalAccuracy
            verticalAccuracy = location.verticalAccuracy
            course = location.course
            speed = location.speed
            timestamp = location.timestamp
        }

        var location: CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                altitude: altitude,
                horizontalAccuracy: horizontalAccuracy,
                verticalAccuracy: verticalAccuracy,
                course: course,
                speed: speed,
                timestamp: timestamp
            )
        }
    }

    private struct TerritoryArchive: Codable {
        static let currentVersion = 1

        let version: Int
        let routes: [StoredRoute]
        var watchSessionIDs: [UUID]?
        var historyRoutes: [String: [StoredRoute]]?
    }

    private struct StoredRoute: Codable, Equatable {
        let points: [StoredCoordinate]
        var coordinates: [CLLocationCoordinate2D] {
            points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
    }

    private struct StoredCoordinate: Codable, Equatable {
        let latitude: Double
        let longitude: Double
    }
}
