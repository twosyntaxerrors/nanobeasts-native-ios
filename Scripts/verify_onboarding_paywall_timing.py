#!/usr/bin/env python3
"""Exercise the isolated onboarding journey, including abandonment and replay guards."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Nanobeasts/Features/Onboarding/OnboardingReplayView.swift').read_text()
model = source.split('/// Runs the shipping onboarding', 1)[0].replace('import SwiftUI', 'import Foundation')
harness = r'''
var count = 0
func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
    precondition(condition(), description)
    count += 1
}
for timing in [TutorialPaywallJourney.Timing.beforeReveal, .afterReveal] {
    var flow = TutorialPaywallJourney(timing: timing, hatchTarget: 250)
    flow.addSteps(); flow.addSteps()
    expect(flow.steps == 200 && flow.phase == .walking, "Two taps do not hatch")
    flow.addSteps()
    expect(flow.steps == 300 && flow.phase == .charging, "Third tap fills the meter before revealing")
    flow.addSteps()
    expect(flow.steps == 300, "Rapid extra taps cannot trigger duplicate milestones")
    flow.finishCharging()
    if timing == .beforeReveal {
        expect(flow.phase == .revealing && !flow.hasRevealed, "Before variant starts the video before its gate")
        flow.finishReveal()
        expect(!flow.hasRevealed, "Video completion cannot bypass an unpaid gate")
        flow.reachVideoCheckpoint()
        expect(flow.phase == .paywall && !flow.hasRevealed, "The playback checkpoint presents the paywall before the reveal")
        flow.finishReveal()
        expect(!flow.hasRevealed, "A stale reveal callback cannot bypass the gate")
    } else {
        expect(flow.phase == .revealing, "After variant plays the native reveal first")
        flow.finishReveal()
        expect(flow.phase == .paywall && flow.hasRevealed, "After variant waits for the reveal callback")
    }
    let revealedBeforeClose = flow.hasRevealed
    flow.closePaywall()
    expect(flow.phase == .paused && !flow.hasPurchased, "Closing never counts as purchase")
    expect(flow.hasRevealed == revealedBeforeClose && flow.steps == 300, "Closing preserves steps and reveal state")
    flow.purchase(); flow.addSteps(); flow.reachVideoCheckpoint(); flow.finishReveal()
    expect(flow.phase == .paused && !flow.hasPurchased, "Delayed callbacks and extra taps do not resume an abandoned flow")
    flow.resume()
    expect(flow.phase == .paywall, "Resume returns to the same gate")
    flow.purchase()
    expect(flow.hasPurchased, "Simulated purchase unlocks the local journey")
    if timing == .beforeReveal { expect(flow.hasReachedVideoCheckpoint, "Purchase retains the resume checkpoint") }
    if timing == .beforeReveal {
        expect(flow.phase == .revealing && !flow.hasRevealed, "Before purchase goes straight to video")
        flow.finishReveal()
    }
    expect(flow.phase == .complete && flow.hasRevealed, "Both variants end with a revealed companion")
    flow.finishReveal(); flow.finishCharging(); flow.closePaywall(); flow.purchase()
    expect(flow.phase == .complete, "Repeated callbacks do not replay the paywall")
    let reset = TutorialPaywallJourney(timing: timing, hatchTarget: 250)
    expect(reset.steps == 0 && !reset.hasPurchased && !reset.hasRevealed, "Restart clears only preview state")
}

for familyIndex in [1, 12] {
    var flow = TutorialPaywallJourney(timing: .beforeNextEvolution, hatchTarget: 250)
    flow.chooseEgg(familyIndex: familyIndex, hatchTarget: 3_000, evolutionTarget: 5_500)
    expect(flow.familyIndex == 0 && flow.phase == .walking, "Cannot skip the tutorial")
    flow.addSteps(); flow.addSteps(); flow.addSteps()
    flow.finishCharging(); flow.reachVideoCheckpoint()
    expect(flow.phase == .revealing && !flow.hasPurchased, "Tutorial plays without any paywall")
    flow.finishReveal()
    expect(flow.phase == .walking && flow.milestone == .tutorialMaturity && flow.hasRevealed, "Tutorial hatch returns to walking toward maturity")
    expect(flow.stageIndex == 1 && flow.stageSteps == 50 && flow.target == 500, "Tutorial keeps hatch overflow toward its normal maturity target")
    flow.chooseEgg(familyIndex: familyIndex, hatchTarget: 3_000, evolutionTarget: 5_500)
    expect(flow.familyIndex == 0 && flow.phase == .walking, "Cannot choose the next egg before maturity")
    for _ in 0..<4 { flow.addSteps() }
    expect(flow.stageSteps == 450 && flow.phase == .walking && !flow.hasMaturedTutorial, "Tutorial does not mature early")
    flow.addSteps()
    expect(flow.steps == 750 && flow.phase == .charging, "Maturity requires its own walking milestone")
    flow.chooseEgg(familyIndex: familyIndex, hatchTarget: 3_000, evolutionTarget: 5_500)
    expect(flow.familyIndex == 0 && flow.phase == .charging, "Egg selection cannot bypass the maturity presentation")
    flow.finishCharging()
    expect(flow.phase == .choosingEgg && flow.hasMaturedTutorial && !flow.hasPurchased, "Maturity opens the normal next-egg sequence without paywall")
    flow.addSteps(); flow.finishReveal(); flow.purchase()
    expect(flow.steps == 750 && flow.phase == .choosingEgg, "Stale callbacks cannot advance egg selection")
    flow.chooseEgg(familyIndex: familyIndex, hatchTarget: 3_000, evolutionTarget: 5_500)
    expect(flow.phase == .receivingEgg && flow.stageIndex == 0 && flow.stageSteps == 0, "New egg begins at zero")
    flow.addSteps()
    expect(flow.steps == 750, "Cannot walk before egg arrival finishes")
    flow.finishEggArrival()
    flow.addSteps(); flow.addSteps()
    expect(flow.stageSteps == 2_000 && flow.phase == .walking, "Later taps accelerate walking")
    flow.addSteps(); flow.addSteps()
    expect(flow.stageSteps == 3_000 && flow.steps == 3_750 && flow.phase == .charging, "Hatch target clamps and blocks duplicate taps")
    flow.finishCharging(); flow.reachVideoCheckpoint()
    expect(flow.phase == .revealing && !flow.hasPurchased, "Second hatch also plays freely")
    flow.finishReveal()
    expect(flow.phase == .walking && flow.stageIndex == 1 && flow.hasHatchedNextEgg, "Second companion is earned without subscription")
    expect(flow.stageSteps == 0 && flow.target == 5_500, "Evolution starts a fresh milestone")
    for _ in 0..<5 { flow.addSteps() }
    expect(flow.phase == .walking && flow.stageSteps == 5_000, "Paywall does not arrive before evolution target")
    flow.addSteps(); flow.finishCharging()
    expect(flow.phase == .revealing && flow.steps == 9_250 && flow.stageSteps == 5_500, "Evolution milestone starts the prelude and video instead of a paywall")
    expect(!flow.hasReachedVideoCheckpoint && !flow.hasEvolved, "The evolution teaser begins before the gate")
    flow.finishReveal()
    expect(flow.phase == .revealing && !flow.hasEvolved && flow.stageIndex == 1, "Video completion cannot bypass an unpaid evolution gate")
    flow.reachVideoCheckpoint()
    expect(flow.phase == .paywall && flow.hasReachedVideoCheckpoint, "The media checkpoint presents the evolution paywall")
    flow.reachVideoCheckpoint(); flow.finishReveal()
    expect(flow.phase == .paywall && !flow.hasEvolved, "Repeated video callbacks cannot reveal stage two")
    flow.closePaywall()
    let savedSteps = flow.steps
    flow.purchase(); flow.addSteps(); flow.finishReveal(); flow.finishCharging()
    expect(flow.phase == .paused && !flow.hasPurchased && flow.steps == savedSteps, "Closing preserves progress and rejects stale callbacks")
    flow.resume(); flow.purchase()
    expect(flow.phase == .revealing && flow.hasPurchased && !flow.hasEvolved && flow.hasReachedVideoCheckpoint, "Purchase resumes the evolution at its saved video checkpoint")
    flow.reachVideoCheckpoint()
    expect(flow.phase == .revealing, "A paid evolution cannot be gated a second time")
    flow.finishReveal()
    expect(flow.phase == .complete && flow.hasEvolved && flow.stageIndex == 2, "Evolution completes after simulated purchase")
    flow.finishReveal(); flow.addSteps(); flow.closePaywall()
    expect(flow.phase == .complete && flow.steps == savedSteps, "Completed flow remains stable")
    let restarted = TutorialPaywallJourney(timing: .beforeNextEvolution, hatchTarget: 250)
    expect(restarted.familyIndex == 0 && restarted.steps == 0 && !restarted.hasHatchedNextEgg && !restarted.hasMaturedTutorial && !restarted.hasPurchased, "Restart returns to tutorial")
}
print("Passed \(count) onboarding paywall journey checks")
'''
with tempfile.TemporaryDirectory(prefix='nanobeasts-paywall-timing-') as temp:
    swift = Path(temp) / 'main.swift'
    swift.write_text(model + '\n' + harness)
    subprocess.run(['swift', '-module-cache-path', str(Path(temp) / 'module-cache'), str(swift)], check=True)

# The Settings entry must be present in the Release build used on the phone.
preview_paywall = (root / 'Nanobeasts/Features/Paywall/RevenueCatPaywallScreen.swift').read_text()
purchase = preview_paywall.split('private func purchaseSelectedPlan() async {', 1)[1].split('private func restore()', 1)[0]
assert purchase.index('if isPreview {') < purchase.index('Purchases.shared.purchase(')
preview_branch = purchase.split('if isPreview {', 1)[1].split('}', 1)[0]
assert 'onPreviewPurchase?()' in preview_branch and 'return' in preview_branch
# The replay now renders the production tabs with a fresh, non-persisting store.
assert '@Environment(AppStore.self)' not in source
assert '@State private var replayStore = AppStore.makeOnboardingReplay()' in source
assert '.environment(replayStore)' in source
assert '.defaultAppStorage(replayStore.replayPreferences)' in source
assert 'MainTabView(' in source and 'TutorialWalkingPreview' not in source
assert 'previewFinishesAtReveal: timing == .afterReveal' in source
assert 'previewStartsAtDex: true' in source
assert 'showsTour: showsTour, onTourFinished:' in source
health_view = (root / 'Nanobeasts/Components/NanoComponents.swift').read_text()
assert '.presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(330)])' in health_view
assert 'pendingHomeHealth = false' in source.split('private func restart()', 1)[1]
assert '.task(id: pendingHomeHealth)' in source
assert '.safeAreaInset(edge: .top' not in source
assert 'Preview complete' not in source
assert 'journey = TutorialPaywallJourney' in source.split('private func restart()', 1)[1].split('private func start(', 1)[0]
app_store = (root / 'Nanobeasts/Models/AppStore.swift').read_text()
for entry in ['func bootstrap() async {', 'func refreshHealthData() async {',
              'func activateJourneyTracking() async {', 'func refreshSubscriptionStatus(forceRefresh: Bool = false) async {',
              'func applyRevenueCatCustomerInfo(_ customerInfo: CustomerInfo) async {',
              'private func persist() {', 'private func publishWidgetSnapshot() {',
              'private func persistDiscoveryEvents() {']:
    assert entry + '\n        guard !isOnboardingReplay' in app_store, entry
assert 'guard isOnboardingReplay else { return }' in app_store.split('func updateOnboardingReplay', 1)[1].split('private static func', 1)[0]
assert 'if !isOnboardingReplay {\n            OnboardingDraft.clear()' in app_store
root_view = (root / 'Nanobeasts/App/AppRootView.swift').read_text()
assert 'StatsView(historyDefaults: store.isOnboardingReplay ? store.replayPreferences : .standard)' in root_view
assert 'onReplayNameTap: onReplayNameTap' in root_view
# The shipping gate remains unchanged while evaluating the proposed flow.
assert 'OnboardingFlowView(onFinished: showOnboardingPaywall)' in root_view
assert 'case .choosingEgg, .receivingEgg:' in source
assert 'CreatureDiscoveryEvent(stage: creature, kind: .maturity)' in source
assert 'nextEggs: replayEggs, allowsDismissal: false, onChooseEgg: chooseNextEgg' in source
assert 'private var nextEggSelection' not in source
later = source.split('private var laterJourney:', 1)[1].split('private func chooseNextEgg', 1)[0]
assert 'playsPrelude: !journey.hasReachedVideoCheckpoint' in later
assert 'previewVideoPauseTime: journey.milestone == .firstEvolution && !journey.hasPurchased' in later
assert 'onPreviewVideoPause: { journey.reachVideoCheckpoint() }' in later
assert '? TutorialPaywallJourney.evolutionVideoCheckpoint : 0' in later
assert '"Start Walking"' in root_view and '"Start exploring"' not in root_view
print('Preview purchase, native maturity sequence, and progress isolation checks passed')
