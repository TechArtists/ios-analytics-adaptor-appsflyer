/*
MIT License

Copyright (c) 2025 Tech Artists Agency

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

//  TAAppsFlyerConsumer.swift
//  Created by Adi on 10/24/22.
//
//  Copyright (c) 2022 TA SRL (http://TA.com/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation
import OSLog

import TAAnalytics
import AppsFlyerLib

public class TAAppsFlyerConsumer: AnalyticsConsumer, AnalyticsConsumerWithWriteOnlyUserID {
   
    public static let DevKey = "AppFlyerDevKey"
    public static let AppleAppId = "AppleAppIdKey"
    
    let appsFlyerTrackerInstance: AppsFlyerLib = AppsFlyerLib.shared()
  
    init(devKey: String, appleAppId: String) {
        appsFlyerTrackerInstance.appsFlyerDevKey = devKey
        appsFlyerTrackerInstance.appleAppID = appleAppId
    }
    
    public func startFor(installType: TAAnalyticsConfig.InstallType, userDefaults: UserDefaults, TAAnalytics: TAAnalytics) async throws {
        do {
            try await AppsFlyerLib.shared().start()
        } catch {
            throw error
        }
    }
    
    public func track(trimmedEvent: TrimmedEvent, params: [String : any AnalyticsBaseParameterValue]?) {
        let event = trimmedEvent.event
        
        appsFlyerTrackerInstance.logEvent(event.rawValue, withValues: params)
    }
    
    public func set(trimmedUserProperty: TrimmedUserProperty, to: String?) {
        //let userProperty = trimmedUserProperty.userProperty
    }
    
    public func trim(event: AnalyticsEvent) -> TrimmedEvent {
        TrimmedEvent(event.rawValue.ob_trim(type: "event", toLength: 40))
    }
    
    public func trim(userProperty: AnalyticsUserProperty) -> TrimmedUserProperty {
        TrimmedUserProperty(userProperty.rawValue.ob_trim(type: "user property", toLength: 40))
    }
    
    public var wrappedValue: TAAppsFlyerConsumer {
        self
    }
    
    public typealias T = TAAppsFlyerConsumer
    
    public func set(userID: String?) {
        AppsFlyerLib.shared().customerUserID = userID
    }
    
    public typealias T = TAAppsFlyerConsumer
    
}
