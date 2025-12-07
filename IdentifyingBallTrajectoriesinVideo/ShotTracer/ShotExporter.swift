import AVFoundation
import UIKit

enum ShotExportError: Error, LocalizedError {
    case missingAsset
    case exportFailed
    case noTrajectoryDetected
    case simulatorLimitation
    
    var errorDescription: String? {
        switch self {
        case .missingAsset:
            return "Could not read the video file"
        case .exportFailed:
            return "Video export failed. Please try again."
        case .noTrajectoryDetected:
            return "Could not detect the golf ball trajectory.\n\nTips:\n• Use a WHITE golf ball\n• Film against a clear sky\n• Keep the camera steady\n• Ensure good lighting"
        case .simulatorLimitation:
            return "Shot tracer requires a real iPhone.\n\nThe iOS Simulator cannot render the tracer overlay. Please test on a physical device."
        }
    }
}

final class ShotExporter {
    
    var tracerStyle: TracerStyle = .neon
    var glowIntensity: CGFloat = 1.0
    
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    func export(videoURL: URL, trajectory: Trajectory?, tracerColor: UIColor, completion: @escaping (Result<URL, Error>) -> Void) {
        
        print("═══════════════════════════════════════")
        print("🎬 EXPORT STARTING")
        print("═══════════════════════════════════════")
        print("   Video: \(videoURL.lastPathComponent)")
        
        if let traj = trajectory {
            print("   Trajectory: ✅ \(traj.points.count) points")
            for (i, point) in traj.points.prefix(5).enumerated() {
                print("     Point \(i): (\(String(format: "%.3f", point.normalized.x)), \(String(format: "%.3f", point.normalized.y)))")
            }
            if traj.points.count > 5 {
                print("     ... and \(traj.points.count - 5) more")
            }
        } else {
            print("   Trajectory: ❌ NONE - No tracer will be added!")
        }
        print("   Color: \(tracerColor)")
        
        #if targetEnvironment(simulator)
        print("⚠️ SIMULATOR: Tracer overlay not supported")
        handleSimulatorExport(videoURL: videoURL, trajectory: trajectory, completion: completion)
        return
        #endif
        
        // Real device export with tracer overlay
        performRealDeviceExport(videoURL: videoURL, trajectory: trajectory, tracerColor: tracerColor, completion: completion)
    }
    
    // MARK: - Simulator Export (simplified, no Core Animation)
    private func handleSimulatorExport(videoURL: URL, trajectory: Trajectory?, completion: @escaping (Result<URL, Error>) -> Void) {
        // On simulator, we'll just copy the original video since Core Animation export doesn't work
        // This still allows testing the rest of the app flow
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("traced_sim_\(UUID().uuidString).mp4")
        
        do {
            // Remove existing file if any
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            
            try FileManager.default.copyItem(at: videoURL, to: outputURL)
            
            DispatchQueue.main.async {
                completion(.success(outputURL))
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Real Device Export (with Core Animation tracer)
    private func performRealDeviceExport(videoURL: URL, trajectory: Trajectory?, tracerColor: UIColor, completion: @escaping (Result<URL, Error>) -> Void) {
        let asset = AVAsset(url: videoURL)
        
        // Load tracks on background thread to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            guard let videoTrack = asset.tracks(withMediaType: .video).first else {
                DispatchQueue.main.async {
                    completion(.failure(ShotExportError.missingAsset))
                }
                return
            }
            
            self.performExport(asset: asset, videoTrack: videoTrack, trajectory: trajectory, tracerColor: tracerColor, completion: completion)
        }
    }
    
    private func performExport(asset: AVAsset, videoTrack: AVAssetTrack, trajectory: Trajectory?, tracerColor: UIColor, completion: @escaping (Result<URL, Error>) -> Void) {
        
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async {
                completion(.failure(ShotExportError.missingAsset))
            }
            return
        }
        
        do {
            try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
            
            // Apply the video track's preferred transform
            compositionVideoTrack.preferredTransform = videoTrack.preferredTransform
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }
        
        // Add audio track if available
        if let sourceAudio = asset.tracks(withMediaType: .audio).first,
           let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audioCompositionTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: sourceAudio, at: .zero)
        }
        
        // Calculate render size accounting for transform
        let naturalSize = videoTrack.naturalSize
        let transform = videoTrack.preferredTransform
        let isPortrait = transform.a == 0 && abs(transform.b) == 1
        let renderSize = isPortrait ? CGSize(width: naturalSize.height, height: naturalSize.width) : naturalSize
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        let fps = videoTrack.nominalFrameRate
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(fps, 30)))
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        
        // Apply transform to correct orientation
        if isPortrait {
            var correctedTransform = transform
            if transform.b == 1 {
                // 90 degrees clockwise (right)
                correctedTransform = CGAffineTransform(translationX: naturalSize.height, y: 0).rotated(by: .pi / 2)
            } else if transform.b == -1 {
                // 90 degrees counter-clockwise (left)
                correctedTransform = CGAffineTransform(translationX: 0, y: naturalSize.width).rotated(by: -.pi / 2)
            }
            layerInstruction.setTransform(correctedTransform, at: .zero)
        }
        
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        // Add overlay if we have a trajectory
        if let trajectory = trajectory, !trajectory.points.isEmpty {
            print("🎯 Adding tracer overlay to export...")
            print("   Render size: \(renderSize)")
            
            let overlayLayers = makeOverlayLayers(size: renderSize, trajectory: trajectory, color: tracerColor)
            let parentLayer = overlayLayers.parent
            let videoLayer = overlayLayers.video
            
            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
            print("   ✅ Animation tool configured")
        } else {
            print("⚠️ No trajectory provided - exporting without tracer")
        }
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            DispatchQueue.main.async {
                completion(.failure(ShotExportError.exportFailed))
            }
            return
        }
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("traced_\(UUID().uuidString).mp4")
        
        // Clean up any existing file
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    completion(.success(outputURL))
                case .failed:
                    let error = exportSession.error ?? ShotExportError.exportFailed
                    print("Export failed: \(error.localizedDescription)")
                    completion(.failure(error))
                case .cancelled:
                    completion(.failure(ShotExportError.exportFailed))
                default:
                    break
                }
            }
        }
    }

    private func makeOverlayLayers(size: CGSize, trajectory: Trajectory?, color: UIColor) -> (parent: CALayer, video: CALayer) {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: size)
        parentLayer.isGeometryFlipped = true // Important for video coordinate system

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        let overlayLayer = CALayer()
        overlayLayer.frame = parentLayer.bounds
        
        // Outer glow layer for premium effect
        let outerGlowLayer = CAShapeLayer()
        outerGlowLayer.frame = overlayLayer.bounds
        outerGlowLayer.strokeColor = color.withAlphaComponent(0.15 * glowIntensity).cgColor
        outerGlowLayer.lineWidth = 24
        outerGlowLayer.lineCap = .round
        outerGlowLayer.lineJoin = .round
        outerGlowLayer.fillColor = UIColor.clear.cgColor
        
        // Inner glow layer
        let innerGlowLayer = CAShapeLayer()
        innerGlowLayer.frame = overlayLayer.bounds
        innerGlowLayer.strokeColor = color.withAlphaComponent(0.3 * glowIntensity).cgColor
        innerGlowLayer.lineWidth = 14
        innerGlowLayer.lineCap = .round
        innerGlowLayer.lineJoin = .round
        innerGlowLayer.fillColor = UIColor.clear.cgColor

        let shadowLayer = CAShapeLayer()
        shadowLayer.frame = overlayLayer.bounds
        shadowLayer.strokeColor = UIColor.black.withAlphaComponent(0.55).cgColor
        shadowLayer.lineWidth = 8
        shadowLayer.lineCap = .round
        shadowLayer.fillColor = UIColor.clear.cgColor

        let tracerLayer = CAShapeLayer()
        tracerLayer.frame = overlayLayer.bounds
        tracerLayer.strokeColor = color.cgColor
        tracerLayer.lineWidth = 6
        tracerLayer.lineCap = .round
        tracerLayer.lineJoin = .round
        tracerLayer.fillColor = UIColor.clear.cgColor
        
        // Highlight layer for depth
        let highlightLayer = CAShapeLayer()
        highlightLayer.frame = overlayLayer.bounds
        highlightLayer.strokeColor = UIColor.white.withAlphaComponent(0.5).cgColor
        highlightLayer.lineWidth = 2
        highlightLayer.lineCap = .round
        highlightLayer.lineJoin = .round
        highlightLayer.fillColor = UIColor.clear.cgColor
        
        // Ball indicator at end
        let ballLayer = CAShapeLayer()
        ballLayer.frame = overlayLayer.bounds
        ballLayer.fillColor = UIColor.white.cgColor
        
        let ballGlowLayer = CAShapeLayer()
        ballGlowLayer.frame = overlayLayer.bounds
        ballGlowLayer.fillColor = color.withAlphaComponent(0.4).cgColor

        if let trajectory = trajectory, !trajectory.points.isEmpty {
            // Create smooth path using Catmull-Rom spline
            let viewPoints = trajectory.points.map { point -> CGPoint in
                CGPoint(x: point.normalized.x * size.width, y: point.normalized.y * size.height)
            }
            
            let path = createSmoothPath(from: viewPoints)
            let shadowPath = UIBezierPath(cgPath: path.cgPath)
            shadowPath.apply(CGAffineTransform(translationX: 2, y: 2))

            outerGlowLayer.path = path.cgPath
            innerGlowLayer.path = path.cgPath
            tracerLayer.path = path.cgPath
            shadowLayer.path = shadowPath.cgPath
            highlightLayer.path = path.cgPath
            
            // Ball at end of trajectory
            if let lastPoint = viewPoints.last {
                ballLayer.path = UIBezierPath(
                    arcCenter: lastPoint,
                    radius: 8,
                    startAngle: 0,
                    endAngle: .pi * 2,
                    clockwise: true
                ).cgPath
                
                ballGlowLayer.path = UIBezierPath(
                    arcCenter: lastPoint,
                    radius: 16,
                    startAngle: 0,
                    endAngle: .pi * 2,
                    clockwise: true
                ).cgPath
            }

            let duration = (trajectory.points.last!.time - trajectory.points.first!.time).seconds
            if duration > 0.01 {
                let anim = CABasicAnimation(keyPath: "strokeEnd")
                anim.fromValue = 0
                anim.toValue = 1
                anim.duration = duration
                anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                anim.beginTime = AVCoreAnimationBeginTimeAtZero
                anim.isRemovedOnCompletion = false
                anim.fillMode = .forwards
                
                outerGlowLayer.add(anim, forKey: "stroke")
                innerGlowLayer.add(anim, forKey: "stroke")
                tracerLayer.add(anim, forKey: "stroke")
                shadowLayer.add(anim, forKey: "stroke")
                highlightLayer.add(anim, forKey: "stroke")
                
                // Ball fade in at end
                let ballDelay = duration * 0.8
                let ballFade = CABasicAnimation(keyPath: "opacity")
                ballFade.fromValue = 0
                ballFade.toValue = 1
                ballFade.duration = 0.3
                ballFade.beginTime = AVCoreAnimationBeginTimeAtZero + ballDelay
                ballFade.isRemovedOnCompletion = false
                ballFade.fillMode = .forwards
                
                ballLayer.opacity = 0
                ballGlowLayer.opacity = 0
                ballLayer.add(ballFade, forKey: "fadeIn")
                ballGlowLayer.add(ballFade, forKey: "fadeIn")
            }
        }

        // Add layers in correct order (back to front)
        overlayLayer.addSublayer(outerGlowLayer)
        overlayLayer.addSublayer(innerGlowLayer)
        overlayLayer.addSublayer(shadowLayer)
        overlayLayer.addSublayer(tracerLayer)
        overlayLayer.addSublayer(highlightLayer)
        overlayLayer.addSublayer(ballGlowLayer)
        overlayLayer.addSublayer(ballLayer)
        parentLayer.addSublayer(overlayLayer)

        return (parentLayer, videoLayer)
    }
    
    private func createSmoothPath(from points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        
        guard points.count > 1 else {
            if let first = points.first {
                path.move(to: first)
                path.addLine(to: first)
            }
            return path
        }
        
        path.move(to: points[0])
        
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        
        // Use Catmull-Rom spline for smooth curves
        for i in 1..<points.count {
            let p0 = i == 1 ? points[0] : points[i - 2]
            let p1 = points[i - 1]
            let p2 = points[i]
            let p3 = i == points.count - 1 ? points[i] : points[i + 1]
            
            let tension: CGFloat = 0.5
            
            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6 * tension,
                y: p1.y + (p2.y - p0.y) / 6 * tension
            )
            
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6 * tension,
                y: p2.y - (p3.y - p1.y) / 6 * tension
            )
            
            path.addCurve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
        }
        
        return path
    }
}
