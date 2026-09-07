import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Info.plist declares UIApplicationSceneManifest, so this app's real
    // window lives on a UIWindowScene — the legacy `AppDelegate.window`
    // property is never populated by UIKit in that setup and stays nil
    // (applicationDidBecomeActive doesn't populate it either in this
    // Scene-based lifecycle). flutter_stripe's iOS plugin (stripe_ios's
    // StripeSdk.swift) still looks up the presenting view controller via
    // `UIApplication.shared.delegate?.window`; when that's nil it silently
    // presents from a brand-new, disconnected UIViewController instead,
    // which is a silent UIKit no-op — no crash, no error, the sheet never
    // renders. Populating `self.window` the moment any window becomes
    // visible keeps that legacy lookup working without touching Flutter's
    // own Scene-based window management.
    NotificationCenter.default.addObserver(
      forName: UIWindow.didBecomeVisibleNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self = self, self.window == nil else { return }
      self.window = notification.object as? UIWindow
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
