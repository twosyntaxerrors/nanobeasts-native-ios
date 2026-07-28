import Foundation

struct CreatureCatalog: Decodable, Sendable {
    let families: [CreatureFamily]

    enum CodingKeys: String, CodingKey {
        case families = "evolution_families"
    }

    var creatureStages: [CreatureStage] {
        families.flatMap(\.stages).filter { $0.stage > 0 }
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
