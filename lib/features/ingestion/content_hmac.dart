/// ADR-017's D1 exact-duplicate key, **v2** (ADR-017 "KHA-137 decision",
/// approved 2026-07-30):
///
/// > `contentHmac = HMAC-SHA256(k, "massrofy/content-hmac/v2" ‖ normalisedBody
/// > ‖ normalisedSender)`, UNIQUE — "storing an HMAC rather than the text
/// > keeps the dedup index non-reversible".
///
/// ## Why the delivery timestamp is NOT in here (KHA-137)
///
/// v1 folded the SMS's `receivedAt` into the digest at millisecond precision.
/// That defeated the one case D1 exists for. A carrier redelivery is *by
/// definition* the same text arriving at a **different instant** under a
/// **new** inbox row — so `smsProviderId` cannot catch it (new row) and a
/// timestamped digest cannot catch it either (different instant). QA
/// reproduced this on a device: one SMS re-delivered 43 s later produced two
/// transactions and doubled the displayed month total.
///
/// So the digest is now a function of **the message text and its sender, and
/// nothing else**. Do not add a timestamp back, in any form. The architect
/// considered and rejected both softened variants:
///
///  - **Coarse-bucketing** the timestamp (per-day, per-hour) still fails at
///    every bucket boundary — i.e. it reproduces KHA-137 *intermittently*,
///    which is worse than a clean rule because it is unreproducible in the
///    field. And it buys nothing: byte-identical bodies already imply the
///    same in-body minute, so two genuinely separate purchases land in the
///    same bucket anyway.
///  - **Suppress only within a window `W`** loses by the same arithmetic:
///    the pair that must stay separate is co-located in time by
///    construction, so every useful `W` suppresses it too.
///
/// ### The residual, stated rather than buried (AC-A5.3)
///
/// Two *genuinely separate* purchases — same card, same merchant, same
/// amount, **within the same in-body minute** — produce byte-identical SMS,
/// and D1 will now suppress the second. This is irreducible from the message:
/// nothing in the text distinguishes them. It is narrow because every
/// transaction rule in the shipped pack captures `occurredAt` **to the
/// minute** from the body, so ordinary same-day repeat purchases still differ
/// in the text. Where AC-A5.1 (common: carrier retries) and AC-A5.3 (rare:
/// same-minute duplicate spend) formally contradict, we resolve toward
/// AC-A5.1 — a human-approved, disclosed trade. The suppression is not
/// invisible (`_withDedupGuard` writes the `duplicate_suppressed` diagnostic,
/// ADR-015) and the recovery is US-B4 manual entry.
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
/// The **sender is canonicalised the same way** — `SmsTextNormalizer.normalize`
/// then lower-cased — for the same reason, one level down. Rule-pack
/// `senderPatterns` compile with `caseSensitive: false`, so the *parser*
/// already treats `D360` and `d360` as one bank; a case-sensitive digest would
/// treat them as two messages and dedup would miss. Closed here rather than
/// later because v2 is invalidating every stored digest anyway, and a second
/// invalidation would cost the user a second exposure window.
///
/// Note this means the HMAC is computed over text that may still contain a
/// secret. That is fine and is the whole point of hashing: the digest is
/// stored, the input is not.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/text/sms_text_normalizer.dart';

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
  ///
  /// **This label stays at `v1` even though the message format moved to v2**
  /// (ADR-017 KHA-137 (B)). It separates *keys by protocol domain*, not
  /// message formats; bumping it would rotate a Keystore-derived subkey for
  /// no security reason. [_scheme] is the field that versions the format.
  static const String keyDerivationLabel = 'massrofy/dedup-content-hmac/v1';

  /// The D1 key for one message.
  ///
  /// [key] must be the audit-chain root key's dedup subkey — derive it with
  /// `DomainSeparatedKey.derive(rootKey: auditChainKey, label:
  /// ContentHmac.keyDerivationLabel)` — never the raw `auditChainKey`
  /// itself. See [keyDerivationLabel]'s doc comment for why.
  ///
  /// The inputs are joined with `\x00`, a byte that cannot occur in SMS text.
  /// Concatenating without a separator would let a crafted sender and body
  /// pair produce the same digest as a different sender/body pair
  /// (`"AB" + "C"` and `"A" + "BC"`) — a textbook length-extension-adjacent
  /// ambiguity, and one that here would mean one message silently suppressing
  /// an unrelated one.
  ///
  /// **There is deliberately no timestamp parameter** (KHA-137). It is
  /// *removed* rather than accepted-and-ignored, because an unused parameter
  /// is an invitation to wire it back in. See the library comment above for
  /// why, and for what was considered and rejected instead.
  ///
  /// [_scheme] leads the material so the digest is self-describing: a future
  /// v3 has to change the tag deliberately rather than collide with v2 by
  /// accident. Note this also means a v1 digest can never equal a v2 digest,
  /// which is what lets the two formats coexist in the same `UNIQUE` column
  /// across the update with no migration and no false suppression (ADR-017
  /// KHA-137 (C) — forward-only, DB stays at version 7).
  static String compute({
    required List<int> key,
    required String normalizedBody,
    required String sender,
  }) {
    final String material = <String>[
      _scheme,
      normalizedBody,
      // Canonicalise the sender the same way the body already was, so `D360`
      // and `d360` are one message rather than two. `normalize` additionally
      // drops bidi/zero-width marks and trims; that half is belt-and-braces
      // rather than load-bearing, because a sender carrying such a mark fails
      // `senderPatterns` upstream and never reaches a digest at all. Interior
      // spaces are deliberately preserved — `D 360` really is a different
      // sender id from `D360`.
      SmsTextNormalizer.normalize(sender).toLowerCase(),
    ].join('\x00');

    final Hmac hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(material)).toString();
  }

  /// The message-format version, distinct from [keyDerivationLabel] (which
  /// versions the *key domain*, not the format — see (B) of the KHA-137
  /// decision for why that one does NOT move).
  static const String _scheme = 'massrofy/content-hmac/v2';
}
