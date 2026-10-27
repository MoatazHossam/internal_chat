import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // FlutterAppDelegate forwards notification callbacks to plugins such as
    // PushNotificationsPlugin below.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PushNotificationsPlugin") {
      PushNotificationsPlugin.register(with: registrar)
    }
  }
}

/// Push notifications through APNs, without any third-party SDK.
///
/// The push itself carries the visible text (a generic "New message" in the
/// user's language, set when the app registers its pusher), the room ID and
/// the event ID. Nothing here reads message content.
final class PushNotificationsPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var token: String?
  private var waitingForToken: [FlutterResult] = []
  /// A notification tapped before Dart asked for it (cold start).
  private var pendingRoom: String?
  private var dartReady = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "internal_chat/push", binaryMessenger: registrar.messenger())
    let instance = PushNotificationsPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermission":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
        granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    case "getToken":
      if let token {
        result(Self.tokenArguments(token))
        return
      }
      waitingForToken.append(result)
      UIApplication.shared.registerForRemoteNotifications()
    case "takeOpenedRoom":
      dartReady = true
      result(pendingRoom)
      pendingRoom = nil
    case "clearDelivered":
      let center = UNUserNotificationCenter.current()
      center.removeAllDeliveredNotifications()
      if #available(iOS 16.0, *) {
        center.setBadgeCount(0)
      } else {
        UIApplication.shared.applicationIconBadgeNumber = 0
      }
      result(nil)
    case "setAlertText":
      // iOS receives the text inside the push.
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Token

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // The gateway (Sygnal) expects the APNs token base64-encoded.
    let value = deviceToken.base64EncodedString()
    let changed = token != nil && token != value
    token = value
    let waiting = waitingForToken
    waitingForToken.removeAll()
    waiting.forEach { $0(Self.tokenArguments(value)) }
    if changed {
      channel.invokeMethod("tokenChanged", arguments: Self.tokenArguments(value))
    }
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    let waiting = waitingForToken
    waitingForToken.removeAll()
    waiting.forEach { $0(FlutterError(code: "token_unavailable", message: nil, details: nil)) }
  }

  private static func tokenArguments(_ token: String) -> [String: String] {
    ["service": "apns", "token": token]
  }

  // MARK: - Notifications

  /// In the foreground the conversation list updates live, so no banner.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let room = response.notification.request.content.userInfo["room_id"] as? String,
      !room.isEmpty
    {
      if dartReady {
        channel.invokeMethod("opened", arguments: room)
      } else {
        pendingRoom = room
      }
    }
    completionHandler()
  }
}
