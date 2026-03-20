#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MeasureMe.xcodeproj"
SCHEME_NAME="MeasureMe Release Validation"
TEST_PLAN_NAME="MeasureMe Release Validation"
DEBUG_DEVICE_CONFIGURATION="Debug-Device"
DEBUG_CHECKERS_CONFIGURATION="Debug-Checkers"
DEFAULT_SESSION_ROOT="$ROOT_DIR/build/release-validation"
DERIVED_DATA_PATH="$ROOT_DIR/build/release-validation-derived-data"

usage() {
  cat <<'EOF'
Usage:
  scripts/release_validation.sh start-session [label]
  scripts/release_validation.sh list-destinations
  scripts/release_validation.sh list-devices
  scripts/release_validation.sh show-test-plans
  scripts/release_validation.sh analyze [result-dir]
  scripts/release_validation.sh sim-regression [destination] [result-dir]
  scripts/release_validation.sh device-ui [destination] [result-dir] [repeat-count]
  scripts/release_validation.sh checkers-sim [destination] [result-dir]
  scripts/release_validation.sh archive-rc [result-dir]
  scripts/release_validation.sh profile-guide [device-name-or-id]

Notes:
  - When result-dir is omitted, a timestamped session folder is created under build/release-validation/.
  - sim-regression and device-ui pin the test plan to the Debug-Device configuration.
  - device-ui runs the critical UI suites called out by the release validation plan.
  - checkers-sim pins the Debug-Checkers configuration and adds Address Sanitizer and Undefined Behavior Sanitizer. Run Main Thread Checker from Xcode.
EOF
}

ensure_dependencies() {
  command -v xcodebuild >/dev/null
  command -v xcrun >/dev/null
}

timestamp() {
  date +"%Y%m%d-%H%M%S"
}

session_dir() {
  local label="${1:-session}"
  printf "%s/%s-%s" "$DEFAULT_SESSION_ROOT" "$(timestamp)" "$label"
}

prepare_result_dir() {
  local dir="$1"
  mkdir -p "$dir"
  mkdir -p "$DERIVED_DATA_PATH"
}

copy_summary_template() {
  local dir="$1"
  if [[ -f "$ROOT_DIR/docs/release-validation-template.md" && ! -f "$dir/summary.md" ]]; then
    cp "$ROOT_DIR/docs/release-validation-template.md" "$dir/summary.md"
  fi
}

resolve_simulator_destination() {
  python3 - "$PROJECT_PATH" "$SCHEME_NAME" <<'PY'
import re
import subprocess
import sys

project, scheme = sys.argv[1:]
out = subprocess.check_output(
    ["xcodebuild", "-project", project, "-scheme", scheme, "-showdestinations"],
    text=True,
    stderr=subprocess.STDOUT,
)
candidates = []
for line in out.splitlines():
    match = re.search(r"\{([^}]*)\}", line)
    if not match:
        continue
    raw = match.group(1)
    if "platform:iOS Simulator" not in raw:
        continue
    normalized = raw.replace(", ", ",")
    fields = {}
    for part in normalized.split(","):
        if ":" not in part:
            continue
        key, value = part.split(":", 1)
        fields[key.strip()] = value.strip()
    os_version = fields.get("OS", "")
    try:
        order = tuple(int(chunk) for chunk in os_version.split("."))
    except ValueError:
        order = (0,)
    candidates.append((order, normalized))
if not candidates:
    raise SystemExit("No iOS Simulator destinations found.")
print(max(candidates)[1])
PY
}

write_note() {
  local file="$1"
  local message="$2"
  printf "%s\n" "$message" >> "$file"
}

run_xcodebuild() {
  local log_file="$1"
  shift
  "$@" 2>&1 | tee "$log_file"
}

critical_ui_filters=(
  "-only-testing:MeasureMeUITests/MeasureMeUITests"
  "-only-testing:MeasureMeUITests/OnboardingUITests"
  "-only-testing:MeasureMeUITests/SettingsViewUITests"
  "-only-testing:MeasureMeUITests/QuickAddUITests"
  "-only-testing:MeasureMeUITests/PhotoFlowUITests"
  "-only-testing:MeasureMeUITests/MultiPhotoImportUITests"
  "-only-testing:MeasureMeUITests/PerformanceUITests"
)

main() {
  ensure_dependencies

  local command="${1:-}"
  shift || true

  case "$command" in
    start-session)
      local label="${1:-release-validation}"
      local dir
      dir="$(session_dir "$label")"
      prepare_result_dir "$dir"
      copy_summary_template "$dir"
      printf "%s\n" "$dir"
      ;;

    list-destinations)
      xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME_NAME" -showdestinations
      ;;

    list-devices)
      xcrun xctrace list devices
      ;;

    show-test-plans)
      xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME_NAME" -showTestPlans
      ;;

    analyze)
      local dir="${1:-$(session_dir analyze)}"
      prepare_result_dir "$dir"
      copy_summary_template "$dir"
      local log_file="$dir/analyze.log"
      run_xcodebuild "$log_file" \
        xcodebuild \
          -project "$PROJECT_PATH" \
          -scheme "$SCHEME_NAME" \
          -configuration Debug \
          -destination "generic/platform=iOS Simulator" \
          -derivedDataPath "$DERIVED_DATA_PATH" \
          -resultBundlePath "$dir/analyze.xcresult" \
          analyze
      ;;

    sim-regression)
      local destination="${1:-}"
      local dir="${2:-}"
      if [[ -z "$destination" ]]; then
        destination="$(resolve_simulator_destination)"
      fi
      if [[ -z "$dir" ]]; then
        dir="$(session_dir sim-regression)"
      fi
      prepare_result_dir "$dir"
      copy_summary_template "$dir"
      local log_file="$dir/sim-regression.log"
      run_xcodebuild "$log_file" \
        xcodebuild \
          -project "$PROJECT_PATH" \
          -scheme "$SCHEME_NAME" \
          -testPlan "$TEST_PLAN_NAME" \
          -only-test-configuration "$DEBUG_DEVICE_CONFIGURATION" \
          -configuration Debug \
          -destination "$destination" \
          -derivedDataPath "$DERIVED_DATA_PATH" \
          -resultBundlePath "$dir/sim-regression.xcresult" \
          CODE_SIGNING_ALLOWED=NO \
          test
      ;;

    device-ui)
      local destination="${1:-}"
      local dir="${2:-}"
      local repeat_count="${3:-1}"
      if [[ -z "$destination" ]]; then
        echo "device-ui requires an explicit destination, for example: 'platform=iOS,id=<device-id>'" >&2
        exit 1
      fi
      if [[ -z "$dir" ]]; then
        dir="$(session_dir device-ui)"
      fi
      prepare_result_dir "$dir"
      copy_summary_template "$dir"
      local loop_index
      for ((loop_index=1; loop_index<=repeat_count; loop_index++)); do
        local run_dir="$dir/run-$loop_index"
        mkdir -p "$run_dir"
        local log_file="$run_dir/device-ui.log"
        run_xcodebuild "$log_file" \
          xcodebuild \
            -project "$PROJECT_PATH" \
            -scheme "$SCHEME_NAME" \
            -testPlan "$TEST_PLAN_NAME" \
            -only-test-configuration "$DEBUG_DEVICE_CONFIGURATION" \
            -configuration Debug \
            -destination "$destination" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            -resultBundlePath "$run_dir/device-ui.xcresult" \
            "${critical_ui_filters[@]}" \
            test
      done
      ;;

    checkers-sim)
      local destination="${1:-}"
      local dir="${2:-}"
      if [[ -z "$destination" ]]; then
        destination="$(resolve_simulator_destination)"
      fi
      if [[ -z "$dir" ]]; then
        dir="$(session_dir checkers-sim)"
      fi
      prepare_result_dir "$dir"
      copy_summary_template "$dir"
      local log_file="$dir/checkers-sim.log"
      run_xcodebuild "$log_file" \
        xcodebuild \
          -project "$PROJECT_PATH" \
          -scheme "$SCHEME_NAME" \
          -testPlan "$TEST_PLAN_NAME" \
          -only-test-configuration "$DEBUG_CHECKERS_CONFIGURATION" \
          -configuration Debug \
          -destination "$destination" \
          -derivedDataPath "$DERIVED_DATA_PATH" \
          -resultBundlePath "$dir/checkers-sim.xcresult" \
          -enableAddressSanitizer YES \
          -enableUndefinedBehaviorSanitizer YES \
          CODE_SIGNING_ALLOWED=NO \
          test
      write_note "$dir/checkers-sim.log" "Main Thread Checker still needs an Xcode GUI run because xcodebuild does not expose a dedicated flag for it."
      ;;

    archive-rc)
      local dir="${1:-$(session_dir archive-rc)}"
      prepare_result_dir "$dir"
      copy_summary_template "$dir"
      local log_file="$dir/archive.log"
      run_xcodebuild "$log_file" \
        xcodebuild \
          -project "$PROJECT_PATH" \
          -scheme "$SCHEME_NAME" \
          -configuration Release \
          -destination "generic/platform=iOS" \
          -derivedDataPath "$DERIVED_DATA_PATH" \
          -archivePath "$dir/MeasureMe.xcarchive" \
          archive
      ;;

    profile-guide)
      local device_ref="${1:-connected-device}"
      cat <<EOF
Release profiling build:
  xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME_NAME" -configuration Release -destination "generic/platform=iOS" build

Instruments templates to run on $device_ref:
  xcrun xctrace record --template "Time Profiler" --device "$device_ref" --launch -- "$ROOT_DIR/build/Release-iphoneos/MeasureMe.app"
  xcrun xctrace record --template "Leaks" --device "$device_ref" --launch -- "$ROOT_DIR/build/Release-iphoneos/MeasureMe.app"
  xcrun xctrace record --template "Allocations" --device "$device_ref" --launch -- "$ROOT_DIR/build/Release-iphoneos/MeasureMe.app"
  xcrun xctrace record --template "Energy Log" --device "$device_ref" --launch -- "$ROOT_DIR/build/Release-iphoneos/MeasureMe.app"
  xcrun xctrace record --template "Network" --device "$device_ref" --launch -- "$ROOT_DIR/build/Release-iphoneos/MeasureMe.app"
  xcrun xctrace record --template "File Activity" --device "$device_ref" --launch -- "$ROOT_DIR/build/Release-iphoneos/MeasureMe.app"

Use Product > Profile in Xcode when you want a signed launch straight from the scheme.
EOF
      ;;

    ""|-h|--help|help)
      usage
      ;;

    *)
      echo "Unknown command: $command" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
