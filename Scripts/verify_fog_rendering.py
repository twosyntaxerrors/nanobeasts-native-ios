#!/usr/bin/env python3
"""Rasterize the production fog renderer on macOS without Simulator."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
s = (root/'Nanobeasts/Features/Settings/WorkoutPreviewView.swift').read_text()
renderer = s[s.index('final class WorkoutTerritoryOverlay:'):s.index('private struct WorkoutGoalRow:')]
policy = (root/'NanobeastsShared/WorkoutRoutePolicy.swift').read_text()
harness = r'''
import AppKit
import SwiftUI
import MapKit
typealias UIColor = NSColor
enum NanoTheme { static let teal = Color.cyan }
POLICY
RENDERER
let center = CLLocationCoordinate2D(latitude: 40.7, longitude: -73.92)
let origin = MKMapPoint(center)
let units = MKMapPointsPerMeterAtLatitude(center.latitude)
func coordinate(_ x: Double, _ y: Double) -> CLLocationCoordinate2D {
    MKMapPoint(x: origin.x + x * units, y: origin.y + y * units).coordinate
}
func raster(span: Double, routes: [[CLLocationCoordinate2D]]) -> (CGContext, (Double, Double) -> Int) {
    let pixels = 600
    let fog = WorkoutTerritoryOverlay()
    fog.showsFog = true
    fog.exploredRoutes = routes
    let renderer = WorkoutTerritoryRenderer(overlay: fog)
    let mapRect = MKMapRect(x: origin.x - span * units / 2, y: origin.y - span * units / 2,
                            width: span * units, height: span * units)
    let zoom = Double(pixels) / mapRect.width
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
        bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    let rect = renderer.rect(for: mapRect)
    context.scaleBy(x: zoom, y: zoom)
    context.translateBy(x: -rect.minX, y: -rect.minY)
    renderer.draw(mapRect, zoomScale: zoom, in: context)
    let alpha: (Double, Double) -> Int = { x, y in
        let px = min(pixels - 1, max(0, Int(Double(pixels) * (0.5 + x / span))))
        let py = min(pixels - 1, max(0, Int(Double(pixels) * (0.5 + y / span))))
        return Int(context.data!.assumingMemoryBound(to: UInt8.self)[(py * pixels + px) * 4 + 3])
    }
    return (context, alpha)
}
let path = [coordinate(-100, 0), coordinate(100, 0)]
for span in [250.0, 500.0, 1500.0] {
    let (_, alpha) = raster(span: span, routes: [path])
    print("Span \(Int(span))m: route alpha=\(alpha(0,0)), 30m away=\(alpha(0,30)), 60m away=\(alpha(0,60))")
    CHECKS
}
'''.replace('POLICY',policy).replace('RENDERER',renderer)
checks = '''precondition(alpha(0, 0) < 5, "Visited path must be clear")
    precondition(alpha(0, 30) > 145, "Unvisited ground 30m away must stay pink at every zoom")'''
import sys
harness = harness.replace('CHECKS', '' if '--baseline' in sys.argv else checks)
harness += r'''
let (_, untouched) = raster(span: 500, routes: [])
precondition(untouched(0, 0) > 145, "New maps begin covered in fog")
let (_, paused) = raster(span: 500, routes: [
    [coordinate(-100, 0), coordinate(-40, 0)],
    [coordinate(40, 0), coordinate(100, 0)]
])
precondition(paused(0, 0) > 145, "Recording gaps cannot reveal a connecting corridor")
let (_, repeated) = raster(span: 1500, routes: Array(repeating: path, count: 100))
precondition(repeated(0, 30) > 145, "Repeated walks cannot spread beyond the geographic reveal width")
print("Passed new-map, pause-gap, repeated-walk, and zoom-invariant fog raster checks.")
if CommandLine.arguments.count > 2 {
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
    var stored = object["routes"] as? [[String: Any]] ?? []
    let history = object["historyRoutes"] as? [String: [[String: Any]]] ?? [:]
    stored += history.values.flatMap { $0 }
    let routes = stored.map { segment in
        (segment["points"] as! [[String: Double]]).map {
            CLLocationCoordinate2D(latitude: $0["latitude"]!, longitude: $0["longitude"]!)
        }
    }
    let (context, _) = raster(span: 500, routes: routes)
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    let foggyPixels = (0..<(600 * 600)).filter { data[$0 * 4 + 3] > 145 }.count
    print("Saved-route raster: \(foggyPixels * 100 / (600 * 600)) percent of this 500m view remains fully fogged.")
}
'''
with tempfile.TemporaryDirectory(prefix='nano-fog-render-') as temp:
    path = Path(temp); f=path/'main.swift'; f.write_text(harness)
    subprocess.run(['swift','-module-cache-path',str(path/'cache'),str(f)] + sys.argv[1:],check=True)
