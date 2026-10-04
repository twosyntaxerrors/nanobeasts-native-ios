#!/usr/bin/env python3
"""Exercise production replay geometry in isolation; never touches app data."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
files = ['NanobeastsShared/WorkoutRoutePolicy.swift',
         'Nanobeasts/Features/Settings/WorkoutRouteReplayTrack.swift',
         'Scripts/WorkoutRegression/ReplayChecks.swift']
with tempfile.TemporaryDirectory(prefix='nano-replay-checks-') as folder:
    folder = pathlib.Path(folder)
    source = folder / 'main.swift'
    source.write_text('\n'.join((root / file).read_text() for file in files))
    executable = folder / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(folder / 'ModuleCache'),
                    str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
