import Flutter
import UIKit
import AVFoundation
import AudioToolbox

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var ringtoneChannel: FlutterMethodChannel?

  // Brute-force ringtone: Timer recreates player + forces speaker every cycle
  private var ringtoneTimer: Timer?
  private var audioPlayer: AVAudioPlayer?
  private var ringtonePath: String?
  private var ringtoneVolume: Float = 1.0
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
      NSLog("[Ringtone] MethodChannel registered")
    } else {
      NSLog("[Ringtone] ERROR: registrar nil")
    }
  }

  // MARK: - MethodChannel

  private func handleRingtone(call: FlutterMethodCall, result: @escaping FlutterResult) {
    NSLog("[Ringtone] method: %@", call.method)
    switch call.method {
    case "play":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "ARGS", message: "Missing path", details: nil))
        return
      }
      let volume = Float(args["volume"] as? Double ?? 1.0)
      startRinging(path: path, volume: volume)
      result(nil)

    case "stop":
      stopRinging()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Brute-Force Ringtone Engine
  //
  // Strategy: A repeating Timer fires every N seconds.
  // Each tick:
  //   1. Kills the old AVAudioPlayer (if any)
  //   2. Reconfigures AVAudioSession (.playAndRecord + .mixWithOthers)
  //   3. Forces speaker output
  //   4. Creates a FRESH AVAudioPlayer and plays
  //   5. Triggers vibration
  //
  // This guarantees continuous playback because:
  //   - Even if WebRTC kills the player by reconfiguring the audio session,
  //     the next Timer tick creates a brand new player with forced speaker.
  //   - No reliance on interruption notifications, completion callbacks,
  //     or audio session observer patterns that WebRTC can silently bypass.

  private func startRinging(path: String, volume: Float) {
    stopRinging()

    guard FileManager.default.fileExists(atPath: path) else {
      NSLog("[Ringtone] ERROR: file not found: %@", path)
      return
    }

    ringtonePath = path
    ringtoneVolume = volume
    isRinging = true

    // Play immediately
    playOneCycle()

    // Then replay every 4.5 seconds (our WAV is ~5s: 2s ring + 3s silence)
    // Slightly less than WAV duration ensures continuous coverage
    ringtoneTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: true) { [weak self] _ in
      self?.playOneCycle()
    }

    NSLog("[Ringtone] Started ringing loop")
  }

  private func playOneCycle() {
    guard isRinging, let path = ringtonePath else { return }

    // Kill existing player
    audioPlayer?.stop()
    audioPlayer = nil

    do {
      // Reconfigure audio session every cycle (WebRTC may have changed it)
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .voiceChat,              // Match WebRTC's mode exactly
        options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
      )
      try session.setActive(true)
      try session.overrideOutputAudioPort(.speaker)

      // Create fresh player
      let url = URL(fileURLWithPath: path)
      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.volume = ringtoneVolume
      audioPlayer?.numberOfLoops = 0  // Single play (Timer handles looping)
      audioPlayer?.prepareToPlay()
      audioPlayer?.play()

      // Vibrate
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

      NSLog("[Ringtone] Cycle played, isPlaying=%d", audioPlayer?.isPlaying == true ? 1 : 0)
    } catch {
      NSLog("[Ringtone] Cycle play error: %@", error.localizedDescription)
      // Still vibrate even if audio fails
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
  }

  private func stopRinging() {
    isRinging = false
    ringtoneTimer?.invalidate()
    ringtoneTimer = nil
    ringtonePath = nil
    audioPlayer?.stop()
    audioPlayer = nil
    NSLog("[Ringtone] Stopped")
  }
}
