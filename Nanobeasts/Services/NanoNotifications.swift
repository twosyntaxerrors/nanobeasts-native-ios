import Combine
import UserNotifications

enum NanoReminderPolicy {
    static func shouldRemind(enabled: Bool, authorized: Bool, remaining: Int, target: Int) -> Bool {
        enabled && authorized && target > 0 && remaining > 0
            && Double(remaining) / Double(target) <= 0.2
    }
}

/// The app preference is independent of Apple's notification permission.
/// Disabling it cancels reminders without repeatedly asking for OS permission.
@MainActor
final class NanoNotifications: ObservableObject {
    static let shared = NanoNotifications()
    static let enabledKey = "nanobeasts.notifications.enabled"
    static let progressID = "nanobeasts.creature.near-milestone"
    static let setupPreferenceKey = "nanobeasts.notifications.setup-reminders"
    static let setupIDs = (0..<OnboardingReminderPolicy.count).map { "nanobeasts.onboarding.\($0)" }
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isRequesting = false
    private var revision = 0
    private var isScheduling = false
    private struct Progress {
        let stageID: String
        let name: String
        let isEgg: Bool
        let remaining: Int
        let target: Int
        let journey: Date?
        let eligible: Bool
    }
    private var pendingProgress: Progress?
    private let center = UNUserNotificationCenter.current()
    private var setupRevision = 0
    private var setupScheduling = false
    private var pendingSetup: (name: String, planReady: Bool, completed: Bool, premium: Bool)?

    func setSetupReminderPreference(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.setupPreferenceKey)
        if !enabled { cancelOnboardingReminders() }
    }

    func cancelOnboardingReminders() {
        setupRevision += 1
        pendingSetup = nil
        center.removePendingNotificationRequests(withIdentifiers: Self.setupIDs)
        center.removeDeliveredNotifications(withIdentifiers: Self.setupIDs)
    }

    func scheduleOnboardingReminders(name: String, planReady: Bool, completed: Bool, premium: Bool) async {
        setupRevision += 1
        pendingSetup = (name, planReady, completed, premium)
        guard !setupScheduling else { return }
        setupScheduling = true
        defer { setupScheduling = false }
        while let setup = pendingSetup {
            pendingSetup = nil
            let token = setupRevision
            await refreshAuthorization()
            guard token == setupRevision else { continue }
            center.removePendingNotificationRequests(withIdentifiers: Self.setupIDs)
            guard OnboardingReminderPolicy.shouldSchedule(
                consented: UserDefaults.standard.bool(forKey: Self.setupPreferenceKey),
                enabled: Self.enabled, authorized: authorized,
                completed: setup.completed, premium: setup.premium
            ) else { continue }

            let defaults = UserDefaults.standard
            let dateKey = "nanobeasts.notifications.setup-scheduled-at"
            let indexKey = "nanobeasts.notifications.setup-next-index"
            let now = Date()
            var nextIndex = defaults.integer(forKey: indexKey)
            if let previous = defaults.object(forKey: dateKey) as? Date {
                nextIndex = min(OnboardingReminderPolicy.count,
                    nextIndex + max(0, Int(now.timeIntervalSince(previous) / OnboardingReminderPolicy.interval)))
            }
            defaults.set(nextIndex, forKey: indexKey)
            defaults.set(now, forKey: dateKey)
            let messages = OnboardingReminderPolicy.messages(name: setup.name, planReady: setup.planReady)
            for index in nextIndex..<messages.count {
                guard token == setupRevision, Self.enabled,
                      defaults.bool(forKey: Self.setupPreferenceKey) else { break }
                let content = UNMutableNotificationContent()
                content.title = messages[index].title
                content.body = messages[index].body
                content.sound = .default
                content.userInfo = ["nanobeastsDestination": "onboarding"]
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: Double(index - nextIndex + 1) * OnboardingReminderPolicy.interval,
                    repeats: false)
                try? await center.add(UNNotificationRequest(
                    identifier: Self.setupIDs[index], content: content, trigger: trigger))
                if token != setupRevision {
                    center.removePendingNotificationRequests(withIdentifiers: Self.setupIDs)
                    break
                }
            }
        }
    }

    var authorized: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }

    nonisolated static var enabled: Bool { UserDefaults.standard.bool(forKey: "nanobeasts.notifications.enabled") }

    func setPreference(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        revision += 1
        if !enabled {
            cancelOnboardingReminders()
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
        }
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        guard !isRequesting else { return false }
        isRequesting = true
        defer { isRequesting = false }
        await refreshAuthorization()
        if authorization == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
        }
        return authorized
    }

    func updateProgress(stageID: String, name: String, isEgg: Bool, remaining: Int,
                        target: Int, journey: Date?, eligible: Bool) async {
        revision += 1
        pendingProgress = Progress(stageID: stageID, name: name, isEgg: isEgg,
                                   remaining: remaining, target: target, journey: journey, eligible: eligible)
        guard !isScheduling else { return }
        isScheduling = true
        defer { isScheduling = false }
        // Serialize notification writes, retaining the newest activity while awaiting iOS.
        while let progress = pendingProgress {
            pendingProgress = nil
            await schedule(progress)
        }
    }

    private func schedule(_ progress: Progress) async {
        guard progress.eligible, Self.enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.progressID])
            return
        }
        let token = revision
        await refreshAuthorization()
        guard token == revision else { return }
        guard NanoReminderPolicy.shouldRemind(enabled: Self.enabled, authorized: authorized,
                                               remaining: progress.remaining, target: progress.target) else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.progressID])
            return
        }
        let milestone = "\(progress.journey?.timeIntervalSince1970 ?? 0):\(progress.stageID)"
        let key = "nanobeasts.notifications.lastMilestone"
        guard UserDefaults.standard.string(forKey: key) != milestone else { return }
        let content = UNMutableNotificationContent()
        content.title = progress.isEgg ? "Your egg is close to hatching" : "An evolution is getting closer"
        content.body = "\(progress.name) is nearly there. A little movement goes a long way."
        content.sound = .default
        let request = UNNotificationRequest(identifier: Self.progressID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        do {
            try await center.add(request)
            guard token == revision, Self.enabled else {
                center.removePendingNotificationRequests(withIdentifiers: [Self.progressID])
                return
            }
            UserDefaults.standard.set(milestone, forKey: key)
        } catch {
            // Retry on a later authoritative activity update; never invent activity.
        }
    }
}
