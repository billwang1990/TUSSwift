//
//  TUSUploadData.swift
//  TUSSwiftExample
//
//  Created by Yaqing Wang on 10/30/15.
//  Copyright © 2015 billwang. All rights reserved.
//

import Foundation

public protocol TUSUploadData{
    
    mutating func length() -> CLongLong
    
    mutating func dataStream() -> NSInputStream
    
}
