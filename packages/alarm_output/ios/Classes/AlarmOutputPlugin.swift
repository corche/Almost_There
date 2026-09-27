import Flutter
import AVFoundation

public class AlarmOutputPlugin: NSObject, FlutterPlugin {
  private static var player: AVAudioPlayer?
  private static var routeObserver: NSObjectProtocol?
  private static var fadeTimer: Timer?
  private static var playbackOwner: String?
  private let registrar: FlutterPluginRegistrar

  init(registrar: FlutterPluginRegistrar) { self.registrar = registrar }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "almost_there/alarm_output", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AlarmOutputPlugin(registrar: registrar), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "stop" {
      let owner = (call.arguments as? [String: Any])?["owner"] as? String
      if owner == nil || owner == Self.playbackOwner { Self.stop() }
      result(nil); return
    }
    if call.method == "canFullScreen" { result(false); return }
    if call.method == "pickAudioFile" {
      result(FlutterError(code: "picker_unavailable", message: "Audio selection is currently available on Android.", details: nil)); return
    }
    guard call.method == "start", let args = call.arguments as? [String: Any] else { result(FlutterMethodNotImplemented); return }
    let asset = args["asset"] as? String
    let filePath = args["filePath"] as? String
    guard asset != nil || filePath != nil else {
      result(FlutterError(code: "missing_audio", message: "An asset or file path is required.", details: nil)); return
    }
    Self.stop()
    Self.playbackOwner = args["owner"] as? String
    do {
      let session = AVAudioSession.sharedInstance()
      let earphones = args["earphones"] as? Bool ?? false
      if earphones {
        try session.setCategory(.playback, mode: .default, options: [])
      } else {
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.overrideOutputAudioPort(.speaker)
      }
      try session.setActive(true)
      func correctRoute() -> Bool {
        let outputs = session.currentRoute.outputs
        return !outputs.isEmpty && outputs.allSatisfy { port in
          if !earphones { return port.portType == .builtInSpeaker }
          return [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio].contains(port.portType)
        }
      }
      guard correctRoute() else { result(false); return }
      let path: String
      if let filePath { path = filePath }
      else {
        let key = registrar.lookupKey(forAsset: asset!)
        guard let bundledPath = Bundle.main.path(forResource: key, ofType: nil) else {
          result(FlutterError(code: "missing_asset", message: asset, details: nil)); return
        }
        path = bundledPath
      }
      let output = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      output.numberOfLoops = -1
      output.volume = 0
      output.prepareToPlay()
      Self.player = output
      Self.routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
          object: session, queue: nil) { _ in
        // Mute synchronously when the operating system reports a route change.
        output.volume = 0
        output.stop()
        DispatchQueue.main.async { Self.stop() }
      }
      output.play()
      let gain = min(1, max(0, args["volume"] as? Double ?? 0.7))
      let duration = max(0, args["fadeSeconds"] as? Double ?? 10)
      output.setVolume(Float(gain), fadeDuration: duration)
      result(true)
    } catch {
      Self.stop()
      result(FlutterError(code: "audio_output", message: error.localizedDescription, details: nil))
    }
  }

  private static func stop() {
    playbackOwner = nil
    player?.volume = 0
    player?.stop()
    player = nil
    fadeTimer?.invalidate()
    fadeTimer = nil
    if let observer = routeObserver { NotificationCenter.default.removeObserver(observer) }
    routeObserver = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }
}
