#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
mode="${1:-}"
case "$mode" in
  lint|unit|ui|package) ;;
  *) echo 'Usage: bash scripts/ci.sh {lint|unit|ui|package}' >&2; exit 2 ;;
esac

# CI pins DEVELOPER_DIR. Local runs intentionally use the selected Xcode instead.
xcodebuild -version
xcrun swift --version
sw_vers
if ! xcodebuild -version | awk 'NR == 1 { split($2, v, "."); exit !(v[1] >= 26) }'; then
  echo 'InkEdit CI requires Xcode 26 or newer.' >&2
  exit 1
fi

if [[ "$mode" == lint ]]; then
  bash -n scripts/ci.sh
  xcrun swift-format lint --strict --recursive InkEdit InkEditTests InkEditUITests
  exit 0
fi

output="${CI_OUTPUT_DIR:-$PWD/build/ci}"
mkdir -p "$output/reports" "$output/artifacts"
derived="$output/DerivedData-$mode"
common=(
  -project InkEdit.xcodeproj -scheme InkEdit
  -derivedDataPath "$derived"
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
  CODE_SIGNING_ALLOWED=YES SWIFT_EMIT_LOC_STRINGS=NO
)

if [[ "$mode" == unit || "$mode" == ui ]]; then
  target=InkEditTests
  if [[ "$mode" == ui ]]; then target=InkEditUITests; fi
  result="$output/reports/$mode.xcresult"
  # Never delete a previous report or reuse its path silently.
  if [[ -e "$result" ]]; then
    echo "Report already exists: $result. Choose a fresh CI_OUTPUT_DIR." >&2
    exit 1
  fi
  status=0
  xcodebuild test "${common[@]}" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -only-testing:"$target" -parallel-testing-enabled NO \
    -enableCodeCoverage YES -resultBundlePath "$result" \
    | tee "$output/reports/$mode.log" || status=$?
  if [[ -d "$result" ]]; then
    xcrun xcresulttool get test-results summary --path "$result" --compact \
      > "$output/reports/$mode-summary.json" || echo 'Could not summarize xcresult; raw bundle is retained.' >&2
  fi
  exit "$status"
fi

xcodebuild build "${common[@]}" -configuration Release \
  -destination 'generic/platform=macOS' 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  | tee "$output/reports/package.log"

app="$derived/Build/Products/Release/InkEdit.app"
for architecture in arm64 x86_64; do
  xcrun lipo "$app/Contents/MacOS/InkEdit" -verify_arch "$architecture"
done
codesign --verify --deep --strict "$app"
revision="$(git rev-parse --short=12 HEAD)"
archive="InkEdit-internal-$revision-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/artifacts/$archive"
(
  cd "$output/artifacts"
  shasum -a 256 "$archive" > "$archive.sha256"
)
cp docs/INTERNAL_BUILD.md "$output/artifacts/README.md"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '### Internal test build\n\n- Commit: `%s`\n- Architectures: arm64 + x86_64\n- Ad-hoc signed; **not notarized or publicly released**.\n- Download the ZIP, checksum and README from this run’s artifacts.\n' \
    "$revision" >> "$GITHUB_STEP_SUMMARY"
fi
