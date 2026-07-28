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

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .info
        #endif
        Purchases.configure(withAPIKey: "appl_FwXsMJUoZPApMdDjDssGCUZKfyP")
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}
