/// In-app legal copy for DateWise AI's Privacy Policy, Terms of Service, and
/// Disclaimer. Kept in sync with the hosted pages (web/privacy.html,
/// web/terms.html) so the in-app text matches datewiseai.com.
///
/// Format: lines beginning with "# " render as section headings; everything
/// else is body text (see LegalScreen).
library;

const String kLegalLastUpdated = 'Last updated: 22 November 2026';

const String kPrivacyPolicy = '''
$kLegalLastUpdated

DateWise AI ("DateWise AI", "we", "us") provides an AI dating-coaching app with four AI coaches. This policy explains what information the app handles, how it is used, and your choices. DateWise AI is intended only for adults aged 18 and over.

# Information you provide
- No account: DateWise AI has no sign-in and no account. We do not collect your name, email address or password.
- Your coaching preferences: During setup you choose what you want help with, your coaching language and your coach, and you confirm you are 18 or older. These are used only to personalize the coaching.
- Coaching content: The messages you send to your AI coach, typed or spoken.
- Coach memory (optional, off by default): If you turn it on, a short note you write is sent with your messages so your coach can take it into account. You can view, edit or clear it in You › Coach memory.

# Information stored on your device
- Your conversations, preferences, weekly plan, progress counts and Coach memory note are stored locally on your device and are not uploaded to us.

# How we use information
- To provide AI coaching: your messages, your coaching preferences and (only when Coach memory is on) your note are sent to our AI processing provider to generate replies, which are returned to you.
- To operate, secure, and improve the app.
- We do not sell your personal information, do not use your messages to train AI models, and the app contains no advertising, analytics, or tracking.

# Voice
- Voice mode uses your device's built-in speech recognition to turn what you say into text while you hold the talk button; only the resulting text is sent to your coach. Replies are read aloud with your device's built-in voices.
- The microphone is used only while you hold the talk button. Voice features need your permission and can be turned off in your device settings.

# How your messages are handled
- Messages are transmitted securely to our AI processing provider, processed to generate a reply, and the reply is returned to your device. They are processed transiently and are not stored on our servers.

# Subscriptions
- DateWise Premium is purchased and managed through Apple. Apple processes the payment; we do not receive your payment details. The app checks your subscription status with Apple on your device.

# Service providers
- Cloudflare (Workers AI) generates the AI coaching replies; inputs are processed to return a reply and are not used to train models.
- Apple processes subscriptions and provides on-device speech recognition and voices.
- These providers process data only to provide their service to us.

# Data retention and deletion
- On-device data remains until you delete it: You › Delete all conversations, You › Delete my data (erases everything DateWise stored on the device), or uninstalling the app.
- Messages sent for a reply are not retained on our servers after processing.

# Security
All data in transit uses encrypted (HTTPS) connections. No method of transmission or storage is 100% secure, but we take reasonable measures to protect your information.

# International processing
Our providers may process information on servers located in various countries. By using the app you consent to this processing.

# Children
DateWise AI is for users aged 18 and older. We do not knowingly collect data from anyone under 18. If you believe a minor has used the app, contact us.

# Your choices
Your data stays on your device and you can delete it at any time in the app. Depending on where you live, you may have rights to access, correct, or delete your personal information; email support@datewiseai.com.

# Changes to this policy
We may update this policy from time to time. We will revise the "Last updated" date above, and significant changes will be reflected in the app.

# Contact
Questions about privacy or this policy: support@datewiseai.com
Website: https://datewiseai.com
''';

const String kTermsOfService = '''
$kLegalLastUpdated

By using DateWise AI you agree to these terms. DateWise AI is for adults aged 18 and over.

# The service
DateWise AI provides AI-generated dating and profile coaching for informational and entertainment purposes.

# Not professional advice
Suggestions are automated and are not a substitute for professional relationship, psychological, legal, or medical advice. Suggestions are AI opinions, not guarantees; outcomes such as matches, dates, or responses are not promised.

# AI coaches
Ava, Ethan, Sofía and Diego are AI coaches, not people. Their portraits are illustrations of the coach characters.

# Subscription
Coaching chat requires DateWise Premium, an auto-renewable monthly subscription. The price is shown in the app before you buy. Payment is charged to your Apple ID at confirmation of purchase. The subscription renews automatically each month unless canceled at least 24 hours before the end of the current period. You can manage or cancel it any time in Settings › Apple ID › Subscriptions. There is no free plan and no free trial.

# Acceptable use
Don't upload content you don't have the right to share, and don't use the service for unlawful purposes.

# Your content
You keep ownership of the content you submit. You grant us permission to process it solely to provide the service.

# Availability
The service may change or be unavailable at times and depends on third-party AI providers.

# Changes
We may update these terms; continued use means you accept the changes.

# Contact
Questions about these terms: support@datewiseai.com
''';

const String kDisclaimer = '''
$kLegalLastUpdated

# Not professional advice
DateWise AI provides automated suggestions for entertainment and informational
purposes only. It is not a substitute for professional relationship,
psychological, legal, or medical advice.

# AI-generated content
Feedback, scores, and "match-rate" estimates are generated by AI and may be
inaccurate or inconsistent. They are opinions, not guarantees, and outcomes
(matches, dates, responses) are not promised.

# Your responsibility
You are responsible for how you use the suggestions, the photos and information
you choose to share on dating platforms, and your interactions with others.

# Availability
The service may change or be unavailable at times and depends on third-party AI
providers.
''';
