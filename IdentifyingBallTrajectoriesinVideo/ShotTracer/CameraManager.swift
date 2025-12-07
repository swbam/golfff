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

final class CameraManager: NSObject {
    weak var delegate: CameraManagerDelegate?

    let previewView: PreviewView
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.shottracer.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoQueue = DispatchQueue(label: "com.shottracer.vision")

    private(set) var isRecording = false
    private(set) var isConfigured = false
    private(set) var isRunning = false

    init(previewView: PreviewView = PreviewView()) {
        self.previewView = previewView
        super.init()
        self.previewView.videoPreviewLayer.session = session
        self.previewView.videoPreviewLayer.videoGravity = .resizeAspectFill
    }

    func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            print("📷 Configuring camera session...")
            
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
            self.session.sessionPreset = .hd1920x1080

            // Add video input
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("❌ No back camera available")
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.delegate?.cameraManager(self, didFail: CameraError.noCameraAvailable)
                    self.delegate?.cameraManagerDidConfigure(self, success: false)
                }
                return
            }
            
            print("📷 Found camera: \(device.localizedName)")

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

            // Add video output for Vision processing
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                print("✅ Video output added")
            }

            // Add movie output for recording
            if self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
                self.movieOutput.movieFragmentInterval = .invalid
                print("✅ Movie output added")
            }

            self.session.commitConfiguration()
            self.isConfigured = true
            print("✅ Camera session configured successfully")
            
            // NOW start the session
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
            print("🎬 Recording started: \(fileURL.lastPathComponent)")
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
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.cameraManager(self, didOutput: sampleBuffer)
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
                DispatchQueue.main.async {
                    self.delegate?.cameraManager(self, didFinishRecordingTo: outputFileURL)
                }
            }
        }
    }
}
