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

  /// S-02 headline (docs/mockups/onboarding.html). Shown BEFORE the OS permission dialog — design flag D-9, AC-A1.2.
  ///
  /// In en, this message translates to:
  /// **'Why Massrofy needs SMS access'**
  String get smsRationaleTitle;

  /// S-02 explanation card body.
  ///
  /// In en, this message translates to:
  /// **'Your bank sends transaction alerts by SMS. Massrofy reads only those messages, on your device, to build a picture of your spending.'**
  String get smsRationaleLead;

  /// S-02 guarantee bullet 1. Backed by ADR-001: the release build declares no INTERNET permission, so this is an OS-enforced property, not a promise.
  ///
  /// In en, this message translates to:
  /// **'Everything is processed on your phone'**
  String get smsRationalePointOnDevice;

  /// S-02 guarantee bullet 2 (AC-F4.2).
  ///
  /// In en, this message translates to:
  /// **'No data is sent to us or to anyone else'**
  String get smsRationalePointNoSharing;

  /// S-02 guarantee bullet 3.
  ///
  /// In en, this message translates to:
  /// **'You can revoke access at any time'**
  String get smsRationalePointRevocable;

  /// S-02 guarantee bullet 4. This is literally true per NFR-P4: a message from an unrecognised sender produces no database row at all.
  ///
  /// In en, this message translates to:
  /// **'Non-financial messages are ignored and never stored'**
  String get smsRationalePointNoiseIgnored;

  /// S-02 primary CTA — opens the OS permission dialog.
  ///
  /// In en, this message translates to:
  /// **'Grant SMS access'**
  String get smsRationaleGrant;

  /// S-02 secondary CTA. Declining leads to S-04 limited mode, never to a dead end.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get smsRationaleNotNow;

  /// S-04 headline. Covers both permission-declined and permission-revoked (AC-A1.2, AC-A1.3).
  ///
  /// In en, this message translates to:
  /// **'Limited mode is on'**
  String get smsLimitedModeTitle;

  /// S-04 body. The 'already have is still intact' half is required by AC-A1.3 — a user who fears their history is gone may reinstall, which would actually destroy it.
  ///
  /// In en, this message translates to:
  /// **'Without SMS access, transactions will not be added automatically. Any data you already have is still intact, and you can add transactions manually at any time.'**
  String get smsLimitedModeBody;

  /// S-04 primary CTA when the permission is permanently denied — the OS silently no-ops a re-request, so a deep link is the only honest offer.
  ///
  /// In en, this message translates to:
  /// **'Open system settings'**
  String get smsLimitedModeOpenSettings;

  /// S-04 primary CTA when the permission was merely declined and the OS dialog will still appear.
  ///
  /// In en, this message translates to:
  /// **'Grant SMS access'**
  String get smsLimitedModeTryAgain;

  /// S-04 fallback CTA — the app must never be a dead end (AC-A1.2).
  ///
  /// In en, this message translates to:
  /// **'Add a transaction manually'**
  String get smsLimitedModeAddManually;

  /// AC-A1.3 persistent banner shown on Home when access was granted and later revoked — including by Android 11+'s automatic permission reset for unused apps.
  ///
  /// In en, this message translates to:
  /// **'SMS access was turned off'**
  String get smsRevokedBannerTitle;

  /// S-05 headline (AC-A3.2).
  ///
  /// In en, this message translates to:
  /// **'Importing your messages'**
  String get importProgressTitle;

  /// S-05 live count.
  ///
  /// In en, this message translates to:
  /// **'{count} transactions found so far…'**
  String importProgressFound(int count);

  /// S-05 dismiss action. The import is non-blocking per NFR-R2/AC-A3.2 — the user is never trapped on this screen.
  ///
  /// In en, this message translates to:
  /// **'Continue in the background'**
  String get importProgressContinueInBackground;

  /// Sets the expectation set by AC-A3.1 (OQ-11 resolved: current calendar month, not full history) so an empty-looking result is not mistaken for a failure.
  ///
  /// In en, this message translates to:
  /// **'Massrofy imports messages from the start of this month.'**
  String get importProgressScopeNote;

  /// S-18 app-bar title.
  ///
  /// In en, this message translates to:
  /// **'Needs review'**
  String get needsReviewTitle;

  /// S-18 tab 1 — messages the parser could not turn into a transaction (US-A4). Kept separate from low-confidence items, which are a different problem with a different fix.
  ///
  /// In en, this message translates to:
  /// **'Not understood ({count})'**
  String needsReviewTabUnparsed(int count);

  /// S-18 tab 2 — parsed transactions flagged for the user, including ADR-017 possible duplicates.
  ///
  /// In en, this message translates to:
  /// **'Low confidence ({count})'**
  String needsReviewTabLowConfidence(int count);

  /// S-18 empty state. Reassurance, not an error — deliberately not styled as a warning.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs review right now'**
  String get needsReviewEmpty;

  /// S-18 empty-state body.
  ///
  /// In en, this message translates to:
  /// **'Every message and transaction is understood and categorised.'**
  String get needsReviewEmptyBody;

  /// S-18 primary action on an unparsed message — opens S-19 (AC-A4.2).
  ///
  /// In en, this message translates to:
  /// **'Fill in details'**
  String get needsReviewFillInDetails;

  /// S-18 dismissal (US-A4). Marks the message as dismissed; never deletes it, so a later inbox sweep cannot resurrect it.
  ///
  /// In en, this message translates to:
  /// **'Not a transaction'**
  String get needsReviewNotATransaction;

  /// S-18 metadata line under a raw message preview.
  ///
  /// In en, this message translates to:
  /// **'Received {time} · From: {sender}'**
  String needsReviewReceivedFrom(String time, String sender);

  /// Badge on a transaction flagged by ADR-017's D2/D3 tiers. Both transactions stay in every total until the user decides — never auto-removed.
  ///
  /// In en, this message translates to:
  /// **'Possible duplicate'**
  String get needsReviewPossibleDuplicate;

  /// Explains UnparsedReason.noRuleMatched in plain language — usually means the bank changed its template (risk R-4).
  ///
  /// In en, this message translates to:
  /// **'This message did not match any known format'**
  String get needsReviewReasonNoRule;

  /// Explains UnparsedReason.requiredFieldMissing / extractionRegexFailed.
  ///
  /// In en, this message translates to:
  /// **'Some details were missing from this message'**
  String get needsReviewReasonMissingField;
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
