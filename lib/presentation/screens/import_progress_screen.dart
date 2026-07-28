import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';

/// **S-05 — Historical Import Progress.** Mockup:
/// `docs/mockups/onboarding.html`.
///
/// Satisfies AC-A3.2: *"Given an initial import is running over a large
/// inbox, when the user views the app, then **progress is shown and the app
/// remains responsive**."*
///
/// ## The dismiss button is the requirement, not the decoration
///
/// "Continue in the background" is what makes the second half of AC-A3.2 and
/// NFR-R2 true. The import is chunked and resumable (see
/// `historical_importer.dart`); it does not need the user watching it, and
/// trapping them on a progress screen for a first run over a busy inbox is
/// exactly the kind of thing that gets an app deleted before it has shown any
/// value.
///
/// ## Why the scope note is on screen
///
/// AC-A3.1 (resolving OQ-11) imports **from the start of the current calendar
/// month**, not all history. Without saying so, a user with two years of bank
/// SMS sees "41 transactions found" and concludes the app is broken. Stating
/// the scope converts a perceived bug into an understood boundary.
///
/// ## For a Flutter newcomer: determinate vs indeterminate progress
///
/// `LinearProgressIndicator(value: ...)` draws a filled bar; passing `null`
/// draws the sweeping animation instead. This screen shows the real fraction
/// once a total is known, and sweeps only while the total is still being
/// counted — a bar that sits at a fake percentage is worse than an honest
/// "working on it".
class ImportProgressScreen extends StatelessWidget {
  /// Messages examined so far.
  final int processed;

  /// Total candidate messages, or `null` while still being counted.
  final int? total;

  /// Transactions produced so far — the number the user actually cares
  /// about, and the one the mockup shows.
  final int transactionsFound;

  final VoidCallback onContinueInBackground;

  const ImportProgressScreen({
    required this.processed,
    required this.total,
    required this.transactionsFound,
    required this.onContinueInBackground,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    // Guard against a zero total: `0 / 0` is NaN, which renders as a bar in an
    // undefined state rather than throwing, so it would slip through review.
    final double? fraction = (total == null || total == 0)
        ? null
        : (processed / total!).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.sync, size: 56, color: AppColors.primary),
                const SizedBox(height: 20),
                Text(
                  l10n.importProgressTitle,
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 8,
                    backgroundColor: AppColors.ink100,
                    // A screen reader announcing a bare percentage is
                    // meaningless; naming what is progressing is NFR-U2.
                    semanticsLabel: l10n.importProgressTitle,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.importProgressFound(transactionsFound),
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: AppColors.ink500),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.importProgressScopeNote,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: AppColors.ink500),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onContinueInBackground,
                    child: Text(l10n.importProgressContinueInBackground),
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
