#!/usr/bin/env python3
"""Exercise the real purchase/restore methods with counted service stand-ins."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Nanobeasts/Features/Paywall/RevenueCatPaywallScreen.swift').read_text()
start = source.index('    @MainActor\n    private func purchaseSelectedPlan(')
end = source.index('    private func purchaseErrorMessage(', start)
methods = source[start:end].replace('private func', 'func')
harness = r'''
import Foundation
enum ProductType { case nonConsumable, subscription }
struct Product {
    let productIdentifier: String
    let localizedPriceString: String
    let productType: ProductType
}
struct Package { let storeProduct: Product }
struct PurchaseResult { var userCancelled = false; var customerInfo = 1 }
@MainActor final class Purchases {
    static let shared = Purchases()
    var purchaseCalls = 0, restoreCalls = 0
    func purchase(package: Package) async throws -> PurchaseResult {
        purchaseCalls += 1; return PurchaseResult()
    }
    func restorePurchases() async throws -> Int { restoreCalls += 1; return 1 }
}
@MainActor final class Store {
    var isPremium = false, accessUpdates = 0
    func applyRevenueCatPurchase(_ info: Int) async { accessUpdates += 1; isPremium = true }
    func applyRevenueCatCustomerInfo(_ info: Int) async { accessUpdates += 1; isPremium = true }
}
@MainActor final class Paywall {
    var isPreview = true, isLoadingPlans = false, isPurchasing = false, isRestoring = false
    var selectedPackage: Package?
    var onPreviewPurchase: (() -> Void)?
    var previewNotice: String?, errorMessage: String?
    let store = Store()
    var dismissals = 0
    func dismiss() { dismissals += 1 }
    func purchaseErrorMessage(for error: Error, productID: String) -> String { "error" }
METHODS
}
@MainActor func run() async {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); checks += 1
    }
    let lifetime = Package(storeProduct: Product(productIdentifier: "lifetime", localizedPriceString: "$29.99", productType: .nonConsumable))
    let monthly = Package(storeProduct: Product(productIdentifier: "monthly", localizedPriceString: "$4.99", productType: .subscription))
    let winback = Package(storeProduct: Product(productIdentifier: "winback", localizedPriceString: "$19.99", productType: .nonConsumable))
    for variant in ["original", "refined"] {
        let p = Paywall()
        for package in [lifetime, monthly] {
            p.selectedPackage = package
            await p.purchaseSelectedPlan()
            expect(p.previewNotice?.contains(package.storeProduct.localizedPriceString) == true, "Preview shows simulated selected charge: \(variant)")
            expect(p.previewNotice?.contains("No purchase was made") == true, "Explicit no-purchase notice")
        }
        await p.purchaseSelectedPlan(package: winback)
        expect(p.previewNotice?.contains("$19.99 once for lifetime access") == true, "Win-back simulates its own product")
        await p.restore()
        expect(p.previewNotice?.contains("Restore is simulated") == true, "Preview restore is simulated")
        expect(p.store.accessUpdates == 0 && !p.store.isPremium && p.dismissals == 0, "Preview leaves real access and profile unchanged")
        expect(Purchases.shared.purchaseCalls == 0 && Purchases.shared.restoreCalls == 0, "Preview never calls purchase services")
        var replayCallbacks = 0
        p.onPreviewPurchase = { replayCallbacks += 1 }
        await p.purchaseSelectedPlan()
        expect(replayCallbacks == 1 && p.store.accessUpdates == 0, "Existing onboarding replay callback still works")
        p.isLoadingPlans = true
        await p.purchaseSelectedPlan()
        expect(replayCallbacks == 1, "Loading disables simulated purchase")
        p.isLoadingPlans = false; p.selectedPackage = nil
        await p.purchaseSelectedPlan()
        expect(replayCallbacks == 1, "Missing product cannot simulate purchase")
    }
    let live = Paywall()
    live.isPreview = false; live.selectedPackage = lifetime
    await live.purchaseSelectedPlan()
    expect(Purchases.shared.purchaseCalls == 1 && live.store.isPremium && live.dismissals == 1, "Live checkout still reaches service and grants confirmed access")
    await live.restore()
    expect(Purchases.shared.restoreCalls == 1 && live.store.accessUpdates == 2, "Live restore still reaches service")
    print("Passed \(checks) paywall preview isolation and live checkout checks.")
}
await run()
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='nanobeasts-paywall-preview-') as temp:
    path = Path(temp) / 'main.swift'
    path.write_text(harness)
    subprocess.run(['swift', '-module-cache-path', str(Path(temp) / 'ModuleCache'), str(path)], check=True, cwd=root)
