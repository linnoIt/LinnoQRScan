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


public enum QRState {
    case Barcodes
    case Codes2D
    case Bodies
    case All
}

struct QRModel {
    static let statuHeight:CGFloat = {
        if #available(iOS 13.0, *) {
            let set = UIApplication.shared.connectedScenes
            let windowScene = set.first as! UIWindowScene
            return windowScene.statusBarManager?.statusBarFrame.size.height ?? 68.0
        } else {
            return UIApplication.shared.statusBarFrame.size.height;
        }
    }()
    
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
        .dogBody,
        .dogBody
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
        case .Barcodes:
            res = supportedCodeTypesBarcodes()
        case .Codes2D:
            res = supportedCodeTypesCodes2D()
        case .Bodies:
            if #available(iOS 13.0, *) {
                res = supportedCodeTypesCodesBodies()
            }
        case .All:
            res.append(contentsOf: supportedCodeTypesBarcodes())
            res.append(contentsOf: supportedCodeTypesCodes2D())
            if #available(iOS 13.0, *) {
                res.append(contentsOf: supportedCodeTypesCodesBodies())
            }
                // Fallback on earlier versions
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
    static func feedbackGenerator() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)       
    }
    
    
    static func singleOutput(metadataObjects:[AVMetadataObject]) -> (kString:String,kState: QRState){
        let metadataObj = metadataObjects.first as! AVMetadataMachineReadableCodeObject
//        if QRModel.supportedCodeTypes().contains(metadataObj.type) {
            if metadataObj.stringValue != nil {
                return (metadataObj.stringValue! ,QRModel.coderState(objType: metadataObj.type))
            }
//        }
        return ("12345678->测试数据",.Barcodes)
    }
}


