import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
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
    Locale('ar'),
    Locale('en'),
  ];

  /// The app name, shown as the wordmark on the lock gate and as the OS task label. Never translated — brand.md §4.4 fixes both the English and Arabic wordmark forms as literals, not a translated string, but it still lives in .arb so every screen references one source of truth.
  ///
  /// In en, this message translates to:
  /// **'Massrofy'**
  String get appTitle;

  /// Lock gate headline shown above the biometric prompt (docs/mockups/lock-gate.html, idle state).
  ///
  /// In en, this message translates to:
  /// **'Unlock to view your data'**
  String get lockGateUnlockToView;

  /// Lock gate subtitle under the biometric icon.
  ///
  /// In en, this message translates to:
  /// **'Place your finger on the sensor'**
  String get lockGateBiometricHint;

  /// Link/button offering the PIN fallback when biometrics are available but the user prefers not to use them.
  ///
  /// In en, this message translates to:
  /// **'Use PIN instead'**
  String get lockGateUsePinInstead;

  /// Link/button offering the OS device-credential fallback (BIOMETRIC_STRONG|DEVICE_CREDENTIAL, ADR-005).
  ///
  /// In en, this message translates to:
  /// **'Use device passcode instead'**
  String get lockGateUsePasscode;

  /// Generic failure banner (ADR-005: the message is deliberately generic, never revealing which factor or why, and never revealing any data).
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Try again.'**
  String get lockGateAuthFailed;

  /// Headline for the PIN-entry fallback state.
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get lockGateEnterPin;

  /// Headline for the locked-out state after repeated failed attempts (ADR-005 exponential backoff).
  ///
  /// In en, this message translates to:
  /// **'Too many attempts'**
  String get lockGateTooManyAttempts;

  /// Locked-out countdown message.
  ///
  /// In en, this message translates to:
  /// **'Try again in {seconds}, or use PIN'**
  String lockGateRetryIn(String seconds);

  /// Banner shown when re-locked after AppLifecycleState.paused past the grace period (ADR-005 re-lock policy).
  ///
  /// In en, this message translates to:
  /// **'Your session ended while the app was in the background. Unlock again to continue where you left off.'**
  String get lockGateSessionExpiredBanner;

  /// Headline shown together with the session-expired banner.
  ///
  /// In en, this message translates to:
  /// **'Unlock to continue'**
  String get lockGateContinueUnlock;

  /// Screen-reader label for the biometric icon/button (NFR-U2).
  ///
  /// In en, this message translates to:
  /// **'Unlock with biometrics'**
  String get lockGateUnlockButtonSemanticLabel;

  /// Placeholder home screen shown after unlock in this P1 foundation build; replaced by the real dashboard (S-08) in a later phase.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homePlaceholderTitle;

  /// Explanatory copy for the placeholder home screen.
  ///
  /// In en, this message translates to:
  /// **'This is the Massrofy foundation build. SMS ingestion, categorisation, and reporting are built in later phases — this screen only proves the app launches, unlocks, and reads/writes its encrypted store correctly.'**
  String get homePlaceholderBody;
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
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
