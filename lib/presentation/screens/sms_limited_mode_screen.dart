import 'package:flutter/material.dart';

import '../../features/ingestion/sms_permission_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';

/// **S-04 — Permission Denied / Limited Mode.** Mockup:
/// `docs/mockups/onboarding.html`.
///
/// This one screen covers two different journeys that arrive at the same
/// place, which is why the mockup treats it as the most important state in
/// onboarding:
///
///  - **AC-A1.2** — access was never granted. *"The app shows a clear
///    explanation of why access is needed and a way to grant it, and **does
///    not show an empty state with no explanation**."*
///  - **AC-A1.3** — access was granted and later revoked, including by
///    Android 11+ automatically resetting permissions for an unused app
///    (ADR-006). *"The app warns that ingestion has stopped **and previously
///    captured data is still intact**."*
///
/// ## Two details that look cosmetic and are not
///
/// **1. The primary action changes with the status.** When the permission is
/// merely `denied`, the OS dialog will still appear, so the button asks for
/// it directly. When it is `permanentlyDenied`, Android **silently no-ops**
/// the request — a "Grant" button would visibly do nothing, with no dialog
/// and no error. That is the most confusing possible outcome, so the button
/// becomes a deep link into system Settings instead. See
/// `sms_permission_service.dart` for why the platform layer has to
/// distinguish these at all.
///
/// **2. "Any data you already have is still intact."** Required verbatim in
/// substance by AC-A1.3. A user who sees "SMS access stopped" with no further
/// information reasonably concludes their spending history is gone — and the
/// instinctive fix for that, reinstalling, would actually destroy it. The
/// sentence exists to prevent a specific user action, not to be polite.
///
/// **3. "Add a transaction manually" is always offered.** The app must never
/// be a dead end. Manual entry (US-B4) is a first-class path, not a
/// consolation prize — cash spending needs it regardless of SMS access.
class SmsLimitedModeScreen extends StatelessWidget {
  final SmsPermissionStatus status;

  /// Retry the OS permission dialog. Only shown when [status] is
  /// [SmsPermissionStatus.denied].
  final VoidCallback onRequestPermission;

  /// Deep-link into system settings. Shown when the permission is
  /// permanently denied.
  final VoidCallback onOpenSettings;

  final VoidCallback onAddManually;

  const SmsLimitedModeScreen({
    required this.status,
    required this.onRequestPermission,
    required this.onOpenSettings,
    required this.onAddManually,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final bool permanentlyDenied =
        status == SmsPermissionStatus.permanentlyDenied;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 40, 20, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Icon + heading + body together, not icon alone: NFR-U4
                // requires meaning to survive without colour or iconography.
                const Icon(
                  Icons.sms_failed_outlined,
                  size: 44,
                  color: AppColors.warningText,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.smsLimitedModeTitle,
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.smsLimitedModeBody,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: AppColors.ink500),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: permanentlyDenied
                        ? onOpenSettings
                        : onRequestPermission,
                    child: Text(
                      permanentlyDenied
                          ? l10n.smsLimitedModeOpenSettings
                          : l10n.smsLimitedModeTryAgain,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onAddManually,
                    child: Text(l10n.smsLimitedModeAddManually),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The persistent AC-A1.3 banner for a user who *does* have data but has lost
/// SMS access — shown on Home rather than as a full screen, because taking
/// over the whole app would hide the very data the banner is reassuring them
/// still exists.
class SmsAccessRevokedBanner extends StatelessWidget {
  final VoidCallback onFix;

  const SmsAccessRevokedBanner({required this.onFix, super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Material(
      color: AppColors.secondaryTint10,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.sms_failed_outlined,
              size: 20,
              color: AppColors.warningText,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.smsRevokedBannerTitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.warningText,
                    ),
                  ),
                  // The "your data is intact" half of AC-A1.3 travels with the
                  // banner. Dropping it here and keeping it only on the full
                  // screen would leave the most common presentation of this
                  // state saying only the frightening half.
                  Text(
                    l10n.smsLimitedModeBody,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.ink700),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onFix,
              child: Text(l10n.smsLimitedModeOpenSettings),
            ),
          ],
        ),
      ),
    );
  }
}
