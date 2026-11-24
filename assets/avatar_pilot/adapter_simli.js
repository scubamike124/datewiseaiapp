/*
 * Simli adapter. Docs (checked 2026-11-24):
 *   https://docs.simli.com/api-reference/javascript   (SimliClient, sendAudioData, ClearBuffer, stop, events)
 *   https://docs.simli.com/api-reference/simli-webrtc (session token, audio format)
 * SimliClient(session_token, videoEl, audioEl, iceServers=null, logLevel) uses the default (LiveKit)
 * transport, so no ICE call (which would need the API key) is made in the page.
 * start() resolves when the first video frame is on screen. Audio in: PCM16 LE, 16 kHz, mono,
 * chunks of about 6000 bytes. ClearBuffer() drops audio not yet spoken.
 */
(function () {
  'use strict';
  var client = null;
  var speaking = false;
  var CHUNK = 6000;

  window.DWAdapters = window.DWAdapters || {};
  window.DWAdapters.simli = {
    start: function (cfg, host) {
      var S = window.DWVendor && window.DWVendor.simli;
      if (!S) return host.emit({ type: 'error', code: 'sdk_missing', message: 'simli sdk not bundled' });
      host.emit({ type: 'state', state: 'idle' });
      var c = new S.SimliClient(cfg.sessionToken, host.video, host.audio, null, S.LogLevel.ERROR);
      client = c;
      c.on('speaking', function () { speaking = true; host.emit({ type: 'state', state: 'speaking' }); });
      c.on('silent', function () { speaking = false; host.emit({ type: 'state', state: 'listening' }); });
      c.on('stop', function () { if (client === c) { client = null; host.emit({ type: 'ended', reason: 'remote' }); } });
      c.on('error', function (d) { host.emit({ type: 'error', code: 'session_refused', message: String(d).slice(0, 120) }); });
      c.start().then(
        function () { host.video.muted = false; host.emit({ type: 'firstFrame' }); host.emit({ type: 'state', state: 'listening' }); },
        function (e) { host.emit({ type: 'error', code: 'connect_timeout', message: String(e && e.message || e).slice(0, 120) }); });
    },
    speak: function (m, host) {
      if (!client || !m.audio) return; // Simli has no text input: the app sends audio
      var pcm = host.resample(host.b64ToBytes(m.audio), m.sampleRate || 24000, 16000);
      for (var i = 0; i < pcm.length; i += CHUNK) client.sendAudioData(pcm.subarray(i, Math.min(i + CHUNK, pcm.length)));
    },
    interrupt: function (host) {
      if (client) client.ClearBuffer();
      host.emit({ type: 'state', state: 'listening' });
    },
    stop: function () {
      var c = client;
      client = null;
      if (c) c.stop().catch(function () {});
    },
    stats: function () {
      // A coarse signal only: the SDK exposes no RTT. Poor = nothing playing for 15 s while we expect a frame.
      return Promise.resolve(null);
    },
  };
})();
