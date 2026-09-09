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

import XCTest
import TAAnalytics
import AppsFlyerLib
@testable import AppsFlyerAnalyticsAdaptor

final class AppsFlyerAnalyticsAdaptorTests: XCTestCase {
    func testDefaultMapperPreservesNumericValuesAndCustomEvents() {
        let adaptor = AppsFlyerAnalyticsAdaptor(configuration: .init(sdkKey: "test", appleAppID: "123"))
        let values = adaptor.eventValues(for: adaptor.trim(event: .init("custom")), params: ["count": 3, "enabled": true])
        XCTAssertEqual(values?["count"] as? Int, 3)
        XCTAssertEqual(values?["enabled"] as? Bool, true)
    }

    func testInjectedMapperCanFilterEventsAndSupplyRevenue() {
        let adaptor = AppsFlyerAnalyticsAdaptor(configuration: .init(sdkKey: "test", appleAppID: "123"), eventMapper: TestMapper())
        XCTAssertNil(adaptor.eventValues(for: .init("ignored"), params: nil))
        let values = adaptor.eventValues(for: .init("purchase"), params: nil)
        XCTAssertEqual(values?[AFEventParamRevenue] as? Double, 20)
        XCTAssertEqual(values?[AFEventParamCurrency] as? String, "USD")
        XCTAssertEqual(values?["custom"] as? Bool, true)
    }

    func testInvalidMappedRevenueIsWithheld() {
        for revenue in [AppsFlyerEventPayload.Revenue(amount: .nan, currency: "USD"),
                        .init(amount: -1, currency: "USD"), .init(amount: 20, currency: "$")] {
            let adaptor = AppsFlyerAnalyticsAdaptor(configuration: .init(sdkKey: "test", appleAppID: "123"),
                                                    eventMapper: TestMapper(revenue: revenue))
            let values = adaptor.eventValues(for: .init("purchase"), params: nil)
            XCTAssertNil(values?[AFEventParamRevenue])
            XCTAssertNil(values?[AFEventParamCurrency])
        }
    }

    func testFailureReasonKeepsTheNameDashboardsAlreadyMatchOn() {
        struct Stub: Error {}
        let session = AppsFlyerAnalyticsAdaptor.Failure.sessionStart(Stub())
        // This string reaches trackErrorEvent(reason:); changing it silently breaks reporting.
        XCTAssertEqual(session.analyticsReason, "appsflyer_start_failed")
        XCTAssertTrue(session.error is Stub)
    }

    func testAttributionTranslatesStraightFromTheSDKPayloadType() {
        // The host app owns the delegate, so the untyped SDK dictionary is the public entry point.
        let raw: [AnyHashable: Any] = ["af_status": "Non-organic", "media_source": "tiktok",
                                       "campaign": "autumn_sale", "is_first_launch": true]
        let attribution = AppsFlyerAnalyticsAdaptor.makeAttribution(from: raw)
        XCTAssertEqual(attribution.network, "tiktok")
        XCTAssertEqual(attribution.campaign, "autumn_sale")
        XCTAssertTrue(attribution.isFirstLaunch)
        XCTAssertFalse(attribution.isOrganic)
    }

    func testOrganicInstallNormalizesFieldsAndOmitsVendorParameters() {
        let attribution = AppsFlyerAnalyticsAdaptor.makeAttribution(from: [
            "af_status": "Organic", "media_source": "ignored", "campaign": "ignored",
            "install_time": "2026-09-09 10:00:00"
        ])
        XCTAssertTrue(attribution.isOrganic)
        XCTAssertEqual(attribution.network, "organic")
        XCTAssertEqual(attribution.campaign, "organic")
        // An organic install carries no meaningful source, so the af_ fields are withheld.
        XCTAssertNil(attribution.vendorParameters["af_media_source"])
        XCTAssertNil(attribution.vendorParameters["af_campaign"])
        XCTAssertNil(attribution.vendorParameters["af_status"])
        XCTAssertEqual(attribution.vendorParameters["af_install_time"], "2026-09-09 10:00:00")
    }

    func testAttributedInstallKeepsSourceAndVendorParameters() {
        let attribution = AppsFlyerAnalyticsAdaptor.makeAttribution(from: [
            "af_status": "Non-organic", "media_source": "tiktok", "campaign": "autumn_sale",
            "click_time": "2026-09-08 09:00:00"
        ])
        XCTAssertFalse(attribution.isOrganic)
        XCTAssertEqual(attribution.network, "tiktok")
        XCTAssertEqual(attribution.campaign, "autumn_sale")
        XCTAssertEqual(attribution.vendorParameters["af_media_source"], "tiktok")
        XCTAssertEqual(attribution.vendorParameters["af_campaign"], "autumn_sale")
        XCTAssertEqual(attribution.vendorParameters["af_status"], "Non-organic")
        XCTAssertEqual(attribution.vendorParameters["af_click_time"], "2026-09-08 09:00:00")
        XCTAssertNil(attribution.vendorParameters["af_install_time"])
    }

    func testAttributedInstallWithoutSourceFallsBackRatherThanEmptying() {
        let attribution = AppsFlyerAnalyticsAdaptor.makeAttribution(from: ["af_status": "Non-organic"])
        XCTAssertEqual(attribution.network, "organic")
        XCTAssertEqual(attribution.campaign, "organic")
    }

    func testFirstLaunchAcceptsBothStringShapesTheSDKSends() {
        for (value, expected) in [("true", true), ("TRUE", true), ("1", true),
                                  ("false", false), ("0", false)] {
            let attribution = AppsFlyerAnalyticsAdaptor.makeAttribution(from: ["is_first_launch": value])
            XCTAssertEqual(attribution.isFirstLaunch, expected, "is_first_launch=\(value)")
        }
        XCTAssertFalse(AppsFlyerAnalyticsAdaptor.makeAttribution(from: [:]).isFirstLaunch)
    }

    func testRawPayloadIsPreservedForVendorSpecificConsumers() {
        let info = ["af_status": "Non-organic", "media_source": "tiktok", "custom_field": "kept"]
        XCTAssertEqual(AppsFlyerAnalyticsAdaptor.makeAttribution(from: info).raw, info)
    }

    @MainActor func testAnUnconfiguredSDKIsRefusedRatherThanLoggingIntoNothing() async {
        // The SDK ignores attempts to clear its dev key, so the credential state is injected.
        let adaptor = AppsFlyerAnalyticsAdaptor(configuration: .init(sdkKey: "test", appleAppID: "123"),
                                                eventMapper: AppsFlyerPassthroughEventMapper(),
                                                enabledInstallTypes: TAAnalyticsConfig.InstallType.allCases,
                                                sdkHasCredentials: { false })
        let analytics = TAAnalytics(config: .init(analyticsVersion: "test", adaptors: []))
        do {
            try await adaptor.startFor(installType: .AppStore, userDefaults: .standard, taAnalytics: analytics)
            XCTFail("startFor must refuse an SDK that has no credentials")
        } catch {}
    }

    @MainActor func testAHostThatConfiguresTheSDKItselfStillReceivesEvents() async throws {
        // Such a host never lets the adaptor configure the SDK, so the guard has to read the
        // SDK's own state rather than this adaptor's isConfigured flag.
        let adaptor = AppsFlyerAnalyticsAdaptor(configuration: .init(sdkKey: "", appleAppID: ""),
                                                eventMapper: AppsFlyerPassthroughEventMapper(),
                                                enabledInstallTypes: TAAnalyticsConfig.InstallType.allCases,
                                                sdkHasCredentials: { true })
        let analytics = TAAnalytics(config: .init(analyticsVersion: "test", adaptors: []))
        try await adaptor.startFor(installType: .AppStore, userDefaults: .standard, taAnalytics: analytics)
    }

    @MainActor func testStartForHandsTheInstallTypeToTheMapper() async throws {
        // A UIKit lifecycle forward carries no install type, so this is startFor's job.
        let mapper = RecordingMapper()
        let adaptor = AppsFlyerAnalyticsAdaptor(configuration: .init(sdkKey: "test", appleAppID: "123"),
                                                eventMapper: mapper,
                                                enabledInstallTypes: TAAnalyticsConfig.InstallType.allCases,
                                                sdkHasCredentials: { true })
        XCTAssertNil(mapper.installType)
        try await adaptor.startFor(installType: .TestFlight, userDefaults: .standard,
                                   taAnalytics: TAAnalytics(config: .init(analyticsVersion: "test", adaptors: [])))
        XCTAssertEqual(mapper.installType, .TestFlight)
    }

    @MainActor func testARefusedStartForTellsTheMapperNothing() async {
        let mapper = RecordingMapper()
        let adaptor = AppsFlyerAnalyticsAdaptor(configuration: .init(sdkKey: "test", appleAppID: "123"),
                                                eventMapper: mapper,
                                                enabledInstallTypes: TAAnalyticsConfig.InstallType.allCases,
                                                sdkHasCredentials: { false })
        let analytics = TAAnalytics(config: .init(analyticsVersion: "test", adaptors: []))
        do {
            try await adaptor.startFor(installType: .AppStore, userDefaults: .standard, taAnalytics: analytics)
            XCTFail("startFor must refuse an SDK that has no credentials")
        } catch {}
        XCTAssertNil(mapper.installType)
    }

    @MainActor func testADisabledInstallTypeIsRejected() async {
        let adaptor = AppsFlyerAnalyticsAdaptor(configuration: .init(sdkKey: "test", appleAppID: "123"),
                                                eventMapper: AppsFlyerPassthroughEventMapper(),
                                                enabledInstallTypes: [.AppStore],
                                                sdkHasCredentials: { true })
        let analytics = TAAnalytics(config: .init(analyticsVersion: "test", adaptors: []))
        do {
            try await adaptor.startFor(installType: .Xcode, userDefaults: .standard, taAnalytics: analytics)
            XCTFail("startFor must refuse a disabled install type")
        } catch {}
    }

    @MainActor func testUnusableCredentialsLeaveTheSDKUnconfigured() {
        // The launch forward cannot throw, so a bad configuration has to show up as "not
        // configured" — which is what startFor and appsFlyerID both read.
        let adaptor = AppsFlyerAnalyticsAdaptor(configuration: .init(sdkKey: "", appleAppID: ""))
        adaptor.application(.shared, didFinishLaunchingWithOptions: nil)
        XCTAssertNil(adaptor.appsFlyerID)
    }
}

private struct TestMapper: AppsFlyerEventMapping {
    var revenue = AppsFlyerEventPayload.Revenue(amount: 20, currency: "USD")
    func map(event: EventAnalyticsModelTrimmed, params: [String: any AnalyticsBaseParameterValue]?) -> AppsFlyerEventPayload? {
        guard event.rawValue == "purchase" else { return nil }
        return .init(parameters: ["custom": true], revenue: revenue)
    }
}

private final class RecordingMapper: AppsFlyerEventMapping, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: TAAnalyticsConfig.InstallType?
    var installType: TAAnalyticsConfig.InstallType? {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
    func setInstallType(_ installType: TAAnalyticsConfig.InstallType) {
        lock.lock(); defer { lock.unlock() }
        recorded = installType
    }
    func map(event: EventAnalyticsModelTrimmed,
             params: [String: any AnalyticsBaseParameterValue]?) -> AppsFlyerEventPayload? {
        .init(parameters: [:])
    }
}
