//
//  ViewController.swift
//  QRScan
//
//  Created by linnoIt on 09/21/2022.
//  Copyright (c) 2022 linnoIt. All rights reserved.
//

import UIKit
import QRScan

class ViewController: UIViewController {
    var kQR:QRProxy?
    override func viewDidLoad() {
        super.viewDidLoad()
//        self.view.backgroundColor = .systemGray
//        let or =  CGPoint(x: view.center.x - (view.bounds.width - 50)/2, y: view.center.y - (view.bounds.width - 50)/2)
//        kQR = QRProxy.init(bounds:CGRect(origin: or, size: CGSize(width: view.bounds.width - 50, height: view.bounds.width - 50)), showView: self.view, outPut: { kResult in
//            print(kResult as Any)
//        })
        /// To quickly build
        /// bounds = self.view. bounds
        /// view = self.view
        kQR = QRProxy.init(outPut: { kString, kState in
            
        })
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

