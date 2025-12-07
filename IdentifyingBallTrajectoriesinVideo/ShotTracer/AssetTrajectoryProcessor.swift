import AVFoundation
import Vision

/// Processes video assets to detect golf ball trajectories
/// Uses BALL TRACKING from a known starting position (the key to making this work!)
final class AssetTrajectoryProcessor: NSObject {
    
    private var completion: ((Result<Trajectory?, Error>) -> Void)?
    private var didComplete = false
    
    // Ball tracker (tracks from known position)
    private let ballTracker = BallTracker()
    
    // Initial ball position (SET BY USER - this is critical!)
    private var initialBallPosition: CGPoint?
    
    // Detection settings
    private var regionOfInterest: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    private var videoOrientation: CGImagePropertyOrientation = .up
    
    // Legacy support
    private weak var legacyDetector: TrajectoryDetector?

    // Vision trajectory detection
    private var visionObservation: VNTrajectoryObservation?
    private let visionSequenceHandler = VNSequenceRequestHandler()
    
    override init() {
        super.init()
    }
    
    convenience init(detector: TrajectoryDetector) {
        self.init()
        self.legacyDetector = detector
        self.regionOfInterest = detector.regionOfInterest ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        self.videoOrientation = detector.orientation
    }
    
    convenience init(roi: CGRect?, orientation: CGImagePropertyOrientation) {
        self.init()
        if let roi = roi {
            self.regionOfInterest = roi
        }
        self.videoOrientation = orientation
    }
    
    /// Set the initial ball position (from user tap)
    func setInitialBallPosition(_ position: CGPoint) {
        self.initialBallPosition = position
        ballTracker.setInitialBallPosition(position)
    }
    
    // MARK: - Processing
    
    func process(asset: AVAsset, completion: @escaping (Result<Trajectory?, Error>) -> Void) {
        self.completion = completion
        self.didComplete = false
        ballTracker.reset()
        
        // If we have an initial ball position, use it
        if let initialPos = initialBallPosition {
            ballTracker.setInitialBallPosition(initialPos)
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.processAssetSync(asset: asset)
        }
    }
    
    private func processAssetSync(asset: AVAsset) {
        print("═══════════════════════════════════════")
        print("🔍 BALL TRACKING STARTING")
        print("═══════════════════════════════════════")
        
        if let initialPos = initialBallPosition {
            print("✅ Initial ball position: (\(String(format: "%.3f", initialPos.x)), \(String(format: "%.3f", initialPos.y)))")
        } else {
            print("⚠️ NO INITIAL BALL POSITION - Detection may fail!")
        }
        
        guard let track = asset.tracks(withMediaType: .video).first else {
            print("❌ No video track found!")
            finishOnce(.failure(ShotExportError.missingAsset))
            return
        }
        
        let duration = asset.duration
        let frameRate = track.nominalFrameRate
        let transform = track.preferredTransform
        let naturalSize = track.naturalSize
        
        self.videoOrientation = orientationFromTransform(transform)
        
        print("📹 Video Properties:")
        print("   Duration: \(String(format: "%.2f", duration.seconds))s")
        print("   Frame rate: \(Int(frameRate)) fps")
        print("   Size: \(Int(naturalSize.width)) x \(Int(naturalSize.height))")
        print("   Orientation: \(videoOrientation.rawValue)")
        
        // Create asset reader
        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        do {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
            output.alwaysCopiesSampleData = false
            
            guard reader.canAdd(output) else {
                finishOnce(.failure(ShotExportError.missingAsset))
                return
            }
            reader.add(output)
            reader.startReading()
            
            var frameCount = 0
            var detectionCount = 0
            
            // Process each frame
            while reader.status == .reading {
                autoreleasepool {
                    guard let sampleBuffer = output.copyNextSampleBuffer() else { return }
                    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                    
                    let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    frameCount += 1
                    
                    // Track the ball from its known position
                    if ballTracker.processFrame(pixelBuffer, time: time, orientation: videoOrientation) != nil {
                        detectionCount += 1
                    }
                }
            }
            
            print("═══════════════════════════════════════")
            print("📊 TRACKING COMPLETE")
            print("   Frames processed: \(frameCount)")
            print("   Ball detections: \(detectionCount)")
            
            if reader.status == .failed, let error = reader.error {
                finishOnce(.failure(error))
                return
            }
            
            // Build trajectory from tracked positions
            let trajectory = ballTracker.buildTrajectory()
            
            if let traj = trajectory {
                print("✅ TRAJECTORY FOUND: \(traj.points.count) points")
                for (i, point) in traj.points.prefix(5).enumerated() {
                    print("   Point \(i): (\(String(format: "%.3f", point.normalized.x)), \(String(format: "%.3f", point.normalized.y)))")
                }
            } else {
                print("❌ NO TRAJECTORY DETECTED")
            }
            print("═══════════════════════════════════════")
            
            finishOnce(.success(trajectory))
            
        } catch {
            print("❌ Error: \(error)")
            finishOnce(.failure(error))
        }
    }
    
    // MARK: - Helpers
    
    private func orientationFromTransform(_ transform: CGAffineTransform) -> CGImagePropertyOrientation {
        if transform.a == 0 && transform.b == 1 && transform.c == -1 && transform.d == 0 {
            return .right
        } else if transform.a == 0 && transform.b == -1 && transform.c == 1 && transform.d == 0 {
            return .left
        } else if transform.a == -1 && transform.b == 0 && transform.c == 0 && transform.d == -1 {
            return .down
        }
        return .up
    }
    
    private func finishOnce(_ result: Result<Trajectory?, Error>) {
        guard !didComplete else { return }
        didComplete = true
        DispatchQueue.main.async { [weak self] in
            self?.completion?(result)
        }
    }
}
