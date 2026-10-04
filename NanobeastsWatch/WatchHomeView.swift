import Charts
import SwiftUI
import WatchKit

struct WatchHomeView: View {
    @Environment(\.watchAccent) private var accent
    let activity: WatchDailyActivity?
    let image: UIImage?
    let creatureName: String?
    let dailyGoal: Int?
    var animationFrames: [UIImage] = []
    var startsAtHourlyActivity = false
    var isLoading = false
    var notice: String?
    let startWalk: () -> Void
    let moreWorkouts: () -> Void
    @State private var selectedHour: Date?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var stepSize: CGFloat = 43
    private var compactWatch: Bool { WKInterfaceDevice.current().screenBounds.width < 176 }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: compactWatch ? 6 : 9) {
                HStack(spacing: 8) {
                    WatchCompanionRing(image: image, frames: animationFrames, name: creatureName,
                                       progress: activity?.goalProgress(target: dailyGoal) ?? 0,
                                       diameter: compactWatch ? 45 : 51)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(activity?.steps?.formatted() ?? "—")
                            .font(.system(size: stepSize, weight: .semibold, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(goalDescription)
                weeklyChart
                HStack(alignment: .top, spacing: 4) {
                    metric(activity?.activeCalories.map { Int($0).formatted() }, unit: "kcal", label: "Active energy")
                    metric(activity?.distanceMiles.map { String(format: "%.1f", $0) }, unit: "mi", label: "Distance today")
                    metric(activity?.exerciseMinutes.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) }, unit: "h", label: "Exercise hours and minutes")
                }.padding(.bottom, 14)
                hourlyChart.id("hourly")
                if let notice {
                    Text(notice).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal, 3).padding(.bottom, 8)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .padding(.top, -18)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityAction(named: "Show workouts", moreWorkouts)
        .onAppear { if startsAtHourlyActivity { proxy.scrollTo("hourly", anchor: .top) } }
        }
    }

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 3) {
            Chart {
                ForEach(activity?.weeklySteps ?? []) { point in
                    if let steps = point.steps {
                        AreaMark(x: .value("Day", point.start), y: .value("Steps", steps))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [accent.opacity(0.35), .clear],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Day", point.start), y: .value("Steps", steps))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(accent).lineStyle(StrokeStyle(lineWidth: 3))
                        PointMark(x: .value("Day", point.start), y: .value("Steps", steps))
                            .foregroundStyle(.white).symbolSize(22)
                        if point.id == activity?.weeklySteps.last?.id {
                            PointMark(x: .value("Day", point.start), y: .value("Steps", steps))
                                .symbol { Circle().stroke(.white, lineWidth: 1.5).frame(width: 13, height: 13) }
                        }
                    }
                }
                if let average = weeklyAverage {
                    RuleMark(y: .value("Seven-day average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3])).foregroundStyle(.white.opacity(0.5))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.2))
                }
            }.chartYAxis(.hidden)
            .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 8))
            .chartYScale(domain: 0...max(1, Double(activity?.weeklySteps.compactMap(\.steps).max() ?? 1)))
            .frame(height: compactWatch ? 53 : 66)
            .accessibilityLabel("Steps over the last seven days")
        }
    }

    private var weeklyAverage: Double? {
        let values = activity?.weeklySteps.compactMap(\.steps) ?? []
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private var selectedInterval: WatchStepInterval? {
        let hours = activity?.hourlySteps ?? []
        guard let selectedHour else { return hours.last }
        return hours.first { selectedHour >= $0.start && selectedHour < $0.end } ?? hours.last
    }

    private var hourlyChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedInterval?.steps.map { "\($0.formatted()) Steps" } ?? "Hourly Steps")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let hour = selectedInterval {
                Text("\(hour.start.formatted(date: .omitted, time: .shortened)) – \(hour.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text(isLoading ? "Loading activity…" : "Activity appears as Health updates.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(hourSlots, id: \.self) { hour in
                    PointMark(x: .value("Hour", hour, unit: .hour), y: .value("Steps", 0))
                        .symbolSize(12).foregroundStyle(.white.opacity(0.25))
                        .accessibilityHidden(true)
                }
                ForEach(activity?.hourlySteps ?? []) { hour in
                    if let steps = hour.steps, steps > 0 {
                        BarMark(x: .value("Hour", hour.start, unit: .hour), y: .value("Steps", steps))
                            .foregroundStyle(accent).cornerRadius(3)
                    }
                }
                if let selectedHour {
                    RuleMark(x: .value("Selected hour", selectedHour))
                        .foregroundStyle(.white.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXScale(domain: dayStart...dayEnd).chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { axis in
                    AxisGridLine().foregroundStyle(.white.opacity(0.14))
                    AxisValueLabel {
                        if let date = axis.as(Date.self) {
                            let hour = Calendar.autoupdatingCurrent.component(.hour, from: date)
                            Text(hour == 0 ? "0" : hour == 12 ? "12" : "6")
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedHour)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 150 : 128)
            .accessibilityLabel("Today's steps by hour")
        }.padding(.top, 4)
    }

    private var dayStart: Date { Calendar.autoupdatingCurrent.startOfDay(for: activity?.day ?? Date()) }
    private var dayEnd: Date { Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400) }
    private var hourSlots: [Date] {
        (0..<25).compactMap { Calendar.autoupdatingCurrent.date(byAdding: .hour, value: $0, to: dayStart) }
            .filter { $0 < dayEnd }
    }
    private var goalDescription: String {
        if isLoading, activity?.steps == nil { return "Loading today…" }
        guard let dailyGoal, dailyGoal > 0 else { return "Daily goal syncing from iPhone…" }
        guard let steps = activity?.steps else { return "\(dailyGoal.formatted()) step daily goal" }
        return steps >= dailyGoal ? "Daily goal reached" : "\(max(0, dailyGoal - steps).formatted()) steps to your daily goal"
    }
    private func metric(_ value: String?, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value ?? "—").font(.system(size: 19, weight: .medium, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            Text(unit).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label).accessibilityValue("\(value ?? "Unavailable") \(unit)")
    }
}

private struct WatchCompanionRing: View {
    @Environment(\.watchAccent) private var accent
    let image: UIImage?
    let frames: [UIImage]
    let name: String?
    let progress: Double
    var diameter: CGFloat = 51
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.scenePhase) private var scenePhase
    @State private var animationStart: Date?

    var body: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.18), lineWidth: 5)
            Circle().trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            TimelineView(.animation(minimumInterval: 0.1, paused: animationStart == nil || dimmed || reduceMotion)) { context in
                let elapsed = animationStart.map { context.date.timeIntervalSince($0) } ?? 100
                let index = max(0, Int(elapsed * 10))
                let frame = elapsed >= 0 && index < frames.count ? frames[index] : image
                WatchCurrentCreature(image: frame, size: diameter - 9)
            }
        }
        .frame(width: diameter, height: diameter).padding(3)
        .accessibilityLabel(name.map { "Your companion, \($0)" } ?? "Creature syncing")
        .task(id: "\(name ?? "")-\(frames.count)-\(scenePhase == .active)") {
            guard !reduceMotion, !dimmed, scenePhase == .active else { animationStart = nil; return }
            animationStart = Date()
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            animationStart = nil
        }
        .onChange(of: dimmed) { _, value in if value { animationStart = nil } }
        .onChange(of: reduceMotion) { _, value in if value { animationStart = nil } }
    }
}
