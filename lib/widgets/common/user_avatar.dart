import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Circular user avatar: shows the network profile picture when available,
/// otherwise a colored circle with the first letter of the email/name.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.avatarUrl,
    this.label,
    this.radius = 18,
    this.backgroundColor = AppColors.primary,
  });

  final String? avatarUrl;

  /// Email or name used to derive the fallback initial.
  final String? label;
  final double radius;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final hasImage = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    final initial =
        (label != null && label!.trim().isNotEmpty) ? label![0].toUpperCase() : '?';

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      foregroundImage: hasImage ? NetworkImage(avatarUrl!) : null,
      // Shown while the image loads or if it fails.
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.9,
        ),
      ),
    );
  }
}
