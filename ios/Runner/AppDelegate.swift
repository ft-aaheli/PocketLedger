import Flutter
import LocalAuthentication
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var credentialContext: LAContext?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let lock = FlutterMethodChannel(name: "pocketledger/device_lock", binaryMessenger: messenger)
    lock.setMethodCallHandler { [weak self] call, result in
      guard call.method == "confirm" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self else {
        result(FlutterError(code: "unavailable", message: nil, details: nil))
        return
      }
      self.confirmDeviceOwner(result)
    }

    let storage = FlutterMethodChannel(name: "pocketledger/storage", binaryMessenger: messenger)
    storage.setMethodCallHandler { call, result in
      guard call.method == "databasePath" else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        let files = FileManager.default
        let support = try files.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask, appropriateFor: nil, create: true)
        var directory = support.appendingPathComponent("PocketLedger", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try directory.setResourceValues(attributes)
        result(directory.appendingPathComponent("pocketledger.db").path)
      } catch {
        result(FlutterError(code: "storage_unavailable", message: nil, details: nil))
      }
    }
  }

  private func confirmDeviceOwner(_ result: @escaping FlutterResult) {
    guard credentialContext == nil else {
      result(FlutterError(code: "in_progress", message: nil, details: nil))
      return
    }
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      let code = error?.code == LAError.Code.passcodeNotSet.rawValue
        ? "no_screen_lock" : "unavailable"
      result(FlutterError(code: code, message: nil, details: nil))
      return
    }
    credentialContext = context
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock PocketLedger") {
      [weak self] verified, _ in
      DispatchQueue.main.async {
        self?.credentialContext = nil
        result(verified)
      }
    }
  }
}
