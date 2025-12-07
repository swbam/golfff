import UIKit
import AVKit

final class ReviewViewController: UIViewController {
    private let videoURL: URL
    private var player: AVPlayer?

    init(videoURL: URL) {
        self.videoURL = videoURL
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPlayer()
        setupButtons()
    }

    private func setupPlayer() {
        let player = AVPlayer(url: videoURL)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(controller)
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.75)
        ])
        controller.didMove(toParent: self)
        player.play()
        self.player = player
    }

    private func setupButtons() {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 16
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        let share = UIButton(type: .system)
        share.setTitle("Share", for: .normal)
        share.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)

        let close = UIButton(type: .system)
        close.setTitle("Close", for: .normal)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        stack.addArrangedSubview(share)
        stack.addArrangedSubview(close)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc private func shareTapped() {
        let activity = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
        present(activity, animated: true)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
