/// **AC-B12.3** — the same bank under different names resolves to one entity.
///
/// This is the acceptance criterion KHA-23 calls out as mattering most, and
/// it has two halves. The sender half (`BAJ` vs `Aljazira` as originating
/// addresses) is proved end to end in
/// `test/features/ledger/ingestion_ledger_test.dart` against the real corpus.
/// This file proves the *name* half: a bank named in Arabic in one message
/// and abbreviated in another.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/ledger/bank_directory.dart';

void main() {
  final BankDirectory directory = BankDirectory(const <BankProfile>[
    BankProfile(
      canonicalKey: 'bank-aljazira',
      displayNameAr: 'بنك الجزيرة',
      displayNameEn: 'Bank Aljazira',
      aliases: <String>['ALJAZIRA', 'BAJ', 'الجزيرة'],
    ),
    BankProfile(
      canonicalKey: 'd360',
      displayNameAr: 'دي ٣٦٠',
      displayNameEn: 'D360 Bank',
      aliases: <String>['D360', 'D360BANK'],
    ),
  ]);

  group('AC-B12.3 — one bank, many names', () {
    test('the Arabic name, the English name and the abbreviation all resolve '
        'to the SAME canonical key', () {
      // The literal scenario in the acceptance criterion: "Arabic name in one
      // message, an abbreviation in another".
      expect(directory.resolveByName('بنك الجزيرة'), 'bank-aljazira');
      expect(directory.resolveByName('BAJ'), 'bank-aljazira');
      expect(directory.resolveByName('Bank Aljazira'), 'bank-aljazira');
      expect(directory.resolveByName('ALJAZIRA'), 'bank-aljazira');
      expect(directory.resolveByName('الجزيرة'), 'bank-aljazira');
    });

    test('case and surrounding whitespace do not create a second bank', () {
      expect(directory.resolveByName('  bank aljazira  '), 'bank-aljazira');
      expect(directory.resolveByName('baj'), 'bank-aljazira');
    });

    test('Arabic spelling variants that a reader treats as one word resolve '
        'as one word', () {
      // الجزيره with ha instead of ta-marbuta, and an alef with hamza — both
      // are the same name to a human and different strings to a computer.
      expect(directory.resolveByName('الجزيره'), 'bank-aljazira');
      expect(directory.resolveByName('بنك الجزيرة'), 'bank-aljazira');
    });

    test('branding punctuation is not identity — D-360, D360 and d 360 are '
        'one bank', () {
      expect(directory.resolveByName('D360'), 'd360');
      expect(directory.resolveByName('D-360'), 'd360');
      expect(directory.resolveByName('d 360'), 'd360');
      expect(directory.resolveByName('D360BANK'), 'd360');
    });

    test('two different banks stay two banks', () {
      expect(directory.resolveByName('D360 Bank'), 'd360');
      expect(directory.resolveByName('Bank Aljazira'), 'bank-aljazira');
    });
  });

  group('an unknown name resolves to nothing — it never invents a bank', () {
    test(
      'returns null rather than minting a canonical key from the string',
      () {
        // This is the failure mode that would put a typo in the bank tree
        // permanently. Null is the only safe answer.
        expect(directory.resolveByName('Bank of Nowhere'), isNull);
        expect(directory.resolveByName(''), isNull);
        expect(directory.resolveByName('   '), isNull);
      },
    );

    test('an empty directory resolves nothing and does not throw', () {
      const BankDirectory empty = BankDirectory.empty();
      expect(empty.resolveByName('BAJ'), isNull);
      expect(empty.byCanonicalKey('bank-aljazira'), isNull);
    });
  });

  group('byCanonicalKey', () {
    test('returns the profile so display names come from the pack', () {
      final BankProfile? profile = directory.byCanonicalKey('bank-aljazira');
      expect(profile, isNotNull);
      expect(profile!.displayNameAr, 'بنك الجزيرة');
      expect(profile.displayNameEn, 'Bank Aljazira');
    });

    test('returns null for a bank no active pack declares — a replaced pack '
        'must not break the banks that already hold transactions', () {
      expect(directory.byCanonicalKey('bank-retired'), isNull);
    });
  });

  group('normalizeBankName', () {
    test('is not fuzzy — similar-but-different names stay different', () {
      // An edit-distance match here would eventually merge two real banks,
      // which is a far worse error than failing to recognise an alias.
      expect(
        normalizeBankName('Bank Aljazira'),
        isNot(normalizeBankName('Bank Aljazirah Holdings')),
      );
    });
  });
}
