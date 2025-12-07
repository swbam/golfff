import UIKit

// MARK: - Empty State View
// Shows helpful tips when no trajectory is detected

final class EmptyStateView: UIView {
    
    enum State {
        case ready           // Ready to record
        case recording       // Recording, waiting for ball
        case noTrajectory    // Recording ended but no ball detected
        case processing      // Processing/exporting
        case permissionDenied // Camera permission denied
    }
    
    var currentState: State = .ready {
        didSet { updateState() }
    }
    
    var onActionTapped: (() -> Void)?
    
    // UI Elements
    private let containerStack = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = PremiumButton(style: .secondary)
    private let tipsStack = UIStackView()
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - Setup
    private func setupUI() {
        backgroundColor = .clear
        
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        containerStack.axis = .vertical
        containerStack.spacing = ShotTracerDesign.Spacing.md
        containerStack.alignment = .center
        addSubview(containerStack)
        
        // Icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = ShotTracerDesign.Colors.accent
        containerStack.addArrangedSubview(iconView)
        
        // Title
        titleLabel.font = ShotTracerDesign.Typography.headline()
        titleLabel.textColor = ShotTracerDesign.Colors.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        containerStack.addArrangedSubview(titleLabel)
        
        // Subtitle
        subtitleLabel.font = ShotTracerDesign.Typography.body()
        subtitleLabel.textColor = ShotTracerDesign.Colors.textSecondary
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        containerStack.addArrangedSubview(subtitleLabel)
        
        // Tips
        tipsStack.axis = .vertical
        tipsStack.spacing = ShotTracerDesign.Spacing.sm
        tipsStack.alignment = .leading
        containerStack.addArrangedSubview(tipsStack)
        
        // Action button
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        containerStack.addArrangedSubview(actionButton)
        
        NSLayoutConstraint.activate([
            containerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            containerStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            containerStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
            
            iconView.widthAnchor.constraint(equalToConstant: 60),
            iconView.heightAnchor.constraint(equalToConstant: 60)
        ])
        
        updateState()
    }
    
    private func updateState() {
        // Clear tips
        tipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        let config = UIImage.SymbolConfiguration(pointSize: 50, weight: .light)
        
        switch currentState {
        case .ready:
            iconView.image = UIImage(systemName: "figure.golf", withConfiguration: config)
            titleLabel.text = "Ready to Record"
            subtitleLabel.text = "Position your camera and tap record when ready"
            actionButton.isHidden = true
            tipsStack.isHidden = false
            
            addTip("📱 Mount phone on tripod for best results")
            addTip("☀️ Ensure good lighting conditions")
            addTip("🎯 Ball should be visible in frame")
            
        case .recording:
            iconView.image = UIImage(systemName: "waveform", withConfiguration: config)
            titleLabel.text = "Listening for Ball..."
            subtitleLabel.text = "Swing when ready - we'll detect the ball automatically"
            actionButton.isHidden = true
            tipsStack.isHidden = true
            
            // Pulse animation
            startPulseAnimation()
            
        case .noTrajectory:
            iconView.image = UIImage(systemName: "questionmark.circle", withConfiguration: config)
            iconView.tintColor = ShotTracerDesign.Colors.warning
            titleLabel.text = "No Ball Detected"
            subtitleLabel.text = "We couldn't detect the ball trajectory in that recording"
            actionButton.setTitle("Try Again", for: .normal)
            actionButton.isHidden = false
            tipsStack.isHidden = false
            
            addTip("💡 Make sure the ball is visible against the background")
            addTip("🎥 Try filming from a different angle")
            addTip("⚡ Ensure sufficient lighting")
            
        case .processing:
            iconView.image = UIImage(systemName: "gearshape.2", withConfiguration: config)
            titleLabel.text = "Processing..."
            subtitleLabel.text = "Creating your traced video"
            actionButton.isHidden = true
            tipsStack.isHidden = true
            
            startSpinAnimation()
            
        case .permissionDenied:
            iconView.image = UIImage(systemName: "camera.fill", withConfiguration: config)
            iconView.tintColor = ShotTracerDesign.Colors.error
            titleLabel.text = "Camera Access Required"
            subtitleLabel.text = "Tracer needs camera access to record your shots"
            actionButton.setTitle("Open Settings", for: .normal)
            actionButton.isHidden = false
            tipsStack.isHidden = true
        }
    }
    
    private func addTip(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = ShotTracerDesign.Typography.caption()
        label.textColor = ShotTracerDesign.Colors.textTertiary
        label.numberOfLines = 0
        tipsStack.addArrangedSubview(label)
    }
    
    private func startPulseAnimation() {
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.1
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        iconView.layer.add(pulse, forKey: "pulse")
    }
    
    private func startSpinAnimation() {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 2.0
        rotation.repeatCount = .infinity
        iconView.layer.add(rotation, forKey: "spin")
    }
    
    func stopAnimations() {
        iconView.layer.removeAllAnimations()
    }
    
    @objc private func actionTapped() {
        ShotTracerDesign.Haptics.buttonTap()
        
        if currentState == .permissionDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } else {
            onActionTapped?()
        }
    }
}

// MARK: - Camera Permission Denied View Controller
final class CameraPermissionDeniedViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = ShotTracerDesign.Colors.background
        
        let emptyState = EmptyStateView()
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.currentState = .permissionDenied
        view.addSubview(emptyState)
        
        NSLayoutConstraint.activate([
            emptyState.topAnchor.constraint(equalTo: view.topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}



