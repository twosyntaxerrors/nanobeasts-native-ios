import Foundation

struct CreatureCatalog: Decodable, Sendable {
    let families: [CreatureFamily]

    enum CodingKeys: String, CodingKey {
        case families = "evolution_families"
    }

    var creatureStages: [CreatureStage] {
        families.flatMap(\.stages).filter { $0.stage > 0 }
    }

    /// Full lifecycle cost per true evolution across species that can evolve.
    /// Includes hatching and maturity; neither is counted as an evolution.
    var averageStepsPerEvolution: Int? {
        var steps = 0
        var evolutions = 0
        for (index, family) in families.enumerated() {
            let count = zip(family.stages, family.stages.dropFirst()).filter { !$0.0.isEgg }.count
            guard count > 0 else { continue }
            steps += family.stages.reduce(0) { $0 + CreatureProgressionRules.steps(familyIndex: index, stage: $1.stage) }
            evolutions += count
        }
        guard evolutions > 0 else { return nil }
        return Int(ceil(Double(steps) / Double(evolutions)))
    }

    static func load() -> CreatureCatalog {
        guard
            let url = Bundle.main.url(forResource: "creatures-by-family", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(CreatureCatalog.self, from: data),
            !catalog.families.isEmpty
        else {
            return .fallback
        }
        return catalog
    }

    static let fallback = CreatureCatalog(families: [
        CreatureFamily(
            id: "tutorial-family-000",
            name: "Tutoria Line",
            stages: [
                CreatureStage(
                    familyID: "tutorial-family-000",
                    name: "Tutoria Egg",
                    imageKey: "tutorial-egg-stage-0-modern",
                    stage: 0,
                    types: ["Normal"],
                    description: "A special egg given to new researchers."
                ),
                CreatureStage(
                    familyID: "tutorial-family-000",
                    name: "Tutoria",
                    imageKey: "tutorial-stage-1-modern",
                    stage: 1,
                    types: ["Normal"],
                    description: "A friendly first companion for every Nanobeast researcher."
                )
            ]
        )
    ])
}

/// Shared by actual progression and the onboarding challenge estimate.
enum CreatureProgressionRules {
    static func steps(familyIndex: Int, stage: Int) -> Int {
        if familyIndex == 0 { return stage == 0 ? 250 : 500 }
        let base = 10_000 + 1_500 * max(familyIndex - 1, 0)
        let multiplier: Double = switch min(max(stage, 0), 3) {
        case 0: 0.30
        case 1: 0.55
        case 2: 0.75
        default: 1
        }
        let rounded = Int((Double(base) * multiplier / 100).rounded()) * 100
        return min(max(rounded, 500), 15_000)
    }
}

struct CreatureFamily: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let stages: [CreatureStage]

    enum CodingKeys: String, CodingKey {
        case id = "evolution_family_id"
        case name = "family_name"
        case stages
    }

    init(id: String, name: String, stages: [CreatureStage]) {
        self.id = id
        self.name = name
        self.stages = stages.map {
            CreatureStage(
                familyID: id,
                name: $0.name,
                imageKey: $0.imageKey,
                stage: $0.stage,
                types: $0.types,
                description: $0.description
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decode(String.self, forKey: .id)
        id = decodedID
        name = try container.decode(String.self, forKey: .name)
        let rawStages = try container.decode([RawCreatureStage].self, forKey: .stages)
        stages = rawStages.map {
            CreatureStage(
                familyID: decodedID,
                name: $0.name,
                imageKey: $0.imageKey,
                stage: $0.stage,
                types: $0.types,
                description: $0.description
            )
        }
    }
}

private struct RawCreatureStage: Decodable {
    let name: String
    let imageKey: String
    let stage: Int
    let types: [String]
    let description: String

    enum CodingKeys: String, CodingKey {
        case name
        case imageKey = "image_key"
        case stage
        case types
        case description
    }
}

struct CreatureStage: Identifiable, Hashable, Sendable {
    let familyID: String
    let name: String
    let imageKey: String
    let stage: Int
    let types: [String]
    let description: String

    var id: String {
        "\(familyID)-\(stage)-\(imageKey)"
    }

    var isEgg: Bool {
        stage == 0
    }
}

struct DailyStepRecord: Identifiable, Hashable, Codable, Sendable {
    let day: Date
    let steps: Int

    var id: Date { day }
}

struct HourlyStepRecord: Identifiable, Hashable, Codable, Sendable {
    let start: Date
    let steps: Int

    var id: Date { start }
}

struct DailyGoalRecord: Identifiable, Hashable, Codable, Sendable {
    let day: Date
    let goal: Int

    var id: Date { day }
}

enum CreatureDiscoveryKind: String, Codable, Hashable, Sendable {
    case eggAcquired
    case hatch
    case evolution
    case maturity

    var title: String {
        switch self {
        case .eggAcquired: "EGG ACQUIRED"
        case .hatch: "HATCHED"
        case .evolution: "EVOLVED"
        case .maturity: "FULL MATURITY"
        }
    }

    var symbol: String {
        switch self {
        case .eggAcquired: "gift.fill"
        case .hatch: "sparkles"
        case .evolution: "flask.fill"
        case .maturity: "crown.fill"
        }
    }
}

struct CreatureDiscoveryEvent: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let kind: CreatureDiscoveryKind
    let familyID: String
    let name: String
    let imageKey: String
    let stage: Int
    let types: [String]
    let description: String

    init(stage: CreatureStage, kind: CreatureDiscoveryKind, timestamp: Date = Date()) {
        id = UUID()
        self.timestamp = timestamp
        self.kind = kind
        familyID = stage.familyID
        name = stage.name
        imageKey = stage.imageKey
        self.stage = stage.stage
        types = stage.types
        description = stage.description
    }

    var creatureStage: CreatureStage {
        CreatureStage(
            familyID: familyID,
            name: name,
            imageKey: imageKey,
            stage: stage,
            types: types,
            description: description
        )
    }
}

enum HealthConnectionState: Equatable, Sendable {
    case notRequested
    case connecting
    case connected
    case unavailable
    case failed(String)

    var title: String {
        switch self {
        case .notRequested: "Not connected"
        case .connecting: "Connecting…"
        case .connected: "Apple Health connected"
        case .unavailable: "Health data unavailable"
        case .failed: "Sync needs attention"
        }
    }
}
