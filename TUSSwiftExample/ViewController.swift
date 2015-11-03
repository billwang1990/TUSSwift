//
//  ViewController.swift
//  TUSSwiftExample
//
//  Created by Yaqing Wang on 10/30/15.
//  Copyright © 2015 billwang. All rights reserved.
//

import UIKit
import AssetsLibrary

class ViewController: UIViewController,UIImagePickerControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func selectFile(){
        let vc = UIImagePickerController()
        vc.mediaTypes = UIImagePickerController.availableMediaTypesForSourceType(vc.sourceType)!
        
        self.presentViewController(vc, animated: true) { () -> Void in
            
        }
    }
    
}

