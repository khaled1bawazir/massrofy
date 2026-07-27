import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/text/masking.dart';

void main() {
  group('formatMaskedCardOrAccount (NFR-S2 display masking)', () {
    test('formats a last-4 string as bullet-dots + last4', () {
      expect(formatMaskedCardOrAccount('4821'), '•••• 4821');
    });

    test('does not pad a shorter identifier some banks send', () {
      expect(formatMaskedCardOrAccount('21'), '•••• 21');
    });
  });

  group('formatMaskedIban', () {
    test('formats as SA**…<last4>', () {
      expect(formatMaskedIban('7712'), 'SA**…7712');
    });
  });

  group('maskAmountForDisplay (Privacy Mode toggle, docs/design.md §3.2)', () {
    test('replaces every digit with a bullet, keeps other characters', () {
      expect(maskAmountForDisplay('45.00 SAR'), '••.•• SAR');
    });

    test('keeps a leading sign character intact', () {
      expect(maskAmountForDisplay('-1,204.50 SAR'), '-•,•••.•• SAR');
    });
  });
}
