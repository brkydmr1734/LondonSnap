import Flutter
import UIKit
import AudioToolbox

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var ringtoneChannel: FlutterMethodChannel?

  // AudioToolbox system sound — immune to AVAudioSession changes from WebRTC
  private var systemSoundID: SystemSoundID = 0
  private var isRinging: Bool = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RingtonePlugin") {
      ringtoneChannel = FlutterMethodChannel(
        name: "com.londonsnaps.ringtone",
        binaryMessenger: registrar.messenger()
      )
      ringtoneChannel?.setMethodCallHandler { [weak self] call, result in
        self?.handleRingtone(call: call, result: result)
      }
      NSLog("[Ringtone-iOS] MethodChannel registered via AudioToolbox engine")
    } else {
      NSLog("[Ringtone-iOS] ERROR: Could not get registrar for RingtonePlugin")
    }
  }

  // MARK: - MethodChannel Handler

  private func handleRingtone(call: FlutterMethodCall, result: @escaping FlutterResult) {
    NSLog("[Ringtone-iOS] method: %@", call.method)
    switch call.method {
    case "play":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "ARGS", message: "Missing path", details: nil))
        return
      }
      NSLog("[Ringtone-iOS] play: %@", path)
      playSystemSound(path: path, result: result)

    case "stop":
      stopSystemSound()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - AudioToolbox System Sound (immune to AVAudioSession / WebRTC)

  private func playSystemSound(path: String, result: @escaping FlutterResult) {
    stopSystemSound()

    guard FileManager.default.fileExists(atPath: path) else {
      NSLog("[Ringtone-iOS] ERROR: File not found: %@", path)
      result(FlutterError(code: "FILE", message: "Not found: \(path)", details: nil))
      return
    }

    let url = URL(fileURLWithPath: path) as CFURL
    let status = AudioServicesCreateSystemSoundID(url, &systemSoundID)

    guard status == kAudioServicesNoError else {
      NSLog("[Ringtone-iOS] ERROR: AudioServicesCreateSystemSoundID failed: %d", status)
      result(FlutterError(code: "CREATE", message: "SystemSound create failed: \(status)", details: nil))
      return
    }

    isRinging = true

    // Set up completion callback to loop the sound
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    AudioServicesAddSystemSoundCompletion(systemSoundID, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue, { (ssID, clientData) in
      guard let clientData = clientData else { return }
      let appDelegate = Unmanaged<AppDelegate>.fromOpaque(clientData).takeUnretainedValue()
      if appDelegate.isRinging {
        NSLog("[Ringtone-iOS] Loop: replaying system sound")
        AudioServicesPlayAlertSound(ssID)
      }
    }, selfPtr)

    // Play first time (AlertSound = sound + vibration, respects silent switch)
    AudioServicesPlayAlertSound(systemSoundID)
    NSLog("[Ringtone-iOS] System sound playing, ID=%d", systemSoundID)
    result(nil)
  }

  private func stopSystemSound() {
    guard isRinging || systemSoundID != 0 else { return }

    isRinging = false

    if systemSoundID != 0 {
      AudioServicesRemoveSystemSoundCompletion(systemSoundID)
      AudioServicesDisposeSystemSoundID(systemSoundID)
      NSLog("[Ringtone-iOS] System sound stopped, disposed ID=%d", systemSoundID)
      systemSoundID = 0
    }
  }
}
