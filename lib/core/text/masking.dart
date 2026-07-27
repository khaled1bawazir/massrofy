/// Display-masking helpers for card/account identifiers (NFR-S2).
///
/// Important distinction from `sms_sanitizer.dart`: [SmsSanitizer] destroys
/// sensitive data **before storage** (it runs once, at ingestion). The
/// functions here run **at display time**, over data the schema is already
/// incapable of holding in full (there is no column anywhere that can hold a
/// full PAN — see `docs/architecture.md` §4.3), so masking here is about
/// presenting an already-masked identifier consistently, not about
/// redacting anything secret.
library;

/// Formats an already-masked identifier (e.g. the last 4 digits a bank SMS
/// gave us) as `•••• 4821`, matching `docs/design.md`'s `MaskedIdentifier`
/// component and `docs/mockups/banks.html`.
///
/// [last4] must already be the last 4 digits/characters as received — this
/// function never has, and must never be given, a full number to truncate
/// itself. If [last4] is shorter than 4 characters (some banks send fewer),
/// it is displayed as-is after the mask dots, never padded with invented
/// digits.
String formatMaskedCardOrAccount(String last4) {
  final String trimmed = last4.trim();
  return '•••• $trimmed';
}

/// Formats an already-masked Saudi IBAN fragment as `SA**…7712`, matching
/// the redaction/display form ADR-013 specifies.
String formatMaskedIban(String last4) {
  final String trimmed = last4.trim();
  return 'SA**…$trimmed';
}

/// A length-preserving mask for an amount string, used by the Home/Reports
/// "Privacy Mode" toggle (`docs/design.md` §3.2 item 2 — shoulder-surfing
/// protection, session-only, resets to visible on next unlock). Unlike
/// PAN/IBAN masking above, this is **not** a security control — the value
/// still exists in full in memory and in the database; it only avoids
/// displaying a total on-screen when the user chooses to hide it.
///
/// Non-digit characters (currency codes, separators, the sign) are kept as
/// literal context so the masked form still visually reads as "an amount",
/// per the design rationale in `docs/design.md`; only the digits themselves
/// become bullets.
String maskAmountForDisplay(String formattedAmount) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in formattedAmount.runes) {
    final String char = String.fromCharCode(rune);
    if (RegExp(r'\d').hasMatch(char)) {
      buffer.write('•');
    } else {
      buffer.write(char);
    }
  }
  return buffer.toString();
}
