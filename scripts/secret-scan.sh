#!/usr/bin/env bash
set -euo pipefail

pattern='(sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)'

scan_file() {
  local file="$1"
  if grep -nE "$pattern" "$file"; then
    echo "Potential credential detected in $file" >&2
    return 1
  fi
}

if [[ "${1:-}" == "--self-test" ]]; then
  temp_file="$(mktemp)"
  trap 'rm -f "$temp_file"' EXIT
  printf '%s\n' 'sk-'"$(printf 'a%.0s' {1..24})" > "$temp_file"
  if scan_file "$temp_file" >/dev/null 2>&1; then
    echo "Secret scanner self-test failed: fixture was not detected." >&2
    exit 1
  fi
  echo "Secret scanner self-test passed."
  exit 0
fi

failed=0
while IFS= read -r -d '' file; do
  if [[ -f "$file" ]] && ! scan_file "$file"; then
    failed=1
  fi
done < <(git ls-files -z --cached --others --exclude-standard)

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "No credential patterns detected in repository files."
