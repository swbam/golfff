import UIKit

/// A view that draws golfer silhouette outlines for alignment, similar to SmoothSwing
final class GolferSilhouetteView: UIView {
    
    enum StanceType {
        case address    // Setup position
        case backswing  // Top of backswing
        case impact     // Impact position
        case followThrough // Follow through
    }
    
    var silhouetteColor: UIColor = .white {
        didSet { setNeedsDisplay() }
    }
    
    var lineWidth: CGFloat = 4 {
        didSet { setNeedsDisplay() }
    }
    
    var stanceType: StanceType = .address {
        didSet { setNeedsDisplay() }
    }
    
    var showBallPosition: Bool = true {
        didSet { setNeedsDisplay() }
    }
    
    /// The normalized ball position (0-1) within this view's bounds
    var ballPosition: CGPoint {
        switch stanceType {
        case .address, .impact:
            // Ball is at the golfer's feet, slightly left of center (for right-handed golfer)
            return CGPoint(x: 0.42, y: 0.92)
        case .backswing:
            return CGPoint(x: 0.42, y: 0.92)
        case .followThrough:
            return CGPoint(x: 0.42, y: 0.92)
        }
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
        
        context.setStrokeColor(silhouetteColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        let path = createGolferPath(in: rect)
        context.addPath(path.cgPath)
        context.strokePath()
        
        // Draw ball position indicator
        if showBallPosition {
            let ballCenter = CGPoint(
                x: rect.width * ballPosition.x,
                y: rect.height * ballPosition.y
            )
            let ballRadius: CGFloat = 8
            
            // Ball outline
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(2)
            context.addEllipse(in: CGRect(
                x: ballCenter.x - ballRadius,
                y: ballCenter.y - ballRadius,
                width: ballRadius * 2,
                height: ballRadius * 2
            ))
            context.strokePath()
            
            // Ball fill
            context.setFillColor(UIColor.white.withAlphaComponent(0.3).cgColor)
            context.addEllipse(in: CGRect(
                x: ballCenter.x - ballRadius,
                y: ballCenter.y - ballRadius,
                width: ballRadius * 2,
                height: ballRadius * 2
            ))
            context.fillPath()
        }
    }
    
    private func createGolferPath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        
        // Scale factors
        let w = rect.width
        let h = rect.height
        
        // Draw a golfer in address position (simplified but recognizable silhouette)
        // All coordinates are normalized 0-1, then scaled
        
        switch stanceType {
        case .address:
            drawAddressStance(path: path, w: w, h: h)
        case .backswing:
            drawBackswingStance(path: path, w: w, h: h)
        case .impact:
            drawImpactStance(path: path, w: w, h: h)
        case .followThrough:
            drawFollowThroughStance(path: path, w: w, h: h)
        }
        
        return path
    }
    
    private func drawAddressStance(path: UIBezierPath, w: CGFloat, h: CGFloat) {
        // Head
        let headCenter = CGPoint(x: w * 0.5, y: h * 0.1)
        let headRadius = w * 0.07
        path.addArc(withCenter: headCenter, radius: headRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)

        // Neck
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.17))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.2))

        // Shoulders + arms forming a triangle toward the grip
        let leftShoulder = CGPoint(x: w * 0.36, y: h * 0.2)
        let rightShoulder = CGPoint(x: w * 0.64, y: h * 0.2)
        let grip = CGPoint(x: w * 0.45, y: h * 0.42)

        path.move(to: leftShoulder)
        path.addLine(to: rightShoulder)
        path.move(to: leftShoulder)
        path.addQuadCurve(to: grip, controlPoint: CGPoint(x: w * 0.30, y: h * 0.32))
        path.move(to: rightShoulder)
        path.addQuadCurve(to: grip, controlPoint: CGPoint(x: w * 0.70, y: h * 0.32))

        // Torso
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.2))
        path.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.45), controlPoint: CGPoint(x: w * 0.55, y: h * 0.32))

        // Hips
        let leftHip = CGPoint(x: w * 0.42, y: h * 0.45)
        let rightHip = CGPoint(x: w * 0.58, y: h * 0.45)
        path.move(to: leftHip)
        path.addLine(to: rightHip)

        // Legs
        let leftKnee = CGPoint(x: w * 0.40, y: h * 0.65)
        let rightKnee = CGPoint(x: w * 0.60, y: h * 0.65)
        let leftAnkle = CGPoint(x: w * 0.40, y: h * 0.9)
        let rightAnkle = CGPoint(x: w * 0.60, y: h * 0.9)

        path.move(to: leftHip)
        path.addQuadCurve(to: leftAnkle, controlPoint: leftKnee)
        path.move(to: rightHip)
        path.addQuadCurve(to: rightAnkle, controlPoint: rightKnee)

        // Feet
        path.move(to: CGPoint(x: leftAnkle.x - w * 0.03, y: leftAnkle.y))
        path.addLine(to: CGPoint(x: leftAnkle.x + w * 0.05, y: leftAnkle.y))
        path.move(to: CGPoint(x: rightAnkle.x - w * 0.05, y: rightAnkle.y))
        path.addLine(to: CGPoint(x: rightAnkle.x + w * 0.03, y: rightAnkle.y))

        // Golf club (shaft + head)
        path.move(to: grip)
        let clubHead = CGPoint(x: w * 0.44, y: h * 0.88)
        path.addLine(to: clubHead)
        path.addLine(to: CGPoint(x: clubHead.x - w * 0.05, y: clubHead.y))
        path.addLine(to: CGPoint(x: clubHead.x + w * 0.02, y: clubHead.y + h * 0.02))
    }
    
    private func drawBackswingStance(path: UIBezierPath, w: CGFloat, h: CGFloat) {
        // Head (rotated)
        let headCenter = CGPoint(x: w * 0.48, y: h * 0.10)
        let headRadius = w * 0.06
        path.addArc(withCenter: headCenter, radius: headRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        
        // Neck
        path.move(to: CGPoint(x: w * 0.48, y: h * 0.16))
        path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.20))
        
        // Shoulders (rotated)
        path.move(to: CGPoint(x: w * 0.38, y: h * 0.18))
        path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.22))
        
        // Torso
        path.move(to: CGPoint(x: w * 0.50, y: h * 0.20))
        path.addQuadCurve(to: CGPoint(x: w * 0.52, y: h * 0.45), controlPoint: CGPoint(x: w * 0.54, y: h * 0.32))
        
        // Left arm (extended up)
        path.move(to: CGPoint(x: w * 0.38, y: h * 0.18))
        path.addQuadCurve(to: CGPoint(x: w * 0.70, y: h * 0.08), controlPoint: CGPoint(x: w * 0.50, y: h * 0.05))
        
        // Right arm (folded)
        path.move(to: CGPoint(x: w * 0.62, y: h * 0.22))
        path.addQuadCurve(to: CGPoint(x: w * 0.68, y: h * 0.12), controlPoint: CGPoint(x: w * 0.70, y: h * 0.18))
        
        // Hands at top
        path.addArc(withCenter: CGPoint(x: w * 0.69, y: h * 0.10), radius: w * 0.025, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        
        // Club (pointing down behind)
        path.move(to: CGPoint(x: w * 0.70, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.35))
        
        // Hips (slight turn)
        path.move(to: CGPoint(x: w * 0.42, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.46))
        
        // Legs (weight shifted)
        path.move(to: CGPoint(x: w * 0.44, y: h * 0.45))
        path.addQuadCurve(to: CGPoint(x: w * 0.40, y: h * 0.70), controlPoint: CGPoint(x: w * 0.40, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.90))
        
        path.move(to: CGPoint(x: w * 0.34, y: h * 0.90))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.90))
        
        path.move(to: CGPoint(x: w * 0.58, y: h * 0.46))
        path.addQuadCurve(to: CGPoint(x: w * 0.60, y: h * 0.70), controlPoint: CGPoint(x: w * 0.62, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.90))
        
        path.move(to: CGPoint(x: w * 0.58, y: h * 0.90))
        path.addLine(to: CGPoint(x: w * 0.66, y: h * 0.90))
    }
    
    private func drawImpactStance(path: UIBezierPath, w: CGFloat, h: CGFloat) {
        // Similar to address but with rotation through impact
        drawAddressStance(path: path, w: w, h: h)
    }
    
    private func drawFollowThroughStance(path: UIBezierPath, w: CGFloat, h: CGFloat) {
        // Head
        let headCenter = CGPoint(x: w * 0.52, y: h * 0.08)
        let headRadius = w * 0.07
        path.addArc(withCenter: headCenter, radius: headRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)

        // Neck + tilted torso
        path.move(to: CGPoint(x: w * 0.52, y: h * 0.15))
        path.addQuadCurve(to: CGPoint(x: w * 0.54, y: h * 0.42), controlPoint: CGPoint(x: w * 0.60, y: h * 0.28))

        // Shoulders + arms wrapped (finish pose)
        let leftShoulder = CGPoint(x: w * 0.40, y: h * 0.18)
        let rightShoulder = CGPoint(x: w * 0.64, y: h * 0.20)
        let hands = CGPoint(x: w * 0.35, y: h * 0.12)

        path.move(to: leftShoulder)
        path.addLine(to: rightShoulder)
        path.move(to: rightShoulder)
        path.addQuadCurve(to: hands, controlPoint: CGPoint(x: w * 0.62, y: h * 0.08))
        path.move(to: leftShoulder)
        path.addQuadCurve(to: hands, controlPoint: CGPoint(x: w * 0.34, y: h * 0.10))

        // Hips rotated
        let leftHip = CGPoint(x: w * 0.45, y: h * 0.46)
        let rightHip = CGPoint(x: w * 0.58, y: h * 0.46)
        path.move(to: leftHip)
        path.addLine(to: rightHip)

        // Lead leg straight, trail leg on toe
        let leadKnee = CGPoint(x: w * 0.46, y: h * 0.68)
        let leadAnkle = CGPoint(x: w * 0.46, y: h * 0.92)
        path.move(to: leftHip)
        path.addQuadCurve(to: leadAnkle, controlPoint: leadKnee)
        path.move(to: CGPoint(x: leadAnkle.x - w * 0.04, y: leadAnkle.y))
        path.addLine(to: CGPoint(x: leadAnkle.x + w * 0.05, y: leadAnkle.y))

        let trailKnee = CGPoint(x: w * 0.64, y: h * 0.68)
        let trailAnkle = CGPoint(x: w * 0.66, y: h * 0.88)
        path.move(to: rightHip)
        path.addQuadCurve(to: trailAnkle, controlPoint: trailKnee)
        path.move(to: CGPoint(x: trailAnkle.x - w * 0.02, y: trailAnkle.y))
        path.addLine(to: CGPoint(x: trailAnkle.x + w * 0.05, y: trailAnkle.y - w * 0.02))

        // Club wrapped around shoulders
        path.move(to: hands)
        path.addQuadCurve(to: CGPoint(x: w * 0.25, y: h * 0.28), controlPoint: CGPoint(x: w * 0.20, y: h * 0.10))
    }
}

// MARK: - Alignment Overlay View
/// Complete alignment overlay with dual silhouettes and trajectory arrow
final class AlignmentOverlayView: UIView {
    
    private let leftSilhouette = GolferSilhouetteView()
    private let rightSilhouette = GolferSilhouetteView()
    private let trajectoryArrow = CAShapeLayer()
    private let instructionLabel = UILabel()
    private let ballZoneIndicator = UIView()
    
    /// Normalized ball position (0-1) based on ball zone indicator
    var normalizedBallPosition: CGPoint {
        // Infer ball position from silhouettes (between their feet) rather than a separate marker
        let leftBall = leftSilhouette.convert(
            CGPoint(
                x: leftSilhouette.bounds.width * leftSilhouette.ballPosition.x,
                y: leftSilhouette.bounds.height * leftSilhouette.ballPosition.y
            ),
            to: self
        )
        let rightBall = rightSilhouette.convert(
            CGPoint(
                x: rightSilhouette.bounds.width * rightSilhouette.ballPosition.x,
                y: rightSilhouette.bounds.height * rightSilhouette.ballPosition.y
            ),
            to: self
        )
        
        let center = CGPoint(x: (leftBall.x + rightBall.x) / 2, y: (leftBall.y + rightBall.y) / 2)
        return CGPoint(x: center.x / bounds.width, y: center.y / bounds.height)
    }
    
    /// The calculated region of interest based on silhouette positions
    var detectionROI: CGRect {
        // Anchor ROI on the ball zone indicator so Vision starts exactly where we expect launch
        let ball = normalizedBallPosition

        let roiWidth: CGFloat = 0.55
        let roiHeight: CGFloat = 0.85

        let paddedX = max(0, min(ball.x - roiWidth / 2, 1 - roiWidth))
        // Lift ROI upward from ball while keeping it inside bounds
        let proposedY = max(0, ball.y - 0.5)
        let height = min(roiHeight, 1 - proposedY - 0.02)
        let paddedY = max(0, min(proposedY, 1 - height))

        return CGRect(x: paddedX, y: paddedY, width: roiWidth, height: height)
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
        
        // Left silhouette (address position)
        leftSilhouette.stanceType = .address
        leftSilhouette.silhouetteColor = .white
        leftSilhouette.lineWidth = 2.5
        leftSilhouette.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftSilhouette)
        
        // Right silhouette (follow through)
        rightSilhouette.stanceType = .followThrough
        rightSilhouette.silhouetteColor = .white
        rightSilhouette.lineWidth = 2.5
        rightSilhouette.showBallPosition = false
        rightSilhouette.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rightSilhouette)
        
        // Ball zone indicator (where ball should be)
        ballZoneIndicator.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        ballZoneIndicator.layer.borderColor = UIColor.white.cgColor
        ballZoneIndicator.layer.borderWidth = 2
        ballZoneIndicator.layer.cornerRadius = 20
        ballZoneIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ballZoneIndicator)
        
        // Trajectory arrow
        trajectoryArrow.strokeColor = UIColor.white.cgColor
        trajectoryArrow.fillColor = UIColor.clear.cgColor
        trajectoryArrow.lineWidth = 3
        trajectoryArrow.lineCap = .round
        layer.addSublayer(trajectoryArrow)
        
        // Instruction label
        instructionLabel.text = "Position yourself within the guides"
        instructionLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(instructionLabel)
        
        NSLayoutConstraint.activate([
            // Left silhouette - left side
            leftSilhouette.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            leftSilhouette.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 40),
            leftSilhouette.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.35),
            leftSilhouette.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.6),
            
            // Right silhouette - right side
            rightSilhouette.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            rightSilhouette.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 40),
            rightSilhouette.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.35),
            rightSilhouette.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.6),
            
            // Ball zone between silhouettes at bottom
            ballZoneIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            ballZoneIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -60),
            ballZoneIndicator.widthAnchor.constraint(equalToConstant: 40),
            ballZoneIndicator.heightAnchor.constraint(equalToConstant: 40),
            
            // Instruction at top
            instructionLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            instructionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateTrajectoryArrow()
    }
    
    private func updateTrajectoryArrow() {
        let path = UIBezierPath()
        
        // Arrow starts from ball zone and goes up
        let startPoint = CGPoint(x: bounds.midX, y: bounds.height - 80)
        let endPoint = CGPoint(x: bounds.midX, y: bounds.height * 0.25)
        
        path.move(to: startPoint)
        path.addLine(to: endPoint)
        
        // Arrow head
        let arrowSize: CGFloat = 15
        path.move(to: CGPoint(x: endPoint.x - arrowSize, y: endPoint.y + arrowSize))
        path.addLine(to: endPoint)
        path.addLine(to: CGPoint(x: endPoint.x + arrowSize, y: endPoint.y + arrowSize))
        
        trajectoryArrow.path = path.cgPath
        
        // Animate the arrow
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = 1.5
        animation.repeatCount = .infinity
        trajectoryArrow.add(animation, forKey: "arrowAnimation")
    }
    
    func setAligned(_ aligned: Bool) {
        UIView.animate(withDuration: 0.3) {
            self.leftSilhouette.silhouetteColor = aligned ? UIColor.systemGreen : .white
            self.rightSilhouette.silhouetteColor = aligned ? UIColor.systemGreen : .white
            self.trajectoryArrow.strokeColor = aligned ? UIColor.systemGreen.cgColor : UIColor.white.cgColor
            self.ballZoneIndicator.layer.borderColor = aligned ? UIColor.systemGreen.cgColor : UIColor.white.cgColor
        }
        
        instructionLabel.text = aligned ? "✓ Aligned! Tap Record when ready" : "Position yourself within the guides"
    }
}
