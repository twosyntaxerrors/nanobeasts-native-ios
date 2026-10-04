import MapKit
import SwiftUI

struct WorkoutRouteReplayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let payload: WorkoutSharePayload
    let distanceUnit: DistanceUnitPreference
    private let track: WorkoutRouteReplayTrack
    @State private var progress = 0.0
    @State private var isPlaying = false
    @State private var speed = 1.0
    @State private var wasPlayingBeforeScrub = false
    private let recapDuration = 30.0
    @State private var companionArtwork: UIImage?
    @State private var artworkKey: String?
    @State private var artworkFailed = false
    @State private var endingCard: UIImage?
    @State private var exportTask: Task<Void, Never>?
    @State private var exportProgress = 0.0
    @State private var sharedVideo: WorkoutReplayVideoShare?
    @State private var cachedVideo: WorkoutReplayVideoShare?
    @State private var cachedVideoKey: String?
    @State private var shareError: String?
    private var isExporting: Bool { exportTask != nil }


    init(payload: WorkoutSharePayload, distanceUnit: DistanceUnitPreference) {
        self.payload = payload
        self.distanceUnit = distanceUnit
        track = WorkoutRouteReplayTrack(route: payload.route, breakIndices: payload.routeBreakIndices)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 14) {
                    header
                    finalStats
                    if track.canReplay {
                        WorkoutReplayMap(track: track, progress: progress, companion: store.currentStage, artwork: companionArtwork)
                            .frame(height: max(200, geometry.size.height - 410))
                            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 23).stroke(NanoTheme.teal.opacity(0.3)))
                            .overlay {
                                if progress >= 1, let endingCard {
                                    Image(uiImage: endingCard).resizable().scaledToFit()
                                        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(.black.opacity(0.86))
                                        .clipShape(RoundedRectangle(cornerRadius: 23))
                                        .padding(.bottom, 28)
                                        .transition(.opacity)
                                }
                            }
                            .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.25), value: progress >= 1)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Recorded route with pink fog clearing behind your path")
                            .accessibilityValue("\(Int(progress * 100)) percent revealed")
                        controls
                        shareVideoButton
                    } else {
                        ContentUnavailableView("No route to replay", systemImage: "location.slash",
                                               description: Text("A recorded GPS path is needed to replay this workout."))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
        }
        .background(NanoTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { isPlaying = track.canReplay && !reduceMotion }
        .onDisappear {
            isPlaying = false
            exportTask?.cancel()
        }
        .sheet(item: $sharedVideo) { item in
            WorkoutReplayVideoShareSheet(url: item.url).presentationDetents([.medium, .large])
        }
        .alert("Couldn’t prepare your video", isPresented: Binding(
            get: { shareError != nil }, set: { if !$0 { shareError = nil } }
        )) { Button("OK", role: .cancel) { shareError = nil } } message: {
            Text(shareError ?? "Please try again.")
        }
        .task(id: store.currentStage.imageKey) {
            let companion = store.currentStage
            companionArtwork = nil
            artworkKey = nil
            endingCard = nil
            artworkFailed = false
            do {
                _ = try await loadArtwork(for: companion)
            } catch is CancellationError {
            } catch { artworkFailed = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { isPlaying = false }
            if phase == .background, isExporting {
                exportTask?.cancel()
                shareError = "Keep Nanobeasts open while the video is being prepared, then try sharing again."
            }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { isPlaying = false }
        }
        .task(id: isPlaying) {
            guard isPlaying else { return }
            var previous = ContinuousClock.now
            while !Task.isCancelled && isPlaying {
                do { try await Task.sleep(for: .milliseconds(33)) }
                catch { return }
                guard !Task.isCancelled, isPlaying else { return }
                let now = ContinuousClock.now
                let elapsed = previous.duration(to: now).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                previous = now
                progress = min(1, progress + seconds * speed / recapDuration)
                if progress >= 1 { isPlaying = false }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ROUTE REPLAY")
                    .font(NanoFont.aldrich(11)).tracking(1).foregroundStyle(NanoTheme.teal)
                Text(payload.workoutName)
                    .font(.title3.weight(.semibold)).foregroundStyle(.white)
            }
            Spacer(minLength: 4)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(NanoTheme.surface))
            }
            .foregroundStyle(.white)
            .buttonStyle(WorkoutReplayPressStyle())
            .disabled(isExporting)
            .accessibilityLabel("Close route replay")
        }
    }

    private var finalStats: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("YOUR COMPLETED WORKOUT")
                .font(.caption2.weight(.medium)).tracking(0.6).foregroundStyle(NanoTheme.secondaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 10) {
                metric("STEPS", payload.steps.formatted())
                metric("DISTANCE", distanceText)
                metric("ACTIVE TIME", WorkoutMetricsFormat.time(TimeInterval(payload.elapsedSeconds)))
                metric("AVG PACE", paceText)
                metric("ENERGY", "\(Int(payload.calories)) kcal")
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(NanoTheme.surface))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(.caption2, design: .rounded)).foregroundStyle(NanoTheme.secondaryText)
            Text(value).font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
    }

    private var distanceText: String {
        let value = payload.distanceMiles * (distanceUnit == .kilometers ? 1.609344 : 1)
        return String(format: "%.2f %@", value, distanceUnit.abbreviation.lowercased())
    }

    private var paceText: String {
        guard payload.distanceMiles > 0.005 else { return "—" }
        let pace = payload.paceMinutesPerMile / (distanceUnit == .kilometers ? 1.609344 : 1)
        let seconds = Int((pace * 60).rounded())
        return String(format: "%d:%02d/%@", seconds / 60, seconds % 60, distanceUnit.abbreviation.lowercased())
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack {
                Text(progress >= 1 ? "Route revealed" : "\(Int(progress * 100))% of route")
                Spacer()
                Text("\(String(format: "%g", recapDuration / speed))-second recap")
            }
            .font(.caption).foregroundStyle(NanoTheme.secondaryText)
            Slider(value: $progress, in: 0...1, onEditingChanged: { editing in
                if editing {
                    wasPlayingBeforeScrub = isPlaying
                    isPlaying = false
                } else {
                    isPlaying = wasPlayingBeforeScrub && progress < 1
                }
            })
            .tint(NanoTheme.teal)
            .disabled(isExporting)
            .accessibilityLabel("Route replay position")
            .accessibilityValue("\(Int(progress * 100)) percent")
            HStack(spacing: 12) {
                Button {
                    progress = 0
                    isPlaying = !reduceMotion
                } label: {
                    Image(systemName: "backward.end.fill").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Restart route replay")
                Button {
                    if progress >= 1 { progress = 0 }
                    isPlaying.toggle()
                } label: {
                    Label(isPlaying ? "Pause" : progress >= 1 ? "Replay" : "Play",
                          systemImage: isPlaying ? "pause.fill" : progress >= 1 ? "arrow.clockwise" : "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .foregroundStyle(NanoTheme.background)
                        .background(Capsule().fill(NanoTheme.teal))
                }
                Button { speed = speed == 1 ? 2 : speed == 2 ? 4 : 1 } label: {
                    Text("\(Int(speed))×").font(.body.monospacedDigit().weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Replay speed")
                .accessibilityValue("\(Int(speed)) times")
                .accessibilityHint("Cycles through normal, two times, and four times speed")
            }
            .foregroundStyle(NanoTheme.teal)
            .buttonStyle(WorkoutReplayPressStyle())
            .disabled(isExporting)
            if reduceMotion {
                Text("Use the slider to explore, or tap Play.")
                    .font(.caption2).foregroundStyle(NanoTheme.secondaryText)
            }
        }
    }

    private var shareVideoButton: some View {
        VStack(spacing: 8) {
            if isExporting {
                ProgressView(value: exportProgress).tint(NanoTheme.teal)
                    .accessibilityLabel("Preparing route video")
                HStack {
                    Text("Preparing video · \(Int(exportProgress * 100))%")
                        .font(.caption).foregroundStyle(NanoTheme.secondaryText)
                    Spacer()
                    Button("Cancel") { exportTask?.cancel() }
                        .frame(minHeight: 44).tint(NanoTheme.teal)
                }
            } else {
                Button(action: shareVideo) {
                    Label("Share video", systemImage: "square.and.arrow.up")
                        .font(.body.weight(.semibold)).foregroundStyle(NanoTheme.teal)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 15).fill(NanoTheme.teal.opacity(0.12)))
                }
                .buttonStyle(WorkoutReplayPressStyle())
                .disabled(companionArtwork == nil && !artworkFailed)
                .accessibilityHint("Share the full route replay with your companion, stats and a closing route card")
            }
        }
    }

    private func shareVideo() {
        guard !isExporting else { return }
        let cacheKey = "\(payload.id)|\(store.currentStage.imageKey)|\(distanceUnit.rawValue)|\(speed)|\(store.interfaceAccent.rawValue)"
        if let cachedVideo, cachedVideoKey == cacheKey,
           FileManager.default.fileExists(atPath: cachedVideo.url.path) {
            sharedVideo = WorkoutReplayVideoShare(url: cachedVideo.url)
            return
        }
        let companion = store.currentStage
        let selectedSpeed = speed
        isPlaying = false
        exportProgress = 0
        exportTask = Task { @MainActor in
            let wasIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            defer {
                UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled
                exportTask = nil
            }
            do {
                let artwork = try await loadArtwork(for: companion)
                let url = try await WorkoutReplayVideoExporter.export(payload: payload, companion: companion,
                    artwork: artwork, distanceUnit: distanceUnit, speed: selectedSpeed) { exportProgress = $0 }
                try Task.checkCancellation()
                let video = WorkoutReplayVideoShare(url: url)
                cachedVideo = video
                cachedVideoKey = cacheKey
                sharedVideo = video
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { shareError = error.localizedDescription }
            }
        }
    }

    private func loadArtwork(for companion: CreatureStage) async throws -> UIImage {
        if let companionArtwork, artworkKey == companion.imageKey { return companionArtwork }
        let data = try await R2ArtworkCache.shared.data(for: R2AssetManifest.url(for: companion.imageKey))
        try Task.checkCancellation()
        guard let image = UIImage(data: data) else { throw WorkoutReplayVideoError.artwork }
        companionArtwork = image
        artworkKey = companion.imageKey
        artworkFailed = false
        endingCard = WorkoutReplayVideoArtwork.ending(payload: payload, companion: companion,
                                                      artwork: image, unit: distanceUnit)
        return image
    }

}

private struct WorkoutReplayPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct WorkoutReplayMap: UIViewRepresentable {
    let track: WorkoutRouteReplayTrack
    let progress: Double
    let companion: CreatureStage
    let artwork: UIImage?

    func makeCoordinator() -> Coordinator { Coordinator(track: track) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.showsCompass = false
        map.showsScale = true
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.pointOfInterestFilter = .excludingAll
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.emphasisStyle = .muted
        map.preferredConfiguration = configuration
        context.coordinator.install(on: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.updateCompanion(companion, artwork: artwork, on: map)
        context.coordinator.update(progress: progress, on: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let track: WorkoutRouteReplayTrack
        private let fog = WorkoutTerritoryOverlay()
        private let marker = MKPointAnnotation()
        private weak var renderer: WorkoutTerritoryRenderer?
        private var lastProgress: Double?
        private var companionImage: UIImage?
        private var companionName = "Your companion"
        private weak var artworkView: UIImageView?

        init(track: WorkoutRouteReplayTrack) { self.track = track }

        func install(on map: MKMapView) {
            fog.showsFog = true
            // Deliberately isolated from the permanently explored map: show
            // what this one recorded route uncovered, even on repeat visits.
            map.addOverlay(fog, level: .aboveLabels)
            marker.title = "Your route"
            if let first = track.coordinates.first { marker.coordinate = first }
            map.addAnnotation(marker)
            let bounds = WorkoutReplayMapBounds.rect(for: track.coordinates, padding: 0)
            map.setVisibleMapRect(bounds, edgePadding: UIEdgeInsets(top: 38, left: 30, bottom: 38, right: 30), animated: false)
        }

        func update(progress: Double, on map: MKMapView) {
            guard progress != lastProgress else { return }
            lastProgress = progress
            let frame = track.frame(at: progress)
            fog.updateRoute(frame.coordinates, breakIndices: frame.breakIndices)
            if let coordinate = frame.marker { marker.coordinate = coordinate }
            renderer?.setNeedsDisplay(map.visibleMapRect)
        }

        func updateCompanion(_ companion: CreatureStage, artwork: UIImage?, on map: MKMapView) {
            companionName = companion.name
            companionImage = artwork
            artworkView?.image = artwork
            marker.title = companion.name
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = WorkoutTerritoryRenderer(overlay: overlay)
            self.renderer = renderer
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let view = MKAnnotationView(annotation: annotation, reuseIdentifier: "route-replay-marker")
            view.frame = CGRect(x: 0, y: 0, width: 54, height: 54)
            view.backgroundColor = UIColor.black.withAlphaComponent(0.8)
            view.layer.cornerRadius = 27
            view.layer.borderWidth = 1.5
            view.layer.borderColor = UIColor(NanoTheme.teal).withAlphaComponent(0.75).cgColor
            let icon = UIImageView(image: companionImage)
            icon.contentMode = .scaleAspectFit
            icon.frame = view.bounds.insetBy(dx: 4, dy: 4)
            view.addSubview(icon)
            artworkView = icon
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOpacity = 0.65
            view.layer.shadowRadius = 4
            view.displayPriority = .required
            view.isAccessibilityElement = false
            return view
        }
    }
}

/// Shared entry point on both a just-finished workout and a saved Watch workout.
struct WorkoutRouteReplayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Watch my route", systemImage: "play.circle.fill")
                .font(NanoFont.aldrich(14))
                .foregroundStyle(NanoTheme.teal)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 16).fill(NanoTheme.teal.opacity(0.12)))
        }
        .buttonStyle(WorkoutReplayPressStyle())
        .accessibilityHint("Replay your recorded path as it clears the pink fog")
    }
}
