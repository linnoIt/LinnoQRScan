//
//  QRProxy.swift
//  QR
//
//  Created by 韩增超 on 2022/9/20.
//

import Foundation
import AVFoundation
import UIKit

// Define constants used within the class
private enum QRProxyConstants {
    static let defaultFpsNum = 1
    static let maxFpsNum = 60
    static let soundIDBeep: SystemSoundID = 1109 // Standard beep sound
    static let initialButtonTag = 100
    static let qrCodeBorderColor = UIColor.green.cgColor
    static let qrCodeBorderWidth: CGFloat = 2.0
    static let defaultRectOfInterest = CGRect(x: 0.2, y: 0.2, width: 0.8, height: 0.8) // Default scanning area
    
    // AutoFocus Zoom Constants
    static let idealQRCodeWidthMinProportion: CGFloat = 0.25 // Ideal QR code width min proportion of preview width
    static let idealQRCodeWidthMaxProportion: CGFloat = 0.45 // Ideal QR code width max proportion of preview width
    static let zoomFactorStep: CGFloat = 0.3 // Zoom factor adjustment step
    static let zoomAdjustmentRate: Float = 3.0 // Rate for ramp(toVideoZoomFactor:withRate:)
    static let minZoomAdjustmentInterval: TimeInterval = 0.5 // Minimum interval between zoom adjustments (seconds)
    static let minZoomFactorChangeThreshold: CGFloat = 0.05 // Minimum change in zoom factor to apply adjustment

    // Keys for associated objects
    static var urlAssociationKey: UInt8 = 0
    static var qrStateAssociationKey: UInt8 = 0
}

open class QRProxy: NSObject {
    
    private var captureSession = AVCaptureSession()
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var captureMetadataOutput = AVCaptureMetadataOutput()
    private var device : AVCaptureDevice?
    
    // AutoFocus Zoom Properties
    public var isAutoFocusZoomEnabled: Bool = false
    private var maxZoomFactor: CGFloat = 1.0
    private var currentZoomFactor: CGFloat = 1.0
    private var lastZoomAdjustmentTime: Date = Date.distantPast
    
    private var kBounds = UIScreen.main.bounds
    // kShowView should be optional or checked before use if it's implicitly unwrapped
    private var kShowView : UIView?
    
    // Closure type now accepts an optional tuple, matching QRModel.singleOutput's new return type
    private var kSingleClosure:(((kString:String, kState:QRState)?) -> Void)?
    
    private var tagArray: Array<Int> = []
    private var maxNumAVMetadataObjectArray: Array<[AVMetadataObject]> = []
 
    private var kFpsNum: Int = QRProxyConstants.defaultFpsNum // Provide a default value
    private var kScanState: QRState = .All // Provide a default value
    private var kPlay: Bool = false

    // Safely unwrap QRModel.currentViewController() and its view
    public static var currentView: UIView? { QRModel.currentViewController()?.view }

    // Safely unwrap currentView and its bounds
    public static var currentBounds: CGRect? { currentView?.bounds }

    /**
     swift convenience init
     - parameter bounds: it's pixels captured by the screen,The position is relative to the background page
     - parameter showView: add AVCaptureVideoPreviewLayer, As a background page
     - parameter fpsNum: Collect fpsNum times and output once ,default is 1, if fpsNum = 10  scan 10 fps show pixels captured
     - parameter sanState: choose enum QRState
     - parameter playSource: play success 'di' and shakes
     - parameter outPut:  result tuple with String & QRState
     */
    // Updated default values for bounds and showView to handle optionals
    public convenience init(bounds: CGRect? = Self.currentBounds, showView:UIView? = Self.currentView ,fpsNum: Int = QRProxyConstants.defaultFpsNum , sanState:QRState = .All, playSource:Bool = true, outPut:@escaping ((kString:String,kState:QRState)?) -> Void) {
        self.init()
        // Ensure bounds and showView are not nil before proceeding
        guard let validBounds = bounds, let validShowView = showView else {
            print("Error: Bounds or ShowView is nil during QRProxy initialization.")
            // Consider calling outPut with nil or an error state if appropriate
            // outPut(nil) 
            return
        }
        attributeSet(bounds: validBounds, showView: validShowView, fpsNum: fpsNum, scanState: sanState, play: playSource)
        self.kSingleClosure = outPut
    }
    /**
     no  parameter  convenience init
     showView = current view
     bounds = current view bounds
     fpsNum = 1
     sanState = (swift = all) (oc = 4)
     playSource = true
     */
    @objc public convenience init(outPut:@escaping ( _ kString: String,  _ kState:Int)-> Void){
        self.init()
        guard let validBounds = Self.currentBounds, let validShowView = Self.currentView else {
            print("Error: Could not get current bounds or view for QRProxy OC initialization.")
            // Handle error: perhaps by not setting up the capture session or calling output with an error.
            return
        }
        attributeSet(bounds: validBounds, showView: validShowView, fpsNum: QRProxyConstants.defaultFpsNum, scanState: .All, play: true)
        self.kSingleClosure = { kResultOptional in
            // Safely unwrap the result from QRModel.singleOutput
            if let kResult = kResultOptional {
                outPut(kResult.kString, kResult.kState.rawValue)
            }
            // Else: QRModel.singleOutput returned nil, decide if outPut should be called with default/error values or not at all
        }
    }
    
    /**  oc  convenience init
     - parameter bounds: it's pixels captured by the screen
     - parameter showView: add AVCaptureVideoPreviewLayer
     - parameter fpsNum: Collect fpsNum times and output once ,default is 1, if fpsNum = 10  scan 10 fps show pixels captured
     - parameter sanState: scanState is int = QRState 1~4
     - parameter outPut:  result = String & QRState
        */
    @objc public convenience init( bounds: CGRect? = Self.currentBounds,  showView:UIView? = Self.currentView, fpsNum: Int = QRProxyConstants.defaultFpsNum, scanState:Int = QRState.All.rawValue, playSource:Bool = true, outPut:@escaping (_ kString: String, _ kState:Int)-> Void){
        self.init()
        guard let validBounds = bounds, let validShowView = showView else {
            print("Error: Bounds or ShowView is nil during QRProxy OC initialization.")
            return
        }
        attributeSet(bounds: validBounds, showView: validShowView, fpsNum: fpsNum, scanState:  QRState(rawValue: scanState) ?? .All, play: playSource)
        self.kSingleClosure = { kResultOptional in
            // Safely unwrap the result from QRModel.singleOutput
            if let kResult = kResultOptional {
                outPut(kResult.kString, kResult.kState.rawValue)
            }
        }
    }
    private func attributeSet(bounds:CGRect,showView:UIView,fpsNum:Int,scanState:QRState,play:Bool){
        guard QRModel.isAuther() else {
            // If authorization fails, QRModel.isAuther() already handles user notification.
            return
        }
        setUI() // This method sets up videoPreviewLayer.
        
        // Ensure videoPreviewLayer is available after setUI()
        guard let previewLayer = self.videoPreviewLayer else {
            print("Error: videoPreviewLayer not initialized after setUI(). Cannot proceed with attributeSet.")
            QRModel.showError() // Show generic camera error.
            return
        }

        self.kBounds = bounds
        self.kShowView = showView
        
        // Validate fpsNum
        if fpsNum > QRProxyConstants.maxFpsNum {
            self.kFpsNum = QRProxyConstants.maxFpsNum
        } else if fpsNum <= 0 {
            self.kFpsNum = QRProxyConstants.defaultFpsNum
        } else {
            self.kFpsNum = fpsNum
        }
        
        self.kPlay = play
        self.kScanState = scanState // Store scanState
        captureMetadataOutput.metadataObjectTypes = QRModel.supportedCodeTypes(scanState: scanState)
        
        previewLayer.frame = CGRect(x: 0, y: 0, width: showView.frame.width, height: showView.frame.height)
        // kShowView is already validated in the convenience init, or should be made optional.
        // Assuming kShowView is valid here due to earlier guards in init.
        showView.layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
            // Safely calculate rectOfInterest
            let interRect = previewLayer.metadataOutputRectConverted(fromLayerRect: bounds)
            self.captureMetadataOutput.rectOfInterest = interRect // rectOfInterest is not optional.
        }
    }
    
    @objc public func stopCurrentDevice(){
        captureSession.stopRunning()
    }
    @objc public func startCurrentDevice(){
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    /** install flash on off*/
    @objc public func trunOffDevice(touchMode: AVCaptureDevice.TorchMode){
        var mode:AVCaptureDevice.TorchMode = touchMode
        if mode == .auto{
            mode = isFlashed() ? .off : .on
        }
        try? device?.lockForConfiguration()
        device?.torchMode = mode
        device?.unlockForConfiguration()
    }
    
    @objc public func isFlashed() -> Bool{
        return device?.isTorchActive ?? false
    }
    private func setUI(){
        guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
            QRModel.showError()
            return
        }
        do {
            device = captureDevice
            try captureDevice.lockForConfiguration()
            captureDevice.focusMode = .continuousAutoFocus
            // Store max zoom factor and current zoom factor
            self.maxZoomFactor = captureDevice.activeFormat.videoMaxZoomFactor
            self.currentZoomFactor = captureDevice.videoZoomFactor
            captureDevice.unlockForConfiguration()
            
            // Get an instance of the AVCaptureDeviceInput class using the previous device object.
            let input = try AVCaptureDeviceInput(device: captureDevice)
            
           
            // Set the input device on the capture session.
            captureSession.addInput(input)
            
            // Initialize a AVCaptureMetadataOutput object and set it as the output device to the capture session.
            captureSession.addOutput(captureMetadataOutput)
            // Set delegate and use the default dispatch queue to execute the call back
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)

        } catch {
            // If any error occurs, print it out and don't continue any more.
            print("Error setting up camera input: \(error)")
            QRModel.showError() // Show a generic error message to the user
            return
        }
        // Initialize the video preview layer and add it as a sublayer to the viewPreview view's layer.
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        // Set a default rectOfInterest, this can be overridden by attributeSet if bounds are provided
        captureMetadataOutput.rectOfInterest = QRProxyConstants.defaultRectOfInterest
    }
    
    private override init() {
        super.init()
    }
    // Removed deinit print statement
    deinit {
        // Perform cleanup if necessary, e.g., stop capture session
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
}
extension  QRProxy:AVCaptureMetadataOutputObjectsDelegate{
    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !metadataObjects.isEmpty else { return }

        captureSession.stopRunning()

        if kFpsNum == QRProxyConstants.defaultFpsNum {
            processFrame(metadataObjects, isSingleFrameMode: true)
        } else {
            maxNumAVMetadataObjectArray.append(metadataObjects)
            guard maxNumAVMetadataObjectArray.count >= kFpsNum else {
                startCurrentDevice() // Not enough frames yet, restart and continue collecting
                return
            }
            
            // Process the richest frame from the accumulated ones
            if let richestFrame = maxNumAVMetadataObjectArray.max(by: { $0.count < $1.count }), !richestFrame.isEmpty {
                processFrame(richestFrame, isSingleFrameMode: false)
            } else {
                // Should not happen if initial metadataObjects was not empty, but as a fallback:
                startCurrentDevice()
            }
            maxNumAVMetadataObjectArray.removeAll() // Clear for the next batch
        }
    }

    /// Processes a given frame (set of metadata objects), whether in single frame mode or from batched frames.
    /// - Parameters:
    ///   - frameObjects: The metadata objects to process for this frame.
    ///   - isSingleFrameMode: True if processing is for kFpsNum == 1, false otherwise (affects restart logic mainly).
    private func processFrame(_ frameObjects: [AVMetadataObject], isSingleFrameMode: Bool) {
        if let firstObject = frameObjects.first {
            adjustZoom(basedOn: firstObject)
        }
        
        self.feedbackGenerator()

        if frameObjects.count == 1 {
            if let closure = kSingleClosure {
                closure(QRModel.singleOutput(metadataObjects: frameObjects))
            }
            // For single object found (either in single frame mode or richest frame), restart capture after a delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startCurrentDevice()
            }
        } else if frameObjects.count > 1 {
            // Multiple objects found (can only happen if isSingleFrameMode is false, or if initial frame had multiple)
            // If it was single frame mode but somehow multiple objects (e.g. from a single hardware frame),
            // this will still create buttons. This might be desired or not.
            // Current logic: if kFpsNum = 1, it implies objectsToProcess.count is from a single hardware capture,
            // and if that single capture has multiple QR codes, this will create buttons.
            handleMultipleMetadataObjects(frameObjects)
        } else {
             // No objects to process (e.g. richestFrame was empty after all, though guarded against)
             // Or if frameObjects was somehow empty.
            if isSingleFrameMode { // If it was supposed to be a single frame, restart.
                 DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.startCurrentDevice()
                }
            } else { // If part of batch processing and ended up with no objects, just ensure we can scan again.
                startCurrentDevice()
            }
        }
    }

    /// Handles the creation of interactive buttons when multiple QR codes/barcodes are detected.
    /// - Parameter metadataObjects: The array of AVMetadataObject, each representing a detected code.
    private func handleMultipleMetadataObjects(_ metadataObjects: [AVMetadataObject]) {
        tagArray.removeAll()
        var currentButtonTag = QRProxyConstants.initialButtonTag
        
        guard let showView = self.kShowView, let previewLayer = self.videoPreviewLayer else {
            // If showView or previewLayer is nil, we cannot proceed to create and place buttons.
            // Restart capture to allow re-initialization or recovery if possible.
            startCurrentDevice()
            return
        }

        for metadataItem in metadataObjects { // Changed from richestFrameObjects to metadataObjects parameter
            // Ensure the metadata type is supported. Use the stored kScanState.
            if QRModel.supportedCodeTypes(scanState: kScanState).contains(metadataItem.type) {
                guard let barCodeObject = previewLayer.transformedMetadataObject(for: metadataItem) else {
                    continue // Skip if we can't transform this specific metadata item
                }

                let btn = UrlButton(frame: barCodeObject.bounds)
                
                // Corrected button positioning:
                // The barCodeObject.bounds are already in the coordinate system of the previewLayer (which is kShowView).
                // The primary adjustment needed is for the status bar height if coordinates are meant to be screen-relative
                // or if the showView is itself offset by the status bar.
                // However, buttons are added to showView, so their frames should be relative to showView's bounds.
                // The original xOffset and yOffset calculations seemed to try to align with a kBounds rect
                // that might be different from showView.bounds. Assuming transformedMetadataObject gives correct
                // bounds relative to previewLayer, further complex offsets are likely incorrect unless
                // kShowView itself is not full-screen or not aligned with the screen origin.

                // Simplification: Use barCodeObject.bounds directly. If status bar compensation is truly needed
                // for positioning within showView (e.g. if showView is fullscreen and content should avoid status bar),
                // it should be applied explicitly.
                // For now, let's assume barCodeObject.bounds is the intended frame within showView.
                // If QRModel.statuHeight() is universally needed for all buttons, it can be added.
                // btn.frame.origin.y += QRModel.statuHeight() // Example if status bar always pushes content down.

                // The original logic for adjusting barcode button height:
                if QRModel.coderState(objType: metadataItem.type) == .Barcodes {
                    // This adjustment resizes the button for barcode types to be wider than they are tall.
                    btn.frame.size.height = btn.frame.size.width / 3
                    // The following line adjusts the vertical center of the button.
                    // If barCodeObject.bounds.origin.y is the top of the detected barcode,
                    // and the new height is smaller, this moves the button upwards relative to its original top position
                    // to keep its new center roughly aligned with where its old center would have been if it was taller,
                    // or effectively shifting it up.
                    // This specific visual adjustment should be verified based on desired UI behavior.
                    btn.center.y -= btn.frame.size.height / 2
                }
                
                btn.tag = currentButtonTag
                
                // Safely extract stringValue or bodyID
                if let machineReadableObj = metadataItem as? AVMetadataMachineReadableCodeObject,
                   let stringValue = machineReadableObj.stringValue {
                    btn.url = stringValue
                    btn.qrState = QRModel.coderState(objType: machineReadableObj.type)
                } else if #available(iOS 13.0, *), let bodyObj = metadataItem as? AVMetadataBodyObject {
                    btn.url = String(bodyObj.bodyID)
                    btn.qrState = QRModel.coderState(objType: bodyObj.type)
                } else {
                    continue // Skip if no usable data
                }
                
                btn.addTarget(self, action: #selector(chooseButtonClick(_:)), for: .touchUpInside)
                btn.layer.borderColor = QRProxyConstants.qrCodeBorderColor
                btn.layer.borderWidth = QRProxyConstants.qrCodeBorderWidth
                tagArray.append(currentButtonTag)
                currentButtonTag += 1
                showView.addSubview(btn)
            }
        }
        // If no buttons were added (e.g. all items filtered out), restart capture
        if tagArray.isEmpty {
            startCurrentDevice()
        }
    }
    
    @objc fileprivate func chooseButtonClick(_ btn:UrlButton){
        // Safely remove buttons from kShowView
        if let showView = self.kShowView {
            for num in tagArray {
                showView.viewWithTag(num)?.removeFromSuperview()
            }
        }
        
        startCurrentDevice() // Restart capture session
        maxNumAVMetadataObjectArray.removeAll(keepingCapacity: true)
        tagArray.removeAll(keepingCapacity: true)
        
        // Safely call kSingleClosure with button's data
        if let closure = kSingleClosure, let url = btn.url, let qrState = btn.qrState {
            closure((kString: url, kState: qrState))
        } else if let closure = kSingleClosure {
            // If url or qrState is nil, decide on behavior: call with nil or default, or don't call.
            // Current kSingleClosure type allows nil tuple.
            closure(nil)
        }
    }
    
    // MARK: - AutoFocus Zoom Logic
    /// Adjusts the camera's zoom factor based on the size and position of the detected QR code.
    /// - Parameter metadataObject: The `AVMetadataObject` detected, expected to be a machine-readable code.
    private func adjustZoom(basedOn metadataObject: AVMetadataObject) {
        guard isAutoFocusZoomEnabled,
              let device = self.device,
              // Ensure device supports zoom by checking if maxZoomFactor is greater than 1.0.
              // self.maxZoomFactor is initialized from device.activeFormat.videoMaxZoomFactor in setUI().
              self.maxZoomFactor > 1.0, 
              Date().timeIntervalSince(lastZoomAdjustmentTime) > QRProxyConstants.minZoomAdjustmentInterval,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let previewLayer = self.videoPreviewLayer, // Video preview layer must be available.
              // Transform the metadata object's coordinates to the preview layer's coordinate system.
              let transformedObject = previewLayer.transformedMetadataObject(for: readableObject) else {
            return // Conditions for zoom adjustment not met.
        }

        let previewWidth = previewLayer.bounds.width
        guard previewWidth > 0 else { return }

        let qrCodeWidth = transformedObject.bounds.width
        let qrCodeProportion = qrCodeWidth / previewWidth
        
        var targetZoomFactor = self.currentZoomFactor
        
        if qrCodeProportion < QRProxyConstants.idealQRCodeWidthMinProportion && self.currentZoomFactor < maxZoomFactor {
            // QR code is too small (far), zoom in
            targetZoomFactor = min(self.currentZoomFactor + QRProxyConstants.zoomFactorStep, maxZoomFactor)
        } else if qrCodeProportion > QRProxyConstants.idealQRCodeWidthMaxProportion && self.currentZoomFactor > 1.0 {
            // QR code is too large (close), zoom out
            targetZoomFactor = max(self.currentZoomFactor - QRProxyConstants.zoomFactorStep, 1.0)
        } else {
            // QR code is within the ideal size range, or cannot zoom further.
            // If no adjustment needed, ensure device restarts if it was stopped for this check.
            // However, this specific return should not prevent restarting the session if it was stopped for processing.
            return
        }
        
        // Apply adjustment only if the change is significant
        guard abs(targetZoomFactor - self.currentZoomFactor) > QRProxyConstants.minZoomFactorChangeThreshold else {
             // Even if no zoom change, session might need restart if processing is done.
            return
        }
        
        do {
            try device.lockForConfiguration()
            device.ramp(toVideoZoomFactor: targetZoomFactor, withRate: QRProxyConstants.zoomAdjustmentRate)
            device.unlockForConfiguration()
            self.currentZoomFactor = targetZoomFactor // Update current zoom factor
            self.lastZoomAdjustmentTime = Date() // Record adjustment time
        } catch {
            print("Error while trying to lock device for configuration for zoom: \(error)")
            // If lock fails, ensure session restarts if needed.
        }
    }
}
extension QRProxy{
     func feedbackGenerator() {
         guard self.kPlay else {
             return
         }
         // Vibrate - kSystemSoundID_Vibrate is a system constant.
         AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
         // Play beep sound using the defined constant
         AudioServicesPlaySystemSound(QRProxyConstants.soundIDBeep)
    }
}

fileprivate class UrlButton: UIButton {

    // Added override keyword
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    // Added override keyword
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// Use static vars for association keys to ensure uniqueness.
// private var urlKey: Void? // Replaced by QRProxyConstants
// private var qrKey: Void?  // Replaced by QRProxyConstants

fileprivate extension UrlButton {
    var url: String?{
        get {
            // Use the defined constant for the key and perform safe casting
            return objc_getAssociatedObject(self, &QRProxyConstants.urlAssociationKey) as? String
        }
        set {
            // Use the defined constant for the key
            objc_setAssociatedObject(self, &QRProxyConstants.urlAssociationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    var qrState: QRState?{
        get {
            // Use the defined constant for the key and perform safe casting
            return objc_getAssociatedObject(self, &QRProxyConstants.qrStateAssociationKey) as? QRState
        }
        set {
            // Use the defined constant for the key
            objc_setAssociatedObject(self, &QRProxyConstants.qrStateAssociationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
