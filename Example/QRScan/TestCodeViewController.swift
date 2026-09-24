//
//  TestCodeViewController.swift
//  QRScan_Example
//
//  生成测试用码，供另一台设备（或电脑）显示，当作被测设备的扫描目标。
//  人工测试必须有可控的码：尺寸、类型、数量都能自己决定，否则测不了阈值与过滤。
//

import UIKit
import CoreImage

final class TestCodeViewController: UIViewController {

    /// 可生成的码类型。`requiredScanState` 提示被测端需要哪种 scanState 才能识别。
    enum Kind: Int, CaseIterable {
        case qr
        case code128

        var title: String {
            switch self {
            case .qr: return "二维码"
            case .code128: return "Code128 条码"
            }
        }

        var filterName: String {
            switch self {
            case .qr: return "CIQRCodeGenerator"
            case .code128: return "CICode128BarcodeGenerator"
            }
        }

        var message: String {
            switch self {
            case .qr: return "https://hmax.top/qrscan-manual-test"
            case .code128: return "QRSCAN-MANUAL-TEST-0001"
            }
        }

        var requirement: String {
            switch self {
            case .qr: return "需要 scanState = 二维码 / 全部"
            case .code128: return "需要 scanState = 条码 / 全部"
            }
        }

        /// 生成图时用的放大倍率：二维码模块小、条码本身矮，各自取合适的值。
        var scale: CGFloat {
            switch self {
            case .qr: return 12
            case .code128: return 6
            }
        }
    }

    /// 一次生成两个码时并排显示，用来验证「一帧多码取最宽的码」。
    private let imageView = UIImageView()
    private let hintLabel = UILabel()
    private let segmentedControl = UISegmentedControl(items: Kind.allCases.map { $0.title })
    private let sharedContext = CIContext()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "测试码"

        setupUI()
        refresh()
    }

    private func setupUI() {
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(kindChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.numberOfLines = 0
        hintLabel.font = .systemFont(ofSize: 14)
        hintLabel.textColor = .darkGray
        hintLabel.textAlignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("关闭", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let pairButton = UIButton(type: .system)
        pairButton.setTitle("并排显示两个码（验证取最宽的码）", for: .normal)
        pairButton.titleLabel?.font = .systemFont(ofSize: 13)
        pairButton.titleLabel?.numberOfLines = 2
        pairButton.addTarget(self, action: #selector(showPair), for: .touchUpInside)
        pairButton.translatesAutoresizingMaskIntoConstraints = false

        for subview in [segmentedControl, imageView, hintLabel, pairButton, closeButton] {
            view.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            imageView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 24),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 0.6),

            hintLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            pairButton.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 20),
            pairButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            pairButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            closeButton.topAnchor.constraint(equalTo: pairButton.bottomAnchor, constant: 20),
            closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    // MARK: - 交互

    @objc private func kindChanged() {
        refresh()
    }

    @objc private func showPair() {
        // 一个大码 + 一个小码并排：被测端应把镜头往大码收敛，
        // 这是一帧多码场景（AZ-07）唯一可靠的复现方式。
        let large = makeImage(kind: .qr, scale: 14)
        let small = makeImage(kind: .qr, scale: 4)
        imageView.contentMode = .scaleAspectFit
        imageView.image = sideBySide([large, small])
        hintLabel.text = """
        左：大码（约 14 倍）　右：小码（约 4 倍）
        让两个码同时进入取景框，然后缓慢后退。
        预期：镜头向左侧大码收敛，倍率不会被右侧小码推远。
        """
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private func refresh() {
        guard let kind = Kind(rawValue: segmentedControl.selectedSegmentIndex) else { return }
        imageView.image = makeImage(kind: kind, scale: kind.scale)
        hintLabel.text = """
        \(kind.title) · 内容：\(kind.message)
        \(kind.requirement)

        用另一台设备或电脑显示此码，再用被测设备扫描。
        """
    }

    // MARK: - 生成

    private func makeImage(kind: Kind, scale: CGFloat) -> UIImage? {
        guard let filter = CIFilter(name: kind.filterName) else { return nil }
        filter.setValue(kind.message.data(using: .ascii), forKey: "inputMessage")
        if kind == .qr {
            filter.setValue("M", forKey: "inputCorrectionLevel")
        }
        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        // 一次性栅格化成 CGImage：直接把 CIImage 交给 UIImageView 会按需重绘，滚动时开销大
        guard let cgImage = sharedContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func sideBySide(_ candidates: [UIImage?]) -> UIImage? {
        let images = candidates.compactMap { $0 }
        guard !images.isEmpty else { return nil }
        let spacing: CGFloat = 40
        let height = images.map { $0.size.height }.max() ?? 0
        let width = images.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(images.count - 1)
        let size = CGSize(width: width, height: height)

        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        defer { UIGraphicsEndImageContext() }
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))

        var x: CGFloat = 0
        for image in images {
            image.draw(in: CGRect(x: x, y: (height - image.size.height) / 2, width: image.size.width, height: image.size.height))
            x += image.size.width + spacing
        }
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
