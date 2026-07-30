/// **KHA-146 — what the parser managed to read from a message it could not
/// finish parsing.**
///
/// ## The defect this type exists to close
///
/// When a rule's `RuleMatch` gate passes and its extraction `regex` matches,
/// `RulePackMessageParser` builds a complete [ParsedFields] — amount,
/// merchant, card, date, the lot — and *then* checks `requiredFields`. If one
/// required field came out empty the message is correctly routed to the review
/// queue (AC-A4.1, NFR-A7, nothing is ever dropped)… and until this type
/// existed, **every field that had extracted successfully was thrown away on
/// the way there**. The "Complete the details" form (S-19) then had nothing to
/// work from but the raw text, so the user retyped an amount, a merchant and a
/// card the app had already read correctly, because one *other* field failed.
///
/// Live evidence on the human's device (KHA-146): a purchase notification
/// containing a type word, a card, a merchant, an amount and a date arrived at
/// the form with **only the date** filled in.
///
/// ## The two cases this type deliberately keeps apart
///
/// - **(a) no rule matched at all** (`UnparsedReason.noRuleMatched`,
///   `extractionRegexFailed`, `ruleTimedOut`) — nothing was ever extracted, so
///   there is nothing honest to pre-fill. The value here is `null` and a blank
///   form is the correct outcome.
/// - **(b) a rule matched and extracted, but `requiredFields` failed**
///   (`UnparsedReason.requiredFieldMissing`) — this is the case with data to
///   carry, and the only case that produces a non-null value.
///
/// Conflating them is how "we understood nothing" would start pre-filling a
/// form with fields nobody read.
///
/// ## This is UNCONFIRMED data, and that is a money-safety property
///
/// Everything here is a *suggestion for a form*, never a transaction. It lives
/// on the `raw_message` row, not on `transactions`; it is never summed, never
/// counted, and never reaches a total. The only way it becomes money is the
/// user reading the pre-filled form and pressing **Save as transaction** —
/// exactly the same explicit confirmation as before, on exactly the same
/// screen. Nothing in this file writes to the ledger.
///
/// ## Why persisting it adds no new privacy exposure (NFR-P4, ADR-013)
///
/// Every value here is derived from `raw_message.sanitized_body`, which is
/// **already stored on the same row** — redacted at the ingestion boundary,
/// with the PAN masked to last-4 by `InstrumentMask` before it can ever reach
/// [instrumentMaskedRef]. This is a structured *projection* of text the app
/// already keeps for AC-A4.1, not a new category of retained data. It is
/// deleted with the row, like everything else on it.
library;

import 'dart:convert';

import 'parsed_fields.dart';

/// The subset of a partial extraction that the S-19 completion form can
/// actually use.
///
/// **Deliberately not "every field `ParsedFields` holds".** `feeAmount`,
/// `convertedAmount`, `exchangeRate`, `remainingBalance` and the counterparty
/// fields are omitted because the manual-completion path
/// (`TransactionDao.insertManualCompletion`) has nowhere to put them — storing
/// them would be data that nothing can read, which rots. When the completion
/// form grows a field, add it here in the same change.
final class PartialExtraction {
  /// Exact decimal text, e.g. `"152.75"` — never a `double` (ADR-002), and
  /// deliberately a `String` rather than a `Money` so the presentation layer
  /// can drop it straight into a text field without importing the money type
  /// or re-formatting a value the bank already printed.
  final String? amountText;

  /// ISO 4217 code that went with [amountText]. Null whenever [amountText] is
  /// null: NFR-A5 allows no amount without a currency, so the two travel
  /// together or not at all.
  final String? currencyCode;

  final String? merchantRawText;

  /// `card` | `account` (`InstrumentKind`), from the matched rule's declared
  /// kind — never guessed from how many digits were printed (AC-B13.1/2).
  final String? instrumentKind;

  /// Already masked to last-4, e.g. `****4821`. There is no path by which a
  /// fuller identifier can arrive here (NFR-S2): the value comes from
  /// `InstrumentReference.maskedIdentifier`, which `InstrumentMask.maskLast4`
  /// is the sole producer of.
  final String? instrumentMaskedRef;

  /// The instant the message stated, already interpreted as `Asia/Riyadh` and
  /// converted to UTC (architecture §7.4).
  final DateTime? occurredAtUtc;

  /// The matched rule's `messageType`, e.g. `pos_purchase` — the "transaction
  /// type word" KHA-146 observed the message opening with.
  ///
  /// A rule pack may declare a type this build has never heard of (§5.2's
  /// forward-compatibility rule), so consumers must check it against a known
  /// vocabulary before using it. The form does exactly that.
  final String? transactionType;

  /// The `requiredFields` entries that actually came out empty — i.e. the
  /// fields the user genuinely has to supply.
  ///
  /// Carried so the form can be honest about *which* gap it is asking the
  /// person to fill, rather than presenting a half-filled form with no
  /// explanation of why some boxes are empty.
  final List<String> missingFields;

  const PartialExtraction({
    this.amountText,
    this.currencyCode,
    this.merchantRawText,
    this.instrumentKind,
    this.instrumentMaskedRef,
    this.occurredAtUtc,
    this.transactionType,
    this.missingFields = const <String>[],
  });

  /// True when at least one field is worth pre-filling.
  ///
  /// [missingFields] deliberately does not count: knowing *what failed* is not
  /// something the form can put in a box. A record that carries only missing
  /// field names is, to the form, the same as no record at all — which is why
  /// the ingestion pipeline declines to store one.
  bool get hasAnyValue =>
      amountText != null ||
      merchantRawText != null ||
      instrumentMaskedRef != null ||
      occurredAtUtc != null ||
      transactionType != null;

  /// Projects a [ParsedFields] built by a rule that then failed its
  /// `requiredFields` check.
  ///
  /// [transactionType] is the rule's `messageType` and [missingFields] the
  /// names that failed — both known to the parser at the point of failure and
  /// neither derivable from [fields] alone.
  factory PartialExtraction.fromParsedFields(
    ParsedFields fields, {
    String? transactionType,
    List<String> missingFields = const <String>[],
  }) {
    return PartialExtraction(
      // `Money.amount` is a `Decimal`; its `toString()` is the exact decimal
      // literal, with no floating-point round-trip anywhere in the path.
      amountText: fields.amount?.amount.toString(),
      currencyCode: fields.amount?.currencyCode,
      merchantRawText: fields.merchantRawText,
      instrumentKind: fields.instrument?.kind,
      instrumentMaskedRef: fields.instrument?.maskedIdentifier,
      occurredAtUtc: fields.occurredAtUtc,
      transactionType: transactionType,
      missingFields: List<String>.unmodifiable(missingFields),
    );
  }

  /// A copy with the amount (and therefore its currency) removed.
  ///
  /// For the one caller that has a full extraction whose **amount** is the
  /// unusable part — the ingestion pipeline's defensive branch for an imported
  /// pack that produced a missing or negative amount. The merchant, card, date
  /// and type it read are still worth carrying; the figure is not, and
  /// pre-filling a rejected amount into a form the user is skimming is exactly
  /// the direction a spending tracker must never be wrong in.
  ///
  /// The currency goes with it: NFR-A5 allows no amount without a currency,
  /// and a currency alone tells the form nothing it does not already default.
  PartialExtraction withoutAmount() => PartialExtraction(
    merchantRawText: merchantRawText,
    instrumentKind: instrumentKind,
    instrumentMaskedRef: instrumentMaskedRef,
    occurredAtUtc: occurredAtUtc,
    transactionType: transactionType,
    missingFields: missingFields,
  );

  /// The stored form: compact JSON, written to
  /// `raw_message.partial_extraction`.
  ///
  /// Null-valued keys are **omitted rather than written as `null`**, so
  /// "absent" has exactly one spelling in the stored document and a decoder
  /// cannot accidentally distinguish two representations of the same unknown.
  String encode() {
    final Map<String, Object?> json = <String, Object?>{
      // A version tag, so a later build that changes this shape can decide
      // what to do with an old row instead of guessing. Cheap now,
      // impossible to add retroactively.
      _kVersion: _currentVersion,
      if (amountText != null) _kAmount: amountText,
      if (currencyCode != null) _kCurrency: currencyCode,
      if (merchantRawText != null) _kMerchant: merchantRawText,
      if (instrumentKind != null) _kInstrumentKind: instrumentKind,
      if (instrumentMaskedRef != null) _kInstrumentRef: instrumentMaskedRef,
      if (occurredAtUtc != null)
        _kOccurredAt: occurredAtUtc!.toUtc().toIso8601String(),
      if (transactionType != null) _kTransactionType: transactionType,
      if (missingFields.isNotEmpty) _kMissingFields: missingFields,
    };
    return jsonEncode(json);
  }

  /// Reads back what [encode] wrote, returning `null` for anything it cannot
  /// make sense of.
  ///
  /// **Every failure mode degrades to `null`, i.e. to a blank form**, and that
  /// is the deliberate direction to fail in: a malformed row must not crash
  /// the review queue for every *other* message (NFR-R5), and a half-decoded
  /// value must never become a pre-filled figure. `null` here costs the user
  /// some typing; a wrong number costs them a wrong total.
  static PartialExtraction? tryDecode(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(encoded);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      // An unknown (future) version is not decoded on a best-effort basis. A
      // newer build could give a key a different meaning, and quietly
      // reinterpreting it as this version's meaning is how a currency ends up
      // in an amount field.
      if (decoded[_kVersion] != _currentVersion) {
        return null;
      }

      final String? amountText = _string(decoded[_kAmount]);
      final String? currencyCode = _string(decoded[_kCurrency]);

      return PartialExtraction(
        // NFR-A5, enforced on read as well as on write: an amount without a
        // currency is not a usable amount, so neither survives alone. Without
        // this, a truncated row could pre-fill "152.75" against whatever
        // currency the form happened to default to.
        amountText: currencyCode == null ? null : amountText,
        currencyCode: amountText == null ? null : currencyCode,
        merchantRawText: _string(decoded[_kMerchant]),
        instrumentKind: _string(decoded[_kInstrumentKind]),
        instrumentMaskedRef: _string(decoded[_kInstrumentRef]),
        occurredAtUtc: _utcDateTime(decoded[_kOccurredAt]),
        transactionType: _string(decoded[_kTransactionType]),
        missingFields: _stringList(decoded[_kMissingFields]),
      );
    } on FormatException {
      // Not JSON at all. Same answer as every other unreadable case.
      return null;
    }
  }

  /// Accepts only a genuinely non-empty string. A JSON `null`, a number, or
  /// `""` all read as "not stated" (AC-B1.3) rather than as a value.
  static String? _string(Object? value) {
    if (value is! String) {
      return null;
    }
    return value.trim().isEmpty ? null : value;
  }

  static DateTime? _utcDateTime(Object? value) {
    final String? text = _string(value);
    if (text == null) {
      return null;
    }
    return DateTime.tryParse(text)?.toUtc();
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return List<String>.unmodifiable(<String>[
      for (final Object? entry in value)
        if (_string(entry) case final String name) name,
    ]);
  }

  /// **No amount, no merchant, no identifier** (NFR-S4, ADR-015). An object
  /// interpolated into a log line is the most plausible leak in a Dart
  /// codebase, and this one is made of exactly the values that must not leak,
  /// so it reports shape only — the same discipline as `ParsedFields`.
  @override
  String toString() {
    final int populated = <bool>[
      amountText != null,
      merchantRawText != null,
      instrumentMaskedRef != null,
      occurredAtUtc != null,
      transactionType != null,
    ].where((bool present) => present).length;
    return 'PartialExtraction(fields: $populated, '
        'missing: ${missingFields.length})';
  }

  // --- Stored key names ----------------------------------------------------
  //
  // Constants rather than inline literals because encode and decode must agree
  // exactly, and a typo in one of two string literals is the kind of bug that
  // shows up as "the amount silently stopped pre-filling" months later.

  static const int _currentVersion = 1;
  static const String _kVersion = 'v';
  static const String _kAmount = 'amount';
  static const String _kCurrency = 'currency';
  static const String _kMerchant = 'merchant';
  static const String _kInstrumentKind = 'instrumentKind';
  static const String _kInstrumentRef = 'instrumentRef';
  static const String _kOccurredAt = 'occurredAt';
  static const String _kTransactionType = 'transactionType';
  static const String _kMissingFields = 'missingFields';
}
