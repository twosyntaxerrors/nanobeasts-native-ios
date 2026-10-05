import Combine
import HealthKit
import ImageIO
import SDWebImage
import UniformTypeIdentifiers
import UIKit
import WatchConnectivity

@MainActor
final class WorkoutWatchBridge: NSObject, ObservableObject {
    static let shared = WorkoutWatchBridge()
    @Published private(set) var isPaired = false
    @Published private(set) var isInstalled = false
    @Published private(set) var isReachable = false
    @Published private(set) var isStarting = false
    @Published private(set) var snapshot: WatchWorkoutSnapshot?
    @Published private(set) var liveRoute = WatchWorkoutLiveRoute()
    @Published private(set) var connectionMessage: String?
    @Published private(set) var finishError: String?
    @Published private(set) var savedWorkoutID: UUID?
    @Published private var finishRequest: WatchWorkoutFinishRequest?
    private var finishTimeout: Task<Void, Never>?
    private let store = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?
    private var companion: WorkoutCompanionSnapshot?
    private var watchArtwork: WatchCompanionArtwork?
    private var artworkTask: Task<Void, Never>?
    private var phoneWorkoutActive = false
    private let liveActivityController = WorkoutLiveActivityController()
    private var liveActivityTask: Task<Void, Never>?
    private var subscriptionAccess: NanoSubscriptionAccess?

    func updateSubscriptionAccess(_ access: NanoSubscriptionAccess) {
        subscriptionAccess = access
        publishCompanion()
    }
    private var interfaceAppearance = WatchInterfaceAppearance(
        accentName: NanoAccentPreference.current.rawValue, updatedAt: Date())
    var isActive: Bool { isStarting || mirroredSession != nil || snapshot?.isActive == true }
    var isFinishing: Bool { finishRequest != nil || snapshot?.phase == .saving }
    var displaySnapshot: WatchWorkoutSnapshot? {
        guard let snapshot else { return nil }
        return finishRequest?.displaySnapshot(snapshot) ?? snapshot
    }
    var canControl: Bool { mirroredSession != nil && snapshot?.isActive == true && !isFinishing }
    var canFinish: Bool {
        snapshot?.isActive == true && (!isFinishing || finishError != nil)
            && (mirroredSession != nil || isReachable)
    }

    func requestLiveRoute() {
        guard let snapshot, snapshot.isActive, !snapshot.indoor,
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["requestLiveRoute": snapshot.id.uuidString],
                                      replyHandler: { _ in }, errorHandler: { _ in })
    }

    override init() {
        super.init()
        companion = UserDefaults.standard.data(forKey: "nanobeasts.watch.companion")
            .flatMap { try? JSONDecoder().decode(WorkoutCompanionSnapshot.self, from: $0) }
        watchArtwork = UserDefaults.standard.data(forKey: WatchCompanionArtwork.cacheKey)
            .flatMap { try? JSONDecoder().decode(WatchCompanionArtwork.self, from: $0) }
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in
                self?.mirroredSession = session
                session.delegate = self
                self?.isStarting = false
                self?.connectionMessage = nil
            }
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        processInbox()
    }

    func updateCompanion(_ stage: CreatureStage, dailyGoal: Int? = nil,
                         evolution: WorkoutEvolutionProgress? = nil) {
        let goal = dailyGoal ?? watchArtwork?.dailyStepGoal
        let progress = evolution ?? (watchArtwork?.stageID == stage.id ? watchArtwork?.evolution : nil)
        companion = WorkoutCompanionSnapshot(stage: stage)
        if let data = try? JSONEncoder().encode(companion) {
            UserDefaults.standard.set(data, forKey: "nanobeasts.watch.companion")
        }
        if watchArtwork?.stageID != stage.id {
            artworkTask?.cancel()
            artworkTask = nil
            watchArtwork = WatchCompanionArtwork(stageID: stage.id, name: stage.name, updatedAt: Date(),
                dailyStepGoal: goal, evolution: progress)
            publishCompanion()
        } else if watchArtwork?.dailyStepGoal != goal || watchArtwork?.evolution != progress, let previous = watchArtwork {
            watchArtwork = WatchCompanionArtwork(stageID: previous.stageID, name: previous.name,
                updatedAt: Date(), pngData: previous.pngData, dailyStepGoal: goal,
                animationData: previous.animationData, evolution: progress)
            publishCompanion()
        }
        guard (watchArtwork?.pngData == nil || watchArtwork?.animationData == nil), artworkTask == nil else {
            publishCompanion()
            return
        }
        let url = R2AssetManifest.url(for: stage.imageKey)
        artworkTask = Task { [weak self] in
            defer { if !Task.isCancelled { self?.artworkTask = nil } }
            do {
                let data = try await R2ArtworkCache.shared.data(for: url)
                guard !Task.isCancelled, let self, self.watchArtwork?.stageID == stage.id,
                      let png = Self.watchPNG(from: data) else { return }
                self.watchArtwork?.pngData = png
                self.publishCompanion()
                let animatedData = try await R2ArtworkCache.shared.data(for: R2AnimationManifest.url(for: stage))
                let gif = await Task.detached(priority: .utility) { Self.watchAnimation(from: animatedData) }.value
                guard !Task.isCancelled, self.watchArtwork?.stageID == stage.id else { return }
                self.watchArtwork?.animationData = gif
                self.publishCompanion()
            } catch {
                // Retry on the next connection or foreground refresh. Never
                // substitute another creature while this one's artwork loads.
            }
        }
    }

    private static func watchPNG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        for size in [192, 160, 128, 96, 64] {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: size]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
               let png = UIImage(cgImage: image).pngData(), png.count <= 24_000 { return png }
        }
        return nil
    }

    /// One short, bounded idle cycle. Keep the entire context below WCSession's
    /// message budget and decode only tiny frames on the Watch.
    nonisolated private static func watchAnimation(from data: Data) -> Data? {
        guard let animation = SDAnimatedImage(data: data), animation.animatedImageFrameCount > 1 else { return nil }
        for size in [64, 48, 36] {
            let result = NSMutableData()
            let count = min(16, Int(animation.animatedImageFrameCount))
            guard let writer = CGImageDestinationCreateWithData(result, UTType.gif.identifier as CFString, count, nil) else { return nil }
            for index in 0..<count {
                let sourceIndex = UInt(index * Int(animation.animatedImageFrameCount) / count)
                guard let frame = animation.animatedImageFrame(at: sourceIndex) else { return nil }
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
                let thumbnail = renderer.image { _ in
                    let scale = min(CGFloat(size) / frame.size.width, CGFloat(size) / frame.size.height)
                    let width = frame.size.width * scale, height = frame.size.height * scale
                    frame.draw(in: CGRect(x: (CGFloat(size) - width) / 2, y: (CGFloat(size) - height) / 2,
                                          width: width, height: height))
                }
                guard let image = thumbnail.cgImage else { return nil }
                CGImageDestinationAddImage(writer, image,
                    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
            }
            if CGImageDestinationFinalize(writer), result.length <= 18_000 { return result as Data }
        }
        return nil
    }

    func updateInterfaceAccent() {
        interfaceAppearance = WatchInterfaceAppearance(
            accentName: NanoAccentPreference.current.rawValue, updatedAt: Date())
        publishCompanion()
        let session = WCSession.default
        if session.activationState == .activated, session.isReachable,
           let data = try? JSONEncoder().encode(interfaceAppearance) {
            session.sendMessage([WatchInterfaceAppearance.contextKey: data], replyHandler: nil,
                                errorHandler: { _ in /* The durable context delivers when reconnected. */ })
        }
    }

    private func companionContext() -> [String: Any] {
        var context: [String: Any] = [:]
        if let data = try? JSONEncoder().encode(interfaceAppearance) {
            context[WatchInterfaceAppearance.contextKey] = data
        }
        if let watchArtwork, let data = try? JSONEncoder().encode(watchArtwork), data.count < 60_000 {
            UserDefaults.standard.set(data, forKey: WatchCompanionArtwork.cacheKey)
            context[WatchCompanionArtwork.contextKey] = data
        }
        if let subscriptionAccess, let data = try? JSONEncoder().encode(subscriptionAccess) {
            context[NanoSubscriptionAccess.contextKey] = data
        }
        return context
    }

    private func publishCompanion() {
        let context = companionContext()
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        // Latest-state delivery works even when the Watch is temporarily offline.
        try? session.updateApplicationContext(context)
    }

    private func refreshCompanion() {
        if interfaceAppearance.accentName != NanoAccentPreference.current.rawValue { updateInterfaceAccent() }
        if let companion { updateCompanion(companion.creatureStage) }
        else { publishCompanion() }
    }

    func setPhoneWorkoutActive(_ active: Bool) { phoneWorkoutActive = active }

    func start(workoutID: String, indoor: Bool) async {
        guard !isActive else { return }
        refreshAvailability()
        guard isInstalled else {
            connectionMessage = "Install Nanobeasts from the Watch app on your iPhone, then try again."
            return
        }
        isStarting = true
        connectionMessage = nil
        snapshot = nil
        savedWorkoutID = nil
        finishRequest = nil
        finishError = nil
        finishTimeout?.cancel()
        let config = HKWorkoutConfiguration()
        config.activityType = workoutID.contains("run") ? .running : ["hiking", "nordic-walk"].contains(workoutID) ? .hiking : .walking
        config.locationType = indoor ? .indoor : .outdoor
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.startWatchApp(with: config) { success, error in
                    if let error { continuation.resume(throwing: error) }
                    else if success { continuation.resume() }
                    else { continuation.resume(throwing: NSError(domain: "NanobeastsWatch", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Apple Watch did not accept the workout request."])) }
                }
            }
            // Starting can include first-run permission prompts on the Watch.
            for _ in 0..<120 where isStarting {
                try await Task.sleep(for: .milliseconds(500))
            }
            if isStarting {
                isStarting = false
                connectionMessage = "Check your Watch to approve Health and Location access. If it is already recording, it will sync when connected."
            }
        } catch {
            isStarting = false
            connectionMessage = "Could not start on Apple Watch: \(error.localizedDescription)"
        }
    }

    func pauseOrResume() {
        guard let mirroredSession else { return }
        if mirroredSession.state == .paused { mirroredSession.resume() }
        else if mirroredSession.state == .running { mirroredSession.pause() }
    }
    func finish() {
        guard canFinish, let snapshot else { return }
        let now = Date()
        let request = finishRequest ?? WatchWorkoutFinishRequest(sessionID: snapshot.id,
            requestedAt: now, displayElapsed: snapshot.elapsed(at: now))
        finishRequest = request
        finishError = nil
        connectionMessage = nil
        // Show finishing immediately. Actual completion still requires a Watch
        // acknowledgement; a failed connection must never claim it was saved.
        if snapshot.phase != .saving { mirroredSession?.stopActivity(with: request.requestedAt) }
        if WCSession.default.isReachable, let data = try? JSONEncoder().encode(request) {
            WCSession.default.sendMessage([WatchWorkoutFinishRequest.messageKey: data], replyHandler: { reply in
                guard let data = reply[WatchWorkoutFinishRequest.snapshotKey] as? Data,
                      let state = try? JSONDecoder().decode(WatchWorkoutSnapshot.self, from: data) else { return }
                Task { @MainActor in self.receive(state) }
            }, errorHandler: { _ in /* Mirroring remains available as an independent path. */ })
        }
        finishTimeout?.cancel()
        finishTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, let state = self.snapshot,
                  state.id == request.sessionID, state.isActive else { return }
            if state.phase == .saving {
                self.finishError = "Your workout stopped. Saving is taking longer than expected. Retry to check your Watch."
            } else {
                self.finishRequest = nil
                self.finishError = "Could not confirm the finish on your Watch. Try again, or finish from your Watch."
            }
        }
    }

    private func refreshAvailability() {
        guard WCSession.isSupported() else { return }
        isPaired = WCSession.default.isPaired
        isInstalled = WCSession.default.isWatchAppInstalled
        isReachable = WCSession.default.isReachable
    }

    private func receive(_ state: WatchWorkoutSnapshot) {
        // Save final metrics before publishing completion. Route files enrich
        // this same history row later, without delaying the success feedback.
        if !state.isActive, state.hasRecordedActivity {
            WorkoutHistoryStore().receiveWatchWorkout(
                WatchWorkoutResult(snapshot: state, locations: [], breakIndices: []), companion: companion)
        }
        guard state.supersedes(snapshot) else { return }
        let previousID = snapshot?.id
        liveRoute.receive(state)
        snapshot = state
        updateLiveActivity(state)
        isStarting = false
        connectionMessage = nil
        if !state.isActive {
            finishRequest = nil
            finishTimeout?.cancel()
            finishError = nil
            savedWorkoutID = state.hasRecordedActivity ? state.id : nil
        } else if previousID != state.id {
            finishRequest = nil
            finishTimeout?.cancel()
            finishError = nil
            savedWorkoutID = nil
        }
    }

    private func receiveSnapshotMessage(_ message: [String: Any]) {
        guard let data = message[WatchWorkoutFinishRequest.snapshotKey] as? Data,
              let state = try? JSONDecoder().decode(WatchWorkoutSnapshot.self, from: data) else { return }
        receive(state)
    }

    private func updateLiveActivity(_ state: WatchWorkoutSnapshot) {
        // Serialize lifecycle work so a delayed update cannot race completion
        // or end the Live Activity belonging to the next recording.
        let previousTask = liveActivityTask
        liveActivityTask = Task { @MainActor [weak self] in
            await previousTask?.value
            guard let self else { return }
            let sessionID = "watch-\(state.id.uuidString)"
            var content = state.workoutActivityState
            if let evolution = self.watchArtwork?.evolution,
               evolution.stageID == self.watchArtwork?.stageID {
                content.evolutionFraction = evolution.fraction
                content.evolutionCaption = evolution.caption
            }
            if !state.isActive {
                if self.liveActivityController.sessionID != sessionID {
                    // Final snapshots can arrive after iOS relaunched the app.
                    guard self.liveActivityController.restore(sessionID: sessionID) != nil else { return }
                }
                await self.liveActivityController.end(with: content)
                return
            }
            guard !self.phoneWorkoutActive else { return }
            if self.liveActivityController.sessionID != sessionID {
                if self.liveActivityController.restore(sessionID: sessionID) == nil {
                    let workout = PreviewWorkout.all.first { $0.id == state.workoutID }
                    await self.liveActivityController.start(
                        workoutID: state.workoutID, workoutName: state.name,
                        symbolName: workout?.symbol ?? "figure.walk", indoor: state.indoor,
                        goalDescription: "Apple Watch workout", goalKind: "Open Goal", goalTarget: nil,
                        companionID: self.companion?.creatureStage.id ?? "",
                        companionName: self.companion?.name, companionStage: self.companion?.stage,
                        companionImageKey: self.companion?.imageKey,
                        sessionID: sessionID, workoutSource: "watch", state: content)
                }
            }
            await self.liveActivityController.update(content)
        }
    }

    private static var inbox: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nanobeasts/WatchInbox")
    }

    private func processInbox() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: Self.inbox, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            do {
                let result = try JSONDecoder().decode(WatchWorkoutResult.self, from: Data(contentsOf: file))
                if result.snapshot.isActive {
                    if snapshot?.id == result.snapshot.id {
                        liveRoute.receiveFullRoute(result)
                    }
                    try FileManager.default.removeItem(at: file)
                    continue
                }
                WorkoutHistoryStore().receiveWatchWorkout(result, companion: companion)
                WorkoutLocationTracker.shared.importWatchTerritory(result)
                receive(result.snapshot)
                if snapshot?.id == result.snapshot.id { liveRoute.receiveFullRoute(result) }
                // Keep the original result as a durable route backup. Receiving
                // the same transfer again is safe: its session UUID is stable.
                let archive = Self.inbox.deletingLastPathComponent().appendingPathComponent("WatchResults")
                try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
                let destination = archive.appendingPathComponent(file.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: file)
                } else { try FileManager.default.moveItem(at: file, to: destination) }
            } catch { connectionMessage = "A Watch workout is waiting to sync: \(error.localizedDescription)" }
        }
    }
}

extension WorkoutWatchBridge: HKWorkoutSessionDelegate, WCSessionDelegate {
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.refreshCompanion()
            var reply = self.companionContext()
            reply["phoneWorkoutActive"] = self.phoneWorkoutActive || WorkoutLocationTracker.persistedActiveSessionID != nil
            replyHandler(reply)
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                   from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.mirroredSession === workoutSession else { return }
            if let current = self.snapshot, current.isActive {
                let phase: WatchWorkoutSnapshot.Phase?
                switch toState {
                case .paused: phase = .paused
                case .running: phase = .running
                case .stopped, .ended: phase = .saving
                default: phase = nil
                }
                if let phase {
                    let updated = current.changingPhase(to: phase, at: date)
                    if updated.supersedes(current) { self.receive(updated) }
                }
            }
            if toState == .ended { self.mirroredSession = nil }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.mirroredSession === workoutSession, self.snapshot?.isActive == true else { return }
            self.connectionMessage = error.localizedDescription
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for value in data {
            guard let snapshot = try? JSONDecoder().decode(WatchWorkoutSnapshot.self, from: value) else { continue }
            Task { @MainActor in self.receive(snapshot) }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in
            guard self.mirroredSession === workoutSession else { return }
            self.mirroredSession = nil
            if self.snapshot?.phase == .saving {
                self.connectionMessage = "Your workout stopped. Waiting for the saved result from your Watch."
            } else if self.snapshot?.isActive == true {
                self.connectionMessage = "Reconnect to update the live display, or finish on your Watch."
            }
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.refreshAvailability()
            self.refreshCompanion()
            self.receiveSnapshotMessage(session.receivedApplicationContext)
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receiveSnapshotMessage(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receiveSnapshotMessage(applicationContext) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.receiveSnapshotMessage(userInfo) }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshAvailability(); self.refreshCompanion() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshAvailability(); self.refreshCompanion() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["nanobeastsWorkout"] as? Bool == true else { return }
        // WatchConnectivity removes its temporary file as soon as this callback
        // returns, so copy before dispatching to the main actor.
        let inbox = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nanobeasts/WatchInbox")
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let destination = inbox.appendingPathComponent(UUID().uuidString + ".json")
            try FileManager.default.copyItem(at: file.fileURL, to: destination)
            Task { @MainActor in self.processInbox() }
        } catch {
            Task { @MainActor in self.connectionMessage = "Could not receive the Watch workout: \(error.localizedDescription)" }
        }
    }
}

extension WatchWorkoutSnapshot {
    /// Anchor the clock to the sample date, not delivery time, so delayed Watch
    /// messages don't make the Lock Screen clock jump backwards.
    var workoutActivityState: WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            timerAnchor: updatedAt.addingTimeInterval(-max(0, elapsed)),
            elapsedSeconds: Int(max(0, elapsed)), steps: max(0, steps),
            distanceMiles: max(0, distanceMiles), calories: Int(max(0, calories)),
            goalProgress: 0, isPaused: phase != .running,
            goalReached: false, isComplete: !isActive)
    }
}
