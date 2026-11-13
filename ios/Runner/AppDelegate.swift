import Flutter
import UIKit
import AVFoundation
import Contacts

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let btChannel = FlutterMethodChannel(name: "com.example.akilli_asistan/bluetooth",
                                          binaryMessenger: controller.binaryMessenger)

    btChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "isHeadsetConnected":
        let route = AVAudioSession.sharedInstance().currentRoute
        let connected = route.outputs.contains {
          $0.portType == .bluetoothA2DP ||
          $0.portType == .bluetoothHFP ||
          $0.portType == .bluetoothLE ||
          $0.portType == .headphones
        }
        result(connected)

      case "startBluetoothMic":
        do {
          let session = AVAudioSession.sharedInstance()
          try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
          try session.setActive(true)
          result(true)
        } catch {
          result(false)
        }

      case "stopBluetoothMic":
        result(true)

      case "makeCall":
        if let args = call.arguments as? [String: Any],
           let number = args["number"] as? String {
          let clean = number.replacingOccurrences(of: " ", with: "")
          if let url = URL(string: "tel://\(clean)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
          }
        }
        result(true)

      case "findContact":
        if let args = call.arguments as? [String: Any],
           let query = args["name"] as? String {
          let store = CNContactStore()
          let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
          let predicate = CNContact.predicateForContacts(matchingName: query)
          if let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys),
             let first = contacts.first,
             let phone = first.phoneNumbers.first?.value.stringValue {
            let fullName = "\(first.givenName) \(first.familyName)".trimmingCharacters(in: .whitespaces)
            result(["name": fullName, "number": phone])
            return
          }
        }
        result(nil)

      case "openGemini":
        if let url = URL(string: "googlegemini://"), UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url)
          result(true)
        } else if let webUrl = URL(string: "https://google.com") {
          UIApplication.shared.open(webUrl)
          result(true)
        } else {
          result(false)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}