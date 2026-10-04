import Foundation
import RevenueCat

/// Deterministic new-customer preview. These products must never reach purchase(package:).
enum PaywallPreviewOffering {
    static func make() -> Offering {
        let trial = TestStoreProductDiscount(
            identifier: "preview.seven-day-trial",
            price: 0,
            localizedPriceString: "$0",
            paymentMode: .freeTrial,
            subscriptionPeriod: .init(value: 1, unit: .week),
            numberOfPeriods: 1,
            type: .introductory
        )
        let monthly = TestStoreProduct(
            localizedTitle: "Nanobeasts Pro Monthly",
            price: Decimal(string: "4.99")!, currencyCode: "USD", localizedPriceString: "$4.99",
            productIdentifier: "nanobeasts.preview.monthly", productType: .autoRenewableSubscription,
            localizedDescription: "Monthly preview", subscriptionPeriod: .init(value: 1, unit: .month),
            locale: Locale(identifier: "en_US")
        ).toStoreProduct()
        let yearly = TestStoreProduct(
            localizedTitle: "Nanobeasts Pro Yearly",
            price: Decimal(string: "29.99")!, currencyCode: "USD", localizedPriceString: "$29.99",
            productIdentifier: "nanobeasts.preview.yearly", productType: .autoRenewableSubscription,
            localizedDescription: "Yearly preview", subscriptionPeriod: .init(value: 1, unit: .year),
            introductoryDiscount: trial, locale: Locale(identifier: "en_US")
        ).toStoreProduct()
        return Offering(
            identifier: "nanobeasts.preview", serverDescription: "Onboarding preview",
            availablePackages: [
                Package(identifier: "$rc_monthly", packageType: .monthly, storeProduct: monthly,
                        offeringIdentifier: "nanobeasts.preview", webCheckoutUrl: nil),
                Package(identifier: "$rc_annual", packageType: .annual, storeProduct: yearly,
                        offeringIdentifier: "nanobeasts.preview", webCheckoutUrl: nil)
            ],
            webCheckoutUrl: nil
        )
    }
}
