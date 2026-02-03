#!/usr/bin/env bash
#
# PHOSPHENE signal tamper-hash utilities (v1)
#
# Goal:
# - Provide a lightweight integrity check that makes "hand edits" to signal JSON
#   detectable unless the official update step is run.
#
# Design:
# - Each signal JSON includes a required top-level field:
#     "tamper_hash": "sha256:<hex>"
# - The tamper hash is computed over the signal file bytes with the tamper_hash
#   value normalized to a fixed placeholder:
#     sha256:000...000 (64 hex chars)
# - If a file lacks tamper_hash, it is treated as-if it had been inserted as the
#   final JSON field (with the placeholder value) for the purpose of computing.
#
# This is not cryptographic authentication (no secrets); it is an integrity guardrail.
#
set -euo pipefail

fail() { echo "PHOSPHENE: $*" >&2; exit 2; }

TAMPER_PLACEHOLDER_HEX="0000000000000000000000000000000000000000000000000000000000000000"

hash_sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    # prints: "(stdin)= <hex>"
    openssl dgst -sha256 | awk '{print $2}'
    return 0
  fi
  fail "no SHA-256 tool found (need sha256sum, shasum, or openssl)"
}

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/phosphene-core/bin/signal_tamper_hash.sh compute <signal.json>
  ./phosphene/phosphene-core/bin/signal_tamper_hash.sh update  <signal.json>
  ./phosphene/phosphene-core/bin/signal_tamper_hash.sh validate <signal.json>
  ./phosphene/phosphene-core/bin/signal_tamper_hash.sh compute-line  <json_line>
  ./phosphene/phosphene-core/bin/signal_tamper_hash.sh validate-line <json_line>

Notes:
  - The tamper hash is computed over the file bytes with the tamper_hash value
    normalized to a fixed placeholder (all-zero hex).
  - update ensures the file contains tamper_hash and sets it to the correct value.
  - compute-line/validate-line operate on a single JSONL record (one JSON object per line).
EOF
}

require_file() {
  local f="$1"
  [[ -n "${f:-}" ]] || fail "missing file path"
  [[ -f "$f" ]] || fail "missing file: $f"
}

has_tamper_field() {
  local f="$1"
  grep -qE '"tamper_hash"[[:space:]]*:' "$f"
}

stream_with_inserted_tamper_field() {
  # If tamper_hash exists, stream the file as-is.
  # If missing, stream the file with a new final field inserted:
  #   ,"tamper_hash": "sha256:000..0"
  local f="$1"
  if has_tamper_field "$f"; then
    cat "$f"
    return 0
  fi

  awk -v ph="$TAMPER_PLACEHOLDER_HEX" '
    function rtrim(s){ sub(/[[:space:]]+$/, "", s); return s }
    { lines[NR] = $0 }
    END{
      if (NR <= 0) { exit 2 }
      # Find last non-empty line.
      n = NR
      while (n > 0 && rtrim(lines[n]) == "") n--
      if (n <= 0) { exit 2 }
      close_line = lines[n]
      if (close_line !~ /^[[:space:]]*}[[:space:]]*$/) {
        print "PHOSPHENE: signal JSON must end with a closing brace on its own line to insert tamper_hash" > "/dev/stderr"
        exit 2
      }
      if (n <= 1) {
        print "PHOSPHENE: signal JSON too small (cannot insert tamper_hash)" > "/dev/stderr"
        exit 2
      }
      prev = rtrim(lines[n-1])
      if (prev !~ /,$/) {
        lines[n-1] = prev ","
      } else {
        lines[n-1] = prev
      }
      for (i=1; i<n; i++) print lines[i]
      print "  \"tamper_hash\": \"sha256:" ph "\""
      for (i=n; i<=NR; i++) print lines[i]
    }
  ' "$f"
}

canonical_stream_for_hash() {
  # Produce the canonical-by-convention bytes for hashing:
  # - ensure tamper_hash exists (insert with placeholder if missing)
  # - normalize the tamper_hash value to the placeholder hex (preserving spacing)
  local f="$1"

  stream_with_inserted_tamper_field "$f" \
    | sed -E 's/("tamper_hash"[[:space:]]*:[[:space:]]*"sha256:)[0-9A-Fa-f]{64}(")/\1'"$TAMPER_PLACEHOLDER_HEX"'\2/'
}

compute_expected() {
  local f="$1"
  local hex
  hex="$(canonical_stream_for_hash "$f" | hash_sha256_hex)"
  printf "sha256:%s\n" "$hex"
}

extract_current() {
  local f="$1"
  # Extract the first occurrence. (Signals are expected to be small and have a single top-level field.)
  # Output: sha256:<hex>
  grep -oE '"tamper_hash"[[:space:]]*:[[:space:]]*"sha256:[0-9A-Fa-f]{64}"' "$f" \
    | head -n 1 \
    | sed -E 's/^"tamper_hash"[[:space:]]*:[[:space:]]*"//; s/"$//'
}

has_tamper_field_in_line() {
  local line="$1"
  grep -qE '"tamper_hash"[[:space:]]*:' <<<"$line"
}

canonical_line_for_hash() {
  # Normalize the tamper_hash value to the placeholder. The rest of the line bytes
  # remain unchanged (no JSON canonicalization beyond this substitution).
  local line="$1"
  printf "%s" "$line" \
    | sed -E 's/("tamper_hash"[[:space:]]*:[[:space:]]*"sha256:)[0-9A-Fa-f]{64}(")/\1'"$TAMPER_PLACEHOLDER_HEX"'\2/'
}

extract_current_from_line() {
  local line="$1"
  grep -oE '"tamper_hash"[[:space:]]*:[[:space:]]*"sha256:[0-9A-Fa-f]{64}"' <<<"$line" \
    | head -n 1 \
    | sed -E 's/^"tamper_hash"[[:space:]]*:[[:space:]]*"//; s/"$//'
}

compute_expected_line() {
  local line="$1"
  local hex
  hex="$(canonical_line_for_hash "$line" | hash_sha256_hex)"
  printf "sha256:%s\n" "$hex"
}

cmd_compute_line() {
  local line="${1:-}"
  [[ -n "${line:-}" ]] || fail "missing json line"
  # Require the field to exist to avoid ambiguous canonical insertion semantics.
  has_tamper_field_in_line "$line" || fail "missing tamper_hash in line"
  compute_expected_line "$line"
}

cmd_validate_line() {
  local line="${1:-}"
  [[ -n "${line:-}" ]] || fail "missing json line"

  local cur
  cur="$(extract_current_from_line "$line" || true)"
  if [[ -z "${cur:-}" ]]; then
    echo "FAIL: missing or malformed tamper_hash (line)" >&2
    return 1
  fi

  local expected
  expected="$(compute_expected_line "$line")"
  if [[ "$cur" != "$expected" ]]; then
    echo "FAIL: tamper_hash mismatch (line)" >&2
    echo "  expected: $expected" >&2
    echo "  found:    $cur" >&2
    return 1
  fi
  return 0
}

update_file_in_place() {
  local f="$1"
  local expected="$2"
  local expected_hex
  expected_hex="$(echo "$expected" | sed -E 's/^sha256://')"

  local tmp="${f}.tmp.$$"

  if has_tamper_field "$f"; then
    sed -E 's/("tamper_hash"[[:space:]]*:[[:space:]]*"sha256:)[0-9A-Fa-f]{64}(")/\1'"$expected_hex"'\2/' "$f" > "$tmp"
  else
    # Insert placeholder, then replace placeholder with expected.
    stream_with_inserted_tamper_field "$f" \
      | sed -E 's/("tamper_hash"[[:space:]]*:[[:space:]]*"sha256:)[0-9A-Fa-f]{64}(")/\1'"$expected_hex"'\2/' \
      > "$tmp"
  fi

  mv "$tmp" "$f"
}

cmd_compute() {
  local f="${1:-}"
  require_file "$f"
  compute_expected "$f"
}

cmd_update() {
  local f="${1:-}"
  require_file "$f"
  local expected
  expected="$(compute_expected "$f")"
  update_file_in_place "$f" "$expected"
  echo "OK: updated tamper_hash ($expected): $f" >&2
}

cmd_validate() {
  local f="${1:-}"
  require_file "$f"

  local cur
  cur="$(extract_current "$f" || true)"
  if [[ -z "${cur:-}" ]]; then
    echo "FAIL: missing or malformed tamper_hash: $f" >&2
    return 1
  fi

  local expected
  expected="$(compute_expected "$f")"
  if [[ "$cur" != "$expected" ]]; then
    echo "FAIL: tamper_hash mismatch: $f" >&2
    echo "  expected: $expected" >&2
    echo "  found:    $cur" >&2
    return 1
  fi
  return 0
}

CMD="${1:-help}"
shift || true
case "$CMD" in
  compute) cmd_compute "$@" ;;
  update) cmd_update "$@" ;;
  validate) cmd_validate "$@" ;;
  compute-line) cmd_compute_line "$@" ;;
  validate-line) cmd_validate_line "$@" ;;
  help|-h|--help) usage; exit 0 ;;
  *) fail "unknown command: $CMD" ;;
esac

