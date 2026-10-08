#!/usr/bin/env python3
"""Exercise production history-to-territory recovery and its durable archive."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Nanobeasts/Services/WorkoutLocationTracker.swift').read_text()
recovery = source[source.index('    func restoreSavedTerritory('):source.index('    private static func simplified(')]
persist = source[source.index('    private static func persist(exploredRoutes:'):source.index('    private static var territoryArchiveURL:')]
types = source[source.index('    private struct TerritoryArchive:'):]
harness = '''import Foundation
import CoreLocation
@MainActor final class WorkoutZoneCelebrations { static let shared = WorkoutZoneCelebrations(); func territoryChanged(_ routes: [[CLLocationCoordinate2D]]) {} }
final class WorkoutLocationTracker {
    var exploredRoutes: [[CLLocationCoordinate2D]] = []
    private var legacyExploredRoutes: [[CLLocationCoordinate2D]] = []
    private var importedWatchSessionIDs: Set<UUID> = []
    private var savedHistoryRoutes: [String: [StoredRoute]] = [:]
    private static var territoryArchiveURL: URL? { URL(fileURLWithPath: CommandLine.arguments[1]) }
''' + recovery + persist + types + '''
let tracker = WorkoutLocationTracker()
let id = UUID()
let route = (0..<8).map { CLLocationCoordinate2D(latitude: 40 + Double($0) * 0.001, longitude: -73) }
tracker.restoreSavedTerritory([id: [Array(route.prefix(2))]])
precondition(tracker.exploredRoutes.count == 1)
tracker.restoreSavedTerritory([id: [Array(route.prefix(4)), Array(route.suffix(4))]])
precondition(tracker.exploredRoutes.map(\\.count) == [4, 4], "Full route replaces partial territory and preserves pause gap")
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let before = try Data(contentsOf: url)
tracker.restoreSavedTerritory([id: [Array(route.prefix(4)), Array(route.suffix(4))]])
let after = try Data(contentsOf: url)
precondition(after == before, "Repeated map opening must not rewrite or duplicate a route")
precondition(tracker.exploredRoutes.count == 2)
tracker.restoreSavedTerritory([:])
precondition(tracker.exploredRoutes.count == 2, "Temporarily unavailable history must not erase earned territory")
var corrected = route
corrected[2].longitude += 0.001
tracker.restoreSavedTerritory([id: [Array(corrected.prefix(4)), Array(corrected.suffix(4))]])
precondition(tracker.exploredRoutes[0][2].longitude == corrected[2].longitude, "Same-size corrected route refreshes the fog geometry")
let archive = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
let histories = archive["historyRoutes"] as! [String: [[String: Any]]]
precondition(histories.count == 1 && histories[id.uuidString]?.count == 2, "Durable archive retains one route and its segments for the next launch")
print("Passed territory recovery: full-route replacement, pauses, idempotence, persistence, and same-size route corrections.")
'''
with tempfile.TemporaryDirectory(prefix='nano-territory-checks-') as temp:
    path = Path(temp)
    swift = path / 'main.swift'
    swift.write_text(harness)
    subprocess.run(['swift', '-module-cache-path', str(path / 'cache'), str(swift), str(path / 'territory.json')], check=True)
