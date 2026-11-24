import 'dart:async';

import 'package:flutter/painting.dart' show Color;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'bridge_protocol.dart';

/// Dart side of the bridge: send commands, listen to events. The controller
/// only ever talks to this interface, so tests use a fake and a later White
/// Glove (Capacitor) shell can provide its own implementation of the same page.
abstract class AvatarBridge {
  Stream<AvatarBridgeEvent> get events;
  Future<void> send(AvatarBridgeCommand command);
  Future<void> dispose();
}

/// The real bridge: a WKWebView / Android WebView running assets/avatar_pilot/index.html
/// (bundled in the app; nothing is loaded from a CDN at runtime, the vendor SDKs are
/// bundled in assets/avatar_pilot/vendor/, built by tool/avatar_pilot/build_vendor.sh).
///
/// Audio session (iOS): the page plays the vendor's audio in a <video playsinline>
/// element. It never calls getUserMedia (the face only receives our audio), so the
/// WebView never asks for the microphone and does not take the record category;
/// on-device speech recognition (speech_to_text) keeps the mic exactly as before.
/// The controller ends the live session while the app is in the background and
/// while the user records, so the two never compete for the audio session.
/// UNVERIFIED on a device: WKWebView playback while speech_to_text is idle, and
/// the route after STT ends. The pilot runbook measures it.
class WebViewAvatarBridge implements AvatarBridge {
  WebViewAvatarBridge() {
    // iOS: play the vendor's video inline and without a tap (the user already
    // chose to start the live face); everything else keeps the defaults.
    final PlatformWebViewControllerCreationParams params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(allowsInlineMediaPlayback: true, mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{})
        : const PlatformWebViewControllerCreationParams();
    controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel('DWAvatar', onMessageReceived: (m) {
        final e = decodeBridgeEvent(m.message);
        if (e != null && !_events.isClosed) _events.add(e);
      })
      ..setNavigationDelegate(NavigationDelegate(
        // The page is local; any navigation away from it is refused.
        onNavigationRequest: (r) => r.url.startsWith('file:') || r.url.startsWith('about:') ? NavigationDecision.navigate : NavigationDecision.prevent,
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) _events.add(ErrorEvent('webview', e.description));
        },
      ))
      ..loadFlutterAsset(pageAsset).catchError((Object e) {
        _events.add(ErrorEvent('webview', '$e'));
      });
  }

  static const pageAsset = 'assets/avatar_pilot/index.html';
  late final WebViewController controller;
  final _events = StreamController<AvatarBridgeEvent>.broadcast();

  @override
  Stream<AvatarBridgeEvent> get events => _events.stream;

  @override
  Future<void> send(AvatarBridgeCommand command) async {
    // jsonEncode output is passed as a JS string literal, then parsed in the page.
    final literal = _jsString(command.encode());
    try {
      await controller.runJavaScript('window.dwAvatar && window.dwAvatar.receive($literal);');
    } catch (e) {
      _events.add(ErrorEvent('webview', '$e'));
    }
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

String _jsString(String s) {
  final b = StringBuffer("'");
  for (final r in s.runes) {
    switch (r) {
      case 0x5C:
        b.write(r'\\');
      case 0x27:
        b.write(r"\'");
      case 0x0A:
        b.write(r'\n');
      case 0x0D:
        b.write(r'\r');
      case 0x2028:
        b.write(r' ');
      case 0x2029:
        b.write(r' ');
      default:
        b.writeCharCode(r);
    }
  }
  b.write("'");
  return b.toString();
}
