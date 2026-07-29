/// Riverpod wiring for the P4a categorization spine (KHA-30, KHA-31).
///
/// ## This file is the composition root for the learning loop
///
/// Two things happen here that happen nowhere else, and both are the reason
/// the P1 review's rule — *"a component with no production call site is
/// library code, not shipped behaviour"* — is satisfied for this phase:
///
///  1. **The starter list is seeded.** [categorizationServiceProvider] calls
///     `ensureDefaultsSeeded` the first time it is built for an unlocked
///     session, so design §4's thirteen categories exist in the database of a
///     real install and not only in tests.
///  2. **The categorizer is bound into ingestion.**
///     [ingestionCategorizerProvider] adapts `CategorizationService` to the
///     `CategorizeWrittenTransaction` callback `IngestionPipeline` accepts.
///     That adapter lives *here*, in the layer that already depends on both
///     features, which is how architecture §3's "`ingestion` never imports
///     `categorization`" is honoured — the same technique
///     `ledger_providers.dart` uses to keep `features/ledger` from importing
///     `features/parsing`.
///
/// **No screen is routed by this file, and none exists yet.** P4a is the data
/// and domain spine; the pickers, the review inbox and the learned-rules
/// screen are P4b (KHA-32/33/34), which is gated behind KHA-87/88 for reasons
/// recorded in `docs/build-plan.md`.
///
/// ## Everything is null while the app is locked
///
/// Like every other provider in this app: ADR-005 makes the lock
/// cryptographic, so while locked there is no database and the honest value is
/// nothing at all.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dao/category_dao.dart';
import '../../data/dao/merchant_dao.dart';
import '../../data/db/app_database.dart';
import '../../features/categorization/categories.dart';
import '../../features/categorization/categorization_service.dart';
import '../../features/ingestion/ingestion_pipeline.dart';
import 'app_providers.dart';

/// The categorization DAOs and service for the current unlocked session, with
/// the default categories already seeded.
final FutureProvider<CategorizationService?> categorizationServiceProvider =
    FutureProvider<CategorizationService?>((Ref ref) async {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        return null;
      }

      final CategorizationService service = CategorizationService(
        categoryDao: CategoryDao(session.database, session.auditLogDao),
        merchantDao: MerchantDao(session.database, session.auditLogDao),
        transactionDao: session.transactionDao,
      );

      // Idempotent (`INSERT OR IGNORE` per row), so running it on every
      // unlocked session costs thirteen no-op statements and guarantees that
      // the row AC-C1.1 depends on exists — including on an install that
      // upgraded from schema v5, where the migration deliberately seeded
      // nothing (see `app_database.dart`).
      await service.ensureDefaultsSeeded();
      return service;
    });

/// The adapter the ingestion pipeline calls after writing a transaction.
///
/// Returns null while locked, which the pipeline handles by simply not
/// categorising — the same shape as a missing `entityResolver`.
final FutureProvider<CategorizeWrittenTransaction?>
ingestionCategorizerProvider = FutureProvider<CategorizeWrittenTransaction?>((
  Ref ref,
) async {
  final CategorizationService? service = await ref.watch(
    categorizationServiceProvider.future,
  );
  if (service == null) {
    return null;
  }
  return (int transactionId) =>
      service.categorizeTransaction(transactionId: transactionId);
});

/// Every category, live — the source for every picker (AC-C3.1's *"available
/// in every picker"*) and for the breakdown's resolver.
///
/// A stream so a category created in one place appears everywhere else with no
/// manual refresh (architecture §7.5).
final StreamProvider<List<Category>> categoriesProvider =
    StreamProvider<List<Category>>((Ref ref) async* {
      final CategorizationService? service = await ref.watch(
        categorizationServiceProvider.future,
      );
      if (service == null) {
        yield const <Category>[];
        return;
      }
      // `watchAll()` emits its current value immediately and again on every
      // change, so this is a complete stream on its own — no priming yield.
      // Each emission is re-read through the service rather than mapped here,
      // so the row → domain conversion has exactly one implementation.
      yield* service.categoryDao.watchAll().asyncMap(
        (List<CategoryRow> _) => service.categories(),
      );
    });

/// A resolver over the current categories — what makes AC-C1.1's *"never a
/// blank"* true for anything that renders a transaction.
final FutureProvider<CategoryResolver> categoryResolverProvider =
    FutureProvider<CategoryResolver>((Ref ref) async {
      final List<Category> categories = await ref.watch(
        categoriesProvider.future,
      );
      // Falls back to the compiled-in list while locked or before seeding, so
      // a caller never has to handle "no resolver yet".
      return categories.isEmpty
          ? CategoryResolver.defaults()
          : CategoryResolver(categories);
    });
