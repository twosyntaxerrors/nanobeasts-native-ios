import Charts
import SwiftUI

struct ActionableInsightsCard: View {
    let analyticsRecords: [DailyStepRecord]
    let hourlyRecords: [HourlyStepRecord]
    let journeyRecords: [DailyStepRecord]
    let goalHistory: [DailyGoalRecord]
    let currentGoal: Int
    let stepsRemaining: Int
    let creatureName: String

    @State private var range: ActivityInsightRange = .sevenDays

    private var snapshot: ActivityInsightSnapshot {
        ActivityInsightSnapshot(
            range: range,
            analyticsRecords: analyticsRecords,
            hourlyRecords: hourlyRecords,
            journeyRecords: journeyRecords,
            goalHistory: goalHistory,
            currentGoal: currentGoal,
            stepsRemaining: stepsRemaining,
            creatureName: creatureName
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            archiveNotice
            rangePicker
            trendCard
            paceCard
            insightGrid
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(NanoTheme.teal.opacity(0.025))
                .stroke(NanoTheme.teal.opacity(0.34), lineWidth: 1)
        )
        .animation(.smooth(duration: 0.32), value: range)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("ACTIVITY INTELLIGENCE")
                .font(NanoFont.aldrich(16))
                .tracking(1.1)
                .foregroundStyle(NanoTheme.teal)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Rectangle()
                .fill(NanoTheme.teal.opacity(0.55))
                .frame(height: 1)
        }
    }

    private var archiveNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NanoTheme.teal)

            Text("Imported Health history is insight-only. It never unlocks badges or advances evolutions.")
                .font(NanoFont.aldrich(8))
                .foregroundStyle(NanoTheme.secondaryText)
                .lineSpacing(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(NanoTheme.teal.opacity(0.055))
                .stroke(NanoTheme.teal.opacity(0.20), lineWidth: 1)
        )
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(ActivityInsightRange.allCases) { option in
                Button {
                    range = option
                } label: {
                    Text(option.rawValue)
                        .font(NanoFont.aldrich(9))
                        .foregroundStyle(
                            range == option ? NanoTheme.background : NanoTheme.secondaryText
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            Capsule()
                                .fill(range == option ? NanoTheme.teal : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(NanoTheme.surface)
                .stroke(NanoTheme.elevated, lineWidth: 1)
        )
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.primaryHeadline)
                        .font(NanoFont.aldrich(11))
                        .tracking(0.6)
                        .foregroundStyle(NanoTheme.teal)
                    Text(snapshot.primaryNarrative)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineSpacing(2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(snapshot.averageSteps.formatted())
                        .font(NanoFont.aldrich(25))
                        .foregroundStyle(.white)
                    Text("AVG / DAY")
                        .font(NanoFont.aldrich(7))
                        .tracking(1)
                        .foregroundStyle(NanoTheme.secondaryText)
                }
            }

            if snapshot.points.isEmpty {
                ContentUnavailableView(
                    "Learning your movement",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Connect Apple Health or take your first steps to begin.")
                )
                .frame(height: 164)
                .foregroundStyle(NanoTheme.secondaryText)
            } else {
                Chart {
                    ForEach(snapshot.points) { point in
                        BarMark(
                            x: .value("Period", point.date, unit: snapshot.chartUnit),
                            y: .value("Steps", point.steps)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    NanoTheme.teal.opacity(0.42),
                                    NanoTheme.teal
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(5)
                    }

                    if range.showsDailyGoalLine {
                        RuleMark(y: .value("Daily goal", currentGoal))
                            .foregroundStyle(NanoTheme.orange.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                            .foregroundStyle(NanoTheme.elevated.opacity(0.55))
                        AxisValueLabel {
                            if let steps = value.as(Int.self) {
                                Text(steps.formatted(.number.notation(.compactName)))
                                    .font(NanoFont.aldrich(7))
                                    .foregroundStyle(NanoTheme.mutedText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: range.axisLabelCount)) { value in
                        AxisGridLine().foregroundStyle(.clear)
                        AxisValueLabel(format: snapshot.axisFormat)
                            .font(NanoFont.aldrich(7))
                            .foregroundStyle(NanoTheme.mutedText)
                    }
                }
                .frame(height: 164)
                .accessibilityLabel(snapshot.chartAccessibilityLabel)
            }
        }
        .nanoHUDCard(tint: NanoTheme.teal, radius: 18, padding: 15, illuminated: true)
    }

    private var paceCard: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: snapshot.paceSymbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(snapshot.paceTint)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(snapshot.paceTint.opacity(0.10))
                        .stroke(snapshot.paceTint.opacity(0.38), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text("TODAY’S PACE")
                    .font(NanoFont.aldrich(9))
                    .tracking(1.1)
                    .foregroundStyle(snapshot.paceTint)
                Text(snapshot.paceNarrative)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nanoHUDCard(tint: snapshot.paceTint, radius: 17, padding: 14)
    }

    private var insightGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            InsightMetricCard(
                symbol: "flag.checkered",
                label: "GOAL CONSISTENCY",
                value: snapshot.goalCompletionValue,
                caption: snapshot.goalCompletionCaption,
                tint: Color(red: 0.26, green: 0.92, blue: 0.52)
            )

            InsightMetricCard(
                symbol: "trophy.fill",
                label: "BEST DAY",
                value: snapshot.bestDayValue,
                caption: snapshot.bestDayCaption,
                tint: Color(red: 0.24, green: 0.72, blue: 1)
            )

            InsightMetricCard(
                symbol: "clock.fill",
                label: "ACTIVE WINDOW",
                value: snapshot.activeWindowValue,
                caption: snapshot.activeWindowCaption,
                tint: Color(red: 0.78, green: 0.48, blue: 1)
            )

            InsightMetricCard(
                symbol: "sparkles",
                label: "EVOLUTION FORECAST",
                value: snapshot.evolutionValue,
                caption: snapshot.evolutionCaption,
                tint: NanoTheme.orange
            )
        }
    }
}

private struct InsightMetricCard: View {
    let symbol: String
    let label: String
    let value: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .font(NanoFont.aldrich(7))
            .tracking(0.65)
            .foregroundStyle(tint)

            Text(value)
                .font(NanoFont.aldrich(21))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.58)

            Text(caption)
                .font(NanoFont.aldrich(7))
                .foregroundStyle(NanoTheme.secondaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .nanoHUDCard(tint: tint, radius: 16, padding: 12)
    }
}

private enum ActivityInsightRange: String, CaseIterable, Identifiable {
    case sevenDays = "7D"
    case fourWeeks = "4W"
    case threeMonths = "3M"
    case oneYear = "1Y"

    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .sevenDays: 7
        case .fourWeeks: 28
        case .threeMonths: 90
        case .oneYear: 365
        }
    }

    var axisLabelCount: Int {
        switch self {
        case .sevenDays: 7
        case .fourWeeks: 4
        case .threeMonths: 6
        case .oneYear: 6
        }
    }

    var showsDailyGoalLine: Bool {
        self == .sevenDays || self == .fourWeeks
    }

    var accessibilityLabel: String {
        switch self {
        case .sevenDays: "Seven days"
        case .fourWeeks: "Four weeks"
        case .threeMonths: "Three months"
        case .oneYear: "One year"
        }
    }
}

private struct ActivityTrendPoint: Identifiable {
    let date: Date
    let steps: Int

    var id: Date { date }
}

private struct ActivityInsightSnapshot {
    let range: ActivityInsightRange
    let points: [ActivityTrendPoint]
    let averageSteps: Int
    let primaryHeadline: String
    let primaryNarrative: String
    let paceNarrative: String
    let paceSymbol: String
    let paceTint: Color
    let goalCompletionValue: String
    let goalCompletionCaption: String
    let bestDayValue: String
    let bestDayCaption: String
    let activeWindowValue: String
    let activeWindowCaption: String
    let evolutionValue: String
    let evolutionCaption: String

    private let calendar = Calendar.autoupdatingCurrent

    init(
        range: ActivityInsightRange,
        analyticsRecords: [DailyStepRecord],
        hourlyRecords: [HourlyStepRecord],
        journeyRecords: [DailyStepRecord],
        goalHistory: [DailyGoalRecord],
        currentGoal: Int,
        stepsRemaining: Int,
        creatureName: String
    ) {
        self.range = range
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let currentStart = calendar.date(
            byAdding: .day,
            value: -(range.dayCount - 1),
            to: today
        ) ?? today
        let previousStart = calendar.date(
            byAdding: .day,
            value: -range.dayCount,
            to: currentStart
        ) ?? currentStart

        let currentRecords = analyticsRecords.filter {
            let day = calendar.startOfDay(for: $0.day)
            return day >= currentStart && day <= today
        }
        let previousRecords = analyticsRecords.filter {
            let day = calendar.startOfDay(for: $0.day)
            return day >= previousStart && day < currentStart
        }

        points = Self.makePoints(
            records: currentRecords,
            range: range,
            calendar: calendar
        )

        let currentTotal = currentRecords.reduce(0) { $0 + $1.steps }
        averageSteps = range.dayCount > 0 ? currentTotal / range.dayCount : 0
        let previousTotal = previousRecords.reduce(0) { $0 + $1.steps }
        let previousAverage =
            previousRecords.isEmpty ? 0 : previousTotal / range.dayCount

        if currentRecords.isEmpty {
            primaryHeadline = "BUILDING YOUR BASELINE"
            primaryNarrative = "Your first movement pattern will appear here."
        } else if previousRecords.isEmpty || previousAverage == 0 {
            primaryHeadline = "\(range.accessibilityLabel.uppercased()) AVERAGE"
            primaryNarrative = "\(averageSteps.formatted()) steps per day so far."
        } else {
            let change = Int(
                ((Double(averageSteps - previousAverage) / Double(previousAverage)) * 100)
                    .rounded()
            )
            primaryHeadline = change >= 0 ? "MOMENTUM RISING" : "MOMENTUM CHECK"
            primaryNarrative =
                change >= 0
                    ? "Your average is \(abs(change))% higher than the previous period."
                    : "Your average is \(abs(change))% lower than the previous period."
        }

        let pace = Self.makePace(
            hourlyRecords: hourlyRecords,
            calendar: calendar
        )
        paceNarrative = pace.narrative
        paceSymbol = pace.symbol
        paceTint = pace.tint

        let journeyInRange = journeyRecords.filter {
            let day = calendar.startOfDay(for: $0.day)
            return day >= currentStart && day <= today
        }
        if journeyInRange.isEmpty {
            goalCompletionValue = "—"
            goalCompletionCaption = "Begins with your Nanobeasts journey"
        } else {
            let completed = journeyInRange.filter { record in
                record.steps >= Self.goal(
                    for: record.day,
                    history: goalHistory,
                    fallback: currentGoal,
                    calendar: calendar
                )
            }.count
            let percentage = Int(
                (Double(completed) / Double(journeyInRange.count) * 100).rounded()
            )
            goalCompletionValue = "\(percentage)%"
            goalCompletionCaption =
                "\(completed) OF \(journeyInRange.count) JOURNEY DAYS"
        }

        if let best = currentRecords.max(by: { $0.steps < $1.steps }), best.steps > 0 {
            bestDayValue = best.steps.formatted(.number.notation(.compactName))
            bestDayCaption = best.day.formatted(.dateTime.month(.abbreviated).day()).uppercased()
        } else {
            bestDayValue = "—"
            bestDayCaption = "NO ACTIVITY YET"
        }

        let activeWindow = Self.makeActiveWindow(
            hourlyRecords: hourlyRecords,
            calendar: calendar
        )
        activeWindowValue = activeWindow.value
        activeWindowCaption = activeWindow.caption

        let recent = analyticsRecords
            .filter { $0.day >= (calendar.date(byAdding: .day, value: -6, to: today) ?? today) }
        let recentAverage = recent.isEmpty
            ? 0
            : recent.reduce(0) { $0 + $1.steps } / max(recent.count, 1)
        if stepsRemaining <= 0 {
            evolutionValue = "READY"
            evolutionCaption = "\(creatureName.uppercased()) SIGNAL COMPLETE"
        } else if recentAverage > 0 {
            let days = max(Int(ceil(Double(stepsRemaining) / Double(recentAverage))), 1)
            evolutionValue = days == 1 ? "~1 DAY" : "~\(days) DAYS"
            evolutionCaption = "\(stepsRemaining.formatted()) STEPS REMAINING"
        } else {
            evolutionValue = "—"
            evolutionCaption = "WALK TO BUILD A FORECAST"
        }
    }

    var chartUnit: Calendar.Component {
        switch range {
        case .sevenDays, .fourWeeks: .day
        case .threeMonths: .weekOfYear
        case .oneYear: .month
        }
    }

    var axisFormat: Date.FormatStyle {
        switch range {
        case .sevenDays:
            .dateTime.weekday(.narrow)
        case .fourWeeks, .threeMonths:
            .dateTime.month(.abbreviated).day()
        case .oneYear:
            .dateTime.month(.abbreviated)
        }
    }

    var chartAccessibilityLabel: String {
        "\(range.accessibilityLabel) step trend. Average \(averageSteps) steps per day."
    }

    private static func makePoints(
        records: [DailyStepRecord],
        range: ActivityInsightRange,
        calendar: Calendar
    ) -> [ActivityTrendPoint] {
        switch range {
        case .sevenDays, .fourWeeks:
            return records.map {
                ActivityTrendPoint(
                    date: calendar.startOfDay(for: $0.day),
                    steps: $0.steps
                )
            }
        case .threeMonths:
            let grouped = Dictionary(grouping: records) { record in
                calendar.dateInterval(of: .weekOfYear, for: record.day)?.start
                    ?? calendar.startOfDay(for: record.day)
            }
            return grouped.map { date, values in
                ActivityTrendPoint(
                    date: date,
                    steps: values.reduce(0) { $0 + $1.steps } / max(values.count, 1)
                )
            }
            .sorted { $0.date < $1.date }
        case .oneYear:
            let grouped = Dictionary(grouping: records) { record in
                calendar.dateInterval(of: .month, for: record.day)?.start
                    ?? calendar.startOfDay(for: record.day)
            }
            return grouped.map { date, values in
                ActivityTrendPoint(
                    date: date,
                    steps: values.reduce(0) { $0 + $1.steps } / max(values.count, 1)
                )
            }
            .sorted { $0.date < $1.date }
        }
    }

    private static func makePace(
        hourlyRecords: [HourlyStepRecord],
        calendar: Calendar
    ) -> (narrative: String, symbol: String, tint: Color) {
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let today = calendar.startOfDay(for: now)
        let grouped = Dictionary(grouping: hourlyRecords) {
            calendar.startOfDay(for: $0.start)
        }

        let todaySteps = (grouped[today] ?? [])
            .filter { calendar.component(.hour, from: $0.start) <= currentHour }
            .reduce(0) { $0 + $1.steps }

        let comparisons = grouped
            .filter { $0.key < today }
            .sorted { $0.key > $1.key }
            .prefix(14)
            .map { _, records in
                records
                    .filter { calendar.component(.hour, from: $0.start) <= currentHour }
                    .reduce(0) { $0 + $1.steps }
            }
            .filter { $0 > 0 }

        guard comparisons.count >= 5 else {
            return (
                "Nanobeasts is learning your usual pace. A comparison appears after five active days.",
                "waveform.path.ecg",
                NanoTheme.teal
            )
        }

        let sorted = comparisons.sorted()
        let median = sorted[sorted.count / 2]
        let difference = todaySteps - median
        if abs(difference) < max(Int(Double(median) * 0.08), 100) {
            return (
                "You’re moving at about your usual pace for this time of day.",
                "equal.circle.fill",
                NanoTheme.teal
            )
        } else if difference > 0 {
            return (
                "You’re \(difference.formatted()) steps ahead of your usual pace by now.",
                "arrow.up.right.circle.fill",
                Color(red: 0.26, green: 0.92, blue: 0.52)
            )
        } else {
            return (
                "You’re \(abs(difference).formatted()) steps behind your usual pace by now.",
                "figure.walk.motion",
                NanoTheme.orange
            )
        }
    }

    private static func makeActiveWindow(
        hourlyRecords: [HourlyStepRecord],
        calendar: Calendar
    ) -> (value: String, caption: String) {
        let activeDays = Set(
            hourlyRecords.filter { $0.steps > 0 }.map {
                calendar.startOfDay(for: $0.start)
            }
        )
        guard activeDays.count >= 7 else {
            return ("LEARNING", "NEEDS 7 ACTIVE DAYS")
        }

        let byHour = Dictionary(grouping: hourlyRecords, by: {
            calendar.component(.hour, from: $0.start)
        })
        guard let best = byHour.max(by: {
            $0.value.reduce(0) { $0 + $1.steps }
                < $1.value.reduce(0) { $0 + $1.steps }
        }) else {
            return ("—", "NO HOURLY DATA")
        }

        let start = calendar.date(bySettingHour: best.key, minute: 0, second: 0, of: Date())
            ?? Date()
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        return (
            start.formatted(.dateTime.hour()),
            "\(start.formatted(.dateTime.hour()))–\(end.formatted(.dateTime.hour())) MOST ACTIVE"
        )
    }

    private static func goal(
        for day: Date,
        history: [DailyGoalRecord],
        fallback: Int,
        calendar: Calendar
    ) -> Int {
        let normalized = calendar.startOfDay(for: day)
        return history
            .filter { calendar.startOfDay(for: $0.day) <= normalized }
            .max { $0.day < $1.day }?
            .goal ?? fallback
    }
}
