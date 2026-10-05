import Combine
import MapKit
import SwiftUI
import UIKit

struct WorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppStore.self) private var store
    @AppStorage("nanobeasts.didCompleteWorkoutControlsTour.v2") private var didCompleteWorkoutTour = false
    @StateObject private var locationTracker: WorkoutLocationTracker
    @StateObject private var liveActivityController = WorkoutLiveActivityController()
    @StateObject private var workoutTracker = WorkoutSessionTracker.shared
    @StateObject private var historyStore = WorkoutHistoryStore()

    @State private var phase: WorkoutPreviewPhase = .setup
    @State private var hubSection: WorkoutHubSection = .start
    @State private var selectedHistoryWorkout: WorkoutHistoryRecord?
    @State private var environment: WorkoutEnvironment = .outdoor
    @State private var workout = PreviewWorkout.outdoorWalk
    @State private var goalKind: WorkoutGoalKind = .open
    @State private var showsWatchWorkout = false
    @State private var stepGoal = 1_000
    @State private var calorieGoal = 100
    @State private var durationGoal = 1_800
    @State private var distanceGoalHundredths = 100
    @State private var goalVibrationEnabled = true

    @State private var countdown = 3
    @State private var elapsedSeconds = 0
    @State private var steps = 0
    @State private var didReachGoal = false
    @State private var showsGoalBanner = false
    @State private var showsMap = true
    @State private var workoutTourStep: WorkoutTourStep?
    @State private var lastActivityCommandToken: String?
    @State private var workoutBeganAt: Date?
    @State private var workoutCompanion: CreatureStage?
    @State private var evolutionAnchor: WorkoutEvolutionAnchor?
    @State private var workoutStartingDiscoveryEventIDs: Set<UUID> = []
    @State private var workoutRewards: [CreatureDiscoveryEvent] = []
    @State private var hasEstablishedOutdoorMovement = false
    @State private var lastInactivityReminderRefresh = Date.distantPast
    @State private var showsEmptyWorkoutAlert = false
    @State private var isFinalizingWorkout = false
    @State private var workoutEndedAt: Date?
    @State private var completedRecordID: UUID?
    @State private var isAcquiringWorkoutLocation = false
    @State private var showsLocationStartAlert = false
    @State private var locationStartMessage = ""
    private let simulatesTerritory: Bool
    private let resumingSessionID: String?

    init(
        simulatesTerritory: Bool = false,
        resumingSessionID: String? = nil
    ) {
        let tracker = simulatesTerritory
            ? WorkoutLocationTracker()
            : WorkoutLocationTracker.shared
#if targetEnvironment(simulator)
        if simulatesTerritory {
            tracker.seedTerritoryDemo()
        }
#endif
        _locationTracker = StateObject(wrappedValue: tracker)
        _phase = State(initialValue: simulatesTerritory ? .active : .setup)
        _showsMap = State(initialValue: true)
        _elapsedSeconds = State(initialValue: simulatesTerritory ? 1_847 : 0)
        _steps = State(initialValue: simulatesTerritory ? 4_286 : 0)
        _workoutBeganAt = State(
            initialValue: simulatesTerritory
                ? Date().addingTimeInterval(-1_847)
                : nil
        )
        self.simulatesTerritory = simulatesTerritory
        self.resumingSessionID = resumingSessionID
    }

    private var completedHistoryRecord: WorkoutHistoryRecord? {
        guard let completedRecordID else { return nil }
        return historyStore.workouts.first { $0.id == completedRecordID }
    }

    private var distanceMiles: Double {
        if phase == .summary, let record = completedHistoryRecord { return record.distanceMiles }
        return max(workoutTracker.motionDistanceMiles, locationTracker.distanceMiles)
    }

    private var calories: Double {
        if phase == .summary, let record = completedHistoryRecord { return record.calories }
        return max(Double(steps) * workout.caloriesPerStep, distanceMiles * workout.caloriesPerMile)
    }

    private var paceMinutesPerMile: Double {
        distanceMiles > 0.005 ? (Double(elapsedSeconds) / 60) / distanceMiles : 0
    }

    private var isMeaningfulOutdoorWorkout: Bool {
        guard workout.environment == .outdoor else { return true }
        if workout.id == "cycling" {
            return distanceMiles >= 0.05
                && locationTracker.lastMeaningfulMovementAt != nil
        }
        return steps >= 20
            || (distanceMiles >= 0.03 && locationTracker.lastMeaningfulMovementAt != nil)
    }

    private var japaneseWalkingTempo: JapaneseWalkingTempo? {
        guard workout.isJapaneseWalking else { return nil }
        return JapaneseWalkingTempo.tempo(at: elapsedSeconds)
    }

    private var japaneseWalkingTempoSecondsRemaining: Int? {
        guard workout.isJapaneseWalking else { return nil }
        return JapaneseWalkingTempo.secondsRemaining(at: elapsedSeconds)
    }

    private var goalTarget: Double? {
        switch goalKind {
        case .open:
            return nil
        case .steps:
            return Double(stepGoal)
        case .calories:
            return Double(calorieGoal)
        case .duration:
            return Double(durationGoal)
        case .distance:
            return Double(distanceGoalHundredths) / 100
        }
    }

    private var goalValue: Double {
        switch goalKind {
        case .open:
            return 0
        case .steps:
            return Double(steps)
        case .calories:
            return calories
        case .duration:
            return Double(elapsedSeconds)
        case .distance:
            return distanceMiles
        }
    }

    private var goalProgress: Double {
        guard let goalTarget, goalTarget > 0 else { return 0 }
        return min(goalValue / goalTarget, 1)
    }

    private var goalDescription: String {
        switch goalKind {
        case .open:
            return "No target"
        case .steps:
            return "\(stepGoal.formatted()) Steps"
        case .calories:
            return "\(calorieGoal) kcal"
        case .duration:
            return workoutTime(durationGoal)
        case .distance:
            return String(format: "%.2f mi", Double(distanceGoalHundredths) / 100)
        }
    }

    private var liveActivityState: WorkoutActivityAttributes.ContentState {
        let evolution = store.workoutCompanionProgress.duringWorkout(steps: steps, anchor: evolutionAnchor)
        return WorkoutActivityAttributes.ContentState(
            timerAnchor: Date().addingTimeInterval(-Double(elapsedSeconds)),
            elapsedSeconds: elapsedSeconds,
            steps: steps,
            distanceMiles: distanceMiles,
            calories: Int(calories),
            goalProgress: goalKind == .open ? 0 : goalProgress,
            isPaused: phase == .paused,
            goalReached: didReachGoal,
            isComplete: phase == .summary,
            evolutionFraction: evolution.fraction,
            evolutionCaption: evolution.caption
        )
    }

    private var workoutContent: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            Group {
                switch phase {
                case .setup:
                    switch hubSection {
                    case .start:
                        WorkoutSetupScreen(
                            locationTracker: locationTracker,
                            creature: store.currentStage,
                            workout: workout,
                            goalKind: goalKind,
                            goalDescription: goalDescription,
                            liveActivityAvailable: liveActivityController.isAvailable,
                            isAcquiringLocation: isAcquiringWorkoutLocation,
                            goalVibrationEnabled: $goalVibrationEnabled,
                            chooseWorkout: { phase = .workoutPicker },
                            chooseGoal: { phase = .goalPicker },
                            showHelp: showWorkoutTour,
                            tourFocus: workoutTourStep,
                            start: startWorkout,
                            startOnWatch: startOnWatch
                        )
                    case .history:
                        WorkoutHistoryScreen(
                            historyStore: historyStore,
                            distanceUnit: store.distanceUnit,
                            selectWorkout: { selectedHistoryWorkout = $0 }
                        )
                    }
                case .workoutPicker:
                    WorkoutPickerScreen(
                        environment: $environment,
                        selection: $workout,
                        done: { phase = .setup }
                    )
                case .goalPicker:
                    WorkoutGoalScreen(
                        selection: $goalKind,
                        stepGoal: $stepGoal,
                        calorieGoal: $calorieGoal,
                        durationGoal: $durationGoal,
                        distanceGoalHundredths: $distanceGoalHundredths,
                        done: { phase = .setup }
                    )
                case .countdown:
                    WorkoutCountdownScreen(value: countdown)
                case .active, .paused:
                    WorkoutLiveScreen(
                        locationTracker: locationTracker,
                        creature: store.workoutCompanionStage,
                        evolution: store.workoutCompanionProgress.duringWorkout(steps: steps, anchor: evolutionAnchor),
                        workout: workout,
                        goalKind: goalKind,
                        goalDescription: goalDescription,
                        goalProgress: goalProgress,
                        didReachGoal: didReachGoal,
                        elapsedSeconds: elapsedSeconds,
                        steps: steps,
                        distanceMiles: distanceMiles,
                        paceMinutesPerMile: paceMinutesPerMile,
                        calories: calories,
                        japaneseWalkingTempo: japaneseWalkingTempo,
                        tempoSecondsRemaining: japaneseWalkingTempoSecondsRemaining,
                        showsMap: $showsMap,
                        isPaused: phase == .paused,
                        pause: pauseWorkout,
                        resume: resumeWorkout,
                        end: requestEndWorkout
                    )
                case .summary:
                    WorkoutSummaryScreen(
                        workout: workout,
                        goalDescription: goalDescription,
                        didReachGoal: didReachGoal,
                        elapsedSeconds: Int(completedHistoryRecord?.duration ?? Double(elapsedSeconds)),
                        steps: completedHistoryRecord?.steps ?? steps,
                        distanceMiles: distanceMiles,
                        calories: calories,
                        route: locationTracker.route,
                        routeBreakIndices: locationTracker.routeBreakIndices,
                        territoryTiles: locationTracker.clearedTerritory.count,
                        companion: workoutCompanion ?? store.currentStage,
                        rewards: workoutRewards,
                        savedToHealth: workoutTracker.savedToHealth,
                        totalsSourceLabel: completedHistoryRecord?.totalsSourceLabel ?? "Syncing Apple Health totals…",
                        saveError: workoutTracker.saveError,
                        repeatWorkout: startWorkout,
                        done: finishWorkout
                    )
                }
            }
            .allowsHitTesting(workoutTourStep == nil)
            .accessibilityHidden(workoutTourStep != nil)
            .id(phase.screenIdentity)
            .transition(reduceMotion ? .opacity : .workoutScreen)

            if showsGoalBanner {
                WorkoutGoalReachedBanner(goalDescription: goalDescription)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .offset(y: -12).combined(with: .opacity).combined(with: .scale(scale: 0.98)),
                                removal: .offset(y: -6).combined(with: .opacity)
                            )
                    )
                    .zIndex(20)
            }

            if phase == .setup {
                WorkoutHubHeader(
                    selection: $hubSection,
                    close: { dismiss() }
                )
                .allowsHitTesting(workoutTourStep == nil)
                .accessibilityHidden(workoutTourStep != nil)
                .anchorPreference(key: WorkoutTourAnchors.self, value: .bounds) { [.history: $0] }
                .frame(maxHeight: .infinity, alignment: .top)
                .zIndex(30)
            }

        }
        .disabled(isFinalizingWorkout)
        .overlay {
            if isFinalizingWorkout {
                ProgressView("Finishing workout…")
                    .padding(24)
                    .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .overlayPreferenceValue(WorkoutTourAnchors.self) { anchors in
            if let workoutTourStep {
                WorkoutControlsTour(step: workoutTourStep, anchors: anchors,
                                    next: advanceWorkoutTour, skip: completeWorkoutTour)
                    .transition(.opacity)
            }
        }
    }

    private var observedWorkoutContent: some View {
        workoutContent
        .animation(WorkoutMotion.screen(reduceMotion: reduceMotion), value: phase.screenIdentity)
        .toolbar(phase.showsTabBar ? .visible : .hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(phase.isSessionInProgress)
        .task(id: phase) {
            await runPhaseLoop()
        }
        .task {
            await restoreLiveActivitySessionIfNeeded()
            await historyStore.refreshHealthTotals()
            handlePendingInactivityResponse()
            await observeLiveActivityCommands()
        }
        .onChange(of: steps) {
            noteOutdoorMovementProgress()
        }
        .onReceive(workoutTracker.$steps) { recordedSteps in
            guard !simulatesTerritory, phase == .active || phase == .paused,
                  let workoutBeganAt else { return }
            store.creditRecordedWorkoutSteps(recordedSteps, anchor: evolutionAnchor, startedAt: workoutBeganAt)
            // Sensor deliveries also refresh ActivityKit while the screen's
            // animation/timer loop isn't advancing in the background.
            Task { @MainActor in
                guard phase == .active else { return }
                updateLiveMetrics()
            }
        }
        .onReceive(historyStore.$workouts.map { records in
            records.flatMap { [$0.id] + ($0.healthWorkoutIDs ?? []) + ($0.nanobeastsWorkoutID.map { [$0] } ?? []) }
        }.removeDuplicates()) { _ in
            Task { @MainActor in
                locationTracker.restoreSavedTerritory(await historyStore.loadSavedTerritoryRoutes())
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WorkoutHistoryRouteArchive.didChangeNotification)) { _ in
            Task { @MainActor in
                locationTracker.restoreSavedTerritory(await historyStore.loadSavedTerritoryRoutes())
            }
        }
        .onReceive(locationTracker.$distanceMiles) { _ in
            Task { @MainActor in
                guard !simulatesTerritory, phase == .active else { return }
                updateLiveMetrics()
            }
        }
        .onChange(of: locationTracker.lastMeaningfulMovementAt) {
            noteOutdoorMovementProgress()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                locationTracker.checkpointWorkout()
            }
        }
    }

    var body: some View {
        observedWorkoutContent
        .onReceive(
            NotificationCenter.default.publisher(
                for: WorkoutInactivityResponseStore.didChangeNotification
            )
        ) { _ in
            handlePendingInactivityResponse()
        }
        .onAppear {
            presentWorkoutTourIfNeeded()
            if workout.environment == .outdoor,
               locationTracker.isAuthorized,
               !simulatesTerritory {
                locationTracker.prepareForWorkout()
            }
        }
        .onChange(of: workout.environment) { _, environment in
            if environment == .outdoor, locationTracker.isAuthorized {
                locationTracker.prepareForWorkout()
            } else {
                locationTracker.stopPreparingForWorkout()
            }
        }
        .onDisappear {
            locationTracker.stopPreparingForWorkout()
        }
        .sheet(item: $selectedHistoryWorkout) { workout in
            WorkoutHistoryDetailView(
                workout: workout,
                distanceUnit: store.distanceUnit
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showsWatchWorkout) {
            WatchWorkoutPanel(onSaved: {
                historyStore.reload()
                hubSection = .history
            })
        }
        .alert("No movement recorded", isPresented: $showsEmptyWorkoutAlert) {
            Button("Discard Workout", role: .destructive, action: discardWorkout)
            Button("Keep Anyway") {
                completeWorkout(commitTerritory: false)
            }
            Button("Continue Workout", role: .cancel) {
                resumeWorkout()
            }
        } message: {
            Text(
                "This outdoor workout has fewer than 20 steps and almost no distance. "
                    + "Discard it to keep GPS drift out of your history and cleared map."
            )
        }
        .alert("Route Recording Is Not Ready", isPresented: $showsLocationStartAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(locationStartMessage)
        }
    }

    private func startWorkout() {
        guard !isAcquiringWorkoutLocation else { return }
        if WorkoutWatchBridge.shared.isActive {
            showsWatchWorkout = true
            return
        }

        guard workout.environment == .outdoor else {
            beginWorkoutStart()
            return
        }

        guard !locationTracker.hasWorkoutQualityLocation else {
            beginWorkoutStart()
            return
        }

        isAcquiringWorkoutLocation = true
        locationTracker.prepareForWorkout()

        Task { @MainActor in
            for _ in 0..<120 {
                guard phase == .setup, workout.environment == .outdoor else {
                    isAcquiringWorkoutLocation = false
                    return
                }
                if locationTracker.hasWorkoutQualityLocation {
                    isAcquiringWorkoutLocation = false
                    beginWorkoutStart()
                    return
                }
                if locationTracker.isDenied {
                    break
                }
                try? await Task.sleep(for: .milliseconds(250))
            }

            isAcquiringWorkoutLocation = false
            if locationTracker.isDenied {
                locationStartMessage = "Location access is off. Enable Location and Precise Location for Nanobeasts in iPhone Settings before starting an outdoor workout."
            } else if locationTracker.needsPreciseLocation {
                locationStartMessage = "Precise Location is off. Turn it on for Nanobeasts so the route and cleared fog match where you walk."
            } else {
                locationStartMessage = "Nanobeasts could not get an accurate GPS fix. Move to an open area, keep the app visible for a moment, and try Start Workout again."
            }
            showsLocationStartAlert = true
        }
    }

    private func startOnWatch() {
        showsWatchWorkout = true
        WorkoutWatchBridge.shared.updateCompanion(store.workoutCompanionStage, dailyGoal: store.dailyGoal, evolution: store.workoutCompanionProgress)
        Task { await WorkoutWatchBridge.shared.start(workoutID: workout.id, indoor: workout.environment == .indoor) }
    }

    private func beginWorkoutStart() {
        hubSection = .start
        locationTracker.resetWorkout()
        if workout.environment == .outdoor {
            locationTracker.prepareForWorkout()
        }
        elapsedSeconds = 0
        steps = 0
        didReachGoal = false
        showsGoalBanner = false
        showsMap = workout.environment == .outdoor
        countdown = 3
        workoutRewards = []
        workoutEndedAt = nil
        completedRecordID = nil
        workoutCompanion = store.currentStage
        workoutStartingDiscoveryEventIDs = Set(store.discoveryEvents.map(\.id))
        hasEstablishedOutdoorMovement = false
        lastInactivityReminderRefresh = .distantPast
        showsEmptyWorkoutAlert = false
        Task { @MainActor in
            await workoutTracker.requestWorkoutAuthorization()
            phase = .countdown
        }
    }

    private func presentWorkoutTourIfNeeded() {
        guard !didCompleteWorkoutTour,
              !simulatesTerritory,
              resumingSessionID == nil
        else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard phase == .setup, workoutTourStep == nil else { return }
            withAnimation(WorkoutMotion.screen(reduceMotion: reduceMotion)) {
                workoutTourStep = .map
#if targetEnvironment(simulator)
                if let preview = UserDefaults.standard.object(forKey: "nanobeasts.workout-tour-preview-step") as? Int {
                    workoutTourStep = WorkoutTourStep(rawValue: preview) ?? .map
                }
#endif
            }
        }
    }

    private func showWorkoutTour() {
        hubSection = .start
        withAnimation(WorkoutMotion.screen(reduceMotion: reduceMotion)) {
            workoutTourStep = .map
        }
    }

    private func advanceWorkoutTour() {
        guard let workoutTourStep else { return }
        guard let nextStep = workoutTourStep.next else {
            completeWorkoutTour()
            return
        }

        withAnimation(WorkoutMotion.state(reduceMotion: reduceMotion)) {
            self.workoutTourStep = nextStep
        }
    }

    private func completeWorkoutTour() {
        didCompleteWorkoutTour = true
        withAnimation(WorkoutMotion.screen(reduceMotion: reduceMotion)) {
            workoutTourStep = nil
        }
    }

    @MainActor
    private func runPhaseLoop() async {
        switch phase {
        case .countdown:
            for value in stride(from: 3, through: 1, by: -1) {
                guard phase == .countdown, !Task.isCancelled else { return }
                countdown = value
                WorkoutHaptics.countdown(enabled: store.hapticsEnabled)
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }
            guard phase == .countdown, !Task.isCancelled else { return }
            if WorkoutWatchBridge.shared.isActive {
                phase = .setup
                showsWatchWorkout = true
                return
            }
            guard scenePhase == .active else {
                phase = .setup
                return
            }
            let phoneSessionID = UUID().uuidString
            if workout.environment == .outdoor {
                locationTracker.startWorkout(sessionID: phoneSessionID,
                    maximumExpectedSpeed: workout.maximumExpectedRouteSpeed)
            }
            WorkoutWatchBridge.shared.setPhoneWorkoutActive(true)
            workoutBeganAt = Date()
            evolutionAnchor = WorkoutEvolutionAnchor(
                totalCreditedSteps: store.workoutEvolutionProgress.totalCreditedSteps)
            workoutTracker.start()
            await liveActivityController.start(
                workoutID: workout.id,
                workoutName: workout.name,
                symbolName: workout.symbol,
                indoor: workout.environment == .indoor,
                goalDescription: goalDescription,
                goalKind: goalKind.rawValue,
                goalTarget: goalTarget,
                companionID: (workoutCompanion ?? store.currentStage).id,
                companionName: (workoutCompanion ?? store.currentStage).name,
                companionStage: (workoutCompanion ?? store.currentStage).stage,
                companionImageKey: (workoutCompanion ?? store.currentStage).imageKey,
                sessionID: phoneSessionID,
                state: liveActivityState
            )
            if let sessionID = liveActivityController.sessionID, let evolutionAnchor {
                WorkoutEvolutionAnchorStore.save(evolutionAnchor, sessionID: sessionID)
            }
            phase = .active
            if let sessionID = liveActivityController.sessionID,
               workout.environment == .outdoor {
                Task {
                    await WorkoutInactivityNotifications.begin(
                        sessionID: sessionID,
                        activityPrompt: workout.inactivityPrompt,
                        after: 10 * 60
                    )
                }
            }

        case .active:
            while phase == .active, !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard phase == .active, !Task.isCancelled else { return }
                updateLiveMetrics()
            }

        default:
            break
        }
    }

    @MainActor
    private func updateLiveMetrics() {
        if simulatesTerritory {
            elapsedSeconds += 1
            return
        }
        let previousTempo = japaneseWalkingTempo
        elapsedSeconds = workoutTracker.elapsedSeconds
        steps = workoutTracker.steps

        if let previousTempo,
           let currentTempo = japaneseWalkingTempo,
           previousTempo != currentTempo {
            WorkoutHaptics.tempoChange(enabled: store.hapticsEnabled)
        }

        Task { @MainActor in
            await liveActivityController.update(liveActivityState)
        }

        guard !didReachGoal,
              let target = goalTarget,
              target > 0,
              goalValue >= target else { return }

        didReachGoal = true
        withAnimation(WorkoutMotion.celebration(reduceMotion: reduceMotion)) {
            showsGoalBanner = true
        }

        Task { @MainActor in
            await WorkoutHaptics.goalReached(
                enabled: goalVibrationEnabled && store.hapticsEnabled
            )
        }

        Task { @MainActor in
            await liveActivityController.update(liveActivityState)
        }

        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 2_400_000_000)
            } catch {
                return
            }
            withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.18)) {
                showsGoalBanner = false
            }
        }
    }

    private func pauseWorkout() {
        guard phase == .active else { return }
        phase = .paused
        workoutTracker.pause()
        locationTracker.pauseWorkout()
        WorkoutInactivityNotifications.cancel(sessionID: liveActivityController.sessionID)
        Task { @MainActor in
            await liveActivityController.update(liveActivityState)
        }
    }

    private func resumeWorkout() {
        guard phase == .paused else { return }
        phase = .active
        workoutTracker.resume()
        locationTracker.resumeWorkout()
        scheduleNextInactivityReminder()
        Task { @MainActor in
            await liveActivityController.update(liveActivityState)
        }
    }

    private func requestEndWorkout() {
        guard (phase == .active || phase == .paused), !isFinalizingWorkout else { return }
        isFinalizingWorkout = true
        workoutEndedAt = Date()
        // Freeze the interval immediately; the historical query must complete
        // before activity validation, rewards, local history or Health export.
        pauseWorkout()
        Task { @MainActor in
            await workoutTracker.finishMotion()
            defer { isFinalizingWorkout = false }
            guard phase == .paused || phase == .active else { return }
            if !simulatesTerritory { updateLiveMetrics() }
            guard WorkoutActivityPolicy.hasActivity(
                steps: simulatesTerritory ? steps : workoutTracker.steps,
                distanceMiles: distanceMiles, calories: calories
            ) else {
                discardWorkout()
                return
            }
            guard isMeaningfulOutdoorWorkout else {
                showsEmptyWorkoutAlert = true
                return
            }
            completeWorkout(commitTerritory: true)
        }
    }

    private func completeWorkout(commitTerritory: Bool) {
        guard phase == .active || phase == .paused else { return }
        guard WorkoutActivityPolicy.hasActivity(
            steps: simulatesTerritory ? steps : workoutTracker.steps,
            distanceMiles: distanceMiles, calories: calories
        ) else {
            discardWorkout()
            return
        }
        phase = .summary
        WorkoutWatchBridge.shared.setPhoneWorkoutActive(false)
        WorkoutInactivityNotifications.cancel(sessionID: liveActivityController.sessionID)
        WorkoutInactivityResponseStore.clear()
        // Keeping a short workout must still keep its recorded route, even
        // when it does not qualify for territory credit.
        let completedRoute = locationTracker.historyRouteSnapshot()
        let completedLocations = locationTracker.recordedLocations.count == completedRoute.count
            ? locationTracker.recordedLocations : []
        let completedRouteBreaks = locationTracker.routeBreakIndices
        let endedAt = workoutEndedAt ?? Date()
        if !simulatesTerritory { elapsedSeconds = workoutTracker.elapsedSeconds }
        let startedAt = workoutBeganAt
            ?? endedAt.addingTimeInterval(-TimeInterval(elapsedSeconds))
        let completedCompanion = workoutCompanion ?? store.currentStage
        if !simulatesTerritory { steps = workoutTracker.steps }
        captureWorkoutRewards()
        let completedWorkout = workout
        let completedDistance = distanceMiles
        let completedCalories = calories
        let startingDiscoveries = workoutStartingDiscoveryEventIDs
        // Save locally before clearing the recovery archive or awaiting Health
        // and ActivityKit. The user can immediately leave the summary screen.
        let recordID = historyStore.record(
            workoutID: completedWorkout.id,
            name: completedWorkout.name,
            symbol: completedWorkout.symbol,
            startedAt: startedAt,
            endedAt: endedAt,
            duration: workoutTracker.activeIntervals(endingAt: endedAt)?.reduce(0) { $0 + $1.duration }
                ?? TimeInterval(elapsedSeconds),
            steps: steps,
            distanceMiles: completedDistance,
            calories: completedCalories,
            indoor: completedWorkout.environment == .indoor,
            companion: completedCompanion,
            discoveries: workoutRewards,
            route: completedRoute,
            routeBreakIndices: completedRouteBreaks,
            activeIntervals: workoutTracker.activeIntervals(endingAt: endedAt)
        )
        completedRecordID = recordID
        locationTracker.stopWorkout(commitRoute: commitTerritory)
        workoutTracker.pause()
        let completedActivityState = liveActivityState
        let completedSession = workoutTracker.detachCompletedSession()
        Task { @MainActor in
            await liveActivityController.end(with: completedActivityState)
            await historyStore.refreshHealthTotals(for: recordID)
            let healthRecord = historyStore.workouts.first { $0.id == recordID }
            if let healthID = await workoutTracker.stopAndSave(
                session: completedSession,
                workoutID: completedWorkout.id,
                indoor: completedWorkout.environment == .indoor,
                distanceMiles: healthRecord?.distanceMiles ?? completedDistance,
                calories: healthRecord?.calories ?? completedCalories,
                historyRecordID: recordID,
                healthTotals: healthRecord?.healthTotals,
                locations: completedLocations,
                routeBreaks: completedRouteBreaks,
                finishedAt: endedAt
            ) {
                historyStore.linkHealthWorkout(healthID, to: recordID)
                await historyStore.refreshHealthTotals(for: recordID)
            }
            await store.refreshHealthData()
            let discoveries = store.discoveryEvents.filter { !startingDiscoveries.contains($0.id) }
            historyStore.updateDiscoveries(discoveries, for: recordID)
            if workoutBeganAt == startedAt { workoutRewards = discoveries }
        }
    }

    private func finishWorkout() {
        WorkoutInactivityNotifications.cancel(sessionID: liveActivityController.sessionID)
        WorkoutInactivityResponseStore.clear()
        locationTracker.stopWorkout(commitRoute: false)
        Task { @MainActor in
            await liveActivityController.endImmediately()
            await store.refreshHealthData()
            hubSection = .history
            phase = .setup
        }
    }

    private func discardWorkout() {
        WorkoutWatchBridge.shared.setPhoneWorkoutActive(false)
        WorkoutInactivityNotifications.cancel(sessionID: liveActivityController.sessionID)
        WorkoutInactivityResponseStore.clear()
        locationTracker.resetWorkout()
        workoutTracker.cancel()
        elapsedSeconds = 0
        steps = 0
        workoutRewards = []
        hasEstablishedOutdoorMovement = false
        lastInactivityReminderRefresh = .distantPast
        phase = .setup
        hubSection = .start
        Task { @MainActor in
            await liveActivityController.endImmediately()
        }
    }

    private func noteOutdoorMovementProgress() {
        guard phase == .active, workout.environment == .outdoor else { return }
        guard isMeaningfulOutdoorWorkout else { return }

        let now = Date()
        if !hasEstablishedOutdoorMovement {
            hasEstablishedOutdoorMovement = true
        } else if now.timeIntervalSince(lastInactivityReminderRefresh) < 15 {
            return
        }
        lastInactivityReminderRefresh = now
        scheduleNextInactivityReminder()
    }

    private func scheduleNextInactivityReminder() {
        guard
            phase == .active,
            workout.environment == .outdoor,
            let sessionID = liveActivityController.sessionID
        else { return }

        WorkoutInactivityNotifications.schedule(
            sessionID: sessionID,
            activityPrompt: workout.inactivityPrompt,
            after: hasEstablishedOutdoorMovement ? 5 * 60 : 10 * 60
        )
    }

    private func handlePendingInactivityResponse() {
        guard
            let response = WorkoutInactivityResponseStore.load(),
            response.sessionID == liveActivityController.sessionID
        else { return }

        WorkoutInactivityResponseStore.clear()
        if response.action == .endWorkout {
            requestEndWorkout()
        }
    }

    private func captureWorkoutRewards() {
        workoutRewards = store.discoveryEvents.filter {
            !workoutStartingDiscoveryEventIDs.contains($0.id)
        }
    }

    @MainActor
    private func restoreLiveActivitySessionIfNeeded() async {
        guard let resumingSessionID else { return }
        // A Watch Live Activity opens the mirrored workout panel. Restoring it
        // as a phone recording would start a second pedometer/GPS session.
        if resumingSessionID.hasPrefix("watch-") {
            showsWatchWorkout = true
            return
        }
        let restoredActivity = liveActivityController.restore(sessionID: resumingSessionID)
        let restoredRoute = locationTracker.resumeState(sessionID: resumingSessionID)
        guard restoredActivity != nil || restoredRoute != nil else { return }

        let restoredWorkout = restoredActivity.flatMap { restored in
            PreviewWorkout.all.first {
                $0.id == restored.attributes.workoutID
                    || ($0.name == restored.attributes.workoutName
                        && $0.symbol == restored.attributes.symbolName)
            }
        } ?? .outdoorWalk
        let isPaused = restoredActivity?.state.isPaused ?? restoredRoute?.isPaused ?? false
        let isComplete = restoredActivity?.state.isComplete ?? false
        let restoredElapsed: Int
        if let state = restoredActivity?.state {
            restoredElapsed = state.isPaused || state.isComplete
                ? state.elapsedSeconds
                : max(state.elapsedSeconds, Int(Date().timeIntervalSince(state.timerAnchor)))
        } else if let startedAt = restoredRoute?.startedAt {
            restoredElapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
        } else {
            restoredElapsed = 0
        }
        let restoredSteps = restoredActivity?.state.steps ?? 0
        let restoredDistance = max(
            restoredActivity?.state.distanceMiles ?? 0,
            restoredRoute?.distanceMiles ?? 0
        )

        workout = restoredWorkout
        environment = restoredWorkout.environment
        elapsedSeconds = max(restoredElapsed, 0)
        steps = max(restoredSteps, 0)
        // Health already includes some restored steps. Resume counting from
        // this point, rather than re-applying the session's full step count.
        evolutionAnchor = WorkoutEvolutionAnchorStore.load(sessionID: resumingSessionID)
            ?? WorkoutEvolutionAnchor(totalCreditedSteps: store.workoutEvolutionProgress.totalCreditedSteps,
                                      workoutSteps: steps)
        didReachGoal = restoredActivity?.state.goalReached ?? false
        showsGoalBanner = false
        showsMap = restoredWorkout.environment == .outdoor
        workoutBeganAt = restoredRoute?.startedAt
            ?? Date().addingTimeInterval(-Double(elapsedSeconds))
        workoutStartingDiscoveryEventIDs = Set(store.discoveryEvents.map(\.id))
        if let companionID = restoredActivity?.attributes.companionID {
            workoutCompanion = store.catalog.families
                .flatMap(\.stages)
                .first { $0.id == companionID }
                ?? store.currentStage
        } else {
            workoutCompanion = store.currentStage
        }

        if let rawGoalKind = restoredActivity?.attributes.goalKind,
           let restoredGoalKind = WorkoutGoalKind(rawValue: rawGoalKind) {
            goalKind = restoredGoalKind
            applyRestoredGoalTarget(
                restoredActivity?.attributes.goalTarget,
                kind: restoredGoalKind
            )
        }

        await workoutTracker.requestWorkoutAuthorization()
        workoutTracker.restore(
            startedAt: workoutBeganAt ?? Date(),
            steps: restoredSteps,
            distanceMiles: restoredDistance,
            isPaused: isPaused,
            elapsed: TimeInterval(restoredElapsed)
        )
        if restoredWorkout.environment == .outdoor {
            locationTracker.restoreWorkout(
                sessionID: resumingSessionID,
                isPaused: isPaused
            )
        }
        phase = isComplete ? .summary : (isPaused ? .paused : .active)
        hasEstablishedOutdoorMovement = isMeaningfulOutdoorWorkout
        lastInactivityReminderRefresh = Date()
        if phase == .active {
            scheduleNextInactivityReminder()
        }
    }

    private func applyRestoredGoalTarget(_ target: Double?, kind: WorkoutGoalKind) {
        guard let target, target > 0 else { return }
        switch kind {
        case .open:
            break
        case .steps:
            stepGoal = Int(target.rounded())
        case .calories:
            calorieGoal = Int(target.rounded())
        case .duration:
            durationGoal = max(1, Int((target / 60).rounded()))
        case .distance:
            distanceGoalHundredths = max(1, Int((target * 100).rounded()))
        }
    }

    @MainActor
    private func observeLiveActivityCommands() async {
        while !Task.isCancelled {
            if let command = WorkoutActivityCommandStore.load(),
               command.sessionID == liveActivityController.sessionID,
               command.token != lastActivityCommandToken {
                lastActivityCommandToken = command.token
                if command.isPaused, phase == .active {
                    pauseWorkout()
                } else if !command.isPaused, phase == .paused {
                    resumeWorkout()
                }
            }

            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
        }
    }
}

private enum WorkoutPreviewPhase: Hashable {
    case setup
    case workoutPicker
    case goalPicker
    case countdown
    case active
    case paused
    case summary

    var screenIdentity: String {
        switch self {
        case .active, .paused: "live"
        default: String(describing: self)
        }
    }

    var showsTabBar: Bool {
        switch self {
        case .setup, .workoutPicker, .goalPicker: true
        case .countdown, .active, .paused, .summary: false
        }
    }

    var isSessionInProgress: Bool {
        switch self {
        case .countdown, .active, .paused:
            true
        case .setup, .workoutPicker, .goalPicker, .summary:
            false
        }
    }
}

private enum WorkoutTourStep: Int, CaseIterable, Identifiable {
    case map, activity, goal, start, history
    var id: Int { rawValue }
    var next: Self? { Self(rawValue: rawValue + 1) }
    var title: String {
        switch self {
        case .map: "Walk to reveal the map"
        case .activity: "Choose your adventure"
        case .goal: "Give this walk a target"
        case .start: "Take your Nanobeast along"
        case .history: "Replay and share your route"
        }
    }
    var detail: String {
        switch self {
        case .map: "Outdoor walks clear the pink fog as you move, including walks started on Apple Watch. Tap Show map or swipe the menu handle down to watch your route. Tap the handle again to bring the menu back."
        case .activity: "Tap here to choose a walk, run, hike, or another activity. Pick indoor tracking when you don’t need a GPS route."
        case .goal: "Choose steps, time, distance, calories, or an open goal. Goal alerts can give you a haptic when you get there."
        case .start: "Choose your recording device below. Both Start on Apple Watch and Start on iPhone stay visible. Your current egg or creature comes with you while your stats update live."
        case .history: "Completed workouts live in History. Open one with a recorded route to watch your creature clear the fog, then share the replay video with your stats."
        }
    }
}

private struct WorkoutTourAnchors: PreferenceKey {
    static var defaultValue: [WorkoutTourStep: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [WorkoutTourStep: Anchor<CGRect>],
                       nextValue: () -> [WorkoutTourStep: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct WorkoutControlsTour: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isFocused: Bool
    let step: WorkoutTourStep
    let anchors: [WorkoutTourStep: Anchor<CGRect>]
    let next: () -> Void
    let skip: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let rect = anchors[step].map { geometry[$0] } ?? .zero
            let cardAtTop = rect.midY > geometry.size.height * 0.5
            ZStack {
                Color.black.opacity(0.70)
                    .mask {
                        Rectangle().overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: max(0, rect.width + 8), height: max(0, rect.height + 8))
                                .position(x: rect.midX, y: rect.midY)
                                .blendMode(.destinationOut)
                        }.compositingGroup()
                    }
                    .contentShape(Rectangle()).onTapGesture {}
                RoundedRectangle(cornerRadius: 20)
                    .stroke(NanoTheme.teal, lineWidth: 2)
                    .frame(width: max(0, rect.width + 8), height: max(0, rect.height + 8))
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)

                VStack {
                    if !cardAtTop { Spacer(minLength: 16) }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("WORKOUT FIELD TOUR · \(step.rawValue + 1)/5")
                                .font(WorkoutFont.ui(10)).foregroundStyle(NanoTheme.teal)
                            Spacer()
                            Button("Skip", action: skip).frame(minWidth: 44, minHeight: 44)
                        }
                        Text(step.title).font(.system(size: 24, weight: .bold, design: .rounded))
                            .accessibilityFocused($isFocused)
                        Text(step.detail).font(WorkoutFont.ui(12))
                            .foregroundStyle(NanoTheme.secondaryText).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                        WorkoutPrimaryButton(title: step.next == nil ? "Let’s explore" : "Next",
                                             symbol: "arrow.right", action: next)
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 26).fill(NanoTheme.surface)
                        .stroke(NanoTheme.teal.opacity(0.5), lineWidth: 1))
                    if cardAtTop { Spacer(minLength: 16) }
                }
                .padding(.horizontal, 18).padding(.vertical, 18)
            }
            .contentShape(Rectangle())
            .onAppear { isFocused = true }
            .onChange(of: step) { isFocused = true }
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, skip)
        }
        .animation(WorkoutMotion.state(reduceMotion: reduceMotion), value: step)
    }
}

private enum WorkoutMotion {
    static func screen(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .timingCurve(0.23, 1, 0.32, 1, duration: 0.24)
    }

    static func state(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .timingCurve(0.77, 0, 0.175, 1, duration: 0.22)
    }

    static func celebration(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(duration: 0.28, bounce: 0.12)
    }
}

private enum WorkoutFont {
    static func ui(_ size: CGFloat) -> Font {
        NanoFont.aldrich(size)
    }

    static func metric(_ size: CGFloat) -> Font {
        NanoFont.spaceMono(size, bold: true)
    }
}

private extension AnyTransition {
    static var workoutScreen: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)).combined(with: .scale(scale: 0.985)),
            removal: .opacity.combined(with: .offset(y: -4))
        )
    }
}

enum WorkoutEnvironment: String, CaseIterable, Identifiable {
    case outdoor = "Outdoor"
    case indoor = "Indoor"

    var id: Self { self }
}

struct PreviewWorkout: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let environment: WorkoutEnvironment
    let milesPerStep: Double
    let caloriesPerStep: Double
    let caloriesPerMile: Double
    let detail: String?

    init(
        id: String,
        name: String,
        symbol: String,
        environment: WorkoutEnvironment,
        milesPerStep: Double,
        caloriesPerStep: Double,
        caloriesPerMile: Double,
        detail: String? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.environment = environment
        self.milesPerStep = milesPerStep
        self.caloriesPerStep = caloriesPerStep
        self.caloriesPerMile = caloriesPerMile
        self.detail = detail
    }

    var isJapaneseWalking: Bool {
        id.hasPrefix("japanese-walk")
    }

    var inactivityPrompt: String {
        switch id {
        case "outdoor-run": "running"
        case "cycling": "cycling"
        case "hiking": "hiking"
        default: "walking"
        }
    }

    var maximumExpectedRouteSpeed: Double {
        switch id {
        case "cycling": 35
        case "outdoor-run": 14
        case "hiking", "nordic-walk": 8
        default: 9
        }
    }

    var baselinePaceMinutesPerMile: Double {
        switch id {
        case "outdoor-run", "indoor-run": 9.2
        case "cycling": 4.4
        case "hiking", "nordic-walk": 19.5
        case "stair-stepper", "elliptical": 14.5
        default: 17.5
        }
    }

    static let outdoor = [
        PreviewWorkout(id: "outdoor-walk", name: "Outdoor Walk", symbol: "figure.walk", environment: .outdoor, milesPerStep: 0.00045, caloriesPerStep: 0.040, caloriesPerMile: 85),
        PreviewWorkout(id: "japanese-walk-outdoor", name: "Japanese Walking", symbol: "figure.walk.motion", environment: .outdoor, milesPerStep: 0.00046, caloriesPerStep: 0.047, caloriesPerMile: 92, detail: "3 min brisk · 3 min recovery"),
        PreviewWorkout(id: "outdoor-run", name: "Outdoor Run", symbol: "figure.run", environment: .outdoor, milesPerStep: 0.00062, caloriesPerStep: 0.055, caloriesPerMile: 110),
        PreviewWorkout(id: "nordic-walk", name: "Nordic Walking", symbol: "figure.hiking", environment: .outdoor, milesPerStep: 0.00047, caloriesPerStep: 0.050, caloriesPerMile: 95),
        PreviewWorkout(id: "hiking", name: "Hiking", symbol: "figure.hiking", environment: .outdoor, milesPerStep: 0.00044, caloriesPerStep: 0.060, caloriesPerMile: 120)
    ]

    static let indoor = [
        PreviewWorkout(id: "indoor-walk", name: "Indoor Walk", symbol: "figure.walk", environment: .indoor, milesPerStep: 0.00043, caloriesPerStep: 0.038, caloriesPerMile: 85),
        PreviewWorkout(id: "japanese-walk-indoor", name: "Japanese Walking", symbol: "figure.walk.motion", environment: .indoor, milesPerStep: 0.00044, caloriesPerStep: 0.045, caloriesPerMile: 90, detail: "3 min brisk · 3 min recovery"),
        PreviewWorkout(id: "indoor-run", name: "Indoor Run", symbol: "figure.run", environment: .indoor, milesPerStep: 0.00060, caloriesPerStep: 0.052, caloriesPerMile: 110),
        PreviewWorkout(id: "hiit", name: "HIIT", symbol: "figure.highintensity.intervaltraining", environment: .indoor, milesPerStep: 0.00048, caloriesPerStep: 0.070, caloriesPerMile: 135, detail: "High-intensity interval training"),
        PreviewWorkout(id: "elliptical", name: "Elliptical", symbol: "figure.elliptical", environment: .indoor, milesPerStep: 0.00050, caloriesPerStep: 0.058, caloriesPerMile: 100),
        PreviewWorkout(id: "stair-stepper", name: "Stair Stepper", symbol: "figure.stair.stepper", environment: .indoor, milesPerStep: 0.00032, caloriesPerStep: 0.065, caloriesPerMile: 130)
    ]

    static var outdoorWalk: PreviewWorkout {
        outdoor.first { $0.id == "outdoor-walk" }!
    }

    static var all: [PreviewWorkout] {
        outdoor + indoor
    }

    static func options(for environment: WorkoutEnvironment) -> [PreviewWorkout] {
        environment == .outdoor ? outdoor : indoor
    }
}

private enum JapaneseWalkingTempo: Equatable {
    case brisk
    case recovery

    static let intervalSeconds = 3 * 60

    static func tempo(at elapsedSeconds: Int) -> Self {
        let interval = max(0, elapsedSeconds) / intervalSeconds
        return interval.isMultiple(of: 2) ? .brisk : .recovery
    }

    static func secondsRemaining(at elapsedSeconds: Int) -> Int {
        intervalSeconds - (max(0, elapsedSeconds) % intervalSeconds)
    }

    var title: String {
        switch self {
        case .brisk: "BRISK PACE"
        case .recovery: "RECOVERY PACE"
        }
    }

    var instruction: String {
        switch self {
        case .brisk: "Walk quickly with purpose"
        case .recovery: "Ease down and recover"
        }
    }

    var symbol: String {
        switch self {
        case .brisk: "hare.fill"
        case .recovery: "tortoise.fill"
        }
    }

    var tint: Color {
        switch self {
        case .brisk: NanoTheme.orange
        case .recovery: NanoTheme.teal
        }
    }
}

@MainActor
private enum WorkoutHaptics {
    static func countdown(enabled: Bool) {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 0.65)
    }

    static func tempoChange(enabled: Bool) {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 1)
    }

    static func goalReached(enabled: Bool) async {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        for pulse in 0..<3 {
            guard !Task.isCancelled else { return }
            generator.prepare()
            generator.impactOccurred(intensity: 1)
            if pulse < 2 {
                try? await Task.sleep(for: .milliseconds(360))
            }
        }
    }
}

private enum WorkoutGoalKind: String, CaseIterable, Identifiable {
    case open = "Open Goal"
    case steps = "Steps"
    case calories = "Calories"
    case duration = "Duration"
    case distance = "Distance"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .open: "scope"
        case .steps: "shoeprints.fill"
        case .calories: "flame.fill"
        case .duration: "clock.fill"
        case .distance: "arrow.right"
        }
    }
}

private struct WorkoutSetupScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var watchBridge = WorkoutWatchBridge.shared
    @State private var isMenuCollapsed = false
    @State private var recenterID = 0
    @AppStorage("nanobeasts.workouts.saveToHealth") private var saveToHealth = true
    @ObservedObject var locationTracker: WorkoutLocationTracker
    let creature: CreatureStage
    let workout: PreviewWorkout
    let goalKind: WorkoutGoalKind
    let goalDescription: String
    let liveActivityAvailable: Bool
    let isAcquiringLocation: Bool
    @Binding var goalVibrationEnabled: Bool
    let chooseWorkout: () -> Void
    let chooseGoal: () -> Void
    let showHelp: () -> Void
    let tourFocus: WorkoutTourStep?
    let start: () -> Void
    let startOnWatch: () -> Void

    private var supportsWatchWorkout: Bool {
        ["outdoor-walk", "indoor-walk", "outdoor-run", "indoor-run", "hiking", "nordic-walk",
         "japanese-walk-outdoor", "japanese-walk-indoor"].contains(workout.id)
    }

    private var recordingDeviceButtons: some View {
        VStack(spacing: 10) {
            if watchBridge.isActive {
                WorkoutPrimaryButton(title: "View Watch Workout", symbol: "applewatch", action: start)
            } else {
                if watchBridge.isPaired && supportsWatchWorkout {
                    WorkoutPrimaryButton(title: "Start on Apple Watch", symbol: "applewatch", action: startOnWatch)
                        .disabled(isAcquiringLocation)
                    Button(action: start) {
                        Label(isAcquiringLocation ? "Acquiring GPS…" : "Start on iPhone",
                              systemImage: "iphone")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .font(WorkoutFont.ui(14))
                    .foregroundStyle(NanoTheme.teal)
                    .buttonStyle(WorkoutPressButtonStyle())
                    .disabled(isAcquiringLocation)
                } else {
                    WorkoutPrimaryButton(
                        title: isAcquiringLocation ? "Acquiring GPS…" : "Start on iPhone",
                        symbol: "iphone", action: start)
                        .disabled(isAcquiringLocation)
                    if supportsWatchWorkout {
                        Button(action: startOnWatch) {
                            Label("Start on Apple Watch", systemImage: "applewatch")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .font(WorkoutFont.ui(14))
                        .foregroundStyle(NanoTheme.teal)
                        .buttonStyle(WorkoutPressButtonStyle())
                        .disabled(isAcquiringLocation)
                    }
                }
            }
        }
        .anchorPreference(key: WorkoutTourAnchors.self, value: .bounds) { [.start: $0] }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(NanoTheme.surface)
    }

    private var watchSession: WatchWorkoutSnapshot? {
        guard let state = watchBridge.displaySnapshot, state.isActive else { return nil }
        return state
    }

    private var showsLiveWatchMap: Bool {
        watchSession.map { !$0.indoor } ?? false
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                if showsLiveWatchMap {
                    WorkoutTerritoryMap(
                        route: watchBridge.liveRoute.locations.map { $0.location.coordinate },
                        routeBreakIndices: watchBridge.liveRoute.breakIndices,
                        exploredRoutes: locationTracker.exploredRoutes,
                        currentLocation: watchBridge.liveRoute.locations.last?.location ?? locationTracker.currentLocation,
                        showsFog: true,
                        followsUser: true,
                        reduceMotion: reduceMotion,
                        recenterID: recenterID,
                        companionImageKey: creature.imageKey
                    )
                    .ignoresSafeArea()
                } else {
                    WorkoutActualMap(locationTracker: locationTracker, recenterID: recenterID,
                                     showsRecenterControl: false, companionImageKey: creature.imageKey)
                        .ignoresSafeArea()
                }
                Color.clear
                    .frame(height: geometry.size.height * 0.18)
                    .anchorPreference(key: WorkoutTourAnchors.self, value: .bounds) { [.map: $0] }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        WorkoutCircleButton(symbol: "questionmark.circle.fill", action: showHelp)
                            .accessibilityLabel("Show workout walkthrough")
                        Spacer()
                        WorkoutCircleButton(
                            symbol: "location.fill",
                            action: {
                                locationTracker.requestAccess()
                                recenterID += 1
                                isMenuCollapsed = true
                            }
                        )
                        .accessibilityLabel("Zoom to my location")
                        .accessibilityHint("Centers the map on you and zooms in to nearby streets")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 70)
                    Spacer()
                }

                if isMenuCollapsed {
                    Button {
                        isMenuCollapsed = false
                    } label: {
                        Label("Workout", systemImage: "slider.horizontal.3")
                            .font(WorkoutFont.ui(12))
                            .foregroundStyle(NanoTheme.teal)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 48)
                            .background(Capsule().fill(NanoTheme.surface.opacity(0.97)))
                            .overlay(Capsule().stroke(NanoTheme.teal.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(WorkoutPressButtonStyle())
                    .accessibilityLabel("Open workout menu")
                    .padding(.trailing, 18)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                VStack(spacing: 0) {
                    menuHandle
                    ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(alignment: .center, spacing: 14) {
                                WorkoutCreatureArtwork(creature: creature)
                                    .frame(width: 78, height: 78)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("YOUR NEXT ADVENTURE")
                                        .font(WorkoutFont.ui(10))
                                        .foregroundStyle(NanoTheme.teal)
                                    Text("Let's get moving.")
                                        .font(WorkoutFont.ui(23))
                                        .foregroundStyle(.white)
                                    Text("Every step grows \(creature.name).")
                                        .font(WorkoutFont.ui(11))
                                        .foregroundStyle(NanoTheme.secondaryText)
                                }
                                Spacer(minLength: 0)
                            }

                            Button(action: chooseWorkout) {
                                HStack(spacing: 12) {
                                    Image(systemName: workout.symbol)
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundStyle(NanoTheme.teal)
                                        .frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(workout.environment.rawValue.uppercased())
                                            .font(WorkoutFont.ui(9))
                                            .foregroundStyle(NanoTheme.secondaryText)
                                        Text(workout.name)
                                            .font(WorkoutFont.ui(19))
                                            .foregroundStyle(.white)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(NanoTheme.secondaryText)
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 20).fill(NanoTheme.background.opacity(0.65)))
                            }
                            .buttonStyle(WorkoutPressButtonStyle())
                            .accessibilityHint("Choose your activity and indoor or outdoor tracking")
                            .id(WorkoutTourStep.activity)
                            .anchorPreference(key: WorkoutTourAnchors.self, value: .bounds) { [.activity: $0] }

                            Button(action: chooseGoal) {
                                HStack {
                                    WorkoutSetupOption(symbol: goalKind.symbol, eyebrow: "WORKOUT GOAL", title: goalDescription, tint: NanoTheme.teal)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(NanoTheme.secondaryText)
                                        .padding(.trailing, 14)
                                }
                                .background(RoundedRectangle(cornerRadius: 17).fill(NanoTheme.background.opacity(0.65)))
                            }
                            .buttonStyle(WorkoutPressButtonStyle())
                            .id(WorkoutTourStep.goal)
                            .anchorPreference(key: WorkoutTourAnchors.self, value: .bounds) { [.goal: $0] }

                            HStack(spacing: 6) {
                                Image(systemName: workout.environment == .indoor ? "figure.walk" : "location.fill")
                                Text(workout.environment == .indoor ? "Indoor tracking" : locationTracker.hasWorkoutQualityLocation ? "GPS ready" : "GPS connects when you start")
                                if liveActivityAvailable {
                                    Text("·")
                                    Image(systemName: "lock.iphone")
                                    Text("Lock Screen ready")
                                }
                            }
                            .font(WorkoutFont.ui(10))
                            .foregroundStyle(NanoTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                            VStack(spacing: 16) {
                                Toggle("Haptic alert at your goal", isOn: $goalVibrationEnabled)
                                Toggle("Save to Apple Health", isOn: $saveToHealth)
                            }
                            .font(WorkoutFont.ui(12))
                            .tint(NanoTheme.teal)
                            .foregroundStyle(.white)


                        }
                        .padding(20)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: tourFocus) { _, step in
                        if let step, step == .activity || step == .goal {
                            reader.scrollTo(step, anchor: .bottom)
                        }
                    }
                    }

                    recordingDeviceButtons
                }
                .frame(height: max(280, geometry.size.height * 0.74))
                .background(NanoTheme.surface.opacity(0.97))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
                        .stroke(NanoTheme.teal.opacity(0.16), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isMenuCollapsed)
            .onAppear {
                if showsLiveWatchMap, tourFocus == nil { isMenuCollapsed = true }
            }
            .task(id: watchSession?.id) {
                watchBridge.requestLiveRoute()
            }
            .onChange(of: watchBridge.isReachable) { _, reachable in
                if reachable { watchBridge.requestLiveRoute() }
            }
            .onChange(of: showsLiveWatchMap) { _, active in
                if active, tourFocus == nil { isMenuCollapsed = true }
            }
            .onChange(of: tourFocus) { _, step in
                if step != nil { isMenuCollapsed = false }
                else if showsLiveWatchMap { isMenuCollapsed = true }
            }
        }
    }

    private var menuHandle: some View {
        Button {
            isMenuCollapsed.toggle()
        } label: {
            VStack(spacing: 7) {
                Capsule().fill(NanoTheme.secondaryText.opacity(0.6))
                    .frame(width: 36, height: 4)
                HStack(spacing: 8) {
                    Image(systemName: isMenuCollapsed ? "chevron.up" : "chevron.down")
                    Text(isMenuCollapsed ? (watchSession == nil ? "Workout options" : "Watch workout") : "Show map")
                }
                .font(WorkoutFont.ui(12))
                .foregroundStyle(NanoTheme.teal)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMenuCollapsed ? "Expand workout menu" : "Collapse workout menu to show map")
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
            guard abs(value.translation.height) > abs(value.translation.width) else { return }
            isMenuCollapsed = value.translation.height > 0
        })
    }


}

private struct WorkoutFogWalkthroughVisual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealProgress: CGFloat = 0.12

    var body: some View {
        GeometryReader { proxy in
            let route = walkthroughRoute(in: proxy.size)

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.055, green: 0.09, blue: 0.13))

                WorkoutMiniMapRoads()

                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(red: 0.82, green: 0.12, blue: 0.66).opacity(0.72))
                    route
                        .trimmedPath(from: 0, to: revealProgress)
                        .stroke(
                            Color.black,
                            style: StrokeStyle(lineWidth: 64, lineCap: .round, lineJoin: .round)
                        )
                        .blendMode(.destinationOut)
                }
                .compositingGroup()

                route
                    .trimmedPath(from: 0, to: revealProgress)
                    .stroke(
                        NanoTheme.teal,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: NanoTheme.teal.opacity(0.65), radius: 7)

                VStack {
                    HStack {
                        Label("FOG", systemImage: "cloud.fog.fill")
                            .font(WorkoutFont.ui(9))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Capsule().fill(NanoTheme.pink.opacity(0.88)))
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        Label("WALK TO REVEAL", systemImage: "figure.walk")
                            .font(WorkoutFont.ui(9))
                            .foregroundStyle(NanoTheme.background)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Capsule().fill(NanoTheme.teal))
                    }
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.10), lineWidth: 1))
        }
        .frame(height: 218)
        .onAppear {
            guard !reduceMotion else {
                revealProgress = 0.86
                return
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                revealProgress = 0.88
            }
        }
    }

    private func walkthroughRoute(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: size.width * 0.13, y: size.height * 0.77))
            path.addCurve(
                to: CGPoint(x: size.width * 0.52, y: size.height * 0.50),
                control1: CGPoint(x: size.width * 0.26, y: size.height * 0.78),
                control2: CGPoint(x: size.width * 0.30, y: size.height * 0.48)
            )
            path.addCurve(
                to: CGPoint(x: size.width * 0.86, y: size.height * 0.24),
                control1: CGPoint(x: size.width * 0.70, y: size.height * 0.54),
                control2: CGPoint(x: size.width * 0.73, y: size.height * 0.25)
            )
        }
    }
}

private struct WorkoutMiniMapRoads: View {
    var body: some View {
        Canvas { context, size in
            context.opacity = 0.74
            let roadColor = Color(red: 0.25, green: 0.32, blue: 0.39)
            let minorRoadColor = Color(red: 0.17, green: 0.23, blue: 0.29)

            for index in 1...5 {
                let y = size.height * CGFloat(index) / 6
                var road = Path()
                road.move(to: CGPoint(x: 0, y: y))
                road.addLine(to: CGPoint(x: size.width, y: y - 8))
                context.stroke(road, with: .color(minorRoadColor), lineWidth: 7)
                context.stroke(road, with: .color(roadColor), lineWidth: 1)
            }

            for index in 1...4 {
                let x = size.width * CGFloat(index) / 5
                var road = Path()
                road.move(to: CGPoint(x: x, y: 0))
                road.addLine(to: CGPoint(x: x + 16, y: size.height))
                context.stroke(road, with: .color(minorRoadColor), lineWidth: 8)
                context.stroke(road, with: .color(roadColor), lineWidth: 1)
            }
        }
    }
}

private struct WorkoutSetupWalkthroughVisual: View {
    let creature: CreatureStage

    var body: some View {
        HStack(spacing: 14) {
            CreatureArtworkView(stage: creature)
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 10) {
                walkthroughRow(number: "1", title: "Walk and earn steps")
                walkthroughRow(number: "2", title: "Reach its growth target")
                walkthroughRow(number: "3", title: "Hatch or evolve")
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 174)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(NanoTheme.background.opacity(0.72))
                .stroke(NanoTheme.orange.opacity(0.30), lineWidth: 1)
        )
    }

    private func walkthroughRow(number: String, title: String) -> some View {
        HStack(spacing: 9) {
            Text(number)
                .font(WorkoutFont.metric(11))
                .foregroundStyle(NanoTheme.background)
                .frame(width: 25, height: 25)
                .background(Circle().fill(NanoTheme.orange))
            Text(title.uppercased())
                .font(WorkoutFont.ui(10))
                .foregroundStyle(.white)
        }
    }
}

private struct WorkoutControlsWalkthroughVisual: View {
    @State private var showsMap = true

    var body: some View {
        VStack(spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("00:12:48")
                        .font(WorkoutFont.metric(22))
                        .foregroundStyle(NanoTheme.teal)
                    Text("TRACKING ON LOCK SCREEN")
                        .font(WorkoutFont.ui(8))
                        .foregroundStyle(NanoTheme.secondaryText)
                }
                Spacer()
                WorkoutDisplayPicker(showsMap: $showsMap)
            }

            HStack(spacing: 10) {
                Label("MAP FIRST", systemImage: "map.fill")
                Spacer()
                Label("PAUSE ANYTIME", systemImage: "pause.fill")
            }
            .font(WorkoutFont.ui(9))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 15).fill(NanoTheme.elevated))
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 174)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(NanoTheme.background.opacity(0.72))
                .stroke(NanoTheme.cyan.opacity(0.30), lineWidth: 1)
        )
    }
}

private struct WorkoutPickerScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var environment: WorkoutEnvironment
    @Binding var selection: PreviewWorkout
    let done: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            WorkoutModalHeader(title: "Choose Workout", done: done)

            Picker("Workout environment", selection: $environment) {
                ForEach(WorkoutEnvironment.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: environment) { _, newValue in
                if !PreviewWorkout.options(for: newValue).contains(selection) {
                    selection = PreviewWorkout.options(for: newValue)[0]
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text(environment == .outdoor ? "WALKING, RUNNING & CYCLING" : "INDOOR TRAINING")
                        .font(WorkoutFont.ui(11))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .padding(.vertical, 8)

                    ForEach(PreviewWorkout.options(for: environment)) { option in
                        Button {
                            selection = option
                        } label: {
                            HStack(spacing: 15) {
                                Circle()
                                    .fill(selection == option ? NanoTheme.teal : NanoTheme.elevated)
                                    .frame(width: 12, height: 12)
                                    .shadow(color: selection == option ? NanoTheme.teal : .clear, radius: 6)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.name)
                                        .font(WorkoutFont.ui(18))
                                        .foregroundStyle(.white)
                                    if let detail = option.detail {
                                        Text(detail.uppercased())
                                            .font(WorkoutFont.ui(9))
                                            .foregroundStyle(NanoTheme.secondaryText)
                                    }
                                }
                                Spacer()
                                Image(systemName: option.symbol)
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(selection == option ? NanoTheme.background : NanoTheme.secondaryText)
                                    .frame(width: 46, height: 46)
                                    .background(
                                        Circle().fill(selection == option ? NanoTheme.teal : NanoTheme.elevated)
                                    )
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(NanoTheme.surface)
                                    .stroke(selection == option ? NanoTheme.teal : NanoTheme.elevated, lineWidth: selection == option ? 2 : 1)
                            )
                        }
                        .buttonStyle(WorkoutPressButtonStyle())
                        .accessibilityAddTraits(selection == option ? .isSelected : [])
                    }
                }
                .animation(WorkoutMotion.state(reduceMotion: reduceMotion), value: selection)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }
}

private struct WorkoutGoalScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: WorkoutGoalKind
    @Binding var stepGoal: Int
    @Binding var calorieGoal: Int
    @Binding var durationGoal: Int
    @Binding var distanceGoalHundredths: Int
    let done: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            WorkoutModalHeader(title: "Workout Goal", done: done)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    goalPreset("1,000 steps", selected: selection == .steps && stepGoal == 1_000) {
                        stepGoal = 1_000
                        selection = .steps
                    }
                    goalPreset("30 minutes", selected: selection == .duration && durationGoal == 1_800) {
                        durationGoal = 1_800
                        selection = .duration
                    }
                    goalPreset("1 mile", selected: selection == .distance && distanceGoalHundredths == 100) {
                        distanceGoalHundredths = 100
                        selection = .distance
                    }
                }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    WorkoutGoalRow(
                        kind: .open,
                        value: "No target",
                        selected: selection == .open,
                        select: { selection = .open }
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("SET A GOAL")
                            .font(WorkoutFont.ui(12))
                            .foregroundStyle(.white)
                        Text("Choose a target for this workout. Turn on goal alerts in workout setup for a haptic when you reach it.")
                            .font(WorkoutFont.ui(11))
                            .foregroundStyle(NanoTheme.secondaryText)
                    }
                    .padding(.vertical, 8)

                    WorkoutGoalRow(
                        kind: .steps,
                        value: "\(stepGoal.formatted())",
                        selected: selection == .steps,
                        decrement: { selection = .steps; decreaseStepGoal() },
                        increment: { selection = .steps; increaseStepGoal() },
                        select: { selection = .steps }
                    )

                    WorkoutGoalRow(
                        kind: .calories,
                        value: "\(calorieGoal) kcal",
                        selected: selection == .calories,
                        decrement: { selection = .calories; calorieGoal = max(25, calorieGoal - 25) },
                        increment: { selection = .calories; calorieGoal = min(5_000, calorieGoal + 25) },
                        select: { selection = .calories }
                    )

                    WorkoutGoalRow(
                        kind: .duration,
                        value: workoutTime(durationGoal),
                        selected: selection == .duration,
                        decrement: { selection = .duration; durationGoal = max(300, durationGoal - 300) },
                        increment: { selection = .duration; durationGoal = min(43_200, durationGoal + 300) },
                        select: { selection = .duration }
                    )

                    WorkoutGoalRow(
                        kind: .distance,
                        value: String(format: "%.2f mi", Double(distanceGoalHundredths) / 100),
                        selected: selection == .distance,
                        decrement: { selection = .distance; distanceGoalHundredths = max(25, distanceGoalHundredths - 25) },
                        increment: { selection = .distance; distanceGoalHundredths = min(10_000, distanceGoalHundredths + 25) },
                        select: { selection = .distance }
                    )
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private func goalPreset(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(WorkoutMotion.state(reduceMotion: reduceMotion), action)
        } label: {
            Text(title)
                .font(WorkoutFont.ui(11))
                .foregroundStyle(selected ? NanoTheme.background : NanoTheme.teal)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(selected ? NanoTheme.teal : NanoTheme.surface))
        }
        .buttonStyle(WorkoutPressButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func increaseStepGoal() {
        let increment = 100
        stepGoal = min(50_000, stepGoal + increment)
    }

    private func decreaseStepGoal() {
        let decrement = 100
        stepGoal = max(100, stepGoal - decrement)
    }
}

private struct WorkoutLiveScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var locationTracker: WorkoutLocationTracker
    let creature: CreatureStage
    let evolution: WorkoutEvolutionProgress
    let workout: PreviewWorkout
    let goalKind: WorkoutGoalKind
    let goalDescription: String
    let goalProgress: Double
    let didReachGoal: Bool
    let elapsedSeconds: Int
    let steps: Int
    let distanceMiles: Double
    let paceMinutesPerMile: Double
    let calories: Double
    let japaneseWalkingTempo: JapaneseWalkingTempo?
    let tempoSecondsRemaining: Int?
    @Binding var showsMap: Bool
    let isPaused: Bool
    let pause: () -> Void
    let resume: () -> Void
    let end: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    WorkoutCreatureProgressView(stage: creature, progress: evolution,
                                                diameter: 60, isPlaying: !isPaused)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workoutTime(elapsedSeconds))
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .font(WorkoutFont.metric(22))
                            .monospacedDigit()
                            .foregroundStyle(NanoTheme.teal)
                        Text(workout.name.uppercased())
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .font(WorkoutFont.ui(9))
                            .foregroundStyle(NanoTheme.secondaryText)
                        Text(evolution.caption)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NanoTheme.teal)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer()
                    WorkoutDisplayPicker(showsMap: $showsMap)
                        .layoutPriority(1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                WorkoutMilestoneAction(source: .phone(paused: isPaused))
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                Capsule()
                    .fill(NanoTheme.elevated)
                    .frame(width: 62, height: 5)
                    .padding(.bottom, 10)

                if let japaneseWalkingTempo, let tempoSecondsRemaining {
                    JapaneseWalkingTempoStrip(
                        tempo: japaneseWalkingTempo,
                        secondsRemaining: tempoSecondsRemaining
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                if showsMap {
                    WorkoutActualMap(
                        locationTracker: locationTracker,
                        title: "LIVE ROUTE",
                        growthLabel: creature.isEgg
                            ? "EACH STEP POWERS \(creature.name.uppercased()) TOWARD HATCHING"
                            : "EACH STEP POWERS \(creature.name.uppercased()) TOWARD EVOLUTION",
                        companionImageKey: creature.imageKey
                    )
                        .transition(.opacity)
                } else {
                    WorkoutMetricsPanel(
                        goalKind: goalKind,
                        goalDescription: goalDescription,
                        goalProgress: goalProgress,
                        didReachGoal: didReachGoal,
                        steps: steps,
                        distanceMiles: distanceMiles,
                        paceMinutesPerMile: paceMinutesPerMile,
                        calories: calories
                    )
                    .transition(.opacity)
                }

                WorkoutPrimaryButton(
                    title: "Pause",
                    symbol: "pause.fill",
                    action: pause
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            if isPaused {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()
                    .transition(.opacity)
                VStack(spacing: 18) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(NanoTheme.orange)
                        .frame(width: 68, height: 68)
                        .background(Circle().fill(NanoTheme.orange.opacity(0.12)))

                    Text("WORKOUT PAUSED")
                        .font(WorkoutFont.ui(16))
                        .foregroundStyle(.white)
                    Text("Metrics and route recording are paused.")
                        .font(WorkoutFont.ui(12))
                        .foregroundStyle(NanoTheme.secondaryText)

                    WorkoutPrimaryButton(title: "Resume", symbol: "play.fill", action: resume)

                    Button(action: end) {
                        Text("End Workout")
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .font(WorkoutFont.ui(15))
                            .foregroundStyle(NanoTheme.danger)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 17).fill(NanoTheme.danger.opacity(0.10)))
                    }
                    .buttonStyle(WorkoutPressButtonStyle())
                }
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(NanoTheme.surface)
                        .stroke(NanoTheme.elevated, lineWidth: 1)
                )
                .padding(.horizontal, 28)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: 8))
                )
            }
        }
        .animation(WorkoutMotion.state(reduceMotion: reduceMotion), value: showsMap)
        .animation(WorkoutMotion.screen(reduceMotion: reduceMotion), value: isPaused)
    }
}

private struct WorkoutMetricsPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let goalKind: WorkoutGoalKind
    let goalDescription: String
    let goalProgress: Double
    let didReachGoal: Bool
    let steps: Int
    let distanceMiles: Double
    let paceMinutesPerMile: Double
    let calories: Double

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 18) {
                    Text(goalKind == .open ? "ONE STEP AT A TIME" : "EVERY STEP COUNTS")
                        .font(WorkoutFont.ui(10))
                        .tracking(1.8)
                        .foregroundStyle(NanoTheme.teal)
                    ZStack {
                        if goalKind != .open {
                            Circle()
                                .stroke(NanoTheme.elevated, lineWidth: 7)
                            Circle()
                                .trim(from: 0, to: min(max(goalProgress, 0), 1))
                                .stroke(NanoTheme.teal, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(reduceMotion ? nil : WorkoutMotion.state(reduceMotion: false), value: goalProgress)
                        }
                        VStack(spacing: 6) {
                            Text(steps.formatted())
                                .font(WorkoutFont.metric(goalKind == .open ? 64 : 48))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                            Text("STEPS")
                                .font(WorkoutFont.ui(12))
                                .tracking(2)
                                .foregroundStyle(NanoTheme.secondaryText)
                        }
                        .padding(.horizontal, 16)
                        if didReachGoal && goalKind != .open {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundStyle(NanoTheme.teal, NanoTheme.background)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity))
                        }
                    }
                    .frame(width: 250, height: goalKind == .open ? 170 : 250)
                    .animation(WorkoutMotion.celebration(reduceMotion: reduceMotion), value: didReachGoal)

                    Label(goalKind == .open ? "Go at your own pace" : didReachGoal ? "Goal reached · keep exploring" : "Goal: \(goalDescription)", systemImage: goalKind == .open ? "infinity" : didReachGoal ? "checkmark" : goalKind.symbol)
                        .font(WorkoutFont.ui(11))
                        .foregroundStyle(didReachGoal ? NanoTheme.teal : NanoTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                HStack(spacing: 10) {
                    WorkoutMetricTile(symbol: "arrow.right", value: String(format: "%.2f", distanceMiles), unit: "MI")
                    WorkoutMetricTile(symbol: "speedometer", value: workoutPace(paceMinutesPerMile), unit: "/MI")
                    WorkoutMetricTile(symbol: "flame.fill", value: "\(Int(calories))", unit: "KCAL")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }
}

private struct JapaneseWalkingTempoStrip: View {
    let tempo: JapaneseWalkingTempo
    let secondsRemaining: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tempo.symbol)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(tempo.tint)
                .frame(width: 42, height: 42)
                .background(Circle().fill(tempo.tint.opacity(0.14)))

            VStack(alignment: .leading, spacing: 3) {
                Text(tempo.title)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .font(WorkoutFont.ui(12))
                    .foregroundStyle(.white)
                Text(tempo.instruction)
                    .font(WorkoutFont.ui(10))
                    .foregroundStyle(NanoTheme.secondaryText)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(workoutTime(secondsRemaining))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .font(WorkoutFont.metric(16))
                    .monospacedDigit()
                    .foregroundStyle(tempo.tint)
                Text("TO SWITCH")
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .font(WorkoutFont.ui(8))
                    .foregroundStyle(NanoTheme.secondaryText)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(minHeight: 62)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(NanoTheme.surface)
                .stroke(tempo.tint.opacity(0.42), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.2), value: tempo)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Japanese walking, \(tempo.title.lowercased()), switch in \(workoutTime(secondsRemaining))"
        )
    }
}

private struct WorkoutSummaryScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("nanobeasts.workouts.saveToHealth") private var saveToHealth = true
    @State private var heroVisible = false
    let workout: PreviewWorkout
    let goalDescription: String
    let didReachGoal: Bool
    let elapsedSeconds: Int
    let steps: Int
    let distanceMiles: Double
    let calories: Double
    let route: [CLLocationCoordinate2D]
    let routeBreakIndices: [Int]
    let territoryTiles: Int
    let companion: CreatureStage
    let rewards: [CreatureDiscoveryEvent]
    let savedToHealth: Bool
    let totalsSourceLabel: String
    let saveError: String?
    let repeatWorkout: () -> Void
    let done: () -> Void
    @State private var sharePayload: WorkoutSharePayload?
    @State private var replayPayload: WorkoutSharePayload?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Text("ADVENTURE COMPLETE")
                        .font(WorkoutFont.ui(11))
                        .tracking(1)
                        .foregroundStyle(NanoTheme.teal)
                    Spacer()
                    Button("Done", action: done)
                        .font(WorkoutFont.ui(14))
                        .foregroundStyle(NanoTheme.teal)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(NanoTheme.surface))
                        .buttonStyle(WorkoutPressButtonStyle())
                }

                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(NanoTheme.teal.opacity(0.07))
                            .frame(width: 170, height: 170)
                        Circle()
                            .stroke(NanoTheme.teal.opacity(0.18), lineWidth: 1)
                            .frame(width: 170, height: 170)
                        CreatureArtworkView(stage: companion)
                            .frame(width: 138, height: 138)
                    }
                    .padding(.top, 6)

                    Text(steps.formatted())
                        .font(WorkoutFont.metric(56))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text("STEPS TOGETHER")
                        .font(WorkoutFont.ui(11))
                        .tracking(2)
                        .foregroundStyle(NanoTheme.teal)
                    Text(didReachGoal ? "You reached your goal." : "A little stronger, together.")
                        .font(WorkoutFont.ui(20))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                    Text("\(workout.name) · \(goalDescription)")
                        .font(WorkoutFont.ui(11))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .opacity(heroVisible ? 1 : 0)
                .scaleEffect(heroVisible || reduceMotion ? 1 : 0.97)
                .offset(y: heroVisible || reduceMotion ? 0 : 8)

                Text(totalsSourceLabel)
                    .font(WorkoutFont.ui(11))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    WorkoutMetricTile(symbol: "clock", value: workoutTime(elapsedSeconds), unit: "TIME")
                    WorkoutMetricTile(symbol: "arrow.right", value: String(format: "%.2f", distanceMiles), unit: "MI")
                    WorkoutMetricTile(symbol: "flame", value: "\(Int(calories))", unit: "KCAL")
                }
                if territoryTiles > 0 {
                    Label("\(territoryTiles) territory tiles explored", systemImage: "map")
                        .font(WorkoutFont.ui(11))
                        .foregroundStyle(NanoTheme.secondaryText)
                }

                if workout.environment != .indoor,
                   WorkoutRouteReplayTrack(route: route, breakIndices: routeBreakIndices).canReplay {
                    WorkoutRouteReplayButton { replayPayload = makeWorkoutPayload() }
                }

                WorkoutRewardRecap(
                    companion: companion,
                    steps: steps,
                    rewards: rewards
                )

                VStack(alignment: .leading, spacing: 8) {
                    Label(savedToHealth ? "SAVED TO APPLE HEALTH" : "APPLE HEALTH", systemImage: savedToHealth ? "checkmark.circle.fill" : "heart")
                        .font(WorkoutFont.ui(11))
                        .foregroundStyle(savedToHealth ? NanoTheme.teal : NanoTheme.cyan)
                    Text(saveError ?? (savedToHealth
                        ? "Your workout is in your Health and Fitness history."
                        : saveToHealth
                            ? "Health has not confirmed a saved workout yet. You can review Health access in Settings."
                            : "Health sharing is off. You can turn it on in workout setup for your next adventure."))
                        .font(WorkoutFont.ui(11))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .nanoHUDCard(tint: NanoTheme.cyan, padding: 15)

                Button(action: repeatWorkout) {
                    Label("Do It Again", systemImage: "arrow.clockwise")
                        .font(WorkoutFont.ui(14))
                        .foregroundStyle(NanoTheme.teal)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(NanoTheme.teal.opacity(0.10))
                                .stroke(NanoTheme.teal.opacity(0.48), lineWidth: 1)
                        )
                }
                .buttonStyle(WorkoutPressButtonStyle())
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WorkoutPrimaryButton(title: "Share your workout", symbol: "square.and.arrow.up") {
                    sharePayload = makeWorkoutPayload()
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(NanoTheme.background)
        }
        .onAppear {
            withAnimation(WorkoutMotion.celebration(reduceMotion: reduceMotion)) {
                heroVisible = true
            }
        }
        .fullScreenCover(item: $replayPayload) { payload in
            WorkoutRouteReplayView(payload: payload, distanceUnit: store.distanceUnit)
        }
        .sheet(item: $sharePayload) { payload in
            WorkoutShareComposer(payload: payload)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    private func makeWorkoutPayload() -> WorkoutSharePayload {
        WorkoutSharePayload(
            workoutName: workout.name,
            workoutSymbol: workout.symbol,
            elapsedSeconds: elapsedSeconds,
            steps: steps,
            distanceMiles: distanceMiles,
            calories: calories,
            isIndoor: workout.environment == .indoor,
            route: route,
            territoryTiles: territoryTiles,
            companion: companion,
            rewards: rewards,
            routeBreakIndices: routeBreakIndices
        )
    }
}

private struct WorkoutRewardRecap: View {
    let companion: CreatureStage
    let steps: Int
    let rewards: [CreatureDiscoveryEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR COMPANION’S PROGRESS")
                    .font(WorkoutFont.ui(11))
                    .foregroundStyle(NanoTheme.orange)
                Spacer()
                Text(rewards.isEmpty ? "GROWING" : "\(rewards.count) UNLOCKED")
                    .font(WorkoutFont.ui(9))
                    .foregroundStyle(NanoTheme.secondaryText)
            }

            if rewards.isEmpty {
                HStack(spacing: 12) {
                    CreatureArtworkView(stage: companion)
                        .frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(steps.formatted()) steps grew \(companion.name)")
                            .font(WorkoutFont.ui(13))
                            .foregroundStyle(.white)
                        Text("Every step adds up. Your next adventure brings a new form closer.")
                            .font(WorkoutFont.ui(10))
                            .foregroundStyle(NanoTheme.secondaryText)
                    }
                }
            } else {
                ForEach(rewards.prefix(3)) { reward in
                    HStack(spacing: 12) {
                        CreatureArtworkView(stage: reward.creatureStage)
                            .frame(width: 54, height: 54)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(reward.kind.title)
                                .font(WorkoutFont.ui(9))
                                .foregroundStyle(NanoTheme.orange)
                            Text(reward.name)
                                .font(WorkoutFont.ui(15))
                                .foregroundStyle(.white)
                            Text("DEX ENTRY UNLOCKED")
                                .font(WorkoutFont.ui(8))
                                .foregroundStyle(NanoTheme.teal)
                        }
                        Spacer()
                        Image(systemName: reward.kind.symbol)
                            .foregroundStyle(NanoTheme.teal)
                    }
                }
            }
        }
        .nanoHUDCard(tint: NanoTheme.orange, padding: 15)
    }
}

private struct WorkoutCountdownScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Int

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("GET READY")
                .font(WorkoutFont.ui(15))
                .foregroundStyle(NanoTheme.secondaryText)
            ZStack {
                Circle()
                    .stroke(NanoTheme.teal.opacity(0.12), lineWidth: 2)
                    .frame(width: 226, height: 226)
                Circle()
                    .stroke(NanoTheme.teal.opacity(0.28), lineWidth: 1)
                    .frame(width: 184, height: 184)
                Text("\(value)")
                    .font(WorkoutFont.metric(144))
                    .monospacedDigit()
                    .foregroundStyle(NanoTheme.teal)
                    .shadow(color: NanoTheme.teal.opacity(0.5), radius: 22)
                    .id(value)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .opacity.combined(with: .scale(scale: 1.04))
                            )
                    )
            }
            .animation(WorkoutMotion.celebration(reduceMotion: reduceMotion), value: value)
            Text("Tracking begins automatically")
                .font(WorkoutFont.ui(12))
                .foregroundStyle(NanoTheme.secondaryText)
            Spacer()
        }
    }
}

private struct WorkoutGoalReachedBanner: View {
    let goalDescription: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 25, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text("GOAL REACHED")
                    .font(WorkoutFont.ui(13))
                Text(goalDescription)
                    .font(WorkoutFont.ui(12))
            }
            Spacer()
            Image(systemName: "iphone.radiowaves.left.and.right")
        }
        .foregroundStyle(NanoTheme.background)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(NanoTheme.teal))
        .shadow(color: NanoTheme.teal.opacity(0.45), radius: 18)
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 14)
    }
}

private struct WorkoutActualMap: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var locationTracker: WorkoutLocationTracker
    var title: String? = nil
    var growthLabel: String? = nil
    var recenterID: Int = 0
    var showsRecenterControl = true
    var companionImageKey: String? = nil
    @State private var localRecenterID = 0

    var body: some View {
        ZStack {
            WorkoutTerritoryMap(
                route: locationTracker.route,
                routeBreakIndices: locationTracker.routeBreakIndices,
                exploredRoutes: locationTracker.exploredRoutes,
                currentLocation: locationTracker.currentLocation,
                showsFog: true,
                followsUser: locationTracker.isTracking,
                reduceMotion: reduceMotion,
                recenterID: recenterID + localRecenterID,
                companionImageKey: companionImageKey
            )

            VStack {
                if let title {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(WorkoutFont.ui(10))
                            .foregroundStyle(NanoTheme.teal)

                        if locationTracker.isTracking || !locationTracker.clearedTerritory.isEmpty {
                            Label(
                                "\(locationTracker.clearedTerritory.count) CLEARED",
                                systemImage: "sparkles"
                            )
                            .font(WorkoutFont.ui(9))
                            .foregroundStyle(.white)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .animation(
                                reduceMotion ? nil : WorkoutMotion.state(reduceMotion: false),
                                value: locationTracker.clearedTerritory.count
                            )
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(Capsule().fill(NanoTheme.background.opacity(0.82)))
                    .overlay(Capsule().stroke(NanoTheme.teal.opacity(0.45), lineWidth: 1))
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }

                Spacer()

                if locationTracker.isTracking {
                    Text(growthLabel ?? "EVERY STEP POWERS CREATURE GROWTH")
                        .font(WorkoutFont.ui(8))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(Capsule().fill(NanoTheme.background.opacity(0.82)))
                        .overlay(Capsule().stroke(NanoTheme.orange.opacity(0.5), lineWidth: 1))
                        .padding(.bottom, 16)
                }
            }

            if locationTracker.needsPermission
                || locationTracker.isDenied
                || locationTracker.needsPreciseLocation {
                VStack(spacing: 10) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(NanoTheme.teal)
                    Text(locationPromptTitle)
                        .font(WorkoutFont.ui(14))
                        .foregroundStyle(.white)
                    Text(
                        locationPromptMessage
                    )
                    .font(WorkoutFont.ui(10))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    Button("Continue", action: continueLocationSetup)
                        .font(WorkoutFont.ui(13))
                        .foregroundStyle(NanoTheme.background)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(Capsule().fill(NanoTheme.teal))
                        .buttonStyle(WorkoutPressButtonStyle())
                        .accessibilityHint(
                            locationTracker.isDenied
                                ? "Opens Nanobeasts location settings."
                                : "Shows the iOS location permission prompt."
                        )
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 20).fill(NanoTheme.surface.opacity(0.94)))
                .padding(.horizontal, 48)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsRecenterControl {
                WorkoutCircleButton(symbol: "location.fill") {
                    locationTracker.requestAccess()
                    localRecenterID += 1
                }
                .accessibilityLabel("Zoom to my location")
                .padding(.trailing, 18)
                .padding(.top, title == nil ? 14 : 58)
            }
        }
        .animation(WorkoutMotion.state(reduceMotion: reduceMotion), value: locationTracker.needsPermission)
        .animation(WorkoutMotion.state(reduceMotion: reduceMotion), value: locationTracker.isDenied)
    }

    private func continueLocationSetup() {
        guard locationTracker.isDenied else {
            locationTracker.prepareForWorkout()
            return
        }

        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(settingsURL)
    }

    private var locationPromptTitle: String {
        if locationTracker.needsPreciseLocation { return "Precise Location Is Off" }
        return locationTracker.needsPermission ? "Enable Location" : "Location Is Off"
    }

    private var locationPromptMessage: String {
        if locationTracker.needsPreciseLocation {
            return "Turn on Precise Location so your route and cleared fog match the path you actually took."
        }
        return locationTracker.needsPermission
            ? "Use your position to clear territory as you move."
            : "Enable location for Nanobeasts in iPhone Settings."
    }
}

private struct WorkoutTerritoryMap: UIViewRepresentable {
    let route: [CLLocationCoordinate2D]
    let routeBreakIndices: [Int]
    let exploredRoutes: [[CLLocationCoordinate2D]]
    let currentLocation: CLLocation?
    let showsFog: Bool
    let followsUser: Bool
    let reduceMotion: Bool
    var recenterID: Int = 0
    var companionImageKey: String? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .includingAll

        let configuration = MKStandardMapConfiguration(elevationStyle: .realistic)
        configuration.emphasisStyle = .muted
        mapView.preferredConfiguration = configuration

        context.coordinator.install(on: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(
            route: route,
            routeBreakIndices: routeBreakIndices,
            exploredRoutes: exploredRoutes,
            currentLocation: currentLocation,
            showsFog: showsFog,
            followsUser: followsUser,
            reduceMotion: reduceMotion,
            recenterID: recenterID,
            companionImageKey: companionImageKey,
            on: mapView
        )
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        coordinator.stopAnimating()
        mapView.delegate = nil
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let territoryOverlay = WorkoutTerritoryOverlay()
        private weak var territoryRenderer: WorkoutTerritoryRenderer?
        private weak var mapView: MKMapView?
        private var targetRoute: [CLLocationCoordinate2D] = []
        private var animationStartCoordinate: CLLocationCoordinate2D?
        private var animationStartTime: CFTimeInterval = 0
        private var displayLink: CADisplayLink?
        private var hasPositionedCamera = false
        private var lastCenteredLocation: CLLocation?
        private var lastRecenterID = 0
        #if DEBUG
        private let companionExperiment = WorkoutMapCompanionExperiment()
        #endif

        func install(on mapView: MKMapView) {
            self.mapView = mapView
            mapView.addOverlay(territoryOverlay, level: .aboveLabels)
        }

        func update(
            route: [CLLocationCoordinate2D],
            routeBreakIndices: [Int],
            exploredRoutes: [[CLLocationCoordinate2D]],
            currentLocation: CLLocation?,
            showsFog: Bool,
            followsUser: Bool,
            reduceMotion: Bool,
            recenterID: Int,
            companionImageKey: String?,
            on mapView: MKMapView
        ) {
            #if DEBUG
            companionExperiment.update(on: mapView, imageKey: companionImageKey,
                                       location: currentLocation, reduceMotion: reduceMotion)
            #endif
            territoryOverlay.showsFog = showsFog
            territoryOverlay.routeBreakIndices = routeBreakIndices
            updateExploredRoutes(exploredRoutes)
            updateRoute(route, reduceMotion: reduceMotion)

            let requestedRecenter = recenterID != lastRecenterID
            let phoneLocation = mapView.userLocation.location.flatMap {
                abs($0.timestamp.timeIntervalSinceNow) < 15 ? $0 : nil
            }
            let targetLocation = requestedRecenter ? (phoneLocation ?? currentLocation) : currentLocation
            guard let currentLocation = targetLocation else {
                redrawVisibleMap()
                return
            }

            if requestedRecenter || !hasPositionedCamera {
                hasPositionedCamera = true
                lastRecenterID = recenterID
                lastCenteredLocation = currentLocation
                let region = MKCoordinateRegion(
                    center: currentLocation.coordinate,
                    latitudinalMeters: requestedRecenter ? 450 : 850,
                    longitudinalMeters: requestedRecenter ? 450 : 850
                )
                mapView.setRegion(region, animated: requestedRecenter && !reduceMotion)
            } else if followsUser,
                      lastCenteredLocation?.distance(from: currentLocation) ?? .greatestFiniteMagnitude > 8 {
                lastCenteredLocation = currentLocation
                mapView.setCenter(currentLocation.coordinate, animated: !reduceMotion)
            }

            redrawVisibleMap()
        }

        #if DEBUG
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            companionExperiment.view(for: annotation, on: mapView)
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            companionExperiment.refreshLocation(on: mapView)
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            companionExperiment.refreshNativeMarker(on: mapView)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            companionExperiment.refreshFacing(on: mapView)
        }
        #endif

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let territoryOverlay = overlay as? WorkoutTerritoryOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = WorkoutTerritoryRenderer(overlay: territoryOverlay)
            territoryRenderer = renderer
            return renderer
        }

        private func updateRoute(_ route: [CLLocationCoordinate2D], reduceMotion: Bool) {
            guard routeChanged(route) else { return }
            targetRoute = route

            guard !reduceMotion,
                  route.count > 1,
                  !territoryOverlay.routeBreakIndices.contains(route.count - 1),
                  let target = route.last
            else {
                stopAnimating()
                territoryOverlay.route = route
                redrawVisibleMap()
                return
            }

            animationStartCoordinate = territoryOverlay.route.last ?? route.dropLast().last ?? target
            animationStartTime = CACurrentMediaTime()

            if displayLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(animateRoute))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        }

        private func updateExploredRoutes(
            _ routes: [[CLLocationCoordinate2D]]
        ) {
            guard !routes.elementsEqual(territoryOverlay.exploredRoutes, by: { lhs, rhs in
                lhs.elementsEqual(rhs, by: { $0.latitude == $1.latitude && $0.longitude == $1.longitude })
            })
            else {
                return
            }

            territoryOverlay.exploredRoutes = routes
            redrawVisibleMap()
        }

        private func routeChanged(_ route: [CLLocationCoordinate2D]) -> Bool {
            guard route.count == targetRoute.count else { return true }
            guard let incoming = route.last, let existing = targetRoute.last else {
                return route.isEmpty != targetRoute.isEmpty
            }
            return abs(incoming.latitude - existing.latitude) > 0.000_000_1
                || abs(incoming.longitude - existing.longitude) > 0.000_000_1
        }

        @objc private func animateRoute(_ link: CADisplayLink) {
            guard let start = animationStartCoordinate,
                  let target = targetRoute.last
            else {
                stopAnimating()
                return
            }

            let rawProgress = min(1, max(0, (link.timestamp - animationStartTime) / 0.34))
            let progress = rawProgress * rawProgress * (3 - 2 * rawProgress)
            let interpolated = CLLocationCoordinate2D(
                latitude: start.latitude + (target.latitude - start.latitude) * progress,
                longitude: start.longitude + (target.longitude - start.longitude) * progress
            )
            territoryOverlay.route = Array(targetRoute.dropLast()) + [interpolated]
            redrawVisibleMap()

            if rawProgress >= 1 {
                territoryOverlay.route = targetRoute
                stopAnimating()
                redrawVisibleMap()
            }
        }

        fileprivate func stopAnimating() {
            displayLink?.invalidate()
            displayLink = nil
        }

        private func redrawVisibleMap() {
            guard let mapView else { return }
            territoryRenderer?.setNeedsDisplay(mapView.visibleMapRect)
        }
    }
}

#if DEBUG
/// Temporary, display-only experiment. Set this switch to false to restore the dot.
@MainActor
private final class WorkoutMapCompanionExperiment {
    static let isEnabled = true

    private enum Facing: String, CaseIterable, Sendable {
        case front = "Front", back = "Back", left = "Left", right = "Right"
    }

    private let marker = MKPointAnnotation()
    private var enabled = false
    private var installed = false
    private var reduceMotion = false
    private var suppliedLocation: CLLocation?
    private var lastLocation: CLLocation?
    private var directionAnchor: CLLocation?
    private var movement: (CLLocationCoordinate2D, CLLocationCoordinate2D)?
    private var facing = Facing.front
    private static var sprites: [Facing: UIImage] = [:]
    private static var spriteLoading: Task<[Facing: UIImage], Never>?
    private var preparationTask: Task<Void, Never>?

    private static func loadSprites() async {
        if !sprites.isEmpty { return }
        if spriteLoading == nil {
            spriteLoading = Task.detached(priority: .userInitiated) {
                Dictionary(uniqueKeysWithValues: Facing.allCases.compactMap { facing in
                    preparedSprite(named: "StratalclawMap\(facing.rawValue)").map { (facing, $0) }
                })
            }
        }
        if let spriteLoading { sprites = await spriteLoading.value }
    }

    func update(on mapView: MKMapView, imageKey: String?, location: CLLocation?, reduceMotion: Bool) {
        enabled = Self.isEnabled && imageKey?.lowercased() == "stratalclaw-stage-3-modern"

        suppliedLocation = location
        self.reduceMotion = reduceMotion
        guard enabled else {
            if installed { mapView.removeAnnotation(marker) }
            installed = false
            lastLocation = nil
            directionAnchor = nil
            movement = nil
            facing = .front
            refreshNativeMarker(on: mapView)
            return
        }
        guard Self.sprites.count == Facing.allCases.count else {
            if preparationTask == nil {
                preparationTask = Task { [weak self, weak mapView] in
                    await Self.loadSprites()
                    guard let self, let mapView else { return }
                    self.preparationTask = nil
                    self.refreshLocation(on: mapView)
                }
            }
            return
        }
        refreshLocation(on: mapView)
    }

    func refreshLocation(on mapView: MKMapView) {
        guard enabled, Self.sprites.count == Facing.allCases.count else { return }
        // Keep listening to MapKit's location even when the setup screen is idle.
        // A fresh tracker/Watch fix takes precedence; stale archives never place the sprite.
        let location = [suppliedLocation, mapView.userLocation.location].compactMap { $0 }.first {
            CLLocationCoordinate2DIsValid($0.coordinate) && $0.horizontalAccuracy >= 0
                && $0.horizontalAccuracy <= 65 && abs($0.timestamp.timeIntervalSinceNow) < 20
        }
        guard let location else { return }
        guard location.timestamp != lastLocation?.timestamp
            || location.coordinate.latitude != lastLocation?.coordinate.latitude
            || location.coordinate.longitude != lastLocation?.coordinate.longitude else {
            refreshNativeMarker(on: mapView)
            return
        }

        let distance = lastLocation.map { location.distance(from: $0) } ?? 0
        if distance > 60 { directionAnchor = nil; movement = nil }
        if let anchor = directionAnchor {
            let displacement = location.distance(from: anchor)
            let threshold = max(6, min(15, location.horizontalAccuracy * 0.5))
            // Hold facing while stopped, or while a poor GPS fix wanders around.
            if (location.speed >= 0 && location.speed < 0.35) || location.horizontalAccuracy > 25 {
                directionAnchor = location
            } else if displacement >= threshold {
                movement = (anchor.coordinate, location.coordinate)
                directionAnchor = location
            }
        } else {
            directionAnchor = location
        }

        if !installed {
            marker.coordinate = location.coordinate
            marker.title = "Stratalclaw — your location"
            installed = true
            mapView.addAnnotation(marker)
        } else if !reduceMotion && distance > 0.5 && distance < 60 {
            UIView.animate(withDuration: 0.35, delay: 0,
                           options: [.beginFromCurrentState, .curveLinear, .allowUserInteraction]) {
                self.marker.coordinate = location.coordinate
            }
        } else {
            marker.coordinate = location.coordinate
        }
        lastLocation = location
        refreshFacing(on: mapView)
        refreshNativeMarker(on: mapView)
    }

    func view(for annotation: MKAnnotation, on mapView: MKMapView) -> MKAnnotationView? {
        guard annotation === marker else { return nil }
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: "StratalclawMapExperiment")
            ?? MKAnnotationView(annotation: marker, reuseIdentifier: "StratalclawMapExperiment")
        view.annotation = marker
        view.image = Self.sprites[facing]
        view.centerOffset = CGPoint(x: 0, y: -30)
        view.canShowCallout = false
        view.displayPriority = .required
        view.zPriority = .max
        view.layer.magnificationFilter = .nearest
        view.layer.minificationFilter = .nearest
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Stratalclaw, your current location"
        return view
    }

    func refreshNativeMarker(on mapView: MKMapView) {
        mapView.view(for: mapView.userLocation)?.alpha = installed ? 0 : 1
    }

    func refreshFacing(on mapView: MKMapView) {
        guard installed, let movement else { return }
        // Screen-space movement stays correct when the map is rotated or pitched.
        let start = mapView.convert(movement.0, toPointTo: mapView)
        let end = mapView.convert(movement.1, toPointTo: mapView)
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx.isFinite, dy.isFinite, abs(dx) + abs(dy) > 0.01 else { return }
        let next: Facing
        if abs(dx) > abs(dy) * 1.15 {
            next = dx > 0 ? .right : .left
        } else if abs(dy) > abs(dx) * 1.15 {
            next = dy > 0 ? .front : .back
        } else {
            return // Hysteresis at diagonal boundaries avoids rapid frame switching.
        }
        guard next != facing else { return }
        facing = next
        mapView.view(for: marker)?.image = Self.sprites[facing]
    }

    /// Normalize generated padding at load time, preserving original concept files.
    /// Every pose has the same visible height and its feet at the location anchor.
    nonisolated private static func preparedSprite(named name: String) -> UIImage? {
        guard let source = UIImage(named: name)?.cgImage else { return nil }
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let cropped: CGImage? = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return nil }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            let rgba = bytes.bindMemory(to: UInt8.self)
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width where rgba[(y * width + x) * 4 + 3] > 32 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return context.makeImage()?.cropping(to: CGRect(x: minX, y: minY,
                width: maxX - minX + 1, height: maxY - minY + 1))
        }
        guard let cropped else { return nil }
        let size = CGSize(width: 64, height: 60)
        let scale = min(56 / CGFloat(cropped.width), 52 / CGFloat(cropped.height))
        let spriteSize = CGSize(width: CGFloat(cropped.width) * scale, height: CGFloat(cropped.height) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: cropped).draw(in: CGRect(x: (size.width - spriteSize.width) / 2,
                y: size.height - spriteSize.height, width: spriteSize.width, height: spriteSize.height))
        }
    }
}
#endif

final class WorkoutTerritoryOverlay: NSObject, MKOverlay {
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect = MKMapRect.world

    struct Snapshot {
        var route: [CLLocationCoordinate2D] = []
        var routeBreakIndices: [Int] = []
        var exploredRoutes: [[CLLocationCoordinate2D]] = []
        var showsFog = false
    }
    private let lock = NSLock()
    private var state = Snapshot()
    // MapKit can draw on background threads while a replay advances on main.
    // Each draw gets a coherent, immutable copy of the route and its gaps.
    var snapshot: Snapshot { lock.withLock { state } }
    var route: [CLLocationCoordinate2D] {
        get { snapshot.route }
        set { lock.withLock { state.route = newValue } }
    }
    var routeBreakIndices: [Int] {
        get { snapshot.routeBreakIndices }
        set { lock.withLock { state.routeBreakIndices = newValue } }
    }
    var exploredRoutes: [[CLLocationCoordinate2D]] {
        get { snapshot.exploredRoutes }
        set { lock.withLock { state.exploredRoutes = newValue } }
    }
    var showsFog: Bool {
        get { snapshot.showsFog }
        set { lock.withLock { state.showsFog = newValue } }
    }
    func updateRoute(_ route: [CLLocationCoordinate2D], breakIndices: [Int]) {
        lock.withLock {
            state.route = route
            state.routeBreakIndices = breakIndices
        }
    }
}

final class WorkoutTerritoryRenderer: MKOverlayRenderer {
    private var territoryOverlay: WorkoutTerritoryOverlay? {
        overlay as? WorkoutTerritoryOverlay
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let snapshot = territoryOverlay?.snapshot else { return }

        let drawingRect = rect(for: mapRect)
        context.saveGState()
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        if snapshot.showsFog {
            context.setBlendMode(.normal)
            context.setFillColor(
                UIColor(red: 0.64, green: 0.10, blue: 0.56, alpha: 0.62).cgColor
            )
            context.fill(drawingRect)
        }

        if snapshot.showsFog {
            let revealedRoutes = (
                snapshot.exploredRoutes + WorkoutRouteSegments.split(
                    snapshot.route, at: snapshot.routeBreakIndices
                )
            )
            drawClearedCorridors(
                revealedRoutes,
                in: context
            )
        }

        if let currentPath = currentRoutePath(snapshot) {
            // The active route remains distinct from previously explored corridors.
            context.setBlendMode(.normal)
            context.addPath(currentPath)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(
                UIColor(NanoTheme.teal).withAlphaComponent(0.82).cgColor
            )
            context.setLineWidth(4 / CGFloat(zoomScale))
            context.setShadow(
                offset: .zero,
                blur: 5 / CGFloat(zoomScale),
                color: UIColor(NanoTheme.teal).withAlphaComponent(0.45).cgColor
            )
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawClearedCorridors(
        _ routes: [[CLLocationCoordinate2D]],
        in context: CGContext
    ) {
        let corridors = routes.compactMap { route -> (path: CGPath, unitsPerMeter: Double)? in
            guard let path = routePath(for: route), !route.isEmpty else { return nil }
            return (path, MKMapPointsPerMeterAtLatitude(route[route.count / 2].latitude))
        }
        guard !corridors.isEmpty else { return }

        // Widths are ground meters, not screen points. A 12m reveal on each
        // side of a walk must not expand over unvisited blocks when zooming out.
        let featherPasses: [(width: CGFloat, alpha: CGFloat)] = [
            (40, 0.12),
            (36, 0.20),
            (32, 0.32),
            (28, 0.50),
            (24, 1.00),
        ]
        context.setBlendMode(.destinationOut)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for pass in featherPasses {
            for corridor in corridors {
                context.addPath(corridor.path)
                context.setStrokeColor(UIColor.white.withAlphaComponent(pass.alpha).cgColor)
                context.setLineWidth(pass.width * corridor.unitsPerMeter)
                context.strokePath()
            }
        }
    }

    private func currentRoutePath(_ snapshot: WorkoutTerritoryOverlay.Snapshot) -> CGPath? {
        let path = CGMutablePath()
        for segment in WorkoutRouteSegments.split(
            snapshot.route, at: snapshot.routeBreakIndices
        ) {
            if let segmentPath = routePath(for: segment) { path.addPath(segmentPath) }
        }
        return path.isEmpty ? nil : path
    }

    private func routePath(for route: [CLLocationCoordinate2D]) -> CGPath? {
        guard let first = route.first else { return nil }

        let path = CGMutablePath()
        path.move(to: point(for: MKMapPoint(first)))
        for coordinate in route.dropFirst() {
            path.addLine(to: point(for: MKMapPoint(coordinate)))
        }

        // A zero-length segment still renders a round cleared cap at workout start.
        if route.count == 1 {
            path.addLine(to: point(for: MKMapPoint(first)))
        }
        return path
    }
}

private struct WorkoutGoalRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: WorkoutGoalKind
    let value: String
    let selected: Bool
    var decrement: (() -> Void)?
    var increment: (() -> Void)?
    let select: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: select) {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(selected ? NanoTheme.teal : NanoTheme.secondaryText)
                    VStack(alignment: .leading, spacing: 5) {
                        Label(kind.rawValue.uppercased(), systemImage: kind.symbol)
                            .font(WorkoutFont.ui(10))
                            .foregroundStyle(NanoTheme.secondaryText)
                        Text(value)
                            .font(WorkoutFont.metric(19))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(WorkoutPressButtonStyle())
            .accessibilityLabel("\(kind.rawValue) goal")
            .accessibilityValue(value)
            .accessibilityAddTraits(selected ? .isSelected : [])

            if let decrement, let increment {
                HStack(spacing: 4) {
                    WorkoutGoalAdjustButton(symbol: "minus", action: decrement)
                        .accessibilityLabel("Decrease \(kind.rawValue.lowercased()) goal")
                    WorkoutGoalAdjustButton(symbol: "plus", action: increment)
                        .accessibilityLabel("Increase \(kind.rawValue.lowercased()) goal")
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(selected ? NanoTheme.teal.opacity(0.08) : NanoTheme.surface)
                .stroke(selected ? NanoTheme.teal.opacity(0.7) : NanoTheme.elevated, lineWidth: 1)
        )
        .animation(WorkoutMotion.state(reduceMotion: reduceMotion), value: selected)
    }
}

private struct WorkoutGoalAdjustButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(NanoTheme.elevated))
        }
        .buttonStyle(WorkoutPressButtonStyle())
    }
}

private struct WorkoutModalHeader: View {
    let title: String
    let done: () -> Void

    var body: some View {
        HStack {
            Text(title.uppercased())
                .lineLimit(1).minimumScaleFactor(0.8)
                .font(WorkoutFont.ui(14))
                .foregroundStyle(.white)
            Spacer()
            Button("Done", action: done)
                .fixedSize(horizontal: true, vertical: false)
                .font(WorkoutFont.ui(15))
                .foregroundStyle(NanoTheme.teal)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Capsule().fill(NanoTheme.surface))
                .buttonStyle(WorkoutPressButtonStyle())
        }
    }
}

private struct WorkoutPrimaryButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .lineLimit(1).minimumScaleFactor(0.85)
                .font(WorkoutFont.ui(16))
                .foregroundStyle(NanoTheme.background)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(NanoTheme.teal)
                        .shadow(color: NanoTheme.teal.opacity(0.30), radius: 12)
                )
        }
        .buttonStyle(WorkoutPressButtonStyle())
    }
}

private struct WorkoutCircleButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(NanoTheme.surface.opacity(0.88)))
        }
        .buttonStyle(WorkoutPressButtonStyle())
    }
}

private struct WorkoutDisplayPicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    @Binding var showsMap: Bool

    var body: some View {
        HStack(spacing: 2) {
            option(title: "Metrics", symbol: "chart.bar.fill", selected: !showsMap) {
                showsMap = false
            }
            option(title: "Map", symbol: "map.fill", selected: showsMap) {
                showsMap = true
            }
        }
        .padding(3)
        .background(Capsule().fill(NanoTheme.surface))
        .overlay(Capsule().stroke(NanoTheme.elevated, lineWidth: 1))
        .animation(reduceMotion ? nil : WorkoutMotion.state(reduceMotion: false), value: showsMap)
    }

    private func option(
        title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(WorkoutFont.ui(11))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
                .foregroundStyle(selected ? NanoTheme.background : NanoTheme.secondaryText)
                .padding(.horizontal, title == "Metrics" ? 9 : 10)
                .frame(height: 44)
                .background {
                    if selected {
                        Capsule().fill(NanoTheme.teal)
                            .matchedGeometryEffect(id: "workout-display-selection", in: selectionNamespace)
                    }
                }
        }
        .buttonStyle(WorkoutPressButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct WorkoutCapabilityStrip: View {
    let locationReady: Bool
    let liveActivityReady: Bool
    let alertReady: Bool

    var body: some View {
        HStack(spacing: 0) {
            WorkoutCapabilityItem(
                symbol: locationReady ? "location.fill" : "location.slash.fill",
                title: "Location",
                ready: locationReady
            )
            Divider().overlay(NanoTheme.elevated)
            WorkoutCapabilityItem(
                symbol: liveActivityReady ? "iphone.gen3.radiowaves.left.and.right" : "iphone.slash",
                title: "Lock Screen",
                ready: liveActivityReady
            )
            Divider().overlay(NanoTheme.elevated)
            WorkoutCapabilityItem(
                symbol: alertReady ? "waveform" : "speaker.slash.fill",
                title: "Goal Alert",
                ready: alertReady
            )
        }
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 17).fill(NanoTheme.background.opacity(0.48)))
    }
}

private struct WorkoutCapabilityItem: View {
    let symbol: String
    let title: String
    let ready: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ready ? NanoTheme.teal : NanoTheme.secondaryText)
            Text(title.uppercased())

                .font(WorkoutFont.ui(8))
                .foregroundStyle(ready ? .white : NanoTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityValue(ready ? "Ready" : "Unavailable")
    }
}

private struct WorkoutPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: configuration.isPressed ? 0.10 : 0.16), value: configuration.isPressed)
    }
}

private struct WorkoutCreatureBadge: View {
    let creature: CreatureStage

    var body: some View {
        WorkoutCreatureArtwork(creature: creature)
            .padding(5)
            .frame(width: 64, height: 64)
            .background(Circle().fill(NanoTheme.teal.opacity(0.13)))
            .overlay(Circle().stroke(NanoTheme.teal.opacity(0.45), lineWidth: 1))
            .shadow(color: NanoTheme.teal.opacity(0.35), radius: 10)
    }
}

private struct WorkoutCreatureArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let creature: CreatureStage
    var isPlaying = true

    var body: some View {
        Group {
            if reduceMotion {
                CreatureArtworkView(stage: creature)
            } else {
                AnimatedCreatureArtworkView(
                    stage: creature,
                    isPlaying: isPlaying,
                    preloadsAllFrames: false
                )
            }
        }
        .accessibilityLabel("Workout companion, \(creature.name)")
    }
}

private struct WorkoutMiniBadge: View {
    let symbol: String
    let active: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(active ? NanoTheme.background : NanoTheme.secondaryText)
            .frame(width: 54, height: 54)
            .background(Circle().fill(active ? NanoTheme.teal : NanoTheme.elevated.opacity(0.72)))
    }
}

private struct WorkoutSetupOption: View {
    let symbol: String
    let eyebrow: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)

                    .font(WorkoutFont.ui(9))
                    .foregroundStyle(NanoTheme.secondaryText)
                Text(title)
                    .font(WorkoutFont.ui(12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(RoundedRectangle(cornerRadius: 17).fill(NanoTheme.background.opacity(0.65)))
    }
}

private struct WorkoutMetricTile: View {
    let symbol: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NanoTheme.teal)
            Text(value)

                .font(WorkoutFont.metric(18))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit)
                .lineLimit(1).minimumScaleFactor(0.8)
                .font(WorkoutFont.ui(9))
                .foregroundStyle(NanoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 17).fill(NanoTheme.surface))
    }
}

private struct WorkoutSummaryTile: View {
    let label: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .font(WorkoutFont.ui(10))
                    .foregroundStyle(NanoTheme.secondaryText)
                Spacer()
                Image(systemName: symbol)
                    .foregroundStyle(NanoTheme.teal)
            }
            Text(value)

                .font(WorkoutFont.metric(19))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .nanoHUDCard(tint: NanoTheme.teal, padding: 15)
    }
}

private func workoutTime(_ seconds: Int) -> String {
    if seconds >= 3_600 {
        return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

private func workoutPace(_ minutesPerMile: Double) -> String {
    guard minutesPerMile.isFinite, minutesPerMile > 0 else { return "--:--" }
    let capped = min(minutesPerMile, 99.98)
    let minutes = Int(capped)
    let seconds = Int((capped - Double(minutes)) * 60)
    return String(format: "%02d:%02d", minutes, seconds)
}

#Preview {
    WorkoutView()
}
