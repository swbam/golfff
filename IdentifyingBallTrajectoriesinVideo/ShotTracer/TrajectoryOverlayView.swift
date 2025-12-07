import UIKit

/// Renders the golf ball trajectory as a smooth arc
/// Uses Catmull-Rom splines for smooth curves between Vision's projected points
final class TrajectoryOverlayView: UIView {
    
    // MARK: - Layers
    
    private let tracerLayer = CAShapeLayer()
    private let shadowLayer = CAShapeLayer()
    private let glowLayer = CAShapeLayer()
    
    // Ball position indicator
    private let ballLayer = CAShapeLayer()
    
    // MARK: - Configuration
    
    var tracerColor: UIColor = .systemRed {
        didSet {
            tracerLayer.strokeColor = tracerColor.cgColor
            glowLayer.strokeColor = tracerColor.withAlphaComponent(0.3).cgColor
        }
    }
    
    var lineWidth: CGFloat = 5 {
        didSet {
            tracerLayer.lineWidth = lineWidth
            shadowLayer.lineWidth = lineWidth + 2
            glowLayer.lineWidth = lineWidth + 8
        }
    }
    
    var showBallIndicator: Bool = true
    var useSplineSmoothing: Bool = true
    
    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        setupLayers()
    }

    // MARK: - Public API
    
    /// Update with a Trajectory object - uses projectedPoints for smooth arc!
    func update(with trajectory: Trajectory) {
        // Use projectedPoints (Vision's predicted full arc) for smooth rendering
        // This is what makes live = export!
        let points = trajectory.projectedPoints.map { $0.normalized }
        update(with: points, color: tracerColor)
    }
    
    /// Update with raw normalized points
    func update(with normalizedPoints: [CGPoint], color: UIColor) {
        tracerColor = color
        
        guard normalizedPoints.count >= 2 else {
            clearPaths()
            return
        }

        // Convert to view coordinates
        let viewPoints = normalizedPoints.map { normalizedToView($0) }
        
        // Generate smooth path
        let path: UIBezierPath
        if useSplineSmoothing && viewPoints.count >= 4 {
            path = createCatmullRomPath(points: viewPoints)
        } else {
            path = createLinearPath(points: viewPoints)
        }
        
        // Shadow path (offset)
        let shadowPath = path.copy() as! UIBezierPath
        shadowPath.apply(CGAffineTransform(translationX: 2, y: 2))
        
        // Update layers
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        glowLayer.path = path.cgPath
        shadowLayer.path = shadowPath.cgPath
        tracerLayer.path = path.cgPath
        
        // Update ball indicator at last point
        if showBallIndicator, let lastPoint = viewPoints.last {
            let ballRadius: CGFloat = 6
            let ballRect = CGRect(
                x: lastPoint.x - ballRadius,
                y: lastPoint.y - ballRadius,
                width: ballRadius * 2,
                height: ballRadius * 2
            )
            ballLayer.path = UIBezierPath(ovalIn: ballRect).cgPath
            ballLayer.isHidden = false
        } else {
            ballLayer.isHidden = true
        }
        
        CATransaction.commit()
    }

    func clear() {
        clearPaths()
    }

    // MARK: - Path Generation
    
    private func createLinearPath(points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        
        return path
    }
    
    /// Create smooth Catmull-Rom spline through points
    private func createCatmullRomPath(points: [CGPoint], alpha: CGFloat = 0.5) -> UIBezierPath {
        let path = UIBezierPath()
        guard points.count >= 2 else { return path }
        
        path.move(to: points[0])
        
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        
        // Catmull-Rom spline interpolation
        for i in 0..<points.count - 1 {
            let p0 = points[max(0, i - 1)]
            let p1 = points[i]
            let p2 = points[min(points.count - 1, i + 1)]
            let p3 = points[min(points.count - 1, i + 2)]
            
            // Calculate control points
            let d1 = distance(p0, p1)
            let d2 = distance(p1, p2)
            _ = distance(p2, p3)  // d3 - available for extended spline calculations
            
            var b1: CGPoint
            var b2: CGPoint
            
            if d1 + d2 > 0.0001 {
                let scale1 = d1 / (d1 + d2)
                let scale2 = d2 / (d1 + d2)
                
                b1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) * scale2 * alpha / 3,
                    y: p1.y + (p2.y - p0.y) * scale2 * alpha / 3
                )
                b2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) * scale1 * alpha / 3,
                    y: p2.y - (p3.y - p1.y) * scale1 * alpha / 3
                )
            } else {
                b1 = p1
                b2 = p2
            }
            
            path.addCurve(to: p2, controlPoint1: b1, controlPoint2: b2)
        }
        
        return path
    }
    
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }
    
    // MARK: - Coordinate Conversion
    
    private func normalizedToView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * bounds.width, y: point.y * bounds.height)
    }
    
    // MARK: - Layer Setup

    private func setupLayers() {
        // Glow layer (outermost)
        glowLayer.strokeColor = tracerColor.withAlphaComponent(0.3).cgColor
        glowLayer.fillColor = UIColor.clear.cgColor
        glowLayer.lineWidth = lineWidth + 8
        glowLayer.lineCap = .round
        glowLayer.lineJoin = .round
        
        // Shadow layer
        shadowLayer.strokeColor = UIColor.black.withAlphaComponent(0.4).cgColor
        shadowLayer.fillColor = UIColor.clear.cgColor
        shadowLayer.lineWidth = lineWidth + 2
        shadowLayer.lineCap = .round
        shadowLayer.lineJoin = .round

        // Main tracer layer
        tracerLayer.strokeColor = tracerColor.cgColor
        tracerLayer.fillColor = UIColor.clear.cgColor
        tracerLayer.lineWidth = lineWidth
        tracerLayer.lineCap = .round
        tracerLayer.lineJoin = .round
        
        // Ball indicator
        ballLayer.fillColor = UIColor.white.cgColor
        ballLayer.strokeColor = tracerColor.cgColor
        ballLayer.lineWidth = 2
        ballLayer.isHidden = true

        // Add in order (back to front)
        layer.addSublayer(glowLayer)
        layer.addSublayer(shadowLayer)
        layer.addSublayer(tracerLayer)
        layer.addSublayer(ballLayer)
    }
    
    private func clearPaths() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowLayer.path = nil
        shadowLayer.path = nil
        tracerLayer.path = nil
        ballLayer.isHidden = true
        CATransaction.commit()
    }
    
    // MARK: - Animation
    
    /// Animate the tracer drawing in
    func animateDrawing(duration: TimeInterval = 0.5) {
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        tracerLayer.add(animation, forKey: "strokeEnd")
        shadowLayer.add(animation, forKey: "strokeEnd")
        glowLayer.add(animation, forKey: "strokeEnd")
    }
}
