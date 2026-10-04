#!/usr/bin/env python3
"""Run the production replay-data adapter against fresh and non-replay profiles."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Nanobeasts/Models/AppStore.swift').read_text()
start = source.index('    func updateOnboardingReplay(')
opening = source.index('{', start)
depth = 1
end = opening + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
method = source[start:end]
cap_start = source.index('    var freeProgressionCapReached: Bool {')
cap_end = source.index('\n    }', cap_start) + len('\n    }')
method += '\n' + source[cap_start:cap_end]
fixture = r'''
import Foundation
struct Stage { let id: String; let stage: Int }
struct Family { let stages: [Stage] }
struct Catalog { let families = [
    Family(stages: [Stage(id: "egg", stage: 0), Stage(id: "creature", stage: 1)]),
    Family(stages: [Stage(id: "next-egg", stage: 0), Stage(id: "next-creature", stage: 1), Stage(id: "evolved", stage: 2)])
] }
struct DailyStepRecord { let day: Date; let steps: Int }
enum CreatureDiscoveryKind { case eggAcquired, hatch, evolution, maturity }
struct CreatureDiscoveryEvent {
    let stage: Stage
    let kind: CreatureDiscoveryKind
    var creatureStage: Stage { stage }
}
enum CreatureProgressionRules {
    static func steps(familyIndex: Int, stage: Int) -> Int { 250 }
}
final class Profile {
    static let freeDailyProgressionCap = 2_500
    var testingProgressionCreditSteps = 0
    var progressionStepsCreditedToday: Int { progressionCreditHistory.first?.steps ?? 0 }
    let isOnboardingReplay: Bool
    let catalog = Catalog()
    var familyIndex = 0, stageIndex = 0, progressionSteps = 0
    var isPremium = false
    var awaitingEggSelection = false
    var dailyHistory: [DailyStepRecord] = []
    var analyticsHistory: [DailyStepRecord] = []
    var progressionCreditHistory: [DailyStepRecord] = []
    var discoveredStageIDs: Set<String> = []
    var discoveryEvents: [CreatureDiscoveryEvent] = []
    var evolutionEventID = UUID(), stepSyncAnimationID = UUID(), badgeEvaluationID = UUID()
    var stepSyncFromTodaySteps = 0, stepSyncFromHatchProgress = 0.0, stepSyncDuration = 0.0
    var displayedTodaySteps: Int { dailyHistory.first?.steps ?? 0 }
    var currentFamily: Family { catalog.families[familyIndex] }
    var currentStage: Stage { currentFamily.stages[stageIndex] }
    var hatchProgress: Double { Double(progressionSteps) / Double(stageIndex == 0 ? 250 : 500) }
    init(replay: Bool) { isOnboardingReplay = replay }
METHOD
}
var count = 0
func expect(_ condition: @autoclosure () -> Bool) { precondition(condition()); count += 1 }
let real = Profile(replay: false)
real.updateOnboardingReplay(steps: 300, revealed: true, purchased: true)
expect(real.displayedTodaySteps == 0)
expect(!real.isPremium && real.stageIndex == 0 && real.discoveryEvents.isEmpty)
let preview = Profile(replay: true)
preview.updateOnboardingReplay(steps: 0, revealed: false, purchased: false)
expect(preview.discoveryEvents.count == 1 && preview.discoveredStageIDs == ["egg"])
for steps in [100, 200, 300] {
    let oldSteps = preview.displayedTodaySteps
    preview.updateOnboardingReplay(steps: steps, revealed: false, purchased: false)
    expect(preview.displayedTodaySteps == steps && preview.analyticsHistory.first?.steps == steps)
    expect(preview.stepSyncFromTodaySteps == oldSteps)
    expect(preview.stageIndex == 0 && preview.discoveryEvents.count == 1 && !preview.isPremium)
}
expect(preview.progressionSteps == 250)
preview.updateOnboardingReplay(steps: 300, revealed: false, purchased: true)
expect(preview.isPremium && preview.stageIndex == 0)
preview.updateOnboardingReplay(steps: 300, revealed: true, purchased: true)
expect(preview.stageIndex == 1 && preview.progressionSteps == 50)
expect(preview.discoveredStageIDs == ["egg", "creature"])
expect(preview.discoveryEvents.count == 2)
preview.updateOnboardingReplay(steps: 300, revealed: true, purchased: true)
expect(preview.discoveryEvents.count == 2)
let fresh = Profile(replay: true)
fresh.updateOnboardingReplay(steps: 0, revealed: false, purchased: false)
expect(fresh.stageIndex == 0 && !fresh.isPremium && fresh.discoveryEvents.count == 1)
expect(real.displayedTodaySteps == 0 && !real.isPremium)

real.updateOnboardingReplay(steps: 8_800, revealed: true, purchased: true, familyIndex: 1, stageIndex: 2, stageSteps: 0)
expect(real.displayedTodaySteps == 0 && !real.isPremium && real.discoveryEvents.isEmpty)
preview.updateOnboardingReplay(steps: 300, revealed: true, purchased: false, familyIndex: 1, stageIndex: 0, stageSteps: 0)
expect(preview.currentStage.id == "next-egg" && preview.progressionSteps == 0 && !preview.isPremium)
expect(preview.discoveredStageIDs == ["egg", "creature", "next-egg"])
preview.updateOnboardingReplay(steps: 3_300, revealed: true, purchased: false, familyIndex: 1, stageIndex: 1, stageSteps: 0)
expect(preview.currentStage.id == "next-creature" && preview.discoveryEvents.count == 4)
preview.updateOnboardingReplay(steps: 8_800, revealed: true, purchased: false, familyIndex: 1, stageIndex: 1, stageSteps: 5_500)
expect(preview.progressionSteps == 5_500 && !preview.discoveredStageIDs.contains("evolved") && !preview.isPremium)
preview.updateOnboardingReplay(steps: 8_800, revealed: true, purchased: true, familyIndex: 1, stageIndex: 1, stageSteps: 5_500)
expect(preview.isPremium && !preview.discoveredStageIDs.contains("evolved"))
preview.updateOnboardingReplay(steps: 8_800, revealed: true, purchased: true, familyIndex: 1, stageIndex: 2, stageSteps: 0)
expect(preview.currentStage.id == "evolved" && preview.discoveryEvents.count == 5 && preview.progressionSteps == 0)
expect(preview.discoveryEvents.last?.kind == .evolution)
preview.updateOnboardingReplay(steps: 8_800, revealed: true, purchased: true, familyIndex: 1, stageIndex: 2, stageSteps: 0)
expect(preview.discoveryEvents.count == 5)
preview.updateOnboardingReplay(steps: 0, revealed: false, purchased: false, familyIndex: 99, stageIndex: 0, stageSteps: 0)
expect(preview.currentStage.id == "evolved" && preview.isPremium)
let mature = Profile(replay: true)
mature.updateOnboardingReplay(steps: 750, revealed: true, purchased: false, stageIndex: 1, stageSteps: 0, tutorialMatured: true)
expect(mature.awaitingEggSelection && mature.currentStage.id == "creature")
expect(mature.discoveryEvents.count == 3 && mature.discoveryEvents.last?.kind == .maturity)
mature.updateOnboardingReplay(steps: 750, revealed: true, purchased: false, stageIndex: 1, stageSteps: 0, tutorialMatured: true)
expect(mature.discoveryEvents.count == 3)
mature.updateOnboardingReplay(steps: 750, revealed: true, purchased: false, familyIndex: 1, stageIndex: 0, stageSteps: 0, tutorialMatured: true)
expect(!mature.awaitingEggSelection && mature.currentStage.id == "next-egg")
expect(mature.discoveryEvents.count == 4 && mature.discoveryEvents.last?.kind == .eggAcquired)
mature.updateOnboardingReplay(steps: 3_750, revealed: true, purchased: false, familyIndex: 1, stageIndex: 1, stageSteps: 0, tutorialMatured: true)
expect(mature.discoveryEvents.count == 5 && mature.discoveryEvents.last?.kind == .hatch)
expect(!mature.isPremium && !mature.discoveredStageIDs.contains("evolved"))
real.updateOnboardingReplay(steps: 750, revealed: true, purchased: false, stageIndex: 1, stageSteps: 0, tutorialMatured: true)
expect(!real.awaitingEggSelection && real.discoveryEvents.isEmpty)
preview.isPremium = false
expect(!preview.freeProgressionCapReached)
real.progressionCreditHistory = [DailyStepRecord(day: Date(), steps: 3_000)]
expect(real.freeProgressionCapReached)
real.isPremium = true
expect(!real.freeProgressionCapReached)
print("Passed \(count) replay-profile checks: steps, fresh history, reveal timing, discovery deduplication, and live-profile guard.")
'''
with tempfile.TemporaryDirectory(prefix='nano-replay-profile-') as temp:
    path = Path(temp) / 'main.swift'
    path.write_text(fixture.replace('METHOD', method))
    subprocess.run(['swift', '-module-cache-path', str(Path(temp) / 'cache'), str(path)], check=True)
