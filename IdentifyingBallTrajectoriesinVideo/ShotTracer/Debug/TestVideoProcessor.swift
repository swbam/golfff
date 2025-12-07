import AVFoundation
import UIKit
import Photos
import Vision

/// Debug Test Video Processor
/// Uses Apple's VNDetectTrajectoriesRequest - the REAL way to detect golf balls!
///
/// KEY INSIGHT: VNDetectTrajectoriesRequest automatically:
/// - Tracks objects following PARABOLIC paths
/// - Predicts the full trajectory arc
/// - Works without knowing ball position beforehand!
///
/// This is what SmoothSwing uses!

#if DEBUG

protocol TestVideoProcessorDelegate: AnyObject {
    func testProcessor(_ processor: TestVideoProcessor, didStartProcessing asset: AVAsset)
    func testProcessor(_ processor: TestVideoProcessor, didProcessFrame frameNumber: Int, total: Int)
    func testProcessor(_ processor: TestVideoProcessor, didDetectBall at: CGPoint, confidence: Float)
    func testProcessor(_ processor: TestVideoProcessor, didUpdateTrajectory trajectory: Trajectory)
    func testProcessor(_ processor: TestVideoProcessor, didFinishWithTrajectory trajectory: Trajectory?, videoURL: URL)
    func testProcessor(_ processor: TestVideoProcessor, didFail error: Error)
}

final class TestVideoProcessor {
    
    weak var delegate: TestVideoProcessorDelegate?
    
    /// Vision request handler
    private var requestHandler: VNSequenceRequestHandler!
    
    /// Vision trajectory request
    private var trajectoryRequest: VNDetectTrajectoriesRequest!
    
    /// Trajectory store
    private let trajectoryStore = TrajectoryStore()
    
    /// Processing state
    private var isProcessing = false
    private var shouldCancel = false
    
    /// Region of interest (where to look for ball)
    private var regionOfInterest: CGRect?
    
    /// Debug logging
    var debugLogging = true
    
    /// Detection counts
    private var frameCount = 0
    private var detectionCount = 0
    
    // MARK: - Initialization
    
    init() {
        requestHandler = VNSequenceRequestHandler()
    }
    
    // MARK: - Public API
    
    /// Process a video using Vision's trajectory detection
    func processVideo(_ asset: AVAsset, initialBallPosition: CGPoint) {
        guard !isProcessing else {
            print("⚠️ Already processing a video")
            return
        }
        
        isProcessing = true
        shouldCancel = false
        frameCount = 0
        detectionCount = 0
        trajectoryStore.reset()
        
        // Set region of interest based on ball position
        // Focus on upper part of frame where ball will fly
        regionOfInterest = CGRect(
            x: 0.0,
            y: 0.0,  // Vision: Y=0 is BOTTOM
            width: 1.0,
            height: 0.95  // Full height minus bottom where golfer stands
        )
        
        // Create trajectory request
        trajectoryRequest = createTrajectoryRequest()
        
        print("═══════════════════════════════════════")
        print("🎯 VISION TRAJECTORY DETECTION STARTED")
        print("═══════════════════════════════════════")
        print("   Using: VNDetectTrajectoriesRequest")
        print("   Ball hint: (\(String(format: "%.3f", initialBallPosition.x)), \(String(format: "%.3f", initialBallPosition.y)))")
        print("   ROI: \(regionOfInterest!)")
        
        delegate?.testProcessor(self, didStartProcessing: asset)
        
        // Process on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.processAssetSync(asset: asset, ballHint: initialBallPosition)
        }
    }
    
    /// Cancel processing
    func cancel() {
        shouldCancel = true
    }
    
    // MARK: - Vision Request
    
    private func createTrajectoryRequest() -> VNDetectTrajectoriesRequest {
        // ═══════════════════════════════════════════════════════════════
        // THIS IS THE KEY: Apple's Vision framework trajectory detection
        // ═══════════════════════════════════════════════════════════════
        
        let request = VNDetectTrajectoriesRequest(
            frameAnalysisSpacing: .zero,  // Analyze every frame
            trajectoryLength: 5  // Need 5 frames to establish trajectory (lower = faster detection)
        ) { [weak self] req, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Vision error: \(error.localizedDescription)")
                return
            }
            
            self.handleTrajectoryResults(req)
        }
        
        // Set region of interest
        if let roi = regionOfInterest {
            request.regionOfInterest = roi
        }
        
        // DON'T constrain size - let Vision detect anything parabolic
        // This is how Mizuno's code works!
        
        // For iOS 15+, set target frame time
        if #available(iOS 15.0, *) {
            request.targetFrameTime = CMTime(value: 1, timescale: 60)
        }
        
        return request
    }
    
    private func handleTrajectoryResults(_ request: VNRequest) {
        guard let observations = request.results as? [VNTrajectoryObservation],
              !observations.isEmpty else {
            return
        }
        
        for observation in observations {
            detectionCount += 1
            
            // Update trajectory store
            trajectoryStore.update(with: observation)
            
            if debugLogging {
                print("🎾 TRAJECTORY DETECTED! (#\(detectionCount))")
                print("   Confidence: \(String(format: "%.2f", observation.confidence))")
                print("   Detected points: \(observation.detectedPoints.count)")
                print("   Projected points: \(observation.projectedPoints.count)")
                
                // Log first and last projected points
                if let first = observation.projectedPoints.first,
                   let last = observation.projectedPoints.last {
                    print("   Arc: (\(String(format: "%.2f", first.x)), \(String(format: "%.2f", first.y))) → (\(String(format: "%.2f", last.x)), \(String(format: "%.2f", last.y)))")
                }
            }
            
            // Report to delegate
            if let trajectory = trajectoryStore.getTrajectoryForRendering() {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.testProcessor(self, didUpdateTrajectory: trajectory)
                }
            }
            
            // Report ball position
            if let lastPoint = observation.detectedPoints.last {
                let pos = CGPoint(x: CGFloat(lastPoint.x), y: CGFloat(lastPoint.y))
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.testProcessor(self, didDetectBall: pos, confidence: observation.confidence)
                }
            }
        }
    }
    
    // MARK: - Processing
    
    private func processAssetSync(asset: AVAsset, ballHint: CGPoint) {
        guard let track = asset.tracks(withMediaType: .video).first else {
            finishWithError(TestError.noVideoTrack)
            return
        }
        
        let duration = asset.duration
        let nominalFrameRate = track.nominalFrameRate
        let transform = track.preferredTransform
        let orientation = orientationFromTransform(transform)
        
        print("📹 Video Properties:")
        print("   Duration: \(String(format: "%.2f", duration.seconds))s")
        print("   Frame rate: \(Int(nominalFrameRate)) fps")
        print("   Orientation: \(orientation.rawValue)")
        
        do {
            let reader = try AVAssetReader(asset: asset)
            let outputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            trackOutput.alwaysCopiesSampleData = false
            
            guard reader.canAdd(trackOutput) else {
                finishWithError(TestError.cannotAddOutput)
                return
            }
            
            reader.add(trackOutput)
            reader.startReading()
            
            let totalFrames = Int(duration.seconds * Double(nominalFrameRate))
            
            print("🎬 Processing \(totalFrames) frames with Vision...")
            
            // Reset request handler for new sequence
            requestHandler = VNSequenceRequestHandler()
            trajectoryRequest = createTrajectoryRequest()
            
            while reader.status == .reading && !shouldCancel {
                autoreleasepool {
                    guard let sampleBuffer = trackOutput.copyNextSampleBuffer(),
                          let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        return
                    }
                    
                    frameCount += 1
                    
                    // Tick trajectory store
                    trajectoryStore.tick()
                    
                    // Process with Vision
                    do {
                        try requestHandler.perform([trajectoryRequest], on: pixelBuffer, orientation: orientation)
                    } catch {
                        if debugLogging && frameCount % 100 == 0 {
                            print("⚠️ Vision error at frame \(frameCount): \(error.localizedDescription)")
                        }
                    }
                    
                    // Report progress every 30 frames
                    if frameCount % 30 == 0 {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.delegate?.testProcessor(self, didProcessFrame: self.frameCount, total: totalFrames)
                        }
                        
                        if debugLogging {
                            let progress = Double(frameCount) / Double(totalFrames) * 100
                            print("   Progress: \(String(format: "%.0f", progress))% (\(frameCount)/\(totalFrames)) - Detections: \(detectionCount)")
                        }
                    }
                }
            }
            
            // Get final trajectory
            let finalTrajectory = trajectoryStore.getTrajectoryForRendering()
            
            print("═══════════════════════════════════════")
            print("✅ VISION PROCESSING COMPLETE")
            print("   Frames processed: \(frameCount)")
            print("   Trajectory detections: \(detectionCount)")
            if let traj = finalTrajectory {
                print("   Final trajectory: \(traj.detectedPoints.count) detected, \(traj.projectedPoints.count) projected")
            } else {
                print("   ⚠️ No trajectory detected")
                print("")
                print("   TIPS:")
                print("   • Need a video with object moving in PARABOLIC arc")
                print("   • Golf ball, thrown ball, or similar")
                print("   • Object should be visible for at least 5 frames")
            }
            print("═══════════════════════════════════════")
            
            // Export if we got a trajectory
            if let trajectory = finalTrajectory {
                exportWithTrajectory(asset: asset, trajectory: trajectory)
            } else {
                finishWithTrajectory(nil, videoURL: nil)
            }
            
        } catch {
            finishWithError(error)
        }
    }
    
    private func exportWithTrajectory(asset: AVAsset, trajectory: Trajectory) {
        print("🎬 Exporting video with trajectory overlay...")
        
        if let urlAsset = asset as? AVURLAsset {
            let exporter = ShotExporter()
            exporter.export(
                videoURL: urlAsset.url,
                trajectory: trajectory,
                tracerColor: ShotTracerDesign.Colors.tracerGold
            ) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let exportedURL):
                    print("✅ Export success: \(exportedURL)")
                    self.finishWithTrajectory(trajectory, videoURL: exportedURL)
                case .failure(let error):
                    print("❌ Export failed: \(error)")
                    self.finishWithTrajectory(trajectory, videoURL: nil)
                }
            }
        } else {
            finishWithTrajectory(trajectory, videoURL: nil)
        }
    }
    
    // MARK: - Helpers
    
    private func orientationFromTransform(_ transform: CGAffineTransform) -> CGImagePropertyOrientation {
        if transform.a == 0 && transform.b == 1 && transform.c == -1 && transform.d == 0 {
            return .right  // 90° CW (portrait video)
        } else if transform.a == 0 && transform.b == -1 && transform.c == 1 && transform.d == 0 {
            return .left   // 90° CCW
        } else if transform.a == -1 && transform.b == 0 && transform.c == 0 && transform.d == -1 {
            return .down   // 180°
        }
        return .up  // Landscape
    }
    
    private func finishWithError(_ error: Error) {
        isProcessing = false
        print("❌ Test processing error: \(error)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.testProcessor(self, didFail: error)
        }
    }
    
    private func finishWithTrajectory(_ trajectory: Trajectory?, videoURL: URL?) {
        isProcessing = false
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.testProcessor(self, didFinishWithTrajectory: trajectory, videoURL: videoURL ?? URL(fileURLWithPath: ""))
        }
    }
    
    // MARK: - Errors
    
    enum TestError: LocalizedError {
        case noVideoTrack
        case cannotAddOutput
        case processingFailed
        
        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "Video has no video track"
            case .cannotAddOutput: return "Cannot read video frames"
            case .processingFailed: return "Processing failed"
            }
        }
    }
}

// MARK: - Photo Library Helper

extension TestVideoProcessor {
    
    /// Request photo library access and get first video
    static func loadFirstVideoFromLibrary(completion: @escaping (AVAsset?) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            guard status == .authorized || status == .limited else {
                print("❌ Photo library access denied")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 1
            
            let videos = PHAsset.fetchAssets(with: .video, options: fetchOptions)
            
            guard let firstVideo = videos.firstObject else {
                print("⚠️ No videos found in library")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            print("📹 Found video: \(firstVideo.localIdentifier)")
            
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestAVAsset(forVideo: firstVideo, options: options) { asset, _, _ in
                DispatchQueue.main.async {
                    completion(asset)
                }
            }
        }
    }
}

#endif


