#if DEBUG
import UIKit
import AVFoundation
import AVKit
import PhotosUI
import Vision
import CoreImage

/// Test Mode - Processes video with ENHANCED detection
/// Uses AVAssetReader for reliable frame access + contrast enhancement
final class TestModeViewController: UIViewController {
    
    // MARK: - Vision Detection
    private var trajectoryRequest: VNDetectTrajectoriesRequest!
    private var requestHandler: VNSequenceRequestHandler!
    private let trajectoryStore = TrajectoryStore()
    
    // MARK: - Image Processing
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // MARK: - UI
    private let videoContainerView = UIView()
    private let videoImageView = UIImageView()
    private let trajectoryLayer = CAShapeLayer()
    private let ballMarkerView = UIView()
    private let silhouetteOverlay = AlignmentOverlayView()
    private let statusLabel = UILabel()
    private let progressView = UIProgressView()
    private let logTextView = UITextView()
    
    // MARK: - State
    private var selectedAsset: AVAsset?
    private var ballPosition: CGPoint = CGPoint(x: 0.5, y: 0.85)
    private var overlayScale: CGFloat = 1.0
    private var isProcessing = false
    private var detectedPoints: [CGPoint] = []
    private var allProjectedPoints: [CGPoint] = []
    private var frameCount = 0
    private var detectionCount = 0
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupVision()
        log("🧪 Test Mode Ready")
        log("Load a video with golf ball in flight")
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        trajectoryLayer.frame = videoImageView.bounds
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = ShotTracerDesign.Colors.background
        
        // Navigation
        title = "🧪 Test Mode"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(closeTapped))
        
        // Scroll view
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        
        // Title
        let titleLabel = UILabel()
        titleLabel.text = "Shot Tracer Test"
        titleLabel.font = ShotTracerDesign.Typography.displayLarge()
        titleLabel.textColor = ShotTracerDesign.Colors.textPrimary
        titleLabel.textAlignment = .center
        contentStack.addArrangedSubview(titleLabel)
        
        // Video container
        videoContainerView.backgroundColor = .black
        videoContainerView.layer.cornerRadius = 12
        videoContainerView.clipsToBounds = true
        videoContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(videoContainerView)
        
        // Video image view
        videoImageView.contentMode = .scaleAspectFit
        videoImageView.backgroundColor = .black
        videoImageView.translatesAutoresizingMaskIntoConstraints = false
        videoImageView.isUserInteractionEnabled = true
        videoContainerView.addSubview(videoImageView)
        
        // Silhouette overlay (movable/scalable)
        silhouetteOverlay.frame = videoImageView.bounds
        silhouetteOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        silhouetteOverlay.alpha = 0.55
        silhouetteOverlay.isUserInteractionEnabled = true
        videoImageView.addSubview(silhouetteOverlay)
        
        // Trajectory layer
        trajectoryLayer.strokeColor = ShotTracerDesign.Colors.tracerGold.cgColor
        trajectoryLayer.fillColor = UIColor.clear.cgColor
        trajectoryLayer.lineWidth = 5
        trajectoryLayer.lineCap = .round
        trajectoryLayer.lineJoin = .round
        trajectoryLayer.shadowColor = ShotTracerDesign.Colors.tracerGold.cgColor
        trajectoryLayer.shadowRadius = 10
        trajectoryLayer.shadowOpacity = 1.0
        trajectoryLayer.shadowOffset = .zero
        videoImageView.layer.addSublayer(trajectoryLayer)
        
        // Ball marker
        ballMarkerView.backgroundColor = .red
        ballMarkerView.layer.cornerRadius = 12
        ballMarkerView.layer.borderColor = UIColor.white.cgColor
        ballMarkerView.layer.borderWidth = 3
        ballMarkerView.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        ballMarkerView.isHidden = true
        videoImageView.addSubview(ballMarkerView)
        
        // Tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(videoTapped(_:)))
        videoImageView.addGestureRecognizer(tapGesture)
        
        // Pan/Pinch to position silhouette on the golfer
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        silhouetteOverlay.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        silhouetteOverlay.addGestureRecognizer(pinch)
        
        // Status
        statusLabel.text = "No video loaded"
        statusLabel.font = ShotTracerDesign.Typography.body()
        statusLabel.textColor = ShotTracerDesign.Colors.textSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        contentStack.addArrangedSubview(statusLabel)
        
        // Progress
        progressView.progressTintColor = ShotTracerDesign.Colors.mastersGreen
        progressView.trackTintColor = ShotTracerDesign.Colors.surface
        progressView.isHidden = true
        contentStack.addArrangedSubview(progressView)
        
        // Buttons
        let buttonRow = UIStackView()
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.distribution = .fillEqually
        contentStack.addArrangedSubview(buttonRow)
        
        let loadBtn = createButton(title: "📁 Load", color: ShotTracerDesign.Colors.championshipGold)
        loadBtn.addTarget(self, action: #selector(loadVideoTapped), for: .touchUpInside)
        buttonRow.addArrangedSubview(loadBtn)
        
        let processBtn = createButton(title: "▶️ TRACE", color: ShotTracerDesign.Colors.mastersGreen)
        processBtn.addTarget(self, action: #selector(processTapped), for: .touchUpInside)
        buttonRow.addArrangedSubview(processBtn)
        
        let quickBtn = createButton(title: "⚡ Quick", color: ShotTracerDesign.Colors.surfaceElevated)
        quickBtn.addTarget(self, action: #selector(quickLoadTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(quickBtn)
        
        let lockBtn = createButton(title: "🔒 Lock Silhouette", color: ShotTracerDesign.Colors.tracerRed)
        lockBtn.addTarget(self, action: #selector(lockSilhouetteTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(lockBtn)
        
        // Log
        logTextView.backgroundColor = ShotTracerDesign.Colors.surface
        logTextView.textColor = ShotTracerDesign.Colors.textSecondary
        logTextView.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        logTextView.isEditable = false
        logTextView.layer.cornerRadius = 8
        contentStack.addArrangedSubview(logTextView)
        
        // Constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            
            videoContainerView.heightAnchor.constraint(equalTo: videoContainerView.widthAnchor, multiplier: 16/9),
            
            videoImageView.topAnchor.constraint(equalTo: videoContainerView.topAnchor),
            videoImageView.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor),
            videoImageView.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor),
            videoImageView.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor),
            
            logTextView.heightAnchor.constraint(equalToConstant: 180)
        ])
    }
    
    private func createButton(title: String, color: UIColor) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = ShotTracerDesign.Typography.button()
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = color
        btn.layer.cornerRadius = 12
        btn.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return btn
    }
    
    private func setupVision() {
        requestHandler = VNSequenceRequestHandler()
        trajectoryStore.allowAnyTrajectory = true
        
        // Instant / permissive trajectory detection for test mode
        trajectoryRequest = VNDetectTrajectoriesRequest(
            frameAnalysisSpacing: .zero,
            trajectoryLength: 5
        ) { [weak self] request, error in
            self?.handleTrajectoryResults(request, error: error)
        }
        
        trajectoryRequest.objectMinimumNormalizedRadius = 0.0005
        trajectoryRequest.objectMaximumNormalizedRadius = 0.15
        trajectoryRequest.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
        if #available(iOS 15.0, *) {
            trajectoryRequest.targetFrameTime = CMTime(value: 1, timescale: 240)
        }
    }
    
    // MARK: - Actions
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    @objc private func loadVideoTapped() {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    @objc private func quickLoadTapped() {
        log("⚡ Loading first video...")
        loadFirstVideo { [weak self] asset in
            guard let self = self, let asset = asset else {
                self?.log("❌ No video found")
                return
            }
            self.loadAsset(asset)
        }
    }
    
    @objc private func videoTapped(_ gesture: UITapGestureRecognizer) {
        let loc = gesture.location(in: videoImageView)
        ballPosition = CGPoint(
            x: loc.x / videoImageView.bounds.width,
            y: loc.y / videoImageView.bounds.height
        )
        updateBallMarker()
        log("🎯 Ball: (\(String(format: "%.2f", ballPosition.x)), \(String(format: "%.2f", ballPosition.y)))")
    }
    
    @objc private func processTapped() {
        guard let asset = selectedAsset else {
            showAlert("No Video", "Load a video first")
            return
        }
        guard !isProcessing else { return }
        
        startProcessing(asset: asset)
    }
    
    // MARK: - Video Loading
    
    private func loadAsset(_ asset: AVAsset) {
        selectedAsset = asset
        
        guard let track = asset.tracks(withMediaType: .video).first else {
            log("❌ No video track")
            return
        }
        
        let size = track.naturalSize.applying(track.preferredTransform)
        let duration = asset.duration.seconds
        let fps = track.nominalFrameRate
        
        log("📹 Loaded: \(Int(abs(size.width)))x\(Int(abs(size.height))), \(String(format: "%.1f", duration))s, \(Int(fps))fps")
        statusLabel.text = "Video loaded - Tap TRACE to detect ball"
        
        // Show first frame
        showFirstFrame(of: asset)
        
        ballMarkerView.isHidden = true
        updateBallMarker()
    }
    
    private func showFirstFrame(of asset: AVAsset) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero
        
        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            videoImageView.image = UIImage(cgImage: cgImage)
        } catch {
            log("⚠️ Couldn't get first frame")
        }
    }
    
    // MARK: - Processing with AVAssetReader (RELIABLE!)
    
    private func startProcessing(asset: AVAsset) {
        isProcessing = true
        detectedPoints.removeAll()
        allProjectedPoints.removeAll()
        frameCount = 0
        detectionCount = 0
        trajectoryStore.reset()
        trajectoryStore.allowAnyTrajectory = true
        trajectoryLayer.path = nil
        
        // Reset Vision
        requestHandler = VNSequenceRequestHandler()
        setupVision()
        
        log("▶️ Starting trajectory detection...")
        log("   Using AVAssetReader for reliable frames")
        log("   Applying contrast enhancement")
        
        progressView.isHidden = false
        progressView.progress = 0
        statusLabel.text = "Processing..."
        
        // Process on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.processWithAssetReader(asset: asset)
        }
    }
    
    private func processWithAssetReader(asset: AVAsset) {
        guard let track = asset.tracks(withMediaType: .video).first else {
            finishProcessing(success: false, message: "No video track")
            return
        }
        
        let duration = asset.duration
        let fps = track.nominalFrameRate
        let totalFrames = Int(duration.seconds * Double(fps))
        let orientation = getOrientation(from: track)
        
        log("🎬 Processing \(totalFrames) frames...")
        
        do {
            let reader = try AVAssetReader(asset: asset)
            
            let outputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            trackOutput.alwaysCopiesSampleData = false
            
            guard reader.canAdd(trackOutput) else {
                finishProcessing(success: false, message: "Can't read video")
                return
            }
            
            reader.add(trackOutput)
            reader.startReading()
            
            var lastDisplayedFrame: CGImage?
            
            while reader.status == .reading {
                autoreleasepool {
                    guard let sampleBuffer = trackOutput.copyNextSampleBuffer(),
                          let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        return
                    }
                    
                    let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    frameCount += 1
                    
                    // ENHANCE CONTRAST for better ball detection
                    let enhancedBuffer = enhanceContrast(pixelBuffer)
                    
                    // Process with Vision
                    trajectoryStore.tick()
                    
                    do {
                        try requestHandler.perform([trajectoryRequest], on: enhancedBuffer ?? pixelBuffer, orientation: orientation)
                    } catch {
                        // Silently continue
                    }
                    
                    // Update UI every 15 frames
                    if frameCount % 15 == 0 {
                        let progress = Float(frameCount) / Float(totalFrames)
                        
                        // Create image for display
                        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                        if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                            lastDisplayedFrame = cgImage
                        }
                        
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.progressView.progress = progress
                            self.statusLabel.text = "Frame \(self.frameCount)/\(totalFrames) | Detections: \(self.detectionCount)"
                            
                            if let frame = lastDisplayedFrame {
                                self.videoImageView.image = UIImage(cgImage: frame)
                            }
                            
                            // Update trajectory drawing
                            self.updateTrajectoryDrawing()
                        }
                    }
                }
            }
            
            // Done!
            let success = !allProjectedPoints.isEmpty || !detectedPoints.isEmpty
            let pointCount = max(allProjectedPoints.count, detectedPoints.count)
            finishProcessing(success: success, message: success ? "Found \(pointCount) trajectory points!" : "No trajectory detected")
            
        } catch {
            finishProcessing(success: false, message: "Error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Contrast Enhancement
    
    private func enhanceContrast(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Apply contrast and exposure boost to make ball more visible
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(1.3, forKey: kCIInputContrastKey)      // Boost contrast
        filter.setValue(0.1, forKey: kCIInputBrightnessKey)    // Slight brightness boost
        filter.setValue(1.1, forKey: kCIInputSaturationKey)    // Keep colors vivid
        
        guard let outputImage = filter.outputImage else { return nil }
        
        // Apply unsharp mask to enhance edges (ball edges)
        guard let sharpen = CIFilter(name: "CIUnsharpMask") else { return pixelBuffer }
        sharpen.setValue(outputImage, forKey: kCIInputImageKey)
        sharpen.setValue(1.5, forKey: kCIInputRadiusKey)
        sharpen.setValue(0.8, forKey: kCIInputIntensityKey)
        
        guard let finalImage = sharpen.outputImage else { return nil }
        
        // Render back to pixel buffer
        var newBuffer: CVPixelBuffer?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            nil,
            &newBuffer
        )
        
        if let buffer = newBuffer {
            ciContext.render(finalImage, to: buffer)
            return buffer
        }
        
        return nil
    }
    
    // MARK: - Vision Results
    
    private func handleTrajectoryResults(_ request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNTrajectoryObservation],
              !observations.isEmpty else {
            return
        }
        
        for observation in observations {
            detectionCount += 1
            trajectoryStore.update(with: observation)
            
            // Collect detected points
            for point in observation.detectedPoints {
                let cgPoint = CGPoint(x: CGFloat(point.x), y: CGFloat(1 - point.y))
                detectedPoints.append(cgPoint)
            }
            
            // Collect projected points (the smooth arc!)
            for point in observation.projectedPoints {
                let cgPoint = CGPoint(x: CGFloat(point.x), y: CGFloat(1 - point.y))
                allProjectedPoints.append(cgPoint)
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.log("🎾 DETECTED! Conf: \(String(format: "%.2f", observation.confidence)), \(observation.projectedPoints.count) projected pts")
            }
        }
    }
    
    // MARK: - Drawing
    
    private func updateBallMarker() {
        let x = ballPosition.x * videoImageView.bounds.width - 12
        let y = ballPosition.y * videoImageView.bounds.height - 12
        ballMarkerView.frame = CGRect(x: x, y: y, width: 24, height: 24)
    }
    
    private func updateTrajectoryDrawing() {
        // Use projected points if available, otherwise detected points
        let points = allProjectedPoints.isEmpty ? detectedPoints : allProjectedPoints
        guard points.count >= 2 else { return }
        
        let bounds = videoImageView.bounds
        let path = UIBezierPath()
        
        // Sort by X for left-to-right drawing
        let sorted = points.sorted { $0.x < $1.x }
        
        // Remove duplicates and outliers
        var filtered: [CGPoint] = []
        for point in sorted {
            if filtered.isEmpty || 
               (abs(point.x - filtered.last!.x) > 0.005 || abs(point.y - filtered.last!.y) > 0.005) {
                filtered.append(point)
            }
        }
        
        guard filtered.count >= 2 else { return }
        
        // Convert to view coordinates
        let viewPoints = filtered.map { CGPoint(x: $0.x * bounds.width, y: $0.y * bounds.height) }
        
        // Draw smooth curve
        path.move(to: viewPoints[0])
        
        if viewPoints.count == 2 {
            path.addLine(to: viewPoints[1])
        } else {
            for i in 1..<viewPoints.count {
                let prev = viewPoints[i - 1]
                let curr = viewPoints[i]
                let midPoint = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
                path.addQuadCurve(to: midPoint, controlPoint: prev)
            }
            path.addLine(to: viewPoints.last!)
        }
        
        trajectoryLayer.path = path.cgPath
    }
    
    // MARK: - Gestures (Silhouette positioning)
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: videoImageView)
        silhouetteOverlay.center = CGPoint(
            x: silhouetteOverlay.center.x + translation.x,
            y: silhouetteOverlay.center.y + translation.y
        )
        gesture.setTranslation(.zero, in: videoImageView)
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        overlayScale *= gesture.scale
        silhouetteOverlay.transform = CGAffineTransform(scaleX: overlayScale, y: overlayScale)
        gesture.scale = 1.0
    }
    
    @objc private func lockSilhouetteTapped() {
        ballPosition = silhouetteOverlay.normalizedBallPosition
        updateBallMarker()
        log("🔒 Silhouette locked. Ball: (\(String(format: "%.2f", ballPosition.x)), \(String(format: "%.2f", ballPosition.y)))")
    }
    
    private func finishProcessing(success: Bool, message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.isProcessing = false
            self.progressView.isHidden = true
            
            self.log("═══════════════════════════")
            self.log(success ? "✅ SUCCESS!" : "❌ FAILED")
            self.log("   Frames: \(self.frameCount)")
            self.log("   Detections: \(self.detectionCount)")
            self.log("   Detected pts: \(self.detectedPoints.count)")
            self.log("   Projected pts: \(self.allProjectedPoints.count)")
            self.log("═══════════════════════════")
            
            self.statusLabel.text = message
            self.updateTrajectoryDrawing()
            
            if success {
                self.showAlert("🎯 Trajectory Found!", "Detected \(self.detectionCount) trajectory segments with \(self.allProjectedPoints.count) points.\n\nThe golden line shows the ball's path!")
            } else {
                self.showNoTrajectoryHelp()
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getOrientation(from track: AVAssetTrack) -> CGImagePropertyOrientation {
        let t = track.preferredTransform
        if t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0 { return .right }
        if t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 { return .left }
        if t.a == -1 && t.b == 0 && t.c == 0 && t.d == -1 { return .down }
        return .up
    }
    
    private func loadFirstVideo(completion: @escaping (AVAsset?) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 1
            
            let videos = PHAsset.fetchAssets(with: .video, options: options)
            guard let video = videos.firstObject else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let reqOptions = PHVideoRequestOptions()
            reqOptions.version = .current
            reqOptions.deliveryMode = .highQualityFormat
            
            PHImageManager.default().requestAVAsset(forVideo: video, options: reqOptions) { asset, _, _ in
                DispatchQueue.main.async { completion(asset) }
            }
        }
    }
    
    private func log(_ msg: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let text = "[\(time)] \(msg)\n"
        print(text)
        DispatchQueue.main.async { [weak self] in
            self?.logTextView.text += text
            let range = NSRange(location: max(0, (self?.logTextView.text.count ?? 0) - 1), length: 0)
            self?.logTextView.scrollRangeToVisible(range)
        }
    }
    
    private func showAlert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showNoTrajectoryHelp() {
        let alert = UIAlertController(
            title: "No Trajectory Detected",
            message: """
            Vision didn't detect a ball trajectory.
            
            Requirements:
            • Ball must be VISIBLE in flight
            • Ball should follow a parabolic arc
            • Video needs at least ~5 frames of ball movement
            
            Tips:
            • Try a video with clear ball visibility
            • Ensure good contrast (ball vs background)
            • Ball shouldn't be too small in frame
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension TestModeViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }
        
        log("📁 Loading...")
        
        result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
            guard let url = url else {
                DispatchQueue.main.async { self?.log("❌ Load failed") }
                return
            }
            
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.copyItem(at: url, to: tempURL)
            
            let asset = AVAsset(url: tempURL)
            DispatchQueue.main.async { self?.loadAsset(asset) }
        }
    }
}

#endif
