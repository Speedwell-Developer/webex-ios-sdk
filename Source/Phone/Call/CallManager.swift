// Copyright 2016 Cisco Systems Inc
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

class CallManager {
    
    private var callInstances = [String: Call]()
    private let authenticationStrategy: AuthenticationStrategy
    private let reachabilityService: ReachabilityService
    private let deviceService: DeviceService
    
    var localReachabilityInfo: [String /* media cluster tag */ : Reachability]? {
        return reachabilityService.feedback?.reachabilities
    }
    
    init(authenticationStrategy: AuthenticationStrategy, deviceService: DeviceService) {
        self.authenticationStrategy = authenticationStrategy
        self.reachabilityService = ReachabilityService(authenticationStrategy: authenticationStrategy, deviceService: deviceService)
        self.deviceService = deviceService
    }
    
    func addCallWith(url: String, call: Call) {
        guard url.characters.count > 0 else { return }
		
        callInstances.updateValue(call, forKey: url)
        Logger.info("Add call for call url:\(url)")
    }
    
    func removeCallWith(url: String) {
        callInstances.removeValue(forKey: url)
        Logger.info("Remove call for call url:\(url)")
    }
    
    func findCallBy(mediaSession session: MediaSession) -> Call? {
        for call in callInstances.values {
            if call.isMediaSessionAssociated(session) {
                return call
            }
        }
        return nil
    }
    
    func fetchActiveCalls() {
        Logger.info("Fetch call infos")
        CallClient(authenticationStrategy: authenticationStrategy, deviceService: deviceService).fetchCallInfos() {
            switch $0.result {
            case .success(let callInfos):
                for callInfo in callInfos {
                    self.handle(callInfo: callInfo)
                }
                Logger.info("Success: fetch call infos")
            case .failure(let error):
                Logger.error("Failure", error: error)
            }
        }
    }
    
    func prepareToHandleCalls() {
        // TODO until this class has prepared to handle calls, it should probably not be asked to handle calls!
        reachabilityService.fetch() // TODO should have a callback to know when we're done fetching
    }
    
    func clearReachabilityState() {
        // XXX This is only a partial clearing of data, consider not clearing this at all, as it may be worthless to do so
        reachabilityService.clear()
    }
    
    func handle(callInfo: CallInfo) {
        guard let callUrl = callInfo.callUrl else {
            return
        }
        
        // TODO: support room call
        guard callInfo.isOneOnOne else {
            return
        }
        
        // If it belongs to existing active call, update it.
        if let call = callInstances[callUrl] {
            call.update(callInfo: callInfo)
        } else if let deviceUrl = deviceService.deviceUrl, callInfo.isIncomingCall, callInfo.hasJoinedOnOtherDevice(deviceUrl: deviceUrl) {
            let callClient = CallClient(authenticationStrategy: authenticationStrategy, deviceService: deviceService)
            let call = Call(callInfo, callManager: self, callClient: callClient, deviceUrl: deviceUrl)
            addCallWith(url: callUrl, call: call)

            if callInfo.isIncomingCall {
                PhoneNotificationCenter.sharedInstance.notifyIncomingCall(call)
                Logger.info("Receive incoming call")
            }
            // TODO: need to support other device joined case
        }
    }
    
    func createOutgoingCall() -> Call {
        let callClient = CallClient(authenticationStrategy: authenticationStrategy, deviceService: deviceService)
        return Call(callManager: self, callClient: callClient, deviceUrl: deviceService.deviceUrl!)
    }
}
