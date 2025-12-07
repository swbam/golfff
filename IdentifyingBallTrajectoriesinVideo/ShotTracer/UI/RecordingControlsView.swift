import UIKit

// MARK: - Recording Controls Delegate
protocol RecordingControlsDelegate: AnyObject {
    func recordingControlsDidTapRecord(_ controls: RecordingControlsView)
    func recordingControlsDidTapSettings(_ controls: RecordingControlsView)
    func recordingControlsDidTapRealign(_ controls: RecordingControlsView)
    func recordingControls(_ controls: RecordingControlsView, didSelectColor color: UIColor)
    func recordingControls(_ controls: RecordingControlsView, didSelectStyle style: TracerStyle)
}

// MARK: - Recording Controls View
/// Clean, focused controls for live recording only
final class RecordingControlsView: UIView {
    
    weak var delegate: RecordingControlsDelegate?
    
    // MARK: - State
    var isRecording: Bool = false {
        didSet { updateRecordingState() }
    }
    
    var recordingDuration: TimeInterval = 0 {
        didSet { updateTimerDisplay() }
    }
    
    var selectedColor: UIColor = ShotTracerDesign.Colors.tracerGold {
        didSet { updateColorSelection() }
    }
    
    var selectedStyle: TracerStyle = .neon {
        didSet { updateStyleSelection() }
    }
    
    var statusText: String = "Ready" {
        didSet { statusLabel.text = statusText }
    }
    
    // MARK: - UI Elements
    private let topBar = GlassmorphicView()
    private let statusLabel = UILabel()
    private let timerLabel = UILabel()
    private let settingsButton = UIButton(type: .system)
    
    private let bottomBar = GlassmorphicView()
    private let recordButton = RecordButton()
    private let realignButton = UIButton(type: .system)
    private let colorPickerButton = UIButton(type: .system)
    
    private let colorPicker = TracerColorPicker()
    private var colorPickerBottomConstraint: NSLayoutConstraint?
    private var isColorPickerVisible = false
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - Setup
    private func setupUI() {
        backgroundColor = .clear
        
        setupTopBar()
        setupBottomBar()
        setupColorPicker()
    }
    
    private func setupTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBar)
        
        // Status label
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Ready"
        statusLabel.font = ShotTracerDesign.Typography.captionMedium()
        statusLabel.textColor = ShotTracerDesign.Colors.textSecondary
        topBar.addSubview(statusLabel)
        
        // Timer label
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.text = "00:00"
        timerLabel.font = ShotTracerDesign.Typography.timer()
        timerLabel.textColor = ShotTracerDesign.Colors.textPrimary
        topBar.addSubview(timerLabel)
        
        // Settings button
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        settingsButton.setImage(UIImage(systemName: "gearshape.fill", withConfiguration: config), for: .normal)
        settingsButton.tintColor = ShotTracerDesign.Colors.textSecondary
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        topBar.addSubview(settingsButton)
        
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: ShotTracerDesign.Spacing.sm),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            topBar.heightAnchor.constraint(equalToConstant: 56),
            
            statusLabel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            statusLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            
            timerLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            timerLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            
            settingsButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            settingsButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 44),
            settingsButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBar)
        
        // Realign button (replaces import button)
        realignButton.translatesAutoresizingMaskIntoConstraints = false
        let realignConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        realignButton.setImage(UIImage(systemName: "person.crop.rectangle", withConfiguration: realignConfig), for: .normal)
        realignButton.tintColor = ShotTracerDesign.Colors.textPrimary
        realignButton.backgroundColor = ShotTracerDesign.Colors.surfaceOverlay
        realignButton.layer.cornerRadius = 28
        realignButton.addTarget(self, action: #selector(realignTapped), for: .touchUpInside)
        bottomBar.addSubview(realignButton)
        
        // Record button
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.addTarget(self, action: #selector(recordTapped), for: .touchUpInside)
        bottomBar.addSubview(recordButton)
        
        // Color picker button
        colorPickerButton.translatesAutoresizingMaskIntoConstraints = false
        colorPickerButton.backgroundColor = selectedColor
        colorPickerButton.layer.cornerRadius = 28
        colorPickerButton.layer.borderWidth = 3
        colorPickerButton.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        colorPickerButton.addTarget(self, action: #selector(colorPickerTapped), for: .touchUpInside)
        bottomBar.addSubview(colorPickerButton)
        
        NSLayoutConstraint.activate([
            bottomBar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -ShotTracerDesign.Spacing.md),
            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            bottomBar.heightAnchor.constraint(equalToConstant: 100),
            
            recordButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            recordButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            recordButton.widthAnchor.constraint(equalToConstant: 80),
            recordButton.heightAnchor.constraint(equalToConstant: 80),
            
            realignButton.trailingAnchor.constraint(equalTo: recordButton.leadingAnchor, constant: -ShotTracerDesign.Spacing.xl),
            realignButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            realignButton.widthAnchor.constraint(equalToConstant: 56),
            realignButton.heightAnchor.constraint(equalToConstant: 56),
            
            colorPickerButton.leadingAnchor.constraint(equalTo: recordButton.trailingAnchor, constant: ShotTracerDesign.Spacing.xl),
            colorPickerButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            colorPickerButton.widthAnchor.constraint(equalToConstant: 56),
            colorPickerButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }
    
    private func setupColorPicker() {
        colorPicker.translatesAutoresizingMaskIntoConstraints = false
        colorPicker.delegate = self
        colorPicker.alpha = 0
        addSubview(colorPicker)
        
        colorPickerBottomConstraint = colorPicker.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -ShotTracerDesign.Spacing.md)
        
        NSLayoutConstraint.activate([
            colorPicker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            colorPicker.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            colorPickerBottomConstraint!
        ])
    }
    
    // MARK: - State Updates
    private func updateRecordingState() {
        recordButton.isRecording = isRecording
        
        UIView.animate(withDuration: ShotTracerDesign.Animation.normal) {
            self.realignButton.alpha = self.isRecording ? 0.3 : 1.0
            self.realignButton.isUserInteractionEnabled = !self.isRecording
            
            self.colorPickerButton.alpha = self.isRecording ? 0.3 : 1.0
            self.colorPickerButton.isUserInteractionEnabled = !self.isRecording
            
            self.settingsButton.alpha = self.isRecording ? 0.3 : 1.0
            self.settingsButton.isUserInteractionEnabled = !self.isRecording
        }
        
        // Hide color picker when recording starts
        if isRecording && isColorPickerVisible {
            toggleColorPicker()
        }
        
        // Update status
        statusLabel.text = isRecording ? "Recording" : "Ready"
        statusLabel.textColor = isRecording ? ShotTracerDesign.Colors.tracerRed : ShotTracerDesign.Colors.textSecondary
    }
    
    private func updateTimerDisplay() {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        timerLabel.text = String(format: "%02d:%02d", minutes, seconds)
        
        // Pulse timer when recording
        if isRecording {
            timerLabel.textColor = ShotTracerDesign.Colors.tracerRed
        } else {
            timerLabel.textColor = ShotTracerDesign.Colors.textPrimary
        }
    }
    
    private func updateColorSelection() {
        colorPickerButton.backgroundColor = selectedColor
        colorPicker.selectedColor = selectedColor
    }
    
    private func updateStyleSelection() {
        colorPicker.selectedStyle = selectedStyle
    }
    
    // MARK: - Actions
    @objc private func recordTapped() {
        delegate?.recordingControlsDidTapRecord(self)
    }
    
    @objc private func realignTapped() {
        ShotTracerDesign.Haptics.buttonTap()
        delegate?.recordingControlsDidTapRealign(self)
    }
    
    @objc private func settingsTapped() {
        ShotTracerDesign.Haptics.buttonTap()
        delegate?.recordingControlsDidTapSettings(self)
    }
    
    @objc private func colorPickerTapped() {
        ShotTracerDesign.Haptics.buttonTap()
        toggleColorPicker()
    }
    
    private func toggleColorPicker() {
        isColorPickerVisible.toggle()
        
        if isColorPickerVisible {
            colorPicker.alpha = 0
            colorPicker.transform = CGAffineTransform(translationX: 0, y: 20)
            
            UIView.animate(
                withDuration: ShotTracerDesign.Animation.normal,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.5
            ) {
                self.colorPicker.alpha = 1
                self.colorPicker.transform = .identity
            }
        } else {
            UIView.animate(withDuration: ShotTracerDesign.Animation.quick) {
                self.colorPicker.alpha = 0
                self.colorPicker.transform = CGAffineTransform(translationX: 0, y: 20)
            }
        }
    }
    
    // MARK: - Public Methods
    func resetTimer() {
        recordingDuration = 0
    }
    
    func hideControls(_ hidden: Bool, animated: Bool = true) {
        let duration = animated ? ShotTracerDesign.Animation.normal : 0
        
        UIView.animate(withDuration: duration) {
            self.topBar.alpha = hidden ? 0 : 1
            self.bottomBar.alpha = hidden ? 0 : 1
        }
    }
}

// MARK: - TracerColorPickerDelegate
extension RecordingControlsView: TracerColorPickerDelegate {
    func colorPicker(_ picker: TracerColorPicker, didSelectColor color: UIColor) {
        selectedColor = color
        delegate?.recordingControls(self, didSelectColor: color)
    }
    
    func colorPicker(_ picker: TracerColorPicker, didSelectStyle style: TracerStyle) {
        selectedStyle = style
        delegate?.recordingControls(self, didSelectStyle: style)
    }
}

// MARK: - Record Button
final class RecordButton: UIButton {
    
    var isRecording: Bool = false {
        didSet { animateState() }
    }
    
    private let outerRing = CAShapeLayer()
    private let innerCircle = CAShapeLayer()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupButton()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
    }
    
    private func setupButton() {
        backgroundColor = .clear
        
        // Outer ring
        outerRing.fillColor = UIColor.clear.cgColor
        outerRing.strokeColor = UIColor.white.cgColor
        outerRing.lineWidth = 4
        layer.addSublayer(outerRing)
        
        // Inner circle
        innerCircle.fillColor = ShotTracerDesign.Colors.tracerRed.cgColor
        layer.addSublayer(innerCircle)
        
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outerRadius = min(bounds.width, bounds.height) / 2 - 4
        let innerRadius = outerRadius - 8
        
        outerRing.path = UIBezierPath(
            arcCenter: center,
            radius: outerRadius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        ).cgPath
        
        if isRecording {
            let squareSize = innerRadius * 0.8
            innerCircle.path = UIBezierPath(
                roundedRect: CGRect(
                    x: center.x - squareSize / 2,
                    y: center.y - squareSize / 2,
                    width: squareSize,
                    height: squareSize
                ),
                cornerRadius: 6
            ).cgPath
        } else {
            innerCircle.path = UIBezierPath(
                arcCenter: center,
                radius: innerRadius,
                startAngle: 0,
                endAngle: .pi * 2,
                clockwise: true
            ).cgPath
        }
    }
    
    private func animateState() {
        if isRecording {
            ShotTracerDesign.Haptics.recordStart()
        } else {
            ShotTracerDesign.Haptics.recordStop()
        }
        
        let animation = CASpringAnimation(keyPath: "path")
        animation.damping = 15
        animation.initialVelocity = 10
        animation.duration = animation.settlingDuration
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outerRadius = min(bounds.width, bounds.height) / 2 - 4
        let innerRadius = outerRadius - 8
        
        let targetPath: CGPath
        if isRecording {
            let squareSize = innerRadius * 0.8
            targetPath = UIBezierPath(
                roundedRect: CGRect(
                    x: center.x - squareSize / 2,
                    y: center.y - squareSize / 2,
                    width: squareSize,
                    height: squareSize
                ),
                cornerRadius: 6
            ).cgPath
        } else {
            targetPath = UIBezierPath(
                arcCenter: center,
                radius: innerRadius,
                startAngle: 0,
                endAngle: .pi * 2,
                clockwise: true
            ).cgPath
        }
        
        animation.toValue = targetPath
        innerCircle.add(animation, forKey: "morphing")
        innerCircle.path = targetPath
    }
    
    @objc private func touchDown() {
        UIView.animate(withDuration: ShotTracerDesign.Animation.quick) {
            self.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
    }
    
    @objc private func touchUp() {
        UIView.animate(
            withDuration: ShotTracerDesign.Animation.normal,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.5
        ) {
            self.transform = .identity
        }
    }
}

// MARK: - Tracer Color Picker
protocol TracerColorPickerDelegate: AnyObject {
    func colorPicker(_ picker: TracerColorPicker, didSelectColor color: UIColor)
    func colorPicker(_ picker: TracerColorPicker, didSelectStyle style: TracerStyle)
}

final class TracerColorPicker: GlassmorphicView {
    
    weak var delegate: TracerColorPickerDelegate?
    
    var selectedColor: UIColor = ShotTracerDesign.Colors.tracerRed {
        didSet { updateSelection() }
    }
    
    var selectedStyle: TracerStyle = .neon {
        didSet { updateStyleSelection() }
    }
    
    private let colorStack = UIStackView()
    private let styleStack = UIStackView()
    private let colorLabel = UILabel()
    private let styleLabel = UILabel()
    private var colorButtons: [UIButton] = []
    private var styleButtons: [UIButton] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        // Color section label
        colorLabel.translatesAutoresizingMaskIntoConstraints = false
        colorLabel.text = "COLOR"
        colorLabel.font = ShotTracerDesign.Typography.caption()
        colorLabel.textColor = ShotTracerDesign.Colors.textTertiary
        addSubview(colorLabel)
        
        // Color stack
        colorStack.translatesAutoresizingMaskIntoConstraints = false
        colorStack.axis = .horizontal
        colorStack.spacing = ShotTracerDesign.Spacing.sm
        colorStack.distribution = .fillEqually
        addSubview(colorStack)
        
        // Create color buttons
        for (index, color) in ShotTracerDesign.Colors.allTracerColors.enumerated() {
            let button = createColorButton(color: color, tag: index)
            colorButtons.append(button)
            colorStack.addArrangedSubview(button)
        }
        
        // Style section label
        styleLabel.translatesAutoresizingMaskIntoConstraints = false
        styleLabel.text = "STYLE"
        styleLabel.font = ShotTracerDesign.Typography.caption()
        styleLabel.textColor = ShotTracerDesign.Colors.textTertiary
        addSubview(styleLabel)
        
        // Style stack
        styleStack.translatesAutoresizingMaskIntoConstraints = false
        styleStack.axis = .horizontal
        styleStack.spacing = ShotTracerDesign.Spacing.sm
        styleStack.distribution = .fillEqually
        addSubview(styleStack)
        
        // Create style buttons
        for style in TracerStyle.allCases {
            let button = createStyleButton(style: style)
            styleButtons.append(button)
            styleStack.addArrangedSubview(button)
        }
        
        NSLayoutConstraint.activate([
            colorLabel.topAnchor.constraint(equalTo: topAnchor, constant: ShotTracerDesign.Spacing.md),
            colorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            
            colorStack.topAnchor.constraint(equalTo: colorLabel.bottomAnchor, constant: ShotTracerDesign.Spacing.sm),
            colorStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            colorStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            colorStack.heightAnchor.constraint(equalToConstant: 36),
            
            styleLabel.topAnchor.constraint(equalTo: colorStack.bottomAnchor, constant: ShotTracerDesign.Spacing.md),
            styleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            
            styleStack.topAnchor.constraint(equalTo: styleLabel.bottomAnchor, constant: ShotTracerDesign.Spacing.sm),
            styleStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            styleStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            styleStack.heightAnchor.constraint(equalToConstant: 44),
            styleStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -ShotTracerDesign.Spacing.md)
        ])
        
        updateSelection()
        updateStyleSelection()
    }
    
    private func createColorButton(color: UIColor, tag: Int) -> UIButton {
        let button = UIButton(type: .custom)
        button.backgroundColor = color
        button.layer.cornerRadius = 18
        button.layer.borderWidth = 2
        button.layer.borderColor = UIColor.clear.cgColor
        button.tag = tag
        button.addTarget(self, action: #selector(colorTapped(_:)), for: .touchUpInside)
        
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        
        return button
    }
    
    private func createStyleButton(style: TracerStyle) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = style.rawValue
        
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        button.setImage(UIImage(systemName: style.iconName, withConfiguration: config), for: .normal)
        button.tintColor = ShotTracerDesign.Colors.textSecondary
        button.backgroundColor = ShotTracerDesign.Colors.surfaceOverlay
        button.layer.cornerRadius = ShotTracerDesign.CornerRadius.small
        button.addTarget(self, action: #selector(styleTapped(_:)), for: .touchUpInside)
        
        return button
    }
    
    private func updateSelection() {
        for (index, button) in colorButtons.enumerated() {
            let isSelected = ShotTracerDesign.Colors.allTracerColors[index] == selectedColor
            button.layer.borderColor = isSelected ? UIColor.white.cgColor : UIColor.clear.cgColor
            button.transform = isSelected ? CGAffineTransform(scaleX: 1.1, y: 1.1) : .identity
        }
    }
    
    private func updateStyleSelection() {
        for button in styleButtons {
            let isSelected = TracerStyle(rawValue: button.tag) == selectedStyle
            button.tintColor = isSelected ? ShotTracerDesign.Colors.accent : ShotTracerDesign.Colors.textSecondary
            button.backgroundColor = isSelected ? ShotTracerDesign.Colors.accent.withAlphaComponent(0.2) : ShotTracerDesign.Colors.surfaceOverlay
        }
    }
    
    @objc private func colorTapped(_ sender: UIButton) {
        ShotTracerDesign.Haptics.colorSelect()
        let color = ShotTracerDesign.Colors.allTracerColors[sender.tag]
        selectedColor = color
        delegate?.colorPicker(self, didSelectColor: color)
    }
    
    @objc private func styleTapped(_ sender: UIButton) {
        ShotTracerDesign.Haptics.colorSelect()
        guard let style = TracerStyle(rawValue: sender.tag) else { return }
        selectedStyle = style
        delegate?.colorPicker(self, didSelectStyle: style)
    }
}
