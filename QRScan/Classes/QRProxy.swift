//
//  QRProxy.swift
//  QR
//
//  Created by 韩增超 on 2022/9/20.
//

import Foundation
import AVFoundation
import UIKit

open class QRProxy: NSObject {
    
    private let captureSession = AVCaptureSession()
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private let captureMetadataOutput = AVCaptureMetadataOutput()
    private var device: AVCaptureDevice?

    private var bounds: CGRect = UIScreen.main.bounds
    private weak var showView: UIView?
    private var outputHandler: ((kString: String, kState: QRState)) -> Void = { _ in }

    private var tagArray = [Int]()
    private var frameBuffer = [[AVMetadataObject]]()

    private var fpsNum: Int = 1
    private var scanState: QRState = .All
    private var shouldPlayFeedback = false
    
    private var currentZoomFactor: CGFloat = 1.0
    
    private var pause: Bool = false
    
    private var turnWideAngle: Bool = false

    /// captureSession 的装配 / 启动 / 停止统一走这条串行队列。
    ///
    /// 这些操作都是阻塞式的（`AVCaptureDeviceInput` 初始化要打开设备，`addInput` / `addOutput`
    /// 要重整会话图，`startRunning()` 可能占用几十到上百毫秒），放主线程会直接体现为进入扫描页时的卡顿。
    /// QoS 取 `.userInitiated`：用户此刻正盯着屏幕等画面出来。
    private let sessionQueue = DispatchQueue(label: "com.linno.qrscan.session", qos: .userInitiated)

    /// 本实例实际参与识别的码类型，由 scanState 与 supportCodeTypes 共同决定。
    private var supportedTypes: [AVMetadataObject.ObjectType] = []

    /// 产出一次结果后，恢复识别的延迟，避免结果展示期间被重复触发。
    private static let resumeInterval: TimeInterval = 1

    /// 自动变焦控制器。相机装配成功后才存在（它需要一个真实的 `AVCaptureDevice`）。
    private var autoZoomController: QRAutoZoomController?

    /// 自动变焦开关的唯一存储位。控制器可能晚于开关创建，所以这里保存一份并在创建时同步过去。
    private var autoZoomEnabled = false

    /// 是否开启自动变焦，默认关闭。
    ///
    /// 开启后，识别到码时会根据码在预览层中的宽度占比自动拉近 / 推远：
    /// 占比小于 25% 逐步拉近，大于 45% 逐步推远，步进 0.3，两次调整至少间隔 0.5 秒。
    /// 手动调用 `setZoom(factor:)` 与它是互斥的 —— 开启后请不要再手动设定倍率。
    @objc public var isAutoFocusZoomEnabled: Bool {
        get { autoZoomEnabled }
        set {
            autoZoomEnabled = newValue
            autoZoomController?.isEnabled = newValue
        }
    }

    public static var currentView: UIView { QRModel.currentViewController()?.view ?? UIView()}
    public static var currentBounds: CGRect { currentView.bounds }

    /// - Parameters:
    ///   - bounds: 看到的bounds
    ///   - scanFrame: 扫描区域的frame
    ///   - showView: 需要添加layer的view
    ///   - fpsNum: 识别
    ///   - scanState: 扫描类型
    ///   - playSource: 播放识别声音
    ///   - supportCodeTypes: 支持的code类型
    ///   - turnWideAngle: 是否开启广角
    ///   - outPut: 返回的闭包
    public convenience init(
        bounds: CGRect = QRProxy.currentBounds,
        scanFrame: CGRect? = nil,
        showView: UIView = QRProxy.currentView,
        fpsNum: Int = 1,
        scanState: QRState = .All,
        playSource: Bool = true,
        supportCodeTypes: [AVMetadataObject.ObjectType]? = nil,
        turnWideAngle: Bool = false,
        outPut: @escaping ((kString: String, kState: QRState)) -> Void
    ) {
        self.init()
        self.configure(bounds: bounds, scanFrame: scanFrame, showView: showView, fpsNum: fpsNum, scanState: scanState, playFeedback: playSource, supportCodeTypes: supportCodeTypes, turnWideAngle: turnWideAngle)
        self.outputHandler = outPut
    }

    @objc public convenience init(outPut: @escaping (_ kString: String, _ kState: Int) -> Void) {
        self.init()
        self.configure(bounds: Self.currentBounds, showView: Self.currentView, fpsNum: 1, scanState: .All, playFeedback: true, supportCodeTypes: nil, turnWideAngle: false)
        self.outputHandler = { result in outPut(result.kString, result.kState.rawValue) }
    }

    @objc public convenience init(
        bounds: CGRect = QRProxy.currentBounds,
        showView: UIView = QRProxy.currentView,
        scanFrame: CGRect = .zero,
        fpsNum: Int = 1,
        scanState: Int = QRState.All.rawValue,
        playSource: Bool = true,
        supportCodeTypes: [AVMetadataObject.ObjectType]? = nil,
        turnWideAngle: Bool = false,
        outPut: @escaping (_ kString: String, _ kState: Int) -> Void
    ) {
        self.init()
        let kScanFrame: CGRect? = scanFrame == .zero ? nil : scanFrame
        self.configure(bounds: bounds, scanFrame: kScanFrame, showView: showView, fpsNum: fpsNum, scanState: QRState(rawValue: scanState) ?? .All, playFeedback: playSource, supportCodeTypes: supportCodeTypes, turnWideAngle: turnWideAngle)
        self.outputHandler = { result in outPut(result.kString, result.kState.rawValue) }
    }

    private override init() { super.init() }

    private func configure(bounds: CGRect, scanFrame: CGRect? = nil , showView: UIView, fpsNum: Int, scanState: QRState, playFeedback: Bool, supportCodeTypes: [AVMetadataObject.ObjectType]?, turnWideAngle: Bool) {
        self.bounds = scanFrame ?? bounds
        self.showView = showView
        self.fpsNum = max(1, min(fpsNum, 60))
        self.scanState = scanState
        self.shouldPlayFeedback = playFeedback
        self.turnWideAngle = turnWideAngle
        self.supportedTypes = QRModel.supportedCodeTypes(for: scanState, optional: supportCodeTypes)

        // 首次使用时系统授权弹窗是异步的，必须等结果回来再装配相机；
        // 已授权时同步回调，行为与旧版一致。
        QRModel.ensureCameraAuthorization { [weak self] granted in
            guard let self = self, granted else { return }
            DispatchQueue.main.async {
                self.prepareCamera(bounds: bounds, scanFrame: scanFrame)
            }
        }
    }

    /// 权限就绪后装配相机。
    ///
    /// 线程分工：
    /// - 预览层是 UI 资产，只在主线程创建、设 frame、挂到视图上；
    /// - 设备配置与 session 装配是阻塞操作，整段丢到 `sessionQueue`；
    /// - `rectOfInterest` 依赖预览层的坐标换算，必须回主线程算，顺序仍在 `startRunning()` 之后。
    private func prepareCamera(bounds: CGRect, scanFrame: CGRect?) {
        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        videoPreviewLayer = preview
        showView?.layer.addSublayer(preview)

        let interestRectSource = scanFrame ?? bounds
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.setupCamera()
            self.captureSession.startRunning()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // 自动变焦控制器在主线程创建并持有：它会被 metadataOutput 的主队列回调读取，
                // 单线程访问才能让「开关」与「评估」不打架。
                if let device = self.device {
                    let autoZoom = QRAutoZoomController(zooming: QRDeviceZooming(device: device))
                    autoZoom.isEnabled = self.autoZoomEnabled
                    self.autoZoomController = autoZoom
                }

                if let layer = self.videoPreviewLayer {
                    self.captureMetadataOutput.rectOfInterest = layer.metadataOutputRectConverted(fromLayerRect: interestRectSource)
                }
            }
        }
    }
    
//        .builtInWideAngleCamera
//        内置广角相机（iPhone/iPad 前后置默认摄像头）
//        .builtInTelephotoCamera
//        内置长焦相机（部分支持多摄的 iPhone）
//        .builtInUltraWideCamera
//        内置超广角相机（iPhone 11 及更新机型）

    private func systemAllDevice() -> AVCaptureDevice? {
        guard turnWideAngle else {
            return AVCaptureDevice.default(for: .video)
        }
        var captureDevice: AVCaptureDevice?
        /// 获取超广角、长焦、普通相机的结合体
        /// 不能获取所有的相机，会导致手机持续扫码的时候，发热严重
        if #available(iOS 13.0, *) {
            /// 获取超广角相机
            captureDevice = AVCaptureDevice.DiscoverySession.init(deviceTypes: [AVCaptureDevice.DeviceType.builtInUltraWideCamera], mediaType: .video, position: .back).devices.first
            if captureDevice == nil {
                /// 获取普通相机
                captureDevice = AVCaptureDevice.default(for: .video)
            }
            
        } else {
            captureDevice = AVCaptureDevice.default(for: .video)
            // Fallback on earlier versions
        }
        return captureDevice
    }
    
    /// 设备配置与 session 装配。**必须在 `sessionQueue` 上调用**，其中每一项都是阻塞操作。
    ///
    /// 这里不再碰任何 UI：预览层由 `prepareCamera` 在主线程创建，失败提示也回主线程弹。
    private func setupCamera() {
        guard let captureDevice = systemAllDevice() else {
            DispatchQueue.main.async { QRModel.showError() }
            return
        }
        do {
            device = captureDevice
            try captureDevice.lockForConfiguration()
            if captureDevice.isFocusModeSupported(.continuousAutoFocus) {
                captureDevice.focusMode = .continuousAutoFocus
            }
            if captureDevice.isExposureModeSupported(.continuousAutoExposure) {
                captureDevice.exposureMode = .continuousAutoExposure
            }
            // 初始倍率与对焦 / 曝光共用同一次 lock，省掉一次 lock / unlock 往返。
            // 取值范围由 [1.0, videoMaxZoomFactor] 钳制 —— 越界会抛不可捕获的 NSRangeException。
            let initialZoom = max(1.0, min(currentZoomFactor, captureDevice.activeFormat.videoMaxZoomFactor))
            captureDevice.videoZoomFactor = initialZoom
            captureDevice.unlockForConfiguration()
            currentZoomFactor = initialZoom

            let input = try AVCaptureDeviceInput(device: captureDevice)
            captureSession.addInput(input)
            captureSession.addOutput(captureMetadataOutput)
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            captureMetadataOutput.metadataObjectTypes = supportedTypes
        } catch {
            #if DEBUG
            print("LinnoQRScan: 相机装配失败 - \(error)")
            #endif
        }
    }

    deinit {
        // 预览层会强持有 session（AVFoundation 实测行为），而它挂在调用方的视图层级上。
        // 不主动摘除的话，QRProxy 释放后相机仍在出图、仍在耗电，且画面残留在屏幕上。
        // 覆盖用的绿框按钮同理，都属于「挂别人视图上的残留」。
        let layer = videoPreviewLayer
        let host = showView
        let tags = tagArray
        DispatchQueue.main.async {
            tags.forEach { host?.viewWithTag($0)?.removeFromSuperview() }
            layer?.removeFromSuperlayer()
        }

        // 即使还有别处持有着预览层，也要保证相机停下来。
        let session = captureSession
        let queue = sessionQueue
        queue.async { if session.isRunning { session.stopRunning() } }

        #if DEBUG
        print("QRProxy -> deinit")
        #endif
    }

    var isIdentification : Bool = true
}

extension QRProxy {
    
    @objc public func start() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    @objc public func stop() {
        // 强持有 session：即使调用方随即释放了 QRProxy，也要保证停止动作真正执行完成，
        // 与原同步实现的语义保持一致。
        let session = captureSession
        sessionQueue.async {
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }
    
    @objc public func pause(_ value: Bool) {
        pause = value
    }

    @objc public func setZoom(factor: CGFloat) {
        guard let device = self.device else { return }

        do {
            try device.lockForConfiguration()

            let zoomFactor = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))
            device.videoZoomFactor = zoomFactor
            currentZoomFactor = zoomFactor

            device.unlockForConfiguration()
        } catch {
            print("Failed to set zoom factor: \(error.localizedDescription)")
        }
    }

    @objc public func currentZoomLevel() -> CGFloat {
        // 以设备实际值为准：自动变焦（或画面 ramp 过程中）不会让这里返回过期数值。
        return device?.videoZoomFactor ?? currentZoomFactor
    }
    
    @objc public func toggleTorch(mode: AVCaptureDevice.TorchMode) {
        guard let device = device, device.hasTorch else { return }
        let newMode: AVCaptureDevice.TorchMode = mode == .auto ? (device.isTorchActive ? .off : .on) : mode
        try? device.lockForConfiguration()
        device.torchMode = newMode
        device.unlockForConfiguration()
    }

    @objc public func isTorchOn() -> Bool {
        device?.isTorchActive ?? false
    }
}

extension QRProxy: AVCaptureMetadataOutputObjectsDelegate {
    
    /// 暂停识别
    private func pausePreviewForHalfSecond(isEnabled: Bool) {
        isIdentification = isEnabled
    }
    
    private func previewConnection() -> Bool {
        isIdentification
    }
    
    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !metadataObjects.isEmpty else { return }
        guard pause == false else { return }

        // 自动变焦只看「这一帧有没有码」，与结果门闩无关：
        // 门闩控制的是产出结果的节奏，而变焦需要尽快把码拉进理想区间，
        // 不应被产出结果后的冷却窗口挡住。
        adjustAutoZoomIfNeeded(with: metadataObjects)

        // 门闩只在「已产出结果、等待恢复」的窗口期关闭。
        // 多帧累积期间必须保持打开，否则 frameBuffer 永远攒不满 fpsNum 帧，识别会彻底停摆。
        guard previewConnection() else { return }

        if fpsNum == 1 {
            pausePreviewForHalfSecond(isEnabled: false)
            processScan(metadataObjects)
        } else {
            frameBuffer.append(metadataObjects)
            guard frameBuffer.count >= fpsNum else { return }
            pausePreviewForHalfSecond(isEnabled: false)
            // 取识别到码数量最多的那一帧
            let bestFrame = frameBuffer.max { $0.count < $1.count } ?? []
            frameBuffer.removeAll()
            displayResults(bestFrame)
        }
    }

    /// 产出结果后统一恢复识别。所有出口都必须走到这里，否则门闩会永久关闭。
    private func scheduleResumeIdentification() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resumeInterval) { [weak self] in
            self?.pausePreviewForHalfSecond(isEnabled: true)
        }
    }

    /// 用当前帧里最宽的那个码评估一次自动变焦。
    ///
    /// 取宽度的依据是**预览层坐标系下的矩形**，不是相机原始像素，
    /// 这样比例阈值才能和用户实际看到的画面一致。
    private func adjustAutoZoomIfNeeded(with objects: [AVMetadataObject]) {
        guard let controller = autoZoomController, controller.isEnabled else { return }
        guard let layer = videoPreviewLayer else { return }

        let widths = objects.compactMap { layer.transformedMetadataObject(for: $0)?.bounds.width }
        guard let proportion = QRAutoZoomPolicy.widestProportion(codeWidths: widths,
                                                                previewWidth: layer.bounds.width) else {
            return
        }

        controller.adjust(codeWidthProportion: proportion)
    }

    private func processScan(_ objects: [AVMetadataObject]) {
        feedback()
        outputHandler(QRModel.singleOutput(from: objects))
        scheduleResumeIdentification()
    }

    private func displayResults(_ objects: [AVMetadataObject]) {
        // 无论中间有多少个提前返回，都必须恢复识别，否则门闩永久关闭。
        defer { scheduleResumeIdentification() }

        guard let showView = showView else { return }
        tagArray.forEach { showView.viewWithTag($0)?.removeFromSuperview() }
        tagArray.removeAll()

        var tag = 100

        for object in objects {
            guard supportedTypes.contains(object.type),
                  let transformed = videoPreviewLayer?.transformedMetadataObject(for: object) else { continue }

            let button = UrlButton(frame: transformed.bounds)
            button.frame.origin.y += (showView.bounds.width / 2 + QRModel.statuHeight())
            button.frame.origin.x += (showView.frame.width - bounds.width) / 2

            if QRModel.coderState(for: object.type) == .Barcodes {
                button.frame.size.height = button.frame.width / 3
                button.center.y -= button.frame.size.height / 2
            }

            if let codeObj = object as? AVMetadataMachineReadableCodeObject {
                button.url = codeObj.stringValue
                button.qrState = QRModel.coderState(for: codeObj.type)
            } else if #available(iOS 13.0, *), let bodyObj = object as? AVMetadataBodyObject {
                button.url = "\(bodyObj.bodyID)"
                button.qrState = QRModel.coderState(for: bodyObj.type)
            }

            button.tag = tag
            tagArray.append(tag)
            tag += 1

            button.layer.borderColor = UIColor.green.cgColor
            button.layer.borderWidth = 2
            button.addTarget(self, action: #selector(handleButtonTap(_:)), for: .touchUpInside)

            showView.addSubview(button)
        }
    }

    @objc private func handleButtonTap(_ sender: UrlButton) {
        tagArray.forEach { showView?.viewWithTag($0)?.removeFromSuperview() }
        tagArray.removeAll()
        frameBuffer.removeAll()
        pausePreviewForHalfSecond(isEnabled: true)
        if let url = sender.url, let state = sender.qrState {
            outputHandler((url, state))
        }
    }

    private func feedback() {
        guard shouldPlayFeedback else { return }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        AudioServicesPlaySystemSound(1109)
    }
}

fileprivate class UrlButton: UIButton {
    var url: String? {
        get { objc_getAssociatedObject(self, &urlKey) as? String }
        set { objc_setAssociatedObject(self, &urlKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    var qrState: QRState? {
        get { objc_getAssociatedObject(self, &qrKey) as? QRState }
        set { objc_setAssociatedObject(self, &qrKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

private var urlKey: Void?
private var qrKey: Void?
