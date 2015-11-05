//
//  TUSSwift.swift
//  TUSSwift
//
//  Created by Yaqing Wang on 10/30/15.
//  Copyright © 2015 billwang. All rights reserved.
//

import Foundation

public typealias UploadProcessBlock = ((Float,Float)->Void)
public typealias UploadResultBlock = ((NSURL)->Void)
public typealias UploadFailureBlock = ((NSError)->Void)

public enum TUSUploadState{
    case Idle, CheckingFile, CreatingFile, UploadingFile
}

let HTTP_PATCH = "PATCH"
let HTTP_POST = "POST"
let HTTP_HEAD = "HEAD"
let HTTP_OFFSET = "Upload-Offset"
let HTTP_UPLOAD_LENGTH = "Entity-Length"
let HTTP_TUS = "Tus-Resumable"
let HTTP_TUS_VERSION = "1.0.0"
let HTTP_UPLOAD_META = "Upload-Metadata"

public class TUSSwift : NSObject, NSURLSessionTaskDelegate{
    
    var url : NSURL?
    var endPointurl : NSURL!
    var data: TUSUploadData!
    var fingerPrint : String!
    var uploadHeaders : [String:String]!
    var fileName : String!
    var processBlock : UploadProcessBlock?
    var state: TUSUploadState = TUSUploadState.Idle
    var offset: UInt = 0
    var urlSession : NSURLSession?
    
    static var resumableUploads:Dictionary<String,String> = {
        guard let url = try? TUSSwift.resumableUploadFilePath() as NSURL else{
            print("Resume upload path error!!!\n")
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
            print("Init NSURL error, please check your input!!!\n")
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
            guard let _url = NSURL(string: uploadUrl) else{
                print("Init NSURL error, please check your input!!!\n")
                return
            }
            self.url = _url
            self.checkFile()
        }else{
            self.createFile()
        }
    }
    //MARK: Tus
    func createFile(){
        
        self.state = .CreatingFile
        let (request,headers) =  self.generateRequestAndHeaders()
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.HTTPAdditionalHeaders = headers
        NSURLSession(configuration: configuration).dataTaskWithRequest(request, completionHandler: { (data, response, error) -> Void in
            guard let _ = response else{
                print("reponse error %s", __FUNCTION__)
                return
            }
            self.handleResponse(response!)
        }).resume()
    }
    
    func checkFile(){
        self.state = .CheckingFile
        let (request, headers) = self.generateRequestAndHeaders()
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.HTTPAdditionalHeaders = headers
        
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
        let (request, headers) = self.generateRequestAndHeaders()
        let configuration = NSURLSessionConfiguration.backgroundSessionConfigurationWithIdentifier("TUSID-\(self.fingerPrint)")
        configuration.HTTPAdditionalHeaders = headers
        let session = NSURLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let uploadTask = session.uploadTaskWithStreamedRequest(request)
        uploadTask.resume()
    }
    // MARK: private
    private func generateRequestAndHeaders() -> (NSURLRequest,[String:String]){
        
        var headers:[String:String] = [:]
        headers += self.uploadHeaders
        var url = self.url
        var mtd = HTTP_POST
        
        switch self.state{
            
        case .CreatingFile:
            
            headers.updateValue("\(self.data.length())", forKey: HTTP_UPLOAD_LENGTH)
            headers.updateValue(HTTP_TUS_VERSION, forKey: HTTP_TUS)
            headers.updateValue((self.fileName+self.fileName.base64String()), forKey: HTTP_UPLOAD_META)
            url = self.endPointurl
            
        case .CheckingFile:
            mtd = HTTP_HEAD
            
        case .UploadingFile:
            headers.updateValue("\(self.offset)", forKey: HTTP_OFFSET)
            headers.updateValue(HTTP_TUS_VERSION, forKey: HTTP_TUS)
            mtd = HTTP_PATCH
            
        default:
            break
        }
        
        let request = NSMutableURLRequest(URL: url!, cachePolicy: NSURLRequestCachePolicy.ReloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.HTTPShouldHandleCookies = false
        request.HTTPMethod = mtd
        
        return (request,headers)
    }
    
    public func URLSession(session: NSURLSession, task: NSURLSessionTask, needNewBodyStream completionHandler: (NSInputStream?) -> Void) {
        print("NeedNewBodyStream----------------------->\n")
        completionHandler(self.data.dataStream())
    }
    
    func handleResponse(response:NSURLResponse){
        
        if let httpResp = response as? NSHTTPURLResponse{
            
            var headers = httpResp.allHeaderFields
            let statuscode = httpResp.statusCode
            print("HTTP status code :\(statuscode)\n")
            
            switch self.state{
            case .CreatingFile:
                guard let location = headers["Location"] as? String else{
                    print("Cannot get location from repsonse header!!!\n")
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
                        let size = UInt(rangeHeader)
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
        
        let folders = NSFileManager.defaultManager().URLsForDirectory(NSSearchPathDirectory.CachesDirectory, inDomains: NSSearchPathDomainMask.UserDomainMask)
        
        let applicationSupportDirectoryURL = folders.last as NSURL!
        let applicationSupportDirectoryPath = applicationSupportDirectoryURL.absoluteString
        
        var isFolder = ObjCBool(false)
        if NSFileManager.defaultManager().fileExistsAtPath(applicationSupportDirectoryPath, isDirectory: &isFolder) == false{
            do{
                try NSFileManager.defaultManager().createDirectoryAtPath(applicationSupportDirectoryPath, withIntermediateDirectories: true, attributes: nil)
            }catch{
                print("Unable to create \(error) directory due!!!\n")
            }
        }
        return applicationSupportDirectoryURL.URLByAppendingPathComponent("TUSResumableUploads.plist")
    }
}


// MARK: Request class

class Request{
    
}

// MARK: Manager class
class Manager {
    
    
}


extension String{
    func base64String() -> String
    {
        guard let data = self.dataUsingEncoding(NSUTF8StringEncoding) else{
            print("Cannot create data with UTF8 encoding!!!\n")
            return ""
        }
        return data.base64EncodedStringWithOptions(NSDataBase64EncodingOptions.Encoding64CharacterLineLength)
    }
}


func += <KeyType, ValueType> (inout lhs: Dictionary<KeyType, ValueType>, rhs: Dictionary<KeyType, ValueType>) {
    for (k, v) in rhs {
        lhs.updateValue(v, forKey: k)
    }
}