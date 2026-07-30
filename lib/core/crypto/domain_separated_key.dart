/// Domain-separated subkey derivation — turns one Keystore-held root secret
/// into several **independent** HMAC keys, one per protocol, instead of
/// letting those protocols share the literal root key material.
///
/// ## Why this exists (KHA-21 / B5, ADR-017 D1)
///
/// ADR-010's `auditChainKey` seeds the audit trail's tamper-evidence chain
/// (`AuditLogDao._computeHash`: `HMAC_k(prevHash '|' canonicalPayload)`).
/// ADR-017's D1 dedup also needs a Keystore-held HMAC key
/// (`ContentHmac.compute`: `HMAC_k(scheme '\x00' normalisedBody '\x00'
/// normalisedSender)` — the delivery timestamp was dropped from that material
/// by the KHA-137 decision; see `ContentHmac`). P2 originally passed
/// `auditChainKey` straight into both — "one secret, two uses" — which review
/// caught as exactly the wrong instinct for a mechanism whose entire job is
/// tamper-evidence: the two protocols only stayed collision-free by the
/// accident that one input encoding ends in JSON's `}` and the other ends in
/// the digits of a timestamp. That is not a property either protocol was
/// designed to rely on, so it is not one this codebase should ship relying on
/// — and KHA-137 has since removed that trailing timestamp entirely, which is
/// precisely why the accident was never safe to depend on.
///
/// The fix keeps the single stored secret (still one Keystore-wrapped root
/// key, still one rotation/lifecycle story) but derives a distinct subkey
/// **per protocol** from it, each bound to a fixed, protocol-specific label:
/// `HMAC-SHA256(rootKey, label)`. Two different labels can never collapse to
/// the same subkey short of an HMAC collision — the same hardness assumption
/// every caller of these subkeys already depends on — so the audit chain and
/// D1 dedup become cryptographically independent even though only one secret
/// is ever provisioned or stored.
///
/// ## Why a fixed-label HMAC and not HKDF
///
/// [Hkdf256PassphraseKeyDeriver] (`passphrase_key_deriver.dart`) uses real
/// HKDF because its input keying material is a low-entropy user secret that
/// needs HKDF's extract step to whiten it before expanding. The root key
/// here is already a uniformly-random 32-byte CSPRNG value straight out of
/// the Keystore (see `AuditChainKeyStore`), so there is nothing to extract —
/// a single labelled HMAC call gives the same domain-separation guarantee
/// HKDF-expand would, with less code.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

abstract final class DomainSeparatedKey {
  /// Derives a subkey from [rootKey], bound to [label].
  ///
  /// Deterministic: the same `(rootKey, label)` pair always produces the
  /// same subkey, which is what lets D1 dedup keep matching a message it
  /// has already seen across app restarts. A different [label] — even one
  /// character different — produces an unrelated subkey.
  static List<int> derive({required List<int> rootKey, required String label}) {
    final Hmac hmac = Hmac(sha256, rootKey);
    return hmac.convert(utf8.encode(label)).bytes;
  }
}
