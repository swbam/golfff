import UIKit

// MARK: - Launch Screen View Controller
// A beautiful animated launch screen for the app

final class LaunchScreenViewController: UIViewController {
    
    private let logoContainer = UIView()
    private let trajectoryLayer = CAShapeLayer()
    private let ballLayer = CAShapeLayer()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateLogo()
    }
    
    private func setupUI() {
        // Background gradient
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = view.bounds
        gradientLayer.colors = [
            ShotTracerDesign.Colors.primaryDark.cgColor,
            ShotTracerDesign.Colors.background.cgColor
        ]
        gradientLayer.locations = [0, 1]
        view.layer.addSublayer(gradientLayer)
        
        // Logo container
        logoContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logoContainer)
        
        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "TRACER"
        titleLabel.font = .systemFont(ofSize: 36, weight: .black)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.alpha = 0
        view.addSubview(titleLabel)
        
        // Subtitle
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Shot Tracking"
        subtitleLabel.font = ShotTracerDesign.Typography.caption()
        subtitleLabel.textColor = ShotTracerDesign.Colors.accent
        subtitleLabel.textAlignment = .center
        subtitleLabel.alpha = 0
        view.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            logoContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            logoContainer.widthAnchor.constraint(equalToConstant: 150),
            logoContainer.heightAnchor.constraint(equalToConstant: 150),
            
            titleLabel.topAnchor.constraint(equalTo: logoContainer.bottomAnchor, constant: ShotTracerDesign.Spacing.lg),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: ShotTracerDesign.Spacing.xs),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        // Setup trajectory path
        trajectoryLayer.strokeColor = ShotTracerDesign.Colors.accent.cgColor
        trajectoryLayer.fillColor = UIColor.clear.cgColor
        trajectoryLayer.lineWidth = 4
        trajectoryLayer.lineCap = .round
        trajectoryLayer.strokeEnd = 0
        logoContainer.layer.addSublayer(trajectoryLayer)
        
        // Setup ball
        ballLayer.fillColor = UIColor.white.cgColor
        ballLayer.opacity = 0
        logoContainer.layer.addSublayer(ballLayer)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if let gradientLayer = view.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = view.bounds
        }
        
        drawTrajectory()
    }
    
    private func drawTrajectory() {
        let bounds = logoContainer.bounds
        let path = UIBezierPath()
        
        // Parabolic trajectory (golf ball flight path)
        let startPoint = CGPoint(x: bounds.width * 0.1, y: bounds.height * 0.9)
        let endPoint = CGPoint(x: bounds.width * 0.9, y: bounds.height * 0.7)
        let peakPoint = CGPoint(x: bounds.width * 0.5, y: bounds.height * 0.15)
        
        path.move(to: startPoint)
        path.addQuadCurve(to: endPoint, controlPoint: peakPoint)
        
        trajectoryLayer.path = path.cgPath
        
        // Ball at end of trajectory
        ballLayer.path = UIBezierPath(
            arcCenter: endPoint,
            radius: 8,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        ).cgPath
    }
    
    private func animateLogo() {
        // Animate trajectory drawing
        let trajectoryAnim = CABasicAnimation(keyPath: "strokeEnd")
        trajectoryAnim.fromValue = 0
        trajectoryAnim.toValue = 1
        trajectoryAnim.duration = 1.2
        trajectoryAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        trajectoryAnim.fillMode = .forwards
        trajectoryAnim.isRemovedOnCompletion = false
        trajectoryLayer.add(trajectoryAnim, forKey: "stroke")
        
        // Animate ball appearance
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let ballAnim = CABasicAnimation(keyPath: "opacity")
            ballAnim.fromValue = 0
            ballAnim.toValue = 1
            ballAnim.duration = 0.3
            ballAnim.fillMode = .forwards
            ballAnim.isRemovedOnCompletion = false
            self.ballLayer.add(ballAnim, forKey: "fadeIn")
            
            // Pulse effect
            let pulse = CASpringAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.5
            pulse.toValue = 1.0
            pulse.damping = 8
            pulse.initialVelocity = 10
            pulse.duration = pulse.settlingDuration
            self.ballLayer.add(pulse, forKey: "pulse")
        }
        
        // Animate text
        UIView.animate(
            withDuration: 0.5,
            delay: 0.8,
            options: [.curveEaseOut]
        ) {
            self.titleLabel.alpha = 1
        }
        
        UIView.animate(
            withDuration: 0.5,
            delay: 1.0,
            options: [.curveEaseOut]
        ) {
            self.subtitleLabel.alpha = 1
        }
    }
}

