import UIKit
import AVFoundation
import CoreGraphics

/// Result of alignment - includes ROI and ball position
struct AlignmentResult {
    let roi: CGRect
    let ballPosition: CGPoint  // Normalized 0-1, where the ball is
}

// MARK: - Premium Alignment View Controller
/// SmoothSwing-style alignment with dual golfer silhouettes
/// 
/// NEW: Automatic lock-in with body pose detection!
/// - Uses VNDetectHumanBodyPoseRequest to detect golfer stance
/// - Automatically locks in when golfer is properly positioned
/// - Haptic feedback provides progress and confirmation
final class PremiumAlignmentViewController: UIViewController {
    
    // MARK: - Properties
    private let previewView: PreviewView
    private let onLockIn: (AlignmentResult) -> Void
    
    // UI Elements
    private let alignmentOverlay = AlignmentOverlayView()
    private let instructionCard = GlassmorphicView()
    private let lockButton = PremiumButton(style: .primary)
    private let titleLabel = UILabel()
    private let instructionLabel = UILabel()
    private let skipButton = UIButton(type: .system)
    private let alignmentStatusLabel = UILabel()
    private let alignmentProgressView = UIProgressView(progressViewStyle: .default)
    
    // Gradient overlay for better visibility
    private let topGradient = CAGradientLayer()
    private let bottomGradient = CAGradientLayer()
    
    // Animation state
    private var hasAnimatedIn = false
    
    // Automatic alignment detection (iOS 14+)
    private var alignmentDetector: GolferAlignmentDetector?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private let detectionQueue = DispatchQueue(label: "com.tracer.alignment", qos: .userInteractive)
    
    // MARK: - Init
    init(session: AVCaptureSession, onLockIn: @escaping (AlignmentResult) -> Void) {
        self.previewView = PreviewView()
        self.previewView.videoPreviewLayer.session = session
        self.previewView.videoPreviewLayer.videoGravity = .resizeAspectFill
        self.onLockIn = onLockIn
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        
        // Setup automatic alignment detection
        if #available(iOS 14.0, *) {
            setupAlignmentDetection(session: session)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        // Remove video output when done
        if let output = videoDataOutput,
           let session = previewView.videoPreviewLayer.session {
            session.removeOutput(output)
        }
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGradients()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasAnimatedIn {
            hasAnimatedIn = true
            animateIn()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        topGradient.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 180)
        bottomGradient.frame = CGRect(x: 0, y: view.bounds.height - 280, width: view.bounds.width, height: 280)
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black
        
        // Preview
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        
        // Alignment overlay with dual silhouettes
        alignmentOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(alignmentOverlay)
        
        // Instruction card
        instructionCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionCard)
        
        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "⛳ Align Your Shot"
        titleLabel.font = ShotTracerDesign.Typography.headline()
        titleLabel.textColor = ShotTracerDesign.Colors.textPrimary
        titleLabel.textAlignment = .center
        instructionCard.addSubview(titleLabel)
        
        // Instructions
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.text = "Position yourself between the silhouettes.\nHold still - auto-lock when aligned!"
        instructionLabel.font = ShotTracerDesign.Typography.body()
        instructionLabel.textColor = ShotTracerDesign.Colors.textSecondary
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        instructionCard.addSubview(instructionLabel)
        
        // Alignment status
        alignmentStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        alignmentStatusLabel.text = "Looking for golfer..."
        alignmentStatusLabel.font = ShotTracerDesign.Typography.captionMedium()
        alignmentStatusLabel.textColor = .gray
        alignmentStatusLabel.textAlignment = .center
        instructionCard.addSubview(alignmentStatusLabel)
        
        // Alignment progress
        alignmentProgressView.translatesAutoresizingMaskIntoConstraints = false
        alignmentProgressView.progress = 0
        alignmentProgressView.tintColor = ShotTracerDesign.Colors.mastersGreen
        alignmentProgressView.trackTintColor = UIColor.white.withAlphaComponent(0.2)
        instructionCard.addSubview(alignmentProgressView)
        
        // Lock button
        lockButton.translatesAutoresizingMaskIntoConstraints = false
        lockButton.setTitle("🎯 Lock In Position", for: .normal)
        lockButton.addTarget(self, action: #selector(lockTapped), for: .touchUpInside)
        view.addSubview(lockButton)
        
        // Skip button
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        skipButton.setTitle("Skip Alignment", for: .normal)
        skipButton.titleLabel?.font = ShotTracerDesign.Typography.captionMedium()
        skipButton.setTitleColor(ShotTracerDesign.Colors.textSecondary, for: .normal)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        view.addSubview(skipButton)
        
        // Layout
        NSLayoutConstraint.activate([
            // Preview fills entire view
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Alignment overlay
            alignmentOverlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 120),
            alignmentOverlay.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -120),
            alignmentOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            alignmentOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Instruction card
            instructionCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            instructionCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            instructionCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: ShotTracerDesign.Spacing.md),
            
            // Title inside card
            titleLabel.topAnchor.constraint(equalTo: instructionCard.topAnchor, constant: ShotTracerDesign.Spacing.md),
            titleLabel.leadingAnchor.constraint(equalTo: instructionCard.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            titleLabel.trailingAnchor.constraint(equalTo: instructionCard.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            
            // Instructions inside card
            instructionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: ShotTracerDesign.Spacing.sm),
            instructionLabel.leadingAnchor.constraint(equalTo: instructionCard.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            instructionLabel.trailingAnchor.constraint(equalTo: instructionCard.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            
            // Alignment status
            alignmentStatusLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: ShotTracerDesign.Spacing.md),
            alignmentStatusLabel.leadingAnchor.constraint(equalTo: instructionCard.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            alignmentStatusLabel.trailingAnchor.constraint(equalTo: instructionCard.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            
            // Alignment progress bar
            alignmentProgressView.topAnchor.constraint(equalTo: alignmentStatusLabel.bottomAnchor, constant: ShotTracerDesign.Spacing.sm),
            alignmentProgressView.leadingAnchor.constraint(equalTo: instructionCard.leadingAnchor, constant: ShotTracerDesign.Spacing.lg),
            alignmentProgressView.trailingAnchor.constraint(equalTo: instructionCard.trailingAnchor, constant: -ShotTracerDesign.Spacing.lg),
            alignmentProgressView.bottomAnchor.constraint(equalTo: instructionCard.bottomAnchor, constant: -ShotTracerDesign.Spacing.md),
            
            // Lock button
            lockButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lockButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -ShotTracerDesign.Spacing.lg),
            lockButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            
            // Skip button
            skipButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            skipButton.bottomAnchor.constraint(equalTo: lockButton.topAnchor, constant: -ShotTracerDesign.Spacing.md)
        ])
    }
    
    private func setupGradients() {
        // Top gradient for instruction visibility
        topGradient.colors = [
            UIColor.black.withAlphaComponent(0.8).cgColor,
            UIColor.clear.cgColor
        ]
        topGradient.locations = [0, 1]
        view.layer.insertSublayer(topGradient, above: previewView.layer)
        
        // Bottom gradient for button visibility
        bottomGradient.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.85).cgColor
        ]
        bottomGradient.locations = [0, 1]
        view.layer.insertSublayer(bottomGradient, above: previewView.layer)
    }
    
    // MARK: - Automatic Alignment Detection
    
    @available(iOS 14.0, *)
    private func setupAlignmentDetection(session: AVCaptureSession) {
        alignmentDetector = GolferAlignmentDetector()
        alignmentDetector?.debugLogging = false
        
        // Setup callbacks
        alignmentDetector?.onAlignmentChanged = { [weak self] result in
            DispatchQueue.main.async {
                self?.updateAlignmentUI(result: result)
            }
        }
        
        alignmentDetector?.onLockedIn = { [weak self] result in
            DispatchQueue.main.async {
                self?.handleAutoLockIn(result: result)
            }
        }
        
        // Note: We'll reuse frames from the main camera manager
        // The alignment is handled by ShotSessionController calling the detector
    }
    
    @available(iOS 14.0, *)
    private func updateAlignmentUI(result: GolferAlignmentDetector.AlignmentResult) {
        // Update status label
        alignmentStatusLabel.text = result.state.displayName
        alignmentStatusLabel.textColor = result.state.color
        
        // Update progress bar
        UIView.animate(withDuration: 0.15) {
            self.alignmentProgressView.progress = result.alignmentScore
            self.alignmentProgressView.tintColor = result.state.color
        }
        
        // Update overlay colors based on alignment
        let isAligning = result.state == .aligning || result.state == .locked
        alignmentOverlay.setAligned(isAligning)
        
        // Update button state
        if result.state == .locked {
            lockButton.setTitle("✓ Locked In!", for: .normal)
        } else if result.isInGolfStance {
            lockButton.setTitle("🎯 Hold Still...", for: .normal)
        } else {
            lockButton.setTitle("🎯 Lock In Position", for: .normal)
        }
    }
    
    @available(iOS 14.0, *)
    private func handleAutoLockIn(result: GolferAlignmentDetector.AlignmentResult) {
        // Auto-lock successful!
        alignmentOverlay.setAligned(true)
        
        // Flash effect
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = ShotTracerDesign.Colors.mastersGreen
        flash.alpha = 0
        view.addSubview(flash)
        
        UIView.animateKeyframes(withDuration: 0.5, delay: 0, options: []) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.2) {
                flash.alpha = 0.4
            }
            UIView.addKeyframe(withRelativeStartTime: 0.2, relativeDuration: 0.8) {
                flash.alpha = 0
            }
        } completion: { _ in
            flash.removeFromSuperview()
            
            let roi = self.computeVisionROI()
            let ballPos = result.ballPosition ?? self.alignmentOverlay.normalizedBallPosition
            let alignResult = AlignmentResult(roi: roi, ballPosition: ballPos)
            
            print("🔒 AUTO-LOCKED!")
            print("   ROI: \(roi)")
            print("   Ball: (\(String(format: "%.3f", ballPos.x)), \(String(format: "%.3f", ballPos.y)))")
            
            self.animateOut {
                self.onLockIn(alignResult)
                self.dismiss(animated: false)
            }
        }
    }
    
    // MARK: - ROI Computation
    private func computeVisionROI() -> CGRect {
        view.layoutIfNeeded()
        
        // Get ROI from the alignment overlay
        let uiKitROI = alignmentOverlay.detectionROI.clamped
        let visionROI = CoordinateConverter.uiKitToVision(uiKitROI).clamped
        
        // Ensure valid bounds
        return CGRect(
            x: max(0, min(1, visionROI.origin.x)),
            y: max(0, min(1, visionROI.origin.y)),
            width: max(0.1, min(1, visionROI.width)),
            height: max(0.1, min(1, visionROI.height))
        )
    }
    
    // MARK: - Actions
    @objc private func lockTapped() {
        ShotTracerDesign.Haptics.lockIn()
        
        // Mark as aligned
        alignmentOverlay.setAligned(true)
        
        // Flash effect
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = ShotTracerDesign.Colors.accent
        flash.alpha = 0
        view.addSubview(flash)
        
        UIView.animateKeyframes(withDuration: 0.5, delay: 0, options: []) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.2) {
                flash.alpha = 0.4
            }
            UIView.addKeyframe(withRelativeStartTime: 0.2, relativeDuration: 0.8) {
                flash.alpha = 0
            }
        } completion: { _ in
            flash.removeFromSuperview()
            let roi = self.computeVisionROI()
            let ballPos = self.alignmentOverlay.normalizedBallPosition
            let result = AlignmentResult(roi: roi, ballPosition: ballPos)
            
            print("🔒 LOCKED IN!")
            print("   ROI: \(roi)")
            print("   Ball: (\(String(format: "%.3f", ballPos.x)), \(String(format: "%.3f", ballPos.y)))")
            
            self.animateOut {
                self.onLockIn(result)
                self.dismiss(animated: false)
            }
        }
    }
    
    @objc private func skipTapped() {
        ShotTracerDesign.Haptics.buttonTap()
        // Use full frame as ROI, ball at bottom center
        let fullROI = CGRect(x: 0, y: 0, width: 1, height: 1)
        let defaultBallPos = CGPoint(x: 0.5, y: 0.85)  // Bottom center
        let result = AlignmentResult(roi: fullROI, ballPosition: defaultBallPos)
        animateOut {
            self.onLockIn(result)
            self.dismiss(animated: false)
        }
    }
    
    // MARK: - Animations
    private func animateIn() {
        // Initial state
        instructionCard.alpha = 0
        instructionCard.transform = CGAffineTransform(translationX: 0, y: -30)
        
        alignmentOverlay.alpha = 0
        alignmentOverlay.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        
        lockButton.alpha = 0
        lockButton.transform = CGAffineTransform(translationX: 0, y: 30)
        
        skipButton.alpha = 0
        
        // Animate in sequence
        UIView.animate(
            withDuration: ShotTracerDesign.Animation.smooth,
            delay: 0.1,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.5
        ) {
            self.instructionCard.alpha = 1
            self.instructionCard.transform = .identity
        }
        
        UIView.animate(
            withDuration: ShotTracerDesign.Animation.smooth,
            delay: 0.2,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.5
        ) {
            self.alignmentOverlay.alpha = 1
            self.alignmentOverlay.transform = .identity
        }
        
        UIView.animate(
            withDuration: ShotTracerDesign.Animation.smooth,
            delay: 0.4,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.5
        ) {
            self.lockButton.alpha = 1
            self.lockButton.transform = .identity
            self.skipButton.alpha = 1
        }
    }
    
    private func animateOut(completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: ShotTracerDesign.Animation.normal,
            animations: {
                self.view.alpha = 0
                self.alignmentOverlay.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            },
            completion: { _ in
                completion()
            }
        )
    }
}
