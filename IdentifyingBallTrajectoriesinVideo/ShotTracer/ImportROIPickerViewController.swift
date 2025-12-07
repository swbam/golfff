import UIKit
import AVFoundation

/// Import Result - contains ROI and ball position
struct ImportResult {
    let roi: CGRect?
    let ballPosition: CGPoint
    let trajectory: Trajectory?
}

/// Import flow - User must identify the ball position first
/// This is the KEY to making shot tracing work!
final class ImportROIPickerViewController: UIViewController {
    
    // MARK: - Properties
    private let asset: AVAsset
    private let onComplete: (ImportResult) -> Void
    
    // Ball position from user
    private var ballPosition: CGPoint?
    
    // MARK: - Init
    init(asset: AVAsset, onComplete: @escaping (ImportResult) -> Void) {
        self.asset = asset
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        // Immediately show ball locator
        showBallLocator()
    }
    
    // MARK: - Flow
    private func showBallLocator() {
        let locator = BallLocatorViewController(asset: asset) { [weak self] ballPosition in
            guard let self = self else { return }
            
            print("✅ Ball position selected: (\(String(format: "%.3f", ballPosition.x)), \(String(format: "%.3f", ballPosition.y)))")
            
            self.ballPosition = ballPosition
            self.processVideo(withBallPosition: ballPosition)
        }
        
        // Present after a small delay to ensure view is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.present(locator, animated: true)
        }
    }
    
    private func processVideo(withBallPosition ballPosition: CGPoint) {
        // Show loading indicator
        let loadingVC = createLoadingViewController()
        present(loadingVC, animated: true)
        
        // Process the video with the known ball position
        let processor = AssetTrajectoryProcessor()
        processor.setInitialBallPosition(ballPosition)
        
        processor.process(asset: asset) { [weak self] result in
            guard let self = self else { return }
            
            loadingVC.dismiss(animated: true) {
                switch result {
                case .success(let trajectory):
                    // Create ROI around ball position
                    let roi = CGRect(
                        x: max(0, ballPosition.x - 0.2),
                        y: 0,
                        width: 0.4,
                        height: 1
                    )
                    
                    let importResult = ImportResult(
                        roi: roi,
                        ballPosition: ballPosition,
                        trajectory: trajectory
                    )
                    
                    self.dismiss(animated: true) {
                        self.onComplete(importResult)
                    }
                    
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
    
    private func createLoadingViewController() -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        vc.modalPresentationStyle = .overFullScreen
        vc.modalTransitionStyle = .crossDissolve
        
        let container = UIView()
        container.backgroundColor = UIColor(white: 0.15, alpha: 1)
        container.layer.cornerRadius = 16
        container.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(container)
        
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = UIColor(red: 1, green: 0.84, blue: 0, alpha: 1)
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(spinner)
        
        let label = UILabel()
        label.text = "🏌️ Tracking ball flight..."
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 220),
            container.heightAnchor.constraint(equalToConstant: 120),
            
            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])
        
        return vc
    }
    
    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Could Not Track Ball",
            message: "The ball could not be tracked in this video. Please try:\n\n• Tap on the ball more precisely\n• Use a video with a white ball\n• Ensure the ball is visible against the sky",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
            self?.showBallLocator()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        
        present(alert, animated: true)
    }
}
