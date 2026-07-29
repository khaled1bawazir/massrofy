QA re-verification probe for PR #37 / KHA-108 (throwaway; branch is deleted after the run).

Run 1 of 3 -- baseline. Docs-only diff on a PR whose base is NOT `main`.
Expected: qa-pr-lint succeeds, including the newly added `flutter test
--exclude-tags=release_mode_guard` step.
