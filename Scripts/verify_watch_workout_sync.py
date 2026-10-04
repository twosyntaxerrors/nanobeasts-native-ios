#!/usr/bin/env python3
"""Exercise real Watch payloads and history writes without generating Health data."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
history = (root / 'Nanobeasts/Features/Settings/WorkoutHistoryView.swift').read_text()
models = (root / 'Nanobeasts/Models/CreatureModels.swift').read_text()
domain = models[models.index('struct CreatureStage:'):models.index('enum HealthConnectionState:')]
policy = history[history.index('struct WorkoutCompanionSnapshot:'):history.index('@MainActor\nfinal class WorkoutHistoryStore:')]
store = history[history.index('@MainActor\nfinal class WorkoutHistoryStore:'):history.index('    func importFromAppleHealth(')]
store = store.replace('    private let healthStore = HKHealthStore()\n', '')
# This harness exercises Watch persistence; HealthKit I/O is verified on device.
# Keep the actual receiver/reconciliation logic, replacing only the async reader.
a = store.index('    func refreshHealthTotals(')
b = store.index('    func updateDiscoveries(', a)
store = store[:a] + '    func refreshHealthTotals(for workoutID: UUID? = nil, force: Bool = false) async {}\n\n' + store[b:]
store += history[history.index('    private func persist()'):history.index('    private static func makeRecord(')] + '}\n'
archive = history[history.index('enum WorkoutHistoryRouteArchive'):history.index('struct WorkoutHubHeader:')]
a = archive.index('        FileManager.default.urls(')
b = archive.index('            .appendingPathComponent("Nanobeasts"', a)
archive = archive[:a] + '        Optional(URL(fileURLWithPath: CommandLine.arguments[1]))?\n' + archive[b:]
message = (root / 'NanobeastsShared/WatchWorkoutMessage.swift').read_text()
route_policy = (root / 'NanobeastsShared/WorkoutRoutePolicy.swift').read_text()
checks = (root / 'Scripts/WorkoutRegression/WatchSyncChecks.swift').read_text()
with tempfile.TemporaryDirectory(prefix='nanobeasts-watch-checks-') as directory:
    directory = pathlib.Path(directory)
    source = directory / 'main.swift'
    source.write_text('import Foundation\nimport Combine\nimport CoreLocation\n' + domain + policy + message + route_policy + store + archive + checks)
    executable = directory / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'ModuleCache'), str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable), str(directory / 'Archive')], check=True)
