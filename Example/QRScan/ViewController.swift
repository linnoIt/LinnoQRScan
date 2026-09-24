//
//  ViewController.swift
//  QRScan
//
//  Created by linnoIt on 09/21/2022.
//  Copyright (c) 2022 linnoIt. All rights reserved.
//
//  人工测试宿主。
//
//  设计要点：
//  1. 只用 LinnoQRScan 的公开 API（不 @testable import），顺带证明公开面足够支撑一次真实接入；
//  2. 相机预览挂在**最底层的容器视图**上，遮罩 / 扫描框 / 面板都挂在 view 上，
//     这样预览层晚一步被库加进来也不会盖住面板 —— 不依赖「后 addSubview 的在上」这种脆弱时序；
//  3. 计量器（帧率 / 回调频率 / 倍率轨迹 / 内存）与清单都在 ManualTestKit、ManualTestChecklist 里，
//     它们是纯逻辑且带单测，面板只做展示。
//

import UIKit
import AVFoundation
import LinnoQRScan

/// CADisplayLink 会强持有 target；用弱引用代理避免与宿主互相持有。
private final class DisplayLinkProxy: NSObject {
    weak var owner: ViewController?

    @objc func tick(_ link: CADisplayLink) {
        owner?.displayLinkTicked(link)
    }
}

final class ViewController: UIViewController {

    // MARK: - 扫描器状态

    private var kQR: QRProxy?
    private var currentFPSNum = 1
    private var currentScanState: QRState = .All
    private var autoZoomEnabled = false
    private var isPaused = false
    private var isSessionRunning = true
    private var scanFrame: CGRect = .zero
    private var hasBuiltScanner = false

    // MARK: - 计量

    private let frameMeter = FrameRateMeter()
    private let scanCounter = RollingCounter(window: 1)
    private let zoomTrace = ZoomTrace()
    private let displayLinkProxy = DisplayLinkProxy()
    private var displayLink: CADisplayLink?
    private var readoutTimer: Timer?
    private var lastMemorySample = Date.distantPast
    private var cachedMemoryText = "--"

    // MARK: - UI

    /// 相机预览的宿主。放在层级最底部，遮罩与面板永远在它上面。
    private let cameraContainer = UIView()
    private let maskView = UIView()
    private let scanBorderView = UIView()
    private let panel = ManualTestPanel(frame: .zero)
    private var panelExpandedConstraint: NSLayoutConstraint?
    private var panelCollapsedConstraint: NSLayoutConstraint?

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupCameraContainer()
        setupOverlays()
        setupPanel()
        startMeters()

        panel.appendLog("人工测试台就绪。若帧率稳定在 30 附近，先检查是否开了「低电量模式」（会把上限降到 30Hz）。")
        panel.appendLog("提示：点「显示测试码」用另一台设备显示码，再扫它。")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // 需要真实 bounds 才能算扫描区；只建一次，避免每次布局都重建相机
        guard !hasBuiltScanner, view.bounds.width > 0, view.bounds.height > 0 else { return }
        hasBuiltScanner = true

        scanFrame = computeScanFrame()
        applyScanFrameToOverlays()
        buildScanner(fpsNum: currentFPSNum, scanState: currentScanState, reason: "首屏")
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        panel.appendLog("⚠️ 收到内存警告")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    deinit {
        displayLink?.invalidate()
        readoutTimer?.invalidate()
    }

    // MARK: - UI 装配

    private func setupCameraContainer() {
        cameraContainer.frame = view.bounds
        cameraContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cameraContainer.isUserInteractionEnabled = false
        cameraContainer.clipsToBounds = true
        view.addSubview(cameraContainer)
    }

    private func setupOverlays() {
        maskView.isUserInteractionEnabled = false
        view.addSubview(maskView)

        scanBorderView.layer.borderColor = UIColor(red: 0.16, green: 0.72, blue: 0.55, alpha: 1).cgColor
        scanBorderView.layer.borderWidth = 2
        scanBorderView.layer.cornerRadius = 6
        scanBorderView.isUserInteractionEnabled = false
        view.addSubview(scanBorderView)
    }

    private func setupPanel() {
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.delegate = self
        view.addSubview(panel)

        let expanded = panel.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.62)
        let collapsed = panel.heightAnchor.constraint(equalToConstant: 88)

        panel.onExpandedChanged = { [weak self] isExpanded in
            guard let self = self else { return }
            self.panelExpandedConstraint?.isActive = isExpanded
            self.panelCollapsedConstraint?.isActive = !isExpanded
            UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
        }

        panelExpandedConstraint = expanded
        panelCollapsedConstraint = collapsed

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        expanded.isActive = true
    }

    /// 扫描区放在面板上方，避免被面板挡住。
    private func computeScanFrame() -> CGRect {
        let panelTop = view.bounds.height * 0.38
        let top = view.safeAreaInsets.top + 20
        let side = min(view.bounds.width - 60, max(160, panelTop - top - 16))
        return CGRect(x: (view.bounds.width - side) / 2, y: top, width: side, height: side)
    }

    private func applyScanFrameToOverlays() {
        maskView.frame = view.bounds
        maskView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let full = UIBezierPath(rect: view.bounds)
        full.append(UIBezierPath(rect: scanFrame))
        full.usesEvenOddFillRule = true

        let shape = CAShapeLayer()
        shape.path = full.cgPath
        shape.fillRule = .evenOdd
        shape.fillColor = UIColor.black.cgColor
        shape.opacity = 0.45
        maskView.layer.addSublayer(shape)

        scanBorderView.frame = scanFrame
    }

    // MARK: - 扫描器

    private func buildScanner(fpsNum: Int, scanState: QRState, reason: String) {
        releaseScanner(log: false)
        currentFPSNum = fpsNum
        currentScanState = scanState
        isPaused = false
        isSessionRunning = true

        let proxy = QRProxy(bounds: view.frame,
                           scanFrame: scanFrame,
                           showView: cameraContainer,
                           fpsNum: fpsNum,
                           scanState: scanState,
                           playSource: true,
                           supportCodeTypes: nil,
                           turnWideAngle: false) { [weak self] kString, kState in
            self?.handleScanResult(value: kString, state: kState)
        }
        proxy.isAutoFocusZoomEnabled = autoZoomEnabled
        kQR = proxy

        // 预览层由库在稍后异步加入 cameraContainer.layer；重置计量以本次重建为起点
        resetMeters()
        panel.appendLog("重建（\(reason)）：fpsNum=\(fpsNum) scanState=\(scanState.rawValue) 自动变焦=\(autoZoomEnabled ? "开" : "关")")
    }

    private func releaseScanner(log: Bool) {
        guard let proxy = kQR else {
            if log { panel.appendLog("当前没有扫描器实例，无需释放") }
            return
        }
        proxy.stop()
        kQR = nil
        isSessionRunning = false
        if log {
            panel.appendLog("已释放 proxy（预期：预览画面消失、控制台打印 QRProxy -> deinit、相机指示灯熄灭）")
        }
    }

    private func handleScanResult(value: String, state: QRState) {
        scanCounter.mark()
        let preview = value.count > 48 ? String(value.prefix(48)) + "…" : value
        panel.appendLog("识别回调 state=\(state.rawValue) value=\(preview)")
    }

    // MARK: - 计量

    private func startMeters() {
        displayLinkProxy.owner = self
        let link = CADisplayLink(target: displayLinkProxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link

        // 10Hz 刷新读数：比显示刷新慢一个数量级，不会明显影响被测的帧率
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.refreshReadouts()
        }
        RunLoop.main.add(timer, forMode: .common)
        readoutTimer = timer
    }

    fileprivate func displayLinkTicked(_ link: CADisplayLink) {
        frameMeter.tick(timestamp: link.timestamp)
    }

    private func resetMeters() {
        frameMeter.reset()
        scanCounter.reset()
        zoomTrace.reset()
    }

    private func refreshReadouts() {
        // 只读一个 10Hz 的读数，且只在实例存在时记录倍率，避免释放后记入一段假变化
        let zoom = kQR?.currentZoomLevel() ?? 1
        if kQR != nil {
            zoomTrace.record(factor: zoom)
        }

        // 内存读数变化慢，1 秒采一次就够：10Hz 调 mach 系统调用本身也会成为观测噪声
        let now = Date()
        if now.timeIntervalSince(lastMemorySample) >= 1 {
            lastMemorySample = now
            cachedMemoryText = MemoryProbe.residentMemoryText()
        }

        let snapshot = frameMeter.snapshot
        panel.update(with: ManualTestPanel.Readouts(
            fps: snapshot.fps,
            hitchCount: snapshot.hitchCount,
            worstFrameMilliseconds: snapshot.worstFrameMilliseconds,
            zoom: zoom,
            zoomChangeCount: zoomTrace.changes.count,
            minimumChangeInterval: zoomTrace.minimumChangeInterval,
            scanCallbacksPerSecond: scanCounter.rate(),
            memoryText: cachedMemoryText,
            scanState: currentScanState,
            fpsNum: currentFPSNum,
            autoZoomEnabled: autoZoomEnabled,
            isRunning: isSessionRunning
        ))
    }

    // MARK: - 手势

    /// 点画面空白区切换手电（保留原示例的交互，便于快速验证 toggleTorch）。
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        toggleTorch()
    }

    private func toggleTorch() {
        guard let proxy = kQR else {
            panel.appendLog("未创建扫描器，手电无效")
            return
        }
        proxy.toggleTorch(mode: .auto)
        panel.appendLog("手电切换 → isTorchOn=\(proxy.isTorchOn())")
    }
}

// MARK: - 面板回调

extension ViewController: ManualTestPanelDelegate {

    func panel(_ panel: ManualTestPanel, didChangeAutoZoom isOn: Bool) {
        autoZoomEnabled = isOn
        kQR?.isAutoFocusZoomEnabled = isOn
        // 换模式后重新观察倍率变化，避免把切换瞬间算进间隔统计
        zoomTrace.reset()
        panel.appendLog("自动变焦 → \(isOn ? "开启" : "关闭")（默认关闭，开启后与手动 setZoom 互斥）")
    }

    func panel(_ panel: ManualTestPanel, didRequestZoomStep delta: CGFloat) {
        guard let proxy = kQR else {
            panel.appendLog("未创建扫描器，倍率调整无效")
            return
        }
        let current = proxy.currentZoomLevel()
        let target = min(max(current + delta, 1.0), 10.0)
        proxy.setZoom(factor: target)
        panel.appendLog("setZoom \(String(format: "%.2f", current)) → \(String(format: "%.2f", target))")
    }

    func panelDidRequestZoomReset(_ panel: ManualTestPanel) {
        kQR?.setZoom(factor: 1.0)
        panel.appendLog("setZoom → 1.00")
    }

    func panelDidRequestTorchToggle(_ panel: ManualTestPanel) {
        toggleTorch()
    }

    func panelDidRequestPauseToggle(_ panel: ManualTestPanel) {
        guard let proxy = kQR else {
            panel.appendLog("未创建扫描器，暂停无效")
            return
        }
        isPaused.toggle()
        proxy.pause(isPaused)
        panel.appendLog("pause(\(isPaused)) —— 暂停期间不应有任何识别回调")
    }

    func panelDidRequestStart(_ panel: ManualTestPanel) {
        guard let proxy = kQR else {
            panel.appendLog("未创建扫描器，start 无效")
            return
        }
        proxy.start()
        isSessionRunning = true
        panel.appendLog("start()")
    }

    func panelDidRequestStop(_ panel: ManualTestPanel) {
        guard let proxy = kQR else {
            panel.appendLog("未创建扫描器，stop 无效")
            return
        }
        proxy.stop()
        isSessionRunning = false
        panel.appendLog("stop()（异步：返回时相机未必已停，稍后画面才冻结）")
    }

    func panelDidRequestRelease(_ panel: ManualTestPanel) {
        releaseScanner(log: true)
    }

    func panelDidRequestShowTestCodes(_ panel: ManualTestPanel) {
        let controller = TestCodeViewController()
        let nav = UINavigationController(rootViewController: controller)
        present(nav, animated: true)
    }

    func panelDidRequestResetCounters(_ panel: ManualTestPanel) {
        resetMeters()
        panel.appendLog("计量已重置（帧率 / 卡顿 / 回调 / 倍率轨迹）")
    }

    func panel(_ panel: ManualTestPanel, didRequestRebuildWithFPS fpsNum: Int, scanState: QRState) {
        buildScanner(fpsNum: fpsNum, scanState: scanState, reason: "手动")
    }
}
