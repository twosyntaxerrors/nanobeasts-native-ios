import MapKit
import SwiftUI

struct WatchWorkoutPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var bridge = WorkoutWatchBridge.shared
    @StateObject private var locationTracker = WorkoutLocationTracker.shared
    @StateObject private var exploration = WorkoutExplorationProgress()
    @State private var expanded = false
    @State private var isBrowsing = false
    @StateObject private var zoneCelebrations = WorkoutZoneCelebrations.shared
    @State private var recenterID = 0
    @State private var savedWorkout: WorkoutHistoryRecord?
    var onSaved: (() -> Void)? = nil
    @State private var fallbackEvolutionAnchor: WorkoutEvolutionAnchor?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                if let state = bridge.displaySnapshot, state.isActive {
                    if !state.indoor {
                        WorkoutTerritoryMap(route: bridge.liveRoute.locations.map { $0.location.coordinate },
                            routeBreakIndices: bridge.liveRoute.breakIndices, exploredRoutes: locationTracker.exploredRoutes,
                            currentLocation: bridge.liveRoute.locations.last?.location ?? locationTracker.currentLocation,
                            showsFog: true, followsUser: true, reduceMotion: reduceMotion,
                            recenterID: recenterID,
                            companionImageKey: store.workoutCompanionStage.imageKey,
                            onBrowsingChange: { isBrowsing = $0 })
                            .ignoresSafeArea()
                            .overlay(alignment: .topTrailing) {
                                if isBrowsing { WorkoutRecenterPill { recenterID += 1 }.padding(20) }
                            }
                            .animation(.snappy, value: isBrowsing)
                            .overlay { if state.phase == .paused { Color.black.opacity(0.25).ignoresSafeArea().allowsHitTesting(false) } }
                        WorkoutNeighborhoodBadge(exploration: exploration).padding(20)
                    } else { NanoTheme.backgroundGradient.ignoresSafeArea() }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if let state = bridge.displaySnapshot { session(state) }
                            else { waitingState }
                            connectionStatus
                        }.padding(22)
                    }
                    .scrollIndicators(.hidden)
                    .background(NanoTheme.backgroundGradient.ignoresSafeArea())
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let state = bridge.displaySnapshot, state.isActive {
                    VStack(spacing: 12) {
                        if !state.indoor { WorkoutTileChip(recap: exploration.recap) }
                        ScrollView {
                            VStack(spacing: 10) {
                                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                    WorkoutFloatingStats(title: state.name,
                                        creature: store.workoutCompanionStage,
                                        evolution: store.workoutCompanionProgress.duringWorkout(steps: state.steps,
                                            anchor: state.evolutionAnchor ?? fallbackEvolutionAnchor),
                                        elapsedSeconds: state.elapsed(at: timeline.date), distance: distance(state.distanceMiles),
                                        steps: state.steps,
                                        heartRate: state.currentHeartRate(at: timeline.date).map { "\(Int($0)) bpm" } ?? "—",
                                        paused: state.phase != .running, expanded: expanded || state.indoor,
                                        expand: state.indoor ? nil : { expanded.toggle() })
                                }
                                WorkoutMilestoneAction(source: .watch).disabled(bridge.isFinishing)
                                Text(statusMessage(state)).font(.caption).foregroundStyle(NanoTheme.secondaryText)
                                if let error = state.error { Text(error).font(.caption).foregroundStyle(NanoTheme.orange) }
                                if state.phase == .saving { ProgressView("Saving on Apple Watch") }
                                connectionStatus
                            }
                        }
                        .scrollIndicators(.hidden).frame(maxHeight: expanded || state.indoor ? 400 : 300)
                        .fixedSize(horizontal: false, vertical: true)
                        if state.phase == .running || state.phase == .paused { controls(state) }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
            .navigationTitle("Apple Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if bridge.savedWorkoutID != nil { onSaved?() }
                        dismiss()
                    }.font(NanoFont.aldrich(13)).tint(NanoTheme.teal)
                }
            }
            // A Watch walk that masters a zone celebrates here once the walk has ended.
            .fullScreenCover(item: zoneCelebrations.binding(when: bridge.displaySnapshot?.isActive != true)) { completion in
                WorkoutZoneCelebrationView(completion: completion)
            }
            .navigationDestination(item: $savedWorkout) { workout in
                WorkoutHistoryDetailView(workout: workout, distanceUnit: store.distanceUnit)
            }

        }

        .task {
            locationTracker.restoreSavedTerritory(await WorkoutHistoryStore().loadSavedTerritoryRoutes())
            refreshExploration()
        }
        .onReceive(bridge.$liveRoute) { live in
            exploration.update(route: live.locations.map { $0.location.coordinate }, breaks: live.breakIndices,
                explored: locationTracker.exploredRoutes, location: live.locations.last?.location ?? locationTracker.currentLocation)
        }
        .onReceive(locationTracker.$exploredRoutes) { routes in
            exploration.update(route: bridge.liveRoute.locations.map { $0.location.coordinate }, breaks: bridge.liveRoute.breakIndices,
                explored: routes, location: bridge.liveRoute.locations.last?.location ?? locationTracker.currentLocation)
        }
        .task(id: bridge.snapshot?.id) {
            fallbackEvolutionAnchor = WorkoutEvolutionAnchor(
                totalCreditedSteps: store.workoutEvolutionProgress.totalCreditedSteps,
                workoutSteps: bridge.snapshot?.steps ?? 0)
        }
    }

    private func session(_ state: WatchWorkoutSnapshot) -> some View {
        let progress = store.workoutCompanionProgress.duringWorkout(
            steps: state.steps, anchor: state.evolutionAnchor ?? fallbackEvolutionAnchor)
        return VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                Image(systemName: "applewatch")
                Text(statusTitle(state))
                    .id(statusTitle(state))
                    .transition(.opacity)
            }
            .font(NanoFont.aldrich(11))
            .tracking(0.8)
            .foregroundStyle(state.phase == .paused ? NanoTheme.orange : NanoTheme.teal)
            .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.2), value: state.phase)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.name)
                        .font(NanoFont.aldrich(27))
                        .foregroundStyle(NanoTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(store.workoutCompanionStage.name)
                        .font(NanoFont.aldrich(12))
                        .foregroundStyle(NanoTheme.secondaryText)
                    Text(progress.caption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(NanoTheme.teal)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                WorkoutCreatureProgressView(stage: store.workoutCompanionStage, progress: progress,
                                            diameter: 88, isPlaying: state.phase == .running)
            }

            WorkoutMilestoneAction(source: .watch)
                .disabled(bridge.isFinishing)

            if bridge.savedWorkoutID == state.id {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Saved to History", systemImage: "checkmark.circle.fill")
                        .font(.headline).foregroundStyle(NanoTheme.teal)
                    Button("View workout") {
                        savedWorkout = WorkoutHistoryStore().workouts.first { $0.id == state.id }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered).tint(NanoTheme.teal)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(NanoTheme.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
            }

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(WorkoutMetricsFormat.time(state.elapsed(at: timeline.date)))
                            .font(NanoFont.spaceMono(43, bold: true))
                            .foregroundStyle(state.phase == .paused ? NanoTheme.orange : NanoTheme.teal)
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        Text("ACTIVE TIME").font(NanoFont.aldrich(10)).tracking(1.1)
                            .foregroundStyle(NanoTheme.secondaryText)
                    }
                    Rectangle().fill(NanoTheme.elevated).frame(height: 1)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 22) {
                        metric(state.steps.formatted(), "STEPS")
                        metric(distance(state.distanceMiles), "DISTANCE")
                        metric("\(Int(state.calories)) kcal", "ACTIVE ENERGY")
                        metric(state.currentHeartRate(at: timeline.date).map { "\(Int($0)) bpm" } ?? "—", "HEART RATE")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(NanoTheme.surface)
                        .stroke(NanoTheme.teal.opacity(0.25), lineWidth: 1)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                if state.phase == .saving {
                    ProgressView("Saving on Apple Watch").tint(NanoTheme.teal)
                }
                Label(routeTitle(state), systemImage: state.indoor || state.routeEnabled == false ? "location.slash" : "location.fill")
                    .font(NanoFont.aldrich(12))
                    .foregroundStyle(NanoTheme.teal)
                Text(statusMessage(state))
                    .font(NanoFont.aldrich(12))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = state.error {
                    Text(error).font(NanoFont.aldrich(12)).foregroundStyle(NanoTheme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var waitingState: some View {
        VStack(alignment: .leading, spacing: 22) {
            CreatureArtworkView(stage: store.currentStage)
                .frame(width: 120, height: 120)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text(bridge.isStarting ? "Your adventure is almost ready." : "Take Nano along.")
                .font(NanoFont.aldrich(28)).foregroundStyle(NanoTheme.text)
            if bridge.isStarting {
                ProgressView("Starting on Apple Watch").tint(NanoTheme.teal)
            }
            Text(bridge.isStarting
                 ? "Check your Watch for any Health or Location permission requests."
                 : "Open Nanobeasts on your Watch and start a walk, run, or hike. Your workout saves once and syncs here.")
                .font(NanoFont.aldrich(13)).foregroundStyle(NanoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = bridge.finishError {
                Text(message).font(.caption).foregroundStyle(NanoTheme.orange)
                Button("Retry finish") { bridge.finish() }
                    .buttonStyle(.borderedProminent).tint(NanoTheme.teal).disabled(!bridge.canFinish)
            } else if let message = bridge.connectionMessage {
                Label(message, systemImage: "applewatch.slash").font(.caption).foregroundStyle(NanoTheme.orange)
            }
        }
    }

    private func refreshExploration() {
        exploration.update(route: bridge.liveRoute.locations.map { $0.location.coordinate }, breaks: bridge.liveRoute.breakIndices,
            explored: locationTracker.exploredRoutes, location: bridge.liveRoute.locations.last?.location ?? locationTracker.currentLocation)
    }

    private func controls(_ state: WatchWorkoutSnapshot) -> some View {
        VStack(spacing: 10) {
            Button { bridge.pauseOrResume() } label: {
                Label(state.phase == .paused ? "Resume" : "Pause", systemImage: state.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(NanoTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(NanoTheme.teal, in: RoundedRectangle(cornerRadius: 20))
            }
            .disabled(!bridge.canControl)
            if state.phase == .paused {
                WorkoutHoldToFinishButton { bridge.finish() }.disabled(!bridge.canFinish)
            }
        }
        .buttonStyle(WatchPanelPressStyle())
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(NanoFont.spaceMono(18, bold: true)).foregroundStyle(NanoTheme.text)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            Text(label).font(NanoFont.aldrich(9)).tracking(0.5).foregroundStyle(NanoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func statusTitle(_ state: WatchWorkoutSnapshot) -> String {
        switch state.phase {
        case .running: "ADVENTURE IN MOTION"
        case .paused: state.automaticallyPaused == true ? "TAKING A BREATHER" : "WORKOUT PAUSED"
        case .saving: "SAVING YOUR ADVENTURE"
        case .finished: state.hasRecordedActivity ? "ADVENTURE COMPLETE" : "WORKOUT DISCARDED"
        case .failed: "WORKOUT NEEDS ATTENTION"
        }
    }

    private func routeTitle(_ state: WatchWorkoutSnapshot) -> String {
        if state.indoor { return "Indoor workout · GPS off" }
        if state.routeEnabled == false { return "GPS routes are off" }
        switch state.phase {
        case .running: return "GPS route enabled on Watch"
        case .paused: return "Route recording paused"
        case .saving: return "Saving workout and route"
        case .finished: return state.hasRecordedActivity ? "Your recorded route syncs to History" : "No activity recorded"
        case .failed: return "Check your Watch for workout details"
        }
    }

    private func statusMessage(_ state: WatchWorkoutSnapshot) -> String {
        switch state.phase {
        case .running: "Your Watch is recording. You can lower your wrist or lock your iPhone."
        case .paused: state.automaticallyPaused == true
            ? "Your Watch paused when you stopped moving. Start walking to resume automatically."
            : "Take your time. Tap Resume when you’re ready to keep going."
        case .saving: "Keep your Watch nearby while it saves. Your session will appear in History."
        case .finished: state.hasRecordedActivity ? "Your workout is saved. Tap View workout to see it in History." : "No activity was recorded, so nothing was added to your history."
        case .failed: state.hasRecordedActivity
            ? "Your recorded activity is saved to History. Check the message below for the Health sync status."
            : "Check the message below or open Nanobeasts on your Watch."
        }
    }

    private func distance(_ miles: Double) -> String {
        let value = store.distanceUnit == .miles ? miles : miles * 1.609_344
        return value.formatted(.number.precision(.fractionLength(2))) + " " + store.distanceUnit.abbreviation.lowercased()
    }
}

private struct WatchPanelPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: configuration.isPressed ? 0.1 : 0.16), value: configuration.isPressed)
    }
}
