import AVFoundation
import Vision
import UIKit

/// GolferAlignmentDetector - Automatic golfer position detection with haptic feedback
///
/// This is how SmoothSwing achieves the "lock in" with vibration:
/// - Uses VNDetectHumanBodyPoseRequest to detect golfer's body position
/// - Checks if golfer is in proper address position (golf stance)
/// - Triggers haptic feedback when aligned
/// - No manual tap required - silhouette defines ball position
@available(iOS 14.0, *)
final class GolferAlignmentDetector {
    
    // MARK: - Types
    
    enum AlignmentState {
        case searching      // Looking for golfer
        case detected       // Golfer detected, checking position
        case aligning       // Golfer adjusting position
        case locked         // Golfer in correct position!
        case lost           // Lost tracking
    }
    
    struct AlignmentResult {
        let state: AlignmentState
        let confidence: Float
        let bodyBounds: CGRect?          // Normalized bounding box of body
        let ballPosition: CGPoint?        // Estimated ball position
        let isInGolfStance: Bool
        let alignmentScore: Float        // 0-1, how well aligned to template
    }
    
    // MARK: - Callbacks
    
    /// Called when alignment state changes
    var onAlignmentChanged: ((AlignmentResult) -> Void)?
    
    /// Called when golfer is locked in (ready to swing)
    var onLockedIn: ((AlignmentResult) -> Void)?
    
    /// Called when alignment is lost
    var onAlignmentLost: (() -> Void)?
    
    // MARK: - Properties
    
    private let sequenceHandler = VNSequenceRequestHandler()
    
    /// Body pose detection request
    private lazy var poseRequest: VNDetectHumanBodyPoseRequest = {
        return VNDetectHumanBodyPoseRequest()
    }()
    
    /// Human rectangles detection (for bounding box)
    private lazy var bodyRectRequest: VNDetectHumanRectanglesRequest = {
        let request = VNDetectHumanRectanglesRequest()
        // upperBodyOnly is iOS 15+ only
        if #available(iOS 15.0, *) {
            request.upperBodyOnly = false  // Full body
        }
        return request
    }()
    
    // State tracking
    private var currentState: AlignmentState = .searching
    private var stableFrameCount: Int = 0
    private var lastBodyBounds: CGRect?
    private var lastConfidence: Float = 0
    
    // Configuration
    private let stableFramesRequired: Int = 10  // Need 10 consecutive aligned frames
    private let alignmentThreshold: Float = 0.6  // 60% alignment score to lock
    private let movementThreshold: CGFloat = 0.05  // Max movement to be "stable"
    
    // Haptic generators
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let successGenerator = UINotificationFeedbackGenerator()
    
    // Debug
    var debugLogging: Bool = false
    
    // MARK: - Initialization
    
    init() {
        impactGenerator.prepare()
        successGenerator.prepare()
    }
    
    // MARK: - Public API
    
    /// Process a camera frame for alignment detection
    func processFrame(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .right) -> AlignmentResult {
        var bodyBounds: CGRect?
        var isInStance = false
        var alignmentScore: Float = 0
        var confidence: Float = 0
        
        // 1. Detect human body rectangle
        do {
            try sequenceHandler.perform([bodyRectRequest], on: pixelBuffer, orientation: orientation)
            if let observation = bodyRectRequest.results?.first {
                // Convert from Vision (bottom-left) to UIKit (top-left) coordinates
                bodyBounds = CGRect(
                    x: observation.boundingBox.minX,
                    y: 1.0 - observation.boundingBox.maxY,
                    width: observation.boundingBox.width,
                    height: observation.boundingBox.height
                )
                confidence = observation.confidence
            }
        } catch {
            if debugLogging {
                print("⚠️ Body rect detection error: \(error)")
            }
        }
        
        // 2. Detect body pose for stance validation
        do {
            try sequenceHandler.perform([poseRequest], on: pixelBuffer, orientation: orientation)
            if let pose = poseRequest.results?.first {
                let stanceResult = evaluateGolfStance(pose: pose)
                isInStance = stanceResult.isValid
                alignmentScore = stanceResult.score
            }
        } catch {
            if debugLogging {
                print("⚠️ Pose detection error: \(error)")
            }
        }
        
        // 3. Update state machine
        let newState = updateState(
            bodyDetected: bodyBounds != nil,
            isAligned: isInStance && alignmentScore > alignmentThreshold,
            currentBounds: bodyBounds
        )
        
        // 4. Calculate ball position (bottom center of body, slightly in front)
        let ballPosition = calculateBallPosition(bodyBounds: bodyBounds)
        
        let result = AlignmentResult(
            state: newState,
            confidence: confidence,
            bodyBounds: bodyBounds,
            ballPosition: ballPosition,
            isInGolfStance: isInStance,
            alignmentScore: alignmentScore
        )
        
        // 5. Trigger callbacks
        if newState != currentState {
            currentState = newState
            onAlignmentChanged?(result)
            
            if newState == .locked {
                onLockedIn?(result)
            } else if newState == .lost {
                onAlignmentLost?()
            }
        }
        
        return result
    }
    
    /// Reset detector state
    func reset() {
        currentState = .searching
        stableFrameCount = 0
        lastBodyBounds = nil
        lastConfidence = 0
    }
    
    // MARK: - Golf Stance Evaluation
    
    private struct StanceEvaluation {
        let isValid: Bool
        let score: Float
    }
    
    private func evaluateGolfStance(pose: VNHumanBodyPoseObservation) -> StanceEvaluation {
        var score: Float = 0
        var validChecks = 0
        var totalChecks = 0
        
        // Get key body points
        let points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint?] = [
            .leftAnkle: try? pose.recognizedPoint(.leftAnkle),
            .rightAnkle: try? pose.recognizedPoint(.rightAnkle),
            .leftHip: try? pose.recognizedPoint(.leftHip),
            .rightHip: try? pose.recognizedPoint(.rightHip),
            .leftShoulder: try? pose.recognizedPoint(.leftShoulder),
            .rightShoulder: try? pose.recognizedPoint(.rightShoulder),
            .leftWrist: try? pose.recognizedPoint(.leftWrist),
            .rightWrist: try? pose.recognizedPoint(.rightWrist),
            .neck: try? pose.recognizedPoint(.neck)
        ]
        
        // Check 1: Feet are roughly shoulder-width apart
        if let leftAnkle = points[.leftAnkle] as? VNRecognizedPoint,
           let rightAnkle = points[.rightAnkle] as? VNRecognizedPoint,
           leftAnkle.confidence > 0.3 && rightAnkle.confidence > 0.3 {
            
            let feetDistance = abs(leftAnkle.location.x - rightAnkle.location.x)
            // Good stance: feet 0.15-0.4 of frame width apart
            if feetDistance > 0.1 && feetDistance < 0.5 {
                validChecks += 1
                score += 0.2
            }
            totalChecks += 1
        }
        
        // Check 2: Both hands are close together (grip position)
        if let leftWrist = points[.leftWrist] as? VNRecognizedPoint,
           let rightWrist = points[.rightWrist] as? VNRecognizedPoint,
           leftWrist.confidence > 0.3 && rightWrist.confidence > 0.3 {
            
            let wristDistance = sqrt(
                pow(leftWrist.location.x - rightWrist.location.x, 2) +
                pow(leftWrist.location.y - rightWrist.location.y, 2)
            )
            // Good grip: hands within 0.15 of each other
            if wristDistance < 0.2 {
                validChecks += 1
                score += 0.25
            }
            totalChecks += 1
        }
        
        // Check 3: Body is slightly bent forward (not standing straight up)
        if let neck = points[.neck] as? VNRecognizedPoint,
           let leftHip = points[.leftHip] as? VNRecognizedPoint,
           let rightHip = points[.rightHip] as? VNRecognizedPoint,
           neck.confidence > 0.3 {
            
            let hipX = (leftHip.location.x + rightHip.location.x) / 2
            _ = (leftHip.location.y + rightHip.location.y) / 2  // hipY for potential future use
            
            // Check for forward lean: neck should be slightly forward of hips
            // In Vision coords, Y increases upward
            let forwardLean = neck.location.x - hipX
            
            // Slight forward lean expected in address position
            if forwardLean > -0.1 && forwardLean < 0.15 {
                validChecks += 1
                score += 0.2
            }
            totalChecks += 1
        }
        
        // Check 4: Shoulders relatively level (not tilted too much)
        if let leftShoulder = points[.leftShoulder] as? VNRecognizedPoint,
           let rightShoulder = points[.rightShoulder] as? VNRecognizedPoint,
           leftShoulder.confidence > 0.3 && rightShoulder.confidence > 0.3 {
            
            let shoulderTilt = abs(leftShoulder.location.y - rightShoulder.location.y)
            // Allow some tilt but not too much
            if shoulderTilt < 0.1 {
                validChecks += 1
                score += 0.15
            }
            totalChecks += 1
        }
        
        // Check 5: Body is in frame (not cut off)
        if let leftAnkle = points[.leftAnkle] as? VNRecognizedPoint,
           let rightAnkle = points[.rightAnkle] as? VNRecognizedPoint,
           let neck = points[.neck] as? VNRecognizedPoint {
            
            let inFrame = leftAnkle.location.x > 0.05 &&
                          rightAnkle.location.x < 0.95 &&
                          neck.location.y < 0.95 &&
                          leftAnkle.location.y > 0.05
            
            if inFrame {
                validChecks += 1
                score += 0.2
            }
            totalChecks += 1
        }
        
        // Normalize score
        let finalScore = totalChecks > 0 ? score : 0
        let isValid = validChecks >= 3 && finalScore > 0.5
        
        return StanceEvaluation(isValid: isValid, score: finalScore)
    }
    
    // MARK: - State Machine
    
    private func updateState(bodyDetected: Bool, isAligned: Bool, currentBounds: CGRect?) -> AlignmentState {
        // Check for movement stability
        let isStable: Bool
        if let current = currentBounds, let last = lastBodyBounds {
            let movement = abs(current.midX - last.midX) + abs(current.midY - last.midY)
            isStable = movement < movementThreshold
        } else {
            isStable = false
        }
        
        lastBodyBounds = currentBounds
        
        switch currentState {
        case .searching:
            if bodyDetected {
                return .detected
            }
            
        case .detected:
            if !bodyDetected {
                stableFrameCount = 0
                return .searching
            }
            if isAligned {
                return .aligning
            }
            
        case .aligning:
            if !bodyDetected {
                stableFrameCount = 0
                return .lost
            }
            
            if isAligned && isStable {
                stableFrameCount += 1
                
                // Provide progress haptic
                if stableFrameCount % 3 == 0 && stableFrameCount < stableFramesRequired {
                    impactGenerator.impactOccurred(intensity: CGFloat(stableFrameCount) / CGFloat(stableFramesRequired))
                }
                
                if stableFrameCount >= stableFramesRequired {
                    // LOCKED IN!
                    successGenerator.notificationOccurred(.success)
                    
                    if debugLogging {
                        print("🔒 GOLFER LOCKED IN!")
                    }
                    
                    return .locked
                }
            } else if !isAligned {
                stableFrameCount = max(0, stableFrameCount - 2)
                if stableFrameCount == 0 {
                    return .detected
                }
            }
            
        case .locked:
            // Stay locked until explicitly reset or golfer moves significantly
            if !bodyDetected || !isStable {
                return .lost
            }
            
        case .lost:
            stableFrameCount = 0
            if bodyDetected {
                return .detected
            } else {
                return .searching
            }
        }
        
        return currentState
    }
    
    // MARK: - Ball Position Calculation
    
    private func calculateBallPosition(bodyBounds: CGRect?) -> CGPoint? {
        guard let bounds = bodyBounds else { return nil }
        
        // Ball is typically at the bottom center of the stance, slightly forward
        // In UIKit coordinates (top-left origin)
        let ballX = bounds.midX
        let ballY = bounds.maxY - 0.02  // Slightly above bottom of body bounds
        
        return CGPoint(x: ballX, y: ballY)
    }
    
    // MARK: - Silhouette Matching
    
    /// Check how well the current pose matches a reference silhouette
    func matchesSilhouette(_ pose: VNHumanBodyPoseObservation, reference: GolferSilhouetteView.StanceType) -> Float {
        // This could be expanded to compare against specific pose templates
        // For now, we use the golf stance evaluation as our matching metric
        let stance = evaluateGolfStance(pose: pose)
        return stance.score
    }
}

// MARK: - Convenience Extensions

@available(iOS 14.0, *)
extension GolferAlignmentDetector.AlignmentState {
    var displayName: String {
        switch self {
        case .searching: return "Looking for golfer..."
        case .detected: return "Golfer detected"
        case .aligning: return "Hold still..."
        case .locked: return "Locked in! ✓"
        case .lost: return "Position lost"
        }
    }
    
    var color: UIColor {
        switch self {
        case .searching: return .gray
        case .detected: return .systemYellow
        case .aligning: return .systemOrange
        case .locked: return .systemGreen
        case .lost: return .systemRed
        }
    }
}
