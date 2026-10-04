import CoreLocation
import MapKit

/// A distance-based recap of recorded GPS only. Gaps consume no distance and
/// remain separate paths; replay never records steps or reveals saved territory.
struct WorkoutRouteReplayTrack {
    struct Frame {
        let coordinates: [CLLocationCoordinate2D]
        let breakIndices: [Int]
        let marker: CLLocationCoordinate2D?
    }

    private struct Edge {
        let startIndex: Int
        let endIndex: Int
        let startDistance: Double
        let endDistance: Double
    }

    let coordinates: [CLLocationCoordinate2D]
    let breakIndices: [Int]
    let distance: Double
    private let edges: [Edge]
    var canReplay: Bool { distance > 0 && !edges.isEmpty }

    init(route: [CLLocationCoordinate2D], breakIndices: [Int]) {
        var points: [CLLocationCoordinate2D] = []
        var breaks: [Int] = []
        var edges: [Edge] = []
        var distance = 0.0
        for segment in WorkoutRouteSegments.split(route, at: breakIndices) where segment.count > 1 {
            if !points.isEmpty { breaks.append(points.count) }
            for (index, coordinate) in segment.enumerated() {
                if index > 0, let previous = points.last {
                    let length = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                        .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                    if length.isFinite && length > 0 {
                        edges.append(Edge(startIndex: points.count - 1, endIndex: points.count,
                                          startDistance: distance, endDistance: distance + length))
                        distance += length
                    }
                }
                points.append(coordinate)
            }
        }
        self.coordinates = points
        self.breakIndices = breaks
        self.edges = edges
        self.distance = distance
    }

    func frame(at progress: Double) -> Frame {
        guard canReplay else { return Frame(coordinates: [], breakIndices: [], marker: nil) }
        let progress = progress.isFinite ? min(1, max(0, progress)) : 0
        if progress >= 1 {
            return Frame(coordinates: coordinates, breakIndices: breakIndices, marker: coordinates.last)
        }
        let target = progress * distance
        var low = 0
        var high = edges.count - 1
        while low < high {
            let mid = (low + high) / 2
            if edges[mid].endDistance < target { low = mid + 1 } else { high = mid }
        }
        let edge = edges[low]
        let fraction = (target - edge.startDistance) / (edge.endDistance - edge.startDistance)
        let start = MKMapPoint(coordinates[edge.startIndex])
        let end = MKMapPoint(coordinates[edge.endIndex])
        let worldWidth = MKMapRect.world.size.width
        var dx = end.x - start.x
        if dx > worldWidth / 2 { dx -= worldWidth }
        if dx < -worldWidth / 2 { dx += worldWidth }
        var x = (start.x + dx * fraction).truncatingRemainder(dividingBy: worldWidth)
        if x < 0 { x += worldWidth }
        let marker = MKMapPoint(x: x, y: start.y + (end.y - start.y) * fraction).coordinate
        var visible = Array(coordinates.prefix(edge.startIndex + 1))
        visible.append(marker)
        return Frame(coordinates: visible,
                     breakIndices: breakIndices.filter { $0 <= edge.startIndex }, marker: marker)
    }
}
