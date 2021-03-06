//
//  TUSSwift.swift
//  TUSSwift
//
//  Created by Yaqing Wang on 10/30/15.
//  Copyright © 2015 billwang. All rights reserved.
//

import Foundation

public typealias UploadProcessBlock = ((Int64,Int64)->Void)
public typealias UploadResultBlock = ((NSURL)->Void)
public typealias UploadFailureBlock = ((ErrorType)->Void)


let HTTP_PATCH = "PATCH"
let HTTP_POST = "POST"
let HTTP_HEAD = "HEAD"
let HTTP_OFFSET = "Upload-Offset"
let HTTP_UPLOAD_LENGTH = "Entity-Length"
let HTTP_TUS = "Tus-Resumable"
let HTTP_TUS_VERSION = "1.0.0"
let HTTP_UPLOAD_META = "Upload-Metadata"

public enum TUSUploadState{
    case Idle, CheckingFile, CreatingFile, UploadingFile
}

public class TUSSwift{

    let queue = dispatch_queue_create(nil, DISPATCH_QUEUE_SERIAL)
    static let shareInstance = TUSSwift()
    var tasks = Array<TusTask>()
    
    class func scheduleUploadTask(url:String, data:TUSUploadData, fingerPrint:String, uploadHeaders :[String:String]=[:], fileName:String) -> TusTask{
        let task = TusTask(url: url, data: data, fingerPrint: fingerPrint, uploadHeaders: uploadHeaders, fileName: fileName)
        TUSSwift.shareInstance.scheduleTask(task)
        
        return task
    }
    
    private func scheduleTask(task:TusTask)->Void{
        dispatch_sync(queue) {[unowned self] () -> Void in
            task.start()
            self.tasks.append(task)
        }
    }
    
    public func cancelTask(task:TusTask){
        task.cancel()
    }
    
    public func pauseTask(task:TusTask){
        task.pause()
    }
    
    public func cancelAllTasks(){
        let _ = self.tasks.map { (task)  in
            task.cancel()
        }
    }
    
    public func pauseAllTasks(){
        let _ = self.tasks.map { (task) in
            task.pause()
        }
    }
}

public class TusTask : NSObject, NSURLSessionTaskDelegate{
    
    private var url : NSURL!
    private var endPointurl : NSURL!
    var data: TUSUploadData!
    var fingerPrint : String = ""
    var uploadHeaders : [String:String] = [:]
    var fileName : String!
    var state: TUSUploadState = .CreatingFile
    var offset: Int64 = 0
    var currentTask : NSURLSessionTask?
    var contentLength: Int64 = 0

    var processBlock : UploadProcessBlock?
    var sucessBlock : UploadResultBlock?
    var failureBlock : UploadFailureBlock?
    
    init(url:String, data:TUSUploadData, fingerPrint:String, uploadHeaders:[String:String]=[:], fileName:String){

        guard let _url = NSURL(string: url) else
        {
            print("Init NSURL error, please check your input!!!\n")
            return
        }
        self.endPointurl = _url
        self.data = data
        self.contentLength = self.data.length()
        self.fingerPrint = fingerPrint
        self.uploadHeaders = uploadHeaders
        self.fileName = fileName
    }
    
    func start(){
        if let _ = self.processBlock{
            self.processBlock!(0, 0)
        }
        if let uploadUrl = Cache.shareInstance[self.fingerPrint]{
            guard let _url = NSURL(string: uploadUrl) else{
                print("Init NSURL error, please check your input!!!\n")
                return
            }
            self.url = _url
            self.checkFile()
        }else{
            self.url = self.endPointurl
            self.createFile()
        }
    }
    
    func pause(){
        if let _ = self.currentTask{
            switch self.currentTask!.state{
            case .Running: /* The task is currently being serviced by the session */
                self.currentTask!.suspend()
            case .Suspended:
                self.currentTask!.resume()
            default:
                break
            }
        }
    }
    
    func cancel(){
        self.currentTask?.cancel()
    }
    
    //MARK: Tus
    func createFile(){
        self.state = .CreatingFile
        if let (_, task) = self.genSessionWithTask(){
            self.currentTask = task
            task.resume()
        }
    }
    
    func checkFile(){
        self.state = .CheckingFile
        if let (_ , task) = self.genSessionWithTask(){
            self.currentTask = task
            task.resume()
        }
    }
    
    func uploadFile(){
        self.state = .UploadingFile
        if let (_, task) = self.genSessionWithTask(){
            self.currentTask = task
            task.resume()
        }
    }
    
    private func genSessionWithTask() -> (NSURLSession, NSURLSessionTask)?{
        var httpHeaders:[String:String] = [:]
        httpHeaders += self.uploadHeaders
        httpHeaders[HTTP_TUS] = HTTP_TUS_VERSION
        
        let request = NSMutableURLRequest(URL: self.url!, cachePolicy: NSURLRequestCachePolicy.ReloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.HTTPShouldHandleCookies = false
        
        let commonSession = { (req:NSURLRequest) -> (NSURLSession, NSURLSessionTask)in
            let conf = NSURLSessionConfiguration.defaultSessionConfiguration()
            conf.HTTPAdditionalHeaders = httpHeaders
            let session = NSURLSession(configuration: conf)
            let task = session.dataTaskWithRequest(request, completionHandler: { [unowned self] (d, r, e) -> Void in
                self.handleResponse(r, error: e)
            })
            return (session, task)
        }
        
        let uploadSession = { (req:NSURLRequest) -> (NSURLSession, NSURLSessionTask)in
            let configuration = NSURLSessionConfiguration.backgroundSessionConfigurationWithIdentifier("TUSID-\(self.fingerPrint)")
            configuration.HTTPAdditionalHeaders = httpHeaders
            let session = NSURLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            let uploadTask = session.uploadTaskWithStreamedRequest(request)
            return (session, uploadTask)
        }
        
        switch self.state{
        case .CreatingFile:
            print("New created------------------------->\n")
            httpHeaders[HTTP_UPLOAD_LENGTH] = String(self.contentLength)
            httpHeaders[HTTP_UPLOAD_META] = self.fileName+self.fileName.base64String()
            request.HTTPMethod = HTTP_POST
            return commonSession(request)
            
        case .CheckingFile:
            print("Check upload------------------------->\n")
            request.HTTPMethod = HTTP_HEAD
            return commonSession(request)
            
        case .UploadingFile:
            print("Start uploading...\n")
            httpHeaders[HTTP_OFFSET] = String(self.offset)
            request.HTTPMethod = HTTP_PATCH
            return uploadSession(request)
        default:
            break
        }
        return nil
    }

    //MARK: NSURLSessionTask Delegate
    public func URLSession(session: NSURLSession, task: NSURLSessionTask, needNewBodyStream completionHandler: (NSInputStream?) -> Void) {
        print("NeedNewBodyStream----------------------->\n")
        completionHandler(self.data.dataStream())
    }
    
    public func URLSession(session: NSURLSession, task: NSURLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64){
        self.offset += bytesSent
        if self.offset == self.contentLength{
            self.sucessBlock?(self.url)
        }else
        {
            self.processBlock?(self.offset, self.contentLength)
        }
    }
    
    func handleResponse(response:NSURLResponse?, error:ErrorType?){

        if let _ = error{
            self.failureBlock?(error!)
            return
        }
        
        if let httpResp = response as? NSHTTPURLResponse{
            var headers = httpResp.allHeaderFields
            let statuscode = httpResp.statusCode
            print("HTTP status code :\(statuscode)\n Header info : \(headers)")
            
            switch self.state{
            case .CreatingFile:
                guard let location = headers["Location"] as? String else{
                    print("Cannot get location from repsonse header!!!\n")
                    break
                }
                self.url = NSURL(string: location)
                
                Cache.shareInstance[self.fingerPrint] = location
                self.uploadFile()
                
            case .CheckingFile:
                
                if (200...201) ~= httpResp.statusCode{
                    if let rangeHeader = headers[HTTP_OFFSET] as? String{
                        let size = Int64(rangeHeader)
                        if size >= self.offset{
                            self.state = .Idle
                            Cache.shareInstance -= self.fingerPrint
                            break
                        }else{
                            self.offset = size!
                            self.data.correctOffset(self.offset)
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
            print("Reponse error : \(response)\n")
        }
    }
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

//MARK: Operation
private func += <KeyType, ValueType> (inout lhs: Dictionary<KeyType, ValueType>, rhs: Dictionary<KeyType, ValueType>) {
    for (k, v) in rhs {
        lhs[k] = v
    }
}

private func -=(lhs:Cache, rhs:String){
    lhs.resumableUploads.removeValueForKey(rhs)
    lhs.archiveResumable()
}

func resumableUploadFilePath() -> NSURL{
    
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

