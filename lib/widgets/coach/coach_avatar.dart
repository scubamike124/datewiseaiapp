import 'package:flutter/material.dart';

import '../../models/coach.dart';

/// A coach's avatar: their initial on a gradient of their accent colour, with
/// an optional gold ring when selected. No photos: the coaches are AI, and the
/// avatar must not suggest a real person.
class CoachAvatar extends StatelessWidget {
  const CoachAvatar({super.key, required this.coach, this.radius = 20, this.selected = false});

  final Coach coach;
  final double radius;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    return Semantics(
      label: '${coach.name}, ${coach.language.label}',
      image: true,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(selected ? 2.5 : 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? const Color(0xFFE0A13A) : null,
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [coach.color, Color.lerp(coach.color, Colors.black, 0.35)!],
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            coach.initial,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.9),
          ),
        ),
      ),
    );
  }
}
