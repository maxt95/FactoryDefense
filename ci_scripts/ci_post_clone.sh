#!/usr/bin/env bash
set -euo pipefail

echo "=== ci_post_clone.sh ==="
echo "Installing XcodeGen..."

brew install xcodegen

echo "Generating Xcode project..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

# Set build number from Xcode Cloud CI_BUILD_NUMBER
if [ -n "${CI_BUILD_NUMBER:-}" ]; then
    echo "Setting CURRENT_PROJECT_VERSION to $CI_BUILD_NUMBER"
    cd "$CI_PRIMARY_REPOSITORY_PATH"
    agvtool new-version -all "$CI_BUILD_NUMBER"
fi

echo "=== Project generated successfully ==="
