import AuthenticationServices
import CryptoKit
import Foundation
import Observation

/// Sign in with Apple, step uploads, and the weekly friends leaderboard.
/// Nothing here runs until the player asks to race friends.
@MainActor
@Observable
final class FriendsStore {
    private(set) var me: FriendsUser?
    private(set) var board: LeaderboardResponse?
    private(set) var isWorking = false
    var errorMessage: String?
    /// An invite opened before sign-in; it's accepted right after signing in.
    private(set) var pendingInviteCode: String?
    /// Bumped when an invite link arrives so Home can open the leaderboard.
    private(set) var leaderboardRequestID = 0
    private var seenPodiumWeek: String?

    @ObservationIgnored private weak var appStore: AppStore?
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var currentNonce: String?
    @ObservationIgnored private var lastUpload: Date?
    @ObservationIgnored private var uploadTask: Task<Void, Never>?
    @ObservationIgnored private let healthClient = HealthKitClient()
    @ObservationIgnored private let defaults: UserDefaults

    private static let meKey = "nanobeasts.friends.me.v1"
    private static let boardKey = "nanobeasts.friends.board.v1"
    private static let inviteKey = "nanobeasts.friends.pending-invite.v1"
    private static let podiumKey = "nanobeasts.friends.podium-seen.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        token = FriendsKeychain.read()
        if token != nil {
            me = defaults.data(forKey: Self.meKey).flatMap { try? JSONDecoder().decode(FriendsUser.self, from: $0) }
            board = defaults.data(forKey: Self.boardKey).flatMap {
                try? JSONDecoder().decode(LeaderboardResponse.self, from: $0)
            }
        }
        pendingInviteCode = defaults.string(forKey: Self.inviteKey)
        seenPodiumWeek = defaults.string(forKey: Self.podiumKey)
    }

    var isSignedIn: Bool { token != nil && me != nil }

    private var api: FriendsAPI { FriendsAPI(token: token) }

    // MARK: - Ranking

    /// This week's standings, most steps first.
    var weekRanking: [LeaderboardEntry] {
        ranked(by: \.week)
    }

    var todayRanking: [LeaderboardEntry] {
        ranked(by: \.today)
    }

    var hasFriends: Bool { (board?.entries.count ?? 0) > 1 }

    var weeklyRank: Int? {
        weekRanking.firstIndex(where: \.isMe).map { $0 + 1 }
    }

    var lastWeekRanking: [LeaderboardEntry] {
        ranked(by: \.lastWeek)
    }

    /// Last week's results exist once a friend is on the board and someone walked.
    var hasLastWeekResults: Bool {
        hasFriends && (board?.entries.contains { $0.lastWeek > 0 } ?? false)
    }

    /// Home shows last week's results on Sunday and Monday until they're dismissed.
    var weeklyResultsDue: Bool {
        guard let board, hasLastWeekResults, seenPodiumWeek != board.weekStart else { return false }
        return board.today <= Self.addDays(board.weekStart, 1)
    }

    func dismissWeeklyResults() {
        guard let board else { return }
        seenPodiumWeek = board.weekStart
        defaults.set(board.weekStart, forKey: Self.podiumKey)
    }

    /// "Sep 27 – Oct 3" for the week that just ended.
    var lastWeekLabel: String {
        guard let board else { return "Last week" }
        return Self.rangeLabel(from: Self.addDays(board.weekStart, -7), to: Self.addDays(board.weekStart, -1))
            ?? "Last week"
    }

    // MARK: - Race details

    /// "Oct 4 – Oct 10" for the current week.
    var thisWeekLabel: String? {
        guard let board else { return nil }
        return Self.rangeLabel(from: board.weekStart, to: Self.addDays(board.weekStart, 6))
    }

    /// The week's number in the year, as on a race calendar.
    var weekNumber: Int? {
        guard let board, let start = Self.parseDay(board.weekStart) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.component(.weekOfYear, from: start)
    }

    /// Which day of the seven-day race it is, from 1 (Sunday) to 7.
    var raceDay: Int {
        guard let board, let start = Self.parseDay(board.weekStart), let today = Self.parseDay(board.today)
        else { return 1 }
        return min(max(Int((today.timeIntervalSince(start) / 86_400).rounded()) + 1, 1), 7)
    }

    /// Places gained (positive) or lost since the end of yesterday, by player ID.
    /// Empty on Sunday, when there is no earlier standing to compare with.
    var weeklyMovement: [String: Int] {
        guard raceDay > 1, let entries = board?.entries else { return [:] }
        let now = weekRanking.map(\.id)
        let before = sorted(entries) { $0.week - $0.today }.map(\.id)
        var movement: [String: Int] = [:]
        for (index, id) in now.enumerated() {
            if let previous = before.firstIndex(of: id), previous != index {
                movement[id] = previous - index
            }
        }
        return movement
    }

    /// The biggest single day anyone on the board has walked this week.
    var bestDayOfWeek: (entry: LeaderboardEntry, day: LeaderboardEntry.BestDay)? {
        board?.entries
            .compactMap { entry in entry.bestDay.map { (entry: entry, day: $0) } }
            .max { $0.day.steps < $1.day.steps }
    }

    /// "Tuesday" for a "YYYY-MM-DD" day.
    static func weekdayName(_ day: String) -> String {
        guard let date = parseDay(day) else { return "" }
        var style = Date.FormatStyle.dateTime.weekday(.wide)
        style.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(style)
    }

    private func ranked(by steps: KeyPath<LeaderboardEntry, Int>) -> [LeaderboardEntry] {
        sorted(board?.entries ?? []) { $0[keyPath: steps] }
    }

    private func sorted(_ entries: [LeaderboardEntry], by steps: (LeaderboardEntry) -> Int) -> [LeaderboardEntry] {
        entries.sorted {
            if steps($0) != steps($1) { return steps($0) > steps($1) }
            if $0.isMe != $1.isMe { return $0.isMe }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private static func parseDay(_ day: String) -> Date? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        return parser.date(from: day)
    }

    private static func rangeLabel(from first: String, to last: String) -> String? {
        guard let start = parseDay(first), let end = parseDay(last) else { return nil }
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = TimeZone(identifier: "UTC")!
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }

    // MARK: - Lifecycle

    func attach(to appStore: AppStore) {
        guard self.appStore !== appStore else { return }
        self.appStore = appStore
        appStore.onStepsRefreshed = { [weak self] in
            self?.scheduleUpload()
        }
    }

    /// Uploads steps and reloads the board. Called when Home appears and on pull to refresh.
    func refresh() async {
        guard isSignedIn else { return }
        await uploadSteps(force: true)
        await syncProfileIfNeeded()
        await loadBoard()
    }

    // MARK: - Sign in with Apple

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        // The player's Nanobeasts name is used instead of their Apple name or email.
        request.requestedScopes = []
        request.nonce = Self.sha256(nonce)
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Sign in with Apple didn't go through. Try again."
            }
        case let .success(authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let identityToken = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
                let nonce = currentNonce
            else {
                errorMessage = "Sign in with Apple didn't go through. Try again."
                return
            }
            await perform {
                let response = try await FriendsAPI().signInWithApple(
                    identityToken: identityToken,
                    authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                    nonce: nonce,
                    displayName: self.profileName,
                    avatarKey: self.appStore?.currentStage.imageKey
                )
                self.token = response.token
                FriendsKeychain.write(response.token)
                self.setMe(response.user)
                await self.acceptPendingInvite()
                await self.uploadSteps(force: true)
                await self.loadBoard()
            }
        }
    }

    func signOut() async {
        let api = api
        try? await api.signOut()
        clearSession()
    }

    func deleteAccount() async {
        await perform {
            try await self.api.deleteAccount()
            self.clearSession()
        }
    }

    // MARK: - Friends

    /// Handles nanobeasts.app/i/CODE and nanobeasts://invite/CODE.
    func handleInviteURL(_ url: URL) -> Bool {
        let parts = url.pathComponents.filter { $0 != "/" }
        let code: String?
        if url.host?.lowercased() == "nanobeasts.app", parts.first == "i" {
            code = parts.dropFirst().first
        } else if url.scheme?.lowercased() == "nanobeasts", url.host?.lowercased() == "invite" {
            code = parts.first
        } else {
            return false
        }
        guard let code = code.map(Self.normalizedCode), !code.isEmpty else { return false }
        leaderboardRequestID += 1
        if isSignedIn {
            Task { await addFriend(code: code) }
        } else {
            pendingInviteCode = code
            defaults.set(code, forKey: Self.inviteKey)
        }
        return true
    }

    func addFriend(code: String) async {
        let code = Self.normalizedCode(code)
        guard !code.isEmpty else { return }
        await perform {
            try await self.api.addFriend(code: code)
            await self.loadBoard()
        }
    }

    func removeFriend(_ entry: LeaderboardEntry) async {
        await perform {
            try await self.api.removeFriend(id: entry.id)
            await self.loadBoard()
        }
    }

    private func acceptPendingInvite() async {
        guard let code = pendingInviteCode else { return }
        pendingInviteCode = nil
        defaults.removeObject(forKey: Self.inviteKey)
        if me?.inviteCode == code { return }
        do {
            try await api.addFriend(code: code)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sync

    private var profileName: String {
        let name = appStore?.playerName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Researcher" : String(name.prefix(20))
    }

    private func syncProfileIfNeeded() async {
        guard let me else { return }
        let avatar = appStore?.currentStage.imageKey
        guard me.displayName != profileName || me.avatarKey != avatar || me.timeZone != TimeZone.current.identifier
        else { return }
        if let updated = try? await api.updateProfile(displayName: profileName, avatarKey: avatar) {
            setMe(updated)
        }
    }

    private func scheduleUpload() {
        guard isSignedIn, uploadTask == nil else { return }
        uploadTask = Task {
            await uploadSteps(force: false)
            uploadTask = nil
        }
    }

    /// Sends this week's and last week's daily totals. The server ignores days
    /// outside the open weeks, so sending both is always safe.
    private func uploadSteps(force: Bool) async {
        guard isSignedIn, let appStore else { return }
        if !force, let lastUpload, Date().timeIntervalSince(lastUpload) < 60 { return }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -13, to: today) else { return }

        var records: [DailyStepRecord]
        if appStore.healthState == .connected,
           let recorded = try? await healthClient.fetchDailySteps(startingAt: start, excludingUserEntered: true) {
            records = recorded
        } else {
            records = appStore.analyticsHistory.filter { $0.day >= start }
        }
        guard !records.isEmpty else { return }

        let formatter = Self.dayFormatter
        let days = records.map { FriendsDayTotal(date: formatter.string(from: $0.day), steps: $0.steps) }
        do {
            try await api.uploadSteps(days)
            lastUpload = Date()
        } catch FriendsAPIError.unauthorized {
            clearSession()
        } catch {
            // Offline uploads are retried on the next refresh.
        }
    }

    private func loadBoard() async {
        do {
            let board = try await api.leaderboard()
            self.board = board
            defaults.set(try? JSONEncoder().encode(board), forKey: Self.boardKey)
        } catch FriendsAPIError.unauthorized {
            clearSession()
        } catch {
            // Keep showing the cached board.
        }
    }

    private func perform(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch FriendsAPIError.unauthorized {
            clearSession()
            errorMessage = FriendsAPIError.unauthorized.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setMe(_ user: FriendsUser) {
        me = user
        defaults.set(try? JSONEncoder().encode(user), forKey: Self.meKey)
    }

    private func clearSession() {
        token = nil
        me = nil
        board = nil
        lastUpload = nil
        FriendsKeychain.write(nil)
        defaults.removeObject(forKey: Self.meKey)
        defaults.removeObject(forKey: Self.boardKey)
    }

    // MARK: - Helpers

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func normalizedCode(_ code: String) -> String {
        String(code.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(12))
    }

    private static func addDays(_ day: String, _ count: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day) else { return day }
        return formatter.string(from: date.addingTimeInterval(Double(count) * 86_400))
    }

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
