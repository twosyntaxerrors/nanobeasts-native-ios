#!/usr/bin/env python3
"""Exercise shipping lifetime selection, localized prices and discount eligibility."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Nanobeasts/Features/Paywall/RevenueCatPaywallScreen.swift').read_text()
properties = source[source.index('    private var lifetimeAmount:'):source.index('    private func closePaywall()')].replace('private var', 'var')
harness = r'''
import Foundation
enum PaywallDesign { case original, refined }
enum ProductType { case nonConsumable, autoRenewableSubscription }
enum AppStore {
    static let premiumMonthlyProductID = "monthly"
    static let premiumLifetimeProductID = "lifetime"
    static let premiumLifetimeWinbackProductID = "winback"
}
struct SubscriptionPeriod { enum Unit { case month, year }; var unit: Unit; var value: Int }
struct Product {
    var productIdentifier: String
    var productType = ProductType.nonConsumable
    var localizedPriceString: String
    var price: Decimal
    var currencyCode: String? = "USD"
    var subscriptionPeriod: SubscriptionPeriod? = nil
}
struct Package { var storeProduct: Product }
struct Offering { var availablePackages: [Package] }
struct Paywall {
    enum Plan { case monthly, lifetime }
    var design: PaywallDesign = .original
    var selectedPlan: Plan = .lifetime
    var showsWinback = false
    var isLoadingPlans = false
    var offering: Offering? = Offering(availablePackages: [Package(storeProduct: Product(
        productIdentifier: "lifetime", localizedPriceString: "$29.99", price: Decimal(string: "29.99")!)), Package(storeProduct: Product(
        productIdentifier: "monthly", productType: .autoRenewableSubscription, localizedPriceString: "$4.99",
        price: Decimal(string: "4.99")!, subscriptionPeriod: .init(unit: .month, value: 1)))])
    var winbackOffering: Offering? = Offering(availablePackages: [Package(storeProduct: Product(
        productIdentifier: "winback", localizedPriceString: "$19.99", price: Decimal(string: "19.99")!))])
__PROPERTIES__
}
var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message); checks += 1
}
var p = Paywall()
expect(p.selectedPackage?.storeProduct.productIdentifier == "lifetime", "Default checkout selects standard lifetime")
expect(p.lifetimeAmount == "$29.99", "The store price has no recurring suffix")
expect(p.purchaseSummary == "$29.99, paid once for lifetime access.", "Standard charge is disclosed as one payment")
expect(p.purchaseDisclosure == "Billed today. No recurring payments.", "No trial or renewal promise")
expect(p.canOfferWinback, "Discount follows actual same-currency prices")
p.showsWinback = true
expect(p.selectedPackage?.storeProduct.productIdentifier == "lifetime" && p.winbackPackage?.storeProduct.productIdentifier == "winback", "Popup has a separate product and preserves the underlying selection")
expect(p.winbackAmount == "$19.99", "Popup price comes from its own product")
expect(p.winbackDiscountPercent == 33, "US offer derives its discount from actual product prices")
expect(p.purchaseButtonTitle == "Unlock Forever", "Original lifetime CTA removes Pro")
p.design = .refined
expect(p.purchaseButtonTitle == "Unlock Forever", "New lifetime CTA removes Pro")
expect(p.lifetimeComparison == "About 6 monthly payments. Yours forever.", "Lifetime comparison follows real prices")
p.offering?.availablePackages[1].storeProduct.price = 10
expect(p.lifetimeComparison == "About 3 monthly payments. Yours forever.", "Comparison updates when monthly pricing changes")
p.offering?.availablePackages[1].storeProduct.currencyCode = "EUR"
expect(p.lifetimeComparison == nil, "Do not compare lifetime and monthly in different currencies")
p.offering?.availablePackages[1].storeProduct.currencyCode = nil
expect(p.lifetimeComparison == nil, "Unknown currency cannot produce a comparison")
p.offering?.availablePackages[1].storeProduct.price = 0
expect(p.lifetimeComparison == nil, "Do not divide by a free monthly plan")
p.winbackOffering?.availablePackages[0].storeProduct.localizedPriceString = "19,99 €"
p.winbackOffering?.availablePackages[0].storeProduct.currencyCode = "EUR"
expect(p.winbackAmount == "19,99 €", "Use StoreKit's localized string")
expect(!p.canOfferWinback && p.winbackDiscountPercent == nil, "Do not compare different currencies or publish a mismatched discount")
p = Paywall()
for price: Decimal in [0, 30, -1] {
    p.winbackOffering?.availablePackages[0].storeProduct.price = price
    expect(!p.canOfferWinback, "Free or higher-priced products are not discounts")
}
p = Paywall()
p.offering?.availablePackages[0].storeProduct.productType = .autoRenewableSubscription
expect(p.standardPackage == nil && !p.canOfferWinback, "Never sell a subscription as lifetime")
p = Paywall()
p.winbackOffering?.availablePackages[0].storeProduct.productIdentifier = "unrelated"
expect(p.winbackPackage == nil && !p.canOfferWinback, "Do not substitute another product for win-back")
p = Paywall()
p.isLoadingPlans = true
expect(p.lifetimeAmount == "Loading…" && p.purchaseButtonTitle == "Loading…", "Loading does not quote a stale charge")
expect(p.purchaseSummary.isEmpty && p.purchaseDisclosure.isEmpty && !p.canOfferWinback, "Loading cannot promise a price or discount")
p.isLoadingPlans = false
p.offering = nil
expect(p.lifetimeAmount == "Unavailable" && p.purchaseButtonTitle == "Plan unavailable", "Missing products have no fabricated price")
expect(p.purchaseSummary.isEmpty && p.purchaseDisclosure.isEmpty && !p.canOfferWinback, "Unavailable checkout makes no billing promise")
p = Paywall()
p.offering?.availablePackages[0].storeProduct.currencyCode = "EUR"
p.offering?.availablePackages[0].storeProduct.price = Decimal(string: "34.99")!
p.winbackOffering?.availablePackages[0].storeProduct.currencyCode = "EUR"
p.winbackOffering?.availablePackages[0].storeProduct.price = Decimal(string: "22.99")!
expect(p.winbackDiscountPercent == 34, "Discount follows international prices, with rounding down")
p.offering?.availablePackages[0].storeProduct.price = 10
p.winbackOffering?.availablePackages[0].storeProduct.price = Decimal(string: "9.95")!
expect(p.winbackDiscountPercent == nil, "Sub-percent discounts do not show a zero-percent headline")
p = Paywall()
p.selectedPlan = .monthly
p.design = .refined
expect(p.monthlyAmount == "$4.99", "Monthly price is retained")
expect(p.selectedPackage?.storeProduct.productIdentifier == "monthly", "Monthly selection purchases the monthly product")
expect(p.purchaseSummary == "$4.99/month, billed today.", "Disclose the monthly charge")
expect(p.purchaseDisclosure == "Renews automatically until cancelled.", "Monthly has recurring billing disclosure")
expect(p.purchaseButtonTitle == "Start your journey", "Monthly does not promise lifetime access")
p.offering?.availablePackages[1].storeProduct.subscriptionPeriod = .init(unit: .year, value: 1)
expect(p.monthlyPackage == nil, "Reject a yearly product in the monthly slot")
print("Passed \(checks) monthly/lifetime pricing and win-back checks.")
'''.replace('__PROPERTIES__', properties)
with tempfile.TemporaryDirectory(prefix='nanobeasts-lifetime-pricing-') as temp:
    path = Path(temp) / 'main.swift'
    path.write_text(harness)
    subprocess.run(['swift', '-module-cache-path', str(Path(temp) / 'ModuleCache'), str(path)], check=True, cwd=root)
