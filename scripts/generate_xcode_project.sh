#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if command -v xcodegen >/dev/null 2>&1; then
  XCODEGEN_BIN="$(command -v xcodegen)"
elif [[ -x "./tools/xcodegen" ]]; then
  XCODEGEN_BIN="./tools/xcodegen"
else
  echo "error: xcodegen is required but not installed."
  echo "Install via Homebrew: brew install xcodegen"
  echo "Or place the binary at ./tools/xcodegen."
  exit 1
fi

"${XCODEGEN_BIN}" generate

echo "Generated FactoryDefense.xcodeproj"

# Validate expected targets exist in the generated project
EXPECTED_TARGETS=("FactoryDefense_iOS" "FactoryDefense_macOS")
for target in "${EXPECTED_TARGETS[@]}"; do
  if ! grep -q "\"${target}\"" FactoryDefense.xcodeproj/project.pbxproj; then
    echo "warning: Expected target '${target}' not found in generated project."
    exit 1
  fi
done

echo "Validated targets: ${EXPECTED_TARGETS[*]}"
