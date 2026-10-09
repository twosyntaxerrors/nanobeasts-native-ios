import Foundation
import Security

struct FriendsUser: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let avatarKey: String?
    let timeZone: String
    let inviteCode: String
    let inviteURL: URL
}

struct LeaderboardEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let avatarKey: String?
    let isMe: Bool
    /// Milliseconds since 1970 of the player's last step upload.
    let updatedAt: Double?
    let today: Int
    let week: Int
    let lastWeek: Int

    var lastSync: Date? {
        updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}

struct LeaderboardResponse: Codable, Equatable, Sendable {
    /// The signed-in player's current week start and today, as "YYYY-MM-DD".
    let weekStart: String
    let today: String
    let entries: [LeaderboardEntry]
}

struct FriendsDayTotal: Codable, Sendable {
    let date: String
    let steps: Int
}

enum FriendsAPIError: LocalizedError {
    case unauthorized
    case server(String)
    case offline

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Your sign-in expired. Sign in again to see your friends."
        case .offline:
            "Couldn't reach Nanobeasts. Check your connection and try again."
        case let .server(code):
            switch code {
            case "invite_not_found": "That invite code doesn't exist. Check it and try again."
            case "own_invite": "That's your own invite code. Share it with a friend instead."
            case "friend_limit": "You've reached the 100-friend limit."
            case "invalid_identity_token", "invalid_nonce": "Sign in with Apple didn't go through. Try again."
            default: "Something went wrong. Try again in a moment."
            }
        }
    }
}

/// Talks to the friends Worker at nanobeasts.app/api/v1.
struct FriendsAPI: Sendable {
    static let baseURL = URL(string: "https://nanobeasts.app/api/v1/")!

    var token: String?

    struct SignInResponse: Decodable {
        let token: String
        let user: FriendsUser
    }

    private struct UserResponse: Decodable {
        let user: FriendsUser
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    private struct Empty: Decodable {}

    func signInWithApple(
        identityToken: String,
        authorizationCode: String?,
        nonce: String,
        displayName: String,
        avatarKey: String?
    ) async throws -> SignInResponse {
        try await send("POST", "auth/apple", body: [
            "identityToken": identityToken,
            "authorizationCode": authorizationCode,
            "nonce": nonce,
            "displayName": displayName,
            "avatarKey": avatarKey,
            "timeZone": TimeZone.current.identifier,
        ])
    }

    func updateProfile(displayName: String, avatarKey: String?) async throws -> FriendsUser {
        let response: UserResponse = try await send("PATCH", "me", body: [
            "displayName": displayName,
            "avatarKey": avatarKey,
            "timeZone": TimeZone.current.identifier,
        ])
        return response.user
    }

    func uploadSteps(_ days: [FriendsDayTotal]) async throws {
        struct Upload: Encodable {
            let timeZone: String
            let days: [FriendsDayTotal]
        }
        let _: Empty = try await send(
            "PUT", "steps",
            encodable: Upload(timeZone: TimeZone.current.identifier, days: days)
        )
    }

    func leaderboard() async throws -> LeaderboardResponse {
        try await send("GET", "leaderboard")
    }

    func addFriend(code: String) async throws {
        let _: Empty = try await send("POST", "friends", body: ["code": code])
    }

    func removeFriend(id: String) async throws {
        let _: Empty = try await send("DELETE", "friends/\(id)")
    }

    func signOut() async throws {
        let _: Empty = try await send("POST", "auth/signout")
    }

    func deleteAccount() async throws {
        let _: Empty = try await send("DELETE", "me")
    }

    private func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        body: [String: String?]? = nil
    ) async throws -> Response {
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0.compactMapValues { $0 }) }
        return try await perform(method, path, data: data)
    }

    private func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        encodable: some Encodable
    ) async throws -> Response {
        try await perform(method, path, data: JSONEncoder().encode(encodable))
    }

    private func perform<Response: Decodable>(
        _ method: String,
        _ path: String,
        data: Data?
    ) async throws -> Response {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FriendsAPIError.offline
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw FriendsAPIError.unauthorized }
        guard (200..<300).contains(status) else {
            let code = (try? JSONDecoder().decode(ErrorResponse.self, from: responseData))?.error
            throw FriendsAPIError.server(code ?? "http_\(status)")
        }
        if Response.self == Empty.self { return Empty() as! Response }
        return try JSONDecoder().decode(Response.self, from: responseData)
    }
}

/// The session token lives in the Keychain; it never leaves this device.
enum FriendsKeychain {
    private static let service = "com.twosyntaxerrors.nanobeasts.friends"
    private static let account = "session"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ token: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let token, let data = token.data(using: .utf8) else { return }
        var item = query
        item[kSecValueData as String] = data
        // Background HealthKit deliveries upload steps while the phone is locked.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
