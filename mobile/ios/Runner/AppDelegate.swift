import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioPlayer: AVAudioPlayer?
  private var ringtoneChannel: FlutterMethodChannel?
  private var watchdogTimer: Timer?
  private var currentRingtonePath: String?
  private var currentVolume: Float = 1.0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register for remote notifications
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Register ringtone MethodChannel using the engine's plugin registry
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RingtonePlugin") {
      ringtoneChannel = FlutterMethodChannel(
        name: "com.londonsnaps.ringtone",
        binaryMessenger: registrar.messenger()
      )
      ringtoneChannel?.setMethodCallHandler { [weak self] call, result in
        self?.handleRingtone(call: call, result: result)
      }
      NSLog("[Ringtone-iOS] MethodChannel registered successfully")
    } else {
      NSLog("[Ringtone-iOS] ERROR: Could not get registrar for RingtonePlugin")
    }
  }

  // MARK: - Ringtone Playback via AVAudioPlayer

  private func handleRingtone(call: FlutterMethodCall, result: @escaping FlutterResult) {
    NSLog("[Ringtone-iOS] Received method call: %@", call.method)
    switch call.method {
    case "play":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        NSLog("[Ringtone-iOS] ERROR: Missing path argument")
        result(FlutterError(code: "ARGS", message: "Missing path", details: nil))
        return
      }
      let loop = args["loop"] as? Bool ?? true
      let volume = args["volume"] as? Double ?? 1.0
      NSLog("[Ringtone-iOS] play: path=%@, loop=%d, vol=%.1f", path, loop ? 1 : 0, volume)
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
      NSLog("[Ringtone-iOS] ERROR: File not found: %@", path)
      result(FlutterError(code: "FILE", message: "WAV not found: \(path)", details: nil))
      return
    }

    do {
      // Configure audio session - .playAndRecord coexists with WebRTC
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
      )
      try session.setActive(true)

      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.volume = volume
      audioPlayer?.numberOfLoops = loop ? -1 : 0
      audioPlayer?.prepareToPlay()

      // Force speaker output
      try session.overrideOutputAudioPort(.speaker)

      // Listen for audio session interruptions (e.g. getUserMedia reconfigures session)
      NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleAudioInterruption),
        name: AVAudioSession.interruptionNotification,
        object: nil
      )
      // Also listen for route changes (speaker override might get reset)
      NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleRouteChange),
        name: AVAudioSession.routeChangeNotification,
        object: nil
      )

      let success = audioPlayer?.play() ?? false
      NSLog("[Ringtone-iOS] play() returned: %d, isPlaying=%d", success ? 1 : 0, audioPlayer?.isPlaying ?? false ? 1 : 0)

      // Start watchdog: checks every 1s if player died unexpectedly and restarts it
      currentRingtonePath = path
      currentVolume = volume
      watchdogTimer?.invalidate()
      watchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
        self?.checkAndRestartIfNeeded()
      }

      result(nil)
    } catch {
      NSLog("[Ringtone-iOS] Play error: %@", error.localizedDescription)
      result(FlutterError(code: "PLAY", message: error.localizedDescription, details: nil))
    }
  }

  @objc private func handleAudioInterruption(_ notification: Notification) {
    guard let info = notification.userInfo,
          let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

    NSLog("[Ringtone-iOS] Audio interruption: %@", type == .began ? "began" : "ended")

    if type == .ended {
      // Interruption ended — resume playback
      if let player = audioPlayer, !player.isPlaying {
        do {
          let session = AVAudioSession.sharedInstance()
          try session.setActive(true)
          try session.overrideOutputAudioPort(.speaker)
          player.play()
          NSLog("[Ringtone-iOS] Resumed after interruption")
        } catch {
          NSLog("[Ringtone-iOS] Resume failed: %@", error.localizedDescription)
        }
      }
    }
  }

  @objc private func handleRouteChange(_ notification: Notification) {
    // Re-force speaker if route changed while ringtone is playing
    if let player = audioPlayer, player.isPlaying {
      do {
        try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
      } catch {
        NSLog("[Ringtone-iOS] Route change speaker override failed: %@", error.localizedDescription)
      }
    }
  }

  private func stopAudio() {
    watchdogTimer?.invalidate()
    watchdogTimer = nil
    currentRingtonePath = nil
    if audioPlayer != nil {
      NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
      NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
      audioPlayer?.stop()
      audioPlayer = nil
      NSLog("[Ringtone-iOS] Stopped")
    }
  }

  /// Watchdog: if the player was killed by an audio session change, restart it
  private func checkAndRestartIfNeeded() {
    guard let path = currentRingtonePath else { return }

    // If player exists and is playing, all good
    if let player = audioPlayer, player.isPlaying { return }

    NSLog("[Ringtone-iOS] Watchdog: player died, restarting...")

    let url = URL(fileURLWithPath: path)
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
      )
      try session.setActive(true)

      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.volume = currentVolume
      audioPlayer?.numberOfLoops = -1
      audioPlayer?.prepareToPlay()
      try session.overrideOutputAudioPort(.speaker)
      audioPlayer?.play()
      NSLog("[Ringtone-iOS] Watchdog: restarted successfully")
    } catch {
      NSLog("[Ringtone-iOS] Watchdog restart failed: %@", error.localizedDescription)
    }
  }
}
