#!/usr/bin/env python3
"""Exercise the production Watch save handoff with a delayed fake transport."""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'NanobeastsWatch/WatchWorkoutRecorder.swift').read_text()
def member(marker):
    start=s.index(marker);opening=s.index('{',start);end=opening+1;depth=1
    while depth:
        depth += (s[end]=='{') - (s[end]=='}');end+=1
    return s[start:end].replace('private ', '', 1)
logic='\n'.join(member(m) for m in ['private func prepareToSave(', 'private func publish()', 'private func save('])
harness=r'''
import Foundation
let HKMetadataKeyIndoorWorkout = "indoor"
@MainActor final class FakeSession {
    var ended = false
    var finalDeliveredBeforeEnd = false
    var delay: UInt64 = 30_000_000
    func sendToRemoteWorkoutSession(data: Data) async throws {
        let state = try JSONDecoder().decode(WatchWorkoutSnapshot.self, from: data)
        try await Task.sleep(nanoseconds: delay)
        if !state.isActive { finalDeliveredBeforeEnd = !ended }
    }
    func end() { ended = true }
}
struct FakeWorkout { let uuid = UUID() }
@MainActor final class FakeBuilder {
    var finishCount = 0
    var shouldFail = false
    var endedAt: Date?
    func endCollection(at date: Date) async throws {
        endedAt = date
        try await Task.sleep(for: .milliseconds(10))
    }
    func addMetadata(_ metadata: [String: Any]) async throws {}
    func finishWorkout() async throws -> FakeWorkout? {
        finishCount += 1
        if shouldFail { throw RecorderError.message("Offline test failure") }
        return FakeWorkout()
    }
    func discardWorkout() {}
}
struct FakePedometer { func stopUpdates() {} }
enum RecorderError: LocalizedError {
    case message(String)
    var errorDescription: String? { "Test save failure" }
}
enum WorkoutHealthRouteWriter {
    static func save(_ locations: [WorkoutRecordedLocation], breaks: [Int], workout: FakeWorkout, store: Int) async throws {}
}
@MainActor final class FinishHarness {
    var session: FakeSession? = FakeSession()
    var builder: FakeBuilder? = FakeBuilder()
    var snapshot: WatchWorkoutSnapshot?
    var stoppedAt: Date?
    var saving = false
    var saveToHealth = true
    var timer: Timer?
    var stepSegment: Date?
    let pedometer = FakePedometer()
    let store = 0
    var locations: [WorkoutRecordedLocation] = []
    var breaks: [Int] = []
    var checkpoints: [WatchWorkoutSnapshot.Phase] = []
    var published: [WatchWorkoutSnapshot.Phase] = []
    var queuedResult: WatchWorkoutSnapshot?
    func stopMotionMonitoring() {}
    func dismissMilestones() {}
    func stopRoute() {}
    func updateMetrics(at date: Date) {
        if let snapshot { self.snapshot = snapshot.changingPhase(to: snapshot.phase, at: stoppedAt ?? date) }
    }
    func checkpoint(force: Bool) { if let snapshot { checkpoints.append(snapshot.phase) } }
    func publishCompanionStatus(durable: Bool = false) { if let snapshot { published.append(snapshot.phase) } }
    func queueResult() { queuedResult = snapshot }
''' + logic + '\n}\n'
checks=r'''
@MainActor func runChecks() async throws {
    var count = 0
    func check(_ value: Bool, _ description: String) {
        precondition(value, description); count += 1; print("PASS: \(description)")
    }
    func fixture() -> FinishHarness {
        let h=FinishHarness(), now=Date()
        h.snapshot=WatchWorkoutSnapshot(id: UUID(), workoutID: "indoor-walk", name: "Indoor Walk", indoor: true,
            startedAt: now.addingTimeInterval(-100), updatedAt: now, elapsed: 100, steps: 500,
            distanceMiles: 0.2, calories: 20, phase: .running)
        return h
    }
    let h=fixture(), connection=h.session!, builder=h.builder!
    let finishAt=h.snapshot!.updatedAt.addingTimeInterval(5)
    h.prepareToSave(at: finishAt)
    h.prepareToSave(at: finishAt.addingTimeInterval(100))
    check(h.snapshot?.elapsed == 105 && h.snapshot?.phase == .saving && h.stoppedAt == finishAt,
          "A finish request freezes once, even when repeated")
    await h.save(at: finishAt.addingTimeInterval(10))
    check(builder.endedAt == finishAt && h.snapshot?.elapsed == 105, "Health saving uses the original stop time")
    check(connection.finalDeliveredBeforeEnd && connection.ended, "Final metrics delivery completes before mirroring ends")
    check(h.queuedResult?.phase == .finished && h.snapshot?.healthWorkoutID != nil,
          "Confirmed completion has a durable result and Health identity")
    check(h.session == nil && h.builder == nil && h.published == [.saving, .finished],
          "Recorder closes and publishes stopping then saved")
    await h.save(at: Date())
    check(builder.finishCount == 1, "Duplicate finish callbacks cannot save twice")
    let failed=fixture(), failureConnection=failed.session!
    failed.builder!.shouldFail=true
    await failed.save(at: Date())
    check(failed.snapshot?.phase == .failed && failed.queuedResult?.steps == 500,
          "Health failure preserves actual recorded activity for History")
    check(failureConnection.finalDeliveredBeforeEnd && failureConnection.ended,
          "Health failure still reports terminal state and closes recording")
    // Start another recording while the previous terminal payload is in flight.
    let overlap=fixture(), previous=overlap.session!
    previous.delay=100_000_000
    let saveTask=Task { await overlap.save(at: Date()) }
    while overlap.queuedResult == nil { try await Task.sleep(for: .milliseconds(2)) }
    let next=FakeSession(), nextBuilder=FakeBuilder()
    overlap.session=next;overlap.builder=nextBuilder
    await saveTask.value
    check(previous.ended && !next.ended && overlap.session === next && overlap.builder === nextBuilder,
          "Finishing an old session cannot end or clear a newly started workout")
    print("PASS: \(count) production save handoff checks; no Health data or Simulator used")
}
try await runChecks()
'''
with tempfile.TemporaryDirectory(prefix='nano-watch-finish-') as temp:
    temp=Path(temp);(temp/'main.swift').write_text(harness+checks)
    subprocess.run(['xcrun','swiftc','-module-cache-path','/tmp/nano-workout-swiftcache',
        str(root/'NanobeastsShared/WatchWorkoutMessage.swift'),str(temp/'main.swift'),'-o',str(temp/'checks')],check=True)
    subprocess.run([str(temp/'checks')],check=True)
