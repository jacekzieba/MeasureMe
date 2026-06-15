#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MeasureMe.xcodeproj"
SCHEME_NAME="MeasureMe"
PACKAGE_CACHE_PATH="${PACKAGE_CACHE_PATH:-$HOME/Library/Caches/org.swift.swiftpm}"
SMALL_IPHONE_NAME="${SMALL_IPHONE_NAME:-iPhone 17e}"
IPAD_NAME="${IPAD_NAME:-iPad mini (A17 Pro)}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
OUTPUT_ROOT="${ACCESSIBILITY_OUTPUT_ROOT:-/tmp/MeasureMe-accessibility-matrix-$RUN_ID}"
DERIVED_DATA_PATH="$OUTPUT_ROOT/derived-data"

run_layout_test() {
  local device_name="$1"
  local slug
  slug="$(printf "%s" "$device_name" | tr ' /()' '----')"
  local result_bundle="$OUTPUT_ROOT/$slug.xcresult"

  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,name=$device_name,OS=latest" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -packageCachePath "$PACKAGE_CACHE_PATH" \
    -resultBundlePath "$result_bundle" \
    -only-testing:MeasureMeUITests/AccessibilityQualityUITests/testAdaptiveLayoutKeepsCoreContentInsideTheWindow \
    COMPILER_INDEX_STORE_ENABLE=NO \
    ONLY_ACTIVE_ARCH=YES \
    SYMROOT="$DERIVED_DATA_PATH/Build/Products" \
    OBJROOT="$DERIVED_DATA_PATH/Build/Intermediates.noindex" \
    test
}

mkdir -p "$DERIVED_DATA_PATH"
run_layout_test "$SMALL_IPHONE_NAME"
run_layout_test "$IPAD_NAME"

printf "Accessibility device matrix passed. Results: %s\n" "$OUTPUT_ROOT"
