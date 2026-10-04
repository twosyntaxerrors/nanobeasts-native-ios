import AVFoundation
import CoreLocation
import MapKit
import PhotosUI
import SwiftUI
import UIKit

struct WorkoutSharePayload: Identifiable {
    let id = UUID()
    let workoutName: String
    let workoutSymbol: String
    let elapsedSeconds: Int
    let steps: Int
    let distanceMiles: Double
    let calories: Double
    let isIndoor: Bool
    let route: [CLLocationCoordinate2D]
    let territoryTiles: Int
    let companion: CreatureStage
    let rewards: [CreatureDiscoveryEvent]
    var routeBreakIndices: [Int] = []

    var paceMinutesPerMile: Double {
        guard distanceMiles > 0.005 else { return 0 }
        return (Double(elapsedSeconds) / 60) / distanceMiles
    }
}

struct WorkoutShareComposer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let payload: WorkoutSharePayload

    @State private var style: WorkoutShareStyle = .photo
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var photoPlacement = WorkoutSharePlacement()
    @State private var stickerPlacement = WorkoutSharePlacement(center: CGPoint(x: 0.5, y: 0.5))
    @State private var dragOrigin: CGPoint?
    @State private var pinchOrigin: Double?
    @GestureState private var isPinching = false
    @State private var cameraPresented = false
    @State private var shareItem: WorkoutRenderedShare?
    @State private var isRendering = false
    @State private var isLoadingPhoto = false
    @State private var isOpeningCamera = false
    @State private var didCopyOverlay = false
    @State private var shareError: String?
    @State private var shareConfirmation: WorkoutShareConfirmation?
    @State private var showsAdjustments = false
    @Namespace private var modeSelection

    init(payload: WorkoutSharePayload, samplePhoto: UIImage? = nil) {
        self.payload = payload
        _photo = State(initialValue: samplePhoto)
    }

    private var placement: Binding<WorkoutSharePlacement> {
        style == .sticker ? $stickerPlacement : $photoPlacement
    }
    private var needsPhoto: Bool { style == .photo && photo == nil }
    private var busy: Bool { isRendering || isLoadingPhoto || isOpeningCamera }
    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .timingCurve(0.23, 1, 0.32, 1, duration: 0.2)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                composerHeader
                GeometryReader { geometry in
                    let previewHeight = style == .route
                        ? min(620, max(230, geometry.size.height - 155))
                        : min(400, max(230, geometry.size.height * 0.52))
                    let previewWidth = min(geometry.size.width - 40,
                        previewHeight * style.canvasSize.width / style.canvasSize.height)
                    ScrollView {
                        VStack(spacing: 18) {
                            modePicker
                            if payload.route.count < 2 {
                                Text("No GPS route was recorded. Photo and Overlay are still available.")
                                    .font(.footnote).foregroundStyle(NanoTheme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text(style.detail)
                                .font(.subheadline)
                                .foregroundStyle(NanoTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)

                            if needsPhoto {
                                WorkoutPhotoInvitation()
                                photoActions
                            } else {
                                sharePreview(width: previewWidth)
                                if style == .photo { photoActions }
                                if style != .route {
                                    Text("Drag to move. Pinch to resize.")
                                        .font(.footnote).foregroundStyle(NanoTheme.secondaryText)
                                    DisclosureGroup("Adjust overlay", isExpanded: $showsAdjustments) {
                                        placementControls.padding(.top, 12)
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .tint(NanoTheme.teal)
                                }
                            }
                            if isLoadingPhoto {
                                ProgressView("Loading photo").font(.subheadline).tint(NanoTheme.teal)
                            }
                            if style == .sticker {
                                Button(action: copyTransparentOverlay) {
                                    Label(didCopyOverlay ? "Copied" : "Copy overlay",
                                          systemImage: didCopyOverlay ? "checkmark" : "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(WorkoutShareSecondaryButtonStyle())
                                .disabled(busy)
                                Text("No background is exported. Copy or share this PNG to place it over a photo in Stories or another editor.")
                                    .font(.footnote).foregroundStyle(NanoTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: 540)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    .background(NanoTheme.background)
                }
                shareAction
            }
            .background(NanoTheme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $cameraPresented) {
            WorkoutCameraPicker(image: $photo).ignoresSafeArea()
        }
        .sheet(item: $shareItem) { item in
            WorkoutActivityView(items: [item.url]) { activityType, completed, error in
                Task { @MainActor in
                    shareItem = nil

                    if error != nil {
                        shareError = "The workout photo couldn’t be shared. Please try again."
                        return
                    }
                    guard completed else { return }

                    let savedToPhotos = activityType == .saveToCameraRoll
                    let confirmation = WorkoutShareConfirmation(
                        title: savedToPhotos ? "Photo saved to Photos" : "Workout photo shared",
                        message: savedToPhotos
                            ? "Your workout photo is now in the Photos app."
                            : "Your workout photo was shared successfully."
                    )

                    // Let the activity sheet finish dismissing before presenting the confirmation.
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    shareConfirmation = confirmation
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Couldn’t prepare your share", isPresented: Binding(
            get: { shareError != nil }, set: { if !$0 { shareError = nil } }
        )) { Button("OK", role: .cancel) { shareError = nil } } message: {
            Text(shareError ?? "Please try again.")
        }
        .alert(item: $shareConfirmation) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            isLoadingPhoto = true
            defer { isLoadingPhoto = false }
            do {
                guard let data = try await selectedPhoto.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    shareError = "This photo couldn’t be opened. Choose another photo or try again."
                    return
                }
                try Task.checkCancellation()
                photo = image
            } catch is CancellationError {
            } catch {
                shareError = "The photo couldn’t be loaded. Check your connection if it’s stored in iCloud, or choose another."
            }
        }
        .onChange(of: style) { _, _ in
            didCopyOverlay = false
            dragOrigin = nil
            pinchOrigin = nil
            showsAdjustments = false
        }
        .onChange(of: isPinching) { _, active in
            guard !active else { return }
            pinchOrigin = nil
            if dragOrigin == nil { placement.wrappedValue.clamp(in: style.canvasSize) }
        }
    }

    private var composerHeader: some View {

        HStack {
            Text("Share your workout")
                .font(.custom("Aldrich-Regular", size: 20, relativeTo: .title2))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 10)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(NanoTheme.surface, in: Circle())
            }
            .buttonStyle(WorkoutSharePrimaryButtonStyle())
            .accessibilityLabel("Close sharing")
            .disabled(isRendering)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(NanoTheme.background)

    }

    private var shareAction: some View {

        Button(action: renderAndShare) {
            HStack(spacing: 10) {
                if isRendering { ProgressView().tint(NanoTheme.background) }
                else { Image(systemName: needsPhoto ? "photo" : "square.and.arrow.up") }
                Text(isRendering ? "Preparing image…" : needsPhoto ? "Add a photo to share" : style.shareTitle)
                    .font(.custom("Aldrich-Regular", size: 14, relativeTo: .headline))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(NanoTheme.background)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 12)
            .background(NanoTheme.teal, in: RoundedRectangle(cornerRadius: 16))
            .opacity(needsPhoto || busy ? 0.5 : 1)
        }
        .buttonStyle(WorkoutSharePrimaryButtonStyle())
        .disabled(needsPhoto || busy)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(NanoTheme.background)

    }

    private var modePicker: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            ForEach(WorkoutShareStyle.allCases) { option in
                Button {
                    style = option
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(style == option ? .white : NanoTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if style == option {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(NanoTheme.elevated)
                                    .matchedGeometryEffect(id: "share-mode", in: modeSelection)
                            }
                        }
                }
                .buttonStyle(WorkoutSharePrimaryButtonStyle())
                .disabled(busy || (option == .route && payload.route.count < 2))
                .opacity(option == .route && payload.route.count < 2 ? 0.45 : 1)
                .accessibilityAddTraits(style == option ? .isSelected : [])
                .accessibilityHint(option == .route && payload.route.count < 2 ? "No GPS route was recorded for this workout" : option.detail)
            }
        }
        .padding(4).background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .animation(reduceMotion ? nil : motion, value: style)
    }

    private func sharePreview(width: CGFloat) -> some View {
        WorkoutShareCard(payload: payload, style: style, photo: photo,
            placement: placement.wrappedValue, showsTransparencyGrid: style == .sticker)
        .overlay {
            if style != .route {
                GeometryReader { geometry in
                    let rect = placement.wrappedValue.rect(in: geometry.size)
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(dragOrigin == nil && !isPinching ? 0 : 0.65),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .contentShape(Rectangle())
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .gesture(DragGesture(coordinateSpace: .named("shareCanvas"))
                            .onChanged { value in
                                if dragOrigin == nil { dragOrigin = CGPoint(x: rect.midX, y: rect.midY) }
                                guard let origin = dragOrigin else { return }
                                placement.wrappedValue.center = CGPoint(
                                    x: (origin.x + value.translation.width) / geometry.size.width,
                                    y: (origin.y + value.translation.height) / geometry.size.height)
                                didCopyOverlay = false
                            }
                            .onEnded { _ in placement.wrappedValue.clamp(in: geometry.size); dragOrigin = nil }
                        )
                        .accessibilityLabel("Workout overlay")
                        .accessibilityHint("Drag to move and pinch to resize. Adjust overlay also provides size and position controls.")
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            MagnifyGesture()
                .updating($isPinching) { _, active, _ in active = true }
                .onChanged { value in
                    if pinchOrigin == nil { pinchOrigin = placement.wrappedValue.scale }
                    guard let origin = pinchOrigin else { return }
                    placement.wrappedValue.resize(by: value.magnification, from: origin)
                    didCopyOverlay = false
                },
            including: style == .route ? .none : .all
        )
        .allowsHitTesting(!busy)
        .coordinateSpace(name: "shareCanvas")
        .environment(\.dynamicTypeSize, .large)
        .frame(width: width, height: width * style.canvasSize.height / style.canvasSize.width)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    private var placementControls: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Size").font(.subheadline)
                Slider(value: placement.scale, in: WorkoutSharePlacement.scaleLimits)
                    .tint(NanoTheme.teal).accessibilityLabel("Overlay size")
                Button("Reset") {
                    placement.wrappedValue = style == .sticker
                        ? WorkoutSharePlacement(center: CGPoint(x: 0.5, y: 0.5)) : WorkoutSharePlacement()
                    didCopyOverlay = false
                }.frame(minWidth: 44, minHeight: 44)
            }
            HStack(spacing: 16) {
                positionButton("Move left", symbol: "arrow.left", dx: -0.05, dy: 0)
                positionButton("Move up", symbol: "arrow.up", dx: 0, dy: -0.05)
                positionButton("Move down", symbol: "arrow.down", dx: 0, dy: 0.05)
                positionButton("Move right", symbol: "arrow.right", dx: 0.05, dy: 0)
            }
        }
        .onChange(of: placement.wrappedValue.scale) { _, _ in
            if dragOrigin == nil && !isPinching { placement.wrappedValue.clamp(in: style.canvasSize) }
            didCopyOverlay = false
        }
    }

    private func positionButton(_ title: String, symbol: String, dx: CGFloat, dy: CGFloat) -> some View {
        Button {
            placement.wrappedValue.clamp(in: style.canvasSize)
            placement.wrappedValue.center.x += dx
            placement.wrappedValue.center.y += dy
            placement.wrappedValue.clamp(in: style.canvasSize)
            didCopyOverlay = false
        } label: {
            Image(systemName: symbol).frame(width: 44, height: 44)
                .foregroundStyle(NanoTheme.teal)
                .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(WorkoutSharePrimaryButtonStyle())
        .accessibilityLabel(title)
    }

    private var photoActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(photo == nil ? "Choose photo" : "Change photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkoutShareSecondaryButtonStyle())
            .disabled(busy)
            Button(action: openCamera) {
                Label("Camera", systemImage: "camera").frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkoutShareSecondaryButtonStyle())
            .disabled(busy || !UIImagePickerController.isSourceTypeAvailable(.camera))
        }
    }

    private func openCamera() {
        guard !isOpeningCamera else { return }
        isOpeningCamera = true
        Task { @MainActor in
            defer { isOpeningCamera = false }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            var allowed = status == .authorized
            if status == .notDetermined {
                allowed = await AVCaptureDevice.requestAccess(for: .video)
            }
            if allowed { cameraPresented = true }
            else { shareError = "Camera access is off. Allow Nanobeasts to use your camera in iPhone Settings, or choose a photo instead." }
        }
    }

    @MainActor private func renderAndShare() {
        guard !busy, !needsPhoto else { return }
        isRendering = true
        Task { @MainActor in
            await Task.yield()
            defer { isRendering = false }
            guard let image = renderedImage(for: style), let data = image.pngData() else {
                shareError = "The image couldn’t be rendered. Please try again."
                return
            }
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WorkoutShares", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("Nanobeasts-\(UUID().uuidString).png")
                try data.write(to: url, options: .atomic)
                shareItem = WorkoutRenderedShare(url: url)
            } catch { shareError = "The share image couldn’t be saved. Please try again." }
        }
    }

    @MainActor private func copyTransparentOverlay() {
        guard !busy else { return }
        isRendering = true
        Task { @MainActor in
            await Task.yield()
            defer { isRendering = false }
            guard let image = renderedImage(for: .sticker), let data = image.pngData() else {
                shareError = "The overlay couldn’t be prepared. Please try again."
                return
            }
            UIPasteboard.general.setData(data, forPasteboardType: "public.png")
            didCopyOverlay = true
        }
    }

    @MainActor private func renderedImage(for style: WorkoutShareStyle) -> UIImage? {
        let card = WorkoutShareCard(payload: payload, style: style, photo: photo,
            placement: style == .sticker ? stickerPlacement : photoPlacement, showsTransparencyGrid: false)
            .frame(width: style.canvasSize.width, height: style.canvasSize.height)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(style.canvasSize)
        renderer.isOpaque = style != .sticker
        return renderer.uiImage
    }
}

private struct WorkoutPhotoInvitation: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(NanoTheme.teal)
            Text("Your walk. Your photo.")
                .font(.custom("Aldrich-Regular", size: 23, relativeTo: .title2))
                .multilineTextAlignment(.center)
            Text("Choose a favorite moment or take a photo. Your workout stats go on top.")
                .font(.subheadline).foregroundStyle(NanoTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28).frame(maxWidth: .infinity, minHeight: 220)
        .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

private enum WorkoutShareStyle: String, CaseIterable, Identifiable {
    case photo
    case route
    case sticker

    var id: Self { self }

    var canvasSize: CGSize {
        CGSize(width: 1_080, height: self == .sticker ? 1_350 : 1_920)
    }

    var title: String {
        switch self {
        case .photo: "Photo"
        case .route: "Route card"
        case .sticker: "Overlay"
        }
    }

    var symbol: String {
        switch self {
        case .photo: "camera.fill"
        case .route: "map.fill"
        case .sticker: "sparkles.rectangle.stack"
        }
    }

    var detail: String {
        switch self {
        case .photo: "Your photo, with your workout stats."
        case .route: "A finished route card, ready to share without a photo."
        case .sticker: "Just your stats and route. A transparent PNG for another app."
        }
    }

    var shareTitle: String {
        switch self {
        case .photo: "Share photo"
        case .route: "Share route card"
        case .sticker: "Share transparent PNG"
        }
    }

    var accent: Color { NanoTheme.orange }
}

/// Normalized placement keeps the editor and full-resolution PNG identical.
private struct WorkoutSharePlacement {
    var center = CGPoint(x: 0.28, y: 0.48)
    var scale: Double = 1
    static let blockSize = CGSize(width: 440, height: 900)
    static let scaleLimits = 0.65...1.5

    mutating func resize(by magnification: CGFloat, from initialScale: Double) {
        guard magnification.isFinite, magnification > 0 else { return }
        scale = min(Self.scaleLimits.upperBound, max(Self.scaleLimits.lowerBound,
            initialScale * Double(magnification)))
    }

    func rect(in canvas: CGSize) -> CGRect {
        let margin = canvas.width * 0.025
        let factor = min(canvas.width / 1080 * scale,
                         (canvas.height - margin * 2) / Self.blockSize.height,
                         (canvas.width - margin * 2) / Self.blockSize.width)
        let size = CGSize(width: Self.blockSize.width * factor, height: Self.blockSize.height * factor)
        let x = min(max(center.x * canvas.width, margin + size.width / 2), canvas.width - margin - size.width / 2)
        let y = min(max(center.y * canvas.height, margin + size.height / 2), canvas.height - margin - size.height / 2)
        return CGRect(x: x - size.width / 2, y: y - size.height / 2, width: size.width, height: size.height)
    }

    mutating func clamp(in canvas: CGSize) {
        let frame = rect(in: canvas)
        center = CGPoint(x: frame.midX / canvas.width, y: frame.midY / canvas.height)
    }
}

private struct WorkoutShareCard: View {
    let payload: WorkoutSharePayload
    let style: WorkoutShareStyle
    let photo: UIImage?
    var placement = WorkoutSharePlacement()
    let showsTransparencyGrid: Bool

    var body: some View {
        GeometryReader { geometry in
            let rect = placement.rect(in: geometry.size)
            ZStack(alignment: .topLeading) {
                background
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                if style == .route {
                    WorkoutRoutePoster(payload: payload)
                        .frame(width: 1080, height: 1920)
                        .scaleEffect(geometry.size.width / 1080)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                WorkoutShareOverlay(payload: payload)
                    .frame(width: WorkoutSharePlacement.blockSize.width, height: WorkoutSharePlacement.blockSize.height)
                    .scaleEffect(rect.width / WorkoutSharePlacement.blockSize.width)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .photo:
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(white: 0.25), Color(white: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        case .route:
            Color(white: 0.08)
        case .sticker:
            if showsTransparencyGrid { WorkoutTransparencyGrid() } else { Color.clear }
        }
    }
}

/// A complete, opaque editorial card; the photo/PNG overlay stays a separate composition.
private struct WorkoutRoutePoster: View {
    let payload: WorkoutSharePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("NANOBEASTS")
                    .font(NanoFont.aldrich(36)).tracking(3)
                Spacer()
                Image(systemName: payload.workoutSymbol)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(NanoTheme.teal)
            }
            .padding(.bottom, 92)

            Text(payload.workoutName.uppercased())
                .font(NanoFont.aldrich(28)).tracking(3)
                .foregroundStyle(NanoTheme.teal)
                .padding(.bottom, 20)
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(String(format: "%.2f", payload.distanceMiles))
                    .font(.system(size: 160, weight: .semibold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                Text("MI").font(NanoFont.aldrich(42)).foregroundStyle(NanoTheme.secondaryText)
            }

            ZStack {
                WorkoutShareGrid().opacity(0.32)
                WorkoutRouteShape(coordinates: payload.route, breakIndices: payload.routeBreakIndices)
                    .stroke(NanoTheme.orange, style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
                    .padding(70)
            }
            .frame(maxHeight: .infinity)
            .padding(.vertical, 64)

            Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
            HStack(alignment: .top, spacing: 30) {
                metric("STEPS", value: payload.steps.formatted())
                Spacer()
                metric("ACTIVE TIME", value: shareTime(payload.elapsedSeconds))
            }
            .padding(.top, 36)
            .padding(.bottom, 76)

            HStack {
                Text("EVERY STEP. MORE LIFE.")
                    .font(NanoFont.aldrich(24)).tracking(2)
                Spacer()
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 30)).foregroundStyle(NanoTheme.teal)
            }
            .foregroundStyle(NanoTheme.secondaryText)
        }
        .foregroundStyle(.white)
        .padding(76)
        .background(Color(red: 0.025, green: 0.035, blue: 0.033))
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(NanoFont.aldrich(24)).tracking(2)
                .foregroundStyle(NanoTheme.secondaryText)
            Text(value).font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

private struct WorkoutShareOverlay: View {
    let payload: WorkoutSharePayload

    var body: some View {
        VStack(spacing: 0) {
            metric("Distance", value: String(format: "%.2f mi", payload.distanceMiles))
            Spacer().frame(height: 26)
            metric("Steps", value: payload.steps.formatted())
            Spacer().frame(height: 26)
            metric("Time", value: shareTime(payload.elapsedSeconds))
            if payload.route.count > 1 {
                WorkoutRouteShape(coordinates: payload.route, breakIndices: payload.routeBreakIndices)
                    .stroke(NanoTheme.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .padding(18)
                    .frame(height: 310)
                    .padding(.top, 34)
            }
            Text("NANOBEASTS")
                .font(NanoFont.aldrich(34))
                .tracking(34 * 2 / 24)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 30)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 28, weight: .semibold)).lineLimit(1)
            Text(value)
                .font(.system(size: 60, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(height: 110)
    }
}

struct WorkoutRouteShape: Shape {
    let coordinates: [CLLocationCoordinate2D]
    var breakIndices: [Int] = []

    func path(in rect: CGRect) -> Path {
        let segments = WorkoutRouteSegments.split(coordinates, at: breakIndices)
        // Use MapKit's projection so the exported silhouette matches the map,
        // including longitude scaling at the workout's latitude.
        var projected = segments.map { $0.map(MKMapPoint.init) }
        let worldWidth = MKMapRect.world.size.width
        var previousX: Double?
        for segment in projected.indices {
            for index in projected[segment].indices {
                var point = projected[segment][index]
                if let previousX {
                    point.x += ((previousX - point.x) / worldWidth).rounded() * worldWidth
                }
                projected[segment][index] = point
                previousX = point.x
            }
        }
        let points = projected.flatMap { $0 }
        guard points.count > 1, rect.width > 0, rect.height > 0,
              let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return Path() }
        let width = max(maxX - minX, 0.001)
        let height = max(maxY - minY, 0.001)
        let scale = min(rect.width / width, rect.height / height)
        let offsetX = rect.midX - (maxX + minX) / 2 * scale
        let offsetY = rect.midY - (maxY + minY) / 2 * scale
        var path = Path()
        for segment in projected where segment.count > 1 {
            for (index, point) in segment.enumerated() {
                let position = CGPoint(x: point.x * scale + offsetX, y: point.y * scale + offsetY)
                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
            }
        }
        return path
    }
}

private struct WorkoutShareGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing = max(size.width / 12, 1)
            stride(from: 0.0, through: size.width, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: 0.0, through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(NanoTheme.teal), lineWidth: 1)
        }
    }
}

private struct WorkoutTransparencyGrid: View {
    var body: some View {
        Canvas { context, size in
            let tile = max(size.width / 18, 8)
            for row in 0...Int(size.height / tile) {
                for column in 0...Int(size.width / tile) where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)),
                        with: .color(.white.opacity(0.08))
                    )
                }
            }
        }
        .background(NanoTheme.background)
    }
}

private struct WorkoutSharePrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: configuration.isPressed ? 0.1 : 0.16), value: configuration.isPressed)
    }
}

private struct WorkoutShareSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Aldrich-Regular", size: 13, relativeTo: .subheadline))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12).padding(.vertical, 12)
            .foregroundStyle(NanoTheme.teal)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14).fill(NanoTheme.teal.opacity(configuration.isPressed ? 0.18 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(NanoTheme.teal.opacity(0.24), lineWidth: 1))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: configuration.isPressed ? 0.1 : 0.16), value: configuration.isPressed)
    }
}

private struct WorkoutRenderedShare: Identifiable {
    let id = UUID()
    let url: URL
}

private struct WorkoutShareConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct WorkoutActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let onCompletion: (UIActivity.ActivityType?, Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, _, error in
            onCompletion(activityType, completed, error)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private func shareTime(_ seconds: Int) -> String {
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    let remainingSeconds = seconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }
    return String(format: "%d:%02d", minutes, remainingSeconds)
}
