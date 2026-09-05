import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // Info.plist declares UIApplicationSceneManifest, so this app's real
  // window lives on a UIWindowScene — the legacy `AppDelegate.window`
  // property is never populated by Flutter/UIKit in that setup and stays
  // nil. Some plugins (e.g. flutter_stripe's iOS implementation of
  // presentPaymentSheet, in stripe_ios's StripeSdk.swift) still look up
  // the presenting view controller via `UIApplication.shared.delegate?
  // .window`, exactly as if this were a pre-Scene app. When that's nil,
  // Stripe silently falls back to presenting from a brand-new, disconnected
  // UIViewController — presenting from a view controller with no window
  // is a silent no-op in UIKit: no crash, no error, the completion handler
  // never fires, and the sheet never renders. Populating `self.window`
  // here from the connected scene keeps that legacy lookup working without
  // touching Flutter's own Scene-based window management.
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    if self.window == nil {
      self.window = application.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.windows.first }
        .first
    }
  }
}
