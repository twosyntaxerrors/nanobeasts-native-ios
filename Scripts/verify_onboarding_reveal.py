#!/usr/bin/env python3
"""Run the production finite animation driver, including cancellation and Reduce Motion."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
checks = r'''
@main struct RevealChecks {
    @MainActor static func main() async {
        var samples: [TimeInterval] = []
        await WalkingPlanReveal.play(reduceMotion: false) { samples.append($0) }
        precondition(samples.first == 0 && samples.last == WalkingPlanReveal.duration)
        precondition(samples.count > 20 && samples.contains { $0 > 1 && $0 < 3 })
        precondition(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        let final = WalkingPlanReveal(elapsed: samples.last!)
        precondition(final.total(dailySteps: 5500) == 165000 && final.day == 30)
        var reduced: [TimeInterval] = []
        await WalkingPlanReveal.play(reduceMotion: true) { reduced.append($0) }
        precondition(reduced == [WalkingPlanReveal.duration])
        var cancelled: [TimeInterval] = []
        let task = Task { @MainActor in
            await WalkingPlanReveal.play(reduceMotion: false) { cancelled.append($0) }
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await task.value
        precondition(cancelled.first == 0 && cancelled.last == WalkingPlanReveal.duration)
        var preparationSamples: [TimeInterval] = []
        let finished = await WalkingPlanPreparation.play(from: 0, reduceMotion: false) { preparationSamples.append($0) }
        precondition(finished && preparationSamples.first! < 0.1 && preparationSamples.last == WalkingPlanPreparation.duration)
        precondition(preparationSamples.count > 30 && zip(preparationSamples, preparationSamples.dropFirst()).allSatisfy { $0 <= $1 })
        var stopped: [TimeInterval] = []
        let preparing = Task { @MainActor in
            await WalkingPlanPreparation.play(from: 0, reduceMotion: false) { stopped.append($0) }
        }
        try? await Task.sleep(for: .milliseconds(100))
        preparing.cancel()
        let didFinish = await preparing.value
        precondition(!didFinish && stopped.last! < WalkingPlanPreparation.duration)
        var resumed: [TimeInterval] = []
        let didResume = await WalkingPlanPreparation.play(from: 4.0, reduceMotion: false) { resumed.append($0) }
        precondition(didResume && resumed.first! >= 4 && resumed.last == WalkingPlanPreparation.duration)
        var preparationReduced: [TimeInterval] = []
        let reducedFinished = await WalkingPlanPreparation.play(from: 0, reduceMotion: true) { preparationReduced.append($0) }
        precondition(reducedFinished && preparationReduced == [WalkingPlanPreparation.duration])
        print("PASS: preparation completes, resumes, and never navigates after cancellation; reduced motion skips movement.\nPASS: production animation advances and finishes; Reduce Motion and cancellation settle on final totals.")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='nano-reveal-') as temp:
    temp=Path(temp)
    source=temp/'RevealChecks.swift'
    source.write_text((root/'Nanobeasts/Features/Onboarding/OnboardingJourney.swift').read_text()+'\n'+checks)
    subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(temp/'ModuleCache'),str(source),'-o',str(temp/'checks')],check=True)
    subprocess.run([str(temp/'checks')],check=True)
