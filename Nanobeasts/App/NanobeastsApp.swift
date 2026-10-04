import AVFoundation
import CoreLocation
import RevenueCat
import SDWebImage
import SDWebImageWebPCoder
import SwiftUI
import UIKit

private enum GoldieCapturePresentation: Identifiable {
    case workout
    case onboarding
    case workoutGuide
    case share(WorkoutSharePayload)
    case replay(WorkoutSharePayload)
    case history(WorkoutHistoryRecord)

    var id: String {
        switch self {
        case .workout: "workout"
        case .onboarding: "onboarding"
        case .workoutGuide: "workoutGuide"
        case .share: "share"
        case .replay: "replay"
        case .history: "history"
        }
    }
}

@main
struct NanobeastsApp: App {
    @UIApplicationDelegateAdaptor(WorkoutNotificationAppDelegate.self)
    private var workoutNotificationDelegate
    @State private var store = AppStore()
    @State private var goldieRootID = 0
#if targetEnvironment(simulator)
    @State private var capturesOnboarding = false
    @State private var capturesWorkoutGuide = false
    @State private var capturesOnboardingPreview = false
#endif
    @State private var goldiePresentation: GoldieCapturePresentation?

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
            rootContent
                .environment(store)
                .tint(store.interfaceAccent.color)
                .preferredColorScheme(.dark)
                .id(goldieRootID)
                .onOpenURL(perform: handleSimulatorCaptureURL)
                .fullScreenCover(item: $goldiePresentation) { presentation in
                    switch presentation {
                    case .onboarding:
                        OnboardingFlowView { _ in goldiePresentation = nil }.environment(store)
                    case .workoutGuide:
                        WorkoutView().environment(store)
                case .workout:
                    WorkoutView(simulatesTerritory: true)
                            .environment(store)
                    case let .history(workout):
                        WorkoutHistoryDetailView(workout: workout, distanceUnit: store.distanceUnit)
                            .environment(store)
                    case let .replay(payload):
                        WorkoutRouteReplayView(payload: payload, distanceUnit: store.distanceUnit)
                            .environment(store)
                    case let .share(payload):
                        WorkoutShareComposer(
                            payload: payload,
                            samplePhoto: UIImage(named: "WorkoutShareDemo")
                        )
                            .environment(store)
                    }
                }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
#if targetEnvironment(simulator)
        if capturesOnboardingPreview {
#if DEBUG
            OnboardingReplayView()
#else
            OnboardingFlowView(previewDraft: OnboardingDraft()) { _ in capturesOnboardingPreview = false }
#endif
        } else if capturesOnboarding {
            OnboardingFlowView { _ in capturesOnboarding = false }
        } else if capturesWorkoutGuide {
            WorkoutView()
        } else {
            AppRootView()
        }
#else
        AppRootView()
#endif
    }

    private func handleSimulatorCaptureURL(_ url: URL) {
#if targetEnvironment(simulator)
        guard url.scheme == "nanobeasts", url.host == "goldie" else { return }

        switch url.pathComponents.dropFirst().first {
        case "onboarding-preview":
            goldiePresentation = nil
            capturesOnboarding = false
            capturesWorkoutGuide = false
            capturesOnboardingPreview = true
            goldieRootID += 1
        case "onboarding":
            capturesOnboardingPreview = false
            goldiePresentation = nil
            var draft = OnboardingDraft()
            draft.playerName = "Ervenst"
            draft.activity = "Very Active"
            draft.currentSteps = "8,000+"
            draft.selectedGoals = ["Walk More"]
            draft.selectedBlockers = ["Walking feels boring"]
            let value = url.lastPathComponent
            draft.phase = OnboardingPhase(rawValue: value) ?? .chat
            draft.chatStep = value == "name" ? .name : .reminders
            draft.save()
            capturesWorkoutGuide = false
            capturesOnboarding = true
            goldieRootID += 1
        case "workout-guide":
            goldiePresentation = nil
            UserDefaults.standard.set(false, forKey: "nanobeasts.didCompleteWorkoutControlsTour.v2")
            UserDefaults.standard.set(Int(url.lastPathComponent) ?? 0, forKey: "nanobeasts.workout-tour-preview-step")
            capturesOnboarding = false
            capturesWorkoutGuide = true
            goldieRootID += 1
        case "scenario":
            guard
                let rawValue = url.pathComponents.dropFirst(2).first,
                AppScreenshotScenario(rawValue: rawValue) != nil
            else { return }

            goldiePresentation = nil
            UserDefaults.standard.set(
                rawValue,
                forKey: AppScreenshotScenario.goldieScenarioDefaultsKey
            )
            store = AppStore()
            goldieRootID += 1

        case "benchmark-video":
            let payload = makeGoldieWorkoutSharePayload()
            let companion = payload.companion
            Task { @MainActor in
                let resultURL = FileManager.default.temporaryDirectory.appendingPathComponent("VideoBenchmarkResult.json")
                do {
                    let data = try await R2ArtworkCache.shared.data(for: R2AssetManifest.url(for: companion.imageKey))
                    guard let artwork = UIImage(data: data) else { throw WorkoutReplayVideoError.artwork }
                    let video = try await WorkoutReplayVideoExporter.export(payload: payload, companion: companion,
                        artwork: artwork, distanceUnit: .miles, speed: 4) { _ in }
                    let result = ["video": video.path, "status": "complete"]
                    try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted).write(to: resultURL)
                } catch {
                    let result = ["status": "error", "error": error.localizedDescription]
                    try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted).write(to: resultURL)
                }
            }

        case "workout-history", "workout-history-no-route":
            goldiePresentation = nil
            let payload = makeGoldieWorkoutSharePayload()
            let workout = WorkoutHistoryRecord(
                id: UUID(), workoutID: "outdoor-walk", name: "Outdoor Walk", symbol: "figure.walk",
                startedAt: Date().addingTimeInterval(-1800), endedAt: Date(), duration: 1800,
                steps: 3200, distanceMiles: 1.5, calories: 180, indoor: false, source: .nanobeasts,
                sourceName: "Nanobeasts · Apple Watch", companion: WorkoutCompanionSnapshot(stage: payload.companion),
                discoveries: []
            )
            if url.lastPathComponent != "workout-history-no-route" {
                WorkoutHistoryDetailView.cachePreviewRoute(payload.route, for: workout.id)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                goldiePresentation = .history(workout)
            }

        case "workout-share", "workout-replay":
            goldiePresentation = nil
            UserDefaults.standard.removeObject(
                forKey: AppScreenshotScenario.goldieScenarioDefaultsKey
            )
            store = AppStore()
            goldieRootID += 1
            let payload = makeGoldieWorkoutSharePayload()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                goldiePresentation = url.lastPathComponent == "workout-replay" ? .replay(payload) : .share(payload)
            }

        case "workout":
            goldiePresentation = nil
            UserDefaults.standard.removeObject(
                forKey: AppScreenshotScenario.goldieScenarioDefaultsKey
            )
            store = AppStore()
            goldieRootID += 1
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                goldiePresentation = .workout
            }

        case "clear":
            goldiePresentation = nil
            UserDefaults.standard.removeObject(
                forKey: AppScreenshotScenario.goldieScenarioDefaultsKey
            )

        default:
            break
        }
#endif
    }

#if targetEnvironment(simulator)
    private func makeGoldieWorkoutSharePayload() -> WorkoutSharePayload {
        let allStages = store.catalog.families.flatMap(\.stages)
        let evolvedStage = allStages.first(where: { $0.stage == 2 && !$0.isEgg })
            ?? store.currentStage
        let discoveredEgg = store.catalog.families
            .dropFirst()
            .compactMap { $0.stages.first(where: \.isEgg) }
            .first
            ?? store.currentStage

        return WorkoutSharePayload(
            workoutName: "Sunset Creature Hunt",
            workoutSymbol: "figure.run",
            elapsedSeconds: 2_864,
            steps: 6_842,
            distanceMiles: 3.74,
            calories: 418,
            isIndoor: false,
            route: [
                CLLocationCoordinate2D(latitude: 40.6940, longitude: -73.9214),
                CLLocationCoordinate2D(latitude: 40.6978, longitude: -73.9168),
                CLLocationCoordinate2D(latitude: 40.7011, longitude: -73.9196),
                CLLocationCoordinate2D(latitude: 40.7044, longitude: -73.9143),
                CLLocationCoordinate2D(latitude: 40.7082, longitude: -73.9177),
                CLLocationCoordinate2D(latitude: 40.7059, longitude: -73.9231),
                CLLocationCoordinate2D(latitude: 40.7005, longitude: -73.9256),
                CLLocationCoordinate2D(latitude: 40.6962, longitude: -73.9228),
            ],
            territoryTiles: 28,
            companion: evolvedStage,
            rewards: [
                CreatureDiscoveryEvent(stage: evolvedStage, kind: .evolution),
                CreatureDiscoveryEvent(stage: discoveredEgg, kind: .eggAcquired),
            ]
        )
    }
#endif
}
