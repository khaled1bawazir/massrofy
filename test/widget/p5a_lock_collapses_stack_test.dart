/// **NFR-S3 — nothing survives above the lock gate.**
///
/// `_AppLockGateway` is `MaterialApp.home`, i.e. the content of the **first**
/// route. Every screen P5a lets a user push — banks, an instrument's
/// transactions, manual entry, the review inbox — is drawn in an opaque route
/// *above* it, so swapping the gateway to `LockGateScreen` hides nothing by
/// itself.
///
/// That was unreachable while `HomePlaceholderScreen` pushed nothing. This PR
/// adds the routes, so it is reachable now: exactly the expiry `docs/lessons.md`
/// describes — *"'unreachable today' is a claim about navigation, not about
/// code."*
///
/// The gateway therefore collapses the stack on every lock. This test pins that
/// behaviour without booting the whole app: it builds the same
/// `home` + pushed-route shape and drives the same provider.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/security/app_lock_controller.dart';
import 'package:massrofy/features/security/app_lock_state.dart';

/// A lock controller a test can drive, standing in for real biometrics and the
/// Keystore. Starts unlocked.
class _DrivableLockController extends AppLockController {
  @override
  AppLockState build() => const AppLockState(status: AppLockStatus.unlocked);

  void lockNow() => state = const AppLockState(status: AppLockStatus.locked);
}

/// The same shape `app.dart` has: a gateway as `MaterialApp.home` that swaps
/// its content on lock, collapsing the stack as it does.
class _Gateway extends ConsumerStatefulWidget {
  const _Gateway();

  @override
  ConsumerState<_Gateway> createState() => _GatewayState();
}

class _GatewayState extends ConsumerState<_Gateway> {
  void _collapse() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).popUntil((Route<Object?> route) => route.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppLockState>(appLockControllerProvider, (
      AppLockState? previous,
      AppLockState next,
    ) {
      if ((previous?.isUnlocked ?? false) && !next.isUnlocked) {
        _collapse();
      }
    });

    if (!ref.watch(appLockControllerProvider).isUnlocked) {
      return const Scaffold(body: Center(child: Text('LOCK GATE')));
    }
    return const _Pushable(depth: 0);
  }
}

/// A screen that can push another copy of itself, so a test can build a stack
/// as deep as the real app's Banks → Bank detail → Instrument detail.
class _Pushable extends StatelessWidget {
  final int depth;

  const _Pushable({required this.depth});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (depth > 0) const Text('BANK DETAIL — 12,400.00 SAR'),
          ElevatedButton(
            key: Key('push.$depth'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _Pushable(depth: depth + 1),
              ),
            ),
            child: const Text('open a deeper screen'),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('a lock taken while a pushed screen is open leaves the lock gate '
      'on top, not underneath', (WidgetTester tester) async {
    final _DrivableLockController controller = _DrivableLockController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appLockControllerProvider.overrideWith(() => controller)],
        child: const MaterialApp(home: _Gateway()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('push.0')));
    await tester.pumpAndSettle();
    expect(find.text('BANK DETAIL — 12,400.00 SAR'), findsOneWidget);

    // The lock event — what `didChangeAppLifecycleState` does on background,
    // and what the More menu's "Lock now" does directly.
    controller.lockNow();
    await tester.pumpAndSettle();

    expect(
      find.text('BANK DETAIL — 12,400.00 SAR'),
      findsNothing,
      reason:
          'without the collapse, this route stays drawn above MaterialApp.home '
          'and the lock gate is rendered beneath a screen full of the '
          'user\'s figures',
    );
    expect(find.text('LOCK GATE'), findsOneWidget);
  });

  testWidgets('several stacked routes are all collapsed, not just the top one', (
    WidgetTester tester,
  ) async {
    final _DrivableLockController controller = _DrivableLockController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appLockControllerProvider.overrideWith(() => controller)],
        child: const MaterialApp(home: _Gateway()),
      ),
    );
    await tester.pumpAndSettle();

    // Banks -> Bank detail -> Instrument detail is three deep in the real app.
    for (int depth = 0; depth < 3; depth++) {
      await tester.tap(find.byKey(Key('push.$depth')));
      await tester.pumpAndSettle();
    }
    expect(find.text('BANK DETAIL — 12,400.00 SAR'), findsOneWidget);

    controller.lockNow();
    await tester.pumpAndSettle();

    expect(find.text('BANK DETAIL — 12,400.00 SAR'), findsNothing);
    expect(find.text('LOCK GATE'), findsOneWidget);
  });
}
