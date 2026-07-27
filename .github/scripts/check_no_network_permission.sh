#!/usr/bin/env bash
# ADR-001 enforcement (docs/architecture.md): "The release build declares no
# INTERNET permission and no ACCESS_NETWORK_STATE permission" — with explicit
# tools:node="remove" directives so no transitive dependency (a plugin, an SDK)
# can merge them back in. Flutter's debug/profile manifests deliberately KEEP
# INTERNET for hot reload — this check must run against the RELEASE variant
# only, never debug/profile, or it will produce a permanent false failure.
#
# Two layers, matching the architecture doc:
#   1. Static check — the source manifest must still carry both
#      tools:node="remove" directives (catches someone deleting them in review).
#   2. Build check — the actual MERGED release manifest (post Gradle manifest
#      merger, i.e. what really ships) must not contain either permission. This
#      is the authoritative check: (1) can be bypassed by a change elsewhere
#      that re-adds the permission before the merger step; (2) cannot.
#
# This script is a no-op (exit 0, clearly logged) until the Android project
# exists — mobile-engineer's P1 scaffold. It starts enforcing automatically
# the moment android/app/src/main/AndroidManifest.xml lands; no further devops
# action is required at that point.

set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"

if [ ! -f "$MANIFEST" ]; then
  echo "No $MANIFEST yet — Android project not scaffolded. Skipping ADR-001 no-network guard; it will activate automatically once the Flutter Android project exists."
  exit 0
fi

fail=0

# --- Layer 1: static source check ---
for perm in INTERNET ACCESS_NETWORK_STATE; do
  if ! grep -q "android.permission.${perm}\".*tools:node=\"remove\"" "$MANIFEST"; then
    echo "::error file=${MANIFEST}::ADR-001 violation — missing 'tools:node=\"remove\"' removal directive for android.permission.${perm}. See docs/architecture.md ADR-001."
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "Expected in ${MANIFEST}:"
  echo '  <uses-permission android:name="android.permission.INTERNET" tools:node="remove" />'
  echo '  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" tools:node="remove" />'
  exit 1
fi

echo "Layer 1 (static source manifest) OK: removal directives present for INTERNET and ACCESS_NETWORK_STATE."

# --- Layer 2: build check against the actual merged RELEASE manifest ---
# If a release build has already happened earlier in this job (e.g. deploy.yml
# builds the real staging APK before calling this script), reuse its merged
# manifest instead of building again. Otherwise, build the smallest possible
# release artifact (single ABI, no signing secrets required — Gradle falls
# back to debug signing with a warning if no release signingConfig is present
# yet) purely to force Gradle's manifest merger to run.
#
# The merged manifest path has moved across AGP versions
# (merged_manifests/, merged_manifest/, processReleaseManifest output, etc.),
# so search broadly for any release-variant AndroidManifest.xml under build/.
mapfile -t merged_manifests < <(find android/app/build build -type f -path '*release*AndroidManifest.xml' 2>/dev/null | sort -u)

if [ "${#merged_manifests[@]}" -eq 0 ]; then
  echo "No merged release manifest found from an earlier build step — building a release APK (arm64 only) to force the manifest merger and inspect the real merged manifest..."
  flutter build apk --release --target-platform android-arm64
  mapfile -t merged_manifests < <(find android/app/build build -type f -path '*release*AndroidManifest.xml' 2>/dev/null | sort -u)
fi

if [ "${#merged_manifests[@]}" -eq 0 ]; then
  echo "::error::Could not locate a merged release AndroidManifest.xml after 'flutter build apk --release'. The manifest-merger output layout may have changed with a newer Android Gradle Plugin version — devops-engineer must update .github/scripts/check_no_network_permission.sh's search path. Treating as a hard failure rather than silently passing (ADR-001 is non-negotiable)."
  exit 1
fi

for mf in "${merged_manifests[@]}"; do
  echo "Inspecting: $mf"
  if grep -Eq 'android\.permission\.(INTERNET|ACCESS_NETWORK_STATE)' "$mf"; then
    echo "::error file=${mf}::ADR-001 violation — the merged RELEASE manifest contains INTERNET and/or ACCESS_NETWORK_STATE. A dependency has re-introduced a network permission. See docs/architecture.md ADR-001 (AC-F4.2 depends on this being structurally impossible)."
    grep -En 'android\.permission\.(INTERNET|ACCESS_NETWORK_STATE)' "$mf"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "Layer 2 (merged release manifest) OK: no INTERNET / ACCESS_NETWORK_STATE permission present."
