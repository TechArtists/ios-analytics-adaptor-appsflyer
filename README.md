# AppsFlyerAnalyticsAdaptor

An AppsFlyer SDK adaptor for TAAnalytics 1.14.0 or later. Version 0.11.0 keeps the Swift 6 and iOS 15 requirements. The package retains its historical macOS platform declaration, but its UIKit-dependent integration and TAAnalytics dependency are intended and tested for iOS.

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

## Lifecycle

TAAnalytics configures this adaptor at launch and starts a session on each activation, its policy being `.everyForeground`. Each adaptor becomes ready independently, so a slow SDK cannot delay this one's session. Waiting for the network or for ATT never blocks adaptor preparation.

Forward links through TAAnalytics, which calls `observeOpenURL(_:options:)` and `observeUserActivity(_:)` on every configured adaptor. Both observe only, so app routing is unaffected.

Set `onFailure` on the main actor to receive a typed `Failure`. Only `.sessionStart` originates here — it is transient, and retried on the next foreground.

## Events

The default `AppsFlyerPassthroughEventMapper` preserves custom events and parameter types. Inject an `AppsFlyerEventMapping` implementation to filter events (return nil) or return an `AppsFlyerEventPayload` with parameters and optional revenue, which the adaptor validates as finite, non-negative and ISO-4217-shaped before converting to the native AppsFlyer keys. Mapping implementations must be Sendable, because TAAnalytics delivers events from its event actor.

## Attribution

The adaptor does not claim `AppsFlyerLibDelegate`, and `configure(installType:)` deliberately leaves the SDK's delegate unset. The host app owns it, so attribution can be routed alongside whatever else that app does with it. Only the parsing lives here, because only the payload's shape is AppsFlyer's:

```swift
extension MyHandler: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        let attribution = AppsFlyerAnalyticsAdaptor.makeAttribution(from: conversionInfo)
        Task { @MainActor in analytics.trackMMPAttribution(attribution) }
    }

    func onConversionDataFail(_ error: any Error) { /* report it */ }
}
```

`makeAttribution(from:)` normalises `af_status`, `media_source`, `campaign` and `is_first_launch` into TAAnalytics' `MMPAttribution`, carries the `af_`-named fields as `vendorParameters`, and keeps the original payload as `raw`. `trackMMPAttribution(_:)` then sets the shared `mmp_attributed_*` user properties and records the install once.

## Migration

The existing sdkKey initializer remains available. Set the numeric Apple app ID there or on the SDK before launch. Direct `startFor` calls prepare the mapper only; TAAnalytics owns SDK session startup.

From 0.10.0: `AppsFlyerMappedEvent` is now `AppsFlyerEventPayload`, `onError(reason:error:)` is now `onFailure(Failure)`, and `onAttribution` is gone — the app owns the delegate and calls `makeAttribution(from:)` instead.

[AppsFlyer SDK lifecycle documentation](https://dev.appsflyer.com/hc/docs/integrate-ios-sdk)
