import UIKit
import AVFoundation
import Photos
import PhotosUI

// MARK: - Premium Shot View Controller
/// Main view controller for live golf shot recording and tracing
/// 
/// Flow:
/// 1. Alignment - User aligns with silhouette (ball position is FIXED)
/// 2. Record - High frame rate capture (240fps)
/// 3. Track - Detect ball in flight
/// 4. Export - Video with tracer overlay at 30fps
final class PremiumShotViewController: UIViewController {
    
    // MARK: - Core Components
    private let cameraManager = CameraManager()
    private let trajectoryDetector = TrajectoryDetector()
    private lazy var sessionController = ShotSessionController(
        cameraManager: cameraManager,
        trajectoryDetector: trajectoryDetector
    )
    
    // MARK: - UI Components
    private let glowingTracerView = GlowingTracerView()
    private let recordingControls = RecordingControlsView()
    private let liveYardageView = LiveYardageView(frame: .zero)
    
    // Recording timer
    private var timer: Timer?
    private var recordingStart: Date?
    
    // Alignment state
    private var hasShownAlignment = false
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        
        // In simulator, skip camera and go straight to test mode
        #if targetEnvironment(simulator)
        // Don't start camera in simulator - run tests instead!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.runTestsAutomatically()
        }
        #else
        sessionController.startSession()
        #endif
        
        // Show test mode button in simulator/debug
        #if DEBUG
        setupDebugUI()
        #endif
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        #if targetEnvironment(simulator)
        // Skip alignment in simulator - we're running tests instead
        return
        #else
        if !hasShownAlignment {
            hasShownAlignment = true
            presentAlignment()
        }
        #endif
    }
    
    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = ShotTracerDesign.Colors.background
        
        // Camera preview - full screen
        let previewView = cameraManager.previewView
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        
        // Glowing tracer overlay
        glowingTracerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(glowingTracerView)
        
        // Live yardage display (PGA-style)
        liveYardageView.translatesAutoresizingMaskIntoConstraints = false
        liveYardageView.alpha = 0 // Hidden until ball is detected
        view.addSubview(liveYardageView)
        
        // Recording controls
        recordingControls.translatesAutoresizingMaskIntoConstraints = false
        recordingControls.delegate = self
        view.addSubview(recordingControls)
        
        NSLayoutConstraint.activate([
            // Preview fills entire view
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Tracer overlay matches preview
            glowingTracerView.topAnchor.constraint(equalTo: previewView.topAnchor),
            glowingTracerView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor),
            glowingTracerView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
            glowingTracerView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
            
            // Live yardage display (top-right corner, PGA-style)
            liveYardageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            liveYardageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            liveYardageView.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            
            // Controls overlay fills view
            recordingControls.topAnchor.constraint(equalTo: view.topAnchor),
            recordingControls.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            recordingControls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            recordingControls.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
    
    private func setupBindings() {
        sessionController.delegate = self
    }
    
    // MARK: - Alignment
    /// Present the alignment screen where user positions themselves with the silhouette
    /// The ball position is FIXED in the silhouette - NO TAP REQUIRED!
    private func presentAlignment() {
        #if targetEnvironment(simulator)
        // Skip alignment on simulator - no camera available
        sessionController.state = .ready
        showSimulatorWarning()
        return
        #else
        guard let session = cameraManager.previewView.videoPreviewLayer.session,
              cameraManager.isConfigured else {
            sessionController.state = .ready
            return
        }
        
        sessionController.state = .aligning
        
        let alignmentVC = PremiumAlignmentViewController(session: session) { [weak self] result in
            guard let self = self else { return }
            
            // Set ROI and ball position from silhouette
            // Ball position comes from silhouette - NO USER TAP REQUIRED!
            self.sessionController.setRegionOfInterest(result.roi)
            self.sessionController.lockPosition(ballPosition: result.ballPosition)
            self.sessionController.state = .ready
        }
        
        present(alignmentVC, animated: true)
        #endif
    }
    
    private func showSimulatorWarning() {
        let alert = UIAlertController(
            title: "Simulator Mode",
            message: "Camera features are not available in the simulator. To test the full app, please run on a real iOS device with a camera.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Recording Timer
    private func startTimer() {
        recordingStart = Date()
        recordingControls.recordingDuration = 0
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let start = self?.recordingStart else { return }
            self?.recordingControls.recordingDuration = Date().timeIntervalSince(start)
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Error Handling
    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - RecordingControlsDelegate
extension PremiumShotViewController: RecordingControlsDelegate {
    
    func recordingControlsDidTapRecord(_ controls: RecordingControlsView) {
        switch sessionController.state {
        case .ready:
            // Start recording at HIGH FRAME RATE
            sessionController.startRecording()
            controls.isRecording = true
            startTimer()
            glowingTracerView.clear()
            ShotTracerDesign.Haptics.recordStart()
            
        case .recording:
            // Stop recording - will process and export
            sessionController.stopRecording()
            controls.isRecording = false
            stopTimer()
            ShotTracerDesign.Haptics.recordStop()
            
        default:
            break
        }
    }
    
    func recordingControlsDidTapSettings(_ controls: RecordingControlsView) {
        let settingsVC = SettingsViewController()
        let nav = UINavigationController(rootViewController: settingsVC)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }
    
    func recordingControlsDidTapRealign(_ controls: RecordingControlsView) {
        hasShownAlignment = false
        presentAlignment()
    }
    
    func recordingControlsDidTapImport(_ controls: RecordingControlsView) {
        presentVideoPicker()
    }
    
    func recordingControls(_ controls: RecordingControlsView, didSelectColor color: UIColor) {
        sessionController.setTracerColor(color)
        glowingTracerView.tracerColor = color
    }
    
    func recordingControls(_ controls: RecordingControlsView, didSelectStyle style: TracerStyle) {
        sessionController.setTracerStyle(style)
        glowingTracerView.tracerStyle = style
    }
}

// MARK: - ShotSessionControllerDelegate
extension PremiumShotViewController: ShotSessionControllerDelegate {
    
    func shotSession(_ controller: ShotSessionController, didUpdateState state: ShotState) {
        switch state {
        case .recording:
            recordingControls.statusText = "Recording @ \(Int(cameraManager.currentFrameRate))fps"
            
        case .tracking:
            recordingControls.statusText = "Processing..."
            
        case .exporting:
            recordingControls.statusText = "Exporting..."
            recordingControls.isRecording = false
            
        case .ready:
            recordingControls.statusText = "Ready"
            recordingControls.resetTimer()
            
        case .aligning:
            recordingControls.statusText = "Aligning..."
            
        case .idle:
            recordingControls.statusText = "Initializing..."
            
        case .finished:
            recordingControls.statusText = "Ready"
            
        case .importing:
            // Not used anymore
            recordingControls.statusText = "Processing..."
        }
    }
    
    func shotSession(_ controller: ShotSessionController, didUpdateTrajectory trajectory: Trajectory) {
        // Use projectedPoints for live rendering (smooth full arc)
        // This ensures LIVE = EXPORT
        let pointsToRender = trajectory.projectedPoints.isEmpty
            ? trajectory.detectedPoints
            : trajectory.projectedPoints
        
        let normalizedPoints = pointsToRender.map { $0.normalized }
        glowingTracerView.update(with: normalizedPoints, color: controller.tracerColor)
        
        // Show yardage view when trajectory is detected
        if !normalizedPoints.isEmpty {
            liveYardageView.setVisible(true)
        }
    }
    
    func shotSession(_ controller: ShotSessionController, didUpdateMetrics metrics: ShotMetrics) {
        liveYardageView.update(with: metrics)
    }
    
    func shotSession(_ controller: ShotSessionController, didFinishExportedVideo url: URL) {
        stopTimer()
        glowingTracerView.clear()
        recordingControls.resetTimer()
        liveYardageView.setVisible(false)
        liveYardageView.reset()
        
        // Present review screen
        let reviewVC = PremiumReviewViewController(videoURL: url)
        present(reviewVC, animated: true) {
            self.sessionController.state = .ready
        }
    }
    
    func shotSession(_ controller: ShotSessionController, didFail error: Error) {
        stopTimer()
        recordingControls.isRecording = false
        recordingControls.resetTimer()
        showError(error)
    }
}

// MARK: - Video Import

extension PremiumShotViewController: PHPickerViewControllerDelegate {
    
    func presentVideoPicker() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard let result = results.first else { return }
        
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Loading Video", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Get the video asset
        if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        if let error = error {
                            self?.showError(error)
                            return
                        }
                        
                        guard let url = url else {
                            self?.showError(NSError(domain: "VideoImport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not load video"]))
                            return
                        }
                        
                        // Copy to temp location since the URL is temporary
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("imported_\(UUID().uuidString).mov")
                        
                        do {
                            if FileManager.default.fileExists(atPath: tempURL.path) {
                                try FileManager.default.removeItem(at: tempURL)
                            }
                            try FileManager.default.copyItem(at: url, to: tempURL)
                            
                            // Process the imported video
                            self?.processImportedVideo(at: tempURL)
                        } catch {
                            self?.showError(error)
                        }
                    }
                }
            }
        }
    }
    
    private func processImportedVideo(at url: URL) {
        // Open test mode with the video
        let testVC = TestModeViewController()
        testVC.preloadedVideoURL = url
        let nav = UINavigationController(rootViewController: testVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
}

// MARK: - Debug UI (DEBUG builds only)

#if DEBUG
extension PremiumShotViewController {
    
    func setupDebugUI() {
        // Only show prominent test button on simulator (no camera)
        #if targetEnvironment(simulator)
        addSimulatorTestUI()
        #else
        // On device, just add a subtle debug indicator
        addDebugIndicator()
        #endif
    }
    
    private func addSimulatorTestUI() {
        // Large test mode button for simulator
        let testButton = UIButton(type: .system)
        testButton.setTitle("🧪 Open Test Mode", for: .normal)
        testButton.titleLabel?.font = ShotTracerDesign.Typography.button()
        testButton.backgroundColor = ShotTracerDesign.Colors.mastersGreen
        testButton.setTitleColor(.white, for: .normal)
        testButton.layer.cornerRadius = ShotTracerDesign.CornerRadius.medium
        testButton.translatesAutoresizingMaskIntoConstraints = false
        
        testButton.addTarget(self, action: #selector(openTestMode), for: .touchUpInside)
        
        view.addSubview(testButton)
        
        NSLayoutConstraint.activate([
            testButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            testButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            testButton.widthAnchor.constraint(equalToConstant: 200),
            testButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Info label
        let infoLabel = UILabel()
        infoLabel.text = "Camera not available in Simulator.\nUse Test Mode to verify the tracer."
        infoLabel.font = ShotTracerDesign.Typography.caption()
        infoLabel.textColor = ShotTracerDesign.Colors.textSecondary
        infoLabel.textAlignment = .center
        infoLabel.numberOfLines = 0
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(infoLabel)
        
        NSLayoutConstraint.activate([
            infoLabel.topAnchor.constraint(equalTo: testButton.bottomAnchor, constant: 20),
            infoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            infoLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        ])
        
        // Quick load button
        let quickLoadButton = UIButton(type: .system)
        quickLoadButton.setTitle("⚡ Quick Load First Video", for: .normal)
        quickLoadButton.titleLabel?.font = ShotTracerDesign.Typography.buttonSmall()
        quickLoadButton.backgroundColor = ShotTracerDesign.Colors.surfaceOverlay
        quickLoadButton.setTitleColor(ShotTracerDesign.Colors.championshipGold, for: .normal)
        quickLoadButton.layer.cornerRadius = ShotTracerDesign.CornerRadius.small
        quickLoadButton.translatesAutoresizingMaskIntoConstraints = false
        
        quickLoadButton.addTarget(self, action: #selector(quickLoadVideo), for: .touchUpInside)
        
        view.addSubview(quickLoadButton)
        
        NSLayoutConstraint.activate([
            quickLoadButton.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 16),
            quickLoadButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            quickLoadButton.widthAnchor.constraint(equalToConstant: 200),
            quickLoadButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    private func addDebugIndicator() {
        // Small debug indicator on device
        let debugLabel = UILabel()
        debugLabel.text = "DEBUG"
        debugLabel.font = ShotTracerDesign.Typography.small()
        debugLabel.textColor = ShotTracerDesign.Colors.championshipGold.withAlphaComponent(0.5)
        debugLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(debugLabel)
        
        NSLayoutConstraint.activate([
            debugLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            debugLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8)
        ])
    }
    
    @objc private func openTestMode() {
        let testVC = TestModeViewController()
        let nav = UINavigationController(rootViewController: testVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
    
    private func runTestsAutomatically() {
        print("═══════════════════════════════════════════════════════")
        print("🧪 AUTO-RUNNING BALL TRACKER TESTS IN SIMULATOR")
        print("═══════════════════════════════════════════════════════")
        
        BallTrackerTests.shared.runAllTests { results in
            let passed = results.filter { $0.passed }.count
            let failed = results.filter { !$0.passed }.count
            
            print("\n═══════════════════════════════════════════════════════")
            print("✅ TEST RESULTS: \(passed) passed, \(failed) failed")
            print("═══════════════════════════════════════════════════════")
            
            // Show results in UI
            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: "Shot Tracer Tests",
                    message: "\(passed) tests passed\n\(failed) tests failed\n\nSee console for details.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "View Test Mode", style: .default) { _ in
                    self.openTestMode()
                })
                alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                self.present(alert, animated: true)
            }
        }
    }
    
    @objc private func quickLoadVideo() {
        TestVideoProcessor.loadFirstVideoFromLibrary { [weak self] asset in
            if asset != nil {
                // Open test mode with this video pre-loaded
                let testVC = TestModeViewController()
                let nav = UINavigationController(rootViewController: testVC)
                nav.modalPresentationStyle = .fullScreen
                self?.present(nav, animated: true) {
                    // Could pass the asset to testVC here if needed
                }
            } else {
                let alert = UIAlertController(
                    title: "No Videos Found",
                    message: "Add a video to the Simulator:\n\n1. Drag a .mov or .mp4 file onto the Simulator window\n2. It will be saved to Photos",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            }
        }
    }
}
#endif
