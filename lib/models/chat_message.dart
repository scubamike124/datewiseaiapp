enum MessageRole { user, coach }

/// How a coach reply ended. A reply that [failed] (the coach could not be
/// reached) or was [stopped] (the user left the chat mid-reply) is shown with
/// a "Try again" button and is never sent back to the model as history.
enum MessageStatus { ok, failed, stopped }

/// A single message within a coaching thread.
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.hadPhoto = false,
    this.isStreaming = false,
    this.status = MessageStatus.ok,
  });

  final String id;
  final MessageRole role;
  String text;
  final DateTime createdAt;

  /// The message was a photo (or a photo critique) saved by v1. v2 does not
  /// keep photos: the image data is dropped on load and the bubble shows a
  /// short "no longer available" note when there is no text.
  final bool hadPhoto;

  /// True while the coach reply is still streaming in.
  bool isStreaming;

  /// See [MessageStatus]. Persisted, so a failed reply can be retried after a
  /// restart.
  MessageStatus status;

  bool get isUser => role == MessageRole.user;

  /// A complete coach reply or a user message (what the model may see).
  bool get isComplete => !isStreaming && status == MessageStatus.ok;

  /// A v1 photo message with no text left to show.
  bool get isPhotoOnly => hadPhoto && text.trim().isEmpty;

  /// A reply saved while it was still streaming (the app was closed or
  /// crashed mid-reply) is stored, and reloads, as [MessageStatus.stopped]:
  /// it is shown as incomplete with "Try again" and never sent as history.
  Map<String, dynamic> toJson() {
    final saved = isStreaming && status == MessageStatus.ok ? MessageStatus.stopped : status;
    return {
      'id': id,
      'role': role.name,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      if (hadPhoto) 'hadPhoto': true,
      if (saved != MessageStatus.ok) 'status': saved.name,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        role: MessageRole.values.firstWhere(
          (r) => r.name == json['role'],
          orElse: () => MessageRole.coach,
        ),
        text: json['text'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime(2026),
        // v1 stored photos and photo critiques in the message; only the
        // fact that there was one is kept.
        hadPhoto: json['hadPhoto'] == true ||
            json['imageBase64'] != null ||
            (json['imageBase64s'] is List && (json['imageBase64s'] as List).isNotEmpty) ||
            json['analysis'] != null ||
            json['batchAnalysis'] != null,
        status: json['isStreaming'] == true
            ? MessageStatus.stopped
            : MessageStatus.values.firstWhere(
                (s) => s.name == json['status'],
                orElse: () => MessageStatus.ok,
              ),
      );
}
