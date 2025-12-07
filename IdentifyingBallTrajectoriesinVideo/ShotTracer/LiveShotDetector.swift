import AVFoundation
import Vision
import CoreImage
import UIKit

/// Live Shot Detector - Detects golf swings and impacts using pose detection
/// Uses: Person segmentation + Pose detection + Velocity-based impact detection
@available(iOS 15.0, *)
final class LiveShotDetector {
    
    // MARK: - Types
    
    enum SwingPhase: String {
        case idle = "Idle"
        case setup = "Setup"
        case backswing = "Backswing"
        case topOfSwing = "Top"
        case downswing = "Downswing"
        case impact = "Impact"
        case followThru = "Follow Through"
        case finished = "Finished"
    }
    
    struct DetectionResult {
        let personMask: CIImage?
        let swingPhase: SwingPhase
        let isLocked: Bool
    }
    
    // MARK: - Callbacks
    
    var onSwingPhaseChanged: ((SwingPhase) -> Void)?
    var onLockStatusChanged: ((Bool) -> Void)?
    var onImpactDetected: (() -> Void)?
    
    // MARK: - Properties
    
    private let sequenceHandler = VNSequenceRequestHandler()
    
    /// Debug logging
    var debugLogging = true
    
    // Person segmentation
    private lazy var segmentationRequest: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()
    
    // Body pose detection
    private lazy var poseRequest: VNDetectHumanBodyPoseRequest = {
        return VNDetectHumanBodyPoseRequest()
    }()
    
    // MARK: - State
    
    private var isLocked = false
    private var lockedBallPosition: CGPoint?
    private var currentPhase: SwingPhase = .idle
    private(set) var impactDetected = false
    
    // MARK: - Swing Detection State
    
    /// Wrist position history for velocity calculation
    private var wristYHistory: [Double] = []
    private var wristVelocityHistory: [Double] = []
    private let historySize = 15
    
    /// Track peak velocities for impact detection
    private var peakDownwardVelocity: Double = 0
    private var framesSincePeakVelocity = 0
    
    /// Threshold for detecting swing phases
    private let backswingVelocityThreshold = 0.015    // Wrists moving up
    private let downswingVelocityThreshold = -0.02    // Wrists moving down fast
    private let impactVelocityThreshold = -0.04       // Very fast downward at impact
    
    // Timing
    private var impactTime: Date?
    private let postImpactDuration: TimeInterval = 4.0
    
    // MARK: - Public API
    
    /// Lock in the current position (called when alignment is confirmed)
    func lockPosition(ballPosition: CGPoint) {
        isLocked = true
        lockedBallPosition = ballPosition
        impactDetected = false
        
        // Reset swing detection
        wristYHistory.removeAll()
        wristVelocityHistory.removeAll()
        peakDownwardVelocity = 0
        framesSincePeakVelocity = 0
        currentPhase = .setup
        
        if debugLogging {
            print("🔒 LiveShotDetector: LOCKED at (\(String(format: "%.3f", ballPosition.x)), \(String(format: "%.3f", ballPosition.y)))")
        }
        
        onLockStatusChanged?(true)
    }
    
    /// Unlock and reset
    func unlock() {
        isLocked = false
        lockedBallPosition = nil
        impactDetected = false
        currentPhase = .idle
        
        wristYHistory.removeAll()
        wristVelocityHistory.removeAll()
        peakDownwardVelocity = 0
        impactTime = nil
        
        onLockStatusChanged?(false)
    }
    
    /// Check if shot tracking is complete
    func isTrackingComplete() -> Bool {
        if let impactT = impactTime {
            return Date().timeIntervalSince(impactT) > postImpactDuration
        }
        return false
    }
    
    /// Mark as finished
    func markFinished() {
        if currentPhase != .finished {
            currentPhase = .finished
            onSwingPhaseChanged?(.finished)
        }
    }
    
    /// Process a live camera frame
    func processFrame(_ pixelBuffer: CVPixelBuffer, time: CMTime, orientation: CGImagePropertyOrientation) -> DetectionResult {
        var personMask: CIImage?
        
        // 1. Person Segmentation (for silhouette overlay)
        do {
            try sequenceHandler.perform([segmentationRequest], on: pixelBuffer, orientation: orientation)
            if let maskBuffer = segmentationRequest.results?.first?.pixelBuffer {
                personMask = CIImage(cvPixelBuffer: maskBuffer)
            }
        } catch {
            // Non-fatal - continue without mask
        }
        
        // 2. Body Pose Detection (for swing phase detection)
        if isLocked && !impactDetected {
            do {
                try sequenceHandler.perform([poseRequest], on: pixelBuffer, orientation: orientation)
                if let pose = poseRequest.results?.first {
                    detectSwingPhase(from: pose)
                }
            } catch {
                // Non-fatal
            }
        }
        
        return DetectionResult(
            personMask: personMask,
            swingPhase: currentPhase,
            isLocked: isLocked
        )
    }
    
    // MARK: - Swing Phase Detection
    
    private func detectSwingPhase(from pose: VNHumanBodyPoseObservation) {
        // Get key points for swing detection
        guard let rightWrist = try? pose.recognizedPoint(.rightWrist),
              let leftWrist = try? pose.recognizedPoint(.leftWrist),
              rightWrist.confidence > 0.3 || leftWrist.confidence > 0.3 else {
            return
        }
        
        // Use the more confident wrist, or average if both are good
        let wristY: Double
        if rightWrist.confidence > 0.3 && leftWrist.confidence > 0.3 {
            wristY = (rightWrist.location.y + leftWrist.location.y) / 2
        } else if rightWrist.confidence > leftWrist.confidence {
            wristY = rightWrist.location.y
        } else {
            wristY = leftWrist.location.y
        }
        
        // Store position history
        wristYHistory.append(wristY)
        if wristYHistory.count > historySize {
            wristYHistory.removeFirst()
        }
        
        // Calculate velocity (change between frames)
        if wristYHistory.count >= 2 {
            let velocity = wristYHistory.last! - wristYHistory[wristYHistory.count - 2]
            wristVelocityHistory.append(velocity)
            if wristVelocityHistory.count > historySize {
                wristVelocityHistory.removeFirst()
            }
        }
        
        guard wristVelocityHistory.count >= 3 else { return }
        
        // Smooth velocity (moving average)
        let recentVelocities = Array(wristVelocityHistory.suffix(5))
        let avgVelocity = recentVelocities.reduce(0, +) / Double(recentVelocities.count)
        
        let oldPhase = currentPhase
        
        // State machine for swing phase detection
        switch currentPhase {
        case .idle, .setup:
            // Detect backswing start: wrists moving up
            if avgVelocity > backswingVelocityThreshold {
                currentPhase = .backswing
                if debugLogging {
                    print("⬆️ BACKSWING detected (velocity: \(String(format: "%.4f", avgVelocity)))")
                }
            }
            
        case .backswing:
            // Track peak (top of swing)
            if avgVelocity < 0.005 && avgVelocity > -0.01 {
                let wasGoingUp = wristVelocityHistory.dropLast(3).suffix(3).contains { $0 > 0.01 }
                if wasGoingUp {
                    currentPhase = .topOfSwing
                    if debugLogging {
                        print("🔝 TOP OF SWING detected")
                    }
                }
            }
            
            // Direct transition to downswing if velocity reverses sharply
            if avgVelocity < downswingVelocityThreshold {
                currentPhase = .downswing
                peakDownwardVelocity = avgVelocity
                framesSincePeakVelocity = 0
                if debugLogging {
                    print("⬇️ DOWNSWING detected (velocity: \(String(format: "%.4f", avgVelocity)))")
                }
            }
            
        case .topOfSwing:
            // Detect downswing start
            if avgVelocity < downswingVelocityThreshold {
                currentPhase = .downswing
                peakDownwardVelocity = avgVelocity
                framesSincePeakVelocity = 0
                if debugLogging {
                    print("⬇️ DOWNSWING detected (velocity: \(String(format: "%.4f", avgVelocity)))")
                }
            }
            
        case .downswing:
            framesSincePeakVelocity += 1
            
            // Track peak downward velocity
            if avgVelocity < peakDownwardVelocity {
                peakDownwardVelocity = avgVelocity
                framesSincePeakVelocity = 0
            }
            
            // Impact detection
            let isHighVelocity = peakDownwardVelocity < impactVelocityThreshold
            let isDecelerating = avgVelocity > peakDownwardVelocity + 0.01
            let pastPeak = framesSincePeakVelocity >= 2
            
            if isHighVelocity && isDecelerating && pastPeak {
                triggerImpact()
            }
            
            // Timeout
            if framesSincePeakVelocity > 30 {
                currentPhase = .setup
                peakDownwardVelocity = 0
                if debugLogging {
                    print("⚠️ Downswing timeout - resetting")
                }
            }
            
        case .impact:
            currentPhase = .followThru
            
        case .followThru, .finished:
            break
        }
        
        // Notify if phase changed
        if oldPhase != currentPhase {
            onSwingPhaseChanged?(currentPhase)
        }
    }
    
    private func triggerImpact() {
        guard !impactDetected else { return }
        
        currentPhase = .impact
        impactDetected = true
        impactTime = Date()
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        
        if debugLogging {
            print("💥 IMPACT DETECTED!")
            print("   Peak velocity was: \(String(format: "%.4f", peakDownwardVelocity))")
        }
        
        onImpactDetected?()
        onSwingPhaseChanged?(.impact)
    }
    
    // MARK: - Haptic Support
    
    func provideSwingFeedback(for phase: SwingPhase) {
        switch phase {
        case .backswing:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            
        case .impact:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
        case .finished:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
        default:
            break
        }
    }
}
