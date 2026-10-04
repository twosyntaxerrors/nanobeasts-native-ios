import HealthKit
import SwiftUI
import WatchKit

@main
struct NanobeastsWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var appearance = WatchAppearanceStore.shared
    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG && targetEnvironment(simulator)
            if let page = WatchLayoutPreview.requestedPage {
                WatchLayoutPreview(page: page)
            } else {
                WatchWorkoutView()
            }
#else
            WatchWorkoutView()
#endif
            }
            .environment(\.watchAccent, appearance.color)
            .tint(appearance.color)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
#if DEBUG && targetEnvironment(simulator)
        if WatchLayoutPreview.requestedPage != nil { return }
#endif
        Task { @MainActor in await WatchWorkoutRecorder.shared.recover() }
    }
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WatchWorkoutRecorder.shared.start(activity: workoutConfiguration.activityType,
                indoor: workoutConfiguration.locationType == .indoor)
        }
    }
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in await WatchWorkoutRecorder.shared.recover() }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Renders the production views on Watch simulators without starting or saving a workout.
private struct WatchLayoutPreview: View {
    let page: String
    static var requestedPage: String? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--watch-preview=") }?
            .split(separator: "=", maxSplits: 1).last.map(String.init)
    }
    private static var weeklySteps: [WatchStepInterval] {
        let start = Calendar.current.startOfDay(for: Date())
        return [1400, 1400, 1600, 7800, 7200, 8500, 7404].enumerated().map { index, steps in
            let day = Calendar.current.date(byAdding: .day, value: index - 6, to: start)!
            return WatchStepInterval(start: day, end: day.addingTimeInterval(86400), steps: steps)
        }
    }
    private static var hourlySteps: [WatchStepInterval] {
        let start = Calendar.current.startOfDay(for: Date())
        return [34, 22, 0, 0, 0, 0, 0, 0, 51, 144, 3680, 1514, 42, 231, 388, 0, 0, 0, 0].enumerated().map { hour, steps in
            let date = Calendar.current.date(byAdding: .hour, value: hour, to: start)!
            return WatchStepInterval(start: date, end: date.addingTimeInterval(3600), steps: steps)
        }
    }
    @State private var homePage = 0
    private let date = Date()
    var body: some View {
        let largeValues = page == "large" || page == "long" || page == "home-large"
        let state = WatchWorkoutSnapshot(id: UUID(), workoutID: "outdoor-walk", name: "Outdoor Walk", indoor: false,
            startedAt: date, updatedAt: date, elapsed: largeValues ? 4_264 : 1_355,
            steps: page == "zero" ? 0 : page == "boundary" ? 1_000 : largeValues ? 12_345 : 2_621,
            distanceMiles: page == "zero" ? 0 : largeValues ? 3.12 : 1.08,
            calories: 126, heartRate: 112, phase: page == "paused" ? .paused : .running, heartRateMeasuredAt: date)
        let image = page == "syncing" ? nil
            : ProcessInfo.processInfo.environment["NANO_PREVIEW_ARTWORK"].flatMap { UIImage(contentsOfFile: $0) }
        NavigationStack {
            Group {
                if page == "location" {
                    WatchWorkoutSettingsView(recorder: .shared)
                } else if page.hasPrefix("home") {
                    TabView(selection: $homePage) {
                    WatchHomeView(activity: page == "home-empty" ? nil : WatchDailyActivity(day: date,
                        steps: page == "home-goal" ? 10_221 : largeValues ? 12_345 : 7_404,
                        distanceMiles: 4.1, activeCalories: 448, exerciseMinutes: 79,
                        weeklySteps: Self.weeklySteps, hourlySteps: Self.hourlySteps), image: image, creatureName: "Ampaw",
                        dailyGoal: page == "home-syncing" ? nil : 10_000,
                        startsAtHourlyActivity: page == "home-hourly",
                        notice: page == "home-empty" ? "No activity available yet. Check Nano's Health access." : nil,
                        startWalk: {}, moreWorkouts: { homePage = 1 }).tag(0)
                    ScrollView {
                        VStack(spacing: 10) {
                            WatchWorkoutStartButton(title: "Strolling", symbol: "figure.walk", action: {})
                            WatchWorkoutStartButton(title: "Outdoor Walk", symbol: "figure.walk", action: {})
                            WatchWorkoutStartButton(title: "Outdoor Run", symbol: "figure.run", action: {})
                        }
                    }.contentMargins(.top, 0, for: .scrollContent)
                        .padding(.top, -18).toolbar(.hidden, for: .navigationBar).tag(1)
                    }.tabViewStyle(.page(indexDisplayMode: .always))
                        .onAppear { if page == "home-workouts" { homePage = 1 } }
                } else if page == "milestone" {
                    WatchMilestoneView(milestone: .init(id: "steps-1", title: "1,000 steps!", detail: "Keep going!", symbol: "shoeprints.fill"),
                        image: image,
                        dismiss: {})
                } else {
                    TabView {
                        WatchWorkoutMetricsView(state: state, referenceDate: date, showsEffort: page == "effort",
                                                companionImage: image, companionName: "Ampaw")
                        WatchWorkoutMetricsView(state: state, referenceDate: date, showsEffort: page != "effort",
                                                companionImage: image, companionName: "Ampaw")
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }
            }
            .navigationTitle(page.hasPrefix("home") ? "" : page == "paused" ? "Paused" : "Nanobeasts")
            .toolbarTitleDisplayMode(.inline)
        }
        .environment(\.dynamicTypeSize, page == "large" || page == "home-large" ? .xxxLarge : .large)
    }
}
#endif
