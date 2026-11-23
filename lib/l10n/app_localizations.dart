import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'DateWise AI'**
  String get appTitle;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @languageNameEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageNameEn;

  /// No description provided for @languageNameEs.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get languageNameEs;

  /// No description provided for @coachesForEn.
  ///
  /// In en, this message translates to:
  /// **'Coaches: Ava and Ethan'**
  String get coachesForEn;

  /// No description provided for @coachesForEs.
  ///
  /// In en, this message translates to:
  /// **'Coaches: Sofía and Diego'**
  String get coachesForEs;

  /// No description provided for @coachChip.
  ///
  /// In en, this message translates to:
  /// **'{name} · AI coach · {language}'**
  String coachChip(String name, String language);

  /// No description provided for @coachAiLabel.
  ///
  /// In en, this message translates to:
  /// **'AI dating coach · {language}'**
  String coachAiLabel(String language);

  /// No description provided for @coachPortrait.
  ///
  /// In en, this message translates to:
  /// **'Portrait of {name}, AI coach'**
  String coachPortrait(String name);

  /// No description provided for @coachPortraitStill.
  ///
  /// In en, this message translates to:
  /// **'{name}, AI coach (still portrait)'**
  String coachPortraitStill(String name);

  /// No description provided for @coachDescAva.
  ///
  /// In en, this message translates to:
  /// **'Confidence coach. Direct, supportive, focused on results.'**
  String get coachDescAva;

  /// No description provided for @coachDescEthan.
  ///
  /// In en, this message translates to:
  /// **'Strategy coach. Practical, modern, laid‑back.'**
  String get coachDescEthan;

  /// No description provided for @coachDescSofia.
  ///
  /// In en, this message translates to:
  /// **'Confidence coach. Warm and motivating.'**
  String get coachDescSofia;

  /// No description provided for @coachDescDiego.
  ///
  /// In en, this message translates to:
  /// **'Relationship coach. Practical and honest.'**
  String get coachDescDiego;

  /// No description provided for @chatWith.
  ///
  /// In en, this message translates to:
  /// **'Chat with {name}'**
  String chatWith(String name);

  /// No description provided for @yourCoachBadge.
  ///
  /// In en, this message translates to:
  /// **'Your coach'**
  String get yourCoachBadge;

  /// No description provided for @stopPreview.
  ///
  /// In en, this message translates to:
  /// **'Stop preview'**
  String get stopPreview;

  /// No description provided for @hearCoach.
  ///
  /// In en, this message translates to:
  /// **'Hear {name}'**
  String hearCoach(String name);

  /// No description provided for @tabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// No description provided for @tabCoaches.
  ///
  /// In en, this message translates to:
  /// **'Coaches'**
  String get tabCoaches;

  /// No description provided for @tabChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get tabChat;

  /// No description provided for @tabProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get tabProgress;

  /// No description provided for @tabYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get tabYou;

  /// No description provided for @tabSemantics.
  ///
  /// In en, this message translates to:
  /// **'{label} tab'**
  String tabSemantics(String label);

  /// Semantic label of the welcome hero portrait (Ava in English, Sofía in Spanish).
  ///
  /// In en, this message translates to:
  /// **'{name}, an AI dating coach, smiling'**
  String welcomePortrait(String name);

  /// No description provided for @welcomeTitleLead.
  ///
  /// In en, this message translates to:
  /// **'Meet your\nAI dating '**
  String get welcomeTitleLead;

  /// No description provided for @welcomeTitleAccent.
  ///
  /// In en, this message translates to:
  /// **'coach.'**
  String get welcomeTitleAccent;

  /// No description provided for @welcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Honest help with your profile, your messages and your first date, from a coach who listens.'**
  String get welcomeBody;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @valueConversations.
  ///
  /// In en, this message translates to:
  /// **'Better conversations'**
  String get valueConversations;

  /// No description provided for @valueProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile help'**
  String get valueProfile;

  /// No description provided for @valueDates.
  ///
  /// In en, this message translates to:
  /// **'First-date plans'**
  String get valueDates;

  /// No description provided for @welcomeFootnote.
  ///
  /// In en, this message translates to:
  /// **'AI coaches · For adults 18+ · English · Español'**
  String get welcomeFootnote;

  /// No description provided for @stepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String stepOf(int step, int total);

  /// No description provided for @goalsTitle.
  ///
  /// In en, this message translates to:
  /// **'What would you like help with?'**
  String get goalsTitle;

  /// No description provided for @goalsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick up to three. They become your plan for the week.'**
  String get goalsSubtitle;

  /// No description provided for @goalConversations.
  ///
  /// In en, this message translates to:
  /// **'Better conversations'**
  String get goalConversations;

  /// No description provided for @goalProfile.
  ///
  /// In en, this message translates to:
  /// **'A stronger profile'**
  String get goalProfile;

  /// No description provided for @goalDates.
  ///
  /// In en, this message translates to:
  /// **'Great first dates'**
  String get goalDates;

  /// No description provided for @goalConfidence.
  ///
  /// In en, this message translates to:
  /// **'More confidence'**
  String get goalConfidence;

  /// No description provided for @goalRelationship.
  ///
  /// In en, this message translates to:
  /// **'A healthier relationship'**
  String get goalRelationship;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get languageTitle;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The app and your coaches will use it. You can change it any time in the You tab.'**
  String get languageSubtitle;

  /// No description provided for @ageTitle.
  ///
  /// In en, this message translates to:
  /// **'DateWise is for adults.'**
  String get ageTitle;

  /// No description provided for @ageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your age to continue.'**
  String get ageSubtitle;

  /// No description provided for @ageConfirm.
  ///
  /// In en, this message translates to:
  /// **'I am 18 or older'**
  String get ageConfirm;

  /// No description provided for @ageUnder.
  ///
  /// In en, this message translates to:
  /// **'I am under 18'**
  String get ageUnder;

  /// No description provided for @underageTitle.
  ///
  /// In en, this message translates to:
  /// **'Sorry, DateWise is only for adults.'**
  String get underageTitle;

  /// No description provided for @underageBody.
  ///
  /// In en, this message translates to:
  /// **'You need to be 18 or older to use DateWise AI.'**
  String get underageBody;

  /// No description provided for @underageClose.
  ///
  /// In en, this message translates to:
  /// **'You can close the app now.'**
  String get underageClose;

  /// No description provided for @chooseCoachTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your dating coach'**
  String get chooseCoachTitle;

  /// No description provided for @chooseCoachSubtitle.
  ///
  /// In en, this message translates to:
  /// **'All four are AI coaches. Pick a style; switch any time.'**
  String get chooseCoachSubtitle;

  /// No description provided for @coachesEyebrow.
  ///
  /// In en, this message translates to:
  /// **'AI dating coaches'**
  String get coachesEyebrow;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning.'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon.'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening.'**
  String get greetingEvening;

  /// No description provided for @homeReady.
  ///
  /// In en, this message translates to:
  /// **'{name} is ready when you are. Your AI coach, any time.'**
  String homeReady(String name, String gender);

  /// No description provided for @homeResume.
  ///
  /// In en, this message translates to:
  /// **'{name} is ready when you are. Pick up where you left off: “{title}”'**
  String homeResume(String name, String gender, String title);

  /// No description provided for @talkTo.
  ///
  /// In en, this message translates to:
  /// **'Talk to {name}'**
  String talkTo(String name);

  /// No description provided for @voiceChatWith.
  ///
  /// In en, this message translates to:
  /// **'Voice chat with {name}'**
  String voiceChatWith(String name);

  /// No description provided for @planThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Your plan this week'**
  String get planThisWeek;

  /// No description provided for @planDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get planDone;

  /// No description provided for @planNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get planNext;

  /// No description provided for @planNotYet.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get planNotYet;

  /// No description provided for @planItemConversations.
  ///
  /// In en, this message translates to:
  /// **'Practice an opener with {name}'**
  String planItemConversations(String name);

  /// No description provided for @planItemProfile.
  ///
  /// In en, this message translates to:
  /// **'Rewrite your bio with {name}'**
  String planItemProfile(String name);

  /// No description provided for @planItemDates.
  ///
  /// In en, this message translates to:
  /// **'Plan a first date'**
  String get planItemDates;

  /// No description provided for @planItemConfidence.
  ///
  /// In en, this message translates to:
  /// **'Talk through what makes you nervous'**
  String get planItemConfidence;

  /// No description provided for @planItemRelationship.
  ///
  /// In en, this message translates to:
  /// **'Practice saying how you feel'**
  String get planItemRelationship;

  /// No description provided for @planPromptConversations.
  ///
  /// In en, this message translates to:
  /// **'Help me practice an opener for someone I matched with.'**
  String get planPromptConversations;

  /// No description provided for @planPromptProfile.
  ///
  /// In en, this message translates to:
  /// **'Rewrite my dating bio.'**
  String get planPromptProfile;

  /// No description provided for @planPromptDates.
  ///
  /// In en, this message translates to:
  /// **'Help me plan a great first date.'**
  String get planPromptDates;

  /// No description provided for @planPromptConfidence.
  ///
  /// In en, this message translates to:
  /// **'I get nervous before dates. Can you help?'**
  String get planPromptConfidence;

  /// No description provided for @planPromptRelationship.
  ///
  /// In en, this message translates to:
  /// **'Help me tell my partner how I feel.'**
  String get planPromptRelationship;

  /// No description provided for @quickPractice.
  ///
  /// In en, this message translates to:
  /// **'Practice a conversation'**
  String get quickPractice;

  /// No description provided for @quickPracticePrompt.
  ///
  /// In en, this message translates to:
  /// **'Let\'s practice a conversation. You play my match and I\'ll reply.'**
  String get quickPracticePrompt;

  /// No description provided for @quickProfile.
  ///
  /// In en, this message translates to:
  /// **'Improve my profile'**
  String get quickProfile;

  /// No description provided for @quickProfilePrompt.
  ///
  /// In en, this message translates to:
  /// **'Help me improve my dating profile.'**
  String get quickProfilePrompt;

  /// No description provided for @quickDate.
  ///
  /// In en, this message translates to:
  /// **'Prepare for a date'**
  String get quickDate;

  /// No description provided for @quickDatePrompt.
  ///
  /// In en, this message translates to:
  /// **'Help me prepare for a date.'**
  String get quickDatePrompt;

  /// No description provided for @quickReply.
  ///
  /// In en, this message translates to:
  /// **'Help me reply'**
  String get quickReply;

  /// No description provided for @quickReplyPrompt.
  ///
  /// In en, this message translates to:
  /// **'Help me reply to a message.'**
  String get quickReplyPrompt;

  /// No description provided for @voicePermissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Voice needs microphone and speech recognition access. You can allow it in Settings.'**
  String get voicePermissionNeeded;

  /// No description provided for @voiceUnavailableNote.
  ///
  /// In en, this message translates to:
  /// **'Voice isn\'t available on this device. You can type to {name}.'**
  String voiceUnavailableNote(String name);

  /// No description provided for @newConversation.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get newConversation;

  /// No description provided for @pastConversationsWith.
  ///
  /// In en, this message translates to:
  /// **'Past conversations with {name}'**
  String pastConversationsWith(String name);

  /// No description provided for @switchCoach.
  ///
  /// In en, this message translates to:
  /// **'Switch coach'**
  String get switchCoach;

  /// No description provided for @noSavedConversations.
  ///
  /// In en, this message translates to:
  /// **'No saved conversations yet.'**
  String get noSavedConversations;

  /// No description provided for @conversationsWith.
  ///
  /// In en, this message translates to:
  /// **'Conversations with {name}'**
  String conversationsWith(String name);

  /// No description provided for @deleteConversation.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation'**
  String get deleteConversation;

  /// No description provided for @conversationOptions.
  ///
  /// In en, this message translates to:
  /// **'Conversation options'**
  String get conversationOptions;

  /// No description provided for @voiceSession.
  ///
  /// In en, this message translates to:
  /// **'Voice session · {elapsed}'**
  String voiceSession(String elapsed);

  /// No description provided for @hideCaptions.
  ///
  /// In en, this message translates to:
  /// **'Hide captions'**
  String get hideCaptions;

  /// No description provided for @showCaptions.
  ///
  /// In en, this message translates to:
  /// **'Show captions'**
  String get showCaptions;

  /// No description provided for @coachTyping.
  ///
  /// In en, this message translates to:
  /// **'{name} is typing'**
  String coachTyping(String name);

  /// No description provided for @coachSays.
  ///
  /// In en, this message translates to:
  /// **'{name}: {text}'**
  String coachSays(String name, String text);

  /// No description provided for @youSaid.
  ///
  /// In en, this message translates to:
  /// **'You: {text}'**
  String youSaid(String text);

  /// No description provided for @copyReply.
  ///
  /// In en, this message translates to:
  /// **'Copy {label} reply: {text}'**
  String copyReply(String label, String text);

  /// No description provided for @copiedReply.
  ///
  /// In en, this message translates to:
  /// **'Copied. Paste it into your dating app.'**
  String get copiedReply;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Message {name}…'**
  String messageHint(String name);

  /// No description provided for @voiceMode.
  ///
  /// In en, this message translates to:
  /// **'Voice mode'**
  String get voiceMode;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @stopReply.
  ///
  /// In en, this message translates to:
  /// **'Stop reply'**
  String get stopReply;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get listening;

  /// No description provided for @typeInstead.
  ///
  /// In en, this message translates to:
  /// **'Type instead'**
  String get typeInstead;

  /// No description provided for @holdToTalk.
  ///
  /// In en, this message translates to:
  /// **'Hold to talk'**
  String get holdToTalk;

  /// No description provided for @stopReadingAloud.
  ///
  /// In en, this message translates to:
  /// **'Stop reading replies aloud'**
  String get stopReadingAloud;

  /// No description provided for @readAloud.
  ///
  /// In en, this message translates to:
  /// **'Read replies aloud'**
  String get readAloud;

  /// No description provided for @holdToTalkFooter.
  ///
  /// In en, this message translates to:
  /// **'Hold to talk · {name} is an AI coach'**
  String holdToTalkFooter(String name, String gender);

  /// No description provided for @tapToTalkFooter.
  ///
  /// In en, this message translates to:
  /// **'Tap to talk · {name} is an AI coach'**
  String tapToTalkFooter(String name, String gender);

  /// No description provided for @premiumEyebrow.
  ///
  /// In en, this message translates to:
  /// **'DateWise Premium'**
  String get premiumEyebrow;

  /// No description provided for @lockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat with {name} is part of DateWise Premium.'**
  String lockedTitle(String name);

  /// No description provided for @lockedBody.
  ///
  /// In en, this message translates to:
  /// **'Subscribe to talk with all four AI coaches. Your conversations stay on this device.'**
  String get lockedBody;

  /// No description provided for @seePremium.
  ///
  /// In en, this message translates to:
  /// **'See DateWise Premium'**
  String get seePremium;

  /// No description provided for @chatErrorUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach your coach. Check your connection and try again. Your message is saved.'**
  String get chatErrorUnavailable;

  /// No description provided for @chatErrorBusy.
  ///
  /// In en, this message translates to:
  /// **'Your coach is getting a lot of messages right now. Try again in a moment. Your message is saved.'**
  String get chatErrorBusy;

  /// No description provided for @chatErrorOffline.
  ///
  /// In en, this message translates to:
  /// **'You seem to be offline. Check your connection and try again. Your message is saved.'**
  String get chatErrorOffline;

  /// No description provided for @chatErrorServer.
  ///
  /// In en, this message translates to:
  /// **'Coaching is temporarily unavailable. Try again in a few minutes. Your message is saved.'**
  String get chatErrorServer;

  /// No description provided for @chatErrorStopped.
  ///
  /// In en, this message translates to:
  /// **'The reply was stopped. Your message is saved.'**
  String get chatErrorStopped;

  /// No description provided for @paywallHeadline.
  ///
  /// In en, this message translates to:
  /// **'Everyday coaching with {name} and the team.'**
  String paywallHeadline(String name);

  /// No description provided for @benefitCoaches.
  ///
  /// In en, this message translates to:
  /// **'Chat with all four AI coaches, in English and Spanish'**
  String get benefitCoaches;

  /// No description provided for @benefitVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice practice: speak and hear replies on your device'**
  String get benefitVoice;

  /// No description provided for @benefitPlan.
  ///
  /// In en, this message translates to:
  /// **'Your weekly plan and progress, kept on your device'**
  String get benefitPlan;

  /// No description provided for @monthlyAutoRenews.
  ///
  /// In en, this message translates to:
  /// **'Monthly · auto-renews'**
  String get monthlyAutoRenews;

  /// No description provided for @perMonth.
  ///
  /// In en, this message translates to:
  /// **'per month'**
  String get perMonth;

  /// No description provided for @pricePerMonth.
  ///
  /// In en, this message translates to:
  /// **'{price}/month'**
  String pricePerMonth(String price);

  /// No description provided for @subscribeFor.
  ///
  /// In en, this message translates to:
  /// **'Subscribe for {price}/month'**
  String subscribeFor(String price);

  /// No description provided for @paywallWebOnly.
  ///
  /// In en, this message translates to:
  /// **'Subscribe in the iPhone app. Purchases are not available on the web.'**
  String get paywallWebOnly;

  /// No description provided for @purchasePending.
  ///
  /// In en, this message translates to:
  /// **'Your purchase is pending approval. Chat unlocks as soon as it is approved.'**
  String get purchasePending;

  /// No description provided for @purchaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Purchase failed. Please try again.'**
  String get purchaseFailed;

  /// No description provided for @purchasesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Purchases are not available right now.'**
  String get purchasesUnavailable;

  /// No description provided for @storeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The App Store is not available right now.'**
  String get storeUnavailable;

  /// No description provided for @storeUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the App Store.'**
  String get storeUnreachable;

  /// No description provided for @productUnavailable.
  ///
  /// In en, this message translates to:
  /// **'DateWise Premium is not available in the store yet.'**
  String get productUnavailable;

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not restore purchases.'**
  String get restoreFailed;

  /// No description provided for @noSubscriptionForAppleId.
  ///
  /// In en, this message translates to:
  /// **'No active DateWise Premium subscription was found for this Apple Account.'**
  String get noSubscriptionForAppleId;

  /// No description provided for @reviewBuildNote.
  ///
  /// In en, this message translates to:
  /// **'Review build: purchases are simulated and nothing is charged.'**
  String get reviewBuildNote;

  /// No description provided for @paywallDisclosure.
  ///
  /// In en, this message translates to:
  /// **'{perMonth}. Payment is charged to your Apple Account at confirmation of purchase. The subscription renews automatically every month at {price} unless you cancel it at least 24 hours before the end of the current period. Cancel any time in Settings › [your name] › Subscriptions.'**
  String paywallDisclosure(String perMonth, String price);

  /// No description provided for @priceFromAppStore.
  ///
  /// In en, this message translates to:
  /// **'Price shown by the App Store'**
  String get priceFromAppStore;

  /// No description provided for @subscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscribe;

  /// Paywall line next to the disclosure. Numbers come from lib/config/fair_use.dart (the backend limits).
  ///
  /// In en, this message translates to:
  /// **'Fair use: up to {daily} coach replies a day and {monthly} a month, at most {perMinute} a minute and {concurrent} at a time. Typed and spoken messages count the same. A notice appears near a limit; at the limit, chat pauses until the next day (00:00 UTC) or month.'**
  String paywallFairUse(
    String daily,
    String monthly,
    String perMinute,
    String concurrent,
  );

  /// No description provided for @paywallDisclosureNoPrice.
  ///
  /// In en, this message translates to:
  /// **'Monthly subscription at the price shown by the App Store. Payment is charged to your Apple Account at confirmation of purchase. The subscription renews automatically every month at that price unless you cancel it at least 24 hours before the end of the current period. Cancel any time in Settings › [your name] › Subscriptions.'**
  String get paywallDisclosureNoPrice;

  /// No description provided for @tapToSend.
  ///
  /// In en, this message translates to:
  /// **'Stop and send'**
  String get tapToSend;

  /// No description provided for @tapToTalkHint.
  ///
  /// In en, this message translates to:
  /// **'Double-tap to start talking, then double-tap again to send'**
  String get tapToTalkHint;

  /// No description provided for @voiceRecognitionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition isn\'t available on this device right now. You can type your message instead.'**
  String get voiceRecognitionUnavailable;

  /// No description provided for @voiceLanguageUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Voice isn\'t available for this language on this device. You can type your message instead.'**
  String get voiceLanguageUnsupported;

  /// No description provided for @photoNoLongerAvailable.
  ///
  /// In en, this message translates to:
  /// **'Photo from an earlier version (no longer available)'**
  String get photoNoLongerAvailable;

  /// No description provided for @restorePurchases.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get restorePurchases;

  /// No description provided for @termsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get termsOfUse;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @privacyShort.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyShort;

  /// No description provided for @progressTitle.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progressTitle;

  /// No description provided for @progressSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Counted on this device from what you actually did.'**
  String get progressSubtitle;

  /// No description provided for @statConversations.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{conversation} other{conversations}}'**
  String statConversations(int count);

  /// No description provided for @statStreak.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day in a row} other{days in a row}}'**
  String statStreak(int count);

  /// No description provided for @statDaysUsed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day with a coach} other{days with a coach}}'**
  String statDaysUsed(int count);

  /// No description provided for @statPlanDone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{plan step done this week} other{plan steps done this week}}'**
  String statPlanDone(int count);

  /// No description provided for @noDaysYet.
  ///
  /// In en, this message translates to:
  /// **'No coaching days yet. Send {name} a message to start your streak.'**
  String noDaysYet(String name);

  /// No description provided for @daysTotal.
  ///
  /// In en, this message translates to:
  /// **'You\'ve talked with a coach on {count, plural, =1{1 day} other{{count} days}} in total.'**
  String daysTotal(int count);

  /// No description provided for @weekPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'This week’s plan'**
  String get weekPlanTitle;

  /// No description provided for @planCount.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} done'**
  String planCount(int done, int total);

  /// No description provided for @progressFootnote.
  ///
  /// In en, this message translates to:
  /// **'Check off plan items on Home. Checkmarks reset every Monday.'**
  String get progressFootnote;

  /// No description provided for @youTitle.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get youTitle;

  /// No description provided for @sectionCoaching.
  ///
  /// In en, this message translates to:
  /// **'Coaching'**
  String get sectionCoaching;

  /// No description provided for @languageRow.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageRow;

  /// No description provided for @yourCoachRow.
  ///
  /// In en, this message translates to:
  /// **'Your coach'**
  String get yourCoachRow;

  /// No description provided for @sectionMemory.
  ///
  /// In en, this message translates to:
  /// **'Coach memory'**
  String get sectionMemory;

  /// No description provided for @memoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Coach memory'**
  String get memoryTitle;

  /// No description provided for @memoryOn.
  ///
  /// In en, this message translates to:
  /// **'On: your note is sent with each message.'**
  String get memoryOn;

  /// No description provided for @memoryOff.
  ///
  /// In en, this message translates to:
  /// **'Off: no note is kept (turning it off deletes it) and coaches only see the current conversation.'**
  String get memoryOff;

  /// No description provided for @writeNote.
  ///
  /// In en, this message translates to:
  /// **'Write your note'**
  String get writeNote;

  /// No description provided for @yourNote.
  ///
  /// In en, this message translates to:
  /// **'Your note'**
  String get yourNote;

  /// No description provided for @clearMemory.
  ///
  /// In en, this message translates to:
  /// **'Clear memory'**
  String get clearMemory;

  /// No description provided for @clearMemoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Coach memory?'**
  String get clearMemoryTitle;

  /// No description provided for @clearMemoryBody.
  ///
  /// In en, this message translates to:
  /// **'Your note will be deleted from this device.'**
  String get clearMemoryBody;

  /// No description provided for @memoryOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off Coach memory?'**
  String get memoryOffTitle;

  /// No description provided for @memoryOffBody.
  ///
  /// In en, this message translates to:
  /// **'Your note will be deleted from this device, and coaches will only see the current conversation.'**
  String get memoryOffBody;

  /// No description provided for @memoryTurnOnTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn on Coach memory?'**
  String get memoryTurnOnTitle;

  /// No description provided for @memoryTurnOnBody.
  ///
  /// In en, this message translates to:
  /// **'Your note is kept only while Coach memory is on. It will then be sent to your coach with each message.'**
  String get memoryTurnOnBody;

  /// Confirm button when saving a Coach memory note while memory is off: turns memory on and saves.
  ///
  /// In en, this message translates to:
  /// **'Turn on & save'**
  String get memoryTurnOnAction;

  /// Confirm button when turning Coach memory off: it deletes the note.
  ///
  /// In en, this message translates to:
  /// **'Turn off & delete'**
  String get memoryOffAction;

  /// No description provided for @memorySheetBody.
  ///
  /// In en, this message translates to:
  /// **'A short note your coaches see with each message while Coach memory is on. Write only what you are happy to share.'**
  String get memorySheetBody;

  /// No description provided for @memoryHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. I am 31, shy at first, on Hinge, looking for something serious.'**
  String get memoryHint;

  /// No description provided for @sectionSubscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get sectionSubscription;

  /// No description provided for @subActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get subActive;

  /// No description provided for @subNone.
  ///
  /// In en, this message translates to:
  /// **'Not subscribed'**
  String get subNone;

  /// No description provided for @manageSubscription.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get manageSubscription;

  /// No description provided for @restorePurchasesRow.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get restorePurchasesRow;

  /// No description provided for @restoreOk.
  ///
  /// In en, this message translates to:
  /// **'DateWise Premium is active.'**
  String get restoreOk;

  /// No description provided for @restoreNone.
  ///
  /// In en, this message translates to:
  /// **'No active subscription found.'**
  String get restoreNone;

  /// No description provided for @sectionData.
  ///
  /// In en, this message translates to:
  /// **'Your data'**
  String get sectionData;

  /// No description provided for @deleteAllConversations.
  ///
  /// In en, this message translates to:
  /// **'Delete all conversations'**
  String get deleteAllConversations;

  /// No description provided for @deleteAllConversationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete all conversations?'**
  String get deleteAllConversationsTitle;

  /// No description provided for @deleteAllConversationsBody.
  ///
  /// In en, this message translates to:
  /// **'Every conversation with every coach will be deleted from this device.'**
  String get deleteAllConversationsBody;

  /// No description provided for @deleteMyData.
  ///
  /// In en, this message translates to:
  /// **'Delete my data'**
  String get deleteMyData;

  /// No description provided for @deleteMyDataNote.
  ///
  /// In en, this message translates to:
  /// **'Does not cancel your subscription. Cancel it in Apple settings.'**
  String get deleteMyDataNote;

  /// No description provided for @deleteMyDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete all your data?'**
  String get deleteMyDataTitle;

  /// No description provided for @deleteMyDataBody.
  ///
  /// In en, this message translates to:
  /// **'Conversations, plan, progress, Coach memory and settings will be erased from this device, and the app will start again.\n\nYour subscription is managed by Apple and stays active: deleting your data does not cancel it. To cancel it, go to Settings › [your name] › Subscriptions.'**
  String get deleteMyDataBody;

  /// No description provided for @deleteEverything.
  ///
  /// In en, this message translates to:
  /// **'Delete everything'**
  String get deleteEverything;

  /// No description provided for @sectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get sectionAbout;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// No description provided for @couldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'Could not open {url}'**
  String couldNotOpen(String url);

  /// No description provided for @settingsFootnote.
  ///
  /// In en, this message translates to:
  /// **'Your coaches are AI. Conversations are stored on this device.'**
  String get settingsFootnote;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'DateWise AI {version}'**
  String appVersion(String version);

  /// No description provided for @legalTranslationNote.
  ///
  /// In en, this message translates to:
  /// **''**
  String get legalTranslationNote;

  /// Chat notice: the server's daily fair-use cap (DAILY_LIMIT).
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached today\'s coaching limit. It resets at midnight (UTC).'**
  String get coachLimitDaily;

  /// Chat notice: the monthly fair-use cap (MONTHLY_LIMIT).
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached this month\'s fair-use limit. It resets on the 1st.'**
  String get coachLimitMonthly;

  /// Chat notice: RATE_LIMITED or CONCURRENCY_LIMIT.
  ///
  /// In en, this message translates to:
  /// **'You\'re sending messages quickly. Please wait a moment and try again.'**
  String get coachLimitSlowDown;

  /// Chat notice: SERVICE_BUDGET_EXHAUSTED or GUARD_UNAVAILABLE.
  ///
  /// In en, this message translates to:
  /// **'Coaching is busy right now. Please try again later.'**
  String get coachLimitBusy;

  /// Chat notice: SUBSCRIPTION_EXPIRED or SUBSCRIPTION_REQUIRED.
  ///
  /// In en, this message translates to:
  /// **'Your DateWise Premium subscription isn\'t active. Renew it to keep chatting.'**
  String get coachLimitSubscriptionInactive;

  /// Chat notice: SUBSCRIPTION_REVOKED.
  ///
  /// In en, this message translates to:
  /// **'This purchase was refunded or revoked, so coaching is locked.'**
  String get coachLimitRevoked;

  /// Chat notice: SUBSCRIPTION_INVALID.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm your subscription. Tap Restore purchases.'**
  String get coachLimitVerify;

  /// Chat notice: APP_UPDATE_REQUIRED.
  ///
  /// In en, this message translates to:
  /// **'Update DateWise to the latest version to keep chatting with your coach.'**
  String get coachLimitUpdateApp;

  /// Soft notice before the daily cap.
  ///
  /// In en, this message translates to:
  /// **'You\'re close to today\'s fair-use limit.'**
  String get coachUsageNoticeDaily;

  /// Soft notice before the monthly cap.
  ///
  /// In en, this message translates to:
  /// **'You\'re close to this month\'s fair-use limit.'**
  String get coachUsageNoticeMonthly;

  /// Voice stage: accessibility label of the animated coach portrait (idle).
  ///
  /// In en, this message translates to:
  /// **'{name}, animated AI coach'**
  String avatarAnimated(String name);

  /// Voice stage: animated coach while the reply is read aloud (lip-synced).
  ///
  /// In en, this message translates to:
  /// **'{name}, animated AI coach, speaking'**
  String avatarSpeaking(String name);

  /// Voice stage: animated coach while the user talks.
  ///
  /// In en, this message translates to:
  /// **'{name}, animated AI coach, listening'**
  String avatarListening(String name);

  /// Voice stage: animated coach while the reply is being written.
  ///
  /// In en, this message translates to:
  /// **'{name}, animated AI coach, thinking'**
  String avatarThinking(String name);

  /// Settings row that opens the Premium-voice tip.
  ///
  /// In en, this message translates to:
  /// **'More natural coach voices'**
  String get voiceQualityRow;

  /// Premium-voice tip: title.
  ///
  /// In en, this message translates to:
  /// **'Get more natural voices'**
  String get voiceQualityTitle;

  /// Premium-voice tip: steps (iOS Settings path).
  ///
  /// In en, this message translates to:
  /// **'Coaches speak with your iPhone\'s own voices, on your device. For the most natural sound, download one of Apple\'s Premium or Enhanced voices:\n\n1. Open the Settings app › Accessibility › Spoken Content › Voices.\n2. Choose English or Spanish.\n3. Download a voice marked Premium or Enhanced (for example Ava or Zoe, Evan or Nathan, Paulina or Juan).\n\nDateWise uses it automatically the next time a coach speaks. Each coach keeps a distinct voice when several are installed.'**
  String get voiceQualityBody;

  /// Premium-voice tip: close button.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get voiceQualityDone;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
