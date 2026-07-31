import Foundation

struct WidgetSnapshot: Codable, Hashable {
    static let placeholder = WidgetSnapshot(
        updatedAt: Date(),
        creatureName: "Nanobeast",
        stage: 0,
        todaySteps: 0,
        dailyGoal: 6_500,
        evolutionProgress: 0,
        stepsRemaining: 250,
        streak: 0,
        artworkFilename: nil
    )

    let updatedAt: Date
    let creatureName: String
    let stage: Int
    let todaySteps: Int
    let dailyGoal: Int
    let evolutionProgress: Double
    let stepsRemaining: Int
    let streak: Int
    let artworkFilename: String?

    var goalProgress: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(max(Double(todaySteps) / Double(dailyGoal), 0), 1)
    }
}

enum WidgetSnapshotStore {
    static let appGroupID = "group.com.twosyntaxerrors.nanobeasts.native"
    static let widgetKind = "NanobeastsProgressWidget"
    private static let snapshotKey = "nanobeasts.widget.snapshot.v1"
    private static let artworkDataKey = "nanobeasts.widget.artwork-data.v1"
    private static let snapshotFilename = "nanobeasts-widget-snapshot.json"

    static func load() -> WidgetSnapshot {
        if
            let url = sharedCacheDirectoryURL()?.appendingPathComponent(snapshotFilename),
            let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        {
            return snapshot
        }

        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else {
            return .placeholder
        }
        return snapshot
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        if let url = sharedCacheDirectoryURL()?.appendingPathComponent(snapshotFilename) {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                assertionFailure("Unable to persist widget snapshot: \(error)")
            }
        }

        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(data, forKey: snapshotKey)
            defaults.synchronize()
        }
    }

    static func containerURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )
    }

    static func artworkURL(filename: String) -> URL? {
        sharedCacheDirectoryURL()?.appendingPathComponent(filename)
    }

    static func loadArtworkData(filename: String) -> Data? {
        if let data = UserDefaults(suiteName: appGroupID)?
            .data(forKey: artworkDataKey(for: filename))
        {
            return data
        }
        if
            filename == "current-nanobeast.png",
            let data = UserDefaults(suiteName: appGroupID)?.data(forKey: artworkDataKey)
        {
            return data
        }
        guard let url = artworkURL(filename: filename) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func hasInlineArtworkData(filename: String) -> Bool {
        let defaults = UserDefaults(suiteName: appGroupID)
        return defaults?.data(forKey: artworkDataKey(for: filename)) != nil
            || (
                filename == "current-nanobeast.png"
                    && defaults?.data(forKey: artworkDataKey) != nil
            )
    }

    static func saveArtworkData(_ data: Data, filename: String) {
        if let url = artworkURL(filename: filename) {
            try? data.write(to: url, options: .atomic)
        }
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(data, forKey: artworkDataKey(for: filename))
            if filename == "current-nanobeast.png" {
                defaults.set(data, forKey: artworkDataKey)
            }
            defaults.synchronize()
        }
    }

    static func removeArtworkData(filename: String) {
        if
            let url = artworkURL(filename: filename),
            FileManager.default.fileExists(atPath: url.path())
        {
            try? FileManager.default.removeItem(at: url)
        }
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.removeObject(forKey: artworkDataKey(for: filename))
            if filename == "current-nanobeast.png" {
                defaults.removeObject(forKey: artworkDataKey)
            }
            defaults.synchronize()
        }
    }

    private static func artworkDataKey(for filename: String) -> String {
        "nanobeasts.widget.artwork-data.\(filename).v2"
    }

    private static func sharedCacheDirectoryURL() -> URL? {
        guard let containerURL = containerURL() else { return nil }
        let directoryURL = containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("NanobeastsWidget", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            return directoryURL
        } catch {
            assertionFailure("Unable to create widget cache directory: \(error)")
            return nil
        }
    }
}
