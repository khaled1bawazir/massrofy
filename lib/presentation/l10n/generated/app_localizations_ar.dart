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
}
