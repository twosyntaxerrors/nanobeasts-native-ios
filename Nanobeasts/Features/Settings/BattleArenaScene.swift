import SpriteKit
import UIKit

enum BattlePreviewPhase: Equatable {
    case ready
    case running
    case paused
    case finished
}

struct BattlePreviewTelemetry: Equatable {
    var phase: BattlePreviewPhase = .ready
    var secondsRemaining = 40
    var combatantsRemaining = 4
    var event = "Arena initialized. Choose your contender."
    var winner: String?
    var winnerID: String?
}

struct BattleFighterDefinition: Identifiable {
    let id: String
    let name: String
    let className: String
    let assetName: String
    let moveName: String
    let maxHealth: CGFloat
    let attackPower: CGFloat
    let movementSpeed: CGFloat
    let attackRange: CGFloat
    let attackInterval: TimeInterval
    let attackColor: UIColor

    static let previewRoster = [
        BattleFighterDefinition(
            id: "ampaw",
            name: "Ampaw",
            className: "Arc",
            assetName: "AmpawBattleSprite",
            moveName: "Arc Punch",
            maxHealth: 174,
            attackPower: 25,
            movementSpeed: 76,
            attackRange: 76,
            attackInterval: 0.72,
            attackColor: UIColor(red: 1, green: 0.85, blue: 0.20, alpha: 1)
        ),
        BattleFighterDefinition(
            id: "aquablossom",
            name: "Aquablossom",
            className: "Bloom",
            assetName: "AquablossomBattleSprite",
            moveName: "Lotus Wave",
            maxHealth: 188,
            attackPower: 19,
            movementSpeed: 67,
            attackRange: 110,
            attackInterval: 0.92,
            attackColor: UIColor(red: 0.35, green: 0.94, blue: 0.92, alpha: 1)
        ),
        BattleFighterDefinition(
            id: "flarva",
            name: "Flarva",
            className: "Ember",
            assetName: "FlarvaBattleSprite",
            moveName: "Ember Rush",
            maxHealth: 156,
            attackPower: 23,
            movementSpeed: 82,
            attackRange: 72,
            attackInterval: 0.76,
            attackColor: UIColor(red: 1, green: 0.42, blue: 0.18, alpha: 1)
        ),
        BattleFighterDefinition(
            id: "sproutomb",
            name: "Sproutomb",
            className: "Spore",
            assetName: "SproutombBattleSprite",
            moveName: "Wither Pop",
            maxHealth: 206,
            attackPower: 18,
            movementSpeed: 58,
            attackRange: 96,
            attackInterval: 0.98,
            attackColor: UIColor(red: 0.73, green: 0.52, blue: 0.92, alpha: 1)
        )
    ]
}

final class BattleArenaScene: SKScene {
    var onTelemetry: ((BattlePreviewTelemetry) -> Void)?

    private let matchDuration: TimeInterval = 40
    private let suddenDeathTime: TimeInterval = 27
    private let fixedStep: TimeInterval = 1.0 / 30.0

    private var actors: [BattleActor] = []
    private var random = BattleSeededGenerator(seed: 1)
    private var phase: BattlePreviewPhase = .ready
    private var elapsed: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var accumulator: TimeInterval = 0
    private var lastPublishedSecond = -1
    private var lastEvent = "Arena initialized. Choose your contender."
    private var winner: String?
    private var winnerID: String?
    private var enteredSuddenDeath = false
    private var lineup = BattleFighterDefinition.previewRoster
    private var featuredFighterID = BattleFighterDefinition.previewRoster[0].id
    private var playbackRate: Double = 1

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFit
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reset(
        seed: UInt64,
        lineup: [BattleFighterDefinition],
        featuredFighterID: String
    ) {
        isPaused = false
        speed = playbackRate
        removeAllActions()
        removeAllChildren()
        actors.removeAll()

        self.lineup = lineup
        self.featuredFighterID = featuredFighterID
        random = BattleSeededGenerator(seed: seed)
        phase = .ready
        elapsed = 0
        lastUpdateTime = 0
        accumulator = 0
        lastPublishedSecond = -1
        let featuredName = lineup.first(where: { $0.id == featuredFighterID })?.name
            ?? lineup.first?.name
            ?? "Contender"
        lastEvent = "Four-way free-for-all ready. Your pick: \(featuredName)."
        winner = nil
        winnerID = nil
        enteredSuddenDeath = false

        buildArena()
        spawnCombatants()
        publishTelemetry(force: true)
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = min(max(rate, 1), 2)
        speed = playbackRate
        guard phase == .running || phase == .paused else { return }
        lastEvent = playbackRate == 2
            ? "2× SPEED — arena clock accelerated."
            : "1× SPEED — standard arena clock."
        publishTelemetry(force: true)
    }

    func startBattle() {
        guard phase == .ready else { return }
        phase = .running
        lastUpdateTime = 0
        lastEvent = "BATTLE START — autonomous targeting online."
        publishTelemetry(force: true)
    }

    func pauseBattle() {
        guard phase == .running else { return }
        phase = .paused
        lastEvent = "Simulation paused."
        publishTelemetry(force: true)
        isPaused = true
    }

    func resumeBattle() {
        guard phase == .paused else { return }
        isPaused = false
        phase = .running
        lastUpdateTime = 0
        lastEvent = "Simulation resumed."
        publishTelemetry(force: true)
    }

    override func update(_ currentTime: TimeInterval) {
        guard phase == .running else { return }
        guard lastUpdateTime > 0 else {
            lastUpdateTime = currentTime
            return
        }

        let frameDelta = min(currentTime - lastUpdateTime, 0.1)
        lastUpdateTime = currentTime
        accumulator += frameDelta * playbackRate

        while accumulator >= fixedStep, phase == .running {
            simulate(step: fixedStep)
            accumulator -= fixedStep
        }
    }

    private func simulate(step: TimeInterval) {
        elapsed += step

        if elapsed >= suddenDeathTime, !enteredSuddenDeath {
            enteredSuddenDeath = true
            lastEvent = "OVERCHARGE FIELD — all damage amplified."
            flashArena(color: UIColor(red: 0.98, green: 0.81, blue: 0.20, alpha: 1))
            publishTelemetry(force: true)
        }

        let living = actors.filter(\.isAlive)
        if living.count <= 1 {
            finishBattle(with: living.first)
            return
        }

        for actor in living {
            actor.cooldown = max(actor.cooldown - step, 0)
            actor.retargetCooldown = max(actor.retargetCooldown - step, 0)
            guard let target = target(for: actor, among: living) else { continue }

            let delta = target.root.position - actor.root.position
            let distance = max(delta.length, 0.001)
            let direction = delta / distance

            if distance > actor.attackRange {
                actor.face(direction: direction)
                actor.root.position = clampToArena(
                    actor.root.position + direction * actor.speed * CGFloat(step)
                )
            } else if actor.cooldown <= 0 {
                performAttack(from: actor, to: target)
                actor.cooldown = actor.attackInterval
            }
        }

        separateCombatants()

        if enteredSuddenDeath {
            for actor in actors where actor.isAlive {
                actor.receive(damage: CGFloat(step) * 2.8)
                if !actor.isAlive {
                    eliminate(actor)
                }
            }
        }

        if elapsed >= matchDuration {
            let survivor = actors
                .filter(\.isAlive)
                .max(by: { $0.healthFraction < $1.healthFraction })
            if let survivor {
                for actor in actors where actor.isAlive && actor !== survivor {
                    actor.receive(damage: actor.health + 1)
                    eliminate(actor)
                }
            }
            finishBattle(with: survivor)
            return
        }

        publishTelemetry()
    }

    private func target(
        for actor: BattleActor,
        among candidates: [BattleActor]
    ) -> BattleActor? {
        if actor.retargetCooldown > 0,
           let currentTarget = actor.target,
           currentTarget.isAlive {
            return currentTarget
        }

        let opponents = candidates.filter { $0 !== actor && $0.isAlive }
        guard !opponents.isEmpty else { return nil }

        let ranked = opponents.sorted {
            ($0.root.position - actor.root.position).squaredLength
                < ($1.root.position - actor.root.position).squaredLength
        }
        let nearbyCount = min(ranked.count, 2)
        let nearby = Array(ranked.prefix(nearbyCount))
        let chosen: BattleActor
        if ranked.count > 2, random.unitDouble() < 0.20 {
            chosen = ranked[random.int(in: 0...(ranked.count - 1))]
        } else {
            chosen = nearby[random.int(in: 0...(nearby.count - 1))]
        }

        actor.target = chosen
        actor.retargetCooldown = 1.4 + random.unitDouble() * 1.8
        return chosen
    }

    private func performAttack(from attacker: BattleActor, to target: BattleActor) {
        let roll = 0.86 + random.unitDouble() * 0.28
        let isCritical = random.unitDouble() < 0.12
        let overcharge = enteredSuddenDeath ? 1.45 : 1
        let damage = attacker.attackPower * CGFloat(roll) * CGFloat(overcharge)
            * (isCritical ? 1.65 : 1)

        attacker.face(direction: target.root.position - attacker.root.position)
        attacker.punch()
        showAttack(from: attacker, to: target, critical: isCritical)
        target.receive(damage: damage)
        if target.isAlive, random.unitDouble() < 0.28 {
            target.target = attacker
            target.retargetCooldown = 0.8 + random.unitDouble() * 0.8
        }

        let damageValue = Int(damage.rounded())
        lastEvent = isCritical
            ? "CRITICAL \(attacker.moveName)! \(target.name) -\(damageValue)"
            : "\(attacker.name) used \(attacker.moveName). \(target.name) -\(damageValue)"

        if !target.isAlive {
            eliminate(target)
            lastEvent = "\(target.name) was knocked out by \(attacker.name)."
        }

        publishTelemetry(force: true)
    }

    private func showAttack(
        from attacker: BattleActor,
        to target: BattleActor,
        critical: Bool
    ) {
        let origin = attacker.root.position
        let destination = target.root.position
        let attackColor = attacker.attackColor

        if attacker.isPlayer {
            for index in 1...5 {
                let progress = CGFloat(index) / 6
                let spark = SKSpriteNode(
                    color: index.isMultiple(of: 2) ? .white : attackColor,
                    size: CGSize(width: 10, height: 10)
                )
                spark.position = origin + (destination - origin) * progress
                spark.zPosition = 30
                addChild(spark)
                spark.run(
                    .sequence([
                        .wait(forDuration: Double(index) * 0.018),
                        .scale(to: critical ? 1.8 : 1.25, duration: 0.05),
                        .fadeOut(withDuration: 0.12),
                        .removeFromParent()
                    ])
                )
            }
        } else {
            let projectile = SKSpriteNode(
                color: attackColor,
                size: CGSize(width: critical ? 18 : 13, height: critical ? 18 : 13)
            )
            projectile.position = origin
            projectile.zPosition = 30
            addChild(projectile)
            projectile.run(
                .sequence([
                    .move(to: destination, duration: 0.13),
                    .scale(to: 1.7, duration: 0.04),
                    .fadeOut(withDuration: 0.08),
                    .removeFromParent()
                ])
            )
        }

        showMoveLabel(attacker.moveName, above: attacker, color: attackColor)
        target.flash(color: attackColor)

        let damageLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        damageLabel.text = critical ? "CRIT!" : "HIT"
        damageLabel.fontSize = critical ? 15 : 11
        damageLabel.fontColor = critical ? .white : attackColor
        damageLabel.position = destination + CGPoint(x: 0, y: 48)
        damageLabel.zPosition = 40
        addChild(damageLabel)
        damageLabel.run(
            .sequence([
                .group([
                    .moveBy(x: 0, y: 26, duration: 0.35),
                    .fadeOut(withDuration: 0.35)
                ]),
                .removeFromParent()
            ])
        )
    }

    private func showMoveLabel(
        _ text: String,
        above actor: BattleActor,
        color: UIColor
    ) {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text.uppercased()
        label.fontSize = 11
        label.fontColor = color
        label.position = actor.root.position + CGPoint(x: 0, y: 66)
        label.zPosition = 45
        addChild(label)
        label.run(
            .sequence([
                .group([
                    .moveBy(x: 0, y: 14, duration: 0.32),
                    .fadeOut(withDuration: 0.32)
                ]),
                .removeFromParent()
            ])
        )
    }

    private func eliminate(_ actor: BattleActor) {
        guard !actor.wasEliminated else { return }
        actor.wasEliminated = true
        actor.root.run(
            .sequence([
                .group([
                    .scale(to: 0.15, duration: 0.28),
                    .fadeOut(withDuration: 0.28),
                    .rotate(byAngle: actor.isPlayer ? -0.35 : 0.35, duration: 0.28)
                ])
            ])
        )

        let burstColor = actor.attackColor
        for _ in 0..<8 {
            let bit = SKSpriteNode(color: burstColor, size: CGSize(width: 8, height: 8))
            bit.position = actor.root.position
            bit.zPosition = 35
            addChild(bit)
            let x = CGFloat(random.int(in: -44...44))
            let y = CGFloat(random.int(in: -44...44))
            bit.run(
                .sequence([
                    .group([
                        .moveBy(x: x, y: y, duration: 0.32),
                        .fadeOut(withDuration: 0.32)
                    ]),
                    .removeFromParent()
                ])
            )
        }
    }

    private func finishBattle(with survivor: BattleActor?) {
        guard phase == .running else { return }
        phase = .finished
        winner = survivor?.name
        winnerID = survivor?.id
        if let survivor {
            lastEvent = survivor.isPlayer
                ? "\(survivor.name.uppercased()) WINS — your pick survived."
                : "\(survivor.name) wins the simulation."
        } else {
            lastEvent = "DRAW — no combatants remain."
        }
        publishTelemetry(force: true)
    }

    private func separateCombatants() {
        let living = actors.filter(\.isAlive)
        guard living.count > 1 else { return }

        for firstIndex in 0..<(living.count - 1) {
            for secondIndex in (firstIndex + 1)..<living.count {
                let first = living[firstIndex]
                let second = living[secondIndex]
                let delta = second.root.position - first.root.position
                let distance = max(delta.length, 0.001)
                let minimumDistance: CGFloat = 58
                guard distance < minimumDistance else { continue }

                let correction = delta / distance * ((minimumDistance - distance) * 0.5)
                first.root.position = clampToArena(first.root.position - correction)
                second.root.position = clampToArena(second.root.position + correction)
            }
        }
    }

    private func clampToArena(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 52), size.width - 52),
            y: min(max(point.y, 52), size.height - 52)
        )
    }

    private func buildArena() {
        let base = SKSpriteNode(
            color: UIColor(red: 0.20, green: 0.43, blue: 0.24, alpha: 1),
            size: size
        )
        base.anchorPoint = .zero
        base.position = .zero
        base.zPosition = -30
        addChild(base)

        let tileSize: CGFloat = 72
        for row in 0..<10 {
            for column in 0..<10 {
                let even = (row + column).isMultiple(of: 2)
                let tile = SKSpriteNode(
                    color: even
                        ? UIColor(red: 0.35, green: 0.61, blue: 0.32, alpha: 1)
                        : UIColor(red: 0.31, green: 0.55, blue: 0.29, alpha: 1),
                    size: CGSize(width: tileSize, height: tileSize)
                )
                tile.anchorPoint = .zero
                tile.position = CGPoint(
                    x: CGFloat(column) * tileSize,
                    y: CGFloat(row) * tileSize
                )
                tile.zPosition = -25
                addChild(tile)
            }
        }

        for index in stride(from: 0, through: 720, by: 36) {
            let horizontal = SKSpriteNode(
                color: UIColor.black.withAlphaComponent(0.055),
                size: CGSize(width: 720, height: 2)
            )
            horizontal.position = CGPoint(x: 360, y: CGFloat(index))
            horizontal.zPosition = -20
            addChild(horizontal)

            let vertical = SKSpriteNode(
                color: UIColor.black.withAlphaComponent(0.055),
                size: CGSize(width: 2, height: 720)
            )
            vertical.position = CGPoint(x: CGFloat(index), y: 360)
            vertical.zPosition = -20
            addChild(vertical)
        }

        let centerPlate = SKSpriteNode(
            color: UIColor(red: 0.10, green: 0.31, blue: 0.19, alpha: 1),
            size: CGSize(width: 116, height: 116)
        )
        centerPlate.position = CGPoint(x: 360, y: 360)
        centerPlate.zPosition = -10
        addChild(centerPlate)

        let centerCore = SKSpriteNode(
            color: UIColor(red: 0.33, green: 0.96, blue: 0.76, alpha: 1),
            size: CGSize(width: 66, height: 66)
        )
        centerCore.position = CGPoint(x: 360, y: 360)
        centerCore.zPosition = -9
        addChild(centerCore)

        addGate(label: "N", position: CGPoint(x: 360, y: 690), color: .systemRed)
        addGate(label: "W", position: CGPoint(x: 30, y: 360), color: .systemOrange)
        addGate(label: "E", position: CGPoint(x: 690, y: 360), color: .systemBlue)
        addGate(label: "S", position: CGPoint(x: 360, y: 30), color: .systemPurple)

        let border = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        border.strokeColor = UIColor(red: 0.32, green: 0.94, blue: 0.74, alpha: 0.72)
        border.lineWidth = 8
        border.isAntialiased = false
        border.zPosition = 60
        addChild(border)
    }

    private func addGate(label: String, position: CGPoint, color: UIColor) {
        let gate = SKSpriteNode(color: color, size: CGSize(width: 58, height: 58))
        gate.position = position
        gate.zPosition = -8
        addChild(gate)

        let text = SKLabelNode(fontNamed: "Menlo-Bold")
        text.text = label
        text.fontSize = 28
        text.fontColor = .white
        text.verticalAlignmentMode = .center
        text.position = position
        text.zPosition = -7
        addChild(text)
    }

    private func spawnCombatants() {
        var positions = [
            CGPoint(x: 360, y: 106),
            CGPoint(x: 360, y: 614),
            CGPoint(x: 108, y: 360),
            CGPoint(x: 612, y: 360)
        ]
        var orderedLineup = lineup
        shuffle(&orderedLineup)
        shuffle(&positions)

        for (index, fighter) in orderedLineup.prefix(positions.count).enumerated() {
            let texture = SKTexture(imageNamed: fighter.assetName)
            texture.filteringMode = .nearest
            let actor = BattleActor(
                id: fighter.id,
                name: fighter.name,
                moveName: fighter.moveName,
                texture: texture,
                position: positions[index],
                maxHealth: fighter.maxHealth,
                attackPower: fighter.attackPower,
                speed: fighter.movementSpeed,
                attackRange: fighter.attackRange,
                attackInterval: fighter.attackInterval,
                attackColor: fighter.attackColor,
                isPlayer: fighter.id == featuredFighterID
            )
            actor.cooldown = Double(index) * 0.13
            actor.retargetCooldown = 0
            actors.append(actor)
            addChild(actor.root)
        }
    }

    private func shuffle<Value>(_ values: inout [Value]) {
        guard values.count > 1 else { return }
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            values.swapAt(index, random.int(in: 0...index))
        }
    }

    private func flashArena(color: UIColor) {
        let flash = SKSpriteNode(color: color, size: size)
        flash.anchorPoint = .zero
        flash.alpha = 0.26
        flash.zPosition = 55
        addChild(flash)
        flash.run(
            .sequence([
                .fadeOut(withDuration: 0.32),
                .removeFromParent()
            ])
        )
    }

    private func publishTelemetry(force: Bool = false) {
        let seconds = max(Int(ceil(matchDuration - elapsed)), 0)
        guard force || seconds != lastPublishedSecond else { return }
        lastPublishedSecond = seconds
        onTelemetry?(
            BattlePreviewTelemetry(
                phase: phase,
                secondsRemaining: seconds,
                combatantsRemaining: actors.filter(\.isAlive).count,
                event: lastEvent,
                winner: winner,
                winnerID: winnerID
            )
        )
    }
}

private final class BattleActor {
    let id: String
    let name: String
    let moveName: String
    let root = SKNode()
    let sprite: SKSpriteNode
    let maxHealth: CGFloat
    let attackPower: CGFloat
    let speed: CGFloat
    let attackRange: CGFloat
    let attackInterval: TimeInterval
    let attackColor: UIColor
    let isPlayer: Bool

    var health: CGFloat
    var cooldown: TimeInterval = 0
    var retargetCooldown: TimeInterval = 0
    weak var target: BattleActor?
    var wasEliminated = false

    private let healthFill: SKSpriteNode
    private let spriteScale: CGFloat

    var isAlive: Bool {
        health > 0 && !wasEliminated
    }

    var healthFraction: CGFloat {
        guard maxHealth > 0 else { return 0 }
        return max(min(health / maxHealth, 1), 0)
    }

    init(
        id: String,
        name: String,
        moveName: String,
        texture: SKTexture,
        position: CGPoint,
        maxHealth: CGFloat,
        attackPower: CGFloat,
        speed: CGFloat,
        attackRange: CGFloat,
        attackInterval: TimeInterval,
        attackColor: UIColor,
        isPlayer: Bool
    ) {
        self.id = id
        self.name = name
        self.moveName = moveName
        self.maxHealth = maxHealth
        self.health = maxHealth
        self.attackPower = attackPower
        self.speed = speed
        self.attackRange = attackRange
        self.attackInterval = attackInterval
        self.attackColor = attackColor
        self.isPlayer = isPlayer

        sprite = SKSpriteNode(texture: texture)
        sprite.size = isPlayer
            ? CGSize(width: 104, height: 104)
            : CGSize(width: 82, height: 82)
        spriteScale = 1

        let healthWidth: CGFloat = isPlayer ? 92 : 76
        let healthBackground = SKSpriteNode(
            color: UIColor.black.withAlphaComponent(0.82),
            size: CGSize(width: healthWidth + 6, height: 12)
        )
        healthBackground.position = CGPoint(x: 0, y: isPlayer ? 63 : 53)
        healthBackground.zPosition = 8

        healthFill = SKSpriteNode(
            color: isPlayer
                ? UIColor(red: 0.32, green: 0.96, blue: 0.72, alpha: 1)
                : UIColor(red: 0.98, green: 0.37, blue: 0.31, alpha: 1),
            size: CGSize(width: healthWidth, height: 6)
        )
        healthFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        healthFill.position = CGPoint(x: -healthWidth / 2, y: healthBackground.position.y)
        healthFill.zPosition = 9

        let nameLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        nameLabel.text = name.uppercased()
        nameLabel.fontSize = isPlayer ? 12 : 10
        nameLabel.fontColor = .white
        nameLabel.position = CGPoint(x: 0, y: healthBackground.position.y + 10)
        nameLabel.zPosition = 9

        root.position = position
        root.zPosition = isPlayer ? 12 : 10
        root.addChild(sprite)
        root.addChild(healthBackground)
        root.addChild(healthFill)
        root.addChild(nameLabel)
    }

    func face(direction: CGPoint) {
        guard abs(direction.x) > 1 else { return }
        sprite.xScale = direction.x < 0 ? -spriteScale : spriteScale
    }

    func punch() {
        let facing = sprite.xScale < 0 ? -spriteScale : spriteScale
        sprite.removeAction(forKey: "attack")
        sprite.run(
            .sequence([
                .group([
                    .scaleX(to: facing * 1.14, duration: 0.07),
                    .scaleY(to: spriteScale * 1.14, duration: 0.07)
                ]),
                .group([
                    .scaleX(to: facing, duration: 0.12),
                    .scaleY(to: spriteScale, duration: 0.12)
                ])
            ]),
            withKey: "attack"
        )
    }

    func receive(damage: CGFloat) {
        health = max(health - max(damage, 0), 0)
        let fullWidth: CGFloat = isPlayer ? 92 : 76
        healthFill.size.width = fullWidth * healthFraction
    }

    func flash(color: UIColor) {
        sprite.color = color
        sprite.colorBlendFactor = 0.86
        sprite.removeAction(forKey: "hit")
        sprite.run(
            .sequence([
                .wait(forDuration: 0.06),
                .run { [weak sprite] in
                    sprite?.colorBlendFactor = 0
                }
            ]),
            withKey: "hit"
        )
    }
}

private struct BattleSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xA5A5_A5A5_A5A5_A5A5 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func unitDouble() -> Double {
        Double(next()) / Double(UInt64.max)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        let count = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % count)
    }
}

private extension CGPoint {
    static func + (left: CGPoint, right: CGPoint) -> CGPoint {
        CGPoint(x: left.x + right.x, y: left.y + right.y)
    }

    static func - (left: CGPoint, right: CGPoint) -> CGPoint {
        CGPoint(x: left.x - right.x, y: left.y - right.y)
    }

    static func * (point: CGPoint, scalar: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scalar, y: point.y * scalar)
    }

    static func / (point: CGPoint, scalar: CGFloat) -> CGPoint {
        CGPoint(x: point.x / scalar, y: point.y / scalar)
    }

    var squaredLength: CGFloat {
        x * x + y * y
    }

    var length: CGFloat {
        sqrt(squaredLength)
    }
}
