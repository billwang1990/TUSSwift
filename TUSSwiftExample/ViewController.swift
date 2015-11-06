//
//  ViewController.swift
//  TUSSwiftExample
//
//  Created by Yaqing Wang on 10/30/15.
//  Copyright © 2015 billwang. All rights reserved.
//

import UIKit
import AssetsLibrary

class ViewController: UIViewController,UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    var assetLibrary = ALAssetsLibrary()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        self.selectFile()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func selectFile(){
        let vc = UIImagePickerController()
        vc.mediaTypes = UIImagePickerController.availableMediaTypesForSourceType(vc.sourceType)!
        vc.delegate = self
        self.presentViewController(vc, animated: true) { () -> Void in}
    }
    
    func imagePickerController(picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : AnyObject]) {
        self.dismissViewControllerAnimated(true, completion: nil)
        let assetURL = info[UIImagePickerControllerReferenceURL] as! NSURL
        
        self.assetLibrary.assetForURL(assetURL, resultBlock: { (asset) -> Void in
            let fingerprint = assetURL.absoluteString
            let uploadData = TUSAssetData(asset: asset)
            let task = TUSSwift.scheduleUploadTask("http://localhost:8000/files", data: uploadData, fingerPrint: fingerprint, fileName: "first.png")
            
            task.processBlock =  { (current, total) in
                print("current \(current), total is \(total)\n")
            }
            
            }, failureBlock: nil)
        
    }
}

