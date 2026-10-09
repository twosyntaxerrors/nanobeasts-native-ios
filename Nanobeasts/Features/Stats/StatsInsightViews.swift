import Charts
import SwiftUI

// MARK: - Shared chrome

/// Dark panel lit from the top by its tint, with a hairline edge that fades downward.
struct StatsPanelModifier: ViewModifier {
    var tint: Color = NanoTheme.teal
    var glow: Double = 0.16
    var radius: CGFloat = 28
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(NanoTheme.panel)
                    .overlay {
                        RadialGradient(colors: [tint.opacity(glow), .clear],
                                       center: .top, startRadius: 0, endRadius: 280)
                            .clipShape(shape)
                    }
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(colors: [NanoTheme.ink.opacity(0.13), NanoTheme.ink.opacity(0.03)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    }
            }
    }
}

extension View {
    /// Renders shadowed content into one bitmap, so scrolling moves a finished
    /// image instead of recomputing every shadow each frame. The margin keeps
    /// the shadows from being clipped.
    func flattenedShadows(margin: CGFloat) -> some View {
        padding(margin).drawingGroup().padding(-margin)
    }

    func statsPanel(tint: Color = NanoTheme.teal, glow: Double = 0.16, padding: CGFloat = 18) -> some View {
        modifier(StatsPanelModifier(tint: tint, glow: glow, padding: padding))
    }
}

/// Numbered dex-style section label: `03  TRENDS ───────`.
struct StatsSectionHeader<Trailing: View>: View {
    let number: Int
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", number))
                .font(NanoFont.spaceMono(11, bold: true))
                .foregroundStyle(NanoTheme.teal)
            Text(title)
                .font(NanoFont.aldrich(14))
                .tracking(1.4)
                .foregroundStyle(NanoTheme.text)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
            Rectangle()
                .fill(LinearGradient(colors: [NanoTheme.ink.opacity(0.14), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .frame(minWidth: 8)
            trailing
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension StatsSectionHeader where Trailing == EmptyView {
    init(number: Int, title: String) {
        self.init(number: number, title: title) { EmptyView() }
    }
}

/// Renders an `InsightLine`, coloring its highlighted runs.
struct InsightText: View {
    let line: InsightLine
    var tint: Color = NanoTheme.teal
    var base: Color = NanoTheme.text

    var body: some View {
        line.runs.reduce(Text(verbatim: "")) { partial, run in
            let piece = Text(verbatim: run.text).foregroundColor(run.isHighlighted ? tint : base)
            return Text("\(partial)\(piece)")
        }
    }
}

/// Opal-style segmented range control.
struct StatsRangePicker: View {
    @Binding var range: TrendRange

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TrendRange.allCases) { option in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { range = option }
                } label: {
                    Text(option.rawValue)
                        .font(NanoFont.aldrich(12))
                        .foregroundStyle(range == option ? NanoTheme.onAccent : NanoTheme.secondaryText)
                        .frame(width: 38, height: 30)
                        .background(Capsule().fill(range == option ? NanoTheme.teal : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityName)
                .accessibilityAddTraits(range == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(NanoTheme.ink.opacity(0.06)))
    }
}

/// Four corner brackets, like a scanner viewfinder.
struct ScannerBrackets: Shape {
    var length: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                 (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                 (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x + dx * length, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * length))
        }
        return path
    }
}

// MARK: - Trends

struct StatsTrendsCard: View {
    let trends: [TrendRange: TrendSnapshot]
    let dailyGoal: Int

    @State private var range: TrendRange = .week
    @State private var selectedDate: Date?

    var body: some View {
        if let snapshot = trends[range] {
            content(snapshot)
                .statsPanel()
                .onChange(of: range) { selectedDate = nil }
        }
    }

    private func content(_ snapshot: TrendSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AVG / DAY")
                        .font(NanoFont.aldrich(9)).tracking(1.2)
                        .foregroundStyle(NanoTheme.secondaryText)
                    Text(snapshot.averageSteps.formatted())
                        .font(NanoFont.aldrich(30))
                        .foregroundStyle(NanoTheme.text)
                        .contentTransition(.numericText())
                }
                Spacer()
                StatsRangePicker(range: $range)
            }

            InsightText(line: snapshot.headline)
                .font(NanoFont.aldrich(15))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            chart(snapshot)

            HStack(spacing: 0) {
                metric("GOAL DAYS", "\(snapshot.goalDays)/\(snapshot.dayCount)", tint: NanoTheme.text)
                divider
                metric("TOTAL", snapshot.totalSteps.formatted(.number.notation(.compactName)), tint: NanoTheme.text)
                divider
                if let delta = snapshot.deltaPercent {
                    metric("VS PREV", "\(delta >= 0 ? "▲" : "▼") \(abs(delta))%",
                           tint: delta >= 0 ? NanoTheme.green : NanoTheme.orange)
                } else {
                    metric("VS PREV", "—", tint: NanoTheme.secondaryText)
                }
            }
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(NanoTheme.ink.opacity(0.04)))
        }
    }

    private var divider: some View {
        Rectangle().fill(NanoTheme.ink.opacity(0.08)).frame(width: 1, height: 28)
    }

    private func metric(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(NanoFont.aldrich(16))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title)
                .font(NanoFont.aldrich(8)).tracking(1.1)
                .foregroundStyle(NanoTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func highlighted(in snapshot: TrendSnapshot) -> TrendPoint? {
        guard let selectedDate else { return snapshot.best }
        let unit: Calendar.Component = snapshot.range == .year ? .month : .day
        return snapshot.points.first {
            Calendar.autoupdatingCurrent.isDate($0.date, equalTo: selectedDate, toGranularity: unit)
        } ?? snapshot.best
    }

    private func chart(_ snapshot: TrendSnapshot) -> some View {
        let focus = highlighted(in: snapshot)
        let unit: Calendar.Component = snapshot.range == .year ? .month : .day
        return Chart {
            ForEach(snapshot.points) { point in
                let isFocus = point.date == focus?.date
                BarMark(x: .value("Date", point.date, unit: unit),
                        y: .value("Steps", point.steps),
                        width: .ratio(snapshot.range == .month ? 0.7 : 0.55))
                    .clipShape(RoundedRectangle(cornerRadius: snapshot.range == .month ? 3 : 6))
                    .foregroundStyle(isFocus
                        ? LinearGradient(colors: [NanoTheme.teal, NanoTheme.teal.opacity(0.35)],
                                         startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [NanoTheme.ink.opacity(0.24), NanoTheme.ink.opacity(0.06)],
                                         startPoint: .top, endPoint: .bottom))
                    .annotation(position: .top, spacing: 4) {
                        if isFocus, point.steps > 0 {
                            Text(point.steps.formatted(.number.notation(.compactName)))
                                .font(NanoFont.spaceMono(10, bold: true))
                                .foregroundStyle(NanoTheme.teal)
                        }
                    }
            }
            RuleMark(y: .value("Goal", dailyGoal))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .foregroundStyle(NanoTheme.text.opacity(0.32))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text("GOAL")
                        .font(NanoFont.aldrich(7)).tracking(1)
                        .foregroundStyle(NanoTheme.text.opacity(0.4))
                }
        }
        .chartYScale(domain: 0...snapshot.chartMaximum)
        .chartYAxis(.hidden)
        .chartXAxis {
            switch snapshot.range {
            case .week:
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            case .month:
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            case .year:
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .font(NanoFont.aldrich(9))
        .foregroundStyle(NanoTheme.secondaryText)
        .frame(height: 170)
        .animation(.snappy(duration: 0.3), value: snapshot.range)
        .accessibilityLabel("\(snapshot.range.accessibilityName) steps chart")
        .accessibilityValue(snapshot.headline.plainText)
    }
}

// MARK: - Rhythm

struct StatsRhythmCard: View {
    let rhythm: RhythmSnapshot?

    var body: some View {
        Group {
            if let rhythm {
                content(rhythm)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(NanoTheme.teal)
                    Text("Your daily rhythm appears after about a week of walking.")
                        .font(NanoFont.spaceMono(12))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
        }
        .statsPanel(tint: NanoTheme.cyan, glow: 0.18)
    }

    private func content(_ rhythm: RhythmSnapshot) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                InsightText(line: rhythm.headline)
                    .font(NanoFont.aldrich(20))
                if let pace = rhythm.todayPace {
                    InsightText(line: pace, tint: rhythm.todayIsAhead ? NanoTheme.green : NanoTheme.orange,
                                base: NanoTheme.secondaryText)
                        .font(NanoFont.spaceMono(12))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(NanoTheme.ink.opacity(0.05)))
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                let peak = max(rhythm.hourlyAverages.max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<24, id: \.self) { hour in
                        let isPeak = rhythm.peakHours.contains(hour)
                        let fraction = CGFloat(rhythm.hourlyAverages[hour]) / CGFloat(peak)
                        Capsule()
                            .fill(isPeak
                                  ? AnyShapeStyle(LinearGradient(colors: [NanoTheme.teal, NanoTheme.cyan],
                                                                 startPoint: .bottom, endPoint: .top))
                                  : AnyShapeStyle(NanoTheme.ink.opacity(0.13)))
                            .frame(height: max(4, 74 * fraction))
                            .shadow(color: isPeak ? NanoTheme.teal.opacity(0.7) : .clear, radius: isPeak ? 6 : 0)
                    }
                }
                .frame(height: 74, alignment: .bottom)
                .flattenedShadows(margin: 12)
                HStack {
                    let labels = ["12A", "6A", "12P", "6P", "12A"]
                    ForEach(labels.indices, id: \.self) { index in
                        Text(labels[index])
                        if index < labels.count - 1 { Spacer(minLength: 0) }
                    }
                }
                .font(NanoFont.spaceMono(9))
                .foregroundStyle(NanoTheme.mutedText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Average steps by hour of day")
            .accessibilityValue(rhythm.headline.plainText)

            HStack(spacing: 10) {
                weekdayTile(rhythm)
                weekendTile(rhythm)
            }

            Text("Based on your last \(rhythm.sampledDays) days")
                .font(NanoFont.spaceMono(10))
                .foregroundStyle(NanoTheme.mutedText)
        }
    }

    private func weekdayTile(_ rhythm: RhythmSnapshot) -> some View {
        let symbols = Calendar.autoupdatingCurrent.veryShortWeekdaySymbols
        let peak = max(rhythm.weekdayAverages.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("STRONGEST DAY")
                .font(NanoFont.aldrich(8)).tracking(1.2)
                .foregroundStyle(NanoTheme.secondaryText)
            Text(Calendar.autoupdatingCurrent.weekdaySymbols[rhythm.bestWeekday])
                .font(NanoFont.aldrich(17))
                .foregroundStyle(NanoTheme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<7, id: \.self) { day in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day == rhythm.bestWeekday ? NanoTheme.teal : NanoTheme.ink.opacity(0.14))
                            .frame(height: max(3, 30 * CGFloat(rhythm.weekdayAverages[day]) / CGFloat(peak)))
                        Text(symbols[day])
                            .font(NanoFont.spaceMono(8))
                            .foregroundStyle(day == rhythm.bestWeekday ? NanoTheme.teal : NanoTheme.mutedText)
                    }
                }
            }
            .frame(height: 44, alignment: .bottom)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(NanoTheme.ink.opacity(0.04)))
        .accessibilityElement(children: .combine)
    }

    private func weekendTile(_ rhythm: RhythmSnapshot) -> some View {
        let lift = rhythm.weekendLiftPercent
        let tint = lift >= 0 ? NanoTheme.green : NanoTheme.orange
        return VStack(alignment: .leading, spacing: 10) {
            Text("WEEKENDS")
                .font(NanoFont.aldrich(8)).tracking(1.2)
                .foregroundStyle(NanoTheme.secondaryText)
            Text("\(lift >= 0 ? "+" : "−")\(abs(lift))%")
                .font(NanoFont.aldrich(26))
                .foregroundStyle(tint)
            Text(lift >= 0 ? "more than weekdays" : "less than weekdays")
                .font(NanoFont.spaceMono(10))
                .foregroundStyle(NanoTheme.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(NanoTheme.ink.opacity(0.04)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Records

struct StatsRecordsGrid: View {
    let records: [PersonalRecord]
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(record.title)
                            .font(NanoFont.aldrich(8)).tracking(1.2)
                            .foregroundStyle(NanoTheme.teal)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if record.isNew {
                            Text("NEW")
                                .font(NanoFont.aldrich(8)).tracking(1)
                                .foregroundStyle(NanoTheme.onAccent)
                                .padding(.horizontal, 6).frame(height: 16)
                                .background(Capsule().fill(NanoTheme.teal))
                        } else {
                            Text(String(format: "#%02d", index + 1))
                                .font(NanoFont.spaceMono(9))
                                .foregroundStyle(NanoTheme.mutedText)
                        }
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(record.value)
                            .font(NanoFont.aldrich(22))
                            .foregroundStyle(NanoTheme.text)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        if !record.unit.isEmpty {
                            Text(record.unit)
                                .font(NanoFont.aldrich(10))
                                .foregroundStyle(NanoTheme.secondaryText)
                        }
                    }
                    Text(record.caption)
                        .font(NanoFont.spaceMono(10))
                        .foregroundStyle(NanoTheme.mutedText)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(NanoTheme.panel)
                        .overlay(alignment: .topLeading) {
                            // A notched accent along the top edge, like a dex data plate.
                            Capsule().fill(NanoTheme.teal.opacity(0.7))
                                .frame(width: 22, height: 2)
                                .padding(.leading, 14)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(NanoTheme.ink.opacity(0.07), lineWidth: 1)
                        }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Recap entry

/// The Nanobeasts a recap is about: new forms first, then eggs, else the current companion.
func recapLineup(_ recap: MonthRecap, fallback: CreatureStage) -> [CreatureStage] {
    var seen = Set<String>()
    let pool = (recap.newForms.reversed() + recap.discoveries.filter { $0.kind == .eggAcquired }.reversed())
        .map(\.stage)
        .filter { seen.insert($0.id).inserted }
    return pool.isEmpty ? [fallback] : Array(pool.prefix(3))
}

/// Up to three overlapping creatures, the newest in front.
struct RecapLineupView: View {
    let stages: [CreatureStage]
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            ForEach(Array(stages.enumerated().reversed()), id: \.element.id) { position, stage in
                // Downsampled to the display size: full 1024px art was decoded
                // and shadowed for a card under 100pt wide.
                CreatureArtworkView(stage: stage, maxPixel: Int(size * 3))
                    .frame(width: size * (position == 0 ? 1 : 0.78), height: size * (position == 0 ? 1 : 0.78))
                    .offset(x: CGFloat(position) * -size * 0.48, y: CGFloat(position) * -size * 0.08)
                    .shadow(color: NanoTheme.shadow.opacity(0.35), radius: 10, y: 6)
            }
        }
        .frame(width: size * (1 + 0.48 * CGFloat(max(stages.count - 1, 0))), height: size, alignment: .trailing)
        .flattenedShadows(margin: 24)
        .accessibilityHidden(true)
    }
}

struct StatsRecapCard: View {
    let recap: MonthRecap
    let fallbackStage: CreatureStage
    let onOpen: () -> Void

    private var subtitle: String {
        let entries = recap.newForms.count
        let discoveries = entries == 0 ? "" : " · \(entries) new Dex \(entries == 1 ? "entry" : "entries")"
        return "\(recap.totalSteps.formatted(.number.notation(.compactName))) steps\(discoveries)"
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR MONTH IN THE FIELD")
                            .font(NanoFont.aldrich(10)).tracking(1.5)
                            .foregroundStyle(NanoTheme.text.opacity(0.75))
                        Text(recap.monthName)
                            .font(NanoFont.aldrich(34))
                            .foregroundStyle(NanoTheme.text)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(subtitle)
                            .font(NanoFont.spaceMono(11))
                            .foregroundStyle(NanoTheme.text.opacity(0.8))
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .bottom) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                        Text("PLAY RECAP").font(NanoFont.aldrich(11)).tracking(1)
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(Capsule().fill(.white))
                    Spacer(minLength: 8)
                    RecapLineupView(stages: recapLineup(recap, fallback: fallbackStage), size: 92)
                }
                .padding(.top, 10)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Accent-tinted over a dark base so white type reads on every accent.
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(NanoTheme.panel)
                    .overlay {
                        LinearGradient(colors: [NanoTheme.teal.opacity(0.62), NanoTheme.cyan.opacity(0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    .overlay(alignment: .topTrailing) {
                        // Oversized month numeral as texture.
                        Text(recap.month.formatted(.dateTime.month(.twoDigits)))
                            .font(NanoFont.aldrich(150))
                            .foregroundStyle(NanoTheme.text.opacity(0.08))
                            .offset(x: 14, y: -34)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel("\(recap.monthName) recap. \(subtitle).")
        .accessibilityHint("Plays your monthly recap")
    }
}

/// Shown until the first finished month exists: what the recap is and when it unlocks.
struct StatsRecapTeaser: View {
    let companion: CreatureStage
    var now = Date.now

    private var calendar: Calendar { .autoupdatingCurrent }

    private var month: DateInterval? { calendar.dateInterval(of: .month, for: now) }

    private var unlockDay: Date? {
        month.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) }
    }

    private var daysLeft: Int {
        guard let unlockDay else { return 0 }
        return max(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: unlockDay).day ?? 0, 1)
    }

    private var monthProgress: Double {
        guard let month else { return 0 }
        return min(max(now.timeIntervalSince(month.start) / month.duration, 0), 1)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                    Text("UNLOCKS \(unlockDay.map { $0.formatted(.dateTime.month(.abbreviated).day()) }?.uppercased() ?? "SOON")")
                        .font(NanoFont.aldrich(10)).tracking(1.4)
                }
                .foregroundStyle(NanoTheme.teal)
                Text("\(now.formatted(.dateTime.month(.wide))) recap")
                    .font(NanoFont.aldrich(24))
                    .foregroundStyle(NanoTheme.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Every step and Nanobeast you find this month goes in it.")
                    .font(NanoFont.spaceMono(11))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 5) {
                    GeometryReader { proxy in
                        Capsule().fill(NanoTheme.ink.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule().fill(NanoTheme.teal)
                                    .frame(width: proxy.size.width * monthProgress)
                            }
                    }
                    .frame(height: 6)
                    Text("\(daysLeft) \(daysLeft == 1 ? "day" : "days") to go")
                        .font(NanoFont.spaceMono(10))
                        .foregroundStyle(NanoTheme.mutedText)
                }
                .padding(.top, 4)
            }
            CreatureArtworkView(stage: companion, maxPixel: 252)
                .frame(width: 84, height: 84)
                .saturation(0)
                .opacity(0.35)
                .accessibilityHidden(true)
        }
        .statsPanel(glow: 0.12)
        .accessibilityElement(children: .combine)
    }
}
