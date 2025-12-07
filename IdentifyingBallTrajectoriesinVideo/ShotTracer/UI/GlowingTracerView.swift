import UIKit

// MARK: - Tracer Style
enum TracerStyle: Int, CaseIterable {
    case solid = 0
    case gradient
    case neon
    case fire
    case ice
    case rainbow
    
    var name: String {
        switch self {
        case .solid: return "Solid"
        case .gradient: return "Gradient"
        case .neon: return "Neon"
        case .fire: return "Fire"
        case .ice: return "Ice"
        case .rainbow: return "Rainbow"
        }
    }
    
    var iconName: String {
        switch self {
        case .solid: return "line.diagonal"
        case .gradient: return "paintbrush.fill"
        case .neon: return "lightbulb.fill"
        case .fire: return "flame.fill"
        case .ice: return "snowflake"
        case .rainbow: return "rainbow"
        }
    }
}

// MARK: - Glowing Tracer View
final class GlowingTracerView: UIView {
    
    // MARK: - Properties
    var tracerColor: UIColor = ShotTracerDesign.Colors.tracerRed {
        didSet { updateLayers() }
    }
    
    var tracerStyle: TracerStyle = .neon {
        didSet { updateLayers() }
    }
    
    var lineWidth: CGFloat = 5 {
        didSet { updateLayers() }
    }
    
    var glowIntensity: CGFloat = 1.0 {
        didSet { updateLayers() }
    }
    
    private var normalizedPoints: [CGPoint] = []
    
    // Layers for effects
    private let outerGlowLayer = CAShapeLayer()
    private let innerGlowLayer = CAShapeLayer()
    private let mainTracerLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private let gradientLayer = CAGradientLayer()
    private let gradientMaskLayer = CAShapeLayer()
    
    // Ball indicator at end of trajectory
    private let ballIndicator = CAShapeLayer()
    private let ballGlow = CAShapeLayer()
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    // MARK: - Setup
    private func setupLayers() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        
        // Order matters: outer glow -> inner glow -> main -> highlight
        layer.addSublayer(outerGlowLayer)
        layer.addSublayer(innerGlowLayer)
        layer.addSublayer(gradientLayer)
        layer.addSublayer(mainTracerLayer)
        layer.addSublayer(highlightLayer)
        layer.addSublayer(ballGlow)
        layer.addSublayer(ballIndicator)
        
        // Configure gradient layer
        gradientLayer.mask = gradientMaskLayer
        
        // Configure all layers
        [outerGlowLayer, innerGlowLayer, mainTracerLayer, highlightLayer, gradientMaskLayer].forEach { layer in
            layer.fillColor = UIColor.clear.cgColor
            layer.lineCap = .round
            layer.lineJoin = .round
        }
        
        // Ball indicator setup
        ballIndicator.fillColor = UIColor.white.cgColor
        ballGlow.fillColor = UIColor.white.withAlphaComponent(0.3).cgColor
        
        updateLayers()
    }
    
    private func updateLayers() {
        // Outer glow - widest, most transparent
        outerGlowLayer.strokeColor = tracerColor.withAlphaComponent(0.15 * glowIntensity).cgColor
        outerGlowLayer.lineWidth = lineWidth * 6
        
        // Inner glow - medium
        innerGlowLayer.strokeColor = tracerColor.withAlphaComponent(0.3 * glowIntensity).cgColor
        innerGlowLayer.lineWidth = lineWidth * 3
        
        // Main tracer
        mainTracerLayer.strokeColor = tracerColor.cgColor
        mainTracerLayer.lineWidth = lineWidth
        
        // Highlight - thin white line for depth
        highlightLayer.strokeColor = UIColor.white.withAlphaComponent(0.6).cgColor
        highlightLayer.lineWidth = lineWidth * 0.3
        
        // Update gradient colors based on style
        updateGradientStyle()
        
        // Re-render current points
        if !normalizedPoints.isEmpty {
            renderTrajectory()
        }
    }
    
    private func updateGradientStyle() {
        switch tracerStyle {
        case .solid:
            gradientLayer.isHidden = true
            mainTracerLayer.isHidden = false
            
        case .gradient:
            gradientLayer.isHidden = false
            mainTracerLayer.isHidden = true
            gradientLayer.colors = [
                tracerColor.cgColor,
                tracerColor.lighter(by: 0.3).cgColor
            ]
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            
        case .neon:
            gradientLayer.isHidden = true
            mainTracerLayer.isHidden = false
            // Neon uses stronger glow
            outerGlowLayer.strokeColor = tracerColor.withAlphaComponent(0.25 * glowIntensity).cgColor
            innerGlowLayer.strokeColor = tracerColor.withAlphaComponent(0.5 * glowIntensity).cgColor
            
        case .fire:
            gradientLayer.isHidden = false
            mainTracerLayer.isHidden = true
            gradientLayer.colors = [
                ShotTracerDesign.Colors.tracerYellow.cgColor,
                ShotTracerDesign.Colors.tracerOrange.cgColor,
                ShotTracerDesign.Colors.tracerRed.cgColor
            ]
            gradientLayer.startPoint = CGPoint(x: 0, y: 0)
            gradientLayer.endPoint = CGPoint(x: 1, y: 1)
            
        case .ice:
            gradientLayer.isHidden = false
            mainTracerLayer.isHidden = true
            gradientLayer.colors = [
                UIColor.white.cgColor,
                ShotTracerDesign.Colors.tracerCyan.cgColor,
                ShotTracerDesign.Colors.tracerBlue.cgColor
            ]
            gradientLayer.startPoint = CGPoint(x: 0, y: 0)
            gradientLayer.endPoint = CGPoint(x: 1, y: 1)
            
        case .rainbow:
            gradientLayer.isHidden = false
            mainTracerLayer.isHidden = true
            gradientLayer.colors = [
                ShotTracerDesign.Colors.tracerRed.cgColor,
                ShotTracerDesign.Colors.tracerOrange.cgColor,
                ShotTracerDesign.Colors.tracerYellow.cgColor,
                ShotTracerDesign.Colors.tracerGreen.cgColor,
                ShotTracerDesign.Colors.tracerCyan.cgColor,
                ShotTracerDesign.Colors.tracerBlue.cgColor,
                ShotTracerDesign.Colors.tracerPurple.cgColor
            ]
            gradientLayer.startPoint = CGPoint(x: 0, y: 0)
            gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        }
    }
    
    // MARK: - Public Update Method
    func update(with points: [CGPoint], color: UIColor? = nil) {
        if let color = color {
            tracerColor = color
        }
        
        normalizedPoints = points
        
        guard !points.isEmpty else {
            clear()
            return
        }
        
        renderTrajectory()
    }
    
    func clear() {
        normalizedPoints = []
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        [outerGlowLayer, innerGlowLayer, mainTracerLayer, highlightLayer, gradientMaskLayer].forEach { layer in
            layer.path = nil
        }
        
        ballIndicator.path = nil
        ballGlow.path = nil
        
        CATransaction.commit()
    }
    
    // MARK: - Rendering
    private func renderTrajectory() {
        guard !normalizedPoints.isEmpty else { return }
        
        // Convert normalized points to view coordinates
        let viewPoints = normalizedPoints.map { point -> CGPoint in
            CGPoint(x: point.x * bounds.width, y: point.y * bounds.height)
        }
        
        // Create smooth bezier path
        let path = createSmoothPath(from: viewPoints)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // Apply path to all layers
        outerGlowLayer.path = path.cgPath
        innerGlowLayer.path = path.cgPath
        mainTracerLayer.path = path.cgPath
        highlightLayer.path = path.cgPath
        gradientMaskLayer.path = path.cgPath
        gradientMaskLayer.lineWidth = lineWidth
        gradientMaskLayer.strokeColor = UIColor.white.cgColor
        
        // Update gradient layer frame
        gradientLayer.frame = bounds
        
        // Add ball indicator at the end
        if let lastPoint = viewPoints.last {
            let ballRadius: CGFloat = lineWidth * 1.5
            let glowRadius: CGFloat = lineWidth * 3
            
            ballIndicator.path = UIBezierPath(
                arcCenter: lastPoint,
                radius: ballRadius,
                startAngle: 0,
                endAngle: .pi * 2,
                clockwise: true
            ).cgPath
            
            ballGlow.path = UIBezierPath(
                arcCenter: lastPoint,
                radius: glowRadius,
                startAngle: 0,
                endAngle: .pi * 2,
                clockwise: true
            ).cgPath
            
            ballIndicator.fillColor = UIColor.white.cgColor
            ballGlow.fillColor = tracerColor.withAlphaComponent(0.4).cgColor
        }
        
        CATransaction.commit()
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
    
    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        
        // Re-render with new bounds
        if !normalizedPoints.isEmpty {
            renderTrajectory()
        }
    }
    
    // MARK: - Animation
    func animateAppearance() {
        let layers: [CAShapeLayer] = [outerGlowLayer, innerGlowLayer, mainTracerLayer, highlightLayer]
        
        layers.forEach { layer in
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = 0
            animation.toValue = 1
            animation.duration = 0.5
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "strokeAnimation")
        }
        
        // Animate ball appearance
        ballIndicator.opacity = 0
        ballGlow.opacity = 0
        
        let delay = DispatchTime.now() + 0.4
        DispatchQueue.main.asyncAfter(deadline: delay) {
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0
            fadeIn.toValue = 1
            fadeIn.duration = 0.2
            fadeIn.fillMode = .forwards
            fadeIn.isRemovedOnCompletion = false
            
            self.ballIndicator.add(fadeIn, forKey: "fadeIn")
            self.ballGlow.add(fadeIn, forKey: "fadeIn")
            self.ballIndicator.opacity = 1
            self.ballGlow.opacity = 1
        }
    }
    
    // Pulse effect when ball is hit
    func pulseEffect() {
        let pulse = CASpringAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.2
        pulse.damping = 8
        pulse.initialVelocity = 10
        pulse.duration = pulse.settlingDuration
        
        ballIndicator.add(pulse, forKey: "pulse")
        ballGlow.add(pulse, forKey: "pulse")
        
        // Flash effect
        let flash = CABasicAnimation(keyPath: "opacity")
        flash.fromValue = 1.0
        flash.toValue = 0.5
        flash.duration = 0.1
        flash.autoreverses = true
        
        mainTracerLayer.add(flash, forKey: "flash")
    }
}

// MARK: - Preview Container for SwiftUI (Debug)
#if DEBUG
import SwiftUI

@available(iOS 13.0, *)
struct GlowingTracerView_Preview: UIViewRepresentable {
    func makeUIView(context: Context) -> GlowingTracerView {
        let view = GlowingTracerView()
        view.backgroundColor = .black
        view.tracerStyle = .neon
        view.tracerColor = ShotTracerDesign.Colors.tracerCyan
        
        // Sample trajectory
        let points: [CGPoint] = [
            CGPoint(x: 0.5, y: 0.9),
            CGPoint(x: 0.52, y: 0.7),
            CGPoint(x: 0.55, y: 0.5),
            CGPoint(x: 0.6, y: 0.35),
            CGPoint(x: 0.65, y: 0.25),
            CGPoint(x: 0.72, y: 0.2),
            CGPoint(x: 0.8, y: 0.22),
            CGPoint(x: 0.85, y: 0.28)
        ]
        view.update(with: points)
        
        return view
    }
    
    func updateUIView(_ uiView: GlowingTracerView, context: Context) {}
}

@available(iOS 13.0, *)
struct GlowingTracerView_Previews: PreviewProvider {
    static var previews: some View {
        GlowingTracerView_Preview()
            .frame(width: 400, height: 600)
            .background(Color.black)
    }
}
#endif


