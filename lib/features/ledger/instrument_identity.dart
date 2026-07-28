/// How two mentions of the same account or card are recognised as one
/// instrument — KHA-23, AC-B3.2, AC-B13.1/2, AC-B15.1, NFR-S2.
///
/// ## The constraint that shapes everything here
///
/// NFR-S2 means the app **only ever holds a masked identifier** — the last
/// four digits the bank itself printed. So entity matching has to work on the
/// masked form. That is not a workaround; it is the actual design constraint,
/// and Linear KHA-23 names it as "a real constraint, not an afterthought".
///
/// Four digits are not globally unique, so the key is scoped by the two other
/// facts we know for certain:
///
/// ```
/// refKey = <bank canonical key> : <kind> : <digits>
/// ```
///
///  - **bank** — `****4821` at one bank and `****4821` at another are two
///    different cards, and merging them would put one bank's spending on the
///    other's page.
///  - **kind** — PRD §3.4 observed the same bank printing a bare *account*
///    number in a transfer message and a masked *card* number in a purchase
///    message. If an account happened to end in the same four digits as a
///    card, collapsing them would conflate "money in my account" with "credit
///    card spend", which is the exact confusion US-B13 exists to prevent.
///  - **digits** — the identifier reduced to digits only, so `****4821`,
///    `xxxx4821` and `4821` are one key. Bank templates differ in their mask
///    characters; the digits are the stable part.
///
/// What the key deliberately does **not** contain: the friendly name (US-B3 —
/// renaming must not spawn a duplicate, AC-B3.2), the network, or the card
/// type. Those are attributes of the instrument, not its identity.
///
/// ## Residual collision, stated honestly
///
/// Two different cards at the same bank whose last four digits coincide will
/// resolve to one instrument. With four digits that is a 1-in-10,000 chance
/// per pair, and there is no additional information in the SMS to separate
/// them — the app cannot see more than the bank printed. The alternative
/// (splitting on any other observed difference) would produce duplicate
/// instruments for the *common* case, which is a worse and far more frequent
/// error. This is recorded here rather than left as a surprise.
library;

/// The declared kinds of instrument (architecture §4.2 `Instrument.kind`).
///
/// A closed vocabulary as constants rather than a Dart `enum`, because these
/// values are also what the rule pack writes in its `kind` field and what the
/// database stores — one spelling, checked in one place.
abstract final class InstrumentKind {
  static const String account = 'account';
  static const String card = 'card';

  static const Set<String> all = <String>{account, card};

  /// True when [value] is a kind this app understands.
  ///
  /// An unrecognised kind from an *imported* rule pack (ADR-007's answer to
  /// R-11) must not create a mystery instrument, so callers route it the same
  /// way an unreadable field is routed: the instrument stays unknown and the
  /// transaction is still recorded (AC-B1.3, NFR-A7).
  static bool isKnown(String value) => all.contains(value);
}

/// Where a link between a card and its settlement account came from.
abstract final class InstrumentLinkSource {
  /// AC-B14.1 — a card-repayment SMS that named both the card and the
  /// debiting account. The **only** automatic source.
  static const String smsRepayment = 'sms_repayment';

  /// The user said so.
  static const String user = 'user';
}

final RegExp _nonDigit = RegExp(r'[^0-9]');

/// Builds the stable match key for one instrument mention.
///
/// Returns `null` when [maskedIdentifier] carries no digits at all or [kind]
/// is not a kind this app knows — in both cases the honest outcome is "no
/// instrument", which the caller records as AC-B1.3's explicit unknown rather
/// than inventing a key that would match nothing consistently.
String? buildInstrumentRefKey({
  required String bankCanonicalKey,
  required String kind,
  required String maskedIdentifier,
}) {
  if (!InstrumentKind.isKnown(kind)) {
    return null;
  }
  final String digits = maskedIdentifier.replaceAll(_nonDigit, '');
  if (digits.isEmpty) {
    return null;
  }
  // Take the trailing four where there are at least four. Bank templates are
  // inconsistent about how much of an identifier they print, and a message
  // that showed six digits must still match one that showed four.
  final String tail = digits.length <= 4
      ? digits
      : digits.substring(digits.length - 4);
  return '$bankCanonicalKey:$kind:$tail';
}
