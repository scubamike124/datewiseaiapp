import 'package:flutter/widgets.dart';

import 'avatar_flags.dart';
import 'hosted_avatar_controller.dart';
import 'hosted_avatar_view.dart';

enum AvatarEngineKind { frame, hosted }

/// What the coach stage talks to, whichever engine draws the face.
///
///  * [FrameAvatarEngine]: the existing on-device frame avatar (lib/avatar/*), unchanged.
///    It is the default and the emergency fallback. It is driven by the existing
///    VoiceService (system voice + lip-sync), so [speakReply] returns false: "speak it
///    the usual way".
///  * [HostedAvatarEngine]: the vendor's live face. [speakReply] feeds the reply's
///    text, as audio, to the vendor and returns true while the live face speaks it.
///
/// The stage contract (to wire in the conversation-screen branch):
///     if (!await engine.speakReply(replyText)) await voice.speak(replyText);
abstract class AvatarEngine {
  AvatarEngineKind get kind;
  Widget build(BuildContext context);
  Future<bool> speakReply(String text);
  Future<void> interrupt();
  Future<void> dispose();
}

class FrameAvatarEngine implements AvatarEngine {
  FrameAvatarEngine({required this.builder});

  /// Builds the existing frame avatar widget (the stage passes its own).
  final WidgetBuilder builder;
  @override
  AvatarEngineKind get kind => AvatarEngineKind.frame;
  @override
  Widget build(BuildContext context) => builder(context);
  @override
  Future<bool> speakReply(String text) async => false;
  @override
  Future<void> interrupt() async {}
  @override
  Future<void> dispose() async {}
}

class HostedAvatarEngine implements AvatarEngine {
  HostedAvatarEngine({required this.controller, required this.fallback, required this.coachName});
  final HostedAvatarController controller;
  final FrameAvatarEngine fallback;
  final String coachName;
  @override
  AvatarEngineKind get kind => AvatarEngineKind.hosted;
  @override
  Widget build(BuildContext context) =>
      HostedAvatarView(controller: controller, coachName: coachName, fallback: Builder(builder: fallback.build));
  @override
  Future<bool> speakReply(String text) => controller.speakReply(text);
  @override
  Future<void> interrupt() => controller.interrupt();
  @override
  Future<void> dispose() async => controller.dispose();
}

/// The engine for this build: the frame avatar unless the hosted flag is on (and
/// not killed remotely). With the flag off, [hosted] is never called, so no
/// controller, WebView or network object is created.
AvatarEngine selectAvatarEngine({
  required AvatarFlags flags,
  required FrameAvatarEngine frame,
  HostedAvatarEngine Function()? hosted,
}) {
  if (flags.hostedEnabled && hosted != null) return hosted();
  return frame;
}
