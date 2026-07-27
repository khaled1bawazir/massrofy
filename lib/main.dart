import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// Entry point.
///
/// `ProviderScope` is Riverpod's root widget — it holds the container that
/// every `Provider`/`NotifierProvider` in `lib/presentation/providers/` and
/// `lib/features/security/app_lock_controller.dart` resolves against.
/// Nothing else needs to happen here in this P1 foundation slice: locale
/// resolution and the lock gate are wired inside `MassrofyApp`
/// (`lib/app.dart`), and the encrypted database is only opened once a
/// successful unlock produces a key (see `AppLockController`) — there is no
/// unencrypted, pre-lock code path that touches the database at all.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MassrofyApp()));
}
