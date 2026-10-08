#!/usr/bin/env python3
"""Exercise production reward gates and persistent badge acknowledgement policy."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
checks = r'''
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    checks += 1
}
let ready = RewardPresentationState(hasAccess: true, isHome: true, isActive: true,
    isLoading: false, showsSplash: false, showsTour: false, showsWorkout: false,
    showsSheet: false, homeIsBusy: false, showsPaywall: false,
    showsEvolution: false, showsBadge: false)
check(ready.isReady, "Home can present an earned badge")
let blockers: [(WritableKeyPath<RewardPresentationState, Bool>, Bool)] = [
    (\.hasAccess, false), (\.isHome, false), (\.isActive, false),
    (\.isLoading, true), (\.showsSplash, true), (\.showsTour, true),
    (\.showsWorkout, true), (\.showsSheet, true), (\.homeIsBusy, true),
    (\.showsPaywall, true), (\.showsEvolution, true), (\.showsBadge, true)
]
let now = Date(timeIntervalSince1970: 1_800_000_000)
let five = BadgeAwardDelivery.Candidate(id: "streak-5", completedAt: now,
    unlocked: true, acknowledged: false)
for (key, value) in blockers {
    var state = ready
    state[keyPath: key] = value
    check(!state.isReady, "No celebration behind another experience or in background")
    check(BadgeAwardDelivery.pendingIDs([five]) == ["streak-5"], "Blocking cannot consume the award")
    state[keyPath: key] = !value
    check(state.isReady, "Returning to Home after dismissing a blocker enables delivery")
}
let pending: [BadgeAwardDelivery.Candidate] = [
    five, five,
    .init(id: "streak-3", completedAt: now.addingTimeInterval(-86400), unlocked: true, acknowledged: false),
    .init(id: "streak-7", completedAt: nil, unlocked: false, acknowledged: false),
    .init(id: "already-seen", completedAt: now, unlocked: true, acknowledged: true),
    .init(id: "undated", completedAt: nil, unlocked: true, acknowledged: false)
]
check(BadgeAwardDelivery.pendingIDs(pending) == ["streak-5", "streak-3", "undated"],
      "Recent awards first; omit locked, acknowledged, and duplicate IDs")
check(BadgeAwardDelivery.pendingIDs([five]) == ["streak-5"], "Unacknowledged award survives another evaluation")
let acknowledged = BadgeAwardDelivery.Candidate(id: five.id, completedAt: five.completedAt,
    unlocked: true, acknowledged: true)
check(BadgeAwardDelivery.pendingIDs([acknowledged]).isEmpty, "Explicit dismissal prevents repeat celebrations")
let tie: [BadgeAwardDelivery.Candidate] = ["b", "a"].map {
    .init(id: $0, completedAt: now, unlocked: true, acknowledged: false)
}
check(BadgeAwardDelivery.pendingIDs(tie) == ["a", "b"], "Equal-date awards have stable order")
check(BadgeAwardDelivery.validAcknowledgements(["streak-5", "streak-30"], unlockedIDs: ["streak-5"])
      == ["streak-5"], "Legacy repair preserves earned receipts and removes impossible future receipts")
check(BadgeAwardDelivery.pendingIDs([]).isEmpty, "Empty catalog")
print("Passed \(checks) badge-delivery checks")
'''
with tempfile.TemporaryDirectory(prefix='nano-badge-checks-') as directory:
    directory = Path(directory)
    source = directory / 'main.swift'
    source.write_text((root / 'Nanobeasts/Models/BadgeAwardDelivery.swift').read_text() + checks)
    executable = directory / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'),
                    str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

# Compile the production catalog and Recent Achievements selection on macOS.
insights = (root / 'Nanobeasts/Features/Stats/StatsInsightComponents.swift').read_text()
badge_models = insights[insights.index('struct StatsBadge:'):insights.index('actor BadgeArtworkImageCache')]
catalog = insights[insights.index('enum StatsBadgeCatalog {'):insights.index('struct RecentAchievementsRow:')]
store = (root / 'Nanobeasts/Models/AppStore.swift').read_text()
units = store[store.index('enum DistanceUnitPreference:'):store.index('@MainActor\n@Observable')]
assert 'StatsBadge.recentUnlocked(in: sections)' in insights
stats_view = (root / 'Nanobeasts/Features/Stats/StatsView.swift').read_text()
assert 'evolutionEventID: store.evolutionEventID' in stats_view
assert 'discoveryEvents: input.discoveryEvents' in stats_view
# Real awards persist even during the hidden step preview, and never repeat in a session.
assert 'if hasTestingActivityPreview, !earnedWithoutPreview {' in store
root_view = (root / 'Nanobeasts/App/AppRootView.swift').read_text()
assert 'earnedWithoutPreview: isEarnedWithoutPreview(badge.id)' in root_view
assert 'badgesShownThisSession.contains($0.id)' in root_view
support = '''
import Foundation
import SwiftUI
enum NanoTheme {
    static let purple = Color.purple, teal = Color.teal, orange = Color.orange, green = Color.green
}
enum R2BadgeManifest { static func url(for id: String) -> URL? { nil } }
enum AppScreenshotScenario { case badges, collectionBadges; static let active: Self? = nil }
'''
recent_checks = r'''
var count = 0
func expect(_ value: Bool, _ label: String) { precondition(value, label); count += 1 }
let now = Date(timeIntervalSince1970: 1_800_000_000)
func badge(_ id: String, _ date: Date?, unlocked: Bool = true) -> StatsBadge {
    StatsBadge(id: id, symbol: "", artworkURL: nil, title: id, description: "", tint: .teal,
               unlocked: unlocked, completedAt: date)
}
let badges = [badge("old", now.addingTimeInterval(-86400)), badge("new", now),
              badge("locked", now.addingTimeInterval(100), unlocked: false),
              badge("legacy-b", nil), badge("legacy-a", nil), badge("same-time", now)]
let sections = [StatsBadgeSection(id: "first", title: "", badges: Array(badges.prefix(2))),
                StatsBadgeSection(id: "second", title: "", badges: Array(badges.dropFirst(2)))]
let recent = StatsBadge.recentUnlocked(in: sections)
expect(recent.map(\.id) == ["new", "same-time", "old", "legacy-a", "legacy-b"],
       "Newest first across sections; locked omitted; stable ties and undated legacy last")
expect(Array(recent.prefix(4)).map(\.id) == ["new", "same-time", "old", "legacy-a"], "Sort before taking visible four")
expect(StatsBadge.recentUnlocked(in: sections.reversed()).map(\.id) == recent.map(\.id), "Catalog order cannot change recency")
expect(StatsBadge.recentUnlocked(in: []).isEmpty, "Empty achievements")
func stage(_ family: String, _ number: Int) -> CreatureStage {
    CreatureStage(familyID: family, name: family, imageKey: "", stage: number, types: [], description: "")
}
let first = stage("a", 1), second = stage("b", 1), third = stage("c", 1), evolved = stage("a", 2), final = stage("a", 3)
let hatchDate = now.addingTimeInterval(-50000)
let events = [CreatureDiscoveryEvent(stage: third, kind: .hatch, timestamp: now),
              CreatureDiscoveryEvent(stage: first, kind: .hatch, timestamp: hatchDate),
              CreatureDiscoveryEvent(stage: evolved, kind: .evolution, timestamp: now.addingTimeInterval(-30000)),
              CreatureDiscoveryEvent(stage: second, kind: .hatch, timestamp: now.addingTimeInterval(-10000)),
              CreatureDiscoveryEvent(stage: first, kind: .hatch, timestamp: now.addingTimeInterval(-5000)),
              CreatureDiscoveryEvent(stage: final, kind: .evolution, timestamp: now.addingTimeInterval(-2000))]
func make(_ day: Date, events: [CreatureDiscoveryEvent]) -> [StatsBadge] {
    StatsBadgeCatalog.make(records: [DailyStepRecord(day: day, steps: 20000)], dailyGoal: 5000,
        dailyGoalHistory: [], discoveredStages: [first, second, third, evolved, final],
        distanceUnit: .miles, discoveryEvents: events).flatMap(\.badges)
}
let catalog = make(now, events: events)
func earned(_ id: String) -> Date? { catalog.first { $0.id == id }?.completedAt }
expect(earned("collection-first") == hatchDate, "First hatch uses actual discovery timestamp")
expect(earned("collection-3") == now && earned("species-3") == now, "Third distinct species determines completion despite duplicate hatch")
expect(earned("evolve-first") == now.addingTimeInterval(-30000), "Evolution uses first qualifying evolution timestamp")
expect(earned("final-first") == now.addingTimeInterval(-2000), "Final badge uses final-stage timestamp")
expect(catalog.first { $0.id == "collection-5" }?.unlocked == false && earned("collection-5") == nil, "Unreached milestones remain locked and undated")
let later = make(now.addingTimeInterval(86400), events: events)
expect(later.first { $0.id == "collection-first" }?.completedAt == hatchDate, "Later walking never re-dates an old collection badge")
let legacy = make(now, events: [])
expect(legacy.first { $0.id == "collection-first" }?.unlocked == true, "Legacy discovery retains earned badge")
expect(legacy.first { $0.id == "collection-first" }?.completedAt == nil, "No invented date for missing legacy history")
print("Passed \(count) recent-achievement ordering and actual completion-date checks")
'''
with tempfile.TemporaryDirectory(prefix='nano-recent-badge-checks-') as directory:
    directory = Path(directory)
    source = directory / 'main.swift'
    source.write_text(support + units + badge_models + catalog + recent_checks)
    executable = directory / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'),
                    str(root / 'Nanobeasts/Models/CreatureModels.swift'), str(source),
                    '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
