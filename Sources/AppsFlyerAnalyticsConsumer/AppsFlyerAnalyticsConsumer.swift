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

//  AppsFlyerAnalyticsConsumer.swift
//  Created by Adi on 10/24/22.
//
//  Copyright (c) 2022 Tech Artists Agency SRL
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

public class AppsFlyerAnalyticsConsumer: AnalyticsConsumer, AnalyticsConsumerWithReadWriteUserID {
   
    public typealias T = AppsFlyerLib

    private let sdkKey: String
    private let enabledInstallTypes: [TAAnalyticsConfig.InstallType]
    private let isRedacted: Bool

    public init(
        enabledInstallTypes: [TAAnalyticsConfig.InstallType] = TAAnalyticsConfig.InstallType.allCases,
        isRedacted: Bool = true,
        sdkKey: String
    ) {
        self.sdkKey = sdkKey
        self.enabledInstallTypes = enabledInstallTypes
        self.isRedacted = isRedacted

        AppsFlyerLib.shared().appsFlyerDevKey = sdkKey
    }

    public func startFor(installType: TAAnalyticsConfig.InstallType, userDefaults: UserDefaults, TAAnalytics: TAAnalytics) async throws {
        if !self.enabledInstallTypes.contains(installType) {
            throw InstallTypeError.invalidInstallType
        }
        try await AppsFlyerLib.shared().start()
    }

    public func track(trimmedEvent: EventAnalyticsModelTrimmed, params: [String: any AnalyticsBaseParameterValue]?) {
        var eventValues = [String: Any]()
        if let params = params {
            for (key, value) in params {
                eventValues[key] = value.description
            }
        }
        AppsFlyerLib.shared().logEvent(trimmedEvent.rawValue, withValues: eventValues)
    }

    public func set(trimmedUserProperty: UserPropertyAnalyticsModelTrimmed, to: String?) {
        // AppsFlyer does not support setting user properties directly
    }

    public func trim(event: EventAnalyticsModel) -> EventAnalyticsModelTrimmed {
        EventAnalyticsModelTrimmed(event.rawValue.ta_trim(toLength: 40, debugType: "event"))
    }

    public func trim(userProperty: UserPropertyAnalyticsModel) -> UserPropertyAnalyticsModelTrimmed {
        UserPropertyAnalyticsModelTrimmed(userProperty.rawValue.ta_trim(toLength: 40, debugType: "user property"))
    }

    public var wrappedValue: T {
        AppsFlyerLib.shared()
    }

    public func set(userID: String?) {
        AppsFlyerLib.shared().customerUserID = userID
    }

    public func getUserID() -> String? {
        AppsFlyerLib.shared().customerUserID
    }
}
