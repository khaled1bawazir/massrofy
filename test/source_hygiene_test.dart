/// A guard against source files that git cannot diff.
///
/// ## Why a test, for something that is not a behaviour
///
/// `lib/features/ingestion/content_hmac.dart` shipped with two raw `U+0000`
/// bytes in it — one in a doc comment describing the separator, one as the
/// actual `join()` argument. Dart compiled it perfectly: a raw NUL in a string
/// literal is a valid character, and `'\x00'` and a literal NUL byte produce
/// exactly the same string at runtime. Nothing failed. No test could have
/// caught it by running the code, because there was nothing wrong with the
/// code.
///
/// What broke was **review**. Git classifies any file containing a NUL byte as
/// binary, so the file appeared in its own pull request as `Bin 0 -> 3137
/// bytes` — no diff, and `git blame` dead for the life of the file. That file
/// computes the ADR-017 D1 dedup key, which decides whether a financial
/// message is a duplicate and therefore whether it is silently suppressed. A
/// trust-boundary file that no human can ever read a change to is a security
/// problem even when every byte in it is correct.
///
/// So this test guards the property that makes review possible at all: source
/// is text. It is cheap, it runs everywhere, and it fails loudly the moment
/// someone's editor or generator writes a control byte into a `.dart` file.
///
/// The fix, for reference: write the escape sequence `\x00` as four ordinary
/// ASCII characters in the source. Same string at runtime, same HMAC, and the
/// file stays reviewable.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Control characters that have no business appearing literally in Dart
/// source. Tab (0x09), line feed (0x0A) and carriage return (0x0D) are
/// excluded — those are ordinary formatting.
bool _isForbiddenControlByte(int byte) =>
    byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D;

void main() {
  test('no Dart source file contains a raw control byte — git must be able to '
      'diff and blame every file we ship', () {
    // Tests run with the package root as the working directory.
    final List<File> sources =
        <File>[
              for (final String dir in <String>['lib', 'test'])
                ...Directory(dir)
                    .listSync(recursive: true)
                    .whereType<File>()
                    .where((File f) => f.path.endsWith('.dart')),
            ]
            // Deterministic order, so a failure names the same file for
            // everyone and is trivial to reproduce.
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));

    expect(
      sources,
      isNotEmpty,
      reason:
          'found no Dart files at all — the test is running from an '
          'unexpected working directory and is silently guarding nothing',
    );

    final List<String> offenders = <String>[];
    for (final File file in sources) {
      final List<int> bytes = file.readAsBytesSync();
      final int index = bytes.indexWhere(_isForbiddenControlByte);
      if (index >= 0) {
        offenders.add(
          '${file.path} (byte 0x${bytes[index].toRadixString(16).padLeft(2, '0')} '
          'at offset $index)',
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'these files contain a literal control byte, so git treats them as '
          'binary and no one can review a change to them again. Write the '
          'Dart escape sequence (e.g. \\x00) instead of the raw byte: '
          '${offenders.join(', ')}',
    );
  });

  /// **KHA-115's guard.**
  ///
  /// Flutter's `SnackBar` constructor does `persist = persist ?? action != null`,
  /// so **any** snackbar carrying a `SnackBarAction` stays on screen forever
  /// unless `persist: false` is passed explicitly. That is how a category
  /// correction's *Undo* ended up floating over four unrelated screens for nine
  /// minutes and silently reverting real work when it was tapped by accident.
  ///
  /// The fix lives in one place — `showScopedSnackBar` — and this test is what
  /// keeps it the only place. A lint cannot express "pass this argument", and a
  /// comment asking the next author to remember is exactly the kind of rule
  /// `docs/lessons.md` records failing twice. So the rule is mechanical: if a
  /// second `SnackBarAction` appears in `lib/`, the build fails and the message
  /// says what to do instead.
  test('SnackBarAction is constructed in exactly one place — the KHA-115 '
      'stuck-snackbar defect cannot be reintroduced by a new call site', () {
    const String sanctioned = 'scoped_snack_bar.dart';

    final List<String> offenders = <String>[];
    for (final File file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.endsWith(sanctioned)) {
        continue;
      }
      final String source = file.readAsStringSync();
      if (source.contains('SnackBarAction(')) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'a SnackBar with an action defaults to persist: true and will never '
          'dismiss itself (KHA-115). Raise it through '
          'showScopedSnackBar(...) in lib/presentation/widgets/'
          '$sanctioned instead, which passes persist: false and scopes the '
          'action to the route that raised it: ${offenders.join(', ')}',
    );
  });
}
