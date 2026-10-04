#!/usr/bin/env python3
"""Exercise production workout progress without Simulator or writing Health data."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
s=(root/'NanobeastsShared/WatchWorkoutMessage.swift').read_text()
checks='''
let anchor = WorkoutEvolutionAnchor(totalCreditedSteps: 10_000)
func progress(_ steps: Int = 1_000, _ credited: Int = 10_000, target: Int = 5_000, stage: String = "first", milestone: WorkoutEvolutionProgress.Milestone = .evolve, allowed: Bool = true) -> WorkoutEvolutionProgress {
    WorkoutEvolutionProgress(stageID: stage, steps: steps, target: target, totalCreditedSteps: credited, milestone: milestone, allowsProgress: allowed)
}
func expect(_ value: Bool, _ message: String) { precondition(value, message) }
expect(progress().duringWorkout(steps: 500, anchor: anchor).steps == 1500, "live steps")
expect(progress(1300, 10300).duringWorkout(steps: 500, anchor: anchor).steps == 1500, "partly credited steps are not doubled")
expect(progress(1500, 10500).duringWorkout(steps: 500, anchor: anchor).steps == 1500, "fully credited steps are not doubled")
expect(progress(1700, 10700).duringWorkout(steps: 500, anchor: anchor).steps == 1700, "other Health steps stay authoritative")
expect(progress().duringWorkout(steps: 6000, anchor: anchor).fraction == 1, "milestone clamps until authoritative evolution")
expect(progress(200, 14200, target: 7000, stage: "second").duringWorkout(steps: 4400, anchor: anchor).steps == 400, "evolution carry-over counts only uncredited steps")
expect(progress(1, 15000, target: 1, milestone: .complete).duringWorkout(steps: 9000, anchor: anchor).steps == 1, "maturity remains complete")
expect(progress(500, 10000, milestone: .hatch).caption == "4,500 to hatch", "egg label")
expect(progress(5000).caption == "Ready to evolve", "ready label")
expect(progress(5000, milestone: .mature).caption == "Ready to mature", "maturity label")
expect(progress().duringWorkout(steps: -5, anchor: anchor).steps == 1000, "negative session count")
expect(progress(allowed: false).duringWorkout(steps: 500, anchor: anchor).steps == 1000, "locked access earns no projected progress")
expect(progress().duringWorkout(steps: 500, anchor: nil).steps == 1000, "legacy sessions do not invent an anchor")
let resumed = WorkoutEvolutionAnchor(totalCreditedSteps: 10300, workoutSteps: 500)
expect(progress(1300, 10300).duringWorkout(steps: 700, anchor: resumed).steps == 1500, "late connection counts subsequent steps only")
let data = try JSONEncoder().encode(anchor)
let decoded = try JSONDecoder().decode(WorkoutEvolutionAnchor.self, from: data)
expect(decoded.totalCreditedSteps == 10000 && decoded.workoutSteps == 0, "anchor survives recovery")
let original = progress()
_ = original.duringWorkout(steps: 7000, anchor: anchor)
expect(original.steps == 1000, "projection never mutates the ledger")
let oldJSON = "{\\"stageID\\":\\"first\\",\\"name\\":\\"Glitchlet\\",\\"updatedAt\\":0}"
let old = try JSONDecoder().decode(WatchCompanionArtwork.self, from: Data(oldJSON.utf8))
expect(old.evolution == nil, "old artwork payload still decodes")
print("PASS: 16 workout evolution checks, including Health reconciliation, stage changes, recovery, and legacy payloads")
'''
source=Path('/tmp/workout-evolution-main.swift');source.write_text(s+checks)
subprocess.run(['xcrun','swiftc','-module-cache-path','/tmp/nano-workout-swiftcache',str(source),'-o','/tmp/nano-workout-evolution-checks'],check=True)
subprocess.run(['/tmp/nano-workout-evolution-checks'],check=True)
