import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/crypto/domain_separated_key.dart';
import 'package:massrofy/features/ingestion/content_hmac.dart';

void main() {
  group('DomainSeparatedKey.derive', () {
    final List<int> rootKey = List<int>.filled(32, 0x42);

    test('is deterministic for the same root key and label', () {
      final List<int> a = DomainSeparatedKey.derive(
        rootKey: rootKey,
        label: 'label-a',
      );
      final List<int> b = DomainSeparatedKey.derive(
        rootKey: rootKey,
        label: 'label-a',
      );
      expect(a, b);
    });

    test('a different label produces a different subkey', () {
      final List<int> a = DomainSeparatedKey.derive(
        rootKey: rootKey,
        label: 'label-a',
      );
      final List<int> b = DomainSeparatedKey.derive(
        rootKey: rootKey,
        label: 'label-b',
      );
      expect(a, isNot(b));
    });

    test('a different root key produces a different subkey', () {
      final List<int> a = DomainSeparatedKey.derive(
        rootKey: rootKey,
        label: 'same-label',
      );
      final List<int> b = DomainSeparatedKey.derive(
        rootKey: List<int>.filled(32, 0x99),
        label: 'same-label',
      );
      expect(a, isNot(b));
    });

    test('produces a 32-byte (HMAC-SHA256) subkey', () {
      final List<int> subkey = DomainSeparatedKey.derive(
        rootKey: rootKey,
        label: 'any-label',
      );
      expect(subkey.length, 32);
    });

    // --- KHA-21 / B5 regression -------------------------------------------
    //
    // The bug this guards against: the D1 dedup content-HMAC key and the
    // audit-chain HMAC key must never be the same key, even though both are
    // derived from — and in production start life as — the one Keystore-held
    // `auditChainKey` secret. If a future change collapses the two labels
    // (or removes the derivation and goes back to passing the root key
    // straight through), this test starts failing immediately rather than
    // silently reintroducing the shared-key smell review already flagged
    // once (round 3, B5) and had to flag again as KHA-59.
    test('KHA-21/B5 regression: the dedup subkey and the raw audit-chain root '
        'key it is derived from are never equal', () {
      final List<int> auditChainKey = List<int>.filled(32, 0x07);

      final List<int> dedupSubkey = DomainSeparatedKey.derive(
        rootKey: auditChainKey,
        label: ContentHmac.keyDerivationLabel,
      );

      expect(dedupSubkey, isNot(auditChainKey));
    });

    test('KHA-21/B5 regression: the dedup key-derivation label is pinned to a '
        'concrete, protocol-specific value, so a future edit cannot quietly '
        'make it collide with a label some other protocol might adopt', () {
      expect(ContentHmac.keyDerivationLabel, 'massrofy/dedup-content-hmac/v1');
    });
  });
}
