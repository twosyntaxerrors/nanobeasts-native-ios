#!/usr/bin/env python3
"""Check the production video clock: full route, fixed ending, supported speeds."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / 'Nanobeasts/Features/Settings/WorkoutReplayVideo.swift').read_text()
timing = source[source.index('struct WorkoutReplayVideoTiming'):source.index('enum WorkoutReplayVideoError')]
checks = r'''
var checks = 0
func check(_ condition: Bool, _ message: String) {
    precondition(condition, message)
    checks += 1
}
for (speed, duration) in [(1.0, 33.0), (2.0, 18.0), (4.0, 10.5)] {
    let clock = WorkoutReplayVideoTiming(speed: speed)
    check(Double(clock.frameCount) / Double(clock.framesPerSecond) == duration, "Exact media duration")
    check(clock.routeProgress(frame: 0) == 0, "Share always starts at the beginning")
    let finish = Int(clock.routeDuration * Double(clock.framesPerSecond))
    check(clock.routeProgress(frame: finish - 1) < 1, "Route continues through final travel frame")
    check(clock.routeProgress(frame: finish) == 1, "Route completes before ending")
    check(clock.frameCount - finish == 90, "Three seconds of end card")
    check(clock.endingOpacity(frame: finish) == 0, "End card does not obscure travel")
    check(clock.endingOpacity(frame: finish + 11) == 1, "End card finishes fading in")
    check(clock.endingOpacity(frame: clock.frameCount - 1) == 1, "Last frame is a legible card")
    var previous = 0.0
    for frame in 0..<clock.frameCount {
        let progress = clock.routeProgress(frame: frame)
        check(progress >= previous && progress <= 1, "Progress is monotonic and bounded")
        previous = progress
    }
}
for invalid in [0.0, -1.0, 3.0, Double.infinity, Double.nan] {
    check(WorkoutReplayVideoTiming(speed: invalid).routeDuration == 30, "Unsupported speed has safe default")
}
check(WorkoutReplayVideoTiming(speed: 1).routeProgress(frame: -10) == 0, "Negative frame clamps to start")
print("PASS: \(checks) video clock checks (all speeds, route completion, closing card, invalid inputs)")
'''
with tempfile.TemporaryDirectory(prefix='nano-video-checks-') as directory:
    directory = pathlib.Path(directory)
    path = directory / 'main.swift'
    path.write_text('import Foundation\n' + timing + checks)
    executable = directory / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'ModuleCache'),
                    str(path), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
