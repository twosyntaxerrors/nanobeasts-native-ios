#!/usr/bin/env python3
"""Exercise production history reconciliation, optionally against a device snapshot."""
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
history = (root / 'Nanobeasts/Features/Settings/WorkoutHistoryView.swift').read_text()
models = (root / 'Nanobeasts/Models/CreatureModels.swift').read_text()
domain = models[models.index('struct CreatureStage:'):models.index('enum HealthConnectionState:')]
policy = history[history.index('struct WorkoutCompanionSnapshot:'):history.index('@MainActor\nfinal class WorkoutHistoryStore:')]
shared = (root / 'NanobeastsShared/WatchWorkoutMessage.swift').read_text()
activity = shared[shared.index('enum WorkoutActivityPolicy {'):shared.index('/// A small, durable')]
checks = (root / 'Scripts/WorkoutRegression/HistoryChecks.swift').read_text()
with tempfile.TemporaryDirectory(prefix='nanobeasts-history-checks-') as directory:
    directory = pathlib.Path(directory)
    source = directory / 'main.swift'
    source.write_text('import Foundation\n' + domain + activity + policy + checks)
    executable = directory / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'ModuleCache'), str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable), *sys.argv[1:]], check=True)
