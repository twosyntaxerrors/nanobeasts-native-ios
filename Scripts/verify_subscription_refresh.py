#!/usr/bin/env python3
"""Run production subscription reconciliation against deterministic billing/StoreKit doubles."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Nanobeasts/Models/AppStore.swift').read_text()
methods = source[source.index('    @ObservationIgnored private var subscriptionRefreshTask'):source.index('    private func updatePremiumStatus')]
methods = methods.replace('@ObservationIgnored ', '')
fixture = r'''
enum CacheFetchPolicy: Equatable { case fetchCurrent, notStaleCachedOrFetched }
struct Entitlement { var isActive: Bool; var expirationDate: Date?; var productIdentifier = "monthly" }
struct Subscription { var expiresDate: Date?; var gracePeriodExpiresDate: Date? }
struct CustomerInfo {
    var requestDate = Date()
    var entitlements: [String: Entitlement] = [:]
    var activeSubscriptions: Set<String> = []
    var subscriptionsByProductIdentifier: [String: Subscription] = [:]
    static func active(until date: Date?, grace: Date? = nil) -> Self {
        Self(entitlements: ["premium": Entitlement(isActive: true, expirationDate: date)],
             activeSubscriptions: ["monthly"],
             subscriptionsByProductIdentifier: ["monthly": Subscription(expiresDate: date, gracePeriodExpiresDate: grace)])
    }
}
enum Failure: Error { case offline }
enum AppScreenshotScenario { static let active: Bool? = nil }
enum Verification<T> { case verified(T), unverified(T) }
enum RenewalState { case subscribed, inGracePeriod, expired }
struct Renewal { var gracePeriodExpirationDate: Date? }
struct Status { var state: RenewalState; var renewalInfo: Verification<Renewal> }
enum ProductType { case autoRenewable, nonConsumable, consumable }
enum StoreKit {
    enum Environment { case production, sandbox }
    @MainActor struct Transaction {
        static var results: [Verification<Transaction>] = []
        static var latestResults: [String: Verification<Transaction>] = [:]
        static func latest(for productID: String) async -> Verification<Transaction>? { latestResults[productID] }
        static var currentEntitlements: AsyncStream<Verification<Transaction>> {
            AsyncStream { continuation in
                results.forEach { continuation.yield($0) }
                continuation.finish()
            }
        }
        var environment: Environment = .production
        var productType = ProductType.autoRenewable
        var productID = "monthly"
        var revocationDate: Date? = nil
        var isUpgraded = false
        var expirationDate: Date?
        var status: Status? = nil
        var subscriptionStatus: Status? { get async { status } }
    }
}
@MainActor final class Purchases {
    static let shared = Purchases()
    static var isConfigured = true
    var offline = false
    var syncOffline = false
    var result = CustomerInfo()
    var syncResult = CustomerInfo()
    var policies: [CacheFetchPolicy] = []
    var syncCount = 0
    var beforeFetch: (() -> Void)?
    var resumeFetch: CheckedContinuation<Void, Never>?
    var pausesFetch = false
    var events: [CustomerInfo] = []
    var customerInfoStream: AsyncStream<CustomerInfo> {
        AsyncStream { c in events.forEach { c.yield($0) }; c.finish() }
    }
    func customerInfo(fetchPolicy: CacheFetchPolicy) async throws -> CustomerInfo {
        policies.append(fetchPolicy)
        beforeFetch?()
        if pausesFetch { await withCheckedContinuation { resumeFetch = $0 } }
        if offline { throw Failure.offline }
        return result
    }
    func syncPurchases() async throws -> CustomerInfo {
        syncCount += 1
        if syncOffline { throw Failure.offline }
        return syncResult
    }
    func reset() {
        offline = false; syncOffline = false; syncCount = 0; policies = []
        beforeFetch = nil; pausesFetch = false; resumeFetch = nil; events = []
        result = CustomerInfo(); syncResult = CustomerInfo(); Self.isConfigured = true
        StoreKit.Transaction.results = []
        StoreKit.Transaction.latestResults = [:]
    }
}
@MainActor final class StoreFixture {
    static let premiumProductIDs: Set<String> = ["monthly", "yearly", "lifetime", "winback"]
    static let lifetimeProductIDs: Set<String> = ["lifetime", "winback"]
    static let isUsingRevenueCatTestStore = false
    static let testStorePremiumUnlockKey = "test-unlock"
    var isOnboardingReplay = false
    let onboardingCompleted = true
    let defaults: UserDefaults
    var isPremium = false
    var hasResolvedInitialSubscription = false
    var changes: [Bool] = []
    init(defaults: UserDefaults) { self.defaults = defaults }
    func updatePremiumStatus(_ value: Bool) { changes.append(value); isPremium = value }
'''
checks = r'''
}
@main struct Checks {
    @MainActor static func main() async throws {
        let suite = "nanobeasts.refresh.checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = Purchases.shared
        let future = Date().addingTimeInterval(3600)
        let past = Date().addingTimeInterval(-3600)
        var count = 0
        func expect(_ passed: Bool, _ message: String) {
            precondition(passed, message); count += 1
        }
        func fresh(premium: Bool = false, expiration: Date? = nil) -> StoreFixture {
            client.reset()
            defaults.removePersistentDomain(forName: suite)
            let store = StoreFixture(defaults: defaults)
            store.isPremium = premium
            let access = NanoSubscriptionAccess(premium: premium, onboardingCompleted: true,
                expiresAt: expiration, updatedAt: Date())
            defaults.set(try! JSONEncoder().encode(access), forKey: NanoSubscriptionAccess.cacheKey)
            return store
        }
        // Initial checks always fetch current data, independent of the saved boolean.
        for premium in [false, true] {
            for expired in [false, true] {
                for offline in [false, true] {
                    for renewed in [false, true] {
                        let store = fresh(premium: premium, expiration: expired ? past : future)
                        client.offline = offline
                        client.result = renewed ? .active(until: future) : CustomerInfo()
                        client.syncResult = client.result
                        await store.refreshSubscriptionStatus()
                        expect(client.policies == [.fetchCurrent], "First check must bypass cached denial")
                        expect(store.hasResolvedInitialSubscription, "Launch must resolve after reconciliation")
                        expect(store.isPremium == (offline ? premium && !expired : renewed), "Incorrect access")
                        if premium && renewed && !offline {
                            expect(!store.changes.contains(false), "Do not flash lapsed UI during renewal")
                        }
                    }
                }
            }
        }
        // A fresh server fetch can still need a silent receipt sync.
        var store = fresh()
        client.syncResult = .active(until: future)
        await store.refreshSubscriptionStatus()
        expect(store.isPremium && client.syncCount == 1, "Silent sync must recover an existing subscription")
        expect(!store.changes.contains(false), "Reconcile before applying an inactive response")
        client.result = .active(until: future)
        await store.refreshSubscriptionStatus()
        expect(client.policies.last == .notStaleCachedOrFetched, "Valid periodic checks may use cache")
        await store.refreshSubscriptionStatus(forceRefresh: true)
        expect(client.policies.last == .fetchCurrent, "Foreground must check current status")

        // Apple-verified renewals work even while RevenueCat is stale or unavailable.
        for offline in [false, true] {
            store = fresh()
            client.offline = offline
            StoreKit.Transaction.results = [.verified(.init(expirationDate: future))]
            await store.refreshSubscriptionStatus()
            expect(store.isPremium, "Signed Apple entitlement must restore access")
            expect(!store.changes.contains(false), "Server lag must not revoke an Apple renewal")
        }
        // Verified lifetime purchases recover permanent access even while RevenueCat is stale/offline.
        for productID in ["lifetime", "winback"] {
            for offline in [false, true] {
                store = fresh()
                client.offline = offline
                StoreKit.Transaction.results = [.verified(.init(productType: .nonConsumable,
                    productID: productID, expirationDate: nil))]
                await store.refreshSubscriptionStatus()
                let data = defaults.data(forKey: NanoSubscriptionAccess.cacheKey)!
                let access = try JSONDecoder().decode(NanoSubscriptionAccess.self, from: data)
                expect(store.isPremium && access.expiresAt == nil && access.isDevelopmentOnly != true,
                    "Lifetime Apple access is permanent in both Release and Debug")
            }
        }
        store = fresh()
        client.result = .active(until: future)
        StoreKit.Transaction.results = [.verified(.init(productType: .nonConsumable,
            productID: "lifetime", expirationDate: nil))]
        await store.refreshSubscriptionStatus()
        let lifetime = try JSONDecoder().decode(NanoSubscriptionAccess.self,
            from: defaults.data(forKey: NanoSubscriptionAccess.cacheKey)!)
        expect(lifetime.expiresAt == nil, "A stale yearly entitlement cannot shorten verified lifetime access")
        // Rejected or ended transactions never bypass the paywall.
        let rejected: [Verification<StoreKit.Transaction>] = [
            .unverified(.init(productType: .nonConsumable, productID: "lifetime", expirationDate: nil)),
            .verified(.init(productType: .nonConsumable, productID: "lifetime", revocationDate: Date(), expirationDate: nil)),
            .verified(.init(productType: .consumable, productID: "lifetime", expirationDate: nil)),
            .verified(.init(productType: .nonConsumable, productID: "unrelated", expirationDate: nil)),
            .unverified(.init(expirationDate: future)),
            .verified(.init(productID: "unrelated", expirationDate: future)),
            .verified(.init(revocationDate: Date(), expirationDate: future)),
            .verified(.init(isUpgraded: true, expirationDate: future)),
            .verified(.init(expirationDate: past)),
            .verified(.init(expirationDate: nil)),
            .verified(.init(expirationDate: past, status: .init(state: .inGracePeriod,
                renewalInfo: .unverified(.init(gracePeriodExpirationDate: future))))),
            .verified(.init(expirationDate: past, status: .init(state: .expired,
                renewalInfo: .verified(.init(gracePeriodExpirationDate: future)))))
        ]
        for transaction in rejected {
            store = fresh()
            StoreKit.Transaction.results = [transaction]
            await store.refreshSubscriptionStatus()
            expect(!store.isPremium, "Invalid Apple evidence must not grant access")
        }
        store = fresh()
        StoreKit.Transaction.results = [.verified(.init(expirationDate: past,
            status: .init(state: .inGracePeriod,
            renewalInfo: .verified(.init(gracePeriodExpirationDate: future)))))]
        await store.refreshSubscriptionStatus()
        expect(store.isPremium, "Verified Apple billing grace retains access")

        // SDK isActive can refer to the time its snapshot was fetched.
        store = fresh()
        client.result = .active(until: past)
        await store.refreshSubscriptionStatus()
        expect(!store.isPremium, "An old active snapshot must not bypass expiry")
        store = fresh()
        client.result = .active(until: past, grace: future)
        await store.refreshSubscriptionStatus()
        expect(store.isPremium, "RevenueCat billing grace retains access")
        store = fresh()
        client.result = .active(until: nil)
        await store.refreshSubscriptionStatus()
        expect(store.isPremium, "Non-expiring entitlement remains valid")

        store = fresh(premium: true, expiration: future)
        client.syncOffline = true
        await store.refreshSubscriptionStatus()
        expect(store.isPremium, "Failed reconciliation must preserve unexpired verified access")
        store = fresh(premium: true, expiration: past)
        client.syncOffline = true
        await store.refreshSubscriptionStatus()
        expect(!store.isPremium, "Failed reconciliation must not extend expired access")

        // A failed silent sync is retried automatically on the next check.
        store = fresh()
        client.syncOffline = true
        await store.refreshSubscriptionStatus()
        client.syncOffline = false; client.syncResult = .active(until: future)
        await store.refreshSubscriptionStatus()
        expect(store.isPremium && client.syncCount == 2, "Retry failed receipt sync without user intervention")

        store = fresh(premium: true, expiration: future)
        let cachedStore = store
        client.beforeFetch = {
            expect(cachedStore.hasResolvedInitialSubscription, "Valid saved access should open before a slow network check")
        }
        client.result = .active(until: future)
        await store.refreshSubscriptionStatus()
        store = fresh()
        StoreKit.Transaction.results = [.verified(.init(expirationDate: future))]
        let appleStore = store
        client.beforeFetch = {
            expect(appleStore.hasResolvedInitialSubscription && appleStore.isPremium,
                   "Verified Apple access should open before a slow server response")
        }
        client.result = .active(until: Date().addingTimeInterval(60))
        await store.refreshSubscriptionStatus()
        let cached = try JSONDecoder().decode(NanoSubscriptionAccess.self,
            from: defaults.data(forKey: NanoSubscriptionAccess.cacheKey)!)
        expect(cached.expiresAt == future, "Server lag must not shorten a verified Apple renewal")

        // An older async result must never overwrite the newer purchase.
        store = fresh()
        let older = CustomerInfo(requestDate: Date().addingTimeInterval(-60))
        await store.applyRevenueCatCustomerInfo(.active(until: future))
        await store.applyRevenueCatCustomerInfo(older)
        expect(store.isPremium, "Out-of-order response overwrote newer access")

        // Launch and foreground share a fetch and both wait for its completion.
        store = fresh()
        client.pausesFetch = true; client.result = .active(until: future)
        let sharedStore = store
        let first = Task { await sharedStore.refreshSubscriptionStatus() }
        while client.resumeFetch == nil { await Task.yield() }
        var secondFinished = false
        let second = Task { await sharedStore.refreshSubscriptionStatus(); secondFinished = true }
        for _ in 0..<10 { await Task.yield() }
        expect(!secondFinished && !store.hasResolvedInitialSubscription, "Concurrent bootstrap returned early")
        expect(client.policies.count == 1, "Concurrent checks must share the fetch")
        client.resumeFetch?.resume()
        await first.value; await second.value
        expect(secondFinished && store.isPremium && store.hasResolvedInitialSubscription, "Both waiters must resolve")

        store = fresh()
        client.events = [.active(until: future)]
        await store.observeSubscriptionUpdates()
        expect(store.isPremium, "Updates must reach the visible app")
        store = fresh()
        client.events = [CustomerInfo()]; client.syncResult = .active(until: future)
        await store.observeSubscriptionUpdates()
        expect(store.isPremium, "Inactive updates must reconcile before locking")
        store = fresh()
        store.isOnboardingReplay = true
        await store.refreshSubscriptionStatus(); await store.observeSubscriptionUpdates()
        expect(client.policies.isEmpty && client.syncCount == 0, "Replay must not touch real billing")
        // Historical sandbox purchases only extend access in Debug builds.
        store = fresh()
        StoreKit.Transaction.latestResults = ["monthly": .verified(.init(environment: .sandbox, expirationDate: past))]
        await store.refreshSubscriptionStatus()
#if DEBUG
        expect(store.isPremium, "Debug must recover the existing expired test purchase")
        let debugAccess = try JSONDecoder().decode(NanoSubscriptionAccess.self,
            from: defaults.data(forKey: NanoSubscriptionAccess.cacheKey)!)
        expect(debugAccess.isDevelopmentOnly == true && debugAccess.expiresAt == nil,
               "Development-only access must be marked and survive accelerated expiry")
#else
        expect(!store.isPremium, "Release must not unlock an expired sandbox purchase")
#endif
        let disallowedHistory: [Verification<StoreKit.Transaction>] = [
            .verified(.init(environment: .production, expirationDate: past)),
            .unverified(.init(environment: .sandbox, expirationDate: past)),
            .verified(.init(environment: .sandbox, productID: "unrelated", expirationDate: past)),
            .verified(.init(environment: .sandbox, revocationDate: Date(), expirationDate: past)),
            .verified(.init(environment: .sandbox, isUpgraded: true, expirationDate: past))
        ]
        for record in disallowedHistory {
            store = fresh()
            StoreKit.Transaction.latestResults = ["monthly": record]
            await store.refreshSubscriptionStatus()
            expect(!store.isPremium, "Testing allowance must require a verified, non-revoked sandbox purchase")
        }
        store = fresh(premium: true)
        let devAccess = NanoSubscriptionAccess(premium: true, onboardingCompleted: true,
            expiresAt: nil, updatedAt: Date(), isDevelopmentOnly: true)
        let devData = try JSONEncoder().encode(devAccess)
        defaults.set(devData, forKey: NanoSubscriptionAccess.cacheKey)
        let restoredDevAccess = try JSONDecoder().decode(NanoSubscriptionAccess.self, from: devData)
        client.offline = true
        await store.refreshSubscriptionStatus()
#if DEBUG
        expect(restoredDevAccess.allowsAccess(at: Date()), "Debug must decode its own testing access")
#else
        expect(!restoredDevAccess.allowsAccess(at: Date()), "Release/Watch must reject development-only cache")
        expect(!store.isPremium, "Release must discard development-only access even while offline")
#endif
        print("PASS: \(count) production subscription checks: launch, renewal, reconciliation, offline, expiry, grace, verified transactions, concurrency, stale responses and live updates.")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='nano-refresh-checks-') as temp_dir:
    temp = Path(temp_dir)
    (temp/'main.swift').write_text((root/'NanobeastsShared/NanoSubscriptionAccess.swift').read_text() + '\n' + fixture + methods + checks)
    for configuration, flags in [('Release', []), ('Debug', ['-D', 'DEBUG'])]:
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *flags, '-module-cache-path', str(temp/'ModuleCache'), str(temp/'main.swift'), '-o', str(temp/'checks')], check=True)
        print(configuration, flush=True)
        subprocess.run([str(temp/'checks')], check=True)

ui = (root/'Nanobeasts/App/AppRootView.swift').read_text()
assert 'if store.onboardingCompleted, !subscriptionIsReady {' in ui
assert 'if store.onboardingCompleted, subscriptionIsReady, !store.isPremium {' in ui
assert '.task { await store.observeSubscriptionUpdates() }' in ui
print('PASS: Launch gate waits for initial subscription resolution and starts the update observer.')
