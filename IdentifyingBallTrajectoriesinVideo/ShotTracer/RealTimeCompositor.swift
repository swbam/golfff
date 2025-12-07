import AVFoundation
import CoreImage
import Metal
import UIKit

/// RealTimeCompositor - GPU-accelerated tracer rendering onto video frames
///
/// This is the KEY to achieving SmoothSwing-style instant export:
/// - Every frame gets the tracer composited DURING capture
/// - The saved video IS the live view (no post-processing!)
/// - Uses Metal/CoreImage for GPU acceleration to maintain 240fps
///
/// Flow:
/// 1. Receive raw pixel buffer from camera
/// 2. Get current trajectory from TrajectoryDetector
/// 3. Render tracer path as CIImage overlay
/// 4. Composite overlay onto video frame
/// 5. Output composited buffer for both preview AND recording
final class RealTimeCompositor {
    
    // MARK: - Metal/CoreImage Context
    
    private let metalDevice: MTLDevice
    private let ciContext: CIContext
    private let commandQueue: MTLCommandQueue
    
    // MARK: - Pixel Buffer Pool
    
    private var outputPixelBufferPool: CVPixelBufferPool?
    private var outputPixelBufferAttributes: [String: Any]?
    private var outputWidth: Int = 1920
    private var outputHeight: Int = 1080
    
    // MARK: - Tracer State
    
    /// Current trajectory points to render (normalized 0-1 coordinates)
    var trajectoryPoints: [CGPoint] = []
    
    /// Tracer color
    var tracerColor: UIColor = ShotTracerDesign.Colors.tracerRed
    
    /// Tracer style
    var tracerStyle: TracerStyle = .neon
    
    /// Line width
    var lineWidth: CGFloat = 6
    
    /// Glow intensity
    var glowIntensity: CGFloat = 1.0
    
    /// Enable/disable compositing
    var isCompositing: Bool = true
    
    // MARK: - Pre-rendered Overlay Cache
    
    private var cachedOverlay: CIImage?
    private var lastPointsHash: Int = 0
    
    // MARK: - Debug
    
    var debugLogging: Bool = false
    private var frameCount: Int = 0
    private var lastLogTime: Date = Date()
    
    // MARK: - Initialization
    
    init?() {
        // Initialize Metal
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ RealTimeCompositor: Metal not supported")
            return nil
        }
        
        guard let queue = device.makeCommandQueue() else {
            print("❌ RealTimeCompositor: Failed to create command queue")
            return nil
        }
        
        self.metalDevice = device
        self.commandQueue = queue
        
        // Create CIContext with Metal device for GPU-accelerated rendering
        self.ciContext = CIContext(
            mtlDevice: device,
            options: [
                .cacheIntermediates: false,  // Save memory
                .priorityRequestLow: false,   // High priority
                .highQualityDownsample: false // Speed over quality
            ]
        )
        
        print("✅ RealTimeCompositor: Initialized with Metal")
    }
    
    // MARK: - Configuration
    
    /// Configure output size (call when camera resolution is known)
    func configure(width: Int, height: Int) {
        guard width != outputWidth || height != outputHeight else { return }
        
        outputWidth = width
        outputHeight = height
        
        // Recreate pixel buffer pool
        outputPixelBufferPool = nil
        createPixelBufferPool()
        
        if debugLogging {
            print("📐 RealTimeCompositor configured: \(width)x\(height)")
        }
    }
    
    private func createPixelBufferPool() {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outputWidth,
            kCVPixelBufferHeightKey as String: outputHeight,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        outputPixelBufferAttributes = pixelBufferAttributes
        
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pool
        )
        
        outputPixelBufferPool = pool
        
        if debugLogging {
            print("🔄 RealTimeCompositor: Pixel buffer pool created")
        }
    }
    
    // MARK: - Core Compositing
    
    /// Composite tracer onto video frame and return the result
    /// This is called for EVERY frame during recording
    func composite(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) -> CVPixelBuffer? {
        frameCount += 1
        
        // Get output buffer from pool
        guard let pool = outputPixelBufferPool else {
            configure(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            return pixelBuffer  // Return original if pool not ready
        }
        
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
        
        guard status == kCVReturnSuccess, let output = outputBuffer else {
            if debugLogging && frameCount % 60 == 0 {
                print("⚠️ RealTimeCompositor: Failed to create output buffer")
            }
            return pixelBuffer
        }
        
        // Create CIImage from input
        var inputImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Apply orientation if needed
        if orientation != .up {
            inputImage = inputImage.oriented(forExifOrientation: Int32(orientation.rawValue))
        }
        
        // If no trajectory or compositing disabled, just copy
        if !isCompositing || trajectoryPoints.count < 2 {
            ciContext.render(inputImage, to: output)
            return output
        }
        
        // Render tracer overlay
        let overlayImage = renderTracerOverlay(size: inputImage.extent.size)
        
        // Composite overlay onto video
        let compositedImage = overlayImage.composited(over: inputImage)
        
        // Render to output buffer
        ciContext.render(compositedImage, to: output)
        
        // Debug logging
        if debugLogging && Date().timeIntervalSince(lastLogTime) > 1.0 {
            print("📊 RealTimeCompositor: \(frameCount) frames, \(trajectoryPoints.count) points")
            lastLogTime = Date()
        }
        
        return output
    }
    
    // MARK: - Tracer Rendering
    
    /// Render tracer path as a CIImage overlay
    private func renderTracerOverlay(size: CGSize) -> CIImage {
        // Check cache (create our own hash since CGPoint Hashable is iOS 18+)
        var hasher = Hasher()
        for point in trajectoryPoints {
            hasher.combine(point.x)
            hasher.combine(point.y)
        }
        hasher.combine(tracerColor.hashValue)
        hasher.combine(tracerStyle.hashValue)
        let currentHash = hasher.finalize()
        
        if currentHash == lastPointsHash, let cached = cachedOverlay, cached.extent.size == size {
            return cached
        }
        
        // Create graphics context for drawing
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        
        let image = renderer.image { ctx in
            let context = ctx.cgContext
            
            // Convert normalized points to pixel coordinates
            let pixelPoints = trajectoryPoints.map { point -> CGPoint in
                CGPoint(x: point.x * size.width, y: point.y * size.height)
            }
            
            guard pixelPoints.count >= 2 else { return }
            
            // Create smooth bezier path
            let path = createSmoothPath(from: pixelPoints)
            
            // Draw based on style
            switch tracerStyle {
            case .solid:
                drawSolidTracer(context: context, path: path)
                
            case .gradient:
                drawGradientTracer(context: context, path: path, points: pixelPoints)
                
            case .neon:
                drawNeonTracer(context: context, path: path)
                
            case .fire:
                drawFireTracer(context: context, path: path, points: pixelPoints)
                
            case .ice:
                drawIceTracer(context: context, path: path, points: pixelPoints)
                
            case .rainbow:
                drawRainbowTracer(context: context, path: path, points: pixelPoints)
            }
            
            // Draw ball indicator at end
            if let lastPoint = pixelPoints.last {
                drawBallIndicator(context: context, at: lastPoint)
            }
        }
        
        let overlay = CIImage(image: image)!
        
        // Cache for next frame if points haven't changed
        lastPointsHash = currentHash
        cachedOverlay = overlay
        
        return overlay
    }
    
    // MARK: - Drawing Methods
    
    private func drawSolidTracer(context: CGContext, path: UIBezierPath) {
        // Shadow/glow
        context.saveGState()
        context.setShadow(offset: .zero, blur: lineWidth * 2 * glowIntensity, color: tracerColor.cgColor)
        context.setStrokeColor(tracerColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()
        
        // Main line
        context.setStrokeColor(tracerColor.cgColor)
        context.setLineWidth(lineWidth)
        context.addPath(path.cgPath)
        context.strokePath()
    }
    
    private func drawNeonTracer(context: CGContext, path: UIBezierPath) {
        // Outer glow
        context.saveGState()
        context.setShadow(offset: .zero, blur: lineWidth * 4 * glowIntensity, color: tracerColor.withAlphaComponent(0.5).cgColor)
        context.setStrokeColor(tracerColor.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(lineWidth * 3)
        context.setLineCap(.round)
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()
        
        // Inner glow
        context.saveGState()
        context.setShadow(offset: .zero, blur: lineWidth * 2 * glowIntensity, color: tracerColor.cgColor)
        context.setStrokeColor(tracerColor.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(lineWidth * 1.5)
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()
        
        // Core
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(lineWidth * 0.5)
        context.addPath(path.cgPath)
        context.strokePath()
    }
    
    private func drawGradientTracer(context: CGContext, path: UIBezierPath, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        
        // Draw with gradient along path
        context.saveGState()
        context.setShadow(offset: .zero, blur: lineWidth * 2 * glowIntensity, color: tracerColor.cgColor)
        
        let colors = [tracerColor.cgColor, tracerColor.lighter(by: 0.3).cgColor]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1])!
        
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.addPath(path.cgPath)
        context.replacePathWithStrokedPath()
        context.clip()
        
        let start = points.first!
        let end = points.last!
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }
    
    private func drawFireTracer(context: CGContext, path: UIBezierPath, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        
        let fireColors = [
            ShotTracerDesign.Colors.tracerYellow.cgColor,
            ShotTracerDesign.Colors.tracerOrange.cgColor,
            ShotTracerDesign.Colors.tracerRed.cgColor
        ]
        
        context.saveGState()
        context.setShadow(offset: .zero, blur: lineWidth * 3 * glowIntensity, color: ShotTracerDesign.Colors.tracerOrange.cgColor)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorSpace, colors: fireColors as CFArray, locations: [0, 0.5, 1])!
        
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.addPath(path.cgPath)
        context.replacePathWithStrokedPath()
        context.clip()
        
        let start = points.first!
        let end = points.last!
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }
    
    private func drawIceTracer(context: CGContext, path: UIBezierPath, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        
        let iceColors = [
            UIColor.white.cgColor,
            ShotTracerDesign.Colors.tracerCyan.cgColor,
            ShotTracerDesign.Colors.tracerBlue.cgColor
        ]
        
        context.saveGState()
        context.setShadow(offset: .zero, blur: lineWidth * 3 * glowIntensity, color: ShotTracerDesign.Colors.tracerCyan.cgColor)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorSpace, colors: iceColors as CFArray, locations: [0, 0.4, 1])!
        
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.addPath(path.cgPath)
        context.replacePathWithStrokedPath()
        context.clip()
        
        let start = points.first!
        let end = points.last!
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }
    
    private func drawRainbowTracer(context: CGContext, path: UIBezierPath, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        
        let rainbowColors = [
            ShotTracerDesign.Colors.tracerRed.cgColor,
            ShotTracerDesign.Colors.tracerOrange.cgColor,
            ShotTracerDesign.Colors.tracerYellow.cgColor,
            ShotTracerDesign.Colors.tracerGreen.cgColor,
            ShotTracerDesign.Colors.tracerCyan.cgColor,
            ShotTracerDesign.Colors.tracerBlue.cgColor,
            ShotTracerDesign.Colors.tracerPurple.cgColor
        ]
        
        context.saveGState()
        context.setShadow(offset: .zero, blur: lineWidth * 2 * glowIntensity, color: UIColor.white.withAlphaComponent(0.3).cgColor)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let locations: [CGFloat] = [0, 0.17, 0.33, 0.5, 0.67, 0.83, 1.0]
        let gradient = CGGradient(colorsSpace: colorSpace, colors: rainbowColors as CFArray, locations: locations)!
        
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.addPath(path.cgPath)
        context.replacePathWithStrokedPath()
        context.clip()
        
        let start = points.first!
        let end = points.last!
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }
    
    private func drawBallIndicator(context: CGContext, at point: CGPoint) {
        let ballRadius = lineWidth * 1.5
        
        // Glow
        context.saveGState()
        context.setShadow(offset: .zero, blur: ballRadius * 2 * glowIntensity, color: tracerColor.cgColor)
        context.setFillColor(tracerColor.withAlphaComponent(0.4).cgColor)
        context.fillEllipse(in: CGRect(
            x: point.x - ballRadius * 2,
            y: point.y - ballRadius * 2,
            width: ballRadius * 4,
            height: ballRadius * 4
        ))
        context.restoreGState()
        
        // Ball
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(
            x: point.x - ballRadius,
            y: point.y - ballRadius,
            width: ballRadius * 2,
            height: ballRadius * 2
        ))
    }
    
    // MARK: - Path Creation
    
    private func createSmoothPath(from points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        
        guard points.count > 1 else {
            if let first = points.first {
                path.move(to: first)
            }
            return path
        }
        
        path.move(to: points[0])
        
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        
        // Catmull-Rom spline for smooth curves
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
    
    // MARK: - Public Update Method
    
    /// Update trajectory points (call from TrajectoryDetector delegate)
    func updateTrajectory(_ points: [CGPoint]) {
        trajectoryPoints = points
        cachedOverlay = nil  // Invalidate cache
    }
    
    /// Update trajectory from Trajectory object
    func updateTrajectory(_ trajectory: Trajectory) {
        // Use projectedPoints for smooth arc (same as live view!)
        let points = trajectory.projectedPoints.isEmpty
            ? trajectory.detectedPoints.map { $0.normalized }
            : trajectory.projectedPoints.map { $0.normalized }
        updateTrajectory(points)
    }
    
    /// Clear trajectory
    func clearTrajectory() {
        trajectoryPoints = []
        cachedOverlay = nil
        lastPointsHash = 0
    }
    
    // MARK: - Stats
    
    func resetStats() {
        frameCount = 0
        lastLogTime = Date()
    }
}
