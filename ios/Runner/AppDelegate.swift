import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Clé lue depuis Info.plist (injectée par SecretKeys.xcconfig) — jamais hardcodée.
    let mapsKey = Bundle.main.object(forInfoDictionaryKey: "MapsApiKey") as? String ?? ""
    GMSServices.provideAPIKey(mapsKey)
    GeneratedPluginRegistrant.register(with: self)

    // super crée le FlutterViewController et la fenêtre — appeler avant d'accéder à window.
    let outcome = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Expose la clé Maps au côté Dart via MethodChannel.
    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(name: "dem/config", binaryMessenger: controller.binaryMessenger)
        .setMethodCallHandler { call, result in
          if call.method == "getMapsApiKey" {
            result(mapsKey)
          } else {
            result(FlutterMethodNotImplemented)
          }
        }
    }

    return outcome
  }
}
