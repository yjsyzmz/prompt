#!/usr/bin/env bash
set -euo pipefail

repository_root="${1:-.}"

fail() {
  echo "Project structure check failed: $*" >&2
  exit 1
}

setting_value() {
  local settings="$1"
  local key="$2"
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$settings" | tail -1
}

require_setting() {
  local settings="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(setting_value "$settings" "$key")"
  [[ "$actual" == "$expected" ]] || fail "$key must be '$expected' (found '${actual:-unset}')."
}

cd "$repository_root"

projects=()
while IFS= read -r project; do
  projects+=("$project")
done < <(
  find . -maxdepth 3 -type d -name '*.xcodeproj' \
    -not -path './.worktrees/*' -print | LC_ALL=C sort
)

[[ "${#projects[@]}" -gt 0 ]] || fail "no Xcode project found; T-003 has not created the project yet."
[[ "${#projects[@]}" -eq 1 ]] || fail "exactly one Xcode project is allowed (found ${#projects[@]})."

if find . -maxdepth 3 -type d -name '*.xcworkspace' \
  -not -path './.worktrees/*' -not -path '*.xcodeproj/*' -print -quit | grep -q .; then
  fail "standalone Xcode workspaces are outside the approved scope."
fi

[[ ! -e Package.swift ]] || fail "Swift Package Manager is outside the approved project structure."
[[ -f .ci/xcode.env ]] || fail ".ci/xcode.env must declare the approved project and target roles."

# shellcheck disable=SC1091
source .ci/xcode.env
: "${XCODE_PROJECT:?XCODE_PROJECT must be set in .ci/xcode.env}"
: "${APP_TARGET:?APP_TARGET must be set in .ci/xcode.env}"
: "${UNIT_TEST_TARGET:?UNIT_TEST_TARGET must be set in .ci/xcode.env}"
: "${SYNTHETIC_AX_HOST_TARGET:?SYNTHETIC_AX_HOST_TARGET must be set in .ci/xcode.env}"

[[ "$XCODE_PROJECT" == "${projects[0]#./}" ]] || \
  fail "XCODE_PROJECT must name the repository's only Xcode project."

required_targets=("$APP_TARGET" "$UNIT_TEST_TARGET" "$SYNTHETIC_AX_HOST_TARGET")
[[ "$APP_TARGET" != "$UNIT_TEST_TARGET" && \
   "$APP_TARGET" != "$SYNTHETIC_AX_HOST_TARGET" && \
   "$UNIT_TEST_TARGET" != "$SYNTHETIC_AX_HOST_TARGET" ]] || \
  fail "application, unit-test, and synthetic AX host targets must be distinct."

list_output="$(mktemp)"
settings_dir="$(mktemp -d)"
trap 'rm -f "$list_output"; rm -rf "$settings_dir"' EXIT

xcodebuild -project "$XCODE_PROJECT" -list >"$list_output"

actual_targets="$(
  awk '
    /^[[:space:]]*Targets:/ { in_targets = 1; next }
    /^[[:space:]]*(Build Configurations|Schemes):/ { in_targets = 0 }
    in_targets && NF {
      sub(/^[[:space:]]+/, "")
      sub(/[[:space:]]+$/, "")
      print
    }
  ' "$list_output" | LC_ALL=C sort
)"
expected_targets="$(printf '%s\n' "${required_targets[@]}" | LC_ALL=C sort)"
[[ "$actual_targets" == "$expected_targets" ]] || \
  fail "target set must contain only the application, unit-test, and synthetic AX host roles."

for target in "${required_targets[@]}"; do
  settings="$settings_dir/$target.txt"
  xcodebuild -project "$XCODE_PROJECT" -target "$target" -configuration Debug \
    -showBuildSettings >"$settings"

  deployment_target="$(setting_value "$settings" MACOSX_DEPLOYMENT_TARGET)"
  [[ -n "$deployment_target" ]] || fail "$target has no macOS deployment target."
  awk -v version="$deployment_target" 'BEGIN { exit !(version + 0 >= 14.0) }' || \
    fail "$target must deploy to macOS 14.0 or later (found $deployment_target)."

  swift_version="$(setting_value "$settings" SWIFT_VERSION)"
  [[ "$swift_version" == 6 || "$swift_version" == 6.* ]] || \
    fail "$target must use Swift 6 language mode (found '${swift_version:-unset}')."

  architectures="$(setting_value "$settings" ARCHS)"
  [[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || \
    fail "$target must build arm64 and x86_64 (found '${architectures:-unset}')."
  require_setting "$settings" ONLY_ACTIVE_ARCH NO
  require_setting "$settings" ENABLE_APP_SANDBOX NO
done

require_setting "$settings_dir/$APP_TARGET.txt" PRODUCT_TYPE com.apple.product-type.application
require_setting "$settings_dir/$UNIT_TEST_TARGET.txt" PRODUCT_TYPE com.apple.product-type.bundle.unit-test
require_setting "$settings_dir/$SYNTHETIC_AX_HOST_TARGET.txt" PRODUCT_TYPE com.apple.product-type.application

while IFS= read -r entitlements; do
  if /usr/bin/plutil -p "$entitlements" | grep -Eq \
    'com\.apple\.security\.(app-sandbox|network\.client|network\.server)'; then
    fail "sandbox or network entitlement found in $entitlements."
  fi
done < <(find . -type f -name '*.entitlements' -not -path './.worktrees/*' -print)

if find . -maxdepth 4 \
  \( -name Package.resolved -o -name Podfile -o -name Cartfile \
     -o -name '*.xcframework' -o -name '*.framework' \) \
  -not -path './.worktrees/*' -print -quit | grep -q .; then
  fail "third-party runtime dependency artifact found."
fi

project_file="$XCODE_PROJECT/project.pbxproj"
[[ -f "$project_file" ]] || fail "$XCODE_PROJECT has no project.pbxproj."
if grep -Eq 'XCRemoteSwiftPackageReference|packageProductDependencies|Carthage|Pods/' "$project_file"; then
  fail "third-party runtime dependency reference found in project.pbxproj."
fi

echo "Project structure check passed."
