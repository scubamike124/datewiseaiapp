import 'package:flutter/material.dart';

import '../../models/coach.dart';
import '../../theme/app_theme.dart';
import '../common/effects.dart';

/// A coach's avatar: their initial on a gradient of their accent colour, with
/// an optional rose-gold ring when selected and a soft pulsing glow while the
/// coach is replying. No photos: the coaches are AI, and the avatar must not
/// suggest a real person.
class CoachAvatar extends StatefulWidget {
  const CoachAvatar({
    super.key,
    required this.coach,
    this.radius = 20,
    this.selected = false,
    this.glowing = false,
  });

  final Coach coach;
  final double radius;
  final bool selected;

  /// Pulses a glow in the coach's colour (e.g. while they are replying).
  final bool glowing;

  @override
  State<CoachAvatar> createState() => _CoachAvatarState();
}

class _CoachAvatarState extends State<CoachAvatar>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(CoachAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.glowing != widget.glowing) _sync();
  }

  // The controller only runs while glowing, so idle avatars cost nothing and
  // never keep a test's pumpAndSettle waiting.
  void _sync() {
    if (widget.glowing) {
      _pulse ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      );
      _pulse!.repeat(reverse: true);
    } else {
      _pulse?.stop();
      _pulse?.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coach = widget.coach;
    final radius = widget.radius;
    final size = radius * 2;
    final glowColor = Color.lerp(coach.color, AppColors.primary, 0.35)!;

    Widget avatar = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(widget.selected ? 2.5 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: widget.selected ? AppColors.accentGradient : null,
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(coach.color, Colors.white, 0.08)!,
              Color.lerp(coach.color, AppColors.background, 0.45)!,
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
            width: radius > 24 ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          coach.initial,
          // The initial is decoration; Semantics below names the coach.
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: radius * 0.9,
          ),
        ),
      ),
    );

    final pulse = _pulse;
    if (widget.glowing && pulse != null && !reduceMotion(context)) {
      avatar = AnimatedBuilder(
        animation: pulse,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(pulse.value);
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.35 + 0.35 * t),
                  blurRadius: radius * (0.6 + 0.9 * t),
                  spreadRadius: radius * 0.12 * t,
                ),
              ],
            ),
            child: child,
          );
        },
        child: avatar,
      );
    }

    return Semantics(
      label: '${coach.name}, ${coach.language.label}',
      image: true,
      child: ExcludeSemantics(child: avatar),
    );
  }
}
