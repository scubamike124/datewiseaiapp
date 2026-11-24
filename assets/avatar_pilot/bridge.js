/*
 * DateWise hosted-avatar bridge (protocol v1; the Dart side is
 * lib/avatar/hosted/bridge_protocol.dart, which documents every message).
 *
 *   Dart -> JS : window.dwAvatar.receive(jsonString)
 *   JS -> Dart : DWAvatar.postMessage(jsonString)   (webview_flutter JavaScript channel)
 *
 * Vendor adapters register in window.DWAdapters[vendor] with
 *   start(cfg, host), speak(msg, host), interrupt(host), stop(host)
 * so a new vendor is one new file. This page never requests the microphone.
 */
(function () {
  'use strict';
  var V = 1;
  var adapters = (window.DWAdapters = window.DWAdapters || {});
  var current = null;
  var t0 = 0;
  var firstFrameSent = false;
  var stopped = true;

  function post(o) {
    o.v = V;
    try {
      window.DWAvatar.postMessage(JSON.stringify(o));
    } catch (e) {
      /* outside the app (a desktop browser): ignore */
    }
  }

  var host = {
    video: null,
    audio: null,
    emit: function (o) {
      if (o.type === 'firstFrame') {
        if (firstFrameSent) return;
        firstFrameSent = true;
        o.ms = Math.round(performance.now() - t0);
      }
      post(o);
    },
    now: function () { return performance.now(); },
  };

  function b64ToBytes(b64) {
    var bin = atob(b64);
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  // Linear resampler for PCM16 LE mono (our TTS rate -> the vendor's rate), carrying state across chunks.
  host.resample = function (bytes, fromRate, toRate) {
    if (fromRate === toRate) return bytes;
    var n = bytes.length >> 1;
    var src = new Int16Array(bytes.buffer, bytes.byteOffset, n);
    var ratio = fromRate / toRate;
    var outLen = Math.floor(n / ratio);
    var out = new Int16Array(outLen);
    for (var i = 0; i < outLen; i++) {
      var p = i * ratio;
      var i0 = Math.floor(p);
      var i1 = Math.min(i0 + 1, n - 1);
      var f = p - i0;
      out[i] = Math.round(src[i0] * (1 - f) + src[i1] * f);
    }
    return new Uint8Array(out.buffer);
  };
  host.b64ToBytes = b64ToBytes;

  function start(m) {
    var a = adapters[m.vendor];
    if (!a) return host.emit({ type: 'error', code: 'sdk_missing', message: 'no adapter ' + m.vendor });
    if (!stopped) stop();
    stopped = false;
    firstFrameSent = false;
    t0 = performance.now();
    host.video = document.getElementById('dw-video');
    host.audio = document.getElementById('dw-audio');
    current = a;
    host.emit({ type: 'state', state: 'idle' });
    try {
      a.start(m, host);
    } catch (e) {
      host.emit({ type: 'error', code: 'unknown', message: String(e && e.message || e) });
    }
  }

  function stop() {
    if (stopped) return;
    stopped = true;
    var a = current;
    current = null;
    try { a && a.stop(host); } catch (e) { /* ignore */ }
    host.emit({ type: 'ended', reason: 'stop' });
  }

  window.dwAvatar = {
    ready: function () {
      post({ type: 'ready' });
      // Report the page-side microphone permission for the pilot screen; never prompts.
      try {
        navigator.permissions.query({ name: 'microphone' }).then(
          function (r) { post({ type: 'mic', state: r.state }); },
          function () { post({ type: 'mic', state: 'unknown' }); });
      } catch (e) {
        post({ type: 'mic', state: 'unknown' });
      }
    },
    receive: function (raw) {
      var m;
      try { m = JSON.parse(raw); } catch (e) { return; }
      if (!m || m.v !== V) return;
      if (m.type === 'start') return start(m);
      if (m.type === 'stop') return stop();
      if (stopped || !current) return;
      try {
        if (m.type === 'speak') current.speak(m, host);
        else if (m.type === 'interrupt') current.interrupt(host);
      } catch (e) {
        host.emit({ type: 'error', code: 'media', message: String(e && e.message || e) });
      }
    },
  };

  // Network quality for the pilot screen and the poor-network fallback.
  setInterval(function () {
    if (stopped || !current || !current.stats) return;
    try {
      current.stats(host).then(function (s) { if (s) host.emit({ type: 'network', quality: s.poor ? 'poor' : 'good', rttMs: s.rttMs }); }, function () {});
    } catch (e) { /* ignore */ }
  }, 4000);
})();
