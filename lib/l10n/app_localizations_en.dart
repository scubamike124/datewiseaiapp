// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'DateWise AI';

  @override
  String get back => 'Back';

  @override
  String get continueAction => 'Continue';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get clear => 'Clear';

  @override
  String get retry => 'Try again';

  @override
  String get languageNameEn => 'English';

  @override
  String get languageNameEs => 'Spanish';

  @override
  String get coachesForEn => 'Coaches: Ava and Ethan';

  @override
  String get coachesForEs => 'Coaches: Sofía and Diego';

  @override
  String coachChip(String name, String language) {
    return '$name · AI coach · $language';
  }

  @override
  String coachAiLabel(String language) {
    return 'AI dating coach · $language';
  }

  @override
  String coachPortrait(String name) {
    return 'Portrait of $name, AI coach';
  }

  @override
  String coachPortraitStill(String name) {
    return '$name, AI coach (still portrait)';
  }

  @override
  String get coachDescAva =>
      'Confidence coach. Direct, supportive, focused on results.';

  @override
  String get coachDescEthan => 'Strategy coach. Practical, modern, laid‑back.';

  @override
  String get coachDescSofia => 'Confidence coach. Warm and motivating.';

  @override
  String get coachDescDiego => 'Relationship coach. Practical and honest.';

  @override
  String chatWith(String name) {
    return 'Chat with $name';
  }

  @override
  String get yourCoachBadge => 'Your coach';

  @override
  String get stopPreview => 'Stop preview';

  @override
  String hearCoach(String name) {
    return 'Hear $name';
  }

  @override
  String get tabHome => 'Home';

  @override
  String get tabCoaches => 'Coaches';

  @override
  String get tabChat => 'Chat';

  @override
  String get tabProgress => 'Progress';

  @override
  String get tabYou => 'You';

  @override
  String tabSemantics(String label) {
    return '$label tab';
  }

  @override
  String welcomePortrait(String name) {
    return '$name, an AI dating coach, smiling';
  }

  @override
  String get welcomeTitleLead => 'Meet your\nAI dating ';

  @override
  String get welcomeTitleAccent => 'coach.';

  @override
  String get welcomeBody =>
      'Honest help with your profile, your messages and your first date, from a coach who listens.';

  @override
  String get getStarted => 'Get started';

  @override
  String get valueConversations => 'Better conversations';

  @override
  String get valueProfile => 'Profile help';

  @override
  String get valueDates => 'First-date plans';

  @override
  String get welcomeFootnote =>
      'AI coaches · For adults 18+ · English · Español';

  @override
  String stepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String get goalsTitle => 'What would you like help with?';

  @override
  String get goalsSubtitle =>
      'Pick up to three. They become your plan for the week.';

  @override
  String get goalConversations => 'Better conversations';

  @override
  String get goalProfile => 'A stronger profile';

  @override
  String get goalDates => 'Great first dates';

  @override
  String get goalConfidence => 'More confidence';

  @override
  String get goalRelationship => 'A healthier relationship';

  @override
  String get languageTitle => 'Choose your language';

  @override
  String get languageSubtitle =>
      'The app and your coaches will use it. You can change it any time in the You tab.';

  @override
  String get ageTitle => 'DateWise is for adults.';

  @override
  String get ageSubtitle => 'Please confirm your age to continue.';

  @override
  String get ageConfirm => 'I am 18 or older';

  @override
  String get ageUnder => 'I am under 18';

  @override
  String get underageTitle => 'Sorry, DateWise is only for adults.';

  @override
  String get underageBody => 'You need to be 18 or older to use DateWise AI.';

  @override
  String get underageClose => 'You can close the app now.';

  @override
  String get chooseCoachTitle => 'Choose your dating coach';

  @override
  String get chooseCoachSubtitle =>
      'All four are AI coaches. Pick a style; switch any time.';

  @override
  String get coachesEyebrow => 'AI dating coaches';

  @override
  String get greetingMorning => 'Good morning.';

  @override
  String get greetingAfternoon => 'Good afternoon.';

  @override
  String get greetingEvening => 'Good evening.';

  @override
  String homeReady(String name, String gender) {
    return '$name is ready when you are. Your AI coach, any time.';
  }

  @override
  String homeResume(String name, String gender, String title) {
    return '$name is ready when you are. Pick up where you left off: “$title”';
  }

  @override
  String talkTo(String name) {
    return 'Talk to $name';
  }

  @override
  String voiceChatWith(String name) {
    return 'Voice chat with $name';
  }

  @override
  String get planThisWeek => 'Your plan this week';

  @override
  String get planDone => 'Done';

  @override
  String get planNext => 'Next';

  @override
  String get planNotYet => 'Not yet';

  @override
  String planItemConversations(String name) {
    return 'Practice an opener with $name';
  }

  @override
  String planItemProfile(String name) {
    return 'Rewrite your bio with $name';
  }

  @override
  String get planItemDates => 'Plan a first date';

  @override
  String get planItemConfidence => 'Talk through what makes you nervous';

  @override
  String get planItemRelationship => 'Practice saying how you feel';

  @override
  String get planPromptConversations =>
      'Help me practice an opener for someone I matched with.';

  @override
  String get planPromptProfile => 'Rewrite my dating bio.';

  @override
  String get planPromptDates => 'Help me plan a great first date.';

  @override
  String get planPromptConfidence =>
      'I get nervous before dates. Can you help?';

  @override
  String get planPromptRelationship => 'Help me tell my partner how I feel.';

  @override
  String get quickPractice => 'Practice a conversation';

  @override
  String get quickPracticePrompt =>
      'Let\'s practice a conversation. You play my match and I\'ll reply.';

  @override
  String get quickProfile => 'Improve my profile';

  @override
  String get quickProfilePrompt => 'Help me improve my dating profile.';

  @override
  String get quickDate => 'Prepare for a date';

  @override
  String get quickDatePrompt => 'Help me prepare for a date.';

  @override
  String get quickReply => 'Help me reply';

  @override
  String get quickReplyPrompt => 'Help me reply to a message.';

  @override
  String get voicePermissionNeeded =>
      'Voice needs microphone and speech recognition access. You can allow it in Settings.';

  @override
  String voiceUnavailableNote(String name) {
    return 'Voice isn\'t available on this device. You can type to $name.';
  }

  @override
  String get newConversation => 'New conversation';

  @override
  String pastConversationsWith(String name) {
    return 'Past conversations with $name';
  }

  @override
  String get switchCoach => 'Switch coach';

  @override
  String get noSavedConversations => 'No saved conversations yet.';

  @override
  String conversationsWith(String name) {
    return 'Conversations with $name';
  }

  @override
  String get deleteConversation => 'Delete conversation';

  @override
  String get conversationOptions => 'Conversation options';

  @override
  String voiceSession(String elapsed) {
    return 'Voice session · $elapsed';
  }

  @override
  String get hideCaptions => 'Hide captions';

  @override
  String get showCaptions => 'Show captions';

  @override
  String coachTyping(String name) {
    return '$name is typing';
  }

  @override
  String coachSays(String name, String text) {
    return '$name: $text';
  }

  @override
  String youSaid(String text) {
    return 'You: $text';
  }

  @override
  String copyReply(String label, String text) {
    return 'Copy $label reply: $text';
  }

  @override
  String get copiedReply => 'Copied. Paste it into your dating app.';

  @override
  String messageHint(String name) {
    return 'Message $name…';
  }

  @override
  String get voiceMode => 'Voice mode';

  @override
  String get send => 'Send';

  @override
  String get stopReply => 'Stop reply';

  @override
  String get listening => 'Listening…';

  @override
  String get typeInstead => 'Type instead';

  @override
  String get holdToTalk => 'Hold to talk';

  @override
  String get stopReadingAloud => 'Stop reading replies aloud';

  @override
  String get readAloud => 'Read replies aloud';

  @override
  String holdToTalkFooter(String name, String gender) {
    return 'Hold to talk · $name is an AI coach';
  }

  @override
  String tapToTalkFooter(String name, String gender) {
    return 'Tap to talk · $name is an AI coach';
  }

  @override
  String get premiumEyebrow => 'DateWise Premium';

  @override
  String lockedTitle(String name) {
    return 'Chat with $name is part of DateWise Premium.';
  }

  @override
  String get lockedBody =>
      'Subscribe to talk with all four AI coaches. Your conversations stay on this device.';

  @override
  String get seePremium => 'See DateWise Premium';

  @override
  String get chatErrorUnavailable =>
      'Couldn\'t reach your coach. Check your connection and try again. Your message is saved.';

  @override
  String get chatErrorBusy =>
      'Your coach is getting a lot of messages right now. Try again in a moment. Your message is saved.';

  @override
  String get chatErrorOffline =>
      'You seem to be offline. Check your connection and try again. Your message is saved.';

  @override
  String get chatErrorServer =>
      'Coaching is temporarily unavailable. Try again in a few minutes. Your message is saved.';

  @override
  String get chatErrorStopped =>
      'The reply was stopped. Your message is saved.';

  @override
  String paywallHeadline(String name) {
    return 'Everyday coaching with $name and the team.';
  }

  @override
  String get benefitCoaches =>
      'Chat with all four AI coaches, in English and Spanish';

  @override
  String get benefitVoice =>
      'Voice practice: speak and hear replies on your device';

  @override
  String get benefitPlan =>
      'Your weekly plan and progress, kept on your device';

  @override
  String get monthlyAutoRenews => 'Monthly · auto-renews';

  @override
  String get perMonth => 'per month';

  @override
  String pricePerMonth(String price) {
    return '$price/month';
  }

  @override
  String subscribeFor(String price) {
    return 'Subscribe for $price/month';
  }

  @override
  String get paywallWebOnly =>
      'Subscribe in the app on your iPhone or iPad. Purchases are not available on the web.';

  @override
  String get purchasePending =>
      'Your purchase is pending approval. Chat unlocks as soon as it is approved.';

  @override
  String get purchaseFailed => 'Purchase failed. Please try again.';

  @override
  String get purchasesUnavailable => 'Purchases are not available right now.';

  @override
  String get storeUnavailable => 'The App Store is not available right now.';

  @override
  String get storeUnreachable => 'Could not reach the App Store.';

  @override
  String get productUnavailable =>
      'DateWise Premium is not available in the store yet.';

  @override
  String get restoreFailed => 'Could not restore purchases.';

  @override
  String get noSubscriptionForAppleId =>
      'No active DateWise Premium subscription was found for this Apple Account.';

  @override
  String get reviewBuildNote =>
      'Review build: purchases are simulated and nothing is charged.';

  @override
  String paywallDisclosure(String perMonth, String price) {
    return '$perMonth. Payment is charged to your Apple Account at confirmation of purchase. The subscription renews automatically every month at $price unless you cancel it at least 24 hours before the end of the current period. Cancel any time in Settings › [your name] › Subscriptions.';
  }

  @override
  String get priceFromAppStore => 'Price shown by the App Store';

  @override
  String get subscribe => 'Subscribe';

  @override
  String paywallFairUse(
    String daily,
    String monthly,
    String perMinute,
    String concurrent,
  ) {
    return 'Fair use: up to $daily coach replies a day and $monthly a month, at most $perMinute a minute and $concurrent at a time. Typed and spoken messages count the same. A notice appears near a limit; at the limit, chat pauses until the next day (00:00 UTC) or month.';
  }

  @override
  String get paywallDisclosureNoPrice =>
      'Monthly subscription at the price shown by the App Store. Payment is charged to your Apple Account at confirmation of purchase. The subscription renews automatically every month at that price unless you cancel it at least 24 hours before the end of the current period. Cancel any time in Settings › [your name] › Subscriptions.';

  @override
  String get tapToSend => 'Stop and send';

  @override
  String get tapToTalkHint =>
      'Double-tap to start talking, then double-tap again to send';

  @override
  String get voiceRecognitionUnavailable =>
      'Speech recognition isn\'t available on this device right now. You can type your message instead.';

  @override
  String get voiceLanguageUnsupported =>
      'Voice isn\'t available for this language on this device. You can type your message instead.';

  @override
  String get photoNoLongerAvailable =>
      'Photo from an earlier version (no longer available)';

  @override
  String get restorePurchases => 'Restore purchases';

  @override
  String get termsOfUse => 'Terms of Use';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get privacyShort => 'Privacy';

  @override
  String get progressTitle => 'Progress';

  @override
  String get progressSubtitle =>
      'Counted on this device from what you actually did.';

  @override
  String statConversations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'conversations',
      one: 'conversation',
    );
    return '$_temp0';
  }

  @override
  String statStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days in a row',
      one: 'day in a row',
    );
    return '$_temp0';
  }

  @override
  String statDaysUsed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days with a coach',
      one: 'day with a coach',
    );
    return '$_temp0';
  }

  @override
  String statPlanDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'plan steps done this week',
      one: 'plan step done this week',
    );
    return '$_temp0';
  }

  @override
  String noDaysYet(String name) {
    return 'No coaching days yet. Send $name a message to start your streak.';
  }

  @override
  String daysTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return 'You\'ve talked with a coach on $_temp0 in total.';
  }

  @override
  String get weekPlanTitle => 'This week’s plan';

  @override
  String planCount(int done, int total) {
    return '$done of $total done';
  }

  @override
  String get progressFootnote =>
      'Check off plan items on Home. Checkmarks reset every Monday.';

  @override
  String get youTitle => 'You';

  @override
  String get sectionCoaching => 'Coaching';

  @override
  String get languageRow => 'Language';

  @override
  String get yourCoachRow => 'Your coach';

  @override
  String get sectionMemory => 'Coach memory';

  @override
  String get memoryTitle => 'Coach memory';

  @override
  String get memoryOn => 'On: your note is sent with each message.';

  @override
  String get memoryOff =>
      'Off: no note is kept (turning it off deletes it) and coaches only see the current conversation.';

  @override
  String get writeNote => 'Write your note';

  @override
  String get yourNote => 'Your note';

  @override
  String get clearMemory => 'Clear memory';

  @override
  String get clearMemoryTitle => 'Clear Coach memory?';

  @override
  String get clearMemoryBody => 'Your note will be deleted from this device.';

  @override
  String get memoryOffTitle => 'Turn off Coach memory?';

  @override
  String get memoryOffBody =>
      'Your note will be deleted from this device, and coaches will only see the current conversation.';

  @override
  String get memoryTurnOnTitle => 'Turn on Coach memory?';

  @override
  String get memoryTurnOnBody =>
      'Your note is kept only while Coach memory is on. While it is on, it is sent to your coach with each message.';

  @override
  String get memoryTurnOnAction => 'Turn on & save';

  @override
  String get memoryOffAction => 'Turn off & delete';

  @override
  String get memorySheetBody =>
      'A short note your coaches see with each message while Coach memory is on. Write only what you are happy to share.';

  @override
  String get memoryHint =>
      'e.g. I am 31, shy at first, on Hinge, looking for something serious.';

  @override
  String get sectionSubscription => 'Subscription';

  @override
  String get subActive => 'Active';

  @override
  String get subNone => 'Not subscribed';

  @override
  String get manageSubscription => 'Manage subscription';

  @override
  String get restorePurchasesRow => 'Restore purchases';

  @override
  String get restoreOk => 'DateWise Premium is active.';

  @override
  String get restoreNone => 'No active subscription found.';

  @override
  String get sectionData => 'Your data';

  @override
  String get deleteAllConversations => 'Delete all conversations';

  @override
  String get deleteAllConversationsTitle => 'Delete all conversations?';

  @override
  String get deleteAllConversationsBody =>
      'Every conversation with every coach will be deleted from this device.';

  @override
  String get deleteMyData => 'Delete my data';

  @override
  String get deleteMyDataNote =>
      'Does not cancel your subscription. Cancel it in Apple settings.';

  @override
  String get deleteMyDataTitle => 'Delete all your data?';

  @override
  String get deleteMyDataBody =>
      'Conversations, plan, progress, Coach memory and settings will be erased from this device, and the app will start again.\n\nYour subscription is managed by Apple and stays active: deleting your data does not cancel it. To cancel it, go to Settings › [your name] › Subscriptions.';

  @override
  String get deleteEverything => 'Delete everything';

  @override
  String get sectionAbout => 'About';

  @override
  String get support => 'Support';

  @override
  String couldNotOpen(String url) {
    return 'Could not open $url';
  }

  @override
  String get findTable => 'Find a table';

  @override
  String get findTableSemantics => 'Find a table nearby. Opens Apple Maps.';

  @override
  String get findTableQuery => 'restaurants';

  @override
  String get settingsFootnote =>
      'Your coaches are AI. Conversations are stored on this device.';

  @override
  String appVersion(String version) {
    return 'DateWise AI $version';
  }

  @override
  String get legalTranslationNote => '';

  @override
  String get coachLimitDaily =>
      'You\'ve reached today\'s coaching limit. It resets at midnight (UTC).';

  @override
  String get coachLimitMonthly =>
      'You\'ve reached this month\'s fair-use limit. It resets on the 1st.';

  @override
  String get coachLimitSlowDown =>
      'You\'re sending messages quickly. Please wait a moment and try again.';

  @override
  String get coachLimitBusy =>
      'Coaching is busy right now. Please try again later.';

  @override
  String get coachLimitSubscriptionInactive =>
      'Your DateWise Premium subscription isn\'t active. Renew it to keep chatting.';

  @override
  String get coachLimitRevoked =>
      'This purchase was refunded or revoked, so coaching is locked.';

  @override
  String get coachLimitVerify =>
      'We couldn\'t confirm your subscription. Tap Restore purchases.';

  @override
  String get coachLimitUpdateApp =>
      'Update DateWise to the latest version to keep chatting with your coach.';

  @override
  String get coachUsageNoticeDaily =>
      'You\'re close to today\'s fair-use limit.';

  @override
  String get coachUsageNoticeMonthly =>
      'You\'re close to this month\'s fair-use limit.';

  @override
  String get chatErrorInterrupted =>
      'The reply was interrupted when the app closed. Your message is saved.';

  @override
  String get conversationDeleted => 'Conversation deleted.';

  @override
  String get undo => 'Undo';

  @override
  String get ageUnderConfirmTitle => 'Are you under 18?';

  @override
  String get ageUnderConfirmBody =>
      'DateWise is only for adults. If you confirm, the app stays locked on this device.';

  @override
  String get ageUnderConfirmAction => 'Yes, I\'m under 18';

  @override
  String voicePermissionDeniedNote(String name) {
    return 'Microphone or speech recognition access is turned off for DateWise. Allow it in Settings to talk with $name, or type instead.';
  }

  @override
  String get openSettings => 'Open Settings';

  @override
  String get voiceNoSpeech =>
      'I didn\'t catch that. Hold the button and try again.';

  @override
  String get voiceKeptInComposer =>
      'Your coach is still replying. What you said is in the message box.';

  @override
  String avatarAnimated(String name) {
    return '$name, animated AI coach';
  }

  @override
  String avatarSpeaking(String name) {
    return '$name, animated AI coach, speaking';
  }

  @override
  String avatarListening(String name) {
    return '$name, animated AI coach, listening';
  }

  @override
  String avatarThinking(String name) {
    return '$name, animated AI coach, thinking';
  }

  @override
  String get voiceQualityRow => 'More natural coach voices';

  @override
  String get voiceQualityTitle => 'Get more natural voices';

  @override
  String get voiceQualityBody =>
      'Coaches speak with your iPhone\'s own voices, on your device. For the most natural sound, download one of Apple\'s Premium or Enhanced voices:\n\n1. Open the Settings app › Accessibility › Spoken Content › Voices.\n2. Choose English or Spanish.\n3. Download a voice marked Premium or Enhanced (for example Ava or Zoe, Evan or Nathan, Paulina or Juan).\n\nDateWise uses it automatically the next time a coach speaks. Each coach keeps a distinct voice when several are installed.';

  @override
  String get voiceQualityDone => 'Got it';

  @override
  String get aiConsentTitle => 'Share messages with our AI provider?';

  @override
  String get aiConsentBody =>
      'To write your coach\'s replies, DateWise sends your messages (typed or spoken, as text), your coaching preferences, your country (US, Canada, Mexico or Spain only, for the right crisis lines) and, if Coach memory is on, your memory note to Cloudflare Workers AI, which runs Meta\'s Llama model. They are processed only to write the reply: they are not stored on our servers, not used to train AI models and not linked to your identity. See our Privacy Policy for details.';

  @override
  String get aiConsentAgree => 'Agree';

  @override
  String get aiConsentNotNow => 'Not now';

  @override
  String get copyFailed => 'Couldn\'t copy that. Try again.';

  @override
  String get coachLimitTooLong =>
      'That message is too long for your coach. Shorten it and try again, or start a new conversation.';

  @override
  String lockedHistoryNote(String name) {
    return 'Your conversations are saved. Subscribe to keep chatting with $name.';
  }

  @override
  String get sectionPrivacy => 'Privacy';

  @override
  String get aiSharingTitle => 'Share messages with the AI provider';

  @override
  String get aiSharingOn =>
      'On. Your messages go to Cloudflare Workers AI only to write each reply.';

  @override
  String get aiSharingOff =>
      'Off. Nothing is sent and your coach can\'t reply. Your conversations stay on this device.';

  @override
  String get sectionSafety => 'Safety';

  @override
  String get getHelpNow => 'Get help now';

  @override
  String get getHelpSubtitle => 'Crisis and emergency lines';

  @override
  String get getHelpIntro =>
      'If you or someone else is in danger, call your local emergency number now. These official lines are confidential and open 24 hours. DateWise is not a crisis service.';

  @override
  String get helpCountryUS => 'United States';

  @override
  String get helpCountryCA => 'Canada';

  @override
  String get helpCountryMX => 'Mexico';

  @override
  String get helpCountryES => 'Spain';

  @override
  String get helpEmergency => 'Emergencies';

  @override
  String get helpUsSuicide =>
      '988 Suicide & Crisis Lifeline: call or text (free, 24/7, Spanish available)';

  @override
  String get helpUsAbuse => 'National Domestic Violence Hotline (free, 24/7)';

  @override
  String get helpUsAbuseText => 'Domestic violence: text START to 88788';

  @override
  String get helpCaSuicide =>
      '9-8-8 Suicide Crisis Helpline: call or text (24/7, English or French)';

  @override
  String get helpCaAbuse =>
      'Family or gender-based violence: contact your province\'s or territory\'s crisis line, or 9-1-1 in an emergency.';

  @override
  String get helpMxSuicide => 'Línea de la Vida (free, 24/7)';

  @override
  String get helpMxWomen =>
      'Línea de las Mujeres, gender-based violence: dial 079, then option 1 (free, 24/7)';

  @override
  String get helpEsSuicide =>
      '024 suicide crisis line (free, confidential, 24/7)';

  @override
  String get helpEsAbuse =>
      '016 violence against women (free, 24/7, not shown on the phone bill)';

  @override
  String get helpEsWhatsApp => '016 on WhatsApp';

  @override
  String get helpFootnote =>
      'Numbers checked on official government and service websites, November 2026. In another country, call your local emergency number.';

  @override
  String lockedPreviewLabel(String name) {
    return 'How $name starts a conversation';
  }

  @override
  String get storeStatusTitle => 'Store status';

  @override
  String get storeStatusCopy => 'Copy';

  @override
  String get storeStatusQueryAgain => 'Query again';

  @override
  String get storeStatusQuerying => 'Querying…';

  @override
  String get storeStatusStore => 'Store';

  @override
  String storeStatusNoStoreKit(String store) {
    return '$store (no StoreKit in this build)';
  }

  @override
  String get storeStatusProductId => 'Product id queried';

  @override
  String get storeStatusQueries => 'Queries run';

  @override
  String get storeStatusLastQuery => 'Last query';

  @override
  String get storeStatusProductsReturned => 'Products returned';

  @override
  String get storeStatusReturnedIds => 'Returned ids';

  @override
  String get storeStatusNotFoundIds => 'notFoundIDs';

  @override
  String get storeStatusErrorCode => 'Error code';

  @override
  String get storeStatusErrorMessage => 'Error message';

  @override
  String get storeStatusCanMakePayments => 'Can make payments';

  @override
  String get storeStatusStorefront => 'Storefront';

  @override
  String get storeStatusStoreKit2 => 'StoreKit 2';

  @override
  String get storeStatusPrice => 'Price from store';

  @override
  String get storeStatusSubscribed => 'Subscribed';

  @override
  String get storeStatusStatusRead => 'Status read';

  @override
  String get storeStatusPaywallError => 'Paywall error';

  @override
  String get storeStatusNotYet => 'not yet';

  @override
  String get storeStatusUnknown => 'unknown';

  @override
  String get storeStatusNotApplicable => 'n/a';

  @override
  String get storeStatusUnavailable => 'unavailable';

  @override
  String get storeStatusYes => 'yes';

  @override
  String get storeStatusNo => 'no';
}
