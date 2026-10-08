import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Street tiles

extension WorkoutHexKey {
    /// The six touching tiles (axial coordinates).
    var neighbors: [WorkoutHexKey] {
        [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)].map {
            WorkoutHexKey(band: band, q: q + $0.0, r: r + $0.1)
        }
    }

    var storageID: String { "\(band)_\(q)_\(r)" }
}

/// Which tiles of a zone a street runs through. A zone's percentage only counts
/// these, so 100% means every street was walked, never the inside of buildings.
/// Street geometry comes from OpenStreetMap once per zone and is kept on disk.
final class WorkoutZoneStreets: @unchecked Sendable {
    static let shared = WorkoutZoneStreets()
    static let didLoad = Notification.Name("WorkoutZoneStreets.didLoad")

    /// Nanobeasts' own cache in front of OpenStreetMap: each zone is fetched from
    /// OpenStreetMap once for everyone, then served from Cloudflare's edge.
    static let cacheBase = URL(string: "https://assets.nanobeasts.app/zone-streets/v2/")!
    /// Direct OpenStreetMap servers, used only when the cache can't answer.
    private static let overpassEndpoints = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://maps.mail.ru/osm/tools/overpass/api/interpreter")!,
    ]

    private let lock = NSLock()
    private var memory: [WorkoutHexKey: Set<WorkoutHexKey>] = [:]
    private var diskMisses: Set<WorkoutHexKey> = []
    private var inFlight: [WorkoutHexKey: Task<Set<WorkoutHexKey>?, Never>] = [:]
    private var failures: [WorkoutHexKey: (count: Int, at: Date)] = [:]

    /// Thread-safe; the map renderer reads this while drawing, so a zone missing
    /// from disk is remembered rather than re-read on every map tile.
    func cached(_ zone: WorkoutHexKey) -> Set<WorkoutHexKey>? {
        let known: (Set<WorkoutHexKey>?, Bool) = lock.withLock { (memory[zone], diskMisses.contains(zone)) }
        if let tiles = known.0 { return tiles }
        guard !known.1 else { return nil }
        let tiles = Self.readDisk(zone)
        lock.withLock { if let tiles { memory[zone] = tiles } else { diskMisses.insert(zone) } }
        return tiles
    }

    /// Short, growing pauses between retries: 2s, 5s, 15s, then 30s.
    func retryDelay(_ zone: WorkoutHexKey) -> TimeInterval? {
        lock.withLock {
            guard let failure = failures[zone] else { return nil }
            let wait = [2.0, 5, 15, 30][min(failure.count, 4) - 1]
            return max(0, wait - Date().timeIntervalSince(failure.at))
        }
    }

    /// Several failures in a row usually means the phone is offline.
    func seemsOffline(_ zone: WorkoutHexKey) -> Bool {
        lock.withLock { (failures[zone]?.count ?? 0) >= 3 }
    }

    /// Loads a zone's street tiles, fetching them once if this device has never seen it.
    func load(_ zone: WorkoutHexKey) async -> Set<WorkoutHexKey>? {
        if let tiles = cached(zone) { return tiles }
        if let wait = retryDelay(zone), wait > 0 { return nil }
        let task: Task<Set<WorkoutHexKey>?, Never> = lock.withLock {
            if let running = inFlight[zone] { return running }
            let task = Task<Set<WorkoutHexKey>?, Never> { await Self.fetch(zone) }
            inFlight[zone] = task
            return task
        }
        let tiles = await task.value
        lock.withLock {
            inFlight[zone] = nil
            if let tiles {
                memory[zone] = tiles
                diskMisses.remove(zone)
                failures[zone] = nil
            } else {
                failures[zone] = ((failures[zone]?.count ?? 0) + 1, Date())
            }
        }
        if let tiles {
            Self.writeDisk(tiles, zone: zone)
            await MainActor.run { NotificationCenter.default.post(name: Self.didLoad, object: zone) }
        }
        return tiles
    }

    /// Warms the six zones around one you are in, one at a time, so walking or
    /// panning into a neighbour shows its streets immediately.
    func prefetchNeighbors(of zone: WorkoutHexKey) {
        Task(priority: .utility) {
            for neighbor in zone.neighbors where cached(neighbor) == nil {
                _ = await load(neighbor)
            }
        }
    }

    private static func fetch(_ zone: WorkoutHexKey) async -> Set<WorkoutHexKey>? {
        if let streets = await fetchFromCache(zone) { return streetTiles(streets, in: zone) }
        for endpoint in overpassEndpoints {
            if let streets = await fetchFromOverpass(zone, endpoint: endpoint) { return streetTiles(streets, in: zone) }
        }
        return nil
    }

    /// The zone's bounding box (south, west, north, east), padded 3% so streets on
    /// the edge are included and rounded so every phone asks for the identical box.
    static func box(_ zone: WorkoutHexKey) -> [Double] {
        let corners = zone.vertices(scale: 20).map(\.coordinate)
        let lats = corners.map(\.latitude), lons = corners.map(\.longitude)
        let (south, north, west, east) = (lats.min() ?? 0, lats.max() ?? 0, lons.min() ?? 0, lons.max() ?? 0)
        let padLat = (north - south) * 0.03, padLon = (east - west) * 0.03
        return [south - padLat, west - padLon, north + padLat, east + padLon].map { ($0 * 100_000).rounded() / 100_000 }
    }

    private static func fetchFromCache(_ zone: WorkoutHexKey) async -> [[CLLocationCoordinate2D]]? {
        var components = URLComponents(url: cacheBase.appendingPathComponent(zone.storageID + ".json"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "b", value: box(zone).map { String(format: "%.5f", $0) }.joined(separator: ","))]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Nanobeasts/1.0 (iOS walking game)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(CachedStreets.self, from: data) else { return nil }
        // Each street is [lat0, lon0, dLat1, dLon1, …] in 0.00001° steps (~1 m):
        // the first point, then each point's change from the one before.
        return result.ways.map { encoded in
            var lat = 0, lon = 0
            return stride(from: 0, to: encoded.count - 1, by: 2).map { i in
                lat = i == 0 ? encoded[i] : lat + encoded[i]
                lon = i == 0 ? encoded[i + 1] : lon + encoded[i + 1]
                return CLLocationCoordinate2D(latitude: Double(lat) / 100_000, longitude: Double(lon) / 100_000)
            }
        }
    }

    private static func fetchFromOverpass(_ zone: WorkoutHexKey, endpoint: URL) async -> [[CLLocationCoordinate2D]]? {
        let bounds = box(zone)
        let (south, west, north, east) = (bounds[0], bounds[1], bounds[2], bounds[3])
        // Public streets people walk; motorways, private roads and parking aisles are left
        // out. "skel" drops names and tags, so the reply is a fraction of the size.
        let query = """
        [out:json][timeout:20];
        way["highway"~"^(primary|secondary|tertiary|residential|unclassified|living_street|pedestrian|primary_link|secondary_link|tertiary_link)$"]["access"!~"^(private|no)$"](\(south),\(west),\(north),\(east));
        out skel geom qt;
        """
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Nanobeasts/1.0 (iOS walking game)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(("data=" + (query.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")).utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(OverpassResult.self, from: data),
              // A "remark" means the server ran out of time and the list may be partial.
              result.remark == nil else { return nil }
        return result.elements.map { $0.geometry?.map(\.coordinate) ?? [] }
    }

    /// Tiles inside `zone` that the given street lines pass through.
    static func streetTiles(_ streets: [[CLLocationCoordinate2D]], in zone: WorkoutHexKey) -> Set<WorkoutHexKey> {
        streets.reduce(into: Set<WorkoutHexKey>()) { result, street in
            result.formUnion(WorkoutHexGrid.tiles(route: street).filter { $0.district == zone })
        }
    }

    private struct OverpassResult: Decodable {
        struct Element: Decodable { let geometry: [Point]? }
        struct Point: Decodable {
            let lat: Double, lon: Double
            var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
        }
        let elements: [Element]
        let remark: String?
    }

    private struct CachedStreets: Decodable { let ways: [[Int]] }

    private static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Nanobeasts/zone-streets-v1", isDirectory: true)
    }

    private static func readDisk(_ zone: WorkoutHexKey) -> Set<WorkoutHexKey>? {
        guard let url = directory?.appendingPathComponent(zone.storageID + ".json"),
              let data = try? Data(contentsOf: url),
              let pairs = try? JSONDecoder().decode([[Int]].self, from: data) else { return nil }
        return Set(pairs.compactMap { $0.count == 2 ? WorkoutHexKey(band: zone.band, q: $0[0], r: $0[1]) : nil })
    }

    private static func writeDisk(_ tiles: Set<WorkoutHexKey>, zone: WorkoutHexKey) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pairs = tiles.map { [$0.q, $0.r] }
        try? JSONEncoder().encode(pairs).write(to: directory.appendingPathComponent(zone.storageID + ".json"))
    }
}

/// How much of a zone's streets have been walked.
struct WorkoutZoneProgress: Equatable {
    let walked: Int
    let total: Int

    /// 90% of a zone's streets masters it. Every last dead end and service road is
    /// not a fair ask, so the remaining streets are a bonus, not a requirement.
    static let masteryThreshold = 0.9

    var fraction: Double { total > 0 ? Double(walked) / Double(total) : 0 }
    var isMastered: Bool { total > 0 && fraction >= Self.masteryThreshold }
    var percent: Double { fraction * 100 }

    /// A street tile counts once you walked it or the tile beside it: sidewalks sit
    /// a few meters off the centerline that OpenStreetMap draws.
    init(streets: Set<WorkoutHexKey>, walked isWalked: (WorkoutHexKey) -> Bool) {
        total = streets.count
        walked = streets.reduce(0) { count, tile in
            count + (isWalked(tile) || tile.neighbors.contains(where: isWalked) ? 1 : 0)
        }
    }
}

// MARK: - Names

/// "Himrod St" / "Brooklyn": the street at a zone's center names it, so
/// neighbouring zones in one borough stay distinct.
@MainActor
enum WorkoutZoneNames {
    private static var cache: [WorkoutHexKey: (name: String, area: String)] = [:]

    static func cached(_ zone: WorkoutHexKey) -> (name: String, area: String)? { cache[zone] }

    /// A geocoder handles one lookup at a time, so each zone gets its own, and a
    /// failed lookup (busy, offline) is retried a few times before giving up.
    static func name(for zone: WorkoutHexKey) async -> (name: String, area: String) {
        if let cached = cache[zone] { return cached }
        let center = WorkoutHexGrid.center(q: zone.q, r: zone.r, radius: zone.radius * 20).coordinate
        var found: CLPlacemark?
        for attempt in 0..<4 where found == nil && !Task.isCancelled {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt) * 3)) }
            found = try? await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: center.latitude, longitude: center.longitude)).first
        }
        guard let mark = found else { return ("This zone", "") }
        let area = mark.subLocality ?? mark.locality ?? ""
        let name = mark.thoroughfare ?? (area.isEmpty ? "This zone" : area)
        let result = (name, name == area ? "" : area)
        cache[zone] = result
        return result
    }
}

// MARK: - Completions

struct WorkoutZoneCompletion: Identifiable {
    let zone: WorkoutHexKey
    let name: String
    let area: String
    let streetTiles: Set<WorkoutHexKey>
    let walkedTiles: Set<WorkoutHexKey>
    let percent: Double
    let completedAt: Date
    let ordinal: Int
    var id: String { zone.storageID }
}

/// Remembers which zones were celebrated, so each mastery is celebrated exactly once.
enum WorkoutZoneLedger {
    private static let key = "nanobeasts.workout.completedZones.v1"

    static var completed: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    /// Records a mastered zone in the order zones were mastered; returns its number
    /// ("Zone #3"). Recording one twice keeps its original number.
    static func markCompleted(_ zone: WorkoutHexKey) -> Int {
        var zones = UserDefaults.standard.stringArray(forKey: key) ?? []
        if let index = zones.firstIndex(of: zone.storageID) { return index + 1 }
        zones.append(zone.storageID)
        UserDefaults.standard.set(zones, forKey: key)
        return zones.count
    }

    /// The number a zone gets ("Zone #3") without recording it yet.
    static func ordinal(for zone: WorkoutHexKey) -> Int {
        let zones = UserDefaults.standard.stringArray(forKey: key) ?? []
        return (zones.firstIndex(of: zone.storageID) ?? zones.count) + 1
    }
}

/// One place that notices mastered zones, whichever device recorded the walk: phone
/// walks, Apple Watch walks and Health imports all arrive as explored routes. Each
/// mastered zone is queued once and shown by whichever workout screen is on top.
@MainActor
final class WorkoutZoneCelebrations: ObservableObject {
    static let shared = WorkoutZoneCelebrations()
    @Published private(set) var pending: [WorkoutZoneCompletion] = []
    private var checking: Task<Void, Never>?
    private var queuedZones: Set<WorkoutHexKey> = []

    /// Called whenever explored territory changes. Checks the zones the routes cross.
    func territoryChanged(_ routes: [[CLLocationCoordinate2D]]) {
        let previous = checking
        checking = Task { [weak self] in
            await previous?.value                     // one check at a time, in order
            let walked = await Task.detached(priority: .utility) { WorkoutHexGrid.tiles(routes: routes) }.value
            // A mastered zone has hundreds of street tiles; skip zones barely touched.
            let candidates = Dictionary(grouping: walked, by: \.district).filter { $0.value.count >= 40 }.keys
            for zone in candidates {
                guard let self, !WorkoutZoneLedger.completed.contains(zone.storageID),
                      !self.queuedZones.contains(zone) else { continue }
                guard let streets = await WorkoutZoneStreets.shared.load(zone), !streets.isEmpty else { continue }
                let progress = WorkoutZoneProgress(streets: streets, walked: walked.contains)
                guard progress.isMastered else { continue }
                let label = await WorkoutZoneNames.name(for: zone)
                self.queuedZones.insert(zone)
                self.pending.append(WorkoutZoneCompletion(
                    zone: zone, name: label.name, area: label.area, streetTiles: streets,
                    walkedTiles: walked.filter { $0.district == zone }, percent: progress.percent,
                    completedAt: Date(), ordinal: WorkoutZoneLedger.ordinal(for: zone)))
            }
        }
    }

    /// The celebration being shown is recorded, so it never appears again.
    func shown(_ completion: WorkoutZoneCompletion) {
        _ = WorkoutZoneLedger.markCompleted(completion.zone)
    }

    func dismissFirst() {
        guard !pending.isEmpty else { return }
        pending.removeFirst()
    }

    /// Binding for a screen's full-screen cover; nil whenever that screen shouldn't show it.
    func binding(when visible: Bool) -> Binding<WorkoutZoneCompletion?> {
        Binding(get: { visible ? self.pending.first : nil },
                set: { if $0 == nil { self.dismissFirst() } })
    }
}

// MARK: - Trail drawing

/// The walked-trail look shared by the live map, replays and share images:
/// tiles in the user's accent, one clean outline, older walks softer.
enum WorkoutTrailPainter {
    /// `outline` (tiles grown slightly) draws the edge with fills, far cheaper than
    /// stroking thousands of hexagons; without it the edge is stroked `rimWidth` wide.
    static func paint(explored: CGPath, walking: CGPath, accent: UIColor, isDark: Bool,
                      rimWidth: CGFloat, outline: CGPath? = nil, in context: CGContext) {
        context.saveGState()
        guard rimWidth > 0 else {
            context.addPath(explored)
            context.setFillColor(accent.withAlphaComponent(isDark ? 0.45 : 0.5).cgColor)
            context.fillPath()
            context.addPath(walking)
            context.setFillColor(accent.withAlphaComponent(0.92).cgColor)
            context.fillPath()
            context.restoreGState()
            return
        }
        let all = CGMutablePath()
        all.addPath(explored)
        all.addPath(walking)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        // Stroke every tile, then erase the interiors, leaving only the trail's
        // outer edge (no honeycomb lines inside it).
        if let outline {
            context.addPath(outline)
            context.setFillColor(rim(for: accent).cgColor)
            context.fillPath()
        } else {
            context.addPath(all)
            context.setStrokeColor(rim(for: accent).cgColor)
            context.setLineWidth(rimWidth * 2)
            context.setLineJoin(.round)
            context.strokePath()
        }
        context.setBlendMode(.destinationOut)
        context.addPath(all)
        context.setFillColor(UIColor.black.cgColor)
        context.fillPath()
        context.setBlendMode(.normal)
        context.addPath(explored)
        context.setFillColor(accent.withAlphaComponent(isDark ? 0.45 : 0.5).cgColor)
        context.fillPath()
        context.addPath(walking)
        context.setFillColor(accent.withAlphaComponent(0.92).cgColor)
        context.fillPath()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    static func rim(for accent: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        accent.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * 0.6, green: g * 0.6, blue: b * 0.6, alpha: 1)
    }

    static func hexPath(_ tiles: some Sequence<WorkoutHexKey>, project: (MKMapPoint) -> CGPoint) -> CGMutablePath {
        let path = CGMutablePath()
        for tile in tiles {
            let points = tile.vertices().map(project)
            path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Celebration

/// Full-screen moment for a mastered zone: its collectible zone card, with the
/// foil shimmering and the stamp landing, plus a 9:16 image ready to post.
struct WorkoutZoneCelebrationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let completion: WorkoutZoneCompletion
    @State private var map: UIImage?
    @State private var shareImage: UIImage?
    @State private var revealed = false
    @State private var stamped = false

    private var accent: Color { Color(UIColor(NanoAccentPreference.current.color)) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            WorkoutHexBurst(color: accent, active: stamped && !reduceMotion)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white).frame(width: 44, height: 44)
                            .background(Circle().fill(.white.opacity(0.14)))
                    }
                    .accessibilityLabel("Close")
                }
                Spacer(minLength: 0)
                WorkoutZoneCard(completion: completion, map: map, accent: accent,
                                stamped: stamped || reduceMotion, shimmers: !reduceMotion)
                    .frame(width: 360, height: 640)
                    .scaleEffect(min(1, 0.92 * UIScreen.main.bounds.height / 760))
                    .frame(maxHeight: .infinity)
                    .scaleEffect(revealed || reduceMotion ? 1 : 0.9)
                    .opacity(revealed ? 1 : 0)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Zone card: \(completion.name) mastered")
                Spacer(minLength: 0)
                if let shareImage {
                    ShareLink(item: Image(uiImage: shareImage),
                              preview: SharePreview("\(completion.name) · Mastered", image: Image(uiImage: shareImage))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Capsule().fill(accent))
                    }
                }
                Button("Keep exploring") { dismiss() }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 22).padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .task {
            WorkoutZoneCelebrations.shared.shown(completion)
            map = await WorkoutZoneCardRenderer.map(for: completion, accent: UIColor(NanoAccentPreference.current.color))
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.6, bounce: 0.25)) { revealed = true }
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(650)) }
            // The stamp thuds onto the map.
            withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.45)) { stamped = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            shareImage = WorkoutZoneCardRenderer.image(completion, map: map, accent: accent)
        }
    }
}

/// Accent hexagons flying outward once, behind the card.
private struct WorkoutHexBurst: View {
    let color: Color
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.45)
            ForEach(0..<26, id: \.self) { index in
                let angle = Double(index) / 26 * 2 * .pi + Double(index % 3) * 0.2
                let distance = proxy.size.width * (0.45 + Double(index % 5) * 0.09)
                Image(systemName: "hexagon.fill")
                    .font(.system(size: CGFloat(10 + (index % 4) * 6)))
                    .foregroundStyle(color.opacity(0.4 + Double(index % 3) * 0.2))
                    .position(x: center.x + (active ? cos(angle) * distance : 0),
                              y: center.y + (active ? sin(angle) * distance : 0))
                    .opacity(active ? 0 : 1)
                    .scaleEffect(active ? 1.4 : 0.2)
                    .animation(.easeOut(duration: 1.4).delay(Double(index % 6) * 0.03), value: active)
            }
        }
    }
}

/// The zone's map with its walked streets, and the still 9:16 share image.
@MainActor
enum WorkoutZoneCardRenderer {
    static func image(_ completion: WorkoutZoneCompletion, map: UIImage?, accent: Color) -> UIImage? {
        let card = WorkoutZoneCard(completion: completion, map: map, accent: accent, stamped: true, shimmers: false)
            .frame(width: 360, height: 640)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    static func map(for completion: WorkoutZoneCompletion, accent: UIColor) async -> UIImage? {
        let outline = completion.zone.vertices(scale: 20)
        var rect = MKMapRect.null
        for point in outline { rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0))) }
        let side = max(rect.width, rect.height) * 1.08
        let options = MKMapSnapshotter.Options()
        options.mapRect = MKMapRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        options.size = CGSize(width: 272, height: 272)
        options.scale = 3
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.emphasisStyle = .muted
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(size: options.size, format: format).image { context in
            snapshot.image.draw(at: .zero)
            let cg = context.cgContext
            let project = { (point: MKMapPoint) in snapshot.point(for: point.coordinate) }
            let zonePath = CGMutablePath()
            let corners = outline.map(project)
            zonePath.move(to: corners[0])
            corners.dropFirst().forEach { zonePath.addLine(to: $0) }
            zonePath.closeSubpath()
            cg.addPath(zonePath)
            cg.setFillColor(accent.withAlphaComponent(0.12).cgColor)
            cg.fillPath()
            WorkoutTrailPainter.paint(
                explored: CGMutablePath(),
                walking: WorkoutTrailPainter.hexPath(completion.walkedTiles, project: project),
                accent: accent, isDark: true, rimWidth: 0.8, in: cg)
            cg.addPath(zonePath)
            cg.setStrokeColor(accent.cgColor)
            cg.setLineWidth(1.6)
            cg.strokePath()
        }
    }
}

/// A mastered zone as a collectible card: numbered, foil-edged, stamped. No
/// percentage and no single creature, so every mastery reads as a win.
private struct WorkoutZoneCard: View {
    let completion: WorkoutZoneCompletion
    let map: UIImage?
    let accent: Color
    let stamped: Bool
    let shimmers: Bool
    @State private var foilTurn = 0.0

    private let ink = Color(red: 0.035, green: 0.035, blue: 0.045)

    var body: some View {
        ZStack {
            ink
            RadialGradient(colors: [accent.opacity(0.35), .clear], center: .init(x: 0.5, y: 0.42),
                           startRadius: 10, endRadius: 330)
            VStack(spacing: 0) {
                card
                    .padding(.horizontal, 24)
                    .padding(.top, 54)
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    Text("NANOBEASTS")
                        .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(4)
                        .foregroundStyle(accent)
                    Text("Walk your streets. Master your neighborhood.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Street data © OpenStreetMap contributors")
                        .font(.system(size: 7)).foregroundStyle(.white.opacity(0.35)).padding(.top, 6)
                }
                .padding(.bottom, 22)
            }
        }
        .onAppear {
            guard shimmers else { return }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { foilTurn = 360 }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("ZONE CARD", systemImage: "hexagon.fill")
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(2)
                    .foregroundStyle(accent)
                Spacer()
                Text(String(format: "No. %03d", completion.ordinal))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(completion.name)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !completion.area.isEmpty {
                    Text(completion.area.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.6)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let map { Image(uiImage: map).resizable().scaledToFill() }
                    else { Color.white.opacity(0.05) }
                }
                .frame(width: 272, height: 272)
                .clipped()
                .overlay(LinearGradient(colors: [.clear, .white.opacity(0.16), .clear],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                stamp
                    .offset(x: 22, y: 22)
                    .scaleEffect(stamped ? 1 : 2.2)
                    .opacity(stamped ? 1 : 0)
            }
            .padding(.top, 4)
            HStack(spacing: 0) {
                stat(completion.walkedTiles.count.formatted(), "TILES PAINTED")
                divider
                stat("#\(completion.ordinal)", "ZONE")
                divider
                stat(completion.completedAt.formatted(.dateTime.month(.abbreviated).day()).uppercased(), "MASTERED")
            }
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
            .padding(.top, 10)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(red: 0.07, green: 0.075, blue: 0.085)))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(AngularGradient(colors: [accent, Color(red: 0.4, green: 0.6, blue: 1),
                                                       Color(red: 0.75, green: 0.5, blue: 1), Color(red: 1, green: 0.55, blue: 0.75),
                                                       Color(red: 1, green: 0.85, blue: 0.45), accent],
                                              center: .center, angle: .degrees(foilTurn)), lineWidth: 3)
        )
    }

    private var stamp: some View {
        ZStack {
            Circle().fill(ink)
            Circle().strokeBorder(accent, lineWidth: 3)
            Circle().strokeBorder(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).padding(7)
            VStack(spacing: 1) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(accent)
                Text("MASTERED")
                    .font(.system(size: 11, weight: .black, design: .rounded)).tracking(1.2)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 92, height: 92)
        .rotationEffect(.degrees(-12))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 8, weight: .bold, design: .rounded)).tracking(1)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 26)
    }
}
