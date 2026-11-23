import 'package:flutter/material.dart';

import '../models/coach.dart';
import '../theme/app_theme.dart';
import 'dw.dart';
import '../l10n/l10n.dart';

/// Portrait card for one coach (Coaches tab and onboarding), per the mockup:
/// photo, text-only language pill, serif name, approved description, and a
/// rose "Chat with Ava →" button. [onPreview] (voice preview) is shown only
/// when on-device text-to-speech is available.
class CoachCard extends StatelessWidget {
  const CoachCard({
    super.key,
    required this.coach,
    required this.onChat,
    this.onPreview,
    this.selected = false,
    this.previewing = false,
  });

  final Coach coach;
  final VoidCallback onChat;
  final VoidCallback? onPreview;
  final bool selected;
  final bool previewing;

  /// Where the 120 pt strip (stacked cards, large text) and the low
  /// landscape photo sit on the portrait: on the eyes and the smile.
  static const stripAlignment = Alignment(0, -0.1);
  static const landscapeAlignment = Alignment(0, -0.4);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final compact = MediaQuery.textScalerOf(context).scale(1) > CoachGrid.stackAboveScale;
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    return Container(
      key: ValueKey('coach-card-${coach.id}'),
      decoration: BoxDecoration(
        color: AppColors.cardDeep,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: selected ? AppColors.gold : const Color(0x29FFDCE6), width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhotoBox(
            key: ValueKey('coach-photo-${coach.id}'),
            // When the cards stack (text scale above CoachGrid.stackAboveScale)
            // each card is full width, so a portrait-shaped photo would fill
            // the screen (344x413 pt on an iPhone SE): the photo becomes a
            // 120 pt strip on the face instead. Otherwise its height follows
            // the card's width: portrait on phones, square on iPad, and
            // shorter in phone landscape, where the screen is low. The head,
            // from the top of the hair to the smile, sits above the fade.
            compact: compact,
            heightPerWidth: isTabletLayout(context) ? 1.0 : (landscape ? 0.8 : 1.2),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Portrait: the card shows the photo from its top edge (the
                // hair with the margin above it, then the face; the fade starts
                // below the smile). The strip and the landscape photo are lower
                // than the head, so they center on the face.
                CoachImage(
                  coach: coach,
                  semanticLabel: l.coachPortrait(coach.name),
                  alignment: compact
                      ? CoachCard.stripAlignment
                      : (landscape && !isTabletLayout(context) ? CoachCard.landscapeAlignment : Alignment.topCenter),
                ),
                const FadeToBackground(stops: [0.72, 1], color: AppColors.cardDeep),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xEBFFF8F2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      // Each language in its own name ("English" / "Español"),
                      // whatever the UI language.
                      coach.language.label,
                      style: const TextStyle(fontFamily: AppFonts.sans, fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF2A1A1F)),
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Icon(Icons.check_circle_rounded, color: AppColors.gold, size: 22, semanticLabel: l.yourCoachBadge),
                  )
                else if (onPreview != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: CircleIconButton(
                      key: ValueKey('preview-${coach.id}'),
                      icon: previewing ? Icons.stop_rounded : Icons.volume_up_rounded,
                      tooltip: previewing ? l.stopPreview : l.hearCoach(coach.name),
                      onPressed: onPreview,
                      filled: true,
                      size: 44,
                      iconSize: 18,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(coach.name, style: AppText.name),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      l.coachDescription(coach),
                      key: ValueKey('desc-${coach.id}'),
                      style: const TextStyle(fontFamily: AppFonts.sans, fontSize: 12, height: 1.35, color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DwButton(
                    key: ValueKey('chat-${coach.id}'),
                    label: l.chatWith(coach.name),
                    trailing: Icons.arrow_forward_rounded,
                    fitLabel: true,
                    onPressed: onChat,
                    style: DwButtonStyle.rose,
                    expand: true,
                    height: 44,
                    fontSize: 12.5,
                    padding: 8,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The four coaches in a 2x2 grid, cards in a row sharing one height that
/// grows with Dynamic Type. [preferred] language goes first.
class CoachGrid extends StatelessWidget {
  const CoachGrid({
    super.key,
    required this.onChat,
    this.onPreview,
    this.selectedId,
    this.previewingId,
    this.preferred,
  });

  final void Function(Coach) onChat;
  final void Function(Coach)? onPreview;
  final String? selectedId;
  final String? previewingId;
  final CoachLanguage? preferred;

  /// Above this text scale the cards stack (as ProgressScreen's stat tiles do).
  static const double stackAboveScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final coaches = [...Coaches.all];
    if (preferred == CoachLanguage.es) {
      coaches.sort((a, b) => (a.language == CoachLanguage.es ? 0 : 1).compareTo(b.language == CoachLanguage.es ? 0 : 1));
    }
    Widget card(Coach c) => CoachCard(
          coach: c,
          onChat: () => onChat(c),
          onPreview: onPreview == null ? null : () => onPreview!(c),
          selected: c.id == selectedId,
          previewing: c.id == previewingId,
        );
    // At large text two cards side by side break words mid-way
    // ("autoconfian/za"), so they stack, one per row.
    if (MediaQuery.textScalerOf(context).scale(1) > stackAboveScale) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < coaches.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            // The card stretches its content to a given height (side by
            // side, the row's); alone it takes its own intrinsic height.
            IntrinsicHeight(child: card(coaches[i])),
          ],
        ],
      );
    }
    Widget row(Coach a, Coach b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: card(a)), const SizedBox(width: 10), Expanded(child: card(b))],
          ),
        );
    return Column(
      children: [
        row(coaches[0], coaches[1]),
        const SizedBox(height: 10),
        row(coaches[2], coaches[3]),
      ],
    );
  }
}


/// The card's photo area: [compact] is a fixed 120 pt strip (stacked cards,
/// large text); otherwise the height is [heightPerWidth] times the card's width.
/// AspectRatio (not LayoutBuilder) so the stacked cards' IntrinsicHeight
/// still works.
class _PhotoBox extends StatelessWidget {
  const _PhotoBox({super.key, required this.compact, required this.heightPerWidth, required this.child});
  final bool compact;
  final double heightPerWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      compact ? SizedBox(height: 120, child: child) : AspectRatio(aspectRatio: 1 / heightPerWidth, child: child);
}
