import Foundation

/// A reward stays pending until Home can actually present it. Changes to any
/// blocker are observable, so dismissing a workout or tour retries delivery.
struct RewardPresentationState: Equatable {
    var hasAccess: Bool
    var isHome: Bool
    var isActive: Bool
    var isLoading: Bool
    var showsSplash: Bool
    var showsTour: Bool
    var showsWorkout: Bool
    var showsSheet: Bool
    var homeIsBusy: Bool
    var showsPaywall: Bool
    var showsEvolution: Bool
    var showsBadge: Bool

    var isReady: Bool {
        hasAccess && isHome && isActive && !isLoading && !showsSplash
            && !showsTour && !showsWorkout && !showsSheet && !homeIsBusy
            && !showsPaywall && !showsEvolution && !showsBadge
    }
}

enum BadgeAwardDelivery {
    static func validAcknowledgements(_ acknowledged: Set<String>, unlockedIDs: Set<String>) -> Set<String> {
        acknowledged.intersection(unlockedIDs)
    }

    struct Candidate {
        let id: String
        let completedAt: Date?
        let unlocked: Bool
        let acknowledged: Bool
    }

    static func pendingIDs(_ candidates: [Candidate]) -> [String] {
        var seen = Set<String>()
        return candidates
            .filter { $0.unlocked && !$0.acknowledged }
            .sorted {
                let lhs = $0.completedAt ?? .distantPast
                let rhs = $1.completedAt ?? .distantPast
                return lhs == rhs ? $0.id < $1.id : lhs > rhs
            }
            .compactMap { seen.insert($0.id).inserted ? $0.id : nil }
    }
}
