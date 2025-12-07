import UIKit
import AVFoundation
import Photos

// MARK: - Onboarding View Controller
// First-time user experience with permissions and tutorial

final class OnboardingViewController: UIViewController {
    
    // MARK: - Properties
    private var currentPage = 0
    private let totalPages = 4
    
    private let scrollView = UIScrollView()
    private let pageControl = UIPageControl()
    private let continueButton = PremiumButton(style: .primary)
    private let skipButton = UIButton(type: .system)
    
    var onComplete: (() -> Void)?
    
    // Page content
    private let pages: [(icon: String, title: String, subtitle: String, action: OnboardingAction)] = [
        (
            icon: "figure.golf",
            title: "Welcome to Tracer",
            subtitle: "Track your golf shots in real-time with professional-quality shot tracing.",
            action: .none
        ),
        (
            icon: "camera.fill",
            title: "Camera Access",
            subtitle: "We need camera access to record your swing and track the ball flight in real-time.",
            action: .requestCamera
        ),
        (
            icon: "mic.fill",
            title: "Microphone Access",
            subtitle: "Capture the satisfying sound of a pure strike with your traced videos.",
            action: .requestMicrophone
        ),
        (
            icon: "photo.fill",
            title: "Photo Library",
            subtitle: "Save your traced shots and import existing videos to add tracers.",
            action: .requestPhotos
        )
    ]
    
    enum OnboardingAction {
        case none
        case requestCamera
        case requestMicrophone
        case requestPhotos
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupPages()
    }
    
    override var prefersStatusBarHidden: Bool { true }
    
    // MARK: - Setup
    private func setupUI() {
        // Gradient background
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = view.bounds
        gradientLayer.colors = [
            ShotTracerDesign.Colors.primaryDark.cgColor,
            ShotTracerDesign.Colors.background.cgColor
        ]
        gradientLayer.locations = [0, 0.6]
        view.layer.addSublayer(gradientLayer)
        
        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        view.addSubview(scrollView)
        
        // Page control
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.numberOfPages = totalPages
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = ShotTracerDesign.Colors.accent
        pageControl.pageIndicatorTintColor = ShotTracerDesign.Colors.textMuted
        view.addSubview(pageControl)
        
        // Continue button
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.setTitle("Continue", for: .normal)
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        view.addSubview(continueButton)
        
        // Skip button
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        skipButton.setTitle("Skip", for: .normal)
        skipButton.setTitleColor(ShotTracerDesign.Colors.textSecondary, for: .normal)
        skipButton.titleLabel?.font = ShotTracerDesign.Typography.captionMedium()
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        view.addSubview(skipButton)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -20),
            
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -30),
            
            continueButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            continueButton.widthAnchor.constraint(equalToConstant: 200),
            continueButton.heightAnchor.constraint(equalToConstant: 50),
            
            skipButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            skipButton.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -10)
        ])
    }
    
    private func setupPages() {
        var previousPageView: UIView?
        
        for (index, page) in pages.enumerated() {
            let pageView = UIView()
            pageView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(pageView)
            
            // Icon
            let iconView = UIImageView()
            iconView.translatesAutoresizingMaskIntoConstraints = false
            let config = UIImage.SymbolConfiguration(pointSize: 80, weight: .light)
            iconView.image = UIImage(systemName: page.icon, withConfiguration: config)
            iconView.tintColor = ShotTracerDesign.Colors.accent
            iconView.contentMode = .scaleAspectFit
            pageView.addSubview(iconView)
            
            // Title
            let titleLabel = UILabel()
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.text = page.title
            titleLabel.font = ShotTracerDesign.Typography.displayMedium()
            titleLabel.textColor = ShotTracerDesign.Colors.textPrimary
            titleLabel.textAlignment = .center
            pageView.addSubview(titleLabel)
            
            // Subtitle
            let subtitleLabel = UILabel()
            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            subtitleLabel.text = page.subtitle
            subtitleLabel.font = ShotTracerDesign.Typography.body()
            subtitleLabel.textColor = ShotTracerDesign.Colors.textSecondary
            subtitleLabel.textAlignment = .center
            subtitleLabel.numberOfLines = 0
            pageView.addSubview(subtitleLabel)
            
            // Constraints - now pageView is in hierarchy
            NSLayoutConstraint.activate([
                pageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
                pageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
                pageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
                
                iconView.centerXAnchor.constraint(equalTo: pageView.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: pageView.centerYAnchor, constant: -80),
                iconView.widthAnchor.constraint(equalToConstant: 120),
                iconView.heightAnchor.constraint(equalToConstant: 120),
                
                titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 30),
                titleLabel.leadingAnchor.constraint(equalTo: pageView.leadingAnchor, constant: 40),
                titleLabel.trailingAnchor.constraint(equalTo: pageView.trailingAnchor, constant: -40),
                
                subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
                subtitleLabel.leadingAnchor.constraint(equalTo: pageView.leadingAnchor, constant: 40),
                subtitleLabel.trailingAnchor.constraint(equalTo: pageView.trailingAnchor, constant: -40)
            ])
            
            // Horizontal positioning
            if let previous = previousPageView {
                pageView.leadingAnchor.constraint(equalTo: previous.trailingAnchor).isActive = true
            } else {
                pageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor).isActive = true
            }
            
            // Last page anchors to trailing
            if index == totalPages - 1 {
                pageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor).isActive = true
            }
            
            previousPageView = pageView
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.contentSize = CGSize(
            width: view.bounds.width * CGFloat(totalPages),
            height: scrollView.bounds.height
        )
        
        // Update gradient
        if let gradientLayer = view.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = view.bounds
        }
    }
    
    // MARK: - Actions
    @objc private func continueTapped() {
        let page = pages[currentPage]
        
        switch page.action {
        case .none:
            goToNextPage()
            
        case .requestCamera:
            requestCameraPermission { [weak self] granted in
                if granted {
                    self?.goToNextPage()
                } else {
                    self?.showPermissionDeniedAlert(for: "Camera")
                }
            }
            
        case .requestMicrophone:
            requestMicrophonePermission { [weak self] granted in
                if granted {
                    self?.goToNextPage()
                } else {
                    self?.showPermissionDeniedAlert(for: "Microphone")
                }
            }
            
        case .requestPhotos:
            requestPhotosPermission { [weak self] granted in
                // Photos permission is optional, proceed anyway
                self?.completeOnboarding()
            }
        }
    }
    
    @objc private func skipTapped() {
        // Skip to end if they already have permissions
        if hasRequiredPermissions() {
            completeOnboarding()
        } else {
            goToNextPage()
        }
    }
    
    private func goToNextPage() {
        if currentPage < totalPages - 1 {
            currentPage += 1
            let offset = CGPoint(x: CGFloat(currentPage) * view.bounds.width, y: 0)
            scrollView.setContentOffset(offset, animated: true)
            pageControl.currentPage = currentPage
            updateButtonState()
        } else {
            completeOnboarding()
        }
    }
    
    private func updateButtonState() {
        let isLastPage = currentPage == totalPages - 1
        continueButton.setTitle(isLastPage ? "Get Started" : "Continue", for: .normal)
        skipButton.isHidden = isLastPage
    }
    
    private func completeOnboarding() {
        // Save that onboarding is complete
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        
        ShotTracerDesign.Haptics.notification(.success)
        
        // Animate out
        UIView.animate(withDuration: 0.3, animations: {
            self.view.alpha = 0
        }) { _ in
            self.onComplete?()
        }
    }
    
    // MARK: - Permissions
    private func hasRequiredPermissions() -> Bool {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        return cameraStatus == .authorized && micStatus == .authorized
    }
    
    private func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    private func requestPhotosPermission(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                completion(status == .authorized || status == .limited)
            }
        }
    }
    
    private func showPermissionDeniedAlert(for permission: String) {
        let alert = UIAlertController(
            title: "\(permission) Access Denied",
            message: "To use Tracer, please enable \(permission.lowercased()) access in Settings.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    // MARK: - Static Check
    static var needsOnboarding: Bool {
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if hasCompleted { return false }
        
        // Also check if permissions are already granted (user may have reinstalled)
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        return cameraStatus != .authorized || micStatus != .authorized
    }
}

// MARK: - UIScrollViewDelegate
extension OnboardingViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let page = Int(round(scrollView.contentOffset.x / view.bounds.width))
        if page != currentPage && page >= 0 && page < totalPages {
            currentPage = page
            pageControl.currentPage = page
            updateButtonState()
        }
    }
}

