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
}
