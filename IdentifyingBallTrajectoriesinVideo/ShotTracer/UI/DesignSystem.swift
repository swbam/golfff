import UIKit

// MARK: - Premium Golf Design System
// A cohesive design language inspired by premium golf equipment and luxury sports apps

enum ShotTracerDesign {
    
    // MARK: - Color Palette
    enum Colors {
        // Primary palette - Deep forest greens
        static let primaryDark = UIColor(hex: "#0D1F17")
        static let primary = UIColor(hex: "#1B4332")
        static let primaryLight = UIColor(hex: "#2D6A4F")
        
        // Accent - Premium gold
        static let accent = UIColor(hex: "#D4AF37")
        static let accentLight = UIColor(hex: "#F4D03F")
        static let accentSubtle = UIColor(hex: "#D4AF37").withAlphaComponent(0.3)
        
        // Background hierarchy
        static let background = UIColor(hex: "#050505")
        static let surface = UIColor(hex: "#121212")
        static let surfaceElevated = UIColor(hex: "#1A1A1A")
        static let surfaceOverlay = UIColor(hex: "#252525")
        
        // Tracer colors - Vibrant and visible against any background
        static let tracerRed = UIColor(hex: "#FF3B30")
        static let tracerOrange = UIColor(hex: "#FF9500")
        static let tracerYellow = UIColor(hex: "#FFCC00")
        static let tracerGreen = UIColor(hex: "#34C759")
        static let tracerCyan = UIColor(hex: "#00D4FF")
        static let tracerBlue = UIColor(hex: "#007AFF")
        static let tracerPurple = UIColor(hex: "#AF52DE")
        static let tracerPink = UIColor(hex: "#FF2D92")
        static let tracerWhite = UIColor(hex: "#FFFFFF")
        
        // Semantic colors
        static let success = UIColor(hex: "#10B981")
        static let warning = UIColor(hex: "#F59E0B")
        static let error = UIColor(hex: "#EF4444")
        static let info = UIColor(hex: "#3B82F6")
        
        // Text hierarchy
        static let textPrimary = UIColor.white
        static let textSecondary = UIColor.white.withAlphaComponent(0.7)
        static let textTertiary = UIColor.white.withAlphaComponent(0.5)
        static let textMuted = UIColor.white.withAlphaComponent(0.3)
        
        // All available tracer colors
        static let allTracerColors: [UIColor] = [
            tracerRed, tracerOrange, tracerYellow, tracerGreen,
            tracerCyan, tracerBlue, tracerPurple, tracerPink, tracerWhite
        ]
    }
    
    // MARK: - Typography
    enum Typography {
        static func displayLarge() -> UIFont {
            return .systemFont(ofSize: 34, weight: .bold)
        }
        
        static func displayMedium() -> UIFont {
            return .systemFont(ofSize: 28, weight: .bold)
        }
        
        static func headline() -> UIFont {
            return .systemFont(ofSize: 22, weight: .semibold)
        }
        
        static func title() -> UIFont {
            return .systemFont(ofSize: 18, weight: .semibold)
        }
        
        static func body() -> UIFont {
            return .systemFont(ofSize: 16, weight: .regular)
        }
        
        static func bodyMedium() -> UIFont {
            return .systemFont(ofSize: 16, weight: .medium)
        }
        
        static func caption() -> UIFont {
            return .systemFont(ofSize: 14, weight: .regular)
        }
        
        static func captionMedium() -> UIFont {
            return .systemFont(ofSize: 14, weight: .medium)
        }
        
        static func timer() -> UIFont {
            return .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        }
        
        static func timerLarge() -> UIFont {
            return .monospacedDigitSystemFont(ofSize: 48, weight: .bold)
        }
        
        static func button() -> UIFont {
            return .systemFont(ofSize: 17, weight: .semibold)
        }
    }
    
    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }
    
    // MARK: - Corner Radius
    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xl: CGFloat = 24
        static let pill: CGFloat = 9999
    }
    
    // MARK: - Shadows
    enum Shadow {
        static func apply(to layer: CALayer, elevation: Elevation) {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOffset = elevation.offset
            layer.shadowRadius = elevation.radius
            layer.shadowOpacity = elevation.opacity
        }
        
        enum Elevation {
            case low, medium, high, glow
            
            var offset: CGSize {
                switch self {
                case .low: return CGSize(width: 0, height: 2)
                case .medium: return CGSize(width: 0, height: 4)
                case .high: return CGSize(width: 0, height: 8)
                case .glow: return .zero
                }
            }
            
            var radius: CGFloat {
                switch self {
                case .low: return 4
                case .medium: return 8
                case .high: return 16
                case .glow: return 20
                }
            }
            
            var opacity: Float {
                switch self {
                case .low: return 0.15
                case .medium: return 0.2
                case .high: return 0.3
                case .glow: return 0.6
                }
            }
        }
    }
    
    // MARK: - Animation Durations
    enum Animation {
        static let quick: TimeInterval = 0.15
        static let normal: TimeInterval = 0.25
        static let smooth: TimeInterval = 0.35
        static let slow: TimeInterval = 0.5
        static let dramatic: TimeInterval = 0.8
        
        static let springDamping: CGFloat = 0.8
        static let springVelocity: CGFloat = 0.5
    }
    
    // MARK: - Haptics
    enum Haptics {
        static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
        
        static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
            UINotificationFeedbackGenerator().notificationOccurred(type)
        }
        
        static func selection() {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        
        // Convenience methods
        static func lockIn() {
            notification(.success)
        }
        
        static func recordStart() {
            impact(.heavy)
        }
        
        static func recordStop() {
            impact(.medium)
        }
        
        static func buttonTap() {
            impact(.light)
        }
        
        static func colorSelect() {
            selection()
        }
    }
}

// MARK: - UIColor Hex Extension
extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
    
    func lighter(by percentage: CGFloat = 0.2) -> UIColor {
        return self.adjust(by: abs(percentage))
    }
    
    func darker(by percentage: CGFloat = 0.2) -> UIColor {
        return self.adjust(by: -abs(percentage))
    }
    
    private func adjust(by percentage: CGFloat) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(
            red: min(red + percentage, 1.0),
            green: min(green + percentage, 1.0),
            blue: min(blue + percentage, 1.0),
            alpha: alpha
        )
    }
}

// MARK: - Glassmorphism View
class GlassmorphicView: UIView {
    private let blurView: UIVisualEffectView
    private let tintLayer = CALayer()
    
    override init(frame: CGRect) {
        blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .clear
        
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        
        tintLayer.backgroundColor = UIColor.white.withAlphaComponent(0.05).cgColor
        layer.addSublayer(tintLayer)
        
        layer.cornerRadius = ShotTracerDesign.CornerRadius.large
        layer.masksToBounds = true
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        tintLayer.frame = bounds
        blurView.layer.cornerRadius = layer.cornerRadius
    }
}

// MARK: - Premium Button
class PremiumButton: UIButton {
    
    enum Style {
        case primary      // Gold accent, full
        case secondary    // Outlined
        case ghost        // Transparent
        case danger       // Red
    }
    
    private let style: Style
    private var gradientLayer: CAGradientLayer?
    
    init(style: Style = .primary) {
        self.style = style
        super.init(frame: .zero)
        setupButton()
    }
    
    required init?(coder: NSCoder) {
        self.style = .primary
        super.init(coder: coder)
        setupButton()
    }
    
    private func setupButton() {
        titleLabel?.font = ShotTracerDesign.Typography.button()
        layer.cornerRadius = ShotTracerDesign.CornerRadius.medium
        
        contentEdgeInsets = UIEdgeInsets(
            top: ShotTracerDesign.Spacing.md,
            left: ShotTracerDesign.Spacing.lg,
            bottom: ShotTracerDesign.Spacing.md,
            right: ShotTracerDesign.Spacing.lg
        )
        
        switch style {
        case .primary:
            backgroundColor = ShotTracerDesign.Colors.accent
            setTitleColor(ShotTracerDesign.Colors.primaryDark, for: .normal)
            setTitleColor(ShotTracerDesign.Colors.primaryDark.withAlphaComponent(0.7), for: .highlighted)
            
        case .secondary:
            backgroundColor = .clear
            layer.borderWidth = 2
            layer.borderColor = ShotTracerDesign.Colors.accent.cgColor
            setTitleColor(ShotTracerDesign.Colors.accent, for: .normal)
            setTitleColor(ShotTracerDesign.Colors.accent.withAlphaComponent(0.7), for: .highlighted)
            
        case .ghost:
            backgroundColor = UIColor.white.withAlphaComponent(0.1)
            setTitleColor(.white, for: .normal)
            setTitleColor(UIColor.white.withAlphaComponent(0.7), for: .highlighted)
            
        case .danger:
            backgroundColor = ShotTracerDesign.Colors.error
            setTitleColor(.white, for: .normal)
            setTitleColor(UIColor.white.withAlphaComponent(0.7), for: .highlighted)
        }
        
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    
    @objc private func touchDown() {
        ShotTracerDesign.Haptics.buttonTap()
        UIView.animate(withDuration: ShotTracerDesign.Animation.quick) {
            self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            self.alpha = 0.9
        }
    }
    
    @objc private func touchUp() {
        UIView.animate(
            withDuration: ShotTracerDesign.Animation.normal,
            delay: 0,
            usingSpringWithDamping: ShotTracerDesign.Animation.springDamping,
            initialSpringVelocity: ShotTracerDesign.Animation.springVelocity
        ) {
            self.transform = .identity
            self.alpha = 1
        }
    }
}

// MARK: - Pulsing View (for indicators)
class PulsingView: UIView {
    
    private let pulseLayer = CAShapeLayer()
    private let innerLayer = CAShapeLayer()
    var pulseColor: UIColor = ShotTracerDesign.Colors.accent {
        didSet {
            updateColors()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    private func setupLayers() {
        backgroundColor = .clear
        
        layer.addSublayer(pulseLayer)
        layer.addSublayer(innerLayer)
        
        updateColors()
    }
    
    private func updateColors() {
        pulseLayer.fillColor = pulseColor.withAlphaComponent(0.3).cgColor
        innerLayer.fillColor = pulseColor.cgColor
        innerLayer.strokeColor = UIColor.white.withAlphaComponent(0.5).cgColor
        innerLayer.lineWidth = 2
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2
        
        pulseLayer.path = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        innerLayer.path = UIBezierPath(arcCenter: center, radius: radius * 0.6, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
    }
    
    func startPulsing() {
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.8
        scaleAnimation.toValue = 1.4
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0.8
        opacityAnimation.toValue = 0
        
        let group = CAAnimationGroup()
        group.animations = [scaleAnimation, opacityAnimation]
        group.duration = 1.5
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        pulseLayer.add(group, forKey: "pulse")
    }
    
    func stopPulsing() {
        pulseLayer.removeAnimation(forKey: "pulse")
    }
}

