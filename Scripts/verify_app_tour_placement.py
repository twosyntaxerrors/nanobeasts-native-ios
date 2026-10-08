#!/usr/bin/env python3
"""Exercise production spotlight placement without launching Simulator."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
s = (root/'Nanobeasts/App/AppRootView.swift').read_text()
model = s[s.index('enum AppTourTarget:'):s.index('struct AppTourAnchors:')] + s[s.index('struct AppTourPlacement {'):s.index('private struct AppTourScrim:')]
harness = r'''
import Foundation
import CoreGraphics
MODEL
var count = 0
func check(_ viewport: CGSize, _ targets: [CGRect], _ preferredHeight: CGFloat, avoiding: [CGRect] = []) {
    let layout = AppTourPlacement(viewport: viewport, targets: targets, preferredHeight: preferredHeight, avoiding: avoiding)
    precondition(layout.card.width == viewport.width - 32)
    precondition(layout.card.minX >= 0 && layout.card.maxX <= viewport.width)
    precondition(layout.card.minY >= 0 && layout.card.maxY <= viewport.height)
    precondition(layout.card.height > 0 && layout.card.height <= preferredHeight)
    for target in targets + avoiding { precondition(!layout.card.intersects(target), "Tooltip covered its component or tab") }
    precondition(layout.target == targets.reduce(CGRect.null) { $0.union($1) }, "Pointer must stay on the component")
    let above = max(0, layout.target.minY - 30)
    let below = max(0, viewport.height - layout.target.maxY - 30)
    if avoiding.isEmpty {
        precondition(layout.card.height == min(preferredHeight, max(above, below)) || below >= preferredHeight)
    }
    count += 1
}
for width: CGFloat in [320, 375, 390, 430] {
    for height: CGFloat in [500, 568, 667, 763, 844] {
        for cardHeight: CGFloat in [218, 330] {
            for y: CGFloat in stride(from: 20, through: height - 80, by: 20) {
                check(CGSize(width: width, height: height), [CGRect(x: 20, y: y, width: width - 40, height: 40)], cardHeight)
            }
            check(CGSize(width: width, height: height), [CGRect(x: 30, y: 150, width: width - 60, height: 230)], cardHeight)
            check(CGSize(width: width, height: height), [CGRect(x: width - 95, y: 20, width: 75, height: 44), CGRect(x: 20, y: 110, width: width - 40, height: 70)], cardHeight)
            check(CGSize(width: width, height: height), [CGRect(x: 20, y: height - 250, width: width - 40, height: 90), CGRect(x: 20, y: height - 140, width: width - 40, height: 110)], cardHeight)
        }
    }
}
// Replay tab tooltips target the actual tab bounds, preserving the other tour highlights.
precondition(AppTourTarget.stats.navigationTabTarget == .statsTab)
precondition(AppTourTarget.dex.navigationTabTarget == .dexTab)
precondition(AppTourTarget.settingsGoal.navigationTabTarget == .settingsTab)
precondition(AppTourTarget.workout.navigationTabTarget == nil)
precondition(AppTourTarget.expBadge.navigationTabTarget == nil)
for height: CGFloat in [500, 568, 667, 763, 844] {
    for x: CGFloat in [20, 105, 205, 290] {
        check(CGSize(width: 390, height: height), [CGRect(x: x, y: height - 70, width: 70, height: 62)], 218)
        check(CGSize(width: 390, height: height), [CGRect(x: x, y: height - 86, width: 70, height: 78)], 330)
    }
}
// A top calendar plus bottom tab leaves the useful space BETWEEN the two highlights.
for width: CGFloat in [320, 375, 390, 430] {
    for height: CGFloat in [568, 667, 763, 844] {
        for preferred: CGFloat in [218, 330] {
            let tab = CGRect(x: width / 4, y: height - 70, width: 65, height: 62)
            for componentHeight: CGFloat in [180, 260, 330] {
                check(CGSize(width: width, height: height),
                      [CGRect(x: 18, y: 4, width: width - 36, height: componentHeight)], preferred, avoiding: [tab])
            }
            // Lower component: place the tooltip above it, still clear of both highlights.
            check(CGSize(width: width, height: height),
                  [CGRect(x: 18, y: height - 280, width: width - 36, height: 150)], preferred, avoiding: [tab])
        }
    }
}
let calendar = CGRect(x: 18, y: 4, width: 354, height: 360)
let statsTab = CGRect(x: 90, y: 693, width: 64, height: 62)
let dual = AppTourPlacement(viewport: CGSize(width: 390, height: 763), targets: [calendar], preferredHeight: 218, avoiding: [statsTab])
precondition(dual.card.height == 218 && dual.card.minY > calendar.maxY && dual.card.maxY < statsTab.minY)
precondition(dual.target == calendar, "The pointer should not aim at the union of tab and calendar")
// The reported iPhone layout: the badge is near the middle, not a tab-bar target.
let badge = CGRect(x: 147, y: 402, width: 96, height: 28)
let reported = AppTourPlacement(viewport: CGSize(width: 390, height: 763), targets: [badge], preferredHeight: 218)
precondition(reported.card.minY >= badge.maxY + 14)
let loading = AppTourPlacement(viewport: CGSize(width: 390, height: 763), targets: [], preferredHeight: 218)
precondition(loading.card == .zero)
print("Passed \(count) spotlight placements plus screenshot-badge and missing-anchor regressions.")
'''
with tempfile.TemporaryDirectory(prefix='nano-tour-placement-') as temp:
    swift=Path(temp)/'main.swift'
    swift.write_text(harness.replace('MODEL', model))
    subprocess.run(['swift','-module-cache-path',str(Path(temp)/'cache'),str(swift)],check=True)
# Targets must come from rendered bounds, not guessed device coordinates.
assert 'anchorPreference(key: AppTourAnchors.self' in s
assert 'frames: anchors.mapValues { geometry[$0] }' in s
assert 'indicatorOffset' not in s
assert 'targets: [.ring]' in s and 'targets: [.expBadge]' in s
assert 'contentShape(AppTourScrim(holes: ready ? holes : []), eoFill: true)' in s
for file, targets in {
    'Features/Lab/LabView.swift': ['ring', 'expBadge', 'streak', 'week', 'todaySteps', 'metrics'],
    'Features/Stats/StatsView.swift': ['stats'],
    'Features/Settings/SettingsView.swift': ['settingsGoal'],
}.items():
    content=(root/'Nanobeasts'/file).read_text()
    for target in targets: assert f'.appTourTarget(.{target})' in content, target
assert '.appTourTarget(.workout)' in s
for tab in ['statsTab', 'dexTab', 'settingsTab']:
    assert f'.appTourTarget(.{tab})' in s
assert 'highlightsNavigationTabs: store.isOnboardingReplay' in s
assert 'pages[step].targets.compactMap(\.navigationTabTarget)' in s
assert 'let componentHoles = pages[step].targets.compactMap' in s
assert 'let holes = componentHoles + navigationHoles' in s
assert 'targets: componentHoles' in s and 'avoiding: navigationHoles' in s
assert 'intersection(contentViewport)' in s
assert 'pages[step].targets.map { $0.navigationTabTarget ?? $0 }' not in s
dex=(root/'Nanobeasts/Features/Dex/DexView.swift').read_text()
assert '.appTourTarget(family.id == tourAnchorID ? .dex : nil)' in dex
assert '.appTourTarget(stage.id == tourAnchorID ? .dex : nil)' in dex
print('Shared tour anchors, EXP interaction, and screen-target wiring checks passed.')
