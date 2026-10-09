import CryptoKit
import SwiftUI
import UIKit

struct StatsBadge: Identifiable, Hashable {
    let id: String
    let symbol: String
    let artworkURL: URL?
    let title: String
    let description: String
    let tint: Color
    let unlocked: Bool
    let completedAt: Date?

    static func recentUnlocked(in sections: [StatsBadgeSection]) -> [StatsBadge] {
        sections.flatMap(\.badges).filter(\.unlocked).sorted {
            let lhs = $0.completedAt ?? .distantPast
            let rhs = $1.completedAt ?? .distantPast
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }
    }
}

struct StatsBadgeSection: Identifiable {
    let id: String
    let title: String
    let badges: [StatsBadge]
}

actor BadgeArtworkImageCache {
    static let shared = BadgeArtworkImageCache()

    nonisolated static func key(_ url: URL, maxPixel: Int? = nil) -> String {
        maxPixel.map { "badge:\(url.absoluteString)@\($0)" } ?? "badge:\(url.absoluteString)"
    }

    private var processedData: [URL: Data] = [:]
    private var activeLoads: [URL: Task<Data, Error>] = [:]
    private let cacheDirectory: URL

    init() {
        cacheDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        .appending(path: "nanobeasts-badge-artwork-v2", directoryHint: .isDirectory)

        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    func data(for url: URL) async throws -> Data {
        if let cached = processedData[url] {
            return cached
        }

        let localURL = cachedURL(for: url)
        if let cached = try? Data(contentsOf: localURL, options: .mappedIfSafe),
           !cached.isEmpty {
            processedData[url] = cached
            return cached
        }

        if let activeLoad = activeLoads[url] {
            return try await activeLoad.value
        }

        let load = Task<Data, Error>(priority: .userInitiated) {
            let sourceData = try await R2ArtworkCache.shared.data(for: url)
            return await Task.detached(priority: .userInitiated) {
                UIImage(data: sourceData)?
                    .trimmingTransparentCanvas()
                    .pngData()
                    ?? sourceData
            }.value
        }
        activeLoads[url] = load

        do {
            let data = try await load.value
            processedData[url] = data
            activeLoads[url] = nil
            try? data.write(to: localURL, options: .atomic)
            return data
        } catch {
            activeLoads[url] = nil
            throw error
        }
    }

    func prefetch(urls: [URL], maxPixel: Int? = nil) async {
        let uniqueURLs = Array(Set(urls))
        await withTaskGroup(of: Void.self) { group in
            for url in uniqueURLs {
                group.addTask {
                    // Decode ahead too, so the badge draws on its first frame.
                    guard let data = try? await self.data(for: url) else { return }
                    let key = Self.key(url, maxPixel: maxPixel)
                    if let maxPixel {
                        _ = await NanoImageMemoryCache.shared.thumbnail(data, maxPixel: maxPixel, for: key)
                    } else {
                        _ = await NanoImageMemoryCache.shared.decode(data, for: key)
                    }
                }
            }
        }
    }

    private func cachedURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDirectory.appending(path: "\(digest).png")
    }
}

enum StatsBadgeCatalog {
    static func make(
        records: [DailyStepRecord],
        dailyGoal: Int,
        dailyGoalHistory: [DailyGoalRecord],
        discoveredStages: [CreatureStage],
        distanceUnit: DistanceUnitPreference,
        discoveryEvents: [CreatureDiscoveryEvent] = []
    ) -> [StatsBadgeSection] {
        let ordered = records.sorted { $0.day < $1.day }
        let goalTimeline = DailyGoalTimeline(
            history: dailyGoalHistory,
            fallbackGoal: dailyGoal
        )
        let totalSteps = ordered.reduce(0) { $0 + max($1.steps, 0) }
        let distanceKilometers = Double(totalSteps) * 0.000762
        let goalDays = ordered.filter {
            $0.steps >= goalTimeline.goal(on: $0.day)
        }
        let maximumSteps = ordered.map(\.steps).max() ?? 0
        let discoveredCreatures = discoveredStages.filter { !$0.isEgg }
        let speciesCount = Set(discoveredCreatures.map(\.familyID)).count
        let evolvedSpeciesCount = Set(
            discoveredCreatures.filter { $0.stage >= 2 }.map(\.familyID)
        ).count
        let finalSpeciesCount = Set(
            discoveredCreatures.filter { $0.stage >= 3 }.map(\.familyID)
        ).count

        let distanceTargets: [(kilometers: Double, descriptor: String)] = [
            (1, "First Steps"), (5, "Walked"), (10, "Walked"),
            (15, "Hiker"), (25, "Explorer"), (50, "Expedition"),
            (75, "Trekker"), (100, "Journey"),
            (150, "Adventurer"), (200, "Voyager"),
            (300, "Wanderer"), (350, "Wayfarer"),
            (400, "Trailblazer"), (450, "Ranger"),
            (500, "Pathfinder"), (750, "Pilgrim"),
            (1_000, "The Proclaimer")
        ]
        var distanceBadges = distanceTargets.map { target in
            let displayDistance = formattedDistance(
                kilometers: target.kilometers,
                unit: distanceUnit
            )
            let title =
                target.kilometers == 1 || target.descriptor == "The Proclaimer"
                    ? target.descriptor
                    : "\(displayDistance) \(distanceUnit.abbreviation) \(target.descriptor)"
            return badge(
                id: "distance-\(Int(target.kilometers))",
                symbol: target.kilometers >= 100 ? "figure.hiking" : "figure.walk",
                title: title,
                description:
                    "Walk a total of \(displayDistance) \(distanceUnit.pluralName)",
                tint: NanoTheme.purple,
                unlocked: distanceKilometers >= target.kilometers,
                completedAt: cumulativeCompletionDate(
                    records: ordered,
                    targetSteps: Int((target.kilometers / 0.000762).rounded(.up))
                )
            )
        }
        let sprintDistance = formattedDistance(kilometers: 10, unit: distanceUnit)
        distanceBadges.append(
            badge(
                id: "distance-sprint",
                symbol: "figure.run",
                title: "Sprint Master",
                description:
                    "Walk \(sprintDistance) \(distanceUnit.pluralName) in a single day",
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
                completedAt: definition.unlocked
                    ? collectionCompletionDate(badgeID: definition.id, events: discoveryEvents) : nil
            )
        }

        let streakTargets = [3, 5, 7, 10, 14, 21, 30, 45, 60, 90, 120, 180]
        var consistencyBadges = streakTargets.map { target in
            let completionDate = goalStreakCompletionDate(
                records: ordered,
                target: target,
                goalTimeline: goalTimeline
            )
            return badge(
                id: "streak-\(target)",
                symbol: target >= 30 ? "flame.circle.fill" : "flame.fill",
                title: "\(target) Day Streak",
                description: "Reach your daily goal for \(target) consecutive days",
                tint: NanoTheme.orange,
                unlocked: completionDate != nil,
                completedAt: completionDate
            )
        }
        let weekendDate = weekendWarriorDate(
            records: ordered,
            goalTimeline: goalTimeline
        )
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

        let sections = [
            StatsBadgeSection(id: "distance", title: "Distance", badges: distanceBadges),
            StatsBadgeSection(id: "collection", title: "Collection", badges: collectionBadges),
            StatsBadgeSection(id: "consistency", title: "Consistency", badges: consistencyBadges),
            StatsBadgeSection(id: "intensity", title: "Intensity", badges: intensityBadges)
        ]

        guard
            AppScreenshotScenario.active == .badges
                || AppScreenshotScenario.active == .collectionBadges
        else {
            return sections
        }
        return sections.map { section in
            StatsBadgeSection(
                id: section.id,
                title: section.title,
                badges: section.badges.map { badge in
                    StatsBadge(
                        id: badge.id,
                        symbol: badge.symbol,
                        artworkURL: badge.artworkURL,
                        title: badge.title,
                        description: badge.description,
                        tint: badge.tint,
                        unlocked: true,
                        completedAt: badge.completedAt ?? ordered.last?.day ?? Date()
                    )
                }
            )
        }
    }

    private static func collectionCompletionDate(
        badgeID: String, events: [CreatureDiscoveryEvent]
    ) -> Date? {
        let components = badgeID.split(separator: "-")
        guard let category = components.first, let milestone = components.last,
              let target = milestone == "first" ? 1 : Int(milestone) else { return nil }
        let minimumStage = category == "final" ? 3 : category == "evolve" ? 2 : 1
        var families = Set<String>()
        for event in events.sorted(by: { $0.timestamp < $1.timestamp })
        where (event.kind == .hatch || event.kind == .evolution) && event.stage >= minimumStage {
            if families.insert(event.familyID).inserted, families.count == target {
                return event.timestamp
            }
        }
        // Legacy discoveries without event history remain unlocked and undated.
        // Using today's activity would incorrectly promote them as new awards.
        return nil
    }

    private static func formattedDistance(
        kilometers: Double,
        unit: DistanceUnitPreference
    ) -> String {
        let value = unit.value(fromKilometers: kilometers)
        let isEffectivelyWhole = abs(value.rounded() - value) < 0.01
        return value.formatted(
            .number.precision(.fractionLength(isEffectivelyWhole ? 0 : 1))
        )
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
            artworkURL: R2BadgeManifest.url(for: id),
            title: title,
            description: description,
            tint: tint,
            unlocked: unlocked,
            completedAt: completedAt
        )
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

    private static func goalStreakCompletionDate(
        records: [DailyStepRecord],
        target: Int,
        goalTimeline: DailyGoalTimeline
    ) -> Date? {
        let calendar = Calendar.autoupdatingCurrent
        var current = 0
        var previous: Date?
        for record in records {
            let day = calendar.startOfDay(for: record.day)
            guard record.steps >= goalTimeline.goal(on: day) else {
                current = 0
                previous = day
                continue
            }
            if
                let previous,
                current > 0,
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
        goalTimeline: DailyGoalTimeline
    ) -> Date? {
        let calendar = Calendar.autoupdatingCurrent
        let lookup = Dictionary(
            records.map { (calendar.startOfDay(for: $0.day), $0.steps) },
            uniquingKeysWith: { _, latest in latest }
        )
        for record in records {
            let day = calendar.startOfDay(for: record.day)
            guard
                calendar.component(.weekday, from: day) == 7,
                record.steps >= goalTimeline.goal(on: day)
            else {
                continue
            }
            guard
                let sunday = calendar.date(byAdding: .day, value: 1, to: day),
                (lookup[sunday] ?? 0) >= goalTimeline.goal(on: sunday)
            else {
                continue
            }
            return sunday
        }
        return nil
    }

    private struct DailyGoalTimeline {
        private let fallbackGoal: Int
        private let entries: [(day: Date, goal: Int)]
        private let calendar = Calendar.autoupdatingCurrent

        init(history: [DailyGoalRecord], fallbackGoal: Int) {
            self.fallbackGoal = fallbackGoal
            let calendar = Calendar.autoupdatingCurrent
            let goalsByDay = Dictionary(
                history.map {
                    (calendar.startOfDay(for: $0.day), $0.goal)
                },
                uniquingKeysWith: { _, latest in latest }
            )
            entries = goalsByDay
                .map { (day: $0.key, goal: $0.value) }
                .sorted { $0.day < $1.day }
        }

        func goal(on day: Date) -> Int {
            let normalizedDay = calendar.startOfDay(for: day)
            return entries.last(where: { $0.day <= normalizedDay })?.goal
                ?? fallbackGoal
        }
    }
}

struct RecentAchievementsRow: View {
    let sections: [StatsBadgeSection]
    var sectionNumber = 7
    var unlockedCount = 0
    var totalCount = 0

    @State private var destination: BadgeDestination?

    private var unlocked: [StatsBadge] {
        StatsBadge.recentUnlocked(in: sections)
    }

    private var artworkPrefetchID: String {
        unlocked.map(\.id).joined(separator: "|")
    }

    private var unlockedArtworkURLs: [URL] {
        unlocked.compactMap(\.artworkURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatsSectionHeader(number: sectionNumber, title: "ACHIEVEMENTS") {
                Button {
                    destination = BadgeDestination(highlightBadgeID: nil)
                } label: {
                    HStack(spacing: 6) {
                        Text("\(unlockedCount)/\(totalCount)")
                            .foregroundStyle(NanoTheme.secondaryText)
                        Text("VIEW ALL")
                        Image(systemName: "chevron.right")
                    }
                    .font(NanoFont.aldrich(10))
                    .foregroundStyle(NanoTheme.teal)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View all achievements, \(unlockedCount) of \(totalCount) earned")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if unlocked.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(NanoTheme.teal)
                            Text("Earn badges for steps, streaks, and discoveries.\nTap View All to find your first goal.")
                                .font(NanoFont.aldrich(9))
                                .foregroundStyle(NanoTheme.secondaryText)
                                .multilineTextAlignment(.center)
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
        .task(id: artworkPrefetchID) {
            await BadgeArtworkImageCache.shared.prefetch(
                urls: unlockedArtworkURLs,
                maxPixel: AchievementCard.artworkMaxPixel
            )
        }
    }
}

private struct BadgeDestination: Identifiable {
    let id = UUID()
    let highlightBadgeID: String?
}

private struct BadgeArtworkView: View {
    let badge: StatsBadge
    let size: CGFloat
    /// Small badges pass a pixel size to get a downsampled, pre-decoded thumbnail.
    var maxPixel: Int? = nil
    var onReady: (() -> Void)? = nil

    @State private var image: UIImage?
    @State private var failed = false

    init(badge: StatsBadge, size: CGFloat, maxPixel: Int? = nil, onReady: (() -> Void)? = nil) {
        self.badge = badge
        self.size = size
        self.maxPixel = maxPixel
        self.onReady = onReady
        _image = State(initialValue: badge.unlocked
            ? badge.artworkURL.flatMap {
                NanoImageMemoryCache.shared.image(for: BadgeArtworkImageCache.key($0, maxPixel: maxPixel))
            }
            : nil)
    }

    var body: some View {
        Group {
            if badge.unlocked, badge.artworkURL != nil {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.025)
                        .shadow(color: badge.tint.opacity(0.32), radius: size * 0.10)
                        .modifier(ScrollFriendlyShadow(enabled: maxPixel != nil, margin: size * 0.25))
                } else if failed {
                    fallbackMedallion
                } else {
                    ProgressView()
                        .tint(badge.tint)
                }
            } else {
                fallbackMedallion
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(badge.id)-\(badge.unlocked)") {
            if badge.unlocked, let url = badge.artworkURL,
               let cached = NanoImageMemoryCache.shared.image(for: BadgeArtworkImageCache.key(url, maxPixel: maxPixel)) {
                image = cached
                onReady?()
                return
            }
            image = nil
            failed = false
            guard badge.unlocked, let artworkURL = badge.artworkURL else {
                onReady?()
                return
            }

            do {
                let data = try await BadgeArtworkImageCache.shared.data(for: artworkURL)
                guard !Task.isCancelled else { return }
                let key = BadgeArtworkImageCache.key(artworkURL, maxPixel: maxPixel)
                if let maxPixel {
                    image = await NanoImageMemoryCache.shared.thumbnail(data, maxPixel: maxPixel, for: key)
                } else {
                    image = await NanoImageMemoryCache.shared.decode(data, for: key)
                }
                failed = image == nil
                onReady?()
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
                onReady?()
            }
        }
        .accessibilityHidden(true)
    }

    private var fallbackMedallion: some View {
        Image(systemName: badge.unlocked ? badge.symbol : "lock.fill")
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(badge.unlocked ? badge.tint : NanoTheme.mutedText)
            .frame(width: size * 0.82, height: size * 0.82)
            .background(
                Circle()
                    .fill(NanoTheme.surface)
                    .stroke(
                        badge.unlocked ? badge.tint : NanoTheme.mutedText,
                        style: StrokeStyle(
                            lineWidth: max(2, size * 0.024),
                            dash: badge.unlocked ? [] : [5, 4]
                        )
                    )
            )
    }
}

/// Flattens a small badge's glow into one bitmap so it isn't redrawn every
/// scroll frame. Large, animated medallions keep the live shadow.
private struct ScrollFriendlyShadow: ViewModifier {
    let enabled: Bool
    let margin: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content.flattenedShadows(margin: margin)
        } else {
            content
        }
    }
}

private struct AchievementCard: View {
    /// 72pt at 3x.
    static let artworkMaxPixel = 216

    let badge: StatsBadge

    var body: some View {
        VStack(spacing: 10) {
            BadgeArtworkView(badge: badge, size: 72, maxPixel: Self.artworkMaxPixel)
            Text(badge.title)
                .font(NanoFont.aldrich(10))
                .foregroundStyle(NanoTheme.text)
                .lineLimit(badge.title.contains(" ") ? 2 : 1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
            Text(badge.completedAt?.formatted(.dateTime.month(.abbreviated).day()) ?? "UNLOCKED")
                .font(NanoFont.aldrich(7))
                .foregroundStyle(badge.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 132)
        .frame(minHeight: 154)
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private var artworkPrefetchID: String {
        sections
            .flatMap(\.badges)
            .filter(\.unlocked)
            .map(\.id)
            .joined(separator: "|")
    }

    private var unlockedArtworkURLs: [URL] {
        sections
            .flatMap(\.badges)
            .filter(\.unlocked)
            .compactMap(\.artworkURL)
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        collectionSummary

                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(section.title)
                                        .font(.system(.title3, design: .rounded, weight: .semibold))
                                        .foregroundStyle(NanoTheme.text)
                                    Spacer()
                                    Text("\(section.badges.filter(\.unlocked).count) / \(section.badges.count)")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(NanoTheme.secondaryText)
                                }

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
                                        .buttonStyle(BadgeCollectionPressStyle())
                                        .id(badge.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .top, spacing: 0) {
                    collectionToolbar
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
                    let isFeatureTour =
                        AppScreenshotScenario.active == .featureTourBadges
                    try? await Task.sleep(
                        for: isFeatureTour ? .seconds(8) : .milliseconds(120)
                    )
                    withAnimation(
                        isFeatureTour ? .smooth(duration: 3) : .snappy
                    ) {
                        proxy.scrollTo(highlightBadgeID, anchor: .center)
                    }
                    try? await Task.sleep(
                        for: isFeatureTour ? .seconds(4) : .milliseconds(180)
                    )
                    guard !Task.isCancelled else { return }
                    selectedBadge = highlightedBadge
                }
            }
        }
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailView(badge: badge)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task(id: artworkPrefetchID) {
            await BadgeArtworkImageCache.shared.prefetch(
                urls: unlockedArtworkURLs
            )
        }
    }

    private var collectionSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your achievements")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(NanoTheme.text)
            Text("A collection built one step at a time.")
                .font(.subheadline)
                .foregroundStyle(NanoTheme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(unlockedCount)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(NanoTheme.teal)
                Text("of \(totalCount) earned")
                    .font(.subheadline)
                    .foregroundStyle(NanoTheme.secondaryText)
            }
            .padding(.top, 8)
            ProgressView(value: Double(unlockedCount), total: Double(max(totalCount, 1)))
                .tint(NanoTheme.teal)
                .accessibilityLabel("Badge collection progress")
        }
        .padding(.bottom, 8)
    }

    private var collectionToolbar: some View {
        HStack {
            Text("COLLECTION")
                .font(NanoFont.aldrich(10))
                .tracking(1.8)
                .foregroundStyle(NanoTheme.secondaryText)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NanoTheme.text)
                    .frame(width: 44, height: 44)
                    .background(NanoTheme.ink.opacity(0.07), in: Circle())
            }
            .buttonStyle(BadgeCollectionPressStyle())
            .accessibilityLabel("Close badge collection")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background(NanoTheme.background)
    }

    private var unlockedCount: Int {
        sections.flatMap(\.badges).filter(\.unlocked).count
    }

    private var totalCount: Int {
        sections.flatMap(\.badges).count
    }
}

private struct BadgeCollectionPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct BadgeGridCell: View {
    let badge: StatsBadge
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 12) {
            BadgeArtworkView(badge: badge, size: 102)
                .shadow(color: badge.unlocked ? badge.tint.opacity(0.16) : .clear, radius: 14)
                .padding(.vertical, 8)
                .accessibilityHidden(true)
            Text(badge.title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(badge.unlocked ? NanoTheme.text : NanoTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 40, alignment: .top)
            Label(
                badge.unlocked
                    ? badge.completedAt?.formatted(.dateTime.month(.abbreviated).day()) ?? "Earned"
                    : "Locked",
                systemImage: badge.unlocked ? "checkmark.seal.fill" : "lock.fill"
            )
            .font(.caption)
            .foregroundStyle(badge.unlocked ? badge.tint : NanoTheme.mutedText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [NanoTheme.ink.opacity(badge.unlocked ? 0.055 : 0.025), NanoTheme.ink.opacity(0.015)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(highlighted ? badge.tint.opacity(0.5) : NanoTheme.ink.opacity(0.07), lineWidth: 1)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(badge.title), \(badge.unlocked ? "earned" : "locked")")
        .accessibilityHint("Opens achievement details")
    }
}

private struct BadgeDetailView: View {
    let badge: StatsBadge

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var accent: Color { badge.unlocked ? badge.tint : NanoTheme.secondaryText }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text("NANOBEASTS / ACHIEVEMENTS")
                            .font(NanoFont.aldrich(10))
                            .tracking(1.5)
                            .foregroundStyle(NanoTheme.secondaryText)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(NanoTheme.text)
                                .frame(width: 44, height: 44)
                                .background(NanoTheme.ink.opacity(0.07), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close badge")
                    }

                    ZStack {
                        Circle()
                            .fill(RadialGradient(
                                colors: [accent.opacity(0.18), accent.opacity(0.04), .clear],
                                center: .center, startRadius: 12, endRadius: 165
                            ))
                            .frame(width: 330, height: 330)
                        Circle()
                            .strokeBorder(accent.opacity(0.10), lineWidth: 1)
                            .frame(width: 276, height: 276)
                        Circle()
                            .strokeBorder(NanoTheme.ink.opacity(0.035), lineWidth: 1)
                            .frame(width: 310, height: 310)
                        SpinningBadgeMedallion(badge: badge, appeared: appeared, size: 220)
                    }
                    .frame(height: 330)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                    VStack(spacing: 16) {
                        Label(badge.unlocked ? "EARNED" : "YET TO UNLOCK",
                              systemImage: badge.unlocked ? "checkmark.seal.fill" : "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.8)
                            .foregroundStyle(accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(accent.opacity(0.09), in: Capsule())

                        Text(badge.title)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(NanoTheme.text)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(badge.description)
                            .font(.body)
                            .foregroundStyle(NanoTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 310)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 8)

                    Spacer(minLength: 32)

                    if badge.unlocked {
                        VStack(spacing: 20) {
                            if let date = badge.completedAt {
                                HStack(spacing: 12) {
                                    Rectangle().fill(NanoTheme.ink.opacity(0.10)).frame(height: 1)
                                    Text(date.formatted(.dateTime.month(.wide).day().year()))
                                        .font(.subheadline)
                                        .foregroundStyle(NanoTheme.secondaryText)
                                        .fixedSize()
                                    Rectangle().fill(NanoTheme.ink.opacity(0.10)).frame(height: 1)
                                }
                            }
                            BadgeShareButton(badge: badge)
                        }
                    } else {
                        Text("Every step brings you closer.")
                            .font(.subheadline)
                            .foregroundStyle(NanoTheme.secondaryText)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(NanoTheme.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.24)) { appeared = true }
        }
    }
}

struct BadgeAwardCelebrationView: View {
    let badge: StatsBadge
    var onAcknowledged: (() -> Void)? = nil

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AccessibilityFocusState private var titleHasFocus: Bool
    @State private var appeared = false
    @State private var acknowledged = false

    private var reduceMotion: Bool { systemReduceMotion || store.reduceMotion }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Label("BADGE UNLOCKED", systemImage: "checkmark.seal.fill")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(NanoTheme.teal)
                        Spacer(minLength: 8)
                        Button(action: acknowledgeAndDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(NanoTheme.ink.opacity(0.06), in: Circle())
                        }
                        .buttonStyle(BadgePressStyle(suppressMotion: reduceMotion))
                        .accessibilityLabel("Close achievement")
                    }

                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [badge.tint.opacity(0.23), .clear],
                                                 center: .center, startRadius: 25, endRadius: 116))
                            .frame(width: 232, height: 232)
                        Circle().stroke(badge.tint.opacity(0.12), lineWidth: 1)
                            .frame(width: 208, height: 208)
                        SpinningBadgeMedallion(badge: badge, appeared: appeared, size: 178,
                                              suppressMotion: reduceMotion)
                    }
                    .frame(height: 232)
                    .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        Text(badge.title)
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($titleHasFocus)
                        Text(badge.description)
                            .font(.subheadline)
                            .foregroundStyle(NanoTheme.secondaryText)
                            .lineSpacing(3)
                        if let date = badge.completedAt {
                            Text("Earned \(date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(NanoTheme.secondaryText)
                                .padding(.top, 4)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 8) {
                        BadgeShareButton(badge: badge, accentColor: NanoTheme.teal, suppressMotion: reduceMotion)
                        Button(action: acknowledgeAndDismiss) {
                            Text("Done")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(BadgePressStyle(suppressMotion: reduceMotion))
                    }
                    .padding(.top, 6)
                }
                .padding(24)
                .frame(maxWidth: 390)
                .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 32))
                .overlay(RoundedRectangle(cornerRadius: 32).stroke(NanoTheme.ink.opacity(0.09), lineWidth: 1))
                .shadow(color: NanoTheme.shadow.opacity(0.35), radius: 32, y: 14)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.96)
                .padding(22)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(NanoTheme.text)
        .background(Color.black.opacity(0.64).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .accessibilityAction(.escape, acknowledgeAndDismiss)
        .task {
            guard !appeared else { return }
            if store.hapticsEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)) { appeared = true }
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            titleHasFocus = true
        }
    }

    private func acknowledgeAndDismiss() {
        guard !acknowledged else { return }
        acknowledged = true
        onAcknowledged?()
        dismiss()
    }
}

private struct BadgePressStyle: ButtonStyle {
    var suppressMotion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion && !suppressMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct BadgeShareButton: View {
    let badge: StatsBadge
    var accentColor: Color? = nil
    var suppressMotion = false

    @State private var shareImage: UIImage?
    @State private var presentsShareSheet = false
    @State private var isPreparing = false

    var body: some View {
        Button {
            Task { await prepareSharePayload() }
        } label: {
            HStack(spacing: 9) {
                if isPreparing {
                    ProgressView().controlSize(.small).tint(.black)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(isPreparing ? "Preparing…" : "Share achievement")
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(accentColor ?? badge.tint, in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(BadgePressStyle(suppressMotion: suppressMotion))
        .foregroundStyle(.black)
        .disabled(isPreparing)
        .sheet(isPresented: $presentsShareSheet) {
            if let shareImage {
                BadgeActivityShareSheet(items: [shareImage, "I just unlocked “\(badge.title)” in Nanobeasts!"])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @MainActor
    private func prepareSharePayload() async {
        guard !isPreparing else { return }
        if shareImage != nil { presentsShareSheet = true; return }
        isPreparing = true
        defer { isPreparing = false }
        let artwork: UIImage
        if let url = badge.artworkURL,
           let data = try? await BadgeArtworkImageCache.shared.data(for: url),
           let image = UIImage(data: data) {
            artwork = image
        } else {
            artwork = badge.fallbackShareImage()
        }
        shareImage = BadgeShareArtwork.render(badge: badge, artwork: artwork)
        presentsShareSheet = shareImage != nil
    }
}

private struct BadgeShareArtwork: View {
    let badge: StatsBadge
    let artwork: UIImage

    var body: some View {
        VStack(spacing: 16) {
            Text("NANOBEASTS")
                .font(NanoFont.aldrich(17)).tracking(3)
                .foregroundStyle(NanoTheme.teal)
            Text("ACHIEVEMENT UNLOCKED")
                .font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(2)
                .foregroundStyle(NanoTheme.text.opacity(0.7))
            Image(uiImage: artwork).resizable().scaledToFit()
                .frame(width: 190, height: 190)
                .shadow(color: badge.tint.opacity(0.35), radius: 24)
                .padding(.vertical, 4)
            Text(badge.title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.8).lineLimit(2)
            Text(badge.description)
                .font(.system(size: 13)).foregroundStyle(NanoTheme.text.opacity(0.72))
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if let date = badge.completedAt {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11)).foregroundStyle(NanoTheme.teal)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(NanoTheme.text)
        .padding(30)
        .frame(width: 360, height: 560)
        .background {
            ZStack {
                Color(red: 0.035, green: 0.045, blue: 0.05)
                RadialGradient(colors: [badge.tint.opacity(0.15), .clear], center: .center,
                               startRadius: 15, endRadius: 220)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(NanoTheme.teal.opacity(0.2)).padding(12))
    }

    @MainActor
    static func render(badge: StatsBadge, artwork: UIImage) -> UIImage? {
        let renderer = ImageRenderer(content: BadgeShareArtwork(badge: badge, artwork: artwork)
            .environment(\.colorScheme, .dark))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

private struct BadgeActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

/// A collectible coin: spins twice once it's on screen, spins again on tap,
/// and can be turned by hand, springing back to face forward.
private struct SpinningBadgeMedallion: View {
    let badge: StatsBadge
    let appeared: Bool
    let size: CGFloat
    var suppressMotion = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || suppressMotion }
    @State private var artworkReady = false
    @State private var rotation: Double = 0
    @State private var dragStart: Double?
    @State private var hasIntroSpun = false

    private var canSpin: Bool { badge.unlocked && !reduceMotion }

    var body: some View {
        BadgeArtworkView(
            badge: badge,
            size: size,
            onReady: {
                guard !artworkReady else { return }
                artworkReady = true
            }
        )
            .overlay {
                if !badge.unlocked || badge.artworkURL == nil {
                    Circle()
                        .trim(from: 0.08, to: 0.42)
                        .stroke(NanoTheme.ink.opacity(0.42), lineWidth: 2)
                        .padding(size * 0.11)
                        .rotationEffect(.degrees(appeared && !reduceMotion ? 520 : 0))
                        .animation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.72),
                                   value: appeared)
                }
            }
            .rotation3DEffect(.degrees(rotation), axis: (0, 1, 0), perspective: 0.55)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.95)
            .shadow(color: badge.tint.opacity(badge.unlocked ? 0.48 : 0), radius: 24)
            .contentShape(Circle())
            .onTapGesture { spin(turns: 1, duration: 1.1) }
            .simultaneousGesture(DragGesture(minimumDistance: 6)
                .onChanged { value in
                    // Vertical drags belong to the surrounding scroll view.
                    guard canSpin, dragStart != nil
                        || abs(value.translation.width) > abs(value.translation.height) else { return }
                    let start = dragStart ?? rotation
                    dragStart = start
                    rotation = start + value.translation.width * 0.9
                }
                .onEnded { value in
                    guard canSpin, let start = dragStart else { return }
                    dragStart = nil
                    // Carry the flick's momentum, then settle face-forward.
                    let projected = start + value.predictedEndTranslation.width * 0.9
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) {
                        rotation = (projected / 360).rounded() * 360
                    }
                })
            .task(id: appeared && artworkReady) {
                guard appeared, artworkReady, !hasIntroSpun else { return }
                hasIntroSpun = true
                // Let a presenting sheet settle so the spin is actually seen.
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled else { return }
                spin(turns: 2, duration: 1.6)
            }
            .onChange(of: badge.id) {
                artworkReady = false
                hasIntroSpun = false
                rotation = 0
            }
            .accessibilityAddTraits(canSpin ? .isButton : [])
            .accessibilityHint(canSpin ? "Spins the badge" : "")
    }

    private func spin(turns: Double, duration: Double) {
        guard canSpin, dragStart == nil else { return }
        let target = ((rotation / 360).rounded() + turns) * 360
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: duration)) { rotation = target }
    }
}

private extension StatsBadge {
    @MainActor
    func fallbackShareImage() -> UIImage {
        let canvasSize = CGSize(width: 1_024, height: 1_024)
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: canvasSize)
            context.cgContext.clear(bounds)

            let medallion = bounds.insetBy(dx: 92, dy: 92)
            context.cgContext.setFillColor(UIColor(NanoTheme.surface).cgColor)
            context.cgContext.fillEllipse(in: medallion)
            context.cgContext.setStrokeColor(UIColor(tint).cgColor)
            context.cgContext.setLineWidth(26)
            context.cgContext.strokeEllipse(in: medallion.insetBy(dx: 13, dy: 13))

            let configuration = UIImage.SymbolConfiguration(
                pointSize: 390,
                weight: .semibold
            )
            let symbolImage = UIImage(
                systemName: unlocked ? symbol : "lock.fill",
                withConfiguration: configuration
            )?.withTintColor(UIColor(unlocked ? tint : NanoTheme.mutedText))
            if let symbolImage {
                let symbolSize = symbolImage.size
                let origin = CGPoint(
                    x: (canvasSize.width - symbolSize.width) / 2,
                    y: (canvasSize.height - symbolSize.height) / 2
                )
                symbolImage.draw(at: origin)
            }
        }
    }
}

private extension UIImage {
    func trimmingTransparentCanvas() -> UIImage {
        guard let cgImage else { return self }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return self }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard rendered else { return self }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                let alpha = pixels[offset + 3]
                let colorRange = max(red, green, blue) - min(red, green, blue)
                let isIllustratedContent =
                    colorRange > 18 || max(red, green, blue) < 86
                guard alpha > 24, isIllustratedContent else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return self }
        // Ignore the opaque gray shadows baked into some concept exports so
        // every custom badge uses the same optical footprint as First Hatch.
        let padding = max(Int(Double(max(width, height)) * 0.018), 2)
        let cropRect = CGRect(
            x: max(minX - padding, 0),
            y: max(minY - padding, 0),
            width: min(maxX + padding, width - 1) - max(minX - padding, 0) + 1,
            height: min(maxY + padding, height - 1) - max(minY - padding, 0) + 1
        )
        guard let cropped = cgImage.cropping(to: cropRect) else { return self }
        return UIImage(
            cgImage: cropped,
            scale: scale,
            orientation: imageOrientation
        )
    }
}
