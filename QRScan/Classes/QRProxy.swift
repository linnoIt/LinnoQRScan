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
    
    public static var currentView: UIView { QRModel.currentViewController()?.view ?? UIView()}
    public static var currentBounds: CGRect { currentView.bounds }

    public convenience init(
        bounds: CGRect = QRProxy.currentBounds,
        scanFrame: CGRect? = nil,
        showView: UIView = QRProxy.currentView,
        fpsNum: Int = 1,
        scanState: QRState = .All,
        playSource: Bool = true,
        supportCodeTypes: [AVMetadataObject.ObjectType]? = nil,
        outPut: @escaping ((kString: String, kState: QRState)) -> Void
    ) {
        self.init()
        self.configure(bounds: bounds, scanFrame: scanFrame, showView: showView, fpsNum: fpsNum, scanState: scanState, playFeedback: playSource, supportCodeTypes: supportCodeTypes)
        self.outputHandler = outPut
    }

    @objc public convenience init(outPut: @escaping (_ kString: String, _ kState: Int) -> Void) {
        self.init()
        self.configure(bounds: Self.currentBounds, showView: Self.currentView, fpsNum: 1, scanState: .All, playFeedback: true, supportCodeTypes: nil)
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
        outPut: @escaping (_ kString: String, _ kState: Int) -> Void
    ) {
        self.init()
        let kScanFrame: CGRect? = scanFrame == .zero ? nil : scanFrame
        self.configure(bounds: bounds, scanFrame: kScanFrame, showView: showView, fpsNum: fpsNum, scanState: QRState(rawValue: scanState) ?? .All, playFeedback: playSource, supportCodeTypes: supportCodeTypes)
        self.outputHandler = { result in outPut(result.kString, result.kState.rawValue) }
    }

    private override init() { super.init() }

    private func configure(bounds: CGRect, scanFrame: CGRect? = nil , showView: UIView, fpsNum: Int, scanState: QRState, playFeedback: Bool, supportCodeTypes: [AVMetadataObject.ObjectType]?) {
        guard QRModel.isAuther() else { return }
        
        self.bounds = scanFrame ?? bounds
        self.showView = showView
        self.fpsNum = max(1, min(fpsNum, 60))
        self.scanState = scanState
        self.shouldPlayFeedback = playFeedback

        setupCamera(supportCodeTypes: supportCodeTypes)

        videoPreviewLayer?.frame = bounds
        if let preview = videoPreviewLayer { showView.layer.addSublayer(preview) }

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
            if let interRect = self.videoPreviewLayer?.metadataOutputRectConverted(fromLayerRect: scanFrame ?? bounds) {
                self.captureMetadataOutput.rectOfInterest = interRect
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
    
    private func setupCamera(supportCodeTypes: [AVMetadataObject.ObjectType]?) {
        guard let captureDevice = systemAllDevice() else {
            QRModel.showError()
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
            captureDevice.unlockForConfiguration()

            let input = try AVCaptureDeviceInput(device: captureDevice)
            captureSession.addInput(input)
            captureSession.addOutput(captureMetadataOutput)
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            captureMetadataOutput.metadataObjectTypes = QRModel.supportedCodeTypes(for: scanState, optional: supportCodeTypes)

            let preview = AVCaptureVideoPreviewLayer(session: captureSession)
            preview.videoGravity = .resizeAspectFill
            videoPreviewLayer = preview
            setZoom(factor: currentZoomFactor)
        } catch {
            print("Camera setup error: \(error)")
        }
    }

    deinit { print("QRProxy -> deinit") }
    
    var isIdentification : Bool = true
}

extension QRProxy {
    
    @objc public func start() {
        guard !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { self.captureSession.startRunning() }
    }

    @objc public func stop() {
        guard captureSession.isRunning else { return }
        captureSession.stopRunning()
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
        return currentZoomFactor
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
        guard previewConnection() else { return }
        pausePreviewForHalfSecond(isEnabled: false)

        if fpsNum == 1 {
            processScan(metadataObjects)
        } else {
            frameBuffer.append(metadataObjects)
            if frameBuffer.count >= fpsNum {
                let bestFrame = frameBuffer.max { $0.count < $1.count } ?? []
                frameBuffer.removeAll()
                displayResults(bestFrame)
            }
        }
    }

    private func processScan(_ objects: [AVMetadataObject]) {
        feedback()
        outputHandler(QRModel.singleOutput(from: objects))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.pausePreviewForHalfSecond(isEnabled: true)
        }
    }

    private func displayResults(_ objects: [AVMetadataObject]) {
        guard let showView = showView else { return }
        tagArray.forEach { showView.viewWithTag($0)?.removeFromSuperview() }
        tagArray.removeAll()

        var tag = 100

        for object in objects {
            guard QRModel.supportedCodeTypes(for: .All).contains(object.type),
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
