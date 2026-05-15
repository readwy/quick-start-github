#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
filter_script="$repo_root/.github/scripts/filter-changed-images.sh"

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

prepare_repo() {
  local repo_dir="$1"
  git init -q "$repo_dir"
  git -C "$repo_dir" config user.name "Test User"
  git -C "$repo_dir" config user.email "test@example.com"
}

commit_all() {
  local repo_dir="$1"
  local message="$2"
  git -C "$repo_dir" add -A
  git -C "$repo_dir" commit -q -m "$message"
}

assert_output() {
  local output_file="$1"
  shift

  local expected=""
  if [ "$#" -gt 0 ]; then
    expected="$(printf '%s\n' "$@")"
  fi

  local actual=""
  if [ -f "$output_file" ]; then
    actual="$(<"$output_file")"
  fi

  if [ "$actual" != "$expected" ]; then
    printf 'expected output:\n%s\nactual output:\n%s\n' "${expected:-<empty>}" "${actual:-<empty>}" >&2
    return 1
  fi
}

run_filter() {
  local repo_dir="$1"
  local before_sha="$2"
  local after_sha="$3"
  local output_file="$4"

  (cd "$repo_dir" && bash "$filter_script" "$before_sha" "$after_sha" "images.txt" "$output_file")
}

# add
case_dir="$tmp_root/add"
mkdir -p "$case_dir"
prepare_repo "$case_dir"
git -C "$case_dir" commit --allow-empty -q -m "base"
before_sha="$(git -C "$case_dir" rev-parse HEAD)"
cat > "$case_dir/images.txt" <<'EOF'
ubuntu:24.04
# comment

nginx:1.27
EOF
commit_all "$case_dir" "add images"
after_sha="$(git -C "$case_dir" rev-parse HEAD)"
output_file="$case_dir/output.txt"
run_filter "$case_dir" "$before_sha" "$after_sha" "$output_file"
assert_output "$output_file" "ubuntu:24.04" "nginx:1.27"

# change
case_dir="$tmp_root/change"
mkdir -p "$case_dir"
prepare_repo "$case_dir"
cat > "$case_dir/images.txt" <<'EOF'
alpine:3.19
EOF
commit_all "$case_dir" "base"
before_sha="$(git -C "$case_dir" rev-parse HEAD)"
cat > "$case_dir/images.txt" <<'EOF'
alpine:3.20
EOF
commit_all "$case_dir" "change image"
after_sha="$(git -C "$case_dir" rev-parse HEAD)"
output_file="$case_dir/output.txt"
run_filter "$case_dir" "$before_sha" "$after_sha" "$output_file"
assert_output "$output_file" "alpine:3.20"

# delete
case_dir="$tmp_root/delete"
mkdir -p "$case_dir"
prepare_repo "$case_dir"
cat > "$case_dir/images.txt" <<'EOF'
busybox:1.36
EOF
commit_all "$case_dir" "base"
before_sha="$(git -C "$case_dir" rev-parse HEAD)"
rm "$case_dir/images.txt"
commit_all "$case_dir" "delete image"
after_sha="$(git -C "$case_dir" rev-parse HEAD)"
output_file="$case_dir/output.txt"
run_filter "$case_dir" "$before_sha" "$after_sha" "$output_file"
assert_output "$output_file"

# comment-only
case_dir="$tmp_root/comment-only"
mkdir -p "$case_dir"
prepare_repo "$case_dir"
cat > "$case_dir/images.txt" <<'EOF'
redis:7
EOF
commit_all "$case_dir" "base"
before_sha="$(git -C "$case_dir" rev-parse HEAD)"
cat > "$case_dir/images.txt" <<'EOF'
redis:7
# added comment
EOF
commit_all "$case_dir" "comment only"
after_sha="$(git -C "$case_dir" rev-parse HEAD)"
output_file="$case_dir/output.txt"
run_filter "$case_dir" "$before_sha" "$after_sha" "$output_file"
assert_output "$output_file"

# blank-line-only
case_dir="$tmp_root/blank-line-only"
mkdir -p "$case_dir"
prepare_repo "$case_dir"
cat > "$case_dir/images.txt" <<'EOF'
postgres:16
EOF
commit_all "$case_dir" "base"
before_sha="$(git -C "$case_dir" rev-parse HEAD)"
cat > "$case_dir/images.txt" <<'EOF'
postgres:16


EOF
commit_all "$case_dir" "blank lines only"
after_sha="$(git -C "$case_dir" rev-parse HEAD)"
output_file="$case_dir/output.txt"
run_filter "$case_dir" "$before_sha" "$after_sha" "$output_file"
assert_output "$output_file"

# mixed
case_dir="$tmp_root/mixed"
mkdir -p "$case_dir"
prepare_repo "$case_dir"
cat > "$case_dir/images.txt" <<'EOF'
keep-one
remove-one
# old comment
EOF
commit_all "$case_dir" "base"
before_sha="$(git -C "$case_dir" rev-parse HEAD)"
cat > "$case_dir/images.txt" <<'EOF'
keep-one
add-one
# new comment


EOF
commit_all "$case_dir" "mixed changes"
after_sha="$(git -C "$case_dir" rev-parse HEAD)"
output_file="$case_dir/output.txt"
run_filter "$case_dir" "$before_sha" "$after_sha" "$output_file"
assert_output "$output_file" "add-one"

# zero-before regression
case_dir="$tmp_root/zero-before"
mkdir -p "$case_dir"
prepare_repo "$case_dir"
cat > "$case_dir/images.txt" <<'EOF'
apache:2.4
# initial comment

EOF
commit_all "$case_dir" "initial push"
after_sha="$(git -C "$case_dir" rev-parse HEAD)"
output_file="$case_dir/output.txt"
run_filter "$case_dir" "0000000000000000000000000000000000000000" "$after_sha" "$output_file"
assert_output "$output_file" "apache:2.4"
