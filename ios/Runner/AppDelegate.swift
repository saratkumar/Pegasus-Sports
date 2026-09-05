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

    // TODO(debug): reports live native window/view-controller state on
    // demand, so the "presentPaymentSheet never renders" hang can be
    // diagnosed from on-device UI alone — no Mac, no external log capture.
    // Mirrors exactly what stripe_ios's presentPaymentSheet/
    // findViewControllerPresenter (StripeSdk.swift) would resolve when
    // looking for a view controller to present from. Remove once
    // root-caused.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DebugDiagnostics") {
      let channel = FlutterMethodChannel(
        name: "debug/native_diagnostics",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "checkWindowState" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let delegateWindow = UIApplication.shared.delegate?.window ?? nil
        let scenes = UIApplication.shared.connectedScenes
        let windowScenes = scenes.compactMap { $0 as? UIWindowScene }
        let sceneWindow = windowScenes.first?.windows.first
        let effectivePresenter = delegateWindow?.rootViewController
          ?? sceneWindow?.rootViewController
        var topPresenter = effectivePresenter
        while let presented = topPresenter?.presentedViewController {
          topPresenter = presented
        }
        result([
          "appDelegateWindowIsNil": delegateWindow == nil,
          "appDelegateWindowIsKeyWindow": delegateWindow?.isKeyWindow ?? false,
          "connectedScenesCount": scenes.count,
          "windowScenesCount": windowScenes.count,
          "firstWindowSceneWindowCount": windowScenes.first?.windows.count ?? -1,
          "sceneWindowRootVCType": sceneWindow?.rootViewController.map { "\(type(of: $0))" } ?? "nil",
          "effectivePresenterType": effectivePresenter.map { "\(type(of: $0))" } ?? "nil",
          "topPresenterType": topPresenter.map { "\(type(of: $0))" } ?? "nil",
          "topPresenterViewInWindow": topPresenter?.viewIfLoaded?.window != nil,
        ])
      }
    }
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
