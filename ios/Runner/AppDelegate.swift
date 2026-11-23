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
///   {"e":"start"}  when playback starts (audio time 0)
///   {"e":"marker", "start": utf16, "end": utf16, "t": seconds}  word markers (iOS 17+)
///   {"e":"synthesized"}  all levels sent
///   {"e":"done"} / {"e":"error", "message": ...}
/// Everything stays on the device. Dart falls back to flutter_tts if this
/// channel is missing or reports an error before "start".
final class SpeechAudioChannel: NSObject, FlutterStreamHandler {
  private static var shared: SpeechAudioChannel?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SpeechAudioChannel()
    let method = FlutterMethodChannel(name: "datewise/speech_audio", binaryMessenger: registrar.messenger())
    let events = FlutterEventChannel(name: "datewise/speech_audio/events", binaryMessenger: registrar.messenger())
    method.setMethodCallHandler { call, result in instance.handle(call, result: result) }
    events.setStreamHandler(instance)
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
  private var sampleRate: Double = 22050

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
      stopPlayback()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func speak(text: String, voiceId: String?, language: String, rate: Double, pitch: Double,
                     result: @escaping FlutterResult) {
    stopPlayback()
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
    } catch {
      result(FlutterError(code: "session", message: error.localizedDescription, details: nil))
      return
    }
    scheduledFrames = 0
    pendingBuffers = 0
    synthesisDone = false
    started = false
    let onBuffer: (AVAudioBuffer) -> Void = { [weak self] buffer in
      DispatchQueue.main.async { self?.received(buffer, gen: gen) }
    }
    if #available(iOS 17.0, *) {
      synthesizer.write(utterance, toBufferCallback: onBuffer, toMarkerCallback: { [weak self] markers in
        DispatchQueue.main.async { self?.received(markers, gen: gen) }
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
      send(["e": "synthesized"])
      if pendingBuffers == 0 { finish(gen: gen) }
      return
    }
    guard let playable = floatBuffer(pcm) else {
      fail("could not convert audio")
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
    sampleRate = playable.format.sampleRate
    send(["e": "levels", "t0": Double(scheduledFrames) / sampleRate, "hop": 0.01, "v": levels(playable)])
    scheduledFrames += AVAudioFramePosition(playable.frameLength)
    pendingBuffers += 1
    player.scheduleBuffer(playable) { [weak self] in
      DispatchQueue.main.async {
        guard let self = self, gen == self.generation else { return }
        self.pendingBuffers -= 1
        if self.synthesisDone && self.pendingBuffers == 0 { self.finish(gen: gen) }
      }
    }
    if !started {
      started = true
      player.play()
      send(["e": "start"])
    }
  }

  @available(iOS 16.0, *)
  private func received(_ markers: [AVSpeechSynthesisMarker], gen: Int) {
    guard gen == generation else { return }
    for m in markers where m.mark == .word {
      // byteSampleOffset is a sample position in the rendered audio.
      send(["e": "marker", "start": m.textRange.location, "end": m.textRange.location + m.textRange.length,
            "t": Double(m.byteSampleOffset) / sampleRate])
    }
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

  /// RMS of the first channel per 10 ms.
  private func levels(_ pcm: AVAudioPCMBuffer) -> [Double] {
    guard let data = pcm.floatChannelData?[0] else { return [] }
    let n = Int(pcm.frameLength)
    let hop = max(1, Int(pcm.format.sampleRate * 0.01))
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
    send(["e": "done"])
    player.stop()
    engine.stop()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func fail(_ message: String) {
    let wasStarted = started
    stopPlayback()
    send(["e": "error", "message": message, "started": wasStarted])
  }

  private func stopPlayback() {
    generation += 1
    if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    player.stop()
    if engine.isRunning { engine.stop() }
    pendingBuffers = 0
    started = false
  }
}
