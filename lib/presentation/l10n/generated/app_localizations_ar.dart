// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'مصروفي';

  @override
  String get lockGateUnlockToView => 'افتح القفل لعرض بياناتك';

  @override
  String get lockGateBiometricHint => 'ضع إصبعك على المستشعر';

  @override
  String get lockGateUsePinInstead => 'استخدام رمز PIN بدلاً من ذلك';

  @override
  String get lockGateUsePasscode => 'استخدام رمز الجهاز بدلاً من ذلك';

  @override
  String get lockGateAuthFailed => 'تعذّرت المصادقة. حاول مرة أخرى.';

  @override
  String get lockGateEnterPin => 'أدخل رمز PIN';

  @override
  String get lockGateTooManyAttempts => 'محاولات كثيرة جداً';

  @override
  String lockGateRetryIn(String seconds) {
    return 'حاول مرة أخرى خلال $seconds، أو استخدم رمز PIN';
  }

  @override
  String get lockGateSessionExpiredBanner =>
      'انتهت الجلسة أثناء تصفّح التطبيق في الخلفية. أعد فتح القفل للمتابعة من حيث توقفت.';

  @override
  String get lockGateContinueUnlock => 'افتح القفل للمتابعة';

  @override
  String get lockGateUnlockButtonSemanticLabel => 'افتح القفل ببصمتك';

  @override
  String get homePlaceholderTitle => 'الرئيسية';

  @override
  String get homePlaceholderBody =>
      'هذه نسخة الأساس (Foundation) من مصروفي. رصد الرسائل والتصنيف والتقارير تُبنى في مراحل لاحقة — هذه الشاشة تثبت فقط أن التطبيق يعمل، ويُفتح قفله، ويقرأ ويكتب في مخزنه المشفّر بشكل صحيح.';

  @override
  String get smsRationaleTitle => 'لماذا يحتاج مصروفي إلى إذن الرسائل';

  @override
  String get smsRationaleLead =>
      'يرسل بنكك تنبيهات المعاملات عبر الرسائل النصية. يقرأ مصروفي هذه الرسائل فقط، على جهازك، لبناء صورة إنفاقك.';

  @override
  String get smsRationalePointOnDevice => 'تتم المعالجة بالكامل على هاتفك';

  @override
  String get smsRationalePointNoSharing =>
      'لا تُرسل أي بيانات إلينا أو لأي جهة أخرى';

  @override
  String get smsRationalePointRevocable => 'يمكنك إلغاء الإذن في أي وقت';

  @override
  String get smsRationalePointNoiseIgnored =>
      'الرسائل غير المالية تُتجاهل ولا تُخزَّن أبداً';

  @override
  String get smsRationaleGrant => 'منح إذن الرسائل';

  @override
  String get smsRationaleNotNow => 'ليس الآن';

  @override
  String get smsLimitedModeTitle => 'الوضع المحدود مفعّل';

  @override
  String get smsLimitedModeBody =>
      'بدون إذن الرسائل، لن تُضاف المعاملات تلقائياً. لا تزال بياناتك السابقة (إن وُجدت) سليمة، ويمكنك إضافة المعاملات يدوياً في أي وقت.';

  @override
  String get smsLimitedModeOpenSettings => 'فتح إعدادات النظام';

  @override
  String get smsLimitedModeTryAgain => 'منح إذن الرسائل';

  @override
  String get smsLimitedModeAddManually => 'إضافة معاملة يدوياً';

  @override
  String get smsRevokedBannerTitle => 'تم إيقاف إذن الرسائل';

  @override
  String get importProgressTitle => 'جارٍ استيراد رسائلك';

  @override
  String importProgressFound(int count) {
    return 'تم العثور على $count معاملة حتى الآن…';
  }

  @override
  String get importProgressContinueInBackground => 'المتابعة في الخلفية';

  @override
  String get importProgressScopeNote =>
      'يستورد مصروفي الرسائل من بداية هذا الشهر.';

  @override
  String get needsReviewTitle => 'بحاجة إلى مراجعة';

  @override
  String needsReviewTabUnparsed(int count) {
    return 'غير مفهومة ($count)';
  }

  @override
  String needsReviewTabLowConfidence(int count) {
    return 'منخفضة الثقة ($count)';
  }

  @override
  String get needsReviewEmpty => 'لا شيء يحتاج مراجعة الآن';

  @override
  String get needsReviewEmptyBody => 'كل الرسائل والمعاملات مصنَّفة وواضحة.';

  @override
  String get needsReviewFillInDetails => 'أكمل التفاصيل';

  @override
  String get needsReviewNotATransaction => 'ليست معاملة';

  @override
  String needsReviewReceivedFrom(String time, String sender) {
    return 'استُلمت $time · المرسل: $sender';
  }

  @override
  String get needsReviewPossibleDuplicate => 'تكرار محتمل';

  @override
  String get needsReviewReasonNoRule => 'لم تطابق هذه الرسالة أي صيغة معروفة';

  @override
  String get needsReviewReasonMissingField =>
      'بعض التفاصيل كانت ناقصة في هذه الرسالة';

  @override
  String get transactionDetailTitle => 'المعاملة';

  @override
  String get fieldNotStatedInMessage => 'غير مذكور في الرسالة';

  @override
  String get txnFieldDateTime => 'التاريخ والوقت';

  @override
  String get txnFieldInstrument => 'أداة الدفع';

  @override
  String get txnFieldType => 'النوع';

  @override
  String get txnFieldSource => 'المصدر';

  @override
  String get txnFieldMerchant => 'التاجر / الجهة';

  @override
  String get txnFieldCounterparty => 'الطرف الآخر';

  @override
  String get txnFieldCounterpartyBank => 'بنك الطرف الآخر';

  @override
  String get txnFieldReference => 'رقم العملية';

  @override
  String get txnFieldConvertedAmount => 'المبلغ بعد التحويل';

  @override
  String get txnFieldFxFee => 'رسوم التحويل الدولي';

  @override
  String get txnFieldExchangeRate => 'سعر الصرف';

  @override
  String get txnFieldRemainingBalance => 'الرصيد المتبقي';

  @override
  String txnSourceSms(String bank) {
    return 'رسالة نصية · $bank';
  }

  @override
  String txnSourceSmsCompletedByYou(String bank) {
    return 'رسالة نصية · $bank · أكملتها بنفسك';
  }

  @override
  String get txnSourceManual => 'إدخال يدوي';

  @override
  String get txnSourceStatement => 'كشف حساب';

  @override
  String get txnShowOriginalSms => 'عرض الرسالة الأصلية';

  @override
  String get txnHideOriginalSms => 'إخفاء الرسالة الأصلية';

  @override
  String get txnNoOriginalSms =>
      'لا توجد رسالة أصلية — أُضيفت هذه المعاملة يدوياً';

  @override
  String get txnBadgeManual => 'يدوي';

  @override
  String get txnBadgeNeedsReview => 'بحاجة إلى مراجعة';

  @override
  String get txnDebitLabel => 'مدين';

  @override
  String get txnCreditLabel => 'دائن';

  @override
  String get txnDeletedBanner => 'هذه المعاملة محذوفة ولا تدخل في أي إجمالي';

  @override
  String get txnUnknownBank => 'بنك غير معروف';

  @override
  String get txnTypePosPurchase => 'شراء نقطة بيع';

  @override
  String get txnTypeOnlinePurchase => 'شراء عبر الإنترنت';

  @override
  String get txnTypeTransferOut => 'حوالة صادرة';

  @override
  String get txnTypeTransferIn => 'حوالة واردة';

  @override
  String get txnTypeBillPayment => 'سداد فاتورة';

  @override
  String get txnTypeCardRepayment => 'سداد بطاقة ائتمانية';

  @override
  String get txnTypeFee => 'رسوم / ضريبة';

  @override
  String get txnTypeInstallment => 'قسط تمويل';

  @override
  String get txnTypeAccountDebit => 'خصم من الحساب';

  @override
  String get txnTypeRefund => 'استرداد';

  @override
  String get txnTypeWithdrawal => 'سحب نقدي';

  @override
  String get txnTypeUnknown => 'غير محدد';

  @override
  String get banksTitle => 'البنوك';

  @override
  String get banksEmptyTitle => 'لا توجد بنوك بعد';

  @override
  String get banksEmptyBody =>
      'سيظهر البنك تلقائياً أول مرة تصل فيها رسالة منه — لا حاجة لإعداد شيء.';

  @override
  String get bankTotalThisPeriod => 'الإجمالي هذه الفترة';

  @override
  String bankAccountsSection(int count) {
    return 'الحسابات ($count)';
  }

  @override
  String bankCardsSection(int count) {
    return 'البطاقات ($count)';
  }

  @override
  String get bankNoInstruments => 'لم تُذكر أي حسابات أو بطاقات لهذا البنك بعد';

  @override
  String bankAccountsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count حساب',
      many: '$count حساباً',
      few: '$count حسابات',
      two: 'حسابان',
      one: 'حساب واحد',
      zero: 'لا حسابات',
    );
    return '$_temp0';
  }

  @override
  String bankCardsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count بطاقة',
      many: '$count بطاقة',
      few: '$count بطاقات',
      two: 'بطاقتان',
      one: 'بطاقة واحدة',
      zero: 'لا بطاقات',
    );
    return '$_temp0';
  }

  @override
  String bankInstrumentsSummary(String accounts, String cards) {
    return '$accounts · $cards';
  }

  @override
  String get instrumentKindAccount => 'حساب';

  @override
  String get instrumentKindCard => 'بطاقة';

  @override
  String get instrumentUnnamed => 'غير مُسمّاة بعد';

  @override
  String get instrumentNotLinked => 'غير مرتبطة بحساب تسوية بعد';

  @override
  String instrumentLinkedTo(String account) {
    return 'تُسدَّد من $account';
  }

  @override
  String get instrumentRenameAction => 'إعادة تسمية';

  @override
  String get instrumentRenameTitle => 'إعادة تسمية';

  @override
  String get instrumentRenameFieldLabel => 'الاسم المألوف';

  @override
  String get instrumentRenameSave => 'حفظ الاسم';

  @override
  String get instrumentRecentTransactions => 'أحدث المعاملات';

  @override
  String get instrumentNoTransactions => 'لا معاملات على هذه الأداة بعد';

  @override
  String get totalsNoneForPeriod => 'لا معاملات في هذه الفترة';

  @override
  String get completeTitle => 'إكمال التفاصيل';

  @override
  String get completeIntro =>
      'املأ ما لم تستطع الرسالة إخبارنا به. تبقى الرسالة الأصلية مرتبطة بالمعاملة.';

  @override
  String get completeAmountLabel => 'المبلغ';

  @override
  String get completeAmountMissing => 'أدخل مبلغاً لحفظ هذه المعاملة';

  @override
  String get completeCurrencyLabel => 'العملة';

  @override
  String get completeCurrencyMissing => 'أدخل رمز عملة من ثلاثة أحرف، مثل SAR';

  @override
  String get completeMerchantLabel => 'التاجر / الجهة';

  @override
  String get completeDateLabel => 'التاريخ والوقت';

  @override
  String get completeDateMissing => 'اختر تاريخ ووقت المعاملة';

  @override
  String get completeTypeLabel => 'النوع';

  @override
  String get completeTypeMissing => 'اختر نوع هذه المعاملة';

  @override
  String get completeInstrumentLabel => 'الحساب / البطاقة';

  @override
  String get completeInstrumentNotStated => 'غير مذكور';

  @override
  String get completeDirectionDebit => 'خصم';

  @override
  String get completeDirectionCredit => 'إيداع';

  @override
  String get completeSave => 'حفظ كمعاملة';

  @override
  String get completeOriginalMessage => 'الرسالة الأصلية';

  @override
  String get completeUnavailable => 'لم تعد هذه الرسالة في قائمة المراجعة';

  @override
  String get completeCategoryDeferred =>
      'التصنيف يأتي لاحقاً — ستُحفظ المعاملة كـ«غير مصنفة» ويمكنك تصنيفها من قائمتها.';

  @override
  String get amountMustBePositive =>
      'أدخل مبلغاً أكبر من صفر، ثم اختر «إيداع» أو «سحب»';

  @override
  String get txnFieldFxRateDate => 'تاريخ سعر الصرف';

  @override
  String get txnFxRateDateUnknown => 'التاريخ غير معروف';

  @override
  String get txnFieldFxRateSource => 'مصدر سعر الصرف';

  @override
  String get txnFxSourceSmsImplied =>
      'مستنتج من المبلغ المحوَّل في رسالة البنك';

  @override
  String get txnFxSourceSmsStated => 'مذكور في رسالة البنك';

  @override
  String get txnFxSourceUser => 'أدخلته بنفسك';

  @override
  String get txnFxSourceCarriedForward => 'آخر سعر معروف، منقول من عملية سابقة';

  @override
  String txnFxNotConverted(String currency) {
    return 'لم يُحوَّل إلى $currency — لم تذكر الرسالة سعر صرف، والتطبيق لا يخترع سعراً';
  }

  @override
  String get txnBadgeInternalTransfer => 'تحويل داخلي';

  @override
  String get txnBadgeInternalTransferCandidate => 'قد يكون تحويلاً داخلياً';

  @override
  String get txnInternalTransferExcludedNote =>
      'مستثنى من إجمالي الإنفاق — تحويل المال إلى حسابك ليس إنفاقاً';

  @override
  String get txnInternalTransferCandidateNote =>
      'يُحتسب ضمن الإنفاق حتى تؤكد أنه إلى حسابك الخاص';

  @override
  String get txnTypeSalaryIncome => 'راتب / دخل';

  @override
  String totalsNotConverted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count معاملة لم تُحوَّل',
      many: '$count معاملة لم تُحوَّل',
      few: '$count معاملات لم تُحوَّل',
      two: 'معاملتان لم تُحوَّلا',
      one: 'معاملة واحدة لم تُحوَّل',
    );
    return '$_temp0';
  }

  @override
  String get spentVsKeptTitle => 'المصروف مقابل المتبقي';

  @override
  String get spentVsKeptSpent => 'المصروف';

  @override
  String get spentVsKeptIncome => 'الوارد';

  @override
  String get spentVsKeptNet => 'المتبقي في هذه الفترة';

  @override
  String get spentVsKeptCashOut => 'نقد مسحوب';

  @override
  String get spentVsKeptInternalExcluded => 'تحويلات داخلية مستثناة';

  @override
  String get spentVsKeptIncomplete =>
      'تعذّر تحويل بعض المعاملات، لذلك هذه الأرقام غير مكتملة';

  @override
  String spentVsKeptNeedsReview(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count معاملة تحتاج مراجعة قبل اعتماد هذه الأرقام',
      many: '$count معاملة تحتاج مراجعة قبل اعتماد هذه الأرقام',
      few: '$count معاملات تحتاج مراجعة قبل اعتماد هذه الأرقام',
      two: 'معاملتان تحتاجان مراجعة قبل اعتماد هذه الأرقام',
      one: 'معاملة واحدة تحتاج مراجعة قبل اعتماد هذه الأرقام',
    );
    return '$_temp0';
  }

  @override
  String get manualEntryTitle => 'إضافة معاملة';

  @override
  String get manualEntryIntro =>
      'للنقد، أو لأي معاملة لم يرسل بنكك رسالة عنها.';

  @override
  String get manualEntrySave => 'حفظ المعاملة';

  @override
  String get manualEntryAmountLabel => 'المبلغ';

  @override
  String get manualEntryAmountMissing => 'أدخل المبلغ لحفظ هذه المعاملة';

  @override
  String get manualEntryAmountUnparsable =>
      'هذا ليس مبلغاً يمكن للتطبيق قراءته — استخدم أرقاماً وفاصلة عشرية واحدة على الأكثر';

  @override
  String get manualEntryCurrencyLabel => 'العملة';

  @override
  String get manualEntryCurrencyMissing =>
      'أدخل رمز عملة من ثلاثة أحرف، مثل SAR';

  @override
  String get manualEntryDateLabel => 'وقت حدوثها';

  @override
  String get manualEntryDateMissing => 'اختر تاريخ ووقت حدوث المعاملة';

  @override
  String get manualEntryTypeLabel => 'نوع المعاملة';

  @override
  String get manualEntryTypeMissing => 'اختر نوع هذه المعاملة';

  @override
  String get manualEntryMerchantLabel => 'المتجر أو الوصف';

  @override
  String get manualEntrySourceLabel => 'الدفع عبر';

  @override
  String get manualEntrySourceCash => 'نقداً';

  @override
  String get manualEntryCashNote =>
      'المعاملات النقدية تُحتسب في إجمالياتك تماماً كمعاملات البطاقة.';

  @override
  String get manualEntrySaved => 'تمت إضافة المعاملة';

  @override
  String get txnEditTitle => 'تعديل المعاملة';

  @override
  String get txnEditSave => 'حفظ التعديلات';

  @override
  String get txnEditSaved => 'تم حفظ التعديلات';

  @override
  String get txnEditNoChanges => 'لم يتم تغيير أي شيء';

  @override
  String txnEditOriginalValue(String value) {
    return 'القيمة المكتشفة أصلاً: $value';
  }

  @override
  String get txnEditOriginalValueEmpty => 'القيمة المكتشفة أصلاً: لا شيء';

  @override
  String get txnEditProtectedFromRescan =>
      'تعديلك محفوظ — إعادة قراءة الرسالة لن تستبدله';

  @override
  String get txnDeleteAction => 'حذف';

  @override
  String get txnDeleteConfirmTitle => 'حذف هذه المعاملة؟';

  @override
  String get txnDeleteConfirmBody =>
      'ستُزال من قوائمك وإجمالياتك، وتُنقل إلى المحذوفات مؤخراً. يمكنك استعادتها من هناك.';

  @override
  String get txnDeleteConfirmCancel => 'الاحتفاظ بها';

  @override
  String get txnDeleteConfirmAccept => 'حذف';

  @override
  String get txnDeleted => 'تم حذف المعاملة';

  @override
  String get txnDeletedUndo => 'تراجع';

  @override
  String get txnRestoreAction => 'استعادة';

  @override
  String get txnRestored => 'تمت استعادة المعاملة';

  @override
  String get recentlyDeletedTitle => 'المحذوفات مؤخراً';

  @override
  String get recentlyDeletedIntro =>
      'تُحفظ المعاملات المحذوفة هنا ولا تُحتسب في أي إجمالي. «محو كل شيء» وحده يزيلها نهائياً.';

  @override
  String get recentlyDeletedEmpty => 'لم يُحذف أي شيء';

  @override
  String get recentlyDeletedEmptyBody =>
      'ستظهر هنا المعاملات التي تحذفها كي تتمكن من استعادتها.';

  @override
  String recentlyDeletedOn(String when) {
    return 'حُذفت $when';
  }

  @override
  String recentlyDeletedMergedInto(int id) {
    return 'دُمجت في المعاملة رقم $id';
  }

  @override
  String get reviewTransferCandidateTitle =>
      'هل كان هذا تحويلاً إلى حسابك الخاص؟';

  @override
  String get reviewTransferConfirm => 'نعم، إلى حسابي';

  @override
  String get reviewTransferReject => 'لا، إلى شخص آخر';

  @override
  String get reviewTransferConfirmed => 'مستثنى من الإنفاق — طرفا التحويل معاً';

  @override
  String get reviewTransferRejected => 'احتُسب كدفعة — لن نسأل عن هذه مرة أخرى';

  @override
  String get reviewTransferCrossCurrency =>
      'حدث تحويل بعملة أخرى في الوقت نفسه تقريباً. لا يمكننا مطابقتهما دون اختراع سعر صرف، لذلك ما زال كلاهما محتسباً.';

  @override
  String get reviewTransferUnresolvedInstrument =>
      'وصل تحويل مطابق في الوقت نفسه تقريباً، لكن تعذّر علينا تحديد الحساب الذي وصل إليه، لذلك ما زال هذا محتسباً كإنفاق.';

  @override
  String get reviewTransferDismiss => 'ليس تحويلاً داخلياً';

  @override
  String get reviewDuplicateTitle => 'هل هاتان المعاملتان نفس المعاملة؟';

  @override
  String get reviewDuplicateBody =>
      'كلتاهما محتسبة في إجمالياتك حتى تقرر. الدمج يُبقي واحدة وينقل الأخرى إلى المحذوفات مؤخراً — لا يُتلف شيء.';

  @override
  String get reviewDuplicateMerge => 'نعم، ادمجهما';

  @override
  String get reviewDuplicateKeepBoth => 'لا، احتفظ بكلتيهما';

  @override
  String get reviewMergeConfirmTitle =>
      'هل تريد دمج هاتين المعاملتين في واحدة؟';

  @override
  String get reviewMergeConfirmBody =>
      'ستبقى إحداهما في قوائمك وإجمالياتك، وتنتقل الأخرى إلى المحذوفات مؤخراً مع الاحتفاظ برسالتها، ويمكنك استعادتها في أي وقت — لا يُتلف شيء.';

  @override
  String get reviewMergeConfirmCancel => 'احتفظ بكلتيهما';

  @override
  String get reviewMergeConfirmAccept => 'ادمجهما';

  @override
  String get reviewMergeRefusedFee =>
      'الرسومان مختلفان في هاتين المعاملتين، لذا لا يمكن دمجهما تلقائياً';

  @override
  String get reviewMergeRefusedConversion =>
      'المبلغ المحوَّل أو سعر الصرف مختلف بين المعاملتين، لذا لا يمكن دمجهما';

  @override
  String get reviewMergeRefusedBalance =>
      'الرصيد المتبقي المذكور بعد كل معاملة مختلف، لذا لا يمكن دمجهما';

  @override
  String get reviewMergeRefusedSpendEffect =>
      'تحتسب كل منهما بطريقة مختلفة ضمن إنفاقك، لذا لا يمكن دمجهما';

  @override
  String get reviewMergeRefusedUserEdit =>
      'لقد صحّحت تفصيلاً في إحداهما والأخرى تذكر شيئاً مختلفاً — يرجى مراجعتهما قبل الدمج';

  @override
  String get reviewMergeRefusedChain =>
      'إحدى هاتين المعاملتين سبق أن استوعبت معاملة أخرى، لذا لا يمكن دمجها مرة أخرى';

  @override
  String get reviewDuplicateMerged =>
      'تم الدمج — معاملة واحدة الآن، ويمكن تتبّعها إلى كلتا الرسالتين';

  @override
  String get reviewDuplicateKeptBoth => 'تم الاحتفاظ بكلتيهما';

  @override
  String get reviewMergeRefusedAmount =>
      'المبلغان مختلفان، لذلك لا يمكن أن تكونا نفس المعاملة';

  @override
  String get reviewMergeRefusedDirection =>
      'إحداهما وارد والأخرى صادر، لذلك لا يمكن دمجهما';

  @override
  String get reviewMergeRefusedType =>
      'هاتان معاملتان من نوعين مختلفين، لذلك لا يمكن دمجهما';

  @override
  String get reviewMergeRefusedState =>
      'إحداهما لم تعد نشطة، لذلك لا يوجد ما يُدمج';

  @override
  String get reviewDataProblemTitle => 'تعذّرت قراءة إحدى المعاملات';

  @override
  String reviewDataProblemBody(int id) {
    return 'المعاملة رقم $id مخزَّنة بمبلغ لا يستطيع التطبيق قراءته، لذلك هي غائبة عن إجمالياتك. لم يُغيَّر أو يُحذف أي شيء. استعادة نسخة احتياطية هي أأمن طريقة لاستردادها.';
  }

  @override
  String reviewDataProblemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count معاملة غائبة عن إجمالياتك',
      many: '$count معاملة غائبة عن إجمالياتك',
      few: '$count معاملات غائبة عن إجمالياتك',
      two: 'معاملتان غائبتان عن إجمالياتك',
      one: 'معاملة واحدة غائبة عن إجمالياتك',
    );
    return '$_temp0';
  }

  @override
  String needsReviewTabTransfers(int count) {
    return 'تحويلات ($count)';
  }

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonSave => 'حفظ';

  @override
  String get commonDelete => 'حذف';

  @override
  String get commonEdit => 'تعديل';

  @override
  String get commonRename => 'إعادة تسمية';

  @override
  String get commonCreate => 'إنشاء';

  @override
  String get commonConfirm => 'تأكيد';

  @override
  String get commonUndo => 'تراجع';

  @override
  String get commonRetry => 'أعد المحاولة';

  @override
  String get categoriesTitle => 'الفئات';

  @override
  String get categoriesEmptyTitle => 'لا توجد فئات بعد';

  @override
  String get categoriesEmptyBody =>
      'ستظهر فئاتك الأساسية هنا فور انتهاء التطبيق من التهيئة.';

  @override
  String get categoriesUnavailable => 'تعذّر تحميل فئاتك. لم يتغيّر أي شيء.';

  @override
  String get categoryGroupSpending => 'الإنفاق';

  @override
  String get categoryGroupMoneyMovement => 'حركة الأموال';

  @override
  String categoryRowTransactionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count معاملة',
      many: '$count معاملة',
      few: '$count معاملات',
      two: 'معاملتان',
      one: 'معاملة واحدة',
      zero: 'لا توجد معاملات',
    );
    return '$_temp0';
  }

  @override
  String categoryRowSystemCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count معاملة · فئة نظام',
      many: '$count معاملة · فئة نظام',
      few: '$count معاملات · فئة نظام',
      two: 'معاملتان · فئة نظام',
      one: 'معاملة واحدة · فئة نظام',
      zero: 'فئة نظام — لا يمكن إعادة تسميتها أو حذفها',
    );
    return '$_temp0';
  }

  @override
  String get categoryRenameTitle => 'إعادة تسمية الفئة';

  @override
  String categoryRenamed(String name) {
    return 'تمت إعادة التسمية إلى $name';
  }

  @override
  String categoryDeleteTitle(String name) {
    return 'حذف \"$name\"؟';
  }

  @override
  String categoryDeleteInUseBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تحتوي هذه الفئة على $count معاملة. اختر ماذا يحدث لها:',
      many: 'تحتوي هذه الفئة على $count معاملة. اختر ماذا يحدث لها:',
      few: 'تحتوي هذه الفئة على $count معاملات. اختر ماذا يحدث لها:',
      two: 'تحتوي هذه الفئة على معاملتين. اختر ماذا يحدث لهما:',
      one: 'تحتوي هذه الفئة على معاملة واحدة. اختر ماذا يحدث لها:',
    );
    return '$_temp0';
  }

  @override
  String get categoryDeleteEmptyBody =>
      'لا شيء يستخدم هذه الفئة، لذا لن يتغيّر شيء آخر.';

  @override
  String get categoryDeleteReassignLabel => 'انقل معاملاتها إلى';

  @override
  String categoryDeleted(String name) {
    return 'تم حذف $name';
  }

  @override
  String get categoryPickerTitle => 'اختر فئة';

  @override
  String categoryPickerTitleFor(String merchant) {
    return 'تصنيف · $merchant';
  }

  @override
  String get categoryPickerSearchHint => 'البحث عن فئة';

  @override
  String get categoryPickerRecent => 'الأخيرة';

  @override
  String categoryPickerNoResults(String query) {
    return 'لا توجد فئة تطابق \"$query\"';
  }

  @override
  String get categoryPickerNewCategory => 'فئة جديدة';

  @override
  String get categoryNewNameLabel => 'اسم الفئة';

  @override
  String get categoryNewIconLabel => 'الأيقونة';

  @override
  String get categoryNewCreateAndUse => 'إنشاء واستخدام';

  @override
  String get categoryNewDuplicateName =>
      'توجد فئة بهذا الاسم مسبقاً — اختر اسماً آخر';

  @override
  String categoryAppliedAs(String category) {
    return 'تم التصنيف كـ $category';
  }

  @override
  String categoryScopeQuestion(String merchant) {
    return 'هل تريد تطبيقها على المعاملات المستقبلية من \"$merchant\" أيضاً؟';
  }

  @override
  String get categoryScopeQuestionGeneric =>
      'هل تريد تطبيقها على المعاملات المستقبلية من هذا التاجر أيضاً؟';

  @override
  String get categoryScopeFuture => 'هذه والمستقبل';

  @override
  String get categoryScopeFutureHint => 'يُنشئ أو يُحدّث قاعدة هذا التاجر';

  @override
  String categoryScopeFutureCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ويُكمل أيضاً $count معاملة سابقة غير مصنّفة',
      many: 'ويُكمل أيضاً $count معاملة سابقة غير مصنّفة',
      few: 'ويُكمل أيضاً $count معاملات سابقة غير مصنّفة',
      two: 'ويُكمل أيضاً معاملتين سابقتين غير مصنّفتين',
      one: 'ويُكمل أيضاً معاملة واحدة سابقة غير مصنّفة',
      zero: 'يُنشئ أو يُحدّث قاعدة هذا التاجر',
    );
    return '$_temp0';
  }

  @override
  String get categoryScopeThisOnly => 'هذه المعاملة فقط';

  @override
  String get categoryScopeThisOnlyHint =>
      'يترك قاعدة هذا التاجر الحالية كما هي تماماً';

  @override
  String get categoryScopeAutoConfirm => 'سيتم التطبيق بعد لحظات…';

  @override
  String get correctionAppliedToOne => 'تم تحديث الفئة';

  @override
  String correctionAppliedToMany(int count, String merchant) {
    return 'تم تحديث $count معاملة من $merchant';
  }

  @override
  String get categoryAutoApplied => 'طُبِّقت تلقائياً';

  @override
  String get categoryConfidenceHigh => 'مطابقة مؤكدة';

  @override
  String get categoryConfidenceLow => 'غير متأكد';

  @override
  String get categoryConfidenceNone => 'لم يُعثر على مطابقة';

  @override
  String categoryConfidenceWithValue(String label, int percent) {
    return '$label ($percent٪)';
  }

  @override
  String get reviewReasonUnknownMerchant =>
      'لم نرَ هذا التاجر من قبل — إلى أي فئة ينتمي إنفاقه؟';

  @override
  String get reviewReasonNoRuleForMerchant =>
      'نعرف هذا التاجر، لكن لم يحدّد أحد الفئة التي ينتمي إليها';

  @override
  String get reviewReasonLowConfidence =>
      'وجدنا مطابقة قريبة لكننا لسنا واثقين بما يكفي لتطبيقها';

  @override
  String get reviewReasonGeneric => 'هذه تحتاج إلى حكمك';

  @override
  String get reviewInboxUnavailable =>
      'تعذّر تحميل قائمة المراجعة. لم يتغيّر أي شيء.';

  @override
  String get reviewCountAllClear => 'كل شيء مُراجَع';

  @override
  String reviewCountNeedsReview(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر يحتاج مراجعة',
      many: '$count عنصراً يحتاج مراجعة',
      few: '$count عناصر تحتاج مراجعة',
      two: 'عنصران يحتاجان مراجعة',
      one: 'عنصر واحد يحتاج مراجعة',
    );
    return '$_temp0';
  }

  @override
  String reviewCountBreakdown(int uncategorized, int flagged) {
    return '$uncategorized غير مصنّفة · $flagged مُعلَّمة';
  }

  @override
  String get reviewCountUnavailable => 'عدد عناصر المراجعة غير متاح حالياً';

  @override
  String get learnedRulesTitle => 'القواعد المتعلمة';

  @override
  String get learnedRulesEmptyTitle => 'لا توجد قواعد بعد';

  @override
  String get learnedRulesEmptyBody =>
      'تصحيح فئة أي معاملة يُنشئ قاعدة تلقائياً، فتصل المعاملة التالية من نفس التاجر مصنَّفة.';

  @override
  String get learnedRulesUnavailable =>
      'تعذّر تحميل قواعدك المتعلمة. لم يتغيّر أي شيء.';

  @override
  String ruleAppliedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'طُبِّقت على $count معاملة',
      many: 'طُبِّقت على $count معاملة',
      few: 'طُبِّقت على $count معاملات',
      two: 'طُبِّقت على معاملتين',
      one: 'طُبِّقت على معاملة واحدة',
      zero: 'لم تُطبَّق بعد',
    );
    return '$_temp0';
  }

  @override
  String get ruleSourceSeed => '· مُضمَّنة';

  @override
  String ruleEditTitle(String merchant) {
    return 'تعديل قاعدة $merchant';
  }

  @override
  String ruleEditCurrentCategory(String category) {
    return 'الفئة الحالية: $category';
  }

  @override
  String get ruleEditNewCategory => 'الفئة الجديدة';

  @override
  String ruleReapplyPrompt(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'هل تريد إعادة تطبيق ذلك على $count معاملة حالية من هذا التاجر أيضاً؟',
      many:
          'هل تريد إعادة تطبيق ذلك على $count معاملة حالية من هذا التاجر أيضاً؟',
      few:
          'هل تريد إعادة تطبيق ذلك على $count معاملات حالية من هذا التاجر أيضاً؟',
      two: 'هل تريد إعادة تطبيق ذلك على معاملتين حاليتين من هذا التاجر أيضاً؟',
      one:
          'هل تريد إعادة تطبيق ذلك على معاملة واحدة حالية من هذا التاجر أيضاً؟',
      zero: 'لن تتغيّر أي معاملة حالية.',
    );
    return '$_temp0';
  }

  @override
  String get ruleReapplyPromptCounting =>
      'جارٍ حساب عدد المعاملات الحالية التي ستتغيّر…';

  @override
  String ruleReapplyYes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'نعم، $count معاملة',
      zero: 'إعادة التطبيق',
    );
    return '$_temp0';
  }

  @override
  String get ruleReapplyNo => 'فقط للمستقبل';

  @override
  String ruleReappliedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تحديث القاعدة وإعادة تطبيقها على $count معاملة',
      many: 'تم تحديث القاعدة وإعادة تطبيقها على $count معاملة',
      few: 'تم تحديث القاعدة وإعادة تطبيقها على $count معاملات',
      two: 'تم تحديث القاعدة وإعادة تطبيقها على معاملتين',
      one: 'تم تحديث القاعدة وإعادة تطبيقها على معاملة واحدة',
      zero: 'تم تحديث القاعدة. لم تحتج أي معاملة حالية إلى تغيير.',
    );
    return '$_temp0';
  }

  @override
  String get ruleUpdatedGoingForward =>
      'تم تحديث القاعدة. تُركت المعاملات الحالية كما هي.';

  @override
  String get ruleEditRefused => 'لم تعد هذه الفئة متاحة، لذا لم تتغيّر القاعدة';

  @override
  String ruleDeleteTitle(String merchant) {
    return 'حذف قاعدة $merchant؟';
  }

  @override
  String get ruleDeleteBody =>
      'ستصل المعاملات المستقبلية من هذا التاجر غير مصنّفة. أما المعاملات التي صنّفتها سابقاً فتحتفظ بفئاتها.';

  @override
  String get ruleDeleted => 'تم حذف القاعدة';

  @override
  String get categoryWhyThisCategory => 'لماذا هذه الفئة؟';

  @override
  String get categoryProvenanceUser => 'أنت اخترت هذه الفئة.';

  @override
  String categoryProvenanceAutomatic(int percent) {
    return 'طبّقتها قاعدة متعلمة تلقائياً، بثقة $percent٪.';
  }

  @override
  String get categoryProvenanceUndecided =>
      'نظر التطبيق ولم يستطع التحديد، لذا تُركت غير مصنّفة.';

  @override
  String get categoryProvenanceUnknownSource =>
      'ضُبطت هذه الفئة قبل أن يبدأ التطبيق بتسجيل الكيفية.';

  @override
  String categoryProvenanceRule(String merchant) {
    return 'القاعدة: $merchant';
  }

  @override
  String get categoryProvenanceRuleGone =>
      'القاعدة التي فعلت ذلك حُذفت منذ ذلك الحين.';

  @override
  String get categoryProvenanceNoHistory =>
      'لا يوجد سجل تصنيف لهذه المعاملة بعد.';

  @override
  String categoryProvenanceEntry(String when, String actor) {
    return '$when · $actor';
  }

  @override
  String get categoryProvenanceUnavailable => 'تعذّر تحميل سجل هذه الفئة.';

  @override
  String get categoryActorUser => 'أنت';

  @override
  String get categoryActorRule => 'قاعدة متعلمة';

  @override
  String get categoryActorSystem => 'التطبيق';

  @override
  String get categoryLockedBody =>
      'فئاتك مشفَّرة وتبقى مقفلة حتى تفتح قفل التطبيق.';

  @override
  String get transactionUnavailable => 'تعذّر تحميل هذه المعاملة.';

  @override
  String get transactionGoneTitle => 'لم تعد هذه المعاملة هنا';

  @override
  String get transactionGoneBody =>
      'حُذفت أو دُمجت في معاملة أخرى. يمكنك إيجادها ضمن المحذوفة مؤخراً.';

  @override
  String get completionMessageGone => 'لم تعد هذه الرسالة في قائمة المراجعة';
}
