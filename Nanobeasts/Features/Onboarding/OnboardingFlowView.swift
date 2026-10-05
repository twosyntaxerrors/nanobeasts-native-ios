import AVFoundation
import RevenueCat
import SDWebImage
import SwiftUI
import UIKit

struct OnboardingProfile {
    let playerName: String
    let selectedGoals: Set<String>
    let primaryGoal: String?
    let selectedBlockers: Set<String>
    let dailyGoal: Int
    let wantsHealth: Bool
    let wantsReminders: Bool
}

struct OnboardingFlowView: View {
    @Environment(AppStore.self) private var store

    let onFinished: (OnboardingProfile) -> Void
    private let isPreview: Bool
    private let onDraftChanged: ((OnboardingDraft) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: OnboardingDraft
    @AppStorage("nanobeasts.notifications.setup-reminders") private var setupReminders = false
    @State private var restoreMessage: String?
    @State private var restoring = false
    @FocusState private var nameIsFocused: Bool

    init(previewDraft: OnboardingDraft? = nil,
         onDraftChanged: ((OnboardingDraft) -> Void)? = nil,
         onFinished: @escaping (OnboardingProfile) -> Void) {
        isPreview = previewDraft != nil
        self.onDraftChanged = onDraftChanged
        self.onFinished = onFinished
        _draft = State(initialValue: previewDraft ?? OnboardingDraft.load())
    }

    private var glitchlet: CreatureStage {
        store.catalog.creatureStages.first {
            $0.name.lowercased().contains("glitchlet")
        } ?? store.catalog.creatureStages.first
            ?? CreatureCatalog.fallback.families[0].stages[1]
    }

    private var commitmentEgg: CreatureStage {
        store.catalog.families
            .first(where: { family in
                family.stages.contains(where: { $0.name.lowercased().contains("glitchlet") })
            })?
            .stages.first(where: \.isEgg)
            ?? store.catalog.families.first?.stages.first(where: \.isEgg)
            ?? CreatureCatalog.fallback.families[0].stages[0]
    }

    private var recommendedGoal: Int { draft.recommendedGoal }
    private var evolutionChallenge: WalkingEvolutionChallenge? {
        store.catalog.averageStepsPerEvolution.map {
            WalkingEvolutionChallenge(dailyTarget: recommendedGoal, averageStepsPerEvolution: $0)
        }
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            switch draft.phase {
            case .demo:
                FieldDemoView {
                    transition(to: .chat)
                }
            case .connections:
                // Saved setup drafts from older builds continue without an early Health question.
                Color.clear.onAppear {
                    draft.completedConnections = true
                    transition(to: .commitment)
                }
            case .chat:
                ProfessorChatView(
                    step: $draft.chatStep,
                    playerName: $draft.playerName,
                    selectedGoals: $draft.selectedGoals,
                    primaryGoal: $draft.primaryGoal,
                    selectedBlockers: $draft.selectedBlockers,
                    activity: $draft.activity,
                    currentSteps: $draft.currentSteps,
                    wantsHealth: $draft.wantsHealth,
                    creature: glitchlet,
                    nameIsFocused: $nameIsFocused,
                    onBackToDemo: { transition(to: draft.phase == .connections ? .plan : .demo) },
                    onComplete: {
                        if draft.phase == .connections {
                            draft.completedConnections = true
                            transition(to: .commitment)
                        } else { draft.planPage = .target; transition(to: .preparing) }
                    },
                    isPreview: isPreview
                )
            case .preparing:
                OnboardingPreparationView(
                    playerName: draft.playerName,
                    goal: draft.goalSelection.primary?.title,
                    onBack: { draft.chatStep = .name; transition(to: .chat) },
                    onComplete: { transition(to: .plan) }
                )
            case .profile, .projection, .building, .plan:
                OnboardingPlanView(
                    page: Binding(get: { draft.planPage ?? .target }, set: { draft.planPage = $0 }),
                    comparison: WalkingPlanComparison(baselineSteps: baselineDailySteps, targetSteps: recommendedGoal),
                    selectedGoals: draft.selectedGoals,
                    primaryGoal: draft.goalSelection.primary?.rawValue,
                    selectedBlockers: draft.selectedBlockers,
                    playerName: draft.playerName,
                    evolutionChallenge: evolutionChallenge,
                    journey: WalkingJourneyProjection(
                        comparison: WalkingPlanComparison(baselineSteps: baselineDailySteps, targetSteps: recommendedGoal),
                        discoverySteps: store.catalog.discoveryStepCosts),
                    onBack: { draft.chatStep = .name; transition(to: .chat) },
                    onContinue: {
                        draft.completedConnections = true
                        transition(to: .commitment)
                    }
                )
            case .commitment:
                CommitmentView(
                    playerName: displayName,
                    copy: OnboardingCopy.forGoals(draft.selectedGoals, primaryGoal: draft.primaryGoal),
                    egg: commitmentEgg,
                    onBack: { transition(to: .plan) },
                    onCommitted: completeOnboarding
                )
            }
        }
        .preferredColorScheme(.dark)
        .task {
            OnboardingStoryMedia.prefetch()
            await ProfessorNanoPose.prefetchArtwork(animationsEnabled: !reduceMotion && !store.reduceMotion)
        }
        .onChange(of: draft) { _, value in
            onDraftChanged?(value)
            guard !isPreview else { return }
            value.save()
            Task { await NanoNotifications.shared.scheduleOnboardingReminders(
                name: value.playerName, planReady: value.reachedPaywall,
                completed: store.onboardingCompleted, premium: store.isPremium
            ) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                if setupReminders && !isPreview {
                    Button("Turn off setup reminders") {
                        NanoNotifications.shared.setSetupReminderPreference(false)
                        setupReminders = false
                    }.frame(minHeight: 44)
                }
                Spacer()
                Menu {
                    Button(restoring ? "Restoring…" : "Restore purchases") {
                        Task { await restorePurchases() }
                    }.disabled(restoring)
                    Link("Privacy policy", destination: URL(string: "https://nanobeasts.app/privacy")!)
                    Link("Terms", destination: URL(string: "https://nanobeasts.app/terms")!)
                    Link("Support", destination: URL(string: "https://nanobeasts.app/support")!)
                } label: {
                    Label { Text("Options") } icon: { SolarImage(.more) }.frame(minHeight: 44)
                }
            }
            .font(.caption).foregroundStyle(NanoTheme.secondaryText)
            .padding(.horizontal, 22).background(NanoTheme.background)
        }
        .alert("Restore purchases", isPresented: Binding(get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } })) {
            Button("OK") { restoreMessage = nil }
        } message: { Text(restoreMessage ?? "") }
    }

    private func restorePurchases() async {
        guard !isPreview else {
            restoreMessage = "Restore is simulated in this preview. Your existing subscription is unchanged."
            return
        }
        guard !restoring, Purchases.isConfigured else { return }
        restoring = true
        defer { restoring = false }
        do {
            await store.applyRevenueCatCustomerInfo(try await Purchases.shared.restorePurchases())
            restoreMessage = store.isPremium
                ? "Pro is restored. Finish personalizing your journey; you won’t need to subscribe again."
                : "No active subscription was found for this Apple Account."
        } catch { restoreMessage = "Couldn’t restore right now. Check your connection and try again." }
    }

    private var displayName: String { draft.displayName }

    private var baselineDailySteps: Int { draft.baselineSteps }

    private func transition(to next: OnboardingPhase) {
        nameIsFocused = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .snappy(duration: 0.26, extraBounce: 0.03)) {
            draft.phase = next
        }
    }

    private func completeOnboarding() {
        draft.reachedPaywall = true
        if !isPreview { draft.save() }
        onFinished(
            OnboardingProfile(
                playerName: displayName,
                selectedGoals: draft.selectedGoals,
                primaryGoal: draft.goalSelection.primary?.rawValue,
                selectedBlockers: draft.selectedBlockers,
                dailyGoal: recommendedGoal,
                wantsHealth: draft.wantsHealth,
                wantsReminders: draft.wantsReminders
            )
        )
    }
}

private struct OnboardingOption: Identifiable {
    let title: String
    let detail: String
    var value: String? = nil
    var id: String { value ?? title }

    var symbol: SolarIcon? {
        switch value ?? title {
        case "Walk More": .walking
        case "Lose Weight": .walking
        case "Get Fit": .dumbbell
        case "Collect Creatures": .paw
        default: nil
        }
    }
}

private let goalOptions = WalkingMotivation.allCases.map {
    OnboardingOption(title: $0.title, detail: $0.detail, value: $0.rawValue)
}

private let blockerOptions = [
    OnboardingOption(title: "Hard to stay consistent", detail: "Starting strong but fading fast"),
    OnboardingOption(title: "Walking feels boring", detail: "Nothing to look forward to"),
    OnboardingOption(title: "No way to track progress", detail: "Can’t see if it’s actually working"),
    OnboardingOption(title: "Forget to move", detail: "The day slips by without steps"),
    OnboardingOption(title: "Don’t see results fast enough", detail: "Motivation drops when progress feels invisible")
]

private let walkingRoutineOptions = WalkingRoutine.allCases.map {
    OnboardingOption(title: $0.title, detail: $0.detail, value: $0.rawValue)
}

/// The evolution screen sits a few steps into onboarding. Downloading and decoding
/// its clip as onboarding opens means it plays the instant the screen appears,
/// instead of after a 2.4 MB download plus an 81-frame decode.
enum OnboardingStoryMedia {
    @MainActor static func prefetch() {
        _ = SDWebImagePrefetcher.shared.prefetchURLs(
            [R2TransitionManifest.onboardingGlitchletEvolutionURL],
            options: [.highPriority, .preloadAllFrames],
            context: [.animatedImageClass: SDAnimatedImage.self],
            progress: nil,
            completed: nil
        )
    }
}

enum OnboardingDemoMedia {
    /// v3 matches the landing page cut: no baked-in progress rail or label, so the
    /// in-app countdown can sit in the top-right corner.
    static let url = R2AssetManifest.baseURL
        .appending(path: "videos/onboarding/nanobeasts-field-demo-v3.mp4")
    static let aspectRatio: CGFloat = 1080.0 / 1666.0
}

private struct FieldDemoView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var isRevealed = false
    @State private var isOnScreen = false
    @State private var videoState = DemoVideoState.loading
    @State private var secondsRemaining: Int?
    let onStart: () -> Void

    private var reduceMotion: Bool { systemReduceMotion || store.reduceMotion }

    var body: some View {
        FieldDemoPresentation(isRevealed: isRevealed, reduceMotion: reduceMotion, onStart: onStart) {
            ZStack {
                RemoteLoopingVideoView(
                    url: OnboardingDemoMedia.url,
                    isPlaying: isRevealed && isOnScreen && scenePhase == .active,
                    state: $videoState,
                    onSecondsRemaining: { secondsRemaining = $0 }
                )
                if videoState == .ready, let secondsRemaining {
                    DemoCountdownOverlay(seconds: secondsRemaining)
                }
                if videoState == .loading {
                    ProgressView().tint(NanoTheme.teal)
                } else if videoState == .failed {
                    VStack(spacing: 10) {
                        SolarImage(.danger, size: 28)
                        Text("The demo couldn’t load.")
                        Text("You can still start your journey.").font(.caption)
                    }
                    .foregroundStyle(NanoTheme.secondaryText)
                    .multilineTextAlignment(.center).padding(20)
                }
            }
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .task(id: scenePhase) {
            guard scenePhase == .active, !isRevealed else { return }
            do {
                // Give the opening message time to land before revealing or playing the demo.
                try await Task.sleep(for: .milliseconds(500))
                try Task.checkCancellation()
                withAnimation(reduceMotion ? .easeOut(duration: 0.25)
                    : .spring(response: 0.55, dampingFraction: 0.88)) {
                    isRevealed = true
                }
            } catch { /* Leaving the screen cancels the entrance. */ }
        }
    }
}

private struct FieldDemoPresentation<Demo: View>: View {
    let isRevealed: Bool
    let reduceMotion: Bool
    let onStart: () -> Void
    @ViewBuilder let demo: () -> Demo
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 30

    var body: some View {
        GeometryReader { page in
            ScrollView {
                VStack(spacing: 18) {
                    GeometryReader { space in
                        let height = min(space.size.height, (space.size.width - 48) * 16 / 9)
                        demo()
                            .frame(width: height * 9 / 16, height: height)
                            .background(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .stroke(NanoTheme.teal.opacity(0.24), lineWidth: 1.5))
                            .shadow(color: NanoTheme.teal.opacity(0.14), radius: 20)
                            .scaleEffect(isRevealed || reduceMotion ? 1 : 0.9, anchor: .bottom)
                            .rotationEffect(.degrees(isRevealed || reduceMotion ? 0 : 5))
                            .offset(x: isRevealed || reduceMotion ? 0 : 24,
                                    y: isRevealed || reduceMotion ? 0 : 100)
                            .opacity(isRevealed ? 1 : 0)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: max(160, min(590, page.size.height - 232)))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                    Spacer(minLength: 0)

                    openingCopy
                    startButton
                }
                .padding(.vertical, 12)
                .frame(minHeight: page.size.height)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var openingCopy: some View {
        VStack(spacing: 10) {
            Text("Walk toward a healthier body.")
                .font(.system(size: headlineSize, weight: .bold, design: .rounded))
                .tracking(-0.5)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Evolve together, one step at a time.")
                .font(.subheadline)
                .foregroundStyle(NanoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .layoutPriority(1)
    }

    private var startButton: some View {
        Button(action: onStart) {
            Text("Start my transformation")
                .font(.headline)
                .foregroundStyle(Color.black)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    LinearGradient(
                        colors: [NanoTheme.teal, NanoTheme.cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .layoutPriority(1)
    }
}

enum DemoVideoState { case loading, ready, failed }

/// Time left in the demo loop, matching the landing page, so it's clear how long
/// the video runs. Pinned to the video's own rect, not the letterboxed frame.
struct DemoCountdownOverlay: View {
    let seconds: Int

    var body: some View {
        Color.clear
            .aspectRatio(OnboardingDemoMedia.aspectRatio, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                    .font(NanoFont.aldrich(13))
                    .monospacedDigit()
                    .tracking(0.5)
                    .foregroundStyle(NanoTheme.teal)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.035, green: 0.035, blue: 0.043), in: Capsule())
                    .overlay(Capsule().stroke(Color(red: 0.153, green: 0.153, blue: 0.165), lineWidth: 1))
                    .padding(10)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct RemoteLoopingVideoView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    @Binding var state: DemoVideoState
    var loopDuration: TimeInterval? = nil
    /// Whole seconds left in the current loop, for an on-screen countdown.
    var onSecondsRemaining: ((Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator { state = $0 }
    }

    func makeUIView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = context.coordinator.player
        context.coordinator.onSecondsRemaining = onSecondsRemaining
        context.coordinator.attach(to: view.playerLayer)
        context.coordinator.prepare(url: url, loopDuration: loopDuration)
        context.coordinator.setPlaying(isPlaying)
        return view
    }

    func updateUIView(_ view: LoopingPlayerView, context: Context) {
        context.coordinator.onStateChange = { state = $0 }
        context.coordinator.onSecondsRemaining = onSecondsRemaining
        if context.coordinator.url != url || context.coordinator.loopDuration != loopDuration {
            context.coordinator.prepare(url: url, loopDuration: loopDuration)
        }
        context.coordinator.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ view: LoopingPlayerView, coordinator: Coordinator) {
        coordinator.stop()
        view.playerLayer.player = nil
    }

    @MainActor final class Coordinator {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        var url: URL?
        var loopDuration: TimeInterval?
        var onStateChange: (DemoVideoState) -> Void
        var onSecondsRemaining: ((Int) -> Void)?
        private var timeObserver: Any?
        private var lastSecondsRemaining: Int?
        private var isPlaying = false
        private var isAttached = false
        private var displayObservation: NSKeyValueObservation?
        private var itemObservation: NSKeyValueObservation?
        private var statusObservation: NSKeyValueObservation?

        init(onStateChange: @escaping (DemoVideoState) -> Void) {
            self.onStateChange = onStateChange
            player.isMuted = true
            player.volume = 0
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = true
        }

        func attach(to layer: AVPlayerLayer) {
            isAttached = true
            displayObservation = layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                guard layer.isReadyForDisplay else { return }
                DispatchQueue.main.async {
                    guard let self, self.isAttached else { return }
                    self.onStateChange(.ready)
                }
            }
            itemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.observeCurrentItem() }
            }
            // The looper swaps in a fresh item each pass, so currentTime restarts at zero per loop.
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(value: 1, timescale: 4), queue: .main
            ) { [weak self] time in
                MainActor.assumeIsolated { self?.publishRemaining(at: time) }
            }
        }

        private func publishRemaining(at time: CMTime) {
            guard let onSecondsRemaining, let item = player.currentItem else { return }
            let duration = loopDuration ?? item.duration.seconds
            guard duration.isFinite, duration > 0, time.seconds.isFinite else { return }
            let remaining = max(0, Int(ceil(duration - time.seconds)))
            guard remaining != lastSecondsRemaining else { return }
            lastSecondsRemaining = remaining
            onSecondsRemaining(remaining)
        }

        private func observeCurrentItem() {
            guard isAttached else { return }
            statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                let status = item.status
                DispatchQueue.main.async {
                    guard let self, self.isAttached else { return }
                    if status == .failed {
                        self.onStateChange(.failed)
                    } else if status == .readyToPlay, !self.isPlaying {
                        // Decode the opening frames during the brief title pause.
                        // Preroll prepares playback without advancing the demo.
                        self.player.preroll(atRate: 1) { _ in }
                    }
                }
            }
        }

        func prepare(url: URL, loopDuration: TimeInterval? = nil) {
            self.url = url
            self.loopDuration = loopDuration
            isPlaying = false
            player.pause()
            looper = nil
            player.removeAllItems()
            let item = AVPlayerItem(asset: AVURLAsset(url: url))
            item.preferredForwardBufferDuration = 1
            if let loopDuration {
                let range = CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: loopDuration, preferredTimescale: 600)
                )
                looper = AVPlayerLooper(player: player, templateItem: item, timeRange: range)
            } else {
                looper = AVPlayerLooper(player: player, templateItem: item)
            }
            // Prepare the remote asset without playing behind the opening message.
        }

        func setPlaying(_ shouldPlay: Bool) {
            guard isPlaying != shouldPlay else { return }
            isPlaying = shouldPlay
            player.cancelPendingPrerolls()
            if shouldPlay { player.play() } else { player.pause() }
        }

        func stop() {
            isAttached = false
            if let timeObserver { player.removeTimeObserver(timeObserver) }
            timeObserver = nil
            player.cancelPendingPrerolls()
            displayObservation = nil
            itemObservation = nil
            statusObservation = nil
            setPlaying(false)
            looper = nil
            player.removeAllItems()
        }
    }
}

final class LoopingPlayerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private struct ChatMessage: Identifiable {
    enum Sender { case professor, user }
    let id: String
    let sender: Sender
    let text: String
    var muted = false
    var hasCreature = false
}

private struct ProfessorChatView: View {
    @Environment(AppStore.self) private var store
    @Binding var step: ChatStep
    @Binding var playerName: String
    @Binding var selectedGoals: Set<String>
    @Binding var primaryGoal: String?
    @Binding var selectedBlockers: Set<String>
    @Binding var activity: String?
    @Binding var currentSteps: String?
    @Binding var wantsHealth: Bool
    let creature: CreatureStage
    @FocusState.Binding var nameIsFocused: Bool
    let onBackToDemo: () -> Void
    let onComplete: () -> Void
    let isPreview: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var screenMessages: [ChatMessage] {
        let lines: [String]
        switch step {
        case .welcome:
            lines = ["Welcome! I’m Nano, the Nanobeast Professor.", "I study creatures that grow with your steps. Let’s answer a few quick questions and build a walking plan around you."]
        case .specimen:
            lines = ["This is a Nanobeast.", "Meet Glitchlet. Every Nanobeast has its own story, and your steps help it grow."]
        case .evolution:
            lines = ["When you reach your step milestones, they evolve.", "Watch Glitchlet become Devicore. The steps you take bring each evolution closer."]
        case .research:
            lines = ["Your steps bring this world to life.", "Here’s how it works. Every Field Dex discovery helps my research."]
        case .goal:
            lines = ["Why do you want to walk more?", "Choose all the reasons that matter to you."]
        case .focus:
            lines = ["Which matters most to you right now?", "We’ll build around this goal and keep your other reasons in mind."]
        case .blocker:
            lines = ["What gets in the way?", "Choose what sounds like you."]
        case .activity, .steps:
            lines = ["How much do you walk on a typical day?", "Choose the closest match. An estimate is fine."]
        case .name:
            lines = ["One last thing. What should I call you?", "Optional. Add your name, or we’ll call you Researcher. You can change it anytime in Settings."]
        case .health, .location, .reminders:
            lines = ["Let your everyday steps count.", "Count steps from your iPhone and Apple Watch, even when the app is closed. You choose what to share."]
        case .plan:
            lines = [OnboardingCopy.transition]
        }
        return lines.enumerated().map { ChatMessage(id: "\(step)-\($0.offset)", sender: .professor, text: $0.element, muted: $0.offset > 0) }
    }

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    NanoTheme.teal.opacity(0.18),
                    Color(red: 0.02, green: 0.12, blue: 0.16).opacity(0.72),
                    .clear
                ],
                center: .bottom,
                startRadius: 10,
                endRadius: 470
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                chatHeader

                Group {
                    if step.isStory {
                        introductionPage
                    } else {
                        questionPage
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if step != .health && step != .location && step != .reminders {
                        continueFooter
                    }
                }
            }
        }
    }

    private var introductionPage: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    if step == .research {
                        Text("Here’s how it works")
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("onboarding-question")
                        OnboardingDailyLoopPreview()
                    } else {
                        Spacer(minLength: 12)
                        questionHero(height: min(280, max(170, geometry.size.height * 0.5)))
                        questionPrompt
                    }
                    Spacer(minLength: 8)

                    if storyPageCount > 1, step != .research {
                        HStack(spacing: 6) {
                            ForEach(0..<storyPageCount, id: \.self) { index in
                                Capsule()
                                    .fill(index == storyPage ? NanoTheme.teal : Color.white.opacity(0.12))
                                    .frame(width: index == storyPage ? 24 : 7, height: 7)
                            }
                        }
                        .accessibilityLabel("Introduction page \(storyPage + 1) of \(storyPageCount)")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .id(step)
            .transition(.opacity)
        }
    }

    private var questionPage: some View {
        // The prompt and answers share one scroll view. A long answer list must
        // never reserve screen height at the expense of the question above it.
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if step == .name {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YOUR ANSWERS ARE IN")
                                .font(NanoFont.aldrich(10)).tracking(1.2)
                                .foregroundStyle(NanoTheme.teal)
                            Text("Let’s put it all together.")
                                .font(.title3.weight(.semibold))
                        }
                        Spacer(minLength: 12)
                        ProfessorNanoArtwork(pose: .research, height: 132)
                    }
                    .accessibilityElement(children: .combine)
                }
                questionPrompt
                answerChoices
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: selectedGoals) { previous, values in
            // Selecting the first checkbox isn't an answer to the later focus
            // question. Only preserve a main goal explicitly chosen from several.
            if WalkingMotivation.selected(in: previous).count <= 1,
               WalkingMotivation.selected(in: values).count > 1 {
                primaryGoal = nil
            } else if let primaryGoal, !values.contains(primaryGoal) {
                self.primaryGoal = nil
            }
        }
        .scrollDismissesKeyboard(.interactively)
        // Recreate the scroll position for each question, including Back, so a
        // previous page's scroll offset cannot hide the next prompt on arrival.
        .id(step)
        .transition(.opacity)
    }

    private var questionPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if step != .welcome {
                    SolarImage(questionIcon, size: 20)
                        .foregroundStyle(NanoTheme.teal)
                        .frame(width: 32, height: 32)
                        .background(NanoTheme.teal.opacity(0.09), in: Circle())
                        .accessibilityHidden(true)
                }

                Text(step.isStory ? step.title : "PROFESSOR NANO")
                    .font(NanoFont.aldrich(10))
                    .tracking(1.8)
                    .foregroundStyle(NanoTheme.teal)
            }

            Text(screenMessages.first?.text ?? "")
                .font(.system(.title, design: .rounded).weight(.bold))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding-question")

            if let detail = screenMessages.dropFirst().first?.text {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(NanoTheme.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pageAnimation: Animation? {
        reduceMotion || store.reduceMotion ? nil : .easeOut(duration: 0.22)
    }

    private var chatHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: back) {
                    SolarImage(.left)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .tint(NanoTheme.secondaryText)
                .accessibilityLabel("Back")

                VStack(alignment: .leading, spacing: 1) {
                    Text("NANOBEASTS")
                        .font(NanoFont.aldrich(9))
                        .tracking(1.5)
                        .foregroundStyle(NanoTheme.teal)
                    Text(step.chapter)
                        .font(NanoFont.aldrich(8))
                        .tracking(0.8)
                        .foregroundStyle(NanoTheme.secondaryText)
                }

                Spacer()

                Text(questionCounter)
                    .font(NanoFont.aldrich(11))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .contentTransition(.numericText())
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [NanoTheme.cyan, NanoTheme.teal],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * onboardingProgress)
                    }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.34))
    }

    @ViewBuilder
    private func questionHero(height: CGFloat) -> some View {
        if let pose = professorPose {
            ProfessorNanoArtwork(pose: pose, height: height)
                .id(pose)
                .transition(.opacity)
        } else if step == .specimen {
            AnimatedCreatureArtworkView(stage: creature)
                .frame(width: 188, height: 188)
                .accessibilityLabel("Glitchlet, a Nanobeast")
        } else if step == .evolution {
            RemoteAnimatedWebPView(
                url: R2TransitionManifest.onboardingGlitchletEvolutionURL,
                loopCount: 1,
                freezesOnLastFrame: true,
                preloadsAllFrames: true
            ) { _ in }
            .id("glitchlet-devicore-onboarding")
            .frame(width: 188, height: 188)
            .accessibilityLabel("Glitchlet evolving into Devicore")
        } else {
            SolarImage(questionIcon, size: 48)
                .foregroundStyle(
                    LinearGradient(
                        colors: [NanoTheme.cyan, NanoTheme.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 104, height: 104)
                .background(
                    Circle()
                        .fill(NanoTheme.teal.opacity(0.09))
                        .stroke(NanoTheme.teal.opacity(0.34), lineWidth: 1)
                )
                .shadow(color: NanoTheme.teal.opacity(0.24), radius: 24)
        }
    }

    private var professorPose: ProfessorNanoPose? {
        guard step == .welcome else { return nil }
        return .welcome
    }

    private var storyPageCount: Int { step == .welcome ? 1 : 3 }
    private var storyPage: Int {
        switch step {
        case .welcome: 0
        case .evolution: 1
        case .research: 2
        default: 0
        }
    }

    private var questionCounter: String {
        let questions: [ChatStep] = goalSelection.needsChoice ? [.goal, .focus, .blocker, .activity] : ChatStep.questions
        if let index = questions.firstIndex(of: step) { return "\(index + 1) / \(questions.count)" }
        if step == .welcome { return "WELCOME" }
        if step.isStory { return "\(storyPage + 1) / \(storyPageCount)" }
        return step == .name ? "YOUR PLAN" : "CONNECT"
    }

    private var onboardingProgress: Double {
        step.progress(needsFocus: goalSelection.needsChoice)
    }

    private var questionIcon: SolarIcon {
        switch step {
        case .welcome: .stars
        case .name: .user
        case .goal, .focus: .target
        case .blocker: .bolt
        case .activity: .walking
        case .steps: .walking
        case .health: .health
        case .reminders: .bell
        case .plan: .magic
        case .specimen: .paw
        case .evolution: .stars
        case .research: .book
        case .location: .location
        }
    }

    @ViewBuilder
    private var answerChoices: some View {
        switch step {
        case .welcome, .specimen, .evolution, .research, .plan:
            EmptyView()
        case .name:
            TextField("Your name (optional)", text: $playerName)
                .textContentType(.nickname)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($nameIsFocused)
                .padding(14)
                .background(NanoTheme.elevated, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(nameIsFocused ? NanoTheme.cyan : NanoTheme.border, lineWidth: 1)
                )
                .onSubmit(continueChat)
        case .goal:
            ChoiceList(options: goalOptions, selection: $selectedGoals)
        case .focus:
            SingleChoiceList(options: goalOptions.filter { selectedGoals.contains($0.id) }, selection: $primaryGoal)
        case .blocker:
            ChoiceList(options: blockerOptions, selection: $selectedBlockers)
        case .activity, .steps:
            SingleChoiceList(options: walkingRoutineOptions, selection: Binding(
                get: { currentSteps },
                set: { value in
                    currentSteps = value
                    activity = value.flatMap { WalkingRoutine(rawValue: $0)?.activity }
                }
            ))
        case .health, .location, .reminders:
            PermissionChoices(
                primaryTitle: "Use Apple Health",
                primaryDetail: "Best for background steps and Apple Watch.",
                secondaryTitle: "Not now",
                secondaryDetail: "You can turn it on later in Settings."
            ) { enabled in
                wantsHealth = enabled
                advance()
            }
        }
    }

    private var continueFooter: some View {
        Button(action: continueChat) {
            Text(
                step == .welcome
                    ? "LET’S FIND YOUR START"
                    : step == .name || step == .plan ? "BUILD MY WALKING PLAN" : step.isStory ? "CONTINUE" : "NEXT"
            )
            .font(NanoFont.aldrich(14))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(NanoTheme.cyan)
        .foregroundStyle(.black)
        .disabled(!canContinue)
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(Color.black.opacity(0.42))
    }

    private var canContinue: Bool {
        switch step {
        case .name: true
        case .goal: !selectedGoals.isEmpty
        case .focus: goalSelection.primary != nil
        case .blocker: !selectedBlockers.isEmpty
        case .activity, .steps: currentSteps != nil && activity != nil
        default: true
        }
    }

    private func continueChat() {
        guard canContinue else { return }
        if step == .plan || step == .name {
            onComplete()
        } else {
            advance()
        }
    }

    private var goalSelection: WalkingGoalSelection { .init(values: selectedGoals, preferred: primaryGoal) }

    private func advance() {
        if step == .goal && !goalSelection.needsChoice { primaryGoal = goalSelection.primary?.rawValue }
        if step.current == .health { onComplete(); return }
        guard let next = step.next(needsFocus: goalSelection.needsChoice) else { return }
        nameIsFocused = false
        withAnimation(pageAnimation) {
            step = next
        }
    }

    private func back() {
        guard step.current != .health, let previous = step.previous(needsFocus: goalSelection.needsChoice) else {
            onBackToDemo()
            return
        }
        nameIsFocused = false
        withAnimation(pageAnimation) {
            step = previous
        }
    }

}

private struct ChoiceList: View {
    let options: [OnboardingOption]
    @Binding var selection: Set<String>

    var body: some View {
        VStack(spacing: 8) {
            ForEach(options) { option in
                OptionRow(option: option, selected: selection.contains(option.id), multiple: true) {
                    if selection.contains(option.id) {
                        selection.remove(option.id)
                    } else {
                        selection.insert(option.id)
                    }
                }
            }
        }
    }
}

private struct SingleChoiceList: View {
    let options: [OnboardingOption]
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(options) { option in
                OptionRow(option: option, selected: selection == option.id, multiple: false) {
                    selection = option.id
                }
            }
        }
    }
}

private struct OptionRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppStore.self) private var store
    let option: OnboardingOption
    let selected: Bool
    let multiple: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let symbol = option.symbol {
                    SolarImage(symbol, size: 22)
                        .foregroundStyle(selected ? Color.black : NanoTheme.teal)
                        .frame(width: 36, height: 40)
                        .background(selected ? NanoTheme.teal : NanoTheme.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(NanoFont.aldrich(14))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(option.detail)
                        .font(.caption)
                        .foregroundStyle(NanoTheme.secondaryText)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Group {
                    if selected {
                        SolarImage(.checkCircle, size: 24).foregroundStyle(NanoTheme.teal)
                    } else {
                        Circle().stroke(NanoTheme.border, lineWidth: 1)
                            .frame(width: 22, height: 22)
                    }
                }
                .frame(minWidth: 24, minHeight: 24)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .background(
                selected ? NanoTheme.teal.opacity(0.10) : NanoTheme.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? NanoTheme.teal.opacity(0.68) : NanoTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(reduceMotion || store.reduceMotion ? nil : .easeOut(duration: 0.2), value: selected)
    }
}

private struct PermissionChoices: View {
    let primaryTitle: String
    let primaryDetail: String
    let secondaryTitle: String
    let secondaryDetail: String
    let onSelect: (Bool) -> Void

    var body: some View {
        VStack(spacing: 8) {
            OptionRow(
                option: OnboardingOption(title: primaryTitle, detail: primaryDetail),
                selected: false,
                multiple: false
            ) { onSelect(true) }
            OptionRow(
                option: OnboardingOption(title: secondaryTitle, detail: secondaryDetail),
                selected: false,
                multiple: false
            ) { onSelect(false) }
        }
    }
}

private struct CommitmentView: View {
    let playerName: String
    let copy: OnboardingCopy
    let egg: CreatureStage
    let onBack: () -> Void
    let onCommitted: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var holdProgress = 0.0
    @State private var isHolding = false
    @State private var committed = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered)
                    .tint(NanoTheme.secondaryText)
                Spacer()
                Text("YOUR COMMITMENT")
                    .font(NanoFont.aldrich(11))
                    .tracking(1.5)
                    .foregroundStyle(NanoTheme.teal)
            }
            .padding(18)

            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 10) {
                        Text(copy.commitmentPromise(name: playerName))
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text(OnboardingCopy.eggDetail)
                            .font(.title3)
                            .foregroundStyle(NanoTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 24)

                    ZStack {
                        ForEach(0..<3) { ring in
                            Circle()
                                .stroke(NanoTheme.teal.opacity(0.10 - Double(ring) * 0.02), lineWidth: 1)
                                .frame(width: CGFloat(270 + ring * 32), height: CGFloat(270 + ring * 32))
                                .scaleEffect(isHolding ? 1.04 : 0.96)
                                .animation(
                                    .easeInOut(duration: 0.85 + Double(ring) * 0.2).repeatForever(autoreverses: true),
                                    value: isHolding
                                )
                        }

                        Circle()
                            .stroke(Color.white.opacity(0.09), lineWidth: 12)
                            .frame(width: 270, height: 270)
                        Circle()
                            .trim(from: 0, to: holdProgress)
                            .stroke(
                                AngularGradient(
                                    colors: [NanoTheme.cyan, NanoTheme.teal, NanoTheme.purple, NanoTheme.cyan],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 270, height: 270)
                            .shadow(color: NanoTheme.teal.opacity(0.65), radius: 14)

                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [NanoTheme.teal.opacity(isHolding ? 0.22 : 0.08), .clear],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 130
                                )
                            )
                            .frame(width: 250, height: 250)

                        AnimatedCreatureArtworkView(stage: egg)
                            .frame(width: 185, height: 185)
                            .scaleEffect(isHolding ? 1.06 : 1)
                            .rotationEffect(.degrees(isHolding ? 1.5 : -1.5))
                    }
                    .contentShape(Circle())
                    .gesture(holdGesture)
                    .accessibilityLabel(OnboardingCopy.eggInstruction)
                    .accessibilityAddTraits(.isButton)

                    VStack(spacing: 8) {
                        Text(committed ? OnboardingCopy.eggConfirmed : OnboardingCopy.eggInstruction)
                            .font(NanoFont.aldrich(14))
                            .foregroundStyle(committed ? NanoTheme.teal : .white)
                        Text(committed ? "" : "Keep your finger on the egg until the energy ring closes.")
                            .font(.caption)
                            .foregroundStyle(NanoTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 30)
                }
                .padding(.vertical, 18)
            }
        }
        .onDisappear {
            holdTask?.cancel()
        }
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isHolding, !committed else { return }
                beginHold()
            }
            .onEnded { _ in
                guard !committed else { return }
                cancelHold()
            }
    }

    private func beginHold() {
        isHolding = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.linear(duration: reduceMotion ? 0.25 : 2)) {
            holdProgress = 1
        }

        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.25 : 1))
            guard !Task.isCancelled else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            committed = true
            isHolding = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            onCommitted()
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            holdProgress = 0
        }
    }
}
