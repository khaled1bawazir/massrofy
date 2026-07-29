// QA re-verification probe for PR #37 / KHA-108 (throwaway file; the branch
// carrying it is deleted after the run, and this PR is never merged).
//
// Run 2 of 3. Deliberately format-clean and analyze-clean so the ONLY gate
// it can trip is `flutter test`. Run 3 corrects the assertion and must go
// green again, which is what makes this a single-variable experiment rather
// than an anecdote.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deliberate failure: proves qa-pr-lint really runs flutter test', () {
    expect(2 + 2, 5);
  });
}
