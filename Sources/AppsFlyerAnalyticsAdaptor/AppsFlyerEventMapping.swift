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

import TAAnalytics

/// Maps or filters events without embedding an app's business rules in the SDK adaptor.
/// Calls may originate from TAAnalytics' event actor, so implementations must be Sendable.
public protocol AppsFlyerEventMapping: Sendable {
    /// The install type, handed over during `startFor` — before any event can reach
    /// ``map(event:params:)``. A UIKit lifecycle forward carries no install type, which is why
    /// this arrives from there rather than at launch. Optional; ignored by default.
    func setInstallType(_ installType: TAAnalyticsConfig.InstallType)
    func map(event: EventAnalyticsModelTrimmed,
             params: [String: any AnalyticsBaseParameterValue]?) -> AppsFlyerEventPayload?
}

public extension AppsFlyerEventMapping {
    func setInstallType(_ installType: TAAnalyticsConfig.InstallType) {}
}

/// A synchronous mapping result. Untyped SDK parameters never cross an actor boundary here.
public struct AppsFlyerEventPayload {
    public struct Revenue: Sendable {
        public let amount: Double
        public let currency: String
        public init(amount: Double, currency: String) {
            self.amount = amount
            self.currency = currency
        }
    }

    public let parameters: [String: Any]
    public let revenue: Revenue?
    public init(parameters: [String: Any], revenue: Revenue? = nil) {
        self.parameters = parameters
        self.revenue = revenue
    }
}

/// Default behavior retains event names and original numeric/boolean parameter types.
public struct AppsFlyerPassthroughEventMapper: AppsFlyerEventMapping {
    public init() {}
    public func map(event: EventAnalyticsModelTrimmed,
                    params: [String: any AnalyticsBaseParameterValue]?) -> AppsFlyerEventPayload? {
        .init(parameters: params?.mapValues { $0 as Any } ?? [:])
    }
}
