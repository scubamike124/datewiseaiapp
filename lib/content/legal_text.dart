/// In-app legal copy for DateWise AI's Privacy Policy, Terms of Service, and
/// Disclaimer. Kept in sync with the hosted pages (web/privacy.html,
/// web/terms.html) so the in-app text matches datewiseai.com.
///
/// Format: lines beginning with "# " render as section headings; everything
/// else is body text (see LegalScreen).
library;

const String kLegalLastUpdated = 'Last updated: 13 June 2026';

const String kPrivacyPolicy = '''
$kLegalLastUpdated

DateWise AI ("DateWise AI", "we", "us") provides an AI dating-coaching app that helps you improve your dating profile, photos, and messaging. This policy explains what information the app handles, how it is used, and your choices. DateWise AI is intended only for adults aged 18 and over.

# Information you provide
- Account information (optional): If you create an account, we collect your email address, a password (stored and managed securely by our authentication provider), an optional display name, and an optional profile picture. The app is fully usable without an account.
- Your dating profile details: During setup you may tell us your gender, age, who you're interested in, your dating goal, which dating app you use, and optionally your city. These are used only to personalize the coaching.
- Coaching content: The messages you send to the AI coach and any photos you upload for feedback.

# Information stored on your device
- Your conversations, preferences, profile details, and photo-analysis results are stored locally on your device. Without an account, this information stays on your device and is not uploaded to us.

# How we use information
- To provide AI coaching: your messages, photos, and profile details are sent to our AI processing provider to generate feedback and replies, which are returned to you.
- To provide optional accounts: your email, display name, and profile picture create and manage your account and remember preferences across devices.
- To operate, secure, and improve the app.
- We do not sell your personal information, do not use your photos or messages to train AI models, and the app contains no advertising, analytics, or tracking.

# How your photos and messages are handled
- Photos and messages are transmitted securely to our AI processing provider, processed to generate feedback, and the result is returned to your device. They are processed transiently and are not stored on our servers.
- Photo-analysis results are cached on your device so the same photo isn't analyzed twice.
- If you upload a profile picture with an account, it is stored with your account until you change or delete it.

# Service providers
- Cloudflare (Workers AI) performs the AI photo and text analysis; inputs are processed to return feedback and are not used to train models.
- Supabase provides optional account sign-in and stores account data (email, display name, profile picture, selected plan) when you create an account.
- These providers process data only to provide their service to us.

# Data retention and deletion
- On-device data remains until you delete it (clear conversations or uninstall the app).
- With an account, you can delete it anytime from Settings → Delete account: this clears device data, deletes your plan record, and flags your account for removal. To request complete deletion of any remaining account data, email support@datewiseai.com.
- Photos and messages sent for analysis are not retained on our servers after processing.

# Security
All data in transit uses encrypted (HTTPS) connections; account data is protected by access controls at our providers. No method of transmission or storage is 100% secure, but we take reasonable measures to protect your information.

# International processing
Our providers may process and store information on servers located in various countries. By using the app you consent to this processing.

# Children
DateWise AI is for users aged 18 and older. We do not knowingly collect data from anyone under 18. If you believe a minor has used the app, contact us and we will delete the information.

# Your choices
You can use the app without an account, keeping your data on your device. You can edit your profile and delete your account and data at any time. Depending on where you live, you may have rights to access, correct, or delete your personal information — email support@datewiseai.com.

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
Suggestions are automated and are not a substitute for professional relationship, psychological, legal, or medical advice. Scores and "match-rate" estimates are AI opinions, not guarantees; outcomes such as matches, dates, or responses are not promised.

# Pricing
DateWise AI is currently free to use. If paid plans are introduced in a future update, they will be billed through your app store, where prices, renewal, and cancellation are managed.

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
