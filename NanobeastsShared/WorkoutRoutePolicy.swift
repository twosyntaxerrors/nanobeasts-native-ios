import CoreLocation
import Foundation

/// Pure acceptance policy shared by live recording and regression checks.
enum WorkoutRouteFilter {
    enum Decision { case reject, append, startSegment }

    static func evaluate(
        _ location: CLLocation,
        previous: CLLocation?,
        after earliestDate: Date?,
        now: Date,
        maximumSpeed: CLLocationSpeed
    ) -> Decision {
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 35,
              location.timestamp <= now.addingTimeInterval(10),
              location.timestamp >= (earliestDate ?? .distantPast),
              location.speed < 0 || location.speed <= maximumSpeed * 1.35
        else { return .reject }
        guard let previous else { return .startSegment }
        let time = location.timestamp.timeIntervalSince(previous.timestamp)
        guard time > 0 else { return .reject }
        let distance = location.distance(from: previous)
        let worstAccuracy = max(previous.horizontalAccuracy, location.horizontalAccuracy)
        let maximumPlausibleDistance = max(
            20, maximumSpeed * max(time, 0.25) + min(worstAccuracy * 0.5, 20)
        )
        // Retain walking turns without counting stationary drift or GPS teleports.
        guard distance <= maximumPlausibleDistance,
              distance >= max(2, min(5, location.horizontalAccuracy * 0.15))
        else { return .reject }
        return time > 30 ? .startSegment : .append
    }
}

enum WorkoutRouteSegments {
    static func recorded(_ series: [[CLLocation]]) -> (coordinates: [CLLocationCoordinate2D], breakIndices: [Int]) {
        var coordinates: [CLLocationCoordinate2D] = []
        var breaks: [Int] = []
        for locations in series {
            var previous: CLLocation?
            for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
                guard CLLocationCoordinate2DIsValid(location.coordinate),
                      location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else {
                    previous = nil
                    continue
                }
                if let previous, location.timestamp <= previous.timestamp { continue }
                let startsSegment = previous.map {
                    location.timestamp.timeIntervalSince($0.timestamp) > 30
                } ?? true
                if !coordinates.isEmpty, startsSegment {
                    breaks.append(coordinates.count)
                }
                coordinates.append(location.coordinate)
                previous = location
            }
        }
        return (coordinates, breaks)
    }

    static func split(_ route: [CLLocationCoordinate2D], at breakIndices: [Int]) -> [[CLLocationCoordinate2D]] {
        let breaks = Set(breakIndices)
        var segments: [[CLLocationCoordinate2D]] = []
        var segment: [CLLocationCoordinate2D] = []
        for (index, coordinate) in route.enumerated() {
            if breaks.contains(index) || !CLLocationCoordinate2DIsValid(coordinate) {
                if !segment.isEmpty { segments.append(segment) }
                segment = []
            }
            if CLLocationCoordinate2DIsValid(coordinate) { segment.append(coordinate) }
        }
        if !segment.isEmpty { segments.append(segment) }
        return segments
    }
}

