//
//  QRModel.swift
//  QRCodeReader
//
//  Created by 韩增超 on 2022/9/14.
//

import Foundation
import UIKit
import AVFoundation

public enum QRState: Int {
    case Barcodes = 1
    case Codes2D = 2
    case Bodies = 3
    case Barcodes_Codes2D = 4
    case Barcodes_Bodies = 5
    case Codes2D_Bodies = 6
    case All = 7

    public init?(rawValue: Int) {
        var kState:QRState
        switch rawValue {
        case 1: kState = .Barcodes
        case 2: kState = .Codes2D
        case 3: kState = .Bodies
        case 4: kState = .Barcodes_Codes2D
        case 5: kState = .Barcodes_Bodies
        case 6: kState = .Codes2D_Bodies
        default:
            kState = .All
        }
        self = kState
    }
}

struct QRModel {
    static func isAuther() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized || status == .notDetermined else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showPermissionAlert()
            }
            return false
        }
        return true
    }

    private static func showPermissionAlert() {
        guard let vc = currentViewController() else { return }
        vc.dismiss(animated: true) {
            let alert = UIAlertController(title: "Error", message: "No camera permission was granted", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Done", style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            vc.present(alert, animated: true)
        }
    }

    static func showError() {
        guard let vc = currentViewController() else { return }
        vc.dismiss(animated: true) {
            let alert = UIAlertController(title: "Error", message: "Failed to get the camera device", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Done", style: .default) { _ in
                vc.dismiss(animated: true)
            })
            vc.present(alert, animated: true)
        }
    }

    static func statuHeight() -> CGFloat {
        if #available(iOS 13.0, *) {
            return (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.statusBarManager?.statusBarFrame.height ?? 68.0
        } else {
            return UIApplication.shared.statusBarFrame.height
        }
    }

    static func currentViewController() -> UIViewController? {
        guard let root = currentWindow()?.rootViewController else { return nil }
        return topViewController(base: root)
    }

    private static func topViewController(base: UIViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController ?? nav)
        } else if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController ?? tab)
        } else if let presented = base.presentedViewController {
            return topViewController(base: presented)
        } else {
            return base
        }
    }

    static func currentWindow() -> UIWindow? {
        if #available(iOS 15.0, *) {
            return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first
        } else if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .filter { $0.activationState == .foregroundActive }
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            return UIApplication.shared.delegate?.window ?? nil
        }
    }

    static func deviceOrientation(connection: AVCaptureConnection) -> UIDeviceOrientation {
        return connection.isVideoOrientationSupported ? UIDevice.current.orientation : .unknown
    }

    @available(iOS 13.0, *)
    private static func supportedCodeTypesBodies() -> [AVMetadataObject.ObjectType] {
        [.humanBody, .dogBody, .catBody]
    }

    private static func supportedCodeTypes2D() -> [AVMetadataObject.ObjectType] {
        if #available(iOS 15.4, *) {
            return [.pdf417, .dataMatrix, .aztec, .qr, .microPDF417, .microQR]
        } else {
            return [.pdf417, .dataMatrix, .aztec, .qr]
        }
    }

    private static func supportedCodeTypesBarcodes() -> [AVMetadataObject.ObjectType] {
        if #available(iOS 15.4, *) {
            return [.codabar, .code39, .code39Mod43, .code93, .code128, .ean8, .ean13,
                    .gs1DataBar, .gs1DataBarLimited, .gs1DataBarExpanded, .itf14, .interleaved2of5, .upce]
        } else {
            return [.code39, .code39Mod43, .code93, .code128, .ean8, .ean13, .itf14, .interleaved2of5, .upce]
        }
    }

    static func supportedCodeTypes(for state: QRState) -> [AVMetadataObject.ObjectType] {
        var result: [AVMetadataObject.ObjectType] = []
        switch state {
        case .Barcodes: result += supportedCodeTypesBarcodes()
        case .Codes2D: result += supportedCodeTypes2D()
        case .Bodies:
            if #available(iOS 13.0, *) { result += supportedCodeTypesBodies() }
        case .Barcodes_Codes2D:
            result += supportedCodeTypesBarcodes() + supportedCodeTypes2D()
        case .Barcodes_Bodies:
            result += supportedCodeTypesBarcodes()
            if #available(iOS 13.0, *) { result += supportedCodeTypesBodies() }
        case .Codes2D_Bodies:
            result += supportedCodeTypes2D()
            if #available(iOS 13.0, *) { result += supportedCodeTypesBodies() }
        case .All:
            result += supportedCodeTypesBarcodes() + supportedCodeTypes2D()
            if #available(iOS 13.0, *) { result += supportedCodeTypesBodies() }
        }
        return result
    }

    static func coderState(for type: AVMetadataObject.ObjectType) -> QRState {
        if #available(iOS 15.4, *) {
            switch type {
            case .pdf417, .qr, .dataMatrix, .aztec, .microQR, .microPDF417: return .Codes2D
            case .humanBody, .catBody, .dogBody: return .Bodies
            default: return .Barcodes
            }
        } else {
            if #available(iOS 13.0, *), [.humanBody, .catBody, .dogBody].contains(type) {
                return .Bodies
            }
            switch type {
            case .pdf417, .qr, .dataMatrix, .aztec: return .Codes2D
            default: return .Barcodes
            }
        }
    }

    static func singleOutput(from objects: [AVMetadataObject]) -> (String, QRState) {
        guard let first = objects.first else {
            return ("12345678->测试数据", .Barcodes)
        }
        if #available(iOS 13.0, *) {
            if let codeObj = first as? AVMetadataMachineReadableCodeObject, let value = codeObj.stringValue {
                return (value, coderState(for: codeObj.type))
            } else if let bodyObj = first as? AVMetadataBodyObject, bodyObj.bodyID != 0 {
                return (String(bodyObj.bodyID), coderState(for: bodyObj.type))
            }
        } else if let codeObj = first as? AVMetadataMachineReadableCodeObject, let value = codeObj.stringValue {
            return (value, coderState(for: codeObj.type))
        }
        return ("12345678->测试数据", .Barcodes)
    }
}
