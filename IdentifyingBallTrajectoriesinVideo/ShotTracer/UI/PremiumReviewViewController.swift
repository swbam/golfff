import UIKit
import AVKit
import Photos

// MARK: - Premium Review View Controller
final class PremiumReviewViewController: UIViewController {
    
    // MARK: - Properties
    private let videoURL: URL
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var timeObserver: Any?
    
    // Playback state
    private var isPlaying = false
    private var currentPlaybackRate: Float = 1.0
    
    // UI Elements
    private let playerContainerView = UIView()
    private let controlsOverlay = UIView()
    private let playPauseButton = UIButton(type: .system)
    private let progressSlider = UISlider()
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    
    private let bottomBar = GlassmorphicView()
    private let shareButton = PremiumButton(style: .primary)
    private let saveButton = PremiumButton(style: .secondary)
    private let replayButton = UIButton(type: .system)
    private let speedButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    
    private let topBar = GlassmorphicView()
    private let titleLabel = UILabel()
    
    // Speed options
    private let speedOptions: [Float] = [0.25, 0.5, 1.0, 2.0]
    private var currentSpeedIndex = 2 // 1.0x
    
    // Gradient overlays
    private let topGradient = CAGradientLayer()
    private let bottomGradient = CAGradientLayer()
    
    // MARK: - Init
    init(videoURL: URL) {
        self.videoURL = videoURL
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupPlayer()
        setupGestures()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateIn()
        player?.play()
        isPlaying = true
        updatePlayPauseButton()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = playerContainerView.bounds
        topGradient.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 120)
        bottomGradient.frame = CGRect(x: 0, y: view.bounds.height - 200, width: view.bounds.width, height: 200)
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = ShotTracerDesign.Colors.background
        
        setupPlayerContainer()
        setupGradients()
        setupTopBar()
        setupBottomBar()
        setupControlsOverlay()
    }
    
    private func setupPlayerContainer() {
        playerContainerView.translatesAutoresizingMaskIntoConstraints = false
        playerContainerView.backgroundColor = .black
        view.addSubview(playerContainerView)
        
        NSLayoutConstraint.activate([
            playerContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            playerContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupGradients() {
        topGradient.colors = [
            UIColor.black.withAlphaComponent(0.8).cgColor,
            UIColor.clear.cgColor
        ]
        view.layer.addSublayer(topGradient)
        
        bottomGradient.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.9).cgColor
        ]
        view.layer.addSublayer(bottomGradient)
    }
    
    private func setupTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        
        // Close button
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let closeConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: closeConfig), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        topBar.addSubview(closeButton)
        
        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Shot Preview"
        titleLabel.font = ShotTracerDesign.Typography.title()
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        topBar.addSubview(titleLabel)
        
        // Speed button
        speedButton.translatesAutoresizingMaskIntoConstraints = false
        speedButton.setTitle("1x", for: .normal)
        speedButton.titleLabel?.font = ShotTracerDesign.Typography.captionMedium()
        speedButton.setTitleColor(.white, for: .normal)
        speedButton.backgroundColor = ShotTracerDesign.Colors.surfaceOverlay
        speedButton.layer.cornerRadius = ShotTracerDesign.CornerRadius.small
        speedButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        speedButton.addTarget(self, action: #selector(speedTapped), for: .touchUpInside)
        topBar.addSubview(speedButton)
        
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: ShotTracerDesign.Spacing.sm),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            topBar.heightAnchor.constraint(equalToConstant: 50),
            
            closeButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            closeButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            
            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            
            speedButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            speedButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor)
        ])
    }
    
    private func setupControlsOverlay() {
        controlsOverlay.translatesAutoresizingMaskIntoConstraints = false
        controlsOverlay.backgroundColor = .clear
        view.addSubview(controlsOverlay)
        
        // Play/Pause button
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        let playConfig = UIImage.SymbolConfiguration(pointSize: 50, weight: .medium)
        playPauseButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: playConfig), for: .normal)
        playPauseButton.tintColor = .white
        playPauseButton.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        playPauseButton.layer.cornerRadius = 40
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        controlsOverlay.addSubview(playPauseButton)
        
        // Progress container
        let progressContainer = UIView()
        progressContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsOverlay.addSubview(progressContainer)
        
        // Current time label
        currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        currentTimeLabel.text = "0:00"
        currentTimeLabel.font = ShotTracerDesign.Typography.caption()
        currentTimeLabel.textColor = .white
        progressContainer.addSubview(currentTimeLabel)
        
        // Progress slider
        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.minimumTrackTintColor = ShotTracerDesign.Colors.accent
        progressSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        progressSlider.setThumbImage(createThumbImage(), for: .normal)
        progressSlider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside])
        progressContainer.addSubview(progressSlider)
        
        // Duration label
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.text = "0:00"
        durationLabel.font = ShotTracerDesign.Typography.caption()
        durationLabel.textColor = .white
        progressContainer.addSubview(durationLabel)
        
        NSLayoutConstraint.activate([
            controlsOverlay.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            controlsOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsOverlay.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            
            playPauseButton.centerXAnchor.constraint(equalTo: controlsOverlay.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: controlsOverlay.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 80),
            playPauseButton.heightAnchor.constraint(equalToConstant: 80),
            
            progressContainer.leadingAnchor.constraint(equalTo: controlsOverlay.leadingAnchor, constant: ShotTracerDesign.Spacing.lg),
            progressContainer.trailingAnchor.constraint(equalTo: controlsOverlay.trailingAnchor, constant: -ShotTracerDesign.Spacing.lg),
            progressContainer.bottomAnchor.constraint(equalTo: controlsOverlay.bottomAnchor, constant: -ShotTracerDesign.Spacing.md),
            progressContainer.heightAnchor.constraint(equalToConstant: 40),
            
            currentTimeLabel.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            currentTimeLabel.centerYAnchor.constraint(equalTo: progressContainer.centerYAnchor),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 45),
            
            progressSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: ShotTracerDesign.Spacing.sm),
            progressSlider.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -ShotTracerDesign.Spacing.sm),
            progressSlider.centerYAnchor.constraint(equalTo: progressContainer.centerYAnchor),
            
            durationLabel.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor),
            durationLabel.centerYAnchor.constraint(equalTo: progressContainer.centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 45)
        ])
    }
    
    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)
        
        // Replay button
        replayButton.translatesAutoresizingMaskIntoConstraints = false
        let replayConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        replayButton.setImage(UIImage(systemName: "arrow.counterclockwise", withConfiguration: replayConfig), for: .normal)
        replayButton.tintColor = .white
        replayButton.backgroundColor = ShotTracerDesign.Colors.surfaceOverlay
        replayButton.layer.cornerRadius = 25
        replayButton.addTarget(self, action: #selector(replayTapped), for: .touchUpInside)
        bottomBar.addSubview(replayButton)
        
        // Share button
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.setTitle("Share", for: .normal)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        bottomBar.addSubview(shareButton)
        
        // Save button
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.setTitle("Save", for: .normal)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        bottomBar.addSubview(saveButton)
        
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -ShotTracerDesign.Spacing.md),
            bottomBar.heightAnchor.constraint(equalToConstant: 80),
            
            replayButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            replayButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            replayButton.widthAnchor.constraint(equalToConstant: 50),
            replayButton.heightAnchor.constraint(equalToConstant: 50),
            
            shareButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            shareButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            shareButton.widthAnchor.constraint(equalToConstant: 100),
            
            saveButton.trailingAnchor.constraint(equalTo: shareButton.leadingAnchor, constant: -ShotTracerDesign.Spacing.md),
            saveButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 100)
        ])
    }
    
    private func setupPlayer() {
        player = AVPlayer(url: videoURL)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspect
        playerContainerView.layer.addSublayer(playerLayer!)
        
        // Observe time
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updateProgress(time: time)
        }
        
        // Update duration
        if let duration = player?.currentItem?.asset.duration {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite {
                durationLabel.text = formatTime(seconds)
                progressSlider.maximumValue = Float(seconds)
            }
        }
        
        // Loop video
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem
        )
    }
    
    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(overlayTapped))
        controlsOverlay.addGestureRecognizer(tap)
    }
    
    // MARK: - Helpers
    private func createThumbImage() -> UIImage {
        let size = CGSize(width: 16, height: 16)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(ShotTracerDesign.Colors.accent.cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func updateProgress(time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return }
        
        currentTimeLabel.text = formatTime(seconds)
        progressSlider.value = Float(seconds)
    }
    
    private func updatePlayPauseButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 50, weight: .medium)
        let imageName = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        ShotTracerDesign.Haptics.buttonTap()
        dismiss(animated: true)
    }
    
    @objc private func playPauseTapped() {
        ShotTracerDesign.Haptics.buttonTap()
        isPlaying.toggle()
        
        if isPlaying {
            player?.play()
            player?.rate = currentPlaybackRate
        } else {
            player?.pause()
        }
        
        updatePlayPauseButton()
    }
    
    @objc private func speedTapped() {
        ShotTracerDesign.Haptics.selection()
        
        currentSpeedIndex = (currentSpeedIndex + 1) % speedOptions.count
        currentPlaybackRate = speedOptions[currentSpeedIndex]
        
        speedButton.setTitle("\(currentPlaybackRate == 1.0 ? "1" : String(format: "%.2g", currentPlaybackRate))x", for: .normal)
        
        if isPlaying {
            player?.rate = currentPlaybackRate
        }
    }
    
    @objc private func replayTapped() {
        ShotTracerDesign.Haptics.buttonTap()
        player?.seek(to: .zero)
        player?.play()
        player?.rate = currentPlaybackRate
        isPlaying = true
        updatePlayPauseButton()
    }
    
    @objc private func shareTapped() {
        ShotTracerDesign.Haptics.buttonTap()
        
        let activityVC = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
        activityVC.excludedActivityTypes = [.addToReadingList, .assignToContact]
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = shareButton
            popover.sourceRect = shareButton.bounds
        }
        
        present(activityVC, animated: true)
    }
    
    @objc private func saveTapped() {
        ShotTracerDesign.Haptics.buttonTap()
        
        saveButton.isEnabled = false
        saveButton.setTitle("Saving...", for: .normal)
        
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self?.showSaveError("Photo library access denied")
                }
                return
            }
            
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self?.videoURL ?? URL(fileURLWithPath: ""))
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.showSaveSuccess()
                    } else {
                        self?.showSaveError(error?.localizedDescription ?? "Unknown error")
                    }
                }
            }
        }
    }
    
    @objc private func sliderValueChanged(_ slider: UISlider) {
        let time = CMTime(seconds: Double(slider.value), preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    @objc private func sliderTouchDown() {
        player?.pause()
    }
    
    @objc private func sliderTouchUp() {
        if isPlaying {
            player?.play()
            player?.rate = currentPlaybackRate
        }
    }
    
    @objc private func overlayTapped() {
        playPauseTapped()
    }
    
    @objc private func playerDidFinish() {
        player?.seek(to: .zero)
        player?.play()
        player?.rate = currentPlaybackRate
    }
    
    private func showSaveSuccess() {
        ShotTracerDesign.Haptics.notification(.success)
        saveButton.setTitle("Saved!", for: .normal)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.saveButton.setTitle("Save", for: .normal)
            self?.saveButton.isEnabled = true
        }
    }
    
    private func showSaveError(_ message: String) {
        ShotTracerDesign.Haptics.notification(.error)
        saveButton.setTitle("Save", for: .normal)
        saveButton.isEnabled = true
        
        let alert = UIAlertController(title: "Save Failed", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Animations
    private func animateIn() {
        topBar.alpha = 0
        topBar.transform = CGAffineTransform(translationX: 0, y: -20)
        
        bottomBar.alpha = 0
        bottomBar.transform = CGAffineTransform(translationX: 0, y: 20)
        
        playPauseButton.alpha = 0
        playPauseButton.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        
        UIView.animate(
            withDuration: ShotTracerDesign.Animation.smooth,
            delay: 0.1,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.5
        ) {
            self.topBar.alpha = 1
            self.topBar.transform = .identity
        }
        
        UIView.animate(
            withDuration: ShotTracerDesign.Animation.smooth,
            delay: 0.15,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.5
        ) {
            self.bottomBar.alpha = 1
            self.bottomBar.transform = .identity
        }
        
        UIView.animate(
            withDuration: ShotTracerDesign.Animation.smooth,
            delay: 0.2,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.5
        ) {
            self.playPauseButton.alpha = 1
            self.playPauseButton.transform = .identity
        }
    }
}



