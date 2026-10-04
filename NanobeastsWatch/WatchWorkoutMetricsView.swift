import SwiftUI

/// The walk keeps its creature in view; effort metrics remain on their own page.
struct WatchWorkoutMetricsView: View {
    @Environment(\.watchAccent) private var accent
    let state: WatchWorkoutSnapshot
    var referenceDate: Date? = nil
    var showsEffort = false
    var companionImage: UIImage? = nil
    var companionName: String? = nil
    var evolution: WorkoutEvolutionProgress? = nil
    @ScaledMetric(relativeTo: .title) private var valueSize: CGFloat = 30
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 12

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = referenceDate ?? timeline.date
            ViewThatFits(in: .vertical) {
                content(at: now)
                ScrollView { content(at: now) }
            }
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        if state.workoutID.contains("walk"), !showsEffort {
            walkMetrics(at: now)
        } else {
            metrics(at: now)
        }
    }

    private func walkMetrics(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            metric(WorkoutMetricsFormat.time(state.elapsed(at: now)), label: "TIME",
                   accessibility: "Active time", color: state.phase == .paused ? .orange : accent)
            WatchWalkCompanionProgress(steps: state.steps, image: companionImage, name: companionName,
                evolution: evolution?.duringWorkout(steps: state.steps, anchor: state.evolutionAnchor))
            let distance = WorkoutMetricsFormat.distance(state.distanceMiles)
            metric(distance.value, label: distance.unit, accessibility: "Distance")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func metrics(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if showsEffort {
                metric(WorkoutMetricsFormat.pace(elapsed: state.elapsed, miles: state.distanceMiles),
                       label: "/MI", accessibility: "Average pace", color: accent)
                metric(state.currentHeartRate(at: now).map { "\(Int($0))" } ?? "—",
                       label: "BPM", accessibility: "Heart rate", color: .pink)
                metric("\(Int(max(0, state.calories)))", label: "CAL", accessibility: "Active calories")
            } else {
                Text(WorkoutMetricsFormat.time(state.elapsed(at: now)))
                    .font(.system(size: valueSize + 2, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.phase == .paused ? .orange : accent)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityLabel("Active time")
                    .accessibilityValue(WorkoutMetricsFormat.time(state.elapsed(at: now)))
                metric(state.steps.formatted(), label: "STEPS", accessibility: "Steps")
                let distance = WorkoutMetricsFormat.distance(state.distanceMiles)
                metric(distance.value, label: distance.unit, accessibility: "Distance")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func metric(_ value: String, label: String, accessibility: String, color: Color = .white) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                metricValue(value, color: color)
                metricLabel(label)
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 0) {
                metricValue(value, color: color)
                metricLabel(label)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .accessibilityValue("\(value) \(label)")
    }

    private func metricValue(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.system(size: valueSize, weight: .medium, design: .rounded))
            .foregroundStyle(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
    }

    private func metricLabel(_ label: String) -> some View {
        Text(label).font(.system(size: labelSize, weight: .semibold))
            .foregroundStyle(.secondary).lineLimit(1).fixedSize()
    }
}

private struct WatchWalkCompanionProgress: View {
    @Environment(\.watchAccent) private var accent
    let steps: Int
    let image: UIImage?
    let name: String?
    let evolution: WorkoutEvolutionProgress?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var stepSize: CGFloat = 27
    @ScaledMetric(relativeTo: .caption2) private var captionSize: CGFloat = 11

    var body: some View {
        let progress = WatchStepProgress(steps: steps)
        HStack(spacing: 8) {
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(accent.opacity(0.22), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: 0.75 * (evolution?.fraction ?? 0))
                    .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .animation(reduceMotion || dimmed ? nil : .easeOut(duration: 0.3), value: evolution?.fraction)
                WatchCurrentCreature(image: image, size: 43)
            }
            .frame(width: 52, height: 52)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name.map { "Your companion, \($0)" } ?? "Creature syncing")
            .accessibilityValue(evolution?.accessibilityValue ?? "Evolution progress syncing from iPhone")
            VStack(alignment: .leading, spacing: 5) {
                if dynamicTypeSize > .large {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(progress.steps.formatted())
                            .font(.system(size: stepSize, weight: .semibold, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                        Text("steps").font(.system(size: captionSize, weight: .medium))
                            .fixedSize()
                    }
                    .foregroundStyle(.white)
                } else {
                    (Text(progress.steps.formatted())
                        .font(.system(size: stepSize, weight: .semibold, design: .rounded))
                     + Text(" steps").font(.system(size: captionSize, weight: .medium)))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                        .foregroundStyle(.white)
                }
                Text(milestoneCaption)
                    .font(.system(size: captionSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Walk steps")
            .accessibilityValue("\(progress.steps.formatted()) steps. \(evolution?.accessibilityValue ?? "Evolution progress syncing")")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var milestoneCaption: String {
        guard let evolution else { return "Evolution syncing…" }
        guard evolution.readyEventID != nil else { return evolution.caption }
        switch evolution.milestone {
        case .hatch: return "Hatch on iPhone"
        case .evolve: return "Evolve on iPhone"
        case .mature, .complete: return "Choose egg on iPhone"
        }
    }

}
