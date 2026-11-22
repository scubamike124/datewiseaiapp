import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'effects.dart';

/// Shared building blocks of the midnight theme: glass cards, gradient
/// buttons, gradient icon badges, eyebrow labels and the ambient glow
/// backdrop. Screens compose these instead of hand-rolling decorations.

/// A frosted, softly bordered card on the dark canvas.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.radius = AppRadius.lg,
    this.borderColor,
    this.borderWidth = 1,
    this.glowColor,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Overrides the hairline border (e.g. a selected state).
  final Color? borderColor;
  final double borderWidth;

  /// Adds a soft coloured shadow under the card.
  final Color? glowColor;

  /// A flat fill instead of the default glass gradient.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: glassDecoration(
        radius: radius,
        borderColor: borderColor,
        borderWidth: borderWidth,
        glowColor: glowColor,
        color: color,
      ),
      child: child,
    );
  }
}

/// The [GlassCard] decoration, for widgets that animate or clip their own box.
BoxDecoration glassDecoration({
  double radius = AppRadius.lg,
  Color? borderColor,
  double borderWidth = 1,
  Color? glowColor,
  Color? color,
}) {
  return BoxDecoration(
    color: color,
    gradient: color == null ? AppColors.glassGradient : null,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: borderColor ?? AppColors.glassBorder,
      width: borderWidth,
    ),
    boxShadow: [
      BoxShadow(
        color: (glowColor ?? Colors.black).withValues(
          alpha: glowColor == null ? 0.28 : 0.30,
        ),
        blurRadius: glowColor == null ? 24 : 36,
        offset: const Offset(0, 12),
      ),
    ],
  );
}

/// Primary call to action: a pill filled with the brand gradient, a soft
/// violet glow, hover lift and press feedback. White label (>= 5.7:1).
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.expand = false,
    this.gradient = AppColors.romanticGradient,
    this.foreground = Colors.white,
    this.dense = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;

  /// Fills the available width.
  final bool expand;
  final Gradient gradient;
  final Color foreground;

  /// Smaller padding (header and inline buttons).
  final bool dense;

  /// Shows a spinner instead of the label.
  final bool busy;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final theme = Theme.of(context);
    final label = Text(
      widget.label,
      textAlign: TextAlign.center,
      style: theme.textTheme.labelLarge?.copyWith(
        color: enabled ? widget.foreground : AppColors.textMuted,
        fontWeight: FontWeight.w700,
        fontSize: widget.dense ? 14 : 15,
      ),
    );
    final content =
        widget.busy
            ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: widget.foreground,
              ),
            )
            : Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: widget.foreground),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(child: label),
                if (widget.trailingIcon != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(widget.trailingIcon, size: 18, color: widget.foreground),
                ],
              ],
            );

    return Semantics(
      button: true,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: PressScale(
          child: AnimatedContainer(
            duration: AppMotion.fast,
            constraints: BoxConstraints(minHeight: widget.dense ? 44 : 52),
            decoration: BoxDecoration(
              gradient: enabled ? widget.gradient : null,
              color: enabled ? null : AppColors.raised,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow:
                  enabled
                      ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(
                            alpha: _hover ? 0.55 : 0.35,
                          ),
                          blurRadius: _hover ? 28 : 18,
                          offset: const Offset(0, 8),
                        ),
                      ]
                      : null,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: enabled ? widget.onPressed : null,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        widget.dense ? AppSpacing.md + 4 : AppSpacing.lg,
                    vertical: widget.dense ? 10 : 14,
                  ),
                  child: Center(
                    widthFactor: widget.expand ? null : 1,
                    heightFactor: 1,
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular (or rounded-square) brand-gradient badge holding an icon.
class GradientIcon extends StatelessWidget {
  const GradientIcon({
    super.key,
    required this.icon,
    this.size = 48,
    this.iconSize,
    this.circle = true,
    this.gradient = AppColors.romanticGradient,
    this.iconColor = Colors.white,
    this.glow = true,
  });

  final IconData icon;
  final double size;
  final double? iconSize;
  final bool circle;
  final Gradient gradient;
  final Color iconColor;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size * 0.3),
        boxShadow:
            glow
                ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: size * 0.5,
                    offset: Offset(0, size * 0.12),
                  ),
                ]
                : null,
      ),
      child: Icon(icon, color: iconColor, size: iconSize ?? size * 0.48),
    );
  }
}

/// Small uppercase label above a heading, in rose gold.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark canvas with two blurred colour glows (violet top-left, plum
/// bottom-right). Cheap: radial gradients, no blur filters. Fills its parent,
/// so use it for full-screen bodies (not inside a scroll view).
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child, this.intensity = 1});

  final Widget child;

  /// 0..1 strength of the glows.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.background),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.9, -1.0),
                    radius: 1.1,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.22 * intensity),
                      AppColors.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(1.0, 0.9),
                    radius: 1.0,
                    colors: [
                      const Color(
                        0xFFA0369F,
                      ).withValues(alpha: 0.16 * intensity),
                      const Color(0xFFA0369F).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
