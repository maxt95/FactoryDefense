#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if command -v xcodegen >/dev/null 2>&1; then
  XCODEGEN_BIN="$(command -v xcodegen)"
elif [[ -x "./tools/xcodegen" ]]; then
  XCODEGEN_BIN="./tools/xcodegen"
else
  echo "error: xcodegen is required but not installed."
  echo "Install via Homebrew or place the binary at ./tools/xcodegen."
  exit 1
fi

"${XCODEGEN_BIN}" generate

echo "Generated FactoryDefense.xcodeproj"
