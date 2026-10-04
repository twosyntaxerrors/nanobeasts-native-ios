import Charts
import SwiftUI

struct ActionableInsightsCard: View {
    private static let behindRed = Color(
        red: 1.0,
        green: 0.16,
        blue: 0.22
    )
    private static let aheadGreen = Color(
        red: 0.20,
        green: 1.0,
        blue: 0.46
    )

    let analyticsRecords: [DailyStepRecord]
    let hourlyRecords: [HourlyStepRecord]
    let journeyRecords: [DailyStepRecord]
    let goalHistory: [DailyGoalRecord]
    let currentGoal: Int
    let stepsRemaining: Int
    let creatureName: String

    @State private var range: ActivityInsightRange = .sevenDays
    @State private var isExpanded = true
    @State private var snapshots: [ActivityInsightRange: ActivityInsightSnapshot] = [:]
    @State private var selectedPointDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let selectedSnapshot = snapshots[range] ?? snapshots[.sevenDays],
               let sevenDaySnapshot = snapshots[.sevenDays] ?? snapshots[range]
            {
                insightsContent(
                    isExpanded ? selectedSnapshot : sevenDaySnapshot
                )
            } else {
                loadingContent
            }
        }
        .task(id: inputID) {
            await prepareSnapshots()
        }
    }

    private func insightsContent(_ snapshot: ActivityInsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Group {
                if isExpanded {
                    VStack(alignment: .leading, spacing: 18) {
                        prioritySignal(snapshot)
                        metricRail(snapshot)
                        expandedContent(snapshot)
                    }
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -7)),
                                removal: .opacity
                            )
                    )
                } else {
                    collapsedOverview(snapshot)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 5)),
                                    removal: .opacity
                                )
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 13)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            NanoTheme.teal.opacity(0.065),
                            NanoTheme.surface.opacity(0.98),
                            NanoTheme.background.opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(NanoTheme.teal.opacity(0.34), lineWidth: 1)
                )
        )
        .animation(disclosureAnimation, value: isExpanded)
    }

    private func collapsedOverview(_ snapshot: ActivityInsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Circle()
                    .fill(snapshot.paceTint)
                    .frame(width: 6, height: 6)
                    .shadow(color: snapshot.paceTint.opacity(0.95), radius: 6)

                Text(snapshot.paceStatusLabel)
                    .font(NanoFont.aldrich(8))
                    .tracking(0.85)
                    .foregroundStyle(snapshot.paceTint)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("7D TRACE")
                    .font(NanoFont.aldrich(6))
                    .tracking(0.9)
                    .foregroundStyle(NanoTheme.mutedText)
            }

            compactTrace(snapshot)

            HStack(spacing: 10) {
                CollapsedInsightMetric(
                    value: snapshot.averageSteps.formatted(),
                    label: "AVG / DAY",
                    tint: NanoTheme.teal
                )

                CollapsedInsightMetric(
                    value: snapshot.periodDeltaValue,
                    label: "VS PREV 7D",
                    tint: snapshot.periodDeltaTint
                )

                CollapsedInsightMetric(
                    value: snapshot.evolutionCompactValue,
                    label: "EVOLUTION",
                    tint: NanoTheme.purple
                )
            }
        }
    }

    private func compactTrace(_ snapshot: ActivityInsightSnapshot) -> some View {
        Chart {
            ForEach(snapshot.points) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Steps", point.steps),
                    width: .ratio(0.54)
                )
                .foregroundStyle(
                    point.steps >= currentGoal
                        ? NanoTheme.teal.opacity(0.78)
                        : NanoTheme.teal.opacity(0.38)
                )
                .cornerRadius(3)
            }

            ForEach(snapshot.points) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Trend", point.steps)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(NanoTheme.purple.opacity(0.88))
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 1.5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            RuleMark(y: .value("Daily goal", currentGoal))
                .foregroundStyle(NanoTheme.orange.opacity(0.72))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 5]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("GOAL")
                        .font(NanoFont.aldrich(5))
                        .tracking(0.7)
                        .foregroundStyle(NanoTheme.orange)
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .background(NanoTheme.teal.opacity(0.025))
        }
        .frame(height: 78)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white.opacity(0.012))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(0.075), lineWidth: 1)
                )
        )
        .accessibilityLabel(snapshot.chartAccessibilityLabel)
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            HStack(spacing: 11) {
                ProgressView()
                    .controlSize(.small)
                    .tint(NanoTheme.teal)

                VStack(alignment: .leading, spacing: 4) {
                    Text("PREPARING YOUR SIGNAL")
                        .font(NanoFont.aldrich(11))
                        .foregroundStyle(.white)
                    Text("Building your movement baseline off the main thread.")
                        .font(NanoFont.spaceMono(8))
                        .foregroundStyle(NanoTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(NanoTheme.teal.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(NanoTheme.teal.opacity(0.20), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NanoTheme.surface.opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(NanoTheme.teal.opacity(0.38), lineWidth: 1)
                )
        )
    }

    private var inputID: ActivityInsightInputID {
        ActivityInsightInputID(
            analyticsCount: analyticsRecords.count,
            analyticsFirst: analyticsRecords.first,
            analyticsLast: analyticsRecords.last,
            hourlyCount: hourlyRecords.count,
            hourlyFirst: hourlyRecords.first,
            hourlyLast: hourlyRecords.last,
            journeyCount: journeyRecords.count,
            journeyFirst: journeyRecords.first,
            journeyLast: journeyRecords.last,
            goalCount: goalHistory.count,
            goalFirst: goalHistory.first,
            goalLast: goalHistory.last,
            currentGoal: currentGoal,
            stepsRemaining: stepsRemaining,
            creatureName: creatureName
        )
    }

    private func prepareSnapshots() async {
        let analyticsRecords = analyticsRecords
        let hourlyRecords = hourlyRecords
        let journeyRecords = journeyRecords
        let goalHistory = goalHistory
        let currentGoal = currentGoal
        let stepsRemaining = stepsRemaining
        let creatureName = creatureName

        let prepared = await Task.detached(priority: .userInitiated) {
            Dictionary(
                uniqueKeysWithValues: ActivityInsightRange.allCases.map { range in
                    (
                        range,
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
                    )
                }
            )
        }.value

        guard !Task.isCancelled else { return }
        snapshots = prepared
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("INSIGHTS")
                .font(NanoFont.aldrich(17))
                .tracking(1.1)
                .foregroundStyle(NanoTheme.teal)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            NanoTheme.teal.opacity(0.45),
                            NanoTheme.teal.opacity(0.08)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            HStack(spacing: 5) {
                Circle()
                    .fill(NanoTheme.teal)
                    .frame(width: 5, height: 5)
                    .shadow(color: NanoTheme.teal.opacity(0.8), radius: 4)

                Text("LIVE")
                    .font(NanoFont.aldrich(6))
                    .tracking(0.8)
                    .foregroundStyle(NanoTheme.secondaryText)
            }

            Button {
                withAnimation(disclosureAnimation) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NanoTheme.teal)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: 35, height: 35)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(NanoTheme.teal.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(NanoTheme.teal.opacity(0.28), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(InsightPressStyle())
            .accessibilityLabel(isExpanded ? "Collapse insights" : "Expand insights")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.top, 13)
        .padding(.bottom, 14)
    }

    private var disclosureAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .timingCurve(0.22, 1, 0.36, 1, duration: 0.24)
    }

    private func prioritySignal(_ snapshot: ActivityInsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("PACE SIGNAL")
                    .font(NanoFont.aldrich(8))
                    .tracking(1.15)
                    .foregroundStyle(snapshot.paceTint)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(snapshot.paceTint)
                        .frame(width: 4, height: 4)
                        .shadow(color: snapshot.paceTint, radius: 4)

                    Text("NOW · \(Date().formatted(.dateTime.hour().minute()))")
                        .font(NanoFont.aldrich(6))
                        .tracking(0.8)
                }
                .foregroundStyle(snapshot.paceTint.opacity(0.82))
            }

            Text(snapshot.paceNarrative)
                .font(NanoFont.aldrich(19))
                .foregroundStyle(.white)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            paceTrace(snapshot)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            snapshot.paceTint.opacity(0.12),
                            NanoTheme.surface.opacity(0.99)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(snapshot.paceTint.opacity(0.52), lineWidth: 1)
            )
        )
        .overlay {
            InsightCornerBrackets(tint: snapshot.paceTint)
                .padding(8)
        }
        .shadow(color: snapshot.paceTint.opacity(0.18), radius: 14)
    }

    @ViewBuilder
    private func paceTrace(_ snapshot: ActivityInsightSnapshot) -> some View {
        if snapshot.pacePoints.count > 1 {
            Chart(snapshot.pacePoints) { point in
                LineMark(
                    x: .value("Hour", point.hour),
                    y: .value("Usual pace", point.usualSteps),
                    series: .value("Series", "Usual")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(NanoTheme.secondaryText.opacity(0.62))
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 1.2,
                        dash: [3, 4]
                    )
                )

                LineMark(
                    x: .value("Hour", point.hour),
                    y: .value("Current pace", point.currentSteps),
                    series: .value("Series", "Current")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(snapshot.paceTint)
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                if point.id == snapshot.pacePoints.last?.id {
                    PointMark(
                        x: .value("Hour", point.hour),
                        y: .value("Current pace", point.currentSteps)
                    )
                    .foregroundStyle(snapshot.paceTint)
                    .symbolSize(28)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 2)) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel(format: .dateTime.hour())
                        .font(NanoFont.aldrich(5))
                        .foregroundStyle(NanoTheme.mutedText)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 58)
            .accessibilityLabel(snapshot.paceStatusLabel)
        } else {
            HStack(spacing: 8) {
                Capsule()
                    .fill(snapshot.paceTint)
                    .frame(width: 30, height: 3)
                    .shadow(color: snapshot.paceTint.opacity(0.9), radius: 5)

                Text(snapshot.paceStatusLabel)
                    .font(NanoFont.aldrich(8))
                    .tracking(0.8)
                    .foregroundStyle(snapshot.paceTint)
            }
            .frame(height: 34)
        }
    }

    private func metricRail(_ snapshot: ActivityInsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("KEY TELEMETRY")
                    .font(NanoFont.aldrich(6))
                    .tracking(1)
                    .foregroundStyle(NanoTheme.mutedText)

                Rectangle()
                    .fill(Color.white.opacity(0.075))
                    .frame(height: 1)
            }

            HStack(spacing: 10) {
                InsightBriefMetric(
                    value: snapshot.goalCompletionValue,
                    label: "CONSISTENCY",
                    tint: NanoTheme.teal
                )

                InsightBriefMetric(
                    value: snapshot.bestDayValue,
                    label: "BEST DAY",
                    tint: NanoTheme.cyan
                )

                InsightBriefMetric(
                    value: snapshot.evolutionCompactValue,
                    label: "EVOLUTION",
                    tint: NanoTheme.purple
                )
            }
        }
    }

    @ViewBuilder
    private func expandedContent(_ snapshot: ActivityInsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            rangePicker
            movementTrace(snapshot)
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(ActivityInsightRange.allCases) { option in
                Button {
                    withAnimation(
                        reduceMotion
                            ? .easeOut(duration: 0.12)
                            : .timingCurve(0.22, 1, 0.36, 1, duration: 0.28)
                    ) {
                        range = option
                        selectedPointDate = nil
                    }
                } label: {
                    Text(option.rawValue)
                        .font(NanoFont.aldrich(9))
                        .foregroundStyle(
                            range == option ? NanoTheme.background : NanoTheme.secondaryText
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            Capsule()
                                .fill(range == option ? NanoTheme.teal : .clear)
                        )
                }
                .buttonStyle(InsightPressStyle())
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

    private func movementTrace(_ snapshot: ActivityInsightSnapshot) -> some View {
        let selectedPoint = selectedPoint(in: snapshot)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MOVEMENT TRACE")
                        .font(NanoFont.aldrich(9))
                        .tracking(1.2)
                        .foregroundStyle(NanoTheme.teal)

                    Text(snapshot.rangeLabel)
                        .font(NanoFont.spaceMono(7))
                        .tracking(0.35)
                        .foregroundStyle(NanoTheme.mutedText)
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

            HStack(spacing: 7) {
                Image(
                    systemName: snapshot.periodDeltaPercent >= 0
                        ? "arrow.up.right"
                        : "arrow.down.right"
                )
                .font(.system(size: 8, weight: .bold))

                Text(snapshot.periodDeltaNarrative)
                    .font(NanoFont.spaceMono(8))
                    .tracking(0.2)
            }
            .foregroundStyle(snapshot.periodDeltaTint)

            if snapshot.points.isEmpty {
                ContentUnavailableView(
                    "Learning your movement",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Connect Apple Health or take your first steps to begin.")
                )
                .frame(height: 144)
                .foregroundStyle(NanoTheme.secondaryText)
            } else {
                Chart {
                    ForEach(snapshot.points) { point in
                        BarMark(
                            x: .value("Period", point.date, unit: snapshot.chartUnit),
                            y: .value("Steps", point.steps),
                            width: .ratio(range == .sevenDays ? 0.55 : 0.46)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    NanoTheme.teal.opacity(0.38),
                                    point.id == selectedPoint?.id
                                        ? NanoTheme.teal
                                        : NanoTheme.teal.opacity(0.74)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(4)
                    }

                    ForEach(snapshot.points) { point in
                        LineMark(
                            x: .value("Period", point.date, unit: snapshot.chartUnit),
                            y: .value("Trend", point.steps)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(NanoTheme.cyan)
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: 2,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }

                    ForEach(snapshot.comparisonPoints) { point in
                        LineMark(
                            x: .value("Period", point.date, unit: snapshot.chartUnit),
                            y: .value("Previous period", point.steps),
                            series: .value("Series", "Previous")
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(NanoTheme.purple.opacity(0.62))
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: 1.3,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: [3, 4]
                            )
                        )
                    }

                    if range.showsDailyGoalLine {
                        RuleMark(y: .value("Daily goal", currentGoal))
                            .foregroundStyle(NanoTheme.orange.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }

                    if let selectedPoint {
                        RuleMark(
                            x: .value(
                                "Selected period",
                                selectedPoint.date,
                                unit: snapshot.chartUnit
                            )
                        )
                        .foregroundStyle(NanoTheme.teal.opacity(0.42))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))

                        PointMark(
                            x: .value(
                                "Selected period",
                                selectedPoint.date,
                                unit: snapshot.chartUnit
                            ),
                            y: .value("Selected steps", selectedPoint.steps)
                        )
                        .foregroundStyle(NanoTheme.teal)
                        .symbolSize(34)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(
                            LinearGradient(
                                colors: [
                                    NanoTheme.teal.opacity(0.045),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
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
                .chartXSelection(value: $selectedPointDate)
                .frame(height: 194)
                .accessibilityLabel(snapshot.chartAccessibilityLabel)

                HStack(spacing: 14) {
                    InsightLegendItem(
                        color: NanoTheme.teal,
                        label: "STEPS"
                    )
                    InsightLegendItem(
                        color: NanoTheme.cyan,
                        label: "TREND"
                    )
                    InsightLegendItem(
                        color: NanoTheme.purple,
                        label: "PREV"
                    )
                    if range.showsDailyGoalLine {
                        InsightLegendItem(
                            color: NanoTheme.orange,
                            label: "GOAL",
                            dashed: true
                        )
                    }
                    Spacer()
                    Text("\(snapshot.points.count) SAMPLES")
                        .font(NanoFont.aldrich(6))
                        .tracking(0.8)
                        .foregroundStyle(NanoTheme.mutedText)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if let selectedPoint {
                    selectedPointSummary(
                        point: selectedPoint,
                        snapshot: snapshot
                    )
                }
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NanoTheme.surface.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(NanoTheme.teal.opacity(0.32), lineWidth: 1)
                )
        )
    }

    private func selectedPoint(
        in snapshot: ActivityInsightSnapshot
    ) -> ActivityTrendPoint? {
        guard let selectedPointDate else {
            return snapshot.points.last
        }

        return snapshot.points.min {
            abs($0.date.timeIntervalSince(selectedPointDate))
                < abs($1.date.timeIntervalSince(selectedPointDate))
        }
    }

    private func selectedPointSummary(
        point: ActivityTrendPoint,
        snapshot: ActivityInsightSnapshot
    ) -> some View {
        let goalPercentage = currentGoal > 0
            ? Int((Double(point.steps) / Double(currentGoal) * 100).rounded())
            : 0
        let averageDifference = snapshot.averageSteps > 0
            ? Int(
                (
                    Double(point.steps - snapshot.averageSteps)
                        / Double(snapshot.averageSteps)
                        * 100
                ).rounded()
            )
            : 0

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SELECTED · \(snapshot.selectionLabel(for: point.date))")
                    .font(NanoFont.aldrich(6))
                    .tracking(0.7)
                    .foregroundStyle(NanoTheme.mutedText)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(point.steps.formatted())
                        .font(NanoFont.aldrich(20))
                        .foregroundStyle(.white)
                    Text("STEPS")
                        .font(NanoFont.aldrich(6))
                        .tracking(0.7)
                        .foregroundStyle(NanoTheme.secondaryText)
                }
            }

            Spacer(minLength: 2)

            SelectedInsightMetric(
                label: "OF GOAL",
                value: "\(goalPercentage)%",
                tint: goalPercentage >= 100 ? Self.aheadGreen : NanoTheme.orange
            )

            SelectedInsightMetric(
                label: "VS AVG",
                value: "\(averageDifference >= 0 ? "+" : "")\(averageDifference)%",
                tint: averageDifference >= 0 ? Self.aheadGreen : Self.behindRed
            )
        }
        .padding(.top, 11)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
    }

}

private struct CollapsedInsightMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(tint.opacity(0.58))
                .frame(height: 1)

            Text(value)
                .font(NanoFont.aldrich(15))
                .foregroundStyle(value.contains("▼") ? tint : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(NanoFont.aldrich(5))
                .tracking(0.65)
                .foregroundStyle(NanoTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }
}

private struct InsightBriefMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(tint)
                .frame(width: 20, height: 2)
                .shadow(color: tint.opacity(0.5), radius: 3)

            Text(value)
                .font(NanoFont.aldrich(17))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text(label)
                .font(NanoFont.aldrich(5))
                .tracking(0.55)
                .foregroundStyle(NanoTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.018))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }
}

private struct SelectedInsightMetric: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(NanoFont.aldrich(5))
                .tracking(0.65)
                .foregroundStyle(NanoTheme.secondaryText)

            Text(value)
                .font(NanoFont.aldrich(11))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minWidth: 55, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.018))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct InsightCornerBrackets: View {
    let tint: Color

    var body: some View {
        VStack {
            HStack {
                InsightCorner()
                    .stroke(tint.opacity(0.72), lineWidth: 1)
                    .frame(width: 12, height: 12)

                Spacer()

                InsightCorner()
                    .stroke(tint.opacity(0.72), lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(90))
            }

            Spacer()

            HStack {
                InsightCorner()
                    .stroke(tint.opacity(0.72), lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(-90))

                Spacer()

                InsightCorner()
                    .stroke(tint.opacity(0.72), lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(180))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct InsightCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

private struct InsightLegendItem: View {
    let color: Color
    let label: String
    var dashed = false

    var body: some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: 14, height: dashed ? 1 : 3)
                .overlay {
                    if dashed {
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule()
                                    .fill(color)
                            }
                        }
                    }
                }

            Text(label)
                .font(NanoFont.aldrich(6))
                .tracking(0.7)
                .foregroundStyle(NanoTheme.secondaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct InsightsReticle: View {
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.08), lineWidth: 12)
            Circle()
                .stroke(tint.opacity(0.09), lineWidth: 1)
                .padding(18)
            Rectangle()
                .fill(tint.opacity(0.09))
                .frame(width: 1)
            Rectangle()
                .fill(tint.opacity(0.09))
                .frame(height: 1)
            Circle()
                .fill(tint.opacity(0.22))
                .frame(width: 5, height: 5)
        }
    }
}

private struct InsightPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ActivityInsightInputID: Hashable {
    let analyticsCount: Int
    let analyticsFirstDay: Date?
    let analyticsFirstSteps: Int?
    let analyticsLastDay: Date?
    let analyticsLastSteps: Int?
    let hourlyCount: Int
    let hourlyFirstStart: Date?
    let hourlyFirstSteps: Int?
    let hourlyLastStart: Date?
    let hourlyLastSteps: Int?
    let journeyCount: Int
    let journeyFirstDay: Date?
    let journeyFirstSteps: Int?
    let journeyLastDay: Date?
    let journeyLastSteps: Int?
    let goalCount: Int
    let goalFirstDay: Date?
    let goalFirstValue: Int?
    let goalLastDay: Date?
    let goalLastValue: Int?
    let currentGoal: Int
    let stepsRemaining: Int
    let creatureName: String

    init(
        analyticsCount: Int,
        analyticsFirst: DailyStepRecord?,
        analyticsLast: DailyStepRecord?,
        hourlyCount: Int,
        hourlyFirst: HourlyStepRecord?,
        hourlyLast: HourlyStepRecord?,
        journeyCount: Int,
        journeyFirst: DailyStepRecord?,
        journeyLast: DailyStepRecord?,
        goalCount: Int,
        goalFirst: DailyGoalRecord?,
        goalLast: DailyGoalRecord?,
        currentGoal: Int,
        stepsRemaining: Int,
        creatureName: String
    ) {
        self.analyticsCount = analyticsCount
        analyticsFirstDay = analyticsFirst?.day
        analyticsFirstSteps = analyticsFirst?.steps
        analyticsLastDay = analyticsLast?.day
        analyticsLastSteps = analyticsLast?.steps
        self.hourlyCount = hourlyCount
        hourlyFirstStart = hourlyFirst?.start
        hourlyFirstSteps = hourlyFirst?.steps
        hourlyLastStart = hourlyLast?.start
        hourlyLastSteps = hourlyLast?.steps
        self.journeyCount = journeyCount
        journeyFirstDay = journeyFirst?.day
        journeyFirstSteps = journeyFirst?.steps
        journeyLastDay = journeyLast?.day
        journeyLastSteps = journeyLast?.steps
        self.goalCount = goalCount
        goalFirstDay = goalFirst?.day
        goalFirstValue = goalFirst?.goal
        goalLastDay = goalLast?.day
        goalLastValue = goalLast?.goal
        self.currentGoal = currentGoal
        self.stepsRemaining = stepsRemaining
        self.creatureName = creatureName
    }
}

private enum ActivityInsightRange: String, CaseIterable, Identifiable, Hashable {
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

private struct PaceTracePoint: Identifiable {
    let hour: Date
    let currentSteps: Int
    let usualSteps: Int

    var id: Date { hour }
}

private struct ActivityInsightSnapshot {
    let range: ActivityInsightRange
    let points: [ActivityTrendPoint]
    let comparisonPoints: [ActivityTrendPoint]
    let averageSteps: Int
    let previousAverageSteps: Int
    let periodDeltaPercent: Int
    let primaryHeadline: String
    let primaryNarrative: String
    let paceNarrative: String
    let paceSymbol: String
    let paceTint: Color
    let pacePoints: [PaceTracePoint]
    let paceStatusLabel: String
    let paceActionTitle: String
    let paceActionDetail: String
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
        let previousPoints = Self.makePoints(
            records: previousRecords,
            range: range,
            calendar: calendar
        )
        comparisonPoints = Self.alignComparison(
            previousPoints,
            to: points
        )

        let currentTotal = currentRecords.reduce(0) { $0 + $1.steps }
        averageSteps = range.dayCount > 0 ? currentTotal / range.dayCount : 0
        let previousTotal = previousRecords.reduce(0) { $0 + $1.steps }
        previousAverageSteps =
            previousRecords.isEmpty ? 0 : previousTotal / range.dayCount
        periodDeltaPercent =
            previousAverageSteps > 0
                ? Int(
                    (
                        Double(averageSteps - previousAverageSteps)
                            / Double(previousAverageSteps)
                            * 100
                    ).rounded()
                )
                : 0

        if currentRecords.isEmpty {
            primaryHeadline = "BUILDING YOUR BASELINE"
            primaryNarrative = "Your first movement pattern will appear here."
        } else if previousRecords.isEmpty || previousAverageSteps == 0 {
            primaryHeadline = "\(range.accessibilityLabel.uppercased()) AVERAGE"
            primaryNarrative = "\(averageSteps.formatted()) steps per day so far."
        } else {
            let change = periodDeltaPercent
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
        pacePoints = pace.points
        paceStatusLabel = pace.statusLabel
        paceActionTitle = pace.actionTitle
        paceActionDetail =
            "\(pace.actionDetail) Every step also moves \(creatureName) closer to its next evolution signal."

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

    var periodDeltaTint: Color {
        guard previousAverageSteps > 0 else { return NanoTheme.teal }
        return periodDeltaPercent >= 0
            ? Color(red: 0.20, green: 1.0, blue: 0.46)
            : Color(red: 1.0, green: 0.16, blue: 0.22)
    }

    var periodDeltaValue: String {
        guard previousAverageSteps > 0 else { return "—" }
        return "\(periodDeltaPercent >= 0 ? "▲" : "▼") \(abs(periodDeltaPercent))%"
    }

    var periodDeltaNarrative: String {
        guard previousAverageSteps > 0 else {
            return "COMPARISON BASELINE IN PROGRESS"
        }

        return "\(periodDeltaValue) VS PREVIOUS PERIOD · \(previousAverageSteps.formatted()) BEFORE"
    }

    var evolutionCompactValue: String {
        evolutionValue
            .replacingOccurrences(of: " DAYS", with: "D")
            .replacingOccurrences(of: " DAY", with: "D")
    }

    var rangeLabel: String {
        guard let first = points.first?.date,
              let last = points.last?.date
        else {
            return "\(range.accessibilityLabel.uppercased()) · LEARNING"
        }

        let start = first.formatted(
            .dateTime.month(.abbreviated).day()
        )
        let end = last.formatted(
            .dateTime.month(.abbreviated).day()
        )
        let granularity: String
        switch range {
        case .sevenDays:
            granularity = "DAILY"
        case .fourWeeks, .threeMonths:
            granularity = "WEEKLY AVG"
        case .oneYear:
            granularity = "MONTHLY AVG"
        }
        return "\(start.uppercased()) – \(end.uppercased()) · \(granularity)"
    }

    func selectionLabel(for date: Date) -> String {
        switch range {
        case .sevenDays:
            return date.formatted(
                .dateTime.weekday(.abbreviated).month(.abbreviated).day()
            ).uppercased()
        case .fourWeeks, .threeMonths:
            return "WEEK OF \(date.formatted(.dateTime.month(.abbreviated).day()).uppercased())"
        case .oneYear:
            return date.formatted(
                .dateTime.month(.wide).year()
            ).uppercased()
        }
    }

    var chartUnit: Calendar.Component {
        switch range {
        case .sevenDays: .day
        case .fourWeeks, .threeMonths: .weekOfYear
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
        case .sevenDays:
            return records.map {
                ActivityTrendPoint(
                    date: calendar.startOfDay(for: $0.day),
                    steps: $0.steps
                )
            }
            .sorted { $0.date < $1.date }
        case .fourWeeks, .threeMonths:
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

    private static func alignComparison(
        _ previousPoints: [ActivityTrendPoint],
        to currentPoints: [ActivityTrendPoint]
    ) -> [ActivityTrendPoint] {
        guard !previousPoints.isEmpty, !currentPoints.isEmpty else {
            return []
        }

        let previousValues = previousPoints.map(\.steps)
        return currentPoints.enumerated().compactMap { index, point in
            guard index < previousValues.count else { return nil }
            return ActivityTrendPoint(
                date: point.date,
                steps: previousValues[index]
            )
        }
    }

    private static func makePace(
        hourlyRecords: [HourlyStepRecord],
        calendar: Calendar
    ) -> (
        narrative: String,
        symbol: String,
        tint: Color,
        points: [PaceTracePoint],
        statusLabel: String,
        actionTitle: String,
        actionDetail: String
    ) {
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let today = calendar.startOfDay(for: now)
        let grouped = Dictionary(grouping: hourlyRecords) {
            calendar.startOfDay(for: $0.start)
        }

        let todaySteps = (grouped[today] ?? [])
            .filter { calendar.component(.hour, from: $0.start) <= currentHour }
            .reduce(0) { $0 + $1.steps }

        let comparisonDays = grouped
            .filter { $0.key < today }
            .sorted { $0.key > $1.key }
            .prefix(14)

        let comparisons = comparisonDays
            .map { _, records in
                records
                    .filter { calendar.component(.hour, from: $0.start) <= currentHour }
                    .reduce(0) { $0 + $1.steps }
            }
            .filter { $0 > 0 }

        let traceStartHour = min(6, currentHour)
        let todayRecords = grouped[today] ?? []
        let tracePoints = (traceStartHour...currentHour).compactMap { hour
            -> PaceTracePoint? in
            guard let hourDate = calendar.date(
                bySettingHour: hour,
                minute: 0,
                second: 0,
                of: now
            ) else {
                return nil
            }

            let current = todayRecords
                .filter { calendar.component(.hour, from: $0.start) <= hour }
                .reduce(0) { $0 + $1.steps }
            let usualSamples = comparisonDays.map { _, records in
                records
                    .filter { calendar.component(.hour, from: $0.start) <= hour }
                    .reduce(0) { $0 + $1.steps }
            }
            .filter { $0 > 0 }
            .sorted()
            let usual = usualSamples.isEmpty
                ? 0
                : usualSamples[usualSamples.count / 2]

            return PaceTracePoint(
                hour: hourDate,
                currentSteps: current,
                usualSteps: usual
            )
        }

        guard comparisons.count >= 5 else {
            return (
                "Nanobeasts is learning your usual pace. A comparison appears after five active days.",
                "waveform.path.ecg",
                NanoTheme.teal,
                tracePoints,
                "BASELINE IN PROGRESS",
                "Keep moving naturally today.",
                "Your personal pace signal becomes more precise as Nanobeasts learns your routine."
            )
        }

        let sorted = comparisons.sorted()
        let median = sorted[sorted.count / 2]
        let difference = todaySteps - median
        if abs(difference) < max(Int(Double(median) * 0.08), 100) {
            return (
                "You’re moving at about your usual pace for this time of day.",
                "equal.circle.fill",
                NanoTheme.teal,
                tracePoints,
                "ON YOUR USUAL RHYTHM",
                "Your movement rhythm is steady.",
                "A short walk now can help protect that momentum through the rest of the day."
            )
        } else if difference > 0 {
            return (
                "You’re \(difference.formatted()) steps ahead of your usual pace by now.",
                "arrow.up.right.circle.fill",
                Color(red: 0.20, green: 1.0, blue: 0.46),
                tracePoints,
                "+\(difference.formatted()) STEPS VS USUAL",
                "You’ve built a movement buffer.",
                "Keep the lead with one more comfortable walk during your strongest activity window."
            )
        } else {
            return (
                "You’re \(abs(difference).formatted()) steps behind your usual pace by now.",
                "figure.walk.motion",
                Color(red: 1.0, green: 0.16, blue: 0.22),
                tracePoints,
                "−\(abs(difference).formatted()) STEPS VS USUAL",
                "A focused walk can close the gap.",
                "You do not need to recover it all at once—one intentional walk is enough to shift today’s trajectory."
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
