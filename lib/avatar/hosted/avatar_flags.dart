import 'package:flutter/foundation.dart';

/// Switches for the hosted live avatar pilot. Everything is OFF by default, so
/// a normal build behaves exactly as before (the frame-based avatar).
///
///  * `--dart-define=AVATAR_HOSTED=true`  compiles the live avatar in as an option.
///  * `--dart-define=AVATAR_CONSENT_COPY_APPROVED=true` only after the owner has
///    approved the second AI-sharing consent text (lib/l10n avatarConsent*). Until
///    then the consent dialog is never shown, nothing is ever sent to the vendor
///    and the stage keeps the frame avatar.
///  * `--dart-define=AVATAR_VENDOR_NAME=Simli` names the vendor in the consent
///    text (use `Anam` for the second pilot).
///  * [remoteKill] is the hook for a later remote config: setting it to false
///    turns the hosted avatar off at runtime. It can only switch off, never on.
///
/// The Worker has its own switch (AVATAR_PROVIDER, default 'off').
class AvatarFlags {
  const AvatarFlags({this.hosted = false, this.consentCopyApproved = false, this.vendorName = 'Simli'});

  /// The flags this build was compiled with.
  factory AvatarFlags.fromBuild() => const AvatarFlags(
        hosted: bool.fromEnvironment('AVATAR_HOSTED'),
        consentCopyApproved: bool.fromEnvironment('AVATAR_CONSENT_COPY_APPROVED'),
        vendorName: String.fromEnvironment('AVATAR_VENDOR_NAME', defaultValue: 'Simli'),
      );

  final bool hosted;
  final bool consentCopyApproved;
  final String vendorName;

  /// Runtime kill switch (null or true: no effect; false: hosted avatar off).
  static final ValueNotifier<bool?> remoteKill = ValueNotifier<bool?>(null);

  bool get hostedEnabled => hosted && remoteKill.value != false;

  /// The pilot debug screen exists only in debug builds and in TestFlight
  /// builds pointed at a non-production coach backend, and only with the flag.
  bool pilotScreenAvailable({required bool testBuild}) => hostedEnabled && (kDebugMode || testBuild);
}
