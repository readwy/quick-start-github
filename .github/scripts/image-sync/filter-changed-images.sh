#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <before_sha> <after_sha> <input_file> <output_file>" >&2
  exit 1
fi

before_sha="$1"
after_sha="$2"
input_file="$3"
output_file="$4"

if [[ "$before_sha" =~ ^0+$ ]]; then
  before_sha="$(git hash-object -t tree /dev/null)"
fi

: > "$output_file"

git diff --unified=0 "$before_sha" "$after_sha" -- "$input_file" |
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '+++'*|'@@'*|diff\ --git*|index\ *)
        continue
        ;;
      +*)
        added_line="${line#?}"
        if [[ -n "${added_line//[[:space:]]/}" && ! "$added_line" =~ ^[[:space:]]*# ]]; then
          printf '%s\n' "$added_line" >> "$output_file"
        fi
        ;;
    esac
  done
