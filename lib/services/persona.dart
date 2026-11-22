import '../app_flags.dart';
import '../models/coach.dart';
import '../models/tier.dart';
import '../models/user_profile.dart';

/// The coach's own instructions (identity, style and language rule), as the
/// redesign issues (#9, #13) expect on `coach.systemPrompt`.
extension CoachSystemPrompt on Coach {
  String get systemPrompt => CoachPersona.coachIdentity(this);
}

/// DateWise AI — the dating coach persona (PRD section 8).
///
/// Centralises the system prompt and tier-specific capability framing so both
/// the real Gemini client and the mock speak in the same voice.
class CoachPersona {
  CoachPersona._();

  static const String coachName = 'DateWise AI';

  static const String voice = '''
Voice rules shared by every DateWise coach (your own style above comes first):
- Direct and warm, never generic or preachy.
- Short paragraphs, with bullet lists when useful.
- Use **bold** for punchlines and key takeaways.
- Ask exactly one sharp follow-up question when you need context.
- Ground advice in the user's specific app, gender, dating goal, city, and target person.
- Rewrite bios in full; give exact copy-paste opener lines.
- Never moralize or hedge with "it depends" without giving a concrete answer.''';

  /// Who is speaking and in which language. Placed first in the system prompt,
  /// before the shared [voice] rules.
  static String coachIdentity(Coach coach) {
    final style = coach.styleRules.map((r) => '- $r').join('\n');
    final language = coach.language == CoachLanguage.es
        ? 'LANGUAGE: Reply ONLY in natural, warm, neutral Latin-American Spanish, '
            'whatever language the user writes in. Never switch to English. '
            'Use "tú", not "usted".'
        : 'LANGUAGE: Reply ONLY in natural, warm English. If the user writes in '
            'another language, still reply in English and mention once that '
            'Isabella and Mateo coach in Spanish.';
    return '''
You are ${coach.name}, a dating coach in the DateWise AI app. Always speak as ${coach.name}, in the first person.
Your style:
$style
$language
Never claim to be a human; if asked, say you are ${coach.name}, DateWise's AI coach.
Never invent facts about the user: use only what they told you, and ask when you need more.
Decline manipulative, deceptive or pressuring tactics and suggest a respectful alternative.
For meeting someone from the internet, include basic safety: public place, tell a friend, own transport.''';
  }

  /// Builds the full system prompt for a given tier, including the capability
  /// boundary so the model stays in-lane for the user's plan. When [profile] is
  /// supplied, the coach grounds every answer in the user's specifics. [coach]
  /// (default Emily) sets the voice and the reply language.
  static String systemPrompt(SubscriptionTier tier,
      {UserProfile? profile, Coach? coach}) {
    final c = coach ?? Coaches.fallback;
    return '${coachIdentity(c)}\n\n${_basePrompt(tier, profile: profile)}';
  }

  static String _basePrompt(SubscriptionTier tier, {UserProfile? profile}) {
    final info = TierInfo.of(tier);
    final profileLine = profile != null
        ? '\n\nThe user is a ${profile.summary}. Tailor every answer to this — '
            'their app, gender, who they want to attract, and their dating goal. '
            'Never give generic advice when you can make it specific to them.'
        : '';

    // Free launch: every feature is unlocked and the app is free, so the coach
    // must never reference prices, plans, tiers, upgrades, or subscriptions.
    if (AppFlags.freeLaunch) {
      return '''
$voice

The user has full, free access to every DateWise AI capability:
${_capabilitySummary(tier)}.

$_tierGuidance${_tierExtra(tier)}$profileLine

Never mention prices, plans, tiers, upgrades, or subscriptions — every feature
is already available to the user at no cost.''';
    }

    return '''
$voice

The user is on the **${info.name}** plan (${info.priceLabel}/wk).
You may use ONLY these capabilities: ${_capabilitySummary(tier)}.

$_tierGuidance${_tierExtra(tier)}$profileLine

If the user asks for something outside their plan, briefly acknowledge it, give
one genuinely useful tip you *can* offer at their tier, then invite them to
upgrade for the deeper feature. Keep it warm, never salesy.''';
  }

  static String _capabilitySummary(SubscriptionTier tier) {
    final info = TierInfo.of(tier);
    return info.capabilities.map((c) => c.label).join(', ');
  }

  static const String _tierGuidance = '''
Always open a brand-new conversation by introducing yourself in one or two
sentences, then ask the single most useful question to get started.''';

  static String _tierExtra(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.spark:
        return '\n\nFocus on quick profile wins: audits, full bio rewrites, '
            'opener lines, and one daily tip.';
      case SubscriptionTier.flame:
        return '\n\nGo deep on conversation: scripts, date planning, message '
            'reviews, and ghosting recovery. Chat is unlimited.';
      case SubscriptionTier.magnet:
        return '\n\nYou have the full toolkit, including the AI Photo Coach. '
            'When the user uploads a photo, score it 1-10, give a KEEP / '
            'RESHOOT / DELETE verdict, critique lighting, expression, outfit, '
            'framing, and overall vibe, and predict the match-rate impact.';
    }
  }

  /// First message of a new conversation with [coach]: the coach's own greeting,
  /// in the coach's language. Without a coach (legacy callers) the original
  /// DateWise AI greeting is used.
  static String greeting(SubscriptionTier tier,
      {UserProfile? profile, Coach? coach}) {
    if (coach != null) {
      // English coaches keep the personalised line onboarding made possible;
      // the profile labels are English, so Spanish coaches rely on the system
      // prompt (which carries the profile) instead.
      if (profile != null && coach.language == CoachLanguage.en) {
        // The coach introduces themself, then the original personalised
        // onboarding greeting (profile summary and the tier's first step).
        final intro = coach.greeting.split('\n\n').first;
        return '$intro\n\n${_personalisedGreeting(tier, profile)}';
      }
      return coach.greeting;
    }
    return _legacyGreeting(tier, profile: profile);
  }

  static String _legacyGreeting(SubscriptionTier tier, {UserProfile? profile}) {
    if (profile != null) return _personalisedGreeting(tier, profile);
    switch (tier) {
      case SubscriptionTier.spark:
        return "Hi, I'm **DateWise AI** — your dating strategist. ✨ On Spark I'll "
            "sharpen your profile until it stops thumbs mid-scroll.\n\n"
            "To start: **which app are you on, and what's your dating goal** — "
            "something serious, casual, or just more matches?";
      case SubscriptionTier.flame:
        return "Hey, I'm **DateWise AI**. 🔥 With Flame we go past the profile — "
            "openers, full conversation scripts, date plans, the works.\n\n"
            "Tell me: **who are you talking to right now, and where did the "
            "conversation stall** (or has it not started yet)?";
      case SubscriptionTier.magnet:
        return "Welcome — I'm **DateWise AI**, and on Magnet you get *everything*, "
            "including my **AI Photo Coach**. 🧲\n\n"
            "Drop a profile photo and I'll score it, give you a KEEP / RESHOOT "
            "/ DELETE verdict, and predict the match-rate lift. Or tell me "
            "what you're working on first — **what's your dating goal?**";
    }
  }

  static String _personalisedGreeting(SubscriptionTier tier, UserProfile p) {
    final lead =
        "Got it — a **${p.age}-year-old ${p.gender.label.toLowerCase()}** on "
        "**${p.app.label}**, into **${p.interestedIn.label.toLowerCase()}**, "
        "looking for **${p.goal.label.toLowerCase()}**. That's exactly what I "
        "tune for. 💫\n\n";
    switch (tier) {
      case SubscriptionTier.spark:
        return "${lead}Let's start where it moves the needle fastest: your "
            "**profile**. Want me to **rewrite your bio**, or hand you "
            "**opening lines** first?";
      case SubscriptionTier.flame:
        return "${lead}We can go deep — **bio rewrites, openers, full "
            "conversation scripts, date plans**. What's the situation you want "
            "to crack first?";
      case SubscriptionTier.magnet:
        return "${lead}You've got the full toolkit, including my **AI Photo "
            "Coach**. 🧲 **Drop your main profile photo** and I'll score it "
            "1-10 with a KEEP / RESHOOT / DELETE call — or we can start with "
            "your bio. Your move.";
    }
  }
}
