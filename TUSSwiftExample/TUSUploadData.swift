//
//  TUSUploadData.swift
//  TUSSwiftExample
//
//  Created by Yaqing Wang on 10/30/15.
//  Copyright © 2015 billwang. All rights reserved.
//

import Foundation

extension NSStream {
    class func boundStreamsWithBufferSize(bufferSize: Int) ->
        (inputStream: NSInputStream, outputStream: NSOutputStream) {
            var readStream: Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?
            CFStreamCreateBoundPair(nil, &readStream, &writeStream, bufferSize)
            return (readStream!.takeUnretainedValue(), writeStream!.takeUnretainedValue())
    }
}

public protocol TUSUploadDataStream:NSStreamDelegate{
    
    func length() -> UInt
    
//    func dataStream() -> NSInputStream
    
    func getBytes(buffer:UnsafeMutablePointer<UInt8>, fromOffset:UInt, length:UInt)  -> UInt
}

let TUS_BUFSIZE = (32*1024)
public class TUSUploadData :NSObject, TUSUploadDataStream{
    
    var offset : UInt = 0
    var inputStream : NSInputStream!
    var outputStream : NSOutputStream!
    var data : NSData!
    
    public func length() -> UInt {
        
        guard let data = self.data else{
            print("Data must not be nil!!!")
            return UInt(0)
        }
        return UInt(data.length)
    }
    
    public func dataStream() -> NSInputStream {
        return self.inputStream
    }
    
    public func getBytes(buffer: UnsafeMutablePointer<UInt8>, fromOffset: UInt, length: UInt) -> UInt {
        let range = NSMakeRange(Int(fromOffset), Int(length))
        if (offset + length > UInt(self.data.length)) {
            return UInt(0)
        }
        self.data.getBytes(buffer, range: range)
        return length
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
    
    //MARK: Lifecycle
    override init()
    {
        super.init()
        let (input, output) = NSStream.boundStreamsWithBufferSize(TUS_BUFSIZE)
        self.inputStream = input
        self.outputStream = output
        self.outputStream.delegate = self
        self.outputStream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSRunLoopCommonModes)
        self.outputStream.open()
    }
    
    convenience init(data:NSData){
        self.init()
        self.data = data
    }
    
    //MARK: NSStreamDelegate
    public func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
    
        switch eventCode{
        case NSStreamEvent.HasSpaceAvailable:
            
            var length = UInt(TUS_BUFSIZE)
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
            if bytesRead == 0{
                //TODO:error handle
                print("Read bytes from stream failed!!!")
            }else{
                let bufferWritten = self.outputStream.write(buffer, maxLength: Int(bytesRead))
                if bufferWritten > 0{
                    if bytesRead != UInt(bufferWritten){
                        print("Read \(bytesRead), but only write \(bufferWritten)")
                    }
                    self.offset += UInt(bufferWritten)
                }else{
                    
                }
            }
            break
        case NSStreamEvent.ErrorOccurred:
            //TODO: error handle
            break
        case NSStreamEvent.EndEncountered, NSStreamEvent.OpenCompleted, NSStreamEvent.HasBytesAvailable:
            print("Stream event happened :\(eventCode) ")
            
        default:
            return
        }
    }
}

func +=(inout lhs:UInt,rhs:UInt){
    lhs = lhs + rhs
}
