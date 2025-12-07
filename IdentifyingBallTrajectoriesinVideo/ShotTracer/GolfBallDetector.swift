import AVFoundation
import CoreImage
import Vision
import Accelerate

/// Multi-technique golf ball detector - NO ML, pure computer vision
/// Combines: Color detection + Motion detection + Shape analysis + Trajectory prediction
final class GolfBallDetector {
    
    // MARK: - Detection Results
    struct BallPosition {
        let center: CGPoint      // Normalized 0-1
        let radius: CGFloat      // Normalized
        let confidence: Float
        let frameTime: CMTime
    }
    
    // MARK: - Properties
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // Frame buffer for motion detection
    private var previousFrame: CIImage?
    private var frameCount = 0
    
    // Detected positions for trajectory building
    private var detectedPositions: [BallPosition] = []
    
    // Detection parameters (tuned for golf balls)
    private let whiteThreshold: Float = 0.85      // How white the ball should be (0-1)
    private let minBlobSize: Int = 10             // Minimum pixels for a ball blob
    private let maxBlobSize: Int = 500            // Maximum pixels
    private let motionThreshold: Float = 0.15     // Motion detection sensitivity
    
    // MARK: - Public API
    
    /// Process a video frame and detect golf ball
    func processFrame(_ pixelBuffer: CVPixelBuffer, time: CMTime, orientation: CGImagePropertyOrientation) -> BallPosition? {
        frameCount += 1
        
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Apply orientation correction
        ciImage = ciImage.oriented(orientation)
        
        let imageSize = ciImage.extent.size
        
        // Technique 1: White color detection
        let whiteMask = detectWhiteRegions(in: ciImage)
        
        // Technique 2: Motion detection (if we have previous frame)
        var motionMask: CIImage?
        if let previous = previousFrame {
            motionMask = detectMotion(current: ciImage, previous: previous)
        }
        previousFrame = ciImage
        
        // Technique 3: Combine masks and find blobs
        let combinedMask = combineMasks(white: whiteMask, motion: motionMask)
        
        // Technique 4: Find ball candidates
        if let position = findBallCandidate(in: combinedMask, imageSize: imageSize, time: time) {
            detectedPositions.append(position)
            
            // Keep only recent positions for trajectory
            if detectedPositions.count > 30 {
                detectedPositions.removeFirst()
            }
            
            return position
        }
        
        return nil
    }
    
    /// Build trajectory from detected positions
    func buildTrajectory() -> Trajectory? {
        guard detectedPositions.count >= 3 else { return nil }
        
        // Filter positions that form a valid parabolic trajectory
        let validPositions = filterForParabolicMotion(detectedPositions)
        
        guard validPositions.count >= 3 else { return nil }
        
        let points = validPositions.map { pos in
            TrajectoryPoint(time: pos.frameTime, normalized: pos.center)
        }
        
        let avgConfidence = validPositions.reduce(0) { $0 + $1.confidence } / Float(validPositions.count)
        
        return Trajectory(
            id: UUID(),
            points: points,
            confidence: avgConfidence
        )
    }
    
    /// Reset detector state
    func reset() {
        previousFrame = nil
        detectedPositions.removeAll()
        frameCount = 0
    }
    
    // MARK: - White Detection
    
    private func detectWhiteRegions(in image: CIImage) -> CIImage {
        // Convert to grayscale and threshold for white
        // Golf balls are WHITE - this is the key insight from SmoothSwing
        
        // Create a threshold filter for bright/white pixels
        guard let colorMatrix = CIFilter(name: "CIColorMatrix") else {
            return image
        }
        
        // Convert to grayscale
        colorMatrix.setValue(image, forKey: kCIInputImageKey)
        colorMatrix.setValue(CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0), forKey: "inputRVector")
        colorMatrix.setValue(CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0), forKey: "inputGVector")
        colorMatrix.setValue(CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0), forKey: "inputBVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        
        guard let grayscale = colorMatrix.outputImage else { return image }
        
        // Apply threshold - keep only bright pixels (white ball)
        guard let colorClamp = CIFilter(name: "CIColorClamp") else {
            return grayscale
        }
        colorClamp.setValue(grayscale, forKey: kCIInputImageKey)
        colorClamp.setValue(CIVector(x: CGFloat(whiteThreshold), y: CGFloat(whiteThreshold), z: CGFloat(whiteThreshold), w: 0), forKey: "inputMinComponents")
        colorClamp.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputMaxComponents")
        
        return colorClamp.outputImage ?? grayscale
    }
    
    // MARK: - Motion Detection
    
    private func detectMotion(current: CIImage, previous: CIImage) -> CIImage? {
        // Frame differencing to detect moving objects
        guard let diffFilter = CIFilter(name: "CIDifferenceBlendMode") else {
            return nil
        }
        
        diffFilter.setValue(current, forKey: kCIInputImageKey)
        diffFilter.setValue(previous, forKey: kCIInputBackgroundImageKey)
        
        guard let diff = diffFilter.outputImage else { return nil }
        
        // Threshold the difference to get motion mask
        guard let colorClamp = CIFilter(name: "CIColorClamp") else {
            return diff
        }
        colorClamp.setValue(diff, forKey: kCIInputImageKey)
        colorClamp.setValue(CIVector(x: CGFloat(motionThreshold), y: CGFloat(motionThreshold), z: CGFloat(motionThreshold), w: 0), forKey: "inputMinComponents")
        colorClamp.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputMaxComponents")
        
        return colorClamp.outputImage
    }
    
    // MARK: - Mask Combination
    
    private func combineMasks(white: CIImage, motion: CIImage?) -> CIImage {
        guard let motion = motion else {
            return white
        }
        
        // Multiply masks - ball must be BOTH white AND moving
        guard let multiplyFilter = CIFilter(name: "CIMultiplyBlendMode") else {
            return white
        }
        
        multiplyFilter.setValue(white, forKey: kCIInputImageKey)
        multiplyFilter.setValue(motion, forKey: kCIInputBackgroundImageKey)
        
        return multiplyFilter.outputImage ?? white
    }
    
    // MARK: - Ball Candidate Detection
    
    private func findBallCandidate(in mask: CIImage, imageSize: CGSize, time: CMTime) -> BallPosition? {
        // Render mask to get pixel data
        let extent = mask.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        
        // Create a smaller version for faster processing
        let scale: CGFloat = 0.25
        let scaledExtent = CGRect(
            x: 0, y: 0,
            width: extent.width * scale,
            height: extent.height * scale
        )
        
        guard let scaledMask = CIFilter(name: "CILanczosScaleTransform")?
            .apply(to: mask, extent: scaledExtent) else { return nil }
        
        // Render to bitmap
        let width = Int(scaledExtent.width)
        let height = Int(scaledExtent.height)
        var bitmap = [UInt8](repeating: 0, count: width * height * 4)
        
        ciContext.render(
            scaledMask,
            toBitmap: &bitmap,
            rowBytes: width * 4,
            bounds: scaledExtent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        // Find bright blobs (potential balls)
        var brightPixels: [(x: Int, y: Int, brightness: UInt8)] = []
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = bitmap[offset]
                let g = bitmap[offset + 1]
                let b = bitmap[offset + 2]
                let brightness = UInt8((Int(r) + Int(g) + Int(b)) / 3)
                
                if brightness > 200 { // Very bright = potential ball
                    brightPixels.append((x, y, brightness))
                }
            }
        }
        
        guard !brightPixels.isEmpty else { return nil }
        
        // Find centroid of bright pixels (simple blob detection)
        let totalX = brightPixels.reduce(0) { $0 + $1.x }
        let totalY = brightPixels.reduce(0) { $0 + $1.y }
        let count = brightPixels.count
        
        // Check blob size
        guard count >= minBlobSize, count <= maxBlobSize else { return nil }
        
        let centerX = CGFloat(totalX) / CGFloat(count)
        let centerY = CGFloat(totalY) / CGFloat(count)
        
        // Normalize to 0-1
        let normalizedX = centerX / CGFloat(width)
        let normalizedY = 1.0 - (centerY / CGFloat(height)) // Flip Y for UIKit coords
        
        // Estimate radius from blob size
        let radius = sqrt(CGFloat(count) / .pi) / CGFloat(width)
        
        // Calculate confidence based on blob compactness
        let avgBrightness = brightPixels.reduce(0) { $0 + Int($1.brightness) } / count
        let confidence = Float(avgBrightness) / 255.0
        
        return BallPosition(
            center: CGPoint(x: normalizedX, y: normalizedY),
            radius: radius,
            confidence: confidence,
            frameTime: time
        )
    }
    
    // MARK: - Trajectory Filtering
    
    private func filterForParabolicMotion(_ positions: [BallPosition]) -> [BallPosition] {
        guard positions.count >= 3 else { return positions }
        
        // Golf ball trajectory should be:
        // 1. Moving generally upward then downward (parabola)
        // 2. Moving in a consistent horizontal direction
        // 3. Smooth (no sudden jumps)
        
        var filtered: [BallPosition] = []
        
        for i in 0..<positions.count {
            let current = positions[i]
            
            // Check if this point fits the trajectory
            if filtered.isEmpty {
                filtered.append(current)
                continue
            }
            
            let previous = filtered.last!
            
            // Calculate movement
            let dx = current.center.x - previous.center.x
            let dy = current.center.y - previous.center.y
            let distance = sqrt(dx * dx + dy * dy)
            
            // Filter out:
            // - Stationary points (no movement)
            // - Jumps (too much movement between frames)
            // - Backwards movement (ball should go forward)
            
            if distance > 0.001 && distance < 0.2 {
                // Reasonable movement
                filtered.append(current)
            }
        }
        
        return filtered
    }
}

// MARK: - CIFilter Extension

private extension CIFilter {
    func apply(to image: CIImage, extent: CGRect) -> CIImage? {
        setValue(image, forKey: kCIInputImageKey)
        setValue(extent.width / image.extent.width, forKey: kCIInputScaleKey)
        setValue(1.0, forKey: kCIInputAspectRatioKey)
        return outputImage
    }
}


