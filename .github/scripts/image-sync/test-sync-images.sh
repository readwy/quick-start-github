#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH=".github/scripts/sync-images.sh"

if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "ERROR: $SCRIPT_PATH does not exist" >&2
  exit 1
fi

if ! grep -Fq 'IMAGE_LIST_FILE="${IMAGE_LIST_FILE:-images.txt}"' "$SCRIPT_PATH"; then
  echo "ERROR: missing IMAGE_LIST_FILE default line" >&2
  exit 1
fi

done_count="$(grep -Fc 'done < "$IMAGE_LIST_FILE"' "$SCRIPT_PATH")"
if [[ "$done_count" -ne 2 ]]; then
  echo "ERROR: expected exactly 2 occurrences of done < \"\$IMAGE_LIST_FILE\", found $done_count" >&2
  exit 1
fi

if ! grep -Fq 'docker buildx imagetools create --tag "$unified_target" "$source_ref"' "$SCRIPT_PATH"; then
  echo "ERROR: missing unified manifest publish command" >&2
  exit 1
fi

bash -n "$SCRIPT_PATH"

echo "PASS: static guards succeeded for $SCRIPT_PATH"
