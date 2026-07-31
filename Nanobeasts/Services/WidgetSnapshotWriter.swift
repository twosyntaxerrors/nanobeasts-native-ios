import Foundation
import ImageIO
import UIKit
import WidgetKit

@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    private let artworkFilename = "current-nanobeast.png"
    private let artworkSourceKey = "nanobeasts.widget.artwork-source.v1"
    private var artworkTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?

    private init() {
        removeLegacyLivingWidgetCache()
    }

    func update(
        stage: CreatureStage,
        todaySteps: Int,
        dailyGoal: Int,
        evolutionProgress: Double,
        stepsRemaining: Int,
        streak: Int
    ) {
        let snapshot = WidgetSnapshot(
            updatedAt: Date(),
            creatureName: stage.name,
            stage: stage.stage,
            todaySteps: todaySteps,
            dailyGoal: dailyGoal,
            evolutionProgress: evolutionProgress,
            stepsRemaining: stepsRemaining,
            streak: streak,
            artworkFilename: artworkFilename
        )
        WidgetSnapshotStore.save(snapshot)
        scheduleTimelineReload()

        let sourceURL = R2AssetManifest.url(for: stage.imageKey)
        guard let destination = WidgetSnapshotStore.artworkURL(filename: artworkFilename) else {
            return
        }

        let sharedDefaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)
        let cachedSource = sharedDefaults?.string(forKey: artworkSourceKey)
        if
            cachedSource == sourceURL.absoluteString,
            FileManager.default.fileExists(atPath: destination.path()),
            WidgetSnapshotStore.hasInlineArtworkData(filename: artworkFilename)
        {
            return
        }

        artworkTask?.cancel()
        let sourceKey = artworkSourceKey
        let filename = artworkFilename
        artworkTask = Task.detached(priority: .utility) {
            do {
                let (data, response) = try await URLSession.shared.data(from: sourceURL)
                guard
                    !Task.isCancelled,
                    let http = response as? HTTPURLResponse,
                    200..<300 ~= http.statusCode
                else {
                    return
                }
                let widgetData = WidgetSnapshotWriter.preparedArtworkData(from: data) ?? data
                WidgetSnapshotStore.saveArtworkData(widgetData, filename: filename)
                sharedDefaults?.set(sourceURL.absoluteString, forKey: sourceKey)
                sharedDefaults?.synchronize()
                await MainActor.run {
                    WidgetSnapshotWriter.shared.scheduleTimelineReload()
                }
            } catch {
                // The widget retains its previous R2 frame until the next successful refresh.
            }
        }
    }

    func clear() {
        artworkTask?.cancel()
        WidgetSnapshotStore.removeArtworkData(filename: artworkFilename)
        UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)?
            .removeObject(forKey: artworkSourceKey)
        WidgetSnapshotStore.save(.placeholder)
        scheduleTimelineReload()
    }

    private func removeLegacyLivingWidgetCache() {
        let filename = "ampaw-charging2-widget.gif"
        WidgetSnapshotStore.removeArtworkData(filename: filename)
        UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)?.removeObject(
            forKey: "nanobeasts.widget.living-artwork-source.v1"
        )
    }

    private func scheduleTimelineReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
        }
    }

    nonisolated private static func preparedArtworkData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: thumbnail).pngData()
    }
}
