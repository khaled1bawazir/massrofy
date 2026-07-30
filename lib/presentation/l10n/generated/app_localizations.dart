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

  /// design.md §5 BottomNav tab 1 (S-08), and the AppBar title of the Home dashboard.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// design.md §5 BottomNav tab 2 (S-10).
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get navTransactions;

  /// design.md §5 BottomNav's last tab — the S-40 root that hosts Banks, Categories, Learned rules, Recently deleted.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// Overline above the MonthTotalCard figure (AC-E1.1). 'Month' here is a CALENDAR month in Asia/Riyadh, never a card statement cycle (OQ-12).
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get homeThisMonth;

  /// AC-E1.3's caption, shown UNDER an explicit 0.00 figure. The figure alone would read as 'you spent nothing'; this line says 'nothing has been recorded', which is the different and truthful fact.
  ///
  /// In en, this message translates to:
  /// **'No transactions recorded yet this month'**
  String get homeNoSpendThisMonth;

  /// AC-E1.3 empty state headline on Home.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get homeEmptyTitle;

  /// AC-E1.3 empty state body. States that there is nothing to set up (US-B15) and offers the manual path (US-B4), so an empty screen is never a dead end.
  ///
  /// In en, this message translates to:
  /// **'As soon as your bank sends a transaction message it appears here automatically. You can also add a cash transaction by hand.'**
  String get homeEmptyBody;

  /// Empty-state and FAB action opening S-20 manual entry (US-B4).
  ///
  /// In en, this message translates to:
  /// **'Add a transaction manually'**
  String get homeAddManually;

  /// Section title above Home's recent-activity preview.
  ///
  /// In en, this message translates to:
  /// **'Recent transactions'**
  String get homeRecentTransactions;

  /// Link from a Home section to its full screen.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get homeViewAll;

  /// Manual re-lock action (ADR-005), so the lock path is exercisable without waiting for the OS to background the app.
  ///
  /// In en, this message translates to:
  /// **'Lock now'**
  String get homeLockNow;

  /// AC-E1.4 — 'the prior month remains viewable'. Also the screen-reader label for the back chevron in the period selector (NFR-U2).
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get periodPreviousMonth;

  /// Period selector forward chevron. Disabled on the current month — there is nothing after now.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get periodNextMonth;

  /// Jump-back-to-now affordance, shown only while an older month is being viewed.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get periodCurrentMonth;

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

  /// The sign convention's user-facing contract (defect O-QA-2, lib/core/money/sign_convention.dart). A minus sign is never interpreted as 'this is a refund' — the direction control says that.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than zero, then choose Money in or Money out'**
  String get amountMustBePositive;

  /// S-11 field label — AC-B9.3 requires the rate AND its date to be inspectable (KHA-70).
  ///
  /// In en, this message translates to:
  /// **'Rate date'**
  String get txnFieldFxRateDate;

  /// Shown in place of a rate date the message never stated. An undated rate must say so rather than look authoritative (KHA-70).
  ///
  /// In en, this message translates to:
  /// **'Date unknown'**
  String get txnFxRateDateUnknown;

  /// S-11 field label — where the conversion rate came from (ADR-009).
  ///
  /// In en, this message translates to:
  /// **'Rate source'**
  String get txnFieldFxRateSource;

  /// ExchangeRateSource.smsImplied.
  ///
  /// In en, this message translates to:
  /// **'Implied by the bank\'s own converted amount'**
  String get txnFxSourceSmsImplied;

  /// ExchangeRateSource.smsStated.
  ///
  /// In en, this message translates to:
  /// **'Stated in the bank\'s message'**
  String get txnFxSourceSmsStated;

  /// ExchangeRateSource.user.
  ///
  /// In en, this message translates to:
  /// **'Entered by you'**
  String get txnFxSourceUser;

  /// ExchangeRateSource.carriedForward — marked as such per ADR-009.
  ///
  /// In en, this message translates to:
  /// **'Most recent known rate, carried forward'**
  String get txnFxSourceCarriedForward;

  /// ADR-009 case 4. Shown on a foreign-currency transaction with no conversion, so its absence from the period total is visible rather than silent.
  ///
  /// In en, this message translates to:
  /// **'Not converted to {currency} — this message stated no rate, and the app never invents one'**
  String txnFxNotConverted(String currency);

  /// design.md 3.3 — a transfer between the user's own accounts. Excluded from spend (AC-B11.1). Icon + these words; never colour alone (NFR-U4).
  ///
  /// In en, this message translates to:
  /// **'Internal transfer'**
  String get txnBadgeInternalTransfer;

  /// AC-B11.2 — the app could not determine whether this is the user's own account, so it says so instead of guessing. Still counted as spend until confirmed.
  ///
  /// In en, this message translates to:
  /// **'Possible internal transfer'**
  String get txnBadgeInternalTransferCandidate;

  /// S-11 explanation under the internal-transfer badge, so the exclusion is auditable (NFR-A6).
  ///
  /// In en, this message translates to:
  /// **'Excluded from spend totals — moving money to yourself is not spending'**
  String get txnInternalTransferExcludedNote;

  /// AC-B11.2 / risk R-7 — the unknown state is made visible rather than resolved by a guess.
  ///
  /// In en, this message translates to:
  /// **'Still counted as spend until you confirm this went to your own account'**
  String get txnInternalTransferCandidateNote;

  /// Transaction type label (salary_income). Recorded as income, never as spend (AC-B10.1).
  ///
  /// In en, this message translates to:
  /// **'Salary / income'**
  String get txnTypeSalaryIncome;

  /// AC-B9.2 / ADR-009 — the explicit incompleteness line under a base-currency total. A total that quietly omits a purchase is worse than one that admits it is incomplete.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 transaction not converted} other{{count} transactions not converted}}'**
  String totalsNotConverted(int count);

  /// S-32 heading (AC-B10.3).
  ///
  /// In en, this message translates to:
  /// **'Spent vs kept'**
  String get spentVsKeptTitle;

  /// S-32 row — net spend after refunds, excluding internal transfers.
  ///
  /// In en, this message translates to:
  /// **'Spent'**
  String get spentVsKeptSpent;

  /// S-32 row — salary and third-party incoming transfers (AC-B10.1).
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get spentVsKeptIncome;

  /// S-32 row — received minus spent (AC-B10.3). Negative means the user spent more than came in.
  ///
  /// In en, this message translates to:
  /// **'Kept this period'**
  String get spentVsKeptNet;

  /// S-32 row — AC-B10.2. Neither spend nor income: the money is still the user's, it has stopped being traceable.
  ///
  /// In en, this message translates to:
  /// **'Cash withdrawn'**
  String get spentVsKeptCashOut;

  /// S-32 row — US-B11's exclusion shown as a figure so it can be checked, not left as a silent gap.
  ///
  /// In en, this message translates to:
  /// **'Internal transfers excluded'**
  String get spentVsKeptInternalExcluded;

  /// Shown when any component of the report omits an unconvertible transaction (ADR-009).
  ///
  /// In en, this message translates to:
  /// **'Some transactions could not be converted, so these figures are incomplete'**
  String get spentVsKeptIncomplete;

  /// AC-B11.2 — unproven internal-transfer candidates and unclassifiable movements make the figures provisional.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 transaction needs review before these figures are final} other{{count} transactions need review before these figures are final}}'**
  String spentVsKeptNeedsReview(int count);

  /// S-20 title (US-B4). Cash spending is first-class here, not a fallback (OQ-19).
  ///
  /// In en, this message translates to:
  /// **'Add a transaction'**
  String get manualEntryTitle;

  /// S-20 subtitle. Names the cash case explicitly so it reads as intended use rather than a workaround.
  ///
  /// In en, this message translates to:
  /// **'For cash, or anything your bank did not send a message about.'**
  String get manualEntryIntro;

  /// S-20 confirm button.
  ///
  /// In en, this message translates to:
  /// **'Save transaction'**
  String get manualEntrySave;

  /// S-20 amount field.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get manualEntryAmountLabel;

  /// AC-B4.2 — the message names the field. Never 'invalid input'.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount to save this transaction'**
  String get manualEntryAmountMissing;

  /// AC-B4.2. Distinguished from 'missing' because the user typed something and needs to know what was wrong with it.
  ///
  /// In en, this message translates to:
  /// **'That is not an amount this app can read — use digits and at most one decimal separator'**
  String get manualEntryAmountUnparsable;

  /// S-20 currency field. Always explicit — NFR-A5 allows no amount without one.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get manualEntryCurrencyLabel;

  /// AC-B4.2 — names the field and shows the expected shape.
  ///
  /// In en, this message translates to:
  /// **'Enter a three-letter currency code, such as SAR'**
  String get manualEntryCurrencyMissing;

  /// S-20 date/time field.
  ///
  /// In en, this message translates to:
  /// **'When it happened'**
  String get manualEntryDateLabel;

  /// AC-B4.2.
  ///
  /// In en, this message translates to:
  /// **'Choose the date and time this happened'**
  String get manualEntryDateMissing;

  /// S-20 type picker.
  ///
  /// In en, this message translates to:
  /// **'What kind of transaction'**
  String get manualEntryTypeLabel;

  /// AC-B4.2.
  ///
  /// In en, this message translates to:
  /// **'Choose what kind of transaction this was'**
  String get manualEntryTypeMissing;

  /// S-20 merchant field. Optional — a cash purchase may genuinely have no name.
  ///
  /// In en, this message translates to:
  /// **'Merchant or description'**
  String get manualEntryMerchantLabel;

  /// S-20 instrument picker label.
  ///
  /// In en, this message translates to:
  /// **'Paid with'**
  String get manualEntrySourceLabel;

  /// OQ-19 — the no-instrument choice, named as a real payment method rather than shown as an absence.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get manualEntrySourceCash;

  /// AC-B4.1 reassurance — the whole point of manual entry is that the figure stays true.
  ///
  /// In en, this message translates to:
  /// **'Cash transactions count toward your totals exactly like card ones.'**
  String get manualEntryCashNote;

  /// S-20 success confirmation.
  ///
  /// In en, this message translates to:
  /// **'Transaction added'**
  String get manualEntrySaved;

  /// S-20 in edit mode (US-B5).
  ///
  /// In en, this message translates to:
  /// **'Edit transaction'**
  String get txnEditTitle;

  /// S-20 edit confirm button.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get txnEditSave;

  /// US-B5 success confirmation.
  ///
  /// In en, this message translates to:
  /// **'Changes saved'**
  String get txnEditSaved;

  /// The user pressed Save without altering anything. A legitimate no-op that writes no audit entry (US-F5 is read by a person), and saying so beats a success message for a change that did not happen.
  ///
  /// In en, this message translates to:
  /// **'Nothing was changed'**
  String get txnEditNoChanges;

  /// AC-B5.2 — the detail view shows BOTH the auto-detected value and the user's. Read from the audit trail, not a duplicate column.
  ///
  /// In en, this message translates to:
  /// **'Originally detected: {value}'**
  String txnEditOriginalValue(String value);

  /// AC-B5.2 where the parser produced no value at all — distinct from an empty string, per AC-B1.3.
  ///
  /// In en, this message translates to:
  /// **'Originally detected: nothing'**
  String get txnEditOriginalValueEmpty;

  /// AC-B5.3 made visible. User intent outranks the parser, and the user is told so.
  ///
  /// In en, this message translates to:
  /// **'Your edit is kept — re-reading the message will not overwrite it'**
  String get txnEditProtectedFromRescan;

  /// S-11 delete affordance (US-B6).
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get txnDeleteAction;

  /// AC-B6.2 — deletion requires an explicit confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete this transaction?'**
  String get txnDeleteConfirmTitle;

  /// AC-B6.1 + AC-B8.1 — states the effect on totals AND that this is reversible, so the user is not deciding under a false impression of permanence.
  ///
  /// In en, this message translates to:
  /// **'It will be removed from your lists and totals, and moved to Recently deleted. You can restore it from there.'**
  String get txnDeleteConfirmBody;

  /// AC-B6.2 cancel. Positively worded so the safe choice is the easy one.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get txnDeleteConfirmCancel;

  /// AC-B6.2 confirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get txnDeleteConfirmAccept;

  /// Toast after a soft delete (design.md flow H).
  ///
  /// In en, this message translates to:
  /// **'Transaction deleted'**
  String get txnDeleted;

  /// Immediate undo on the delete toast (design.md flow H).
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get txnDeletedUndo;

  /// US-B8 restore affordance.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get txnRestoreAction;

  /// AC-B8.2 confirmation.
  ///
  /// In en, this message translates to:
  /// **'Transaction restored'**
  String get txnRestored;

  /// S-44 title (US-B8).
  ///
  /// In en, this message translates to:
  /// **'Recently deleted'**
  String get recentlyDeletedTitle;

  /// AC-B8.1 + AC-B8.3 — states plainly what a soft delete is and what the one true hard delete is.
  ///
  /// In en, this message translates to:
  /// **'Deleted transactions are kept here and are not counted in any total. Only Erase everything removes them permanently.'**
  String get recentlyDeletedIntro;

  /// S-44 empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been deleted'**
  String get recentlyDeletedEmpty;

  /// S-44 empty state body.
  ///
  /// In en, this message translates to:
  /// **'Transactions you delete will appear here so you can bring them back.'**
  String get recentlyDeletedEmptyBody;

  /// AC-B6.4 — deletion is shown with its timestamp.
  ///
  /// In en, this message translates to:
  /// **'Deleted {when}'**
  String recentlyDeletedOn(String when);

  /// ADR-017 D2 — a row that stopped counting because the user merged it, not because they deleted it. Saying so stops a merge looking like data loss.
  ///
  /// In en, this message translates to:
  /// **'Merged into transaction #{id}'**
  String recentlyDeletedMergedInto(int id);

  /// AC-B11.2 review card in S-18. A question, because the app genuinely does not know.
  ///
  /// In en, this message translates to:
  /// **'Was this a transfer to your own account?'**
  String get reviewTransferCandidateTitle;

  /// KHA-78 — writes internal_transfer_state = internal on both legs; the pair leaves spend on the next total.
  ///
  /// In en, this message translates to:
  /// **'Yes, my own account'**
  String get reviewTransferConfirm;

  /// KHA-78 — writes external so the detector stops re-proposing this pair.
  ///
  /// In en, this message translates to:
  /// **'No, someone else'**
  String get reviewTransferReject;

  /// Confirmation after AC-B11.1's exclusion is applied.
  ///
  /// In en, this message translates to:
  /// **'Excluded from spend — both sides of the transfer'**
  String get reviewTransferConfirmed;

  /// Confirmation after a rejection. Names the durability explicitly, because a decision that did not stick would be worse than no decision.
  ///
  /// In en, this message translates to:
  /// **'Counted as a payment — we will not ask about this one again'**
  String get reviewTransferRejected;

  /// KHA-80 TransferReviewReason.crossCurrencyNearMatch. ADR-009 forbids inventing a rate, so the app explains rather than guesses.
  ///
  /// In en, this message translates to:
  /// **'A transfer in another currency happened at about the same time. We cannot match them without inventing an exchange rate, so both are still counted.'**
  String get reviewTransferCrossCurrency;

  /// KHA-80 TransferReviewReason.unresolvedInstrument — risk R-7's bootstrapping problem, stated plainly.
  ///
  /// In en, this message translates to:
  /// **'A matching transfer arrived at about the same time, but we could not tell which account it reached, so this is still counted as spending.'**
  String get reviewTransferUnresolvedInstrument;

  /// KHA-80 — the only verdict offered on an unpairable transfer. Deliberately direction-neutral: a near-match flags BOTH legs, and the incoming one is counted as income, not spending, so 'count it as spending' would be wrong on half the cards. This wording is also exactly what the write does — internal_transfer_state = external. There is no 'yes, my own account' here because with no second leg to exclude, confirming one alone would produce figures that reconcile with nothing.
  ///
  /// In en, this message translates to:
  /// **'Not an internal transfer'**
  String get reviewTransferDismiss;

  /// AC-A5.2 merge card in S-18 (ADR-017 D2/D3).
  ///
  /// In en, this message translates to:
  /// **'Are these the same transaction?'**
  String get reviewDuplicateTitle;

  /// Risk R-8 stated to the user: the app never removes a transaction, and the user is told what merging actually does before they do it.
  ///
  /// In en, this message translates to:
  /// **'Both are counted in your totals until you decide. Merging keeps one and files the other under Recently deleted — nothing is destroyed.'**
  String get reviewDuplicateBody;

  /// KHA-64 — the explicit user confirmation ADR-017 D2 requires. Merging is never automatic.
  ///
  /// In en, this message translates to:
  /// **'Yes, merge them'**
  String get reviewDuplicateMerge;

  /// AC-A5.3 — two genuine same-amount purchases on the same day must both survive.
  ///
  /// In en, this message translates to:
  /// **'No, keep both'**
  String get reviewDuplicateKeepBoth;

  /// O-QA-8 / risk R-8 — the merge is the highest-risk operation in the app and, unlike soft delete, had no confirmation step. Asking is what makes ADR-017 D2's 'the decision is the user's' true in the UI and not only in the service.
  ///
  /// In en, this message translates to:
  /// **'Merge these two into one?'**
  String get reviewMergeConfirmTitle;

  /// States the effect on totals AND the reversibility (R-8, AC-B8.1), matching the delete dialog's approach so the user is not deciding under a false impression of permanence.
  ///
  /// In en, this message translates to:
  /// **'One of them will stay in your lists and totals. The other moves to Recently deleted, keeps its own message, and can be restored at any time — nothing is destroyed.'**
  String get reviewMergeConfirmBody;

  /// Cancel, positively worded and first, so the safe choice is the easy one. Dismissing writes nothing.
  ///
  /// In en, this message translates to:
  /// **'Keep both'**
  String get reviewMergeConfirmCancel;

  /// The explicit user confirmation ADR-017 D2 requires.
  ///
  /// In en, this message translates to:
  /// **'Merge them'**
  String get reviewMergeConfirmAccept;

  /// MergeRefusal.feeDiffers (KHA-87) — the fee is a reported figure of its own (PRD §3.4), so a disagreement is the user's to settle.
  ///
  /// In en, this message translates to:
  /// **'These state different fees, so they cannot be merged automatically'**
  String get reviewMergeRefusedFee;

  /// MergeRefusal.conversionDiffers (KHA-87) — the converted amount is what reaches the base-currency total (ADR-009).
  ///
  /// In en, this message translates to:
  /// **'These state different converted amounts or exchange rates, so they cannot be merged'**
  String get reviewMergeRefusedConversion;

  /// MergeRefusal.remainingBalanceDiffers (KHA-87).
  ///
  /// In en, this message translates to:
  /// **'These report different balances after the transaction, so they cannot be merged'**
  String get reviewMergeRefusedBalance;

  /// MergeRefusal.spendEffectDiffers (KHA-87) — affectsSpend or a recorded internal-transfer decision (AC-B11.2) differs.
  ///
  /// In en, this message translates to:
  /// **'These count differently toward your spending, so they cannot be merged'**
  String get reviewMergeRefusedSpendEffect;

  /// MergeRefusal.userEditDiffers (KHA-89 / AC-B5.3) — two statements of user intent, which only the person who made them can reconcile.
  ///
  /// In en, this message translates to:
  /// **'You have corrected a detail on one of these and the other says something different — please check them before merging'**
  String get reviewMergeRefusedUserEdit;

  /// MergeRefusal.chainWouldForm (D-QA-9) — the survivor-direction half of 'no chains'.
  ///
  /// In en, this message translates to:
  /// **'One of these has already absorbed another transaction, so it cannot be merged again'**
  String get reviewMergeRefusedChain;

  /// NFR-A6 confirmation: the merged figure still traces to both sources.
  ///
  /// In en, this message translates to:
  /// **'Merged — one transaction now, traceable to both messages'**
  String get reviewDuplicateMerged;

  /// Confirmation after AC-A5.3's keep-both choice.
  ///
  /// In en, this message translates to:
  /// **'Both kept'**
  String get reviewDuplicateKeptBoth;

  /// MergeRefusal.amountDiffers — states the fact, does not judge the user.
  ///
  /// In en, this message translates to:
  /// **'These have different amounts, so they cannot be the same transaction'**
  String get reviewMergeRefusedAmount;

  /// MergeRefusal.directionDiffers — a purchase and its refund are not duplicates (US-B7).
  ///
  /// In en, this message translates to:
  /// **'One of these is money in and the other is money out, so they cannot be merged'**
  String get reviewMergeRefusedDirection;

  /// MergeRefusal.typeDiffers.
  ///
  /// In en, this message translates to:
  /// **'These are different kinds of transaction, so they cannot be merged'**
  String get reviewMergeRefusedType;

  /// MergeRefusal.notLive / sameTransaction — reachable from a stale screen.
  ///
  /// In en, this message translates to:
  /// **'One of these is no longer active, so there is nothing to merge'**
  String get reviewMergeRefusedState;

  /// KHA-74 — an unreadable stored amount is surfaced instead of vanishing from every list and total.
  ///
  /// In en, this message translates to:
  /// **'A transaction could not be read'**
  String get reviewDataProblemTitle;

  /// KHA-74 / NFR-A6. States the consequence (the total is incomplete), reassures that nothing was destroyed, and gives one concrete next step. The unreadable value itself is never shown (NFR-S4).
  ///
  /// In en, this message translates to:
  /// **'Transaction #{id} is stored with an amount this app cannot read, so it is missing from your totals. Nothing has been changed or removed. Restoring a backup is the safest way to recover it.'**
  String reviewDataProblemBody(int id);

  /// KHA-74 — the headline count, so an incomplete total is visibly incomplete.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 transaction is missing from your totals} other{{count} transactions are missing from your totals}}'**
  String reviewDataProblemCount(int count);

  /// S-18 gains an AC-B11.2 tab: transfers awaiting the user's judgement, kept apart from unparsed messages and duplicate flags because the question is a different one.
  ///
  /// In en, this message translates to:
  /// **'Transfers ({count})'**
  String needsReviewTabTransfers(int count);

  /// P4b shared button label. Reused across the reassignment, rename and rule dialogs so the same action never reads two ways.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// P4b shared button label.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// P4b shared button label for a destructive action, always paired with an icon (NFR-U4).
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// P4b shared button/tooltip label.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// S-14's rename affordance tooltip (AC-C3.4).
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get commonRename;

  /// S-14's new-category submit.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get commonCreate;

  /// S-13's explicit scope confirmation, for a user who does not want to wait for the auto-confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// AC-C5.2's snackbar action. design.md §6.6 chose undo over a blocking confirmation for category corrections.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// design.md §3.4's recoverable-error action.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonRetry;

  /// S-14 app bar title (docs/mockups/categories-rules.html).
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categoriesTitle;

  /// S-14 empty state — only reachable before the design §4 starter list has been seeded.
  ///
  /// In en, this message translates to:
  /// **'No categories yet'**
  String get categoriesEmptyTitle;

  /// S-14 empty state body. States what will happen rather than leaving a blank screen.
  ///
  /// In en, this message translates to:
  /// **'Your starter categories will appear here as soon as the app finishes setting up.'**
  String get categoriesEmptyBody;

  /// design.md §3.4 Error state for S-14. Reassures that a failed READ changed nothing, because a user seeing an error about their categories will assume the worst.
  ///
  /// In en, this message translates to:
  /// **'Your categories could not be loaded. Nothing has been changed.'**
  String get categoriesUnavailable;

  /// design.md §4's first bucket: categories that compete for budget share and appear in breakdowns.
  ///
  /// In en, this message translates to:
  /// **'Spending'**
  String get categoryGroupSpending;

  /// design.md §4's second bucket: income/transfers/withdrawals, excluded from spend totals.
  ///
  /// In en, this message translates to:
  /// **'Money movement'**
  String get categoryGroupMoneyMovement;

  /// S-14 row caption. The number S-15 quotes back on delete, so it is shown before the user commits to anything.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No transactions} one{1 transaction} other{{count} transactions}}'**
  String categoryRowTransactionCount(int count);

  /// The Uncategorized row. Says WHY no affordances are offered, so their absence reads as deliberate rather than as a missing feature (design.md §4, AC-C1.1).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{System category — cannot be renamed or deleted} one{1 transaction · System category} other{{count} transactions · System category}}'**
  String categoryRowSystemCaption(int count);

  /// AC-C3.4 — the id is stable across a rename, so nothing is re-categorized.
  ///
  /// In en, this message translates to:
  /// **'Rename category'**
  String get categoryRenameTitle;

  /// Rename confirmation.
  ///
  /// In en, this message translates to:
  /// **'Renamed to {name}'**
  String categoryRenamed(String name);

  /// S-15 dialog title.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String categoryDeleteTitle(String name);

  /// AC-C3.3 — the delete is blocked until the user decides. The sentence states the requirement rather than warning vaguely.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{This category has 1 transaction. Choose what happens to it:} other{This category has {count} transactions. Choose what happens to them:}}'**
  String categoryDeleteInUseBody(int count);

  /// The no-decision-needed path. Asking where zero transactions should go would be theatre.
  ///
  /// In en, this message translates to:
  /// **'Nothing is using this category, so nothing else will change.'**
  String get categoryDeleteEmptyBody;

  /// S-15's picker label. Uncategorized is one of the options (AC-C3.3's 'or set to Uncategorized').
  ///
  /// In en, this message translates to:
  /// **'Move its transactions to'**
  String get categoryDeleteReassignLabel;

  /// Delete confirmation.
  ///
  /// In en, this message translates to:
  /// **'Deleted {name}'**
  String categoryDeleted(String name);

  /// S-12 sheet title when the transaction names no merchant.
  ///
  /// In en, this message translates to:
  /// **'Choose a category'**
  String get categoryPickerTitle;

  /// S-12 sheet title. Naming the merchant is what makes the scope question that follows make sense.
  ///
  /// In en, this message translates to:
  /// **'Categorize · {merchant}'**
  String categoryPickerTitleFor(String merchant);

  /// design.md §6.2's search field.
  ///
  /// In en, this message translates to:
  /// **'Search categories'**
  String get categoryPickerSearchHint;

  /// design.md §6.2's last-three-used row.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get categoryPickerRecent;

  /// design.md §3.4's Filtered-empty state, which must read differently from a true empty.
  ///
  /// In en, this message translates to:
  /// **'No category matches \"{query}\"'**
  String categoryPickerNoResults(String query);

  /// design.md §6.5's inline create affordance.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get categoryPickerNewCategory;

  /// §6.5's name field.
  ///
  /// In en, this message translates to:
  /// **'Category name'**
  String get categoryNewNameLabel;

  /// §6.5's icon choice.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get categoryNewIconLabel;

  /// §6.5 — the new category is applied to the transaction the user was correcting, which is why they opened the form.
  ///
  /// In en, this message translates to:
  /// **'Create and use'**
  String get categoryNewCreateAndUse;

  /// AC-C3.2. Names the problem rather than saying 'invalid input' (brand.md voice principle 4). CategoryDao.createCustom folds the name, so case, spacing and Arabic orthography all collide.
  ///
  /// In en, this message translates to:
  /// **'A category with this name already exists — choose another name'**
  String get categoryNewDuplicateName;

  /// design.md §6.4's in-sheet confirmation. The category is ALREADY applied when this renders — the scope strip must not read as if the correction were still pending.
  ///
  /// In en, this message translates to:
  /// **'Categorized as {category}'**
  String categoryAppliedAs(String category);

  /// US-D5 / AC-C2.3's scope question.
  ///
  /// In en, this message translates to:
  /// **'Apply this to future transactions from \"{merchant}\" too?'**
  String categoryScopeQuestion(String merchant);

  /// The same question when the merchant has no resolved name.
  ///
  /// In en, this message translates to:
  /// **'Apply this to future transactions from this merchant too?'**
  String get categoryScopeQuestionGeneric;

  /// AC-D5.1's default option, pre-selected because it trains the learning loop (US-D2/D3).
  ///
  /// In en, this message translates to:
  /// **'This and future ones'**
  String get categoryScopeFuture;

  /// Shown while the affected count is still loading, so a number never appears out of nowhere.
  ///
  /// In en, this message translates to:
  /// **'Creates or updates this merchant\'s rule'**
  String get categoryScopeFutureHint;

  /// AC-C5.1 + AC-D5.3 — the bulk half, stated BEFORE the user commits. Only uncategorized rows are counted; rewriting an already-categorized one is AC-D4.4's operation and asks separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Creates or updates this merchant\'s rule} one{Also fills in 1 earlier uncategorized transaction} other{Also fills in {count} earlier uncategorized transactions}}'**
  String categoryScopeFutureCount(int count);

  /// US-D5's one-off (e.g. a supermarket purchase that was actually a gift).
  ///
  /// In en, this message translates to:
  /// **'Just this transaction'**
  String get categoryScopeThisOnly;

  /// AC-D5.2's guarantee, stated where the choice is made.
  ///
  /// In en, this message translates to:
  /// **'Leaves this merchant\'s existing rule exactly as it is'**
  String get categoryScopeThisOnlyHint;

  /// design.md §6.4's auto-confirm. Deliberately not a live countdown: a ticking number invites the user to wait for it, and the whole point is that they need not.
  ///
  /// In en, this message translates to:
  /// **'Applying in a moment…'**
  String get categoryScopeAutoConfirm;

  /// AC-C2.1's immediate save, for a correction that touched one row.
  ///
  /// In en, this message translates to:
  /// **'Category updated'**
  String get correctionAppliedToOne;

  /// AC-D5.3 — the merchant-wide option states how many existing transactions were affected. Mirrors the mockup's toast wording.
  ///
  /// In en, this message translates to:
  /// **'Updated {count} transactions from {merchant}'**
  String correctionAppliedToMany(int count, String merchant);

  /// design.md §3.3's 'Auto-categorized by rule' indicator, as the sparkle icon's semantics label so the fact reaches a screen-reader user (NFR-U4/U1).
  ///
  /// In en, this message translates to:
  /// **'Applied automatically'**
  String get categoryAutoApplied;

  /// KHA-32's confidence display, banded. At or above autoApplyThreshold (AC-D2.2).
  ///
  /// In en, this message translates to:
  /// **'Confident match'**
  String get categoryConfidenceHigh;

  /// Below the threshold, or a tier that may never auto-apply. The app is asking (AC-C4.1).
  ///
  /// In en, this message translates to:
  /// **'Not sure'**
  String get categoryConfidenceLow;

  /// AC-D2.4 — a never-before-seen merchant, never confidently categorized by coincidence.
  ///
  /// In en, this message translates to:
  /// **'No match found'**
  String get categoryConfidenceNone;

  /// The band plus the raw figure. The band is what a person acts on; the figure is what makes the app checkable, and hiding it would sit oddly beside an audit trail this product otherwise exposes in full.
  ///
  /// In en, this message translates to:
  /// **'{label} ({percent}%)'**
  String categoryConfidenceWithValue(String label, int percent);

  /// CategoryReviewReason.unknownMerchant. Three reasons, three questions — collapsing them would make the inbox say the wrong sentence about half its rows.
  ///
  /// In en, this message translates to:
  /// **'We have not seen this merchant before — where does its spending belong?'**
  String get reviewReasonUnknownMerchant;

  /// CategoryReviewReason.noRuleForMerchant.
  ///
  /// In en, this message translates to:
  /// **'We know this merchant, but nobody has said which category it belongs in'**
  String get reviewReasonNoRuleForMerchant;

  /// CategoryReviewReason.lowConfidenceCategory — including every T4 'did you mean' suggestion, which ADR-008 forbids applying at any confidence.
  ///
  /// In en, this message translates to:
  /// **'We found a close match but we are not sure enough to apply it'**
  String get reviewReasonLowConfidence;

  /// Fallback for an unrecognised review reason — §5.2's forward-compatibility rule applied to a stored vocabulary.
  ///
  /// In en, this message translates to:
  /// **'This one needs your judgement'**
  String get reviewReasonGeneric;

  /// design.md §3.4 Error state for S-18. Never rendered as an empty inbox: 'nothing needs review' is this screen's good-news state and showing it wrongly is the worst thing it can do.
  ///
  /// In en, this message translates to:
  /// **'The review inbox could not be loaded. Nothing has been changed.'**
  String get reviewInboxUnavailable;

  /// design.md §5's ReviewCountCard at zero: it recedes visually. A queue that shouted about being empty would train the user to ignore it.
  ///
  /// In en, this message translates to:
  /// **'All caught up'**
  String get reviewCountAllClear;

  /// AC-C4.2 — the count of items needing review, visible from the main screen.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 item needs review} other{{count} items need review}}'**
  String reviewCountNeedsReview(int count);

  /// What the badge number is made of. AC-C1.2 counts uncategorized rows in this queue, and a user who did not know that would be looking for that many PROBLEMS. Deliberately does NOT include unparsed messages: KHA-32's done-check defines the badge as flagged plus uncategorized, and S-18's own tabs carry the message count. The two figures overlap (a row can be both flagged and uncategorized), so they do not add up to the headline — which is why the headline is a union, not a sum.
  ///
  /// In en, this message translates to:
  /// **'{uncategorized} uncategorized · {flagged} flagged'**
  String reviewCountBreakdown(int uncategorized, int flagged);

  /// design.md §3.4 Error state. A failed read must never render as a reassuring zero.
  ///
  /// In en, this message translates to:
  /// **'The review count is unavailable right now'**
  String get reviewCountUnavailable;

  /// S-16 app bar title (US-D4).
  ///
  /// In en, this message translates to:
  /// **'Learned rules'**
  String get learnedRulesTitle;

  /// S-16 empty state.
  ///
  /// In en, this message translates to:
  /// **'No rules yet'**
  String get learnedRulesEmptyTitle;

  /// The copy does real work: it explains how rules come into existence, so an empty screen reads as 'you have not corrected anything yet' rather than 'this feature is broken'.
  ///
  /// In en, this message translates to:
  /// **'Correcting any transaction\'s category teaches a rule automatically, so the next one from that merchant arrives already sorted.'**
  String get learnedRulesEmptyBody;

  /// design.md §3.4 Error state for S-16.
  ///
  /// In en, this message translates to:
  /// **'Your learned rules could not be loaded. Nothing has been changed.'**
  String get learnedRulesUnavailable;

  /// AC-D4.1's per-rule detail.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Not applied yet} one{Applied to 1 transaction} other{Applied to {count} transactions}}'**
  String ruleAppliedCount(int count);

  /// A seed rule versus one the user taught. AC-D3.1 makes a user rule outrank a seed rule, so the two should not look identical.
  ///
  /// In en, this message translates to:
  /// **'· Built in'**
  String get ruleSourceSeed;

  /// S-17 dialog title.
  ///
  /// In en, this message translates to:
  /// **'Edit rule for {merchant}'**
  String ruleEditTitle(String merchant);

  /// S-17 — what the rule says today.
  ///
  /// In en, this message translates to:
  /// **'Currently: {category}'**
  String ruleEditCurrentCategory(String category);

  /// AC-D4.2 — changing this changes what future transactions get.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get ruleEditNewCategory;

  /// AC-D4.4's required prompt. The count is computed BEFORE the dialog can promise it, so the button cannot name a number the write does not deliver.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No existing transactions would change.} one{Also re-apply this to 1 existing transaction from this merchant?} other{Also re-apply this to {count} existing transactions from this merchant?}}'**
  String ruleReapplyPrompt(int count);

  /// Shown while the count is in flight. The re-apply button stays disabled until it arrives — a button reading 'Yes, ? transactions' would ask the user to consent to something unspecified.
  ///
  /// In en, this message translates to:
  /// **'Checking how many existing transactions this would change…'**
  String get ruleReapplyPromptCounting;

  /// AC-D4.4's affirmative.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Re-apply} other{Yes, {count} transactions}}'**
  String ruleReapplyYes(int count);

  /// AC-D4.4's negative — AC-D4.2 without the history rewrite.
  ///
  /// In en, this message translates to:
  /// **'Going forward only'**
  String get ruleReapplyNo;

  /// AC-D4.4's confirmation. Each affected transaction also got its own audit entry naming the rule — a bulk re-apply that wrote no history would be a defect (KHA-34).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Rule updated. No existing transactions needed changing.} one{Rule updated and re-applied to 1 transaction} other{Rule updated and re-applied to {count} transactions}}'**
  String ruleReappliedCount(int count);

  /// AC-D4.2 alone — states the half the user chose NOT to do, so 'nothing visibly happened' is explained rather than mysterious.
  ///
  /// In en, this message translates to:
  /// **'Rule updated. Existing transactions were left as they are.'**
  String get ruleUpdatedGoingForward;

  /// KHA-104's refusal reaching the user. The rule is declined rather than written against a category nothing can render.
  ///
  /// In en, this message translates to:
  /// **'That category is no longer available, so the rule was not changed'**
  String get ruleEditRefused;

  /// AC-D4.3's confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete the rule for {merchant}?'**
  String ruleDeleteTitle(String merchant);

  /// AC-D4.3, both halves. A user who believes deleting a rule will un-categorize a year of history will never delete a bad rule.
  ///
  /// In en, this message translates to:
  /// **'Future transactions from this merchant will arrive uncategorized. Transactions you have already categorized keep their categories.'**
  String get ruleDeleteBody;

  /// AC-D4.3 confirmation.
  ///
  /// In en, this message translates to:
  /// **'Rule deleted'**
  String get ruleDeleted;

  /// KHA-31 — every automatic categorization stays traceable to its audit entry. Loaded on demand, because it is a second query for a question asked rarely.
  ///
  /// In en, this message translates to:
  /// **'Why this category?'**
  String get categoryWhyThisCategory;

  /// category_source = 'user'. Deliberately not phrased as a confidence: 'you told us' is a different kind of fact from 'we are sure'.
  ///
  /// In en, this message translates to:
  /// **'You chose this category.'**
  String get categoryProvenanceUser;

  /// AC-D2.2 / AC-F5.2 — the automatic case, naming the rule below.
  ///
  /// In en, this message translates to:
  /// **'A learned rule applied this automatically, at {percent}% confidence.'**
  String categoryProvenanceAutomatic(int percent);

  /// category_source = 'none'. A real answer, not an absence — AC-D2.4's honest outcome.
  ///
  /// In en, this message translates to:
  /// **'The app looked and could not decide, so this is left uncategorized.'**
  String get categoryProvenanceUndecided;

  /// A row written before P4a. Saying so is better than inventing a provenance.
  ///
  /// In en, this message translates to:
  /// **'This category was set before the app started recording how.'**
  String get categoryProvenanceUnknownSource;

  /// AC-F5.2 — which rule fired, resolved from the live rule row.
  ///
  /// In en, this message translates to:
  /// **'Rule: {merchant}'**
  String categoryProvenanceRule(String merchant);

  /// Honest rather than a dangling id. KHA-103 clears category_rule_id with the rule, so this is a genuine 'no longer exists', not a lookup failure.
  ///
  /// In en, this message translates to:
  /// **'The rule that did this has since been deleted.'**
  String get categoryProvenanceRuleGone;

  /// An empty trail is a claim, so it is only ever shown after a successful read.
  ///
  /// In en, this message translates to:
  /// **'No categorization history for this transaction yet.'**
  String get categoryProvenanceNoHistory;

  /// One audit line, shown verbatim rather than summarised (NFR-A2).
  ///
  /// In en, this message translates to:
  /// **'{when} · {actor}'**
  String categoryProvenanceEntry(String when, String actor);

  /// design.md §3.4 Error state. An empty history is a claim a failed read has not established.
  ///
  /// In en, this message translates to:
  /// **'The history for this category could not be loaded.'**
  String get categoryProvenanceUnavailable;

  /// ADR-010 actor 'user'.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get categoryActorUser;

  /// ADR-010 actor 'system_rule' — the distinction between what the app did and what the person did is the whole value of the trail.
  ///
  /// In en, this message translates to:
  /// **'A learned rule'**
  String get categoryActorRule;

  /// ADR-010 actor 'system'.
  ///
  /// In en, this message translates to:
  /// **'The app'**
  String get categoryActorSystem;

  /// design.md §3.4's Locked state. ADR-005 makes the lock cryptographic, so this is a statement of fact rather than a UI courtesy.
  ///
  /// In en, this message translates to:
  /// **'Your categories are encrypted and stay locked until you unlock the app.'**
  String get categoryLockedBody;

  /// design.md §3.4 Error state for S-11, including KHA-74's unreadable-amount case.
  ///
  /// In en, this message translates to:
  /// **'This transaction could not be loaded.'**
  String get transactionUnavailable;

  /// Reachable without any bug: deleted or merged away while this screen was open.
  ///
  /// In en, this message translates to:
  /// **'This transaction is no longer here'**
  String get transactionGoneTitle;

  /// US-B8 — nothing is destroyed, and the user is told where it went.
  ///
  /// In en, this message translates to:
  /// **'It was deleted or merged into another transaction. You can find it under Recently deleted.'**
  String get transactionGoneBody;

  /// CompletionMessageUnavailable — two screens open on one queue, or a background sweep reclassified it. Not a crash.
  ///
  /// In en, this message translates to:
  /// **'That message is no longer in the review queue'**
  String get completionMessageGone;

  /// S-10's running period total, shown beside the period label. Equals the sum of exactly the rows listed under it (NFR-A6).
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get txnListTotalForPeriod;

  /// S-10 true-empty state — the ledger has never held anything.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get txnListEmptyTitle;

  /// S-10 true-empty body. Deliberately different copy from the filtered-empty state (AC-E5.3), which arrives with KHA-38.
  ///
  /// In en, this message translates to:
  /// **'Transactions appear here as soon as your bank messages arrive. You can also add one by hand.'**
  String get txnListEmptyBody;

  /// S-10 empty-for-the-selected-period state. Distinct from true-empty: there IS data, just not in the month being viewed, and telling the user otherwise would look like data loss.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this month'**
  String get txnListEmptyForPeriodTitle;

  /// Points at the period selector, which is the control that resolves this state.
  ///
  /// In en, this message translates to:
  /// **'There are no transactions in the month you are viewing. Use the arrows above to look at another month.'**
  String get txnListEmptyForPeriodBody;

  /// KHA-74 — rows whose stored amount this build cannot decode. Stated rather than silently dropped: a shorter list with no explanation is indistinguishable from lost data.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transaction could not be read and is not included in the total} other{{count} transactions could not be read and are not included in the total}}'**
  String txnListUnreadableNote(int count);

  /// AC-B6.1/B8.1 confirmation after a soft delete. Names where it went, because 'deleted' alone reads as destroyed.
  ///
  /// In en, this message translates to:
  /// **'Moved to Recently deleted'**
  String get txnDeletedToRecentlyDeleted;

  /// AC-B8.2 confirmation.
  ///
  /// In en, this message translates to:
  /// **'Transaction restored'**
  String get txnRestoredConfirmation;

  /// AC-B5.1 confirmation after the S-20 edit form saves.
  ///
  /// In en, this message translates to:
  /// **'Transaction updated'**
  String get txnEditSavedConfirmation;

  /// TransactionEditTargetMissing — the row was deleted elsewhere in the app while the edit form was open. Reachable without any bug.
  ///
  /// In en, this message translates to:
  /// **'That transaction is no longer here'**
  String get txnEditTargetMissing;

  /// PRD D-9 — the app must remain usable without SMS access. Without this, S-04 is a screen with two buttons that both lead somewhere else and no way into the app itself.
  ///
  /// In en, this message translates to:
  /// **'Continue to Massrofy'**
  String get smsLimitedModeContinue;

  /// Grouping header in the More menu (S-40 root) for the bank/instrument and transaction-entry destinations.
  ///
  /// In en, this message translates to:
  /// **'Your money'**
  String get moreSectionData;

  /// Grouping header in the More menu for categories, learned rules and the review inbox.
  ///
  /// In en, this message translates to:
  /// **'Organising'**
  String get moreSectionOrganise;

  /// Grouping header in the More menu for lock/session actions.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get moreSectionApp;

  /// Stated in the More menu rather than shipping a fourth BottomNav tab that opens onto nothing. design.md §5's BottomNav specifies four tabs; the Reports hub (S-28) is KHA-37, and a dead tab would be a worse answer than an honest sentence.
  ///
  /// In en, this message translates to:
  /// **'Reports arrive in the next release'**
  String get moreReportsComingSoon;

  /// KHA-133. Title of the re-scan screen and its More-menu row. Plain language on purpose: the user is not being asked to understand watermarks or rule packs.
  ///
  /// In en, this message translates to:
  /// **'Check my banks again'**
  String get recheckBanksTitle;

  /// KHA-133 explanation heading. Names the user's actual problem ('I got the SMS but no transaction appeared') rather than the mechanism.
  ///
  /// In en, this message translates to:
  /// **'Messages that were missed'**
  String get recheckBanksIntroTitle;

  /// KHA-133 explanation body. States the trap ADR-006 documents — a rule-pack fix is forward-only — without using the words watermark or rule pack.
  ///
  /// In en, this message translates to:
  /// **'If a bank\'s messages were not recognised before, they were skipped and never come back on their own. This reads them again and records anything that was missed.'**
  String get recheckBanksIntroBody;

  /// Two facts ADR-006 requires the user be told: the re-scan is dedup-safe (D1's UNIQUE keys), and item (C)'s window is the import's ground, NOT full history. 'Nobody should read check again as full history.'
  ///
  /// In en, this message translates to:
  /// **'Nothing is counted twice, and only messages from the same date range as the first import are read.'**
  String get recheckBanksSafeNote;

  /// KHA-133 primary action label.
  ///
  /// In en, this message translates to:
  /// **'Check my banks again'**
  String get recheckBanksAction;

  /// KHA-133 secondary action, shown on the result and error cards. Re-running is safe by design.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get recheckBanksAgain;

  /// KHA-133 loading state. Indeterminate — the re-scan persists no cursor and so has no honest percentage to report.
  ///
  /// In en, this message translates to:
  /// **'Reading your bank messages again…'**
  String get recheckBanksRunning;

  /// KHA-133 empty result. The re-check ran and everything it saw was already recorded — an outcome, not a failure.
  ///
  /// In en, this message translates to:
  /// **'Nothing new found'**
  String get recheckBanksNothingNew;

  /// KHA-133 non-empty result headline. ICU plural rather than a bare placeholder: this is the sentence the user reads first, and 'Found 1 new transactions' is exactly the kind of sloppiness that costs trust in a screen whose whole job is explaining retroactive numbers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Found 1 new transaction} other{Found {count} new transactions}}'**
  String recheckBanksFound(int count);

  /// KHA-133 result detail. 'count' is messages actually re-read (bank senders only); 'since' names item (C)'s window so an empty result is unambiguous about what ground was covered. The =0 case is real: a window with no bank messages at all.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No bank messages to re-check, back to {since}.} =1{1 bank message re-checked, back to {since}.} other{{count} bank messages re-checked, back to {since}.}}'**
  String recheckBanksExamined(int count, String since);

  /// KHA-133 result detail. A recovered message from a bank whose rules cannot parse it lands in Needs Review — still a success, but the user must be told where it went.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 of them needs review before it can be recorded.} other{{count} of them need review before they can be recorded.}}'**
  String recheckBanksNeedReview(int count);

  /// KHA-133 partial-failure detail. Shown rather than hidden: a run that hit errors covered less than it appears to have, and a silently incomplete recovery looks complete.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message could not be read this time. Try again later.} other{{count} messages could not be read this time. Try again later.}}'**
  String recheckBanksSomeFailed(int count);

  /// KHA-133 locked state. ADR-005 makes the lock cryptographic — with no unwrapped key there is no database to write to, so this is an expected state and not an error.
  ///
  /// In en, this message translates to:
  /// **'The app locked before this could run. Unlock and try again.'**
  String get recheckBanksLocked;

  /// KHA-133 unauthorized state (AC-A1.3). Android 11+ can auto-revoke READ_SMS on an unused app, so this is live rather than theoretical.
  ///
  /// In en, this message translates to:
  /// **'Massrofy cannot read your messages right now, so there is nothing to re-check. Grant SMS access and try again.'**
  String get recheckBanksNoPermission;

  /// KHA-133 error state. The second sentence matters: the user's first fear on seeing an error from a button that rewrites history is that it broke something.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while re-checking. Your existing transactions are unaffected.'**
  String get recheckBanksError;
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
