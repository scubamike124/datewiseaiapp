import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/photo_analysis.dart';
import '../../theme/app_theme.dart';
import '../common/effects.dart';

/// Message composer with optional photo attachments (up to [_maxPhotos]). Calls
/// [onSend] with text and/or a list of base64-encoded images. The photo button
/// is shown only when [canSendPhoto] (Magnet tier); otherwise it surfaces an
/// upgrade hint.
class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.onSend,
    required this.enabled,
    required this.canSendPhoto,
    required this.analysisMode,
    required this.onAnalysisModeChanged,
    this.onPhotoBlocked,
    this.hintText = 'Ask DateWise AI anything…',
  });

  /// Placeholder in the message box (the active coach's, in their language).
  final String hintText;

  final void Function({String text, List<String>? images}) onSend;
  final bool enabled;
  final bool canSendPhoto;

  /// Current photo-analysis depth, and a callback to change it. The quick/deep
  /// toggle is only shown once a photo is attached.
  final AnalysisMode analysisMode;
  final ValueChanged<AnalysisMode> onAnalysisModeChanged;
  final VoidCallback? onPhotoBlocked;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  /// Max photos that can be attached and ranked at once.
  static const int _maxPhotos = 4;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();
  final List<String> _pendingImages = [];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (!widget.canSendPhoto) {
      widget.onPhotoBlocked?.call();
      return;
    }
    final remaining = _maxPhotos - _pendingImages.length;
    if (remaining <= 0) return;

    // Multi-select. Preprocess for free on-device: resize to ~768px and
    // recompress to JPEG (image_picker also transcodes HEIC and strips most
    // EXIF) — smaller upload, fewer vision tokens, cheaper and faster.
    final List<XFile> files = await _picker.pickMultiImage(
      maxWidth: 768,
      imageQuality: 80,
    );
    if (files.isEmpty) return;

    final encoded = <String>[];
    for (final f in files.take(remaining)) {
      encoded.add(base64Encode(await f.readAsBytes()));
    }
    if (!mounted) return;
    setState(() => _pendingImages.addAll(encoded));
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingImages.isEmpty) return;
    if (!widget.enabled) return;
    widget.onSend(
      text: text,
      images: _pendingImages.isEmpty ? null : List.of(_pendingImages),
    );
    _controller.clear();
    setState(() => _pendingImages.clear());
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        border: const Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pendingImages.isNotEmpty) ...[
                  _attachmentStrip(),
                  _modeToggle(),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      // Disabled only when at the photo cap; otherwise tapping
                      // either picks photos or (for non-Magnet) shows the upsell.
                      onPressed:
                          widget.enabled &&
                                  !(widget.canSendPhoto &&
                                      _pendingImages.length >= _maxPhotos)
                              ? _pickPhoto
                              : null,
                      tooltip:
                          !widget.canSendPhoto
                              ? 'Photo coach is a Magnet feature'
                              : _pendingImages.length >= _maxPhotos
                              ? 'Up to $_maxPhotos photos'
                              : 'Attach photos',
                      icon: Icon(
                        Icons.add_photo_alternate_outlined,
                        color:
                            widget.canSendPhoto
                                ? AppColors.primarySoft
                                : AppColors.textMuted,
                      ),
                    ),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 140),
                        child: CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.enter):
                                _send,
                          },
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            enabled: widget.enabled,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: widget.hintText,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              border: _pill(AppColors.cardBorder),
                              enabledBorder: _pill(AppColors.cardBorder),
                              disabledBorder: _pill(AppColors.cardBorder),
                              focusedBorder: _pill(AppColors.primaryLight, 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _SendButton(enabled: widget.enabled, onTap: _send),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static OutlineInputBorder _pill(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(26),
        borderSide: BorderSide(color: color, width: width),
      );

  /// Quick/Deep selector shown above the composer once a photo is attached.
  /// Quick = a fast, cheap pass; Deep = the full dimension breakdown.
  Widget _modeToggle() {
    Widget chip(AnalysisMode mode, String label, IconData icon) {
      final selected = widget.analysisMode == mode;
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: ChoiceChip(
          selected: selected,
          onSelected:
              widget.enabled ? (_) => widget.onAnalysisModeChanged(mode) : null,
          avatar: Icon(
            icon,
            size: 16,
            color: selected ? Colors.white : AppColors.textMuted,
          ),
          label: Text(label),
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.text,
            fontWeight: FontWeight.w600,
          ),
          selectedColor: AppColors.primaryDeep,
          backgroundColor: AppColors.raised,
          showCheckmark: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            side: const BorderSide(color: AppColors.cardBorder),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm, left: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            chip(AnalysisMode.quick, 'Quick', Icons.bolt_rounded),
            chip(AnalysisMode.deep, 'Deep', Icons.auto_awesome),
          ],
        ),
      ),
    );
  }

  /// Horizontal strip of attached-photo thumbnails, each with a remove button.
  Widget _attachmentStrip() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm, left: 44, top: 4),
        child: Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [for (var i = 0; i < _pendingImages.length; i++) _thumb(i)],
        ),
      ),
    );
  }

  Widget _thumb(int index) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Image.memory(
            base64Decode(_pendingImages[index]),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: IconButton(
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _pendingImages.removeAt(index)),
            icon: const CircleAvatar(
              radius: 10,
              backgroundColor: AppColors.raised,
              child: Icon(Icons.close, size: 12, color: AppColors.text),
            ),
          ),
        ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Send',
      child: PressScale(
        scale: 0.9,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: enabled ? AppColors.romanticGradient : null,
            color: enabled ? null : AppColors.raised,
            boxShadow:
                enabled
                    ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.45),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ]
                    : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: enabled ? Colors.white : AppColors.textMuted,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
