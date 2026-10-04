import Foundation

struct NanoSubscriptionAccess: Codable, Equatable, Sendable {
    static let contextKey = "nanoSubscriptionAccess"
    static let cacheKey = "nanobeasts.subscription.access.v1"
    let premium: Bool
    let onboardingCompleted: Bool
    let expiresAt: Date?
    let updatedAt: Date
    var isDevelopmentOnly: Bool? = nil

    var permitsCurrentBuild: Bool {
#if DEBUG
        true
#else
        isDevelopmentOnly != true
#endif
    }

    static func accessExpiration(paidThrough: Date?, graceThrough: Date?) -> Date? {
        // A non-expiring entitlement must stay non-expiring. For a subscription,
        // Apple's billing grace period extends the original paid period.
        guard let paidThrough else { return nil }
        return max(paidThrough, graceThrough ?? paidThrough)
    }

    func allowsAccess(at date: Date) -> Bool {
        permitsCurrentBuild && premium && onboardingCompleted && (expiresAt.map { $0 > date } ?? true)
    }
}
