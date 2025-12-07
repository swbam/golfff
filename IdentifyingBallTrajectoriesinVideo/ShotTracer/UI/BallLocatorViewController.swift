import UIKit
import AVFoundation

/// Ball Locator - User taps on the ball position before tracking
/// This is the KEY to making shot tracing work!
final class BallLocatorViewController: UIViewController {
    
    // MARK: - Properties
    private let asset: AVAsset
    private let onComplete: (CGPoint) -> Void  // Returns normalized ball position
    
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    
    // Ball marker
    private var ballMarkerView: UIView?
    private var selectedBallPosition: CGPoint?
    
    // UI
    private let containerView = UIView()
    private let videoView = UIView()
    private let instructionLabel = UILabel()
    private let hintLabel = UILabel()
    private let confirmButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let scrubberContainer = UIView()
    private let scrubber = UISlider()
    private let timeLabel = UILabel()
    
    private var duration: Double = 0
    
    // MARK: - Init
    init(asset: AVAsset, onComplete: @escaping (CGPoint) -> Void) {
        self.asset = asset
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupPlayer()
        setupGestures()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = videoView.bounds
    }
    
    deinit {
        player?.pause()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black
        
        // Container
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)
        
        // Instruction
        instructionLabel.text = "👆 TAP ON THE GOLF BALL"
        instructionLabel.font = .systemFont(ofSize: 22, weight: .bold)
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(instructionLabel)
        
        // Hint
        hintLabel.text = "Scrub to find the ball before the swing, then tap on it"
        hintLabel.font = .systemFont(ofSize: 14, weight: .regular)
        hintLabel.textColor = .lightGray
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hintLabel)
        
        // Video view
        videoView.backgroundColor = .black
        videoView.layer.cornerRadius = 12
        videoView.clipsToBounds = true
        videoView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(videoView)
        
        // Scrubber container
        scrubberContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(scrubberContainer)
        
        // Scrubber
        scrubber.minimumTrackTintColor = UIColor(red: 1, green: 0.84, blue: 0, alpha: 1)
        scrubber.maximumTrackTintColor = .darkGray
        scrubber.addTarget(self, action: #selector(scrubberChanged), for: .valueChanged)
        scrubber.translatesAutoresizingMaskIntoConstraints = false
        scrubberContainer.addSubview(scrubber)
        
        // Time label
        timeLabel.text = "0:00"
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.textColor = .lightGray
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        scrubberContainer.addSubview(timeLabel)
        
        // Confirm button
        confirmButton.setTitle("✓ Confirm Ball Position", for: .normal)
        confirmButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        confirmButton.backgroundColor = UIColor(red: 1, green: 0.84, blue: 0, alpha: 1)
        confirmButton.setTitleColor(.black, for: .normal)
        confirmButton.layer.cornerRadius = 12
        confirmButton.isEnabled = false
        confirmButton.alpha = 0.5
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(confirmButton)
        
        // Cancel button
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        cancelButton.setTitleColor(.lightGray, for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(cancelButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            containerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            
            instructionLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            instructionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            instructionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            
            hintLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 8),
            hintLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            
            videoView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 20),
            videoView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            videoView.heightAnchor.constraint(equalTo: videoView.widthAnchor, multiplier: 16.0/9.0),
            
            scrubberContainer.topAnchor.constraint(equalTo: videoView.bottomAnchor, constant: 16),
            scrubberContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrubberContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrubberContainer.heightAnchor.constraint(equalToConstant: 30),
            
            scrubber.leadingAnchor.constraint(equalTo: scrubberContainer.leadingAnchor),
            scrubber.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -12),
            scrubber.centerYAnchor.constraint(equalTo: scrubberContainer.centerYAnchor),
            
            timeLabel.trailingAnchor.constraint(equalTo: scrubberContainer.trailingAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: scrubberContainer.centerYAnchor),
            timeLabel.widthAnchor.constraint(equalToConstant: 50),
            
            confirmButton.topAnchor.constraint(equalTo: scrubberContainer.bottomAnchor, constant: 24),
            confirmButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            confirmButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            confirmButton.heightAnchor.constraint(equalToConstant: 54),
            
            cancelButton.topAnchor.constraint(equalTo: confirmButton.bottomAnchor, constant: 12),
            cancelButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
        ])
    }
    
    private func setupPlayer() {
        let playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        player?.isMuted = true
        
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspect
        videoView.layer.addSublayer(playerLayer!)
        
        // Get duration
        duration = asset.duration.seconds
        scrubber.maximumValue = Float(duration)
        
        // Seek to start (where ball should be visible)
        player?.seek(to: .zero)
        updateTimeLabel(0)
    }
    
    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        videoView.addGestureRecognizer(tap)
        videoView.isUserInteractionEnabled = true
    }
    
    // MARK: - Actions
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: videoView)
        
        // Get the actual video rect within the view
        guard let playerLayer = playerLayer else { return }
        let videoRect = playerLayer.videoRect
        
        // Check if tap is within video bounds
        guard videoRect.contains(location) else { return }
        
        // Calculate normalized position within video
        let normalizedX = (location.x - videoRect.minX) / videoRect.width
        let normalizedY = (location.y - videoRect.minY) / videoRect.height
        
        selectedBallPosition = CGPoint(x: normalizedX, y: normalizedY)
        
        // Update/create ball marker
        if ballMarkerView == nil {
            ballMarkerView = createBallMarker()
            videoView.addSubview(ballMarkerView!)
        }
        
        // Position the marker
        ballMarkerView?.center = location
        
        // Animate the marker
        ballMarkerView?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
            self.ballMarkerView?.transform = .identity
        }
        
        // Enable confirm button
        confirmButton.isEnabled = true
        confirmButton.alpha = 1.0
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        print("🎯 Ball tapped at: (\(String(format: "%.3f", normalizedX)), \(String(format: "%.3f", normalizedY)))")
    }
    
    private func createBallMarker() -> UIView {
        let size: CGFloat = 50
        let marker = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        
        // Outer ring
        let outerRing = UIView(frame: marker.bounds)
        outerRing.backgroundColor = .clear
        outerRing.layer.borderColor = UIColor.white.cgColor
        outerRing.layer.borderWidth = 3
        outerRing.layer.cornerRadius = size / 2
        marker.addSubview(outerRing)
        
        // Inner ring
        let innerSize: CGFloat = 20
        let innerRing = UIView(frame: CGRect(
            x: (size - innerSize) / 2,
            y: (size - innerSize) / 2,
            width: innerSize,
            height: innerSize
        ))
        innerRing.backgroundColor = UIColor(red: 1, green: 0.84, blue: 0, alpha: 0.8)
        innerRing.layer.cornerRadius = innerSize / 2
        marker.addSubview(innerRing)
        
        // Crosshairs
        let hLine = UIView(frame: CGRect(x: 0, y: size/2 - 1, width: size, height: 2))
        hLine.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        marker.addSubview(hLine)
        
        let vLine = UIView(frame: CGRect(x: size/2 - 1, y: 0, width: 2, height: size))
        vLine.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        marker.addSubview(vLine)
        
        // Pulse animation
        let pulseLayer = CAShapeLayer()
        pulseLayer.path = UIBezierPath(ovalIn: marker.bounds).cgPath
        pulseLayer.fillColor = UIColor.clear.cgColor
        pulseLayer.strokeColor = UIColor.white.cgColor
        pulseLayer.lineWidth = 2
        marker.layer.insertSublayer(pulseLayer, at: 0)
        
        let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
        pulseAnimation.fromValue = 1.0
        pulseAnimation.toValue = 1.5
        pulseAnimation.duration = 1.0
        pulseAnimation.repeatCount = .infinity
        pulseAnimation.autoreverses = false
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 1.0
        opacityAnimation.toValue = 0.0
        opacityAnimation.duration = 1.0
        opacityAnimation.repeatCount = .infinity
        
        pulseLayer.add(pulseAnimation, forKey: "pulse")
        pulseLayer.add(opacityAnimation, forKey: "opacity")
        
        return marker
    }
    
    @objc private func scrubberChanged() {
        let time = CMTime(seconds: Double(scrubber.value), preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        updateTimeLabel(Double(scrubber.value))
    }
    
    private func updateTimeLabel(_ seconds: Double) {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        timeLabel.text = String(format: "%d:%02d", mins, secs)
    }
    
    @objc private func confirmTapped() {
        guard let position = selectedBallPosition else { return }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        dismiss(animated: true) {
            self.onComplete(position)
        }
    }
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}

