import AVFoundation
import RevenueCat
import SDWebImage
import SDWebImageWebPCoder
import SwiftUI
import UIKit

@main
struct NanobeastsApp: App {
    @State private var store = AppStore()

    init() {
        let revenueCatAPIKey =
            Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String
        let isSupportedRevenueCatKey: Bool
#if DEBUG
        // Debug builds may use RevenueCat's non-billable Test Store. Release
        // builds intentionally reject test keys so they can never ship.
        isSupportedRevenueCatKey =
            revenueCatAPIKey?.hasPrefix("appl_") == true
            || revenueCatAPIKey?.hasPrefix("test_") == true
#else
        isSupportedRevenueCatKey = revenueCatAPIKey?.hasPrefix("appl_") == true
#endif

        if let revenueCatAPIKey, isSupportedRevenueCatKey {
#if DEBUG
            Purchases.logLevel = .debug
#else
            Purchases.logLevel = .info
#endif
            Purchases.configure(withAPIKey: revenueCatAPIKey)
        } else {
#if DEBUG
            print(
                "RevenueCat is disabled: set REVENUECAT_PUBLIC_SDK_KEY "
                    + "to the native iOS app's public SDK key."
            )
#endif
        }

        // Nanobeasts' movies are intentionally silent. Using an ambient,
        // mixable session keeps podcasts, music, and background video playing.
        try? AVAudioSession.sharedInstance().setCategory(
            .ambient,
            mode: .default,
            options: [.mixWithOthers]
        )

        if let tabFont = UIFont(name: "PressStart2P-Regular", size: 7) {
            UITabBarItem.appearance().setTitleTextAttributes(
                [.font: tabFont],
                for: .normal
            )
            UITabBarItem.appearance().setTitleTextAttributes(
                [.font: tabFont],
                for: .selected
            )
        }

        SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
        SDWebImageDownloader.shared.setValue(
            "image/webp,image/*,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}
