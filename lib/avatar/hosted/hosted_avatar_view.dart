import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../l10n/l10n.dart';
import 'avatar_bridge.dart';
import 'hosted_avatar_controller.dart';

/// The small widget the coach stage embeds (later; the conversation-screen
/// files are not touched by this branch):
///
///     HostedAvatarView(controller: c, coachName: coach.name, fallback: const TalkingAvatar(...))
///
/// It shows the live face while the session is connecting or live, and the
/// [fallback] (the existing frame avatar) in every other state, so the stage
/// never has a hole. It is a fixed-size box with no modal UI: reading and typing
/// are never blocked. The collapse button ends the live session; the expand
/// button (only after the user collapsed) starts it again. The session also
/// ends when the app goes to the background.
class HostedAvatarView extends StatefulWidget {
  const HostedAvatarView({
    super.key,
    required this.controller,
    required this.fallback,
    required this.coachName,
    this.webViewBuilder,
  });

  final HostedAvatarController controller;
  final Widget fallback;
  final String coachName;

  /// Tests inject a placeholder; by default the real bridge's WebView is shown.
  final WidgetBuilder? webViewBuilder;

  @override
  State<HostedAvatarView> createState() => _HostedAvatarViewState();
}

class _HostedAvatarViewState extends State<HostedAvatarView> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      widget.controller.onBackgrounded();
    }
  }

  Widget _web(BuildContext context) {
    if (widget.webViewBuilder != null) return widget.webViewBuilder!(context);
    final bridge = widget.controller.bridge;
    if (bridge is WebViewAvatarBridge) return WebViewWidget(controller: bridge.controller);
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        if (!c.showsLiveFace) {
          final collapsed = c.fallbackReason == FallbackReason.collapsed;
          return Stack(children: [
            Positioned.fill(child: widget.fallback),
            if (collapsed)
              Positioned(
                top: 4,
                right: 4,
                child: _RoundButton(
                  key: const ValueKey('hosted-avatar-expand'),
                  icon: Icons.videocam_outlined,
                  label: l.avatarExpand,
                  onTap: c.start,
                ),
              ),
          ]);
        }
        return Stack(children: [
          Positioned.fill(child: widget.fallback), // behind: visible until the first frame
          // One stable WebView position, so the platform view is never rebuilt between
          // connecting and live: it runs (hidden) while connecting, shown from the first frame.
          Positioned.fill(
            key: const ValueKey('hosted-avatar-web'),
            child: Opacity(
              opacity: c.isLive ? 1 : 0,
              child: Semantics(
                label: c.isLive ? l.avatarLiveSemantics(widget.coachName) : null,
                image: c.isLive,
                child: ExcludeSemantics(child: _web(context)),
              ),
            ),
          ),
          if (!c.isLive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              child: Semantics(
                liveRegion: true,
                label: l.avatarConnecting,
                child: Center(child: Text(l.avatarConnecting, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70))),
              ),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: _RoundButton(
              key: const ValueKey('hosted-avatar-collapse'),
              icon: Icons.videocam_off_outlined,
              label: l.avatarCollapse,
              onTap: c.collapse,
            ),
          ),
        ]);
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: Tooltip(
            message: label,
            child: InkResponse(
              onTap: onTap,
              radius: 28,
              child: Container(
                width: 44, // iOS minimum tap target
                height: 44,
                decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
      );
}
