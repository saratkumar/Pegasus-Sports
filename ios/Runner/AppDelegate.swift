import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Confirmed via an on-device diagnostic: in this Scene-based app (see
    // Info.plist's UIApplicationSceneManifest), applicationDidBecomeActive
    // never actually runs (or runs before the scene's window exists) — the
    // legacy `self.window` property stayed nil even with that hook in
    // place. Rather than guess another specific lifecycle callback,
    // populate it the moment ANY window actually becomes visible — this
    // doesn't depend on lifecycle ordering at all, only on the one event
    // that must eventually happen for the app to be usable. flutter_stripe's
    // iOS plugin (stripe_ios's StripeSdk.swift) still looks up the
    // presenting view controller via `UIApplication.shared.delegate?
    // .window`; when that's nil it silently presents from a brand-new,
    // disconnected UIViewController instead, which is a silent UIKit
    // no-op — no crash, no error, the sheet never renders. This keeps that
    // legacy lookup working without touching Flutter's own Scene-based
    // window management.
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
      channel.setMethodCallHandler { call, result in
        guard call.method == "checkWindowState" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let delegateWindow: UIWindow? = UIApplication.shared.delegate?.window ?? nil
        let scenes: Set<UIScene> = UIApplication.shared.connectedScenes
        let windowScenes: [UIWindowScene] = scenes.compactMap { $0 as? UIWindowScene }
        let sceneWindow: UIWindow? = windowScenes.first?.windows.first
        let effectivePresenter: UIViewController? =
          delegateWindow?.rootViewController ?? sceneWindow?.rootViewController

        var topPresenter: UIViewController? = effectivePresenter
        while let presented = topPresenter?.presentedViewController {
          topPresenter = presented
        }

        let sceneWindowRootVCType: String
        if let vc = sceneWindow?.rootViewController {
          sceneWindowRootVCType = "\(type(of: vc))"
        } else {
          sceneWindowRootVCType = "nil"
        }

        let effectivePresenterType: String
        if let vc = effectivePresenter {
          effectivePresenterType = "\(type(of: vc))"
        } else {
          effectivePresenterType = "nil"
        }

        let topPresenterType: String
        if let vc = topPresenter {
          topPresenterType = "\(type(of: vc))"
        } else {
          topPresenterType = "nil"
        }

        let topPresenterViewInWindow: Bool = topPresenter?.viewIfLoaded?.window != nil

        let diagnostics: [String: Any] = [
          "appDelegateWindowIsNil": delegateWindow == nil,
          "appDelegateWindowIsKeyWindow": delegateWindow?.isKeyWindow ?? false,
          "connectedScenesCount": scenes.count,
          "windowScenesCount": windowScenes.count,
          "firstWindowSceneWindowCount": windowScenes.first?.windows.count ?? -1,
          "sceneWindowRootVCType": sceneWindowRootVCType,
          "effectivePresenterType": effectivePresenterType,
          "topPresenterType": topPresenterType,
          "topPresenterViewInWindow": topPresenterViewInWindow,
        ]
        result(diagnostics)
      }
    }
  }
}
