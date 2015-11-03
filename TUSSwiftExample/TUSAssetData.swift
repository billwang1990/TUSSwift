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
        return UInt(self.asset.defaultRepresentation().getBytes(buffer, fromOffset: Int64(fromOffset), length: Int(length), error: nil))
    }
    
}