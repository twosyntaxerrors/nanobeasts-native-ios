#!/usr/bin/env python3
"""Exercise the production watch motion and milestone policies without synthetic Health workouts."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
sources = [root / 'NanobeastsShared/WatchWorkoutMessage.swift',
           root / 'NanobeastsWatch/WatchWorkoutFeedback.swift',
           root / 'Scripts/WorkoutRegression/WatchFeedbackChecks.swift']
with tempfile.TemporaryDirectory(prefix='nano-watch-feedback-') as directory:
    directory = pathlib.Path(directory)
    source = directory / 'main.swift'
    source.write_text('\n'.join(path.read_text() for path in sources))
    executable = directory / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'ModuleCache'),
                    str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
