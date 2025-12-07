import UIKit
import AVFoundation
import PhotosUI

final class ShotViewController: UIViewController {
    private let cameraManager = CameraManager()
    private let trajectoryDetector = TrajectoryDetector()
    private lazy var sessionController = ShotSessionController(cameraManager: cameraManager, trajectoryDetector: trajectoryDetector)

    private let overlayView = TrajectoryOverlayView()
    private let timerLabel = UILabel()
    private let recordButton = UIButton(type: .custom)
    private let colorStack = UIStackView()
    private let importButton = UIButton(type: .system)
    private var timer: Timer?
    private var recordingStart: Date?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        sessionController.delegate = self
        layoutUI()
        sessionController.startSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentAlignmentIfNeeded()
    }

    private func layoutUI() {
        let previewView = cameraManager.previewView
        previewView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        colorStack.translatesAutoresizingMaskIntoConstraints = false
        importButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(previewView)
        view.addSubview(overlayView)
        view.addSubview(timerLabel)
        view.addSubview(recordButton)
        view.addSubview(colorStack)
        view.addSubview(importButton)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            overlayView.topAnchor.constraint(equalTo: previewView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),

            timerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            timerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            recordButton.widthAnchor.constraint(equalToConstant: 84),
            recordButton.heightAnchor.constraint(equalToConstant: 84),

            colorStack.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            colorStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            importButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            importButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        ])

        timerLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        timerLabel.textColor = .white
        timerLabel.text = "00:00"

        recordButton.layer.cornerRadius = 42
        recordButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
        recordButton.layer.borderWidth = 4
        recordButton.layer.borderColor = UIColor.white.cgColor
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)

        colorStack.axis = .vertical
        colorStack.spacing = 10

        let colors: [UIColor] = [.systemRed, .systemGreen, .systemOrange, .cyan, .white]
        colors.forEach { color in
            let button = UIButton(type: .custom)
            button.backgroundColor = color
            button.layer.cornerRadius = 16
            button.layer.borderWidth = 2
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            button.addAction(UIAction { [weak self] _ in
                self?.sessionController.setTracerColor(color)
            }, for: .touchUpInside)
            colorStack.addArrangedSubview(button)
        }

        importButton.setTitle("Import", for: .normal)
        importButton.setTitleColor(.white, for: .normal)
        importButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        importButton.layer.cornerRadius = 10
        importButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
    }

    private func presentAlignmentIfNeeded() {
        guard case .ready = sessionController.state else { return }
        sessionController.state = .aligning
        if let session = cameraManager.previewView.videoPreviewLayer.session {
            let alignVC = AlignmentViewController(session: session) { [weak self] roi in
                self?.sessionController.setRegionOfInterest(roi)
                self?.sessionController.state = .ready
            }
            present(alignVC, animated: true)
        } else {
            sessionController.state = .ready
        }
    }

    @objc private func toggleRecording() {
        switch sessionController.state {
        case .ready:
            sessionController.startRecording()
            startTimer()
            animateRecordingUI(isRecording: true)
        case .recording:
            sessionController.stopRecording()
            stopTimer()
            animateRecordingUI(isRecording: false)
        default:
            break
        }
    }

    private func animateRecordingUI(isRecording: Bool) {
        let color = isRecording ? UIColor.systemGray6 : UIColor.systemRed.withAlphaComponent(0.9)
        UIView.animate(withDuration: 0.25) {
            self.recordButton.backgroundColor = color
            self.recordButton.transform = isRecording ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
        }
    }

    @objc private func importTapped() {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func startTimer() {
        recordingStart = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let start = self?.recordingStart else { return }
            let elapsed = Date().timeIntervalSince(start)
            let minutes = Int(elapsed) / 60
            let seconds = Int(elapsed) % 60
            self?.timerLabel.text = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func showShareSheet(url: URL) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(activity, animated: true)
    }
}

extension ShotViewController: ShotSessionControllerDelegate {
    func shotSession(_ controller: ShotSessionController, didUpdateState state: ShotState) {
        switch state {
        case .recording:
            overlayView.clear()
        case .exporting:
            timerLabel.text = "Exporting…"
        case .importing:
            timerLabel.text = "Importing…"
        default:
            break
        }
    }

    func shotSession(_ controller: ShotSessionController, didUpdateTrajectory trajectory: Trajectory) {
        let points = trajectory.points.map { $0.normalized }
        overlayView.update(with: points, color: controller.tracerColor)
    }
    
    func shotSession(_ controller: ShotSessionController, didUpdateMetrics metrics: ShotMetrics) {
        // Legacy controller doesn't display metrics
    }

    func shotSession(_ controller: ShotSessionController, didFinishExportedVideo url: URL) {
        stopTimer()
        timerLabel.text = "Ready"
        overlayView.clear()
        let review = ReviewViewController(videoURL: url)
        present(review, animated: true)
        sessionController.state = .ready
    }

    func shotSession(_ controller: ShotSessionController, didFail error: Error) {
        stopTimer()
        let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension ShotViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.hasItemConformingToTypeIdentifier("public.movie") else { return }
        provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { [weak self] url, error in
            guard let self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.showError(error)
                }
                return
            }
            guard let url = url else { return }
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("import_\(UUID().uuidString).mov")
            do {
                try FileManager.default.copyItem(at: url, to: tempURL)
                let asset = AVAsset(url: tempURL)
                DispatchQueue.main.async {
                    let roiPicker = ImportROIPickerViewController(asset: asset) { [weak self] result in
                        guard let self = self else { return }
                        if let trajectory = result.trajectory, !trajectory.points.isEmpty {
                            self.sessionController.importVideoWithManualTrajectory(from: tempURL, trajectory: trajectory)
                        } else {
                            self.sessionController.importVideo(from: tempURL, roi: result.roi, ballPosition: result.ballPosition)
                        }
                    }
                    self.present(roiPicker, animated: true)
                }
            } catch {
                DispatchQueue.main.async {
                    self.showError(error)
                }
            }
        }
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
