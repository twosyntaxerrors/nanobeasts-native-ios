import SwiftUI

/// One-screen streak view. The card is the hero and the share artwork,
/// so what people see is exactly what they post.
struct StreakSummaryView: View {
    let records: [DailyStepRecord]
    let dailyGoal: Int
    let dailyGoalHistory: [DailyGoalRecord]
    var hapticsEnabled = false
    var reducesMotion = false
    var referenceDate: Date? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var selectedDate: Date?
    @State private var displayedCount = 0
    @State private var ignited = false
    @State private var shareImage: UIImage?
    @State private var presentsShareSheet = false
    @State private var flarvaPoster: UIImage?
    @Namespace private var selection

    private var suppressMotion: Bool { reducesMotion || systemReduceMotion }

    private var motion: Animation? {
        suppressMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.22)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let summary = StreakHistorySummary(records: records, dailyGoal: dailyGoal,
                goalHistory: dailyGoalHistory, now: referenceDate ?? timeline.date)
            let selected = summary.week.first { $0.date == selectedDate } ?? summary.today
            VStack(spacing: 0) {
                topBar
                StreakShareCard(summary: summary, count: displayedCount, animated: !suppressMotion,
                                ignited: ignited || suppressMotion, hapticsEnabled: hapticsEnabled,
                                flarvaPoster: flarvaPoster,
                                selectedID: selected.id, namespace: selection) { day in
                    withAnimation(motion) { selectedDate = day.date }
                }
                .scaleEffect(ignited || suppressMotion ? 1 : 0.96)
                .opacity(ignited ? 1 : 0)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: 520, maxHeight: .infinity)
                footer(summary)
            }
            .background(NanoTheme.background.ignoresSafeArea())
            .sensoryFeedback(.selection, trigger: selectedDate) { _, _ in hapticsEnabled }
            .sensoryFeedback(.success, trigger: ignited) { _, lit in lit && hapticsEnabled && summary.current > 0 }
            .task {
                guard !ignited else { return }
                if suppressMotion {
                    withAnimation(.easeOut(duration: 0.2)) { ignited = true }
                    displayedCount = summary.current
                    return
                }
                withAnimation(.spring(duration: 0.55, bounce: 0.28)) { ignited = true }
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.spring(duration: 0.7, bounce: 0.2)) { displayedCount = summary.current }
            }
            .onChange(of: summary.current) { _, current in
                if ignited { withAnimation(motion) { displayedCount = current } }
            }
            .sheet(isPresented: $presentsShareSheet) {
                if let shareImage {
                    StreakActivityShareSheet(items: [shareImage, "\(summary.current)-day step streak on Nanobeasts 🔥"])
                        .presentationDetents([.medium, .large])
                }
            }
        }
        .task {
            guard flarvaPoster == nil else { return }
            if let data = try? await R2ArtworkCache.shared.data(for: StreakFlarvaArtwork.walkingURL),
               !Task.isCancelled {
                flarvaPoster = UIImage(data: data)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text("Your streak")
                .font(.custom("Aldrich-Regular", size: 20, relativeTo: .title2))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NanoTheme.text.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(NanoTheme.surface, in: Circle())
            }
            .buttonStyle(StreakPressStyle(reduceMotion: suppressMotion))
            .accessibilityLabel("Close streak")
        }
        .foregroundStyle(NanoTheme.text)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func footer(_ summary: StreakHistorySummary) -> some View {
        let canShare = summary.current > 0
        return Button {
            if canShare { share(summary) } else { dismiss() }
        } label: {
            HStack {
                Text(canShare ? "Share streak" : "Back to Lab")
                    .font(.custom("Aldrich-Regular", size: 16, relativeTo: .headline))
                Spacer()
                Image(systemName: canShare ? "square.and.arrow.up" : "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(NanoTheme.background)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(NanoTheme.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StreakPressStyle(reduceMotion: suppressMotion))
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 6)
        .frame(maxWidth: 520)
    }

    @MainActor
    private func share(_ summary: StreakHistorySummary) {
        let card = StreakShareCard(summary: summary, count: summary.current, animated: false, ignited: true,
                                   flarvaPoster: flarvaPoster)
            .frame(width: 360)
            .padding(24)
            .background(NanoTheme.background)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = true
        shareImage = renderer.uiImage
        presentsShareSheet = shareImage != nil
    }
}

/// The hero doubles as the share artwork, so what people see is exactly what they post.
private struct StreakShareCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: StreakHistorySummary
    let count: Int
    let animated: Bool
    let ignited: Bool
    var hapticsEnabled = false
    var flarvaPoster: UIImage? = nil
    var selectedID: Date? = nil
    var namespace: Namespace.ID? = nil
    var onSelect: ((StreakHistorySummary.Day) -> Void)? = nil

    @State private var flare = 0

    private var isLit: Bool { summary.current > 0 || summary.today.metGoal }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("NANOBEASTS")
                    .font(NanoFont.aldrich(13)).tracking(3)
                    .foregroundStyle(NanoTheme.text.opacity(0.9))
                Spacer()
                Text(summary.today.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(NanoFont.spaceMono(12))
                    .foregroundStyle(NanoTheme.text.opacity(0.55))
            }

            StreakFlarvaHero(isLit: isLit, embers: min(18, 6 + summary.current / 3), animated: animated,
                            poster: flarvaPoster)
                .frame(maxWidth: 230, minHeight: 110, maxHeight: 210)
                .scaleEffect(ignited ? 1 : 0.35, anchor: .bottom)
                .opacity(ignited ? 1 : 0)
                .keyframeAnimator(initialValue: 1.0, trigger: animated ? flare : 0) { content, scale in
                    content.scaleEffect(scale, anchor: .bottom)
                } keyframes: { _ in
                    SpringKeyframe(1.16, duration: 0.12, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.6, spring: .bouncy)
                }
                .contentShape(Rectangle())
                .onTapGesture { if onSelect != nil { flare += 1 } }
                .sensoryFeedback(.impact(weight: .medium), trigger: flare) { _, _ in hapticsEnabled }
                .padding(.top, 8)
                .accessibilityHidden(true)

            Text(count.formatted())
                .font(NanoFont.spaceMono(count > 99 ? 84 : 104, bold: true))
                .tracking(-4)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
                .lineLimit(1).minimumScaleFactor(0.6)
                .shadow(color: NanoTheme.orange.opacity(isLit ? 0.55 : 0), radius: 22, y: 4)
                .padding(.top, -12)
            Text("DAY STREAK")
                .font(NanoFont.aldrich(15)).tracking(4)
                .foregroundStyle(isLit ? NanoTheme.orange : NanoTheme.secondaryText)
                .padding(.top, -6)
            Text(Self.headline(for: summary.current))
                .font(.custom("Aldrich-Regular", size: 22, relativeTo: .title2))
                .padding(.top, 14)

            weekStrip.padding(.top, 22)

            statRow.padding(.top, 20)
        }
        .foregroundStyle(NanoTheme.text)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background {
            ZStack {
                Color.nano(dark: NanoPlatformColor(red: 0.06, green: 0.04, blue: 0.035, alpha: 1), light: NanoPlatformColor(hex: 0xFBFAF5))
                RadialGradient(colors: [NanoTheme.orange.opacity(isLit ? 0.34 : 0.08), .clear],
                               center: UnitPoint(x: 0.5, y: 0.3), startRadius: 10, endRadius: 260)
                LinearGradient(colors: [.clear, Color(red: 0.55, green: 0.12, blue: 0.04).opacity(isLit ? (colorScheme == .light ? 0.1 : 0.28) : 0)],
                               startPoint: .center, endPoint: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(LinearGradient(colors: [NanoTheme.orange.opacity(0.45), NanoTheme.ink.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Current streak, \(summary.current) \(summary.current == 1 ? "day" : "days"). Personal best \(summary.best).")
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(summary.week) { day in
                let isSelected = day.id == selectedID
                Button { onSelect?(day) } label: {
                    VStack(spacing: 8) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 11, weight: day.isToday ? .bold : .medium))
                            .foregroundStyle(day.isToday ? NanoTheme.orange : NanoTheme.ink.opacity(0.5))
                        ZStack {
                            Circle().stroke(NanoTheme.ink.opacity(0.12), lineWidth: 2)
                            if !day.isFuture && !day.metGoal {
                                Circle().trim(from: 0, to: day.progress)
                                    .stroke(NanoTheme.orange.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            if day.metGoal {
                                Circle().fill(LinearGradient(colors: [NanoAccent.gold.color, NanoTheme.orange],
                                                             startPoint: .top, endPoint: .bottom))
                                Image(systemName: "flame.fill").font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color(red: 0.25, green: 0.07, blue: 0.0))
                            } else {
                                Text(day.date.formatted(.dateTime.day()))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(day.isFuture ? NanoTheme.ink.opacity(0.35) : .white)
                            }
                        }
                        .frame(width: 30, height: 30)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background {
                        if isSelected, let namespace {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(NanoTheme.ink.opacity(0.08))
                                .matchedGeometryEffect(id: "selected-day", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(StreakPressStyle(reduceMotion: !animated))
                .disabled(onSelect == nil)
                .accessibilityLabel(Self.dayLabel(day))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    /// Today shows the streak overview; any other selected day swaps the row to that day's numbers.
    private var statRow: some View {
        let day = summary.week.first { $0.id == selectedID } ?? summary.today
        return HStack(spacing: 0) {
            if day.isToday {
                stat("BEST", "\(summary.best.formatted())d")
                divider
                stat("THIS WEEK", "\(summary.week.filter(\.metGoal).count)/7")
                divider
                stat("TODAY", day.steps.formatted(), tint: day.metGoal ? NanoTheme.orange : NanoTheme.text)
            } else {
                stat(day.date.formatted(.dateTime.weekday(.abbreviated)).uppercased(),
                     day.isFuture ? "—" : day.steps.formatted(), tint: day.metGoal ? NanoTheme.orange : NanoTheme.text)
                divider
                stat("GOAL", day.goal.formatted())
                divider
                stat("STATUS", day.isFuture ? "Ahead" : day.metGoal ? "Met" : "Missed",
                     tint: day.metGoal ? NanoTheme.orange : NanoTheme.secondaryText)
            }
        }
        .id(day.id)
        .transition(.opacity)
    }

    private func stat(_ label: String, _ value: String, tint: Color = NanoTheme.text) -> some View {
        VStack(spacing: 4) {
            Text(value).font(NanoFont.spaceMono(17, bold: true)).monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(1.2)
                .foregroundStyle(NanoTheme.text.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(NanoTheme.ink.opacity(0.1)).frame(width: 1, height: 28)
    }

    static func headline(for streak: Int) -> String {
        switch streak {
        case 0: "Strike a spark"
        case 1: "Day one. Lit."
        case 2..<7: "Heating up"
        case 7..<14: "On fire"
        case 14..<30: "Unstoppable"
        case 30..<100: "Blazing"
        default: "Legendary"
        }
    }

    static func dayLabel(_ day: StreakHistorySummary.Day) -> String {
        let date = day.date.formatted(.dateTime.weekday(.wide).month().day())
        if day.isFuture { return "\(date), upcoming, show goal" }
        return "\(date)\(day.isToday ? ", today" : ""), \(day.steps.formatted()) of \(day.goal.formatted()) steps, \(day.metGoal ? "goal met" : "goal not met"). Show details."
    }
}

private enum StreakFlarvaArtwork {
    static let walkingURL = R2AssetManifest.baseURL
        .appending(path: "images/gif-animations/Flarva_HappyWalk_Onboard.png")
}

/// The APNG uses the existing animated-image player and stays separate from the fire.
private struct StreakFlarvaHero: View {
    let isLit: Bool
    let embers: Int
    let animated: Bool
    var poster: UIImage? = nil

    @Environment(\.scenePhase) private var scenePhase
    @State private var animationLoaded = false
    @State private var isVisible = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                StreakFlame(isLit: isLit, embers: embers, animated: animated)
                    .frame(width: geometry.size.width * 1.15, height: geometry.size.height * 1.28)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
                    .mask { Rectangle().padding(12).blur(radius: 12) }
                ZStack {
                    if !animationLoaded || !animated {
                        Group {
                            if let poster {
                                Image(uiImage: poster).resizable()
                            } else {
                                Image("StreakFlarvaDetermined").resizable()
                            }
                        }
                        .scaledToFit()
                    }
                    if animated, isVisible {
                        RemoteAnimatedWebPView(
                            url: StreakFlarvaArtwork.walkingURL,
                            isPlaying: scenePhase == .active,
                            maxBufferSize: 16 * 1_024 * 1_024,
                            onLoad: { animationLoaded = $0 }
                        )
                        .opacity(animationLoaded ? 1 : 0)
                    }
                }
                    .frame(width: geometry.size.width * 0.84, height: geometry.size.height * 0.92)
                    .padding(.bottom, geometry.size.height * 0.04)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            animationLoaded = false
        }
        .onChange(of: animated) { animationLoaded = false }
    }
}

/// A procedural flame: layered tongues that sway on incommensurate sine waves so the loop never visibly repeats.
private struct StreakFlame: View {
    let isLit: Bool
    let embers: Int
    let animated: Bool

    var body: some View {
        if animated {
            TimelineView(.animation) { timeline in
                StreakFlameCanvas(time: timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600),
                                  isLit: isLit, embers: embers)
            }
        } else {
            // A frozen frame chosen for a balanced silhouette in reduced motion and share renders.
            StreakFlameCanvas(time: 1.35, isLit: isLit, embers: embers)
        }
    }
}

private struct StreakFlameCanvas: View {
    let time: Double
    let isLit: Bool
    let embers: Int

    private struct Layer { let top: Color; let bottom: Color; let width: CGFloat; let height: CGFloat; let lift: CGFloat; let phase: Double }

    private var layers: [Layer] {
        if isLit {
            return [
                Layer(top: Color(red: 0.92, green: 0.2, blue: 0.05), bottom: Color(red: 0.99, green: 0.42, blue: 0.08), width: 0.6, height: 0.74, lift: 0, phase: 0),
                Layer(top: NanoTheme.orange, bottom: Color(red: 1, green: 0.64, blue: 0.12), width: 0.45, height: 0.56, lift: 0.02, phase: 1.3),
                Layer(top: Color(red: 1, green: 0.76, blue: 0.2), bottom: Color(red: 1, green: 0.9, blue: 0.45), width: 0.3, height: 0.38, lift: 0.035, phase: 2.6),
                Layer(top: Color(red: 1, green: 0.95, blue: 0.75), bottom: Color(red: 1, green: 0.99, blue: 0.9), width: 0.15, height: 0.2, lift: 0.05, phase: 3.9),
            ]
        }
        return [
            Layer(top: NanoTheme.mutedText, bottom: NanoTheme.elevated, width: 0.5, height: 0.56, lift: 0, phase: 0),
            Layer(top: NanoTheme.secondaryText.opacity(0.7), bottom: NanoTheme.mutedText, width: 0.3, height: 0.34, lift: 0.025, phase: 1.3),
        ]
    }

    var body: some View {
        Canvas { context, size in
            let t = time
            let w = size.width, h = size.height
            let base = CGPoint(x: w / 2, y: h * 0.97)
            let energy: Double = isLit ? 1 : 0.4

            var glow = context
            glow.addFilter(.blur(radius: w * 0.11))
            glow.opacity = isLit ? 0.6 + 0.12 * sin(t * 3.1) : 0.18
            glow.fill(Self.tongue(base: base, width: w * 0.66, height: h * 0.7, t: t, phase: 0, energy: energy),
                      with: .color(isLit ? NanoTheme.orange : NanoTheme.mutedText))

            if isLit {
                for side in [-1.0, 1.0] {
                    let tongueBase = CGPoint(x: base.x + side * w * 0.13, y: base.y - h * 0.01)
                    let tongueHeight = h * (0.44 + 0.05 * sin(t * 4.3 + side * 2))
                    context.fill(Self.tongue(base: tongueBase, width: w * 0.34, height: tongueHeight, t: t * 1.25,
                                             phase: side * 1.7 + 4, lean: side * 0.22, energy: energy),
                                 with: .linearGradient(Gradient(colors: [Color(red: 0.85, green: 0.15, blue: 0.05), Color(red: 0.98, green: 0.36, blue: 0.07)]),
                                                       startPoint: CGPoint(x: tongueBase.x, y: tongueBase.y - tongueHeight), endPoint: tongueBase))
                }
            }

            for layer in layers {
                let layerBase = CGPoint(x: base.x, y: base.y - h * layer.lift)
                let layerHeight = h * layer.height * (1 + 0.05 * energy * sin(t * 6.7 + layer.phase))
                context.fill(Self.tongue(base: layerBase, width: w * layer.width, height: layerHeight, t: t,
                                         phase: layer.phase, energy: energy),
                             with: .linearGradient(Gradient(colors: [layer.top, layer.bottom]),
                                                   startPoint: CGPoint(x: layerBase.x, y: layerBase.y - layerHeight),
                                                   endPoint: layerBase))
            }

            guard isLit else { return }
            context.blendMode = .plusLighter
            for index in 0..<embers {
                let seed = (Double(index) * 0.618_034).truncatingRemainder(dividingBy: 1)
                let life = (t * (0.32 + seed * 0.4) + seed * 7).truncatingRemainder(dividingBy: 1)
                let drift = (seed - 0.5) * 0.55 + sin(t * 2 + Double(index)) * 0.07 * life
                let x = base.x + CGFloat(drift) * w
                let y = base.y - h * 0.3 - CGFloat(life) * h * 0.7
                let radius = CGFloat(1.2 + seed * 2.2) * (1 - CGFloat(life) * 0.5) * w / 150
                context.opacity = sin(life * .pi) * 0.95
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(seed > 0.5 ? NanoAccent.gold.color : NanoTheme.orange))
            }
        }
    }

    /// A teardrop with a rounded base and a swaying, slightly hooked tip.
    private static func tongue(base: CGPoint, width: CGFloat, height: CGFloat, t: Double, phase: Double,
                               lean: Double = 0, energy: Double = 1) -> Path {
        let r = width / 2
        let sway = CGFloat((sin(t * 2.1 + phase) * 0.16 + sin(t * 5.3 + phase * 1.7) * 0.06) * energy + lean) * r
        let tip = CGPoint(x: base.x + sway * 1.6, y: base.y - height)
        let shoulder = CGFloat(sin(t * 3.7 + phase * 0.6) * energy) * r * 0.14
        var path = Path()
        path.move(to: base)
        path.addCurve(to: CGPoint(x: base.x + r, y: base.y - r),
                      control1: CGPoint(x: base.x + r * 0.56, y: base.y),
                      control2: CGPoint(x: base.x + r, y: base.y - r * 0.44))
        path.addCurve(to: tip,
                      control1: CGPoint(x: base.x + r + shoulder, y: base.y - r - height * 0.28),
                      control2: CGPoint(x: tip.x + r * 0.2, y: tip.y + height * 0.3))
        path.addCurve(to: CGPoint(x: base.x - r, y: base.y - r),
                      control1: CGPoint(x: tip.x - r * 0.28, y: tip.y + height * 0.36),
                      control2: CGPoint(x: base.x - r - shoulder, y: base.y - r - height * 0.22))
        path.addCurve(to: base,
                      control1: CGPoint(x: base.x - r, y: base.y - r * 0.44),
                      control2: CGPoint(x: base.x - r * 0.56, y: base.y))
        path.closeSubpath()
        return path
    }
}

private struct StreakPressStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: configuration.isPressed ? 0.1 : 0.18),
                       value: configuration.isPressed)
    }
}

private struct StreakActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
