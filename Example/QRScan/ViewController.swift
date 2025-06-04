//
//  ViewController.swift
//  QRScan
//
//  Created by linnoIt on 09/21/2022.
//  Copyright (c) 2022 linnoIt. All rights reserved.
//

import UIKit
import QRScan

// 屏幕宽度
let screenWidth = UIScreen.main.bounds.width

// 屏幕高度
let screenHeight = UIScreen.main.bounds.height

class ViewController: UIViewController {
    var kQR:QRProxy?
    
    // 蒙板View
    let maskView: UIView = {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: screenWidth, height: screenHeight))
        v.backgroundColor = .clear
        let fullPath = UIBezierPath.init(rect: CGRect(origin: .zero, size: CGSizeMake(screenWidth, screenHeight)))
        let path = UIBezierPath.init(rect: CGRectMake((screenWidth - 231) / 2.0, (screenHeight - 231) / 2.0, 231, 231))
        fullPath.append(path)
        fullPath.usesEvenOddFillRule = true
        
        let layer = CAShapeLayer()
        layer.path = fullPath.cgPath
        layer.fillRule = .evenOdd
        layer.fillColor = UIColor.black.cgColor
        layer.opacity = 0.4
        v.layer.addSublayer(layer)
        return v
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(maskView)
//        self.view.backgroundColor = .systemGray
        let or =  CGPoint(x: view.center.x - (view.bounds.width - 50)/2, y: view.center.y - (view.bounds.width - 50)/2)
//        kQR = QRProxy.init(bounds:CGRect(origin: or, size: CGSize(width: view.bounds.width - 50, height: view.bounds.width - 50)), showView: self.view, outPut: { kResult in
//            print(kResult as Any)
//        })
        /// To quickly build
        /// bounds = self.view. bounds
        /// view = self.view
        ///
        let scFrame = CGRect(origin: or, size: CGSize(width: view.bounds.width - 50, height: view.bounds.width - 50))
        kQR = QRProxy.init(bounds: view.frame, scanFrame: scFrame, showView: self.view , outPut: { kString, kState in
            print(kString)
        })
        view.bringSubviewToFront(maskView)
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        kQR?.toggleTorch(mode: .on)
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

