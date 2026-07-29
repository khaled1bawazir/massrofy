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

  @override
  String get transactionDetailTitle => 'Transaction';

  @override
  String get fieldNotStatedInMessage => 'Not stated in message';

  @override
  String get txnFieldDateTime => 'Date & time';

  @override
  String get txnFieldInstrument => 'Account / card';

  @override
  String get txnFieldType => 'Type';

  @override
  String get txnFieldSource => 'Source';

  @override
  String get txnFieldMerchant => 'Merchant / payee';

  @override
  String get txnFieldCounterparty => 'Counterparty';

  @override
  String get txnFieldCounterpartyBank => 'Counterparty bank';

  @override
  String get txnFieldReference => 'Reference number';

  @override
  String get txnFieldConvertedAmount => 'Converted amount';

  @override
  String get txnFieldFxFee => 'Foreign transaction fee';

  @override
  String get txnFieldExchangeRate => 'Exchange rate';

  @override
  String get txnFieldRemainingBalance => 'Remaining balance';

  @override
  String txnSourceSms(String bank) {
    return 'SMS · $bank';
  }

  @override
  String txnSourceSmsCompletedByYou(String bank) {
    return 'SMS · $bank · completed by you';
  }

  @override
  String get txnSourceManual => 'Manual entry';

  @override
  String get txnSourceStatement => 'Statement import';

  @override
  String get txnShowOriginalSms => 'Show original message';

  @override
  String get txnHideOriginalSms => 'Hide original message';

  @override
  String get txnNoOriginalSms =>
      'No original message — this transaction was added manually';

  @override
  String get txnBadgeManual => 'Manual';

  @override
  String get txnBadgeNeedsReview => 'Needs review';

  @override
  String get txnDebitLabel => 'Debit';

  @override
  String get txnCreditLabel => 'Credit';

  @override
  String get txnDeletedBanner =>
      'This transaction is deleted and is in no total';

  @override
  String get txnUnknownBank => 'Unknown bank';

  @override
  String get txnTypePosPurchase => 'Card purchase';

  @override
  String get txnTypeOnlinePurchase => 'Online purchase';

  @override
  String get txnTypeTransferOut => 'Outgoing transfer';

  @override
  String get txnTypeTransferIn => 'Incoming transfer';

  @override
  String get txnTypeBillPayment => 'Bill payment';

  @override
  String get txnTypeCardRepayment => 'Credit-card repayment';

  @override
  String get txnTypeFee => 'Fee / VAT';

  @override
  String get txnTypeInstallment => 'Finance installment';

  @override
  String get txnTypeAccountDebit => 'Account debit';

  @override
  String get txnTypeRefund => 'Refund';

  @override
  String get txnTypeWithdrawal => 'Cash withdrawal';

  @override
  String get txnTypeUnknown => 'Not specified';

  @override
  String get banksTitle => 'Banks';

  @override
  String get banksEmptyTitle => 'No banks yet';

  @override
  String get banksEmptyBody =>
      'A bank appears here automatically the first time a message arrives from it — there is nothing to set up.';

  @override
  String get bankTotalThisPeriod => 'Total this period';

  @override
  String bankAccountsSection(int count) {
    return 'Accounts ($count)';
  }

  @override
  String bankCardsSection(int count) {
    return 'Cards ($count)';
  }

  @override
  String get bankNoInstruments =>
      'No accounts or cards mentioned for this bank yet';

  @override
  String bankAccountsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
      zero: 'no accounts',
    );
    return '$_temp0';
  }

  @override
  String bankCardsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cards',
      one: '1 card',
      zero: 'no cards',
    );
    return '$_temp0';
  }

  @override
  String bankInstrumentsSummary(String accounts, String cards) {
    return '$accounts · $cards';
  }

  @override
  String get instrumentKindAccount => 'Account';

  @override
  String get instrumentKindCard => 'Card';

  @override
  String get instrumentUnnamed => 'Not named yet';

  @override
  String get instrumentNotLinked => 'Not linked to a settlement account yet';

  @override
  String instrumentLinkedTo(String account) {
    return 'Settles from $account';
  }

  @override
  String get instrumentRenameAction => 'Rename';

  @override
  String get instrumentRenameTitle => 'Rename';

  @override
  String get instrumentRenameFieldLabel => 'Friendly name';

  @override
  String get instrumentRenameSave => 'Save name';

  @override
  String get instrumentRecentTransactions => 'Recent transactions';

  @override
  String get instrumentNoTransactions => 'No transactions on this one yet';

  @override
  String get totalsNoneForPeriod => 'No transactions in this period';

  @override
  String get completeTitle => 'Complete the details';

  @override
  String get completeIntro =>
      'Fill in what the message could not tell us. The original message stays linked to the transaction.';

  @override
  String get completeAmountLabel => 'Amount';

  @override
  String get completeAmountMissing =>
      'Enter an amount to save this transaction';

  @override
  String get completeCurrencyLabel => 'Currency';

  @override
  String get completeCurrencyMissing =>
      'Enter a 3-letter currency code, for example SAR';

  @override
  String get completeMerchantLabel => 'Merchant / payee';

  @override
  String get completeDateLabel => 'Date & time';

  @override
  String get completeDateMissing =>
      'Choose the date and time of the transaction';

  @override
  String get completeTypeLabel => 'Type';

  @override
  String get completeTypeMissing => 'Choose what kind of transaction this is';

  @override
  String get completeInstrumentLabel => 'Account / card';

  @override
  String get completeInstrumentNotStated => 'Not stated';

  @override
  String get completeDirectionDebit => 'Money out';

  @override
  String get completeDirectionCredit => 'Money in';

  @override
  String get completeSave => 'Save as transaction';

  @override
  String get completeOriginalMessage => 'Original message';

  @override
  String get completeUnavailable =>
      'This item is no longer in the review queue';

  @override
  String get completeCategoryDeferred =>
      'Categorisation comes later — this will be saved as Uncategorised and you can categorise it from the list.';

  @override
  String get amountMustBePositive =>
      'Enter an amount greater than zero, then choose Money in or Money out';

  @override
  String get txnFieldFxRateDate => 'Rate date';

  @override
  String get txnFxRateDateUnknown => 'Date unknown';

  @override
  String get txnFieldFxRateSource => 'Rate source';

  @override
  String get txnFxSourceSmsImplied =>
      'Implied by the bank\'s own converted amount';

  @override
  String get txnFxSourceSmsStated => 'Stated in the bank\'s message';

  @override
  String get txnFxSourceUser => 'Entered by you';

  @override
  String get txnFxSourceCarriedForward =>
      'Most recent known rate, carried forward';

  @override
  String txnFxNotConverted(String currency) {
    return 'Not converted to $currency — this message stated no rate, and the app never invents one';
  }

  @override
  String get txnBadgeInternalTransfer => 'Internal transfer';

  @override
  String get txnBadgeInternalTransferCandidate => 'Possible internal transfer';

  @override
  String get txnInternalTransferExcludedNote =>
      'Excluded from spend totals — moving money to yourself is not spending';

  @override
  String get txnInternalTransferCandidateNote =>
      'Still counted as spend until you confirm this went to your own account';

  @override
  String get txnTypeSalaryIncome => 'Salary / income';

  @override
  String totalsNotConverted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions not converted',
      one: '1 transaction not converted',
    );
    return '$_temp0';
  }

  @override
  String get spentVsKeptTitle => 'Spent vs kept';

  @override
  String get spentVsKeptSpent => 'Spent';

  @override
  String get spentVsKeptIncome => 'Received';

  @override
  String get spentVsKeptNet => 'Kept this period';

  @override
  String get spentVsKeptCashOut => 'Cash withdrawn';

  @override
  String get spentVsKeptInternalExcluded => 'Internal transfers excluded';

  @override
  String get spentVsKeptIncomplete =>
      'Some transactions could not be converted, so these figures are incomplete';

  @override
  String spentVsKeptNeedsReview(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions need review before these figures are final',
      one: '1 transaction needs review before these figures are final',
    );
    return '$_temp0';
  }

  @override
  String get manualEntryTitle => 'Add a transaction';

  @override
  String get manualEntryIntro =>
      'For cash, or anything your bank did not send a message about.';

  @override
  String get manualEntrySave => 'Save transaction';

  @override
  String get manualEntryAmountLabel => 'Amount';

  @override
  String get manualEntryAmountMissing =>
      'Enter an amount to save this transaction';

  @override
  String get manualEntryAmountUnparsable =>
      'That is not an amount this app can read — use digits and at most one decimal separator';

  @override
  String get manualEntryCurrencyLabel => 'Currency';

  @override
  String get manualEntryCurrencyMissing =>
      'Enter a three-letter currency code, such as SAR';

  @override
  String get manualEntryDateLabel => 'When it happened';

  @override
  String get manualEntryDateMissing => 'Choose the date and time this happened';

  @override
  String get manualEntryTypeLabel => 'What kind of transaction';

  @override
  String get manualEntryTypeMissing =>
      'Choose what kind of transaction this was';

  @override
  String get manualEntryMerchantLabel => 'Merchant or description';

  @override
  String get manualEntrySourceLabel => 'Paid with';

  @override
  String get manualEntrySourceCash => 'Cash';

  @override
  String get manualEntryCashNote =>
      'Cash transactions count toward your totals exactly like card ones.';

  @override
  String get manualEntrySaved => 'Transaction added';

  @override
  String get txnEditTitle => 'Edit transaction';

  @override
  String get txnEditSave => 'Save changes';

  @override
  String get txnEditSaved => 'Changes saved';

  @override
  String get txnEditNoChanges => 'Nothing was changed';

  @override
  String txnEditOriginalValue(String value) {
    return 'Originally detected: $value';
  }

  @override
  String get txnEditOriginalValueEmpty => 'Originally detected: nothing';

  @override
  String get txnEditProtectedFromRescan =>
      'Your edit is kept — re-reading the message will not overwrite it';

  @override
  String get txnDeleteAction => 'Delete';

  @override
  String get txnDeleteConfirmTitle => 'Delete this transaction?';

  @override
  String get txnDeleteConfirmBody =>
      'It will be removed from your lists and totals, and moved to Recently deleted. You can restore it from there.';

  @override
  String get txnDeleteConfirmCancel => 'Keep it';

  @override
  String get txnDeleteConfirmAccept => 'Delete';

  @override
  String get txnDeleted => 'Transaction deleted';

  @override
  String get txnDeletedUndo => 'Undo';

  @override
  String get txnRestoreAction => 'Restore';

  @override
  String get txnRestored => 'Transaction restored';

  @override
  String get recentlyDeletedTitle => 'Recently deleted';

  @override
  String get recentlyDeletedIntro =>
      'Deleted transactions are kept here and are not counted in any total. Only Erase everything removes them permanently.';

  @override
  String get recentlyDeletedEmpty => 'Nothing has been deleted';

  @override
  String get recentlyDeletedEmptyBody =>
      'Transactions you delete will appear here so you can bring them back.';

  @override
  String recentlyDeletedOn(String when) {
    return 'Deleted $when';
  }

  @override
  String recentlyDeletedMergedInto(int id) {
    return 'Merged into transaction #$id';
  }

  @override
  String get reviewTransferCandidateTitle =>
      'Was this a transfer to your own account?';

  @override
  String get reviewTransferConfirm => 'Yes, my own account';

  @override
  String get reviewTransferReject => 'No, someone else';

  @override
  String get reviewTransferConfirmed =>
      'Excluded from spend — both sides of the transfer';

  @override
  String get reviewTransferRejected =>
      'Counted as a payment — we will not ask about this one again';

  @override
  String get reviewTransferCrossCurrency =>
      'A transfer in another currency happened at about the same time. We cannot match them without inventing an exchange rate, so both are still counted.';

  @override
  String get reviewTransferUnresolvedInstrument =>
      'A matching transfer arrived at about the same time, but we could not tell which account it reached, so this is still counted as spending.';

  @override
  String get reviewTransferDismiss => 'Not an internal transfer';

  @override
  String get reviewDuplicateTitle => 'Are these the same transaction?';

  @override
  String get reviewDuplicateBody =>
      'Both are counted in your totals until you decide. Merging keeps one and files the other under Recently deleted — nothing is destroyed.';

  @override
  String get reviewDuplicateMerge => 'Yes, merge them';

  @override
  String get reviewDuplicateKeepBoth => 'No, keep both';

  @override
  String get reviewMergeConfirmTitle => 'Merge these two into one?';

  @override
  String get reviewMergeConfirmBody =>
      'One of them will stay in your lists and totals. The other moves to Recently deleted, keeps its own message, and can be restored at any time — nothing is destroyed.';

  @override
  String get reviewMergeConfirmCancel => 'Keep both';

  @override
  String get reviewMergeConfirmAccept => 'Merge them';

  @override
  String get reviewMergeRefusedFee =>
      'These state different fees, so they cannot be merged automatically';

  @override
  String get reviewMergeRefusedConversion =>
      'These state different converted amounts or exchange rates, so they cannot be merged';

  @override
  String get reviewMergeRefusedBalance =>
      'These report different balances after the transaction, so they cannot be merged';

  @override
  String get reviewMergeRefusedSpendEffect =>
      'These count differently toward your spending, so they cannot be merged';

  @override
  String get reviewMergeRefusedUserEdit =>
      'You have corrected a detail on one of these and the other says something different — please check them before merging';

  @override
  String get reviewMergeRefusedChain =>
      'One of these has already absorbed another transaction, so it cannot be merged again';

  @override
  String get reviewDuplicateMerged =>
      'Merged — one transaction now, traceable to both messages';

  @override
  String get reviewDuplicateKeptBoth => 'Both kept';

  @override
  String get reviewMergeRefusedAmount =>
      'These have different amounts, so they cannot be the same transaction';

  @override
  String get reviewMergeRefusedDirection =>
      'One of these is money in and the other is money out, so they cannot be merged';

  @override
  String get reviewMergeRefusedType =>
      'These are different kinds of transaction, so they cannot be merged';

  @override
  String get reviewMergeRefusedState =>
      'One of these is no longer active, so there is nothing to merge';

  @override
  String get reviewDataProblemTitle => 'A transaction could not be read';

  @override
  String reviewDataProblemBody(int id) {
    return 'Transaction #$id is stored with an amount this app cannot read, so it is missing from your totals. Nothing has been changed or removed. Restoring a backup is the safest way to recover it.';
  }

  @override
  String reviewDataProblemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions are missing from your totals',
      one: '1 transaction is missing from your totals',
    );
    return '$_temp0';
  }

  @override
  String needsReviewTabTransfers(int count) {
    return 'Transfers ($count)';
  }
}
