import 'package:flutter/material.dart';

import '../models/coach.dart';
import '../theme/app_theme.dart';

/// Whether the user asked for less motion (iOS Reduce Motion, Android
/// "remove animations"). Animated glows and transitions then jump instead.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) == true ||
    WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.reduceMotion;

/// [d], or zero when [reduceMotion] is on.
Duration motion(BuildContext context, Duration d) => reduceMotion(context) ? Duration.zero : d;

/// Max content width, so phone layouts stay readable on iPad / desktop.
const double kContentMaxWidth = 560;

/// Centers [child] and caps its width at [kContentMaxWidth].
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = kContentMaxWidth});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Pill-shaped primary (gold) or secondary (rose / ghost) button, >= 44pt.
enum DwButtonStyle { gold, rose, ghost }

class DwButton extends StatelessWidget {
  const DwButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = DwButtonStyle.gold,
    this.trailing,
    this.leading,
    this.expand = false,
    this.height = 54,
    this.fontSize = 16,
    this.padding = 26,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final DwButtonStyle style;
  final IconData? trailing;
  final IconData? leading;
  final bool expand;
  final double height;
  final double fontSize;
  final double padding;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final (Gradient? gradient, Color fg, Color? bg, List<BoxShadow> shadow, Border? border) = switch (style) {
      DwButtonStyle.gold => (
          AppColors.goldGradient,
          AppColors.goldInk,
          null,
          const [BoxShadow(color: Color(0x2EDDB67F), blurRadius: 30, offset: Offset(0, 10))],
          null,
        ),
      DwButtonStyle.rose => (
          AppColors.roseGradient,
          AppColors.roseInk,
          null,
          const [BoxShadow(color: Color(0x59A23E5F), blurRadius: 22, offset: Offset(0, 8))],
          null,
        ),
      DwButtonStyle.ghost => (
          null,
          AppColors.text,
          const Color(0x0AFFFFFF),
          const <BoxShadow>[],
          Border.all(color: AppColors.line2),
        ),
    };
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(fontFamily: AppFonts.sans, fontSize: fontSize, fontWeight: FontWeight.w600, color: fg, height: 1.2),
    );
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
          )
        else if (leading != null)
          Padding(padding: const EdgeInsets.only(right: 8), child: Icon(leading, size: fontSize + 2, color: fg)),
        Flexible(child: text),
        if (trailing != null)
          Padding(padding: const EdgeInsets.only(left: 6), child: Icon(trailing, size: fontSize + 2, color: fg)),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled || busy ? 1 : 0.5,
        child: Container(
          constraints: BoxConstraints(minHeight: height),
          decoration: BoxDecoration(
            gradient: gradient,
            color: bg,
            border: border,
            borderRadius: BorderRadius.circular(999),
            boxShadow: enabled ? shadow : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: enabled ? onPressed : null,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
                child: Center(widthFactor: expand ? null : 1, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 44pt circular icon button with a hairline border.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 44,
    this.iconSize = 20,
    this.filled = false,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final double iconSize;
  final bool filled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: filled ? const Color(0x8C120C0E) : const Color(0x0DFFFFFF),
          shape: CircleBorder(side: BorderSide(color: filled ? AppColors.line2 : AppColors.line)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: iconSize, color: color ?? AppColors.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// The DateWise wordmark: gradient heart outline + "DateWise AI".
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'DateWise AI',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: size * 1.36, height: size * 1.27, child: CustomPaint(painter: _HeartPainter())),
          SizedBox(width: size * 0.45),
          Text('DateWise',
              // The wordmark is a logo: it keeps its size at any text size.
              textScaler: TextScaler.noScaling,
              style: TextStyle(fontFamily: AppFonts.serif, fontSize: size, fontWeight: FontWeight.w500, color: AppColors.text, height: 1)),
          Padding(
            padding: EdgeInsets.only(left: size * 0.27, bottom: size * 0.3),
            child: Text('AI',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                    fontFamily: AppFonts.sans, fontSize: size * 0.62, fontWeight: FontWeight.w600, letterSpacing: size * 0.1, color: AppColors.gold)),
          ),
        ],
      ),
    );
  }
}

class _HeartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 30, sy = size.height / 28;
    final p = Path()
      ..moveTo(15, 25.5)
      ..cubicTo(9, 21.4, 2.5, 16.6, 2.5, 9.6)
      ..cubicTo(2.5, 5.6, 5.5, 2.5, 9.3, 2.5)
      ..cubicTo(11.7, 2.5, 13.7, 3.7, 15, 5.6)
      ..cubicTo(16.3, 3.7, 18.3, 2.5, 20.7, 2.5)
      ..cubicTo(24.5, 2.5, 27.5, 5.6, 27.5, 9.6)
      ..cubicTo(27.5, 13.9, 25.1, 17.4, 21.9, 20.4)
      ..lineTo(23.8, 25.3)
      ..lineTo(18.4, 22.9)
      ..cubicTo(17.3, 23.8, 16.1, 24.7, 15, 25.5)
      ..close();
    canvas.scale(sx, sy);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..shader = AppColors.brandGradient.createShader(const Rect.fromLTWH(0, 0, 30, 28));
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A coach portrait from `assets/coaches/{id}-hero.jpg` or `-avatar.jpg`,
/// cover-cropped around the coach's focal point.
class CoachImage extends StatelessWidget {
  const CoachImage({super.key, required this.coach, this.avatar = false, this.semanticLabel});
  final Coach coach;
  final bool avatar;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      avatar ? coach.avatarAsset : coach.heroAsset,
      fit: BoxFit.cover,
      alignment: avatar ? coach.avatarFocus : coach.heroFocus,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Container(
        color: AppColors.surface2,
        alignment: Alignment.center,
        child: Text(coach.initial, style: AppText.name.copyWith(color: AppColors.gold)),
      ),
    );
  }
}

/// Round coach avatar with an optional soft "speaking" glow (TTS playing).
/// [semanticLabel] is the portrait's alt text; leave it null only where the
/// avatar sits next to text that already names the coach.
class CoachAvatar extends StatelessWidget {
  const CoachAvatar({super.key, required this.coach, this.size = 30, this.speaking = false, this.semanticLabel});
  final Coach coach;
  final double size;
  final bool speaking;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: motion(context, const Duration(milliseconds: 300)),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: speaking ? AppColors.gold : AppColors.line2, width: speaking ? 1.5 : 1),
        boxShadow: speaking ? const [BoxShadow(color: Color(0x66DDB67F), blurRadius: 14, spreadRadius: 1)] : const [],
      ),
      child: ClipOval(child: CoachImage(coach: coach, avatar: true, semanticLabel: semanticLabel)),
    );
  }
}

/// Small translucent pill used over photos ("Ava · AI coach · English").
class GlassChip extends StatelessWidget {
  const GlassChip({super.key, required this.label, this.dot = true});
  final String label;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x9E120C0E),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.line2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(label,
                style: const TextStyle(fontFamily: AppFonts.sans, fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)),
          ),
        ],
      ),
    );
  }
}

/// Rounded surface card with a hairline border.
class DwCard extends StatelessWidget {
  const DwCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.gradient});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? AppColors.surface : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}

/// Large serif page title with an optional eyebrow and subtitle (iOS-style
/// large title at the top of a tab).
class LargeTitle extends StatelessWidget {
  const LargeTitle({super.key, required this.title, this.eyebrow, this.subtitle, this.center = false});
  final String title;
  final String? eyebrow;
  final String? subtitle;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final align = center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        if (eyebrow != null) ...[
          Text(eyebrow!.toUpperCase(), style: AppText.eyebrow, textAlign: textAlign),
          const SizedBox(height: 8),
        ],
        Semantics(header: true, child: Text(title, style: AppText.title, textAlign: textAlign)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: AppText.body.copyWith(fontSize: 14.5, height: 1.45), textAlign: textAlign),
        ],
      ],
    );
  }
}

/// A gradient fading from transparent to the page background, for photos.
class FadeToBackground extends StatelessWidget {
  const FadeToBackground({super.key, this.stops = const [0.45, 1], this.from = 0, this.color = AppColors.background});
  final List<double> stops;
  final double from;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: from), color],
            stops: stops,
          ),
        ),
      );
}
