//
//  ManualTestPanel.swift
//  QRScan_Example
//
//  人工测试台面板。只负责「展示读数 + 收操作 + 渲染测试点清单」，
//  所有相机行为都通过 delegate 交给 ViewController 执行 —— 面板不直接接触 QRProxy，
//  这样面板本身可以在没有相机的情况下单独调试布局。
//

import UIKit
import LinnoQRScan

protocol ManualTestPanelDelegate: AnyObject {
    func panel(_ panel: ManualTestPanel, didChangeAutoZoom isOn: Bool)
    func panel(_ panel: ManualTestPanel, didRequestZoomStep delta: CGFloat)
    func panelDidRequestZoomReset(_ panel: ManualTestPanel)
    func panelDidRequestTorchToggle(_ panel: ManualTestPanel)
    func panelDidRequestPauseToggle(_ panel: ManualTestPanel)
    func panelDidRequestStart(_ panel: ManualTestPanel)
    func panelDidRequestStop(_ panel: ManualTestPanel)
    func panelDidRequestRelease(_ panel: ManualTestPanel)
    func panelDidRequestShowTestCodes(_ panel: ManualTestPanel)
    /// 把帧率 / 回调用计量器清零，重新开始一段观测。
    func panelDidRequestResetCounters(_ panel: ManualTestPanel)
    /// 重建扫描器；`fpsNum` 与 `scanState` 决定新实例的配置。
    func panel(_ panel: ManualTestPanel, didRequestRebuildWithFPS fpsNum: Int, scanState: QRState)
}

final class ManualTestPanel: UIView {

    /// 面板需要展示的实时读数。宿主是唯一真值来源，每次刷新整体覆盖。
    struct Readouts {
        var fps: Double = 0
        var hitchCount: Int = 0
        var worstFrameMilliseconds: Double = 0
        var zoom: CGFloat = 1
        var zoomChangeCount: Int = 0
        var minimumChangeInterval: TimeInterval?
        var scanCallbacksPerSecond: Double = 0
        var memoryText: String = "--"
        var scanState: QRState = .All
        var fpsNum: Int = 1
        var autoZoomEnabled: Bool = false
        var isRunning: Bool = true
    }

    weak var delegate: ManualTestPanelDelegate?

    /// 折叠 / 展开变化时通知宿主调整高度约束。
    var onExpandedChanged: ((_ expanded: Bool) -> Void)?

    /// 清单勾选状态（内存态）。
    private(set) var checkedItemIDs: Set<String> = []

    private var readouts = Readouts()
    private var tapHandlers: [Int: () -> Void] = [:]
    private var nextTag = 1

    /// 自动变焦开关按钮，单独持有以便就地改样式。
    private weak var autoZoomToggleButton: UIButton?

    // MARK: - 视图

    private let headerLabel = ManualTestPanel.makeLabel("人工测试台", font: .boldSystemFont(ofSize: 15), color: .white)
    private let hudLabel = ManualTestPanel.makeLabel("", font: ManualTestPanel.monoFont(size: 10), color: UIColor(white: 0.95, alpha: 1), lines: 2)
    private let readoutLabel = ManualTestPanel.makeLabel("", font: ManualTestPanel.monoFont(size: 11), color: UIColor(white: 0.95, alpha: 1), lines: 0)
    private let collapseButton = UIButton(type: .system)

    private let scrollView = UIScrollView()
    private let bodyStack = UIStackView()
    private let logTextView = UITextView()

    private var logLines: [String] = []
    private let maxLogLines = 300

    /// 清单勾选框，按 item.id 索引；打勾时就地改样式，不重建整个清单。
    private var checkboxes: [String: UIButton] = [:]

    private static let accent = UIColor(red: 0.16, green: 0.72, blue: 0.55, alpha: 1)
    private static let panelBackground = UIColor(white: 0.07, alpha: 0.94)
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    // MARK: - 生命周期

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = Self.panelBackground
        layer.cornerRadius = 14
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor

        setupHeader()
        setupLogTextView()
        setupScrollView()
        rebuildBody()
        updateReadoutLabels()
        setExpanded(true)
    }

    private func setupHeader() {
        for view in [headerLabel, hudLabel, collapseButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        collapseButton.setTitle("折叠", for: .normal)
        collapseButton.setTitleColor(.white, for: .normal)
        collapseButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        registerTap(collapseButton) { [weak self] in
            guard let self = self else { return }
            self.setExpanded(self.bodyStack.isHidden)
        }

        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            collapseButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            collapseButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            collapseButton.widthAnchor.constraint(equalToConstant: 56),

            hudLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            hudLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            hudLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4)
        ])
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .onDrag
        addSubview(scrollView)

        bodyStack.axis = .vertical
        bodyStack.spacing = 14
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(bodyStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.topAnchor.constraint(equalTo: hudLabel.bottomAnchor, constant: 8),

            bodyStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 14),
            bodyStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -14),
            bodyStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            bodyStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            bodyStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -28)
        ])
    }

    /// 日志视图只配置一次：每轮重建都补一条高度约束会导致重复约束累积。
    private func setupLogTextView() {
        logTextView.isEditable = false
        logTextView.isScrollEnabled = true
        logTextView.backgroundColor = UIColor(white: 0, alpha: 0.35)
        logTextView.textColor = UIColor(red: 0.6, green: 1, blue: 0.75, alpha: 1)
        logTextView.font = ManualTestPanel.monoFont(size: 10)
        logTextView.textContainerInset = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        logTextView.layer.cornerRadius = 8
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        logTextView.heightAnchor.constraint(equalToConstant: 150).isActive = true
    }

    /// 展开 / 折叠。折叠后只剩标题 + 一行读数，方便双手对着码操作。
    func setExpanded(_ expanded: Bool) {
        bodyStack.isHidden = !expanded
        collapseButton.setTitle(expanded ? "折叠" : "展开", for: .normal)
        onExpandedChanged?(expanded)
    }

    // MARK: - 内容装配

    private func rebuildBody() {
        bodyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        checkboxes.removeAll()

        bodyStack.addArrangedSubview(sectionTitle("实时读数"))
        bodyStack.addArrangedSubview(boxed(readoutLabel))

        bodyStack.addArrangedSubview(sectionTitle("自动变焦（本轮改动）"))
        bodyStack.addArrangedSubview(buttonColumn([
            ("自动变焦 开/关", { [weak self] button in self?.toggleAutoZoom(from: button) }),
            ("倍率 -0.5", { [weak self] _ in self?.requestZoomStep(-0.5) }),
            ("倍率 +0.5", { [weak self] _ in self?.requestZoomStep(0.5) }),
            ("倍率 +2.0（验证实时读取）", { [weak self] _ in self?.requestZoomStep(2.0) }),
            ("倍率复位 1.0", { [weak self] _ in self?.delegate?.panelDidRequestZoomReset(self!) })
        ]))

        bodyStack.addArrangedSubview(sectionTitle("会话控制"))
        bodyStack.addArrangedSubview(buttonColumn([
            ("手电 开/关（点画面空白区亦然）", { [weak self] _ in self?.delegate?.panelDidRequestTorchToggle(self!) }),
            ("暂停/恢复识别", { [weak self] _ in self?.delegate?.panelDidRequestPauseToggle(self!) }),
            ("停止 stop()", { [weak self] _ in self?.delegate?.panelDidRequestStop(self!) }),
            ("启动 start()", { [weak self] _ in self?.delegate?.panelDidRequestStart(self!) })
        ]))

        bodyStack.addArrangedSubview(sectionTitle("重建（切换 fpsNum / scanState）"))
        bodyStack.addArrangedSubview(buttonColumn([
            ("fps=1 · 全部", { [weak self] _ in self?.requestRebuild(fps: 1, state: .All) }),
            ("fps=3 · 全部（验证多帧修复）", { [weak self] _ in self?.requestRebuild(fps: 3, state: .All) }),
            ("fps=1 · 仅二维码", { [weak self] _ in self?.requestRebuild(fps: 1, state: .Codes2D) }),
            ("fps=1 · 仅条码", { [weak self] _ in self?.requestRebuild(fps: 1, state: .Barcodes) }),
            ("fps=1 · 仅人体", { [weak self] _ in self?.requestRebuild(fps: 1, state: .Bodies) })
        ]))

        bodyStack.addArrangedSubview(sectionTitle("生命周期 / 素材"))
        bodyStack.addArrangedSubview(buttonColumn([
            ("释放 proxy（验证预览层摘除）", { [weak self] _ in self?.delegate?.panelDidRequestRelease(self!) }),
            ("显示测试码（供另一台设备扫）", { [weak self] _ in self?.delegate?.panelDidRequestShowTestCodes(self!) }),
            ("重置计量（帧率/卡顿/回调/倍率）", { [weak self] _ in self?.delegate?.panelDidRequestResetCounters(self!) }),
            ("重置清单勾选", { [weak self] _ in self?.resetChecklist() })
        ]))

        bodyStack.addArrangedSubview(sectionTitle("测试点清单（共 \(ManualTestChecklist.all.count) 条，点方框打勾）"))
        for area in ManualTestArea.allCases {
            bodyStack.addArrangedSubview(areaHeader(area))
            for item in ManualTestChecklist.items(in: area) {
                bodyStack.addArrangedSubview(checklistRow(item))
            }
        }

        bodyStack.addArrangedSubview(sectionTitle("日志"))
        bodyStack.addArrangedSubview(boxed(logTextView))
        bodyStack.addArrangedSubview(buttonColumn([
            ("清空日志", { [weak self] _ in self?.clearLog() }),
            ("滚到清单末尾", { [weak self] _ in self?.scrollToBottom() })
        ]))

        applyAutoZoomToggleStyle()
    }

    // MARK: - 操作

    private func toggleAutoZoom(from button: UIButton) {
        autoZoomToggleButton = button
        readouts.autoZoomEnabled.toggle()
        applyAutoZoomToggleStyle()
        updateReadoutLabels()
        delegate?.panel(self, didChangeAutoZoom: readouts.autoZoomEnabled)
    }

    private func requestZoomStep(_ delta: CGFloat) {
        delegate?.panel(self, didRequestZoomStep: delta)
    }

    private func requestRebuild(fps: Int, state: QRState) {
        delegate?.panel(self, didRequestRebuildWithFPS: fps, scanState: state)
    }

    private func applyAutoZoomToggleStyle() {
        guard let button = autoZoomToggleButton else { return }
        button.setTitle(readouts.autoZoomEnabled ? "自动变焦：开 · 点击关闭" : "自动变焦：关 · 点击开启", for: .normal)
        button.backgroundColor = readouts.autoZoomEnabled ? Self.accent : UIColor(white: 0.2, alpha: 0.95)
    }

    private func scrollToBottom() {
        let bottom = CGPoint(x: 0, y: max(0, scrollView.contentSize.height - scrollView.bounds.height))
        scrollView.setContentOffset(bottom, animated: true)
    }

    private func resetChecklist() {
        checkedItemIDs.removeAll()
        for button in checkboxes.values {
            applyCheckStyle(button, checked: false)
        }
    }

    // MARK: - 清单

    private func areaHeader(_ area: ManualTestArea) -> UIView {
        let title = ManualTestPanel.makeLabel("\(area.code) · \(area.title)", font: .boldSystemFont(ofSize: 12), color: Self.accent, lines: 0)
        let subtitle = ManualTestPanel.makeLabel(area.changeSummary, font: .systemFont(ofSize: 10), color: UIColor(white: 0.6, alpha: 1), lines: 0)
        let stack = UIStackView(arrangedSubviews: [title, subtitle])
        stack.axis = .vertical
        stack.spacing = 2
        return stack
    }

    private func checklistRow(_ item: ManualTestItem) -> UIView {
        let check = UIButton(type: .system)
        check.translatesAutoresizingMaskIntoConstraints = false
        check.titleLabel?.font = .systemFont(ofSize: 18)
        check.widthAnchor.constraint(equalToConstant: 26).isActive = true
        checkboxes[item.id] = check
        applyCheckStyle(check, checked: checkedItemIDs.contains(item.id))

        registerTap(check) { [weak self] in
            guard let self = self else { return }
            let nowChecked = !self.checkedItemIDs.contains(item.id)
            if nowChecked {
                self.checkedItemIDs.insert(item.id)
            } else {
                self.checkedItemIDs.remove(item.id)
            }
            self.applyCheckStyle(check, checked: nowChecked)
        }

        let title = ManualTestPanel.makeLabel("\(item.id)  \(item.title)", font: .systemFont(ofSize: 12, weight: .semibold), color: .white, lines: 0)
        let howTo = ManualTestPanel.makeLabel("操作：\(item.howTo)", font: .systemFont(ofSize: 10), color: UIColor(white: 0.72, alpha: 1), lines: 0)
        let expected = ManualTestPanel.makeLabel("预期：\(item.expected)", font: .systemFont(ofSize: 10), color: UIColor(white: 0.88, alpha: 1), lines: 0)

        let textStack = UIStackView(arrangedSubviews: [title, howTo, expected])
        textStack.axis = .vertical
        textStack.spacing = 3

        let row = UIStackView(arrangedSubviews: [check, textStack])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 6
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        return row
    }

    private func applyCheckStyle(_ button: UIButton, checked: Bool) {
        button.setTitle(checked ? "☑" : "☐", for: .normal)
        button.setTitleColor(checked ? Self.accent : UIColor(white: 0.7, alpha: 1), for: .normal)
    }

    // MARK: - 读数刷新

    func update(with newReadouts: Readouts) {
        let autoZoomChanged = newReadouts.autoZoomEnabled != readouts.autoZoomEnabled
        readouts = newReadouts
        updateReadoutLabels()
        if autoZoomChanged { applyAutoZoomToggleStyle() }
    }

    private func updateReadoutLabels() {
        let intervalText = readouts.minimumChangeInterval.map { String(format: "%.2fs", $0) } ?? "--"

        readoutLabel.text = """
        帧率        \(String(format: "%5.1f", readouts.fps)) fps   卡顿(>50ms) \(readouts.hitchCount) 次   最长帧 \(String(format: "%.0f", readouts.worstFrameMilliseconds)) ms
        倍率        \(String(format: "%5.2f", readouts.zoom))      变化次数 \(readouts.zoomChangeCount)      最小变化间隔 \(intervalText)
        识别回调    \(String(format: "%5.1f", readouts.scanCallbacksPerSecond)) 次/秒（单帧模式下即实际识别节奏）
        常驻内存    \(readouts.memoryText)
        自动变焦    \(readouts.autoZoomEnabled ? "开启" : "关闭")      会话 \(readouts.isRunning ? "运行中" : "已停止")
        当前配置    fpsNum=\(readouts.fpsNum)   scanState=\(readouts.scanState.rawValue)（\(ManualTestPanel.stateName(readouts.scanState))）
        """

        hudLabel.text = String(format: "%.0ffps · 卡顿%d · 倍率%.2f · %@ · %@",
                               readouts.fps,
                               readouts.hitchCount,
                               readouts.zoom,
                               readouts.autoZoomEnabled ? "自动变焦开" : "自动变焦关",
                               readouts.memoryText)
    }

    private static func stateName(_ state: QRState) -> String {
        switch state {
        case .Barcodes: return "条码"
        case .Codes2D: return "二维码"
        case .Bodies: return "人体"
        case .Barcodes_Codes2D: return "条码+二维码"
        case .Barcodes_Bodies: return "条码+人体"
        case .Codes2D_Bodies: return "二维码+人体"
        case .All: return "全部"
        }
    }

    // MARK: - 日志

    func appendLog(_ text: String) {
        let stamp = ManualTestPanel.timeFormatter.string(from: Date())
        logLines.append("[\(stamp)] \(text)")
        if logLines.count > maxLogLines {
            logLines.removeFirst(logLines.count - maxLogLines)
        }
        logTextView.text = logLines.joined(separator: "\n")
        if let end = logTextView.textRange(from: logTextView.endOfDocument, to: logTextView.endOfDocument) {
            logTextView.selectedTextRange = end
        }
    }

    func clearLog() {
        logLines.removeAll()
        logTextView.text = ""
    }

    // MARK: - 小组件

    private func sectionTitle(_ text: String) -> UIView {
        ManualTestPanel.makeLabel(text, font: .boldSystemFont(ofSize: 12), color: Self.accent, lines: 0)
    }

    private func boxed(_ content: UIView) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(white: 0, alpha: 0.35)
        container.layer.cornerRadius = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        return container
    }

    /// 竖直排布的按钮，每行两个。handler 会拿到按钮本身，便于就地改样式。
    private func buttonColumn(_ buttons: [(String, (UIButton) -> Void)]) -> UIView {
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 6

        var currentRow = UIStackView()
        currentRow.axis = .horizontal
        currentRow.spacing = 6
        currentRow.distribution = .fillEqually

        for (index, item) in buttons.enumerated() {
            let button = makeActionButton(item.0, handler: item.1)
            if index == 0, item.0.hasPrefix("自动变焦") {
                autoZoomToggleButton = button
            }
            currentRow.addArrangedSubview(button)
            if currentRow.arrangedSubviews.count == 2 || index == buttons.count - 1 {
                column.addArrangedSubview(currentRow)
                currentRow = UIStackView()
                currentRow.axis = .horizontal
                currentRow.spacing = 6
                currentRow.distribution = .fillEqually
            }
        }
        return column
    }

    private func makeActionButton(_ title: String, handler: @escaping (UIButton) -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.7
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.backgroundColor = UIColor(white: 0.2, alpha: 0.95)
        button.layer.cornerRadius = 7
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        registerTap(button) { handler(button) }
        return button
    }

    /// 用 tag → 闭包映射统一处理点击，避免为每个按钮写一个 @objc 方法。
    private func registerTap(_ button: UIButton, handler: @escaping () -> Void) {
        button.tag = nextTag
        tapHandlers[nextTag] = handler
        nextTag += 1
        button.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)
    }

    @objc private func handleTap(_ sender: UIButton) {
        tapHandlers[sender.tag]?()
    }

    private static func makeLabel(_ text: String, font: UIFont, color: UIColor, lines: Int = 1) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.numberOfLines = lines
        return label
    }

    /// 等宽字体：`monospacedSystemFont` 是 iOS 13 才有的，而本库的部署目标是 iOS 12。
    private static func monoFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        if #available(iOS 13.0, *) {
            return .monospacedSystemFont(ofSize: size, weight: weight)
        }
        return UIFont(name: "Menlo", size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}
