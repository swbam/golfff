import AVFoundation
import CoreMedia
import UIKit

/// RealTimeRecordingManager - Records video with tracer already composited
///
/// KEY DIFFERENCE from AVCaptureMovieFileOutput:
/// - Uses AVAssetWriter to write COMPOSITED frames
/// - Each frame has tracer baked in DURING recording
/// - Export is INSTANT (no post-processing needed!)
///
/// This is how SmoothSwing achieves live = export!
final class RealTimeRecordingManager {
    
    // MARK: - Types
    
    enum RecordingState {
        case idle
        case preparing
        case recording
        case finishing
        case failed(Error)
    }
    
    struct RecordingError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
        
        static let notConfigured = RecordingError(message: "Recording not configured")
        static let alreadyRecording = RecordingError(message: "Already recording")
        static let notRecording = RecordingError(message: "Not currently recording")
        static let writerFailed = RecordingError(message: "AVAssetWriter failed to start")
        static let appendFailed = RecordingError(message: "Failed to append sample buffer")
    }
    
    // MARK: - Callbacks
    
    var onRecordingStarted: (() -> Void)?
    var onRecordingFinished: ((URL) -> Void)?
    var onRecordingFailed: ((Error) -> Void)?
    
    // MARK: - Properties
    
    private(set) var state: RecordingState = .idle
    private(set) var outputURL: URL?
    private(set) var recordingDuration: TimeInterval = 0
    
    // AVAssetWriter
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    // Real-time compositor
    private let compositor: RealTimeCompositor?
    
    // Timing
    private var startTime: CMTime?
    private var lastVideoTime: CMTime?
    private var lastAudioTime: CMTime?
    
    // Configuration
    private var videoSettings: [String: Any]?
    private var audioSettings: [String: Any]?
    private var videoTransform: CGAffineTransform = .identity
    
    // Thread safety
    private let writingQueue = DispatchQueue(label: "com.tracer.recording.writing", qos: .userInitiated)
    private let lock = NSLock()
    
    // Debug
    var debugLogging: Bool = false
    private var frameCount: Int = 0
    private var droppedFrames: Int = 0
    
    // MARK: - Initialization
    
    init(compositor: RealTimeCompositor?) {
        self.compositor = compositor
    }
    
    convenience init() {
        self.init(compositor: RealTimeCompositor())
    }
    
    // MARK: - Configuration
    
    /// Configure video settings (call before starting recording)
    func configureVideo(
        width: Int,
        height: Int,
        frameRate: Float = 30,
        bitRate: Int? = nil,
        transform: CGAffineTransform = .identity
    ) {
        // Calculate appropriate bitrate (higher for higher resolutions)
        let calculatedBitRate = bitRate ?? (width * height * 4)  // ~4 bits per pixel
        
        videoSettings = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: calculatedBitRate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: Int(frameRate * 2),  // Keyframe every 2 seconds
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false  // Lower latency
            ]
        ]
        
        videoTransform = transform
        
        // Configure compositor output size
        compositor?.configure(width: width, height: height)
        
        if debugLogging {
            print("📹 RealTimeRecordingManager configured: \(width)x\(height) @ \(frameRate)fps")
        }
    }
    
    /// Configure audio settings
    func configureAudio(sampleRate: Double = 44100, channels: Int = 1) {
        audioSettings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 128000
        ]
    }
    
    // MARK: - Recording Control
    
    /// Start recording to a new file
    func startRecording() throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard case .idle = state else {
            throw RecordingError.alreadyRecording
        }
        
        guard videoSettings != nil else {
            throw RecordingError.notConfigured
        }
        
        state = .preparing
        
        // Create output URL
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "tracer_\(UUID().uuidString).mp4"
        let url = tempDir.appendingPathComponent(filename)
        
        // Remove existing file if any
        try? FileManager.default.removeItem(at: url)
        
        outputURL = url
        
        do {
            // Create asset writer
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            
            // Create video input
            let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoIn.expectsMediaDataInRealTime = true
            videoIn.transform = videoTransform
            
            // Create pixel buffer adaptor for efficient writing
            let sourceBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoIn,
                sourcePixelBufferAttributes: sourceBufferAttributes
            )
            
            if writer.canAdd(videoIn) {
                writer.add(videoIn)
            }
            
            // Create audio input if configured
            var audioIn: AVAssetWriterInput?
            if let audioSettings = audioSettings {
                let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audio.expectsMediaDataInRealTime = true
                
                if writer.canAdd(audio) {
                    writer.add(audio)
                    audioIn = audio
                }
            }
            
            // Start writing
            guard writer.startWriting() else {
                throw writer.error ?? RecordingError.writerFailed
            }
            
            // Store references
            self.assetWriter = writer
            self.videoInput = videoIn
            self.audioInput = audioIn
            self.pixelBufferAdaptor = adaptor
            
            // Reset timing
            self.startTime = nil
            self.lastVideoTime = nil
            self.lastAudioTime = nil
            self.frameCount = 0
            self.droppedFrames = 0
            self.recordingDuration = 0
            
            // Enable compositor
            compositor?.isCompositing = true
            compositor?.resetStats()
            
            state = .recording
            
            if debugLogging {
                print("═══════════════════════════════════════")
                print("🎬 REAL-TIME RECORDING STARTED")
                print("   Output: \(url.lastPathComponent)")
                print("═══════════════════════════════════════")
            }
            
            onRecordingStarted?()
            
        } catch {
            state = .failed(error)
            throw error
        }
    }
    
    /// Stop recording and finalize the file
    func stopRecording() {
        lock.lock()
        guard case .recording = state else {
            lock.unlock()
            return
        }
        state = .finishing
        lock.unlock()
        
        // Disable compositor
        compositor?.isCompositing = false
        
        writingQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            
            self.assetWriter?.finishWriting { [weak self] in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if let error = self.assetWriter?.error {
                        self.state = .failed(error)
                        self.onRecordingFailed?(error)
                        
                        if self.debugLogging {
                            print("❌ Recording failed: \(error.localizedDescription)")
                        }
                    } else if let url = self.outputURL {
                        self.state = .idle
                        
                        if self.debugLogging {
                            print("═══════════════════════════════════════")
                            print("✅ RECORDING COMPLETE")
                            print("   Duration: \(String(format: "%.2f", self.recordingDuration))s")
                            print("   Frames: \(self.frameCount)")
                            print("   Dropped: \(self.droppedFrames)")
                            print("   File: \(url.lastPathComponent)")
                            print("═══════════════════════════════════════")
                        }
                        
                        self.onRecordingFinished?(url)
                    }
                    
                    // Cleanup
                    self.assetWriter = nil
                    self.videoInput = nil
                    self.audioInput = nil
                    self.pixelBufferAdaptor = nil
                }
            }
        }
    }
    
    /// Cancel recording and discard the file
    func cancelRecording() {
        lock.lock()
        guard case .recording = state else {
            lock.unlock()
            return
        }
        lock.unlock()
        
        compositor?.isCompositing = false
        
        assetWriter?.cancelWriting()
        
        // Delete file
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        state = .idle
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
        
        if debugLogging {
            print("🚫 Recording cancelled")
        }
    }
    
    // MARK: - Frame Processing
    
    /// Process and write a video frame (with tracer composited)
    func processVideoFrame(_ sampleBuffer: CMSampleBuffer, trajectory: Trajectory?) {
        guard case .recording = state else { return }
        guard let videoInput = videoInput, videoInput.isReadyForMoreMediaData else {
            droppedFrames += 1
            return
        }
        
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        // Set start time on first frame
        if startTime == nil {
            startTime = presentationTime
            assetWriter?.startSession(atSourceTime: presentationTime)
            
            if debugLogging {
                print("⏱️ Recording session started at \(presentationTime.seconds)s")
            }
        }
        
        // Update trajectory on compositor
        if let trajectory = trajectory {
            compositor?.updateTrajectory(trajectory)
        }
        
        // Get pixel buffer from sample
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Composite tracer onto frame
        let compositedBuffer: CVPixelBuffer
        if let compositor = compositor, let composited = compositor.composite(pixelBuffer: pixelBuffer) {
            compositedBuffer = composited
        } else {
            compositedBuffer = pixelBuffer
        }
        
        // Write composited frame
        writingQueue.async { [weak self] in
            guard let self = self,
                  let adaptor = self.pixelBufferAdaptor,
                  self.videoInput?.isReadyForMoreMediaData == true else { return }
            
            if adaptor.append(compositedBuffer, withPresentationTime: presentationTime) {
                self.frameCount += 1
                self.lastVideoTime = presentationTime
                
                // Update duration
                if let start = self.startTime {
                    self.recordingDuration = (presentationTime - start).seconds
                }
            } else {
                self.droppedFrames += 1
                if self.debugLogging {
                    print("⚠️ Failed to append video frame")
                }
            }
        }
    }
    
    /// Process and write an audio sample
    func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard case .recording = state else { return }
        guard let audioInput = audioInput, audioInput.isReadyForMoreMediaData else { return }
        
        // Don't write audio before video session starts
        guard startTime != nil else { return }
        
        writingQueue.async { [weak self] in
            guard let self = self,
                  self.audioInput?.isReadyForMoreMediaData == true else { return }
            
            if audioInput.append(sampleBuffer) {
                self.lastAudioTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            }
        }
    }
    
    // MARK: - Compositor Access
    
    /// Update tracer color
    func setTracerColor(_ color: UIColor) {
        compositor?.tracerColor = color
    }
    
    /// Update tracer style
    func setTracerStyle(_ style: TracerStyle) {
        compositor?.tracerStyle = style
    }
    
    /// Clear trajectory (called when starting new shot)
    func clearTrajectory() {
        compositor?.clearTrajectory()
    }
    
    // MARK: - Status
    
    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }
    
    var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }
}
