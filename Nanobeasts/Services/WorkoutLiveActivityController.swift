import ActivityKit
import Combine
import Foundation
import ImageIO
import UserNotifications
import UIKit
import OSLog

enum WorkoutInactivityResponseAction: String, Codable {
    case openWorkout
    case endWorkout
}

struct WorkoutInactivityResponse: Codable, Equatable {
    let sessionID: String
    let action: WorkoutInactivityResponseAction
}

enum WorkoutInactivityResponseStore {
    static let didChangeNotification = Notification.Name(
        "nanobeasts.workout-inactivity-response.did-change"
    )

    private static let storageKey = "nanobeasts.workout-inactivity-response.v1"

    static func save(_ response: WorkoutInactivityResponse) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func load() -> WorkoutInactivityResponse? {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let response = try? JSONDecoder().decode(
                WorkoutInactivityResponse.self,
                from: data
            )
        else {
            return nil
        }
        return response
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

enum WorkoutInactivityNotifications {
    static let categoryIdentifier = "NANOBEASTS_WORKOUT_INACTIVITY"
    static let continueActionIdentifier = "CONTINUE_NANOBEASTS_WORKOUT"
    static let endActionIdentifier = "END_NANOBEASTS_WORKOUT"

    private static let sessionIDKey = "sessionID"
    private static let activityPromptKey = "activityPrompt"

    static func registerCategories() {
        let keepTracking = UNNotificationAction(
            identifier: continueActionIdentifier,
            title: "Keep Tracking"
        )
        let endWorkout = UNNotificationAction(
            identifier: endActionIdentifier,
            title: "End Workout",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [keepTracking, endWorkout],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func begin(
        sessionID: String,
        activityPrompt: String,
        after delay: TimeInterval
    ) async {
        guard NanoNotifications.enabled else { return }
        registerCategories()
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var isAllowed = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral

        if settings.authorizationStatus == .notDetermined {
            isAllowed = (try? await center.requestAuthorization(
                options: [.alert, .sound]
            )) == true
        }

        guard isAllowed, NanoNotifications.enabled else { return }
        schedule(
            sessionID: sessionID,
            activityPrompt: activityPrompt,
            after: delay
        )
    }

    static func schedule(
        sessionID: String,
        activityPrompt: String,
        after delay: TimeInterval
    ) {
        guard NanoNotifications.enabled else { return }
        let center = UNUserNotificationCenter.current()
        let identifier = notificationIdentifier(for: sessionID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Are you still \(activityPrompt)?"
        content.body = "No movement detected recently. Keep tracking or end this workout."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [
            sessionIDKey: sessionID,
            activityPromptKey: activityPrompt,
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(delay, 1),
            repeats: false
        )
        center.add(
            UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
        ) { _ in
            // An opt-out can happen while iOS is committing this request.
            if !NanoNotifications.enabled {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
            }
        }
    }

    static func cancel(sessionID: String?) {
        guard let sessionID else { return }
        let identifier = notificationIdentifier(for: sessionID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    static func handle(_ response: UNNotificationResponse) {
        let content = response.notification.request.content
        guard
            content.categoryIdentifier == categoryIdentifier,
            let sessionID = content.userInfo[sessionIDKey] as? String
        else {
            return
        }

        let activityPrompt = content.userInfo[activityPromptKey] as? String
            ?? "moving"

        switch response.actionIdentifier {
        case continueActionIdentifier:
            schedule(
                sessionID: sessionID,
                activityPrompt: activityPrompt,
                after: 5 * 60
            )
        case endActionIdentifier:
            cancel(sessionID: sessionID)
            WorkoutInactivityResponseStore.save(
                WorkoutInactivityResponse(
                    sessionID: sessionID,
                    action: .endWorkout
                )
            )
        case UNNotificationDefaultActionIdentifier:
            WorkoutInactivityResponseStore.save(
                WorkoutInactivityResponse(
                    sessionID: sessionID,
                    action: .openWorkout
                )
            )
        default:
            break
        }
    }

    private static func notificationIdentifier(for sessionID: String) -> String {
        "nanobeasts.workout.inactivity.\(sessionID)"
    }
}

final class WorkoutNotificationAppDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Recreate an active Core Location background session immediately when
        // iOS launches the process to deliver queued workout locations.
        _ = WorkoutLocationTracker.shared
        _ = WorkoutSessionTracker.shared
        // Migrate already-imported duplicate rows before history totals load.
        _ = WorkoutHistoryStore()
        _ = WorkoutWatchBridge.shared
        WorkoutHealthSync.shared.start()
        WorkoutInactivityNotifications.registerCategories()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier.hasPrefix("nanobeasts.onboarding.") {
            completionHandler([])
        } else {
            completionHandler(NanoNotifications.enabled ? [.banner, .list, .sound] : [])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        WorkoutInactivityNotifications.handle(response)
        completionHandler()
    }
}

@MainActor
final class WorkoutLiveActivityController: ObservableObject {
    private(set) var sessionID: String?
    private var activity: Activity<WorkoutActivityAttributes>?
    @Published private(set) var startFailure: String?
    private var pendingAttributes: WorkoutActivityAttributes?
    private var latestState: WorkoutActivityAttributes.ContentState?
    private var foregroundObserver: AnyCancellable?
    private let logger = Logger(subsystem: "com.twosyntaxerrors.nanobeasts.native", category: "WorkoutLiveActivity")

    init() {
        foregroundObserver = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.requestPendingActivity() }
            }
    }

    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(
        workoutID: String,
        workoutName: String,
        symbolName: String,
        indoor: Bool,
        goalDescription: String,
        goalKind: String,
        goalTarget: Double?,
        companionID: String,
        companionName: String? = nil,
        companionStage: Int? = nil,
        companionImageKey: String? = nil,
        sessionID: String = UUID().uuidString,
        workoutSource: String = "phone",
        state: WorkoutActivityAttributes.ContentState
    ) async {
        // Request before the first suspension: the user may lock the phone as
        // soon as Start is tapped. Never end another recorder's activity.
        let previous = resolvedActivity
        activity = nil
        self.sessionID = sessionID
        startFailure = nil

        let attributes = WorkoutActivityAttributes(
            sessionID: sessionID,
            workoutName: workoutName,
            symbolName: symbolName,
            goalDescription: goalDescription,
            workoutID: workoutID,
            indoor: indoor,
            goalKind: goalKind,
            goalTarget: goalTarget,
            companionID: companionID,
            workoutSource: workoutSource,
            companionName: companionName,
            companionStage: companionStage,
            companionArtwork: companionImageKey.map(WorkoutLiveActivityArtwork.filename(imageKey:))
        )
        // The activity is requested before artwork is ready; it renders the
        // creature on the next state update once the thumbnail lands.
        if let companionImageKey { WorkoutLiveActivityArtwork.prepare(imageKey: companionImageKey) }
        pendingAttributes = attributes
        latestState = state
        requestPendingActivity()
        if let previous, previous.attributes.sessionID != sessionID {
            await previous.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func requestPendingActivity() {
        guard activity == nil, resolvedActivity == nil, let attributes = pendingAttributes,
              let state = latestState, !state.isComplete else { return }
        guard isAvailable else {
            startFailure = "Live Activities are disabled for Nanobeasts in iPhone Settings."
            return
        }
        // Watch mirroring grants background execution, not permission to start
        // an Activity. Retain this request for the next foreground activation.
        guard UIApplication.shared.applicationState == .active else {
            startFailure = "Open Nanobeasts on your iPhone to show this workout on the Lock Screen."
            return
        }

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: state,
                    staleDate: Date().addingTimeInterval(90)
                ),
                pushType: nil
            )
            self.activity = activity
            startFailure = nil
        } catch {
            startFailure = "Could not show the Lock Screen workout: \(error.localizedDescription)"
            logger.error("Unable to start workout Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(_ state: WorkoutActivityAttributes.ContentState) async {
        latestState = state
        // Do not recreate an activity that the user dismissed. Only retry a
        // request that has never succeeded (for example a background start).
        if activity == nil { requestPendingActivity() }
        guard resolvedActivity != nil else { return }
        // Phone workouts call this several times a second (timer, pedometer,
        // GPS). Sending each one invites system throttling and queues stale
        // frames, so send the newest state at most once per interval.
        let wait = Self.minimumUpdateInterval - Date().timeIntervalSince(lastUpdateAt)
        let isTransition = state.isPaused != lastSentState?.isPaused || state.isComplete
        if wait <= 0 || isTransition {
            trailingUpdate?.cancel()
            trailingUpdate = nil
            await send(state)
        } else if trailingUpdate == nil {
            trailingUpdate = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard let self, !Task.isCancelled, let latest = self.latestState else { return }
                self.trailingUpdate = nil
                await self.send(latest)
            }
        }
    }

    private static let minimumUpdateInterval: TimeInterval = 1
    private var lastUpdateAt = Date.distantPast
    private var lastSentState: WorkoutActivityAttributes.ContentState?
    private var trailingUpdate: Task<Void, Never>?

    private func send(_ state: WorkoutActivityAttributes.ContentState) async {
        guard let activity = resolvedActivity else { return }
        lastUpdateAt = Date()
        lastSentState = state
        await activity.update(
            ActivityContent(
                state: state,
                staleDate: Date().addingTimeInterval(90)
            )
        )
    }

    func end(
        with state: WorkoutActivityAttributes.ContentState,
        dismissalDelay: TimeInterval = 60
    ) async {
        let finishingActivity = resolvedActivity
        clearSession()
        if let activity = finishingActivity {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(dismissalDelay))
            )
        }
    }

    func endImmediately() async {
        let endingActivity = resolvedActivity
        clearSession()
        if let activity = endingActivity {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func clearSession() {
        if WorkoutActivityCommandStore.load()?.sessionID == sessionID {
            WorkoutActivityCommandStore.clear()
        }
        activity = nil
        sessionID = nil
        pendingAttributes = nil
        latestState = nil
        startFailure = nil
        trailingUpdate?.cancel()
        trailingUpdate = nil
        lastSentState = nil
        lastUpdateAt = .distantPast
    }

    func restore(
        sessionID: String
    ) -> (attributes: WorkoutActivityAttributes, state: WorkoutActivityAttributes.ContentState)? {
        self.sessionID = sessionID
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: {
            $0.attributes.sessionID == sessionID && ($0.activityState == .active || $0.activityState == .stale)
        }) else {
            return nil
        }

        self.activity = activity
        self.sessionID = sessionID
        pendingAttributes = activity.attributes
        latestState = activity.content.state
        return (activity.attributes, activity.content.state)
    }

    private var resolvedActivity: Activity<WorkoutActivityAttributes>? {
        if let activity {
            return activity.activityState == .active || activity.activityState == .stale ? activity : nil
        }
        guard let sessionID else { return nil }
        return Activity<WorkoutActivityAttributes>.activities.first {
            $0.attributes.sessionID == sessionID && ($0.activityState == .active || $0.activityState == .stale)
        }
    }
}

/// Writes a Lock Screen–sized creature thumbnail into the App Group so the
/// widget extension can draw the current companion inside the Live Activity.
enum WorkoutLiveActivityArtwork {
    /// Live Activities refuse oversized images; 168 px covers a 56 pt badge at 3×.
    private static let maxPixelSize = 168

    static func filename(imageKey: String) -> String {
        "live-companion-" + String(imageKey.map { $0.isLetter || $0.isNumber ? $0 : "-" }) + ".png"
    }

    static func prepare(imageKey: String) {
        let filename = filename(imageKey: imageKey)
        guard !WidgetSnapshotStore.hasInlineArtworkData(filename: filename) else { return }
        let url = R2AssetManifest.url(for: imageKey)
        Task.detached(priority: .userInitiated) {
            guard
                let data = try? await R2ArtworkCache.shared.data(for: url),
                let thumbnail = thumbnail(from: data)
            else { return }
            WidgetSnapshotStore.saveArtworkData(thumbnail, filename: filename)
        }
    }

    private static func thumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).pngData()
    }
}
