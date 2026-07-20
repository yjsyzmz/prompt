#!/usr/bin/env bash
set -euo pipefail

required_files=(
  "AGENTS.md"
  ".specify/memory/constitution.md"
  ".specify/templates/spec-template.md"
  ".specify/templates/plan-template.md"
  ".specify/templates/research-template.md"
  ".specify/templates/tasks-template.md"
  ".github/pull_request_template.md"
  "docs/superpowers/specs/2026-07-17--design.md"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required SDD artifact: $file" >&2
    exit 1
  fi
done

while IFS= read -r spec; do
  feature_dir="$(dirname "$spec")"
  stage="$(sed -n 's/^stage:[[:space:]]*//p' "$spec" | head -1 | tr -d '\"')"

  if [[ -z "$stage" ]]; then
    echo "Missing stage in $spec" >&2
    exit 1
  fi

  if grep -nE 'TODO|TBD|\{\{' "$feature_dir"/*.md; then
    echo "Unresolved placeholder found in $feature_dir" >&2
    exit 1
  fi

  if ! grep -qE 'FR-[0-9]{3}' "$spec"; then
    echo "No functional requirement ID found in $spec" >&2
    exit 1
  fi

  if ! grep -qE 'AC-[0-9]{3}' "$spec"; then
    echo "No acceptance scenario ID found in $spec" >&2
    exit 1
  fi

  case "$stage" in
    spec) ;;
    plan)
      [[ -f "$feature_dir/plan.md" && -f "$feature_dir/research.md" ]] || {
        echo "Plan stage requires plan.md and research.md in $feature_dir" >&2
        exit 1
      }
      grep -q 'Constitution Check' "$feature_dir/plan.md" || {
        echo "plan.md must include a Constitution Check" >&2
        exit 1
      }
      ;;
    tasks|implementation)
      [[ -f "$feature_dir/plan.md" && -f "$feature_dir/research.md" && -f "$feature_dir/tasks.md" ]] || {
        echo "$stage stage requires plan.md, research.md, and tasks.md in $feature_dir" >&2
        exit 1
      }
      grep -q 'Constitution Check' "$feature_dir/plan.md" || {
        echo "plan.md must include a Constitution Check" >&2
        exit 1
      }
      ;;
    *)
      echo "Unsupported stage '$stage' in $spec" >&2
      exit 1
      ;;
  esac

  if [[ -f "$feature_dir/tasks.md" ]]; then
    while IFS= read -r requirement; do
      grep -q "$requirement" "$feature_dir/tasks.md" || {
        echo "Requirement $requirement is not referenced by tasks in $feature_dir" >&2
        exit 1
      }
    done < <(grep -oE 'FR-[0-9]{3}' "$spec" | sort -u)
  fi
done < <(find specs -mindepth 2 -maxdepth 2 -name spec.md -print 2>/dev/null | sort)

echo "SDD artifact validation passed."
