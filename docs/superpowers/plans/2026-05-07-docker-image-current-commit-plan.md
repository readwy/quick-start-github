# Docker Image Current-Commit Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the existing Docker image workflow so it builds and pushes only Dockerfiles changed in the current commit range instead of processing every Dockerfile in the repository.

**Architecture:** Keep the existing single-workflow structure and modify only the discovery/filtering stage to compute the changed Dockerfile set from the current event context. The downstream login and build/push stages will keep using the manifest file, but will become conditional on a new `has_images` output from the filter step.

**Tech Stack:** GitHub Actions YAML, bash, git, docker CLI

---

## File Structure

- Modify: `.github/workflows/docker-build-push.yml` — add current-commit change detection, emit `has_images`, and gate login/build steps on that output.
- Reference only: `docs/superpowers/specs/2026-05-07-docker-image-current-commit-design.md` — approved selective-build design.
- Reference only: `docs/superpowers/specs/2026-05-07-docker-image-workflow-design.md` — original full-build workflow design.

### Task 1: Add trigger-aware changed-file detection to the filter step

**Files:**
- Modify: `.github/workflows/docker-build-push.yml`
- Test: inspect `.github/workflows/docker-build-push.yml`

- [ ] **Step 1: Write the failing trigger context wiring**

Add step-level event context variables to the existing `Discover Dockerfiles and resolve image names` step:

```yaml
      - name: Discover Dockerfiles and resolve image names
        id: filter
        shell: bash
        env:
          EVENT_NAME: ${{ github.event_name }}
          EVENT_BEFORE: ${{ github.event.before }}
          EVENT_SHA: ${{ github.sha }}
        run: |
          set -euo pipefail
```

- [ ] **Step 2: Verify the new trigger context variables are present**

Run: `Read .github/workflows/docker-build-push.yml`
Expected: The workflow contains `EVENT_NAME`, `EVENT_BEFORE`, and `EVENT_SHA` under the filter step `env` block.

- [ ] **Step 3: Replace full-repo Dockerfile scan with changed-file detection logic**

Update the `Discover Dockerfiles and resolve image names` step so the changed file source becomes:

```yaml
      - name: Discover Dockerfiles and resolve image names
        id: filter
        shell: bash
        env:
          EVENT_NAME: ${{ github.event_name }}
          EVENT_BEFORE: ${{ github.event.before }}
          EVENT_SHA: ${{ github.sha }}
        run: |
          set -euo pipefail

          image_list_file="$RUNNER_TEMP/docker-image-list.tsv"
          changed_files_file="$RUNNER_TEMP/changed-files.txt"
          : > "$image_list_file"
          : > "$changed_files_file"

          if [[ "$EVENT_NAME" == "push" && -n "${EVENT_BEFORE:-}" && "$EVENT_BEFORE" != "0000000000000000000000000000000000000000" ]]; then
            git diff --name-only "$EVENT_BEFORE" "$EVENT_SHA" > "$changed_files_file"
          elif git rev-parse --verify HEAD^ >/dev/null 2>&1; then
            git diff --name-only HEAD^ HEAD > "$changed_files_file"
          else
            git diff-tree --no-commit-id --name-only -r HEAD > "$changed_files_file"
          fi

          while IFS= read -r dockerfile; do
            [[ -n "$dockerfile" ]] || continue
            [[ "$(basename "$dockerfile")" == "Dockerfile" ]] || continue

            image_line="$(grep -m1 -E '^# image_name:' "$dockerfile" || true)"
            if [[ -z "$image_line" ]]; then
              continue
            fi

            raw_image_name="${image_line#\# image_name: }"
            resolved_image_name="$(bash -euo pipefail -c 'eval "printf %s \"$1\""' _ "$raw_image_name")"
            if [[ -z "$resolved_image_name" ]]; then
              echo "Resolved image name is empty for $dockerfile" >&2
              exit 1
            fi

            full_image_name="${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${resolved_image_name}"
            printf '%s\t%s\n' "$dockerfile" "$full_image_name" >> "$image_list_file"
          done < "$changed_files_file"
```

- [ ] **Step 4: Verify the discovery step now uses current-commit changed files**

Run: `Read .github/workflows/docker-build-push.yml`
Expected: The step no longer uses `find . -type f -name Dockerfile | sort` and instead derives changed files from `git diff --name-only` based on event context.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/docker-build-push.yml
git commit -m "feat: detect changed dockerfiles from current commit"
```

### Task 2: Emit has_images output and preserve manifest contract

**Files:**
- Modify: `.github/workflows/docker-build-push.yml`
- Test: inspect `.github/workflows/docker-build-push.yml`

- [ ] **Step 1: Add `has_images` output logic to the filter step**

Extend the end of the filter step with:

```yaml
          printf 'image_list_file=%s\n' "$image_list_file" >> "$GITHUB_OUTPUT"

          if [[ -s "$image_list_file" ]]; then
            printf 'has_images=true\n' >> "$GITHUB_OUTPUT"
          else
            printf 'has_images=false\n' >> "$GITHUB_OUTPUT"
          fi
```

- [ ] **Step 2: Verify the output contract is explicit**

Run: `Read .github/workflows/docker-build-push.yml`
Expected: The filter step now exports both `image_list_file` and `has_images` through `$GITHUB_OUTPUT`.

- [ ] **Step 3: Verify the manifest format remains unchanged**

The workflow must still write lines in this exact shape:

```text
<dockerfile_path>	<full_image_ref>
```

Expected example for the current repository:

```text
claude/Dockerfile	${REGISTRY_URL}/${REGISTRY_NAMESPACE}/claude:v-YYYYMMDDHHMMSS
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/docker-build-push.yml
git commit -m "feat: emit selective docker build outputs"
```

### Task 3: Skip login and build/push when no Dockerfile changed

**Files:**
- Modify: `.github/workflows/docker-build-push.yml`
- Test: inspect `.github/workflows/docker-build-push.yml`

- [ ] **Step 1: Gate the login step on `has_images`**

Update the login step header to:

```yaml
      - name: Log in to registry
        if: ${{ steps.filter.outputs.has_images == 'true' }}
        shell: bash
        run: |
          set -euo pipefail
          printf '%s' "$REGISTRY_PASSWORD" | docker login "$REGISTRY_URL" -u "$REGISTRY_USER" --password-stdin
```

- [ ] **Step 2: Gate the build/push step on `has_images`**

Update the build step header to:

```yaml
      - name: Build and push images
        if: ${{ steps.filter.outputs.has_images == 'true' }}
        shell: bash
        env:
          IMAGE_LIST_FILE: ${{ steps.filter.outputs.image_list_file }}
        run: |
          set -euo pipefail

          while IFS=$'\t' read -r dockerfile full_image_name; do
            if [[ -z "$dockerfile" ]]; then
              continue
            fi

            context_dir=$(dirname "$dockerfile")
            docker build -f "$dockerfile" -t "$full_image_name" "$context_dir"
            docker push "$full_image_name"
          done < "$IMAGE_LIST_FILE"
```

- [ ] **Step 3: Verify no-op behavior is explicit**

Run: `Read .github/workflows/docker-build-push.yml`
Expected: Both registry login and build/push steps are skipped when `steps.filter.outputs.has_images` is `false`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/docker-build-push.yml
git commit -m "feat: skip docker push when no dockerfile changed"
```

### Task 4: Validate edge-case handling against the spec

**Files:**
- Modify: `.github/workflows/docker-build-push.yml`
- Test: inspect `.github/workflows/docker-build-push.yml`
- Reference: `docs/superpowers/specs/2026-05-07-docker-image-current-commit-design.md`

- [ ] **Step 1: Verify push fallback for missing or zero `before`**

Confirm the filter logic includes this behavior:

```bash
if [[ "$EVENT_NAME" == "push" && -n "${EVENT_BEFORE:-}" && "$EVENT_BEFORE" != "0000000000000000000000000000000000000000" ]]; then
  git diff --name-only "$EVENT_BEFORE" "$EVENT_SHA" > "$changed_files_file"
elif git rev-parse --verify HEAD^ >/dev/null 2>&1; then
  git diff --name-only HEAD^ HEAD > "$changed_files_file"
else
  git diff-tree --no-commit-id --name-only -r HEAD > "$changed_files_file"
fi
```

Expected: Push events with a usable `before` diff that range; otherwise the workflow falls back deterministically to the current commit.

- [ ] **Step 2: Verify non-Dockerfile changes do not trigger builds**

The changed-file loop must contain:

```bash
[[ "$(basename "$dockerfile")" == "Dockerfile" ]] || continue
```

Expected: Files such as `README.md` or `Dockerfile.template` are excluded.

- [ ] **Step 3: Verify current repository behavior example**

For a commit changing `claude/Dockerfile`, the resulting manifest line shape should remain:

```text
claude/Dockerfile	${REGISTRY_URL}/${REGISTRY_NAMESPACE}/claude:v-YYYYMMDDHHMMSS
```

For a commit that changes no Dockerfiles:

```text
image_list_file=<runner-temp-path>
has_images=false
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/docker-build-push.yml
git commit -m "test: verify selective docker build behavior"
```
