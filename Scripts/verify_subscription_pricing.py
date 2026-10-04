#!/usr/bin/env python3
"""Exercise the production paywall copy with billing/eligibility fixtures.

Only RevenueCat's data types are replaced. The Swift computed properties are
extracted from the shipping view so the checks run against its actual logic.
No StoreKit purchase or customer data is involved.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "Nanobeasts/Features/Paywall/RevenueCatPaywallScreen.swift").read_text()
properties = source.split("    private var yearlyPrice: String {", 1)[1]
properties = "    private var yearlyPrice: String {" + properties.split("    private var monthlyPackage: Package? {", 1)[0]
properties = properties.replace("private var", "var")

harness = r'''
import Foundation

enum Eligibility { case eligible, ineligible, unknown, noIntroOfferExists }
enum PaymentMode { case freeTrial, payUpFront }
enum Unit { case day, week, month, year }
struct Period {
    var value: Int; var unit: Unit
    func numberOfUnitsAs(unit: Unit) -> Decimal {
        precondition(unit == .week)
        switch self.unit {
        case .year: return Decimal(value) * 365 / 7
        case .month: return Decimal(value) * 365 / 12 / 7
        case .week: return Decimal(value)
        case .day: return Decimal(value) / 7
        }
    }
}
struct Discount {
    var paymentMode = PaymentMode.freeTrial
    var subscriptionPeriod = Period(value: 1, unit: .week)
    var numberOfPeriods = 1
}
struct Product {
    var localizedPriceString: String
    var price: Decimal
    var currencyCode: String? = "USD"
    var localeID = "en_US"
    var subscriptionPeriod: Period? = .init(value: 1, unit: .year)
    var introductoryDiscount: Discount? = nil
    var priceFormatter: NumberFormatter? {
        guard let currencyCode else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localeID)
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter
    }
}
struct Package { var storeProduct: Product }
struct Paywall {
    enum Plan { case yearly, monthly }
    var selectedPlan = Plan.yearly
    var isLoadingPlans = false
    var yearlyTrialEligibility = Eligibility.eligible
    var yearlyPackage: Package? = Package(storeProduct: Product(
        localizedPriceString: "$29.99", price: Decimal(string: "29.99")!, introductoryDiscount: Discount()))
    var monthlyPackage: Package? = Package(storeProduct: Product(
        localizedPriceString: "$4.99", price: Decimal(string: "4.99")!))
    var selectedPackage: Package? { selectedPlan == .yearly ? yearlyPackage : monthlyPackage }
__PROPERTIES__
}

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
    precondition(condition(), description)
    checks += 1
}

var p = Paywall()
expect(p.yearlyPrice == "$29.99/year", "Full annual charge must remain visible")
expect(p.monthlyPrice == "$4.99/month", "Monthly price comes from store")
expect(p.yearlySavingsBadge == "SAVE 50%", "Annual savings rounds the actual comparison against 12 monthly payments")
expect(p.eligibleYearlyTrialDuration == "7 days", "One-week Apple offer means seven days")
expect(p.yearlyDetail == "Free trial for 7 days", "Annual card explicitly labels the free trial")
expect(p.purchaseButtonTitle == "Try for $0", "Eligible yearly subscriber gets zero-cost trial CTA")
expect(p.purchaseSummary == "7 days free, then $29.99/year.", "CTA must disclose trial length and full renewal charge")
expect(p.renewalDisclosure.contains("Renews automatically"), "Trial discloses automatic renewal")
expect(p.renewalDisclosure.contains("24 hours"), "Trial cancellation timing is disclosed")
p.selectedPlan = .monthly
expect(p.purchaseButtonTitle == "Start your journey", "Monthly selection never promises the yearly trial")
expect(p.purchaseSummary == "$4.99/month, billed today. No free trial.", "Monthly CTA states immediate payment")
expect(p.renewalDisclosure == "Renews automatically until cancelled.", "Monthly renews until cancelled")

for eligibility in [Eligibility.ineligible, .unknown, .noIntroOfferExists] {
    p = Paywall()
    p.yearlyTrialEligibility = eligibility
    expect(p.eligibleYearlyTrialDuration == nil, "Never promise an unconfirmed or unavailable trial")
    expect(p.yearlyDetail == "Billed yearly", "Annual card does not promise an unavailable trial")
    expect(p.purchaseButtonTitle == "Start your journey", "Noneligible annual CTA")
    expect(p.purchaseSummary == "$29.99/year, billed today.", "Ineligible or unknown eligibility must not advertise zero cost")
    expect(!p.renewalDisclosure.contains("trial"), "No false free-trial disclosure")
}

p = Paywall()
p.yearlyPackage?.storeProduct.introductoryDiscount?.paymentMode = .payUpFront
expect(p.eligibleYearlyTrialDuration == nil, "A paid introduction must never be advertised as free")
p.yearlyPackage?.storeProduct.introductoryDiscount = nil
expect(p.eligibleYearlyTrialDuration == nil, "Eligibility alone does not establish that an offer exists")

p = Paywall()
p.yearlyPackage?.storeProduct.localizedPriceString = "29,99 €"
p.yearlyPackage?.storeProduct.currencyCode = "EUR"
expect(p.yearlyPrice == "29,99 €/year", "Preserve the store's localized currency string")
expect(p.purchaseButtonTitle == "Try for €0", "Use the product currency for zero-cost trial copy")
expect(p.yearlySavingsBadge == nil, "Never compare prices in different currencies")
p.monthlyPackage?.storeProduct.currencyCode = "EUR"
expect(p.yearlySavingsBadge == "SAVE 50%", "Matching currencies enable actual-price savings")
p.monthlyPackage?.storeProduct.price = 0
expect(p.yearlySavingsBadge == nil, "Zero monthly price cannot be a savings denominator")
p.monthlyPackage?.storeProduct.price = 1
expect(p.yearlySavingsBadge == nil, "Do not show savings when annual costs more")

p = Paywall()
p.yearlyPackage?.storeProduct.introductoryDiscount?.subscriptionPeriod = Period(value: 3, unit: .day)
expect(p.eligibleYearlyTrialDuration == "3 days", "Trial duration comes from the store, not a hardcoded seven")
expect(p.purchaseSummary == "3 days free, then $29.99/year.", "CTA summary follows the actual offer duration")

p = Paywall()
p.yearlyPackage?.storeProduct.currencyCode = nil
expect(p.purchaseButtonTitle == "Start your free trial", "Missing currency never fabricates a dollar price")

p = Paywall()
p.yearlyPackage = nil
p.monthlyPackage = nil
p.isLoadingPlans = true
expect(p.yearlyPrice == "Loading…" && p.monthlyPrice == "Loading…", "Never fabricate fallback prices while loading")
expect(p.purchaseButtonTitle == "Loading plans…", "Loading CTA")
expect(p.purchaseSummary.isEmpty, "Loading products do not promise a billing amount")
expect(p.yearlySavingsBadge == nil, "No savings without products")
p.isLoadingPlans = false
expect(p.yearlyPrice == "Unavailable" && p.monthlyPrice == "Unavailable", "Missing products are unavailable")
expect(p.purchaseButtonTitle == "Plan unavailable", "Missing product CTA")
expect(p.purchaseSummary.isEmpty, "Unavailable products do not promise a trial")
expect(p.renewalDisclosure.isEmpty, "No fabricated billing disclosures")

p = Paywall()
expect(p.yearlyWeeklyEquivalent == "$0.58", "Annual equivalent rounds to the nearest cent using the product period")
expect(p.annualBillingPrice == "$29.99/year", "The actual yearly charge is still prominent below checkout")
expect(p.annualBillingLeadIn == "7 days free, then", "The billing amount follows the eligible trial")
p.yearlyTrialEligibility = .ineligible
expect(p.annualBillingLeadIn == "Billed today, then annually", "Ineligible users see immediate billing")
p.selectedPlan = .monthly
expect(p.annualBillingPrice == nil, "Monthly checkout never shows annual billing as the selected charge")
p = Paywall()
p.yearlyPackage?.storeProduct.price = Decimal(string: "49.99")!
p.yearlyPackage?.storeProduct.localizedPriceString = "$49.99"
expect(p.yearlyWeeklyEquivalent == "$0.96", "Weekly comparison follows changed store prices")
expect(p.annualBillingPrice == "$49.99/year", "Full renewal disclosure follows changed store prices")
p.yearlyPackage?.storeProduct.price = Decimal(string: "29.99")!
p.yearlyPackage?.storeProduct.localeID = "de_DE"
p.yearlyPackage?.storeProduct.currencyCode = "EUR"
expect(p.yearlyWeeklyEquivalent?.contains("0,58") == true && p.yearlyWeeklyEquivalent?.contains("€") == true, "Use the storefront decimal separator and currency")
p.yearlyPackage?.storeProduct.price = 3000
p.yearlyPackage?.storeProduct.localeID = "ja_JP"
p.yearlyPackage?.storeProduct.currencyCode = "JPY"
expect(p.yearlyWeeklyEquivalent?.contains("58") == true && p.yearlyWeeklyEquivalent?.contains(".") == false, "Yen equivalents have no invented cents")
p.yearlyPackage?.storeProduct.currencyCode = nil
expect(p.yearlyWeeklyEquivalent == nil, "No fabricated currency when the formatter is missing")
p = Paywall()
p.yearlyPackage?.storeProduct.subscriptionPeriod = nil
expect(p.yearlyWeeklyEquivalent == nil, "Do not invent an annual period")
p.yearlyPackage?.storeProduct.subscriptionPeriod = .init(value: 1, unit: .month)
expect(p.yearlyWeeklyEquivalent == nil, "Do not mistake another subscription period for the annual product")
p.yearlyPackage?.storeProduct.subscriptionPeriod = .init(value: 0, unit: .year)
expect(p.yearlyWeeklyEquivalent == nil, "Invalid periods cannot divide by zero")
p = Paywall()
p.yearlyPackage?.storeProduct.price = 0
expect(p.yearlyWeeklyEquivalent == nil, "Do not advertise a fake free weekly rate")
p = Paywall()
p.isLoadingPlans = true
expect(p.yearlyWeeklyEquivalent == nil && p.annualBillingPrice == nil, "Loading does not present stale weekly quotes")
p.isLoadingPlans = false; p.yearlyPackage = nil
expect(p.yearlyWeeklyEquivalent == nil && p.annualBillingPrice == nil, "Unavailable annual product cannot produce a weekly quote")

print("Passed \(checks) subscription pricing and trial-copy checks.")
'''.replace("__PROPERTIES__", properties)

with tempfile.TemporaryDirectory(prefix="nanobeasts-pricing-check-") as folder:
    path = Path(folder) / "main.swift"
    path.write_text(harness)
    subprocess.run(["swift", "-module-cache-path", str(Path(folder) / "ModuleCache"), str(path)], check=True, cwd=root)
