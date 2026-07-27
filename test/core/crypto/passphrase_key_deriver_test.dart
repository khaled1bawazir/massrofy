import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/crypto/passphrase_key_deriver.dart';

void main() {
  group('Hkdf256PassphraseKeyDeriver (P1 stub — see class doc comment)', () {
    const Hkdf256PassphraseKeyDeriver deriver = Hkdf256PassphraseKeyDeriver();

    test('derives a 32-byte key', () async {
      final result = await deriver.derive(
        secret: 'a fake recovery secret'.codeUnits,
        salt: List<int>.filled(32, 7),
      );
      expect(result.length, 32);
    });

    test('is deterministic for the same secret and salt', () async {
      final List<int> secret = 'same secret'.codeUnits;
      final List<int> salt = List<int>.filled(32, 1);
      final a = await deriver.derive(secret: secret, salt: salt);
      final b = await deriver.derive(secret: secret, salt: salt);
      expect(a, b);
    });

    test('a different salt produces a different key', () async {
      final List<int> secret = 'same secret'.codeUnits;
      final a = await deriver.derive(
        secret: secret,
        salt: List<int>.filled(32, 1),
      );
      final b = await deriver.derive(
        secret: secret,
        salt: List<int>.filled(32, 2),
      );
      expect(a, isNot(b));
    });

    test('a different secret produces a different key', () async {
      final List<int> salt = List<int>.filled(32, 1);
      final a = await deriver.derive(secret: 'secret-a'.codeUnits, salt: salt);
      final b = await deriver.derive(secret: 'secret-b'.codeUnits, salt: salt);
      expect(a, isNot(b));
    });
  });
}
