#!/usr/bin/env bash
set -euo pipefail

IMAGE_LIST_FILE="${IMAGE_LIST_FILE:-images.txt}"

if [[ ! -f "$IMAGE_LIST_FILE" ]]; then
  echo "ERROR: input image list file not found: $IMAGE_LIST_FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y jq
fi

printf '%s' "$REGISTRY_PASSWORD" | docker login -u "$REGISTRY_USER" --password-stdin "$REGISTRY_URL"

unset REGISTRY_PASSWORD

list_platforms() {
  local ref="$1"
  local platforms=""
  local inspect_output=""
  local image_os=""
  local image_arch=""
  local image_variant=""

  if inspect_output="$(docker manifest inspect "$ref" 2>/dev/null)"; then
    platforms="$(printf '%s' "$inspect_output" | jq -r '
      .manifests[]?.platform
      | select(.os and .architecture)
      | .os + "/" + .architecture + (if .variant then "/" + .variant else "" end)
    ' | sort -u)"
  fi

  if [[ -n "$platforms" ]]; then
    printf '%s\n' "$platforms"
    return 0
  fi

  if inspect_output="$(docker manifest inspect --verbose "$ref" 2>/dev/null)"; then
    platforms="$(printf '%s' "$inspect_output" | jq -r '
      def format_platform:
        if type == "object" then
          (.os // .OS // empty) as $os
          | (.architecture // .Architecture // empty) as $arch
          | (.variant // .Variant // empty) as $variant
          | if ($os | length) > 0 and ($arch | length) > 0 then
              $os + "/" + $arch + (if ($variant | length) > 0 then "/" + $variant else "" end)
            else
              empty
            end
        elif type == "string" then
          split(" / ")
          | if length == 2 then .[1] + "/" + .[0] elif length == 3 then .[1] + "/" + .[0] + "/" + .[2] else empty end
        else
          empty
        end;
      (if type == "array" then .[] else . end)
      | (.Platform // .platform // .Descriptor.platform // empty) | format_platform
    ' | sort -u)"
  fi

  if [[ -n "$platforms" ]]; then
    printf '%s\n' "$platforms"
    return 0
  fi

  echo "warning platform query failed, try plain pull inspection" >&2
  if docker pull "$ref" > /dev/null 2>&1; then
    image_os=$(docker image inspect "$ref" --format '{{.Os}}')
    image_arch=$(docker image inspect "$ref" --format '{{.Architecture}}')
    image_variant=$(docker image inspect "$ref" --format '{{if .Variant}}{{.Variant}}{{end}}')
    if [[ -n "$image_variant" ]]; then
      printf '%s/%s/%s\n' "$image_os" "$image_arch" "$image_variant"
    else
      printf '%s/%s\n' "$image_os" "$image_arch"
    fi
    docker rmi "$ref" > /dev/null 2>&1 || true
    return 0
  fi

  echo "warning plain pull failed, try default linux/amd64" >&2
  printf '%s\n' "linux/amd64"
}

get_platform_digest() {
  local ref="$1"
  local platform="$2"
  local inspect_output=""
  local digest=""

  if inspect_output="$(docker manifest inspect "$ref" 2>/dev/null)"; then
    digest="$(printf '%s' "$inspect_output" | jq -r --arg platform "$platform" '
      def format_platform:
        .os + "/" + .architecture + (if .variant then "/" + .variant else "" end);
      [
        .manifests[]?
        | select(.platform.os and .platform.architecture)
        | select((.platform | format_platform) == $platform)
        | .digest
      ][0] // empty
    ')"
    if [[ -n "$digest" ]]; then
      printf '%s\n' "$digest"
      return 0
    fi
  fi

  if inspect_output="$(docker manifest inspect --verbose "$ref" 2>/dev/null)"; then
    digest="$(printf '%s' "$inspect_output" | jq -r --arg platform "$platform" '
      def format_platform:
        if type == "object" then
          (.os // .OS // empty) as $os
          | (.architecture // .Architecture // empty) as $arch
          | (.variant // .Variant // empty) as $variant
          | if ($os | length) > 0 and ($arch | length) > 0 then
              $os + "/" + $arch + (if ($variant | length) > 0 then "/" + $variant else "" end)
            else
              empty
            end
        elif type == "string" then
          split(" / ")
          | if length == 2 then .[1] + "/" + .[0] elif length == 3 then .[1] + "/" + .[0] + "/" + .[2] else empty end
        else
          empty
        end;
      [
        (if type == "array" then .[] else . end)
        | ((.Platform // .platform // .Descriptor.platform // empty) | format_platform) as $current_platform
        | select($current_platform == $platform)
        | (.Digest // .digest // .Descriptor.digest // empty)
      ][0] // empty
    ')"
    if [[ -n "$digest" ]]; then
      printf '%s\n' "$digest"
      return 0
    fi
  fi

  return 1
}

remote_ref_exists() {
  local ref="$1"
  docker manifest inspect "$ref" > /dev/null 2>&1 || docker manifest inspect --verbose "$ref" > /dev/null 2>&1
}

unified_manifest_matches_platforms() {
  local ref="$1"
  local expected_platforms="$2"
  local actual_platforms=""
  local inspect_output=""

  if inspect_output="$(docker manifest inspect "$ref" 2>/dev/null)"; then
    actual_platforms="$(printf '%s' "$inspect_output" | jq -r '
      .manifests[]?.platform
      | select(.os and .architecture)
      | .os + "/" + .architecture + (if .variant then "/" + .variant else "" end)
    ' | sort -u)"
  elif inspect_output="$(docker manifest inspect --verbose "$ref" 2>/dev/null)"; then
    actual_platforms="$(printf '%s' "$inspect_output" | jq -r '
      def format_platform:
        if type == "object" then
          (.os // .OS // empty) as $os
          | (.architecture // .Architecture // empty) as $arch
          | (.variant // .Variant // empty) as $variant
          | if ($os | length) > 0 and ($arch | length) > 0 then
              $os + "/" + $arch + (if ($variant | length) > 0 then "/" + $variant else "" end)
            else
              empty
            end
        elif type == "string" then
          split(" / ")
          | if length == 2 then .[1] + "/" + .[0] elif length == 3 then .[1] + "/" + .[0] + "/" + .[2] else empty end
        else
          empty
        end;
      (if type == "array" then .[] else . end)
      | (.Platform // .platform // .Descriptor.platform // empty) | format_platform
    ' | sort -u)"
  else
    return 1
  fi

  [[ "$actual_platforms" == "$expected_platforms" ]]
}

declare -A duplicate_images=()
declare -A namespace_map=()

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue

  source_ref="$line"
  last_segment="${source_ref##*/}"
  if [[ "$source_ref" != *@* && "$last_segment" != *:* ]]; then
    source_ref="${source_ref}:latest"
  fi

  source_name="${source_ref%%@*}"
  source_name_no_tag="$source_name"
  last_segment="${source_name##*/}"
  if [[ "$last_segment" == *:* ]]; then
    source_name_no_tag="${source_name%:*}"
  fi

  image_name="${source_name_no_tag##*/}"
  namespace_path="${source_name_no_tag%/*}"
  if [[ "$namespace_path" == "$source_name_no_tag" ]]; then
    namespace_path=""
  fi

  namespace_key="${namespace_path//\//_}"
  namespace_key="${namespace_key:-_root}"

  if [[ -n "${namespace_map[$image_name]:-}" && "${namespace_map[$image_name]}" != "$namespace_key" ]]; then
    duplicate_images[$image_name]=1
  else
    namespace_map[$image_name]="$namespace_key"
  fi
done < "$IMAGE_LIST_FILE"

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue

  source_ref="$line"
  last_segment="${source_ref##*/}"
  if [[ "$source_ref" != *@* && "$last_segment" != *:* ]]; then
    source_ref="${source_ref}:latest"
  fi

  source_name="${source_ref%%@*}"
  digest=""
  if [[ "$source_ref" == *@* ]]; then
    digest="${source_ref#*@}"
  fi

  source_name_no_tag="$source_name"
  last_segment="${source_name##*/}"
  explicit_tag=""
  if [[ "$last_segment" == *:* ]]; then
    explicit_tag="${source_name##*:}"
    source_name_no_tag="${source_name%:*}"
  fi

  image_name="${source_name_no_tag##*/}"
  namespace_path="${source_name_no_tag%/*}"
  if [[ "$namespace_path" == "$source_name_no_tag" ]]; then
    namespace_path=""
  fi

  namespace_prefix=""
  if [[ -n "${duplicate_images[$image_name]:-}" && -n "$namespace_path" ]]; then
    namespace_prefix="${namespace_path//\//_}_"
  fi

  target_repo="$REGISTRY_URL/$REGISTRY_NAMESPACE/${namespace_prefix}${image_name}"
  target_tag="$explicit_tag"
  if [[ -z "$target_tag" ]]; then
    if [[ -n "$digest" ]]; then
      digest_value="${digest#*:}"
      if [[ "$digest_value" == "$digest" ]]; then
        digest_value="$digest"
      fi
      target_tag="sha-${digest_value:0:12}"
    else
      target_tag="latest"
    fi
  fi

  unified_target="$target_repo:$target_tag"

  echo "----------------------------------------------------------"
  echo "sync image: $source_ref"

  platforms="$(list_platforms "$source_ref")"
  needs_unified_publish=0

  while IFS= read -r platform; do
    [[ -z "$platform" ]] && continue

    echo "  -> sync: $platform"
    source_digest=""
    target_digest=""

    if source_digest="$(get_platform_digest "$source_ref" "$platform" 2>/dev/null)"; then
      :
    else
      source_digest=""
    fi

    if target_digest="$(get_platform_digest "$unified_target" "$platform" 2>/dev/null)"; then
      :
    else
      target_digest=""
    fi

    if [[ -z "$source_digest" ]]; then
      echo "    [sync] source digest unavailable, republish unified tag"
      needs_unified_publish=1
      continue
    fi

    if [[ -n "$target_digest" && "$source_digest" == "$target_digest" ]]; then
      echo "    [skip] $platform already up to date ($target_digest)"
      continue
    fi

    if [[ -z "$target_digest" ]]; then
      echo "    [sync] target unified tag missing platform or digest unavailable"
    else
      echo "    [sync] digest changed: source=$source_digest target=$target_digest"
    fi

    needs_unified_publish=1
  done <<< "$platforms"

  if [[ $needs_unified_publish -eq 0 ]] && remote_ref_exists "$unified_target" && unified_manifest_matches_platforms "$unified_target" "$platforms"; then
    echo "all platforms already up to date, skip unified tag: $unified_target"
    continue
  fi

  docker buildx imagetools create --tag "$unified_target" "$source_ref"
  echo "published unified tag: $unified_target"
done < "$IMAGE_LIST_FILE"

echo "----------------------------------------------------------"
echo "all image sync finished"
