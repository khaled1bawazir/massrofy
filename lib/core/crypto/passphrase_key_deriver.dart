import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Derives the **Passphrase KEK** — the device-independent half of
/// ADR-004's key hierarchy — from the user's recovery secret plus a salt.
///
/// `docs/architecture.md` ADR-004 specifies `Argon2id(recoverySecret, salt,
/// m=64MiB, t=3, p=2)` for this derivation, and ADR-012 says the recovery
/// secret itself is a CSPRNG-generated 12-word BIP-39 mnemonic shown once
/// during backup setup — none of which exists yet, because Epic I (backup,
/// P8) is where that generation-and-confirmation flow is actually built.
///
/// **This P1 slice implements the interface with a real, working HKDF-based
/// derivation instead of Argon2id — a deliberate, documented stand-in, not
/// an oversight.** The task scope for this P1 foundation work explicitly
/// allows this: "the recovery secret generation itself can be a
/// stub/interface for now if Epic I backup isn't built yet, but the DB
/// encryption and Keystore wrapping must be real." Swapping
/// [Hkdf256PassphraseKeyDeriver] for a genuine Argon2id implementation in
/// P8 is a one-class change — every call site depends only on this
/// interface, never on the concrete algorithm.
///
/// **Do not ship [Hkdf256PassphraseKeyDeriver] as the production recovery
/// path.** HKDF is a fast key-derivation function with no deliberate
/// work-factor — it is the *wrong* primitive for stretching a low-entropy
/// user secret (though ADR-012's generated recovery phrase carries 128 bits
/// of entropy already, which somewhat mitigates this in the generated-phrase
/// mode specifically; it would not be safe for the user-chosen-passphrase
/// fallback mode ADR-012 also describes). Argon2id remains the documented
/// requirement for P8.
abstract interface class PassphraseKeyDeriver {
  /// Derives a 32-byte key from [secret] and [salt].
  Future<Uint8List> derive({
    required List<int> secret,
    required List<int> salt,
  });
}

/// STUB for P1 — see the interface doc comment above. Uses
/// HKDF-SHA256(secret, salt, info: "massrofy/dbkek/v1") instead of the
/// Argon2id ADR-004 specifies; replaced with a real Argon2id implementation
/// in Epic I (P8) once the recovery-secret/backup flow is built.
class Hkdf256PassphraseKeyDeriver implements PassphraseKeyDeriver {
  const Hkdf256PassphraseKeyDeriver();

  @override
  Future<Uint8List> derive({
    required List<int> secret,
    required List<int> salt,
  }) async {
    final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final SecretKey derived = await hkdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: salt,
      info: 'massrofy/dbkek/v1'.codeUnits,
    );
    final List<int> bytes = await derived.extractBytes();
    return Uint8List.fromList(bytes);
  }
}
