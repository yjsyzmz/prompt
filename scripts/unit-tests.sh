#!/usr/bin/env bash
set -euo pipefail

if [[ -f Package.swift ]]; then
  swift test
  exit 0
fi

container="$(find . -maxdepth 3 \( -name '*.xcworkspace' -o -name '*.xcodeproj' \) -print | head -1)"
if [[ -z "$container" ]]; then
  echo "No application project exists yet; collaboration bootstrap unit-test check passed."
  exit 0
fi

if [[ ! -f .ci/xcode.env ]]; then
  echo "An Xcode project exists but .ci/xcode.env is missing." >&2
  exit 1
fi

# shellcheck disable=SC1091
source .ci/xcode.env
: "${XCODE_SCHEME:?XCODE_SCHEME must be set in .ci/xcode.env}"

if [[ "$container" == *.xcworkspace ]]; then
  xcodebuild -workspace "$container" -scheme "$XCODE_SCHEME" -destination 'platform=macOS' test
else
  xcodebuild -project "$container" -scheme "$XCODE_SCHEME" -destination 'platform=macOS' test
fi
