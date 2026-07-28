import Foundation
import WidgetKit

@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    private let artworkFilename = "current-nanobeast.png"
    private let artworkSourceKey = "nanobeasts.widget.artwork-source.v1"
    private var artworkTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?

    private init() {}

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
            FileManager.default.fileExists(atPath: destination.path())
        {
            return
        }

        artworkTask?.cancel()
        let sourceKey = artworkSourceKey
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
                try data.write(to: destination, options: .atomic)
                sharedDefaults?.set(sourceURL.absoluteString, forKey: sourceKey)
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
        if
            let url = WidgetSnapshotStore.artworkURL(filename: artworkFilename),
            FileManager.default.fileExists(atPath: url.path())
        {
            try? FileManager.default.removeItem(at: url)
        }
        UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)?
            .removeObject(forKey: artworkSourceKey)
        WidgetSnapshotStore.save(.placeholder)
        scheduleTimelineReload()
    }

    private func scheduleTimelineReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
        }
    }
}
