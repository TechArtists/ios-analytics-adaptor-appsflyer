//  AppsFlyerAnalyticsAdaptor.swift
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

import AppsFlyerLib
import Foundation
@preconcurrency import TAAnalytics
import UIKit

/// AppsFlyer SDK configuration, session callbacks, and event mapping.
///
/// `AnalyticsAdaptorObservingAppLifecycle` gives the SDK the app lifecycle events it needs, and
/// `AnalyticsAdaptor` sends events to it. Each conformance lives in its own extension below.
///
/// The SDK's delegate is deliberately *not* set here: the host app owns `AppsFlyerLibDelegate`,
/// so that attribution can be routed alongside whatever else that app does with it. Use
/// ``makeAttribution(from:)`` to translate the payload the delegate receives.
public final class AppsFlyerAnalyticsAdaptor: NSObject, Sendable {

    public struct Configuration: Sendable {
        public let sdkKey: String
        public let appleAppID: String?
        public let attWaitTimeout: TimeInterval?
        public let isDebug: Bool
        public let customerUserID: @MainActor @Sendable () -> String?

        public init(sdkKey: String, appleAppID: String? = nil,
                    attWaitTimeout: TimeInterval? = nil, isDebug: Bool = false,
                    customerUserID: @escaping @MainActor @Sendable () -> String? = { nil }) {
            self.sdkKey = sdkKey
            self.appleAppID = appleAppID
            self.attWaitTimeout = attWaitTimeout
            self.isDebug = isDebug
            self.customerUserID = customerUserID
        }
    }

    public enum ConfigurationError: Error { case missingCredentials }

    /// A failure the SDK reports asynchronously, after the launch forward configured it.
    public enum Failure {
        /// `start()` failed — no session was recorded for this activation. Retried on the next one.
        case sessionStart(any Error)
        public var error: any Error {
            switch self {
            case .sessionStart(let error):
                return error
            }
        }

        /// Stable name for `trackErrorEvent(reason:)`. Unchanged from the strings this replaced,
        /// so dashboards already matching on them keep working.
        public var analyticsReason: String {
            switch self {
            case .sessionStart:
                return "appsflyer_start_failed"
            }
        }
    }

    private let configuration: Configuration
    public let eventMapper: any AppsFlyerEventMapping

    @MainActor private var isConfigured = false
    @MainActor public var onFailure: (@MainActor @Sendable (_ failure: Failure) -> Void)?

    private let enabledInstallTypes: [TAAnalyticsConfig.InstallType]
    private let sdkHasCredentials: @MainActor @Sendable () -> Bool
    private static let maxEventNameLength = 45

    public convenience init(configuration: Configuration,
                            eventMapper: any AppsFlyerEventMapping = AppsFlyerPassthroughEventMapper(),
                            enabledInstallTypes: [TAAnalyticsConfig.InstallType] = TAAnalyticsConfig.InstallType.allCases) {
        self.init(configuration: configuration, eventMapper: eventMapper,
                  enabledInstallTypes: enabledInstallTypes,
                  sdkHasCredentials: {
                      let sdk = AppsFlyerLib.shared()
                      return !sdk.appsFlyerDevKey.isEmpty
                          && !sdk.appleAppID.isEmpty
                          && sdk.appleAppID.allSatisfy(\.isNumber)
                  })
    }

    /// Test seam. `AppsFlyerLib` ignores an attempt to clear `appsFlyerDevKey`, so once any test
    /// sets one the "no credentials" path is unreachable for the rest of the process.
    init(configuration: Configuration, eventMapper: any AppsFlyerEventMapping,
         enabledInstallTypes: [TAAnalyticsConfig.InstallType],
         sdkHasCredentials: @escaping @MainActor @Sendable () -> Bool) {
        self.configuration = configuration
        self.eventMapper = eventMapper
        self.enabledInstallTypes = enabledInstallTypes
        self.sdkHasCredentials = sdkHasCredentials
        super.init()
    }

    /// Compatibility initializer. Supply appleAppID here or configure it on the SDK before launch.
    public convenience init(enabledInstallTypes: [TAAnalyticsConfig.InstallType] = TAAnalyticsConfig.InstallType.allCases,
                            sdkKey: String, appleAppID: String? = nil) {
        self.init(configuration: .init(sdkKey: sdkKey, appleAppID: appleAppID),
                  enabledInstallTypes: enabledInstallTypes)
    }

    /// The install identifier, available as soon as the SDK is configured. Purchase SDKs are given
    /// it so a purchase joins back to the install.
    @MainActor public var appsFlyerID: String? {
        guard isConfigured else { return nil }
        return AppsFlyerLib.shared().getAppsFlyerUID()
    }
}

// MARK: - AnalyticsAdaptorObservingAppLifecycle

extension AppsFlyerAnalyticsAdaptor: AnalyticsAdaptorObservingAppLifecycle {

    /// The credentials have to be in place before this returns: a cold launch through a OneLink
    /// delivers the URL immediately afterwards, and an unconfigured SDK cannot resolve it.
    ///
    /// Cannot fail, so unusable credentials simply leave the SDK unconfigured; `startFor` reads
    /// that back and refuses the adaptor, which is where TAAnalytics can still exclude it.
    @MainActor public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) {
        guard !isConfigured else { return }
        let sdk = AppsFlyerLib.shared()
        if configuration.sdkKey.isEmpty {
            isConfigured = sdkHasCredentials()
            return
        }
        let appID = configuration.appleAppID ?? sdk.appleAppID
        guard !configuration.sdkKey.isEmpty, !appID.isEmpty, appID.allSatisfy({ $0.isNumber }) else {
            return
        }
        sdk.appsFlyerDevKey = configuration.sdkKey
        sdk.appleAppID = appID
        sdk.isDebug = configuration.isDebug
        if let userID = configuration.customerUserID() { sdk.customerUserID = userID }
        if let timeout = configuration.attWaitTimeout, timeout > 0 {
            sdk.waitForATTUserAuthorization(timeoutInterval: timeout)
        }
        isConfigured = true
    }

    /// AppsFlyer counts one session per activation and deduplicates them server-side; the first
    /// one doubles as the install postback.
    @MainActor public func applicationDidBecomeActive() {
        guard isConfigured else { return }
        // Do not await the SDK's callback: this runs on the main thread during activation, and
        // AppsFlyer can hold the response for the whole ATT timeout.
        let failureHandler = onFailure
        AppsFlyerLib.shared().start { _, error in
            guard let error else { return }
            Task { @MainActor in failureHandler?(.sessionStart(error)) }
        }
    }

    @MainActor public func observeOpenURL(_ url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
        guard isConfigured else { return }
        AppsFlyerLib.shared().handleOpen(url, options: options)
    }

    @MainActor public func observeUserActivity(_ userActivity: NSUserActivity) {
        guard isConfigured else { return }
        AppsFlyerLib.shared().continue(userActivity, restorationHandler: nil)
    }
}

// MARK: - AnalyticsAdaptor

extension AppsFlyerAnalyticsAdaptor: AnalyticsAdaptor {

    public typealias T = AppsFlyerLib

    public func startFor(
        installType: TAAnalyticsConfig.InstallType,
        userDefaults: UserDefaults,
        taAnalytics: TAAnalytics
    ) async throws {
        guard enabledInstallTypes.contains(installType) else {
            throw InstallTypeError.invalidInstallType
        }
        // Events must never reach an SDK with no credentials. The test is the SDK's own state,
        // not this adaptor's: the launch forward normally sets the key, and a host
        // that configures `AppsFlyerLib` itself satisfies it just as well. Throwing keeps the
        // adaptor out of TAAnalytics' started set, so it receives no events at all rather than
        // logging into a dead SDK — and the failure surfaces once, at startup, instead of
        // silently per event.
        guard await sdkHasCredentials() else {
            throw ConfigurationError.missingCredentials
        }
        await MainActor.run { isConfigured = true }
        // Needs the install type, which a UIKit lifecycle forward does not carry but this does.
        eventMapper.setInstallType(installType)
    }

    public func track(trimmedEvent: EventAnalyticsModelTrimmed, params: [String: any AnalyticsBaseParameterValue]?) {
        guard let values = eventValues(for: trimmedEvent, params: params) else { return }
        AppsFlyerLib.shared().logEvent(trimmedEvent.rawValue, withValues: values)
    }

    /// AppsFlyer has no user-property concept — the closest thing, `setAdditionalData`, is a
    /// partner-integration channel that rides along on every event — so properties stop here.
    public func set(trimmedUserProperty: UserPropertyAnalyticsModelTrimmed, to: String?) {}

    public func trim(event: EventAnalyticsModel) -> EventAnalyticsModelTrimmed {
        EventAnalyticsModelTrimmed(
            event.rawValue.ta_trim(toLength: Self.maxEventNameLength, debugType: "event")
        )
    }

    public func trim(userProperty: UserPropertyAnalyticsModel) -> UserPropertyAnalyticsModelTrimmed {
        UserPropertyAnalyticsModelTrimmed(userProperty.rawValue)
    }

    public var wrappedValue: AppsFlyerLib {
        AppsFlyerLib.shared()
    }
}

// MARK: - Event values

extension AppsFlyerAnalyticsAdaptor {

    /// Applies the mapper, then re-validates the money it produced. The mapper decides *what* to
    /// send and *how much*; the adaptor decides whether AppsFlyer can read it.
    func eventValues(for trimmedEvent: EventAnalyticsModelTrimmed,
                    params: [String: any AnalyticsBaseParameterValue]?) -> [String: Any]? {
        guard let event = eventMapper.map(event: trimmedEvent, params: params) else { return nil }
        var values = event.parameters
        if let revenue = event.revenue,
           revenue.amount.isFinite, revenue.amount >= 0,
           revenue.currency.count == 3,
           revenue.currency.allSatisfy({ $0.isASCII && $0.isUppercase }) {
            values[AFEventParamRevenue] = revenue.amount
            values[AFEventParamCurrency] = revenue.currency
        }
        return values
    }
}

// MARK: - Attribution translation

extension AppsFlyerAnalyticsAdaptor {

    /// The `af_status` AppsFlyer reports for a non-attributed install, and the value both
    /// attributed and organic installs are normalised to, so the fields are never empty.
    private static let organicStatus = "Organic"
    private static let organicValue = "organic"

    /// Translates the payload `AppsFlyerLibDelegate.onConversionDataSuccess` receives.
    ///
    /// The delegate is owned by the host app, but the payload's shape is AppsFlyer's, so parsing it
    /// belongs here. Normalizes the SDK's untyped dictionary, then maps `af_status`, `media_source`,
    /// `campaign` and `is_first_launch` onto ``MMPAttribution``, keeping the `af_`-named fields as
    /// vendor parameters so nothing upstream has to know AppsFlyer's spelling.
    public static func makeAttribution(from conversionInfo: [AnyHashable: Any]) -> MMPAttribution {
        let info = conversionInfo.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String else { return }
            result[key] = String(describing: entry.value)
        }
        return makeAttribution(from: info)
    }

    static func makeAttribution(from info: [String: String]) -> MMPAttribution {
        let status = info["af_status"]
        let isOrganic = status == organicStatus
        let network = isOrganic ? organicValue : (info["media_source"] ?? organicValue)
        let campaign = isOrganic ? organicValue : (info["campaign"] ?? organicValue)

        var vendorParameters = [String: String]()
        vendorParameters["af_install_time"] = info["install_time"]
        vendorParameters["af_click_time"] = info["click_time"]

        // The raw AppsFlyer fields are only meaningful for an attributed install.
        if !isOrganic {
            vendorParameters["af_media_source"] = info["media_source"]
            vendorParameters["af_campaign"] = info["campaign"]
            vendorParameters["af_status"] = status
        }

        return MMPAttribution(
            network: network,
            campaign: campaign,
            isOrganic: isOrganic,
            isFirstLaunch: isFirstLaunch(info),
            vendorParameters: vendorParameters,
            raw: info
        )
    }

    /// AppsFlyer sometimes hands this back stringified rather than as a boolean.
    private static func isFirstLaunch(_ info: [String: String]) -> Bool {
        let flag = info["is_first_launch"]?.lowercased()
        return flag == "true" || flag == "1"
    }
}

// MARK: - AnalyticsAdaptorWithReadWriteUserID

extension AppsFlyerAnalyticsAdaptor: AnalyticsAdaptorWithReadWriteUserID {

    public func set(userID: String?) { AppsFlyerLib.shared().customerUserID = userID }
    public func getUserID() -> String? { AppsFlyerLib.shared().customerUserID }
}
