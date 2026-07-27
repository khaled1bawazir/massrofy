import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/security/app_lock_controller.dart';
import 'features/security/app_lock_state.dart';
import 'presentation/l10n/generated/app_localizations.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/screens/home_placeholder_screen.dart';
import 'presentation/screens/lock_gate_screen.dart';
import 'presentation/theme/app_theme.dart';

/// The app's root widget.
///
/// ## RTL/locale bootstrap (NFR-U8)
/// `supportedLocales` lists **Arabic first** — Arabic is this product's
/// primary, first-designed layout (`docs/design.md` §3.1), with English as
/// a fully-supported second locale. `locale` is left `null`, which tells
/// `MaterialApp` to resolve the locale from the OS via
/// `localeListResolutionCallback`'s default behaviour — i.e. the app
/// launches in Arabic (and therefore RTL, since `flutter_localizations`'
/// Arabic `GlobalMaterialLocalizations` reports `TextDirection.rtl`) on a
/// device set to Arabic, and in English/LTR otherwise, with no manual
/// `Directionality` override required anywhere: Flutter derives text
/// direction from the resolved `Locale` automatically for every widget that
/// asks `Directionality.of(context)`.
class MassrofyApp extends ConsumerWidget {
  const MassrofyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Forces the DI wiring in app_providers.dart to run once, at startup,
    // before anything reads `appLockControllerProvider`.
    ref.watch(appLockControllerConfiguratorProvider);

    return MaterialApp(
      title: 'Massrofy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      supportedLocales: const <Locale>[
        Locale('ar'), // primary — see class doc comment
        Locale('en'),
      ],
      localizationsDelegates: const <LocalizationsDelegate<Object?>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _AppLockGateway(),
    );
  }
}

/// Chooses between [LockGateScreen] and [HomePlaceholderScreen] based on
/// [AppLockController]'s state, and wires the app-lifecycle observer that
/// re-locks on background (ADR-005) and obscures the app-switcher snapshot
/// (ADR-014).
///
/// Kept as its own tiny widget (rather than inlined into [MassrofyApp])
/// specifically so it can host a [WidgetsBindingObserver] with the
/// `State` object's own lifecycle — `MassrofyApp` itself has no reason to
/// be a `StatefulWidget` otherwise.
class _AppLockGateway extends ConsumerStatefulWidget {
  const _AppLockGateway();

  @override
  ConsumerState<_AppLockGateway> createState() => _AppLockGatewayState();
}

class _AppLockGatewayState extends ConsumerState<_AppLockGateway>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final AppLockController controller = ref.read(
      appLockControllerProvider.notifier,
    );
    final bool wasUnlocked = ref.read(appLockControllerProvider).isUnlocked;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        // ADR-005 re-lock policy: default grace is 0 seconds (lock
        // immediately). A configurable grace period (0/15/30/60s) is a
        // Settings feature for a later phase; this P1 slice implements the
        // secure default.
        ref.read(privacyGateProvider).setObscured(true);
        if (wasUnlocked) {
          controller.lock();
        }
      case AppLifecycleState.resumed:
        ref.read(privacyGateProvider).setObscured(false);
        final AppLockStatus status = ref.read(appLockControllerProvider).status;
        if (status == AppLockStatus.locked) {
          controller.authenticate();
        }
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool unlocked = ref.watch(appLockControllerProvider).isUnlocked;
    return unlocked ? const HomePlaceholderScreen() : const LockGateScreen();
  }
}
