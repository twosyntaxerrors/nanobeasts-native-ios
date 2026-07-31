import AVFoundation
import Charts
import SwiftUI
import UIKit

struct OnboardingProfile {
    let playerName: String
    let dailyGoal: Int
    let wantsHealth: Bool
    let wantsReminders: Bool
}

struct OnboardingFlowView: View {
    @Environment(AppStore.self) private var store

    let onFinished: (OnboardingProfile) -> Void

    @State private var phase: OnboardingPhase = .demo
    @State private var chatStep: ChatStep = .welcome
    @State private var playerName = ""
    @State private var selectedGoals: Set<String> = []
    @State private var selectedBlockers: Set<String> = []
    @State private var activity: String?
    @State private var currentSteps: String?
    @State private var wantsHealth = true
    @State private var wantsReminders = false
    @State private var planProgress = 0
    @FocusState private var nameIsFocused: Bool

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

    private var recommendedGoal: Int {
        var base: Int
        switch activity {
        case "Sedentary": base = 3_500
        case "Moderately Active": base = 5_500
        case "Very Active": base = 7_500
        default: base = 4_500
        }

        if selectedGoals.contains("Lose Weight") {
            base += 750
        } else if selectedGoals.contains("Get Fit") {
            base += 750
        } else if selectedGoals.contains("Walk More") {
            base += 500
        }

        switch currentSteps {
        case "Under 2,000":
            base = min(base, 4_000)
        case "2,000 – 5,000":
            base = min(max(base, 4_000), 5_500)
        case "5,000 – 8,000":
            base = min(max(base, 6_000), 7_500)
        case "8,000+":
            base = min(max(base, 8_000), 9_500)
        default:
            break
        }

        return min(
            max(Int((Double(base) / 500).rounded()) * 500, 2_500),
            9_500
        )
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            switch phase {
            case .demo:
                FieldDemoView {
                    transition(to: .chat)
                }
            case .chat:
                ProfessorChatView(
                    step: $chatStep,
                    playerName: $playerName,
                    selectedGoals: $selectedGoals,
                    selectedBlockers: $selectedBlockers,
                    activity: $activity,
                    currentSteps: $currentSteps,
                    wantsHealth: $wantsHealth,
                    wantsReminders: $wantsReminders,
                    creature: glitchlet,
                    nameIsFocused: $nameIsFocused,
                    onBackToDemo: { transition(to: .demo) },
                    onComplete: { transition(to: .profile) }
                )
            case .profile:
                MovementProfileView(
                    playerName: displayName,
                    baseline: currentSteps ?? "Under 2,000",
                    goal: selectedGoals.first ?? "more daily movement",
                    blocker: selectedBlockers.first ?? "Walking feels boring",
                    onBack: { transition(to: .chat) },
                    onContinue: { transition(to: .projection) }
                )
            case .projection:
                ProjectedPathView(
                    baselineSteps: baselineDailySteps,
                    targetSteps: recommendedGoal,
                    onBack: { transition(to: .profile) },
                    onContinue: {
                        planProgress = 0
                        transition(to: .building)
                    }
                )
            case .building:
                PlanBuilderView(
                    playerName: displayName,
                    progress: $planProgress
                ) {
                    transition(to: .plan)
                }
            case .plan:
                FieldPlanView(
                    playerName: displayName,
                    targetSteps: recommendedGoal,
                    onBack: { transition(to: .projection) },
                    onContinue: { transition(to: .commitment) }
                )
            case .commitment:
                CommitmentView(
                    playerName: displayName,
                    egg: commitmentEgg,
                    onBack: { transition(to: .plan) },
                    onCommitted: completeOnboarding
                )
            }
        }
        .preferredColorScheme(.dark)
    }

    private var displayName: String {
        let value = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Researcher" : value
    }

    private var baselineDailySteps: Int {
        switch currentSteps {
        case "Under 2,000": 1_500
        case "2,000 – 5,000": 3_500
        case "5,000 – 8,000": 6_500
        case "8,000+": 9_000
        default: 1_500
        }
    }

    private func transition(to next: OnboardingPhase) {
        nameIsFocused = false
        withAnimation(.snappy(duration: 0.42, extraBounce: 0.06)) {
            phase = next
        }
    }

    private func completeOnboarding() {
        onFinished(
            OnboardingProfile(
                playerName: displayName,
                dailyGoal: recommendedGoal,
                wantsHealth: wantsHealth,
                wantsReminders: wantsReminders
            )
        )
    }
}

private enum OnboardingPhase {
    case demo
    case chat
    case profile
    case projection
    case building
    case plan
    case commitment
}

private enum ChatStep: Int, CaseIterable {
    case welcome
    case name
    case goal
    case blocker
    case activity
    case steps
    case health
    case reminders
    case plan

    var title: String {
        switch self {
        case .welcome: "WELCOME"
        case .name: "NAME"
        case .goal: "GOAL"
        case .blocker: "BLOCKER"
        case .activity: "ACTIVITY"
        case .steps: "STEPS"
        case .health: "HEALTH"
        case .reminders: "REMINDERS"
        case .plan: "PLAN"
        }
    }

    var progress: Double {
        Double(rawValue + 1) / Double(Self.allCases.count)
    }
}

private struct OnboardingOption: Identifiable {
    let title: String
    let detail: String
    var id: String { title }
}

private let goalOptions = [
    OnboardingOption(title: "Walk More", detail: "Build a daily walking habit"),
    OnboardingOption(title: "Lose Weight", detail: "Burn calories through movement"),
    OnboardingOption(title: "Collect Creatures", detail: "Build your collection through walking"),
    OnboardingOption(title: "Get Fit", detail: "Build a stronger, healthier body"),
    OnboardingOption(title: "Have Fun", detail: "Make walking feel like a game")
]

private let blockerOptions = [
    OnboardingOption(title: "Hard to stay consistent", detail: "Starting strong but fading fast"),
    OnboardingOption(title: "Walking feels boring", detail: "Nothing to look forward to"),
    OnboardingOption(title: "No way to track progress", detail: "Can’t see if it’s actually working"),
    OnboardingOption(title: "Forget to move", detail: "The day slips by without steps"),
    OnboardingOption(title: "Don’t see results fast enough", detail: "Motivation drops when progress feels invisible")
]

private let activityOptions = [
    OnboardingOption(title: "Sedentary", detail: "Mostly sitting — desk job or limited movement"),
    OnboardingOption(title: "Lightly Active", detail: "Light movement, occasional walks"),
    OnboardingOption(title: "Moderately Active", detail: "Regular daily movement"),
    OnboardingOption(title: "Very Active", detail: "High activity throughout the day")
]

private let stepOptions = [
    OnboardingOption(title: "Under 2,000", detail: "Very low activity"),
    OnboardingOption(title: "2,000 – 5,000", detail: "Below average"),
    OnboardingOption(title: "5,000 – 8,000", detail: "Average range"),
    OnboardingOption(title: "8,000+", detail: "Above average")
]

private struct FieldDemoView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("NANOBEASTS FIELD DEMO")
                .font(NanoFont.aldrich(13))
                .tracking(2.4)
                .foregroundStyle(NanoTheme.teal)
                .padding(.top, 14)

            Spacer(minLength: 18)

            ZStack {
                RoundedRectangle(cornerRadius: 50, style: .continuous)
                    .fill(Color.black)
                    .stroke(NanoTheme.teal.opacity(0.24), lineWidth: 1.5)
                    .shadow(color: NanoTheme.teal.opacity(0.14), radius: 28)

                RemoteLoopingVideoView(
                    url: R2AssetManifest.baseURL
                        .appending(path: "videos/onboarding/nanobeasts-app-demo-showcase.mov")
                )
                .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
                .allowsHitTesting(false)
            }
            .frame(maxWidth: 365, maxHeight: 590)
            .padding(.horizontal, 24)

            Spacer(minLength: 18)

            Button(action: onStart) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(Color.black)
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
            .padding(.bottom, 12)
        }
    }
}

private struct RemoteLoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = context.coordinator.player
        context.coordinator.play(url: url)
        return view
    }

    func updateUIView(_ view: LoopingPlayerView, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.play(url: url)
    }

    static func dismantleUIView(_ view: LoopingPlayerView, coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.player.removeAllItems()
        coordinator.looper = nil
        view.playerLayer.player = nil
    }

    final class Coordinator {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        var url: URL?

        init() {
            player.isMuted = true
            player.volume = 0
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = true
        }

        func play(url: URL) {
            self.url = url
            player.pause()
            player.removeAllItems()
            let item = AVPlayerItem(asset: AVURLAsset(url: url))
            item.preferredForwardBufferDuration = 3
            looper = AVPlayerLooper(player: player, templateItem: item)
            player.play()
        }
    }
}

private final class LoopingPlayerView: UIView {
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
    @Binding var step: ChatStep
    @Binding var playerName: String
    @Binding var selectedGoals: Set<String>
    @Binding var selectedBlockers: Set<String>
    @Binding var activity: String?
    @Binding var currentSteps: String?
    @Binding var wantsHealth: Bool
    @Binding var wantsReminders: Bool
    let creature: CreatureStage
    @FocusState.Binding var nameIsFocused: Bool
    let onBackToDemo: () -> Void
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var welcomePage = 0
    @State private var visibleCount = 0
    @State private var professorTyping = false
    @State private var typingMessageID: String?
    @State private var typedCharacterCount = 0

    private var messages: [ChatMessage] {
        var result = [
            ChatMessage(id: "welcome-0", sender: .professor, text: "Welcome to Nanobeasts. I’m Nano, the Nanobeast Professor."),
            ChatMessage(id: "welcome-1", sender: .professor, text: "Nanobeasts live in your phone and evolve using energy from your steps."),
            ChatMessage(id: "welcome-2", sender: .professor, text: "This is what we call a Nanobeast.", hasCreature: true),
            ChatMessage(id: "welcome-3", sender: .professor, text: "Walk to help them hatch and evolve, so you can help me study them."),
            ChatMessage(id: "welcome-4", sender: .professor, text: "Before we start, I need to learn a bit more to personalize your experience.")
        ]

        if step.rawValue >= ChatStep.name.rawValue {
            result.append(ChatMessage(id: "name-prompt", sender: .professor, text: "First, what should I call you?"))
        }
        if step.rawValue > ChatStep.name.rawValue {
            addUser(playerName, id: "name-answer", to: &result)
        }
        if step.rawValue >= ChatStep.goal.rawValue {
            result.append(ChatMessage(id: "goal-prompt", sender: .professor, text: "What do you want walking to help with right now?"))
        }
        if step.rawValue > ChatStep.goal.rawValue {
            addUser(ordered(selection: selectedGoals, options: goalOptions).joined(separator: ", "), id: "goal-answer", to: &result)
        }
        if step.rawValue >= ChatStep.blocker.rawValue {
            result.append(ChatMessage(id: "blocker-prompt", sender: .professor, text: "What usually gets in the way?"))
        }
        if step.rawValue > ChatStep.blocker.rawValue {
            addUser(ordered(selection: selectedBlockers, options: blockerOptions).joined(separator: ", "), id: "blocker-answer", to: &result)
        }
        if step.rawValue >= ChatStep.activity.rawValue {
            result.append(ChatMessage(id: "activity-prompt", sender: .professor, text: "How active are you on a normal week?"))
        }
        if step.rawValue > ChatStep.activity.rawValue {
            addUser(activity, id: "activity-answer", to: &result)
        }
        if step.rawValue >= ChatStep.steps.rawValue {
            result.append(ChatMessage(id: "steps-prompt", sender: .professor, text: "About how many steps do you average per day?"))
        }
        if step.rawValue > ChatStep.steps.rawValue {
            addUser(currentSteps, id: "steps-answer", to: &result)
        }
        if step.rawValue >= ChatStep.health.rawValue {
            result.append(ChatMessage(id: "health-prompt", sender: .professor, text: "Want Nanobeasts to read your steps from Apple Health?"))
            result.append(ChatMessage(
                id: "health-context",
                sender: .professor,
                text: "Accept Apple Health sync so Nanobeasts can track steps from your iPhone and Apple Watch even while the app is closed. If you skip it, the app falls back to the iPhone pedometer, which only updates your journey while Nanobeasts is open.",
                muted: true
            ))
        }
        if step.rawValue > ChatStep.health.rawValue {
            addUser(wantsHealth ? "Use Apple Health" : "Not now", id: "health-answer", to: &result)
        }
        if step.rawValue >= ChatStep.reminders.rawValue {
            result.append(ChatMessage(id: "reminders-prompt", sender: .professor, text: "Want reminders only when they matter?"))
            result.append(ChatMessage(
                id: "reminders-context",
                sender: .professor,
                text: "Reminders only let you know when your Nanobeast is close to hatching or evolving. They are designed to be useful—not annoying or intrusive—and you can turn them on or off anytime in Settings.",
                muted: true
            ))
        }
        if step.rawValue > ChatStep.reminders.rawValue {
            addUser(wantsReminders ? "Enable reminders" : "Not now", id: "reminders-answer", to: &result)
        }
        if step == .plan {
            result.append(ChatMessage(id: "plan-prompt", sender: .professor, text: "Your starting target is ready."))
        }
        return result
    }

    private var screenMessages: [ChatMessage] {
        switch step {
        case .welcome:
            let welcome = messages.filter { $0.id.hasPrefix("welcome-") }
            guard !welcome.isEmpty else { return [] }
            return [welcome[min(welcomePage, welcome.count - 1)]]
        case .name:
            return messages.filter { $0.id == "name-prompt" }
        case .goal:
            return messages.filter { $0.id == "goal-prompt" }
        case .blocker:
            return messages.filter { $0.id == "blocker-prompt" }
        case .activity:
            return messages.filter { $0.id == "activity-prompt" }
        case .steps:
            return messages.filter { $0.id == "steps-prompt" }
        case .health:
            return messages.filter { $0.id == "health-prompt" || $0.id == "health-context" }
        case .reminders:
            return messages.filter { $0.id == "reminders-prompt" || $0.id == "reminders-context" }
        case .plan:
            return messages.filter { $0.id == "plan-prompt" }
        }
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

                VStack(spacing: 18) {
                    Spacer(minLength: 12)

                    questionHero

                    VStack(alignment: .leading, spacing: 12) {
                        Text(step.title)
                            .font(NanoFont.aldrich(10))
                            .tracking(1.8)
                            .foregroundStyle(NanoTheme.teal)

                        Text(screenMessages.first?.text ?? "")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .lineSpacing(2)
                            .minimumScaleFactor(0.78)
                            .fixedSize(horizontal: false, vertical: true)

                        if let detail = screenMessages.dropFirst().first?.text {
                            Text(detail)
                                .font(NanoFont.aldrich(12))
                                .foregroundStyle(NanoTheme.secondaryText)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("\(step.rawValue)-\(welcomePage)")
                    .transition(.move(edge: .trailing).combined(with: .opacity))

                    Spacer(minLength: 8)

                    if step == .welcome {
                        HStack(spacing: 6) {
                            ForEach(0..<5, id: \.self) { index in
                                Capsule()
                                    .fill(index == welcomePage ? NanoTheme.teal : Color.white.opacity(0.12))
                                    .frame(width: index == welcomePage ? 24 : 7, height: 7)
                            }
                        }
                        .animation(.snappy(duration: 0.26), value: welcomePage)
                    }
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                composer
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.snappy(duration: 0.38, extraBounce: 0.03), value: step)
        .animation(.snappy(duration: 0.38, extraBounce: 0.03), value: welcomePage)
    }

    private var chatHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .tint(NanoTheme.secondaryText)

                VStack(alignment: .leading, spacing: 1) {
                    Text("NANOBEASTS")
                        .font(NanoFont.aldrich(9))
                        .tracking(1.5)
                        .foregroundStyle(NanoTheme.teal)
                    Text("PERSONALIZED FIELD SETUP")
                        .font(NanoFont.aldrich(8))
                        .tracking(0.8)
                        .foregroundStyle(NanoTheme.secondaryText)
                }

                Spacer()

                Text("\(Int(onboardingProgress * 100))%")
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
    private var questionHero: some View {
        if step == .welcome, welcomePage == 2 {
            AnimatedCreatureArtworkView(stage: creature)
                .frame(width: 150, height: 150)
        } else if step == .welcome, welcomePage == 3 {
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
            Image(systemName: questionSymbol)
                .font(.system(size: 44, weight: .semibold))
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

    private var onboardingProgress: Double {
        let welcomeFraction = step == .welcome ? Double(welcomePage + 1) / 5 : 1
        return min((Double(step.rawValue) + welcomeFraction) / Double(ChatStep.allCases.count), 1)
    }

    private var questionSymbol: String {
        switch step {
        case .welcome: "sparkles"
        case .name: "person.crop.circle"
        case .goal: "scope"
        case .blocker: "bolt.slash.fill"
        case .activity: "figure.walk.motion"
        case .steps: "shoeprints.fill"
        case .health: "heart.text.square.fill"
        case .reminders: "bell.badge.fill"
        case .plan: "wand.and.stars"
        }
    }

    @ViewBuilder
    private var composer: some View {
        VStack(spacing: 10) {
            Group {
                switch step {
                case .welcome, .plan:
                    EmptyView()
                case .name:
                    TextField("Type your name", text: $playerName)
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
                case .blocker:
                    ChoiceList(options: blockerOptions, selection: $selectedBlockers)
                case .activity:
                    SingleChoiceList(options: activityOptions, selection: $activity)
                case .steps:
                    SingleChoiceList(options: stepOptions, selection: $currentSteps)
                case .health:
                    PermissionChoices(
                        primaryTitle: "Use Apple Health",
                        primaryDetail: "Best for background steps and Apple Watch.",
                        secondaryTitle: "Not now",
                        secondaryDetail: "You can turn it on later in Settings."
                    ) { enabled in
                        wantsHealth = enabled
                        advance()
                    }
                case .reminders:
                    PermissionChoices(
                        primaryTitle: "Enable reminders",
                        primaryDetail: "Only for useful progress nudges.",
                        secondaryTitle: "Not now",
                        secondaryDetail: "No reminders unless you turn them on later."
                    ) { enabled in
                        wantsReminders = enabled
                        advance()
                    }
                }
            }

            if step != .health && step != .reminders {
                Button(action: continueChat) {
                    Text(
                        step == .welcome
                            ? welcomePage == 4 ? "START PERSONALIZING" : "CONTINUE"
                            : step == .plan ? "BUILD MY PLAN" : "NEXT"
                    )
                    .font(NanoFont.aldrich(14))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(NanoTheme.cyan)
                .foregroundStyle(.black)
                .disabled(!canContinue)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(Color.black.opacity(0.42))
    }

    private var canContinue: Bool {
        switch step {
        case .name: !playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .goal: !selectedGoals.isEmpty
        case .blocker: !selectedBlockers.isEmpty
        case .activity: activity != nil
        case .steps: currentSteps != nil
        default: true
        }
    }

    private func ordered(selection: Set<String>, options: [OnboardingOption]) -> [String] {
        options.map(\.title).filter(selection.contains)
    }

    private func addUser(_ value: String?, id: String, to messages: inout [ChatMessage]) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messages.append(ChatMessage(id: id, sender: .user, text: value))
    }

    private func continueChat() {
        guard canContinue else { return }
        if step == .welcome, welcomePage < 4 {
            withAnimation(.snappy(duration: 0.34)) {
                welcomePage += 1
            }
        } else if step == .plan {
            onComplete()
        } else {
            advance()
        }
    }

    private func advance() {
        guard let next = ChatStep(rawValue: step.rawValue + 1) else { return }
        nameIsFocused = false
        withAnimation(.snappy(duration: 0.34)) {
            step = next
        }
        if next == .name {
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                nameIsFocused = true
            }
        }
    }

    private func back() {
        if step == .welcome, welcomePage > 0 {
            withAnimation(.snappy(duration: 0.34)) {
                welcomePage -= 1
            }
            return
        }
        guard let previous = ChatStep(rawValue: step.rawValue - 1) else {
            onBackToDemo()
            return
        }
        nameIsFocused = false
        withAnimation(.snappy(duration: 0.34)) {
            step = previous
        }
    }

    private func revealCurrentScreen() async {
        let allMessages = screenMessages
        professorTyping = false
        typingMessageID = nil
        typedCharacterCount = 0

        if reduceMotion {
            visibleCount = allMessages.count
            return
        }

        visibleCount = 0

        while visibleCount < allMessages.count, !Task.isCancelled {
            let message = allMessages[visibleCount]
            if message.sender == .professor {
                withAnimation(.easeOut(duration: 0.2)) {
                    professorTyping = true
                }
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(.easeOut(duration: 0.2)) {
                    professorTyping = false
                }
            } else {
                try? await Task.sleep(for: .milliseconds(320))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                visibleCount += 1
            }

            if message.sender == .professor {
                typingMessageID = message.id
                typedCharacterCount = 0

                while typedCharacterCount < message.text.count, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(18))
                    guard !Task.isCancelled else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        typedCharacterCount += 1
                    }
                }

                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    typingMessageID = nil
                }
            }

            try? await Task.sleep(for: .milliseconds(90))
        }
    }

    private func visibleText(for message: ChatMessage) -> String {
        guard typingMessageID == message.id else { return message.text }
        let endIndex = message.text.index(
            message.text.startIndex,
            offsetBy: min(max(typedCharacterCount, 0), message.text.count)
        )
        return String(message.text[..<endIndex])
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let creature: CreatureStage
    let visibleText: String
    let showsAttachment: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.sender == .user {
                Spacer(minLength: 48)
            }

            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 8) {
                Text(visibleText)
                    .font(NanoFont.aldrich(15))
                    .lineSpacing(2)
                    .foregroundStyle(
                        message.sender == .user
                            ? Color.black
                            : message.muted ? Color.white.opacity(0.66) : Color.white
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        message.sender == .user
                            ? AnyShapeStyle(NanoTheme.cyan)
                            : AnyShapeStyle(NanoTheme.elevated),
                        in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                    )

                if message.hasCreature && showsAttachment {
                    HStack(spacing: 14) {
                        AnimatedCreatureArtworkView(stage: creature)
                            .frame(width: 86, height: 86)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Glitchlet")
                                .font(NanoFont.aldrich(14))
                            Text("A newly observed Nanobeast. Its evolution responds to the energy you earn by walking.")
                                .font(NanoFont.aldrich(11))
                                .foregroundStyle(NanoTheme.secondaryText)
                                .lineSpacing(2)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: 330)
                    .background(
                        LinearGradient(
                            colors: [NanoTheme.teal.opacity(0.12), NanoTheme.surface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(NanoTheme.teal.opacity(0.35), lineWidth: 1)
                    )
                    .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
                }
            }

            if message.sender == .professor {
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TypingBubble: View {
    @State private var activeDot = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.white.opacity(index == activeDot ? 0.9 : 0.35))
                        .frame(width: 7, height: 7)
                        .offset(y: index == activeDot ? -3 : 0)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(NanoTheme.elevated, in: Capsule())

            Spacer(minLength: 48)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.easeInOut(duration: 0.18)) {
                    activeDot = (activeDot + 1) % 3
                }
            }
        }
    }
}

private struct ChoiceList: View {
    let options: [OnboardingOption]
    @Binding var selection: Set<String>

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(options) { option in
                    OptionRow(option: option, selected: selection.contains(option.title), multiple: true) {
                        if selection.contains(option.title) {
                            selection.remove(option.title)
                        } else {
                            selection.insert(option.title)
                        }
                    }
                }
            }
        }
        .frame(height: listHeight)
        .scrollIndicators(.hidden)
    }

    private var listHeight: CGFloat {
        min(CGFloat(options.count) * 64 + CGFloat(max(options.count - 1, 0)) * 8, 352)
    }
}

private struct SingleChoiceList: View {
    let options: [OnboardingOption]
    @Binding var selection: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(options) { option in
                    OptionRow(option: option, selected: selection == option.title, multiple: false) {
                        selection = option.title
                    }
                }
            }
        }
        .frame(height: listHeight)
        .scrollIndicators(.hidden)
    }

    private var listHeight: CGFloat {
        min(CGFloat(options.count) * 64 + CGFloat(max(options.count - 1, 0)) * 8, 352)
    }
}

private struct OptionRow: View {
    let option: OnboardingOption
    let selected: Bool
    let multiple: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(NanoFont.aldrich(14))
                        .foregroundStyle(.white)
                    Text(option.detail)
                        .font(NanoFont.aldrich(11))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(selected ? NanoTheme.teal : .clear)
                        .stroke(selected ? NanoTheme.teal : NanoTheme.border, lineWidth: 1)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.black)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 14)
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

private struct InsightHeader: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Circle()
                    .fill(NanoTheme.teal)
                    .frame(width: 6, height: 6)
                    .shadow(color: NanoTheme.teal, radius: 6)
                Text("PERSONALIZED ANALYSIS")
                    .font(NanoFont.aldrich(11))
                    .tracking(1.4)
                    .foregroundStyle(NanoTheme.teal)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(NanoTheme.teal.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(NanoTheme.teal.opacity(0.24), lineWidth: 1))

            ProgressView(value: progress)
                .tint(NanoTheme.teal)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

private struct AnalysisFooter: View {
    let buttonTitle: String
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Back", action: onBack)
                .buttonStyle(.bordered)
                .tint(NanoTheme.secondaryText)

            Button(action: onContinue) {
                Text(buttonTitle)
                    .font(NanoFont.aldrich(13))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(NanoTheme.teal)
            .foregroundStyle(.black)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

private struct MovementProfileView: View {
    let playerName: String
    let baseline: String
    let goal: String
    let blocker: String
    let onBack: () -> Void
    let onContinue: () -> Void

    private let metrics = [
        ("Routine", 14.0),
        ("Motivation", 50.0),
        ("Visibility", 72.0),
        ("Momentum", 23.0),
        ("Goal clarity", 76.0)
    ]

    var body: some View {
        VStack(spacing: 0) {
            InsightHeader(progress: 1.0 / 3.0)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("YOUR MOVEMENT PROFILE")
                        .font(NanoFont.aldrich(13))
                        .tracking(2)
                        .foregroundStyle(NanoTheme.teal)
                    Text("\(playerName), make walking feel rewarding.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Based on your \(baseline.lowercased()) steps a day baseline and your goal of \(goal.lowercased()), Nano mapped the signals that can make walking easier to repeat.")
                        .foregroundStyle(NanoTheme.secondaryText)
                        .lineSpacing(5)

                    VStack(spacing: 18) {
                        RadarChartView(values: metrics.map { $0.1 / 100 })
                            .frame(height: 235)
                        ForEach(metrics, id: \.0) { metric in
                            AnimatedMetricRow(label: metric.0, score: metric.1)
                        }
                    }
                    .padding(18)
                    .background(
                        LinearGradient(
                            colors: [NanoTheme.teal.opacity(0.10), NanoTheme.surface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(NanoTheme.teal.opacity(0.25)))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("STRONGEST OPPORTUNITY")
                            .font(NanoFont.aldrich(11))
                            .tracking(1.5)
                            .foregroundStyle(NanoTheme.teal)
                        Text("Make walking feel rewarding")
                            .font(.title3.bold())
                        Text(blocker == "Walking feels boring"
                            ? "You said walking can feel boring. Hatching and evolving Nanobeasts turns each walk into visible progress and a discovery to chase."
                            : "Visible milestones turn each walk into progress you can recognize and repeat.")
                            .foregroundStyle(NanoTheme.secondaryText)
                            .lineSpacing(4)
                    }
                    .nanoHUDCard(tint: NanoTheme.teal, illuminated: true)
                }
                .padding(20)
            }
            AnalysisFooter(buttonTitle: "SEE MY PROJECTED PATH", onBack: onBack, onContinue: onContinue)
        }
    }
}

private struct RadarChartView: View {
    let values: [Double]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) * 0.40
            ZStack {
                ForEach(1...4, id: \.self) { ring in
                    RadarPolygon(values: Array(repeating: Double(ring) / 4, count: 5), progress: 1)
                        .stroke(NanoTheme.teal.opacity(0.12), lineWidth: 1)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                }

                Canvas { context, size in
                    for index in 0..<5 {
                        let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / 5
                        var line = Path()
                        line.move(to: center)
                        line.addLine(to: CGPoint(
                            x: center.x + cos(angle) * radius,
                            y: center.y + sin(angle) * radius
                        ))
                        context.stroke(line, with: .color(NanoTheme.teal.opacity(0.11)), lineWidth: 1)
                    }
                }

                RadarPolygon(values: values, progress: progress)
                    .fill(
                        LinearGradient(
                            colors: [NanoTheme.teal.opacity(0.48), NanoTheme.cyan.opacity(0.16)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RadarPolygon(values: values, progress: progress)
                            .stroke(NanoTheme.teal, lineWidth: 2)
                    }
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                    .shadow(color: NanoTheme.teal.opacity(0.3), radius: 12)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 1.1, dampingFraction: 0.74)) {
                progress = 1
            }
        }
    }
}

private struct RadarPolygon: Shape {
    let values: [Double]
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard values.count > 2 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in values.indices {
            let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(values.count)
            let amount = max(0, min(values[index], 1)) * progress
            let point = CGPoint(
                x: center.x + cos(angle) * radius * amount,
                y: center.y + sin(angle) * radius * amount
            )
            index == values.startIndex ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

private struct AnimatedMetricRow: View {
    let label: String
    let score: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal = 0.0

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(Int(score).formatted())
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(NanoTheme.teal)
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [NanoTheme.teal, NanoTheme.cyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * score / 100 * reveal)
                    }
            }
            .frame(height: 7)
        }
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.9, dampingFraction: 0.78).delay(0.12)) {
                reveal = 1
            }
        }
    }
}

private struct ProjectionPoint: Identifiable {
    let week: Int
    let current: Double
    let projected: Double
    var id: Int { week }
}

private struct ProjectedPathView: View {
    let baselineSteps: Int
    let targetSteps: Int
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal = 0.0

    private var points: [ProjectionPoint] {
        let baseline = Double(baselineSteps * 7)
        let target = Double(targetSteps * 7)
        return (0...4).map { week in
            let fraction = Double(week) / 4
            return ProjectionPoint(
                week: week,
                current: baseline * (1 + fraction * 0.05),
                projected: baseline + (target - baseline) * pow(fraction, 0.72)
            )
        }
    }

    private var lift: Double {
        Double(targetSteps) / Double(max(baselineSteps, 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            InsightHeader(progress: 2.0 / 3.0)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("YOUR PROJECTED PATH")
                        .font(NanoFont.aldrich(13))
                        .tracking(2)
                        .foregroundStyle(NanoTheme.teal)
                    Text("A clearer path toward your walking-more goal.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Starting from your current baseline, Nanobeasts turns daily movement into visible progress toward a personalized target.")
                        .foregroundStyle(NanoTheme.secondaryText)
                        .lineSpacing(5)

                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(lift, format: .number.precision(.fractionLength(1)))×")
                            .font(.system(size: 48, weight: .light, design: .rounded))
                            .foregroundStyle(NanoTheme.teal)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("DAILY STEP POTENTIAL")
                                .font(NanoFont.aldrich(12))
                            Text("from your current baseline to your personalized target")
                                .font(.caption)
                                .foregroundStyle(NanoTheme.secondaryText)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 18) {
                            Label("Current pace", systemImage: "line.diagonal")
                                .foregroundStyle(NanoTheme.secondaryText)
                            Label("With Nanobeasts", systemImage: "waveform.path.ecg")
                                .foregroundStyle(NanoTheme.teal)
                        }
                        .font(.caption)

                        Chart(points) { point in
                            LineMark(
                                x: .value("Week", point.week),
                                y: .value("Current", point.current)
                            )
                            .foregroundStyle(NanoTheme.secondaryText)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 5]))

                            AreaMark(
                                x: .value("Week", point.week),
                                y: .value("Projected", Double(baselineSteps * 7) + (point.projected - Double(baselineSteps * 7)) * reveal)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [NanoTheme.teal.opacity(0.32), NanoTheme.cyan.opacity(0.01)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Week", point.week),
                                y: .value("Projected", Double(baselineSteps * 7) + (point.projected - Double(baselineSteps * 7)) * reveal)
                            )
                            .foregroundStyle(NanoTheme.teal)
                            .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)
                            .symbol {
                                Circle()
                                    .fill(NanoTheme.teal)
                                    .frame(width: 7, height: 7)
                                    .shadow(color: NanoTheme.teal, radius: 5)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: [0, 2, 4]) { value in
                                AxisValueLabel {
                                    Text(value.as(Int.self) == 0 ? "NOW" : value.as(Int.self) == 4 ? "TARGET" : "BUILDING")
                                        .font(.caption2)
                                }
                            }
                        }
                        .chartYAxis(.hidden)
                        .frame(height: 245)
                    }
                    .nanoHUDCard(tint: NanoTheme.teal, illuminated: true)

                    HStack(spacing: 10) {
                        ProjectionStat(title: "CURRENT BASELINE", value: baselineSteps * 7)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("YOUR TARGET")
                                .font(NanoFont.aldrich(9))
                                .foregroundStyle(NanoTheme.teal)
                            Text("CALIBRATING")
                                .font(NanoFont.aldrich(17))
                                .foregroundStyle(.white)
                            Text("revealed after analysis")
                                .font(.caption2)
                                .foregroundStyle(NanoTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nanoHUDCard(tint: NanoTheme.teal, padding: 13, illuminated: true)
                    }

                    Text("Illustrative habit projection based on your onboarding answers. Individual activity and body results vary.")
                        .font(.caption2)
                        .foregroundStyle(NanoTheme.mutedText)
                }
                .padding(20)
            }
            AnalysisFooter(buttonTitle: "BUILD MY 30-DAY PLAN", onBack: onBack, onContinue: onContinue)
        }
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 1.4)) {
                reveal = 1
            }
        }
    }
}

private struct ProjectionStat: View {
    let title: String
    let value: Int
    var active = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(NanoFont.aldrich(9))
                .foregroundStyle(active ? NanoTheme.teal : NanoTheme.secondaryText)
            Text(value.formatted())
                .font(.title3.monospacedDigit().bold())
            Text("steps / week")
                .font(.caption2)
                .foregroundStyle(NanoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nanoHUDCard(tint: active ? NanoTheme.teal : NanoTheme.secondaryText, padding: 13, illuminated: active)
    }
}

private struct PlanBuilderView: View {
    let playerName: String
    @Binding var progress: Int
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var operations: [(String, Int)] {
        [
            ("Reviewing your movement preferences", 18),
            ("Balancing challenge with a sustainable pace", 38),
            ("Shaping a plan around your individual goals", 58),
            ("Building a rhythm that helps you walk more", 74),
            ("Personalizing motivation and progress feedback", 90),
            ("\(playerName)’s private movement plan is ready", 100)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            InsightHeader(progress: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("BUILDING YOUR FIELD PLAN")
                        .font(NanoFont.aldrich(13))
                        .tracking(2)
                        .foregroundStyle(NanoTheme.teal)
                    Text("\(playerName), we’re setting everything up for you.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text("\(progress)%")
                        .font(.system(size: 72, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(NanoTheme.teal)
                        .contentTransition(.numericText())

                    Text(status)
                        .font(.headline)
                        .foregroundStyle(NanoTheme.secondaryText)

                    ProgressView(value: Double(progress), total: 100)
                        .tint(NanoTheme.teal)
                        .scaleEffect(y: 2)

                    VStack(spacing: 10) {
                        ForEach(operations, id: \.0) { operation in
                            let complete = progress >= operation.1
                            HStack(spacing: 12) {
                                Image(systemName: complete ? "checkmark.circle.fill" : "circle.dotted")
                                    .font(.title3)
                                    .foregroundStyle(complete ? NanoTheme.teal : NanoTheme.mutedText)
                                    .symbolEffect(.bounce, value: complete)
                                Text(operation.0)
                                    .font(.subheadline)
                                    .foregroundStyle(complete ? .white : NanoTheme.secondaryText)
                                Spacer()
                            }
                            .padding(14)
                            .background(
                                complete ? NanoTheme.teal.opacity(0.08) : NanoTheme.surface,
                                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 17)
                                    .stroke(complete ? NanoTheme.teal.opacity(0.35) : NanoTheme.border)
                            )
                        }
                    }
                }
                .padding(20)
            }
        }
        .task {
            if reduceMotion {
                progress = 100
                try? await Task.sleep(for: .milliseconds(250))
                onComplete()
                return
            }

            while progress < 100, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(35))
                withAnimation(.linear(duration: 0.035)) {
                    progress += 1
                }
            }
            try? await Task.sleep(for: .milliseconds(650))
            if !Task.isCancelled {
                onComplete()
            }
        }
    }

    private var status: String {
        switch progress {
        case 0..<22: "Reading onboarding answers…"
        case 22..<48: "Finding a sustainable starting point…"
        case 48..<72: "Building around your individual goals…"
        case 72..<94: "Personalizing a path that helps you walk more…"
        default: "Your movement plan is ready."
        }
    }
}

private struct FieldPlanView: View {
    let playerName: String
    let targetSteps: Int
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            InsightHeader(progress: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("YOUR 30-DAY FIELD PLAN")
                        .font(NanoFont.aldrich(13))
                        .tracking(2)
                        .foregroundStyle(NanoTheme.teal)
                    Text("\(playerName), your evolution plan is ready.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Your answers point to a daily target that builds more movement into your routine while powering a clear Nanobeasts mission.")
                        .foregroundStyle(NanoTheme.secondaryText)
                        .lineSpacing(5)

                    VStack(spacing: 7) {
                        Text("YOUR DAILY MOVEMENT TARGET")
                            .font(NanoFont.aldrich(11))
                            .tracking(1.4)
                            .foregroundStyle(NanoTheme.teal)
                        Text(targetSteps.formatted())
                            .font(.system(size: 64, weight: .light, design: .rounded).monospacedDigit())
                        Text("steps per day")
                            .font(.headline)
                            .foregroundStyle(NanoTheme.secondaryText)
                        ProgressView(value: 1)
                            .tint(NanoTheme.teal)
                        Text("\((targetSteps * 30).formatted()) steps across 30 days")
                            .font(.caption)
                            .foregroundStyle(NanoTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .nanoHUDCard(tint: NanoTheme.teal, illuminated: true)

                    HStack(spacing: 10) {
                        PlanMilestone(value: "4", label: "HATCH TARGETS")
                        PlanMilestone(value: "8", label: "EVOLUTION TARGETS")
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        TimelineRow(week: "WEEK 1", text: "Establish your daily walking rhythm", last: false)
                        TimelineRow(week: "WEEK 2", text: "Build consistency and power new evolutions", last: false)
                        TimelineRow(week: "WEEK 3", text: "Raise your weekly step total", last: false)
                        TimelineRow(week: "WEEK 4", text: "Complete your 30-day field mission", last: true)
                    }
                    .nanoHUDCard(tint: NanoTheme.teal)

                    Text("This plan supports a more active routine; weight and body-composition outcomes vary by person.")
                        .font(.caption2)
                        .foregroundStyle(NanoTheme.mutedText)
                }
                .padding(20)
            }
            AnalysisFooter(buttonTitle: "CONTINUE", onBack: onBack, onContinue: onContinue)
        }
    }
}

private struct PlanMilestone: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 42, weight: .light, design: .rounded))
                .foregroundStyle(NanoTheme.teal)
            Text(label)
                .font(NanoFont.aldrich(9))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .nanoHUDCard(tint: NanoTheme.teal, padding: 14)
    }
}

private struct TimelineRow: View {
    let week: String
    let text: String
    let last: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 0) {
                Circle()
                    .fill(NanoTheme.teal)
                    .frame(width: 10, height: 10)
                    .shadow(color: NanoTheme.teal, radius: 5)
                if !last {
                    Rectangle()
                        .fill(NanoTheme.teal.opacity(0.28))
                        .frame(width: 2, height: 42)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(week)
                    .font(NanoFont.aldrich(10))
                    .foregroundStyle(NanoTheme.teal)
                Text(text)
                    .font(.subheadline)
            }
            Spacer()
        }
    }
}

private struct CommitmentView: View {
    let playerName: String
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
                Text("FIELD COMMITMENT")
                    .font(NanoFont.aldrich(11))
                    .tracking(1.5)
                    .foregroundStyle(NanoTheme.teal)
            }
            .padding(18)

            Spacer(minLength: 18)

            VStack(spacing: 10) {
                Text("I, \(playerName), will reach my goal")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("to improve my walking habits for a healthier me.")
                    .font(.title3)
                    .foregroundStyle(NanoTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

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
            .accessibilityLabel("Hold to lock in your field commitment")
            .accessibilityAddTraits(.isButton)

            Spacer(minLength: 24)

            VStack(spacing: 8) {
                Text(committed ? "COMMITMENT LOCKED" : "Hold for 2 seconds to lock in")
                    .font(NanoFont.aldrich(14))
                    .foregroundStyle(committed ? NanoTheme.teal : .white)
                Text(committed ? "Your first field mission is ready." : "Keep your finger on the egg until the energy ring closes.")
                    .font(.caption)
                    .foregroundStyle(NanoTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)

            Spacer()
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
