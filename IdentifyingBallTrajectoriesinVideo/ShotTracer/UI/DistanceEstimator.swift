import UIKit
import CoreMedia
import Vision

// MARK: - Distance Estimation Engine
// Physics-based golf ball distance estimation using trajectory data
// No ML models required - uses projectile motion physics

/// Estimated shot metrics
struct ShotMetrics {
    let currentDistance: Double      // Current estimated distance in yards
    let estimatedCarry: Double       // Projected total carry distance
    let ballSpeed: Double            // Estimated ball speed in mph
    let launchAngle: Double          // Estimated launch angle in degrees
    let apex: Double                 // Maximum height in feet
    let hangTime: Double             // Time in air in seconds
    let curve: Double                // Left/right curve in feet (+ = right, - = left)
    
    /// Progress through the shot (0.0 - 1.0)
    var progress: Double {
        guard estimatedCarry > 0 else { return 0 }
        return min(1.0, currentDistance / estimatedCarry)
    }
    
    static let zero = ShotMetrics(
        currentDistance: 0, estimatedCarry: 0, ballSpeed: 0,
        launchAngle: 0, apex: 0, hangTime: 0, curve: 0
    )
}

/// Calibration profile for more accurate estimates
struct CalibrationProfile {
    var typicalDriveDistance: Double = 250    // yards
    var typical7IronDistance: Double = 150    // yards
    var cameraHeightFeet: Double = 4          // approximate camera height
    var cameraDistanceFromBall: Double = 15   // feet behind the ball
    
    static let `default` = CalibrationProfile()
    
    /// Save calibration to UserDefaults
    func save() {
        UserDefaults.standard.set(typicalDriveDistance, forKey: "cal_drive")
        UserDefaults.standard.set(typical7IronDistance, forKey: "cal_7iron")
        UserDefaults.standard.set(cameraHeightFeet, forKey: "cal_cam_height")
        UserDefaults.standard.set(cameraDistanceFromBall, forKey: "cal_cam_dist")
    }
    
    /// Load calibration from UserDefaults
    static func load() -> CalibrationProfile {
        var profile = CalibrationProfile()
        if let drive = UserDefaults.standard.object(forKey: "cal_drive") as? Double {
            profile.typicalDriveDistance = drive
        }
        if let iron = UserDefaults.standard.object(forKey: "cal_7iron") as? Double {
            profile.typical7IronDistance = iron
        }
        if let height = UserDefaults.standard.object(forKey: "cal_cam_height") as? Double {
            profile.cameraHeightFeet = height
        }
        if let dist = UserDefaults.standard.object(forKey: "cal_cam_dist") as? Double {
            profile.cameraDistanceFromBall = dist
        }
        return profile
    }
}

// MARK: - Distance Estimator
final class DistanceEstimator {
    
    // MARK: - Properties
    var calibration: CalibrationProfile
    
    /// Camera frame rate (frames per second)
    var frameRate: Double = 60
    
    /// Video resolution for scaling calculations
    var videoSize: CGSize = CGSize(width: 1920, height: 1080)
    
    // Internal tracking
    private var trajectoryStartTime: CMTime?
    private var previousPoints: [TrajectoryPoint] = []
    private var accumulatedDistance: Double = 0
    private var maxHeight: Double = 0
    private var initialLaunchAngle: Double?
    private var initialBallSpeed: Double?
    private var lateralDeviation: Double = 0
    
    // Physics constants
    private let gravity: Double = 32.174  // ft/s²
    private let yardsPerFoot: Double = 1.0 / 3.0
    private let metersPerYard: Double = 0.9144
    
    // MARK: - Init
    init(calibration: CalibrationProfile = .default) {
        self.calibration = calibration
    }
    
    // MARK: - Public Methods
    
    /// Reset for a new shot
    func reset() {
        trajectoryStartTime = nil
        previousPoints = []
        accumulatedDistance = 0
        maxHeight = 0
        initialLaunchAngle = nil
        initialBallSpeed = nil
        lateralDeviation = 0
    }
    
    /// Update with new trajectory data and get current metrics
    func update(with trajectory: Trajectory) -> ShotMetrics {
        guard !trajectory.points.isEmpty else { return .zero }
        
        let points = trajectory.points
        
        // Set start time on first update
        if trajectoryStartTime == nil {
            trajectoryStartTime = points.first?.time
        }
        
        // Calculate elapsed time
        let hangTime = calculateHangTime(points: points)
        
        // Estimate launch angle from initial trajectory
        let launchAngle = calculateLaunchAngle(points: points)
        if initialLaunchAngle == nil {
            initialLaunchAngle = launchAngle
        }
        
        // Estimate ball speed from pixel velocity
        let ballSpeed = calculateBallSpeed(points: points)
        if initialBallSpeed == nil {
            initialBallSpeed = ballSpeed
        }
        
        // Calculate apex (max height)
        let apex = calculateApex(points: points)
        maxHeight = max(maxHeight, apex)
        
        // Calculate lateral curve
        let curve = calculateCurve(points: points)
        
        // Estimate current distance
        let currentDistance = estimateCurrentDistance(
            hangTime: hangTime,
            launchAngle: initialLaunchAngle ?? launchAngle,
            ballSpeed: initialBallSpeed ?? ballSpeed
        )
        
        // Estimate total carry based on trajectory shape
        let estimatedCarry = estimateTotalCarry(
            hangTime: hangTime,
            launchAngle: initialLaunchAngle ?? launchAngle,
            ballSpeed: initialBallSpeed ?? ballSpeed,
            currentProgress: trajectory.points.count > 5 ? estimateProgress(points: points) : 0.5
        )
        
        previousPoints = points
        
        return ShotMetrics(
            currentDistance: currentDistance,
            estimatedCarry: estimatedCarry,
            ballSpeed: initialBallSpeed ?? ballSpeed,
            launchAngle: initialLaunchAngle ?? launchAngle,
            apex: maxHeight,
            hangTime: hangTime,
            curve: curve
        )
    }
    
    /// Quick estimate from Vision trajectory observation
    func quickEstimate(from observation: VNTrajectoryObservation) -> ShotMetrics {
        let hangTime = observation.timeRange.duration.seconds
        
        // Extract launch angle from equation coefficients
        // Equation: y = ax² + bx + c
        let coefficients = observation.equationCoefficients
        let a = Double(coefficients.x)  // Curvature (negative for downward parabola)
        let b = Double(coefficients.y)  // Initial slope (related to launch angle)
        let c = Double(coefficients.z)  // Y-intercept
        
        // Launch angle approximation from initial slope
        // tan(θ) ≈ b (in normalized coordinates)
        let launchAngleRad = atan(abs(b) * 2) // Scale factor for typical camera view
        let launchAngle = launchAngleRad * 180.0 / .pi
        
        // Estimate ball speed from trajectory curvature and hang time
        let ballSpeed = estimateBallSpeedFromCurvature(a: a, hangTime: hangTime)
        
        // Apex from parabola vertex: x_vertex = -b/(2a), y_vertex = c - b²/(4a)
        let apexNormalized = abs(a) > 0.001 ? c - (b * b) / (4 * a) : 0
        let apex = apexNormalized * calibration.typicalDriveDistance * 3 * 0.15 // Convert to feet approximation
        
        // Estimate distance
        let estimatedCarry = estimateDistanceFromPhysics(
            ballSpeed: ballSpeed,
            launchAngle: launchAngle,
            hangTime: hangTime
        )
        
        // Progress based on hang time (typical driver hang time ~5-6 seconds)
        let progress = min(1.0, hangTime / 6.0)
        let currentDistance = estimatedCarry * progress
        
        return ShotMetrics(
            currentDistance: currentDistance,
            estimatedCarry: estimatedCarry,
            ballSpeed: ballSpeed,
            launchAngle: launchAngle,
            apex: max(apex, 0),
            hangTime: hangTime,
            curve: 0
        )
    }
    
    // MARK: - Private Calculation Methods
    
    private func calculateHangTime(points: [TrajectoryPoint]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        return (last.time - first.time).seconds
    }
    
    private func calculateLaunchAngle(points: [TrajectoryPoint]) -> Double {
        guard points.count >= 3 else { return 15 } // Default assumption
        
        // Use first few points to determine initial angle
        let p1 = points[0].normalized
        let p2 = points[min(2, points.count - 1)].normalized
        
        // Calculate angle from horizontal
        // Note: In Vision coordinates, Y increases upward after our flip
        let dx = p2.x - p1.x
        let dy = p1.y - p2.y  // Flip because ball goes up (lower Y in UIKit coords)
        
        guard dx > 0.001 else { return 15 }
        
        let angleRad = atan(dy / dx)
        var angleDeg = angleRad * 180.0 / .pi
        
        // Clamp to reasonable golf launch angles (5-35 degrees)
        angleDeg = max(5, min(35, angleDeg))
        
        // Scale based on typical camera perspective
        return angleDeg * 2.5  // Perspective adjustment
    }
    
    private func calculateBallSpeed(points: [TrajectoryPoint]) -> Double {
        guard points.count >= 2 else { return 150 } // Default mph assumption
        
        let p1 = points[0]
        let p2 = points[min(3, points.count - 1)]
        
        let dx = Double(p2.normalized.x - p1.normalized.x)
        let dy = Double(p1.normalized.y - p2.normalized.y)
        let dt = (p2.time - p1.time).seconds
        
        guard dt > 0.001 else { return 150 }
        
        // Pixel velocity (normalized)
        let pixelVelocity = sqrt(dx * dx + dy * dy) / dt
        
        // Convert to approximate mph using calibration
        // Assumption: At typical filming distance, normalized velocity relates to actual speed
        // This is calibrated based on typical drive (250 yards, ~170mph ball speed)
        let scaleFactor = calibration.typicalDriveDistance * 0.68 // Empirical factor
        let estimatedMPH = pixelVelocity * scaleFactor
        
        // Clamp to reasonable golf ball speeds (50-200 mph)
        return max(50, min(200, estimatedMPH))
    }
    
    private func calculateApex(points: [TrajectoryPoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        
        // Find minimum Y (highest point since Y increases downward in screen coords)
        let minY = points.map { Double($0.normalized.y) }.min() ?? 0.5
        let startY = Double(points.first?.normalized.y ?? 0.9)
        
        // Height as fraction of screen
        let heightFraction = startY - minY
        
        // Convert to feet based on calibration
        // Typical apex for driver: 80-100 ft
        // Typical apex for iron: 60-90 ft
        let estimatedApex = heightFraction * calibration.typicalDriveDistance * 3 * 0.4
        
        return max(0, estimatedApex)
    }
    
    private func calculateCurve(points: [TrajectoryPoint]) -> Double {
        guard points.count >= 5 else { return 0 }
        
        // Compare X position at start vs end to detect curve
        let startX = Double(points.first!.normalized.x)
        let endX = Double(points.last!.normalized.x)
        
        // Expected X position based on linear trajectory
        let midPoints = points.dropFirst().dropLast()
        let avgMidX = midPoints.map { Double($0.normalized.x) }.reduce(0, +) / Double(midPoints.count)
        
        let expectedMidX = (startX + endX) / 2
        let deviation = avgMidX - expectedMidX
        
        // Convert to feet (positive = right, negative = left for right-handed golfer)
        let curveFeet = deviation * calibration.typicalDriveDistance * 3 * 0.3
        
        return curveFeet
    }
    
    private func estimateProgress(points: [TrajectoryPoint]) -> Double {
        guard points.count >= 3 else { return 0.5 }
        
        // Check if ball is descending (past apex)
        let recentPoints = Array(points.suffix(3))
        let yValues = recentPoints.map { Double($0.normalized.y) }
        
        // If Y is increasing (ball descending), we're past apex
        if yValues.count >= 2 && yValues[1] > yValues[0] {
            return 0.7 // Past apex, estimate 70%+ complete
        }
        
        // Use hang time to estimate progress
        let hangTime = calculateHangTime(points: points)
        let typicalHangTime = 5.0 // seconds for a full shot
        
        return min(0.95, hangTime / typicalHangTime)
    }
    
    private func estimateCurrentDistance(hangTime: Double, launchAngle: Double, ballSpeed: Double) -> Double {
        let progress = min(1.0, hangTime / 5.5) // Assume ~5.5 sec for full flight
        let carry = estimateDistanceFromPhysics(ballSpeed: ballSpeed, launchAngle: launchAngle, hangTime: hangTime)
        return carry * progress
    }
    
    private func estimateTotalCarry(hangTime: Double, launchAngle: Double, ballSpeed: Double, currentProgress: Double) -> Double {
        // If we have enough data, extrapolate
        if currentProgress > 0.3 {
            let current = estimateDistanceFromPhysics(ballSpeed: ballSpeed, launchAngle: launchAngle, hangTime: hangTime)
            return current / currentProgress
        }
        
        // Early in flight - use physics model
        return estimateDistanceFromPhysics(ballSpeed: ballSpeed, launchAngle: launchAngle, hangTime: 5.5)
    }
    
    private func estimateDistanceFromPhysics(ballSpeed: Double, launchAngle: Double, hangTime: Double) -> Double {
        // Golf ball carry distance formula (simplified, accounts for drag)
        // Reference: Typical relationships from golf physics research
        
        let launchRad = launchAngle * .pi / 180.0
        
        // Method 1: From ball speed (most reliable when calibrated)
        // Empirical formula: Carry ≈ ballSpeed * factor * cos(launch) * sin(launch)
        let speedFactor = 2.2  // Empirical factor for golf balls
        let distanceFromSpeed = ballSpeed * speedFactor * sin(2 * launchRad)
        
        // Method 2: From hang time
        // Empirical: ~45 yards per second of hang time (for well-struck shots)
        let distanceFromHangTime = hangTime * 45
        
        // Weight the estimates based on confidence
        // Ball speed is more reliable early, hang time more reliable later
        let speedWeight = max(0.3, 1.0 - hangTime / 6.0)
        let hangTimeWeight = 1.0 - speedWeight
        
        let blendedDistance = distanceFromSpeed * speedWeight + distanceFromHangTime * hangTimeWeight
        
        // Apply calibration adjustment
        let calibrationRatio = calibration.typicalDriveDistance / 250.0
        
        return blendedDistance * calibrationRatio
    }
    
    private func estimateBallSpeedFromCurvature(a: Double, hangTime: Double) -> Double {
        // Higher curvature (more negative a) = higher shot = likely faster
        // Longer hang time = faster ball speed
        
        let curvatureFactor = min(200, abs(a) * 500 + 100)
        let hangTimeFactor = hangTime * 25 + 50
        
        let estimated = (curvatureFactor + hangTimeFactor) / 2
        
        return max(80, min(190, estimated))
    }
}

// MARK: - Live Yardage Display View
final class LiveYardageView: UIView {
    
    // MARK: - UI Elements
    private let distanceLabel = UILabel()
    private let unitLabel = UILabel()
    private let metricsStack = UIStackView()
    
    // Metric labels
    private let ballSpeedLabel = MetricLabel(frame: .zero)
    private let apexLabel = MetricLabel(frame: .zero)
    private let curveLabel = MetricLabel(frame: .zero)
    
    // Animation
    private var displayedDistance: Double = 0
    private var targetDistance: Double = 0
    private var displayLink: CADisplayLink?
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    deinit {
        displayLink?.invalidate()
    }
    
    // MARK: - Setup
    private func setupUI() {
        backgroundColor = .clear
        
        // Main distance container
        let distanceContainer = GlassmorphicView()
        distanceContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(distanceContainer)
        
        // Distance label (big number)
        distanceLabel.translatesAutoresizingMaskIntoConstraints = false
        distanceLabel.text = "0"
        distanceLabel.font = .monospacedDigitSystemFont(ofSize: 56, weight: .bold)
        distanceLabel.textColor = .white
        distanceLabel.textAlignment = .right
        distanceContainer.addSubview(distanceLabel)
        
        // Unit label
        unitLabel.translatesAutoresizingMaskIntoConstraints = false
        unitLabel.text = "YDS"
        unitLabel.font = ShotTracerDesign.Typography.captionMedium()
        unitLabel.textColor = ShotTracerDesign.Colors.accent
        distanceContainer.addSubview(unitLabel)
        
        // Metrics stack
        metricsStack.translatesAutoresizingMaskIntoConstraints = false
        metricsStack.axis = .horizontal
        metricsStack.spacing = ShotTracerDesign.Spacing.md
        metricsStack.distribution = .fillEqually
        addSubview(metricsStack)
        
        // Add metric labels
        ballSpeedLabel.configure(title: "BALL SPEED", unit: "MPH")
        apexLabel.configure(title: "APEX", unit: "FT")
        curveLabel.configure(title: "CURVE", unit: "FT")
        
        [ballSpeedLabel, apexLabel, curveLabel].forEach { metricsStack.addArrangedSubview($0) }
        
        NSLayoutConstraint.activate([
            distanceContainer.topAnchor.constraint(equalTo: topAnchor),
            distanceContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            distanceContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            
            distanceLabel.topAnchor.constraint(equalTo: distanceContainer.topAnchor, constant: ShotTracerDesign.Spacing.sm),
            distanceLabel.trailingAnchor.constraint(equalTo: distanceContainer.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            distanceLabel.bottomAnchor.constraint(equalTo: distanceContainer.bottomAnchor, constant: -ShotTracerDesign.Spacing.sm),
            
            unitLabel.leadingAnchor.constraint(equalTo: distanceLabel.trailingAnchor, constant: 4),
            unitLabel.bottomAnchor.constraint(equalTo: distanceLabel.bottomAnchor, constant: -8),
            
            metricsStack.topAnchor.constraint(equalTo: distanceContainer.bottomAnchor, constant: ShotTracerDesign.Spacing.sm),
            metricsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            metricsStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // Start display link for smooth animations
        displayLink = CADisplayLink(target: self, selector: #selector(updateDisplay))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    // MARK: - Public Methods
    func update(with metrics: ShotMetrics) {
        targetDistance = metrics.currentDistance
        
        // Update metrics with animation
        UIView.animate(withDuration: 0.15) {
            self.ballSpeedLabel.setValue(Int(metrics.ballSpeed))
            self.apexLabel.setValue(Int(metrics.apex))
            
            let curveValue = Int(abs(metrics.curve))
            let curveDirection = metrics.curve >= 0 ? "R" : "L"
            self.curveLabel.setValue(curveValue, suffix: curveDirection)
        }
    }
    
    func reset() {
        targetDistance = 0
        displayedDistance = 0
        distanceLabel.text = "0"
        ballSpeedLabel.setValue(0)
        apexLabel.setValue(0)
        curveLabel.setValue(0)
    }
    
    func setVisible(_ visible: Bool, animated: Bool = true) {
        let duration = animated ? ShotTracerDesign.Animation.normal : 0
        UIView.animate(withDuration: duration) {
            self.alpha = visible ? 1 : 0
        }
    }
    
    // MARK: - Animation
    @objc private func updateDisplay() {
        guard abs(targetDistance - displayedDistance) > 0.5 else {
            displayedDistance = targetDistance
            return
        }
        
        // Smooth interpolation
        let speed: Double = 0.15
        displayedDistance += (targetDistance - displayedDistance) * speed
        
        // Update label
        distanceLabel.text = "\(Int(displayedDistance))"
    }
}

// MARK: - Metric Label
private final class MetricLabel: UIView {
    
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let unitLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .trailing
        addSubview(stack)
        
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = ShotTracerDesign.Colors.textTertiary
        
        let valueStack = UIStackView()
        valueStack.axis = .horizontal
        valueStack.spacing = 2
        valueStack.alignment = .lastBaseline
        
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        valueLabel.textColor = .white
        
        unitLabel.font = .systemFont(ofSize: 10, weight: .medium)
        unitLabel.textColor = ShotTracerDesign.Colors.textSecondary
        
        valueStack.addArrangedSubview(valueLabel)
        valueStack.addArrangedSubview(unitLabel)
        
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(valueStack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor)
        ])
    }
    
    func configure(title: String, unit: String) {
        titleLabel.text = title
        unitLabel.text = unit
        valueLabel.text = "0"
    }
    
    func setValue(_ value: Int, suffix: String? = nil) {
        if let suffix = suffix {
            valueLabel.text = "\(value)\(suffix)"
        } else {
            valueLabel.text = "\(value)"
        }
    }
}

