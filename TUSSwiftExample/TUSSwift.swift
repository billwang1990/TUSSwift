//
//  TUSSwift.swift
//  TUSSwiftExample
//
//  Created by Yaqing Wang on 10/30/15.
//  Copyright © 2015 billwang. All rights reserved.
//

import Foundation

public typealias UploadProcessBlock = ((Float,Float)->Void)

public enum TUSUploadState{
    case Idle, CheckingFile, CreatingFile, UploadingFile
}

let HTTP_PATCH = "PATCH"
let HTTP_POST = "POST"
let HTTP_HEAD = "HEAD"
let HTTP_OFFSET = "Upload-Offset"
let HTTP_UPLOAD_LENGTH = "Upload-Length"
let HTTP_TUS = "Tus-Resumable"
let HTTP_TUS_VERSION = "1.0.0"
let HTTP_UPLOAD_META = "Upload-Metadata"

public class TUSSwift{
    
    var url : NSURL?
    var endPointurl : NSURL!
    var data: TUSUploadData!
    var fingerPrint : String!
    var uploadHeaders : [String:String]!
    var fileName : String!
    var processBlock : UploadProcessBlock?
    var state: TUSUploadState = TUSUploadState.Idle
    var offset: CLongLong = 0
    var urlSession : NSURLSession?
    
    static var resumableUploads:Dictionary<String,String> = {
        
        guard let url = try? TUSSwift.resumableUploadFilePath() as NSURL else
        {
            print("resume upload path error!!!")
            return [:]
        }
        
        if let uploads = NSDictionary(contentsOfURL: url){
            return uploads as! Dictionary
        }else{
            return [:]
        }
    }()
    
    required public init(url:String, data:TUSUploadData, fingerPrint:String, uploadHeaders:[String:String]=[:], fileName:String){
        
        guard let _url = NSURL(string: url) else
        {
            print("init NSURL error, please check your input")
            return
        }
        self.endPointurl = _url
        self.data = data
        self.fingerPrint = fingerPrint
        self.uploadHeaders = uploadHeaders
        self.fileName = fileName
        
    }
    
    func start(){
        if let _ = self.processBlock{
            self.processBlock!(0.0, 0.0)
        }
        
        if let uploadUrl = TUSSwift.resumableUploads[self.fingerPrint]{
            guard let _url = NSURL(string: uploadUrl) else
            {
                print("init NSURL error, please check your input")
                return
            }
            self.url = _url
            //            self.checkFile()
        }else{
            self.createFile()
        }
        
    }
    
    func createFile(){
        
        self.state = .CreatingFile
        let size = self.data.length()
        var mutableHeaders : [String:String] = [:]
        mutableHeaders += self.uploadHeaders
        mutableHeaders.updateValue("\(size)", forKey: HTTP_UPLOAD_LENGTH)
        mutableHeaders.updateValue(HTTP_TUS_VERSION, forKey: HTTP_TUS)
        
        if let plainData = self.fileName.dataUsingEncoding(NSUTF8StringEncoding){
        
            let base64String = plainData.base64EncodedStringWithOptions(NSDataBase64EncodingOptions.Encoding64CharacterLineLength)
        
            mutableHeaders.updateValue(self.fileName.stringByAppendingString(base64String), forKey: HTTP_UPLOAD_META)
            let request = NSMutableURLRequest(URL: self.endPointurl, cachePolicy: NSURLRequestCachePolicy.ReloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
            request.HTTPMethod = HTTP_POST
            request.HTTPShouldHandleCookies = false
            
            let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
            configuration.HTTPAdditionalHeaders = mutableHeaders
            NSURLSession(configuration: configuration).dataTaskWithRequest(request, completionHandler: { (data, response, error) -> Void in
                guard let _ = response else{
                    print("reponse error %s", __FUNCTION__)
                    return
                }
                self.handleResponse(response!)
                
            }).resume()
            
        }else{
            //TODO: error handle
            print("%s create data error", __FUNCTION__)
        }
        
    }
    
    func checkFile(){
        self.state = .CheckingFile
        var mutableHeader:[String:String] = [:]
        mutableHeader += self.uploadHeaders
        
        let request = NSMutableURLRequest(URL: self.url!, cachePolicy: NSURLRequestCachePolicy.ReloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.HTTPMethod = HTTP_HEAD
        request.HTTPShouldHandleCookies = false
        
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.HTTPAdditionalHeaders = mutableHeader
        
        NSURLSession(configuration: configuration).dataTaskWithRequest(request, completionHandler: { (data, response, error) -> Void in
            guard let _ = response else{
                print("reponse error %s", __FUNCTION__)
                return
            }
            self.handleResponse(response!)
            
        }).resume()

    }
    
    func uploadFile(){
        
        self.state = .UploadingFile
        var mutableHeader:[String:String] = [:]
        mutableHeader += self.uploadHeaders
        mutableHeader.updateValue("\(self.offset)", forKey: HTTP_OFFSET)
        mutableHeader.updateValue(HTTP_TUS_VERSION, forKey: HTTP_TUS)
        
        let request = NSMutableURLRequest(URL: self.url!, cachePolicy: NSURLRequestCachePolicy.ReloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.HTTPMethod = HTTP_PATCH
        request.HTTPBodyStream = self.data.dataStream()
        request.HTTPShouldHandleCookies = false

        let configuration = NSURLSessionConfiguration.backgroundSessionConfigurationWithIdentifier("TUSID-\(self.fingerPrint)")
        configuration.HTTPAdditionalHeaders = mutableHeader
        
        NSURLSession(configuration: configuration).uploadTaskWithRequest(request, fromData: nil) { (data, response, error) -> Void in
            if let _ = error{
                //TODO: error handle
            }
        }.resume()
    }
    
    func handleResponse(response:NSURLResponse){
        
        if let httpResp = response as? NSHTTPURLResponse{
            
            var headers = httpResp.allHeaderFields
            
            switch self.state{
            case .CreatingFile:
                
                guard let location = headers["Location"] as? String else{
                    print("cannot get location from repsonse header")
                    break
                }
                
                self.url = NSURL(string: location)
                
                if let fileURL = try? TUSSwift.resumableUploadFilePath() as NSURL{
                    var resumableUploads = TUSSwift.resumableUploads
                    resumableUploads.updateValue(location, forKey: self.fingerPrint)
                    if (resumableUploads as NSDictionary).writeToURL(fileURL, atomically: true) == false{
                        print("Unable to save resumableUploads file")
                    }
                    self.uploadFile()
                }
            case .CheckingFile:
                
                if (200...201) ~= httpResp.statusCode{
                    if let rangeHeader = headers[HTTP_OFFSET] as? String{
                        let size = CLongLong(rangeHeader)
                        if size >= self.offset{
                            self.state = .Idle
                            TUSSwift.resumableUploads.removeValueForKey(self.fingerPrint)
                            do{
                                if (TUSSwift.resumableUploads as NSDictionary).writeToURL(try TUSSwift.resumableUploadFilePath(), atomically: true){
                                    
                                }else{
                                    //TODO: handle write file error
                                    print("write dictionary to file failed")
                                }
                            }catch{
                                //TODO: error handle
                            }
                            
                            break
                        }else{
                            self.offset = size!
                        }
                        print("Resumable upload at \(self.url) for \(self.fingerPrint) from \(self.offset) \(rangeHeader)")

                    }else{
                        print("Restart upload at \(self.url) for \(self.fingerPrint)")
                    }
                    self.uploadFile()

                }else{
                    print("Server responded with \(httpResp.statusCode). Restarting upload")
                    self.createFile()
                    break
                }
            default:
                break
            }
            
        }else{
            print("reponse type error")
        }
    }
}


extension TUSSwift{

    class func resumableUploadFilePath() throws -> NSURL{
        let fileManager = NSFileManager.defaultManager()
        let folders = fileManager.URLsForDirectory(NSSearchPathDirectory.ApplicationSupportDirectory, inDomains: NSSearchPathDomainMask.UserDomainMask)
        let applicationSupportDirectoryURL = folders.last as NSURL!
        let applicationSupportDirectoryPath = applicationSupportDirectoryURL.absoluteString
        
        var isFolder = ObjCBool(false)
        if fileManager.fileExistsAtPath(applicationSupportDirectoryPath, isDirectory: &isFolder){
            do{
                try fileManager.createDirectoryAtPath(applicationSupportDirectoryPath, withIntermediateDirectories: true, attributes: nil)
            }catch{
                print("unable to create \(error) directory due")
                //TODO: error handle
            }
        }
        return applicationSupportDirectoryURL.URLByAppendingPathComponent("TUSResumableUploads.plist")
    }
}


func += <KeyType, ValueType> (inout lhs: Dictionary<KeyType, ValueType>, rhs: Dictionary<KeyType, ValueType>) {
    for (k, v) in rhs {
        lhs.updateValue(v, forKey: k)
    }
}