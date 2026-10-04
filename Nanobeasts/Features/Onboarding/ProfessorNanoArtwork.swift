import SwiftUI
import UIKit
import SDWebImage

enum ProfessorNanoPose: String, CaseIterable {
    case welcome
    case walking
    case research

    var artworkURL: URL {
        R2AssetManifest.baseURL.appending(path: "images/onboarding/professor-nano-\(rawValue)-idle-poster-v1.png")
    }

    var animationURL: URL {
        R2AssetManifest.baseURL.appending(path: "images/onboarding/professor-nano-\(rawValue)-idle-v1.webp")
    }

    static func prefetchArtwork(animationsEnabled: Bool) async {
        if animationsEnabled {
            await MainActor.run {
                // Use the player's disk cache and lazy animated-image decoder.
                // Do not decode all three loops into memory during onboarding.
                _ = SDWebImagePrefetcher.shared.prefetchURLs(
                    allCases.map(\.animationURL),
                    options: [.lowPriority],
                    context: [.animatedImageClass: SDAnimatedImage.self,
                              .storeCacheType: SDImageCacheType.disk.rawValue],
                    progress: nil,
                    completed: nil
                )
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for pose in allCases {
                group.addTask {
                    _ = try? await R2ArtworkCache.shared.data(for: pose.artworkURL)
                }
            }
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .welcome: "Professor Nano welcomes you with his field notebook."
        case .walking: "Professor Nano walks with his phone, following a trail of footprints."
        case .research: "Professor Nano listens with his notebook and pencil ready."
        }
    }
}

struct ProfessorNanoArtwork: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let pose: ProfessorNanoPose
    let height: CGFloat

    @State private var image: UIImage?
    @State private var failed = false
    @State private var retryCount = 0
    @State private var animationLoaded = false
    @State private var isVisible = false

    private var reduceMotion: Bool { systemReduceMotion || store.reduceMotion }

    private var artworkTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.975, anchor: .bottom))
                .combined(with: .offset(y: min(10, height * 0.04))),
            removal: .opacity
        )
    }

    private var entranceAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16)
            : .timingCurve(0.23, 1, 0.32, 1, duration: 0.26)
    }

    var body: some View {
        ZStack {
            if let image, !animationLoaded || reduceMotion {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(pose.accessibilityLabel)
                    .transition(artworkTransition)
            } else if failed && !animationLoaded {
                Button {
                    retryCount += 1
                } label: {
                    Label { Text("Reload artwork") } icon: { SolarImage(.replay, size: 16) }
                        .font(.callout)
                        .frame(minHeight: 44)
                }
                .tint(NanoTheme.teal)
                .accessibilityHint("Check your connection and try loading Professor Nano again.")
            } else if image == nil && !animationLoaded {
                ProgressView()
                    .tint(NanoTheme.teal)
                    .accessibilityLabel("Loading Professor Nano")
            }

            if !reduceMotion, isVisible {
                RemoteAnimatedWebPView(
                    url: pose.animationURL,
                    isPlaying: scenePhase == .active,
                    maxBufferSize: 32 * 1_024 * 1_024,
                    onLoad: { animationLoaded = $0 }
                )
                .opacity(animationLoaded ? 1 : 0)
                .accessibilityHidden(true)
            }
        }
        .frame(width: height * 0.82, height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(pose.accessibilityLabel)
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            animationLoaded = false
        }
        .onChange(of: reduceMotion) { animationLoaded = false }
        .task(id: "\(pose.rawValue)-\(retryCount)") {
            image = nil
            failed = false
            do {
                let data = try await R2ArtworkCache.shared.data(for: pose.artworkURL)
                try Task.checkCancellation()
                guard let decoded = UIImage(data: data) else {
                    failed = true
                    return
                }
                // This poster is the authored loop's first frame, so the
                // switch to playback keeps the pose and framing consistent.
                withAnimation(entranceAnimation) {
                    image = decoded
                }
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
        }
    }
}
