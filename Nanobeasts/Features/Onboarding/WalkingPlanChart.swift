import SwiftUI

/// The same presentation components are used by the iPhone and the macOS design renderer.
struct OnboardingPlanContent: View {
    let comparison: WalkingPlanComparison
    let headline: String
    let detail: String
    let tint: Color
    var elapsed: TimeInterval = WalkingPlanReveal.duration
    var chartElapsed: TimeInterval? = nil
    var comparisonHeadline: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            WalkingPlanLead(headline: headline, detail: detail)
            WalkingPlanTarget(comparison: comparison, tint: tint, elapsed: elapsed)
            WalkingPlanComparisonContent(comparison: comparison, tint: tint, elapsed: chartElapsed ?? elapsed, headline: comparisonHeadline)
        }
    }
}

/// Two chapters of the same saved plan. The graph receives its own viewport.
struct WalkingPlanPageContent: View {
    let page: WalkingPlanPage
    let comparison: WalkingPlanComparison
    let headline: String
    let detail: String
    let comparisonHeadline: String
    let tint: Color
    var elapsed: TimeInterval = WalkingPlanReveal.duration
    var benefits: [OnboardingCopy.Benefit] = []
    var evolutionChallenge: WalkingEvolutionChallenge? = nil
    var comparisonDetail: String = ""
    /// When present, page two shows the long-horizon Dex journey instead of the 30-day comparison.
    var journey: WalkingJourneyProjection? = nil
    var emphasizesBody = false
    var milestoneArtwork: ((Int) -> AnyView?)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if page == .target {
                WalkingPlanLead(headline: headline, detail: journey == nil ? detail : "")
                WalkingPlanTarget(comparison: comparison, tint: tint, elapsed: elapsed,
                    evolutionChallenge: evolutionChallenge)
                if journey == nil, !benefits.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("HOW NANOBEASTS HELPS")
                            .font(.system(size: 10, weight: .semibold)).tracking(1.5)
                            .foregroundStyle(tint)
                        OnboardingBenefitList(benefits: benefits, tint: tint, spacing: 18)
                    }
                }
                Text(OnboardingCopy.targetNote)
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(comparisonHeadline)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .tracking(-0.5).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if !comparisonDetail.isEmpty {
                        Text(comparisonDetail)
                            .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let journey, journey.isAvailable {
                    WalkingJourneyContent(journey: journey, tint: tint, elapsed: elapsed,
                                          emphasizesBody: emphasizesBody, milestoneArtwork: milestoneArtwork)
                } else {
                    WalkingPlanComparisonContent(comparison: comparison, tint: tint, elapsed: elapsed, showsHeadline: false)
                }
            }
        }
        .foregroundStyle(.white)
    }
}

struct WalkingPlanLead: View {
    let headline: String
    let detail: String
    var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(headline)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .tracking(-0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
    }
}

struct WalkingPlanTarget: View {
    let comparison: WalkingPlanComparison
    let tint: Color
    var elapsed: TimeInterval = WalkingPlanReveal.duration
    var compact = false
    var evolutionChallenge: WalkingEvolutionChallenge? = nil
    private var motion: WalkingPlanReveal { .init(elapsed: elapsed) }
    private var dailyTarget: Int { motion.dailyTarget(for: comparison) }
    private let ink = Color(red: 0.04, green: 0.065, blue: 0.085)
    var body: some View {
            VStack(alignment: .leading, spacing: compact ? 12 : 16) {
                Label { Text("YOUR DAILY STEP TARGET") } icon: { SolarImage(.walking, size: 15) }
                    .font(.system(size: 11, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(tint)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { targetNumber }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) { targetNumber }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(comparison.baselineSteps.formatted()) estimated")
                        .foregroundStyle(.white.opacity(0.6))
                    SolarImage(.right, size: 18).accessibilityHidden(true)
                    Text("+\(comparison.dailyIncrease.formatted()) a day").foregroundStyle(tint)
                }
                .font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                if comparison.targetSteps < DailyGoalPolicy.manualMinimum {
                    Text("Rises \(DailyGoalPolicy.rampStep) a week to \(DailyGoalPolicy.manualMinimum.formatted()).")
                        .font(.caption).foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let challenge = evolutionChallenge {
                    Rectangle().fill(tint.opacity(0.18)).frame(height: 1).padding(.vertical, 3)
                    VStack(alignment: .leading, spacing: 6) {
                        Label { Text("EVOLUTION CHALLENGE") } icon: { SolarImage(.stars, size: 14) }
                            .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(tint)
                        Text(challenge.cadence).font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(compact ? 16 : 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 26)
                    .fill(LinearGradient(colors: [tint.opacity(0.16), ink], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(tint.opacity(0.28), lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Suggested daily target")
            .accessibilityValue("\(comparison.targetSteps) or more steps, based on an estimated \(comparison.baselineSteps) steps per day now. \(evolutionChallenge.map { "\($0.cadence). Aim for \($0.evolutionsIn30Days) in thirty days. Timing varies by creature." } ?? "")")
    }
    @ViewBuilder private var targetNumber: some View {
        Text("\(dailyTarget.formatted())+")
            .font(.system(size: compact ? 48 : 60, weight: .bold, design: .rounded).monospacedDigit())
            .tracking(-2).foregroundStyle(.white)
        Text("steps / day").font(.caption).foregroundStyle(.white.opacity(0.6))
    }
}

struct WalkingPlanComparisonContent: View {
    let comparison: WalkingPlanComparison
    let tint: Color
    var elapsed: TimeInterval = WalkingPlanReveal.duration
    var headline: String? = nil
    var showsHeadline = true
    private var motion: WalkingPlanReveal { .init(elapsed: elapsed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showsHeadline {
                Text(headline ?? "Your next 30 days")
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
            }
            WalkingPlanChart(comparison: comparison, tint: tint, elapsed: elapsed)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("+\(comparison.additionalSteps(atDay: Double(WalkingPlanComparison.days) * motion.chartProgress).formatted())")
                        .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.7).lineLimit(1)
                    Text("extra steps in 30 days")
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 50)
                VStack(alignment: .leading, spacing: 5) {
                    Text("+\(comparison.dailyIncrease.formatted())")
                        .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("steps to add each day")
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(comparison.additionalTotal) extra steps in thirty days by adding \(comparison.dailyIncrease) steps per day")
            Text("More steps. More progress you can see, as your eggs hatch and your creatures grow.")
                .font(.subheadline.weight(.medium)).foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Text("With Nanobeasts assumes you reach your daily target. Without keeps your current routine. Illustrated extra steps over 30 days.")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The user's first month as a timeline where every creature they unlock is paired
/// with what their body did to earn it, ending on where they'll be by day 30.
struct WalkingJourneyContent: View {
    let journey: WalkingJourneyProjection
    let tint: Color
    var elapsed: TimeInterval = WalkingPlanReveal.duration
    var emphasizesBody = false
    var milestoneArtwork: ((Int) -> AnyView?)? = nil
    var start = Date()

    /// 0...1 over the shared reveal clock; everything below is choreographed from it.
    private var reveal: Double { min(1, max(0, (elapsed - 0.25) / (WalkingPlanReveal.duration - 0.35))) }
    private let ember = Color(red: 1.0, green: 0.62, blue: 0.24)
    private let ink = Color(red: 0.04, green: 0.065, blue: 0.085)

    // Choreography: the line reaches node i at `arrival(i)`; the card lands last.
    private static let firstArrival = 0.04
    private static let spacing = 0.19
    private func arrival(_ index: Int) -> Double { Self.firstArrival + Double(index) * Self.spacing }
    private var cardArrival: Double { arrival(journey.checkpoints.count) }
    private func phase(from start: Double, length: Double) -> Double {
        min(1, max(0, (reveal - start) / length))
    }
    private var revealedNodes: Int {
        journey.checkpoints.indices.filter { reveal >= arrival($0) }.count + (reveal >= cardArrival ? 1 : 0)
    }
    private var horizon: Int { WalkingJourneyProjection.horizonDays }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            timeline
            futureCard
                .opacity(Ease.out(phase(from: cardArrival, length: 0.1)))
                .scaleEffect(0.94 + 0.06 * Ease.back(phase(from: cardArrival, length: 0.14)), anchor: .top)
                .offset(y: 18 * (1 - Ease.out(phase(from: cardArrival, length: 0.14))))
                .animation(.linear(duration: 0.034), value: reveal)
            Text("Estimates at your daily goal. Results vary.")
                .font(.caption2).foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("EVERY NANOBEAST IS REAL PROGRESS")
                .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                .foregroundStyle(tint)
                .opacity(Ease.out(phase(from: 0, length: 0.08)))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(journey.checkpoints.enumerated()), id: \.element.id) { index, checkpoint in
                    row(checkpoint, index: index, isLast: index == journey.checkpoints.count - 1)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [.white.opacity(0.055), .white.opacity(0.015)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.08), lineWidth: 1))
        // The shared clock ticks ~30 times a second; interpolate between ticks for 120 Hz motion.
        .animation(.linear(duration: 0.034), value: reveal)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: revealedNodes) { old, new in new > old }
        .accessibilityElement(children: .combine)
    }

    private func row(_ checkpoint: WalkingJourneyProjection.Checkpoint, index: Int, isLast: Bool) -> some View {
        let start = arrival(index)
        let pop = phase(from: start, length: 0.12)           // node springs in
        let ring = phase(from: start, length: 0.16)          // ring traces closed
        let text = phase(from: start + 0.03, length: 0.14)   // copy slides in
        let count = phase(from: start + 0.03, length: 0.2)   // numbers count up
        let line = phase(from: start + 0.04, length: Self.spacing - 0.04) // line draws to the next node
        let isStreak = checkpoint.day == WalkingJourneyProjection.streakMilestoneDay
        let accent = isStreak ? ember : tint

        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.35))
                        .blur(radius: 10)
                        .scaleEffect(1 + 0.5 * sin(.pi * pop))
                        .opacity(sin(.pi * pop))
                    Circle().fill(ink)
                    Circle().stroke(.white.opacity(0.1), lineWidth: 1.5)
                    Circle()
                        .trim(from: 0, to: Ease.out(ring))
                        .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if let art = milestoneArtwork?(max(checkpoint.creatures, 1)) ?? nil {
                        art.padding(5)
                    } else {
                        Text("\(checkpoint.creatures)").font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 44, height: 44)
                .scaleEffect(0.4 + 0.6 * Ease.back(pop))
                .opacity(Ease.out(min(1, pop * 2)))
                if !isLast {
                    ZStack(alignment: .top) {
                        Capsule().fill(.white.opacity(0.07))
                        Capsule()
                            .fill(LinearGradient(colors: [accent, tint.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                            .scaleEffect(x: 1, y: Ease.inOut(line), anchor: .top)
                            .shadow(color: tint.opacity(0.6), radius: 4)
                    }
                    .frame(width: 2)
                    .frame(minHeight: 22)
                    .padding(.vertical, 3)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("DAY \(checkpoint.day)")
                        .font(.system(size: 10, weight: .bold)).tracking(1)
                        .foregroundStyle(accent)
                    if isStreak {
                        Text("3-WEEK STREAK")
                            .font(.system(size: 9, weight: .bold)).tracking(0.8)
                            .foregroundStyle(ember)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(ember.opacity(0.14), in: Capsule())
                            .scaleEffect(0.6 + 0.4 * Ease.back(phase(from: start + 0.08, length: 0.12)), anchor: .leading)
                    }
                }
                Text(title(for: checkpoint, progress: Ease.out(count)))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = detail(for: checkpoint, progress: Ease.out(count)) {
                    Text(detail)
                        .font(.footnote).foregroundStyle(.white.opacity(0.7))
                        .monospacedDigit()
                }
            }
            .padding(.top, 2)
            .padding(.bottom, isLast ? 0 : 16)
            .opacity(Ease.out(text))
            .offset(x: 18 * (1 - Ease.out(text)))
            Spacer(minLength: 0)
        }
    }

    private func title(for checkpoint: WalkingJourneyProjection.Checkpoint, progress: Double) -> String {
        if checkpoint.day == 1 { return "First Nanobeast hatches" }
        let shown = max(1, Int((Double(checkpoint.creatures) * progress).rounded()))
        return "\(shown) Nanobeasts"
    }

    private func detail(for checkpoint: WalkingJourneyProjection.Checkpoint, progress: Double) -> String? {
        guard checkpoint.day > 1 else { return nil }
        let miles = "\(Int((Double(checkpoint.miles) * progress).rounded())) mi"
        guard checkpoint.calories >= 50 else { return miles }
        let calories = "\((Int((Double(checkpoint.calories) * progress / 50).rounded()) * 50).formatted()) cal burned"
        return emphasizesBody ? "\(calories) · \(miles)" : "\(miles) · \(calories)"
    }

    // MARK: Future you

    private var futureCard: some View {
        let counted = Ease.out(phase(from: cardArrival + 0.02, length: 0.12))
        let calories = Int((journey.walkingCalories(byDay: horizon) * counted / 100).rounded()) * 100
        let pounds = journey.fatEnergyPounds(byDay: horizon)
        // Half-pound precision for small totals, whole pounds once it's bigger.
        let poundsText = pounds < 3
            ? ((pounds * 2).rounded() / 2).formatted(.number.precision(.fractionLength(0...1)))
            : Int(pounds.rounded()).formatted()
        let miles = Int((Double(journey.milesWalked(byDay: horizon)) * counted).rounded())
        let marathons = journey.marathons(byDay: horizon)
        let creatures = Int((Double(journey.creaturesInHorizon) * counted).rounded())
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DAY \(horizon)")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(tint)
                Text("By \(journey.date(forDay: horizon, from: start).formatted(.dateTime.month(.wide).day()))")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .tracking(-0.6)
            }
            // The body outcome leads, as pounds they can picture stacking up.
            if pounds >= 0.75 {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        // "Like" keeps this an energy equivalence, not a weight-loss promise.
                        Text("LIKE BURNING")
                            .font(.system(size: 11, weight: .bold)).tracking(1.4)
                            .foregroundStyle(ember)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("~\(poundsText) lb")
                                .font(.system(size: 54, weight: .heavy, design: .rounded).monospacedDigit())
                                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.8, blue: 0.4), ember],
                                                                startPoint: .top, endPoint: .bottom))
                                .shadow(color: ember.opacity(0.35), radius: 14)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text("of fat")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    PoundBlocks(pounds: pounds, progress: counted, color: ember)
                    Text("\(calories.formatted()) calories burned walking")
                        .font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(calories.formatted())
                        .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                    Text("calories burned walking")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            HStack(alignment: .top, spacing: 12) {
                statView(Stat(value: miles.formatted(),
                              label: marathons >= 1 ? "miles, about \(marathons) marathon\(marathons == 1 ? "" : "s")" : "miles"),
                         accent: false)
                divider
                statView(Stat(value: "\(creatures)", label: "Nanobeasts"), accent: false)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [tint.opacity(0.16), ink], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(tint.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private struct Stat { let value: String; let label: String }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 52)
    }

    private func statView(_ stat: Stat, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stat.value)
                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent ? tint : .white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(stat.label)
                .font(.caption2).foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

/// An illustrated comparison of additional walking above the user's baseline.
/// Both paths start at zero extra steps; the red line preserves their routine.
/// Smooth milestone segments illustrate the journey, not daily measured results.
struct WalkingPlanChart: View {
    let comparison: WalkingPlanComparison
    let tint: Color
    var elapsed: TimeInterval = WalkingPlanReveal.duration
    private let baselineColor = Color(red: 1, green: 0.38, blue: 0.43)
    private var motion: WalkingPlanReveal { .init(elapsed: elapsed) }
    private var reveal: CGFloat { CGFloat(motion.chartProgress) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("EXTRA WALKING BEYOND YOUR ROUTINE")
                .font(.system(size: 10, weight: .semibold)).tracking(0.9)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geometry in
                let inset: CGFloat = 8
                let width = max(1, geometry.size.width - inset * 2)
                let bottom = max(50, geometry.size.height - 34)
                let top: CGFloat = 34
                let origin = CGPoint(x: inset, y: bottom)
                let endX = inset + width
                let targetPath = curve(inset: inset, width: width, top: top, bottom: bottom)
                let revealedPath = targetPath.trimmedPath(from: 0, to: reveal)
                let tip = revealedPath.currentPoint ?? origin
                ZStack(alignment: .topLeading) {
                    Path { path in
                        for fraction in [0.0, 0.33, 0.66, 1.0] {
                            let y = top + (bottom - top) * fraction
                            path.move(to: CGPoint(x: inset, y: y))
                            path.addLine(to: CGPoint(x: inset + width, y: y))
                        }
                    }.stroke(.white.opacity(0.06), lineWidth: 0.5)
                    Path { path in
                        path.addPath(revealedPath)
                        path.addLine(to: CGPoint(x: tip.x, y: bottom))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.23), tint.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                    Path { path in path.move(to: origin); path.addLine(to: CGPoint(x: endX, y: bottom)) }
                        .stroke(baselineColor.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 5]))
                    revealedPath
                        .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .shadow(color: tint.opacity(0.3), radius: 7)
                    ForEach(0..<5, id: \.self) { index in
                        let fraction = CGFloat(index) / 4
                        Circle().fill(.white).frame(width: 6.5, height: 6.5)
                            .position(x: inset + width * fraction, y: bottom - (bottom - top) * fraction)
                            .opacity(tip.x >= inset + width * fraction ? 1 : 0)
                    }
                    Circle().fill(tint.opacity(0.13)).frame(width: 22, height: 22).position(tip)
                    Circle().fill(.white).frame(width: 7, height: 7).position(tip)
                    HStack { Spacer(minLength: 0); curveLabel("With Nanobeasts", color: tint) }
                    HStack { Spacer(minLength: 0); curveLabel("Without", color: baselineColor) }
                        .offset(y: bottom + 8)
                }
            }.frame(height: 210)
            HStack {
                Text("NOW"); Spacer(); Text("30 DAYS")
            }.font(.system(size: 9, weight: .medium).monospacedDigit()).tracking(0.7).foregroundStyle(.white.opacity(0.42))
            Text("Starting from about \(comparison.baselineSteps.formatted()) steps a day")
                .font(.caption2).foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [.white.opacity(0.055), .white.opacity(0.015)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Extra walking over thirty days, compared with your current routine")
        .accessibilityValue("With Nanobeasts, meeting your daily target adds \(comparison.additionalTotal) steps. Without, keeping your current routine adds \(comparison.withoutAdditionalSteps) extra steps. Your estimated current routine of \(comparison.baselineSteps) daily steps counts in both scenarios. This is an illustration, not a measured outcome.")
    }

    private func curveLabel(_ text: String, color: Color) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func curve(inset: CGFloat, width: CGFloat, top: CGFloat, bottom: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: inset, y: bottom))
            for index in 0..<4 {
                let from = CGFloat(index) / 4
                let to = CGFloat(index + 1) / 4
                let start = CGPoint(x: inset + width * from, y: bottom - (bottom - top) * from)
                let end = CGPoint(x: inset + width * to, y: bottom - (bottom - top) * to)
                let midX = (start.x + end.x) / 2
                path.addCurve(to: end, control1: CGPoint(x: midX, y: start.y),
                              control2: CGPoint(x: midX, y: end.y))
            }
        }
    }
}

/// Pure presentation shared with the lightweight design renderer.
struct WalkingPlanPreparationContent: View {
    let playerName: String
    let goal: String?
    let tint: Color
    let elapsed: TimeInterval
    var reduceMotion = false
    private var calculation: WalkingPlanPreparation { .init(elapsed: elapsed) }
    private var firstName: String { playerName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "" }

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Text(firstName.isEmpty || firstName == "Researcher" ? "Putting your plan together" : "Putting your plan together, \(firstName)")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .tracking(-0.6).fixedSize(horizontal: false, vertical: true)
                if let goal {
                    Text("Built around your goal: \(goal.lowercased()).")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.multilineTextAlignment(.center)

            ZStack {
                Circle().fill(tint.opacity(0.055)).frame(width: 166, height: 166)
                Circle().stroke(tint.opacity(0.12), lineWidth: 1).frame(width: 166, height: 166)
                Circle().trim(from: 0, to: calculation.progress)
                    .stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 184, height: 184)
                if !reduceMotion && calculation.progress < 1 {
                    Circle().trim(from: 0, to: 0.12)
                        .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 196, height: 196)
                        .rotationEffect(.degrees(elapsed * 135 - 90))
                }
                VStack(spacing: 4) {
                    Text("\(Int(calculation.progress * 100))%")
                        .font(.system(size: 45, weight: .bold, design: .rounded).monospacedDigit())
                        .tracking(-1.5)
                    Text(calculation.progress == 1 ? "READY" : "PERSONALIZING")
                        .font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(tint)
                }
            }
            .frame(height: 200)
            .accessibilityHidden(true)

            VStack(spacing: 14) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.12))
                        Capsule().fill(LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, geometry.size.width * calculation.progress))
                    }
                }.frame(height: 12)
                .accessibilityLabel("Plan preparation progress")
                .accessibilityValue("\(Int(calculation.progress * 100)) percent")
                Text(calculation.stage == 0 ? "Starting with your walking routine"
                    : calculation.stage == 1 ? "Setting a challenge that moves you forward"
                    : calculation.stage == 2 ? "Connecting your steps to creature growth"
                    : "Your walking plan is ready")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
                    .frame(minHeight: 32).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 20) {
                calculationRow(index: 0, title: "Your starting point",
                    detail: "Reviewing your walking routine")
                calculationRow(index: 1, title: "Your daily challenge",
                    detail: "Personalizing your step target")
                calculationRow(index: 2, title: "Your evolution challenge",
                    detail: "Setting your creature milestones")
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(tint.opacity(0.16), lineWidth: 1))
        }
        .foregroundStyle(.white)
    }

    private func calculationRow(index: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SolarImage(calculation.stage > index ? .checkCircle : .clock, size: 22)
                .foregroundStyle(calculation.stage >= index ? tint : .white.opacity(0.25))
                .frame(width: 22, height: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(calculation.stage > index ? "Ready to reveal" : calculation.stage == index ? detail : "Up next")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Easing curves for clock-driven choreography.
private enum Ease {
    static func out(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    static func inOut(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
    /// Overshoots slightly before settling, for a springy pop.
    static func back(_ t: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}

/// One block per pound of fat-equivalent energy, filling in as the card counts up.
private struct PoundBlocks: View {
    let pounds: Double
    let progress: Double
    let color: Color

    /// Rounded to half pounds and capped so the row always fits one line.
    private var halves: Int { min(Int((pounds * 2).rounded()), 16) }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<Int(ceil(Double(halves) / 2)), id: \.self) { index in
                let isHalf = index * 2 + 1 == halves
                let filled = progress * Double(halves) / 2 - Double(index)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(color.opacity(0.3), lineWidth: 1))
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 1, green: 0.8, blue: 0.4), color],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: geometry.size.width * min(max(filled, 0), isHalf ? 0.5 : 1))
                    }
                    Text("1 lb")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black.opacity(!isHalf && filled >= 0.6 ? 0.55 : 0))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 34)
                .frame(height: 26)
            }
        }
        .accessibilityHidden(true)
    }
}
