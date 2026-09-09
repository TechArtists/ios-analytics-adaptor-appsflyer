# AppsFlyerAnalyticsAdaptor

An AppsFlyer SDK adaptor for TAAnalytics 1.13.0 or later. Version 0.10.0 keeps the Swift 6 and iOS 15 requirements. The package retains its historical macOS platform declaration, but its UIKit-dependent integration and TAAnalytics dependency are intended and tested for iOS.

```swift
let adaptor = AppsFlyerAnalyticsAdaptor(configuration: .init(
    sdkKey: appsFlyerKey,
    appleAppID: appleAppID,
    attWaitTimeout: 480
))
let analytics = TAAnalytics(config: .init(analyticsVersion: "1", adaptors: [adaptor]))
// In didFinishLaunchingWithOptions, after SDK prerequisites:
analytics.applicationDidFinishLaunching()
Task { await analytics.start() }
```

TAAnalytics configures this adaptor at launch and starts sessions when the app becomes active. Each successful adaptor becomes ready independently. Network and ATT completion do not block adaptor preparation. Supply `onAttribution` and `onError` on the main actor to receive SDK callbacks. Forward links through TAAnalytics; ETUAppCore handles this automatically.

The default `AppsFlyerPassthroughEventMapper` preserves custom events and parameter types. Inject an `AppsFlyerEventMapping` implementation to filter events (return nil) or return an `AppsFlyerMappedEvent` with parameters and optional revenue. The adaptor converts revenue to the native AppsFlyer keys. ETUAppCore provides `ETUAppsFlyerEventMapper` for its purchase-funnel and trial rules. Mapping implementations must be Sendable because TAAnalytics delivers events from its event actor.

Migration: the existing sdkKey initializer remains available. Set the numeric Apple app ID there or on the SDK before launch. Direct `startFor` calls prepare the mapper only; TAAnalytics now owns actual SDK session startup.

[AppsFlyer SDK lifecycle documentation](https://dev.appsflyer.com/hc/docs/integrate-ios-sdk)
