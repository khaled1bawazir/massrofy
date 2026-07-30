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
  String get navHome => 'Home';

  @override
  String get navTransactions => 'Transactions';

  @override
  String get navMore => 'More';

  @override
  String get homeThisMonth => 'This month';

  @override
  String get homeNoSpendThisMonth => 'No transactions recorded yet this month';

  @override
  String get homeEmptyTitle => 'No transactions yet';

  @override
  String get homeEmptyBody =>
      'As soon as your bank sends a transaction message it appears here automatically. You can also add a cash transaction by hand.';

  @override
  String get homeAddManually => 'Add a transaction manually';

  @override
  String get homeRecentTransactions => 'Recent transactions';

  @override
  String get homeViewAll => 'View all';

  @override
  String get homeLockNow => 'Lock now';

  @override
  String get periodPreviousMonth => 'Previous month';

  @override
  String get periodNextMonth => 'Next month';

  @override
  String get periodCurrentMonth => 'This month';

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

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonRename => 'Rename';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonRetry => 'Try again';

  @override
  String get categoriesTitle => 'Categories';

  @override
  String get categoriesEmptyTitle => 'No categories yet';

  @override
  String get categoriesEmptyBody =>
      'Your starter categories will appear here as soon as the app finishes setting up.';

  @override
  String get categoriesUnavailable =>
      'Your categories could not be loaded. Nothing has been changed.';

  @override
  String get categoryGroupSpending => 'Spending';

  @override
  String get categoryGroupMoneyMovement => 'Money movement';

  @override
  String categoryRowTransactionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions',
      one: '1 transaction',
      zero: 'No transactions',
    );
    return '$_temp0';
  }

  @override
  String categoryRowSystemCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions · System category',
      one: '1 transaction · System category',
      zero: 'System category — cannot be renamed or deleted',
    );
    return '$_temp0';
  }

  @override
  String get categoryRenameTitle => 'Rename category';

  @override
  String categoryRenamed(String name) {
    return 'Renamed to $name';
  }

  @override
  String categoryDeleteTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String categoryDeleteInUseBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This category has $count transactions. Choose what happens to them:',
      one: 'This category has 1 transaction. Choose what happens to it:',
    );
    return '$_temp0';
  }

  @override
  String get categoryDeleteEmptyBody =>
      'Nothing is using this category, so nothing else will change.';

  @override
  String get categoryDeleteReassignLabel => 'Move its transactions to';

  @override
  String categoryDeleted(String name) {
    return 'Deleted $name';
  }

  @override
  String get categoryPickerTitle => 'Choose a category';

  @override
  String categoryPickerTitleFor(String merchant) {
    return 'Categorize · $merchant';
  }

  @override
  String get categoryPickerSearchHint => 'Search categories';

  @override
  String get categoryPickerRecent => 'Recent';

  @override
  String categoryPickerNoResults(String query) {
    return 'No category matches \"$query\"';
  }

  @override
  String get categoryPickerNewCategory => 'New category';

  @override
  String get categoryNewNameLabel => 'Category name';

  @override
  String get categoryNewIconLabel => 'Icon';

  @override
  String get categoryNewCreateAndUse => 'Create and use';

  @override
  String get categoryNewDuplicateName =>
      'A category with this name already exists — choose another name';

  @override
  String categoryAppliedAs(String category) {
    return 'Categorized as $category';
  }

  @override
  String categoryScopeQuestion(String merchant) {
    return 'Apply this to future transactions from \"$merchant\" too?';
  }

  @override
  String get categoryScopeQuestionGeneric =>
      'Apply this to future transactions from this merchant too?';

  @override
  String get categoryScopeFuture => 'This and future ones';

  @override
  String get categoryScopeFutureHint =>
      'Creates or updates this merchant\'s rule';

  @override
  String categoryScopeFutureCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Also fills in $count earlier uncategorized transactions',
      one: 'Also fills in 1 earlier uncategorized transaction',
      zero: 'Creates or updates this merchant\'s rule',
    );
    return '$_temp0';
  }

  @override
  String get categoryScopeThisOnly => 'Just this transaction';

  @override
  String get categoryScopeThisOnlyHint =>
      'Leaves this merchant\'s existing rule exactly as it is';

  @override
  String get categoryScopeAutoConfirm => 'Applying in a moment…';

  @override
  String get correctionAppliedToOne => 'Category updated';

  @override
  String correctionAppliedToMany(int count, String merchant) {
    return 'Updated $count transactions from $merchant';
  }

  @override
  String get categoryAutoApplied => 'Applied automatically';

  @override
  String get categoryConfidenceHigh => 'Confident match';

  @override
  String get categoryConfidenceLow => 'Not sure';

  @override
  String get categoryConfidenceNone => 'No match found';

  @override
  String categoryConfidenceWithValue(String label, int percent) {
    return '$label ($percent%)';
  }

  @override
  String get reviewReasonUnknownMerchant =>
      'We have not seen this merchant before — where does its spending belong?';

  @override
  String get reviewReasonNoRuleForMerchant =>
      'We know this merchant, but nobody has said which category it belongs in';

  @override
  String get reviewReasonLowConfidence =>
      'We found a close match but we are not sure enough to apply it';

  @override
  String get reviewReasonGeneric => 'This one needs your judgement';

  @override
  String get reviewInboxUnavailable =>
      'The review inbox could not be loaded. Nothing has been changed.';

  @override
  String get reviewCountAllClear => 'All caught up';

  @override
  String reviewCountNeedsReview(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items need review',
      one: '1 item needs review',
    );
    return '$_temp0';
  }

  @override
  String reviewCountBreakdown(int unparsed, int transactions) {
    return '$unparsed not understood · $transactions transactions to check';
  }

  @override
  String get reviewCountUnavailable =>
      'The review count is unavailable right now';

  @override
  String get learnedRulesTitle => 'Learned rules';

  @override
  String get learnedRulesEmptyTitle => 'No rules yet';

  @override
  String get learnedRulesEmptyBody =>
      'Correcting any transaction\'s category teaches a rule automatically, so the next one from that merchant arrives already sorted.';

  @override
  String get learnedRulesUnavailable =>
      'Your learned rules could not be loaded. Nothing has been changed.';

  @override
  String ruleAppliedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Applied to $count transactions',
      one: 'Applied to 1 transaction',
      zero: 'Not applied yet',
    );
    return '$_temp0';
  }

  @override
  String get ruleSourceSeed => '· Built in';

  @override
  String ruleEditTitle(String merchant) {
    return 'Edit rule for $merchant';
  }

  @override
  String ruleEditCurrentCategory(String category) {
    return 'Currently: $category';
  }

  @override
  String get ruleEditNewCategory => 'New category';

  @override
  String ruleReapplyPrompt(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Also re-apply this to $count existing transactions from this merchant?',
      one: 'Also re-apply this to 1 existing transaction from this merchant?',
      zero: 'No existing transactions would change.',
    );
    return '$_temp0';
  }

  @override
  String get ruleReapplyPromptCounting =>
      'Checking how many existing transactions this would change…';

  @override
  String ruleReapplyYes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Yes, $count transactions',
      zero: 'Re-apply',
    );
    return '$_temp0';
  }

  @override
  String get ruleReapplyNo => 'Going forward only';

  @override
  String ruleReappliedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Rule updated and re-applied to $count transactions',
      one: 'Rule updated and re-applied to 1 transaction',
      zero: 'Rule updated. No existing transactions needed changing.',
    );
    return '$_temp0';
  }

  @override
  String get ruleUpdatedGoingForward =>
      'Rule updated. Existing transactions were left as they are.';

  @override
  String get ruleEditRefused =>
      'That category is no longer available, so the rule was not changed';

  @override
  String ruleDeleteTitle(String merchant) {
    return 'Delete the rule for $merchant?';
  }

  @override
  String get ruleDeleteBody =>
      'Future transactions from this merchant will arrive uncategorized. Transactions you have already categorized keep their categories.';

  @override
  String get ruleDeleted => 'Rule deleted';

  @override
  String get categoryWhyThisCategory => 'Why this category?';

  @override
  String get categoryProvenanceUser => 'You chose this category.';

  @override
  String categoryProvenanceAutomatic(int percent) {
    return 'A learned rule applied this automatically, at $percent% confidence.';
  }

  @override
  String get categoryProvenanceUndecided =>
      'The app looked and could not decide, so this is left uncategorized.';

  @override
  String get categoryProvenanceUnknownSource =>
      'This category was set before the app started recording how.';

  @override
  String categoryProvenanceRule(String merchant) {
    return 'Rule: $merchant';
  }

  @override
  String get categoryProvenanceRuleGone =>
      'The rule that did this has since been deleted.';

  @override
  String get categoryProvenanceNoHistory =>
      'No categorization history for this transaction yet.';

  @override
  String categoryProvenanceEntry(String when, String actor) {
    return '$when · $actor';
  }

  @override
  String get categoryProvenanceUnavailable =>
      'The history for this category could not be loaded.';

  @override
  String get categoryActorUser => 'You';

  @override
  String get categoryActorRule => 'A learned rule';

  @override
  String get categoryActorSystem => 'The app';

  @override
  String get categoryLockedBody =>
      'Your categories are encrypted and stay locked until you unlock the app.';

  @override
  String get transactionUnavailable => 'This transaction could not be loaded.';

  @override
  String get transactionGoneTitle => 'This transaction is no longer here';

  @override
  String get transactionGoneBody =>
      'It was deleted or merged into another transaction. You can find it under Recently deleted.';

  @override
  String get completionMessageGone =>
      'That message is no longer in the review queue';

  @override
  String get txnListTotalForPeriod => 'Total';

  @override
  String get txnListEmptyTitle => 'No transactions yet';

  @override
  String get txnListEmptyBody =>
      'Transactions appear here as soon as your bank messages arrive. You can also add one by hand.';

  @override
  String get txnListEmptyForPeriodTitle => 'Nothing in this month';

  @override
  String get txnListEmptyForPeriodBody =>
      'There are no transactions in the month you are viewing. Use the arrows above to look at another month.';

  @override
  String txnListUnreadableNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count transactions could not be read and are not included in the total',
      one: '1 transaction could not be read and is not included in the total',
    );
    return '$_temp0';
  }

  @override
  String get txnDeletedToRecentlyDeleted => 'Moved to Recently deleted';

  @override
  String get txnRestoredConfirmation => 'Transaction restored';

  @override
  String get txnEditSavedConfirmation => 'Transaction updated';

  @override
  String get txnEditTargetMissing => 'That transaction is no longer here';

  @override
  String get smsLimitedModeContinue => 'Continue to Massrofy';

  @override
  String get moreSectionData => 'Your money';

  @override
  String get moreSectionOrganise => 'Organising';

  @override
  String get moreSectionApp => 'App';

  @override
  String get commonApply => 'Apply';

  @override
  String get commonClose => 'Close';

  @override
  String get navReports => 'Reports';

  @override
  String get reportsHubTitle => 'Reports';

  @override
  String get reportsHubSubtitle =>
      'Every figure here is the sum of transactions you can open and check.';

  @override
  String get reportsByCategory => 'By category';

  @override
  String reportsByCategorySummary(String name, String amount) {
    return 'Top category: $name — $amount';
  }

  @override
  String get reportsByCard => 'By card and account';

  @override
  String reportsByCardSummary(String name, String amount) {
    return 'Most used: $name — $amount';
  }

  @override
  String get reportsMonthOverMonth => 'Month over month';

  @override
  String get reportsSpentVsKept => 'Spent vs kept';

  @override
  String get reportsNothingYetTitle => 'Nothing to report yet';

  @override
  String get reportsNothingYetBody =>
      'Once a bank message arrives, or you add a transaction by hand, the breakdowns appear here.';

  @override
  String get reportsUnavailable => 'These figures could not be loaded.';

  @override
  String categoryBreakdownShareOfPeriod(int percent) {
    return '$percent% of the period';
  }

  @override
  String get categoryBreakdownShareUnknown => 'share not available';

  @override
  String get categoryBreakdownTotalLine => 'Total';

  @override
  String get categoryBreakdownReconciliationFailed =>
      'These category figures do not add up to the period total. Please report this.';

  @override
  String categoryBreakdownOpenTransactions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Show all $count transactions',
      one: 'Show the 1 transaction',
    );
    return '$_temp0';
  }

  @override
  String get categoryBreakdownEmptyCategoryNote =>
      'No transactions in this category this period';

  @override
  String categoryBreakdownMovementOnlyNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions, not counted as spending',
      one: '1 transaction, not counted as spending',
    );
    return '$_temp0';
  }

  @override
  String get instrumentBreakdownUnassigned => 'Cash and unmatched';

  @override
  String get instrumentBreakdownTotalLine => 'Total';

  @override
  String get instrumentBreakdownReconciliationFailed =>
      'These card figures do not add up to the period total. Please report this.';

  @override
  String get instrumentBreakdownNoActivity => 'Not used this period';

  @override
  String instrumentBreakdownBankLabel(String instrument, String bank) {
    return '$instrument · $bank';
  }

  @override
  String monthComparisonThisPeriod(String month) {
    return '$month (this period)';
  }

  @override
  String monthComparisonPriorPeriod(String month) {
    return '$month (previous)';
  }

  @override
  String monthComparisonUp(String amount, String month) {
    return '$amount more than $month';
  }

  @override
  String monthComparisonDown(String amount, String month) {
    return '$amount less than $month';
  }

  @override
  String monthComparisonSame(String month) {
    return 'The same as $month';
  }

  @override
  String get monthComparisonInsufficientTitle => 'Not enough history yet';

  @override
  String get monthComparisonInsufficientBody =>
      'Check back after your second month of use to see a comparison you can rely on.';

  @override
  String get monthComparisonIncomplete =>
      'One of these periods contains transactions the app could not convert, so the difference is not shown.';

  @override
  String get searchTransactionsHint => 'Search a merchant name';

  @override
  String get searchClear => 'Clear search';

  @override
  String get filterTitle => 'Filter';

  @override
  String get filterOpen => 'Filter transactions';

  @override
  String filterActiveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count filters',
      one: '1 filter',
    );
    return '$_temp0';
  }

  @override
  String get filterClearAll => 'Clear filters';

  @override
  String get filterSectionDates => 'Date range';

  @override
  String get filterSectionCategories => 'Categories';

  @override
  String get filterSectionInstruments => 'Cards and accounts';

  @override
  String get filterSectionAmount => 'Amount range';

  @override
  String get filterAmountMin => 'From';

  @override
  String get filterAmountMax => 'To';

  @override
  String filterAmountCurrencyNote(String currency) {
    return 'Compared in $currency, using the rate each transaction recorded.';
  }

  @override
  String get filterAmountInvalid => 'Enter an amount like 45.00';

  @override
  String get filterAmountRangeInverted =>
      'The lower bound is above the upper bound';

  @override
  String get filterDateFrom => 'From';

  @override
  String get filterDateTo => 'To';

  @override
  String get filterDateAny => 'Any date';

  @override
  String filterNotComparableByAmount(int count, String currency) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions have no $currency figure and are not shown',
      one: '1 transaction has no $currency figure and is not shown',
    );
    return '$_temp0';
  }

  @override
  String get txnListFilteredEmptyTitle => 'No transactions match';

  @override
  String get txnListFilteredEmptyBody =>
      'Nothing in this month matches what you searched for. Clearing the filter brings the full list back.';

  @override
  String get txnListFilteredTotal => 'Filtered total';

  @override
  String txnListResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions',
      one: '1 transaction',
      zero: 'No transactions',
    );
    return '$_temp0';
  }

  @override
  String get recheckBanksTitle => 'Check my banks again';

  @override
  String get recheckBanksIntroTitle => 'Messages that were missed';

  @override
  String get recheckBanksIntroBody =>
      'If a bank\'s messages were not recognised before, they were skipped and never come back on their own. This reads them again and records anything that was missed.';

  @override
  String get recheckBanksSafeNote =>
      'Nothing is counted twice, and only messages from the same date range as the first import are read.';

  @override
  String get recheckBanksAction => 'Check my banks again';

  @override
  String get recheckBanksAgain => 'Check again';

  @override
  String get recheckBanksRunning => 'Reading your bank messages again…';

  @override
  String get recheckBanksNothingNew => 'Nothing new found';

  @override
  String recheckBanksFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $count new transactions',
      one: 'Found 1 new transaction',
    );
    return '$_temp0';
  }

  @override
  String recheckBanksExamined(int count, String since) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bank messages re-checked, back to $since.',
      one: '1 bank message re-checked, back to $since.',
      zero: 'No bank messages to re-check, back to $since.',
    );
    return '$_temp0';
  }

  @override
  String recheckBanksNeedReview(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count of them need review before they can be recorded.',
      one: '1 of them needs review before it can be recorded.',
    );
    return '$_temp0';
  }

  @override
  String recheckBanksSomeFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages could not be read this time. Try again later.',
      one: '1 message could not be read this time. Try again later.',
    );
    return '$_temp0';
  }

  @override
  String get recheckBanksLocked =>
      'The app locked before this could run. Unlock and try again.';

  @override
  String get recheckBanksNoPermission =>
      'Massrofy cannot read your messages right now, so there is nothing to re-check. Grant SMS access and try again.';

  @override
  String get recheckBanksError =>
      'Something went wrong while re-checking. Your existing transactions are unaffected.';
}
