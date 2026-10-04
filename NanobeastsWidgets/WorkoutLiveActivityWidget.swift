import ActivityKit
import SwiftUI
import WidgetKit

struct NanobeastsWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.015, green: 0.025, blue: 0.027))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(WorkoutLiveLink.session(context.attributes.sessionID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(WorkoutLivePalette.teal)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutLiveTimer(state: context.state, size: 18)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.workoutName.uppercased())
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
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
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbolName)
                    .foregroundStyle(WorkoutLivePalette.teal)
            } compactTrailing: {
                WorkoutLiveTimer(state: context.state, size: 13)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "pawprint.fill")
                    .foregroundStyle(context.state.isPaused ? WorkoutLivePalette.orange : WorkoutLivePalette.teal)
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
            HStack(spacing: 12) {
                Image(systemName: context.attributes.symbolName)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(WorkoutLivePalette.teal)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(WorkoutLivePalette.teal.opacity(0.12)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.workoutName.uppercased())
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(context.state.isComplete ? "WORKOUT COMPLETE" : context.isStale ? "WAITING FOR UPDATE" : context.attributes.goalDescription.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(context.state.goalReached ? WorkoutLivePalette.teal : .white.opacity(0.55))
                }

                Spacer()
                WorkoutLiveTimer(state: context.state, size: 22)
            }

            if let goalKind = context.attributes.goalKind, goalKind != "Open Goal" {
                ProgressView(value: min(max(context.state.goalProgress, 0), 1))
                    .tint(context.state.goalReached ? WorkoutLivePalette.orange : WorkoutLivePalette.teal)
            }

            HStack(spacing: 8) {
                WorkoutLiveMetric(value: context.state.steps.formatted(), label: "STEPS")
                WorkoutLiveMetric(value: String(format: "%.2f", context.state.distanceMiles), label: "MILES")
                WorkoutLiveMetric(value: "\(context.state.calories)", label: "KCAL")

                if context.attributes.workoutSource == "watch", !context.state.isComplete {
                    Link("Open", destination: WorkoutLiveLink.session(context.attributes.sessionID))
                        .font(.caption.weight(.bold))
                        .accessibilityLabel("Open Watch workout controls")
                        .tint(WorkoutLivePalette.teal)
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
    static let teal = Color(red: 0.36, green: 0.90, blue: 0.84)
    static let orange = Color(red: 1.0, green: 0.43, blue: 0.06)
}
