import UIKit

final class TrajectoryOverlayView: UIView {
    private let tracerLayer = CAShapeLayer()
    private let shadowLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        setupLayers()
    }

    func update(with normalizedPoints: [CGPoint], color: UIColor) {
        guard !normalizedPoints.isEmpty else {
            shadowLayer.path = nil
            tracerLayer.path = nil
            return
        }

        tracerLayer.strokeColor = color.cgColor

        let path = UIBezierPath()
        let shadowPath = UIBezierPath()

        func toView(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * bounds.width, y: p.y * bounds.height)
        }

        let start = toView(normalizedPoints[0])
        path.move(to: start)
        shadowPath.move(to: CGPoint(x: start.x + 2, y: start.y + 2))

        for point in normalizedPoints.dropFirst() {
            let viewPoint = toView(point)
            path.addLine(to: viewPoint)
            shadowPath.addLine(to: CGPoint(x: viewPoint.x + 2, y: viewPoint.y + 2))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tracerLayer.path = path.cgPath
        shadowLayer.path = shadowPath.cgPath
        CATransaction.commit()
    }

    func clear() {
        update(with: [], color: UIColor.red)
    }

    private func setupLayers() {
        tracerLayer.strokeColor = UIColor.systemRed.cgColor
        tracerLayer.fillColor = UIColor.clear.cgColor
        tracerLayer.lineWidth = 5
        tracerLayer.lineCap = .round

        shadowLayer.strokeColor = UIColor.black.withAlphaComponent(0.5).cgColor
        shadowLayer.fillColor = UIColor.clear.cgColor
        shadowLayer.lineWidth = 7
        shadowLayer.lineCap = .round

        layer.addSublayer(shadowLayer)
        layer.addSublayer(tracerLayer)
    }
}
