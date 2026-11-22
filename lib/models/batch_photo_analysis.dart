import 'photo_analysis.dart' show PhotoVerdict;

/// One photo's result inside a multi-photo "rank & compare" analysis.
class RankedPhoto {
  const RankedPhoto({
    required this.imageIndex,
    required this.rank,
    required this.overallScore,
    required this.verdict,
    required this.headline,
    required this.why,
  });

  /// Index into the uploaded set (0-based) this result refers to.
  final int imageIndex;

  /// 1 = best photo in the set, 2 = next, …
  final int rank;
  final int overallScore; // 1-10
  final PhotoVerdict verdict;
  final String headline;

  /// One-line reason for the ranking/score.
  final String why;

  Map<String, dynamic> toJson() => {
        'imageIndex': imageIndex,
        'rank': rank,
        'overallScore': overallScore,
        'verdict': verdict.label,
        'headline': headline,
        'why': why,
      };

  factory RankedPhoto.fromJson(Map<String, dynamic> json) => RankedPhoto(
        imageIndex: (json['imageIndex'] as num?)?.toInt() ?? 0,
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        overallScore: (json['overallScore'] as num?)?.toInt() ?? 5,
        verdict: PhotoVerdict.fromId(json['verdict'] as String?),
        headline: json['headline'] as String? ?? '',
        why: json['why'] as String? ?? '',
      );
}

/// Result of analyzing 2-4 photos together: each photo scored, the set ranked
/// best→worst, plus an overall recommendation on which to lead with / drop.
class BatchPhotoAnalysis {
  const BatchPhotoAnalysis({
    required this.photos,
    required this.bestIndex,
    required this.recommendation,
    this.thumbnails = const [],
  });

  /// Per-photo results. Not guaranteed to be in rank order — sort by [rank].
  final List<RankedPhoto> photos;

  /// Image index of the top-ranked photo (the one to lead with).
  final int bestIndex;

  /// Overall coaching takeaway, e.g. "Lead with #2, drop #4."
  final String recommendation;

  /// The uploaded (already-resized) images, so the result card can show
  /// thumbnails. Carried client-side; not part of the backend response.
  final List<String> thumbnails;

  /// Photos sorted best→worst for display.
  List<RankedPhoto> get ranked =>
      [...photos]..sort((a, b) => a.rank.compareTo(b.rank));

  /// Returns a copy with [thumbnails] attached (the backend response has none;
  /// the client supplies the uploaded images for the result card).
  BatchPhotoAnalysis copyWithThumbnails(List<String> thumbs) =>
      BatchPhotoAnalysis(
        photos: photos,
        bestIndex: bestIndex,
        recommendation: recommendation,
        thumbnails: thumbs,
      );

  Map<String, dynamic> toJson() => {
        'photos': photos.map((p) => p.toJson()).toList(),
        'bestIndex': bestIndex,
        'recommendation': recommendation,
        'thumbnails': thumbnails,
      };

  factory BatchPhotoAnalysis.fromJson(Map<String, dynamic> json) =>
      BatchPhotoAnalysis(
        photos: (json['photos'] as List? ?? [])
            .map((p) => RankedPhoto.fromJson(p as Map<String, dynamic>))
            .toList(),
        bestIndex: (json['bestIndex'] as num?)?.toInt() ?? 0,
        recommendation: json['recommendation'] as String? ?? '',
        thumbnails: (json['thumbnails'] as List? ?? [])
            .map((t) => t as String)
            .toList(),
      );
}
