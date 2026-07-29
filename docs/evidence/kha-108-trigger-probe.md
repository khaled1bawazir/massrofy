QA trigger probe for KHA-108 / PR #37.

Purpose: prove `.github/workflows/qa-pr-lint.yml`'s
`on: pull_request: branches-ignore: [main]` actually fires when a PR's BASE
branch is not `main`, and that `ci.yml` (`branches: [main]`) does not.

This file, its branch, and its PR are throwaway and will be deleted.
