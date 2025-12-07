import UIKit

// MARK: - Masters-Inspired Premium Golf Design System
// A prestigious, timeless design language inspired by The Masters Tournament
// Designed for premium subscription app with professional, elegant aesthetics

enum ShotTracerDesign {
    
    // MARK: - Brand Identity
    enum Brand {
        static let appName = "TRACER"
        static let tagline = "Professional Shot Tracking"
    }
    
    // MARK: - Color Palette (Masters-Inspired)
    enum Colors {
        
        // ═══════════════════════════════════════════════════════════════
        // PRIMARY: Masters Green (Pantone 342)
        // The iconic Augusta National green - prestigious and timeless
        // ═══════════════════════════════════════════════════════════════
        static let mastersGreen = UIColor(hex: "#006747")
        static let mastersGreenLight = UIColor(hex: "#008763")
        static let mastersGreenDark = UIColor(hex: "#004D35")
        
        // For UI elements that need the green
        static let primary = mastersGreen
        static let primaryLight = mastersGreenLight
        static let primaryDark = mastersGreenDark
        
        // ═══════════════════════════════════════════════════════════════
        // ACCENT: Championship Gold
        // Selective use - reserved for premium elements and highlights
        // ═══════════════════════════════════════════════════════════════
        static let championshipGold = UIColor(hex: "#C9A227")  // Muted, elegant gold
        static let brightGold = UIColor(hex: "#D4AF37")
        static let paleGold = UIColor(hex: "#E8D48B")
        
        static let accent = championshipGold
        static let accentLight = brightGold
        static let accentSubtle = championshipGold.withAlphaComponent(0.15)
        
        // ═══════════════════════════════════════════════════════════════
        // BACKGROUND: Deep, Rich Blacks
        // Clean, modern dark theme that lets content shine
        // ═══════════════════════════════════════════════════════════════
        static let background = UIColor(hex: "#0A0A0A")
        static let surface = UIColor(hex: "#141414")
        static let surfaceElevated = UIColor(hex: "#1C1C1C")
        static let surfaceOverlay = UIColor(hex: "#242424")
        static let surfaceCard = UIColor(hex: "#1A1A1A")
        
        // ═══════════════════════════════════════════════════════════════
        // TRACER COLORS
        // Vibrant, visible against any background
        // Gold is the premium default (Masters-inspired)
        // ═══════════════════════════════════════════════════════════════
        static let tracerGold = championshipGold      // Premium default
        static let tracerRed = UIColor(hex: "#E63946")
        static let tracerOrange = UIColor(hex: "#F77F00")
        static let tracerYellow = UIColor(hex: "#FCBF49")
        static let tracerGreen = UIColor(hex: "#2A9D8F")
        static let tracerCyan = UIColor(hex: "#48CAE4")
        static let tracerBlue = UIColor(hex: "#4361EE")
        static let tracerPurple = UIColor(hex: "#7B2CBF")
        static let tracerPink = UIColor(hex: "#F72585")
        static let tracerWhite = UIColor(hex: "#FFFFFF")
        
        // All available tracer colors (gold first as default)
        static let allTracerColors: [UIColor] = [
            tracerGold, tracerRed, tracerOrange, tracerYellow, tracerGreen,
            tracerCyan, tracerBlue, tracerPurple, tracerPink, tracerWhite
        ]
        
        // ═══════════════════════════════════════════════════════════════
        // TEXT HIERARCHY
        // Clean, readable text with proper contrast
        // ═══════════════════════════════════════════════════════════════
        static let textPrimary = UIColor.white
        static let textSecondary = UIColor(hex: "#B0B0B0")
        static let textTertiary = UIColor(hex: "#787878")
        static let textMuted = UIColor(hex: "#505050")
        static let textOnGreen = UIColor.white
        static let textOnGold = UIColor(hex: "#1A1A1A")
        
        // ═══════════════════════════════════════════════════════════════
        // SEMANTIC COLORS
        // Status and feedback colors
        // ═══════════════════════════════════════════════════════════════
        static let success = UIColor(hex: "#2A9D8F")
        static let warning = UIColor(hex: "#E9C46A")
        static let error = UIColor(hex: "#E63946")
        static let info = UIColor(hex: "#4361EE")
        
        // Recording indicator
        static let recording = UIColor(hex: "#E63946")
        
        // Pro/Premium badge
        static let proBadge = championshipGold
    }
    
    // MARK: - Typography (Elegant, Clean)
    enum Typography {
        
        // Display - For large headlines, hero text
        static func displayLarge() -> UIFont {
            // Use Georgia for that classic, prestigious feel
            if let georgia = UIFont(name: "Georgia-Bold", size: 34) {
                return georgia
            }
            return .systemFont(ofSize: 34, weight: .bold)
        }
        
        static func displayMedium() -> UIFont {
            if let georgia = UIFont(name: "Georgia-Bold", size: 28) {
                return georgia
            }
            return .systemFont(ofSize: 28, weight: .bold)
        }
        
        // Headlines - Section headers
        static func headline() -> UIFont {
            if let georgia = UIFont(name: "Georgia-Bold", size: 22) {
                return georgia
            }
            return .systemFont(ofSize: 22, weight: .semibold)
        }
        
        static func headlineLight() -> UIFont {
            if let georgia = UIFont(name: "Georgia", size: 22) {
                return georgia
            }
            return .systemFont(ofSize: 22, weight: .regular)
        }
        
        // Titles - Card titles, navigation
        static func title() -> UIFont {
            return .systemFont(ofSize: 18, weight: .semibold)
        }
        
        static func titleMedium() -> UIFont {
            return .systemFont(ofSize: 18, weight: .medium)
        }
        
        // Body - Main content
        static func body() -> UIFont {
            return .systemFont(ofSize: 16, weight: .regular)
        }
        
        static func bodyMedium() -> UIFont {
            return .systemFont(ofSize: 16, weight: .medium)
        }
        
        static func bodySemibold() -> UIFont {
            return .systemFont(ofSize: 16, weight: .semibold)
        }
        
        // Captions - Secondary info, labels
        static func caption() -> UIFont {
            return .systemFont(ofSize: 13, weight: .regular)
        }
        
        static func captionMedium() -> UIFont {
            return .systemFont(ofSize: 13, weight: .medium)
        }
        
        static func captionBold() -> UIFont {
            return .systemFont(ofSize: 13, weight: .bold)
        }
        
        // Small - Fine print, badges
        static func small() -> UIFont {
            return .systemFont(ofSize: 11, weight: .medium)
        }
        
        // Timer displays
        static func timer() -> UIFont {
            return .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        }
        
        static func timerLarge() -> UIFont {
            return .monospacedDigitSystemFont(ofSize: 48, weight: .medium)
        }
        
        // Metrics/Stats display
        static func metric() -> UIFont {
            return .monospacedDigitSystemFont(ofSize: 32, weight: .bold)
        }
        
        static func metricUnit() -> UIFont {
            return .systemFont(ofSize: 14, weight: .medium)
        }
        
        // Buttons
        static func button() -> UIFont {
            return .systemFont(ofSize: 16, weight: .semibold)
        }
        
        static func buttonSmall() -> UIFont {
            return .systemFont(ofSize: 14, weight: .semibold)
        }
        
        // Letter spacing for premium feel
        static func letterSpacing(for text: String, spacing: CGFloat = 1.5) -> NSAttributedString {
            return NSAttributedString(
                string: text,
                attributes: [.kern: spacing]
            )
        }
    }
    
    // MARK: - Spacing System
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
        
        // Specific use cases
        static let cardPadding: CGFloat = 20
        static let screenPadding: CGFloat = 20
        static let sectionSpacing: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    enum CornerRadius {
        static let xs: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        static let pill: CGFloat = 9999
        
        // Specific elements
        static let button: CGFloat = 12
        static let card: CGFloat = 16
        static let modal: CGFloat = 24
    }
    
    // MARK: - Shadows
    enum Shadow {
        static func apply(to layer: CALayer, elevation: Elevation) {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOffset = elevation.offset
            layer.shadowRadius = elevation.radius
            layer.shadowOpacity = elevation.opacity
        }
        
        // Gold glow for premium elements
        static func applyGoldGlow(to layer: CALayer, intensity: CGFloat = 1.0) {
            layer.shadowColor = Colors.championshipGold.cgColor
            layer.shadowOffset = .zero
            layer.shadowRadius = 12 * intensity
            layer.shadowOpacity = Float(0.4 * intensity)
        }
        
        // Green glow for branded elements
        static func applyGreenGlow(to layer: CALayer, intensity: CGFloat = 1.0) {
            layer.shadowColor = Colors.mastersGreen.cgColor
            layer.shadowOffset = .zero
            layer.shadowRadius = 12 * intensity
            layer.shadowOpacity = Float(0.4 * intensity)
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
                case .low: return 0.2
                case .medium: return 0.25
                case .high: return 0.35
                case .glow: return 0.5
                }
            }
        }
    }
    
    // MARK: - Animation
    enum Animation {
        static let instant: TimeInterval = 0.1
        static let quick: TimeInterval = 0.2
        static let normal: TimeInterval = 0.3
        static let smooth: TimeInterval = 0.4
        static let slow: TimeInterval = 0.5
        static let dramatic: TimeInterval = 0.8
        
        static let springDamping: CGFloat = 0.75
        static let springVelocity: CGFloat = 0.5
        
        // Easing
        static let easeOut = CAMediaTimingFunction(name: .easeOut)
        static let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
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
        
        // Branded haptic experiences
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
        
        static func success() {
            notification(.success)
        }
        
        static func error() {
            notification(.error)
        }
    }
    
    // MARK: - Icons (SF Symbols)
    enum Icons {
        static let record = "circle.fill"
        static let stop = "stop.fill"
        static let play = "play.fill"
        static let pause = "pause.fill"
        static let settings = "gearshape.fill"
        static let profile = "person.crop.circle.fill"
        static let pro = "crown.fill"
        static let realign = "person.crop.rectangle"
        static let share = "square.and.arrow.up"
        static let save = "square.and.arrow.down"
        static let trash = "trash.fill"
        static let checkmark = "checkmark"
        static let close = "xmark"
        static let info = "info.circle.fill"
        static let warning = "exclamationmark.triangle.fill"
        static let golf = "figure.golf"
        static let distance = "ruler"
        static let speed = "speedometer"
        static let angle = "angle"
        static let color = "paintpalette.fill"
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
    
    func lighter(by percentage: CGFloat = 0.15) -> UIColor {
        return self.adjust(by: abs(percentage))
    }
    
    func darker(by percentage: CGFloat = 0.15) -> UIColor {
        return self.adjust(by: -abs(percentage))
    }
    
    private func adjust(by percentage: CGFloat) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(
            red: min(max(red + percentage, 0), 1.0),
            green: min(max(green + percentage, 0), 1.0),
            blue: min(max(blue + percentage, 0), 1.0),
            alpha: alpha
        )
    }
}

// MARK: - Glassmorphic View (Premium Glass Effect)
class GlassmorphicView: UIView {
    private let blurView: UIVisualEffectView
    private let tintLayer = CALayer()
    
    var cornerRadius: CGFloat = ShotTracerDesign.CornerRadius.large {
        didSet {
            layer.cornerRadius = cornerRadius
            blurView.layer.cornerRadius = cornerRadius
        }
    }
    
    override init(frame: CGRect) {
        blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
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
        
        tintLayer.backgroundColor = UIColor.white.withAlphaComponent(0.03).cgColor
        layer.addSublayer(tintLayer)
        
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
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
        case primary      // Gold accent, premium action
        case secondary    // Outlined gold
        case mastersGreen // Green background (for key actions)
        case ghost        // Transparent, subtle
        case danger       // Destructive actions
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
        layer.cornerRadius = ShotTracerDesign.CornerRadius.button
        
        contentEdgeInsets = UIEdgeInsets(
            top: ShotTracerDesign.Spacing.md,
            left: ShotTracerDesign.Spacing.lg,
            bottom: ShotTracerDesign.Spacing.md,
            right: ShotTracerDesign.Spacing.lg
        )
        
        switch style {
        case .primary:
            backgroundColor = ShotTracerDesign.Colors.championshipGold
            setTitleColor(ShotTracerDesign.Colors.textOnGold, for: .normal)
            setTitleColor(ShotTracerDesign.Colors.textOnGold.withAlphaComponent(0.7), for: .highlighted)
            ShotTracerDesign.Shadow.applyGoldGlow(to: layer, intensity: 0.3)
            
        case .secondary:
            backgroundColor = .clear
            layer.borderWidth = 1.5
            layer.borderColor = ShotTracerDesign.Colors.championshipGold.cgColor
            setTitleColor(ShotTracerDesign.Colors.championshipGold, for: .normal)
            setTitleColor(ShotTracerDesign.Colors.championshipGold.withAlphaComponent(0.7), for: .highlighted)
            
        case .mastersGreen:
            backgroundColor = ShotTracerDesign.Colors.mastersGreen
            setTitleColor(ShotTracerDesign.Colors.textOnGreen, for: .normal)
            setTitleColor(ShotTracerDesign.Colors.textOnGreen.withAlphaComponent(0.7), for: .highlighted)
            ShotTracerDesign.Shadow.applyGreenGlow(to: layer, intensity: 0.3)
            
        case .ghost:
            backgroundColor = UIColor.white.withAlphaComponent(0.08)
            setTitleColor(.white, for: .normal)
            setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .highlighted)
            
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
            self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
            self.alpha = 0.85
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

// MARK: - Pro Badge View
class ProBadgeView: UIView {
    
    private let label = UILabel()
    private let iconView = UIImageView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = ShotTracerDesign.Colors.championshipGold
        layer.cornerRadius = ShotTracerDesign.CornerRadius.xs
        
        // Icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: ShotTracerDesign.Icons.pro)
        iconView.tintColor = ShotTracerDesign.Colors.textOnGold
        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)
        
        // Label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "PRO"
        label.font = ShotTracerDesign.Typography.small()
        label.textColor = ShotTracerDesign.Colors.textOnGold
        addSubview(label)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 10),
            iconView.heightAnchor.constraint(equalToConstant: 10),
            
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 3),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            heightAnchor.constraint(equalToConstant: 20)
        ])
        
        ShotTracerDesign.Shadow.applyGoldGlow(to: layer, intensity: 0.5)
    }
}

// MARK: - Pulsing View (Recording Indicator)
class PulsingView: UIView {
    
    private let pulseLayer = CAShapeLayer()
    private let innerLayer = CAShapeLayer()
    
    var pulseColor: UIColor = ShotTracerDesign.Colors.recording {
        didSet { updateColors() }
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
        innerLayer.strokeColor = UIColor.white.withAlphaComponent(0.3).cgColor
        innerLayer.lineWidth = 2
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2
        
        pulseLayer.path = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        innerLayer.path = UIBezierPath(arcCenter: center, radius: radius * 0.5, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
    }
    
    func startPulsing() {
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.9
        scaleAnimation.toValue = 1.5
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0.7
        opacityAnimation.toValue = 0
        
        let group = CAAnimationGroup()
        group.animations = [scaleAnimation, opacityAnimation]
        group.duration = 1.2
        group.repeatCount = .infinity
        group.timingFunction = ShotTracerDesign.Animation.easeOut
        
        pulseLayer.add(group, forKey: "pulse")
    }
    
    func stopPulsing() {
        pulseLayer.removeAnimation(forKey: "pulse")
    }
}

// NOTE: LiveYardageView is defined in DistanceEstimator.swift
// NOTE: TracerStyle is defined in GlowingTracerView.swift
