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
    static func supportedCodeTypes()->[AVMetadataObject.ObjectType]{[
        /** 条形码*/
        AVMetadataObject.ObjectType.upce,
        AVMetadataObject.ObjectType.code39,
        AVMetadataObject.ObjectType.code39Mod43,
        AVMetadataObject.ObjectType.code93,
        AVMetadataObject.ObjectType.code128,
        AVMetadataObject.ObjectType.ean8,
        AVMetadataObject.ObjectType.ean13,
        AVMetadataObject.ObjectType.itf14,
        AVMetadataObject.ObjectType.interleaved2of5,
         /** 二维码 */
        AVMetadataObject.ObjectType.pdf417,
        AVMetadataObject.ObjectType.dataMatrix,
        AVMetadataObject.ObjectType.aztec,
        AVMetadataObject.ObjectType.qr]
    }
    static func coderState(objType:AVMetadataObject.ObjectType) -> QRState{
        if (objType == .pdf417 || objType == .qr || objType == .dataMatrix || objType == .aztec) {
            return .Codes2D
        }
        return .Barcodes
    }
    static func feedbackGenerator() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)       
    }
    
    
    static func singleOutput(metadataObjects:[AVMetadataObject]) -> (kString:String,kState: QRState){
        let metadataObj = metadataObjects.first as! AVMetadataMachineReadableCodeObject
        if QRModel.supportedCodeTypes().contains(metadataObj.type) {
            if metadataObj.stringValue != nil {
                return (metadataObj.stringValue! ,QRModel.coderState(objType: metadataObj.type))
            }
        }
        return ("12345678->测试数据",.Barcodes)
    }
}


