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

  /// S-11 title (transaction-detail.html).
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get transactionDetailTitle;

  /// AC-B1.3 — the literal text for a field the source message did not contain. Never blank, never zero, never guessed. Used everywhere an optional field is absent.
  ///
  /// In en, this message translates to:
  /// **'Not stated in message'**
  String get fieldNotStatedInMessage;

  /// S-11 field label.
  ///
  /// In en, this message translates to:
  /// **'Date & time'**
  String get txnFieldDateTime;

  /// S-11 field label — the instrument the movement hit (AC-B1.1).
  ///
  /// In en, this message translates to:
  /// **'Account / card'**
  String get txnFieldInstrument;

  /// S-11 field label — transaction type (AC-B1.1).
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get txnFieldType;

  /// S-11 field label — provenance (NFR-A1).
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get txnFieldSource;

  /// S-11 field label.
  ///
  /// In en, this message translates to:
  /// **'Merchant / payee'**
  String get txnFieldMerchant;

  /// S-11 field label — who a transfer went to or came from (PRD 3.4).
  ///
  /// In en, this message translates to:
  /// **'Counterparty'**
  String get txnFieldCounterparty;

  /// S-11 field label.
  ///
  /// In en, this message translates to:
  /// **'Counterparty bank'**
  String get txnFieldCounterpartyBank;

  /// S-11 field label — present on transfers and some bill payments.
  ///
  /// In en, this message translates to:
  /// **'Reference number'**
  String get txnFieldReference;

  /// S-11 field label — the bank's own inline conversion (ADR-009).
  ///
  /// In en, this message translates to:
  /// **'Converted amount'**
  String get txnFieldConvertedAmount;

  /// S-11 field label — kept as its own field, never folded into the amount (PRD 3.4).
  ///
  /// In en, this message translates to:
  /// **'Foreign transaction fee'**
  String get txnFieldFxFee;

  /// S-11 field label — an exact decimal string, never a float.
  ///
  /// In en, this message translates to:
  /// **'Exchange rate'**
  String get txnFieldExchangeRate;

  /// S-11 field label — informational only; never counted as spend.
  ///
  /// In en, this message translates to:
  /// **'Remaining balance'**
  String get txnFieldRemainingBalance;

  /// S-11 provenance line for a parser-derived transaction.
  ///
  /// In en, this message translates to:
  /// **'SMS · {bank}'**
  String txnSourceSms(String bank);

  /// AC-A4.2 / KHA-64 — an unparsed message the user completed by hand. Provenance is still SMS and the source message is still linked; the values were supplied by a person.
  ///
  /// In en, this message translates to:
  /// **'SMS · {bank} · completed by you'**
  String txnSourceSmsCompletedByYou(String bank);

  /// US-B4 — a transaction with no message behind it.
  ///
  /// In en, this message translates to:
  /// **'Manual entry'**
  String get txnSourceManual;

  /// Epic H provenance. Not produced yet; the label exists because the provenance value does (NFR-A1).
  ///
  /// In en, this message translates to:
  /// **'Statement import'**
  String get txnSourceStatement;

  /// AC-B1.2 — expands the SmsOriginalTextPanel so the user can verify the parse.
  ///
  /// In en, this message translates to:
  /// **'Show original message'**
  String get txnShowOriginalSms;

  /// Collapses the SmsOriginalTextPanel.
  ///
  /// In en, this message translates to:
  /// **'Hide original message'**
  String get txnHideOriginalSms;

  /// SmsOriginalTextPanel's 'no original text' state, for manual entries.
  ///
  /// In en, this message translates to:
  /// **'No original message — this transaction was added manually'**
  String get txnNoOriginalSms;

  /// AC-B4.3 — non-colour indicator that a transaction was user-entered.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get txnBadgeManual;

  /// NFR-U4 — the flag is an icon AND a word, never a bare coloured dot.
  ///
  /// In en, this message translates to:
  /// **'Needs review'**
  String get txnBadgeNeedsReview;

  /// NFR-U4 — spoken label for a debit, so the sign is not carried by colour alone.
  ///
  /// In en, this message translates to:
  /// **'Debit'**
  String get txnDebitLabel;

  /// NFR-U4 — spoken label for a credit (refund, income, incoming transfer).
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get txnCreditLabel;

  /// US-B8 — the deleted-transaction state of S-11.
  ///
  /// In en, this message translates to:
  /// **'This transaction is deleted and is in no total'**
  String get txnDeletedBanner;

  /// Fallback when a transaction's source message names a bank no longer known to any active rule pack.
  ///
  /// In en, this message translates to:
  /// **'Unknown bank'**
  String get txnUnknownBank;

  /// Transaction type label (rule pack messageType pos_purchase).
  ///
  /// In en, this message translates to:
  /// **'Card purchase'**
  String get txnTypePosPurchase;

  /// Transaction type label (online_purchase).
  ///
  /// In en, this message translates to:
  /// **'Online purchase'**
  String get txnTypeOnlinePurchase;

  /// Transaction type label (transfer_out).
  ///
  /// In en, this message translates to:
  /// **'Outgoing transfer'**
  String get txnTypeTransferOut;

  /// Transaction type label (transfer_in).
  ///
  /// In en, this message translates to:
  /// **'Incoming transfer'**
  String get txnTypeTransferIn;

  /// Transaction type label (bill_payment).
  ///
  /// In en, this message translates to:
  /// **'Bill payment'**
  String get txnTypeBillPayment;

  /// Transaction type label (card_repayment). Does not count as spend — it settles purchases already counted.
  ///
  /// In en, this message translates to:
  /// **'Credit-card repayment'**
  String get txnTypeCardRepayment;

  /// Transaction type label (fee).
  ///
  /// In en, this message translates to:
  /// **'Fee / VAT'**
  String get txnTypeFee;

  /// Transaction type label (installment).
  ///
  /// In en, this message translates to:
  /// **'Finance installment'**
  String get txnTypeInstallment;

  /// Transaction type label (account_debit) — the bare 'debited from account' template in PRD 3.4.
  ///
  /// In en, this message translates to:
  /// **'Account debit'**
  String get txnTypeAccountDebit;

  /// Transaction type label (refund). A credit that reduces spend (US-B7).
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get txnTypeRefund;

  /// Transaction type label (withdrawal).
  ///
  /// In en, this message translates to:
  /// **'Cash withdrawal'**
  String get txnTypeWithdrawal;

  /// Transaction type label for an unrecognised or unset type. Shown rather than hiding the field — an unknown type is a fact, not a blank.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get txnTypeUnknown;

  /// S-21 title (banks.html).
  ///
  /// In en, this message translates to:
  /// **'Banks'**
  String get banksTitle;

  /// S-21 empty state, before any SMS has been seen.
  ///
  /// In en, this message translates to:
  /// **'No banks yet'**
  String get banksEmptyTitle;

  /// S-21 empty-state body, stating US-B15's auto-creation promise plainly.
  ///
  /// In en, this message translates to:
  /// **'A bank appears here automatically the first time a message arrives from it — there is nothing to set up.'**
  String get banksEmptyBody;

  /// Label above a bank's or instrument's combined figure (AC-B2.1, AC-B12.2).
  ///
  /// In en, this message translates to:
  /// **'Total this period'**
  String get bankTotalThisPeriod;

  /// AC-B13.3 — accounts are their own group, never merged with cards.
  ///
  /// In en, this message translates to:
  /// **'Accounts ({count})'**
  String bankAccountsSection(int count);

  /// AC-B13.3 — cards are their own group.
  ///
  /// In en, this message translates to:
  /// **'Cards ({count})'**
  String bankCardsSection(int count);

  /// S-22 empty state for a bank created from a message that named no instrument.
  ///
  /// In en, this message translates to:
  /// **'No accounts or cards mentioned for this bank yet'**
  String get bankNoInstruments;

  /// Half of the S-21 subtitle under a bank name. An ICU plural rather than '{count} accounts', so neither language renders '1 accounts' — Arabic has its own plural categories and gen-l10n applies them from this one form.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no accounts} =1{1 account} other{{count} accounts}}'**
  String bankAccountsCount(int count);

  /// The other half of the S-21 subtitle. See bankAccountsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no cards} =1{1 card} other{{count} cards}}'**
  String bankCardsCount(int count);

  /// Joins the two counts above. Kept as a translatable string rather than a hard-coded ' · ' so a language that separates them differently can.
  ///
  /// In en, this message translates to:
  /// **'{accounts} · {cards}'**
  String bankInstrumentsSummary(String accounts, String cards);

  /// AC-B13.1 — an instrument typed as an account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get instrumentKindAccount;

  /// AC-B13.2 — an instrument typed as a card.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get instrumentKindCard;

  /// AC-B15.2 — an auto-created instrument the user has not renamed; it is labelled by its masked identifier and carries this caption.
  ///
  /// In en, this message translates to:
  /// **'Not named yet'**
  String get instrumentUnnamed;

  /// AC-B14.3 — neutral, not an error. The link is never guessed.
  ///
  /// In en, this message translates to:
  /// **'Not linked to a settlement account yet'**
  String get instrumentNotLinked;

  /// AC-B14.2 — the linked settlement account shown for context.
  ///
  /// In en, this message translates to:
  /// **'Settles from {account}'**
  String instrumentLinkedTo(String account);

  /// Opens S-25 (US-B3).
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get instrumentRenameAction;

  /// S-25 sheet title.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get instrumentRenameTitle;

  /// S-25 text field label (AC-B3.1).
  ///
  /// In en, this message translates to:
  /// **'Friendly name'**
  String get instrumentRenameFieldLabel;

  /// S-25 confirm button.
  ///
  /// In en, this message translates to:
  /// **'Save name'**
  String get instrumentRenameSave;

  /// S-23/S-24 section heading above the instrument's own transactions (AC-B2.3).
  ///
  /// In en, this message translates to:
  /// **'Recent transactions'**
  String get instrumentRecentTransactions;

  /// S-23/S-24 empty state.
  ///
  /// In en, this message translates to:
  /// **'No transactions on this one yet'**
  String get instrumentNoTransactions;

  /// Shown instead of a zero figure when nothing matched the period — zero and 'nothing to show' are different facts.
  ///
  /// In en, this message translates to:
  /// **'No transactions in this period'**
  String get totalsNoneForPeriod;

  /// S-19 title (needs-review.html) — AC-A4.2.
  ///
  /// In en, this message translates to:
  /// **'Complete the details'**
  String get completeTitle;

  /// S-19 intro, stating that provenance is preserved (NFR-A1).
  ///
  /// In en, this message translates to:
  /// **'Fill in what the message could not tell us. The original message stays linked to the transaction.'**
  String get completeIntro;

  /// S-19 field label.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get completeAmountLabel;

  /// AC-B4.2 — validation names the missing field explicitly, never a generic 'invalid input'.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount to save this transaction'**
  String get completeAmountMissing;

  /// S-19 field label. Every stored amount carries a currency (NFR-A5).
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get completeCurrencyLabel;

  /// AC-B4.2 validation message for the currency field.
  ///
  /// In en, this message translates to:
  /// **'Enter a 3-letter currency code, for example SAR'**
  String get completeCurrencyMissing;

  /// S-19 field label. Optional — left blank it is stored as unknown, not as an empty name.
  ///
  /// In en, this message translates to:
  /// **'Merchant / payee'**
  String get completeMerchantLabel;

  /// S-19 field label.
  ///
  /// In en, this message translates to:
  /// **'Date & time'**
  String get completeDateLabel;

  /// AC-B4.2 validation message for the date field.
  ///
  /// In en, this message translates to:
  /// **'Choose the date and time of the transaction'**
  String get completeDateMissing;

  /// S-19 field label.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get completeTypeLabel;

  /// AC-B4.2 validation message for the type field.
  ///
  /// In en, this message translates to:
  /// **'Choose what kind of transaction this is'**
  String get completeTypeMissing;

  /// S-19 picker over the user's existing instruments. The form never creates one — see unparsed_completion.dart.
  ///
  /// In en, this message translates to:
  /// **'Account / card'**
  String get completeInstrumentLabel;

  /// S-19 instrument picker option meaning the message did not say (AC-B1.3).
  ///
  /// In en, this message translates to:
  /// **'Not stated'**
  String get completeInstrumentNotStated;

  /// S-19 direction choice — debit.
  ///
  /// In en, this message translates to:
  /// **'Money out'**
  String get completeDirectionDebit;

  /// S-19 direction choice — credit. Offered because a refund the parser missed is still a refund (US-B7).
  ///
  /// In en, this message translates to:
  /// **'Money in'**
  String get completeDirectionCredit;

  /// S-19 confirm button.
  ///
  /// In en, this message translates to:
  /// **'Save as transaction'**
  String get completeSave;

  /// S-19 heading above the sanitised message text the user is reading from.
  ///
  /// In en, this message translates to:
  /// **'Original message'**
  String get completeOriginalMessage;

  /// Shown when the message was completed or dismissed elsewhere between the form opening and Save.
  ///
  /// In en, this message translates to:
  /// **'This item is no longer in the review queue'**
  String get completeUnavailable;

  /// S-19 note. The mockup shows a category picker; categories are P4 work, and offering a picker with no categories behind it would be a lie.
  ///
  /// In en, this message translates to:
  /// **'Categorisation comes later — this will be saved as Uncategorised and you can categorise it from the list.'**
  String get completeCategoryDeferred;
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
