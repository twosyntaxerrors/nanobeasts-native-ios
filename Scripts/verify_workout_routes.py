#!/usr/bin/env python3
"""Run the exact production GPS policy and projection on macOS, without booting iOS."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
tracker = (root / 'NanobeastsShared/WorkoutRoutePolicy.swift').read_text() + '\nstruct WorkoutTerritoryCell:'
share = (root / 'Nanobeasts/Features/Settings/WorkoutShareView.swift').read_text()
history = (root / 'Nanobeasts/Features/Settings/WorkoutHistoryView.swift').read_text()
# Extract self-contained production declarations, not copies of their algorithms.
policy = tracker[tracker.index('enum WorkoutRouteFilter'):tracker.index('struct WorkoutTerritoryCell:')]
shape = share[share.index('struct WorkoutRouteShape:'):share.index('private struct WorkoutShareGrid:')]
checks = (root / 'Scripts/WorkoutRegression/RouteChecks.swift').read_text()
archive = history[history.index('enum WorkoutHistoryRouteArchive'):history.index('struct WorkoutHubHeader:')]
# Exercise the production archive in an isolated temporary directory.
archive_start = archive.index('        FileManager.default.urls(')
archive_end = archive.index('            .appendingPathComponent("Nanobeasts"', archive_start)
archive = archive[:archive_start] + '        Optional(URL(fileURLWithPath: CommandLine.arguments[1]))?\n' + archive[archive_end:]
with tempfile.TemporaryDirectory(prefix='nanobeasts-route-checks-') as directory:
    directory = pathlib.Path(directory)
    source = directory / 'main.swift'
    source.write_text('import Foundation\nimport CoreLocation\nimport MapKit\nimport SwiftUI\n' + policy + shape + archive + checks)
    executable = directory / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'ModuleCache'), str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable), str(directory / 'Archive')], check=True)
