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
}
