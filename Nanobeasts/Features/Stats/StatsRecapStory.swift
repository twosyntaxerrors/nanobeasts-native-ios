import SwiftUI

/// Full-screen, story-style monthly recap built around the Nanobeasts discovered that month.
/// Tap to advance, auto-plays, and ends on a shareable field report.
struct StatsRecapStoryView: View {
    let recap: MonthRecap
    let companion: CreatureStage
    let distanceUnit: DistanceUnitPreference

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var progress: Double = 0
    @State private var lineupImages: [UIImage] = []
    @State private var shareImage: Image?

    private static let pageDuration: Double = 5
    private static let maxDexCards = 6

    private enum Page: Hashable { case intro, dex, steps, best, goals, share }

    private var lineup: [CreatureStage] { recapLineup(recap, fallback: companion) }

    private var pages: [Page] {
        var result: [Page] = [.intro]
        if !recap.discoveries.isEmpty { result.append(.dex) }
        result.append(.steps)
        if recap.best != nil { result.append(.best) }
        result += [.goals, .share]
        return result
    }

    private var tint: Color {
        switch pages[index] {
        case .intro, .steps, .goals, .share: NanoTheme.teal
        case .dex, .best: NanoTheme.cyan
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea().opacity(0.6)
            RadialGradient(colors: [tint.opacity(0.38), .clear], center: .top, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: index)

            VStack(spacing: 0) {
                header
                page(pages[index])
                    .id(pages[index])
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        value.location.x < 110 ? step(-1) : step(1)
                    })
            }
            .padding(.horizontal, 22)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .task { await loadLineupArtwork() }
        .task(id: index) { await autoplay() }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 4) {
                ForEach(pages.indices, id: \.self) { position in
                    GeometryReader { proxy in
                        Capsule().fill(.white.opacity(0.2))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white)
                                    .frame(width: proxy.size.width * fill(for: position))
                            }
                    }
                    .frame(height: 3)
                }
            }
            HStack {
                Text("\(recap.monthName.uppercased()) RECAP")
                    .font(NanoFont.aldrich(11)).tracking(1.5)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.white.opacity(0.1)).frame(width: 34, height: 34))
                }
                .accessibilityLabel("Close recap")
            }
        }
        .padding(.top, 8)
    }

    private func fill(for position: Int) -> Double {
        position < index ? 1 : position == index ? progress : 0
    }

    // MARK: Pages

    @ViewBuilder
    private func page(_ page: Page) -> some View {
        switch page {
        case .intro: intro
        case .dex: dex
        case .steps: steps
        case .best: best
        case .goals: goals
        case .share: share
        }
    }

    private var intro: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.45), .clear], center: .center,
                                         startRadius: 8, endRadius: 150))
                    .frame(width: 300, height: 300)
                RecapLineupView(stages: lineup, size: lineup.count > 1 ? 140 : 190)
            }
            .frame(height: 230)
            Text("Your \(recap.monthName)\nin the field")
                .font(NanoFont.aldrich(36))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text(introCaption)
                .font(NanoFont.spaceMono(13))
                .foregroundStyle(NanoTheme.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
            Text("TAP TO CONTINUE")
                .font(NanoFont.aldrich(10)).tracking(1.6)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.bottom, 20)
        }
    }

    private var introCaption: String {
        let count = recap.newForms.count
        if count > 0 { return "\(count) new Dex \(count == 1 ? "entry" : "entries") this month." }
        if !recap.discoveries.isEmpty { return "A new egg joined your journey." }
        return "\(companion.name) walked every step with you."
    }

    private var dex: some View {
        let entries = Array(recap.discoveries.prefix(Self.maxDexCards))
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return VStack(spacing: 20) {
            Spacer(minLength: 8)
            Text("NEW IN YOUR DEX")
                .font(NanoFont.aldrich(11)).tracking(2)
                .foregroundStyle(tint)
            statement(dexStatement)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(entries) { entry in
                    RecapDexCard(entry: entry, tint: tint)
                }
            }
            if recap.discoveries.count > Self.maxDexCards {
                Text("+\(recap.discoveries.count - Self.maxDexCards) more in your Dex")
                    .font(NanoFont.spaceMono(12))
                    .foregroundStyle(NanoTheme.secondaryText)
            }
            Spacer(minLength: 8)
        }
    }

    private var dexStatement: String {
        let counts = Dictionary(grouping: recap.discoveries, by: \.kind).mapValues(\.count)
        var parts: [String] = []
        if let hatched = counts[.hatch] { parts.append("hatched **\(hatched)**") }
        if let evolved = counts[.evolution] { parts.append("evolved **\(evolved)**") }
        if let matured = counts[.maturity] { parts.append("fully grew **\(matured)**") }
        if let eggs = counts[.eggAcquired] { parts.append("found **\(eggs) \(eggs == 1 ? "egg" : "eggs")**") }
        guard !parts.isEmpty else { return "Your Dex grew this month." }
        let joined = parts.count == 1 ? parts[0]
            : parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        return "You \(joined)."
    }

    private var steps: some View {
        VStack(spacing: 24) {
            Spacer()
            statement("You walked **\(recap.totalSteps.formatted()) steps**.")
            VStack(spacing: 4) {
                Text(recap.distance.formatted(.number.precision(.fractionLength(1))))
                    .font(NanoFont.aldrich(76))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.6), radius: 18)
                Text(distanceUnit.pluralName.uppercased())
                    .font(NanoFont.aldrich(13)).tracking(2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            if recap.evolutionCount > 0 {
                statement("Enough to power **\(recap.evolutionCount) \(recap.evolutionCount == 1 ? "evolution" : "evolutions")**.", size: 18)
            } else if recap.marathons >= 0.5 {
                statement("That's about **\(recap.marathons.formatted(.number.precision(.fractionLength(1)))) marathons**.", size: 18)
            }
            if let delta = recap.previousMonthDelta {
                Text(delta >= 0 ? "▲ \(delta)% vs the month before" : "▼ \(abs(delta))% vs the month before")
                    .font(NanoFont.spaceMono(12, bold: true))
                    .foregroundStyle(delta >= 0 ? NanoTheme.green : NanoTheme.orange)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.07)))
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var best: some View {
        if let best = recap.best {
            VStack(spacing: 28) {
                Spacer()
                statement("Your best day was **\(best.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))** with **\(best.steps.formatted()) steps**.")
                monthBars(highlight: best)
                Spacer()
            }
        }
    }

    private var goals: some View {
        VStack(spacing: 28) {
            Spacer()
            statement("You hit your goal on **\(recap.goalDays) of \(recap.dayCount) days**.")
            goalGrid
            Text(goalCaption)
                .font(NanoFont.spaceMono(13))
                .foregroundStyle(NanoTheme.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var share: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)
            RecapShareCard(recap: recap, lineup: lineupImages, distanceUnit: distanceUnit)
                .frame(width: 300, height: 430)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: NanoTheme.teal.opacity(0.35), radius: 30)
            if let shareImage {
                ShareLink(item: shareImage,
                          preview: SharePreview("\(recap.monthName) on Nanobeasts", image: shareImage)) {
                    Label("Share recap", systemImage: "square.and.arrow.up")
                        .font(NanoFont.aldrich(15))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Capsule().fill(.white))
                }
            } else {
                ProgressView().tint(.white).frame(height: 54)
            }
            Spacer(minLength: 8)
        }
        .task(id: lineupImages.count) { renderShareImage() }
    }

    private var goalCaption: String {
        let rate = Double(recap.goalDays) / Double(max(recap.dayCount, 1))
        switch rate {
        case 0.8...: return "Legendary consistency."
        case 0.5..<0.8: return "More hits than misses. That's how evolutions happen."
        case 0.2..<0.5: return "A solid base to build on this month."
        default: return "Every step still counted toward growth."
        }
    }

    private func statement(_ markup: String, size: CGFloat = 26) -> some View {
        InsightText(line: InsightLine(markup.components(separatedBy: "**").enumerated().compactMap { index, text in
            text.isEmpty ? nil : InsightLine.Run(text: text, isHighlighted: !index.isMultiple(of: 2))
        }), tint: tint)
            .font(NanoFont.aldrich(size))
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func monthBars(highlight: TrendPoint) -> some View {
        let peak = max(recap.days.map(\.steps).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(recap.days) { day in
                let isBest = day.date == highlight.date
                Capsule()
                    .fill(isBest
                          ? AnyShapeStyle(LinearGradient(colors: [NanoTheme.teal, NanoTheme.cyan], startPoint: .bottom, endPoint: .top))
                          : AnyShapeStyle(Color.white.opacity(0.14)))
                    .frame(height: max(4, 190 * CGFloat(day.steps) / CGFloat(peak)))
                    .shadow(color: isBest ? tint.opacity(0.8) : .clear, radius: 10)
            }
        }
        .frame(height: 190, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private var goalGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(recap.days.indices, id: \.self) { position in
                let hit = recap.goalHits[position]
                Circle()
                    .fill(hit ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.1)))
                    .shadow(color: hit ? tint.opacity(0.7) : .clear, radius: 5)
                    .frame(width: 26, height: 26)
            }
        }
        .frame(maxWidth: 270)
        .accessibilityHidden(true)
    }

    // MARK: Playback

    private func step(_ delta: Int) {
        let next = index + delta
        guard pages.indices.contains(next) else {
            if delta > 0 { dismiss() }
            return
        }
        progress = 0
        withAnimation(.easeOut(duration: 0.25)) { index = next }
    }

    private func autoplay() async {
        progress = 0
        // The share page waits for the reader; reduced motion never auto-advances.
        guard pages[index] != .share, !reduceMotion else {
            progress = 1
            return
        }
        let duration = pages[index] == .dex ? Self.pageDuration * 1.6 : Self.pageDuration
        let start = Date.now
        while !Task.isCancelled {
            let elapsed = Date.now.timeIntervalSince(start)
            progress = min(elapsed / duration, 1)
            if elapsed >= duration { step(1); return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func loadLineupArtwork() async {
        var images: [UIImage] = []
        for stage in lineup {
            if let data = try? await R2ArtworkCache.shared.data(for: R2AssetManifest.url(for: stage.imageKey)),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        lineupImages = images
    }

    @MainActor
    private func renderShareImage() {
        let renderer = ImageRenderer(content:
            RecapShareCard(recap: recap, lineup: lineupImages, distanceUnit: distanceUnit)
                .frame(width: 360, height: 516))
        renderer.scale = 3
        if let image = renderer.uiImage { shareImage = Image(uiImage: image) }
    }
}

/// One discovery, styled like a Dex entry.
private struct RecapDexCard: View {
    let entry: RecapDiscovery
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ScannerBrackets(length: 10)
                    .stroke(tint.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                CreatureArtworkView(stage: entry.stage)
                    .padding(10)
            }
            .frame(height: 92)
            Text(entry.stage.name)
                .font(NanoFont.aldrich(13))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("\(entry.kind.title) · \(entry.date.formatted(.dateTime.month(.abbreviated).day()))")
                .font(NanoFont.spaceMono(9, bold: true))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.stage.name), \(entry.kind.title.lowercased()) \(entry.date.formatted(date: .abbreviated, time: .omitted))")
    }
}

/// Dex-style "field report" card used on the last story page and as the shared image.
private struct RecapShareCard: View {
    let recap: MonthRecap
    let lineup: [UIImage]
    let distanceUnit: DistanceUnitPreference

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("NANOBEASTS")
                        .font(NanoFont.aldrich(13)).tracking(2.5)
                    Spacer()
                    Text("FIELD REPORT")
                        .font(NanoFont.spaceMono(10, bold: true))
                        .foregroundStyle(NanoTheme.teal)
                }
                .foregroundStyle(.white)

                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [NanoTheme.teal.opacity(0.45), .clear], center: .center,
                                             startRadius: 6, endRadius: 120))
                    HStack(spacing: -26) {
                        ForEach(lineup.indices.reversed(), id: \.self) { position in
                            Image(uiImage: lineup[position]).resizable().scaledToFit()
                                .frame(width: lineup.count > 1 ? 120 : 160)
                                .zIndex(Double(lineup.count - position))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)

                Text(recap.monthName.uppercased())
                    .font(NanoFont.aldrich(34))
                    .foregroundStyle(.white)
                Text(recap.newForms.isEmpty
                     ? "\(recap.month.formatted(.dateTime.year())) field report"
                     : "\(recap.newForms.count) new Dex \(recap.newForms.count == 1 ? "entry" : "entries")")
                    .font(NanoFont.spaceMono(12))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .padding(.bottom, 18)

                HStack(spacing: 0) {
                    stat(recap.totalSteps.formatted(.number.notation(.compactName)), "STEPS")
                    stat(recap.distance.formatted(.number.precision(.fractionLength(1))),
                         distanceUnit.abbreviation)
                    stat("\(recap.goalDays)/\(recap.dayCount)", "GOAL DAYS")
                }
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(width: 360, height: 516)
            .background {
                ZStack {
                    Color(red: 0.035, green: 0.035, blue: 0.043)
                    LabGridBackground()
                    RadialGradient(colors: [NanoTheme.cyan.opacity(0.3), .clear],
                                   center: .top, startRadius: 0, endRadius: 360)
                }
            }
            .scaleEffect(proxy.size.width / 360, anchor: .topLeading)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(NanoFont.aldrich(20)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(NanoFont.aldrich(8)).tracking(1.2).foregroundStyle(NanoTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
    }
}
