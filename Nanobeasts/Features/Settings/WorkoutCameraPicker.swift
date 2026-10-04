import AVFoundation
import SwiftUI
import UIKit

struct WorkoutCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> WorkoutCameraController {
        let controller = WorkoutCameraController()
        controller.onCapture = { photo in image = photo; dismiss() }
        controller.onCancel = { dismiss() }
        return controller
    }

    func updateUIViewController(_ controller: WorkoutCameraController, context: Context) {}

    static func dismantleUIViewController(_ controller: WorkoutCameraController, coordinator: ()) {
        controller.stopCamera()
    }
}

/// Own capture and review so iOS's image picker cannot unmirror a selfie
/// between the viewfinder and the "Use photo" screen.
final class WorkoutCameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCapture: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "nanobeasts.workout.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private let preview = AVCaptureVideoPreviewLayer()
    private let previewContainer = UIView()
    private let review = UIImageView()
    private let shutter = UIButton(type: .system)
    private let flip = UIButton(type: .system)
    private let cancel = UIButton(type: .system)
    private let retake = UIButton(type: .system)
    private let usePhoto = UIButton(type: .system)
    private let notice = UILabel()
    private var input: AVCaptureDeviceInput?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var capturedImage: UIImage?
    private var frontFacing = false
    private var busy = true
    private var isVisible = false
    private var isConfigured = false

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.tintColor = UIColor(NanoTheme.teal)
        preview.videoGravity = .resizeAspect
        previewContainer.layer.addSublayer(preview)
        previewContainer.clipsToBounds = true
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewContainer)
        review.contentMode = .scaleAspectFit
        review.backgroundColor = .black
        review.isHidden = true
        review.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(review)

        cancel.setTitle("Cancel", for: .normal)
        cancel.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
        flip.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera"), for: .normal)
        flip.accessibilityLabel = "Switch camera"
        flip.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        shutter.setImage(UIImage(systemName: "circle.inset.filled",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 62, weight: .regular)), for: .normal)
        shutter.tintColor = .white
        shutter.accessibilityLabel = "Take photo"
        shutter.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
        retake.setTitle("Retake", for: .normal)
        retake.addTarget(self, action: #selector(retakePhoto), for: .touchUpInside)
        usePhoto.setTitle("Use photo", for: .normal)
        usePhoto.addTarget(self, action: #selector(acceptPhoto), for: .touchUpInside)
        for button in [cancel, flip, shutter, retake, usePhoto] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            view.addSubview(button)
        }
        notice.text = "Opening camera…"
        notice.textColor = .white
        notice.font = .preferredFont(forTextStyle: .body)
        notice.adjustsFontForContentSizeCategory = true
        notice.numberOfLines = 0
        notice.textAlignment = .center
        notice.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(notice)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            cancel.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            cancel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            previewContainer.topAnchor.constraint(equalTo: cancel.bottomAnchor, constant: 12),
            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewContainer.bottomAnchor.constraint(equalTo: shutter.topAnchor, constant: -20),
            review.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            review.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            review.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            review.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            shutter.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -16),
            shutter.widthAnchor.constraint(equalToConstant: 80),
            shutter.heightAnchor.constraint(equalToConstant: 80),
            flip.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            flip.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24),
            flip.widthAnchor.constraint(equalToConstant: 48),
            flip.heightAnchor.constraint(equalToConstant: 48),
            retake.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 24),
            retake.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            retake.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            usePhoto.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24),
            usePhoto.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            usePhoto.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            notice.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            notice.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 24),
            notice.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -24)
        ])
        updateControls()
        NotificationCenter.default.addObserver(self, selector: #selector(resumeCamera),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopCamera),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        configureCamera(front: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        resumeCamera()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        stopCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = previewContainer.bounds
        CATransaction.commit()
    }

    @objc func stopCamera() {
        busy = true
        updateControls()
        sessionQueue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    @objc private func resumeCamera() {
        guard isVisible, isConfigured, capturedImage == nil else { return }
        busy = true
        updateControls()
        sessionQueue.async { [self] in
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isVisible, self.capturedImage == nil else { return }
                self.busy = false
                self.updateControls()
            }
        }
    }

    private func configureCamera(front: Bool) {
        busy = true
        updateControls()
        sessionQueue.async { [self] in
            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                                          position: front ? .front : .back) else {
                    throw CameraError.unavailable
                }
                let replacement = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                session.sessionPreset = .photo
                let previous = input
                if let previous { session.removeInput(previous) }
                guard session.canAddInput(replacement) else {
                    if let previous, session.canAddInput(previous) { session.addInput(previous) }
                    session.commitConfiguration()
                    throw CameraError.unavailable
                }
                session.addInput(replacement)
                input = replacement
                if !session.outputs.contains(output) {
                    guard session.canAddOutput(output) else {
                        session.commitConfiguration()
                        throw CameraError.unavailable
                    }
                    session.addOutput(output)
                    output.maxPhotoQualityPrioritization = .quality
                }
                session.commitConfiguration()
                DispatchQueue.main.async { [self] in
                    frontFacing = front
                    preview.session = session
                    rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
                    rotationObservation = rotation?.observe(\.videoRotationAngleForHorizonLevelPreview,
                        options: [.initial, .new]) { [weak self] _, _ in
                        DispatchQueue.main.async { self?.updatePreviewOrientation() }
                    }
                    updatePreviewOrientation()
                    isConfigured = true
                    busy = false
                    notice.text = nil
                    updateControls()
                    resumeCamera()
                }
            } catch {
                DispatchQueue.main.async { [self] in
                    busy = false
                    notice.text = "Camera unavailable. Close this screen and try again."
                    updateControls()
                }
            }
        }
    }

    private func updatePreviewOrientation() {
        guard let connection = preview.connection else { return }
        matchMirroring(connection)
        let angle = rotation?.videoRotationAngleForHorizonLevelPreview ?? 90
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
    }

    private func matchMirroring(_ connection: AVCaptureConnection) {
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = frontFacing
        }
    }

    @objc private func takePhoto() {
        guard !busy, session.isRunning, capturedImage == nil,
              let connection = output.connection(with: .video) else { return }
        busy = true
        updateControls()
        // Use the identical mirror policy for preview AND capture, including
        // landscape selfies. Rotation is handled independently by AVFoundation.
        matchMirroring(connection)
        let angle = rotation?.videoRotationAngleForHorizonLevelCapture ?? 90
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.photoQualityPrioritization = .quality
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            self.busy = false
            if let image {
                // UIImage draws EXIF rotation/mirroring into the pixels once.
                // Review, SwiftUI preview and JPEG export now use that same image.
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let normalized = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: image.size))
                }
                self.capturedImage = normalized
                self.review.image = normalized
                self.stopCamera()
            } else {
                self.notice.text = "Couldn’t take the photo. Please try again."
            }
            self.updateControls()
        }
    }

    @objc private func switchCamera() {
        guard !busy else { return }
        configureCamera(front: !frontFacing)
    }

    @objc private func retakePhoto() {
        capturedImage = nil
        review.image = nil
        notice.text = nil
        updateControls()
        resumeCamera()
    }

    @objc private func acceptPhoto() {
        guard let capturedImage else { return }
        onCapture?(capturedImage)
    }

    @objc private func cancelCapture() { onCancel?() }

    private func updateControls() {
        let reviewing = capturedImage != nil
        review.isHidden = !reviewing
        shutter.isHidden = reviewing
        flip.isHidden = reviewing
        retake.isHidden = !reviewing
        usePhoto.isHidden = !reviewing
        shutter.isEnabled = !busy && isConfigured
        flip.isEnabled = !busy && isConfigured
        shutter.alpha = busy ? 0.45 : 1
    }

    private enum CameraError: Error { case unavailable }
}
