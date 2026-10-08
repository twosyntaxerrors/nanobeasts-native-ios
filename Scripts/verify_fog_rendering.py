#!/usr/bin/env python3
"""Exercise and rasterize the production hex fog engine without Simulator."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
s = (root / 'Nanobeasts/Features/Settings/WorkoutPreviewView.swift').read_text()
engine = s[s.index('struct WorkoutRouteLine {'):s.index('private struct WorkoutGoalRow:')]
zones = (root / 'Nanobeasts/Features/Settings/WorkoutZones.swift').read_text()
engine += zones[zones.index('// MARK: - Street tiles'):zones.index('// MARK: - Names')]
engine += zones[zones.index('// MARK: - Trail drawing'):zones.index('// MARK: - Celebration')]
harness = r'''
import AppKit
import MapKit
typealias UIColor = NSColor
ENGINE
var checks = 0
func check(_ condition: Bool, _ message: String) { precondition(condition, message); checks += 1 }
let center = CLLocationCoordinate2D(latitude: 40.7, longitude: -73.92)
let origin = MKMapPoint(center), units = MKMapPointsPerMeterAtLatitude(center.latitude)
func coordinate(_ x: Double, _ y: Double) -> CLLocationCoordinate2D {
    MKMapPoint(x: origin.x + x * units, y: origin.y + y * units).coordinate
}
let walk = (0...80).map { coordinate(Double($0) * 5 - 200, 5 * sin(Double($0) / 3)) }
let overlay = WorkoutTerritoryOverlay()
for end in 1...walk.count {
    let before = overlay.snapshot.currentTiles
    let dirty = overlay.updateRoute(Array(walk.prefix(end)), breakIndices: [])
    let added = overlay.snapshot.currentTiles.subtracting(before)
    if let dirty { for tile in added { check(dirty.contains(tile.center), "New tile lies inside dirty rect") } }
}
let whole = WorkoutHexGrid.tiles(route: walk)
check(overlay.snapshot.currentTiles == whole, "Incremental and one-shot revelation agree")
let originalCount = overlay.snapshot.currentTiles.count
overlay.exploredRoutes = [walk, walk]
check(overlay.snapshot.newTileCount == 0, "Repeated walks grant no new tiles")
check(overlay.snapshot.districtCounts.values.reduce(0,+) == originalCount, "District counts deduplicate routes")
check(overlay.snapshot.chunks.values.reduce(0) { $0 + $1.tiles.count } == originalCount, "Each tile has exactly one chunk")
check(overlay.updateRoute(walk, breakIndices: [])!.isNull, "Unchanged route needs no repaint")
overlay.updateRoute(Array(walk.prefix(3)), breakIndices: [])
check(overlay.snapshot.currentTiles == WorkoutHexGrid.tiles(route: Array(walk.prefix(3))), "Backward scrubbing removes future current tiles")
let separated = [coordinate(-500, 0), coordinate(500, 0)]
let midpoint = WorkoutHexGrid.key(center)
check(!WorkoutHexGrid.tiles(route: separated, breaks: [1]).contains(midpoint), "Pause never clears a bridge")
check(WorkoutHexGrid.tiles(route: separated).contains(midpoint), "Normal segment samples every 10 meters")
check(WorkoutHexGrid.tiles(route: [coordinate(-2000,0),coordinate(2000,0)]).count <= 2, "GPS jump longer than 1.5 km never reveals a bridge")
for latitude in [-60.2, -0.2, 0.2, 40.7, 70.2] {
    let c = CLLocationCoordinate2D(latitude: latitude, longitude: 10)
    let tile = WorkoutHexGrid.key(c)
    check(tile.band == Int(floor(latitude)), "Latitude uses a stable one-degree band")
    check(WorkoutHexGrid.key(tile.center.coordinate) == tile, "Cube rounding returns each hex center")
    let groundRadius = tile.center.distance(to: tile.vertices()[0])
    check(abs(groundRadius - 20) < 0.7, "Hex radius stays about 20 ground meters at each latitude")
}
func raster(span: Double, isDark: Bool, rectOverride: MKMapRect? = nil) -> (CGContext, WorkoutTerritoryRenderer, MKMapRect) {
    let fog = WorkoutTerritoryOverlay(); fog.showsFog = true
    fog.exploredRoutes = [walk]
    fog.setAppearance(isDark: isDark, accent: .cyan, district: nil)
    let renderer = WorkoutTerritoryRenderer(overlay: fog)
    let area = rectOverride ?? MKMapRect(x: origin.x - span * units / 2, y: origin.y - span * units / 2, width: span * units, height: span * units)
    let context = CGContext(data: nil, width: 600, height: 600, bitsPerComponent: 8, bytesPerRow: 2400,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    let zoom = 600 / area.width, rect = renderer.rect(for: area)
    context.scaleBy(x: zoom, y: zoom); context.translateBy(x: -rect.minX, y: -rect.minY)
    renderer.draw(area, zoomScale: zoom, in: context)
    return (context, renderer, area)
}
for dark in [false, true] { for span in [500.0, 1500.0] {
    let (context, renderer, area) = raster(span: span, isDark: dark)
    func alpha(_ p: MKMapPoint) -> Int {
        let x = min(599, max(0, Int((renderer.point(for: p).x-renderer.rect(for: area).minX)/area.width*600)))
        let y = min(599, max(0, 599 - Int((renderer.point(for: p).y-renderer.rect(for: area).minY)/area.height*600)))
        return Int(context.data!.assumingMemoryBound(to: UInt8.self)[(y*600+x)*4+3])
    }
    func red(_ p: MKMapPoint) -> Int {
        let x = min(599, max(0, Int((renderer.point(for: p).x-renderer.rect(for: area).minX)/area.width*600)))
        let y = min(599, max(0, 599 - Int((renderer.point(for: p).y-renderer.rect(for: area).minY)/area.height*600)))
        return Int(context.data!.assumingMemoryBound(to: UInt8.self)[(y*600+x)*4])
    }
    for tile in whole { check(alpha(tile.center) > 100, "Walked hexes are painted in the accent at every zoom in both appearances") }
    check(alpha(MKMapPoint(coordinate(0,100))) < 10, "Unwalked ground stays a clean, readable map")
    if !dark && span == 500 {
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: OUTPUT))
    }
} }
// A single tile's rim must render even when only the rim intersects the map tile.
let lone = WorkoutTerritoryOverlay(); lone.showsFog = true; lone.exploredRoutes = [[center]]
let tile = lone.snapshot.oldTiles.first!
check(lone.snapshot.chunks.values.first!.bounds.contains(MKMapPoint(x: tile.center.x + tile.radius * 1.2, y: tile.center.y)), "Chunk culling includes outer rims")
let begin = Date()
let routes = (0..<200).map { n in (0...60).map { coordinate(Double($0)*7-200, Double(n % 20)*60) } }
let many = WorkoutTerritoryOverlay(); many.exploredRoutes = routes
check(Date().timeIntervalSince(begin) < 2, "200 stored routes derive quickly")
// Zones count streets, not buildings: walking one street of a two-street zone is 50%.
let zone = WorkoutHexGrid.key(center).district
let zoneCenter = WorkoutHexGrid.center(q: zone.q, r: zone.r, radius: zone.radius * 20)
func zc(_ x: Double, _ y: Double) -> CLLocationCoordinate2D { MKMapPoint(x: zoneCenter.x + x * units, y: zoneCenter.y + y * units).coordinate }
let streetA = [zc(-150, 0), zc(150, 0)]
let streetB = [zc(-150, 120), zc(150, 120)]
let streets = WorkoutZoneStreets.streetTiles([streetA, streetB], in: zone)
check(!streets.isEmpty && streets.allSatisfy { $0.district == zone }, "Street tiles stay inside their zone")
// Walking the sidewalk 12 m off the centerline still counts.
let sidewalk = WorkoutHexGrid.tiles(route: [zc(-150, 12), zc(150, 12)])
let half = WorkoutZoneProgress(streets: streets, walked: sidewalk.contains)
check(half.fraction > 0.4 && half.fraction < 0.6, "One of two streets walked is about half, sidewalk offset included")
check(!half.isMastered && half.percent < 100, "Half a zone is not mastered")
let both = sidewalk.union(WorkoutHexGrid.tiles(route: [zc(-150, 108), zc(150, 108)]))
let full = WorkoutZoneProgress(streets: streets, walked: both.contains)
check(full.isMastered && full.percent == 100, "Every street walked masters the zone at 100%")
let empty = WorkoutZoneProgress(streets: [], walked: both.contains)
check(!empty.isMastered && empty.total == 0, "A zone without streets is never mastered")
var almost = streets; let missing = Array(streets.prefix(1))
let nearly = WorkoutZoneProgress(streets: almost, walked: { both.contains($0) && !missing.contains($0) && !$0.neighbors.contains(missing[0]) })
check(nearly.isMastered, "Missing a tile or two still masters a zone (90% threshold)")
almost.removeAll()
print("PASS: \(checks) hex grid, gaps, GPS jumps, dirty rect, duplicate routes, district counts, culling and accent-trail light/dark raster, and street-based zone progress checks")
'''.replace('ENGINE', engine).replace('OUTPUT', '"' + str(root / 'Design/Workout-Redesign-2026-10-06/hex-fog-raster.png') + '"')
with tempfile.TemporaryDirectory(prefix='nano-hex-fog-') as temp:
    directory = Path(temp); source = directory / 'main.swift'; source.write_text(harness)
    subprocess.run(['swift', '-module-cache-path', str(directory/'cache'), str(source)], check=True)
