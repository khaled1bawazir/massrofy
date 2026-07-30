/// **KHA-128 — gate 1: does the app recognise the sender at all?**
///
/// ## The defect this suite exists to make impossible again
///
/// The bundled pack shipped `senderPatterns` that were *written from
/// assumption* and matched nothing on a real device: `^(BAJ|Aljazira|AlJazira|
/// BankAlJazira)$` against a phone that shows the sender as **`Jazira Bank`**,
/// and `^(D360|D360Bank|D-360)$` against **`D360 Bank`**. Neither string
/// matched any alternative, so both banks failed
/// `RulePackMessageParser._resolveBank`, both returned
/// [NotFinancialSender] — and NFR-P4 then discarded every message *with no
/// trace at all*, not even a counter row. The user saw `0.00 SAR`, an empty
/// Needs Review queue, and nothing in the app that could explain either.
///
/// That failure mode is silent by design, which is what makes it dangerous:
/// there is no log, no row and no counter to notice. The only place it can be
/// caught is here, by asserting the confirmed sender strings against the
/// shipped asset.
///
/// ## The seven strings, and where they come from
///
/// Read off the reporting user's phone and confirmed on KHA-128 (2026-07-30).
/// They are sender **ids**, not message content — nothing here reproduces a
/// real message body, so NFR-M3 is untouched.
///
/// ## A note for readers new to Dart
///
/// The pack is loaded from the real asset file with a plain `File` read rather
/// than through `rootBundle`. That keeps this a fast pure-Dart test (no widget
/// binding, no asset manifest) while still exercising the exact bytes that
/// ship in the APK — so a typo in `assets/rule_packs/sa-core.json` fails CI
/// instead of surfacing on a device.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';
import 'package:massrofy/core/text/sms_text_normalizer.dart';
import 'package:massrofy/features/parsing/parse_outcome.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../ingestion/support/load_bundled_pack.dart';

/// Every sender string the human confirmed, mapped to the `bankId` it must
/// resolve to.
///
/// Deliberately a literal table rather than something derived from the pack:
/// deriving the expectation from the data under test would make this suite
/// pass no matter what the data said.
const Map<String, String> _confirmedSenders = <String, String>{
  'Jazira Bank': 'bank-aljazira',
  'nera': 'nera',
  'D360 Bank': 'd360',
  'AlRajhi Bank': 'al-rajhi',
  'STC Bank': 'stc-bank',
  'SAIB': 'saib',
  'SAB': 'sab',
};

/// The alternatives that were already in the pack before KHA-128. They were
/// guesses, but they may still be what *some* message variants arrive as, so
/// the fix **adds** to them rather than replacing them. This table is what
/// stops a future tidy-up from deleting them.
const Map<String, String> _preexistingSenders = <String, String>{
  'BAJ': 'bank-aljazira',
  'Aljazira': 'bank-aljazira',
  'AlJazira': 'bank-aljazira',
  'BankAlJazira': 'bank-aljazira',
  'D360': 'd360',
  'D360Bank': 'd360',
  'D-360': 'd360',
};

void main() {
  late RulePack pack;
  late RulePackMessageParser parser;

  setUpAll(() {
    pack = loadBundledRulePack();
    parser = RulePackMessageParser(packs: <RulePack>[pack]);
  });

  /// The `bankId` whose `senderPatterns` claim [sender], or `null` for none.
  ///
  /// Mirrors the engine's own resolution order (first pack, first bank, first
  /// pattern wins) so this helper cannot disagree with production about which
  /// bank owns an overlapping sender.
  String? bankIdForSender(String sender) {
    for (final BankRule bank in pack.banks) {
      for (final RegExp pattern in bank.senderPatterns) {
        if (pattern.hasMatch(sender.trim())) {
          return bank.bankId;
        }
      }
    }
    return null;
  }

  /// Runs the real parse path for a sender, with a body containing no keyword
  /// any rule gates on — so the *only* thing under test is sender resolution.
  ParseOutcome parseNeutralBody(String sender) {
    const String body = 'ping';
    final SanitizedSmsText sanitized = SmsSanitizer.sanitize(
      body,
      extraRedactPatterns: parser.redactionPatternsForSender(sender),
    );
    return parser.parse(
      sanitized: sanitized,
      normalizedBody: SmsTextNormalizer.normalize(sanitized.value),
      sender: sender,
    );
  }

  group('the seven human-confirmed sender ids (KHA-128)', () {
    _confirmedSenders.forEach((String sender, String expectedBankId) {
      test('"$sender" is recognised as $expectedBankId', () {
        expect(
          bankIdForSender(sender),
          expectedBankId,
          reason:
              'this exact string is what the device shows. If it matches no '
              'bank, every message from $expectedBankId is discarded with no '
              'trace anywhere in the app (NFR-P4) — the KHA-128 defect.',
        );
      });

      // Case is not a property of a sender id we can rely on: the same bank
      // is `SAB` in one carrier's delivery and `Sab` in another's. The loader
      // compiles every pattern with `caseSensitive: false`, and this asserts
      // that rather than trusting it.
      test('"$sender" is recognised case-insensitively', () {
        expect(bankIdForSender(sender.toUpperCase()), expectedBankId);
        expect(bankIdForSender(sender.toLowerCase()), expectedBankId);
      });

      // The whole point of gate 1: whatever else happens downstream, a
      // message from this sender is NOT thrown away.
      test('"$sender" never yields NotFinancialSender through the real '
          'parser', () {
        final ParseOutcome outcome = parseNeutralBody(sender);
        expect(
          outcome,
          isNot(isA<NotFinancialSender>()),
          reason:
              'NotFinancialSender means "retain nothing, not even a counter '
              'row". For a real bank that is a silently lost transaction.',
        );
      });
    });
  });

  group('the pre-KHA-128 alternatives are ADDED to, not replaced', () {
    _preexistingSenders.forEach((String sender, String expectedBankId) {
      test('"$sender" still resolves to $expectedBankId', () {
        expect(
          bankIdForSender(sender),
          expectedBankId,
          reason:
              'these were guesses, but an unused alternative costs nothing '
              'while a deleted-but-real one loses a financial message. '
              'KHA-128 widens the gate; it must not narrow it.',
        );
      });
    });
  });

  group('widening the gate did not make it promiscuous', () {
    // Each of these is a sender that looks like one of the seven and must
    // still be rejected. `^…$` anchoring is what makes that true, so these
    // cases are really testing that the anchors survived the edit.
    for (final String lookalike in <String>[
      // A bank's own marketing/rewards short code is a *different* sender id
      // and stays non-financial (this one is already in the corpus).
      'D360Rewards',
      'JaziraBankOffers',
      // The telecom operator, not the bank. `^STC\s*Bank$` deliberately does
      // not claim it: STC sends OTPs and marketing that are genuinely not
      // financial, and NFR-P4 keeping nothing about them is the promise the
      // transparency screen (US-F4) makes out loud.
      'STC',
      'stc',
      // Substring-of-a-real-bank and superstring cases.
      'SA',
      'SABB',
      'NOTSAB',
      'nerabank',
      // Ordinary senders.
      'ARAMEX',
      '+966500000000',
    ]) {
      test('"$lookalike" matches no bank', () {
        expect(bankIdForSender(lookalike), isNull);
        expect(parseNeutralBody(lookalike), isA<NotFinancialSender>());
      });
    }
  });

  group('the five sender-only banks are structurally complete (AC-A6.5)', () {
    for (final String bankId in <String>[
      'nera',
      'al-rajhi',
      'stc-bank',
      'saib',
      'sab',
    ]) {
      test('$bankId declares a sender and, deliberately, no templates', () {
        final BankRule bank = pack.banks.firstWhere(
          (BankRule b) => b.bankId == bankId,
        );
        expect(bank.senderPatterns, isNotEmpty);
        expect(
          bank.messageRules,
          isEmpty,
          reason:
              'no real message-body sample exists for this bank yet, and '
              'NFR-M3 forbids inventing one that pretends to be real. Zero '
              'rules is the correct, shippable state: AC-A6.5 routes the '
              'message to Needs Review instead.',
        );
        // Display names are required by the schema and are shown to the user,
        // never used for identity (identity is `bankId` — AC-B12.3).
        expect(bank.displayNameAr, isNotEmpty);
        expect(bank.displayNameEn, isNotEmpty);
      });
    }
  });
}
