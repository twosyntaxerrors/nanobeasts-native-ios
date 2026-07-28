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
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: 0.75 * clampedProgress)
                .stroke(
                    NanoTheme.teal,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
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
                        Color.white.opacity(0.68 + 0.22 * energy),
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
                .padding(25)
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
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit.uppercased())
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
                        .lineLimit(2)
                }
            }

            Spacer()

            if store.healthState == .notRequested {
                Button("Connect") {
                    Task { await store.requestHealthAccess() }
                }
                .buttonStyle(.borderedProminent)
                .tint(NanoTheme.teal)
                .foregroundStyle(NanoTheme.background)
            } else if case .failed = store.healthState {
                Button("Retry") {
                    Task { await store.requestHealthAccess() }
                }
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

    var body: some View {
        ZStack {
            NanoTheme.backgroundGradient.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(NanoTheme.pink.opacity(0.12))
                        .frame(width: 132, height: 132)
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 62))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(NanoTheme.pink, NanoTheme.teal)
                }

                VStack(spacing: 12) {
                    Text("Power your Nanobeasts")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Your steps from Apple Health become research energy. Walk to hatch eggs, evolve creatures, and fill your Dex.")
                        .font(.body)
                        .foregroundStyle(NanoTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 14) {
                    permissionRow(icon: "figure.walk", text: "Reads step count only")
                    permissionRow(icon: "lock.shield.fill", text: "Health data stays on your device")
                    permissionRow(icon: "arrow.clockwise", text: "Syncs when Apple Health changes")
                }
                .nanoCard()

                Spacer()

                Button {
                    Task {
                        await store.requestHealthAccess()
                        if store.healthState == .connected {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if store.healthState == .connecting {
                            ProgressView()
                                .tint(NanoTheme.background)
                        }
                        Text(store.healthState == .connecting ? "Connecting…" : "Connect Apple Health")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(NanoTheme.teal)
                .foregroundStyle(NanoTheme.background)
                .disabled(store.healthState == .connecting)

                Button("Not now") {
                    dismiss()
                }
                .foregroundStyle(NanoTheme.secondaryText)
            }
            .padding(24)
        }
    }

    private func permissionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(NanoTheme.teal)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }
}
