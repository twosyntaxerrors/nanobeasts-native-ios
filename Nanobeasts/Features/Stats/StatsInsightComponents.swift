import SwiftUI
import UIKit

struct StatsBadge: Identifiable, Hashable {
    let id: String
    let symbol: String
    let title: String
    let description: String
    let tint: Color
    let unlocked: Bool
    let completedAt: Date?
}

struct StatsBadgeSection: Identifiable {
    let id: String
    let title: String
    let badges: [StatsBadge]
}

enum StatsBadgeCatalog {
    static func make(
        records: [DailyStepRecord],
        dailyGoal: Int,
        discoveredStages: [CreatureStage]
    ) -> [StatsBadgeSection] {
        let ordered = records.sorted { $0.day < $1.day }
        let totalSteps = ordered.reduce(0) { $0 + max($1.steps, 0) }
        let distanceKilometers = Double(totalSteps) * 0.000762
        let activeDays = ordered.filter { $0.steps > 0 }
        let goalDays = ordered.filter { $0.steps >= dailyGoal }
        let maximumSteps = ordered.map(\.steps).max() ?? 0
        let longestStreak = longestActiveStreak(in: ordered)
        let discoveredCreatures = discoveredStages.filter { !$0.isEgg }
        let speciesCount = Set(discoveredCreatures.map(\.familyID)).count
        let evolvedSpeciesCount = Set(
            discoveredCreatures.filter { $0.stage >= 2 }.map(\.familyID)
        ).count
        let finalSpeciesCount = Set(
            discoveredCreatures.filter { $0.stage >= 3 }.map(\.familyID)
        ).count

        let distanceTargets: [(Double, String)] = [
            (1, "First Steps"), (5, "5KM Walked"), (10, "10KM Walked"),
            (15, "15KM Hiker"), (25, "25KM Explorer"), (50, "50KM Expedition"),
            (75, "75KM Trekker"), (100, "100KM Journey"),
            (150, "150KM Adventurer"), (200, "200KM Voyager"),
            (300, "300KM Wanderer"), (350, "350KM Wayfarer"),
            (400, "400KM Trailblazer"), (450, "450KM Ranger"),
            (500, "500KM Pathfinder"), (750, "750KM Pilgrim"),
            (1_000, "The Proclaimer")
        ]
        var distanceBadges = distanceTargets.map { target, title in
            badge(
                id: "distance-\(Int(target))",
                symbol: target >= 100 ? "figure.hiking" : "figure.walk",
                title: title,
                description: "Walk a total of \(Int(target)) kilometers",
                tint: NanoTheme.purple,
                unlocked: distanceKilometers >= target,
                completedAt: cumulativeCompletionDate(
                    records: ordered,
                    targetSteps: Int((target / 0.000762).rounded(.up))
                )
            )
        }
        distanceBadges.append(
            badge(
                id: "distance-sprint",
                symbol: "figure.run",
                title: "Sprint Master",
                description: "Walk 10 kilometers in a single day",
                tint: NanoTheme.purple,
                unlocked: maximumSteps >= 13_124,
                completedAt: ordered.first(where: { $0.steps >= 13_124 })?.day
            )
        )

        let collectionDefinitions: [
            (id: String, symbol: String, title: String, description: String, unlocked: Bool)
        ] = [
            ("collection-first", "sparkles", "First Hatch", "Hatch your first creature", speciesCount >= 1),
            ("collection-3", "circle.grid.3x3.fill", "Trio", "Hatch 3 creatures", speciesCount >= 3),
            ("collection-5", "pawprint.fill", "Handful", "Hatch 5 creatures", speciesCount >= 5),
            ("collection-10", "shippingbox.fill", "Breeder", "Hatch 10 creatures", speciesCount >= 10),
            ("collection-15", "bird.fill", "Nest Keeper", "Hatch 15 creatures", speciesCount >= 15),
            ("collection-25", "crown.fill", "Hatchery Master", "Hatch 25 creatures", speciesCount >= 25),
            ("species-3", "square.grid.2x2.fill", "Starter Set", "Collect 3 unique species", speciesCount >= 3),
            ("species-5", "square.grid.3x3.fill", "Growing Collection", "Collect 5 unique species", speciesCount >= 5),
            ("species-10", "books.vertical.fill", "Collector", "Collect 10 unique species", speciesCount >= 10),
            ("species-15", "archivebox.fill", "Avid Collector", "Collect 15 unique species", speciesCount >= 15),
            ("species-20", "tray.full.fill", "Field Archivist", "Collect 20 unique species", speciesCount >= 20),
            ("species-25", "medal.fill", "Silver Collector", "Collect 25 unique species", speciesCount >= 25),
            ("species-35", "map.fill", "Dex Cartographer", "Collect 35 unique species", speciesCount >= 35),
            ("species-50", "trophy.fill", "Gold Collector", "Collect 50 unique species", speciesCount >= 50),
            ("evolve-first", "arrow.triangle.2.circlepath", "First Evolution", "Evolve a creature to stage 2", evolvedSpeciesCount >= 1),
            ("evolve-3", "arrow.3.trianglepath", "Evolving", "Evolve 3 different species", evolvedSpeciesCount >= 3),
            ("evolve-5", "atom", "Evolution Specialist", "Evolve 5 different species", evolvedSpeciesCount >= 5),
            ("evolve-10", "flask.fill", "Evolution Researcher", "Evolve 10 different species", evolvedSpeciesCount >= 10),
            ("final-first", "point.3.connected.trianglepath.dotted", "Family Reunion", "Reach a creature's final stage", finalSpeciesCount >= 1),
            ("final-3", "point.3.filled.connected.trianglepath.dotted", "Lineage Scholar", "Complete 3 evolution families", finalSpeciesCount >= 3)
        ]
        let collectionBadges = collectionDefinitions.map { definition in
            badge(
                id: definition.id,
                symbol: definition.symbol,
                title: definition.title,
                description: definition.description,
                tint: NanoTheme.teal,
                unlocked: definition.unlocked,
                completedAt: definition.unlocked ? activeDays.last?.day : nil
            )
        }

        let streakTargets = [3, 5, 7, 10, 14, 21, 30, 45, 60, 90, 120, 180]
        var consistencyBadges = streakTargets.map { target in
            badge(
                id: "streak-\(target)",
                symbol: target >= 30 ? "flame.circle.fill" : "flame.fill",
                title: "\(target) Day Streak",
                description: "Walk every day for \(target) days",
                tint: NanoTheme.orange,
                unlocked: longestStreak >= target,
                completedAt: streakCompletionDate(records: ordered, target: target)
            )
        }
        let weekendDate = weekendWarriorDate(records: ordered, dailyGoal: dailyGoal)
        consistencyBadges.append(
            badge(
                id: "weekend-warrior",
                symbol: "sun.max.fill",
                title: "Weekend Warrior",
                description: "Reach your goal on Saturday and Sunday",
                tint: NanoTheme.orange,
                unlocked: weekendDate != nil,
                completedAt: weekendDate
            )
        )
        consistencyBadges.append(
            badge(
                id: "monthly-marathon",
                symbol: "calendar.badge.checkmark",
                title: "Monthly Marathon",
                description: "Reach your goal 25 times",
                tint: NanoTheme.orange,
                unlocked: goalDays.count >= 25,
                completedAt: goalDays.dropFirst(24).first?.day
            )
        )

        let goalTargets: [(Int, String)] = [
            (1, "Goal Getter"), (3, "Triple Threat"), (7, "Week Winner"),
            (15, "Consistent Walker"), (30, "Monthly Pace"), (50, "Goal Veteran")
        ]
        var intensityBadges = goalTargets.map { count, title in
            badge(
                id: "goal-\(count)",
                symbol: "flag.checkered",
                title: title,
                description: "Reach your daily goal \(count) time\(count == 1 ? "" : "s")",
                tint: NanoTheme.green,
                unlocked: goalDays.count >= count,
                completedAt: goalDays.dropFirst(max(count - 1, 0)).first?.day
            )
        }
        let intensityDefinitions: [
            (id: String, symbol: String, title: String, description: String, threshold: Int)
        ] = [
            ("double-goal", "bolt.fill", "Double Down", "Double your daily goal in one day", dailyGoal * 2),
            ("triple-goal", "bolt.circle.fill", "Triple Threat Day", "Triple your daily goal in one day", dailyGoal * 3),
            ("steps-5k", "figure.walk", "5K Steps", "Walk 5,000 steps in one day", 5_000),
            ("steps-10k", "figure.walk.motion", "10K Steps", "Walk 10,000 steps in one day", 10_000),
            ("steps-15k", "figure.run", "15K Steps", "Walk 15,000 steps in one day", 15_000),
            ("steps-20k", "figure.hiking", "20K Steps", "Walk 20,000 steps in one day", 20_000)
        ]
        intensityBadges.append(contentsOf: intensityDefinitions.map { definition in
            badge(
                id: definition.id,
                symbol: definition.symbol,
                title: definition.title,
                description: definition.description,
                tint: NanoTheme.green,
                unlocked: maximumSteps >= definition.threshold,
                completedAt: ordered.first(where: { $0.steps >= definition.threshold })?.day
            )
        })

        return [
            StatsBadgeSection(id: "distance", title: "Distance", badges: distanceBadges),
            StatsBadgeSection(id: "collection", title: "Collection", badges: collectionBadges),
            StatsBadgeSection(id: "consistency", title: "Consistency", badges: consistencyBadges),
            StatsBadgeSection(id: "intensity", title: "Intensity", badges: intensityBadges)
        ]
    }

    private static func badge(
        id: String,
        symbol: String,
        title: String,
        description: String,
        tint: Color,
        unlocked: Bool,
        completedAt: Date?
    ) -> StatsBadge {
        StatsBadge(
            id: id,
            symbol: symbol,
            title: title,
            description: description,
            tint: tint,
            unlocked: unlocked,
            completedAt: completedAt
        )
    }

    private static func longestActiveStreak(in records: [DailyStepRecord]) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        var longest = 0
        var current = 0
        var previous: Date?
        for record in records where record.steps > 0 {
            let day = calendar.startOfDay(for: record.day)
            if
                let previous,
                calendar.dateComponents([.day], from: previous, to: day).day == 1
            {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = day
        }
        return longest
    }

    private static func cumulativeCompletionDate(
        records: [DailyStepRecord],
        targetSteps: Int
    ) -> Date? {
        var total = 0
        for record in records {
            total += record.steps
            if total >= targetSteps { return record.day }
        }
        return nil
    }

    private static func streakCompletionDate(
        records: [DailyStepRecord],
        target: Int
    ) -> Date? {
        let calendar = Calendar.autoupdatingCurrent
        var current = 0
        var previous: Date?
        for record in records {
            guard record.steps > 0 else {
                current = 0
                previous = nil
                continue
            }
            let day = calendar.startOfDay(for: record.day)
            if
                let previous,
                calendar.dateComponents([.day], from: previous, to: day).day == 1
            {
                current += 1
            } else {
                current = 1
            }
            if current >= target { return day }
            previous = day
        }
        return nil
    }

    private static func weekendWarriorDate(
        records: [DailyStepRecord],
        dailyGoal: Int
    ) -> Date? {
        let calendar = Calendar.autoupdatingCurrent
        let lookup = Dictionary(
            records.map { (calendar.startOfDay(for: $0.day), $0.steps) },
            uniquingKeysWith: { _, latest in latest }
        )
        for record in records {
            let day = calendar.startOfDay(for: record.day)
            guard calendar.component(.weekday, from: day) == 7, record.steps >= dailyGoal else {
                continue
            }
            guard
                let sunday = calendar.date(byAdding: .day, value: 1, to: day),
                (lookup[sunday] ?? 0) >= dailyGoal
            else {
                continue
            }
            return sunday
        }
        return nil
    }
}

struct StatsInsightsCard: View {
    let records: [DailyStepRecord]
    let dailyGoal: Int

    @State private var mode: StatsInsightsMode = .carousel
    @State private var page = 0

    private var snapshot: StatsInsightSnapshot {
        StatsInsightSnapshot(records: records)
    }

    private var panels: [StatsInsightPanelModel] {
        [
            StatsInsightPanelModel(
                id: "average",
                symbol: "chart.bar.fill",
                label: "AVG / ACTIVE DAY",
                value: snapshot.average.formatted(),
                unit: "STEPS",
                caption: "\(snapshot.activeDays) DAYS TRACKED",
                tint: NanoTheme.teal,
                signals: Array(records.suffix(14)).map(\.steps)
            ),
            StatsInsightPanelModel(
                id: "best",
                symbol: "trophy.fill",
                label: "BEST DAY",
                value: snapshot.bestDay?.steps.formatted() ?? "0",
                unit: "STEPS",
                caption: snapshot.bestDay?.day.formatted(.dateTime.month(.abbreviated).day()) ?? "NO DATA",
                tint: Color(red: 0.22, green: 0.74, blue: 0.97),
                signals: Array(records.suffix(14)).map(\.steps)
            ),
            StatsInsightPanelModel(
                id: "streak",
                symbol: "flame.fill",
                label: "LONGEST STREAK",
                value: snapshot.longestStreak.formatted(),
                unit: "ACTIVE DAYS",
                caption: "STREAK RECORD",
                tint: Color(red: 1, green: 0.67, blue: 0.09),
                signals: Array(repeating: 1, count: min(snapshot.longestStreak, 14))
            ),
            StatsInsightPanelModel(
                id: "month",
                symbol: "calendar",
                label: "ACTIVE THIS MONTH",
                value: snapshot.currentMonthActiveDays.formatted(),
                unit: "DAYS",
                caption: Date().formatted(.dateTime.month(.wide)).uppercased(),
                tint: Color(red: 0.21, green: 0.90, blue: 0.44),
                signals: snapshot.currentMonthSignals
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            insightsHeader

            Group {
                if mode == .carousel {
                    carousel
                } else {
                    grid
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(NanoTheme.teal.opacity(0.025))
                .stroke(NanoTheme.teal.opacity(0.34), lineWidth: 1)
        )
        .animation(.snappy(duration: 0.28), value: mode)
    }

    private var insightsHeader: some View {
        HStack {
            Text("INSIGHTS")
                .font(NanoFont.aldrich(18))
                .tracking(1.35)
                .foregroundStyle(NanoTheme.teal)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Rectangle()
                .fill(NanoTheme.teal.opacity(0.6))
                .frame(height: 1)
            Button {
                mode = mode == .carousel ? .grid : .carousel
            } label: {
                Label(
                    mode == .carousel ? "2X2" : "SWIPE",
                    systemImage: mode == .carousel
                        ? "square.grid.2x2"
                        : "arrow.left.arrow.right"
                )
                .font(NanoFont.aldrich(9))
                .foregroundStyle(NanoTheme.teal)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    Capsule()
                        .fill(NanoTheme.teal.opacity(0.08))
                        .stroke(NanoTheme.teal.opacity(0.45), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                mode == .carousel
                    ? "Show all insights in a two by two grid"
                    : "Show insights as swipeable cards"
            )
        }
    }

    private var carousel: some View {
        VStack(spacing: 12) {
            TabView(selection: $page) {
                ForEach(Array(panels.enumerated()), id: \.element.id) { index, panel in
                    StatsInsightPanel(panel: panel, dailyGoal: dailyGoal)
                        .padding(.horizontal, 1)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 218)

            HStack(spacing: 7) {
                ForEach(Array(panels.enumerated()), id: \.element.id) { index, panel in
                    Capsule()
                        .fill(panel.tint.opacity(index == page ? 1 : 0.28))
                        .frame(width: index == page ? 22 : 7, height: 7)
                }
            }
            .animation(.snappy, value: page)
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(panels) { panel in
                StatsInsightPanel(panel: panel, dailyGoal: dailyGoal, compact: true)
            }
        }
    }
}

private enum StatsInsightsMode {
    case carousel
    case grid
}

private struct StatsInsightSnapshot {
    let activeDays: Int
    let average: Int
    let bestDay: DailyStepRecord?
    let longestStreak: Int
    let currentMonthActiveDays: Int
    let currentMonthSignals: [Int]

    init(records: [DailyStepRecord]) {
        let calendar = Calendar.autoupdatingCurrent
        let active = records.filter { $0.steps > 0 }.sorted { $0.day < $1.day }
        activeDays = active.count
        average = active.isEmpty ? 0 : active.reduce(0) { $0 + $1.steps } / active.count
        bestDay = active.max { $0.steps < $1.steps }

        var longest = 0
        var current = 0
        var previous: Date?
        for record in active {
            let day = calendar.startOfDay(for: record.day)
            if
                let previous,
                calendar.dateComponents([.day], from: previous, to: day).day == 1
            {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = day
        }
        longestStreak = longest

        let now = Date()
        let monthRecords = records.filter {
            calendar.isDate($0.day, equalTo: now, toGranularity: .month)
        }
        currentMonthActiveDays = monthRecords.filter { $0.steps > 0 }.count
        currentMonthSignals = monthRecords.map(\.steps)
    }
}

private struct StatsInsightPanelModel: Identifiable {
    let id: String
    let symbol: String
    let label: String
    let value: String
    let unit: String
    let caption: String
    let tint: Color
    let signals: [Int]
}

private struct StatsInsightPanel: View {
    let panel: StatsInsightPanelModel
    let dailyGoal: Int
    var compact = false

    private var maximum: Int {
        max(panel.signals.max() ?? 1, dailyGoal, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 12) {
            HStack {
                Image(systemName: panel.symbol)
                Text(panel.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 2)
                Image(systemName: "info.circle")
            }
            .font(NanoFont.aldrich(compact ? 7 : 9))
            .tracking(0.8)
            .foregroundStyle(panel.tint)

            Text(panel.value)
                .font(NanoFont.aldrich(compact ? 25 : 39))
                .foregroundStyle(panel.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(panel.unit)
                .font(NanoFont.aldrich(compact ? 7 : 10))
                .tracking(1.2)
                .foregroundStyle(panel.tint)

            HStack(alignment: .bottom, spacing: compact ? 3 : 5) {
                ForEach(Array(panel.signals.suffix(compact ? 8 : 14).enumerated()), id: \.offset) {
                    _, value in
                    Capsule()
                        .fill(
                            value > 0
                                ? panel.tint.opacity(0.45 + min(Double(value) / Double(maximum), 1) * 0.55)
                                : panel.tint.opacity(0.12)
                        )
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 4,
                            maxHeight: max(
                                4,
                                (compact ? 30 : 54) * min(
                                    max(Double(value) / Double(maximum), value > 0 ? 0.08 : 0),
                                    1
                                )
                            )
                        )
                }
            }
            .frame(maxHeight: compact ? 30 : 54, alignment: .bottom)

            Text(panel.caption)
                .font(NanoFont.aldrich(compact ? 7 : 9))
                .tracking(1)
                .foregroundStyle(panel.tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: compact ? 166 : 186, alignment: .top)
        .nanoHUDCard(
            tint: panel.tint,
            radius: compact ? 16 : 18,
            padding: compact ? 12 : 16,
            illuminated: true
        )
    }
}

struct RecentAchievementsRow: View {
    let sections: [StatsBadgeSection]

    @State private var destination: BadgeDestination?

    private var unlocked: [StatsBadge] {
        sections.flatMap(\.badges).filter(\.unlocked).reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT ACHIEVEMENTS")
                    .font(NanoFont.aldrich(14))
                    .tracking(1.1)
                Spacer()
                Button {
                    destination = BadgeDestination(highlightBadgeID: nil)
                } label: {
                    Label("VIEW ALL", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(NanoFont.aldrich(9))
                        .foregroundStyle(NanoTheme.teal)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if unlocked.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(NanoTheme.teal)
                            Text("Your first achievement will appear here.")
                                .font(NanoFont.aldrich(9))
                                .foregroundStyle(NanoTheme.secondaryText)
                        }
                        .frame(width: 250, height: 120)
                        .nanoHUDCard()
                    } else {
                        ForEach(Array(unlocked.prefix(4))) { badge in
                            Button {
                                destination = BadgeDestination(highlightBadgeID: badge.id)
                            } label: {
                                AchievementCard(badge: badge)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .sheet(item: $destination) { destination in
            BadgeCollectionView(
                sections: sections,
                highlightBadgeID: destination.highlightBadgeID
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct BadgeDestination: Identifiable {
    let id = UUID()
    let highlightBadgeID: String?
}

private struct AchievementCard: View {
    let badge: StatsBadge

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: badge.symbol)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(badge.tint)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(badge.tint.opacity(0.08))
                        .stroke(badge.tint, lineWidth: 2)
                )
            Text(badge.title)
                .font(NanoFont.aldrich(10))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(badge.completedAt?.formatted(.dateTime.month(.abbreviated).day()) ?? "UNLOCKED")
                .font(NanoFont.aldrich(7))
                .foregroundStyle(badge.tint)
                .lineLimit(1)
        }
        .frame(width: 132, height: 154)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(NanoTheme.surface)
                .stroke(badge.tint.opacity(0.48), lineWidth: 1)
        )
    }
}

struct BadgeCollectionView: View {
    let sections: [StatsBadgeSection]
    let highlightBadgeID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedBadge: StatsBadge?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("BADGE COLLECTION")
                                    .font(NanoFont.aldrich(22))
                                Text("\(unlockedCount) / \(totalCount) UNLOCKED")
                                    .font(NanoFont.aldrich(10))
                                    .tracking(1)
                                    .foregroundStyle(NanoTheme.teal)
                            }
                            Spacer()
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                        }

                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 14) {
                                Text(section.title.uppercased())
                                    .font(NanoFont.aldrich(13))
                                    .tracking(1.2)
                                    .foregroundStyle(NanoTheme.secondaryText)

                                LazyVGrid(columns: columns, spacing: 18) {
                                    ForEach(section.badges) { badge in
                                        Button {
                                            selectedBadge = badge
                                        } label: {
                                            BadgeGridCell(
                                                badge: badge,
                                                highlighted: badge.id == highlightBadgeID
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .id(badge.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(18)
                }
                .task {
                    guard let highlightBadgeID else { return }
                    guard let highlightedBadge = sections
                        .lazy
                        .flatMap(\.badges)
                        .first(where: { $0.id == highlightBadgeID })
                    else {
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(.snappy) {
                        proxy.scrollTo(highlightBadgeID, anchor: .center)
                    }
                    try? await Task.sleep(for: .milliseconds(180))
                    guard !Task.isCancelled else { return }
                    selectedBadge = highlightedBadge
                }
            }
        }
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailView(badge: badge)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var unlockedCount: Int {
        sections.flatMap(\.badges).filter(\.unlocked).count
    }

    private var totalCount: Int {
        sections.flatMap(\.badges).count
    }
}

private struct BadgeGridCell: View {
    let badge: StatsBadge
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: badge.unlocked ? badge.symbol : "lock.fill")
                .font(.system(size: badge.unlocked ? 26 : 20, weight: .semibold))
                .foregroundStyle(badge.unlocked ? badge.tint : NanoTheme.mutedText)
                .frame(width: 70, height: 70)
                .background(
                    Circle()
                        .fill(NanoTheme.surface)
                        .stroke(
                            badge.unlocked ? badge.tint : NanoTheme.mutedText,
                            style: StrokeStyle(
                                lineWidth: highlighted ? 3 : 2,
                                dash: badge.unlocked ? [] : [5, 4]
                            )
                        )
                        .shadow(
                            color: badge.unlocked ? badge.tint.opacity(0.30) : .clear,
                            radius: highlighted ? 12 : 5
                        )
                )
            Text(badge.title)
                .font(NanoFont.aldrich(8))
                .foregroundStyle(badge.unlocked ? .white : NanoTheme.mutedText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 26, alignment: .top)
            Text(
                badge.unlocked
                    ? badge.completedAt?.formatted(.dateTime.month(.abbreviated).day()) ?? "UNLOCKED"
                    : "LOCKED"
            )
            .font(NanoFont.aldrich(7))
            .foregroundStyle(badge.unlocked ? badge.tint : NanoTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(badge.title), \(badge.unlocked ? "unlocked" : "locked")")
    }
}

private struct BadgeDetailView: View {
    let badge: StatsBadge

    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            VStack(spacing: 22) {
                HStack {
                    Text("ACHIEVEMENT FILE")
                        .font(NanoFont.aldrich(11))
                        .tracking(1.4)
                        .foregroundStyle(badge.tint)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                }

                SpinningBadgeMedallion(
                    badge: badge,
                    appeared: appeared,
                    size: 126
                )

                VStack(spacing: 10) {
                    Text(badge.title)
                        .font(NanoFont.aldrich(23))
                        .multilineTextAlignment(.center)
                    Text(badge.description)
                        .font(NanoFont.aldrich(11))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    Text(
                        badge.unlocked
                            ? badge.completedAt?.formatted(.dateTime.month(.wide).day().year()) ?? "UNLOCKED"
                            : "LOCKED"
                    )
                    .font(NanoFont.aldrich(10))
                    .tracking(1.2)
                    .foregroundStyle(badge.unlocked ? badge.tint : NanoTheme.mutedText)
                }
            }
            .padding(24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.72)) {
                appeared = true
            }
        }
    }
}

struct BadgeAwardCelebrationView: View {
    let badge: StatsBadge
    let sections: [StatsBadgeSection]

    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false
    @State private var showsCollection = false

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [badge.tint.opacity(0.24), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 230
                    )
                )
                .frame(width: 460, height: 460)
                .scaleEffect(appeared ? 1 : 0.55)

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 7) {
                    Text("ACHIEVEMENT UNLOCKED")
                        .font(NanoFont.aldrich(11))
                        .tracking(2)
                        .foregroundStyle(badge.tint)
                    Text("FIELD MILESTONE")
                        .font(NanoFont.aldrich(9))
                        .tracking(1.5)
                        .foregroundStyle(NanoTheme.secondaryText)
                }

                SpinningBadgeMedallion(
                    badge: badge,
                    appeared: appeared,
                    size: 174
                )

                VStack(spacing: 10) {
                    Text(badge.title)
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(badge.description)
                        .font(NanoFont.aldrich(12))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .frame(maxWidth: 340)

                Spacer()

                VStack(spacing: 11) {
                    ShareLink(
                        item: "I just unlocked “\(badge.title)” in Nanobeasts — \(badge.description)."
                    ) {
                        Label("SHARE ACHIEVEMENT", systemImage: "square.and.arrow.up")
                            .font(NanoFont.aldrich(12))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(badge.tint)
                    .foregroundStyle(.black)

                    Button {
                        showsCollection = true
                    } label: {
                        Label("VIEW BADGE COLLECTION", systemImage: "square.grid.3x3.fill")
                            .font(NanoFont.aldrich(11))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.bordered)
                    .tint(badge.tint)

                    Button("CLOSE") {
                        dismiss()
                    }
                    .font(NanoFont.aldrich(10))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 1.0, dampingFraction: 0.68)) {
                appeared = true
            }
        }
        .sheet(isPresented: $showsCollection) {
            BadgeCollectionView(
                sections: sections,
                highlightBadgeID: badge.id
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct SpinningBadgeMedallion: View {
    let badge: StatsBadge
    let appeared: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: badge.unlocked ? badge.symbol : "lock.fill")
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(badge.unlocked ? badge.tint : NanoTheme.mutedText)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(NanoTheme.surface)
                    .stroke(
                        badge.unlocked ? badge.tint : NanoTheme.mutedText,
                        style: StrokeStyle(
                            lineWidth: max(3, size * 0.024),
                            dash: badge.unlocked ? [] : [7, 6]
                        )
                    )
            )
            .overlay {
                Circle()
                    .trim(from: 0.08, to: 0.42)
                    .stroke(Color.white.opacity(0.42), lineWidth: 2)
                    .padding(8)
                    .rotationEffect(.degrees(appeared ? 520 : 0))
            }
            .rotation3DEffect(
                .degrees(appeared && badge.unlocked ? 360 : 0),
                axis: (0, 1, 0),
                perspective: 0.62
            )
            .scaleEffect(appeared ? 1 : 0.58)
            .shadow(color: badge.tint.opacity(badge.unlocked ? 0.48 : 0), radius: 24)
    }
}
