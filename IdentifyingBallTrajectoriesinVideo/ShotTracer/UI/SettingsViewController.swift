import UIKit

// MARK: - Settings View Controller
// User preferences, calibration, and app settings

final class SettingsViewController: UIViewController {
    
    // MARK: - Properties
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var calibration = CalibrationProfile.load()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSettings()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = ShotTracerDesign.Colors.background
        
        // Navigation bar style
        title = "Settings"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationController?.navigationBar.tintColor = ShotTracerDesign.Colors.accent
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = ShotTracerDesign.Colors.background
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        
        // Close button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(closeTapped)
        )
        
        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        // Content stack
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = ShotTracerDesign.Spacing.lg
        scrollView.addSubview(contentStack)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: ShotTracerDesign.Spacing.md),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -ShotTracerDesign.Spacing.lg)
        ])
        
        // Add sections
        addCalibrationSection()
        addDisplaySection()
        addAboutSection()
        
        // Debug section (only in DEBUG builds)
        #if DEBUG
        addDebugSection()
        #endif
    }
    
    // MARK: - Sections
    private func addCalibrationSection() {
        let section = createSection(title: "DISTANCE CALIBRATION", subtitle: "Improve accuracy by entering your typical distances")
        
        let driveSlider = createSliderRow(
            title: "Driver Distance",
            value: calibration.typicalDriveDistance,
            range: 150...350,
            unit: "yards"
        ) { [weak self] value in
            self?.calibration.typicalDriveDistance = value
            self?.saveCalibration()
        }
        
        let ironSlider = createSliderRow(
            title: "7-Iron Distance",
            value: calibration.typical7IronDistance,
            range: 100...200,
            unit: "yards"
        ) { [weak self] value in
            self?.calibration.typical7IronDistance = value
            self?.saveCalibration()
        }
        
        section.addArrangedSubview(driveSlider)
        section.addArrangedSubview(ironSlider)
        
        contentStack.addArrangedSubview(section)
    }
    
    private func addDisplaySection() {
        let section = createSection(title: "DISPLAY", subtitle: nil)
        
        let yardageToggle = createToggleRow(
            title: "Show Live Yardage",
            key: "showLiveYardage",
            defaultValue: true
        )
        
        let metricsToggle = createToggleRow(
            title: "Show Ball Speed & Apex",
            key: "showMetrics",
            defaultValue: true
        )
        
        let hapticToggle = createToggleRow(
            title: "Haptic Feedback",
            key: "hapticEnabled",
            defaultValue: true
        )
        
        section.addArrangedSubview(yardageToggle)
        section.addArrangedSubview(metricsToggle)
        section.addArrangedSubview(hapticToggle)
        
        contentStack.addArrangedSubview(section)
    }
    
    private func addAboutSection() {
        let section = createSection(title: "ABOUT", subtitle: nil)
        
        let versionRow = createInfoRow(title: "Version", value: "1.0.0")
        let resetButton = createButtonRow(title: "Reset All Settings", style: .destructive) { [weak self] in
            self?.resetAllSettings()
        }
        let recalibrateButton = createButtonRow(title: "Re-run Setup", style: .normal) { [weak self] in
            self?.rerunOnboarding()
        }
        
        section.addArrangedSubview(versionRow)
        section.addArrangedSubview(recalibrateButton)
        section.addArrangedSubview(resetButton)
        
        contentStack.addArrangedSubview(section)
    }
    
    // MARK: - UI Helpers
    private func createSection(title: String, subtitle: String?) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = ShotTracerDesign.Spacing.sm
        
        let headerLabel = UILabel()
        headerLabel.text = title
        headerLabel.font = ShotTracerDesign.Typography.caption()
        headerLabel.textColor = ShotTracerDesign.Colors.textTertiary
        stack.addArrangedSubview(headerLabel)
        
        if let subtitle = subtitle {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.font = ShotTracerDesign.Typography.caption()
            subtitleLabel.textColor = ShotTracerDesign.Colors.textMuted
            subtitleLabel.numberOfLines = 0
            stack.addArrangedSubview(subtitleLabel)
        }
        
        let container = GlassmorphicView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let innerStack = UIStackView()
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        innerStack.axis = .vertical
        innerStack.spacing = 1
        container.addSubview(innerStack)
        
        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: container.topAnchor),
            innerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            innerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            innerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        stack.addArrangedSubview(container)
        
        // Return inner stack for adding rows
        return innerStack
    }
    
    private func createSliderRow(title: String, value: Double, range: ClosedRange<Double>, unit: String, onChange: @escaping (Double) -> Void) -> UIView {
        let container = UIView()
        container.backgroundColor = ShotTracerDesign.Colors.surfaceElevated
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = ShotTracerDesign.Typography.body()
        titleLabel.textColor = ShotTracerDesign.Colors.textPrimary
        container.addSubview(titleLabel)
        
        let valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.text = "\(Int(value)) \(unit)"
        valueLabel.font = ShotTracerDesign.Typography.bodyMedium()
        valueLabel.textColor = ShotTracerDesign.Colors.accent
        valueLabel.textAlignment = .right
        container.addSubview(valueLabel)
        
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.minimumTrackTintColor = ShotTracerDesign.Colors.accent
        slider.maximumTrackTintColor = ShotTracerDesign.Colors.surfaceOverlay
        container.addSubview(slider)
        
        slider.addAction(UIAction { _ in
            let newValue = Double(slider.value)
            valueLabel.text = "\(Int(newValue)) \(unit)"
            onChange(newValue)
        }, for: .valueChanged)
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 80),
            
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: ShotTracerDesign.Spacing.md),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            
            valueLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: ShotTracerDesign.Spacing.md),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: ShotTracerDesign.Spacing.sm),
            slider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            slider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -ShotTracerDesign.Spacing.md)
        ])
        
        return container
    }
    
    private func createToggleRow(title: String, key: String, defaultValue: Bool) -> UIView {
        let container = UIView()
        container.backgroundColor = ShotTracerDesign.Colors.surfaceElevated
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = ShotTracerDesign.Typography.body()
        titleLabel.textColor = ShotTracerDesign.Colors.textPrimary
        container.addSubview(titleLabel)
        
        let toggle = UISwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.isOn = UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
        toggle.onTintColor = ShotTracerDesign.Colors.accent
        container.addSubview(toggle)
        
        toggle.addAction(UIAction { _ in
            UserDefaults.standard.set(toggle.isOn, forKey: key)
            ShotTracerDesign.Haptics.selection()
        }, for: .valueChanged)
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 52),
            
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            toggle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        
        return container
    }
    
    private func createInfoRow(title: String, value: String) -> UIView {
        let container = UIView()
        container.backgroundColor = ShotTracerDesign.Colors.surfaceElevated
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = ShotTracerDesign.Typography.body()
        titleLabel.textColor = ShotTracerDesign.Colors.textPrimary
        container.addSubview(titleLabel)
        
        let valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.text = value
        valueLabel.font = ShotTracerDesign.Typography.body()
        valueLabel.textColor = ShotTracerDesign.Colors.textSecondary
        valueLabel.textAlignment = .right
        container.addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 52),
            
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -ShotTracerDesign.Spacing.md),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        
        return container
    }
    
    private func createButtonRow(title: String, style: ButtonRowStyle, action: @escaping () -> Void) -> UIView {
        let container = UIView()
        container.backgroundColor = ShotTracerDesign.Colors.surfaceElevated
        
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = ShotTracerDesign.Typography.body()
        
        switch style {
        case .normal:
            button.setTitleColor(ShotTracerDesign.Colors.accent, for: .normal)
        case .destructive:
            button.setTitleColor(ShotTracerDesign.Colors.error, for: .normal)
        }
        
        container.addSubview(button)
        
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 52),
            
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: ShotTracerDesign.Spacing.md),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        
        return container
    }
    
    enum ButtonRowStyle {
        case normal
        case destructive
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    private func loadSettings() {
        calibration = CalibrationProfile.load()
    }
    
    private func saveCalibration() {
        calibration.save()
    }
    
    private func resetAllSettings() {
        let alert = UIAlertController(
            title: "Reset All Settings?",
            message: "This will reset calibration and all preferences to defaults.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            // Clear all UserDefaults for this app
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
            
            self?.calibration = .default
            ShotTracerDesign.Haptics.notification(.warning)
            self?.dismiss(animated: true)
        })
        
        present(alert, animated: true)
    }
    
    private func rerunOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        
        let alert = UIAlertController(
            title: "Setup Reset",
            message: "The app will show the setup wizard on next launch.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Debug Section (DEBUG builds only)
    
    #if DEBUG
    private func addDebugSection() {
        let section = createSection(title: "🧪 DEVELOPER TOOLS", subtitle: "Testing tools for development")
        
        let testModeButton = createButtonRow(title: "🎬 Test Mode - Load Video", style: .normal) { [weak self] in
            self?.openTestMode()
        }
        
        let simulatorNote = createInfoRow(title: "Environment", value: isSimulator ? "Simulator" : "Device")
        
        section.addArrangedSubview(testModeButton)
        section.addArrangedSubview(simulatorNote)
        
        // Add helpful tips for simulator
        if isSimulator {
            let tipLabel = UILabel()
            tipLabel.text = "💡 Tip: Drag a video file onto the Simulator window to add it to Photos"
            tipLabel.font = ShotTracerDesign.Typography.caption()
            tipLabel.textColor = ShotTracerDesign.Colors.textTertiary
            tipLabel.numberOfLines = 0
            
            let tipContainer = UIView()
            tipContainer.backgroundColor = ShotTracerDesign.Colors.surfaceElevated
            tipContainer.addSubview(tipLabel)
            tipLabel.translatesAutoresizingMaskIntoConstraints = false
            
            NSLayoutConstraint.activate([
                tipContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
                tipLabel.topAnchor.constraint(equalTo: tipContainer.topAnchor, constant: 12),
                tipLabel.bottomAnchor.constraint(equalTo: tipContainer.bottomAnchor, constant: -12),
                tipLabel.leadingAnchor.constraint(equalTo: tipContainer.leadingAnchor, constant: 16),
                tipLabel.trailingAnchor.constraint(equalTo: tipContainer.trailingAnchor, constant: -16)
            ])
            
            section.addArrangedSubview(tipContainer)
        }
        
        contentStack.addArrangedSubview(section)
    }
    
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    private func openTestMode() {
        let testVC = TestModeViewController()
        let nav = UINavigationController(rootViewController: testVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
    #endif
}


