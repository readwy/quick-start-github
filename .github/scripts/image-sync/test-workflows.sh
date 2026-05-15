#!/usr/bin/env bash
set -euo pipefail

assert_contains() {
  local file="$1"
  local expected="$2"

  if [[ ! -f "$file" ]]; then
    echo "FAIL: file not found: $file"
    exit 1
  fi

  if ! grep -Fq "$expected" "$file"; then
    echo "FAIL: expected '$expected' in $file"
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"

  if [[ ! -f "$file" ]]; then
    echo "FAIL: file not found: $file"
    exit 1
  fi

  if grep -Fq "$unexpected" "$file"; then
    echo "FAIL: did not expect '$unexpected' in $file"
    exit 1
  fi
}

docker_workflow=".github/workflows/docker.yaml"
docker_push_workflow=".github/workflows/docker-push.yaml"

assert_contains "$docker_workflow" "workflow_dispatch:"
assert_contains "$docker_workflow" "schedule:"
assert_not_contains "$docker_workflow" "push:"
assert_contains "$docker_workflow" "bash ./.github/scripts/sync-images.sh"

assert_contains "$docker_push_workflow" "push:"
assert_contains "$docker_push_workflow" "branches: [ main ]"
assert_contains "$docker_push_workflow" "paths: [ images.txt ]"
assert_contains "$docker_push_workflow" "fetch-depth: 0"
assert_contains "$docker_push_workflow" "bash ./.github/scripts/filter-changed-images.sh"
assert_contains "$docker_push_workflow" "bash ./.github/scripts/sync-images.sh"
assert_contains "$docker_push_workflow" "Record disk space before disk release"
assert_contains "$docker_push_workflow" "Maximize build space"
assert_contains "$docker_push_workflow" "Restart docker"
assert_contains "$docker_push_workflow" "Record disk space after disk release complete"
assert_contains "$docker_push_workflow" "No images to sync for this push."

echo "PASS: workflow configuration checks passed"
