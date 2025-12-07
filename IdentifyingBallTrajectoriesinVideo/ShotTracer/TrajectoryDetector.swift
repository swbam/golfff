import AVFoundation
import Vision

protocol TrajectoryDetectorDelegate: AnyObject {
    func trajectoryDetector(_ detector: TrajectoryDetector, didUpdate trajectory: Trajectory)
    func trajectoryDetectorDidFinish(_ detector: TrajectoryDetector, finalTrajectory: Trajectory?)
}

final class TrajectoryDetector {
    weak var delegate: TrajectoryDetectorDelegate?

    var regionOfInterest: CGRect?
    var orientation: CGImagePropertyOrientation = .right
    var frameAnalysisSpacing: CMTime = .zero

    private var isRunning = false
    private var currentTrajectory: Trajectory?
    private var missingFrameCount = 0
    private let maxMissingFrames = 8
    private let requestHandler = VNSequenceRequestHandler()
    private var request: VNDetectTrajectoriesRequest!
    private let syncQueue = DispatchQueue(label: "com.shottracer.trajectory")

    init() {
        request = makeRequest()
    }

    func start() {
        syncQueue.async {
            self.missingFrameCount = 0
            self.currentTrajectory = nil
            self.isRunning = true
            self.request = self.makeRequest()
        }
    }

    func stop() {
        syncQueue.async {
            guard self.isRunning else { return }
            self.isRunning = false
            let final = self.currentTrajectory
            DispatchQueue.main.async {
                self.delegate?.trajectoryDetectorDidFinish(self, finalTrajectory: final)
            }
        }
    }

    func process(sampleBuffer: CMSampleBuffer) {
        syncQueue.async {
            guard self.isRunning else { return }

            if let roi = self.regionOfInterest {
                self.request.regionOfInterest = roi
            } else {
                self.request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
            }

            do {
                try self.requestHandler.perform([self.request], on: sampleBuffer, orientation: self.orientation)
            } catch {
                // Vision errors are non-fatal for the session; log and continue.
                print("TrajectoryDetector Vision error: \(error)")
            }
        }
    }

    func update(frameSpacingSeconds: Double) {
        frameAnalysisSpacing = CMTime(seconds: frameSpacingSeconds, preferredTimescale: 600)
        if isRunning {
            request = makeRequest()
        }
    }

    private func makeRequest() -> VNDetectTrajectoriesRequest {
        // Golf ball trajectory detection requires specific parameters:
        // - Golf balls are small (4.27cm diameter)
        // - They move fast (driver: 150+ mph, wedge: 80+ mph)
        // - trajectoryLength: minimum 5 points needed for parabolic detection
        let request = VNDetectTrajectoriesRequest(frameAnalysisSpacing: frameAnalysisSpacing, trajectoryLength: 5) { [weak self] req, error in
            guard let self else { return }
            if let error = error {
                print("Trajectory request error: \(error)")
                return
            }
            self.handle(request: req)
        }
        
        // Golf ball size parameters (normalized to frame size):
        // - At typical filming distance (5-15m), ball appears as 0.5-2% of frame
        // - Minimum: catches ball at further distances / smaller in frame
        // - Maximum: allows detection when ball is closer / larger
        request.objectMinimumNormalizedRadius = 0.004  // ~0.4% of frame (ball at 15m)
        request.objectMaximumNormalizedRadius = 0.08   // ~8% of frame (ball very close or with motion blur)
        
        if let roi = regionOfInterest {
            request.regionOfInterest = roi
        }
        return request
    }

    private func handle(request: VNRequest) {
        guard let observations = request.results as? [VNTrajectoryObservation] else {
            missingFrameCount += 1
            checkForCompletion()
            return
        }

        guard let best = observations.max(by: { $0.confidence < $1.confidence }) else {
            missingFrameCount += 1
            checkForCompletion()
            return
        }

        missingFrameCount = 0

        let normalizedPoints: [CGPoint] = best.detectedPoints.map { CGPoint(x: CGFloat($0.x), y: 1.0 - CGFloat($0.y)) }
        guard !normalizedPoints.isEmpty else { return }

        let durationSeconds = best.timeRange.duration.seconds
        let dt = durationSeconds / Double(max(normalizedPoints.count - 1, 1))
        var timeCursor = best.timeRange.start.seconds
        var points = [TrajectoryPoint]()
        for point in normalizedPoints {
            let time = CMTime(seconds: timeCursor, preferredTimescale: 600)
            points.append(TrajectoryPoint(time: time, normalized: point))
            timeCursor += dt
        }

        var trajectory = currentTrajectory ?? Trajectory(id: best.uuid, points: [], confidence: best.confidence)
        trajectory.points = points
        trajectory.confidence = max(trajectory.confidence, best.confidence)
        currentTrajectory = trajectory

        DispatchQueue.main.async {
            self.delegate?.trajectoryDetector(self, didUpdate: trajectory)
        }
    }

    private func checkForCompletion() {
        if missingFrameCount >= maxMissingFrames {
            isRunning = false
            let final = currentTrajectory
            DispatchQueue.main.async {
                self.delegate?.trajectoryDetectorDidFinish(self, finalTrajectory: final)
            }
        }
    }
}
