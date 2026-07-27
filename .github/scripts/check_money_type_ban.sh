#!/usr/bin/env bash
# ADR-002 enforcement (docs/architecture.md): "Money is an exact-decimal,
# currency-tagged value object; `double` is banned by construction and by CI."
#
# This script implements ADR-002's enforcement item (1) literally:
#   "A CI grep failing the build on `double`, `num`, `.toDouble()`, or
#   `double.parse` anywhere under `lib/core/money/`, `lib/domain/`, or any file
#   matching `*money*`, `*amount*`, `*budget*`, `*report*`."
# and enforcement item (2):
#   "A CI grep failing the build on `SUM(`, `TOTAL(`, or `AVG(` in any `.drift`
#   file or raw SQL string that references a money column."
#
# Why grep, not just a Dart analyzer plugin: this repo does not have a Flutter
# project yet (mobile-engineer's P1 scaffold lands separately), and ADR-002
# explicitly names a CI grep as one of the two required enforcement mechanisms
# (the other, a custom_lint rule, is a Dart-analyzer-time complement — the
# mobile-engineer may add it in lib/ once the project exists; it does not
# replace this CI check, it supplements it).
#
# This script is intentionally safe to run before lib/ exists: it just finds
# nothing and passes. It starts enforcing the moment money-related Dart files
# are added, which is the point at which it matters.

set -euo pipefail

violations=0

fail() {
  echo "::error file=$1::ADR-002 violation (docs/architecture.md) — banned token '$2' found in a money-critical path. Money must be represented by lib/core/money/Money (package:decimal), never double/num."
  violations=1
}

# --- Part 1: double / num / toDouble() / double.parse banned in money paths ---
if [ -d lib ]; then
  # Word-boundary match so we don't false-positive on identifiers that merely
  # contain "double" or "num" as a substring (e.g. "numeral_normalizer.dart" the
  # filename is fine; it's the *token* inside code that's banned).
  BANNED_REGEX='(^|[^A-Za-z0-9_])(double|num)([^A-Za-z0-9_]|$)|\.toDouble\(\)|double\.parse\('

  # 1a. Explicit protected directories named in ADR-002.
  for dir in lib/core/money lib/domain; do
    if [ -d "$dir" ]; then
      while IFS= read -r -d '' f; do
        if grep -nE "$BANNED_REGEX" "$f" > /tmp/hits.$$; then
          fail "$f" "double/num"
          cat /tmp/hits.$$
        fi
        rm -f /tmp/hits.$$
      done < <(find "$dir" -type f -name '*.dart' -print0)
    fi
  done

  # 1b. Any file anywhere under lib/ matching *money*, *amount*, *budget*, *report*.
  while IFS= read -r -d '' f; do
    if grep -nE "$BANNED_REGEX" "$f" > /tmp/hits.$$; then
      fail "$f" "double/num"
      cat /tmp/hits.$$
    fi
    rm -f /tmp/hits.$$
  done < <(find lib -type f -name '*.dart' \
            \( -iname '*money*' -o -iname '*amount*' -o -iname '*budget*' -o -iname '*report*' \) \
            -print0)
else
  echo "No lib/ directory yet — Flutter app not scaffolded. Money-type guard has nothing to check yet; it will start enforcing as soon as lib/ exists."
fi

# --- Part 2: SUM(/TOTAL(/AVG( banned in .drift files (money aggregation must
#     happen in Dart over Money, never in SQL — see ADR-002's non-negotiable rule
#     about SUM()/AVG() on the `_minor` column). ---
if find . -type f -name '*.drift' -not -path './node_modules/*' 2>/dev/null | grep -q .; then
  while IFS= read -r -d '' f; do
    if grep -nEi '(SUM\(|TOTAL\(|AVG\()' "$f" > /tmp/hits.$$; then
      fail "$f" "SUM/TOTAL/AVG in .drift file"
      cat /tmp/hits.$$
    fi
    rm -f /tmp/hits.$$
  done < <(find . -type f -name '*.drift' -not -path './node_modules/*' -print0)
else
  echo "No .drift files yet — nothing to check for banned SQL aggregation."
fi

if [ "$violations" -ne 0 ]; then
  echo ""
  echo "ADR-002 (docs/architecture.md) is non-negotiable: money is exact-decimal only."
  echo "Fix: use lib/core/money/Money (package:decimal) and aggregate in Dart, never in SQL."
  exit 1
fi

echo "ADR-002 money-type guard: no banned double/num/SQL-aggregation usage found."
