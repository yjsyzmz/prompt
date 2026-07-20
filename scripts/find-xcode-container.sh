#!/usr/bin/env bash
set -euo pipefail

find_container() {
  local search_root="$1"
  local pattern
  local candidate

  for pattern in '*.xcworkspace' '*.xcodeproj'; do
    while IFS= read -r candidate; do
      printf '%s\n' "$candidate"
      return 0
    done < <(
      find "$search_root" -maxdepth 3 -type d -name "$pattern" \
        -not -path "$search_root/.worktrees/*" \
        -not -path '*.xcodeproj/*' \
        -print | LC_ALL=C sort
    )
  done
}

run_self_test() {
  local worktree_root
  local internal_root
  local workspace_root
  local project_root
  local actual

  xcode_test_root="$(mktemp -d)"
  trap 'rm -rf "$xcode_test_root"' EXIT
  worktree_root="$xcode_test_root/worktree"
  internal_root="$xcode_test_root/internal"
  workspace_root="$xcode_test_root/workspace"
  project_root="$xcode_test_root/project"

  mkdir -p \
    "$worktree_root/.worktrees/solar/Ignored.xcodeproj" \
    "$internal_root/App.xcodeproj/project.xcworkspace" \
    "$workspace_root/Zeta.xcodeproj" \
    "$workspace_root/Alpha.xcworkspace" \
    "$project_root/Zeta.xcodeproj" \
    "$project_root/Beta.xcodeproj"

  actual="$(find_container "$worktree_root")"
  if [[ -n "$actual" ]]; then
    echo "Xcode container self-test failed: worktree container selected: $actual" >&2
    exit 1
  fi

  actual="$(find_container "$internal_root")"
  if [[ "$actual" != "$internal_root/App.xcodeproj" ]]; then
    echo "Xcode container self-test failed: internal workspace selected instead of project." >&2
    exit 1
  fi

  actual="$(find_container "$workspace_root")"
  if [[ "$actual" != "$workspace_root/Alpha.xcworkspace" ]]; then
    echo "Xcode container self-test failed: workspace preference is not deterministic." >&2
    exit 1
  fi

  actual="$(find_container "$project_root")"
  if [[ "$actual" != "$project_root/Beta.xcodeproj" ]]; then
    echo "Xcode container self-test failed: project ordering is not deterministic." >&2
    exit 1
  fi

  echo "Xcode container discovery self-test passed."
}

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit 0
fi

find_container "${1:-.}"
