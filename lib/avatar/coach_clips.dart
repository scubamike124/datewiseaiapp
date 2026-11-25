import '../models/coach.dart';

/// One approved prerecorded clip of a DateWise coach (PR #58, the owner-approved four-coach pilot).
///
/// The clips are bundled under `assets/coach_clips/`. Each already carries its own voice and, for the
/// Spanish coaches, the owner-approved 15% slowdown, so they play at normal speed.
class CoachClip {
  const CoachClip({
    required this.coachId,
    required this.asset,
    required this.seconds,
    required this.language,
    required this.labelKey,
  });

  final String coachId;
  final String asset;

  /// Duration of the clip in seconds, as published in the pilot's `lines.json`.
  final double seconds;

  final CoachLanguage language;

  /// Which localized label to show: `reference` or `opening` (Ava's two approved lines).
  final String labelKey;
}

/// The clip catalogue. Ava's ten-second clip is the approved reference for natural mouth closure.
class CoachClips {
  CoachClips._();

  static const ava = CoachClip(
    coachId: 'ava',
    asset: 'assets/coach_clips/ava.mp4',
    seconds: 10.0,
    language: CoachLanguage.en,
    labelKey: 'reference',
  );

  static const avaOpening = CoachClip(
    coachId: 'ava',
    asset: 'assets/coach_clips/ava_opening.mp4',
    seconds: 2.4,
    language: CoachLanguage.en,
    labelKey: 'opening',
  );

  static const ethan = CoachClip(
    coachId: 'ethan',
    asset: 'assets/coach_clips/ethan.mp4',
    seconds: 2.5,
    language: CoachLanguage.en,
    labelKey: 'reference',
  );

  static const diego = CoachClip(
    coachId: 'diego',
    asset: 'assets/coach_clips/diego.mp4',
    seconds: 2.1,
    language: CoachLanguage.es,
    labelKey: 'reference',
  );

  static const sofia = CoachClip(
    coachId: 'sofia',
    asset: 'assets/coach_clips/sofia.mp4',
    seconds: 2.2,
    language: CoachLanguage.es,
    labelKey: 'reference',
  );

  /// Shown while a clip loads, and when it cannot be played.
  static const posterAsset = 'assets/coach_clips/ava_poster.jpg';

  static const List<CoachClip> all = [ava, avaOpening, ethan, diego, sofia];

  /// Every clip for [coachId], the reference first.
  static List<CoachClip> forCoach(String coachId) => all.where((c) => c.coachId == coachId).toList();

  /// The reference clip for [coachId], or null for a coach without a pilot clip.
  static CoachClip? referenceFor(String coachId) {
    for (final c in all) {
      if (c.coachId == coachId && c.labelKey == 'reference') return c;
    }
    return null;
  }
}
