import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Az emlékeztetők akkor is megjelennek, ha az alkalmazás nyitva van.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private var captureChannel: FlutterMethodChannel?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Az Apple Pay-automatizmusból érkezett fizetések átadása a Dart-oldalnak.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BeleferCapture") {
      let channel = FlutterMethodChannel(
        name: "belefer/capture",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "drain":
          result(CaptureStore.drain())
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      captureChannel = channel
    }
  }
}
