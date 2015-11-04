//
//  TUSAssetData.swift
//  TUSSwiftExample
//
//  Created by Yaqing Wang on 11/3/15.
//  Copyright © 2015 billwang. All rights reserved.
//

import Foundation
import UIKit
import AssetsLibrary

class TUSAssetData:TUSUploadData {

    var asset : ALAsset!
    
    convenience init(asset:ALAsset){
        self.init()
        self.asset = asset
    }
    
    override func length() -> UInt {
        return UInt(self.asset.defaultRepresentation().size())
    }
    
    override func getBytes(buffer: UnsafeMutablePointer<UInt8>, fromOffset: UInt, length: UInt) -> UInt {
        let offset = Int64(fromOffset)
        let len = Int(length)
        var error:NSError?
        let ret = self.asset.defaultRepresentation().getBytes(buffer, fromOffset: offset , length: len, error: &error)
        if let _  = error{
            print("GET BYTES ERROR\(error)===> offset:\(offset), length:\(len)")
        }

        return UInt(ret)
    }
    
}