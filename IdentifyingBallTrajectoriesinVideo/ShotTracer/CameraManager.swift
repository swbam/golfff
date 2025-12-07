import AVFoundation
import UIKit

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: CameraManager, didFinishRecordingTo url: URL)
    func cameraManager(_ manager: CameraManager, didFail error: Error)
    func cameraManagerDidConfigure(_ manager: CameraManager, success: Bool)
}

// Default implementation for optional methods
extension CameraManagerDelegate {
    func cameraManagerDidConfigure(_ manager: CameraManager, success: Bool) {}
}

enum CameraError: LocalizedError {
    case noCameraAvailable
    case noMicrophoneAvailable
    case cameraPermissionDenied
    case microphonePermissionDenied
    case configurationFailed
    case simulatorMode
    
    var errorDescription: String? {
        switch self {
        case .noCameraAvailable:
            return "No camera available. Camera is required for this app."
        case .noMicrophoneAvailable:
            return "No microphone available."
        case .cameraPermissionDenied:
            return "Camera access denied. Please enable in Settings."
        case .microphonePermissionDenied:
            return "Microphone access denied. Please enable in Settings."
        case .configurationFailed:
            return "Failed to configure camera session."
        case .simulatorMode:
            return "Camera not available on simulator. Please use a real device."
        }
    }
}

/// Camera Manager with HIGH FRAME RATE support for golf ball tracking
/// 
/// KEY INSIGHT: Recording at 240fps makes ball detection 4x easier:
/// - Ball moves ~1 foot per frame instead of ~4 feet
/// - Much less motion blur
/// - Smaller search window needed
/// 
/// Then we export at 30fps - trajectory timestamps still match!
final class CameraManager: NSObject {
    weak var delegate: CameraManagerDelegate?

    let previewView: PreviewView
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.shottracer.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoQueue = DispatchQueue(label: "com.shottracer.vision", qos: .userInteractive)

    private(set) var isRecording = false
    private(set) var isConfigured = false
    private(set) var isRunning = false
    
    /// Current capture frame rate
    private(set) var currentFrameRate: Double = 60
    
    /// Target frame rate for capture (240fps if available, falls back to highest)
    var targetFrameRate: Double = 240
    
    /// Export frame rate (30fps standard)
    let exportFrameRate: Double = 30

    init(previewView: PreviewView = PreviewView()) {
        self.previewView = previewView
        super.init()
        self.previewView.videoPreviewLayer.session = session
        self.previewView.videoPreviewLayer.videoGravity = .resizeAspectFill
    }

    func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            print("═══════════════════════════════════════")
            print("📷 CONFIGURING HIGH FRAME RATE CAPTURE")
            print("═══════════════════════════════════════")
            
            // Check camera permission
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                print("📷 Camera permission: authorized")
            case .notDetermined:
                print("📷 Camera permission: requesting...")
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        print("📷 Camera permission: granted")
                        self.configureSession()
                    } else {
                        print("❌ Camera permission: denied by user")
                        DispatchQueue.main.async {
                            self.delegate?.cameraManager(self, didFail: CameraError.cameraPermissionDenied)
                            self.delegate?.cameraManagerDidConfigure(self, success: false)
                        }
                    }
                }
                return
            case .denied, .restricted:
                print("❌ Camera permission: denied/restricted")
                DispatchQueue.main.async {
                    self.delegate?.cameraManager(self, didFail: CameraError.cameraPermissionDenied)
                    self.delegate?.cameraManagerDidConfigure(self, success: false)
                }
                return
            @unknown default:
                return
            }
            
            self.session.beginConfiguration()

            // Find camera with highest frame rate support
            guard let device = self.findBestCamera() else {
                print("❌ No suitable camera available")
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.delegate?.cameraManager(self, didFail: CameraError.noCameraAvailable)
                    self.delegate?.cameraManagerDidConfigure(self, success: false)
                }
                return
            }
            
            print("📷 Using camera: \(device.localizedName)")
            
            // Configure for high frame rate
            self.configureHighFrameRate(device: device)

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    print("✅ Camera input added")
                } else {
                    throw CameraError.configurationFailed
                }
            } catch {
                print("❌ Camera input error: \(error)")
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.delegate?.cameraManager(self, didFail: error)
                    self.delegate?.cameraManagerDidConfigure(self, success: false)
                }
                return
            }

            // Add audio input
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                do {
                    let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                    if self.session.canAddInput(audioInput) {
                        self.session.addInput(audioInput)
                        print("✅ Audio input added")
                    }
                } catch {
                    print("⚠️ Could not add audio input: \(error)")
                }
            }

            // Add video output for Vision processing (HIGH FRAME RATE!)
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
                self.videoOutput.alwaysDiscardsLateVideoFrames = false  // Don't discard - we need all frames!
                self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                print("✅ Video output added (high frame rate)")
            }

            // Add movie output for recording
            if self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
                self.movieOutput.movieFragmentInterval = .invalid
                print("✅ Movie output added")
            }

            self.session.commitConfiguration()
            self.isConfigured = true
            
            print("═══════════════════════════════════════")
            print("✅ CAMERA CONFIGURED")
            print("   Frame rate: \(self.currentFrameRate) fps")
            print("   Export rate: \(self.exportFrameRate) fps")
            print("═══════════════════════════════════════")
            
            // Start the session
            if !self.session.isRunning {
                self.session.startRunning()
                self.isRunning = self.session.isRunning
                print("✅ Camera session started: \(self.session.isRunning)")
            }
            
            DispatchQueue.main.async {
                self.delegate?.cameraManagerDidConfigure(self, success: true)
            }
        }
    }
    
    // MARK: - High Frame Rate Configuration
    
    private func findBestCamera() -> AVCaptureDevice? {
        // Prefer back camera with best specs
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera],
            mediaType: .video,
            position: .back
        )
        
        // Find device that supports highest frame rate
        var bestDevice: AVCaptureDevice?
        var highestFrameRate: Double = 0
        
        for device in discoverySession.devices {
            for format in device.formats {
                for range in format.videoSupportedFrameRateRanges {
                    if range.maxFrameRate > highestFrameRate {
                        // Check if format is suitable (not too low resolution)
                        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                        if dimensions.width >= 1280 && dimensions.height >= 720 {
                            highestFrameRate = range.maxFrameRate
                            bestDevice = device
                        }
                    }
                }
            }
        }
        
        print("📷 Best available frame rate: \(highestFrameRate) fps")
        
        return bestDevice ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
    
    private func configureHighFrameRate(device: AVCaptureDevice) {
        // Find format that supports our target frame rate (or highest available)
        var bestFormat: AVCaptureDevice.Format?
        var bestFrameRateRange: AVFrameRateRange?
        var bestFrameRate: Double = 0
        
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            
            // We want at least 720p
            guard dimensions.width >= 1280 && dimensions.height >= 720 else { continue }
            
            // Prefer 1080p if available
            let is1080p = dimensions.width >= 1920 && dimensions.height >= 1080
            
            for range in format.videoSupportedFrameRateRanges {
                // Check if this format supports our target or better
                if range.maxFrameRate >= targetFrameRate {
                    if bestFormat == nil || (is1080p && bestFrameRate < targetFrameRate) {
                        bestFormat = format
                        bestFrameRateRange = range
                        bestFrameRate = min(range.maxFrameRate, targetFrameRate)
                    }
                } else if range.maxFrameRate > bestFrameRate {
                    // Fall back to highest available
                    bestFormat = format
                    bestFrameRateRange = range
                    bestFrameRate = range.maxFrameRate
                }
            }
        }
        
        guard let format = bestFormat, let frameRateRange = bestFrameRateRange else {
            print("⚠️ Could not find suitable format, using default")
            currentFrameRate = 60
            return
        }
        
        do {
            try device.lockForConfiguration()
            
            device.activeFormat = format
            
            // Set frame rate
            let targetRate = min(bestFrameRate, frameRateRange.maxFrameRate)
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetRate))
            
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            
            // Optimize for video recording
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            
            // Use continuous autofocus
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            // Use continuous exposure
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            device.unlockForConfiguration()
            
            currentFrameRate = targetRate
            
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            print("📷 Configured: \(dimensions.width)x\(dimensions.height) @ \(targetRate) fps")
            
        } catch {
            print("❌ Could not configure high frame rate: \(error)")
            currentFrameRate = 60
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard self.isConfigured else {
                print("⚠️ Cannot start session - not configured yet")
                return
            }
            
            if !self.session.isRunning {
                self.session.startRunning()
                self.isRunning = self.session.isRunning
                print("📷 Camera session started: \(self.session.isRunning)")
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
                self.isRunning = false
                print("📷 Camera session stopped")
            }
        }
    }

    func startRecording() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard self.isConfigured, self.session.isRunning else {
                print("⚠️ Cannot record - session not ready")
                return
            }
            
            guard !self.isRecording else { return }
            
            self.isRecording = true
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            let fileURL = tempDir.appendingPathComponent("shot_\(UUID().uuidString).mov")
            self.movieOutput.startRecording(to: fileURL, recordingDelegate: self)
            
            print("═══════════════════════════════════════")
            print("🎬 RECORDING STARTED @ \(self.currentFrameRate) fps")
            print("   Output: \(fileURL.lastPathComponent)")
            print("═══════════════════════════════════════")
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.isRecording else { return }
            self.movieOutput.stopRecording()
            print("🎬 Recording stopped")
        }
    }
    
    /// Get the ratio for downsampling frames (e.g., 240fps → 30fps = 8:1)
    var frameDownsampleRatio: Int {
        return max(1, Int(currentFrameRate / exportFrameRate))
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Every frame at high frame rate!
        delegate?.cameraManager(self, didOutput: sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Log dropped frames - shouldn't happen often
        print("⚠️ Dropped frame")
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.isRecording = false
            if let error = error {
                print("❌ Recording error: \(error)")
                DispatchQueue.main.async {
                    self.delegate?.cameraManager(self, didFail: error)
                }
            } else {
                print("✅ Recording finished: \(outputFileURL.lastPathComponent)")
                print("   Frame rate: \(self.currentFrameRate) fps")
                DispatchQueue.main.async {
                    self.delegate?.cameraManager(self, didFinishRecordingTo: outputFileURL)
                }
            }
        }
    }
}
