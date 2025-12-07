import UIKit

/// A view that draws a REALISTIC golfer silhouette outline for alignment
/// This is similar to what SmoothSwing uses - a clear, recognizable golfer figure
final class GolferSilhouetteView: UIView {
    
    enum StanceType {
        case address      // Setup position - bent over, hands together
        case backswing    // Top of backswing
        case impact       // Impact position
        case followThrough // Follow through - wrapped around
    }
    
    var silhouetteColor: UIColor = .white {
        didSet { setNeedsDisplay() }
    }
    
    var lineWidth: CGFloat = 3 {
        didSet { setNeedsDisplay() }
    }
    
    var stanceType: StanceType = .address {
        didSet { setNeedsDisplay() }
    }
    
    var showBallPosition: Bool = true {
        didSet { setNeedsDisplay() }
    }
    
    /// Flip for left-handed golfer
    var isLeftHanded: Bool = false {
        didSet { setNeedsDisplay() }
    }
    
    /// The normalized ball position (0-1) within this view's bounds
    var ballPosition: CGPoint {
        // Ball is at the golfer's feet, slightly forward of center
        return CGPoint(x: isLeftHanded ? 0.58 : 0.42, y: 0.93)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // Save context for potential flip
        context.saveGState()
        
        // Flip for left-handed if needed
        if isLeftHanded {
            context.translateBy(x: rect.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        
        context.setStrokeColor(silhouetteColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        switch stanceType {
        case .address:
            drawRealisticAddressStance(context: context, in: rect)
        case .backswing:
            drawRealisticBackswing(context: context, in: rect)
        case .impact:
            drawRealisticImpact(context: context, in: rect)
        case .followThrough:
            drawRealisticFollowThrough(context: context, in: rect)
        }
        
        context.restoreGState()
        
        // Draw ball position indicator
        if showBallPosition {
            drawBallIndicator(context: context, in: rect)
        }
    }
    
    // MARK: - Realistic Address Position
    
    private func drawRealisticAddressStance(context: CGContext, in rect: CGRect) {
        let w = rect.width
        let h = rect.height
        
        // ═══════════════════════════════════════════════════════════════
        // REALISTIC GOLFER IN ADDRESS POSITION
        // - Knees slightly bent
        // - Bent at the waist
        // - Arms hanging down, hands together
        // - Head looking at ball
        // - Club extending to ball
        // ═══════════════════════════════════════════════════════════════
        
        // Key body proportions (normalized to view)
        let headCenterX: CGFloat = 0.52
        let headCenterY: CGFloat = 0.15
        let headRadius: CGFloat = 0.055
        
        // Torso bent forward
        let neckX: CGFloat = 0.50
        let neckY: CGFloat = 0.21
        let shoulderWidth: CGFloat = 0.22
        let waistY: CGFloat = 0.48
        let waistX: CGFloat = 0.58  // Waist is back due to forward bend
        
        // Arms hanging down to grip
        let gripX: CGFloat = 0.38
        let gripY: CGFloat = 0.58
        
        // Legs with knee bend
        let hipWidth: CGFloat = 0.14
        let kneeY: CGFloat = 0.72
        let footY: CGFloat = 0.92
        
        // HEAD - slightly tilted looking at ball
        let headCenter = CGPoint(x: w * headCenterX, y: h * headCenterY)
        context.addArc(center: headCenter, radius: w * headRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        context.strokePath()
        
        // Face direction indicator (looking down at ball)
        context.move(to: CGPoint(x: headCenter.x - w * 0.02, y: headCenter.y + w * 0.03))
        context.addLine(to: CGPoint(x: headCenter.x - w * 0.04, y: headCenter.y + w * 0.05))
        context.strokePath()
        
        // CAP/VISOR
        context.move(to: CGPoint(x: w * (headCenterX - headRadius - 0.01), y: h * (headCenterY - 0.01)))
        context.addLine(to: CGPoint(x: w * (headCenterX - headRadius - 0.04), y: h * (headCenterY - 0.02)))
        context.strokePath()
        
        // NECK
        context.move(to: CGPoint(x: w * headCenterX, y: h * (headCenterY + headRadius)))
        context.addLine(to: CGPoint(x: w * neckX, y: h * neckY))
        context.strokePath()
        
        // SHOULDERS
        let leftShoulderX = neckX - shoulderWidth / 2
        let rightShoulderX = neckX + shoulderWidth / 2
        context.move(to: CGPoint(x: w * leftShoulderX, y: h * (neckY + 0.02)))
        context.addLine(to: CGPoint(x: w * rightShoulderX, y: h * (neckY + 0.02)))
        context.strokePath()
        
        // TORSO - curved spine showing forward bend
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w * neckX, y: h * neckY))
        path.addCurve(
            to: CGPoint(x: w * waistX, y: h * waistY),
            controlPoint1: CGPoint(x: w * (neckX + 0.05), y: h * (neckY + 0.10)),
            controlPoint2: CGPoint(x: w * (waistX + 0.02), y: h * (waistY - 0.08))
        )
        context.addPath(path.cgPath)
        context.strokePath()
        
        // LEFT ARM - hanging down to grip
        let leftArmPath = UIBezierPath()
        leftArmPath.move(to: CGPoint(x: w * leftShoulderX, y: h * (neckY + 0.02)))
        leftArmPath.addCurve(
            to: CGPoint(x: w * gripX, y: h * gripY),
            controlPoint1: CGPoint(x: w * (leftShoulderX - 0.06), y: h * (neckY + 0.15)),
            controlPoint2: CGPoint(x: w * (gripX - 0.02), y: h * (gripY - 0.12))
        )
        context.addPath(leftArmPath.cgPath)
        context.strokePath()
        
        // RIGHT ARM - hanging down to grip
        let rightArmPath = UIBezierPath()
        rightArmPath.move(to: CGPoint(x: w * rightShoulderX, y: h * (neckY + 0.02)))
        rightArmPath.addCurve(
            to: CGPoint(x: w * (gripX + 0.03), y: h * gripY),
            controlPoint1: CGPoint(x: w * (rightShoulderX + 0.02), y: h * (neckY + 0.15)),
            controlPoint2: CGPoint(x: w * (gripX + 0.08), y: h * (gripY - 0.10))
        )
        context.addPath(rightArmPath.cgPath)
        context.strokePath()
        
        // HANDS - interlocked grip
        context.addArc(
            center: CGPoint(x: w * (gripX + 0.015), y: h * gripY),
            radius: w * 0.025,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        )
        context.strokePath()
        
        // HIPS
        let leftHipX = waistX - hipWidth / 2
        let rightHipX = waistX + hipWidth / 2
        context.move(to: CGPoint(x: w * leftHipX, y: h * waistY))
        context.addLine(to: CGPoint(x: w * rightHipX, y: h * waistY))
        context.strokePath()
        
        // LEFT LEG - slight knee bend
        let leftKneeX: CGFloat = leftHipX - 0.03
        let leftFootX: CGFloat = leftHipX - 0.05
        
        let leftLegPath = UIBezierPath()
        leftLegPath.move(to: CGPoint(x: w * leftHipX, y: h * waistY))
        leftLegPath.addQuadCurve(
            to: CGPoint(x: w * leftKneeX, y: h * kneeY),
            controlPoint: CGPoint(x: w * (leftHipX - 0.02), y: h * ((waistY + kneeY) / 2))
        )
        leftLegPath.addLine(to: CGPoint(x: w * leftFootX, y: h * footY))
        context.addPath(leftLegPath.cgPath)
        context.strokePath()
        
        // LEFT FOOT
        context.move(to: CGPoint(x: w * (leftFootX - 0.04), y: h * footY))
        context.addLine(to: CGPoint(x: w * (leftFootX + 0.05), y: h * footY))
        context.strokePath()
        
        // RIGHT LEG - slight knee bend
        let rightKneeX: CGFloat = rightHipX + 0.02
        let rightFootX: CGFloat = rightHipX + 0.03
        
        let rightLegPath = UIBezierPath()
        rightLegPath.move(to: CGPoint(x: w * rightHipX, y: h * waistY))
        rightLegPath.addQuadCurve(
            to: CGPoint(x: w * rightKneeX, y: h * kneeY),
            controlPoint: CGPoint(x: w * (rightHipX + 0.01), y: h * ((waistY + kneeY) / 2))
        )
        rightLegPath.addLine(to: CGPoint(x: w * rightFootX, y: h * footY))
        context.addPath(rightLegPath.cgPath)
        context.strokePath()
        
        // RIGHT FOOT
        context.move(to: CGPoint(x: w * (rightFootX - 0.05), y: h * footY))
        context.addLine(to: CGPoint(x: w * (rightFootX + 0.04), y: h * footY))
        context.strokePath()
        
        // GOLF CLUB
        let clubHeadX: CGFloat = 0.40
        let clubHeadY: CGFloat = 0.90
        
        // Shaft
        context.move(to: CGPoint(x: w * gripX, y: h * gripY))
        context.addLine(to: CGPoint(x: w * clubHeadX, y: h * clubHeadY))
        context.strokePath()
        
        // Club head
        context.setLineWidth(lineWidth * 1.5)
        context.move(to: CGPoint(x: w * (clubHeadX - 0.04), y: h * clubHeadY))
        context.addLine(to: CGPoint(x: w * (clubHeadX + 0.02), y: h * (clubHeadY + 0.02)))
        context.strokePath()
        context.setLineWidth(lineWidth)
    }
    
    // MARK: - Realistic Backswing
    
    private func drawRealisticBackswing(context: CGContext, in rect: CGRect) {
        let w = rect.width
        let h = rect.height
        
        // HEAD - rotated back
        let headCenter = CGPoint(x: w * 0.48, y: h * 0.14)
        context.addArc(center: headCenter, radius: w * 0.055, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        context.strokePath()
        
        // TORSO - rotated
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w * 0.48, y: h * 0.20))
        path.addCurve(
            to: CGPoint(x: w * 0.55, y: h * 0.46),
            controlPoint1: CGPoint(x: w * 0.52, y: h * 0.28),
            controlPoint2: CGPoint(x: w * 0.56, y: h * 0.38)
        )
        context.addPath(path.cgPath)
        context.strokePath()
        
        // SHOULDERS - rotated back
        context.move(to: CGPoint(x: w * 0.36, y: h * 0.19))
        context.addLine(to: CGPoint(x: w * 0.58, y: h * 0.24))
        context.strokePath()
        
        // LEFT ARM - extended up
        let leftArmPath = UIBezierPath()
        leftArmPath.move(to: CGPoint(x: w * 0.36, y: h * 0.19))
        leftArmPath.addCurve(
            to: CGPoint(x: w * 0.72, y: h * 0.12),
            controlPoint1: CGPoint(x: w * 0.45, y: h * 0.08),
            controlPoint2: CGPoint(x: w * 0.62, y: h * 0.06)
        )
        context.addPath(leftArmPath.cgPath)
        context.strokePath()
        
        // RIGHT ARM - folded
        let rightArmPath = UIBezierPath()
        rightArmPath.move(to: CGPoint(x: w * 0.58, y: h * 0.24))
        rightArmPath.addCurve(
            to: CGPoint(x: w * 0.70, y: h * 0.14),
            controlPoint1: CGPoint(x: w * 0.66, y: h * 0.22),
            controlPoint2: CGPoint(x: w * 0.72, y: h * 0.18)
        )
        context.addPath(rightArmPath.cgPath)
        context.strokePath()
        
        // HANDS at top
        context.addArc(center: CGPoint(x: w * 0.71, y: h * 0.13), radius: w * 0.025, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        context.strokePath()
        
        // CLUB pointing down behind
        context.move(to: CGPoint(x: w * 0.72, y: h * 0.12))
        context.addLine(to: CGPoint(x: w * 0.78, y: h * 0.38))
        context.strokePath()
        
        // HIPS - slight rotation
        context.move(to: CGPoint(x: w * 0.46, y: h * 0.46))
        context.addLine(to: CGPoint(x: w * 0.64, y: h * 0.47))
        context.strokePath()
        
        // LEGS
        // Left leg
        context.move(to: CGPoint(x: w * 0.46, y: h * 0.46))
        context.addQuadCurve(to: CGPoint(x: w * 0.42, y: h * 0.92), control: CGPoint(x: w * 0.42, y: h * 0.70))
        context.strokePath()
        context.move(to: CGPoint(x: w * 0.36, y: h * 0.92))
        context.addLine(to: CGPoint(x: w * 0.48, y: h * 0.92))
        context.strokePath()
        
        // Right leg
        context.move(to: CGPoint(x: w * 0.64, y: h * 0.47))
        context.addQuadCurve(to: CGPoint(x: w * 0.66, y: h * 0.92), control: CGPoint(x: w * 0.66, y: h * 0.70))
        context.strokePath()
        context.move(to: CGPoint(x: w * 0.60, y: h * 0.92))
        context.addLine(to: CGPoint(x: w * 0.72, y: h * 0.92))
        context.strokePath()
    }
    
    // MARK: - Realistic Impact
    
    private func drawRealisticImpact(context: CGContext, in rect: CGRect) {
        // Impact is very similar to address but with more dynamic elements
        drawRealisticAddressStance(context: context, in: rect)
    }
    
    // MARK: - Realistic Follow Through
    
    private func drawRealisticFollowThrough(context: CGContext, in rect: CGRect) {
        let w = rect.width
        let h = rect.height
        
        // HEAD - looking at target
        let headCenter = CGPoint(x: w * 0.54, y: h * 0.12)
        context.addArc(center: headCenter, radius: w * 0.055, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        context.strokePath()
        
        // TORSO - rotated toward target
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w * 0.54, y: h * 0.18))
        path.addCurve(
            to: CGPoint(x: w * 0.52, y: h * 0.44),
            controlPoint1: CGPoint(x: w * 0.58, y: h * 0.26),
            controlPoint2: CGPoint(x: w * 0.56, y: h * 0.36)
        )
        context.addPath(path.cgPath)
        context.strokePath()
        
        // SHOULDERS - rotated through
        context.move(to: CGPoint(x: w * 0.42, y: h * 0.20))
        context.addLine(to: CGPoint(x: w * 0.64, y: h * 0.22))
        context.strokePath()
        
        // ARMS - wrapped around
        let armsPath = UIBezierPath()
        armsPath.move(to: CGPoint(x: w * 0.64, y: h * 0.22))
        armsPath.addCurve(
            to: CGPoint(x: w * 0.32, y: h * 0.16),
            controlPoint1: CGPoint(x: w * 0.58, y: h * 0.10),
            controlPoint2: CGPoint(x: w * 0.42, y: h * 0.08)
        )
        context.addPath(armsPath.cgPath)
        context.strokePath()
        
        // HANDS
        context.addArc(center: CGPoint(x: w * 0.32, y: h * 0.16), radius: w * 0.025, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        context.strokePath()
        
        // CLUB wrapped around shoulders
        context.move(to: CGPoint(x: w * 0.32, y: h * 0.16))
        context.addQuadCurve(to: CGPoint(x: w * 0.22, y: h * 0.32), control: CGPoint(x: w * 0.20, y: h * 0.18))
        context.strokePath()
        
        // HIPS - fully rotated
        context.move(to: CGPoint(x: w * 0.46, y: h * 0.44))
        context.addLine(to: CGPoint(x: w * 0.60, y: h * 0.45))
        context.strokePath()
        
        // LEFT LEG - posted up, straight
        context.move(to: CGPoint(x: w * 0.46, y: h * 0.44))
        context.addLine(to: CGPoint(x: w * 0.44, y: h * 0.92))
        context.strokePath()
        context.move(to: CGPoint(x: w * 0.38, y: h * 0.92))
        context.addLine(to: CGPoint(x: w * 0.50, y: h * 0.92))
        context.strokePath()
        
        // RIGHT LEG - on toe
        context.move(to: CGPoint(x: w * 0.60, y: h * 0.45))
        context.addQuadCurve(to: CGPoint(x: w * 0.68, y: h * 0.88), control: CGPoint(x: w * 0.66, y: h * 0.68))
        context.strokePath()
        // Toe
        context.move(to: CGPoint(x: w * 0.66, y: h * 0.88))
        context.addLine(to: CGPoint(x: w * 0.72, y: h * 0.85))
        context.strokePath()
    }
    
    // MARK: - Ball Indicator
    
    private func drawBallIndicator(context: CGContext, in rect: CGRect) {
        let ballCenter = CGPoint(
            x: rect.width * ballPosition.x,
            y: rect.height * ballPosition.y
        )
        let ballRadius: CGFloat = 10
        
        // Outer glow
        context.setStrokeColor(silhouetteColor.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(4)
        context.addArc(center: ballCenter, radius: ballRadius + 4, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        context.strokePath()
        
        // Ball outline
        context.setStrokeColor(silhouetteColor.cgColor)
        context.setLineWidth(2.5)
        context.addArc(center: ballCenter, radius: ballRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        context.strokePath()
        
        // Ball fill
        context.setFillColor(silhouetteColor.withAlphaComponent(0.2).cgColor)
        context.addArc(center: ballCenter, radius: ballRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        context.fillPath()
        
        // Crosshair on ball
        context.setStrokeColor(silhouetteColor.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: ballCenter.x - 6, y: ballCenter.y))
        context.addLine(to: CGPoint(x: ballCenter.x + 6, y: ballCenter.y))
        context.move(to: CGPoint(x: ballCenter.x, y: ballCenter.y - 6))
        context.addLine(to: CGPoint(x: ballCenter.x, y: ballCenter.y + 6))
        context.strokePath()
    }
}

// MARK: - Alignment Overlay View
/// Complete alignment overlay with silhouette and trajectory indicator
final class AlignmentOverlayView: UIView {
    
    private let golferSilhouette = GolferSilhouetteView()
    private let trajectoryArrow = CAShapeLayer()
    private let ballZoneIndicator = UIView()
    private let targetLine = CAShapeLayer()
    
    /// Is the golfer aligned?
    private(set) var isAligned: Bool = false
    
    /// Normalized ball position (0-1) based on silhouette
    var normalizedBallPosition: CGPoint {
        let silhouetteBall = golferSilhouette.convert(
            CGPoint(
                x: golferSilhouette.bounds.width * golferSilhouette.ballPosition.x,
                y: golferSilhouette.bounds.height * golferSilhouette.ballPosition.y
            ),
            to: self
        )
        return CGPoint(
            x: silhouetteBall.x / bounds.width,
            y: silhouetteBall.y / bounds.height
        )
    }
    
    /// The calculated region of interest based on silhouette position
    var detectionROI: CGRect {
        let ball = normalizedBallPosition
        
        // ROI should cover area above and around ball where trajectory will be
        let roiWidth: CGFloat = 0.6
        let roiHeight: CGFloat = 0.75
        
        let x = max(0, min(ball.x - roiWidth / 2, 1 - roiWidth))
        let y = max(0, ball.y - roiHeight + 0.1)  // Start above ball
        
        return CGRect(x: x, y: y, width: roiWidth, height: min(roiHeight, 1 - y))
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        backgroundColor = .clear
        
        // Single golfer silhouette in center
        golferSilhouette.stanceType = .address
        golferSilhouette.silhouetteColor = UIColor.white.withAlphaComponent(0.9)
        golferSilhouette.lineWidth = 3
        golferSilhouette.translatesAutoresizingMaskIntoConstraints = false
        addSubview(golferSilhouette)
        
        // Ball zone indicator with pulsing animation
        ballZoneIndicator.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        ballZoneIndicator.layer.borderColor = UIColor.white.cgColor
        ballZoneIndicator.layer.borderWidth = 2
        ballZoneIndicator.layer.cornerRadius = 25
        ballZoneIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ballZoneIndicator)
        
        // Target line showing ball flight direction
        targetLine.strokeColor = UIColor.white.withAlphaComponent(0.4).cgColor
        targetLine.fillColor = UIColor.clear.cgColor
        targetLine.lineWidth = 2
        targetLine.lineDashPattern = [8, 4]
        layer.addSublayer(targetLine)
        
        // Trajectory arrow
        trajectoryArrow.strokeColor = UIColor.white.cgColor
        trajectoryArrow.fillColor = UIColor.clear.cgColor
        trajectoryArrow.lineWidth = 3
        trajectoryArrow.lineCap = .round
        layer.addSublayer(trajectoryArrow)
        
        NSLayoutConstraint.activate([
            // Silhouette centered, takes up most of the view
            golferSilhouette.centerXAnchor.constraint(equalTo: centerXAnchor),
            golferSilhouette.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 20),
            golferSilhouette.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.65),
            golferSilhouette.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.75),
            
            // Ball zone at bottom center
            ballZoneIndicator.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -20),
            ballZoneIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -30),
            ballZoneIndicator.widthAnchor.constraint(equalToConstant: 50),
            ballZoneIndicator.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Start ball zone pulsing
        startBallZonePulse()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateTrajectoryArrow()
        updateTargetLine()
    }
    
    private func updateTrajectoryArrow() {
        let path = UIBezierPath()
        
        // Arrow starts from ball zone and curves upward
        let startPoint = CGPoint(x: bounds.midX - 20, y: bounds.height - 55)
        let endPoint = CGPoint(x: bounds.midX - 20, y: bounds.height * 0.15)
        let controlPoint = CGPoint(x: bounds.midX - 60, y: bounds.height * 0.4)
        
        path.move(to: startPoint)
        path.addQuadCurve(to: endPoint, controlPoint: controlPoint)
        
        // Arrow head
        let arrowSize: CGFloat = 12
        path.move(to: CGPoint(x: endPoint.x - arrowSize, y: endPoint.y + arrowSize * 1.5))
        path.addLine(to: endPoint)
        path.addLine(to: CGPoint(x: endPoint.x + arrowSize, y: endPoint.y + arrowSize * 1.5))
        
        trajectoryArrow.path = path.cgPath
        
        // Animate the arrow drawing
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = 2.0
        animation.repeatCount = .infinity
        trajectoryArrow.add(animation, forKey: "drawArrow")
    }
    
    private func updateTargetLine() {
        let path = UIBezierPath()
        
        // Horizontal line showing target direction
        let y = bounds.height * 0.12
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: bounds.width, y: y))
        
        targetLine.path = path.cgPath
    }
    
    private func startBallZonePulse() {
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.15
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ballZoneIndicator.layer.add(pulse, forKey: "pulse")
    }
    
    func setAligned(_ aligned: Bool) {
        isAligned = aligned
        
        let color = aligned ? ShotTracerDesign.Colors.mastersGreen : UIColor.white
        
        UIView.animate(withDuration: 0.3) {
            self.golferSilhouette.silhouetteColor = color.withAlphaComponent(0.9)
            self.ballZoneIndicator.layer.borderColor = color.cgColor
            self.ballZoneIndicator.backgroundColor = color.withAlphaComponent(0.15)
        }
        
        trajectoryArrow.strokeColor = color.cgColor
        targetLine.strokeColor = color.withAlphaComponent(0.4).cgColor
        
        if aligned {
            // Stop pulsing, show solid
            ballZoneIndicator.layer.removeAnimation(forKey: "pulse")
            
            // Success animation
            let successPulse = CAKeyframeAnimation(keyPath: "transform.scale")
            successPulse.values = [1.0, 1.3, 1.0]
            successPulse.duration = 0.3
            ballZoneIndicator.layer.add(successPulse, forKey: "success")
        } else {
            startBallZonePulse()
        }
    }
}
