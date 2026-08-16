import SwiftUI
import AVFoundation
import UIKit
import CoreMedia

/// Lightweight camera surface. Visible scanner chrome lives in SwiftUI so the
/// preview stays clean and the focus treatment can adapt to each category.
struct ScannerView: View {
    let game: Game
    let pokemonLanguage: PokemonScanLanguage
    @Binding var isTorchOn: Bool
    let onResult: (ScanHit) -> Void

    @State private var engine: CardScannerEngine?
    @State private var isAuthorized = false

    init(
        game: Game = .pokemon,
        pokemonLanguage: PokemonScanLanguage = .english,
        isTorchOn: Binding<Bool>,
        onResult: @escaping (ScanHit) -> Void
    ) {
        self.game = game
        self.pokemonLanguage = pokemonLanguage
        self._isTorchOn = isTorchOn
        self.onResult = onResult
    }

    var body: some View {
        ZStack {
            if isAuthorized {
                CameraPreview(
                    engine: $engine,
                    isTorchOn: isTorchOn,
                    onHit: { hit in
                        let normalized = hit.normalized
                        guard normalized.hasContent else { return }
                        if game == .pokemon {
                            let catalogue = pokemonLanguage
                                .catalogueOrder(for: normalized.name ?? "")
                                .first ?? .english
                            onResult(normalized.tagged(with: catalogue))
                        } else {
                            onResult(normalized)
                        }
                    }
                )
                .ignoresSafeArea()
            } else {
                permissionView
            }
        }
        .task { await setup() }
        .onDisappear {
            isTorchOn = false
            engine?.reset()
        }
    }

    private var permissionView: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(CardSenseTheme.mint)
            Text("Camera access is required")
                .font(.headline)
            Text("The live image stays on your device while Apple Vision reads identifying clues.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(CardSenseTheme.mint)
        }
        .padding(28)
    }

    private func setup() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            isAuthorized = false
        }
        engine = CardScannerEngine(
            languages: game.scanLanguageHints(pokemonLanguage: pokemonLanguage),
            game: game,
            pokemonLanguage: pokemonLanguage
        )
    }
}

extension Game {
    fileprivate func scanLanguageHints(pokemonLanguage: PokemonScanLanguage) -> [String] {
        switch self {
        case .pokemon: pokemonLanguage.ocrLanguageHints
        case .magic, .yugioh: ["en-US", "en", "fr-FR", "de-DE", "es-ES", "it-IT"]
        case .sports: ["en-US", "en", "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR"]
        case .coins: ["en-US", "en", "es-ES", "fr-FR", "de-DE", "it-IT"]
        case .wine: ["en-US", "en", "fr-FR", "it-IT", "es-ES", "de-DE", "pt-PT"]
        case .other: ["en-US", "en", "fr-FR", "de-DE", "es-ES", "it-IT"]
        }
    }
}

// MARK: - UIKit camera bridge

private struct CameraPreview: UIViewControllerRepresentable {
    @Binding var engine: CardScannerEngine?
    let isTorchOn: Bool
    let onHit: (ScanHit) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onHit: onHit) }

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.engineProvider = { engine }
        controller.onHit = { [weak coordinator = context.coordinator] hit in
            coordinator?.onHit(hit)
        }
        controller.setTorch(isTorchOn)
        return controller
    }

    func updateUIViewController(_ controller: CameraViewController, context: Context) {
        controller.engineProvider = { engine }
        controller.setTorch(isTorchOn)
    }

    final class Coordinator {
        let onHit: (ScanHit) -> Void
        init(onHit: @escaping (ScanHit) -> Void) { self.onHit = onHit }
    }
}

/// Delivers a continuously focused rear-camera stream to the OCR engine.
private final class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var engineProvider: () -> CardScannerEngine? = { nil }
    var onHit: ((ScanHit) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "CardSense.CameraCapture", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var cameraDevice: AVCaptureDevice?
    private var requestedTorchState = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captureQueue.async { [weak self] in self?.session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTorch(false)
        captureQueue.async { [weak self] in self?.session.stopRunning() }
    }

    func setTorch(_ enabled: Bool) {
        requestedTorchState = enabled
        guard let device = cameraDevice, device.hasTorch else { return }
        captureQueue.async {
            do {
                try device.lockForConfiguration()
                device.torchMode = enabled ? .on : .off
                device.unlockForConfiguration()
            } catch {
                // The camera remains usable when torch configuration is unavailable.
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        cameraDevice = device
        tuneCamera(device)
        session.addInput(input)

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)
        if session.canAddOutput(output) { session.addOutput(output) }

        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .standard
            }
        }
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
        setTorch(requestedTorchState)
    }

    private func tuneCamera(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            // Smooth autofocus is intentionally disabled: the scanner values
            // a quick lock on small printed text over cinematic focus ramps.
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = false
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            // A slight underexposure protects foil cards, slabs and glossy
            // labels from blown highlights while continuous exposure remains on.
            let glareBias = max(device.minExposureTargetBias, min(-0.15, device.maxExposureTargetBias))
            device.setExposureTargetBias(glareBias, completionHandler: nil)
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        } catch {
            // Default camera settings are a safe fallback.
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let engine = engineProvider(),
              let hit = engine.process(sampleBuffer: sampleBuffer),
              hit.hasContent else { return }
        DispatchQueue.main.async { [weak self] in self?.onHit?(hit.normalized) }
    }
}
