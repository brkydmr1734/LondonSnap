import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioPlayer: AVAudioPlayer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register for remote notifications
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    // Setup ringtone MethodChannel
    let controller = window?.rootViewController as? FlutterViewController
    if let controller = controller {
      let channel = FlutterMethodChannel(
        name: "com.londonsnaps.ringtone",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleRingtone(call: call, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - Ringtone Playback via AVAudioPlayer

  private func handleRingtone(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "play":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "ARGS", message: "Missing path", details: nil))
        return
      }
      let loop = args["loop"] as? Bool ?? true
      let volume = args["volume"] as? Double ?? 1.0

      playAudio(path: path, loop: loop, volume: Float(volume), result: result)

    case "stop":
      stopAudio()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func playAudio(path: String, loop: Bool, volume: Float, result: @escaping FlutterResult) {
    stopAudio()

    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "FILE", message: "WAV file not found: \(path)", details: nil))
      return
    }

    do {
      // Configure audio session for playback through speaker
      // Use .playAndRecord with .defaultToSpeaker so it coexists with WebRTC
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
      )
      try session.setActive(true)

      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.volume = volume
      audioPlayer?.numberOfLoops = loop ? -1 : 0 // -1 = infinite loop
      audioPlayer?.prepareToPlay()

      // Force output to speaker
      try session.overrideOutputAudioPort(.speaker)

      audioPlayer?.play()
      NSLog("[Ringtone-iOS] Playing: \(path), loop=\(loop), volume=\(volume)")
      result(nil)
    } catch {
      NSLog("[Ringtone-iOS] Play error: \(error)")
      result(FlutterError(code: "PLAY", message: error.localizedDescription, details: nil))
    }
  }

  private func stopAudio() {
    audioPlayer?.stop()
    audioPlayer = nil
    NSLog("[Ringtone-iOS] Stopped")
  }
}
