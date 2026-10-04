#!/usr/bin/env python3
"""Compile the actual durable motion ledger and exercise suspended-callback recovery."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
tracker = (root / 'Nanobeasts/Services/WorkoutSessionTracker.swift').read_text()
model = tracker[tracker.index('struct WorkoutMotionLedger:'):]
checks = (root / 'Scripts/WorkoutRegression/MotionChecks.swift').read_text()
with tempfile.TemporaryDirectory(prefix='nano-motion-checks-') as directory:
    path = Path(directory)
    source = path / 'main.swift'
    source.write_text('import Foundation\n' + model + checks)
    subprocess.run(['swift', '-module-cache-path', str(path / 'cache'), str(source)], check=True)
