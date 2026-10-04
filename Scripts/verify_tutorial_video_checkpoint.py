#!/usr/bin/env python3
"""Run the production AVPlayer coordinator against a local hatch or evolution clip, without Simulator."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Nanobeasts/Features/Settings/SettingsView.swift').read_text()
player = source.split('private struct RemoteTransitionVideoView:', 1)[1]
start = player.index('    final class Coordinator {')
opening = player.index('{', start)
depth = 1
end = opening + 1
while depth:
    depth += (player[end] == '{') - (player[end] == '}')
    end += 1
coordinator = player[start:end].replace('final class Coordinator', 'final class PlaybackCoordinator', 1)
fixture = r'''
import Foundation
import AVFoundation
actor R2TransitionVideoCache {
    static let shared = R2TransitionVideoCache()
    func localURL(for url: URL) async throws -> URL { url }
}
'''
harness = r'''
let clip = URL(fileURLWithPath: CommandLine.arguments[1])
let gateTime = Double(CommandLine.arguments[2])!
let first = PlaybackCoordinator()
var paused = false
var endedEarly = false
var failed = false
var pauseCount = 0
func wait(_ timeout: Double, until condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
}
first.load(url: clip, shouldPlay: true, pauseTime: gateTime,
           onPause: { paused = true; pauseCount += 1 },
           onReady: { if !$0 { failed = true } }, onFinished: { endedEarly = true })
wait(15) { paused || failed }
precondition(!failed && paused, "The playing video must reach the gate")
let checkpoint = first.player.currentTime().seconds
precondition(abs(checkpoint - gateTime) < 0.04, "Pause must stop before later reveal frames")
precondition(!endedEarly, "Checkpoint is not a completed reveal")
first.setShouldPlay(true)
wait(0.6) { false }
precondition(first.player.rate == 0, "SwiftUI updates cannot restart a gated video")
precondition(abs(first.player.currentTime().seconds - checkpoint) < 0.04, "Video remains stopped behind paywall")
precondition(pauseCount == 1, "Boundary and end notifications deliver only one paywall")
first.stop()
precondition(first.player.currentItem == nil, "Dismissing the player releases playback")

let resumed = PlaybackCoordinator()
var readyAt = -1.0
var finished = false
resumed.load(url: clip, shouldPlay: false, startTime: gateTime,
             onReady: { ready in
                 if ready { readyAt = resumed.player.currentTime().seconds }
                 else { failed = true }
             }, onFinished: { finished = true })
wait(15) { readyAt >= 0 || failed }
precondition(!failed && abs(readyAt - gateTime) < 0.04, "Resumed player seeks before being displayed")
resumed.setShouldPlay(true)
wait(12) { finished || failed }
precondition(!failed && finished, "Purchased preview resumes and finishes the actual video")
resumed.stop()
print("Video checkpoint passed: paused at \(checkpoint)s, resumed at \(readyAt)s, then finished.")
'''
with tempfile.TemporaryDirectory(prefix='nanobeasts-video-checkpoint-') as temp:
    path = Path(temp) / 'main.swift'
    path.write_text(fixture + coordinator + harness)
    subprocess.run(['swift', '-module-cache-path', str(Path(temp)/'ModuleCache'), str(path), sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '1.25'], check=True)
