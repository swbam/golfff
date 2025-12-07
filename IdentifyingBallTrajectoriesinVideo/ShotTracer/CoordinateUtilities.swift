import Foundation
import AVFoundation
import CoreGraphics

/// Coordinate system utilities for golf ball tracking
/// Handles conversions between different coordinate systems:
/// - Vision Framework: Origin bottom-left, Y increases upward (0-1 normalized)
/// - UIKit: Origin top-left, Y increases downward (0-1 normalized)
/// - Video pixels: Origin top-left, actual pixel coordinates
/// - Camera preview: May have different aspect ratio, letterboxing

// MARK: - Coordinate Systems

enum CoordinateSystem {
    case vision         // Vision framework (bottom-left origin)
    case uikit          // UIKit (top-left origin)
    case videoPixels    // Raw video pixels
    case preview        // Camera preview view
}

// MARK: - Coordinate Converter

final class CoordinateConverter {
    
    // MARK: - Properties
    
    /// Video natural size
    var videoSize: CGSize = CGSize(width: 1920, height: 1080)
    
    /// Preview view size (may include letterboxing)
    var previewSize: CGSize = .zero
    
    /// Video orientation
    var orientation: CGImagePropertyOrientation = .up
    
    /// Preview video gravity
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    
    // MARK: - Vision <-> UIKit Conversions
    
    /// Convert Vision coordinates to UIKit coordinates
    /// Vision: origin bottom-left, Y up
    /// UIKit: origin top-left, Y down
    static func visionToUIKit(_ point: CGPoint) -> CGPoint {
        return CGPoint(x: point.x, y: 1.0 - point.y)
    }
    
    /// Convert UIKit coordinates to Vision coordinates
    static func uiKitToVision(_ point: CGPoint) -> CGPoint {
        return CGPoint(x: point.x, y: 1.0 - point.y)
    }
    
    /// Convert Vision rect to UIKit rect
    static func visionToUIKit(_ rect: CGRect) -> CGRect {
        return CGRect(
            x: rect.minX,
            y: 1.0 - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
    
    /// Convert UIKit rect to Vision rect
    static func uiKitToVision(_ rect: CGRect) -> CGRect {
        return CGRect(
            x: rect.minX,
            y: 1.0 - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
    
    // MARK: - Normalized <-> Pixel Conversions
    
    /// Convert normalized coordinates (0-1) to pixel coordinates
    func normalizedToPixels(_ point: CGPoint, size: CGSize) -> CGPoint {
        return CGPoint(
            x: point.x * size.width,
            y: point.y * size.height
        )
    }
    
    /// Convert pixel coordinates to normalized (0-1)
    func pixelsToNormalized(_ point: CGPoint, size: CGSize) -> CGPoint {
        guard size.width > 0 && size.height > 0 else { return .zero }
        return CGPoint(
            x: point.x / size.width,
            y: point.y / size.height
        )
    }
    
    // MARK: - Orientation Handling
    
    /// Apply video orientation transform to a normalized point
    /// Used when processing camera frames that have been rotated
    func applyOrientation(_ point: CGPoint, orientation: CGImagePropertyOrientation) -> CGPoint {
        switch orientation {
        case .right:  // 90° CW (common for portrait video from iPhone)
            // Rotate point 90° CW around center
            return CGPoint(x: point.y, y: 1.0 - point.x)
            
        case .left:   // 90° CCW
            return CGPoint(x: 1.0 - point.y, y: point.x)
            
        case .down:   // 180°
            return CGPoint(x: 1.0 - point.x, y: 1.0 - point.y)
            
        case .upMirrored:
            return CGPoint(x: 1.0 - point.x, y: point.y)
            
        case .downMirrored:
            return CGPoint(x: point.x, y: 1.0 - point.y)
            
        case .leftMirrored:
            return CGPoint(x: point.y, y: point.x)
            
        case .rightMirrored:
            return CGPoint(x: 1.0 - point.y, y: 1.0 - point.x)
            
        default:  // .up
            return point
        }
    }
    
    /// Remove video orientation transform from a point (inverse operation)
    func removeOrientation(_ point: CGPoint, orientation: CGImagePropertyOrientation) -> CGPoint {
        switch orientation {
        case .right:  // Inverse of 90° CW is 90° CCW
            return CGPoint(x: 1.0 - point.y, y: point.x)
            
        case .left:   // Inverse of 90° CCW is 90° CW
            return CGPoint(x: point.y, y: 1.0 - point.x)
            
        case .down:   // Inverse of 180° is 180°
            return CGPoint(x: 1.0 - point.x, y: 1.0 - point.y)
            
        case .upMirrored:
            return CGPoint(x: 1.0 - point.x, y: point.y)
            
        case .downMirrored:
            return CGPoint(x: point.x, y: 1.0 - point.y)
            
        case .leftMirrored:
            return CGPoint(x: point.y, y: point.x)
            
        case .rightMirrored:
            return CGPoint(x: 1.0 - point.y, y: 1.0 - point.x)
            
        default:
            return point
        }
    }
    
    /// Apply orientation to a rect
    func applyOrientation(_ rect: CGRect, orientation: CGImagePropertyOrientation) -> CGRect {
        let topLeft = applyOrientation(CGPoint(x: rect.minX, y: rect.minY), orientation: orientation)
        let bottomRight = applyOrientation(CGPoint(x: rect.maxX, y: rect.maxY), orientation: orientation)
        
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }
    
    // MARK: - Preview View Conversions
    
    /// Convert normalized video coordinates to preview view coordinates
    func normalizedToPreview(_ point: CGPoint) -> CGPoint {
        guard previewSize.width > 0 && previewSize.height > 0 else { return .zero }
        
        let videoRect = calculateVideoRect()
        
        return CGPoint(
            x: videoRect.minX + point.x * videoRect.width,
            y: videoRect.minY + point.y * videoRect.height
        )
    }
    
    /// Convert preview view coordinates to normalized video coordinates
    func previewToNormalized(_ point: CGPoint) -> CGPoint {
        let videoRect = calculateVideoRect()
        
        guard videoRect.width > 0 && videoRect.height > 0 else { return .zero }
        
        return CGPoint(
            x: (point.x - videoRect.minX) / videoRect.width,
            y: (point.y - videoRect.minY) / videoRect.height
        )
    }
    
    /// Calculate the video rect within the preview (accounting for aspect ratio)
    func calculateVideoRect() -> CGRect {
        guard previewSize.width > 0 && previewSize.height > 0,
              videoSize.width > 0 && videoSize.height > 0 else {
            return .zero
        }
        
        // Account for orientation
        let effectiveVideoSize: CGSize
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            effectiveVideoSize = CGSize(width: videoSize.height, height: videoSize.width)
        default:
            effectiveVideoSize = videoSize
        }
        
        let videoAspect = effectiveVideoSize.width / effectiveVideoSize.height
        let previewAspect = previewSize.width / previewSize.height
        
        switch videoGravity {
        case .resizeAspect:
            // Letterbox/pillarbox - video fits inside preview
            if videoAspect > previewAspect {
                let height = previewSize.width / videoAspect
                let y = (previewSize.height - height) / 2
                return CGRect(x: 0, y: y, width: previewSize.width, height: height)
            } else {
                let width = previewSize.height * videoAspect
                let x = (previewSize.width - width) / 2
                return CGRect(x: x, y: 0, width: width, height: previewSize.height)
            }
            
        case .resizeAspectFill:
            // Fill - video overflows preview, cropped
            if videoAspect > previewAspect {
                let width = previewSize.height * videoAspect
                let x = (previewSize.width - width) / 2
                return CGRect(x: x, y: 0, width: width, height: previewSize.height)
            } else {
                let height = previewSize.width / videoAspect
                let y = (previewSize.height - height) / 2
                return CGRect(x: 0, y: y, width: previewSize.width, height: height)
            }
            
        default:  // .resize
            // Stretch to fill
            return CGRect(origin: .zero, size: previewSize)
        }
    }
    
    // MARK: - Trajectory Conversion
    
    /// Convert entire trajectory from Vision to UIKit coordinates
    func convertTrajectoryToUIKit(_ trajectory: Trajectory) -> Trajectory {
        let convertedPoints = trajectory.points.map { point in
            TrajectoryPoint(
                time: point.time,
                normalized: CoordinateConverter.visionToUIKit(point.normalized)
            )
        }
        
        return Trajectory(
            id: trajectory.id,
            points: convertedPoints,
            confidence: trajectory.confidence
        )
    }
    
    /// Convert trajectory points for video export
    /// Takes normalized UIKit points and converts to video pixel coordinates
    func convertTrajectoryForExport(_ trajectory: Trajectory, videoSize: CGSize) -> [CGPoint] {
        return trajectory.points.map { point in
            normalizedToPixels(point.normalized, size: videoSize)
        }
    }
}

// MARK: - Video Transform Utilities

extension CoordinateConverter {
    
    /// Get orientation from video track transform
    static func orientationFromTransform(_ transform: CGAffineTransform) -> CGImagePropertyOrientation {
        // Analyze transform matrix to determine rotation
        let a = transform.a
        let b = transform.b
        let c = transform.c
        let d = transform.d
        
        if a == 0 && b == 1 && c == -1 && d == 0 {
            return .right   // 90° CW
        } else if a == 0 && b == -1 && c == 1 && d == 0 {
            return .left    // 90° CCW
        } else if a == -1 && b == 0 && c == 0 && d == -1 {
            return .down    // 180°
        } else if a == 1 && b == 0 && c == 0 && d == 1 {
            return .up      // No rotation
        }
        
        // Default
        return .up
    }
    
    /// Get effective video size after applying orientation
    static func effectiveSize(naturalSize: CGSize, orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            return CGSize(width: naturalSize.height, height: naturalSize.width)
        default:
            return naturalSize
        }
    }
}

// MARK: - CGPoint Extensions

extension CGPoint {
    
    /// Clamp point to valid normalized range (0-1)
    var clamped: CGPoint {
        CGPoint(
            x: max(0, min(1, x)),
            y: max(0, min(1, y))
        )
    }
    
    /// Distance to another point
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Lerp (linear interpolation) between two points
    func lerp(to other: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(
            x: x + (other.x - x) * t,
            y: y + (other.y - y) * t
        )
    }
}

// MARK: - CGRect Extensions

extension CGRect {
    
    /// Clamp rect to valid normalized range (0-1)
    var clamped: CGRect {
        CGRect(
            x: max(0, minX),
            y: max(0, minY),
            width: min(1 - max(0, minX), width),
            height: min(1 - max(0, minY), height)
        )
    }
    
    /// Expand rect by a factor (centered)
    func expanded(by factor: CGFloat) -> CGRect {
        let dw = width * (factor - 1) / 2
        let dh = height * (factor - 1) / 2
        return CGRect(
            x: minX - dw,
            y: minY - dh,
            width: width + dw * 2,
            height: height + dh * 2
        ).clamped
    }
}

// MARK: - Singleton Access

extension CoordinateConverter {
    
    /// Shared instance for common operations
    static let shared = CoordinateConverter()
}


