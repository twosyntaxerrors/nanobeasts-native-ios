import Combine
import CoreLocation
import CoreMotion
import HealthKit
import ImageIO
import WatchConnectivity
import WatchKit

@MainActor
final class WatchWorkoutRecorder: NSObject, ObservableObject {
    static let shared = WatchWorkoutRecorder()
    @Published var snapshot: WatchWorkoutSnapshot?
    @Published var isStarting = false
    @Published var startError: String?
    @Published var routePointCount = 0
    @Published private(set) var countdown: Int?
    @Published private(set) var startingWorkoutName = ""
    @Published private(set) var lastGPSFix: Date?

    @Published private(set) var routeNotice: String?
    @Published private(set) var motionNotice: String?
    @Published private(set) var milestone: WatchWorkoutMilestone?
    @Published private(set) var subscriptionAccess: NanoSubscriptionAccess?
    var hasSubscriptionAccess: Bool { subscriptionAccess?.allowsAccess(at: Date()) == true }
    @Published private(set) var companionArtwork: WatchCompanionArtwork?
    @Published private(set) var companionImage: UIImage?
    @Published private(set) var companionAnimationFrames: [UIImage] = []
    @Published private(set) var locationStatus = CLAuthorizationStatus.notDetermined
    @Published private(set) var locationAccuracy = CLAccuracyAuthorization.reducedAccuracy

    var locationAccess: WatchLocationAccess {
        WatchLocationAccess(status: locationStatus, accuracy: locationAccuracy)
    }

    private let activityManager = CMMotionActivityManager()
    private var autoPausePolicy = WatchAutoPausePolicy()
    private var milestonePolicy = WatchMilestonePolicy()
    private var milestoneQueue: [WatchWorkoutMilestone] = []
    private var milestoneTask: Task<Void, Never>?
    private var motionGeneration = UUID()
    private var automaticTransitionPending = false
    private var routeIsUpdating = false
    private let store = HKHealthStore()
    private let locationManager = CLLocationManager()
    private let pedometer = CMPedometer()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var timer: Timer?
    private var locations: [WorkoutRecordedLocation] = []
    private var lastLivePublishAt = Date.distantPast
    private var lastLivePublishPhase: WatchWorkoutSnapshot.Phase?
    private var lastLivePublishSessionID: UUID?
    private var breaks: [Int] = []
    private var previousLocation: CLLocation?
    private var acceptsAfter: Date?
    private var baseSteps = 0
    private var stepSegment: Date?
    private var saving = false
    private var stoppedAt: Date?
    private var saveToHealth = true
    private var lastCheckpoint = Date.distantPast
    private var startWasCancelled = false

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: NanoSubscriptionAccess.cacheKey) {
            subscriptionAccess = try? JSONDecoder().decode(NanoSubscriptionAccess.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: WatchCompanionArtwork.cacheKey) {
            receiveCompanion(data)
        }
        locationManager.delegate = self
        // When In Use must remain effective during a wrist-down workout. The
        // matching UIBackgroundModes/location entry is required on watchOS too.
        locationManager.allowsBackgroundLocationUpdates = true
        refreshLocationStatus()
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func start(activity: HKWorkoutActivityType, indoor: Bool, displayName: String? = nil) async {
        guard !isStarting, snapshot?.isActive != true else { return }
        guard hasSubscriptionAccess else {
            startError = "Open Nanobeasts on your iPhone to start or restore Pro."
            refreshCompanion()
            return
        }
        isStarting = true
        startWasCancelled = false
        startingWorkoutName = displayName ?? Self.presentation(activity: activity, indoor: indoor).name
        startError = nil
        routeNotice = nil; motionNotice = nil
        dismissMilestones()
        defer { isStarting = false; countdown = nil }
        do {
            if await phoneIsRecording() {
                throw RecorderError.message("Nanobeasts is already recording on your iPhone. Finish that workout before starting another on your Watch.")
            }
            let distance = HKQuantityType(.distanceWalkingRunning)
            let energy = HKQuantityType(.activeEnergyBurned)
            saveToHealth = UserDefaults.standard.object(forKey: "saveWorkoutsToHealth") as? Bool ?? true
            let wantsRoute = !indoor && preference("recordGPSRoute")
            var share: Set<HKSampleType> = saveToHealth ? [HKObjectType.workoutType(), distance, energy] : []
            if saveToHealth && wantsRoute { share.insert(HKSeriesType.workoutRoute()) }
            let read: Set<HKObjectType> = [distance, energy, HKQuantityType(.heartRate), HKQuantityType(.stepCount)]
            let requestedShare = share
            try await WatchAuthorizationQueue.shared.perform { [store] in
                let status = try await store.statusForAuthorizationRequest(toShare: requestedShare, read: read)
                try Task.checkCancellation()
                if status == .shouldRequest {
                    try await store.requestAuthorization(toShare: requestedShare, read: read)
                }
            }
            if saveToHealth, store.authorizationStatus(for: HKObjectType.workoutType()) != .sharingAuthorized {
                throw RecorderError.message("Allow Nanobeasts to save Workouts in Health, or turn off Save to Health in Nano Settings.")
            }
            if wantsRoute {
                // The system owns permission persistence, including the user's Allow Once choice.
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestWhenInUseAuthorization()
                    for _ in 0..<150 where locationManager.authorizationStatus == .notDetermined {
                        guard !startWasCancelled else { throw CancellationError() }
                        try await Task.sleep(for: .milliseconds(200))
                    }
                }
                refreshLocationStatus()
            }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = activity
            configuration.locationType = indoor ? .indoor : .outdoor
            for remaining in (1...3).reversed() {
                try Task.checkCancellation()
                guard !startWasCancelled else { throw CancellationError() }
                countdown = remaining
                try await Task.sleep(for: .seconds(1))
            }
            guard !startWasCancelled else { throw CancellationError() }
            countdown = nil
            let workoutSession = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let workoutBuilder = workoutSession.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            // Live step samples arrive between Core Motion's batched pedometer
            // deliveries; whichever source is ahead drives the live readout.
            dataSource.enableCollection(for: HKQuantityType(.stepCount), predicate: nil)
            workoutBuilder.dataSource = dataSource
            let now = Date()
            let type = Self.presentation(activity: activity, indoor: indoor)
            snapshot = WatchWorkoutSnapshot(id: UUID(), workoutID: type.id, name: displayName ?? type.name, indoor: indoor,
                startedAt: now, updatedAt: now, elapsed: 0, steps: 0, distanceMiles: 0, calories: 0, phase: .running)
            snapshot?.routeEnabled = wantsRoute
            if let progress = companionArtwork?.evolution {
                snapshot?.evolutionAnchor = WorkoutEvolutionAnchor(totalCreditedSteps: progress.totalCreditedSteps)
            }
            snapshot?.automaticallyPaused = false
            milestonePolicy = WatchMilestonePolicy()
            autoPausePolicy.reset()
            automaticTransitionPending = false
            locations = []; breaks = []; previousLocation = nil; routePointCount = 0
            lastGPSFix = nil
            acceptsAfter = now.addingTimeInterval(-8)
            saving = false
            stoppedAt = nil
            attach(workoutSession, builder: workoutBuilder)
            workoutSession.startActivity(with: now)
            try await workoutBuilder.beginCollection(at: now)
            startRouteIfAllowed()
            startMotionMonitoring()
            startSteps()
            startTimer()
            checkpoint(force: true)
            // Losing the companion connection must not prevent a Watch-only walk.
            try? await workoutSession.startMirroringToCompanionDevice()
            publish()
            publishCompanionStatus()
        } catch {
            startError = error is CancellationError ? nil : error.localizedDescription
            session?.end()
            stopRoute()
            stopMotionMonitoring()
            pedometer.stopUpdates()
            timer?.invalidate(); timer = nil
            self.session = nil; self.builder = nil
            snapshot = nil
        }
    }

    func cancelStart() { startWasCancelled = true }

    private func preference(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    func refreshLocationStatus() {
        locationStatus = locationManager.authorizationStatus
        locationAccuracy = locationManager.accuracyAuthorization
        routeNotice = locationAccess.notice
        writeLocationDiagnostics()
    }

    /// Recover a stopped stream on foreground return without asking again or
    /// altering the user's saved route switch. A paused workout stays paused.
    func restoreLocationForActiveWorkout() {
        refreshLocationStatus()
        startRouteIfAllowed()
    }

    func enableLocationFromSettings() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        refreshLocationStatus()
    }

    private func startRouteIfAllowed() {
        guard let state = snapshot else { return }
        refreshLocationStatus()
        guard locationAccess.shouldResumeRoute(running: state.phase == .running, indoor: state.indoor,
                                               routeEnabled: state.routeEnabled != false, saving: saving) else { return }
        guard !routeIsUpdating else { return }
        previousLocation = nil
        acceptsAfter = Date()
        routeIsUpdating = true
        locationManager.startUpdatingLocation()
    }

    private func writeLocationDiagnostics() {
#if DEBUG
        // Only permission/configuration state: no coordinates, Health data, or
        // other preferences. This lets device checks verify persistence safely.
        let values: [String: Any] = ["locationStatus": locationStatus.rawValue,
            "fullAccuracy": locationAccuracy == .fullAccuracy,
            "backgroundUpdates": locationManager.allowsBackgroundLocationUpdates,
            "gpsRoutesEnabled": preference("recordGPSRoute"),
            "hasActiveWorkout": snapshot?.isActive == true]
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("nano-location-state.json"), options: .atomic)
#endif
    }

    private func stopRoute() {
        routeIsUpdating = false
        locationManager.stopUpdatingLocation()
        previousLocation = nil
        lastGPSFix = nil
    }

    private func startMotionMonitoring() {
        stopMotionMonitoring()
        guard preference("workoutAutoPause") else { return }
        let generation = motionGeneration
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: .main) { [weak self] activity in
                Task { @MainActor in
                    guard let self, self.motionGeneration == generation, let activity else { return }
                    let motion: WatchAutoPausePolicy.Motion
                    if activity.confidence == .low { motion = .unknown }
                    else if activity.walking || activity.running { motion = .moving }
                    else if activity.stationary && !activity.automotive && !activity.cycling { motion = .stationary }
                    else { motion = .unknown }
                    // The first callback may describe activity from before this workout.
                    self.autoPausePolicy.observe(motion, at: max(activity.startDate, self.motionStartedAt))
                }
            }
        }
        if CMPedometer.isPedometerEventTrackingAvailable() {
            pedometer.startEventUpdates { [weak self] event, error in
                Task { @MainActor in
                    guard let self, self.motionGeneration == generation else { return }
                    if error != nil {
                        self.autoPausePolicy.observe(.unknown, at: Date())
                        self.motionNotice = "Motion detection is unavailable. Use Pause in workout controls."
                    }
                    guard let event, event.date >= self.motionStartedAt else { return }
                    self.autoPausePolicy.observe(event.type == .pause ? .stationary : .moving, at: event.date)
                }
            }
        } else if !CMMotionActivityManager.isActivityAvailable() {
            motionNotice = "Auto-pause is unavailable on this Watch. Use Pause in workout controls."
        }
        if CMMotionActivityManager.authorizationStatus() == .denied || CMPedometer.authorizationStatus() == .denied {
            motionNotice = "Allow Motion & Fitness in Watch Settings for steps and auto-pause."
        }
    }

    private var motionStartedAt = Date()

    private func stopMotionMonitoring() {
        motionGeneration = UUID()
        motionStartedAt = Date()
        activityManager.stopActivityUpdates()
        pedometer.stopEventUpdates()
        autoPausePolicy.reset()
        automaticTransitionPending = false
    }

    private func evaluateAutoPause(at date: Date) {
        guard !saving, stoppedAt == nil, preference("workoutAutoPause"), !automaticTransitionPending,
              let session, let snapshot, snapshot.phase == .running || snapshot.phase == .paused else { return }
        switch autoPausePolicy.action(at: date, running: snapshot.phase == .running,
                                      automaticallyPaused: snapshot.automaticallyPaused == true) {
        case .pause where session.state == .running:
            automaticTransitionPending = true
            self.snapshot?.automaticallyPaused = true
            session.pause()
        case .resume where session.state == .paused:
            automaticTransitionPending = true
            session.resume()
        default: break
        }
    }

    private func updateMilestones() {
        guard !saving, stoppedAt == nil, let state = snapshot else { return }
        let events = milestonePolicy.update(steps: state.steps, miles: state.distanceMiles, elapsed: state.elapsed)
        snapshot?.milestoneStepMark = milestonePolicy.stepMark
        snapshot?.milestoneMileMark = milestonePolicy.mileMark
        snapshot?.lastMileElapsed = milestonePolicy.lastMileElapsed
        guard preference("workoutMilestones"), !events.isEmpty else { return }
        milestoneQueue.append(contentsOf: events)
        // Bound delayed catch-up feedback while retaining both step and mile alerts.
        milestoneQueue = Array(milestoneQueue.suffix(4))
        showNextMilestone()
    }

    private func showNextMilestone() {
        guard milestone == nil, !milestoneQueue.isEmpty else { return }
        milestone = milestoneQueue.removeFirst()
        WKInterfaceDevice.current().play(.notification)
        milestoneTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(7)) } catch { return }
            self?.dismissMilestone()
        }
    }

    func dismissMilestone() {
        milestoneTask?.cancel(); milestoneTask = nil
        milestone = nil
        showNextMilestone()
    }

    private func dismissMilestones() {
        milestoneQueue = []
        milestoneTask?.cancel(); milestoneTask = nil
        milestone = nil
    }

    func retryPendingTransfers() {
        refreshCompanion()
        let connectivity = WCSession.default
        guard connectivity.activationState == .activated,
              let files = try? FileManager.default.contentsOfDirectory(at: Self.archiveURL.deletingLastPathComponent(), includingPropertiesForKeys: nil) else { return }
        let queued = Set(connectivity.outstandingFileTransfers.map { $0.file.fileURL.standardizedFileURL })
        for file in files where file.lastPathComponent.hasPrefix("transfer-") && !queued.contains(file.standardizedFileURL) {
            connectivity.transferFile(file, metadata: ["nanobeastsWorkout": true])
        }
    }

    private func receiveCompanion(_ data: Data) {
        guard let artwork = try? JSONDecoder().decode(WatchCompanionArtwork.self, from: data),
              artwork.supersedes(companionArtwork) else { return }
        // If this is the first progress payload during an existing session,
        // anchor here instead of counting its earlier steps a second time.
        if snapshot?.isActive == true, snapshot?.evolutionAnchor == nil,
           let progress = artwork.evolution {
            snapshot?.evolutionAnchor = WorkoutEvolutionAnchor(
                totalCreditedSteps: progress.totalCreditedSteps, workoutSteps: snapshot?.steps ?? 0)
        }
        let artworkChanged = companionArtwork?.stageID != artwork.stageID
            || companionArtwork?.pngData != artwork.pngData
            || companionArtwork?.animationData != artwork.animationData
        companionArtwork = artwork
        UserDefaults.standard.set(data, forKey: WatchCompanionArtwork.cacheKey)
        guard artworkChanged else { return }
        companionImage = artwork.pngData.flatMap { UIImage(data: $0) }
        companionAnimationFrames = []
        if let data = artwork.animationData, data.count <= 18_000,
           let source = CGImageSourceCreateWithData(data as CFData, nil) {
            companionAnimationFrames = (0..<min(16, CGImageSourceGetCount(source))).compactMap {
                CGImageSourceCreateImageAtIndex(source, $0, nil).map { UIImage(cgImage: $0) }
            }
        }
        UserDefaults.standard.set(data, forKey: WatchCompanionArtwork.cacheKey)
    }

    private func receivePhoneContext(_ context: [String: Any]) {
        if let data = context[NanoSubscriptionAccess.contextKey] as? Data,
           let access = try? JSONDecoder().decode(NanoSubscriptionAccess.self, from: data),
           access.updatedAt >= (subscriptionAccess?.updatedAt ?? .distantPast) {
            subscriptionAccess = access
            UserDefaults.standard.set(data, forKey: NanoSubscriptionAccess.cacheKey)
        }
        if let data = context[WatchInterfaceAppearance.contextKey] as? Data {
            WatchAppearanceStore.shared.receive(data)
        }
        if let data = context[WatchCompanionArtwork.contextKey] as? Data { receiveCompanion(data) }
    }

    func refreshCompanion() {
        let connectivity = WCSession.default
        guard connectivity.activationState == .activated else { return }
        receivePhoneContext(connectivity.receivedApplicationContext)
        guard connectivity.isReachable else { return }
        connectivity.sendMessage(["queryCompanion": true], replyHandler: { reply in
            Task { @MainActor in self.receivePhoneContext(reply) }
        }, errorHandler: { _ in /* Keep the last synced creature when offline. */ })
    }

    func pauseOrResume() {
        guard let session else { return }
        autoPausePolicy.reset()
        snapshot?.automaticallyPaused = false
        if session.state == .paused { session.resume() } else if session.state == .running { session.pause() }
    }

    private func phoneIsRecording() async -> Bool {
        guard WCSession.default.isReachable else { return false }
        return await withCheckedContinuation { continuation in
            WCSession.default.sendMessage(["queryPhoneWorkout": true], replyHandler: { reply in
                continuation.resume(returning: reply["phoneWorkoutActive"] as? Bool ?? false)
            }, errorHandler: { _ in continuation.resume(returning: false) })
        }
    }

    func finish() {
        guard let session, let state = snapshot,
              state.phase == .running || state.phase == .paused else { return }
        let date = Date()
        prepareToSave(at: date)
        session.stopActivity(with: date)
    }

    private func prepareToSave(at date: Date) {
        guard stoppedAt == nil else { return }
        stoppedAt = date
        stopMotionMonitoring()
        dismissMilestones()
        updateMetrics(at: date)
        snapshot?.phase = .saving
        snapshot?.updatedAt = date
        timer?.invalidate(); timer = nil
        stepSegment = nil
        pedometer.stopUpdates(); stopRoute()
        checkpoint(force: true)
        publish()
        publishCompanionStatus()
    }

    func dismissSummary() {
        guard snapshot?.isActive != true else { return }
        snapshot = nil
        startError = nil
    }

    func recover() async {
        guard session == nil,
              let data = try? Data(contentsOf: Self.archiveURL),
              let saved = try? JSONDecoder().decode(WatchWorkoutResult.self, from: data),
              saved.snapshot.isActive else { return }
        snapshot = saved.snapshot
        stoppedAt = saved.snapshot.phase == .saving ? saved.snapshot.updatedAt : nil
        locations = saved.locations; breaks = saved.breakIndices; routePointCount = locations.count
        milestonePolicy = WatchMilestonePolicy(
            stepMark: saved.snapshot.milestoneStepMark ?? saved.snapshot.steps / 1_000,
            mileMark: saved.snapshot.milestoneMileMark ?? Int(saved.snapshot.distanceMiles),
            lastMileElapsed: saved.snapshot.lastMileElapsed ?? (saved.snapshot.distanceMiles < 1 ? 0 : saved.snapshot.elapsed),
            previousMiles: saved.snapshot.distanceMiles, previousElapsed: saved.snapshot.elapsed)
        do {
            guard let recovered = try await store.recoverActiveWorkoutSession() else {
                preserveInterruptedWorkout()
                return
            }
            guard recovered.state != .ended else {
                preserveInterruptedWorkout()
                return
            }
            snapshot?.phase = recovered.state == .stopped || stoppedAt != nil
                ? .saving : recovered.state == .paused ? .paused : .running
            // Start a fresh route segment; GPS was unavailable during recovery.
            previousLocation = nil
            acceptsAfter = Date()
            saveToHealth = UserDefaults.standard.object(forKey: "saveWorkoutsToHealth") as? Bool ?? true
            attach(recovered, builder: recovered.associatedWorkoutBuilder())
            if recovered.state == .stopped || stoppedAt != nil {
                if recovered.state != .stopped { recovered.stopActivity(with: stoppedAt ?? saved.snapshot.updatedAt) }
                else { await save(at: stoppedAt ?? saved.snapshot.updatedAt) }
                return
            }
            if recovered.state == .running {
                startSteps()
                startRouteIfAllowed()
            }
            startMotionMonitoring()
            startTimer()
            try? await recovered.startMirroringToCompanionDevice()
            publishCompanionStatus()
        } catch { preserveInterruptedWorkout() }
    }

    private func preserveInterruptedWorkout() {
        stopMotionMonitoring()
        snapshot?.phase = .failed
        snapshot?.error = "Recording was interrupted. Your last saved progress and route will sync to Nanobeasts. Check Health before recording this workout again."
        checkpoint(force: true)
        queueResult()
    }

    private func attach(_ session: HKWorkoutSession, builder: HKLiveWorkoutBuilder) {
        self.session = session; self.builder = builder
        session.delegate = self; builder.delegate = self
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMetrics() }
        }
    }

    private func startSteps() {
        baseSteps = snapshot?.steps ?? 0
        let segment = Date(); stepSegment = segment
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: segment) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor in
                guard let self, self.stepSegment == segment else { return }
                self.snapshot?.steps = max(self.snapshot?.steps ?? 0,
                                           self.baseSteps + max(0, data.numberOfSteps.intValue))
            }
        }
    }

    private func updateMetrics(at date: Date = Date()) {
        guard let builder, snapshot?.isActive == true else { return }
        let metricsDate = stoppedAt ?? date
        snapshot?.updatedAt = metricsDate
        snapshot?.elapsed = builder.elapsedTime(at: metricsDate)
        if let distance = builder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity() {
            snapshot?.distanceMiles = distance.doubleValue(for: .mile())
        }
        if let energy = builder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
            snapshot?.calories = energy.doubleValue(for: .kilocalorie())
        }
        if let stepCount = builder.statistics(for: HKQuantityType(.stepCount))?.sumQuantity() {
            snapshot?.steps = max(snapshot?.steps ?? 0, Int(stepCount.doubleValue(for: .count())))
        }
        let heartStatistics = builder.statistics(for: HKQuantityType(.heartRate))
        if let rate = heartStatistics?.mostRecentQuantity() {
            snapshot?.heartRate = rate.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            snapshot?.heartRateMeasuredAt = heartStatistics?.mostRecentQuantityDateInterval()?.end
        }
        if snapshot?.phase == .running { updateMilestones() }
        evaluateAutoPause(at: date)
        checkpoint(force: false)
        publish()
    }

    private func publish() {
        let now = Date()
        guard now.timeIntervalSince(lastLivePublishAt) >= 1
                || snapshot?.phase != lastLivePublishPhase
                || snapshot?.id != lastLivePublishSessionID else { return }
        snapshot?.liveRoute = WatchWorkoutRouteWindow(locations: locations, breakIndices: breaks)
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else { return }
        lastLivePublishAt = now
        lastLivePublishPhase = snapshot.phase
        lastLivePublishSessionID = snapshot.id
        if let session { Task { try? await session.sendToRemoteWorkoutSession(data: data) } }
    }

    private func save(at date: Date) async {
        guard !saving, let builder, snapshot != nil else { return }
        saving = true
        let completedSession = session
        prepareToSave(at: date)
        let finishDate = stoppedAt ?? date
        do {
            try await builder.endCollection(at: finishDate)
            if saveToHealth && snapshot!.hasRecordedActivity {
                try await builder.addMetadata([HKMetadataKeyIndoorWorkout: snapshot!.indoor,
                    "NanobeastsWorkoutRecordID": snapshot!.id.uuidString])
                guard let workout = try await builder.finishWorkout() else {
                    throw RecorderError.message("Apple Health could not save this workout.")
                }
                snapshot?.healthWorkoutID = workout.uuid
                do {
                    try await WorkoutHealthRouteWriter.save(locations, breaks: breaks, workout: workout, store: store)
                } catch {
                    snapshot?.error = "Workout saved. The route will sync to Nanobeasts, but could not be added to Health."
                }
            } else { builder.discardWorkout() }
            snapshot?.phase = .finished
        } catch {
            snapshot?.phase = .failed
            snapshot?.error = "Saved on this Watch; Health save failed: \(error.localizedDescription)"
        }
        checkpoint(force: true)
        publishCompanionStatus(durable: true)
        queueResult()
        // Ending a HealthKit session closes mirroring. Await the final send
        // instead of spawning a task that races that connection teardown.
        if let completedSession, let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            try? await completedSession.sendToRemoteWorkoutSession(data: data)
        }
        completedSession?.end()
        // A new recording may start while the final delivery is awaiting I/O.
        if self.session === completedSession {
            self.builder = nil
            self.session = nil
        }
    }

    private func publishCompanionStatus(durable: Bool = false) {
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else { return }
        let connectivity = WCSession.default
        guard connectivity.activationState == .activated else { return }
        let message = [WatchWorkoutFinishRequest.snapshotKey: data]
        // A small status payload remains available after mirroring ends; the
        // full GPS archive uses its existing independent file transfer.
        try? connectivity.updateApplicationContext(message)
        if connectivity.isReachable {
            connectivity.sendMessage(message, replyHandler: nil, errorHandler: { _ in })
        }
        if durable { connectivity.transferUserInfo(message) }
    }

    private func checkpoint(force: Bool) {
        guard let snapshot, force || Date().timeIntervalSince(lastCheckpoint) >= 5 else { return }
        do {
            let result = WatchWorkoutResult(snapshot: snapshot, locations: locations, breakIndices: breaks)
            try FileManager.default.createDirectory(at: Self.archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(result).write(to: Self.archiveURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastCheckpoint = Date()
        } catch { self.snapshot?.error = "Could not checkpoint this workout: \(error.localizedDescription)" }
    }

    private func queueResult() {
        guard let snapshot else { return }
        do {
            let url = Self.archiveURL.deletingLastPathComponent().appendingPathComponent("transfer-\(snapshot.id.uuidString).json")
            let result = WatchWorkoutResult(snapshot: snapshot, locations: locations, breakIndices: breaks)
            try JSONEncoder().encode(result).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            if WCSession.default.activationState == .activated {
                WCSession.default.transferFile(url, metadata: ["nanobeastsWorkout": true])
            }
        } catch { startError = "Workout is saved on the Watch. Phone sync will retry when connected." }
    }

    private static var archiveURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nanobeasts/active-workout.json")
    }

    static func presentation(activity: HKWorkoutActivityType, indoor: Bool) -> (id: String, name: String) {
        switch activity {
        case .running: (indoor ? "indoor-run" : "outdoor-run", indoor ? "Indoor Run" : "Outdoor Run")
        case .hiking: ("hiking", "Hiking")
        default: (indoor ? "indoor-walk" : "outdoor-walk", indoor ? "Indoor Walk" : "Outdoor Walk")
        }
    }

    private enum RecorderError: LocalizedError {
        case message(String)
        var errorDescription: String? { switch self { case let .message(text): text } }
    }
}

extension WatchWorkoutRecorder: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, CLLocationManagerDelegate, WCSessionDelegate {
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receivePhoneContext(applicationContext) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receivePhoneContext(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            if let id = message["requestLiveRoute"] as? String {
                guard let state = self.snapshot, state.id.uuidString == id, state.isActive else {
                    replyHandler(["routeQueued": false])
                    return
                }
                do {
                    let url = Self.archiveURL.deletingLastPathComponent()
                        .appendingPathComponent("live-route-\(UUID().uuidString).json")
                    let result = WatchWorkoutResult(snapshot: state, locations: self.locations, breakIndices: self.breaks)
                    try JSONEncoder().encode(result).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    session.transferFile(url, metadata: ["nanobeastsWorkout": true, "liveRoute": true])
                    replyHandler(["routeQueued": true])
                } catch { replyHandler(["routeQueued": false]) }
                return
            }
            guard let data = message[WatchWorkoutFinishRequest.messageKey] as? Data,
                  let request = try? JSONDecoder().decode(WatchWorkoutFinishRequest.self, from: data),
                  request.applies(to: self.snapshot) else {
                replyHandler(["error": "This recording is no longer active."])
                return
            }
            self.finish()
            if let state = self.snapshot, let encoded = try? JSONEncoder().encode(state) {
                replyHandler([WatchWorkoutFinishRequest.snapshotKey: encoded])
            } else { replyHandler(["error": "Open Nanobeasts on your Watch to check this workout."]) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.refreshLocationStatus()
            if self.locationStatus == .denied || self.locationStatus == .restricted
                || self.locationManager.accuracyAuthorization != .fullAccuracy {
                self.stopRoute()
            } else {
                self.startRouteIfAllowed()
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                   from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            switch toState {
            case .paused:
                guard self.stoppedAt == nil else { return }
                self.updateMetrics(at: date)
                self.snapshot?.phase = .paused
                self.stepSegment = nil; self.pedometer.stopUpdates()
                self.stopRoute()
                self.automaticTransitionPending = false
                WKInterfaceDevice.current().play(.stop)
            case .running:
                guard self.stoppedAt == nil else { return }
                self.snapshot?.elapsed = self.builder?.elapsedTime(at: date) ?? self.snapshot?.elapsed ?? 0
                self.snapshot?.updatedAt = date
                self.snapshot?.phase = .running
                self.automaticTransitionPending = false
                if fromState == .paused {
                    self.snapshot?.automaticallyPaused = false
                    self.autoPausePolicy.reset()
                    WKInterfaceDevice.current().play(.start)
                    self.acceptsAfter = date
                    self.startSteps()
                    self.startRouteIfAllowed()
                }
            case .stopped: await self.save(at: date)
            case .ended:
                if !self.saving { await self.save(at: date) }
            default: break
            }
            self.checkpoint(force: true)
            self.publish()
            self.publishCompanionStatus()
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.snapshot?.error = error.localizedDescription
            await self.save(at: Date())
        }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        Task { @MainActor in
            guard self.builder === workoutBuilder else { return }
            self.updateMetrics()
        }
    }
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            guard self.builder === workoutBuilder else { return }
            self.updateMetrics()
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations updates: [CLLocation]) {
        Task { @MainActor in
            guard self.snapshot?.phase == .running, self.routeIsUpdating else { return }
            for location in updates.sorted(by: { $0.timestamp < $1.timestamp }) {
                if CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0,
                   location.horizontalAccuracy <= 50, abs(location.timestamp.timeIntervalSinceNow) <= 15 {
                    self.lastGPSFix = location.timestamp
                    self.routeNotice = nil
                }
                let decision = WorkoutRouteFilter.evaluate(location, previous: self.previousLocation,
                    after: self.acceptsAfter, now: Date(), maximumSpeed: self.snapshot?.workoutID.contains("run") == true ? 12 : 4)
                guard decision != .reject else { continue }
                if decision == .startSegment, !self.locations.isEmpty { self.breaks.append(self.locations.count) }
                self.locations.append(WorkoutRecordedLocation(location))
                self.previousLocation = location
            }
            self.routePointCount = self.locations.count
            self.checkpoint(force: false)
            self.publish()
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.routeIsUpdating, self.snapshot?.phase == .running, !self.saving else { return }
            self.previousLocation = nil
            self.lastGPSFix = nil
            if (error as? CLError)?.code == .denied {
                self.stopRoute()
                self.refreshLocationStatus()
                if self.locationAccess.canRecordRoute {
                    self.routeNotice = "GPS was interrupted. Return to Nano to reconnect; your recorded route is kept."
                }
            } else if (error as? CLError)?.code != .locationUnknown {
                self.routeNotice = "GPS is temporarily unavailable. Your workout continues; route recording resumes when a signal returns."
            }
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.retryPendingTransfers() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { Task { @MainActor in self.retryPendingTransfers() } }
    }
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if error == nil || fileTransfer.file.metadata?["liveRoute"] as? Bool == true {
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        }
    }
}
