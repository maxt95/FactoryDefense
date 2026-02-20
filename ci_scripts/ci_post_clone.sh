#!/usr/bin/env bash
set -euo pipefail

echo "=== ci_post_clone.sh ==="
echo "Installing XcodeGen..."

brew install xcodegen

echo "Generating Xcode project..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "=== Project generated successfully ==="
