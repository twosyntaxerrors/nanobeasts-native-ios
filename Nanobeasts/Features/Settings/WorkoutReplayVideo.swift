import AVFoundation
import MapKit
import SwiftUI

struct WorkoutReplayVideoTiming {
    let framesPerSecond: Int32 = 30
    let routeDuration: Double
    let endingDuration = 3.0
    var frameCount: Int { Int(ceil((routeDuration + endingDuration) * Double(framesPerSecond))) }

    init(speed: Double) {
        routeDuration = 30 / ([1.0, 2.0, 4.0].contains(speed) ? speed : 1)
    }

    func routeProgress(frame: Int) -> Double {
        min(1, max(0, Double(frame) / Double(framesPerSecond) / routeDuration))
    }

    func endingOpacity(frame: Int) -> Double {
        min(1, max(0, (Double(frame) / Double(framesPerSecond) - routeDuration) / 0.35))
    }
}

enum WorkoutReplayVideoError: LocalizedError {
    case unavailableRoute, artwork, image, encoding(String)
    var errorDescription: String? {
        switch self {
        case .unavailableRoute: "This workout has no recorded route to share."
        case .artwork: "Your companion’s artwork isn’t available yet. Connect to the internet and try again."
        case .image: "The video artwork couldn’t be prepared. Please try again."
        case .encoding(let detail): "The video couldn’t be saved. \(detail)"
        }
    }
}

/// Exports locally from saved GPS. There are no Health or exploration writes.
enum WorkoutReplayVideoExporter {
    static let canvas = CGSize(width: 1080, height: 1920)
    static let mapFrame = CGRect(x: 48, y: 520, width: 984, height: 1210)

    @MainActor
    static func export(payload: WorkoutSharePayload, companion: CreatureStage, artwork: UIImage,
                       distanceUnit: DistanceUnitPreference, speed: Double,
                       progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let exportStarted = Date()
        let track = WorkoutRouteReplayTrack(route: payload.route, breakIndices: payload.routeBreakIndices)
        guard track.canReplay else { throw WorkoutReplayVideoError.unavailableRoute }
        let options = MKMapSnapshotter.Options()
        options.size = mapFrame.size
        options.scale = 1
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.mapRect = WorkoutReplayMapBounds.rect(for: track.coordinates, padding: 0.24)
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.emphasisStyle = .muted
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot = try await withTaskCancellationHandler {
            try await snapshotter.start()
        } onCancel: {
            snapshotter.cancel()
        }
        try Task.checkCancellation()
        let snapshotSeconds = Date().timeIntervalSince(exportStarted)
        progress(0.05)
        guard let chrome = WorkoutReplayVideoArtwork.chrome(payload: payload, companion: companion,
                                                            unit: distanceUnit),
              let ending = WorkoutReplayVideoArtwork.ending(payload: payload, companion: companion,
                                                            artwork: artwork, unit: distanceUnit)
        else { throw WorkoutReplayVideoError.image }
        let accent = UIColor(NanoTheme.teal)
        let timing = WorkoutReplayVideoTiming(speed: speed)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WorkoutVideos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Leave completed files available to share extensions; reclaim them later.
        let oldFiles = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in oldFiles {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               date < Date().addingTimeInterval(-86_400) { try? FileManager.default.removeItem(at: file) }
        }
        let url = directory.appendingPathComponent("Nanobeasts-Route-\(UUID().uuidString).mp4")
        let preparationSeconds = Date().timeIntervalSince(exportStarted)
        let render = Task.detached(priority: .userInitiated) {
            try await encode(url: url, track: track, snapshot: snapshot, artwork: artwork,
                             chrome: chrome, ending: ending, accent: accent, timing: timing, preparationSeconds: preparationSeconds, snapshotSeconds: snapshotSeconds, progress: progress)
            return url
        }
        return try await withTaskCancellationHandler {
            try await render.value
        } onCancel: {
            render.cancel()
        }
    }

    private static func encode(url: URL, track: WorkoutRouteReplayTrack, snapshot: MKMapSnapshotter.Snapshot,
                               artwork: UIImage, chrome: UIImage, ending: UIImage, accent: UIColor,
                               timing: WorkoutReplayVideoTiming, preparationSeconds: Double, snapshotSeconds: Double,
                               progress: @escaping @MainActor (Double) -> Void) async throws {
        let encodeStarted = Date()
        var profile: [String: Double] = ["preparation": preparationSeconds, "snapshot": snapshotSeconds]
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(canvas.width), AVVideoHeightKey: Int(canvas.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(canvas.width),
            kCVPixelBufferHeightKey as String: Int(canvas.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        guard writer.canAdd(input) else { throw WorkoutReplayVideoError.encoding("Video encoding is unavailable.") }
        writer.add(input)
        writer.shouldOptimizeForNetworkUse = true
        var succeeded = false
        defer {
            if !succeeded {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
            }
        }
        guard writer.startWriting() else { throw writer.error ?? WorkoutReplayVideoError.encoding("Please try again.") }
        writer.startSession(atSourceTime: .zero)
        let preparationStarted = Date()
        let prepared = try WorkoutReplayPreparedFrames(snapshot: snapshot.image, chrome: chrome,
                                                       artwork: artwork, ending: ending, accent: accent)
        profile["rasterPreparation"] = Date().timeIntervalSince(preparationStarted)
        let projected = track.coordinates.map { snapshot.point(for: $0) }
        var closingFrame: CVPixelBuffer?
        for index in 0..<timing.frameCount {
            try Task.checkCancellation()
            let waitStarted = ContinuousClock.now
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else {
                    throw writer.error ?? WorkoutReplayVideoError.encoding("The encoder stopped unexpectedly.")
                }
                guard waitStarted.duration(to: .now) < .seconds(20) else {
                    throw WorkoutReplayVideoError.encoding("The encoder stopped responding. Please try again.")
                }
                try await Task.sleep(for: .milliseconds(4))
            }
            let waited = waitStarted.duration(to: .now).components
            profile["encoderWait", default: 0] += Double(waited.seconds) + Double(waited.attoseconds) / 1e18
            let frameStarted = Date()
            try autoreleasepool {
                let time = CMTime(value: Int64(index), timescale: timing.framesPerSecond)
                if let closingFrame {
                    // The complete closing card is static. Retain this immutable buffer
                    // and encode it at each timestamp without drawing it again.
                    guard adaptor.append(closingFrame, withPresentationTime: time) else {
                        throw writer.error ?? WorkoutReplayVideoError.encoding("A video frame couldn’t be written.")
                    }
                    return
                }
                guard let pool = adaptor.pixelBufferPool else { throw WorkoutReplayVideoError.image }
                var allocated: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &allocated) == kCVReturnSuccess,
                      let buffer = allocated else { throw WorkoutReplayVideoError.image }
                CVPixelBufferLockBaseAddress(buffer, [])
                defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                    width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
                else { throw WorkoutReplayVideoError.image }
                context.translateBy(x: 0, y: canvas.height)
                context.scaleBy(x: 1, y: -1)
                UIGraphicsPushContext(context)
                defer { UIGraphicsPopContext() }
                try drawFrame(context, track: track, projected: projected, snapshot: snapshot, prepared: prepared, accent: accent,
                          routeProgress: timing.routeProgress(frame: index), endingOpacity: timing.endingOpacity(frame: index), profile: &profile)
                guard adaptor.append(buffer, withPresentationTime: time) else {
                    throw writer.error ?? WorkoutReplayVideoError.encoding("A video frame couldn’t be written.")
                }
                if timing.endingOpacity(frame: index) >= 1 { closingFrame = buffer }
            }
            profile["frames", default: 0] += Date().timeIntervalSince(frameStarted)
            if index.isMultiple(of: 6) { await progress(0.05 + 0.94 * Double(index + 1) / Double(timing.frameCount)) }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: Int64(timing.frameCount), timescale: timing.framesPerSecond))
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else {
            throw writer.error ?? WorkoutReplayVideoError.encoding("Please check free storage and try again.")
        }
        succeeded = true
        profile["encode"] = Date().timeIntervalSince(encodeStarted)
        profile["total"] = preparationSeconds + Date().timeIntervalSince(encodeStarted)
        profile["frameCount"] = Double(timing.frameCount)
#if DEBUG && targetEnvironment(simulator)
        if let data = try? JSONSerialization.data(withJSONObject: profile, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url.deletingPathExtension().appendingPathExtension("json"))
        }
#endif
        await progress(1)
    }

    private static func drawFrame(_ context: CGContext, track: WorkoutRouteReplayTrack, projected: [CGPoint],
                                  snapshot: MKMapSnapshotter.Snapshot, prepared: WorkoutReplayPreparedFrames,
                                  accent: UIColor, routeProgress: Double, endingOpacity: Double, profile: inout [String: Double]) throws {
        var phase = Date()
        try prepared.copyBase(to: context)
        context.saveGState()
        UIBezierPath(roundedRect: mapFrame, cornerRadius: 44).addClip()
        profile["mapDraw", default: 0] += Date().timeIntervalSince(phase)
        phase = Date()
        let frame = track.frame(at: routeProgress)
        var points = Array(projected.prefix(max(0, frame.coordinates.count - 1)))
        if let marker = frame.marker { points.append(snapshot.point(for: marker)) }
        let path = CGMutablePath()
        let breaks = Set(frame.breakIndices)
        for (index, point) in points.enumerated() {
            let positioned = CGPoint(x: point.x + mapFrame.minX, y: point.y + mapFrame.minY)
            if index == 0 || breaks.contains(index) { path.move(to: positioned) }
            else { path.addLine(to: positioned) }
        }
        profile["pathGeometry", default: 0] += Date().timeIntervalSince(phase)
        phase = Date()
        // An alpha-only mask avoids rebuilding a full-color transparency layer.
        // The map and its native attribution are already in the cached base.
        try prepared.drawFog(clearing: path, into: context)
        profile["fogDraw", default: 0] += Date().timeIntervalSince(phase)
        phase = Date()
        context.addPath(path)
        context.setLineWidth(9)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(accent.cgColor)
        context.setShadow(offset: .zero, blur: 10, color: accent.withAlphaComponent(0.5).cgColor)
        context.strokePath()
        context.setShadow(offset: .zero, blur: 0)
        if let point = points.last {
            let rect = CGRect(x: point.x + mapFrame.minX - 52, y: point.y + mapFrame.minY - 52, width: 104, height: 104)
            prepared.marker.draw(at: CGPoint(x: rect.minX - 2, y: rect.minY - 2))
        }
        context.restoreGState()
        profile["routeAndMarker", default: 0] += Date().timeIntervalSince(phase)
        phase = Date()
        accent.setFill()
        UIBezierPath(roundedRect: CGRect(x: 72, y: 1840, width: 936 * routeProgress, height: 10), cornerRadius: 5).fill()
        profile["chromeDraw", default: 0] += Date().timeIntervalSince(phase)
        phase = Date()
        if endingOpacity > 0 {
            context.saveGState()
            context.setAlpha(endingOpacity)
            prepared.ending.draw(at: CGPoint(x: 72, y: 540))
            context.restoreGState()
        }
        profile["endingDraw", default: 0] += Date().timeIntervalSince(phase)
    }
}

/// Owned by one export worker. Decode, resize and color-convert static artwork once.
private final class WorkoutReplayPreparedFrames {
    private let base: CGContext
    private let fogMask: CGContext
    private let fogRect: CGRect
    let marker: UIImage
    let ending: UIImage

    init(snapshot: UIImage, chrome: UIImage, artwork: UIImage, ending: UIImage, accent: UIColor) throws {
        let canvas = WorkoutReplayVideoExporter.canvas
        let map = WorkoutReplayVideoExporter.mapFrame
        fogRect = CGRect(x: map.minX, y: map.minY, width: map.width, height: map.height - 65)
        base = try Self.bitmap(size: canvas)
        guard let mask = CGContext(data: nil, width: Int(fogRect.width), height: Int(fogRect.height),
            bitsPerComponent: 8, bytesPerRow: Int(fogRect.width), space: nil,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.alphaOnly.rawValue)) else { throw WorkoutReplayVideoError.image }
        fogMask = mask
        mask.translateBy(x: 0, y: fogRect.height)
        mask.scaleBy(x: 1, y: -1)
        mask.translateBy(x: -fogRect.minX, y: -fogRect.minY)

        UIGraphicsPushContext(base)
        UIColor(red: 0.025, green: 0.03, blue: 0.03, alpha: 1).setFill()
        base.fill(CGRect(origin: .zero, size: canvas))
        base.saveGState()
        UIBezierPath(roundedRect: map, cornerRadius: 44).addClip()
        snapshot.draw(in: map)
        base.restoreGState()
        chrome.draw(in: CGRect(origin: .zero, size: canvas))
        UIColor.white.withAlphaComponent(0.14).setFill()
        UIBezierPath(roundedRect: CGRect(x: 72, y: 1840, width: 936, height: 10), cornerRadius: 5).fill()
        UIGraphicsPopContext()

        marker = try Self.raster(size: CGSize(width: 108, height: 108)) { context in
            let rect = CGRect(x: 2, y: 2, width: 104, height: 104)
            UIColor.black.withAlphaComponent(0.8).setFill()
            let circle = UIBezierPath(ovalIn: rect)
            circle.fill()
            accent.withAlphaComponent(0.7).setStroke()
            circle.lineWidth = 3
            circle.stroke()
            artwork.drawAspectFit(in: rect.insetBy(dx: 7, dy: 7))
        }
        self.ending = try Self.raster(size: CGSize(width: 936, height: 1125)) { context in
            UIColor.black.withAlphaComponent(0.92).setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 936, height: 1125), cornerRadius: 36).fill()
            ending.draw(in: CGRect(x: 18, y: 0, width: 900, height: 1125))
        }
    }

    func copyBase(to destination: CGContext) throws {
        // Pixel buffers can have wider row alignment than our tightly packed base.
        // Both use the same 8-bit BGRA format and color space, so no resampling is needed.
        guard let source = base.data, let target = destination.data else { throw WorkoutReplayVideoError.image }
        for row in 0..<base.height {
            memcpy(target.advanced(by: row * destination.bytesPerRow),
                   source.advanced(by: row * base.bytesPerRow), base.width * 4)
        }
    }

    func drawFog(clearing path: CGPath, into context: CGContext) throws {
        fogMask.setBlendMode(.copy)
        fogMask.setFillColor(UIColor.white.cgColor)
        fogMask.fill(fogRect)
        fogMask.setBlendMode(.destinationOut)
        fogMask.setLineCap(.round)
        fogMask.setLineJoin(.round)
        for (width, alpha) in [(260.0, 0.12), (242.0, 0.16), (224.0, 0.23), (205.0, 0.34), (186.0, 0.50), (168.0, 1.0)] {
            fogMask.addPath(path)
            fogMask.setStrokeColor(UIColor.white.withAlphaComponent(alpha).cgColor)
            fogMask.setLineWidth(width)
            fogMask.strokePath()
        }
        guard let image = fogMask.makeImage() else { throw WorkoutReplayVideoError.image }
        context.saveGState()
        defer { context.restoreGState() }
        // CGImage masks use image coordinates; map them into UIKit's top-down canvas.
        context.translateBy(x: fogRect.minX, y: fogRect.maxY)
        context.scaleBy(x: 1, y: -1)
        let bounds = CGRect(origin: .zero, size: fogRect.size)
        context.clip(to: bounds, mask: image)
        context.setFillColor(UIColor(red: 0.64, green: 0.10, blue: 0.56, alpha: 0.62).cgColor)
        context.fill(bounds)
    }

    private static func bitmap(size: CGSize) throws -> CGContext {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw WorkoutReplayVideoError.image }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        return context
    }

    private static func raster(size: CGSize, draw: (CGContext) -> Void) throws -> UIImage {
        let context = try bitmap(size: size)
        UIGraphicsPushContext(context)
        draw(context)
        UIGraphicsPopContext()
        guard let image = context.makeImage() else { throw WorkoutReplayVideoError.image }
        return UIImage(cgImage: image)
    }
}

private extension UIImage {
    func drawAspectFit(in rect: CGRect) {
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        draw(in: CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                        width: fitted.width, height: fitted.height))
    }
}

enum WorkoutReplayMapBounds {
    static func rect(for route: [CLLocationCoordinate2D], padding: Double) -> MKMapRect {
        var rect = MKPolyline(coordinates: route, count: route.count).boundingMapRect
        let minimum = 200 * MKMapPointsPerMeterAtLatitude(route.first?.latitude ?? 0)
        if rect.width < minimum { rect = rect.insetBy(dx: -(minimum - rect.width) / 2, dy: 0) }
        if rect.height < minimum { rect = rect.insetBy(dx: 0, dy: -(minimum - rect.height) / 2) }
        return rect.insetBy(dx: -rect.width * padding, dy: -rect.height * padding)
    }
}
