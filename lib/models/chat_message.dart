import 'batch_photo_analysis.dart';
import 'photo_analysis.dart';

enum MessageRole { user, coach }

/// How a coach reply ended. A reply that [failed] (the coach could not be
/// reached) or was [stopped] (the user left the chat mid-reply) is shown with
/// a "Try again" button and is never sent back to the model as history.
enum MessageStatus { ok, failed, stopped }

/// A single message within a coaching thread.
///
/// A message may carry one or more attached photos (base64, for the Magnet
/// photo coach) and/or a structured result rendered as a rich card — either a
/// single [PhotoAnalysis] or a multi-photo [BatchPhotoAnalysis] (rank & compare).
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.imageBase64,
    this.imageBase64s,
    this.analysis,
    this.batchAnalysis,
    this.isStreaming = false,
    this.isAnalyzing = false,
    this.status = MessageStatus.ok,
  });

  final String id;
  final MessageRole role;
  String text;
  final DateTime createdAt;

  /// Base64-encoded image bytes attached by the user (no data: prefix).
  /// Used for the single-photo path.
  final String? imageBase64;

  /// Multiple attached photos (rank & compare path). When set, takes precedence
  /// over [imageBase64] for rendering the user's bubble.
  final List<String>? imageBase64s;

  /// Structured single-photo result attached to a coach message.
  final PhotoAnalysis? analysis;

  /// Structured multi-photo (rank & compare) result attached to a coach message.
  final BatchPhotoAnalysis? batchAnalysis;

  /// True while the coach reply is still streaming in.
  bool isStreaming;

  /// True while a photo analysis is in progress — renders the animated
  /// "analyzing" skeleton card instead of text. Transient (never persisted).
  bool isAnalyzing;

  /// See [MessageStatus]. Persisted, so a failed reply can be retried after a
  /// restart.
  MessageStatus status;

  bool get isUser => role == MessageRole.user;

  /// A complete coach reply or a user message (what the model may see).
  bool get isComplete => !isStreaming && status == MessageStatus.ok;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'imageBase64': imageBase64,
    'imageBase64s': imageBase64s,
    'analysis': analysis?.toJson(),
    'batchAnalysis': batchAnalysis?.toJson(),
    if (status != MessageStatus.ok) 'status': status.name,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    role: MessageRole.values.firstWhere(
      (r) => r.name == json['role'],
      orElse: () => MessageRole.coach,
    ),
    text: json['text'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime(2026),
    imageBase64: json['imageBase64'] as String?,
    imageBase64s: (json['imageBase64s'] as List?)
        ?.map((e) => e as String)
        .toList(),
    analysis: json['analysis'] == null
        ? null
        : PhotoAnalysis.fromJson(json['analysis'] as Map<String, dynamic>),
    batchAnalysis: json['batchAnalysis'] == null
        ? null
        : BatchPhotoAnalysis.fromJson(
            json['batchAnalysis'] as Map<String, dynamic>),
    status: MessageStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => MessageStatus.ok,
    ),
  );
}
