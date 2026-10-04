#!/usr/bin/env python3
"""Run production progression/selection/credit logic on macOS, without Simulator."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
store = (root/'Nanobeasts/Models/AppStore.swift').read_text()
def member(marker):
    start = store.index(marker)
    opening = store.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (store[end] == '{') - (store[end] == '}')
        end += 1
    return store[start:end].replace('private ', '', 1)
markers = ['var currentFamily:', 'var currentStage:', 'var currentTarget:', 'var hatchProgressSteps:',
           'var workoutEvolutionProgress:', 'var workoutMilestoneEvent:', 'var workoutCompanionStage:',
           'var workoutCompanionProgress:', 'func applyProgress(', 'func advanceStage(',
           'func chooseNextEgg(', 'func acknowledgeLifecycleEvent(',
           'func creditRecordedWorkoutSteps(', 'func creditProgressionForToday(']
logic = '\n'.join(member(m) for m in markers)
state = member('private struct PersistedState:')
assert 'bankedProgressionSteps: bankedProgressionSteps,' in store
assert 'bankedProgressionSteps = max(restored.bankedProgressionSteps ?? 0, 0)' in store
harness = '''
enum DistanceUnitPreference: String, Codable { case miles }
''' + state + '''
final class ProgressionHarness {
    let catalog = CreatureCatalog(families: [CreatureCatalog.fallback.families[0],
        CreatureFamily(id: "next", name: "Next", stages: (0...2).map {
            CreatureStage(familyID: "next", name: "Stage \\($0)", imageKey: "next-\\($0)", stage: $0, types: [], description: "")
        })])
    var familyIndex = 0
    var stageIndex = 0
    var progressionSteps = 0
    var bankedProgressionSteps = 0
    var discoveredStageIDs = Set<String>()
    var awaitingEggSelection = false
    var progressionCreditHistory: [DailyStepRecord] = []
    var pendingLifecycleEvents: [CreatureDiscoveryEvent] = []
    var discoveryEvents: [CreatureDiscoveryEvent] = []
    var testingProgressionPreviewSteps = 0
    var testingProgressionCreditSteps = 0
    var evolutionEventID = UUID()
    var stepSyncFromHatchProgress = 0.0
    var onboardingCompleted = true
    var isPremium = true
    var journeyStartedAt: Date? = Calendar.current.startOfDay(for: Date())
    var todaySteps = 0
    func persist() {}
    func persistDiscoveryEvents() {}
''' + logic + '\n}\n'
checks = r'''
var checkCount = 0
func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
    checkCount += 1
}
let h = ProgressionHarness()
h.applyProgress(249)
expect(h.currentStage.isEgg && h.pendingLifecycleEvents.isEmpty, "No early hatch")
h.applyProgress(1)
let hatch = h.pendingLifecycleEvents[0]
expect(hatch.kind == .hatch && h.currentStage.stage == 1, "Threshold queues one hatch")
expect(h.workoutCompanionStage.isEgg && h.workoutCompanionProgress.fraction == 1, "No evolved-artwork spoiler before reveal")
h.acknowledgeLifecycleEvent(hatch.id)
expect(h.workoutCompanionStage.stage == 1 && h.workoutCompanionProgress.steps == 0, "Completion returns to next stage progress")
h.applyProgress(530)
let maturity = h.pendingLifecycleEvents[0]
expect(h.awaitingEggSelection && h.bankedProgressionSteps == 30, "Threshold remainder is banked")
h.applyProgress(70)
expect(h.bankedProgressionSteps == 100 && h.pendingLifecycleEvents.count == 1, "Walking while mature banks additional steps, never duplicate maturity")
expect(h.workoutCompanionProgress.bankedSteps == 100, "Watch receives saved steps")
expect(!h.chooseNextEgg(h.currentStage) && h.bankedProgressionSteps == 100, "Invalid selection cannot consume bank")
let nextEgg = h.catalog.families[1].stages[0]
expect(h.chooseNextEgg(nextEgg), "Valid egg selection")
expect(h.bankedProgressionSteps == 0 && h.progressionSteps == 100 && !h.awaitingEggSelection, "Bank released exactly once")
expect(!h.pendingLifecycleEvents.contains(where: { $0.id == maturity.id }), "Selection consumes its original maturity atomically")
expect(!h.chooseNextEgg(nextEgg) && h.progressionSteps == 100, "Double confirmation cannot release twice")
// Large saved balance crosses a whole new lineage, retaining the next remainder.
let full = ProgressionHarness()
full.applyProgress(750 + 16000 + 123)
let oldMaturity = full.pendingLifecycleEvents.first(where: { $0.kind == .maturity })!
expect(full.chooseNextEgg(full.catalog.families[1].stages[0]), "Large bank can be assigned")
expect(full.awaitingEggSelection && full.bankedProgressionSteps == 123, "Excess survives a second maturity")
expect(!full.pendingLifecycleEvents.contains(where: { $0.id == oldMaturity.id }) && full.pendingLifecycleEvents.filter { $0.kind == .maturity }.count == 1, "New maturity is distinct from completed selection")
// Production persisted schema supports old installs and retains pending work.
var persisted = PersistedState()
persisted.bankedProgressionSteps = full.bankedProgressionSteps
persisted.pendingLifecycleEvents = full.pendingLifecycleEvents
let data = try JSONEncoder().encode(persisted)
let restored = try JSONDecoder().decode(PersistedState.self, from: data)
expect(restored.bankedProgressionSteps == 123 && restored.pendingLifecycleEvents == full.pendingLifecycleEvents, "Bank and event queue survive persistence")
var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
legacy.removeValue(forKey: "bankedProgressionSteps")
let old = try JSONDecoder().decode(PersistedState.self, from: JSONSerialization.data(withJSONObject: legacy))
expect(old.bankedProgressionSteps == nil, "Legacy installs decode without bank field")
// Recording-first, Health-first, repeated/delayed snapshots and access boundaries.
let live = ProgressionHarness()
live.familyIndex = 1
live.todaySteps = 1000
live.creditProgressionForToday()
let anchor = WorkoutEvolutionAnchor(totalCreditedSteps: live.workoutEvolutionProgress.totalCreditedSteps)
let start = Date()
live.creditRecordedWorkoutSteps(200, anchor: anchor, startedAt: start)
expect(live.progressionSteps == 1200, "Live recording advances progression before Health sync")
live.creditRecordedWorkoutSteps(200, anchor: anchor, startedAt: start)
live.creditRecordedWorkoutSteps(100, anchor: anchor, startedAt: start)
expect(live.progressionSteps == 1200, "Duplicate and delayed lower Watch counts ignored")
live.todaySteps = 1200
live.creditProgressionForToday()
expect(live.progressionSteps == 1200, "Later Health delivery does not double live credits")
live.todaySteps = 1350
live.creditProgressionForToday()
live.creditRecordedWorkoutSteps(350, anchor: anchor, startedAt: start)
expect(live.progressionSteps == 1350, "Health-first delivery does not double subsequent recording")
live.creditRecordedWorkoutSteps(2000, anchor: anchor, startedAt: start)
expect(live.currentStage.stage == 1 && live.pendingLifecycleEvents.count == 1, "Live steps reach and queue a hatch")
live.creditRecordedWorkoutSteps(2001, anchor: anchor, startedAt: start)
expect(live.progressionSteps == 1 && live.workoutCompanionStage.isEgg, "Walk continues earning behind optional celebration")
live.acknowledgeLifecycleEvent(live.pendingLifecycleEvents[0].id)
expect(live.workoutCompanionProgress.steps == 1, "Return shows live next-stage progress")
let before = live.workoutEvolutionProgress.totalCreditedSteps
live.creditRecordedWorkoutSteps(9000, anchor: nil, startedAt: start)
live.creditRecordedWorkoutSteps(-100, anchor: anchor, startedAt: start)
live.creditRecordedWorkoutSteps(9000, anchor: anchor, startedAt: start.addingTimeInterval(-86400))
live.creditRecordedWorkoutSteps(9000, anchor: anchor, startedAt: start, observedAt: Date().addingTimeInterval(3600))
expect(live.workoutEvolutionProgress.totalCreditedSteps == before, "Missing anchor, invalid or historical snapshots cannot invent credits")
live.isPremium = false
live.creditRecordedWorkoutSteps(9000, anchor: anchor, startedAt: start)
expect(live.workoutEvolutionProgress.totalCreditedSteps == before, "No new live rewards without access")
let payload = try JSONEncoder().encode(full.workoutCompanionProgress)
let decoded = try JSONDecoder().decode(WorkoutEvolutionProgress.self, from: payload)
expect(decoded == full.workoutCompanionProgress, "Ready state survives Watch messaging")
print("PASS: \(checkCount) production workout milestone checks; persistence, migration, bank release, queued reveals and live/Health reconciliation")
'''
with tempfile.TemporaryDirectory(prefix='nano-milestone-checks-') as temp:
    temp=Path(temp)
    (temp/'main.swift').write_text('import Foundation\n'+harness+checks)
    subprocess.run(['xcrun','swiftc','-module-cache-path','/tmp/nano-workout-swiftcache',
        str(root/'Nanobeasts/Models/CreatureModels.swift'), str(root/'NanobeastsShared/WatchWorkoutMessage.swift'),
        str(temp/'main.swift'),'-o',str(temp/'checks')],check=True)
    subprocess.run([str(temp/'checks')],check=True)
