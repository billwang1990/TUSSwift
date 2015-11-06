//
//  Cache.swift
//  TUSSwiftExample
//
//  Created by Yaqing Wang on 11/6/15.
//  Copyright © 2015 billwang. All rights reserved.
//

import Foundation
class Cache {
    static let shareInstance = Cache()
    lazy var resumableUploads:Dictionary<String,String> = {
        if let uploads = NSDictionary(contentsOfURL: resumableUploadFilePath()){
            return uploads as! Dictionary
        }else{
            return [:]
        }
    }()
    
    subscript(fingerPrint:String) -> String?{
        get{
            if let f = self.resumableUploads[fingerPrint]{
                return f as String
            }else{
                return nil
            }
        }
        set{
            self.resumableUploads[fingerPrint] = newValue!
            self.archiveResumable()
        }
    }
    
    func archiveResumable(){
        if (resumableUploads as NSDictionary).writeToURL(resumableUploadFilePath(), atomically: true) == false{
            print("Unable to save resumableUploads file\n")
        }
    }
}
