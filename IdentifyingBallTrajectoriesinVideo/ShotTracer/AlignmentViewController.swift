import UIKit
import AVFoundation

final class AlignmentViewController: UIViewController {
    private let previewView: PreviewView
    private let onLockIn: (CGRect) -> Void

    private let outlineImageView = UIImageView()
    private let ballMarker = UIView()
    private let lockButton = UIButton(type: .system)

    init(session: AVCaptureSession, onLockIn: @escaping (CGRect) -> Void) {
        self.previewView = PreviewView()
        self.previewView.videoPreviewLayer.session = session
        self.previewView.videoPreviewLayer.videoGravity = .resizeAspect
        self.onLockIn = onLockIn
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPreview()
        setupOverlays()
    }

    private func setupPreview() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupOverlays() {
        outlineImageView.contentMode = .scaleAspectFit
        outlineImageView.alpha = 0.35
        outlineImageView.translatesAutoresizingMaskIntoConstraints = false
        outlineImageView.image = UIImage(systemName: "figure.golf")

        ballMarker.translatesAutoresizingMaskIntoConstraints = false
        ballMarker.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.85)
        ballMarker.layer.cornerRadius = 14

        lockButton.translatesAutoresizingMaskIntoConstraints = false
        lockButton.setTitle("Lock In", for: .normal)
        lockButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        lockButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
        lockButton.setTitleColor(.white, for: .normal)
        lockButton.layer.cornerRadius = 12
        lockButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        lockButton.addTarget(self, action: #selector(lockTapped), for: .touchUpInside)

        view.addSubview(outlineImageView)
        view.addSubview(ballMarker)
        view.addSubview(lockButton)

        NSLayoutConstraint.activate([
            outlineImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            outlineImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),
            outlineImageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6),
            outlineImageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),

            ballMarker.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ballMarker.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80),
            ballMarker.widthAnchor.constraint(equalToConstant: 28),
            ballMarker.heightAnchor.constraint(equalToConstant: 28),

            lockButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lockButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    @objc private func lockTapped() {
        let roi = computeRegionOfInterest()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onLockIn(roi)
        dismiss(animated: true)
    }

    private func computeRegionOfInterest() -> CGRect {
        // Define ROI from the ball marker upwards to leave space for the full flight.
        view.layoutIfNeeded()
        let overlayFrame = view.bounds
        let markerFrame = ballMarker.frame
        let topPadding: CGFloat = 40
        let roiTop = max(0, markerFrame.minY - overlayFrame.height * 0.65)
        let roiRectUIKit = CGRect(
            x: overlayFrame.width * 0.15,
            y: roiTop,
            width: overlayFrame.width * 0.7,
            height: (markerFrame.maxY - roiTop) + topPadding
        ).intersection(overlayFrame)

        let normalizedTopLeft = CGRect(
            x: roiRectUIKit.minX / overlayFrame.width,
            y: roiRectUIKit.minY / overlayFrame.height,
            width: roiRectUIKit.width / overlayFrame.width,
            height: roiRectUIKit.height / overlayFrame.height
        )

        // Convert to Vision coordinates (origin bottom-left)
        return CGRect(
            x: normalizedTopLeft.minX,
            y: 1 - normalizedTopLeft.maxY,
            width: normalizedTopLeft.width,
            height: normalizedTopLeft.height
        )
    }
}
