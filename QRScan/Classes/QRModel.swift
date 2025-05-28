//
//  QRModel.swift
//  QRCodeReader
//
//  Created by 韩增超 on 2022/9/14.
//  Copyright © 2022 AppCoda. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation


public enum QRState:Int {
    case Barcodes = 1
    case Codes2D = 2
    case Bodies = 3
    case Barcodes_Codes2D = 4
    case Barcodes_Bodies = 5
    case Codes2D_Bodies = 6
    case All = 7
    // Simplified init by removing the temporary kState variable
    public init?(rawValue: Int) {
        switch rawValue {
        case 1: self = .Barcodes
        case 2: self = .Codes2D
        case 3: self = .Bodies
        case 4: self = .Barcodes_Codes2D
        case 5: self = .Barcodes_Bodies
        case 6: self = .Codes2D_Bodies
        default: self = .All
        }
    }
}

// Struct to hold localized strings or constants for UI elements
private enum UILabels {
    static let errorTitle = "Error"
    static let doneButton = "Done"
    static let cancelButton = "cancel"
    static let noCameraPermissionMessage = "No camera permission was granted"
    static let failedToGetCameraMessage = "Failed to get the camera device"
    static let defaultScanErrorMessage = "Unable to parse QR code or barcode."
}


struct QRModel {
     static func isAuther() -> Bool{
        let deviceStatus = AVCaptureDevice.authorizationStatus(for: .video)
         guard (deviceStatus == .authorized || deviceStatus == .notDetermined)  else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                DispatchQueue.main.async {
                    // Safely unwrap currentViewController
                    guard let currentVC = QRModel.currentViewController() else {
                        // Log error or handle missing view controller
                        print("\(UILabels.errorTitle): Could not get current view controller in isAuther.")
                        return
                    }
                    currentVC.dismiss(animated: true) {
                        let alertView = UIAlertController.init(title: UILabels.errorTitle, message: UILabels.noCameraPermissionMessage, preferredStyle: .alert)
                        let doneAction = UIAlertAction.init(title: UILabels.doneButton, style: .default) { _ in
                            // Safely unwrap URL for settings
                            guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
                                print("\(UILabels.errorTitle): Invalid settings URL string.")
                                return
                            }
                            UIApplication.shared.open(settingsUrl)
                        }
                        let cancelAction = UIAlertAction.init(title: UILabels.cancelButton, style: .cancel)
                        alertView.addAction(doneAction)
                        alertView.addAction(cancelAction)
                        // Safely unwrap currentViewController again for presenting the alert
                        guard let vcForAlert = QRModel.currentViewController() else {
                             print("\(UILabels.errorTitle): Could not get current view controller to present alert in isAuther.")
                            return
                        }
                        vcForAlert.present(alertView, animated: true)
                    }
                }
            }
            return false
        }
        return true
    }
    static func showError(){
        // Safely unwrap currentViewController
        guard let currentVC = QRModel.currentViewController() else {
            // Log error or handle missing view controller
            print("\(UILabels.errorTitle): Could not get current view controller in showError.")
            return
        }
        currentVC.dismiss(animated: true) {
            let alertView = UIAlertController.init(title: UILabels.errorTitle, message: UILabels.failedToGetCameraMessage, preferredStyle: .alert)
            let doneAction = UIAlertAction.init(title: UILabels.doneButton, style: .default) { _ in
                // Safely unwrap currentViewController again for dismissing
                 guard let vcToDismiss = QRModel.currentViewController() else {
                    print("\(UILabels.errorTitle): Could not get current view controller to dismiss alert in showError.")
                    return
                }
                vcToDismiss.dismiss(animated: true)
            }
            alertView.addAction(doneAction)
            // Safely unwrap currentViewController again for presenting the alert
            guard let vcForAlert = QRModel.currentViewController() else {
                 print("\(UILabels.errorTitle): Could not get current view controller to present alert in showError.")
                return
            }
            vcForAlert.present(alertView, animated: true)
        }
    }
    static func statuHeight() -> CGFloat {
        if #available(iOS 13.0, *) {
            let set = UIApplication.shared.connectedScenes
            // Safely unwrap the first window scene
            guard let windowScene = set.first as? UIWindowScene else {
                // Provide a fallback height or handle the error appropriately
                return 68.0 // Default or fallback height
            }
            return windowScene.statusBarManager?.statusBarFrame.size.height ?? 68.0
        } else {
            return UIApplication.shared.statusBarFrame.size.height;
        }
    }
    // Updated to return UIViewController? to reflect that a view controller might not always be found.
    // Refactored for clarity using a switch statement for base view controller types.
    static func currentViewController() -> UIViewController?  {
        // Helper recursive function to find the top-most view controller.
        func findTopViewController(base: UIViewController?) -> UIViewController? {
            guard let controller = base else { return nil }

            // Switch on the type of the base controller to navigate the hierarchy.
            switch controller {
            case let navCtl as UINavigationController:
                // If it's a navigation controller, recurse on its visible view controller.
                return findTopViewController(base: navCtl.visibleViewController)
            case let tabCtl as UITabBarController:
                // If it's a tab bar controller, recurse on its selected view controller.
                // Ensure selectedViewController is not nil before recursing.
                return findTopViewController(base: tabCtl.selectedViewController)
            case let splitCtl as UISplitViewController:
                 // For UISplitViewController, prefer the last view controller in the `viewControllers` array
                 // as it's often the most relevant content view.
                 // Fallback to presentingViewController if that's more appropriate in some contexts,
                 // but `viewControllers.last` is generally more robust for typical split view setups.
                 // Note: `presentingViewController` for a root split view controller is often nil.
                return findTopViewController(base: splitCtl.viewControllers.last)
            default:
                // If the controller has a presented view controller, recurse on that.
                if let presented = controller.presentedViewController {
                    return findTopViewController(base: presented)
                }
                // Otherwise, this is the top-most controller we can find.
                return controller
            }
        }

        // Start the search from the root view controller of the current key window.
        guard let rootVC = currentWindow()?.rootViewController else {
            print("\(UILabels.errorTitle): Root view controller not found in currentWindow.")
            return nil
        }
        return findTopViewController(base: rootVC)
    }

    // Refactored to use modern APIs for window retrieval where possible and clarify logic.
    static func currentWindow() -> UIWindow? {
        var currentWindow: UIWindow?

        if #available(iOS 15.0, *) {
            // For iOS 15 and later, directly access the keyWindow of the first active UIWindowScene.
            currentWindow = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive })
                .flatMap({ $0 as? UIWindowScene })?
                .keyWindow
        } else if #available(iOS 13.0, *) {
            // For iOS 13 and 14, find the first active UIWindowScene and then its first key window.
            currentWindow = UIApplication.shared.connectedScenes
                .filter { $0.activationState == .foregroundActive }
                .compactMap { $0 as? UIWindowScene }
                .first?
                .windows
                .first(where: \.isKeyWindow)
        }

        // Fallback for older iOS versions (before 13) or if the above methods fail.
        // UIApplication.shared.windows.first(where: \.isKeyWindow) can also be used for iOS < 13 if scene delegate is not used.
        if currentWindow == nil {
             if #available(iOS 13.0, *) {
                 // This is a broader fallback for iOS 13+ if the specific key window isn't found via active scene.
                 currentWindow = UIApplication.shared.windows.first(where: \.isKeyWindow)
             } else {
                 // Legacy way for iOS < 13.
                 currentWindow = UIApplication.shared.keyWindow
             }
        }
      
        // Final fallback to the delegate's window if still no window is found.
        if currentWindow == nil {
            currentWindow = UIApplication.shared.delegate?.window ?? nil
        }
        
        if currentWindow == nil {
             print("Warning: Could not find current window.")
        }
        return currentWindow
    }
    
    static func deviceOrientation(connection:AVCaptureConnection) -> UIDeviceOrientation{
        
      let currentDevice: UIDevice = UIDevice.current
      let orientation: UIDeviceOrientation = currentDevice.orientation
      let previewLayerConnection : AVCaptureConnection = connection
      
      if previewLayerConnection.isVideoOrientationSupported {
          return orientation
      }
        return UIDeviceOrientation.unknown
    }
    
    @available(iOS 13.0, *)
    private static func supportedCodeTypesCodesBodies() -> [AVMetadataObject.ObjectType]{[
        /** 人脸识别？*/
        .humanBody,
        .dogBody // Removed duplicate .dogBody
    ]}
    private static func supportedCodeTypesCodes2D()->[AVMetadataObject.ObjectType]{
        /** 二维码 */
        if #available(iOS 15.4, *){
            return [.pdf417,
                    .dataMatrix,
                    .aztec,
                    .qr,
                    .microPDF417,
                    .microQR]
            
        }else{
            return  [.pdf417,
                    .dataMatrix,
                    .aztec,
                    .qr,]
        }
    }
   private static func supportedCodeTypesBarcodes()->[AVMetadataObject.ObjectType]{
        /** 条形码*/
        if #available(iOS 15.4, *){
            return [.codabar,
                    .code39,
                    .code39Mod43,
                    .code93,
                    .code128,
                    .ean8,
                    .ean13,
                    .gs1DataBar,
                    .gs1DataBarLimited,
                    .gs1DataBarExpanded,
                    .itf14,
                    .interleaved2of5,
                    .upce]
        }else{
            return [
                .code39,
                .code39Mod43,
                .code93,
                .code128,
                .ean8,
                .ean13,
                .itf14,
                .interleaved2of5,
                .upce]
            
        }
    }
    static func supportedCodeTypes(scanState:QRState)->[AVMetadataObject.ObjectType]{
        var res:[AVMetadataObject.ObjectType] = []
        switch scanState {
            // Fallback on earlier versions
        case .Barcodes:
            res = supportedCodeTypesBarcodes()
        case .Codes2D:
            res = supportedCodeTypesCodes2D()
        case .Bodies:
            if #available(iOS 13.0, *) {
                res = supportedCodeTypesCodesBodies()
            }
        case .Barcodes_Codes2D:
            res.append(contentsOf: supportedCodeTypesBarcodes())
            res.append(contentsOf: supportedCodeTypesCodes2D())
        case .Barcodes_Bodies:
            res.append(contentsOf: supportedCodeTypesBarcodes())
            if #available(iOS 13.0, *) {
                res.append(contentsOf: supportedCodeTypesCodesBodies())
            }
        case .Codes2D_Bodies:
            res.append(contentsOf: supportedCodeTypesCodes2D())
            if #available(iOS 13.0, *) {
                res.append(contentsOf: supportedCodeTypesCodesBodies())
            }
        case .All:
            res.append(contentsOf: supportedCodeTypesBarcodes())
            res.append(contentsOf: supportedCodeTypesCodes2D())
            if #available(iOS 13.0, *) {
                res.append(contentsOf: supportedCodeTypesCodesBodies())
            }
        }
        return res
    }
    static func coderState(objType:AVMetadataObject.ObjectType) -> QRState{
        if #available(iOS 15.4, *){
            switch objType {
            case .pdf417, .qr, .dataMatrix, .aztec, .microQR, .microPDF417: do {
                    return QRState.Codes2D
                }
            case .humanBody, .catBody, .dogBody :do {
                    return QRState.Bodies
                }
            default:do {
                    return QRState.Barcodes
                }
            }
        }else{
            switch objType {
            case .pdf417, .qr, .dataMatrix, .aztec: do {
                    return QRState.Codes2D
                }
            default:do {
                if #available(iOS 13.0, *) {
                    if objType == .humanBody || objType == .catBody || objType == .dogBody {
                        return QRState.Bodies
                    }
                }
                return QRState.Barcodes
                }
            }
        }
    }

    
    
    // Updated to handle potential nil values and removed test data string
    static func singleOutput(metadataObjects:[AVMetadataObject]) -> (kString:String,kState: QRState)? {
        guard let metadataObj = metadataObjects.first else {
            // No metadata objects found
            return nil
        }

        if #available(iOS 13.0, *) {
            if let machineReadableCode = metadataObj as? AVMetadataMachineReadableCodeObject {
                // Safely unwrap stringValue
                if let stringValue = machineReadableCode.stringValue {
                    return (stringValue, QRModel.coderState(objType: machineReadableCode.type))
                }
            } else if let bodyObject = metadataObj as? AVMetadataBodyObject {
                // bodyID is an Int, convert to String. Check if bodyID is meaningful (e.g., not 0 or -1 if those are invalid)
                // Assuming any non-zero bodyID is valid.
                if bodyObject.bodyID != 0 { // Or some other check for a valid ID if needed
                    return (String(bodyObject.bodyID), QRModel.coderState(objType: bodyObject.type))
                }
            }
        } else {
            // Fallback for older iOS versions (before iOS 13.0)
            // AVMetadataBodyObject is not available, so we only check for AVMetadataMachineReadableCodeObject
            if let machineReadableCode = metadataObj as? AVMetadataMachineReadableCodeObject {
                // Safely unwrap stringValue
                if let stringValue = machineReadableCode.stringValue {
                    return (stringValue, QRModel.coderState(objType: machineReadableCode.type))
                }
            }
        }
        // If no valid data could be extracted, return nil
        // Replaced "12345678->测试数据" with a nil return to indicate failure.
        // The caller should handle this nil case.
        // Alternatively, could return (UILabels.defaultScanErrorMessage, .Barcodes) or similar if a non-optional return is strictly required upstream.
        return nil
    }
}


