// QA re-verification probe for PR #37 / KHA-108 (throwaway file; the branch
// carrying it is deleted after the run, and this PR is never merged).
//
// Run 3 of 3. Identical to run 2 except for the expected value, so the
// green -> red -> green transition isolates the `flutter test` step as the
// cause.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('corrected assertion: qa-pr-lint goes green again', () {
    expect(2 + 2, 4);
  });
}
