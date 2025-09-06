#!/usr/bin/env bash
# Minimal helper to inspect and optionally upgrade Flutter/Dart dependencies.
# Usage: ./upgrade_dependencies.sh        -> shows outdated list
#        ./upgrade_dependencies.sh apply  -> runs `flutter pub upgrade --major-versions`

set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."

echo "Working in: $(pwd)"
echo
echo "1) Showing outdated packages (run this first to review breaking changes)..."
flutter pub outdated || { echo "flutter pub outdated failed"; exit 1; }

if [ "${1:-}" = "apply" ]; then
  echo
  echo "2) Applying upgrades (flutter pub upgrade --major-versions)..."
  if flutter pub upgrade --major-versions; then
    echo "Upgrade completed. Now run: flutter pub get && flutter analyze && flutter test"
  else
    echo "Upgrade failed. Inspect errors and revert changes in pubspec.yaml if needed."
    exit 1
  fi
else
  echo
  echo "To attempt automatic major upgrades run: ./tools/upgrade_dependencies.sh apply"
fi

echo
# Quick check: detect grpc override usage
if grep -R "dependency_overrides" -n pubspec.yaml >/dev/null 2>&1; then
  if grep -n "grpc:" pubspec.yaml >/dev/null 2>&1; then
    echo "Note: pubspec.yaml contains a grpc dependency/override. If grpc is incompatible,"
    echo "either remove the override or update the package(s) that require grpc."
  fi
fi

echo
echo "Done."
