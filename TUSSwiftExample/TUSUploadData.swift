//
//  TUSUploadData.swift
//  TUSSwift
//
//  Created by Yaqing Wang on 10/30/15.
//  Copyright © 2015 billwang. All rights reserved.
//

import Foundation

public protocol TUSUploadDataStream:NSStreamDelegate{
    func length() -> Int64
    func dataStream() -> NSInputStream
    func correctOffset(_: Int64) -> ()
}

let TUS_BUFSIZE = (32*1024)

public class TUSUploadData :NSObject, TUSUploadDataStream{
    
    var offset : Int64 = 0
    var inputStream : NSInputStream!
    var outputStream : NSOutputStream!
    var data : NSData!
    
    public func length() -> Int64 {
        guard let data = self.data else{
            print("Data must not be nil!!!")
            return Int64(0)
        }
        return Int64(data.length)
    }
    
    public func correctOffset(curOffset: Int64) {
        self.offset = curOffset
    }
    
    public func dataStream() -> NSInputStream {
        
        let (input, output) = NSStream.boundStreamsWithBufferSize(TUS_BUFSIZE)
        self.inputStream = input
        self.outputStream = output
        self.outputStream.delegate = self
        self.outputStream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSRunLoopCommonModes)
        self.outputStream.open()
        
        return self.inputStream
    }
    
    func getBytes(buffer: UnsafeMutablePointer<UInt8>, fromOffset: Int64, length: Int64) -> Int64 {
        let range = NSMakeRange(Int(fromOffset), Int(length))
        if (offset + length > self.length()) {
            return Int64(0)
        }
        self.data.getBytes(buffer, range: range)
        return length
    }
    
    deinit{
        self.stop()
    }

    public func stop(){
        self.outputStream.delegate = nil
        self.outputStream.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSRunLoopCommonModes)
        self.outputStream.close()
        self.outputStream = nil
        self.inputStream.delegate = nil
        self.inputStream.close()
        self.inputStream = nil
    }
    
    convenience init(data:NSData){
        self.init()
        self.data = data
    }
    
    //MARK: NSStreamDelegate
    public func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
    
        switch eventCode{
        case NSStreamEvent.HasSpaceAvailable:
            
            var length = Int64(TUS_BUFSIZE)
            var buffer = [UInt8](count: TUS_BUFSIZE, repeatedValue: 0)
            
            if (length > self.length() - self.offset) {
                length = self.length() - self.offset
            }
            
            if length < 0{
                self.outputStream.delegate = nil
                self.outputStream.close()
                return
            }
            
            let bytesRead = self.getBytes(&buffer, fromOffset: self.offset, length: length)
            
            if bytesRead != 0{
                let bufferWritten = self.outputStream.write(buffer, maxLength: Int(bytesRead))
                if bufferWritten > 0{
                    if bytesRead != Int64(bufferWritten){
                        print("Read \(bytesRead), but only write \(bufferWritten)")
                    }
                    self.offset += Int64(bufferWritten)
                }
            }
            break
        case NSStreamEvent.ErrorOccurred:
            //TODO: error handle
            print("NSStream error occured\n")
            break
        case NSStreamEvent.EndEncountered, NSStreamEvent.OpenCompleted, NSStreamEvent.HasBytesAvailable:
            print("Stream event happened :\(eventCode) ")
            
        default:
            return
        }
    }
}

extension NSStream {
    class func boundStreamsWithBufferSize(bufferSize: Int) ->
        (inputStream: NSInputStream, outputStream: NSOutputStream) {
            var readStream: Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?
            CFStreamCreateBoundPair(nil, &readStream, &writeStream, bufferSize)
            return (readStream!.takeUnretainedValue(), writeStream!.takeUnretainedValue())
    }
}

//func +=(inout lhs:UInt,rhs:UInt){
//    lhs = lhs + rhs
//}
