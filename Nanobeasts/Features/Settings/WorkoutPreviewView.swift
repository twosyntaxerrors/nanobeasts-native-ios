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

    @StateObject private var exploration = WorkoutExplorationProgress()
    @State private var completedExploration = WorkoutExplorationRecap()
    @StateObject private var zoneCelebrations = WorkoutZoneCelebrations.shared
    @State private var setupSheet: WorkoutSetupSheet?
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
    /// Simulator screenshot fixture: opens straight on a finished walk's summary.
    private let previewsSummary: Bool
    /// Simulator screenshot fixture: the start screen's map over the same walks.
    private let previewsMap: Bool

    init(
        simulatesTerritory: Bool = false,
        resumingSessionID: String? = nil,
        previewsSummary: Bool = false,
        previewsMap: Bool = false
    ) {
        let tracker = simulatesTerritory || previewsSummary || previewsMap
            ? WorkoutLocationTracker()
            : WorkoutLocationTracker.shared
#if targetEnvironment(simulator) && DEBUG
        if previewsSummary || previewsMap {
            tracker.seedSummaryDemo(route: GoldieWalkFixture.route, earlierWalks: GoldieWalkFixture.earlierWalks)
        } else if simulatesTerritory {
            tracker.seedTerritoryDemo()
        }
#endif
        _locationTracker = StateObject(wrappedValue: tracker)
        _phase = State(initialValue: previewsSummary ? .summary : simulatesTerritory ? .active : .setup)
        self.previewsSummary = previewsSummary
        self.previewsMap = previewsMap
        if previewsSummary {
            _elapsedSeconds = State(initialValue: 1_190)
            _steps = State(initialValue: 1_980)
            _workoutEndedAt = State(initialValue: Calendar.current.date(bySettingHour: 18, minute: 18, second: 0, of: Date()))
        }
        _showsMap = State(initialValue: true)
        if !previewsSummary {
            _elapsedSeconds = State(initialValue: simulatesTerritory ? 1_847 : 0)
            _steps = State(initialValue: simulatesTerritory ? 4_286 : 0)
        }
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
                            exploration: exploration,
                            creature: store.currentStage,
                            workout: workout,
                            goalKind: goalKind,
                            goalDescription: goalDescription,
                            liveActivityAvailable: liveActivityController.isAvailable,
                            isAcquiringLocation: isAcquiringWorkoutLocation,
                            goalVibrationEnabled: $goalVibrationEnabled,
                            chooseWorkout: { setupSheet = .activity },
                            chooseGoal: { setupSheet = .goal },
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
                case .countdown:
                    WorkoutCountdownScreen(value: countdown)
                case .active, .paused:
                    WorkoutLiveScreen(
                        locationTracker: locationTracker,
                        exploration: exploration,
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
                        territoryTiles: completedExploration.newTiles,
                        exploration: completedExploration,
                        date: workoutEndedAt ?? Date(),
                        exploredRoutes: locationTracker.exploredRoutes,
                        companion: workoutCompanion ?? store.currentStage,
                        rewards: workoutRewards,
                        savedToHealth: workoutTracker.savedToHealth,
                        totalsSourceLabel: completedHistoryRecord?.totalsSourceLabel ?? "Syncing Apple Health totals…",
                        saveError: workoutTracker.saveError,
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

        .interactiveDismissDisabled(phase.isSessionInProgress)
        .task(id: phase) {
            await runPhaseLoop()
        }
        .task {
            guard previewsSummary else { return }
            // The fixture's zone streets and name arrive over the network; keep the
            // summary's exploration line current until they have.
            for _ in 0..<20 {
                exploration.update(route: locationTracker.route, breaks: [], explored: locationTracker.exploredRoutes,
                                   location: locationTracker.currentLocation)
                completedExploration = exploration.recap
                try? await Task.sleep(for: .milliseconds(500))
            }
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
        .onReceive(locationTracker.$route.combineLatest(locationTracker.$routeBreakIndices, locationTracker.$exploredRoutes)) { route, breaks, explored in
            exploration.update(route: route, breaks: breaks, explored: explored, location: locationTracker.currentLocation)
        }
        .onReceive(locationTracker.$currentLocation) { location in
            exploration.update(route: locationTracker.route, breaks: locationTracker.routeBreakIndices,
                               explored: locationTracker.exploredRoutes, location: location)
        }
        .sheet(item: $setupSheet) { sheet in
            switch sheet {
            case .activity:
                WorkoutPickerScreen(environment: $environment, selection: $workout)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            case .goal:
                WorkoutGoalScreen(selection: $goalKind, stepGoal: $stepGoal, calorieGoal: $calorieGoal,
                    durationGoal: $durationGoal, distanceGoalHundredths: $distanceGoalHundredths)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
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
        // A zone reaching 100% gets its own shareable moment over the summary.
        .fullScreenCover(item: zoneCelebrations.binding(
            when: (phase == .summary || phase == .setup) && !showsWatchWorkout && setupSheet == nil
        )) { completion in
            WorkoutZoneCelebrationView(completion: completion)
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
                locationStartMessage = "Precise Location is off. Turn it on for Nanobeasts so the tiles you paint match where you walk."
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
              !simulatesTerritory, !previewsSummary, !previewsMap,
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
        // Capture before the saved route becomes part of previously explored territory.
        exploration.update(route: completedRoute, breaks: completedRouteBreaks,
                           explored: locationTracker.exploredRoutes, location: locationTracker.currentLocation)
        completedExploration = exploration.recap
        if !commitTerritory { completedExploration.newTiles = 0 }
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

private enum WorkoutSetupSheet: String, Identifiable {
    case activity, goal
    var id: Self { self }
}

private enum WorkoutPreviewPhase: Hashable {
    case setup
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
        case .setup: true
        case .countdown, .active, .paused, .summary: false
        }
    }

    var isSessionInProgress: Bool {
        switch self {
        case .countdown, .active, .paused:
            true
        case .setup, .summary:
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
        case .map: "Paint your streets"
        case .activity: "Choose your adventure"
        case .goal: "Give this walk a target"
        case .start: "Take your Nanobeast along"
        case .history: "Replay and share your route"
        }
    }
    var detail: String {
        switch self {
        case .map: "Outdoor walks paint tiles in your color, including walks started on Apple Watch. Each dashed hexagon is a zone: walk 90% of its streets to master it and earn a shareable card. Faint tiles show the streets you have left."
        case .activity: "Tap here to choose a walk, run, hike, or another activity. Pick indoor tracking when you don’t need a GPS route."
        case .goal: "Choose steps, time, distance, calories, or an open goal. Goal alerts can give you a haptic when you get there."
        case .start: "Tap Start to record on iPhone, or use the Apple Watch button beside it. Your current egg or creature comes with you while your stats update live."
        case .history: "Completed workouts live in History. Open one with a recorded route to watch your creature paint the map, then share the replay video with your stats."
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
        PreviewWorkout(id: "hiking", name: "Hiking", symbol: "figure.hiking", environment: .outdoor, milesPerStep: 0.00044, caloriesPerStep: 0.060, caloriesPerMile: 120)
    ]

    static let indoor = [
        PreviewWorkout(id: "indoor-walk", name: "Indoor Walk", symbol: "figure.walk", environment: .indoor, milesPerStep: 0.00043, caloriesPerStep: 0.038, caloriesPerMile: 85),
        PreviewWorkout(id: "japanese-walk-indoor", name: "Japanese Walking", symbol: "figure.walk.motion", environment: .indoor, milesPerStep: 0.00044, caloriesPerStep: 0.045, caloriesPerMile: 90, detail: "3 min brisk · 3 min recovery"),
        PreviewWorkout(id: "indoor-run", name: "Indoor Run", symbol: "figure.run", environment: .indoor, milesPerStep: 0.00060, caloriesPerStep: 0.052, caloriesPerMile: 110),
        PreviewWorkout(id: "hiit", name: "HIIT", symbol: "figure.highintensity.intervaltraining", environment: .indoor, milesPerStep: 0.00048, caloriesPerStep: 0.070, caloriesPerMile: 135, detail: "High-intensity interval training")
    ]
    // Nordic Walking, Elliptical and Stair Stepper were retired from the picker
    // (Oct 2026); their IDs stay mapped elsewhere so past workouts keep their labels.

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

struct WorkoutExplorationRecap {
    var newTiles = 0
    /// Street-based progress for the focused zone; nil until its street map loads.
    var progress: WorkoutZoneProgress?
    var isLoadingStreets = false
    /// Several fetches failed in a row; streets fill in once the phone is back online.
    var isOffline = false
    /// The zone's own name: the street at its center, so neighbours differ.
    var neighborhood = "This zone"
    /// The wider area it belongs to, e.g. "Brooklyn".
    var area = ""

    var percentText: String {
        guard let progress else { return isOffline ? "Streets load when you're online" : "Mapping streets…" }
        if progress.total == 0 { return "No streets here" }
        let percent = "\(progress.percent.formatted(.number.precision(.fractionLength(1))))%"
        return progress.isMastered ? "\(percent) · Mastered" : "\(percent) of streets"
    }
}

@MainActor
final class WorkoutExplorationProgress: ObservableObject {
    @Published private(set) var recap = WorkoutExplorationRecap()
    /// A mastered zone's card, reopened from its badge.
    @Published var pendingCelebration: WorkoutZoneCompletion?
    private let overlay = WorkoutTerritoryOverlay()
    private var district: WorkoutHexKey?
    private var nameTask: Task<Void, Never>?
    private var focus: CLLocationCoordinate2D?
    private var lastInputs: ([CLLocationCoordinate2D], [Int], [[CLLocationCoordinate2D]], CLLocation?) = ([], [], [], nil)
    private var streetsObserver: NSObjectProtocol?
    private var streetsTask: Task<Void, Never>?
    private var streetsTaskZone: WorkoutHexKey?

    init() {
        streetsObserver = NotificationCenter.default.addObserver(
            forName: WorkoutZoneStreets.didLoad, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Pins the badge to a zone the user panned to; nil follows the walker again.
    func setFocus(_ coordinate: CLLocationCoordinate2D?) {
        focus = coordinate
        refresh()
    }

    /// Fetches the focused zone's streets, retrying on its own after a short pause
    /// so the badge never gets stuck while the phone is briefly offline or busy.
    private func loadStreets(_ zone: WorkoutHexKey) {
        if streetsTaskZone == zone, streetsTask != nil { return }
        streetsTask?.cancel()
        streetsTaskZone = zone
        streetsTask = Task { [weak self] in
            if let wait = WorkoutZoneStreets.shared.retryDelay(zone), wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard !Task.isCancelled else { return }
            let loaded = await WorkoutZoneStreets.shared.load(zone)
            guard let self, !Task.isCancelled else { return }
            self.streetsTask = nil
            if loaded == nil, self.district == zone {
                self.recap.isOffline = WorkoutZoneStreets.shared.seemsOffline(zone)
                self.loadStreets(zone)
            }
        }
    }

    /// The share card for the focused zone if it is mastered: reopens a celebration
    /// any time, so skipping "Share" the first time never loses the moment.
    func masteryCard() -> WorkoutZoneCompletion? {
        guard let district, let streets = WorkoutZoneStreets.shared.cached(district),
              let progress = recap.progress, progress.isMastered else { return nil }
        let snapshot = overlay.snapshot
        return WorkoutZoneCompletion(
            zone: district, name: recap.neighborhood, area: recap.area, streetTiles: streets,
            walkedTiles: snapshot.oldTiles.union(snapshot.currentTiles).filter { $0.district == district },
            percent: progress.percent, completedAt: Date(), ordinal: WorkoutZoneLedger.markCompleted(district))
    }

    /// Tiles from earlier walks, and tiles from the walk in progress.
    var tileSets: (earlier: Set<WorkoutHexKey>, walk: Set<WorkoutHexKey>) {
        let snapshot = overlay.snapshot
        return (snapshot.oldTiles, snapshot.currentTiles)
    }

    private func refresh() {
        let (route, breaks, explored, location) = lastInputs
        update(route: route, breaks: breaks, explored: explored, location: location)
    }

    func update(route: [CLLocationCoordinate2D], breaks: [Int], explored: [[CLLocationCoordinate2D]], location: CLLocation?) {
        lastInputs = (route, breaks, explored, location)
        if !explored.elementsEqual(overlay.exploredRoutes, by: { a, b in
            a.elementsEqual(b, by: { $0.latitude == $1.latitude && $0.longitude == $1.longitude })
        }) { overlay.exploredRoutes = explored }
        overlay.updateRoute(route, breakIndices: breaks)
        let snapshot = overlay.snapshot
        recap.newTiles = snapshot.newTileCount
        guard let coordinate = focus ?? route.last ?? location?.coordinate else { return }
        let next = WorkoutHexGrid.key(coordinate).district
        if let streets = WorkoutZoneStreets.shared.cached(next) {
            recap.progress = WorkoutZoneProgress(streets: streets) {
                snapshot.oldTiles.contains($0) || snapshot.currentTiles.contains($0)
            }
            recap.isLoadingStreets = false
            recap.isOffline = false
        } else {
            recap.progress = nil
            recap.isLoadingStreets = true
            recap.isOffline = WorkoutZoneStreets.shared.seemsOffline(next)
            loadStreets(next)
        }
        guard next != district else { return }
        district = next
        WorkoutZoneStreets.shared.prefetchNeighbors(of: next)
        let cached = WorkoutZoneNames.cached(next)
        recap.neighborhood = cached?.name ?? "This zone"
        recap.area = cached?.area ?? ""
        nameTask?.cancel()
        guard cached == nil else { return }
        nameTask = Task { [weak self] in
            let label = await WorkoutZoneNames.name(for: next)
            guard let self, !Task.isCancelled, self.district == next else { return }
            self.recap.neighborhood = label.name
            self.recap.area = label.area
            self.refresh()
        }
    }
}

struct WorkoutNeighborhoodBadge: View {
    @ObservedObject var exploration: WorkoutExplorationProgress
    /// When set, tapping a mastered zone's badge reopens its shareable card.
    var openMastery: (() -> Void)? = nil
    @ViewBuilder var body: some View {
        // Only a mastered badge is a button, so others never look dimmed or tappable.
        if let openMastery, exploration.recap.progress?.isMastered == true {
            Button(action: openMastery) { content(showsShareHint: true) }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this zone's mastery card to share")
        } else {
            content(showsShareHint: false)
        }
    }

    private func content(showsShareHint: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(exploration.recap.neighborhood)
                    .lineLimit(2).minimumScaleFactor(0.75)
                if exploration.recap.progress?.isMastered == true {
                    // Mastered zones wear a seal for good.
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(NanoTheme.teal)
                        .accessibilityLabel("Mastered")
                }
            }
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white, in: RoundedRectangle(cornerRadius: 5))
                .rotationEffect(.degrees(-2))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            HStack(spacing: 8) {
                if let progress = exploration.recap.progress, progress.total > 0 {
                    ProgressView(value: progress.fraction)
                        .tint(NanoTheme.teal)
                        .frame(width: 44)
                }
                Text([exploration.recap.area, exploration.recap.percentText]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(exploration.recap.progress?.isMastered == true ? NanoTheme.teal : NanoTheme.text)
                    .contentTransition(.numericText())
                if showsShareHint {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(NanoTheme.teal)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(NanoTheme.surface, in: Capsule())
            .animation(.snappy, value: exploration.recap.progress)
        }
        .accessibilityElement(children: .combine)
    }
}

struct WorkoutTileChip: View {
    let recap: WorkoutExplorationRecap
    var body: some View {
        Label("+\(recap.newTiles) new this walk · \(recap.percentText)", systemImage: "hexagon.fill")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(NanoTheme.text)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(NanoTheme.surface, in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

struct WorkoutFloatingStats: View {
    let title: String
    let creature: CreatureStage
    let evolution: WorkoutEvolutionProgress
    let elapsedSeconds: TimeInterval
    let distance: String
    let steps: Int
    var heartRate: String? = nil
    var goalLabel: String? = nil
    var goalProgress: Double = 0
    var paused = false
    var expanded = false
    var expand: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                WorkoutCreatureProgressView(stage: creature, progress: evolution, diameter: 56, isPlaying: !paused)
                VStack(alignment: .leading, spacing: 4) {
                    Text(paused ? "Workout paused" : title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(NanoTheme.text)
                    Text(evolution.caption)
                        .font(.caption).foregroundStyle(NanoTheme.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if let expand {
                    Button(action: expand) {
                        Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NanoTheme.teal)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(expanded ? "Collapse workout numbers" : "Expand workout numbers")
                }
            }
            if expanded {
                stat(steps.formatted(), label: "Steps", large: true)
            }
            HStack(alignment: .top, spacing: 12) {
                stat(WorkoutMetricsFormat.time(elapsedSeconds), label: "Time")
                stat(distance, label: "Distance")
                if let heartRate { stat(heartRate, label: "Heart rate") }
                else if !expanded { stat(steps.formatted(), label: "Steps") }
            }
            if heartRate != nil && !expanded {
                Text("\(steps.formatted()) steps")
                    .font(.caption.weight(.semibold)).foregroundStyle(NanoTheme.secondaryText)
            }
            if let goalLabel {
                VStack(alignment: .leading, spacing: 7) {
                    ProgressView(value: min(1, max(0, goalProgress))).tint(NanoTheme.teal)
                    Text(goalLabel).font(.caption).foregroundStyle(NanoTheme.secondaryText)
                }
            }
        }
        .padding(18)
        .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(NanoTheme.border.opacity(0.6), lineWidth: 1))
        .shadow(color: NanoTheme.shadow.opacity(0.12), radius: 18, y: 6)
    }

    private func stat(_ value: String, label: String, large: Bool = false) -> some View {
        VStack(alignment: large ? .center : .leading, spacing: 5) {
            Text(value)
                .font(.system(size: large ? 58 : 21, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(NanoTheme.text)
            Text(label).font(.caption).foregroundStyle(NanoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: large ? .center : .leading)
        .accessibilityElement(children: .combine)
    }
}

struct WorkoutHoldToFinishButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressing = false
    let action: () -> Void
    var body: some View {
        Text("Hold to finish")
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(NanoTheme.danger)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 18)
                        .fill(NanoTheme.danger.opacity(pressing ? 0.28 : 0.10))
                        .frame(width: pressing ? geometry.size.width : 0)
                        .animation(reduceMotion ? nil : .linear(duration: pressing ? 1.2 : 0.15), value: pressing)
                }
            }
            .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .onLongPressGesture(minimumDuration: 1.2, maximumDistance: 24, pressing: { pressing = $0 }, perform: action)
            .accessibilityElement()
            .accessibilityLabel("Finish workout")
            .accessibilityHint("Touch and hold to finish and save")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

private struct WorkoutSetupScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var watchBridge = WorkoutWatchBridge.shared
    @StateObject private var watchExploration = WorkoutExplorationProgress()
    @State private var recenterID = 0
    @State private var showsSettings = false
    @AppStorage("nanobeasts.workouts.saveToHealth") private var saveToHealth = true
    @ObservedObject var locationTracker: WorkoutLocationTracker
    @ObservedObject var exploration: WorkoutExplorationProgress
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
        ["outdoor-walk", "indoor-walk", "outdoor-run", "indoor-run", "hiking",
         "japanese-walk-outdoor", "japanese-walk-indoor"].contains(workout.id)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if watchBridge.isActive, watchBridge.displaySnapshot?.indoor == false {
                WorkoutTerritoryMap(
                    route: watchBridge.liveRoute.locations.map { $0.location.coordinate },
                    routeBreakIndices: watchBridge.liveRoute.breakIndices,
                    exploredRoutes: locationTracker.exploredRoutes,
                    currentLocation: watchBridge.liveRoute.locations.last?.location ?? locationTracker.currentLocation,
                    showsFog: true, followsUser: true, reduceMotion: reduceMotion,
                    recenterID: recenterID, companionImageKey: creature.imageKey)
                    .ignoresSafeArea()
            } else {
                WorkoutActualMap(locationTracker: locationTracker, recenterID: recenterID,
                                 showsRecenterControl: false, companionImageKey: creature.imageKey,
                                 onZoneFocus: { exploration.setFocus($0) })
                    .ignoresSafeArea()
                    // Live screens follow the walker again, not wherever the map was panned.
                    .onDisappear { exploration.setFocus(nil) }
            }
            HStack(alignment: .top) {
                WorkoutNeighborhoodBadge(exploration: watchBridge.isActive ? watchExploration : exploration,
                                         openMastery: watchBridge.isActive ? nil : {
                                             exploration.pendingCelebration = exploration.masteryCard()
                                         })
                    .anchorPreference(key: WorkoutTourAnchors.self, value: .bounds) { [.map: $0] }
                Spacer(minLength: 8)
                VStack(spacing: 10) {
                    WorkoutCircleButton(symbol: "location.fill") {
                        locationTracker.requestAccess(); recenterID += 1
                    }
                    .accessibilityLabel("Center map on my location")
                    WorkoutCircleButton(symbol: "questionmark", action: showHelp)
                        .accessibilityLabel("Show workout walkthrough")
                }
            }
            .padding(.horizontal, 20).padding(.top, 76)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 14) {
                if let state = watchBridge.displaySnapshot, state.isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Button(action: start) {
                            HStack {
                                Image(systemName: "applewatch")
                                Text("Watch workout")
                                Text(WorkoutMetricsFormat.time(state.elapsed(at: timeline.date))).monospacedDigit()
                                Spacer()
                                Text("View").foregroundStyle(NanoTheme.teal)
                                Image(systemName: "chevron.right")
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(NanoTheme.text)
                            .frame(minHeight: 54)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        chip(workout.name, symbol: workout.symbol, action: chooseWorkout)
                            .anchorPreference(key: WorkoutTourAnchors.self, value: .bounds) { [.activity: $0] }
                        chip(goalKind == .open ? "Open goal" : goalDescription, symbol: goalKind.symbol, action: chooseGoal)
                            .anchorPreference(key: WorkoutTourAnchors.self, value: .bounds) { [.goal: $0] }
                        Button { showsSettings = true } label: {
                            Image(systemName: "gearshape").font(.system(size: 18))
                                .frame(width: 44, height: 44).foregroundStyle(NanoTheme.text)
                        }
                        .accessibilityLabel("Workout settings")
                    }
                    HStack(spacing: 10) {
                        WorkoutPrimaryButton(title: isAcquiringLocation ? "Acquiring GPS…" : "Start", symbol: "play.fill", action: start)
                        if supportsWatchWorkout {
                            Button(action: startOnWatch) {
                                Image(systemName: "applewatch").font(.system(size: 23, weight: .medium))
                                    .foregroundStyle(NanoTheme.teal)
                                    .frame(width: 58, height: 58)
                                    .background(NanoTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                            }
                            .accessibilityLabel("Start on Apple Watch")
                        }
                    }
                    .disabled(isAcquiringLocation)
                    .anchorPreference(key: WorkoutTourAnchors.self, value: .bounds) { [.start: $0] }
                }
            }
            .padding(18)
            .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 28))
            .shadow(color: NanoTheme.shadow.opacity(0.12), radius: 18, y: 6)
            .padding(.horizontal, 12).padding(.bottom, 10)
        }
        .onReceive(watchBridge.$liveRoute) { live in
            watchExploration.update(route: live.locations.map { $0.location.coordinate }, breaks: live.breakIndices,
                                    explored: locationTracker.exploredRoutes, location: live.locations.last?.location)
        }
        .fullScreenCover(item: $exploration.pendingCelebration) { completion in
            WorkoutZoneCelebrationView(completion: completion)
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                Form {
                    Toggle("Haptic goal alerts", isOn: $goalVibrationEnabled)
                    Toggle("Save to Apple Health", isOn: $saveToHealth)
                    Text("Your iPhone and Apple Watch save Health workouts using their own settings.")
                        .font(.footnote).foregroundStyle(NanoTheme.secondaryText)
                }
                .tint(NanoTheme.teal)
                .navigationTitle("Workout settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsSettings = false } } }
            }
            .presentationDetents([.medium]).presentationDragIndicator(.visible)
        }
    }
    private func chip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(NanoTheme.text)
                .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44)
                .background(NanoTheme.elevated.opacity(0.65), in: Capsule())
        }
        .buttonStyle(WorkoutPressButtonStyle())
    }
}

private struct WorkoutPickerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var environment: WorkoutEnvironment
    @Binding var selection: PreviewWorkout
    var body: some View {
        NavigationStack {
            List {
                ForEach(WorkoutEnvironment.allCases) { group in
                    Section(group.rawValue) {
                        ForEach(PreviewWorkout.options(for: group)) { option in
                            Button {
                                environment = option.environment
                                selection = option
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: option.symbol).font(.system(size: 22))
                                        .foregroundStyle(NanoTheme.teal).frame(width: 32)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(option.name).font(.body.weight(.medium)).foregroundStyle(NanoTheme.text)
                                        if let detail = option.detail {
                                            Text(detail).font(.caption).foregroundStyle(NanoTheme.secondaryText)
                                        }
                                    }
                                    Spacer()
                                    if selection == option { Image(systemName: "checkmark").foregroundStyle(NanoTheme.teal) }
                                }
                                .padding(.vertical, 6)
                            }
                            .accessibilityAddTraits(selection == option ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle("Choose activity").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct WorkoutGoalScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: WorkoutGoalKind
    @Binding var stepGoal: Int
    @Binding var calorieGoal: Int
    @Binding var durationGoal: Int
    @Binding var distanceGoalHundredths: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            WorkoutModalHeader(title: "Workout Goal", done: { dismiss() })

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
                            .foregroundStyle(NanoTheme.text)
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
    @Environment(AppStore.self) private var store
    @ObservedObject var locationTracker: WorkoutLocationTracker
    @ObservedObject var exploration: WorkoutExplorationProgress
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

    private var expanded: Bool { workout.environment == .indoor || !showsMap }
    private var distance: String {
        let value = store.distanceUnit == .miles ? distanceMiles : distanceMiles * 1.609344
        return String(format: "%.2f %@", value, store.distanceUnit.abbreviation.lowercased())
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            if workout.environment == .outdoor {
                WorkoutActualMap(locationTracker: locationTracker, showsRecenterControl: false, companionImageKey: creature.imageKey)
                    .ignoresSafeArea()
                    .overlay { if isPaused { Color.black.opacity(0.25).ignoresSafeArea().allowsHitTesting(false) } }
                WorkoutNeighborhoodBadge(exploration: exploration)
                    .padding(.horizontal, 20).padding(.top, 18)
            } else {
                NanoTheme.backgroundGradient.ignoresSafeArea()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                if workout.environment == .outdoor { WorkoutTileChip(recap: exploration.recap) }
                ScrollView {
                    VStack(spacing: 12) {
                        WorkoutFloatingStats(title: workout.name, creature: creature, evolution: evolution,
                            elapsedSeconds: Double(elapsedSeconds), distance: distance, steps: steps,
                            goalLabel: goalKind == .open ? nil : (didReachGoal ? "Goal reached · \(goalDescription)" : "Goal · \(goalDescription)"),
                            goalProgress: goalProgress, paused: isPaused, expanded: expanded,
                            expand: workout.environment == .indoor ? nil : { showsMap.toggle() })
                        WorkoutMilestoneAction(source: .phone(paused: isPaused))
                        if let japaneseWalkingTempo, let tempoSecondsRemaining {
                            JapaneseWalkingTempoStrip(tempo: japaneseWalkingTempo, secondsRemaining: tempoSecondsRemaining)
                        }
                        if expanded {
                            Text("\(Int(calories)) kcal · \(workoutPace(paceMinutesPerMile)) /mi")
                                .font(.caption).foregroundStyle(NanoTheme.secondaryText)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: expanded ? 420 : 270)
                .fixedSize(horizontal: false, vertical: true)
                WorkoutPrimaryButton(title: isPaused ? "Resume" : "Pause", symbol: isPaused ? "play.fill" : "pause.fill", action: isPaused ? resume : pause)
                if isPaused { WorkoutHoldToFinishButton(action: end) }
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .animation(WorkoutMotion.state(reduceMotion: reduceMotion), value: expanded)
        .animation(WorkoutMotion.state(reduceMotion: reduceMotion), value: isPaused)
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
                                .foregroundStyle(NanoTheme.text)
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
                    .foregroundStyle(NanoTheme.text)
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
    let exploration: WorkoutExplorationRecap
    let date: Date
    let exploredRoutes: [[CLLocationCoordinate2D]]
    let companion: CreatureStage
    let rewards: [CreatureDiscoveryEvent]
    let savedToHealth: Bool
    let totalsSourceLabel: String
    let saveError: String?
    let done: () -> Void
    @State private var sharePayload: WorkoutSharePayload?
    @State private var replayPayload: WorkoutSharePayload?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Adventure complete", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(NanoTheme.teal)
                    Spacer()
                    Button("Done", action: done).tint(NanoTheme.teal).frame(minHeight: 44)
                }
                if workout.environment == .outdoor, !route.isEmpty {
                    WorkoutTerritoryMap(route: route, routeBreakIndices: routeBreakIndices, exploredRoutes: exploredRoutes,
                        currentLocation: route.last.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) },
                        showsFog: true, followsUser: false, reduceMotion: reduceMotion, fitsRoute: true)
                        .frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 26))
                        .accessibilityLabel("Completed route with revealed hexagon tiles")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(workout.name).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(NanoTheme.text)
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline).foregroundStyle(NanoTheme.secondaryText)
                    if workout.environment == .outdoor {
                        Text("+\(exploration.newTiles) new tiles · \(exploration.neighborhood): \(exploration.percentText)")
                            .font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(NanoTheme.teal)
                    }
                    if didReachGoal { Label("Goal reached · \(goalDescription)", systemImage: "checkmark").font(.caption).foregroundStyle(NanoTheme.teal) }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    summaryStat(steps.formatted(), "Steps")
                    summaryStat(workoutTime(elapsedSeconds), "Active time")
                    summaryStat(distance, "Distance")
                    summaryStat("\(Int(calories)) kcal", "Energy")
                }
                Text(totalsSourceLabel).font(.caption).foregroundStyle(NanoTheme.secondaryText)
                HStack(spacing: 14) {
                    CreatureArtworkView(stage: companion).frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(steps.formatted()) steps with \(companion.name)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(NanoTheme.text)
                        Text(rewards.isEmpty ? "Every step brings a new form closer." : rewards.prefix(3).map { "\($0.kind.title): \($0.name)" }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(NanoTheme.secondaryText)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                Label(saveError ?? (savedToHealth ? "Saved to Apple Health" : saveToHealth ? "Apple Health save pending" : "Apple Health sharing is off"),
                      systemImage: savedToHealth ? "checkmark.circle" : "heart")
                    .font(.caption).foregroundStyle(saveError == nil ? NanoTheme.secondaryText : NanoTheme.orange)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                WorkoutPrimaryButton(title: "Share workout", symbol: "square.and.arrow.up") { sharePayload = makeWorkoutPayload() }
                if workout.environment == .outdoor,
                   WorkoutRouteReplayTrack(route: route, breakIndices: routeBreakIndices).canReplay {
                    Button { replayPayload = makeWorkoutPayload() } label: {
                        Label("Replay route", systemImage: "play.circle").font(.subheadline.weight(.semibold))
                            .foregroundStyle(NanoTheme.teal).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12).background(NanoTheme.background)
        }
        .fullScreenCover(item: $replayPayload) { payload in
            WorkoutRouteReplayView(payload: payload, distanceUnit: store.distanceUnit)
        }
        .sheet(item: $sharePayload) { payload in
            WorkoutShareComposer(payload: payload).presentationDetents([.large]).presentationDragIndicator(.hidden)
        }
    }
    private var distance: String {
        let value = store.distanceUnit == .miles ? distanceMiles : distanceMiles * 1.609344
        return String(format: "%.2f %@", value, store.distanceUnit.abbreviation.lowercased())
    }
    private func summaryStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65).foregroundStyle(NanoTheme.text)
            Text(label).font(.caption).foregroundStyle(NanoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
    private func makeWorkoutPayload() -> WorkoutSharePayload {
        WorkoutSharePayload(workoutName: workout.name, workoutSymbol: workout.symbol, elapsedSeconds: elapsedSeconds,
            steps: steps, distanceMiles: distanceMiles, calories: calories, isIndoor: workout.environment == .indoor,
            route: route, territoryTiles: territoryTiles, companion: companion, rewards: rewards, routeBreakIndices: routeBreakIndices)
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
    var onZoneFocus: ((CLLocationCoordinate2D) -> Void)? = nil
    @State private var localRecenterID = 0
    @State private var isBrowsing = false

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
                companionImageKey: companionImageKey,
                onZoneFocus: onZoneFocus,
                onBrowsingChange: { isBrowsing = $0 }
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
                            .foregroundStyle(NanoTheme.text)
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
                        .foregroundStyle(NanoTheme.text)
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
                        .foregroundStyle(NanoTheme.text)
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
            } else if isBrowsing, locationTracker.isTracking {
                WorkoutRecenterPill { localRecenterID += 1 }
                    .padding(.trailing, 18).padding(.top, 14)
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
            return "Turn on Precise Location so the tiles you paint match the path you actually took."
        }
        return locationTracker.needsPermission
            ? "Use your position to clear territory as you move."
            : "Enable location for Nanobeasts in iPhone Settings."
    }
}

struct WorkoutTerritoryMap: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let route: [CLLocationCoordinate2D]
    let routeBreakIndices: [Int]
    let exploredRoutes: [[CLLocationCoordinate2D]]
    let currentLocation: CLLocation?
    let showsFog: Bool
    let followsUser: Bool
    let reduceMotion: Bool
    var recenterID: Int = 0
    var companionImageKey: String? = nil
    var fitsRoute = false
    /// Browsing mode: the highlighted zone is whichever one sits at the map's center.
    var onZoneFocus: ((CLLocationCoordinate2D) -> Void)? = nil
    /// True once the user drags the map: following pauses until they recenter.
    var onBrowsingChange: ((Bool) -> Void)? = nil

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

        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
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
            isDark: colorScheme == .dark,
            accent: UIColor(NanoTheme.teal).resolvedColor(with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)),
            fitsRoute: fitsRoute,
            onZoneFocus: onZoneFocus,
            onBrowsingChange: onBrowsingChange,
            on: mapView
        )
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        mapView.delegate = nil
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let territoryOverlay = WorkoutTerritoryOverlay()
        private weak var territoryRenderer: WorkoutTerritoryRenderer?
        private weak var mapView: MKMapView?
        private var hasPositionedCamera = false
        private var lastCenteredLocation: CLLocation?
        private var lastRecenterID = 0
        private var streetsObserver: NSObjectProtocol?
        private var reducesMotion = false
        private var onZoneFocus: ((CLLocationCoordinate2D) -> Void)?
        private var onBrowsingChange: ((Bool) -> Void)?
        private var centerZone: WorkoutHexKey?
        /// Set when the user drags or zooms; live maps stop following until recentered.
        private var isBrowsing = false
        #if DEBUG
        private let companionExperiment = WorkoutMapCompanionExperiment()
        #endif

        func install(on mapView: MKMapView) {
            self.mapView = mapView
            // Street names stay readable on top of the fog and tiles.
            mapView.addOverlay(territoryOverlay, level: .aboveRoads)

            // Repaint when a zone's street map arrives, so its "left to walk" hint appears.
            streetsObserver = NotificationCenter.default.addObserver(
                forName: WorkoutZoneStreets.didLoad, object: nil, queue: .main) { [weak self] _ in
                self?.redrawVisibleMap()
            }
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
            isDark: Bool,
            accent: UIColor,
            fitsRoute: Bool,
            onZoneFocus: ((CLLocationCoordinate2D) -> Void)?,
            onBrowsingChange: ((Bool) -> Void)?,
            on mapView: MKMapView
        ) {
            self.onZoneFocus = onZoneFocus
            self.onBrowsingChange = onBrowsingChange
            #if DEBUG
            companionExperiment.update(on: mapView, imageKey: companionImageKey,
                                       location: currentLocation, reduceMotion: reduceMotion)
            #endif
            reducesMotion = reduceMotion
            let district = onZoneFocus != nil && centerZone != nil
                ? centerZone
                : (route.last ?? currentLocation?.coordinate).map { WorkoutHexGrid.key($0).district }
            let previous = territoryOverlay.snapshot
            let needsFullRedraw = previous.showsFog != showsFog || previous.isDark != isDark
                || previous.district != district || !previous.accent.isEqual(accent)
            territoryOverlay.showsFog = showsFog
            territoryOverlay.setAppearance(isDark: isDark, accent: accent, district: district)
            mapView.overrideUserInterfaceStyle = isDark ? .dark : .light
            updateExploredRoutes(exploredRoutes)
            redraw(territoryOverlay.updateRoute(route, breakIndices: routeBreakIndices))
            if needsFullRedraw { redrawVisibleMap() }

            if fitsRoute, !route.isEmpty {
                if !hasPositionedCamera {
                    hasPositionedCamera = true
                    mapView.setVisibleMapRect(WorkoutReplayMapBounds.rect(for: route, padding: 0.15),
                        edgePadding: UIEdgeInsets(top: 30, left: 25, bottom: 30, right: 25), animated: false)
                }
                return
            }
            let requestedRecenter = recenterID != lastRecenterID
            let phoneLocation = mapView.userLocation.location.flatMap {
                abs($0.timestamp.timeIntervalSinceNow) < 15 ? $0 : nil
            }
            let targetLocation = requestedRecenter ? (phoneLocation ?? currentLocation) : currentLocation
            guard let currentLocation = targetLocation else { return }

            if requestedRecenter, isBrowsing {
                isBrowsing = false
                onBrowsingChange?(false)
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
            } else if followsUser, !isBrowsing,
                      lastCenteredLocation?.distance(from: currentLocation) ?? .greatestFiniteMagnitude > 8 {
                lastCenteredLocation = currentLocation
                mapView.setCenter(currentLocation.coordinate, animated: !reduceMotion)
            }
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

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // Only a finger on the map counts; our own follow/recenter moves never do.
            let touched = mapView.subviews.first?.gestureRecognizers?.contains {
                $0.state == .began || $0.state == .changed || $0.state == .ended
            } ?? false
            guard touched, !isBrowsing else { return }
            isBrowsing = true
            DispatchQueue.main.async { self.onBrowsingChange?(true) }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard let onZoneFocus, hasPositionedCamera else { return }
            let center = mapView.centerCoordinate
            guard CLLocationCoordinate2DIsValid(center) else { return }
            let zone = WorkoutHexGrid.key(center).district
            guard zone != centerZone else { return }
            centerZone = zone
            let snapshot = territoryOverlay.snapshot
            territoryOverlay.setAppearance(isDark: snapshot.isDark, accent: snapshot.accent, district: zone)
            redrawVisibleMap()
            onZoneFocus(center)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let territoryOverlay = overlay as? WorkoutTerritoryOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = WorkoutTerritoryRenderer(overlay: territoryOverlay)
            territoryRenderer = renderer
            return renderer
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

        private func redrawVisibleMap() {
            guard let mapView else { return }
            territoryRenderer?.setNeedsDisplay(mapView.visibleMapRect)
        }

        /// Repaints only what changed; nil means the whole visible map.
        private func redraw(_ changed: MKMapRect?) {
            guard let mapView else { return }
            guard let changed else { return redrawVisibleMap() }
            guard !changed.isNull else { return }
            let visible = changed.intersection(mapView.visibleMapRect)
            if !visible.isNull { territoryRenderer?.setNeedsDisplay(visible) }
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

/// Map-space geometry for one route, prepared once so tiles never redo it.
// Routes remain the persisted source of truth; this grid is derived in memory.
struct WorkoutRouteLine {
    let coordinates: [CLLocationCoordinate2D]
}

struct WorkoutHexKey: Hashable {
    let band: Int
    let q: Int
    let r: Int

    var radius: Double { WorkoutHexGrid.radius(band: band) }
    var center: MKMapPoint { WorkoutHexGrid.center(q: q, r: r, radius: radius) }
    var district: WorkoutHexKey {
        let axial = WorkoutHexGrid.round(q: Double(q) / 20, r: Double(r) / 20)
        return WorkoutHexKey(band: band, q: axial.0, r: axial.1)
    }
    var bounds: MKMapRect {
        MKMapRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }
    func vertices(scale: Double = 1) -> [MKMapPoint] {
        let c = WorkoutHexGrid.center(q: q, r: r, radius: radius * scale)
        return (0..<6).map { i in
            let angle = (Double(i) * 60 - 30) * .pi / 180
            return MKMapPoint(x: c.x + radius * scale * cos(angle), y: c.y + radius * scale * sin(angle))
        }
    }
}

enum WorkoutHexGrid {
    static let radiusMeters = 20.0
    static let districtCapacity = 400
    static func radius(band: Int) -> Double {
        radiusMeters * MKMapPointsPerMeterAtLatitude(Double(band) + 0.5)
    }
    static func center(q: Int, r: Int, radius: Double) -> MKMapPoint {
        MKMapPoint(x: MKMapRect.world.width / 2 + radius * sqrt(3) * (Double(q) + Double(r) / 2),
                   y: MKMapRect.world.height / 2 + radius * 1.5 * Double(r))
    }
    static func round(q: Double, r: Double) -> (Int, Int) {
        var x = q.rounded(), z = r.rounded()
        let y = (-q - r).rounded()
        let dx = abs(x - q), dz = abs(z - r), dy = abs(y + q + r)
        if dx > dy && dx > dz { x = -y - z }
        else if dz > dy { z = -x - y }
        return (Int(x), Int(z))
    }
    static func key(_ coordinate: CLLocationCoordinate2D) -> WorkoutHexKey {
        let band = min(84, max(-85, Int(floor(coordinate.latitude))))
        let p = MKMapPoint(coordinate), radius = radius(band: band)
        let x = p.x - MKMapRect.world.width / 2, y = p.y - MKMapRect.world.height / 2
        let axial = round(q: (sqrt(3) / 3 * x - y / 3) / radius, r: (2 * y / 3) / radius)
        return WorkoutHexKey(band: band, q: axial.0, r: axial.1)
    }
    static func tiles(route: [CLLocationCoordinate2D], breaks: [Int] = [], startingAt start: Int = 0) -> Set<WorkoutHexKey> {
        var result: Set<WorkoutHexKey> = []
        let gaps = Set(breaks)
        for i in max(0, start)..<max(start, route.count) {
            let coordinate = route[i]
            guard CLLocationCoordinate2DIsValid(coordinate) else { continue }
            result.insert(key(coordinate))
            guard i > 0, !gaps.contains(i), CLLocationCoordinate2DIsValid(route[i - 1]) else { continue }
            let a = MKMapPoint(route[i - 1]), b = MKMapPoint(coordinate)
            let meters = a.distance(to: b)
            guard meters <= 1_500 else { continue }
            let samples = max(1, Int(ceil(meters / (radiusMeters / 2))))
            for step in 0...samples {
                let t = Double(step) / Double(samples)
                result.insert(key(MKMapPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t).coordinate))
            }
        }
        return result
    }
    private static let cornerUnits: [(Double, Double)] = (0..<6).map { i in
        let angle = (Double(i) * 60 - 30) * .pi / 180
        return (cos(angle), sin(angle))
    }

    /// Appends one tile's outline in map points (the overlay renderer's own space).
    static func addHexagon(_ tile: WorkoutHexKey, to path: CGMutablePath, scale: Double = 1) {
        let radius = tile.radius * scale, center = tile.center
        path.move(to: CGPoint(x: center.x + radius * cornerUnits[0].0, y: center.y + radius * cornerUnits[0].1))
        for corner in cornerUnits.dropFirst() {
            path.addLine(to: CGPoint(x: center.x + radius * corner.0, y: center.y + radius * corner.1))
        }
        path.closeSubpath()
    }

    /// Zones overlapping a map area, for the faint zone grid. Empty when zoomed
    /// so far out that outlines would turn into noise.
    static func districts(in rect: MKMapRect) -> [WorkoutHexKey] {
        let zoneRadius = radius(band: key(MKMapPoint(x: rect.midX, y: rect.midY).coordinate).band) * 20
        let area = rect.insetBy(dx: -zoneRadius, dy: -zoneRadius)
        let step = zoneRadius * 0.75
        guard (area.width / step) * (area.height / step) <= 400 else { return [] }
        var found: Set<WorkoutHexKey> = []
        var y = area.minY
        while y <= area.maxY {
            var x = area.minX
            while x <= area.maxX {
                found.insert(key(MKMapPoint(x: x, y: y).coordinate).district)
                x += step
            }
            y += step
        }
        return Array(found)
    }
    static func tiles(routes: [[CLLocationCoordinate2D]]) -> Set<WorkoutHexKey> {
        routes.reduce(into: []) { $0.formUnion(tiles(route: $1)) }
    }
}

final class WorkoutTerritoryOverlay: NSObject, MKOverlay {
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect = MKMapRect.world
    struct ChunkKey: Hashable { let band: Int; let q: Int; let r: Int }
    /// Up to 16×16 tiles whose outlines are built once. With a world-sized overlay the
    /// renderer draws in map points, so these paths are reused as-is on every
    /// redraw instead of recomputing thousands of hexagons per map tile.
    struct Chunk {
        var tiles: Set<WorkoutHexKey> = []
        var bounds = MKMapRect.null
        var explored: CGPath = CGMutablePath()
        var walking: CGPath = CGMutablePath()
        /// Every tile grown by 12%: filled behind the tiles it becomes the trail's outline.
        var outline: CGPath = CGMutablePath()
    }
    struct Snapshot {
        var route: [CLLocationCoordinate2D] = []
        var routeBreakIndices: [Int] = []
        var exploredRoutes: [[CLLocationCoordinate2D]] = []
        var oldTiles: Set<WorkoutHexKey> = []
        var currentTiles: Set<WorkoutHexKey> = []
        var chunks: [ChunkKey: Chunk] = [:]
        var districtCounts: [WorkoutHexKey: Int] = [:]
        var district: WorkoutHexKey?
        var showsFog = false
        var isDark = false
        var accent = UIColor(red: 0.2, green: 0.8, blue: 0.7, alpha: 1)
        var newTileCount: Int { currentTiles.subtracting(oldTiles).count }
        mutating func insert(_ tiles: Set<WorkoutHexKey>) {
            var grouped: [ChunkKey: [WorkoutHexKey]] = [:]
            for tile in tiles {
                let key = ChunkKey(band: tile.band, q: Int(floor(Double(tile.q) / 16)), r: Int(floor(Double(tile.r) / 16)))
                grouped[key, default: []].append(tile)
            }
            for (key, group) in grouped {
                var chunk = chunks[key] ?? Chunk()
                let explored = chunk.explored.mutableCopy() ?? CGMutablePath()
                let walking = chunk.walking.mutableCopy() ?? CGMutablePath()
                let outline = chunk.outline.mutableCopy() ?? CGMutablePath()
                for tile in group where chunk.tiles.insert(tile).inserted {
                    chunk.bounds = chunk.bounds.union(tile.bounds.insetBy(dx: -tile.radius * 0.4, dy: -tile.radius * 0.4))
                    districtCounts[tile.district, default: 0] += 1
                    WorkoutHexGrid.addHexagon(tile, to: currentTiles.contains(tile) && !oldTiles.contains(tile) ? walking : explored)
                    WorkoutHexGrid.addHexagon(tile, to: outline, scale: 1.12)
                }
                // Immutable copies: MapKit draws on background threads while walks update.
                chunk.explored = explored.copy() ?? explored
                chunk.walking = walking.copy() ?? walking
                chunk.outline = outline.copy() ?? outline
                chunks[key] = chunk
            }
        }
        mutating func rebuild() {
            chunks = [:]; districtCounts = [:]
            insert(oldTiles.union(currentTiles))
        }
    }
    private let lock = NSLock()
    private var state = Snapshot()
    var snapshot: Snapshot { lock.withLock { state } }
    var route: [CLLocationCoordinate2D] {
        get { snapshot.route }
        set { updateRoute(newValue, breakIndices: routeBreakIndices) }
    }
    var routeBreakIndices: [Int] {
        get { snapshot.routeBreakIndices }
        set { updateRoute(route, breakIndices: newValue) }
    }
    var exploredRoutes: [[CLLocationCoordinate2D]] {
        get { snapshot.exploredRoutes }
        set {
            let tiles = WorkoutHexGrid.tiles(routes: newValue)
            lock.withLock { state.exploredRoutes = newValue; state.oldTiles = tiles; state.rebuild() }
        }
    }
    var showsFog: Bool {
        get { snapshot.showsFog }
        set { lock.withLock { state.showsFog = newValue } }
    }
    func setAppearance(isDark: Bool, accent: UIColor, district: WorkoutHexKey?) {
        lock.withLock { state.isDark = isDark; state.accent = accent; state.district = district }
    }
    @discardableResult
    func updateRoute(_ route: [CLLocationCoordinate2D], breakIndices: [Int]) -> MKMapRect? {
        lock.withLock {
            let continues = route.count >= state.route.count && breakIndices == state.routeBreakIndices
                && zip(state.route, route).allSatisfy { $0.latitude == $1.latitude && $0.longitude == $1.longitude }
            let incoming = WorkoutHexGrid.tiles(route: route, breaks: breakIndices, startingAt: continues ? state.route.count : 0)
            let changed = incoming.subtracting(state.currentTiles)
            state.route = route; state.routeBreakIndices = breakIndices
            if continues { state.currentTiles.formUnion(incoming); state.insert(changed) }
            else { state.currentTiles = incoming; state.rebuild() }
            guard continues else { return nil }
            return changed.reduce(MKMapRect.null) { $0.union($1.bounds.insetBy(dx: -$1.radius * 0.4, dy: -$1.radius * 0.4)) }
        }
    }
}

final class WorkoutTerritoryRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let snapshot = (overlay as? WorkoutTerritoryOverlay)?.snapshot, snapshot.showsFog else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        let unit = 1 / max(zoomScale, 0.000001)
        // Every zone is faintly outlined so there is always a next one to aim for.
        let isWalked = { (tile: WorkoutHexKey) in
            snapshot.oldTiles.contains(tile) || snapshot.currentTiles.contains(tile)
        }
        func isMastered(_ zone: WorkoutHexKey) -> Bool {
            guard let streets = WorkoutZoneStreets.shared.cached(zone) else { return false }
            return WorkoutZoneProgress(streets: streets, walked: isWalked).isMastered
        }
        let grid = CGMutablePath(), mastered = CGMutablePath()
        for zone in WorkoutHexGrid.districts(in: mapRect) {
            if isMastered(zone) { mastered.addPath(path(vertices: zone.vertices(scale: 20))) }
            else if zone != snapshot.district { grid.addPath(path(vertices: zone.vertices(scale: 20))) }
        }
        // Mastered zones keep a solid, softly filled outline: conquered ground at a glance.
        context.addPath(mastered)
        context.setFillColor(snapshot.accent.withAlphaComponent(0.10).cgColor)
        context.fillPath()
        context.addPath(mastered)
        context.setStrokeColor(snapshot.accent.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2.6 * unit)
        context.strokePath()
        context.addPath(grid)
        context.setStrokeColor(snapshot.accent.withAlphaComponent(snapshot.isDark ? 0.22 : 0.3).cgColor)
        context.setLineWidth(1.2 * unit)
        context.setLineDash(phase: 0, lengths: [6 * unit, 5 * unit])
        context.strokePath()
        if let district = snapshot.district {
            // The focused zone: a stronger dashed edge, and its unwalked streets as a
            // faint accent hint, so you can see exactly what is left to explore.
            if let streets = WorkoutZoneStreets.shared.cached(district) {
                let remaining = CGMutablePath()
                for tile in streets where tile.bounds.intersects(mapRect)
                    && !isWalked(tile) && !tile.neighbors.contains(where: isWalked) {
                    remaining.addPath(path(vertices: tile.vertices()))
                }
                context.addPath(remaining)
                context.setFillColor(snapshot.accent.withAlphaComponent(snapshot.isDark ? 0.16 : 0.18).cgColor)
                context.fillPath()
            }
            if !isMastered(district) {
            context.addPath(path(vertices: district.vertices(scale: 20)))
            context.setStrokeColor(snapshot.accent.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(2.2 * unit)
            context.setLineDash(phase: 0, lengths: [8 * unit, 6 * unit])
            context.strokePath()
            }
        }
        context.setLineDash(phase: 0, lengths: [])
        // Prebuilt chunk outlines; CoreGraphics clips anything outside this map tile.
        let visible = snapshot.chunks.values.filter { $0.bounds.intersects(mapRect) }
        guard !visible.isEmpty else { return }
        let explored = CGMutablePath(), walking = CGMutablePath(), outline = CGMutablePath()
        for chunk in visible {
            explored.addPath(chunk.explored)
            walking.addPath(chunk.walking)
            outline.addPath(chunk.outline)
        }
        // Outlines only while tiles are big enough to see them; zoomed out, a plain
        // fill looks the same and skips the offscreen layer.
        let tileRadius = CGFloat(visible.first?.tiles.first?.radius ?? 0)
        WorkoutTrailPainter.paint(explored: explored, walking: walking, accent: snapshot.accent,
                                  isDark: snapshot.isDark, rimWidth: tileRadius * CGFloat(zoomScale) >= 6 ? 1 : 0,
                                  outline: outline, in: context)
    }
    private func path(vertices: [MKMapPoint]) -> CGPath {
        let path = CGMutablePath()
        for (i, vertex) in vertices.enumerated() {
            if i == 0 { path.move(to: point(for: vertex)) } else { path.addLine(to: point(for: vertex)) }
        }
        path.closeSubpath()
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
                            .foregroundStyle(NanoTheme.text)
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
                .foregroundStyle(NanoTheme.text)
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
                .foregroundStyle(NanoTheme.text)
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
                .foregroundStyle(NanoTheme.onAccent)
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

/// Shown on live maps after the user drags away; tapping resumes following.
struct WorkoutRecenterPill: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Recenter", systemImage: "location.fill")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(NanoTheme.onAccent)
                .padding(.horizontal, 16).frame(height: 44)
                .background(Capsule().fill(NanoTheme.teal))
                .shadow(color: NanoTheme.shadow.opacity(0.25), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityHint("Follows your location on the map again")
    }
}

private struct WorkoutCircleButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(NanoTheme.text)
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

private struct WorkoutPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: configuration.isPressed ? 0.10 : 0.16), value: configuration.isPressed)
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
                    .foregroundStyle(NanoTheme.text)
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
                .foregroundStyle(NanoTheme.text)
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
