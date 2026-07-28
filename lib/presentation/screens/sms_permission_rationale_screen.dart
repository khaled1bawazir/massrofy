import 'package:flutter/material.dart';

import '../../features/ingestion/sms_permission_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';

/// **S-02 — SMS Permission Rationale.** Mockup: `docs/mockups/onboarding.html`.
///
/// ## Why a whole screen exists before a system dialog
///
/// This screen resolves design flag **D-9** and satisfies **AC-A1.2**. It is
/// not a courtesy; it is the difference between a working product and a dead
/// one, for a reason specific to Android:
///
/// The OS permission dialog appears **once** in any useful sense. If the user
/// denies it, Android may show it again — but after a second denial it stops
/// appearing at all, silently, forever. At that point the only recovery is a
/// trip into system Settings that most people will never make. A spending
/// tracker that fires `RECEIVE_SMS`/`READ_SMS` cold, with no explanation, is
/// asking for the most alarming permission on the platform from a stranger,
/// and a reflexive "Deny" is the rational response.
///
/// So the four guarantees below are shown **first**, and each one is
/// literally true rather than reassuring copy:
///
/// | Bullet | Why it is true |
/// |---|---|
/// | processed on your phone | NFR-P2, and ADR-001 removes `INTERNET` from the release build entirely |
/// | nothing sent anywhere | AC-F4.2 — there is no network client to send with |
/// | revocable any time | it is a standard runtime permission |
/// | non-financial messages ignored and never stored | NFR-P4 — an unrecognised sender produces **no database row at all** |
///
/// ## Layout notes for a Flutter newcomer
///
/// - `EdgeInsetsDirectional` / `AlignmentDirectional` everywhere, never
///   `EdgeInsets.only(left:)`. The `start`/`end` forms flip automatically
///   under Arabic RTL, which is this app's **primary** direction (design.md
///   §3.1). A raw `left` would pin content to the wrong edge for the main
///   audience.
/// - The CTAs sit under a `Spacer()` in a `Column`, matching the mockup's
///   `margin-top:auto`. Wrapped in `SingleChildScrollView` +
///   `ConstrainedBox`/`IntrinsicHeight` so the layout still works at the
///   largest OS font size without truncation (NFR-U3) — at 200% text scale a
///   plain `Column` with a `Spacer` overflows.
class SmsPermissionRationaleScreen extends StatelessWidget {
  /// Invoked when the user accepts. The caller shows the OS dialog and routes
  /// on the result — this screen deliberately does not call
  /// [SmsPermissionService.request] itself, so it stays a pure, trivially
  /// testable widget with no platform dependency.
  final VoidCallback onGrantPressed;

  /// Invoked on "Not now". Must lead to S-04 limited mode, **never** to a
  /// dead end or an unexplained empty screen (AC-A1.2).
  final VoidCallback onNotNowPressed;

  const SmsPermissionRationaleScreen({
    required this.onGrantPressed,
    required this.onNotNowPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.smsRationaleTitle,
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ExplainCard(body: l10n.smsRationaleLead),
                      const SizedBox(height: 20),
                      _Guarantee(text: l10n.smsRationalePointOnDevice),
                      _Guarantee(text: l10n.smsRationalePointNoSharing),
                      _Guarantee(text: l10n.smsRationalePointRevocable),
                      _Guarantee(text: l10n.smsRationalePointNoiseIgnored),
                      const Spacer(),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: onGrantPressed,
                          child: Text(l10n.smsRationaleGrant),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: onNotNowPressed,
                          child: Text(l10n.smsRationaleNotNow),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The tinted information panel at the top of the mockup.
class _ExplainCard extends StatelessWidget {
  final String body;
  const _ExplainCard({required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(16),
      decoration: BoxDecoration(
        color: AppColors.infoTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.lock_outline, color: AppColors.info, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(body, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// One guarantee bullet.
///
/// The check icon is paired with text rather than standing alone, per NFR-U4
/// (never rely on colour or an icon by itself) — and the whole row is one
/// `Semantics` node so a screen reader announces "check, everything is
/// processed on your phone" instead of reading a decorative glyph separately.
class _Guarantee extends StatelessWidget {
  final String text;
  const _Guarantee({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.check_circle_outline,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.ink700),
            ),
          ),
        ],
      ),
    );
  }
}
