/// How fast the system voices speak at a flutter_tts speech rate, as a model
/// shared by the coach profiles and the lip-sync plan.
///
/// flutter_tts passes the rate straight to AVSpeechUtterance.rate on iOS
/// (0..1, 0.5 is AVSpeechUtteranceDefaultSpeechRate) and to Android's
/// setSpeechRate as rate * 2 (0.5 is the normal 1.0). On both, 0.5 is the
/// platform's default pace.
///
/// ASSUMPTION (needs a device to confirm): the default pace is about 170
/// words a minute of speech (pauses excluded) and the rate is close to linear
/// around it, about 3 words a minute per 0.01 of rate. Real voices differ
/// (compact voices run faster than Enhanced and Premium ones).
class SpeechPace {
  SpeechPace._();

  static const double defaultRate = 0.5;
  static const double wordsPerMinuteAtDefault = 170;
  static const double wordsPerMinutePerRateStep = 300; // per 1.0 of rate

  /// Letters spoken per second at the default rate (calibrated so the sample English replies in test/support come out at the 170 words a minute above).
  static const double lettersPerSecondAtDefault = 12.0;

  /// Words a minute of speech (pauses excluded) at [rate], for average
  /// English text.
  static double wordsPerMinute(double rate) =>
      wordsPerMinuteAtDefault + wordsPerMinutePerRateStep * (rate.clamp(0.1, 1.0) - defaultRate);

  /// Letters per second at [rate].
  static double lettersPerSecond(double rate) =>
      lettersPerSecondAtDefault * wordsPerMinute(rate) / wordsPerMinuteAtDefault;
}
