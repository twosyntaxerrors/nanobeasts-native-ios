#!/usr/bin/env python3
"""Verify route authorization/recovery gates and serialized permission requests."""
import pathlib
import argparse
import platform
import plistlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', required=True, help='UUID of a booted Watch simulator')
args = parser.parse_args()
sdk = subprocess.check_output(['xcrun', '--sdk', 'watchsimulator', '--show-sdk-path'], text=True).strip()
info = plistlib.loads((root / 'NanobeastsWatch/Info.plist').read_bytes())
assert 'location' in info.get('UIBackgroundModes', []), 'Background GPS must use UIBackgroundModes'
assert 'location' not in info.get('WKBackgroundModes', []), 'location is not a WKBackgroundModes value'
sources = [root / 'NanobeastsWatch/WatchLocationAccess.swift',
           root / 'NanobeastsWatch/WatchAuthorizationQueue.swift',
           root / 'Scripts/WorkoutRegression/WatchPermissionChecks.swift']
with tempfile.TemporaryDirectory(prefix='nano-watch-permissions-') as directory:
    executable = pathlib.Path(directory) / 'checks'
    subprocess.run(['xcrun', '--sdk', 'watchsimulator', 'swiftc', '-sdk', sdk,
                    '-target', platform.machine() + '-apple-watchos11.0-simulator',
                    '-module-cache-path', directory + '/ModuleCache',
                    *map(str, sources), '-o', str(executable)], check=True)
    subprocess.run(['xcrun', 'simctl', 'spawn', args.device, str(executable)], check=True, timeout=30)
