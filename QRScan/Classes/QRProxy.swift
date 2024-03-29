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
    
    private var captureSession = AVCaptureSession()
    
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    
    private var captureMetadataOutput = AVCaptureMetadataOutput()
    
    private var device : AVCaptureDevice?
    
    private var kBounds = UIScreen.main.bounds
    
    private var kShowView : UIView!
    
    private var kSingleClosure:(((kString:String, kState:QRState)) -> Void)?
    
    private var tagArray: Array<Int> = []
    
    private var maxNumAVMetadataObjectArray: Array<[AVMetadataObject]> = []
 
    private var kFpsNum: Int?
    
    private var kScanState: Int?
    
    private var kPlay: Bool = false

    public static var currentView: UIView { QRModel.currentViewController().view }

    public static var currentBounds: CGRect {currentView.bounds }

    /**
     swift convenience init
     - parameter bounds: it's pixels captured by the screen,The position is relative to the background page
     - parameter showView: add AVCaptureVideoPreviewLayer, As a background page
     - parameter fpsNum: Collect fpsNum times and output once ,default is 1, if fpsNum = 10  scan 10 fps show pixels captured
     - parameter sanState: choose enum QRState
     - parameter playSource: play success 'di' and shakes
     - parameter outPut:  result tuple with String & QRState
     */
    
    public convenience init(bounds: CGRect = currentBounds, showView:UIView = currentView ,fpsNum: Int = 1 , sanState:QRState = .All, playSource:Bool = true, outPut:@escaping ((kString:String,kState:QRState)?) -> Void) {
        self.init()
        attributeSet(bounds: bounds, showView: showView, fpsNum: fpsNum, scanState: sanState, play: playSource)
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
        attributeSet(bounds: Self.currentBounds, showView: Self.currentView, fpsNum: 1, scanState: .All, play: true)
        self.kSingleClosure = {kResult in
            outPut(kResult.kString,kResult.kState.rawValue)
        }
    }
    
    /**  oc  convenience init
     - parameter bounds: it's pixels captured by the screen
     - parameter showView: add AVCaptureVideoPreviewLayer
     - parameter fpsNum: Collect fpsNum times and output once ,default is 1, if fpsNum = 10  scan 10 fps show pixels captured
     - parameter sanState: scanState is int = QRState 1~4
     - parameter outPut:  result = String & QRState
        */
    @objc public convenience init( bounds: CGRect = currentBounds,  showView:UIView = currentView, fpsNum: Int = 1, scanState:Int = 7, playSource:Bool = true, outPut:@escaping (_ kString: String, _ kState:Int)-> Void){
        self.init()
        attributeSet(bounds: bounds, showView: showView, fpsNum: fpsNum, scanState:  QRState(rawValue: scanState) ?? .All, play: playSource)
        self.kSingleClosure = { kResult in
            outPut(kResult.kString,kResult.kState.rawValue)
        }
    }
    private func attributeSet(bounds:CGRect,showView:UIView,fpsNum:Int,scanState:QRState,play:Bool){
        guard QRModel.isAuther() else {
            return
        }
        setUI()
        self.kBounds = bounds
        self.kShowView = showView
        self.kFpsNum = fpsNum
        // fps max is 60, 1s = 30fps
        if fpsNum > 60 {
            self.kFpsNum = 60
        }
        if fpsNum <= 0 {
            self.kFpsNum = 1
        }
        self.kPlay = play
        captureMetadataOutput.metadataObjectTypes = QRModel.supportedCodeTypes(scanState: scanState)
        videoPreviewLayer?.frame = CGRect(x: 0, y: 0, width: showView.frame.width, height: showView.frame.height)
        kShowView.layer.addSublayer(videoPreviewLayer!)
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
            let interRect = self.videoPreviewLayer?.metadataOutputRectConverted(fromLayerRect: bounds)
            self.captureMetadataOutput.rectOfInterest = interRect!
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
            captureDevice.unlockForConfiguration()
            // Get an instance of the AVCaptureDeviceInput class using the previous device object.
            let input = try AVCaptureDeviceInput(device: captureDevice)
            
           
            // Set the input device on the capture session.
            captureSession.addInput(input)
            
            // Initialize a AVCaptureMetadataOutput object and set it as the output device to the capture session.
            captureSession.addOutput(captureMetadataOutput)
            // Set delegate and use the default dispatch queue to execute the call back
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
//
        } catch {
            // If any error occurs, simply print it out and don't continue any more.
            print(error)
            return
        }
//            captureDevice.focusMode = .continuousAutoFocus
        // Initialize the video preview layer and add it as a sublayer to the viewPreview view's layer.
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        captureMetadataOutput.rectOfInterest = CGRect(x: 0.2, y: 0.2, width: 0.8, height: 0.8)
//        view.layer.bounds
    }
    
    private override init() {
        super.init()
    }
    deinit{
        print("QRProxy -> deinit")
    }
}
extension  QRProxy:AVCaptureMetadataOutputObjectsDelegate{
    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard  metadataObjects.count != 0 else{
            return
        }
        captureSession.stopRunning()
        // 快速扫描，每一帧都扫到
        guard kFpsNum != 1 else{
            self.feedbackGenerator()
            kSingleClosure!(QRModel.singleOutput(metadataObjects: metadataObjects))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startCurrentDevice()
            }
            return
        }
        // 每隔kFpsNum帧生成一次
        maxNumAVMetadataObjectArray.append(metadataObjects)
        if maxNumAVMetadataObjectArray.count >= kFpsNum! {
            self.feedbackGenerator()
            maxNumAVMetadataObjectArray = maxNumAVMetadataObjectArray.reversed()
            let maxAVMetadataObject = maxNumAVMetadataObjectArray.max { one, two in
                one.count < two.count
            }
            guard maxAVMetadataObject!.count != 1 else{
                if kSingleClosure != nil {
                    kSingleClosure!(QRModel.singleOutput(metadataObjects: maxAVMetadataObject!))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.startCurrentDevice()
                }
                return
            }
            tagArray.removeAll()
            var btnTag = 100
            for metadataItem  in maxAVMetadataObject! {
                if QRModel.supportedCodeTypes(scanState: .All).contains(metadataItem.type) {
                    let barCodeObject = videoPreviewLayer?.transformedMetadataObject(for: metadataItem)
                    let btn = UrlButton.init(frame: barCodeObject!.bounds)
                    //  y 值需加上信息栏的高度
                    //  x 值计算采集区域的大小和展示view的偏差
                    btn.frame.origin.y += (kShowView.bounds.width)/2 + QRModel.statuHeight()
                    btn.frame.origin.x += (kShowView.frame.width - kBounds.width) / 2
                    /// 因为采集到的条形码的高度都在1.3左右，所以设置条形码的高度和位置
                    if QRModel.coderState(objType: metadataItem.type) == .Barcodes {
                        btn.frame.size.height =  btn.frame.size.width / 3
                        btn.center.y -= btn.frame.size.height/2
                    }
                    btn.tag = btnTag
                    
                    if metadataItem is  AVMetadataMachineReadableCodeObject{
                        let metadataObj = metadataItem as! AVMetadataMachineReadableCodeObject
                        btn.url = metadataObj.stringValue
                        btn.qrState = QRModel.coderState(objType: metadataObj.type)
                    }else{
                        if #available(iOS 13.0, *) {
                            let metadataObj = metadataItem as! AVMetadataBodyObject
                            btn.url = String("\(metadataObj.bodyID)")
                            btn.qrState = QRModel.coderState(objType: metadataObj.type)
                        }
                    }
                    btn.addTarget(self, action: #selector(chooseButtonClick(_:)), for: .touchUpInside)
                    btn.layer.borderColor = UIColor.green.cgColor
                    btn.layer.borderWidth = 2
                    tagArray.append(btnTag)
                    btnTag += 1
                    kShowView.addSubview(btn)
                }
            }
        }
        
    }
    @objc fileprivate func chooseButtonClick(_ btn:UrlButton){
        _ = tagArray.map { num in
            let button = kShowView.viewWithTag(num)
            button?.removeFromSuperview()
        }
        captureSession.startRunning()
        maxNumAVMetadataObjectArray.removeAll(keepingCapacity: true)
        tagArray.removeAll(keepingCapacity: true)
        if kSingleClosure != nil {
            kSingleClosure!((btn.url,btn.qrState) as! (kString: String, kState: QRState))
        }
    }
}
extension QRProxy{
     func feedbackGenerator() {
         guard self.kPlay else {

             return
         }
         // 震动
         AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
         // 声音
         AudioServicesPlaySystemSound(1109)
    }
}

fileprivate class UrlButton: UIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
private var urlKey: Void?

private var qrKey: Void?

fileprivate extension UrlButton {
    var url: String?{
        get {
            return objc_getAssociatedObject(self, &urlKey) as? String
        }
        set {
            objc_setAssociatedObject(self, &urlKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    var qrState: QRState?{
        get {
            return objc_getAssociatedObject(self, &qrKey) as? QRState
        }
        set {
            objc_setAssociatedObject(self, &qrKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}
