// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Massrofy';

  @override
  String get lockGateUnlockToView => 'Unlock to view your data';

  @override
  String get lockGateBiometricHint => 'Place your finger on the sensor';

  @override
  String get lockGateUsePinInstead => 'Use PIN instead';

  @override
  String get lockGateUsePasscode => 'Use device passcode instead';

  @override
  String get lockGateAuthFailed => 'Authentication failed. Try again.';

  @override
  String get lockGateEnterPin => 'Enter PIN';

  @override
  String get lockGateTooManyAttempts => 'Too many attempts';

  @override
  String lockGateRetryIn(String seconds) {
    return 'Try again in $seconds, or use PIN';
  }

  @override
  String get lockGateSessionExpiredBanner =>
      'Your session ended while the app was in the background. Unlock again to continue where you left off.';

  @override
  String get lockGateContinueUnlock => 'Unlock to continue';

  @override
  String get lockGateUnlockButtonSemanticLabel => 'Unlock with biometrics';

  @override
  String get homePlaceholderTitle => 'Home';

  @override
  String get homePlaceholderBody =>
      'This is the Massrofy foundation build. SMS ingestion, categorisation, and reporting are built in later phases — this screen only proves the app launches, unlocks, and reads/writes its encrypted store correctly.';

  @override
  String get smsRationaleTitle => 'Why Massrofy needs SMS access';

  @override
  String get smsRationaleLead =>
      'Your bank sends transaction alerts by SMS. Massrofy reads only those messages, on your device, to build a picture of your spending.';

  @override
  String get smsRationalePointOnDevice =>
      'Everything is processed on your phone';

  @override
  String get smsRationalePointNoSharing =>
      'No data is sent to us or to anyone else';

  @override
  String get smsRationalePointRevocable => 'You can revoke access at any time';

  @override
  String get smsRationalePointNoiseIgnored =>
      'Non-financial messages are ignored and never stored';

  @override
  String get smsRationaleGrant => 'Grant SMS access';

  @override
  String get smsRationaleNotNow => 'Not now';

  @override
  String get smsLimitedModeTitle => 'Limited mode is on';

  @override
  String get smsLimitedModeBody =>
      'Without SMS access, transactions will not be added automatically. Any data you already have is still intact, and you can add transactions manually at any time.';

  @override
  String get smsLimitedModeOpenSettings => 'Open system settings';

  @override
  String get smsLimitedModeTryAgain => 'Grant SMS access';

  @override
  String get smsLimitedModeAddManually => 'Add a transaction manually';

  @override
  String get smsRevokedBannerTitle => 'SMS access was turned off';

  @override
  String get importProgressTitle => 'Importing your messages';

  @override
  String importProgressFound(int count) {
    return '$count transactions found so far…';
  }

  @override
  String get importProgressContinueInBackground => 'Continue in the background';

  @override
  String get importProgressScopeNote =>
      'Massrofy imports messages from the start of this month.';

  @override
  String get needsReviewTitle => 'Needs review';

  @override
  String needsReviewTabUnparsed(int count) {
    return 'Not understood ($count)';
  }

  @override
  String needsReviewTabLowConfidence(int count) {
    return 'Low confidence ($count)';
  }

  @override
  String get needsReviewEmpty => 'Nothing needs review right now';

  @override
  String get needsReviewEmptyBody =>
      'Every message and transaction is understood and categorised.';

  @override
  String get needsReviewFillInDetails => 'Fill in details';

  @override
  String get needsReviewNotATransaction => 'Not a transaction';

  @override
  String needsReviewReceivedFrom(String time, String sender) {
    return 'Received $time · From: $sender';
  }

  @override
  String get needsReviewPossibleDuplicate => 'Possible duplicate';

  @override
  String get needsReviewReasonNoRule =>
      'This message did not match any known format';

  @override
  String get needsReviewReasonMissingField =>
      'Some details were missing from this message';
}
