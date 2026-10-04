// The runner uses the production SwiftUI card and fonts with AppKit's image
// adapter. This verifies offscreen layout/PNG output, not iOS interaction.
struct CreatureStage { let name: String }
struct CreatureDiscoveryEvent {
    let name: String
    let kind: Kind
    enum Kind { case evolution; var title: String { "Evolved" } }
}
@MainActor
func verifyExports() throws {
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
CTFontManagerRegisterFontsForURL(root.appendingPathComponent("Nanobeasts/Resources/Fonts/Aldrich_400Regular.ttf") as CFURL, .process, nil)
let route: [CLLocationCoordinate2D] = [
    .init(latitude: 40.694, longitude: -73.9214), .init(latitude: 40.6978, longitude: -73.9168),
    .init(latitude: 40.7011, longitude: -73.9196), .init(latitude: 40.7044, longitude: -73.9143),
    .init(latitude: 40.7082, longitude: -73.9177), .init(latitude: 40.7059, longitude: -73.9231),
    .init(latitude: 40.7005, longitude: -73.9256), .init(latitude: 40.6962, longitude: -73.9228)
]
let payload = WorkoutSharePayload(workoutName: "Outdoor Walk", workoutSymbol: "figure.walk",
    elapsedSeconds: 1595, steps: 4286, distanceMiles: 3.12, calories: 225, isIndoor: false,
    route: route, territoryTiles: 28, companion: .init(name: "Komantis"), rewards: [])
let photo = NSImage(contentsOf: root.appendingPathComponent("Nanobeasts/Resources/Assets.xcassets/WorkoutShareDemo.imageset/workout-share-demo.png"))!
func solidPhoto(_ size: CGSize) -> NSImage {
    NSImage(size: size, flipped: false) { rect in
        NSColor(calibratedRed: 0.18, green: 0.26, blue: 0.33, alpha: 1).setFill()
        rect.fill()
        return true
    }
}
// The overlay must remain fully inside the canvas at every size and position,
// and have the same normalized bounds in preview and export.
var pinched = WorkoutSharePlacement(scale: 1.2)
pinched.resize(by: 0.75, from: 1.2)
precondition(abs(pinched.scale - 0.9) < 0.0001)
pinched.resize(by: 0.8, from: 1.2)
precondition(abs(pinched.scale - 0.96) < 0.0001, "Gesture samples must not compound")
let nextOrigin = pinched.scale
pinched.resize(by: 1.25, from: nextOrigin)
precondition(abs(pinched.scale - 1.2) < 0.0001, "A second pinch starts at the current size")
pinched.resize(by: 10, from: 1.2)
precondition(pinched.scale == 1.5)
pinched.resize(by: 0.01, from: 1.2)
precondition(pinched.scale == 0.65)
pinched.resize(by: .nan, from: 1.2)
precondition(pinched.scale == 0.65)
print("PASS: pinch sizing is cumulative between gestures, bounded, and stable within a gesture")
for canvas in [CGSize(width: 1080, height: 1920), CGSize(width: 1080, height: 1350)] {
    for scale in [0.65, 1.0, 1.5] {
        for center in [CGPoint(x: -1, y: -1), CGPoint(x: 0.7, y: 0.3), CGPoint(x: 2, y: 2)] {
            let placement = WorkoutSharePlacement(center: center, scale: scale)
            let full = placement.rect(in: canvas)
            precondition(CGRect(origin: .zero, size: canvas).contains(full))
            let preview = placement.rect(in: CGSize(width: canvas.width / 4, height: canvas.height / 4))
            precondition(abs(full.minX / 4 - preview.minX) < 0.001)
            precondition(abs(full.minY / 4 - preview.minY) < 0.001)
            precondition(abs(full.width / 4 - preview.width) < 0.001)
        }
    }
}
print("PASS: overlay stays inside edges and preview matches export at all sizes")
for (name, style, background, grid) in [
    ("photo", WorkoutShareStyle.photo, photo, false),
    ("photo-moved", .photo, photo, false),
    ("transparent-moved", .sticker, photo, false),
    ("landscape-photo", .photo, solidPhoto(CGSize(width: 2400, height: 800)), false),
    ("portrait-photo", .photo, solidPhoto(CGSize(width: 800, height: 2400)), false),
    ("route", .route, photo, false),
    ("transparent", .sticker, photo, false),
    ("transparent-preview", .sticker, photo, true)
] {
    let placement = name.contains("moved")
        ? WorkoutSharePlacement(center: CGPoint(x: 0.78, y: 0.28), scale: 0.65)
        : WorkoutSharePlacement()
    let card = WorkoutShareCard(payload: payload, style: style, photo: background,
        placement: placement, showsTransparencyGrid: grid)
        .frame(width: style.canvasSize.width, height: style.canvasSize.height)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: card)
    renderer.proposedSize = ProposedViewSize(style.canvasSize)
    renderer.scale = 1
    renderer.isOpaque = style != .sticker || grid
    guard let cgImage = renderer.cgImage else { fatalError("Rendering failed: \(name)") }
    precondition(cgImage.width == Int(style.canvasSize.width) && cgImage.height == Int(style.canvasSize.height))
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent("\(name).png"))
    if style == .route {
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 20) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 20) {
                precondition(bitmap.colorAt(x: x, y: y)!.alphaComponent == 1,
                             "Route card must be a complete opaque image")
            }
        }
    }
    if style == .sticker && !grid {
        precondition(bitmap.hasAlpha)
        for x in 0..<bitmap.pixelsWide {
            precondition(bitmap.colorAt(x: x, y: 0)!.alphaComponent == 0)
            precondition(bitmap.colorAt(x: x, y: bitmap.pixelsHigh - 1)!.alphaComponent == 0)
        }
        for y in 0..<bitmap.pixelsHigh {
            precondition(bitmap.colorAt(x: 0, y: y)!.alphaComponent == 0)
            precondition(bitmap.colorAt(x: bitmap.pixelsWide - 1, y: y)!.alphaComponent == 0)
        }
        var transparent = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 10) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 10) {
                if bitmap.colorAt(x: x, y: y)!.alphaComponent == 0 { transparent += 1 }
            }
        }
        precondition(transparent > 10_000, "Sticker background must remain transparent")
    }
    print("PASS: \(name), \(cgImage.width)×\(cgImage.height)")
}

}
try MainActor.assumeIsolated { try verifyExports() }
