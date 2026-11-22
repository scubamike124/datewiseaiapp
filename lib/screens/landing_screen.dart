import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_flags.dart';
import '../app_links.dart';
import '../models/tier.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common/brand_mark.dart';
import '../widgets/common/effects.dart';
import '../widgets/common/premium.dart';
import '../widgets/common/user_avatar.dart';
import '../widgets/landing/pricing_card.dart';
import 'account_screen.dart';
import 'admin_users_screen.dart';
import 'auth_screen.dart';
import 'chat_screen.dart';
import 'onboarding_screen.dart';

/// Responsive breakpoints used across the landing page.
class Breakpoints {
  Breakpoints._();
  static const double mobile = 600;
  static const double tablet = 900;

  static bool isMobile(BuildContext c) => MediaQuery.sizeOf(c).width < mobile;
  static bool isDesktop(BuildContext c) => MediaQuery.sizeOf(c).width >= tablet;
}

/// Landing page & conversion funnel (PRD section 5.1): hero, feature
/// highlights, pricing comparison, testimonials, final CTA, and footer.
/// Fully responsive with hover effects and scroll-reveal animations.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final GlobalKey _howKey = GlobalKey();
  final GlobalKey _pricingKey = GlobalKey();
  final GlobalKey _storiesKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Enters the app after a tier is chosen: first-timers go through the profile
  /// questionnaire; returning users (with a saved profile) go straight to chat.
  void _enterApp() {
    final state = context.read<AppState>();
    if (!state.hasProfile) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
    } else {
      state.ensureStarterThread();
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ChatScreen()));
    }
  }

  /// Enter coaching. Uses the user's saved tier if they have one, otherwise
  /// starts them on the recommended Flame plan. The unambiguous
  /// "get me into the app" action behind the hero's primary button.
  Future<void> _startCoaching() async {
    final state = context.read<AppState>();
    final tier = state.tier ?? SubscriptionTier.flame;
    await state.selectTier(tier);
    if (!mounted) return;
    _enterApp();
  }

  /// Pick a specific tier from the pricing cards / final CTA, then continue.
  /// When accounts are enabled, subscribing requires signing up first.
  Future<void> _selectTier(SubscriptionTier tier) async {
    final ok = await _requireAuth(
      reason: 'Create an account to subscribe to ${TierInfo.of(tier).name}.',
    );
    if (!ok || !mounted) return;
    await context.read<AppState>().selectTier(tier);
    if (!mounted) return;
    _enterApp();
  }

  /// Ensures the user is signed in when accounts are enabled. Returns true if
  /// the caller may proceed (already signed in, just authenticated, or accounts
  /// are switched off entirely).
  Future<bool> _requireAuth({String? reason}) async {
    final state = context.read<AppState>();
    if (!state.authEnabled || state.isSignedIn) return true;
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => AuthScreen(reason: reason)));
    return result == true;
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
      alignment: 0.05,
    );
  }

  void _scrollToPricing() => _scrollTo(_pricingKey);

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _logIn() async {
    final ok = await _requireAuth(
      reason: 'Log in to your DateWise AI account.',
    );
    if (!ok || !mounted) return;
    setState(() {}); // refresh the header to show the account menu
  }

  void _openAccount() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AccountScreen()));
  }

  void _openManageUsers() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AdminUsersScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hasTier = state.hasTier;

    // During the free launch the pricing section and all "Pricing" navigation
    // are hidden — the app is free, so there is nothing to price.
    final showPricing = !AppFlags.freeLaunch;

    // Sections are built lazily so RevealOnScroll fires as each scrolls in.
    final sections = <Widget>[
      _Hero(
        onStartCoaching: _startCoaching,
        onSeePlans: showPricing ? _scrollToPricing : null,
        hasTier: hasTier,
      ),
      const _FeatureStrip(),
      KeyedSubtree(key: _howKey, child: const _HowItWorks()),
      if (showPricing)
        KeyedSubtree(key: _pricingKey, child: _Pricing(onSelect: _selectTier)),
      KeyedSubtree(key: _storiesKey, child: const _Stories()),
      const _DownloadApp(),
      _FinalCta(onStart: _startCoaching),
      _Footer(
        onStart: _startCoaching,
        onSeePlans: showPricing ? _scrollToPricing : null,
        onStories: () => _scrollTo(_storiesKey),
        onHowItWorks: () => _scrollTo(_howKey),
      ),
    ];

    return Scaffold(
      body: ScrollConfiguration(
        // Smooth, momentum-style scrolling on web/desktop too.
        behavior: const _SmoothScrollBehavior(),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.background.withValues(alpha: 0.88),
              elevation: 0,
              scrolledUnderElevation: 0,
              shape: const Border(
                bottom: BorderSide(color: AppColors.cardBorder),
              ),
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              toolbarHeight: 66,
              title: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal:
                      Breakpoints.isMobile(context)
                          ? AppSpacing.md
                          : AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    // On narrow screens the wordmark takes the free space
                    // (and scales down with large text) so the actions fit.
                    if (Breakpoints.isDesktop(context))
                      const BrandMark()
                    else
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: BrandMark(),
                        ),
                      ),
                    // Centered nav links on desktop.
                    if (Breakpoints.isDesktop(context))
                      Expanded(
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _NavLink(label: 'Home', onTap: _scrollToTop),
                              _NavLink(
                                label: 'How it works',
                                onTap: () => _scrollTo(_howKey),
                              ),
                              if (showPricing)
                                _NavLink(
                                  label: 'Pricing',
                                  onTap: _scrollToPricing,
                                ),
                              _NavLink(
                                label: 'Stories',
                                onTap: () => _scrollTo(_storiesKey),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!Breakpoints.isDesktop(context))
                      PopupMenuButton<VoidCallback>(
                        icon: const Icon(
                          Icons.menu_rounded,
                          color: AppColors.text,
                        ),
                        tooltip: 'Menu',
                        onSelected: (cb) => cb(),
                        itemBuilder:
                            (context) => [
                              PopupMenuItem(
                                value: _scrollToTop,
                                child: const Text('Home'),
                              ),
                              PopupMenuItem(
                                value: () => _scrollTo(_howKey),
                                child: const Text('How it works'),
                              ),
                              if (showPricing)
                                PopupMenuItem(
                                  value: _scrollToPricing,
                                  child: const Text('Pricing'),
                                ),
                              PopupMenuItem(
                                value: () => _scrollTo(_storiesKey),
                                child: const Text('Stories'),
                              ),
                            ],
                      ),
                    const SizedBox(width: AppSpacing.sm),
                    hasTier
                        ? GradientButton(
                          dense: true,
                          onPressed: _enterApp,
                          label: 'Continue',
                        )
                        : GradientButton(
                          dense: true,
                          onPressed: _startCoaching,
                          label: 'Start',
                        ),
                    if (state.authEnabled) ...[
                      const SizedBox(width: AppSpacing.sm),
                      state.isSignedIn
                          ? _AccountMenu(
                            email: state.userEmail,
                            avatarUrl: state.avatarUrl,
                            isAdmin: state.isAdmin,
                            onAccount: _openAccount,
                            onManageUsers: _openManageUsers,
                            onSignOut: () => context.read<AppState>().signOut(),
                          )
                          : _NavLink(label: 'Log in', onTap: _logIn),
                    ],
                  ],
                ),
              ),
            ),
            // All sections are laid out (not lazily built) so every section
            // anchor is reachable for scroll-to-section navigation. The reveal
            // animation is driven by the shared scroll controller instead.
            SliverToBoxAdapter(
              child: Column(
                children: [
                  for (final section in sections)
                    RevealOnScroll(
                      controller: _scrollController,
                      child: section,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Enables smooth dragging via mouse on web/desktop without the default
/// scrollbar overlapping content.
class _SmoothScrollBehavior extends MaterialScrollBehavior {
  const _SmoothScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

/// A centred, max-width content section with responsive padding.
class _Section extends StatelessWidget {
  const _Section({required this.child, this.background, this.gradient});
  final Widget child;
  final Color? background;

  /// A full-bleed band behind the section (overrides [background]).
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final isMobile = Breakpoints.isMobile(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: gradient == null ? background : null,
        gradient: gradient,
      ),
      padding: EdgeInsets.symmetric(
        vertical: isMobile ? AppSpacing.xl : AppSpacing.xxl,
        horizontal: isMobile ? AppSpacing.md : AppSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: child,
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.onStartCoaching,
    this.onSeePlans,
    this.hasTier = false,
  });

  final VoidCallback onStartCoaching;

  /// Whether the visitor already has a session — switches the primary CTA from
  /// "Start coaching free" to "Continue".
  final bool hasTier;

  /// Scrolls to the pricing section. Null during the free launch (no pricing),
  /// which hides the "See pricing" button.
  final VoidCallback? onSeePlans;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < Breakpoints.mobile;
    final isWide = width >= Breakpoints.tablet;

    // Two-column (text + image) on desktop; stacked & centered below.
    final isRow = isWide;
    final cross = isRow ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = isRow ? TextAlign.left : TextAlign.center;

    final titleStyle = (isWide
            ? theme.textTheme.displayMedium
            : isMobile
            ? theme.textTheme.headlineMedium
            : theme.textTheme.displaySmall)
        ?.copyWith(fontWeight: FontWeight.w800, height: 1.05);

    final textColumn = Column(
      crossAxisAlignment: cross,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Eyebrow('Your AI dating coach', icon: Icons.auto_awesome),
        const SizedBox(height: AppSpacing.lg),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text:
                    isRow
                        ? 'Become the\nmost matched\n'
                        : 'Become the most\nmatched ',
              ),
              TextSpan(
                text: isRow ? 'version of you.' : 'version\nof you.',
                style: const TextStyle(color: AppColors.accent),
              ),
            ],
          ),
          textAlign: textAlign,
          style: titleStyle,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          "DateWise AI is a 24/7 dating coach in your pocket. Rewrite your bio, "
          "fix your photos, script the perfect opener — and finally feel like "
          "the kind of person you'd swipe right on.",
          textAlign: textAlign,
          style: (isMobile
                  ? theme.textTheme.bodyLarge
                  : theme.textTheme.titleMedium)
              ?.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w400,
              ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          alignment: isRow ? WrapAlignment.start : WrapAlignment.center,
          children: [
            GradientButton(
              onPressed: onStartCoaching,
              label: hasTier ? 'Continue' : 'Start coaching free',
              trailingIcon: Icons.arrow_forward_rounded,
            ),
            if (onSeePlans != null)
              HoverScale(
                child: OutlinedButton(
                  onPressed: onSeePlans,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('See pricing'),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        // Privacy reassurance — we collect no personal data.
        Text.rich(
          TextSpan(
            children: [
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const TextSpan(
                text:
                    'No sign-up. We never collect your personal data — '
                    'everything stays private on your device.',
              ),
            ],
          ),
          textAlign: textAlign,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
      ],
    );

    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.7, -0.9),
          radius: 1.3,
          colors: [Color(0xFF2E1650), AppColors.background],
        ),
      ),
      padding: EdgeInsets.symmetric(
        vertical:
            isWide
                ? 88
                : isMobile
                ? 40
                : 64,
        horizontal: isMobile ? AppSpacing.md : AppSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child:
              isRow
                  ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 5, child: textColumn),
                      const SizedBox(width: AppSpacing.xl),
                      const Expanded(flex: 6, child: _HeroImage()),
                    ],
                  )
                  : Column(
                    children: [
                      textColumn,
                      const SizedBox(height: AppSpacing.xl),
                      const _HeroImage(),
                    ],
                  ),
        ),
      ),
    );
  }
}

/// Hero visual: a warm portrait with a floating "match" badge for flair.
/// Loads from a bundled, optimized asset so it appears instantly (and offline).
class _HeroImage extends StatelessWidget {
  const _HeroImage();

  static const _imageAsset = 'images/hero.jpg';

  @override
  Widget build(BuildContext context) {
    final isPhone = Breakpoints.isMobile(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: AspectRatio(
          aspectRatio: 3 / 2, // matches the source image (1536×1024)
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.glassBorder),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 70,
                        offset: const Offset(0, 24),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          _imageAsset,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) => const _HeroImageFallback(),
                        ),
                        // A violet dusk wash ties the photo into the theme.
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x1A7C3AED), Color(0x9912081F)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Inset on phones so the floats never leave the screen.
              Positioned(
                left: isPhone ? 8 : -16,
                bottom: isPhone ? 12 : 28,
                child: _FloatingBadge(),
              ),
              Positioned(
                right: isPhone ? 8 : -12,
                top: 24,
                child: const _FloatingChip(label: '+34% matches'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroImageFallback extends StatelessWidget {
  const _HeroImageFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: AppColors.romanticGradient),
      child: Center(
        child: Icon(Icons.favorite_rounded, color: Colors.white, size: 64),
      ),
    );
  }
}

class _FloatingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GradientIcon(icon: Icons.auto_awesome, size: 38, glow: false),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'DateWise AI says',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              Text('“This one’s a KEEP ✨”', style: theme.textTheme.labelLarge),
            ],
          ),
        ],
      ),
    );
  }
}

class _FloatingChip extends StatelessWidget {
  const _FloatingChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        gradient: AppColors.romanticGradient,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_up_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.onDark = false,
  });
  final String eyebrow;
  final String title;
  final String? subtitle;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Every section sits on the dark canvas now; [onDark] is kept for callers.
    const titleColor = AppColors.text;
    const subColor = AppColors.textMuted;
    return Column(
      children: [
        // Rose-gold eyebrow label for an editorial, professional feel.
        Eyebrow(eyebrow),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(color: titleColor),
          textAlign: TextAlign.center,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle!,
            style: theme.textTheme.bodyLarge?.copyWith(color: subColor),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _FeatureStrip extends StatelessWidget {
  const _FeatureStrip();

  static const _features = [
    (
      Icons.edit_note_rounded,
      'Profile audits & bio rewrites',
      'Full rewrites and a brutally honest audit that stops the scroll.',
    ),
    (
      Icons.chat_bubble_outline_rounded,
      'Conversation coaching',
      'Openers, scripts, ghosting recovery — exact words to copy and paste.',
    ),
    (
      Icons.camera_alt_outlined,
      'AI photo coach',
      'Score every photo 1-10 with KEEP / RESHOOT / DELETE verdicts.',
    ),
    (
      Icons.insights_rounded,
      'Match-rate predictions',
      'See the predicted lift before you ever change a thing.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = Breakpoints.isMobile(context);
    return _Section(
      background: AppColors.background,
      child: Column(
        children: [
          const _SectionHeading(
            eyebrow: 'Features',
            title: 'Everything you need to date smarter',
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            alignment: WrapAlignment.center,
            children:
                _features.map((f) {
                  return SizedBox(
                    width: isMobile ? double.infinity : 250,
                    child: HoverScale(
                      scale: 1.02,
                      child: Container(
                        constraints: BoxConstraints(
                          minHeight: isMobile ? 0 : 220,
                        ),
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: glassDecoration(radius: AppRadius.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GradientIcon(icon: f.$1, size: 46, circle: false),
                            const SizedBox(height: AppSpacing.md),
                            Text(f.$2, style: theme.textTheme.titleMedium),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              f.$3,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = [
    (
      '1',
      'Pick your plan',
      'Spark, Flame, or Magnet — each unlocks deeper coaching.',
    ),
    (
      '2',
      'Chat with DateWise AI',
      'Threaded conversations for profile, dates, and photos.',
    ),
    ('3', 'Apply & match', 'Copy-paste fixes and watch your reply rate climb.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = Breakpoints.isMobile(context);
    // A deep plum band — a strong block of colour that breaks up the page.
    return _Section(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.plum, Color(0xFF241046), AppColors.surface],
      ),
      child: Column(
        children: [
          const _SectionHeading(
            eyebrow: 'Process',
            title: 'How it works',
            onDark: true,
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.lg,
            alignment: WrapAlignment.center,
            children:
                _steps.map((s) {
                  return SizedBox(
                    width: isMobile ? double.infinity : 260,
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: AppColors.accentGradient,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.3),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              s.$1,
                              style: const TextStyle(
                                color: AppColors.onAccent,
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          s.$2,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          s.$3,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }
}

class _Pricing extends StatelessWidget {
  const _Pricing({required this.onSelect});
  final ValueChanged<SubscriptionTier> onSelect;

  @override
  Widget build(BuildContext context) {
    return _Section(
      child: Column(
        children: [
          const _SectionHeading(
            eyebrow: 'Pricing',
            title: 'Choose your magnetism',
            subtitle: 'Weekly plans. Upgrade, downgrade, or cancel anytime.',
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            alignment: WrapAlignment.center,
            children:
                TierInfo.all
                    .map(
                      (info) => PricingCard(
                        info: info,
                        onSelect: () => onSelect(info.tier),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }
}

/// A success story: a quote attributed to a name/age and the tier that powered
/// the result.
class _Story {
  const _Story(this.quote, this.name, this.age, this.tier);
  final String quote;
  final String name;
  final int age;
  final SubscriptionTier tier;
}

class _Stories extends StatelessWidget {
  const _Stories();

  static const _stories = [
    _Story(
      'I went from 2 matches a week to 14. The bio rewrite alone was worth it.',
      'Maya',
      28,
      SubscriptionTier.spark,
    ),
    _Story(
      'The photo coach made me reshoot half my profile. My match rate doubled '
          'in 9 days.',
      'Jordan',
      34,
      SubscriptionTier.magnet,
    ),
    _Story(
      "Finally an opener that doesn't sound like a chatbot wrote it.",
      'Sara',
      31,
      SubscriptionTier.flame,
    ),
    _Story(
      'Three dates in one weekend. I had not had three dates in a whole year.',
      'Daniel',
      29,
      SubscriptionTier.flame,
    ),
    _Story(
      'DateWise AI flagged the one photo tanking my profile. Gone — instant '
          'difference.',
      'Priya',
      26,
      SubscriptionTier.magnet,
    ),
    _Story(
      'It rewrote my whole bio in 30 seconds and it actually sounded like me, '
          'just better.',
      'Alex',
      33,
      SubscriptionTier.spark,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Breakpoints.isMobile(context);
    return _Section(
      background: AppColors.background,
      child: Column(
        children: [
          const _SectionHeading(
            eyebrow: 'Stories',
            title: 'The before-and-afters speak for themselves.',
            subtitle: 'Real results from real daters, across every plan.',
          ),
          const SizedBox(height: AppSpacing.xl),
          const _StatsBand(),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            alignment: WrapAlignment.center,
            children:
                _stories
                    .map(
                      (s) => SizedBox(
                        width: isMobile ? double.infinity : 340,
                        child: _StoryCard(story: s),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }
}

class _StatsBand extends StatelessWidget {
  const _StatsBand();

  static const _stats = [
    ('+127%', 'avg. more matches'),
    ('10k+', 'profiles coached'),
    ('4.9★', 'average rating'),
    ('9 days', 'to first results'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.xxl,
      runSpacing: AppSpacing.lg,
      alignment: WrapAlignment.center,
      children:
          _stats.map((s) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback:
                      (bounds) => const LinearGradient(
                        colors: [AppColors.primarySoft, AppColors.accent],
                      ).createShader(bounds),
                  child: Text(
                    s.$1,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.$2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            );
          }).toList(),
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.story});
  final _Story story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tierInfo = TierInfo.of(story.tier);
    return HoverScale(
      scale: 1.02,
      child: Container(
        height: 248,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: glassDecoration(radius: AppRadius.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Row(
                  children: List.generate(
                    5,
                    (_) => const Icon(
                      Icons.star_rounded,
                      color: AppColors.accent,
                      size: 18,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.format_quote_rounded,
                  color: AppColors.accent.withValues(alpha: 0.5),
                  size: 28,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: Text(
                '“${story.quote}”',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                  child: Text(
                    story.name.substring(0, 1),
                    style: const TextStyle(
                      color: AppColors.primarySoft,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${story.name}, ${story.age}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                // The tier badge names a paid plan — hide it during free launch.
                if (!AppFlags.freeLaunch) _TierBadge(tierInfo: tierInfo),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.tierInfo});
  final TierInfo tierInfo;

  @override
  Widget build(BuildContext context) {
    // The tier colour lifted for legibility on the dark card.
    final color = Color.lerp(tierInfo.accentColor, Colors.white, 0.35)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        tierInfo.name,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Animated text nav link for the app bar.
class _NavLink extends StatefulWidget {
  const _NavLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              color: _hover ? AppColors.accent : AppColors.text,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

/// Header account control shown when the user is signed in: a circular avatar
/// that opens a menu with their email and a sign-out action.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu({
    required this.email,
    required this.avatarUrl,
    required this.isAdmin,
    required this.onAccount,
    required this.onManageUsers,
    required this.onSignOut,
  });
  final String? email;
  final String? avatarUrl;
  final bool isAdmin;
  final VoidCallback onAccount;
  final VoidCallback onManageUsers;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      onSelected: (v) {
        switch (v) {
          case 'account':
            onAccount();
          case 'users':
            onManageUsers();
          case 'signout':
            onSignOut();
        }
      },
      itemBuilder:
          (context) => [
            if (email != null)
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  email!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            const PopupMenuItem<String>(
              value: 'account',
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 18, color: AppColors.text),
                  SizedBox(width: AppSpacing.sm),
                  Text('Account'),
                ],
              ),
            ),
            if (isAdmin)
              const PopupMenuItem<String>(
                value: 'users',
                child: Row(
                  children: [
                    Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 18,
                      color: AppColors.primarySoft,
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Text('Manage users'),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: 'signout',
              child: Row(
                children: [
                  Icon(Icons.logout, size: 18, color: AppColors.text),
                  SizedBox(width: AppSpacing.sm),
                  Text('Log out'),
                ],
              ),
            ),
          ],
      child: HoverScale(
        child: UserAvatar(avatarUrl: avatarUrl, label: email, radius: 18),
      ),
    );
  }
}

/// "Get the app" section — App Store / Google Play buttons that surface a
/// friendly "coming soon" dialog (the mobile apps are in development).
class _DownloadApp extends StatelessWidget {
  const _DownloadApp();

  void _showComingSoon(BuildContext context, String platform) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            title: Row(
              children: [
                const GradientIcon(
                  icon: Icons.rocket_launch_rounded,
                  size: 36,
                  circle: false,
                ),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(child: Text('Coming soon!')),
              ],
            ),
            content: Text(
              'Our $platform app is under active development and will release '
              'soon. 🚧\n\nIn the meantime, DateWise AI works beautifully right '
              'here in your browser — no download needed.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Section(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.background, AppColors.surface],
      ),
      child: Column(
        children: [
          const _SectionHeading(
            eyebrow: 'Mobile apps',
            title: 'Take DateWise AI everywhere',
            subtitle:
                'Native Android & iOS apps are on the way. '
                'Be the first to coach on the go.',
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            alignment: WrapAlignment.center,
            children: [
              _StoreButton(
                icon: Icons.apple,
                topLine: 'Download on the',
                bottomLine: 'App Store',
                onTap: () => _showComingSoon(context, 'iOS'),
              ),
              _StoreButton(
                icon: Icons.android,
                topLine: 'Get it on',
                bottomLine: 'Google Play',
                onTap: () => _showComingSoon(context, 'Android'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Available on the web right now — apps launching soon.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StoreButton extends StatelessWidget {
  const _StoreButton({
    required this.icon,
    required this.topLine,
    required this.bottomLine,
    required this.onTap,
  });
  final IconData icon;
  final String topLine;
  final String bottomLine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverScale(
      child: Material(
        color: AppColors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            width: 200,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 30),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      topLine,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      bottomLine,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FinalCta extends StatelessWidget {
  const _FinalCta({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = Breakpoints.isMobile(context);
    return _Section(
      background: AppColors.surface,
      child: Container(
        padding: EdgeInsets.all(isMobile ? AppSpacing.lg + 4 : AppSpacing.xxl),
        decoration: BoxDecoration(
          gradient: AppColors.romanticGradient,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 60,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              'Your next match is one rewrite away.',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Start coaching with DateWise AI in under a minute.',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            HoverScale(
              child: ElevatedButton(
                onPressed: onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primaryDeep,
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 4,
                  ),
                  child: Text('Get started'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Professional multi-column footer with brand blurb, link columns, social
/// icons, and a responsive bottom bar.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.onStart,
    required this.onSeePlans,
    required this.onStories,
    required this.onHowItWorks,
  });
  final VoidCallback onStart;

  /// Scrolls to pricing; null during the free launch (drops the Pricing link).
  final VoidCallback? onSeePlans;
  final VoidCallback onStories;
  final VoidCallback onHowItWorks;

  /// Opens a legal page (Privacy / Terms) at its public URL in a new tab.
  void _openUrl(String url) {
    launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = Breakpoints.isMobile(context);

    final brand = SizedBox(
      width: isMobile ? double.infinity : 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandMark(onLight: true),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Your AI dating coach — brutal honesty, real strategy, and the warmth '
            'of a best friend. Present your most magnetic self.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: const [
              _SocialIcon(Icons.camera_alt_outlined, 'Instagram'),
              _SocialIcon(Icons.alternate_email, 'X / Twitter'),
              _SocialIcon(Icons.music_note, 'TikTok'),
              _SocialIcon(Icons.play_circle_outline, 'YouTube'),
            ],
          ),
        ],
      ),
    );

    final columns = [
      _FooterColumn(
        title: 'Product',
        links: [
          ('How it works', onHowItWorks),
          if (onSeePlans != null) ('Pricing', onSeePlans!),
          ('Stories', onStories),
          ('Start coaching', onStart),
        ],
      ),
      _FooterColumn(
        title: 'Company',
        links: [('About', null), ('Careers', null), ('Press', null)],
      ),
      _FooterColumn(
        title: 'Legal',
        links: [
          ('Privacy', () => _openUrl(AppLinks.privacyPolicyUrl)),
          ('Terms', () => _openUrl(AppLinks.termsUrl)),
        ],
      ),
    ];

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF0C0615),
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.xxl,
        horizontal: isMobile ? AppSpacing.md : AppSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            children: [
              Wrap(
                spacing: AppSpacing.xxl,
                runSpacing: AppSpacing.xl,
                alignment: WrapAlignment.spaceBetween,
                children: [brand, ...columns],
              ),
              const SizedBox(height: AppSpacing.xl),
              Divider(color: Colors.white.withValues(alpha: 0.12)),
              const SizedBox(height: AppSpacing.md),
              Flex(
                direction: isMobile ? Axis.vertical : Axis.horizontal,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment:
                    isMobile
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.center,
                children: [
                  Text(
                    '© 2026 DateWise AI. All rights reserved.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  if (isMobile) const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Private by design · Your data stays on your device',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({required this.title, required this.links});
  final String title;
  final List<(String, VoidCallback?)> links;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: AppSpacing.md),
        ...links.map((l) => _FooterLink(label: l.$1, onTap: l.$2)),
      ],
    );
  }
}

class _FooterLink extends StatefulWidget {
  const _FooterLink({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              color: _hover ? AppColors.accent : AppColors.textMuted,
              fontSize: 14,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

class _SocialIcon extends StatefulWidget {
  const _SocialIcon(this.icon, this.tooltip);
  final IconData icon;
  final String tooltip;

  @override
  State<_SocialIcon> createState() => _SocialIconState();
}

class _SocialIconState extends State<_SocialIcon> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color:
                  _hover
                      ? AppColors.primaryDeep
                      : Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
