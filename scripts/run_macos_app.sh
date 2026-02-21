#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/run_macos_app.sh [options] [-- <extra xcodebuild args>]

Builds and launches the macOS app from the current worktree root.

Options:
  --no-clean                 Skip "clean" and run only "build"
  --no-open                  Build only; do not launch app
  --configuration <name>     Xcode configuration (default: Debug)
  --scheme <name>            Xcode scheme (default: FactoryDefense_macOS)
  --destination <value>      xcodebuild destination (default: platform=macOS)
  --derived-data-path <path> DerivedData path (default: <repo>/.derivedData)
  -h, --help                 Show this help
EOF
}

SCHEME="FactoryDefense_macOS"
CONFIGURATION="Debug"
DESTINATION="platform=macOS"
DERIVED_DATA_PATH=""
CLEAN_BUILD=1
OPEN_APP=1
XCODEBUILD_EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-clean)
      CLEAN_BUILD=0
      shift
      ;;
    --no-open)
      OPEN_APP=0
      shift
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --scheme)
      SCHEME="$2"
      shift 2
      ;;
    --destination)
      DESTINATION="$2"
      shift 2
      ;;
    --derived-data-path)
      DERIVED_DATA_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      XCODEBUILD_EXTRA_ARGS+=("$@")
      break
      ;;
    *)
      XCODEBUILD_EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if command -v git >/dev/null 2>&1 && git -C "${REPO_ROOT}" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "${REPO_ROOT}" rev-parse --show-toplevel)"
fi

if [[ -z "${DERIVED_DATA_PATH}" ]]; then
  DERIVED_DATA_PATH="${REPO_ROOT}/.derivedData"
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is not available." >&2
  exit 1
fi

cd "${REPO_ROOT}"

XCODEPROJ="${REPO_ROOT}/FactoryDefense.xcodeproj"
if [[ ! -d "${XCODEPROJ}" ]]; then
  echo "[run_macos_app] xcodeproj not found — generating..."
  "${REPO_ROOT}/scripts/generate_xcode_project.sh"
fi

# Resolve the actual PRODUCT_NAME from the build settings so the app path
# and process-kill logic use the right name regardless of project.yml changes.
PRODUCT_NAME=$(xcodebuild -project "${XCODEPROJ}" \
  -scheme "${SCHEME}" -configuration "${CONFIGURATION}" \
  -showBuildSettings 2>/dev/null \
  | sed -n 's/^ *PRODUCT_NAME = //p')
if [[ -z "${PRODUCT_NAME}" ]]; then
  echo "warning: could not resolve PRODUCT_NAME; falling back to scheme name" >&2
  PRODUCT_NAME="${SCHEME}"
fi

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${PRODUCT_NAME}.app"

echo "[run_macos_app] repo root: ${REPO_ROOT}"
echo "[run_macos_app] derived data: ${DERIVED_DATA_PATH}"
echo "[run_macos_app] product name: ${PRODUCT_NAME}"

# Prevent macOS "open" from reusing an old app process.
if pgrep -x "${PRODUCT_NAME}" >/dev/null 2>&1; then
  echo "[run_macos_app] stopping existing ${PRODUCT_NAME} process"
  pkill -x "${PRODUCT_NAME}" || true
  sleep 0.2
fi

BUILD_ACTIONS=("build")
if [[ ${CLEAN_BUILD} -eq 1 ]]; then
  BUILD_ACTIONS=("clean" "build")
fi

xcodebuild_cmd=(
  xcodebuild
  -project "${XCODEPROJ}"
  -scheme "${SCHEME}"
  -destination "${DESTINATION}"
  -configuration "${CONFIGURATION}"
  -derivedDataPath "${DERIVED_DATA_PATH}"
)
xcodebuild_cmd+=("${BUILD_ACTIONS[@]}")
if [[ ${#XCODEBUILD_EXTRA_ARGS[@]} -gt 0 ]]; then
  xcodebuild_cmd+=("${XCODEBUILD_EXTRA_ARGS[@]}")
fi
"${xcodebuild_cmd[@]}"

if [[ ${OPEN_APP} -eq 0 ]]; then
  echo "[run_macos_app] build complete (--no-open)"
  exit 0
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: app not found at ${APP_PATH}" >&2
  exit 1
fi

open -n "${APP_PATH}"
echo "[run_macos_app] launched ${APP_PATH}"
