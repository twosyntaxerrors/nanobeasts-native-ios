import SwiftUI

struct ProgressRing: View {
    let progress: Double
    let stage: CreatureStage
    var energy: Double = 0

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    NanoTheme.elevated,
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: 0.75 * clampedProgress)
                .stroke(
                    NanoTheme.teal,
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .shadow(
                    color: NanoTheme.teal.opacity(0.42 + 0.30 * energy),
                    radius: 6 + 8 * energy
                )

            if clampedProgress > 0.004 {
                Circle()
                    .trim(
                        from: max(0, 0.75 * clampedProgress - 0.006),
                        to: 0.75 * clampedProgress
                    )
                    .stroke(
                        NanoTheme.ink.opacity(0.68 + 0.22 * energy),
                        style: StrokeStyle(
                            lineWidth: 7 + 2 * energy,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(135))
                    .shadow(
                        color: NanoTheme.cyan.opacity(0.76),
                        radius: 5 + 10 * energy
                    )
                    .shadow(
                        color: NanoTheme.teal.opacity(0.52),
                        radius: 10 + 12 * energy
                    )
            }

            HomeR2AnimatedArtwork(stage: stage)
                // Animation canvases already include transparent space around the creature.
                .padding(stage.isEgg ? 14 : 0)
                .scaleEffect(stage.isEgg ? 1 : 1.08)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stage.name), \(Int(progress * 100)) percent researched")
    }
}

private struct HomeR2AnimatedArtwork: View {
    let stage: CreatureStage

    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        ZStack {
            if !loaded {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(NanoTheme.teal)
                    if failed {
                        Text("RECONNECTING TO R2")
                            .font(NanoFont.aldrich(7))
                            .tracking(1)
                            .foregroundStyle(NanoTheme.secondaryText)
                    }
                }
            }

            RemoteAnimatedWebPView(
                url: R2AnimationManifest.url(for: stage),
                onLoad: { succeeded in
                    loaded = succeeded
                    failed = !succeeded
                }
            )
            .opacity(loaded ? 1 : 0)
        }
        .onChange(of: stage.id) {
            loaded = false
            failed = false
        }
    }
}

struct StepMetricCard: View {
    let icon: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(NanoTheme.teal)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(NanoTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit.uppercased())
                .lineLimit(1).minimumScaleFactor(0.8)
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(NanoTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
        .nanoCard(padding: 14)
    }
}

struct TypePill: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .lineLimit(1).minimumScaleFactor(0.8)
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(NanoTheme.teal)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(NanoTheme.teal.opacity(0.10))
                    .stroke(NanoTheme.teal.opacity(0.32), lineWidth: 1)
            )
    }
}

struct HealthStatusBanner: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.healthState.title)
                    .font(.subheadline.weight(.semibold))
                if case .failed(let message) = store.healthState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(NanoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if store.healthState == .notRequested {
                Button("Connect") {
                    Task { await store.requestHealthAccess() }
                }
                .fixedSize(horizontal: true, vertical: false)
                .buttonStyle(.borderedProminent)
                .tint(NanoTheme.teal)
                .foregroundStyle(NanoTheme.background)
            } else if case .failed = store.healthState {
                Button("Retry") {
                    Task { await store.requestHealthAccess() }
                }
                .fixedSize(horizontal: true, vertical: false)
                .buttonStyle(.bordered)
            }
        }
        .nanoCard(padding: 14)
    }

    private var statusIcon: String {
        switch store.healthState {
        case .connected: "heart.fill"
        case .connecting: "arrow.triangle.2.circlepath"
        case .notRequested: "heart"
        case .unavailable: "heart.slash"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch store.healthState {
        case .connected: NanoTheme.pink
        case .failed, .unavailable: NanoTheme.orange
        default: NanoTheme.teal
        }
    }
}

struct HealthAccessView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var onPreviewCompletion: (() -> Void)? = nil
    var onPreviewSkip: (() -> Void)? = nil

    private var isConnecting: Bool {
        onPreviewCompletion == nil && store.healthState == .connecting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your steps grow this egg", systemImage: "heart.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(NanoTheme.text)
                    Text("Every step can help hatch your egg. Connect Apple Health to add your walking steps to the ring automatically.")
                        .font(.subheadline)
                        .foregroundStyle(NanoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Reads step counts only. Your Health data stays on your device.", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(NanoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .failed = store.healthState {
                        Text("Couldn’t connect. Try again, or continue and connect later in Settings.")
                            .font(.caption).foregroundStyle(NanoTheme.pink)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button(action: connect) {
                HStack {
                    if isConnecting { ProgressView().tint(NanoTheme.onAccent) }
                    Text(isConnecting ? "Connecting…" : "Connect Apple Health")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(NanoTheme.onAccent)
                .background(NanoTheme.teal, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)

            Button("Not now") {
                if let onPreviewSkip { onPreviewSkip() }
                else if let onPreviewCompletion { onPreviewCompletion() }
                else { dismiss() }
            }
            .font(.subheadline)
            .foregroundStyle(NanoTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .background(NanoTheme.background)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(330)])
        .presentationDragIndicator(.visible)
    }

    private func connect() {
        if let onPreviewCompletion { onPreviewCompletion(); return }
        Task {
            await store.requestHealthAccess()
            if store.healthState == .connected { dismiss() }
        }
    }
}
