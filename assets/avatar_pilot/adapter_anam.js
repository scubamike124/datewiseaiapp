/*
 * Anam adapter. Docs (checked 2026-11-24):
 *   https://anam.ai/docs/javascript-sdk/examples/custom-tts      (audio passthrough: createClient with
 *       disableInputAudio, streamToVideoElement, createAgentAudioInputStream, sendAudioChunk, endSequence)
 *   https://anam.ai/docs/javascript-sdk/reference/event-types    (VIDEO_PLAY_STARTED, CONNECTION_CLOSED, ...)
 *   https://anam.ai/docs/javascript-sdk/reference/interrupt-command (interruptPersona)
 * The session token was minted by the Worker with enableAudioPassthrough, so the avatar speaks our audio
 * (pcm_s16le, mono; 24 kHz is Anam's native rate). The microphone is disabled (disableInputAudio).
 * UNVERIFIED: text input (client.talk) on a passthrough persona; used by the pilot debug screen only.
 */
(function () {
  'use strict';
  var client = null;
  var stream = null;

  window.DWAdapters = window.DWAdapters || {};
  window.DWAdapters.anam = {
    start: function (cfg, host) {
      var A = window.DWVendor && window.DWVendor.anam;
      if (!A) return host.emit({ type: 'error', code: 'sdk_missing', message: 'anam sdk not bundled' });
      var c = A.createClient(cfg.sessionToken, { disableInputAudio: true });
      client = c;
      var rate = (cfg.audio && cfg.audio.sampleRate) || 24000;
      c.addListener(A.AnamEvent.VIDEO_PLAY_STARTED, function () { host.video.muted = false; host.emit({ type: 'firstFrame' }); host.emit({ type: 'state', state: 'listening' }); });
      c.addListener(A.AnamEvent.CONNECTION_CLOSED, function (reason) {
        if (client === c) { client = null; stream = null; host.emit({ type: 'ended', reason: 'remote' }); }
      });
      c.addListener(A.AnamEvent.MIC_PERMISSION_DENIED, function () { host.emit({ type: 'error', code: 'permission_denied', message: 'mic' }); });
      c.addListener(A.AnamEvent.MESSAGE_STREAM_EVENT_RECEIVED, function (e) {
        if (e && e.role === 'persona') host.emit({ type: 'state', state: 'speaking' });
      });
      c.streamToVideoElement(host.video.id).then(
        function () { stream = c.createAgentAudioInputStream({ encoding: 'pcm_s16le', sampleRate: rate, channels: 1 }); },
        function (e) { host.emit({ type: 'error', code: 'connect_timeout', message: String(e && e.message || e).slice(0, 120) }); });
    },
    speak: function (m, host) {
      if (!client) return;
      if (m.text) { client.talk(m.text).catch(function () {}); return; }
      if (!stream || !m.audio) return;
      var rate = 24000;
      stream.sendAudioChunk(host.resample(host.b64ToBytes(m.audio), m.sampleRate || 24000, rate));
      host.emit({ type: 'state', state: 'speaking' });
      if (m.last) stream.endSequence();
    },
    interrupt: function (host) {
      if (client) client.interruptPersona();
      if (stream) stream.endSequence();
      host.emit({ type: 'state', state: 'listening' });
    },
    stop: function () {
      var c = client;
      client = null;
      stream = null;
      if (c) c.stopStreaming().catch(function () {});
    },
  };
})();
