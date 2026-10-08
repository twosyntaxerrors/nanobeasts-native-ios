import Foundation
import RevenueCat

/// Deterministic preview. These products must never reach purchase(package:).
@MainActor
enum PaywallPreviewOffering {
    static func make(isWinback: Bool = false) -> Offering {
        let identifier = isWinback ? AppStore.lifetimeWinbackOfferingID : AppStore.lifetimeOfferingID
        let product = TestStoreProduct(
            localizedTitle: "Nanobeasts Pro Lifetime",
            price: Decimal(string: isWinback ? "19.99" : "29.99")!,
            currencyCode: "USD", localizedPriceString: isWinback ? "$19.99" : "$29.99",
            productIdentifier: isWinback ? AppStore.premiumLifetimeWinbackProductID : AppStore.premiumLifetimeProductID,
            productType: .nonConsumable, localizedDescription: "Lifetime access preview",
            locale: Locale(identifier: "en_US")
        ).toStoreProduct()
        let monthly = TestStoreProduct(
            localizedTitle: "Nanobeasts Pro Monthly", price: Decimal(string: "4.99")!,
            currencyCode: "USD", localizedPriceString: "$4.99",
            productIdentifier: AppStore.premiumMonthlyProductID, productType: .autoRenewableSubscription,
            localizedDescription: "Monthly access preview", subscriptionPeriod: .init(value: 1, unit: .month),
            locale: Locale(identifier: "en_US")
        ).toStoreProduct()
        let packages = [
            Package(identifier: "$rc_lifetime", packageType: .lifetime, storeProduct: product,
                    offeringIdentifier: identifier, webCheckoutUrl: nil)
        ] + (isWinback ? [] : [
            Package(identifier: "$rc_monthly", packageType: .monthly, storeProduct: monthly,
                    offeringIdentifier: identifier, webCheckoutUrl: nil)
        ])
        return Offering(
            identifier: identifier, serverDescription: "Onboarding preview",
            availablePackages: packages, webCheckoutUrl: nil
        )
    }
}
