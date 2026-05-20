#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FractalForge"
SCHEME="FractalForge"
PROJECT="FractalForge.xcodeproj"
CONFIGURATION="${CONFIGURATION:-Release}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/build/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/package}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_NAME="${ARCHIVE_NAME:-$APP_NAME-$TIMESTAMP}"

APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
ZIP_PATH="$OUTPUT_DIR/$ARCHIVE_NAME.zip"

usage() {
  cat >&2 <<EOF
usage: $0

Environment overrides:
  CONFIGURATION=Release
  DERIVED_DATA=$DERIVED_DATA
  OUTPUT_DIR=$OUTPUT_DIR
  ARCHIVE_NAME=$ARCHIVE_NAME
EOF
}

stop_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_release() {
  xcodebuild \
    -project "$ROOT_DIR/$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    build
}

package_app() {
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "error: app bundle not found: $APP_BUNDLE" >&2
    exit 1
  fi

  mkdir -p "$OUTPUT_DIR"
  rm -f "$ZIP_PATH"

  /usr/bin/ditto \
    -c \
    -k \
    --sequesterRsrc \
    --keepParent \
    "$APP_BUNDLE" \
    "$ZIP_PATH"

  echo "Packaged: $ZIP_PATH"
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    stop_app
    build_release
    package_app
    stop_app
    ;;
  *)
    usage
    exit 2
    ;;
esac
