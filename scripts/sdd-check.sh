#!/usr/bin/env bash
set -euo pipefail

validate_feature_spec() {
  local spec="$1"
  local feature_dir
  local stage
  feature_dir="$(dirname "$spec")"
  stage="$(sed -n 's/^stage:[[:space:]]*//p' "$spec" | head -1 | tr -d '\"')"

  if [[ -z "$stage" ]]; then
    echo "Missing stage in $spec" >&2
    return 1
  fi

  if grep -nE 'TODO|TBD|\{\{' "$feature_dir"/*.md; then
    echo "Unresolved placeholder found in $feature_dir" >&2
    return 1
  fi

  if ! grep -qE 'FR-[0-9]{3}' "$spec"; then
    echo "No functional requirement ID found in $spec" >&2
    return 1
  fi

  if ! grep -qE 'AC-[0-9]{3}' "$spec"; then
    echo "No acceptance scenario ID found in $spec" >&2
    return 1
  fi

  case "$stage" in
    spec) ;;
    plan)
      [[ -f "$feature_dir/plan.md" && -f "$feature_dir/research.md" ]] || {
        echo "Plan stage requires plan.md and research.md in $feature_dir" >&2
        return 1
      }
      grep -q 'Constitution Check' "$feature_dir/plan.md" || {
        echo "plan.md must include a Constitution Check" >&2
        return 1
      }
      ;;
    tasks|implementation)
      [[ -f "$feature_dir/plan.md" && -f "$feature_dir/research.md" && -f "$feature_dir/tasks.md" ]] || {
        echo "$stage stage requires plan.md, research.md, and tasks.md in $feature_dir" >&2
        return 1
      }
      grep -q 'Constitution Check' "$feature_dir/plan.md" || {
        echo "plan.md must include a Constitution Check" >&2
        return 1
      }
      ;;
    *)
      echo "Unsupported stage '$stage' in $spec" >&2
      return 1
      ;;
  esac

  if [[ -f "$feature_dir/tasks.md" ]]; then
    while IFS= read -r requirement; do
      grep -q "$requirement" "$feature_dir/tasks.md" || {
        echo "Requirement $requirement is not referenced by tasks in $feature_dir" >&2
        return 1
      }
    done < <(grep -oE 'FR-[0-9]{3}' "$spec" | sort -u)
  fi
}

validate_repository() {
  local required_files=(
    "AGENTS.md"
    ".specify/memory/constitution.md"
    ".specify/templates/spec-template.md"
    ".specify/templates/plan-template.md"
    ".specify/templates/research-template.md"
    ".specify/templates/tasks-template.md"
    ".github/pull_request_template.md"
    "docs/superpowers/specs/2026-07-17--design.md"
  )
  local file
  local spec

  for file in "${required_files[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "Missing required SDD artifact: $file" >&2
      return 1
    fi
  done

  while IFS= read -r spec; do
    validate_feature_spec "$spec"
  done < <(find specs -mindepth 2 -maxdepth 2 -name spec.md -print 2>/dev/null | sort)
}

run_self_test() {
  local feature_dir
  local spec
  sdd_test_root="$(mktemp -d)"
  trap 'rm -rf "$sdd_test_root"' EXIT
  feature_dir="$sdd_test_root/specs/001-self-test"
  spec="$feature_dir/spec.md"
  mkdir -p "$feature_dir"

  printf '%s\n' \
    '---' \
    'stage: implementation' \
    '---' \
    '# Self-test specification' \
    '- FR-001: Validate the gate.' \
    '- AC-001: Missing downstream artifacts are rejected.' > "$spec"

  if validate_feature_spec "$spec" >/dev/null 2>&1; then
    echo "SDD self-test failed: implementation stage passed without plan, research, and tasks." >&2
    exit 1
  fi

  printf '%s\n' '# Plan' '## Constitution Check' 'Pass.' > "$feature_dir/plan.md"
  printf '%s\n' '# Research' 'No open questions.' > "$feature_dir/research.md"
  printf '%s\n' '# Tasks' '- T-001 covers AC-001 only.' > "$feature_dir/tasks.md"

  if validate_feature_spec "$spec" >/dev/null 2>&1; then
    echo "SDD self-test failed: requirement traceability gap was accepted." >&2
    exit 1
  fi

  printf '%s\n' '# Tasks' '- T-001 covers FR-001 and AC-001.' > "$feature_dir/tasks.md"
  validate_feature_spec "$spec" >/dev/null
  echo "SDD gate self-test passed."
}

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit 0
fi

validate_repository

echo "SDD artifact validation passed."
