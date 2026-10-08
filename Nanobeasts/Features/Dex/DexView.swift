import SwiftUI
import UIKit

// MARK: - Type colors

/// Creature colors come from their type, so the collection reads as a varied
/// set of species. App chrome keeps using the user's accent.
enum NanoCreatureType {
    private static func baseColor(_ type: String?) -> Color {
        switch type?.lowercased() {
        case "fire": Color(red: 1.00, green: 0.54, blue: 0.24)
        case "water": Color(red: 0.24, green: 0.61, blue: 1.00)
        case "grass": Color(red: 0.36, green: 0.80, blue: 0.42)
        case "electric": Color(red: 0.97, green: 0.82, blue: 0.17)
        case "fighting": Color(red: 0.88, green: 0.33, blue: 0.24)
        case "bug": Color(red: 0.65, green: 0.79, blue: 0.19)
        case "psychic": Color(red: 1.00, green: 0.36, blue: 0.60)
        case "fairy": Color(red: 0.96, green: 0.61, blue: 0.85)
        case "dragon": Color(red: 0.54, green: 0.36, blue: 0.96)
        case "ghost": Color(red: 0.45, green: 0.44, blue: 0.78)
        case "dark": Color(red: 0.55, green: 0.47, blue: 0.66)
        case "poison": Color(red: 0.70, green: 0.36, blue: 0.84)
        case "steel": Color(red: 0.62, green: 0.68, blue: 0.76)
        case "rock": Color(red: 0.74, green: 0.64, blue: 0.38)
        case "ground": Color(red: 0.85, green: 0.64, blue: 0.36)
        case "ice": Color(red: 0.50, green: 0.88, blue: 0.94)
        default: Color(red: 0.66, green: 0.66, blue: 0.63)
        }
    }

    static func color(for stage: CreatureStage) -> Color { color(stage.types.first) }

    /// Type colors stay vivid in Dark and deepen in Light so labels stay legible.
    static func color(_ type: String?) -> Color { .nanoVivid(baseColor(type), lightFactor: 0.78) }
}

/// How much of an entry the player has seen, Pokédex style.
enum DexEntryState {
    case current, found, silhouette, unknown

    var isRevealed: Bool { self == .current || self == .found }
}

private enum DexLayout: String { case families, gallery }

private extension AppStore {
    func dexState(of stage: CreatureStage, in family: CreatureFamily?) -> DexEntryState {
        if isCurrent(stage) { return .current }
        if isDiscovered(stage) { return .found }
        // The next form after something you have is visible as a silhouette.
        let previous = family?.stages.filter { $0.stage < stage.stage }.max { $0.stage < $1.stage }
        if let previous, isDiscovered(previous) || isCurrent(previous) { return .silhouette }
        return .unknown
    }

    func family(of stage: CreatureStage) -> CreatureFamily? {
        catalog.families.first { $0.id == stage.familyID }
    }

    func dexNumber(of stage: CreatureStage) -> Int? {
        catalog.creatureStages.firstIndex(of: stage).map { $0 + 1 }
    }
}

// MARK: - Dex

struct DexView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTourFocus) private var tourFocus
    @AppStorage("nanobeasts.dex.layout.v2") private var layout: DexLayout = .gallery
    @State private var selection: DexSelection?
    @State private var typeFilter: String?
    @State private var foundOnly = false

    /// Pixel size for grid art: sharp at 3x for a ~110pt tile, ~0.5 MB decoded.
    static let tilePixels = 360

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private let mysteryColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var families: [CreatureFamily] { store.catalog.families }

    private var foundStages: [CreatureStage] {
        store.catalog.creatureStages.filter { store.isDiscovered($0) || store.isCurrent($0) }
    }

    private func isCharted(_ family: CreatureFamily) -> Bool {
        family.stages.contains { store.isDiscovered($0) || store.isCurrent($0) }
    }

    private func isComplete(_ family: CreatureFamily) -> Bool {
        family.stages.filter { !$0.isEgg }.allSatisfy { store.isDiscovered($0) || store.isCurrent($0) }
    }

    private func matchesFilter(_ family: CreatureFamily) -> Bool {
        if foundOnly { return isCharted(family) }
        guard let typeFilter else { return true }
        return family.stages.contains { $0.types.contains(typeFilter) }
    }

    private var chartedFamilies: [CreatureFamily] {
        families.filter { isCharted($0) && matchesFilter($0) }
    }

    private var unchartedFamilies: [CreatureFamily] {
        families.filter { !isCharted($0) && matchesFilter($0) }
    }

    private var gridStages: [CreatureStage] {
        if foundOnly {
            return store.catalog.creatureStages.filter { !$0.isEgg && (store.isDiscovered($0) || store.isCurrent($0)) }
        }
        return store.catalog.creatureStages.filter { typeFilter == nil || $0.types.contains(typeFilter!) }
    }

    /// Forms hatched or evolved this calendar month.
    private var newThisMonth: Int {
        let month = Calendar.autoupdatingCurrent.dateInterval(of: .month, for: .now)
        return Set(store.discoveryEvents
            .filter { $0.kind != .eggAcquired && month?.contains($0.timestamp) == true }
            .map { "\($0.familyID)-\($0.stage)" }).count
    }

    /// Types in the catalog, most common first.
    private var types: [String] {
        let counts = Dictionary(store.catalog.creatureStages.compactMap(\.types.first).map { ($0, 1) }, uniquingKeysWith: +)
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        header

                        DexProgressCard(
                            found: foundStages.count,
                            total: store.catalog.creatureStages.count,
                            completeFamilies: families.filter(isComplete).count,
                            foundFamilies: families.filter(isCharted).count,
                            totalFamilies: families.count,
                            newThisMonth: newThisMonth
                        )

                        DexCompanionCard(
                            stage: store.currentStage,
                            number: store.dexNumber(of: store.currentStage),
                            progress: store.workoutEvolutionProgress
                        ) {
                            select(store.currentStage)
                        }

                        DexTypeFilterBar(types: types, foundCount: foundStages.filter { !$0.isEgg }.count,
                                         selection: $typeFilter, foundOnly: $foundOnly)

                        if layout == .families {
                            familiesContent
                        } else {
                            galleryContent
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                    .animation(.snappy(duration: 0.25), value: typeFilter)
                    .animation(.snappy(duration: 0.25), value: foundOnly)
                }
                .scrollIndicators(.hidden)
                .task(id: tourFocus) {
                    guard tourFocus == .dex else { return }
                    typeFilter = nil
                    foundOnly = false
                    await Task.yield()
                    guard !Task.isCancelled, let anchor = tourAnchorID else { return }
                    proxy.scrollTo(anchor, anchor: .top)
                }
                .task {
                    guard AppScreenshotScenario.active == .featureTourDex else { return }
                    let stages = store.catalog.creatureStages
                    guard !stages.isEmpty else { return }
                    let target = stages[min(22, stages.count - 1)]

                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    withAnimation(.smooth(duration: 4)) {
                        proxy.scrollTo(layout == .families ? target.familyID : target.id, anchor: .center)
                    }

                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    selection = DexSelection(stage: target, isLocked: false)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Decode every tile's small art up front so fast flicks never wait on it.
            await NanoImageMemoryCache.shared.prewarmThumbnails(store.catalog.creatureStages, maxPixel: Self.tilePixels)
        }
        .onAppear {
            if AppScreenshotScenario.active == .dexDetail, selection == nil {
                let stage = store.catalog.creatureStages.first(where: {
                    $0.name == "Overnode"
                }) ?? store.currentStage
                selection = DexSelection(stage: stage, isLocked: false)
            }
        }
        .sheet(item: $selection) { selection in
            CreatureDetailView(
                stage: selection.stage,
                isLocked: selection.isLocked,
                unlockedEntries: foundStages
            )
        }
    }

    private var tourAnchorID: String? {
        layout == .families
            ? (chartedFamilies.first ?? unchartedFamilies.first)?.id
            : gridStages.first?.id
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("FIELD DEX")
                    .font(NanoFont.aldrich(28))
                    .tracking(1.2)
                    .foregroundStyle(NanoTheme.text)
                Text("Catalog every species you evolve.")
                    .font(NanoFont.aldrich(13))
                    .foregroundStyle(NanoTheme.secondaryText)
            }
            Spacer()
            HStack(spacing: 2) {
                layoutButton(.gallery, symbol: "square.grid.3x3", label: "Gallery")
                layoutButton(.families, symbol: "list.bullet.rectangle", label: "Families")
            }
            .padding(3)
            .background(Capsule().fill(NanoTheme.ink.opacity(0.06)))
        }
    }

    private func layoutButton(_ option: DexLayout, symbol: String, label: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { layout = option }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(layout == option ? NanoTheme.onAccent : NanoTheme.secondaryText)
                .frame(width: 40, height: 34)
                .background(Capsule().fill(layout == option ? NanoTheme.teal : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(layout == option ? .isSelected : [])
    }

    @ViewBuilder
    private var familiesContent: some View {
        if !chartedFamilies.isEmpty {
            StatsSectionHeader(number: 1, title: "YOUR FAMILIES") {
                Text("\(chartedFamilies.count)")
                    .font(NanoFont.spaceMono(11, bold: true))
                    .foregroundStyle(NanoTheme.secondaryText)
            }
            ForEach(chartedFamilies) { family in
                DexFamilyRow(
                    family: family,
                    isComplete: isComplete(family),
                    state: { store.dexState(of: $0, in: family) },
                    number: { store.dexNumber(of: $0) },
                    onSelect: select
                )
                .appTourTarget(family.id == tourAnchorID ? .dex : nil)
                .id(family.id)
            }
        }

        if !unchartedFamilies.isEmpty {
            StatsSectionHeader(number: chartedFamilies.isEmpty ? 1 : 2, title: "UNDISCOVERED") {
                Text("\(unchartedFamilies.count)")
                    .font(NanoFont.spaceMono(11, bold: true))
                    .foregroundStyle(NanoTheme.secondaryText)
            }
            Text("Find an egg to discover a new family.")
                .font(NanoFont.spaceMono(11))
                .foregroundStyle(NanoTheme.mutedText)
            LazyVGrid(columns: mysteryColumns, spacing: 8) {
                ForEach(unchartedFamilies) { family in
                    Button {
                        if let first = family.stages.first(where: { !$0.isEgg }) ?? family.stages.first {
                            selection = DexSelection(stage: first, isLocked: true)
                        }
                    } label: {
                        DexMysteryTile()
                    }
                    .buttonStyle(DexPressStyle())
                    .appTourTarget(family.id == tourAnchorID ? .dex : nil)
                    .id(family.id)
                }
            }
        }

        if chartedFamilies.isEmpty && unchartedFamilies.isEmpty {
            DexEmptyFilter(message: foundOnly ? "Hatch your first Nanobeast to start your collection." : "No Nanobeasts of this type yet.")
        }
    }

    @ViewBuilder
    private var galleryContent: some View {
        if gridStages.isEmpty {
            DexEmptyFilter(message: foundOnly ? "Hatch your first Nanobeast to start your collection." : "No Nanobeasts of this type yet.")
        } else {
            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(gridStages) { stage in
                    let state = store.dexState(of: stage, in: store.family(of: stage))
                    Button { select(stage) } label: {
                        DexGridTile(stage: stage, number: store.dexNumber(of: stage) ?? 0, state: state)
                    }
                    .buttonStyle(DexPressStyle())
                    .appTourTarget(stage.id == tourAnchorID ? .dex : nil)
                    .id(stage.id)
                }
            }
        }
    }

    private func select(_ stage: CreatureStage) {
        let state = store.dexState(of: stage, in: store.family(of: stage))
        selection = DexSelection(stage: stage, isLocked: !state.isRevealed)
    }
}

private struct DexSelection: Identifiable {
    let stage: CreatureStage
    let isLocked: Bool

    var id: String { stage.id }
}

private struct DexPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Header cards

private struct DexProgressCard: View {
    let found: Int
    let total: Int
    let completeFamilies: Int
    let foundFamilies: Int
    let totalFamilies: Int
    let newThisMonth: Int

    private var completion: Double { total > 0 ? Double(found) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(NanoTheme.ink.opacity(0.07), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: completion)
                    .stroke(AngularGradient(colors: [NanoTheme.cyan, NanoTheme.teal], center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: NanoTheme.teal.opacity(0.5), radius: 6)
                VStack(spacing: 0) {
                    Text("\(found)")
                        .font(NanoFont.aldrich(30))
                        .foregroundStyle(NanoTheme.text)
                    Text("of \(total)")
                        .font(NanoFont.spaceMono(10))
                        .foregroundStyle(NanoTheme.secondaryText)
                }
            }
            .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 10) {
                Text("\(Int((completion * 100).rounded()))% CATALOGED")
                    .font(NanoFont.aldrich(15))
                    .tracking(1)
                    .foregroundStyle(NanoTheme.teal)
                tally("FAMILIES FOUND", "\(foundFamilies)/\(totalFamilies)")
                tally("FULLY EVOLVED", "\(completeFamilies)/\(totalFamilies)")
                tally("NEW THIS MONTH", "\(newThisMonth)")
            }
        }
        .statsPanel()
        .accessibilityElement(children: .combine)
    }

    private func tally(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(NanoFont.aldrich(9)).tracking(1.1)
                .foregroundStyle(NanoTheme.secondaryText)
            Spacer(minLength: 6)
            Text(value)
                .font(NanoFont.aldrich(15))
                .foregroundStyle(NanoTheme.text)
        }
    }
}

private struct DexCompanionCard: View {
    let stage: CreatureStage
    let number: Int?
    let progress: WorkoutEvolutionProgress
    let onOpen: () -> Void

    private var tint: Color { NanoCreatureType.color(for: stage) }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [tint.opacity(0.45), tint.opacity(0.05)],
                                                 center: .center, startRadius: 2, endRadius: 40))
                    CreatureArtworkView(stage: stage).padding(8)
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 5) {
                    Text("ACTIVE COMPANION")
                        .font(NanoFont.aldrich(9)).tracking(1.3)
                        .foregroundStyle(NanoTheme.secondaryText)
                    Text(stage.name)
                        .font(NanoFont.aldrich(19))
                        .foregroundStyle(NanoTheme.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if progress.milestone != .complete, progress.allowsProgress {
                        GeometryReader { proxy in
                            Capsule().fill(NanoTheme.ink.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(tint).frame(width: proxy.size.width * progress.fraction)
                                }
                        }
                        .frame(height: 5)
                        Text(progress.caption)
                            .font(NanoFont.spaceMono(10))
                            .foregroundStyle(NanoTheme.secondaryText)
                    } else if let type = stage.types.first {
                        DexTypePill(type: type)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 6) {
                    if let number {
                        Text(String(format: "#%03d", number))
                            .font(NanoFont.spaceMono(11, bold: true))
                            .foregroundStyle(tint)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(NanoTheme.mutedText)
                }
            }
            .statsPanel(tint: tint, glow: 0.18, padding: 14)
        }
        .buttonStyle(DexPressStyle())
        .accessibilityLabel("Active companion, \(stage.name). \(progress.caption)")
        .accessibilityHint("Opens its Dex entry")
    }
}

private struct DexTypeFilterBar: View {
    let types: [String]
    let foundCount: Int
    @Binding var selection: String?
    @Binding var foundOnly: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "ALL", color: NanoTheme.teal, isSelected: selection == nil && !foundOnly,
                     accessibility: "All Nanobeasts") {
                    selection = nil; foundOnly = false
                }
                chip(label: "FOUND · \(foundCount)", color: NanoTheme.teal, symbol: "checkmark.seal.fill",
                     isSelected: foundOnly, accessibility: "Discovered Nanobeasts, \(foundCount)") {
                    selection = nil; foundOnly.toggle()
                }
                ForEach(types, id: \.self) { type in
                    chip(label: type.uppercased(), color: NanoCreatureType.color(type), dot: true,
                         isSelected: selection == type, accessibility: "\(type) type") {
                        foundOnly = false
                        selection = selection == type ? nil : type
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func chip(label: String, color: Color, symbol: String? = nil, dot: Bool = false,
                      isSelected: Bool, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if dot {
                    Circle().fill(color).frame(width: 7, height: 7)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
                }
                Text(label)
                    .font(NanoFont.aldrich(10)).tracking(0.8)
                    .foregroundStyle(isSelected ? NanoTheme.text : NanoTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(isSelected ? color.opacity(0.24) : NanoTheme.ink.opacity(0.05)))
            .overlay(Capsule().strokeBorder(isSelected ? color.opacity(0.8) : .clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Entries

/// A crisp, solid silhouette of a creature you haven't caught yet.
struct DexSilhouette: View {
    let stage: CreatureStage
    var opacity: Double = 0.2

    var body: some View {
        NanoTheme.ink.opacity(opacity)
            .mask { CreatureArtworkView(stage: stage, maxPixel: DexView.tilePixels) }
            .accessibilityLabel("Undiscovered Nanobeast")
    }
}

/// One slot of an evolution line: art, silhouette, or an unknown "?".
struct DexSlot: View {
    let stage: CreatureStage
    let state: DexEntryState
    let tint: Color
    var showsCaption = true

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(state.isRevealed
                          ? AnyShapeStyle(RadialGradient(colors: [tint.opacity(0.34), tint.opacity(0.08)],
                                                         center: .center, startRadius: 2, endRadius: 46))
                          : AnyShapeStyle(NanoTheme.ink.opacity(0.035)))
                switch state {
                case .current, .found:
                    CreatureArtworkView(stage: stage, maxPixel: DexView.tilePixels).padding(stage.isEgg ? 12 : 6)
                case .silhouette:
                    DexSilhouette(stage: stage).padding(stage.isEgg ? 12 : 6)
                case .unknown:
                    Text("?")
                        .font(NanoFont.aldrich(22))
                        .foregroundStyle(NanoTheme.mutedText)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(state == .current ? tint : state == .unknown ? NanoTheme.ink.opacity(0.08) : .clear,
                                  style: StrokeStyle(lineWidth: state == .current ? 2 : 1,
                                                     dash: state == .unknown ? [4, 3] : []))
            }
            .overlay(alignment: .top) {
                if state == .current {
                    Text("ACTIVE")
                        .font(NanoFont.aldrich(7)).tracking(0.8)
                        .foregroundStyle(NanoTheme.onAccent)
                        .padding(.horizontal, 5).frame(height: 13)
                        .background(Capsule().fill(tint))
                        .offset(y: -6)
                }
            }

            if showsCaption {
                Text(state.isRevealed ? (stage.isEgg ? "Egg" : stage.name) : "???")
                    .font(NanoFont.aldrich(9))
                    .foregroundStyle(state.isRevealed ? NanoTheme.text : NanoTheme.mutedText)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.isRevealed ? stage.name : "Undiscovered")
        .accessibilityAddTraits(.isButton)
    }
}

private struct DexFamilyRow: View {
    let family: CreatureFamily
    let isComplete: Bool
    let state: (CreatureStage) -> DexEntryState
    let number: (CreatureStage) -> Int?
    let onSelect: (CreatureStage) -> Void

    private static let gold = Color(red: 1.0, green: 0.78, blue: 0.3)

    private var forms: [CreatureStage] { family.stages.filter { !$0.isEgg } }
    private var displayName: String {
        family.name.hasSuffix(" Line") ? String(family.name.dropLast(5)) : family.name
    }
    private var tint: Color { NanoCreatureType.color(for: forms.first ?? family.stages[0]) }
    private var foundCount: Int { forms.filter { state($0).isRevealed }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(displayName.uppercased())
                    .font(NanoFont.aldrich(12)).tracking(1)
                    .foregroundStyle(NanoTheme.text)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                if isComplete {
                    Label("COMPLETE", systemImage: "checkmark.seal.fill")
                        .font(NanoFont.aldrich(8)).tracking(0.8)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8).frame(height: 20)
                        .background(Capsule().fill(Self.gold))
                } else {
                    Text("\(foundCount)/\(forms.count)")
                        .font(NanoFont.spaceMono(11, bold: true))
                        .foregroundStyle(NanoTheme.secondaryText)
                }
            }

            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(family.stages.enumerated()), id: \.element.id) { index, stage in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(NanoTheme.mutedText)
                            .frame(width: 10)
                            .padding(.top, 28)
                    }
                    Button { onSelect(stage) } label: {
                        DexSlot(stage: stage, state: state(stage), tint: tint)
                    }
                    .buttonStyle(DexPressStyle())
                    .frame(maxWidth: 70)
                }
                Spacer(minLength: 0)
            }
        }
        .statsPanel(tint: tint, glow: 0.14, padding: 14)
        .overlay {
            if isComplete {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Self.gold.opacity(0.55), lineWidth: 1.5)
            }
        }
    }
}

private struct DexGridTile: View {
    let stage: CreatureStage
    let number: Int
    let state: DexEntryState

    private var tint: Color { NanoCreatureType.color(for: stage) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                DexSlot(stage: stage, state: state, tint: tint, showsCaption: false)
                Text(String(format: "#%03d", number))
                    .font(NanoFont.spaceMono(9, bold: true))
                    .foregroundStyle(state.isRevealed ? tint : NanoTheme.mutedText)
                    .padding(8)
            }
            Text(state.isRevealed ? stage.name : "???")
                .font(NanoFont.aldrich(11))
                .foregroundStyle(state.isRevealed ? NanoTheme.text : NanoTheme.mutedText)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.isRevealed ? "\(stage.name), number \(number)" : "Undiscovered, number \(number)")
    }
}

private struct DexMysteryTile: View {
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NanoTheme.ink.opacity(0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(NanoTheme.ink.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                Image(systemName: "questionmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(NanoTheme.mutedText)
            }
            .aspectRatio(1, contentMode: .fit)
            Text("???")
                .font(NanoFont.aldrich(9))
                .foregroundStyle(NanoTheme.mutedText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Undiscovered family")
    }
}

private struct DexEmptyFilter: View {
    let message: String
    var body: some View {
        Text(message)
            .font(NanoFont.spaceMono(12))
            .foregroundStyle(NanoTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }
}

private struct DexTypePill: View {
    let type: String

    var body: some View {
        let tint = NanoCreatureType.color(type)
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(type.uppercased())
                .font(NanoFont.aldrich(9)).tracking(0.8)
                .foregroundStyle(NanoTheme.text)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(tint.opacity(0.2)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 1))
    }
}

// MARK: - Detail

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
    /// Height of everything below the creature, so the hero can take only what's left.
    @State private var infoHeight: CGFloat = 0

    init(
        stage: CreatureStage,
        isLocked: Bool,
        unlockedEntries: [CreatureStage] = []
    ) {
        self.isLocked = isLocked
        self.unlockedEntries = unlockedEntries
        _selectedStage = State(initialValue: stage)
    }

    private var stage: CreatureStage { selectedStage }

    private var family: CreatureFamily? { store.family(of: selectedStage) }

    private var navigableStages: [CreatureStage] {
        guard !isLocked else { return [stage] }
        // Eggs are family stages but not grid entries; include them so browsing
        // within a line never collapses to a single page.
        let family = unlockedFamilyStages(for: stage)
        guard !unlockedEntries.isEmpty else { return family.isEmpty ? [stage] : family }
        let availableIDs = Set((unlockedEntries + family).map(\.id))
        return store.catalog.families.flatMap(\.stages)
            .filter { availableIDs.contains($0.id) }
    }

    private func unlockedFamilyStages(for stage: CreatureStage) -> [CreatureStage] {
        guard !isLocked else { return [] }
        return store.family(of: stage)?
            .stages
            .filter { store.isDiscovered($0) || store.isCurrent($0) }
            .sorted { $0.stage < $1.stage }
            ?? []
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LinearGradient(colors: [tint.opacity(isLocked ? 0.12 : 0.38), tint.opacity(0.06), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.35), value: selectedStage.id)
            LabGridBackground().ignoresSafeArea().opacity(0.6)

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
            withAnimation(.linear(duration: 1.4)) {
                scanProgress = 1
            }
            try? await Task.sleep(for: .milliseconds(1_400))
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

    private var tint: Color { NanoCreatureType.color(for: selectedStage) }

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

    private func discoveryDate(for entry: CreatureStage) -> Date? {
        store.discoveryEvents
            .filter { $0.familyID == entry.familyID && $0.stage == entry.stage && $0.kind != .eggAcquired }
            .map(\.timestamp).min()
            ?? store.discoveryEvents
                .filter { $0.familyID == entry.familyID && $0.stage == entry.stage }
                .map(\.timestamp).min()
    }

    private func stepsToReach(_ entry: CreatureStage) -> Int? {
        guard entry.stage > 0,
              let index = store.catalog.families.firstIndex(where: { $0.id == entry.familyID }) else { return nil }
        return CreatureProgressionRules.steps(familyIndex: index, stage: entry.stage - 1)
    }

    /// The creature shrinks (never below a comfortable size) so the whole entry,
    /// notes included, fits on screen without scrolling.
    private func heroHeight(available: CGFloat) -> CGFloat {
        let chrome: CGFloat = 44 + Self.spacing * 2 + Self.padding * 2
        return min(290, max(150, available - chrome - infoHeight))
    }

    private static let spacing: CGFloat = 12
    private static let padding: CGFloat = 16

    private func detailPage(for entry: CreatureStage) -> some View {
        let forms = family?.stages.filter { !$0.isEgg } ?? []
        return GeometryReader { geometry in
        ScrollView {
            VStack(spacing: Self.spacing) {
                HStack {
                    if let number = store.dexNumber(of: entry) {
                        Text(String(format: "#%03d", number))
                            .font(NanoFont.spaceMono(13, bold: true))
                            .foregroundStyle(isLocked ? NanoTheme.mutedText : tint)
                    } else {
                        Text(entry.isEgg ? "EGG" : "ENTRY")
                            .font(NanoFont.spaceMono(13, bold: true))
                            .foregroundStyle(tint)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(NanoTheme.text)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(NanoTheme.ink.opacity(0.1)).frame(width: 36, height: 36))
                    }
                    .accessibilityLabel("Close specimen profile")
                }

                CreatureScannerView(
                    stage: entry,
                    isLocked: isLocked,
                    tint: tint,
                    progress: entry.id == scanningStageID ? scanProgress : 0,
                    scanCompleted: entry.id == scanningStageID && scanCompleted
                )
                .frame(height: heroHeight(available: geometry.size.height))

                VStack(spacing: Self.spacing) {
                VStack(spacing: 8) {
                    Text(isLocked ? "???" : entry.name)
                        .font(NanoFont.aldrich(32))
                        .foregroundStyle(NanoTheme.text)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if !isLocked {
                        HStack(spacing: 6) {
                            ForEach(entry.types, id: \.self) { DexTypePill(type: $0) }
                        }
                    }
                }

                if isLocked {
                    lockedHint(for: entry)
                } else {
                    HStack(spacing: 8) {
                        statTile("STAGE", entry.isEgg ? "Egg" : "\(entry.stage) of \(forms.count)")
                        statTile("FOUND", discoveryDate(for: entry)?
                            .formatted(.dateTime.month(.abbreviated).day()) ?? "—")
                        statTile("STEPS", stepsToReach(entry)?.formatted(.number.notation(.compactName)) ?? "—")
                    }
                }

                if let family {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("EVOLUTIONS")
                                .font(NanoFont.aldrich(10)).tracking(1.4)
                                .foregroundStyle(NanoTheme.secondaryText)
                            Spacer()
                            if !isLocked, entry.stage > 0 {
                                Button {
                                    replayEvent = CreatureDiscoveryEvent(
                                        stage: entry,
                                        kind: entry.stage == 1 ? .hatch : .evolution
                                    )
                                } label: {
                                    Label(entry.stage == 1 ? "REPLAY HATCH" : "REPLAY EVOLUTION",
                                          systemImage: "play.fill")
                                        .font(NanoFont.aldrich(9)).tracking(0.6)
                                        .foregroundStyle(NanoTheme.onAccent)
                                        .padding(.horizontal, 10).frame(height: 28)
                                        .background(Capsule().fill(tint))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(entry.stage == 1 ? "Replay hatch" : "Replay evolution")
                            }
                        }
                        HStack(alignment: .top, spacing: 4) {
                            ForEach(Array(family.stages.enumerated()), id: \.element.id) { index, member in
                                if index > 0 {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(NanoTheme.mutedText)
                                        .frame(width: 10)
                                        .padding(.top, 28)
                                }
                                let state = store.dexState(of: member, in: family)
                                Button {
                                    if !isLocked, state.isRevealed { selectStage(member) }
                                } label: {
                                    DexSlot(stage: member, state: isLocked && member.id == entry.id ? .silhouette : state,
                                            tint: tint)
                                        .overlay(alignment: .bottom) {
                                            if member.id == entry.id {
                                                Capsule().fill(tint).frame(width: 18, height: 3).offset(y: 6)
                                            }
                                        }
                                }
                                .buttonStyle(DexPressStyle())
                                .frame(maxWidth: 58)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .statsPanel(tint: tint, glow: 0.1, padding: 14)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("RESEARCH NOTES")
                        .font(NanoFont.aldrich(10)).tracking(1.4)
                        .foregroundStyle(NanoTheme.secondaryText)
                    Text(isLocked
                         ? "This entry is encrypted. Keep walking and evolving creatures to reveal the specimen profile."
                         : entry.description)
                        .font(NanoFont.aldrich(12))
                        .foregroundStyle(isLocked ? NanoTheme.secondaryText : NanoTheme.text)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .statsPanel(tint: tint, glow: 0.06, padding: 14)
                }
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { infoHeight = $0 }
            }
            .padding(Self.padding)
        }
        .scrollIndicators(.hidden)
        // Only scrolls when the entry truly can't fit (e.g. accessibility text sizes).
        .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(NanoFont.aldrich(16))
                .foregroundStyle(NanoTheme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(NanoFont.aldrich(8)).tracking(1.2)
                .foregroundStyle(NanoTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(NanoTheme.ink.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    private func lockedHint(for entry: CreatureStage) -> some View {
        let previous = family?.stages.filter { $0.stage < entry.stage }.max { $0.stage < $1.stage }
        let hasPrevious = previous.map { store.isDiscovered($0) || store.isCurrent($0) } ?? false
        let hint: String = if let previous, hasPrevious {
            previous.isEgg ? "Hatch the \(previous.name) to reveal this form."
                : "Evolve \(previous.name) to reveal this form."
        } else {
            "Find this family's egg to begin uncovering it."
        }
        return HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(NanoTheme.secondaryText)
            Text(hint)
                .font(NanoFont.spaceMono(12))
                .foregroundStyle(NanoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(NanoTheme.ink.opacity(0.05)))
    }
}

/// The hero: a scan line reveals the specimen, then it comes alive.
private struct CreatureScannerView: View {
    let stage: CreatureStage
    let isLocked: Bool
    let tint: Color
    let progress: CGFloat
    let scanCompleted: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(isLocked ? 0.12 : 0.4), .clear],
                                         center: .center, startRadius: 10, endRadius: proxy.size.height * 0.55))
                Ellipse()
                    .fill(NanoTheme.shadow.opacity(0.35))
                    .frame(width: proxy.size.width * 0.42, height: 16)
                    .blur(radius: 8)
                    .offset(y: proxy.size.height * 0.4)

                if isLocked {
                    DexSilhouette(stage: stage, opacity: 0.16)
                        .padding(28)
                } else if scanCompleted {
                    AnimatedCreatureArtworkView(stage: stage)
                        .padding(18)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    DexSilhouette(stage: stage, opacity: 0.18)
                        .padding(18)
                    CreatureArtworkView(stage: stage)
                        .padding(18)
                        .mask(alignment: .top) {
                            VStack(spacing: 0) {
                                Rectangle().frame(height: proxy.size.height * progress)
                                Spacer(minLength: 0)
                            }
                        }
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, tint, .white, tint, .clear],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * 0.8, height: 2)
                        .shadow(color: tint, radius: 10)
                        .offset(y: -proxy.size.height / 2 + proxy.size.height * progress)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLocked ? "Undiscovered specimen" : stage.name)
    }
}
