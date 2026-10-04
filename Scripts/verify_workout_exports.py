#!/usr/bin/env python3
"""Render production share layout on macOS using AppKit's image adapter.
This does not replace verification of the iOS composer and share sheet.
"""
import pathlib
import subprocess
import tempfile
import sys

root = pathlib.Path(__file__).resolve().parents[1]
output = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'build/WorkoutShareVerification'
share = (root / 'Nanobeasts/Features/Settings/WorkoutShareView.swift').read_text()
tracker = (root / 'NanobeastsShared/WorkoutRoutePolicy.swift').read_text() + '\nstruct WorkoutTerritoryCell:'
theme = (root / 'Nanobeasts/DesignSystem/NanoTheme.swift').read_text()
accent = (root / 'NanobeastsShared/NanoAccent.swift').read_text()
payload = share[share.index('struct WorkoutSharePayload:'):share.index('struct WorkoutShareComposer:')]
card = share[share.index('private enum WorkoutShareStyle:'):share.index('private struct WorkoutSharePrimaryButtonStyle:')]
card = card.replace('Image(uiImage:', 'Image(nsImage:')
segments = tracker[tracker.index('enum WorkoutRouteSegments'):tracker.index('struct WorkoutTerritoryCell:')]
time = share[share.index('private func shareTime('):]
checks = (root / 'Scripts/WorkoutRegression/ExportChecks.swift').read_text()
with tempfile.TemporaryDirectory(prefix='nanobeasts-export-checks-') as directory:
    directory = pathlib.Path(directory)
    source = directory / 'main.swift'
    source.write_text('import Foundation\nimport SwiftUI\nimport AppKit\nimport MapKit\nimport CoreText\ntypealias UIImage = NSImage\n' + accent + theme[:theme.index('struct NanoCardModifier:')] + payload + segments + card + time + checks)
    executable = directory / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'ModuleCache'), str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable), str(root), str(output)], check=True)
