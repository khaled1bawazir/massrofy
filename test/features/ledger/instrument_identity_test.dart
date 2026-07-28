/// The instrument match key — AC-B3.2, AC-B13.1, AC-B13.2, AC-B15.1, NFR-S2.
///
/// Entity matching in this app has to work on **masked** identifiers, because
/// a masked identifier is all the app is ever allowed to hold. These tests
/// pin the three scopes that make four digits sufficient (bank, kind, digits)
/// and the two cases where the honest answer is "no instrument".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';

void main() {
  group('the key is stable across the mask forms banks actually print', () {
    test('`****4821`, `xxxx4821` and a bare `4821` are one instrument', () {
      final String a = buildInstrumentRefKey(
        bankCanonicalKey: 'bank-aljazira',
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
      )!;
      final String b = buildInstrumentRefKey(
        bankCanonicalKey: 'bank-aljazira',
        kind: InstrumentKind.card,
        maskedIdentifier: 'xxxx4821',
      )!;
      final String c = buildInstrumentRefKey(
        bankCanonicalKey: 'bank-aljazira',
        kind: InstrumentKind.card,
        maskedIdentifier: '4821',
      )!;

      expect(a, b);
      expect(b, c);
    });

    test('a template that prints more digits still matches one that prints '
        'four', () {
      expect(
        buildInstrumentRefKey(
          bankCanonicalKey: 'd360',
          kind: InstrumentKind.account,
          maskedIdentifier: '1234821',
        ),
        buildInstrumentRefKey(
          bankCanonicalKey: 'd360',
          kind: InstrumentKind.account,
          maskedIdentifier: '****4821',
        ),
      );
    });
  });

  group('the key is scoped so unrelated instruments never collide', () {
    test('the same last four at two banks are two instruments', () {
      expect(
        buildInstrumentRefKey(
          bankCanonicalKey: 'bank-aljazira',
          kind: InstrumentKind.card,
          maskedIdentifier: '****4821',
        ),
        isNot(
          buildInstrumentRefKey(
            bankCanonicalKey: 'd360',
            kind: InstrumentKind.card,
            maskedIdentifier: '****4821',
          ),
        ),
      );
    });

    test('AC-B13.1/2 — an account and a card sharing the last four are NOT '
        'conflated', () {
      // US-B13's whole point: "money sitting in my account" and "credit card
      // spend" must not merge. PRD §3.4 records that the same bank prints
      // both forms depending on the message type, so this collision is a
      // realistic accident rather than a contrived one.
      expect(
        buildInstrumentRefKey(
          bankCanonicalKey: 'bank-aljazira',
          kind: InstrumentKind.account,
          maskedIdentifier: '****4821',
        ),
        isNot(
          buildInstrumentRefKey(
            bankCanonicalKey: 'bank-aljazira',
            kind: InstrumentKind.card,
            maskedIdentifier: '****4821',
          ),
        ),
      );
    });
  });

  group('the key never depends on anything the user can change', () {
    test('AC-B3.2 — nothing in the key comes from a friendly name, a network '
        'or a card type', () {
      // The key is built from bank + kind + digits only. This test asserts
      // the *signature*: there is no parameter through which a rename could
      // reach the key, which is why renaming cannot spawn a duplicate.
      final String key = buildInstrumentRefKey(
        bankCanonicalKey: 'bank-aljazira',
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
      )!;
      expect(key, 'bank-aljazira:card:4821');
    });
  });

  group('cases where the honest answer is "no instrument" (AC-B1.3)', () {
    test('an unknown kind from an imported pack yields null, not a guess', () {
      expect(
        buildInstrumentRefKey(
          bankCanonicalKey: 'bank-aljazira',
          kind: 'wallet',
          maskedIdentifier: '****4821',
        ),
        isNull,
      );
    });

    test('an identifier with no digits yields null', () {
      expect(
        buildInstrumentRefKey(
          bankCanonicalKey: 'bank-aljazira',
          kind: InstrumentKind.card,
          maskedIdentifier: '****',
        ),
        isNull,
      );
    });
  });

  test('InstrumentKind.isKnown is the single gate on the vocabulary', () {
    expect(InstrumentKind.isKnown('account'), isTrue);
    expect(InstrumentKind.isKnown('card'), isTrue);
    expect(InstrumentKind.isKnown('Card'), isFalse);
    expect(InstrumentKind.isKnown('wallet'), isFalse);
  });
}
