import UIKit
import AVFoundation
import PhotosUI

// MARK: - Premium Shot View Controller
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
        sessionController.startSession()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasShownAlignment {
            hasShownAlignment = true
            presentAlignment()
        }
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
    private func presentAlignment() {
        // Skip alignment on simulator - no camera available
        #if targetEnvironment(simulator)
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
            
            // Set ROI and ball position
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
    
    // MARK: - Import Video
    private func presentImportPicker() {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    private func processImportedVideo(url: URL) {
        let asset = AVAsset(url: url)
        let roiPicker = ImportROIPickerViewController(asset: asset) { [weak self] result in
            guard let self = self else { return }
            
            // If trajectory was already detected during processing, export directly
            if let trajectory = result.trajectory, !trajectory.points.isEmpty {
                // Use the pre-detected trajectory
                self.sessionController.importVideoWithManualTrajectory(from: url, trajectory: trajectory)
            } else {
                // Fall back to auto-detect with ball position
                self.sessionController.importVideo(from: url, roi: result.roi, ballPosition: result.ballPosition)
            }
        }
        present(roiPicker, animated: true)
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
            // Start recording
            sessionController.startRecording()
            controls.isRecording = true
            startTimer()
            glowingTracerView.clear()
            ShotTracerDesign.Haptics.recordStart()
            
        case .recording:
            // Stop recording
            sessionController.stopRecording()
            controls.isRecording = false
            stopTimer()
            ShotTracerDesign.Haptics.recordStop()
            
        default:
            break
        }
    }
    
    func recordingControlsDidTapImport(_ controls: RecordingControlsView) {
        presentImportPicker()
    }
    
    func recordingControlsDidTapSettings(_ controls: RecordingControlsView) {
        presentSettings()
    }
    
    private func presentSettings() {
        let settingsVC = SettingsViewController()
        let nav = UINavigationController(rootViewController: settingsVC)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }
    
    func recordingControls(_ controls: RecordingControlsView, didSelectColor color: UIColor) {
        sessionController.setTracerColor(color)
        glowingTracerView.tracerColor = color
    }
    
    func recordingControls(_ controls: RecordingControlsView, didSelectStyle style: TracerStyle) {
        glowingTracerView.tracerStyle = style
    }
}

// MARK: - ShotSessionControllerDelegate
extension PremiumShotViewController: ShotSessionControllerDelegate {
    
    func shotSession(_ controller: ShotSessionController, didUpdateState state: ShotState) {
        switch state {
        case .recording:
            recordingControls.statusText = "Recording"
            
        case .tracking:
            recordingControls.statusText = "Processing..."
            
        case .exporting:
            recordingControls.statusText = "Exporting..."
            recordingControls.isRecording = false
            
        case .importing:
            recordingControls.statusText = "Importing..."
            
        case .ready:
            recordingControls.statusText = "Ready"
            recordingControls.resetTimer()
            
        case .aligning:
            recordingControls.statusText = "Aligning..."
            
        case .idle:
            recordingControls.statusText = "Initializing..."
            
        case .finished:
            recordingControls.statusText = "Ready"
        }
    }
    
    func shotSession(_ controller: ShotSessionController, didUpdateTrajectory trajectory: Trajectory) {
        let points = trajectory.points.map { $0.normalized }
        glowingTracerView.update(with: points, color: controller.tracerColor)
        
        // Show yardage view when trajectory is detected
        if !points.isEmpty {
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
        
        // Present review
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

// MARK: - PHPickerViewControllerDelegate
extension PremiumShotViewController: PHPickerViewControllerDelegate {
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard let provider = results.first?.itemProvider,
              provider.hasItemConformingToTypeIdentifier("public.movie") else {
            return
        }
        
        provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { [weak self] url, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.showError(error)
                }
                return
            }
            
            guard let url = url else { return }
            
            // Copy to temp directory
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("import_\(UUID().uuidString).mov")
            
            do {
                try FileManager.default.copyItem(at: url, to: tempURL)
                DispatchQueue.main.async {
                    self?.processImportedVideo(url: tempURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showError(error)
                }
            }
        }
    }
}

// MARK: - Scene Delegate Update
// Add this to your SceneDelegate.swift to use PremiumShotViewController as root

/*
 In SceneDelegate.swift, update the scene(_:willConnectTo:options:) method:
 
 func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
     guard let windowScene = (scene as? UIWindowScene) else { return }
     
     let window = UIWindow(windowScene: windowScene)
     window.rootViewController = PremiumShotViewController()
     self.window = window
     window.makeKeyAndVisible()
 }
 */

