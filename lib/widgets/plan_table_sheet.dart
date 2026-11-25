import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../models/table_plan.dart';
import '../theme/app_theme.dart';
import 'dw.dart';

/// "Plan a table": opened by "Find a table" under the coach's reply, in text
/// chat and in the voice conversation alike. The user types the area, an
/// optional cuisine and budget, and picks the date, time and party size; the
/// results are search links that open outside the app (OpenTable with the
/// party size, date and time; Google Maps; Apple Maps where it exists).
///
/// Honest by design: DateWise cannot see availability or book (no partner
/// API, accounts or paid services), so it never shows a table, a hold or a
/// confirmation. The partner's own page shows live tables and the user books
/// there. Only what the user typed here goes into the links, only on tap.
Future<void> showPlanTableSheet(BuildContext context) {
  return showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const PlanTableSheet());
}

class PlanTableSheet extends StatefulWidget {
  /// The pickers' frame. Text scaling is capped at [pickerMaxTextScale]: Material's date and time dialogs cut day
  /// numbers and the dial apart at 2.0 (the sheet itself keeps the user's full size). When the language writes times
  /// in 24-hour form, the picker reads typed times that way too (otherwise Spanish 20:00 is refused and 9:15 becomes 21:15).
  static MediaQueryData pickerMediaQuery(MediaQueryData mq, TimeOfDayFormat languageFormat) => mq.copyWith(
        textScaler: mq.textScaler.clamp(maxScaleFactor: pickerMaxTextScale),
        alwaysUse24HourFormat: mq.alwaysUse24HourFormat || hourFormat(of: languageFormat) != HourFormat.h,
      );

  static const double pickerMaxTextScale = 1.3;

  const PlanTableSheet({super.key});

  /// Opens [uri] outside the app. Tests replace it to record the launch.
  @visibleForTesting
  static Future<bool> Function(Uri uri) launch = (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  /// The clock for the default date and time. Tests replace it.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// Where Apple Maps exists: iPhone / iPad and a Mac (not the web or Android).
  static bool get appleMapsAvailable =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

  @override
  State<PlanTableSheet> createState() => _PlanTableSheetState();
}

class _PlanTableSheetState extends State<PlanTableSheet> {
  final _area = TextEditingController();
  final _cuisine = TextEditingController();
  late DateTime _date;
  late TimeOfDay _time;
  late final DateTime _today;
  int _budget = 0;
  int _party = TablePlan.defaultPartySize;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = PlanTableSheet.now();
    _today = DateTime(now.year, now.month, now.day);
    final (date, time) = TablePlan.defaultsFor(now);
    _date = date;
    _time = time;
  }

  @override
  void dispose() {
    _area.dispose();
    _cuisine.dispose();
    super.dispose();
  }

  TablePlan get _plan =>
      TablePlan(area: _area.text, cuisine: _cuisine.text, budget: _budget, date: _date, time: _time, partySize: _party);

  Widget _pickerFrame(BuildContext context, Widget? child) => MediaQuery(
        data: PlanTableSheet.pickerMediaQuery(MediaQuery.of(context), MaterialLocalizations.of(context).timeOfDayFormat()),
        child: child!,
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      builder: _pickerFrame,
      initialDate: _date,
      firstDate: _today,
      lastDate: DateTime(_today.year + 1, _today.month, _today.day),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time, builder: _pickerFrame);
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _open(Uri uri) async {
    setState(() => _error = null);
    final ok = await PlanTableSheet.launch(uri).catchError((_) => false);
    if (!ok && mounted) setState(() => _error = context.l10n.couldNotOpen(uri.host));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = MaterialLocalizations.of(context);
    final plan = _plan;
    return Padding(
      // Above the keyboard while typing the area or cuisine.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('plan-table'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(l.planTableTitle, style: AppText.name.copyWith(fontSize: 22)),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('plan-table-close'),
                    tooltip: m.closeButtonTooltip,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l.planTableHonest,
                key: const ValueKey('plan-table-honest'),
                style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              _Field(
                fieldKey: const ValueKey('plan-table-area'),
                controller: _area,
                label: l.planTableArea,
                hint: l.planTableAreaHint,
                icon: Icons.place_outlined,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 10),
              _Field(
                fieldKey: const ValueKey('plan-table-cuisine'),
                controller: _cuisine,
                label: l.planTableCuisine,
                hint: l.planTableCuisineHint,
                icon: Icons.restaurant_menu_outlined,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 14),
              Text(l.planTableBudget, style: AppText.label),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var level = 1; level <= 4; level++)
                    ChoiceChip(
                      key: ValueKey('plan-table-budget-$level'),
                      label: Text('\$' * level, semanticsLabel: l.planTableBudgetLevel('$level')),
                      selected: _budget == level,
                      selectedColor: AppColors.gold,
                      checkmarkColor: AppColors.goldInk,
                      labelStyle: TextStyle(color: _budget == level ? AppColors.goldInk : null),
                      // Tapping the selected level again clears the budget.
                      onSelected: (on) => setState(() => _budget = on ? level : 0),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _PickerButton(
                    key: const ValueKey('plan-table-date'),
                    icon: Icons.calendar_today_outlined,
                    label: l.planTableDate,
                    value: m.formatMediumDate(_date),
                    onTap: _pickDate,
                  ),
                  _PickerButton(
                    key: const ValueKey('plan-table-time'),
                    icon: Icons.schedule_rounded,
                    label: l.planTableTime,
                    value: m.formatTimeOfDay(_time, alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context)),
                    onTap: _pickTime,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _PartySize(value: _party, onChanged: (v) => setState(() => _party = v)),
              const SizedBox(height: 18),
              Text(l.planTableSearchOn, style: AppText.label),
              const SizedBox(height: 8),
              _SearchLink(
                key: const ValueKey('plan-table-opentable'),
                site: l.planTableOpenTable,
                icon: Icons.event_available_outlined,
                style: DwButtonStyle.gold,
                onTap: () => _open(plan.openTableUri),
              ),
              const SizedBox(height: 10),
              _SearchLink(
                key: const ValueKey('plan-table-google'),
                site: l.planTableGoogleMaps,
                icon: Icons.map_outlined,
                onTap: () => _open(plan.googleMapsUri(l)),
              ),
              if (PlanTableSheet.appleMapsAvailable) ...[
                const SizedBox(height: 10),
                _SearchLink(
                  key: const ValueKey('plan-table-apple'),
                  site: l.planTableAppleMaps,
                  icon: Icons.map_outlined,
                  onTap: () => _open(plan.appleMapsUri(l)),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      key: const ValueKey('plan-table-error'),
                      style: const TextStyle(fontSize: 14, color: AppColors.danger),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labeled one-line text field in the app's input style.
class _Field extends StatelessWidget {
  const _Field({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onChanged,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.line2),
      ),
      child: TextField(
        key: fieldKey,
        controller: controller,
        maxLength: TablePlan.maxTextLength,
        maxLines: 1,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onChanged(),
        style: const TextStyle(color: AppColors.text, fontSize: 15, height: 1.3),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          counterText: '',
          icon: Icon(icon, size: 20, color: AppColors.faint),
          labelStyle: const TextStyle(color: AppColors.textMuted),
          floatingLabelStyle: const TextStyle(color: AppColors.gold),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

/// Date or time: a label, the current value, and a picker on tap.
class _PickerButton extends StatelessWidget {
  const _PickerButton({super.key, required this.icon, required this.label, required this.value, required this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: $value',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: const BorderSide(color: AppColors.line2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(label, style: AppText.small), Text(value, style: AppText.label)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Party size 1 to 20: minus / value / plus. VoiceOver reads it as one
/// adjustable control (swipe up / down) as well as the two buttons.
class _PartySize extends StatelessWidget {
  const _PartySize({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canLess = value > TablePlan.minPartySize;
    final canMore = value < TablePlan.maxPartySize;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(l.planTableParty, style: AppText.label),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey('plan-table-fewer'),
              tooltip: l.planTableFewer,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.remove_circle_outline_rounded),
              color: AppColors.gold,
              onPressed: canLess ? () => onChanged(value - 1) : null,
            ),
            Flexible(
              child: Semantics(
                label: l.planTableParty,
                value: l.planTablePeople(value),
                increasedValue: canMore ? l.planTablePeople(value + 1) : null,
                decreasedValue: canLess ? l.planTablePeople(value - 1) : null,
                onIncrease: canMore ? () => onChanged(value + 1) : null,
                onDecrease: canLess ? () => onChanged(value - 1) : null,
                excludeSemantics: true,
                // Wraps instead of overflowing at the largest text sizes.
                child: Text(
                  l.planTablePeople(value),
                  key: const ValueKey('plan-table-party'),
                  textAlign: TextAlign.center,
                  style: AppText.label,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('plan-table-more'),
              tooltip: l.planTableMore,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.add_circle_outline_rounded),
              color: AppColors.gold,
              onPressed: canMore ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// One search result: a link that opens [site] outside the app.
class _SearchLink extends StatelessWidget {
  const _SearchLink({
    super.key,
    required this.site,
    required this.icon,
    required this.onTap,
    this.style = DwButtonStyle.ghost,
  });

  final String site;
  final IconData icon;
  final VoidCallback onTap;
  final DwButtonStyle style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      link: true,
      label: context.l10n.planTableOpensOutside(site),
      onTap: onTap,
      excludeSemantics: true,
      child: DwButton(
        label: site,
        leading: icon,
        trailing: Icons.north_east_rounded,
        style: style,
        expand: true,
        height: 48,
        fontSize: 15,
        padding: 16,
        onPressed: onTap,
      ),
    );
  }
}
