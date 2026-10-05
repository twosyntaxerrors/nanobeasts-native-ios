import ActivityKit
import ImageIO
import SwiftUI
import UIKit
import WidgetKit

struct NanobeastsWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(context: context)
                .activityBackgroundTint(WorkoutLivePalette.background)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(WorkoutLiveLink.session(context.attributes.sessionID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WorkoutCompanionBadge(context: context, size: 52)
                        .padding(.leading, 2)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutLiveTimer(state: context.state, size: 18)
                        .padding(.top, 6)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.attributes.workoutName.uppercased())
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        WorkoutCompanionLine(context: context)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        WorkoutLiveMetric(value: context.state.steps.formatted(), label: "STEPS")
                        WorkoutLiveMetric(value: String(format: "%.2f", context.state.distanceMiles), label: "MI")
                        WorkoutLiveMetric(value: "\(context.state.calories)", label: "KCAL")

                        if context.attributes.workoutSource == "watch", !context.state.isComplete {
                            Link(destination: WorkoutLiveLink.session(context.attributes.sessionID)) {
                                Image(systemName: "applewatch")
                                    .frame(width: 38, height: 38)
                            }
                            .accessibilityLabel("Open Watch workout controls")
                            .tint(WorkoutLivePalette.teal)
                        } else if !context.state.isComplete {
                            Button(
                                intent: ToggleWorkoutActivityIntent(
                                    sessionID: context.attributes.sessionID,
                                    shouldPause: !context.state.isPaused
                                )
                            ) {
                                Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .frame(width: 38, height: 38)
                            }
                            .buttonStyle(.plain)
                            .tint(WorkoutLivePalette.teal)
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                WorkoutCompanionBadge(context: context, size: 24, ringWidth: 2)
            } compactTrailing: {
                WorkoutLiveTimer(state: context.state, size: 13)
            } minimal: {
                if context.state.isPaused {
                    Image(systemName: "pause.fill")
                        .foregroundStyle(WorkoutLivePalette.orange)
                } else {
                    WorkoutCompanionBadge(context: context, size: 24, ringWidth: 2)
                }
            }
            .keylineTint(WorkoutLivePalette.teal)
            .widgetURL(WorkoutLiveLink.session(context.attributes.sessionID))
        }
    }
}

private enum WorkoutLiveLink {
    static func session(_ sessionID: String) -> URL {
        URL(string: "nanobeasts://workout/session/\(sessionID)")!
    }
}

private struct WorkoutLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                WorkoutCompanionBadge(context: context, size: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.workoutName.uppercased())
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    WorkoutCompanionLine(context: context)
                    Text(statusText)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(context.state.goalReached ? WorkoutLivePalette.orange : .white.opacity(0.5))
                }

                Spacer(minLength: 4)
                WorkoutLiveTimer(state: context.state, size: 24)
            }

            if let goalKind = context.attributes.goalKind, goalKind != "Open Goal" {
                ProgressView(value: min(max(context.state.goalProgress, 0), 1))
                    .tint(context.state.goalReached ? WorkoutLivePalette.orange : WorkoutLivePalette.teal)
            }

            Rectangle()
                .fill(WorkoutLivePalette.teal.opacity(0.14))
                .frame(height: 1)

            HStack(spacing: 8) {
                WorkoutLiveMetric(value: context.state.steps.formatted(), label: "STEPS")
                WorkoutLiveMetric(value: String(format: "%.2f", context.state.distanceMiles), label: "MILES")
                WorkoutLiveMetric(value: "\(context.state.calories)", label: "KCAL")

                if context.attributes.workoutSource == "watch", !context.state.isComplete {
                    Link(destination: WorkoutLiveLink.session(context.attributes.sessionID)) {
                        Label("Open", systemImage: "applewatch")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .foregroundStyle(WorkoutLivePalette.teal)
                            .background(Capsule().fill(WorkoutLivePalette.teal.opacity(0.14)))
                            .overlay(Capsule().stroke(WorkoutLivePalette.teal.opacity(0.4), lineWidth: 1))
                    }
                    .accessibilityLabel("Open Watch workout controls")
                    .layoutPriority(1)
                } else if !context.state.isComplete {
                    Button(
                        intent: ToggleWorkoutActivityIntent(
                            sessionID: context.attributes.sessionID,
                            shouldPause: !context.state.isPaused
                        )
                    ) {
                        Label(
                            context.state.isPaused ? "Resume" : "Pause",
                            systemImage: context.state.isPaused ? "play.fill" : "pause.fill"
                        )
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(height: 34)
                        .padding(.horizontal, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WorkoutLivePalette.teal)
                    .foregroundStyle(Color.black)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                }
            }
        }
        .padding(16)
        .background(WorkoutLiveGrid())
    }

    private var statusText: String {
        if context.state.isComplete { return "WORKOUT COMPLETE" }
        if context.isStale { return "WAITING FOR UPDATE" }
        if context.state.isPaused { return "PAUSED" }
        if context.attributes.workoutSource == "watch" { return "TRACKING ON APPLE WATCH" }
        return context.attributes.goalDescription.uppercased()
    }
}

/// The current egg or creature inside the app's 270° evolution ring.
private struct WorkoutCompanionBadge: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    let size: CGFloat
    var ringWidth: CGFloat? = nil

    private var progress: Double { min(max(context.state.evolutionFraction ?? 0, 0), 1) }

    var body: some View {
        let lineWidth = ringWidth ?? max(2.5, size * 0.065)
        ZStack {
            Circle()
                .fill(WorkoutLivePalette.teal.opacity(0.08))
                .padding(lineWidth)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * progress)
                .stroke(WorkoutLivePalette.teal, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: WorkoutLivePalette.teal.opacity(0.5), radius: lineWidth)
            WorkoutCompanionArtwork(filename: context.attributes.companionArtwork,
                                    isEgg: context.attributes.companionStage == 0)
                .padding(lineWidth + size * 0.06)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(context.attributes.companionName ?? "Nanobeast")
    }
}

private struct WorkoutCompanionArtwork: View {
    let filename: String?
    let isEgg: Bool

    var body: some View {
        if let image = Self.image(filename: filename) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: isEgg ? "circle.hexagongrid.fill" : "pawprint.fill")
                .resizable()
                .scaledToFit()
                .padding(4)
                .foregroundStyle(WorkoutLivePalette.teal)
        }
    }

    /// Re-downsampled at render time so an oversized file can never blank the activity.
    private static func image(filename: String?) -> UIImage? {
        guard
            let filename,
            let data = WidgetSnapshotStore.loadArtworkData(filename: filename),
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 168
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
    }
}

/// "SPARKIT · 1,240 TO EVOLVE": who you're walking with and what the steps are doing.
private struct WorkoutCompanionLine: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .lineLimit(1).minimumScaleFactor(0.7)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(WorkoutLivePalette.teal)
    }

    private var text: String {
        let name = (context.attributes.companionName ?? "Your Nanobeast").uppercased()
        guard let caption = context.state.evolutionCaption, !caption.isEmpty else { return name }
        return "\(name) · \(caption.uppercased())"
    }
}

private struct WorkoutLiveGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for x in stride(from: 0, through: size.width, by: 18) {
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: 18) {
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(WorkoutLivePalette.teal.opacity(0.05)), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }
}

private struct WorkoutLiveMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .lineLimit(1).minimumScaleFactor(0.8)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkoutLiveTimer: View {
    let state: WorkoutActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Group {
            if state.isPaused || state.isComplete {
                Text(formatElapsed(state.elapsedSeconds))
            } else {
                Text(state.timerAnchor, style: .timer)
            }
        }
        .font(.system(size: size, weight: .bold, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.75)
        .foregroundStyle(state.isPaused ? WorkoutLivePalette.orange : WorkoutLivePalette.teal)
        .multilineTextAlignment(.trailing)
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}

private enum WorkoutLivePalette {
    static let background = Color(red: 0.015, green: 0.025, blue: 0.027)
    static let teal = Color(red: 0.36, green: 0.90, blue: 0.84)
    static let orange = Color(red: 1.0, green: 0.43, blue: 0.06)
}
