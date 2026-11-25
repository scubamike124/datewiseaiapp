import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DateWiseSpeechAudio") {
      SpeechAudioChannel.register(with: registrar)
    }
  }
}

/// Coach speech for the talking avatar (lib/avatar/speech_audio.dart).
///
/// Renders the utterance to PCM with AVSpeechSynthesizer.write (iOS 13+),
/// plays the buffers through AVAudioEngine, and streams to Dart:
///   {"e":"levels", "t0": seconds, "hop": 0.01, "v": [rms...]}  per buffer
///   {"e":"start", "latency": seconds}  playback started (audio time 0); latency = output latency
///   {"e":"marker", "start": utf16, "end": utf16, "t": seconds}  word markers (iOS 17+)
///   {"e":"synthesized"}  all levels sent
///   {"e":"done"} (also after an interruption, route loss, engine reset or backgrounding)
///   {"e":"error", "message": ..., "started": bool}  started=false: nothing was heard (Dart falls back)
/// Everything stays on the device.
final class SpeechAudioChannel: NSObject, FlutterStreamHandler {
  private static var shared: SpeechAudioChannel?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SpeechAudioChannel()
    let method = FlutterMethodChannel(name: "datewise/speech_audio", binaryMessenger: registrar.messenger())
    let events = FlutterEventChannel(name: "datewise/speech_audio/events", binaryMessenger: registrar.messenger())
    method.setMethodCallHandler { call, result in instance.handle(call, result: result) }
    events.setStreamHandler(instance)
    instance.observe()
    shared = instance
  }

  private var sink: FlutterEventSink?
  private let synthesizer = AVSpeechSynthesizer()
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private var connectedFormat: AVAudioFormat?
  private var converter: AVAudioConverter?
  private var generation = 0
  private var scheduledFrames: AVAudioFramePosition = 0
  private var pendingBuffers = 0
  private var synthesisDone = false
  private var started = false
  private var active = false  // an utterance is being synthesized or played
  private var sampleRate: Double = 0
  private var bytesPerFrame: Double = 0
  private var pendingMarkers: [(Int, Int, Int)] = []  // (start, end, byteSampleOffset)
  private var ownsSession = false  // this channel activated the audio session

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func send(_ event: [String: Any]) {
    sink?(event)
  }

  // MARK: interruptions

  private func observe() {
    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(onInterruption(_:)),
                   name: AVAudioSession.interruptionNotification, object: nil)
    nc.addObserver(self, selector: #selector(onRouteChange(_:)),
                   name: AVAudioSession.routeChangeNotification, object: nil)
    nc.addObserver(self, selector: #selector(onEngineChange(_:)),
                   name: .AVAudioEngineConfigurationChange, object: engine)
    nc.addObserver(self, selector: #selector(onBackground(_:)),
                   name: UIApplication.didEnterBackgroundNotification, object: nil)
  }

  @objc private func onInterruption(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
    DispatchQueue.main.async { self.interrupt("interruption") }
  }

  @objc private func onRouteChange(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
    // Headphones unplugged / Bluetooth gone: stop, as Apple's guidelines ask.
    if reason == .oldDeviceUnavailable {
      DispatchQueue.main.async { self.interrupt("route") }
    }
  }

  @objc private func onEngineChange(_ note: Notification) {
    DispatchQueue.main.async {
      // Activating the session for an utterance (and the microphone's
      // session before it) can change the hardware format, and this
      // notification arrives asynchronously. Before playback has started, or
      // once the engine runs again, it is stale: the next buffer (re)starts
      // the engine. Only an engine that stopped itself during playback ends
      // the utterance.
      guard self.started, !self.engine.isRunning else { return }
      self.interrupt("engine")
    }
  }

  @objc private func onBackground(_ note: Notification) {
    DispatchQueue.main.async { self.interrupt("background") }
  }

  /// Ends the current utterance after an interruption: Dart gets "done"
  /// (never an error, so it neither replays the reply nor turns this path
  /// off) and clears its speaking state.
  private func interrupt(_ reason: String) {
    guard active else { return }
    stopPlayback()
    deactivateSession()
    send(["e": "done", "interrupted": reason])
  }

  // MARK: channel

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "available":
      result(true)
    case "speak":
      guard let args = call.arguments as? [String: Any], let text = args["text"] as? String else {
        result(FlutterError(code: "args", message: "text missing", details: nil))
        return
      }
      speak(
        text: text,
        voiceId: args["voice"] as? String,
        language: args["language"] as? String ?? "en-US",
        rate: args["rate"] as? Double ?? 0.5,
        pitch: args["pitch"] as? Double ?? 1.0,
        result: result)
    case "stop":
      // An explicit stop: also release the session so other apps' audio is
      // no longer ducked.
      stopPlayback()
      deactivateSession()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func speak(text: String, voiceId: String?, language: String, rate: Double, pitch: Double,
                     result: @escaping FlutterResult) {
    stopPlayback()  // keeps the session active: the next utterance starts right away
    generation += 1
    let gen = generation
    let utterance = AVSpeechUtterance(string: text)
    if let id = voiceId, let voice = AVSpeechSynthesisVoice(identifier: id) {
      utterance.voice = voice
    } else {
      utterance.voice = AVSpeechSynthesisVoice(language: language)
    }
    utterance.rate = Float(rate)
    utterance.pitchMultiplier = Float(pitch)
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio,
                              options: [.mixWithOthers, .duckOthers, .allowBluetoothA2DP])
      try session.setActive(true)
      ownsSession = true
    } catch {
      result(FlutterError(code: "session", message: error.localizedDescription, details: nil))
      return
    }
    scheduledFrames = 0
    pendingBuffers = 0
    synthesisDone = false
    started = false
    active = true
    sampleRate = 0
    bytesPerFrame = 0
    pendingMarkers = []
    let onBuffer: (AVAudioBuffer) -> Void = { [weak self] buffer in
      DispatchQueue.main.async { self?.received(buffer, gen: gen) }
    }
    if #available(iOS 17.0, *) {
      synthesizer.write(utterance, toBufferCallback: onBuffer, toMarkerCallback: { [weak self] markers in
        let words = markers.filter { $0.mark == .word }
          .map { ($0.textRange.location, $0.textRange.location + $0.textRange.length, $0.byteSampleOffset) }
        DispatchQueue.main.async { self?.received(words, gen: gen) }
      })
    } else {
      synthesizer.write(utterance, toBufferCallback: onBuffer)
    }
    result(true)
  }

  private func received(_ buffer: AVAudioBuffer, gen: Int) {
    guard gen == generation, let pcm = buffer as? AVAudioPCMBuffer else { return }
    if pcm.frameLength == 0 {
      synthesisDone = true
      if scheduledFrames == 0 {
        // The synthesizer produced no audio at all (missing voice, empty
        // text after cleaning...): nothing will play, let Dart fall back.
        stopPlayback()
        deactivateSession()  // as in fail(): do not leave other apps' audio ducked
        send(["e": "error", "message": "no audio rendered", "started": false])
        return
      }
      send(["e": "synthesized"])
      if pendingBuffers == 0 { finish(gen: gen) }
      return
    }
    if bytesPerFrame == 0 {
      // Markers count bytes of the synthesizer's own format.
      bytesPerFrame = Double(pcm.format.streamDescription.pointee.mBytesPerFrame)
      sampleRate = pcm.format.sampleRate
      flushMarkers()
    }
    guard let playable = floatBuffer(pcm) else {
      fail("could not convert audio")
      return
    }
    if started && !engine.isRunning {
      // The engine stopped itself during playback (its notification is not
      // handled yet): restarting it here would leave the player stopped and
      // the rest of the reply silent.
      interrupt("engine")
      return
    }
    if connectedFormat == nil || connectedFormat! != playable.format {
      if engine.isRunning { engine.stop() }
      if connectedFormat == nil { engine.attach(player) } else { engine.disconnectNodeOutput(player) }
      engine.connect(player, to: engine.mainMixerNode, format: playable.format)
      connectedFormat = playable.format
    }
    if !engine.isRunning {
      do { try engine.start() } catch {
        fail(error.localizedDescription)
        return
      }
    }
    let rate = playable.format.sampleRate
    // The exact hop in seconds (220 frames at 22.05 kHz are 9.98 ms).
    let hop = max(1, Int(rate * 0.01))
    send(["e": "levels", "t0": Double(scheduledFrames) / rate, "hop": Double(hop) / rate,
          "v": levels(playable, hop: hop)])
    scheduledFrames += AVAudioFramePosition(playable.frameLength)
    pendingBuffers += 1
    // .dataPlayedBack: called when the samples have actually been heard, so
    // the tail is never cut and "done" is not early.
    player.scheduleBuffer(playable, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self = self, gen == self.generation else { return }
        self.pendingBuffers -= 1
        if self.synthesisDone && self.pendingBuffers == 0 { self.finish(gen: gen) }
      }
    }
    if started && !player.isPlaying {
      player.play()  // a format change above restarted the engine
    }
    if !started {
      started = true
      player.play()
      // What is played now is heard this much later (AirPods: ~0.15-0.25 s).
      let session = AVAudioSession.sharedInstance()
      send(["e": "start", "latency": session.outputLatency + session.ioBufferDuration])
    }
  }

  private func received(_ words: [(Int, Int, Int)], gen: Int) {
    guard gen == generation else { return }
    pendingMarkers.append(contentsOf: words)
    flushMarkers()
  }

  /// Sends the buffered word markers once the audio format (bytes per frame,
  /// sample rate) is known.
  private func flushMarkers() {
    guard bytesPerFrame > 0, sampleRate > 0 else { return }
    for (start, end, bytes) in pendingMarkers {
      send(["e": "marker", "start": start, "end": end, "t": Double(bytes) / bytesPerFrame / sampleRate])
    }
    pendingMarkers = []
  }

  /// The buffer as 32-bit float (what AVAudioPlayerNode plays everywhere).
  private func floatBuffer(_ pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    if pcm.format.commonFormat == .pcmFormatFloat32 { return pcm }
    guard let target = AVAudioFormat(standardFormatWithSampleRate: pcm.format.sampleRate,
                                     channels: pcm.format.channelCount) else { return nil }
    if converter == nil || converter!.inputFormat != pcm.format {
      converter = AVAudioConverter(from: pcm.format, to: target)
    }
    guard let conv = converter,
          let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: pcm.frameLength) else { return nil }
    do { try conv.convert(to: out, from: pcm) } catch { return nil }
    return out
  }

  /// RMS of the first channel per [hop] frames (about 10 ms).
  private func levels(_ pcm: AVAudioPCMBuffer, hop: Int) -> [Double] {
    guard let data = pcm.floatChannelData?[0] else { return [] }
    let n = Int(pcm.frameLength)
    var out: [Double] = []
    var i = 0
    while i < n {
      let end = min(n, i + hop)
      var sum: Float = 0
      for k in i..<end { sum += data[k] * data[k] }
      out.append(Double((sum / Float(end - i)).squareRoot()))
      i = end
    }
    return out
  }

  private func finish(gen: Int) {
    guard gen == generation else { return }
    active = false
    send(["e": "done"])
    player.stop()
    engine.stop()
    deactivateSession()
  }

  private func fail(_ message: String) {
    let wasStarted = started
    stopPlayback()
    deactivateSession()
    send(["e": "error", "message": message, "started": wasStarted])
  }

  /// Releases the audio session, only if this channel activated it (so a
  /// stop never deactivates a session that flutter_tts or speech
  /// recognition is using).
  private func deactivateSession() {
    guard ownsSession else { return }
    ownsSession = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func stopPlayback() {
    generation += 1
    active = false
    if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    player.stop()
    if engine.isRunning { engine.stop() }
    pendingBuffers = 0
    started = false
  }
}
