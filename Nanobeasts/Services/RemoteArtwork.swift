import Foundation
import SDWebImage
import SwiftUI
import UIKit

enum R2AssetManifest {
    static let baseURL = URL(string: "https://assets.nanobeasts.app")!

    private static let pathOverrides: [String: String] = [
        "tutorial-egg-stage-0-modern": "images/hatchstep-eggs/Tutorial-egg-nobg.png",

        "ampaw-egg-stage-0-modern": "images/hatchstep-eggs/Ampaw-egg-nobg.png",
        "aquablossom-egg-stage-0-modern": "images/hatchstep-eggs/Aquablossom-egg-nobg.png",
        "aquamity-egg-stage-0-modern": "images/hatchstep-eggs/Aquamity-egg-nobg.png",
        "ceraforge-egg-stage-0-modern": "images/hatchstep-eggs/ceraforge-egg-nobg.png",
        "circute-egg-stage-0-modern": "images/hatchstep-eggs/Circute-egg-nobg.png",
        "vexile-egg-stage-0-modern": "images/hatchstep-eggs/Vexile-egg-nobg.png",
        "drakling-egg-stage-0-modern": "images/hatchstep-eggs/drakling-egg-nobg.png",
        "draklysm-egg-stage-0-modern": "images/hatchstep-eggs/Draklysm-egg-nobg.png",
        "emberspout-egg-stage-0-modern": "images/hatchstep-eggs/emberspout-egg-nobg.png",
        "flarva-egg-stage-0-modern": "images/hatchstep-eggs/Flarva-egg-nobg.png",
        "glitchlet-egg-stage-0-modern": "images/hatchstep-eggs/Glitchlet-egg-nobg.png",
        "kittanium-egg-stage-0-modern": "images/hatchstep-eggs/Kittanium-egg-nobg.png",
        "komantis-egg-stage-0-modern": "images/hatchstep-eggs/komantis-egg-nobg.png",
        "larvagon-egg-stage-0-modern": "images/hatchstep-eggs/larvagon-egg-nobg.png",
        "lavacoon-egg-stage-0-modern": "images/hatchstep-eggs/Lavacoon-egg-nobg.png",
        "leafalon-egg-stage-0-modern": "images/hatchstep-eggs/leafalon-egg-nobg.png",
        "lithicub-egg-stage-0-modern": "images/hatchstep-eggs/Lithicub-egg-nobg.png",
        "netspark-egg-stage-0-modern": "images/hatchstep-eggs/netspark-egg-nobg.png",
        "pebblatops-egg-stage-0-modern": "images/hatchstep-eggs/ceraforge-egg-nobg.png",
        "petralithe-egg-stage-0-modern": "images/hatchstep-eggs/petralithe-egg-nobg.png",
        "rumbleep-egg-stage-0-modern": "images/hatchstep-eggs/Rumbleep-egg-nobg.png",
        "slimerick-egg-stage-0-modern": "images/hatchstep-eggs/slimerick-egg-nobg.png",
        "sludgling-egg-stage-0-modern": "images/hatchstep-eggs/sludgling-egg-nobg.png",
        "sparklutter-egg-stage-0-modern": "images/hatchstep-eggs/Sparklutter-egg-nobg.png",
        "sproutomb-egg-stage-0-modern": "images/hatchstep-eggs/sproutomb-egg-nobg.png",
        "steelclad-egg-stage-0-modern": "images/hatchstep-eggs/steelclad-egg-nobg.png",
        "stinglet-egg-stage-0-modern": "images/hatchstep-eggs/stinglet-egg-nobg.png",
        "therabolt-egg-stage-0-modern": "images/hatchstep-eggs/therabolt-egg-nobg.png",
        "umbralare-egg-stage-0-modern": "images/hatchstep-eggs/umbralare-egg-nobg.png",
        "whimpergeist-egg-stage-0-modern": "images/hatchstep-eggs/whimpergeist-egg-nobg.png",
        "wybit-egg-stage-0-modern": "images/hatchstep-eggs/wybit-egg-nobg.png",
        "wyborg-egg-stage-0-modern": "images/hatchstep-eggs/wybit-egg-nobg.png",
        "zenithruption-egg-stage-0-modern": "images/hatchstep-eggs/zenithruption-egg-nobg.png",

        "ceraforge-stage-2-modern": "images/modern-assets-only/Ceraforge-stage-1-modern.png",
        "vexile-stage-2-modern": "images/modern-assets-only/Vexile-stage-1-modern.png",
        "clawgust-stage-3-modern": "images/modern-assets-only/Clawgust-stage-2-modern.png",
        "terraton-stage-3-modern": "images/modern-assets-only/Terraton-stage-2-modern.png",
        "wyborg-stage-2-modern": "images/modern-assets-only/Wyborg-stage-1-modern.png"
    ]

    static func url(for imageKey: String) -> URL {
        let key = imageKey.lowercased()
        let path: String

        if let override = pathOverrides[key] {
            path = override
        } else {
            let pieces = key.split(separator: "-", omittingEmptySubsequences: false)
            let filename: String
            if let first = pieces.first {
                filename = ([String(first).capitalized] + pieces.dropFirst().map(String.init))
                    .joined(separator: "-") + ".png"
            } else {
                filename = key + ".png"
            }
            path = "images/modern-assets-only/\(filename)"
        }

        return baseURL.appending(path: path)
    }
}

enum R2AnimationManifest {
    private static let filenameOverrides: [String: String] = [
        "lavacoon": "lavacoon-idle-animation-30fps-alt-seq-v1.webp",
        "overnode": "overnode-idle-animation-30fps-alt-seq-v3.webp"
    ]

    static func url(for stage: CreatureStage) -> URL {
        let normalizedName = stage.name
            .lowercased()
            .filter(\.isLetter)

        let path: String
        let cacheVersion: String?
        if stage.isEgg {
            if normalizedName == "tutoriaegg" {
                path = "images/egg-animations-optimized/tutorial-egg-idle-alpha-v4-384.webp"
                cacheVersion = nil
            } else {
                let familyName = normalizedName.hasSuffix("egg")
                    ? String(normalizedName.dropLast(3))
                    : normalizedName
                path = "images/egg-animations-optimized/\(familyName)-egg-animation.webp"
                cacheVersion = nil
            }
        } else if let override = filenameOverrides[normalizedName] {
            path = "images/idle-animations-optimized/\(override)"
            cacheVersion = nil
        } else {
            path = "images/idle-animations-optimized/\(normalizedName)-idle-animation.webp"
            cacheVersion = nil
        }

        let url = R2AssetManifest.baseURL.appending(path: path)
        guard let cacheVersion else { return url }
        return url.appending(queryItems: [URLQueryItem(name: "v", value: cacheVersion)])
    }
}

enum R2TransitionManifest {
    static let onboardingGlitchletEvolutionURL = R2AssetManifest.baseURL.appending(
        path: "images/evolution-animations-optimized/glitchlet-devicore-evolution-onboarding-v1.webp"
    )

    private static let transparentEvolutionVideoPaths: [String: String] = [
        "ampaw-ampunch": "images/evolution-animations-optimized/ampaw-ampunch-evolution-alpha-v3.mov",
        "ampunch-ampact": "images/evolution-animations-optimized/ampunch-ampact-evolution-alpha-v1.mov"
    ]

    private static let transparentEvolutionPaths: [String: String] = [
        "circute-synaptor": "images/evolution-animations-optimized/circute-synaptor-evolution-v4.webp",
        "glitchlet-devicore": "images/evolution-animations-optimized/glitchlet-devicore-evolution-v4.webp",
        "synaptor-cognetix": "images/evolution-animations-optimized/synaptor-cognetix-evolution-v4.webp",
        "wybit-wyborg": "images/evolution-animations-optimized/wybit-wyborg-evolution-v4.webp",
        "ampaw-ampunch": "images/evolution-animations-optimized/ampaw-ampunch-evolution-v4.webp",
        "ampterra-cryoshock": "images/evolution-animations-optimized/ampterra-cryoshock-evolution-v4.webp",
        "ampunch-ampact": "images/evolution-animations-optimized/ampunch-ampact-evolution-v4.webp",
        "aquablossom-hydralilly": "images/evolution-animations-optimized/aquablossom-hydralilly-evolution-v4.webp",
        "aquamity-dragquanimity": "images/evolution-animations-optimized/aquamity-dragquanimity-evolution-v4.webp",
        "armalisk-gladiatorb": "images/evolution-animations-optimized/armalisk-gladiatorb-evolution-v4.webp",
        "bloomwraith-necroflora": "images/evolution-animations-optimized/bloomwraith-necroflora-evolution-v4.webp",
        "bogsterrant-murkhemoth": "images/evolution-animations-optimized/bogsterrant-murkhemoth-evolution-v4.webp",
        "ceraforge-terraton": "images/evolution-animations-optimized/ceraforge-terraton-evolution-v4.webp",
        "chrysalis-sylvernalis": "images/evolution-animations-optimized/chrysalis-sylvernalis-evolution-v4.webp",
        "devicore-overnode": "images/evolution-animations-optimized/devicore-overnode-evolution-v4.webp",
        "dragquanimity-seraphydra": "images/evolution-animations-optimized/dragquanimity-seraphydra-evolution-v4.webp",
        "drakling-noctalisk": "images/evolution-animations-optimized/drakling-noctalisk-evolution-v4.webp",
        "draklysm-triklopsar": "images/evolution-animations-optimized/draklysm-triklopsar-evolution-v4.webp",
        "emberspout-geyserpent": "images/evolution-animations-optimized/emberspout-geyserpent-evolution-v4.webp",
        "ferrohawk-stratalclaw": "images/evolution-animations-optimized/ferrohawk-stratalclaw-evolution-v4.webp",
        "flarva-igneatoad": "images/evolution-animations-optimized/flarva-igneatoad-evolution-v4.webp",
        "igneatoad-lavacrook": "images/evolution-animations-optimized/igneatoad-lavacrook-evolution-v4.webp",
        "kittanium-leonite": "images/evolution-animations-optimized/kittanium-leonite-evolution-v4.webp",
        "komantis-dracmanteon": "images/evolution-animations-optimized/komantis-dracmanteon-evolution-v4.webp",
        "larvagon-chrysalis": "images/evolution-animations-optimized/larvagon-chrysalis-evolution-v4.webp",
        "lavacoon-armalisk": "images/evolution-animations-optimized/lavacoon-armalisk-evolution-v4.webp",
        "leafalon-ferrohawk": "images/evolution-animations-optimized/leafalon-ferrohawk-evolution-v4.webp",
        "leonite-steelking": "images/evolution-animations-optimized/leonite-steelking-evolution-v4.webp",
        "netspark-solvolt": "images/evolution-animations-optimized/netspark-solvolt-evolution-v4.webp",
        "noctalisk-cosmeraus": "images/evolution-animations-optimized/noctalisk-cosmeraus-evolution-v4.webp",
        "pebblatops-ceraforge": "images/evolution-animations-optimized/pebblatops-ceraforge-evolution-v4.webp",
        "petralithe-litheglade": "images/evolution-animations-optimized/petralithe-litheglade-evolution-v4.webp",
        "rumbleep-landrill": "images/evolution-animations-optimized/rumbleep-landrill-evolution-v4.webp",
        "slimerick-bogsterrant": "images/evolution-animations-optimized/slimerick-bogsterrant-evolution-v4.webp",
        "sludgling-toxispike": "images/evolution-animations-optimized/sludgling-toxispike-evolution-v4.webp",
        "solvolt-spectsurge": "images/evolution-animations-optimized/solvolt-spectsurge-evolution-v4.webp",
        "sparklutter-ampterra": "images/evolution-animations-optimized/sparklutter-ampterra-evolution-v4.webp",
        "sproutomb-bloomwraith": "images/evolution-animations-optimized/sproutomb-bloomwraith-evolution-v4.webp",
        "stinglet-reapion": "images/evolution-animations-optimized/stinglet-reapion-evolution-v4.webp",
        "umbralare-nocturnyx": "images/evolution-animations-optimized/umbralare-nocturnyx-evolution-v4.webp",
        "vexile-clawgust": "images/evolution-animations-optimized/vexile-clawgust-evolution-v4.webp",
        "whimpergeist-purrltergeist": "images/evolution-animations-optimized/whimpergeist-purrltergeist-evolution-v4.webp"
    ]

    private static let videoPaths: [String: String] = [
        "tutoria-egg": "images/hatchstep-evolution-animations/Tutorial-Evolution-Video/tutorial-creature-evolution.mp4",
        "ampaw-egg": "images/hatchstep-evolution-animations/Ampaw Evolution Videos/ampaw-egg-evolution.mp4",
        "ampaw-ampunch": "images/hatchstep-evolution-animations/Ampaw Evolution Videos/ampaw-evolution.mp4",
        "ampunch-ampact": "images/hatchstep-evolution-animations/Ampaw Evolution Videos/ampunch-evolution.mp4",
        "aquablossom-egg": "images/hatchstep-evolution-animations/Aquablossom Evolution Videos/aquablossom-egg-evolution.mp4",
        "aquablossom-hydralilly": "images/hatchstep-evolution-animations/Aquablossom Evolution Videos/aquablossom-Evolution.mp4",
        "aquamity-egg": "images/hatchstep-evolution-animations/Aquamity Evolution Videos/aquamity-egg-evolution.mp4",
        "aquamity-dragquanimity": "images/hatchstep-evolution-animations/Aquamity Evolution Videos/aquamity-evolution.mp4",
        "dragquanimity-seraphydra": "images/hatchstep-evolution-animations/Aquamity Evolution Videos/dragquanimity-evolution.mp4",
        "circute-egg": "images/hatchstep-evolution-animations/Circute Evolution Videos/circute-egg-evolution.mp4",
        "circute-synaptor": "images/hatchstep-evolution-animations/Circute Evolution Videos/circute-evolution.mp4",
        "synaptor-cognetix": "images/hatchstep-evolution-animations/Circute Evolution Videos/synaptor-evolution.mp4",
        "vexile-egg": "images/hatchstep-evolution-animations/Vexile Evolution Videos/vexile-egg-evolution.mp4",
        "vexile-clawgust": "images/hatchstep-evolution-animations/Vexile Evolution Videos/vexile-evolution.mp4",
        "drakling-egg": "images/hatchstep-evolution-animations/Drakling Evolution Videos/drakling-egg-evolution.mp4",
        "drakling-noctalisk": "images/hatchstep-evolution-animations/Drakling Evolution Videos/drakling-evolution.mp4",
        "noctalisk-cosmeraus": "images/hatchstep-evolution-animations/Drakling Evolution Videos/noctalisk-evolution.mp4",
        "draklysm-egg": "images/hatchstep-evolution-animations/Draklysm Evolution Videos/Draklysm-egg-evolution.mp4",
        "draklysm-triklopsar": "images/hatchstep-evolution-animations/Draklysm Evolution Videos/Draklysm-evolution.mp4",
        "emberspout-egg": "images/hatchstep-evolution-animations/Emberspot Evolution Videos/emberspout-egg-evolution.mp4",
        "emberspout-geyserpent": "images/hatchstep-evolution-animations/Emberspot Evolution Videos/emberspout-evolution.mp4",
        "flarva-egg": "images/hatchstep-evolution-animations/Flarva Evolution Videos/flarva-egg-evolution.mp4",
        "flarva-igneatoad": "images/hatchstep-evolution-animations/Flarva Evolution Videos/flarva-evolution.mp4",
        "igneatoad-lavacrook": "images/hatchstep-evolution-animations/Flarva Evolution Videos/Ignitetoad-evolution.mp4",
        "glitchlet-egg": "images/hatchstep-evolution-animations/Glitchlet Evolution Videos/glitchlet-egg-evolution.mp4",
        "glitchlet-devicore": "images/hatchstep-evolution-animations/Glitchlet Evolution Videos/glitchlet-evolution.mp4",
        "devicore-overnode": "images/hatchstep-evolution-animations/Glitchlet Evolution Videos/devicore-evolution.mp4",
        "kittanium-egg": "images/hatchstep-evolution-animations/Kitanium Evolution Videos/kittanium-egg-evolution.mp4",
        "kittanium-leonite": "images/hatchstep-evolution-animations/Kitanium Evolution Videos/kittanium-evolution.mp4",
        "leonite-steelking": "images/hatchstep-evolution-animations/Kitanium Evolution Videos/leonite-evolution.mp4",
        "larvagon-egg": "images/hatchstep-evolution-animations/Larvagon Evolution Videos/larvagon-egg-evolution.mp4",
        "larvagon-chrysalis": "images/hatchstep-evolution-animations/Larvagon Evolution Videos/larvagon-evolution.mp4",
        "chrysalis-sylvernalis": "images/hatchstep-evolution-animations/Larvagon Evolution Videos/chrysalis-evolution.mp4",
        "lavacoon-egg": "images/hatchstep-evolution-animations/Lavacoon Evolution Videos/lavacoon-egg-evolution.mp4",
        "lavacoon-armalisk": "images/hatchstep-evolution-animations/Lavacoon Evolution Videos/lavacoon-evolution.mp4",
        "armalisk-gladiatorb": "images/hatchstep-evolution-animations/Lavacoon Evolution Videos/armalisk-evolution.mp4",
        "leafalon-egg": "images/hatchstep-evolution-animations/Leafalon Evolution Videos/leafalon-egg-evolution.mp4",
        "leafalon-ferrohawk": "images/hatchstep-evolution-animations/Leafalon Evolution Videos/leafalon-evolution.mp4",
        "ferrohawk-stratalclaw": "images/hatchstep-evolution-animations/Leafalon Evolution Videos/ferrohawk-evolution.mp4",
        "netspark-egg": "images/hatchstep-evolution-animations/Netspark Evolution Videos/netspark-egg-evolution.mp4",
        "netspark-solvolt": "images/hatchstep-evolution-animations/Netspark Evolution Videos/netspark-evolution.mp4",
        "solvolt-spectsurge": "images/hatchstep-evolution-animations/Netspark Evolution Videos/solvolt-evolution.mp4",
        "pebblatops-egg": "images/hatchstep-evolution-animations/Pebblatops Evolution Videos/pebblatops-egg-evolution.mp4",
        "pebblatops-ceraforge": "images/hatchstep-evolution-animations/Pebblatops Evolution Videos/pebblatops-evolution.mp4",
        "ceraforge-terraton": "images/hatchstep-evolution-animations/Pebblatops Evolution Videos/cerraforge-evolution.mp4",
        "petralithe-egg": "images/hatchstep-evolution-animations/Petralithe Evolution Videos/petralithe-egg-evolution.mp4",
        "petralithe-litheglade": "images/hatchstep-evolution-animations/Petralithe Evolution Videos/petralithe-evolution.mp4",
        "rumbleep-egg": "images/hatchstep-evolution-animations/Rumbleep Evolution Videos/rumbleep-egg-evolution.mp4",
        "rumbleep-landrill": "images/hatchstep-evolution-animations/Rumbleep Evolution Videos/rumbleep-evolution.mp4",
        "slimerick-egg": "images/hatchstep-evolution-animations/Slimerick Evolution Videos/slimerick-egg-evolution.mp4",
        "slimerick-bogsterrant": "images/hatchstep-evolution-animations/Slimerick Evolution Videos/slimerick-evolution.mp4",
        "bogsterrant-murkhemoth": "images/hatchstep-evolution-animations/Slimerick Evolution Videos/bogsterrant-evolution.mp4",
        "sludgling-egg": "images/hatchstep-evolution-animations/Sludgling Evolution Videos/sludgling-egg-evolution.mp4",
        "sludgling-toxispike": "images/hatchstep-evolution-animations/Sludgling Evolution Videos/sludgling-evolution.mp4",
        "sproutomb-egg": "images/hatchstep-evolution-animations/Sproutomb Evolution Videos/sproutomb-egg-evolution.mp4",
        "sproutomb-bloomwraith": "images/hatchstep-evolution-animations/Sproutomb Evolution Videos/sproutomb-evolution.mp4",
        "bloomwraith-necroflora": "images/hatchstep-evolution-animations/Sproutomb Evolution Videos/bloomwraith-evolution.mp4",
        "stinglet-egg": "images/hatchstep-evolution-animations/Stinglet Evolution Videos/stinglet-egg-evolution.mp4",
        "stinglet-reapion": "images/hatchstep-evolution-animations/Stinglet Evolution Videos/stinglet-evolution.mp4",
        "therabolt-egg": "images/hatchstep-evolution-animations/Therabolt Evolution Videos/therabolt-egg-evolution.mp4",
        "umbralare-egg": "images/hatchstep-evolution-animations/Umbralare Evolution Videos/umbralare-egg-evolution.mp4",
        "umbralare-nocturnyx": "images/hatchstep-evolution-animations/Umbralare Evolution Videos/umbralare-evolution.mp4",
        "whimpergeist-egg": "images/hatchstep-evolution-animations/Whimpergeist Evolution Videos/whimpergeist-egg-evolution.mp4",
        "whimpergeist-purrltergeist": "images/hatchstep-evolution-animations/Whimpergeist Evolution Videos/whimpergeist-evolution.mp4",
        "wybit-egg": "images/hatchstep-evolution-animations/Wybit Evolution Videos/wybit-egg-evolution.mp4",
        "wybit-wyborg": "images/hatchstep-evolution-animations/Wybit Evolution Videos/wybit-evolution.mp4",
        "zenithruption-egg": "images/hatchstep-evolution-animations/Zenithruption Evolution Videos/zenithruption-egg-evolution.mp4",
        "komantis-egg": "images/hatchstep-evolution-animations/Komantis Evolution Videos/komantis-egg-evolution.mp4",
        "komantis-dracmanteon": "images/hatchstep-evolution-animations/Komantis Evolution Videos/komantis-evolution.mp4",
        "sparklutter-egg": "images/hatchstep-evolution-animations/Sparklutter Evolution Videos/sparklutter-egg-evolution.mp4",
        "sparklutter-ampterra": "images/hatchstep-evolution-animations/Sparklutter Evolution Videos/sparklutter-evolution.mp4",
        "ampterra-cryoshock": "images/hatchstep-evolution-animations/Sparklutter Evolution Videos/ampterra-evolution.mp4",
        "lithicub-egg": "images/hatchstep-evolution-animations/Lithicub Evolution Videos/Lithicub-egg-evolution.mp4"
    ]

    static func transparentEvolutionURL(from: CreatureStage, to: CreatureStage) -> URL? {
        url(for: transitionKey(from: from, to: to), in: transparentEvolutionPaths)
    }

    static func transparentEvolutionVideoURL(from: CreatureStage, to: CreatureStage) -> URL? {
        url(for: transitionKey(from: from, to: to), in: transparentEvolutionVideoPaths)
    }

    static func evolutionVideoURL(from: CreatureStage, to: CreatureStage) -> URL? {
        url(for: transitionKey(from: from, to: to), in: videoPaths)
    }

    static func hatchVideoURL(for stage: CreatureStage) -> URL? {
        url(for: "\(normalized(stage.name))-egg", in: videoPaths)
    }

    private static func transitionKey(from: CreatureStage, to: CreatureStage) -> String {
        "\(normalized(from.name))-\(normalized(to.name))"
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private static func url(for key: String, in paths: [String: String]) -> URL? {
        guard let path = paths[key] else { return nil }
        return R2AssetManifest.baseURL.appending(path: path)
    }
}

actor R2ArtworkCache {
    static let shared = R2ArtworkCache()

    private let cache: URLCache
    private let session: URLSession

    init() {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "nanobeasts-r2-artwork", directoryHint: .isDirectory)
        cache = URLCache(
            memoryCapacity: 48 * 1_024 * 1_024,
            diskCapacity: 256 * 1_024 * 1_024,
            directory: cacheDirectory
        )

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func data(for url: URL) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        if let cached = cache.cachedResponse(for: request) {
            return cached.data
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }

        cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
        return data
    }

    func clear() {
        cache.removeAllCachedResponses()
    }
}

struct CreatureArtworkView: View {
    let stage: CreatureStage
    var isLocked = false

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if failed {
                placeholder
            } else {
                ProgressView()
                    .tint(NanoTheme.teal)
            }
        }
        .saturation(isLocked ? 0 : 1)
        .opacity(isLocked ? 0.18 : 1)
        .task(id: stage.imageKey) {
            image = nil
            failed = false
            do {
                let data = try await R2ArtworkCache.shared.data(for: R2AssetManifest.url(for: stage.imageKey))
                image = UIImage(data: data)
                failed = image == nil
            } catch {
                failed = true
            }
        }
        .accessibilityLabel(isLocked ? "Undiscovered Nanobeast" : stage.name)
    }

    private var placeholder: some View {
        Image(systemName: stage.isEgg ? "circle.hexagongrid.fill" : "pawprint.fill")
            .resizable()
            .scaledToFit()
            .padding(42)
            .foregroundStyle(NanoTheme.teal)
            .accessibilityHint("Artwork could not be loaded")
    }
}

struct AnimatedCreatureArtworkView: View {
    let stage: CreatureStage
    var isPlaying = true
    var preloadsAllFrames = false
    @State private var animationLoaded = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if !animationLoaded {
                    CreatureArtworkView(stage: stage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                RemoteAnimatedWebPView(
                    url: R2AnimationManifest.url(for: stage),
                    isPlaying: isPlaying,
                    preloadsAllFrames: preloadsAllFrames,
                    onLoad: { succeeded in
                        animationLoaded = succeeded
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .onChange(of: stage.id) {
            animationLoaded = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stage.name), animated")
    }
}

/// Keeps lifecycle result screens responsive even when an animated WebP needs
/// extra time to decode. The transparent PNG is the guaranteed first frame;
/// the animation is mounted and fully preloaded offscreen, then crossfaded in
/// only after its decoder has had a short settling window.
struct DeferredAnimatedCreatureArtworkView: View {
    let stage: CreatureStage
    var shouldPlay = true

    @State private var animationAssetLoaded = false
    @State private var showsAnimation = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                CreatureArtworkView(stage: stage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(showsAnimation ? 0 : 1)

                RemoteAnimatedWebPView(
                    url: R2AnimationManifest.url(for: stage),
                    isPlaying: shouldPlay && showsAnimation,
                    preloadsAllFrames: true,
                    onLoad: { succeeded in
                        animationAssetLoaded = succeeded
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showsAnimation ? 1 : 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: animationAssetLoaded && shouldPlay) {
            guard animationAssetLoaded, shouldPlay else {
                showsAnimation = false
                return
            }

            // SDWebImage has decoded every frame at this point. Waiting for a
            // few display cycles prevents the first visible playback frames
            // from competing with the lifecycle reveal's teardown work.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, shouldPlay else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                showsAnimation = true
            }
        }
        .onChange(of: stage.id) {
            animationAssetLoaded = false
            showsAnimation = false
        }
        .onChange(of: shouldPlay) {
            if !shouldPlay {
                showsAnimation = false
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage.name)
    }
}

/// A deliberately static lifecycle result. The idle WebP is warmed in the
/// background for the following Dex scan, but it is never allowed to replace
/// the PNG on this screen. That keeps the high-value reveal responsive even
/// when a large animated asset is cold.
struct PreloadingStaticCreatureArtworkView: View {
    let stage: CreatureStage

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                CreatureArtworkView(stage: stage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                RemoteAnimatedWebPView(
                    url: R2AnimationManifest.url(for: stage),
                    isPlaying: false,
                    preloadsAllFrames: true,
                    onLoad: { _ in }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage.name)
    }
}

struct RemoteAnimatedWebPView: UIViewRepresentable {
    let url: URL
    var isPlaying = true
    var loopCount: Int? = nil
    var freezesOnLastFrame = false
    var preloadsAllFrames = false
    let onLoad: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SDAnimatedImageView {
        let imageView = SDAnimatedImageView()
        imageView.backgroundColor = .clear
        imageView.isOpaque = false
        imageView.autoPlayAnimatedImage = isPlaying
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.shouldIncrementalLoad = false
        imageView.shouldCustomLoopCount = loopCount != nil
        imageView.animationRepeatCount = loopCount ?? 0
        imageView.resetFrameIndexWhenStopped = !freezesOnLastFrame
        imageView.isUserInteractionEnabled = false
        return imageView
    }

    func updateUIView(_ imageView: SDAnimatedImageView, context: Context) {
        context.coordinator.isPlaying = isPlaying
        context.coordinator.onLoad = onLoad
        imageView.isHidden = false
        imageView.alpha = 1
        imageView.autoPlayAnimatedImage = isPlaying
        imageView.shouldCustomLoopCount = loopCount != nil
        imageView.animationRepeatCount = loopCount ?? 0
        imageView.resetFrameIndexWhenStopped = !freezesOnLastFrame
        if imageView.sd_imageURL == url {
            if isPlaying, imageView.image != nil, !imageView.isAnimating {
                imageView.startAnimating()
            } else if !isPlaying, imageView.isAnimating {
                imageView.stopAnimating()
            }
            return
        }

        var options: SDWebImageOptions = [
            .retryFailed,
            .highPriority,
            .continueInBackground
        ]
        if preloadsAllFrames {
            options.insert(.preloadAllFrames)
        }

        imageView.sd_setImage(
            with: url,
            placeholderImage: nil,
            options: options
        ) { image, error, _, _ in
            DispatchQueue.main.async {
                guard imageView.sd_imageURL == url else { return }
                let succeeded = image != nil && error == nil
                if context.coordinator.isPlaying, succeeded {
                    imageView.startAnimating()
                } else {
                    imageView.stopAnimating()
                }
                context.coordinator.onLoad(succeeded)
            }
        }
    }

    static func dismantleUIView(
        _ imageView: SDAnimatedImageView,
        coordinator: Coordinator
    ) {
        // Hide before stopping. SDAnimatedImageView can synchronously seek to
        // frame zero during teardown, which otherwise produces a one-frame
        // flash of the source creature.
        imageView.isHidden = true
        imageView.alpha = 0
        imageView.sd_cancelCurrentImageLoad()
        imageView.stopAnimating()
    }

    final class Coordinator {
        var isPlaying = true
        var onLoad: (Bool) -> Void = { _ in }
    }
}
