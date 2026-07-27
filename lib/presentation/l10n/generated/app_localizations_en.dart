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
}
