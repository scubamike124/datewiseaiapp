import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'coaches_screen.dart';
import 'home_screen.dart';
import 'progress_screen.dart';
import 'settings_screen.dart';

enum AppTab { home, coaches, chat, progress, you }

/// Which tab is showing, plus a one-shot request to open the chat (with a
/// starter prompt, or straight into voice mode).
class ShellController extends ChangeNotifier {
  ShellController({AppTab initial = AppTab.home}) : _tab = initial;

  AppTab _tab;
  AppTab get tab => _tab;

  String? _pendingPrompt;
  bool _pendingVoice = false;

  void go(AppTab tab) {
    if (_tab == tab) return;
    _tab = tab;
    notifyListeners();
  }

  /// Opens the Chat tab; [prompt] is sent once the chat is on screen.
  void openChat({String? prompt, bool voice = false}) {
    _pendingPrompt = prompt;
    _pendingVoice = voice;
    _tab = AppTab.chat;
    notifyListeners();
  }

  String? takePrompt() {
    final p = _pendingPrompt;
    _pendingPrompt = null;
    return p;
  }

  bool takeVoice() {
    final v = _pendingVoice;
    _pendingVoice = false;
    return v;
  }
}

/// The five-tab app: Home / Coaches / Chat / Progress / You.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, this.initialTab = AppTab.home});
  final AppTab initialTab;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ShellController(initial: initialTab),
      child: const _ShellBody(),
    );
  }
}

class _ShellBody extends StatelessWidget {
  const _ShellBody();

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: shell.tab.index,
        children: [
          const HomeScreen(),
          const CoachesScreen(),
          ChatScreen(active: shell.tab == AppTab.chat),
          const ProgressScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: DwTabBar(
        current: shell.tab,
        onSelect: shell.go,
      ),
    );
  }
}

/// iOS-style tab bar: dark translucent, gold active tab.
class DwTabBar extends StatelessWidget {
  const DwTabBar({super.key, required this.current, required this.onSelect});
  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  static const _items = [
    (AppTab.home, 'Home', Icons.home_outlined, Icons.home_rounded),
    (AppTab.coaches, 'Coaches', Icons.people_outline_rounded, Icons.people_rounded),
    (AppTab.chat, 'Chat', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
    (AppTab.progress, 'Progress', Icons.bar_chart_rounded, Icons.bar_chart_rounded),
    (AppTab.you, 'You', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Tab labels stay legible but capped, as iOS does in tab bars.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xD1120C0E), Color(0xF7120C0E)],
        ),
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 40, offset: Offset(0, -18))],
      ),
      padding: EdgeInsets.fromLTRB(6, 6, 6, bottom > 0 ? bottom : 10),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler),
        child: Row(
          children: [
            for (final (tab, label, icon, activeIcon) in _items)
              Expanded(
                child: _TabItem(
                  key: ValueKey('tab-${tab.name}'),
                  label: label,
                  icon: tab == current ? activeIcon : icon,
                  active: tab == current,
                  onTap: () => onSelect(tab),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({super.key, required this.label, required this.icon, required this.active, required this.onTap});
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.gold : AppColors.faint;
    return Semantics(
      selected: active,
      button: true,
      label: '$label tab',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: active ? const [BoxShadow(color: Color(0x4DDDB67F), blurRadius: 12)] : const [],
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: AppFonts.sans, fontSize: 11, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
