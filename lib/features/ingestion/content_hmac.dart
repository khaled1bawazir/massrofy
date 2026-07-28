/// ADR-017's D1 exact-duplicate key:
///
/// > `contentHmac = HMAC-SHA256(k, normalisedBody ‖ sender ‖ smsTimestamp)`,
/// > UNIQUE — "storing an HMAC rather than the text keeps the dedup index
/// > non-reversible".
///
/// ## Why an HMAC and not a plain hash
///
/// A plain SHA-256 of an SMS body is **reversible in practice**. Bank SMS come
/// from a small number of templates with a small number of variable fields; an
/// attacker holding the database (and it is on a phone, so assume they might)
/// could enumerate `amount × merchant × card-suffix × timestamp` for a given
/// template and match hashes offline. That would turn a "non-reversible dedup
/// index" into a lookup table for exactly the data ADR-003 encrypted the
/// database to protect.
///
/// Keying it with a secret held in the Android Keystore removes the offline
/// attack entirely: without the key there is nothing to enumerate against.
///
/// ## Why the *normalised* body, not the raw or the redacted one
///
/// Three candidates, and the choice matters:
///
///  - **Raw body** — a carrier redelivery can differ in invisible bidi marks
///    or whitespace, so two deliveries of the same message would hash
///    differently and dedup would silently fail. This is the exact case D1
///    exists for.
///  - **Redacted body** — dedup semantics would then shift whenever a
///    redaction rule changed. A sanitiser improvement would make every
///    previously-seen message look new, and the user would get a wave of
///    duplicates from a security fix.
///  - **Normalised body** — stable against delivery noise, and independent of
///    redaction. Chosen. `RawMessageDao` documents the same requirement from
///    the storage side.
///
/// Note this means the HMAC is computed over text that may still contain a
/// secret. That is fine and is the whole point of hashing: the digest is
/// stored, the input is not.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

abstract final class ContentHmac {
  /// Fixed label for deriving this protocol's HMAC subkey from the shared
  /// audit-chain root key via `DomainSeparatedKey.derive` (see that file for
  /// the full rationale, and `ingestion_providers.dart` for where the
  /// derivation actually happens). [compute]'s `key` parameter must always
  /// be a subkey derived with this label, never the root key itself —
  /// reusing one raw key across the audit chain's HMAC and this one would
  /// let a single leaked/forged key authenticate two unrelated protocols
  /// (KHA-21 / ADR-017 B5), which defeats the point of an HMAC whose only
  /// job is tamper-evidence.
  static const String keyDerivationLabel = 'massrofy/dedup-content-hmac/v1';

  /// The D1 key for one message.
  ///
  /// [key] must be the audit-chain root key's dedup subkey — derive it with
  /// `DomainSeparatedKey.derive(rootKey: auditChainKey, label:
  /// ContentHmac.keyDerivationLabel)` — never the raw `auditChainKey`
  /// itself. See [keyDerivationLabel]'s doc comment for why.
  ///
  /// The three inputs are joined with `\x00`, a byte that cannot occur in
  /// SMS text. Concatenating without a separator would let a crafted sender
  /// and body pair produce the same digest as a different sender/body pair
  /// (`"AB" + "C"` and `"A" + "BC"`) — a textbook length-extension-adjacent
  /// ambiguity, and one that here would mean one message silently suppressing
  /// an unrelated one.
  static String compute({
    required List<int> key,
    required String normalizedBody,
    required String sender,
    required DateTime smsTimestampUtc,
  }) {
    final String material = <String>[
      normalizedBody,
      sender,
      smsTimestampUtc.toUtc().millisecondsSinceEpoch.toString(),
    ].join('\x00');

    final Hmac hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(material)).toString();
  }
}
