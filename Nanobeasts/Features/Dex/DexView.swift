import SwiftUI
import UIKit

struct DexView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTourFocus) private var tourFocus
    @State private var selection: DexSelection?
    @State private var filter: DexFilter = .all
    @State private var isVisible = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var foundStages: [CreatureStage] {
        store.catalog.creatureStages.filter {
            store.isDiscovered($0) || store.isCurrent($0)
        }
    }

    private var displayedStages: [CreatureStage] {
        switch filter {
        case .all:
            store.catalog.creatureStages
        case .found:
            foundStages
        }
    }

    private var completion: Double {
        guard !store.catalog.creatureStages.isEmpty else { return 0 }
        return Double(foundStages.count) / Double(store.catalog.creatureStages.count)
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                    DexScreenHeader()

                    DexProgressHUD(
                        found: foundStages.count,
                        total: store.catalog.creatureStages.count,
                        completion: completion
                    )

                    DexCollectionHeader(
                        count: displayedStages.count,
                        filter: $filter
                    )

                    if displayedStages.isEmpty {
                        DexEmptyState(filter: filter)
                    } else {
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(displayedStages) { stage in
                                    let isLocked = !foundStages.contains(stage)
                                    Button {
                                        selection = DexSelection(stage: stage, isLocked: isLocked)
                                    } label: {
                                        DexArchiveCard(
                                            stage: stage,
                                            number: dexNumber(for: stage),
                                            isCurrent: store.isCurrent(stage),
                                            isLocked: isLocked,
                                            playsAnimation: isVisible
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .appTourTarget(stage.id == displayedStages.first?.id ? .dex : nil)
                                    .id(stage.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .task(id: tourFocus) {
                    guard tourFocus == .dex else { return }
                    filter = .all
                    await Task.yield()
                    guard !Task.isCancelled, let first = displayedStages.first else { return }
                    proxy.scrollTo(first.id, anchor: .top)
                }
                .task {
                    guard AppScreenshotScenario.active == .featureTourDex else { return }
                    let stages = store.catalog.creatureStages
                    guard !stages.isEmpty else { return }
                    let target = stages[min(22, stages.count - 1)]

                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    withAnimation(.smooth(duration: 4)) {
                        proxy.scrollTo(target.id, anchor: .center)
                    }

                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    selection = DexSelection(stage: target, isLocked: false)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            isVisible = true
            if AppScreenshotScenario.active == .dexDetail, selection == nil {
                let stage = store.catalog.creatureStages.first(where: {
                    $0.name == "Overnode"
                }) ?? store.currentStage
                selection = DexSelection(stage: stage, isLocked: false)
            }
        }
        .onDisappear { isVisible = false }
        .sheet(item: $selection) { selection in
            CreatureDetailView(
                stage: selection.stage,
                isLocked: selection.isLocked,
                unlockedEntries: foundStages
            )
        }
    }

    private func dexNumber(for stage: CreatureStage) -> Int {
        (store.catalog.creatureStages.firstIndex(of: stage) ?? 0) + 1
    }
}

private struct DexSelection: Identifiable {
    let stage: CreatureStage
    let isLocked: Bool

    var id: String { stage.id }
}

private enum DexFilter: String, CaseIterable, Identifiable {
    case all = "ALL"
    case found = "FOUND"

    var id: String { rawValue }
}

private struct DexScreenHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("FIELD DEX")
                .font(NanoFont.aldrich(28))
                .tracking(1.2)
                .foregroundStyle(.white)
            Text("Catalog every species you evolve.")
                .font(NanoFont.aldrich(14))
                .foregroundStyle(NanoTheme.secondaryText)
        }
    }
}

private struct DexProgressHUD: View {
    let found: Int
    let total: Int
    let completion: Double

    private var percentage: Int {
        Int((completion * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("CATALOG PROGRESS")
                        .font(NanoFont.aldrich(10))
                        .tracking(1.3)
                        .foregroundStyle(NanoTheme.teal)
                    Text("\(percentage)% COMPLETE")
                        .font(NanoFont.aldrich(25))
                        .foregroundStyle(.white)
                }

                Spacer()

                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(NanoTheme.teal)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(NanoTheme.teal.opacity(0.09))
                            .stroke(NanoTheme.teal.opacity(0.42), lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                DexStatChip(
                    label: "FOUND",
                    value: found,
                    valueColor: NanoTheme.teal,
                    emphasized: true
                )
                DexStatChip(
                    label: "LOCKED",
                    value: max(total - found, 0),
                    valueColor: .white,
                    emphasized: false
                )
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NanoTheme.teal.opacity(0.08))
                        .stroke(NanoTheme.teal.opacity(0.25), lineWidth: 1)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [NanoTheme.teal, NanoTheme.teal.opacity(0.70)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * completion)
                        .shadow(color: NanoTheme.teal.opacity(0.55), radius: 7)
                }
            }
            .frame(height: 8)
        }
        .nanoHUDCard(radius: 24, padding: 18, illuminated: true)
    }
}

private struct DexStatChip: View {
    let label: String
    let value: Int
    let valueColor: Color
    let emphasized: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(NanoFont.aldrich(9))
                .tracking(1.1)
                .foregroundStyle(NanoTheme.secondaryText)
            Spacer()
            Text(value.formatted())
                .font(NanoFont.aldrich(20))
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(emphasized ? NanoTheme.teal.opacity(0.06) : NanoTheme.elevated.opacity(0.56))
                .stroke(
                    emphasized ? NanoTheme.teal.opacity(0.20) : NanoTheme.elevated,
                    lineWidth: 1
                )
        )
    }
}

private struct DexCollectionHeader: View {
    let count: Int
    @Binding var filter: DexFilter

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SPECIMEN ARCHIVE")
                    .font(NanoFont.aldrich(13))
                    .tracking(1.1)
                Text("\(count) entries shown")
                    .font(NanoFont.aldrich(10))
                    .foregroundStyle(NanoTheme.secondaryText)
            }

            Spacer(minLength: 2)

            HStack(spacing: 3) {
                ForEach(DexFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        Text(option.rawValue)
                            .font(NanoFont.aldrich(9))
                            .foregroundStyle(
                                filter == option ? NanoTheme.teal : NanoTheme.mutedText
                            )
                            .frame(width: 54, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 11)
                                    .fill(filter == option ? NanoTheme.teal.opacity(0.10) : .clear)
                                    .stroke(
                                        filter == option ? NanoTheme.teal.opacity(0.38) : .clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(NanoTheme.surface)
                    .stroke(NanoTheme.elevated, lineWidth: 1)
            )
        }
    }
}

private struct LockedCreatureArtwork: View {
    let stage: CreatureStage
    let inset: CGFloat

    // Blur radius as a percentage of the square artwork frame. Adjust here for
    // both the collection cards and locked specimen profiles.
    private static let blurPercentage: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = max(0, min(proxy.size.width, proxy.size.height) - inset * 2)

            NanoTheme.secondaryText
                .mask {
                    CreatureArtworkView(stage: stage)
                        .padding(inset)
                }
                .opacity(0.75)
                .blur(radius: artworkSize * Self.blurPercentage / 100)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Undiscovered Nanobeast silhouette")
    }
}

private struct DexArchiveCard: View {
    let stage: CreatureStage
    let number: Int
    let isCurrent: Bool
    let isLocked: Bool
    let playsAnimation: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(format: "#%03d", number))
                    .foregroundStyle(NanoTheme.secondaryText)
                Spacer()
                Text(isLocked ? "LOCK" : isCurrent ? "ACTIVE" : "S\(stage.stage)/3")
                    .foregroundStyle(isLocked ? NanoTheme.mutedText : NanoTheme.teal)
            }
            .font(NanoFont.aldrich(10))
            .tracking(0.5)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                LinearGradient(
                    colors: [NanoTheme.teal.opacity(0.20), NanoTheme.surface],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            ZStack {
                NanoTheme.background
                LabGridBackground()
                if isLocked {
                    LockedCreatureArtwork(stage: stage, inset: 10)
                } else {
                    AnimatedCreatureArtworkView(
                        stage: stage,
                        isPlaying: playsAnimation
                    )
                        .padding(10)
                }

                if isLocked {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("LOCKED")
                            .font(NanoFont.aldrich(9))
                            .tracking(1.2)
                    }
                    .foregroundStyle(NanoTheme.secondaryText)
                    .padding(7)
                    .background(Capsule().fill(NanoTheme.surface.opacity(0.90)))
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(height: 126)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(NanoTheme.teal.opacity(0.27), lineWidth: 1)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            VStack(spacing: 5) {
                Text(isLocked ? "???" : stage.name)
                    .font(NanoFont.aldrich(13))
                    .foregroundStyle(isLocked ? NanoTheme.mutedText : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if !isLocked, let type = stage.types.first {
                    DexTypeChip(type: type)
                } else {
                    Text("ENCRYPTED")
                        .font(NanoFont.aldrich(8))
                        .tracking(1)
                        .foregroundStyle(NanoTheme.mutedText)
                        .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
            .padding(.horizontal, 8)
            .background(NanoTheme.surface)
        }
        .background(NanoTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isLocked ? NanoTheme.elevated : NanoTheme.teal.opacity(0.40),
                    lineWidth: 1
                )
        )
        .accessibilityLabel(
            isLocked ? "Locked specimen number \(number)" : "\(stage.name), specimen number \(number)"
        )
    }
}

private struct DexTypeChip: View {
    let type: String

    private var tint: Color {
        switch type.lowercased() {
        case "fire": NanoTheme.orange
        case "water": .blue
        case "grass": NanoTheme.green
        case "electric": .yellow
        case "fighting": NanoTheme.danger
        case "bug": Color(red: 0.66, green: 0.72, blue: 0.13)
        case "psychic", "fairy": NanoTheme.pink
        case "dragon", "ghost": NanoTheme.purple
        case "steel": Color(red: 0.72, green: 0.72, blue: 0.82)
        default: NanoTheme.secondaryText
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
            Text(type.uppercased())
                .font(NanoFont.aldrich(9))
                .tracking(0.5)
                .foregroundStyle(NanoTheme.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(tint.opacity(0.08))
                .stroke(tint.opacity(0.55), lineWidth: 1)
        )
    }
}

private struct DexEmptyState: View {
    let filter: DexFilter

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 34))
                .foregroundStyle(NanoTheme.teal)
            Text(filter == .found ? "NO RECORDED SPECIMENS" : "NO DISCOVERIES YET")
                .font(NanoFont.aldrich(14))
                .multilineTextAlignment(.center)
            Text("Keep walking to reveal your next Nanobeast. Undiscovered creatures stay hidden.")
                .font(NanoFont.aldrich(10))
                .foregroundStyle(NanoTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .nanoHUDCard()
    }
}

struct CreatureDetailView: View {
    let isLocked: Bool
    let unlockedEntries: [CreatureStage]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(AppStore.self) private var store
    @State private var scanProgress: CGFloat = 0
    @State private var scanCompleted = false
    @State private var scanningStageID: String?
    @State private var replayEvent: CreatureDiscoveryEvent?
    @State private var selectedStage: CreatureStage

    init(
        stage: CreatureStage,
        isLocked: Bool,
        unlockedEntries: [CreatureStage] = []
    ) {
        self.isLocked = isLocked
        self.unlockedEntries = unlockedEntries
        _selectedStage = State(initialValue: stage)
    }

    private var stage: CreatureStage {
        selectedStage
    }

    private var navigableStages: [CreatureStage] {
        guard !isLocked else { return [stage] }
        // Eggs are family stages but are not necessarily Dex grid entries.
        // Include them without collapsing browsing to a single selected page.
        let family = unlockedFamilyStages(for: stage)
        guard !unlockedEntries.isEmpty else { return family.isEmpty ? [stage] : family }
        let availableIDs = Set((unlockedEntries + family).map(\.id))
        return store.catalog.families.flatMap(\.stages)
            .filter { availableIDs.contains($0.id) }
    }

    private func unlockedFamilyStages(for stage: CreatureStage) -> [CreatureStage] {
        guard !isLocked else { return [] }
        return store.catalog.families
            .first(where: { $0.id == stage.familyID })?
            .stages
            .filter { store.isDiscovered($0) || store.isCurrent($0) }
            .sorted { $0.stage < $1.stage }
            ?? []
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            // Stage controls select a specimen in place. A paged TabView can
            // traverse blank intermediate pages when jumping back to an egg.
            ZStack {
                detailPage(for: selectedStage)
                    .id(selectedStage.id)
                    .transition(.opacity)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        guard abs(horizontal) > abs(value.translation.height) * 1.5,
                              let index = navigableStages.firstIndex(where: { $0.id == selectedStage.id })
                        else { return }
                        let nextIndex = index + (horizontal < 0 ? 1 : -1)
                        guard navigableStages.indices.contains(nextIndex) else { return }
                        selectStage(navigableStages[nextIndex])
                    }
            )
            .accessibilityLabel("Unlocked specimen profiles")
            .accessibilityHint("Swipe left or right to browse unlocked entries")
            .accessibilityAction(named: "Next specimen") { browseStage(offset: 1) }
            .accessibilityAction(named: "Previous specimen") { browseStage(offset: -1) }

        }
        .task(id: stage.id) {
            let stageID = stage.id
            scanningStageID = nil
            scanProgress = 0
            scanCompleted = false
            guard !isLocked else { return }

            if store.reduceMotion || accessibilityReduceMotion {
                scanningStageID = stageID
                scanProgress = 1
                scanCompleted = true
                return
            }

            // Commit the reset before starting the next scan. Without this
            // frame boundary, rapid page changes can coalesce 0 → 1 and make
            // a later profile appear already scanned.
            try? await Task.sleep(for: .milliseconds(24))
            guard !Task.isCancelled, selectedStage.id == stageID else { return }
            scanningStageID = stageID
            withAnimation(.linear(duration: 1.65)) {
                scanProgress = 1
            }
            try? await Task.sleep(for: .milliseconds(1_650))
            guard
                !Task.isCancelled,
                selectedStage.id == stageID,
                scanningStageID == stageID
            else { return }
            withAnimation(.snappy) {
                scanCompleted = true
            }
            if store.hapticsEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .onChange(of: selectedStage.id) {
            guard store.hapticsEnabled else { return }
            UISelectionFeedbackGenerator().selectionChanged()
        }
        .fullScreenCover(item: $replayEvent) { event in
            EvolutionLifecycleExperience(
                catalog: store.catalog,
                event: event,
                nextEggs: [],
                allowsDismissal: true,
                onChooseEgg: nil
            )
            .environment(store)
        }
    }

    private func selectStage(_ next: CreatureStage) {
        guard next.id != selectedStage.id else { return }
        withAnimation(.easeOut(duration: store.reduceMotion || accessibilityReduceMotion ? 0.12 : 0.24)) {
            selectedStage = next
        }
    }

    private func browseStage(offset: Int) {
        guard let index = navigableStages.firstIndex(where: { $0.id == selectedStage.id }),
              navigableStages.indices.contains(index + offset) else { return }
        selectStage(navigableStages[index + offset])
    }

    private func detailPage(for entry: CreatureStage) -> some View {
        ScrollView {
                VStack(spacing: 18) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("SPECIMEN PROFILE")
                                .font(NanoFont.aldrich(10))
                                .tracking(1.5)
                                .foregroundStyle(NanoTheme.teal)
                            Text(isLocked ? "???" : entry.name.uppercased())
                                .font(NanoFont.aldrich(22))
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                        }

                        Spacer(minLength: 8)

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .accessibilityLabel("Close specimen profile")
                    }

                    HStack(spacing: 8) {
                        if isLocked {
                            DexStageCapsule(title: "LOCKED", isSelected: false)
                            Spacer()
                            Text("ENCRYPTED")
                                .font(NanoFont.aldrich(9))
                                .tracking(1)
                                .foregroundStyle(NanoTheme.secondaryText)
                        } else {
                            ForEach(unlockedFamilyStages(for: entry)) { familyStage in
                                Button {
                                    guard familyStage.id != entry.id else { return }
                                    selectStage(familyStage)
                                } label: {
                                    DexStageCapsule(
                                        title: familyStage.isEgg
                                            ? "EGG"
                                            : "STAGE \(familyStage.stage)",
                                        isSelected: familyStage.id == entry.id
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    familyStage.isEgg
                                        ? "View egg, \(familyStage.name)"
                                        : "View stage \(familyStage.stage), \(familyStage.name)"
                                )
                                .accessibilityAddTraits(
                                    familyStage.id == entry.id ? .isSelected : []
                                )
                            }

                            Spacer(minLength: 4)

                            if entry.stage > 0 {
                                Button {
                                    replayEvent = CreatureDiscoveryEvent(
                                        stage: entry,
                                        kind: entry.stage == 1 ? .hatch : .evolution
                                    )
                                } label: {
                                    Label(
                                        entry.stage == 1 ? "HATCH" : "EVOLVE",
                                        systemImage: "play.fill"
                                    )
                                    .font(NanoFont.aldrich(8))
                                    .tracking(0.6)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                    .allowsTightening(true)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .foregroundStyle(NanoTheme.background)
                                    .padding(.horizontal, 10)
                                    .frame(height: 32)
                                    .background(
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [NanoTheme.teal, NanoTheme.cyan],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    entry.stage == 1 ? "Replay hatch" : "Replay evolution"
                                )
                            } else {
                                Text("INCUBATING")
                                    .font(NanoFont.aldrich(8))
                                    .tracking(0.7)
                                    .foregroundStyle(NanoTheme.secondaryText)
                            }
                        }
                    }

                    CreatureScannerView(
                        stage: entry,
                        isLocked: isLocked,
                        progress: entry.id == scanningStageID ? scanProgress : 0,
                        scanCompleted: entry.id == scanningStageID && scanCompleted
                    )
                    .frame(height: 320)

                    if !isLocked {
                        HStack {
                            ForEach(entry.types, id: \.self) { DexTypeChip(type: $0) }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("RESEARCH NOTES")
                            .font(NanoFont.aldrich(9))
                            .tracking(1.4)
                            .foregroundStyle(NanoTheme.teal)
                        Text(
                            isLocked
                                ? "This entry is encrypted. Keep walking and evolving creatures to reveal the specimen profile."
                                : entry.description
                        )
                        .font(NanoFont.aldrich(12))
                        .foregroundStyle(isLocked ? NanoTheme.secondaryText : .white)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .nanoHUDCard()

                    if !isLocked {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(NanoTheme.teal)
                                .frame(width: 8, height: 8)
                                .shadow(color: NanoTheme.teal, radius: 7)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ARCHIVE STATUS")
                                    .font(NanoFont.aldrich(8))
                                    .tracking(1.2)
                                    .foregroundStyle(NanoTheme.teal)
                                Text(
                                    entry.id == scanningStageID && scanCompleted
                                        ? "BIOMETRIC PROFILE VERIFIED"
                                        : "RENDERING SPECIMEN DATA"
                                )
                                    .font(NanoFont.aldrich(10))
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                            Image(
                                systemName: entry.id == scanningStageID && scanCompleted
                                    ? "checkmark.seal.fill"
                                    : "waveform.path.ecg"
                            )
                                .foregroundStyle(NanoTheme.teal)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(NanoTheme.teal.opacity(0.05))
                                .stroke(NanoTheme.teal.opacity(0.28), lineWidth: 1)
                        )
                    }

                }
                .padding(18)
        }
        .scrollIndicators(.hidden)
    }

}

private struct DexStageCapsule: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(NanoFont.aldrich(8))
            .tracking(0.9)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
            .foregroundStyle(isSelected ? NanoTheme.background : NanoTheme.teal)
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(isSelected ? NanoTheme.teal : NanoTheme.teal.opacity(0.07))
                    .stroke(
                        NanoTheme.teal.opacity(isSelected ? 0.9 : 0.42),
                        lineWidth: 1
                    )
            )
    }
}

private struct CreatureScannerView: View {
    let stage: CreatureStage
    let isLocked: Bool
    let progress: CGFloat
    let scanCompleted: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                NanoTheme.background
                LabGridBackground()

                if isLocked {
                    LockedCreatureArtwork(stage: stage, inset: 26)

                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("UNDISCOVERED SPECIES")
                            .font(NanoFont.aldrich(10))
                            .tracking(1.4)
                    }
                    .foregroundStyle(NanoTheme.secondaryText)
                    .padding(12)
                    .background(Capsule().fill(NanoTheme.surface.opacity(0.90)))
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                } else {
                    if scanCompleted {
                        AnimatedCreatureArtworkView(stage: stage)
                            .padding(26)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        CreatureArtworkView(stage: stage)
                            .padding(26)
                            .saturation(0)
                            .colorMultiply(NanoTheme.teal)
                            .opacity(max(0.18, 0.72 - progress * 0.54))
                            .blur(radius: 0.7)

                        CreatureArtworkView(stage: stage)
                            .padding(26)
                            .mask(alignment: .top) {
                                VStack(spacing: 0) {
                                    Rectangle()
                                        .frame(height: proxy.size.height * progress)
                                    Spacer(minLength: 0)
                                }
                            }
                    }

                    if !scanCompleted {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        NanoTheme.teal.opacity(0.95),
                                        .white,
                                        NanoTheme.teal.opacity(0.95),
                                        .clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2)
                            .shadow(color: NanoTheme.teal, radius: 10)
                            .offset(y: -proxy.size.height / 2 + proxy.size.height * progress)
                    }

                    VStack {
                        HStack {
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(NanoFont.spaceMono(9, bold: true))
                                .foregroundStyle(NanoTheme.teal)
                                .contentTransition(.numericText())
                                .padding(.horizontal, 9)
                                .frame(height: 28)
                                .background(
                                    Capsule()
                                        .fill(NanoTheme.background.opacity(0.88))
                                        .stroke(NanoTheme.teal.opacity(0.52), lineWidth: 1)
                                )
                        }
                        Spacer()
                    }
                    .padding(12)
                }

                VStack {
                    Spacer()
                    Text(
                        isLocked
                            ? "LOCKED ENTRY"
                            : scanCompleted ? "CATALOGED • PROFILE STABLE" : "BIOMETRIC SCAN IN PROGRESS"
                    )
                    .font(NanoFont.aldrich(8))
                    .tracking(1.1)
                    .foregroundStyle(isLocked ? NanoTheme.mutedText : NanoTheme.teal)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(
                        Capsule()
                            .fill(NanoTheme.background.opacity(0.92))
                            .stroke(
                                isLocked
                                    ? NanoTheme.mutedText.opacity(0.38)
                                    : NanoTheme.teal.opacity(0.42),
                                lineWidth: 1
                            )
                    )
                    .padding(.bottom, 12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        isLocked ? NanoTheme.mutedText.opacity(0.35) : NanoTheme.teal.opacity(0.52),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isLocked ? .clear : NanoTheme.teal.opacity(scanCompleted ? 0.16 : 0.30),
                radius: 16
            )
        }
    }
}
