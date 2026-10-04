import HealthKit
import SwiftUI

struct WatchWorkoutView: View {
    @Environment(\.watchAccent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var recorder = WatchWorkoutRecorder.shared
    @StateObject private var dailyActivity = WatchDailyActivityStore()
    @AppStorage("recordGPSRoute") private var recordsRoute = true
    @State private var confirmsFinish = false
    @State private var entitlementCheckDate = Date()
    @State private var page = WorkoutPage.metrics
    @State private var homePage = 0
    @State private var navigationPath: [Destination] = []

    private enum WorkoutPage { case controls, metrics, effort, route }
    private enum Destination: Hashable { case workouts }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let state = recorder.snapshot {
                    if state.phase == .saving {
                        ProgressView("Saving workout")
                    } else if state.isActive {
                        TabView(selection: $page) {
                            controls(state).tag(WorkoutPage.controls)
                            WatchWorkoutMetricsView(state: state, companionImage: recorder.companionImage,
                                                    companionName: recorder.companionArtwork?.name,
                                                    evolution: recorder.companionArtwork?.evolution)
                                .tag(WorkoutPage.metrics)
                            WatchWorkoutMetricsView(state: state, showsEffort: true).tag(WorkoutPage.effort)
                            routeStatus(state).tag(WorkoutPage.route)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .automatic))
                    } else {
                        summary(state)
                    }
                } else if recorder.isStarting {
                    countdown
                } else if recorder.subscriptionAccess?.allowsAccess(at: entitlementCheckDate) != true {
                    ScrollView {
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(accent)
                            Text("Your adventure starts on iPhone").font(.headline)
                            Text("Open Nanobeasts on your iPhone to start or restore Pro. Your saved journey stays here.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Check again") { recorder.refreshCompanion() }
                        }.multilineTextAlignment(.center).padding(.horizontal, 10)
                    }
                } else {
                    home
                }
            }
            .navigationTitle(recorder.snapshot?.phase == .paused
                ? (recorder.snapshot?.automaticallyPaused == true ? "Auto-paused" : "Paused")
                : recorder.snapshot == nil && !recorder.isStarting ? "" : "Nanobeasts")
            .toolbarTitleDisplayMode(.inline)
            .tint(accent)
            .overlay {
                if let milestone = recorder.milestone, recorder.snapshot?.isActive == true {
                    WatchMilestoneView(milestone: milestone, image: recorder.companionImage) {
                        recorder.dismissMilestone()
                    }.id(milestone.id)
                }
            }
            .navigationDestination(for: Destination.self) { _ in
                workoutPicker.navigationTitle("Workouts")
            }
            .onChange(of: recorder.snapshot?.id) { _, _ in
                page = .metrics
                navigationPath.removeAll()
            }
            .onChange(of: recorder.isStarting) { _, starting in
                if starting { navigationPath.removeAll() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    entitlementCheckDate = Date()
                    recorder.refreshCompanion()
                    recorder.retryPendingTransfers()
                    recorder.restoreLocationForActiveWorkout()
                }
            }
            .task { recorder.refreshCompanion() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { entitlementCheckDate = $0 }
            .onChange(of: recorder.subscriptionAccess) { _, access in
                if access?.allowsAccess(at: Date()) != true { navigationPath.removeAll() }
            }
            .onChange(of: recorder.snapshot?.phase) { _, phase in
                if phase == .running { page = .metrics }
            }
            .confirmationDialog("Finish this workout?", isPresented: $confirmsFinish) {
                Button("Finish and Save") { recorder.finish() }
                Button("Keep Going", role: .cancel) {}
            }
        }
    }

    private var home: some View {
        TabView(selection: $homePage) {
            WatchHomeView(activity: dailyActivity.snapshot?.isCurrent(at: Date()) == true ? dailyActivity.snapshot : nil,
            image: recorder.companionImage, creatureName: recorder.companionArtwork?.name,
            dailyGoal: recorder.companionArtwork?.dailyStepGoal,
            animationFrames: recorder.companionAnimationFrames, isLoading: dailyActivity.isLoading,
            notice: recorder.startError ?? dailyActivity.notice,
            startWalk: { Task { await recorder.start(activity: .walking, indoor: false) } },
            moreWorkouts: { homePage = 1 }).tag(0)
            workoutPicker.tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            recorder.refreshCompanion()
            await dailyActivity.run()
        }
    }

    private var workoutPicker: some View {
        ScrollView {
            VStack(spacing: 10) {
                startButton("Strolling", symbol: "figure.walk", activity: .walking, indoor: false)
                startButton("Outdoor Walk", symbol: "figure.walk", activity: .walking, indoor: false)
                startButton("Outdoor Run", symbol: "figure.run", activity: .running, indoor: false)
                startButton("Hike", symbol: "figure.hiking", activity: .hiking, indoor: false)
                startButton("Indoor Walk", symbol: "figure.walk", activity: .walking, indoor: true)
                startButton("Indoor Run", symbol: "figure.run", activity: .running, indoor: true)
                NavigationLink {
                    WatchWorkoutSettingsView(recorder: recorder)
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                if let error = recorder.startError { Text(error).font(.footnote).foregroundStyle(.orange) }
            }
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .padding(.top, -18)
        .toolbar(.hidden, for: .navigationBar)
        .task { recorder.refreshCompanion() }
    }

    private func startButton(_ title: String, symbol: String, activity: HKWorkoutActivityType, indoor: Bool) -> some View {
        WatchWorkoutStartButton(title: title, symbol: symbol) {
            Task { await recorder.start(activity: activity, indoor: indoor, displayName: title) }
        }
    }

    private var countdown: some View {
        VStack(spacing: 10) {
            if let remaining = recorder.countdown {
                ZStack {
                    Circle().stroke(accent.opacity(0.15), lineWidth: 7)
                    Circle().trim(from: 0, to: CGFloat(remaining) / 3)
                        .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(remaining)").font(.system(size: 52, weight: .medium, design: .rounded)).monospacedDigit()
                }
                .frame(width: 100, height: 100)
                .accessibilityLabel("Starting in \(remaining)")
                Text(recorder.startingWorkoutName).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Button("Cancel", role: .cancel) { recorder.cancelStart() }.font(.footnote)
            } else {
                ProgressView("Getting ready")
                Text("Allow Health and Location access when asked.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func controls(_ state: WatchWorkoutSnapshot) -> some View {
        VStack(spacing: 14) {
            Text(state.name).font(.headline).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7)
            if state.automaticallyPaused == true && state.phase == .paused {
                Text("Taking a breather. Walk to resume.").font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                control(state.phase == .paused ? "Resume" : "Pause", symbol: state.phase == .paused ? "play.fill" : "pause.fill", color: accent) {
                    recorder.pauseOrResume()
                }
                control("Finish", symbol: "stop.fill", color: .red) { confirmsFinish = true }
            }
            Button("View Stats", systemImage: "chart.bar.fill") { page = .metrics }
                .lineLimit(1).minimumScaleFactor(0.8)
                .font(.footnote).buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6).padding(.bottom, 18)
    }

    private func control(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 25, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(Capsule().fill(color.opacity(0.2))).foregroundStyle(color)
                Text(title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
        }.buttonStyle(.plain).accessibilityLabel(title)
    }

    private func routeStatus(_ state: WatchWorkoutSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(state.steps.formatted()).lineLimit(1).minimumScaleFactor(0.7).font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("STEPS").font(.caption2).foregroundStyle(.secondary)
                    if !state.indoor {
                        let fresh = recorder.lastGPSFix.map { timeline.date.timeIntervalSince($0) < 20 } ?? false
                        let title = state.routeEnabled == false ? "GPS routes off" : state.phase == .paused ? "Route paused"
                            : recorder.routeNotice != nil ? "GPS unavailable" : fresh ? "GPS connected" : "Acquiring GPS"
                        Label(title, systemImage: state.phase == .paused ? "pause.fill" : "location.fill")
                            .font(.headline).foregroundStyle(fresh ? accent : .orange)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Text(recorder.routePointCount > 1 ? "\(recorder.routePointCount.formatted()) route points recorded" : "Waiting for route points")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(state.routeEnabled == false ? "Enable GPS routes in Nano Settings for your next workout."
                             : "View and share your recorded route in iPhone History after finishing.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Label("Indoor workout", systemImage: "house.fill").foregroundStyle(accent)
                        Text("Indoor workouts track your activity without a GPS route.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if state.routeEnabled != false, let notice = recorder.routeNotice { Text(notice).font(.footnote).foregroundStyle(.orange) }
                    if let notice = recorder.motionNotice { Text(notice).font(.footnote).foregroundStyle(.orange) }
                    if let error = state.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.bottom, 20)
            }
        }
    }

    private func summary(_ state: WatchWorkoutSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(state.name).font(.headline).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7)
                if !state.hasRecordedActivity {
                    Label("Workout discarded", systemImage: "trash")
                        .font(.headline)
                    Text("No activity was recorded. Nothing was added to your history.")
                        .font(.body).foregroundStyle(.secondary)
                } else {
                summaryRow("Time", WorkoutMetricsFormat.time(state.elapsed))
                summaryRow("Distance", String(format: "%.2f mi", state.distanceMiles))
                summaryRow("Active calories", "\(Int(state.calories)) kcal")
                summaryRow("Average pace", WorkoutMetricsFormat.pace(elapsed: state.elapsed, miles: state.distanceMiles) + " /mi")
                summaryRow("Steps", state.steps.formatted())
                Label(state.healthWorkoutID == nil ? "Saved to Nano" : "Saved to Apple Health", systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(.green)
                if !state.indoor {
                    Text(recorder.routePointCount > 1 ? "Your route will sync to iPhone History." : "No GPS route was recorded.")
                        .font(.footnote).foregroundStyle(recorder.routePointCount > 1 ? Color.secondary : Color.orange)
                }
                if state.routeEnabled != false, !state.indoor, let notice = recorder.routeNotice {
                    Text(notice).font(.footnote).foregroundStyle(.orange)
                }
                if let error = state.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                }
                Button("Done") { recorder.dismissSummary() }.frame(maxWidth: .infinity)
            }.padding(.horizontal, 5)
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).lineLimit(1).minimumScaleFactor(0.8).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

/// Shared by the workout picker and simulator layout checks.
struct WatchWorkoutStartButton: View {
    @Environment(\.watchAccent) private var accent
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(.black)
                        .frame(width: 32, height: 32).background(accent, in: Circle())
                    Spacer()
                }
                Text(title).font(.system(size: 18, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(9).frame(maxWidth: .infinity, minHeight: 75)
            .background(RoundedRectangle(cornerRadius: 24).fill(WatchNanoStyle.surface))
        }.buttonStyle(.plain).accessibilityLabel("Start \(title)")
    }
}
