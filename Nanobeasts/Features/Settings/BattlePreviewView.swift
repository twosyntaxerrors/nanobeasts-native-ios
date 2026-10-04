import SpriteKit
import SwiftUI
import UIKit

struct BattlePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store

    @State private var scene = BattleArenaScene(size: CGSize(width: 720, height: 720))
    @State private var telemetry = BattlePreviewTelemetry()
    @State private var battleSeed: UInt64 = 0xA11C_E001
    @State private var selectedFighterID = BattleFighterDefinition.previewRoster[0].id
    @State private var playbackRate: Double = 1

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    briefing
                    rosterPicker
                    arena
                    eventFeed
                    controls
                    prototypeNote
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: configureScene)
        .onDisappear {
            if telemetry.phase == .running {
                scene.pauseBattle()
            }
            scene.onTelemetry = nil
        }
        .onChange(of: telemetry.phase) { _, phase in
            guard phase == .finished, store.hapticsEnabled else { return }
            let feedback: UINotificationFeedbackGenerator.FeedbackType =
                telemetry.winnerID == selectedFighterID ? .success : .warning
            UINotificationFeedbackGenerator().notificationOccurred(feedback)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SETTINGS / EXPERIMENTAL")
                    .font(NanoFont.aldrich(9))
                    .tracking(1.4)
                    .foregroundStyle(NanoTheme.teal)
                Text("ARENA SIMULATION")
                    .font(NanoFont.aldrich(21))
                    .tracking(1.1)
                    .foregroundStyle(.white)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(NanoTheme.surface)
                            .stroke(NanoTheme.elevated, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close arena simulation")
        }
    }

    private var briefing: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 13) {
                Image(selectedFighter.assetName)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.black.opacity(0.24))
                            .stroke(NanoTheme.teal.opacity(0.32), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(selectedFighter.name.uppercased()) // \(selectedFighter.className.uppercased()) CLASS")
                        .font(NanoFont.aldrich(13))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                    Text("A true four-beast free-for-all. Every fighter independently targets any surviving opponent until only one remains.")
                        .font(NanoFont.aldrich(9))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                BattleStatChip(
                    title: "TIME",
                    value: "\(telemetry.secondsRemaining)s",
                    color: telemetry.secondsRemaining <= 13 ? .orange : NanoTheme.teal
                )
                BattleStatChip(
                    title: "ACTIVE",
                    value: "\(telemetry.combatantsRemaining) / 4",
                    color: .white
                )
                BattleStatChip(
                    title: "STATE",
                    value: phaseLabel,
                    color: phaseColor
                )
            }
        }
        .nanoHUDCard(radius: 22, padding: 15, illuminated: true)
    }

    private var rosterPicker: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BATTLE-READY COLLECTION")
                        .font(NanoFont.aldrich(10))
                        .tracking(1)
                        .foregroundStyle(.white)
                    Text("Choose the beast you want to root for.")
                        .font(NanoFont.aldrich(8))
                        .foregroundStyle(NanoTheme.secondaryText)
                }
                Spacer()
                Text("4 READY")
                    .font(NanoFont.aldrich(8))
                    .foregroundStyle(NanoTheme.teal)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4),
                spacing: 7
            ) {
                ForEach(BattleFighterDefinition.previewRoster) { fighter in
                    BattleRosterCell(
                        fighter: fighter,
                        isSelected: fighter.id == selectedFighterID
                    ) {
                        select(fighter)
                    }
                    .disabled(telemetry.phase == .running || telemetry.phase == .paused)
                }
            }
        }
        .nanoHUDCard(radius: 20, padding: 13)
    }

    private var arena: some View {
        SpriteView(
            scene: scene,
            preferredFramesPerSecond: 60,
            options: [.allowsTransparency]
        )
        .aspectRatio(1, contentMode: .fit)
        .background(Color(red: 0.13, green: 0.29, blue: 0.17))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(NanoTheme.teal.opacity(0.52), lineWidth: 1.2)
        }
        .shadow(color: NanoTheme.teal.opacity(0.12), radius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animated free-for-all with four Nanobeasts")
        .accessibilityValue(telemetry.event)
        .overlay(alignment: .topTrailing) {
            Button(action: togglePlaybackRate) {
                HStack(spacing: 5) {
                    Image(systemName: playbackRate == 2 ? "forward.fill" : "play.fill")
                    Text(playbackRate == 2 ? "2×" : "1×")
                }
                .font(NanoFont.aldrich(10))
                .foregroundStyle(playbackRate == 2 ? NanoTheme.background : .white)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(playbackRate == 2 ? NanoTheme.teal : NanoTheme.surface.opacity(0.92))
                        .stroke(NanoTheme.teal.opacity(0.55), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel("Battle speed")
            .accessibilityValue(playbackRate == 2 ? "Two times" : "Normal")
            .accessibilityHint("Toggles between normal and two times speed")
        }
    }

    private var eventFeed: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(phaseColor)
                .frame(width: 8, height: 8)
                .shadow(color: phaseColor, radius: 6)
                .padding(.top, 4)

            Text(telemetry.event)
                .font(NanoFont.aldrich(10))
                .foregroundStyle(.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(NanoTheme.surface.opacity(0.92))
                .stroke(NanoTheme.elevated, lineWidth: 1)
        )
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button(action: performPrimaryAction) {
                HStack(spacing: 9) {
                    Image(systemName: primaryIcon)
                    Text(primaryTitle)
                        .font(NanoFont.aldrich(12))
                        .tracking(1)
                }
                .foregroundStyle(NanoTheme.background)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(NanoTheme.teal)
                        .shadow(color: NanoTheme.teal.opacity(0.24), radius: 12, y: 4)
                )
            }
            .buttonStyle(.plain)

            Button(action: reshuffleMatch) {
                HStack(spacing: 9) {
                    Image(systemName: "shuffle")
                    Text("RESHUFFLE MATCH")
                        .font(NanoFont.aldrich(10))
                        .tracking(0.8)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(NanoTheme.surface)
                        .stroke(NanoTheme.elevated, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var prototypeNote: some View {
        Label(
            "Preview roster only — battles do not change steps, evolution progress, or your collection.",
            systemImage: "testtube.2"
        )
        .font(NanoFont.aldrich(9))
        .foregroundStyle(NanoTheme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var phaseLabel: String {
        switch telemetry.phase {
        case .ready: "READY"
        case .running: "LIVE"
        case .paused: "PAUSED"
        case .finished: "FINAL"
        }
    }

    private var phaseColor: Color {
        switch telemetry.phase {
        case .ready: NanoTheme.teal
        case .running: .green
        case .paused: .orange
        case .finished: telemetry.winnerID == selectedFighterID ? NanoTheme.teal : .pink
        }
    }

    private var primaryTitle: String {
        switch telemetry.phase {
        case .ready: "START BATTLE"
        case .running: "PAUSE SIMULATION"
        case .paused: "RESUME BATTLE"
        case .finished: "RUN REMATCH"
        }
    }

    private var primaryIcon: String {
        switch telemetry.phase {
        case .ready: "bolt.fill"
        case .running: "pause.fill"
        case .paused: "play.fill"
        case .finished: "arrow.counterclockwise"
        }
    }

    private var selectedFighter: BattleFighterDefinition {
        BattleFighterDefinition.previewRoster.first(where: { $0.id == selectedFighterID })
            ?? BattleFighterDefinition.previewRoster[0]
    }

    private func configureScene() {
        scene.onTelemetry = { update in
            DispatchQueue.main.async {
                telemetry = update
            }
        }
        resetArena()
        scene.setPlaybackRate(playbackRate)
    }

    private func performPrimaryAction() {
        if store.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        switch telemetry.phase {
        case .ready:
            startFreshBattle()
        case .running:
            scene.pauseBattle()
        case .paused:
            scene.resumeBattle()
        case .finished:
            startFreshBattle()
        }
    }

    private func reshuffleMatch() {
        battleSeed = UInt64.random(in: UInt64.min...UInt64.max)
        resetArena()
        if store.hapticsEnabled {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func select(_ fighter: BattleFighterDefinition) {
        guard fighter.id != selectedFighterID else { return }
        selectedFighterID = fighter.id
        battleSeed = UInt64.random(in: UInt64.min...UInt64.max)
        resetArena()
        if store.hapticsEnabled {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func togglePlaybackRate() {
        playbackRate = playbackRate == 1 ? 2 : 1
        scene.setPlaybackRate(playbackRate)
        if store.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func resetArena() {
        scene.reset(
            seed: battleSeed,
            lineup: BattleFighterDefinition.previewRoster,
            featuredFighterID: selectedFighterID
        )
    }

    private func startFreshBattle() {
        battleSeed = UInt64.random(in: UInt64.min...UInt64.max)
        resetArena()
        scene.startBattle()
    }
}

private struct BattleRosterCell: View {
    let fighter: BattleFighterDefinition
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(fighter.assetName)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 54)

                Text(fighter.name.uppercased())
                    .font(NanoFont.aldrich(6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(isSelected ? NanoTheme.teal : .white)

                Text(isSelected ? "YOUR PICK" : fighter.className.uppercased())
                    .font(NanoFont.aldrich(6))
                    .tracking(0.5)
                    .foregroundStyle(isSelected ? NanoTheme.background : NanoTheme.secondaryText)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(
                        Capsule()
                            .fill(isSelected ? NanoTheme.teal : NanoTheme.background.opacity(0.52))
                    )
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(isSelected ? NanoTheme.teal.opacity(0.08) : NanoTheme.background.opacity(0.38))
                    .stroke(
                        isSelected ? NanoTheme.teal.opacity(0.72) : NanoTheme.elevated,
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fighter.name)
        .accessibilityValue(isSelected ? "Your selected contender" : fighter.className + " class")
        .accessibilityHint("Selects this Nanobeast as your contender")
    }
}

private struct BattleStatChip: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(NanoFont.aldrich(7))
                .tracking(0.9)
                .foregroundStyle(NanoTheme.secondaryText)
            Text(value)
                .font(NanoFont.aldrich(11))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(NanoTheme.background.opacity(0.54))
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
    }
}
