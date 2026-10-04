#!/usr/bin/env python3
"""Check challenge pacing against the real catalog and unchanged game thresholds."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
checks = r'''
import Foundation
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let catalog = try JSONDecoder().decode(CreatureCatalog.self, from: Data(contentsOf: url))
// Independent regression of the previous shipping threshold policy.
for index in 0..<catalog.families.count {
    for stage in -1...5 {
        let base = 10000 + 1500 * max(index - 1, 0)
        let weights = [0.3, 0.55, 0.75, 1.0]
        let original = index == 0 ? (stage == 0 ? 250 : 500)
            : min(15000, max(500, Int((Double(base) * weights[min(3, max(0, stage))] / 100).rounded()) * 100))
        precondition(CreatureProgressionRules.steps(familyIndex: index, stage: stage) == original)
    }
}
let average = catalog.averageStepsPerEvolution!
precondition(average == 28234, "Includes full lifecycle costs across the current evolving families")
precondition(CreatureCatalog.fallback.averageStepsPerEvolution == nil, "A tutorial-only fallback cannot invent evolutions")
// One evolution requires egg, initial creature, and final maturity walking.
let tiny = CreatureCatalog(families: [CreatureCatalog.fallback.families[0],
    CreatureFamily(id: "sample", name: "Sample", stages: (0...2).map { CreatureStage(familyID: "sample", name: "Stage", imageKey: "sample", stage: $0, types: [], description: "") })])
precondition(tiny.averageStepsPerEvolution == 16000, "Hatching and maturity cost steps but do not inflate the evolution count")
for (daily, days, count) in [(3500, 9, 3), (5500, 6, 5), (8000, 4, 7), (11500, 3, 10), (15000, 2, 15), (20000, 2, 15)] {
    let challenge = WalkingEvolutionChallenge(dailyTarget: daily, averageStepsPerEvolution: average)
    precondition(challenge.daysPerEvolution == days && challenge.evolutionsIn30Days == count)
    precondition(challenge.evolutionsIn30Days * average <= daily * 30, "No challenge exceeds its thirty-day step budget")
}
print("PASS: all 217 progression thresholds unchanged; actual catalog lifecycle/evolution arithmetic; conservative rounding; six target cadences including every other day for heavy walkers.")
'''
with tempfile.TemporaryDirectory(prefix='nano-evolution-checks-') as temp:
    temp=Path(temp)
    (temp/'main.swift').write_text(checks)
    subprocess.run(['xcrun','swiftc','-module-cache-path',str(temp/'cache'),
        str(root/'Nanobeasts/Models/CreatureModels.swift'),
        str(root/'Nanobeasts/Features/Onboarding/OnboardingJourney.swift'),
        str(temp/'main.swift'),'-o',str(temp/'checks')],check=True)
    subprocess.run([str(temp/'checks'), str(root/'Nanobeasts/Resources/creatures-by-family.json')],check=True)
