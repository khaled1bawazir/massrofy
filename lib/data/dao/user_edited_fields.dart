/// **AC-B5.3 — "user intent always outranks the parser."**
///
/// The `transactions.user_edited_fields` column stores a JSON array of field
/// names a person has changed by hand, e.g. `["merchantRawText"]`. This file
/// is the only place that column is encoded or decoded, so the format cannot
/// drift between the write path that sets it and the read paths that must
/// respect it.
///
/// ## What it is actually for
///
/// Exactly one question, asked by every write path that did **not** originate
/// with the user:
///
/// > *May I overwrite this field?*
///
/// The answer is no if a person has already edited it. That covers AC-B5.3's
/// literal case (a re-scan of the source SMS) and — more importantly, because
/// it is the path that genuinely writes over existing rows — ADR-017 D2's
/// **enrichment merge**, which fills gaps in one transaction from another. A
/// merge that "enriched" a merchant name the user had corrected would undo the
/// correction silently, and the user would have no reason to look at that row
/// again.
///
/// ## Why the vocabulary is shared with the audit trail
///
/// The names stored here are the same strings the audit trail's
/// `fieldChanges[].field` uses. One vocabulary means the change history and
/// the protection list can be read against each other — *"merchantRawText was
/// edited by user at 14:02, and merchantRawText is protected"* is one fact
/// told twice, not two facts that could disagree.
library;

import 'dart:convert';

/// The field names an edit or a merge can name.
///
/// A closed set, and deliberately narrow: these are the fields US-B5's edit
/// form exposes. Anything not listed here cannot be user-edited, so nothing
/// can be *protected* by accident either.
abstract final class TransactionField {
  static const String amount = 'amount';
  static const String currency = 'currency';
  static const String merchantRawText = 'merchantRawText';
  static const String occurredAt = 'occurredAt';
  static const String direction = 'direction';
  static const String transactionType = 'transactionType';
  static const String categoryId = 'categoryId';
  static const String instrumentId = 'instrumentId';
  static const String referenceNumber = 'referenceNumber';
  static const String counterpartyName = 'counterpartyName';

  static const Set<String> all = <String>{
    amount,
    currency,
    merchantRawText,
    occurredAt,
    direction,
    transactionType,
    categoryId,
    instrumentId,
    referenceNumber,
    counterpartyName,
  };
}

/// Decodes the `user_edited_fields` column.
///
/// **Never throws.** A malformed or hand-edited value yields the empty set,
/// which is the *conservative* direction to fail in for this particular
/// column: it means a subsequent merge is permitted to enrich the row, i.e.
/// the app behaves as though the row had never been edited. The alternative —
/// treating unreadable JSON as "everything is protected" — would silently
/// freeze a row against all future enrichment with no way for the user to see
/// why. Neither failure is good; this one is visible in the change history.
Set<String> decodeUserEditedFields(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const <String>{};
  }
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) {
      return const <String>{};
    }
    return <String>{
      for (final Object? entry in decoded)
        if (entry is String && TransactionField.all.contains(entry)) entry,
    };
  } on FormatException {
    return const <String>{};
  }
}

/// Encodes [fields] for storage, or returns null when nothing is protected.
///
/// Null rather than `"[]"` so "nobody has edited this row" is the *absence* of
/// a value, matching every other nullable column in this schema (AC-B1.3's
/// explicit-unknown discipline). The names are sorted so two rows with the
/// same protected set store byte-identical text, which keeps diffs and test
/// expectations stable.
String? encodeUserEditedFields(Set<String> fields) {
  if (fields.isEmpty) {
    return null;
  }
  final List<String> sorted = fields.toList()..sort();
  return jsonEncode(sorted);
}
