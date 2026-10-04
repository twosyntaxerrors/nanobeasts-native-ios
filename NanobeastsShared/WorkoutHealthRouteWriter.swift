import CoreLocation
import HealthKit

@MainActor
enum WorkoutHealthRouteWriter {
    static func save(_ locations: [WorkoutRecordedLocation], breaks: [Int], workout: HKWorkout, store: HKHealthStore) async throws {
        let boundaries = Set(breaks)
        var segments: [[CLLocation]] = []
        var segment: [CLLocation] = []
        for (index, sample) in locations.enumerated() {
            if boundaries.contains(index), !segment.isEmpty {
                segments.append(segment)
                segment = []
            }
            segment.append(sample.location)
        }
        if !segment.isEmpty { segments.append(segment) }
        for segment in segments where segment.count > 1 {
            let builder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
            try await builder.insertRouteData(segment)
            _ = try await builder.finishRoute(with: workout, metadata: nil)
        }
    }
}
