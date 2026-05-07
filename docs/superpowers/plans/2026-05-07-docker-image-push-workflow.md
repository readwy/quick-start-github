# Docker Image Push Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GitHub Actions workflow that discovers every repository `Dockerfile`, resolves each `# image_name:` declaration including embedded Linux command substitutions, then builds and pushes each image to the configured registry.

**Architecture:** The workflow will use one discovery step to scan all `Dockerfile` files and generate a manifest file containing `dockerfile_path` and fully resolved image reference pairs. A second step will log in to the registry and iterate over that manifest to run `docker build` and `docker push` for each image.

**Tech Stack:** GitHub Actions YAML, bash, docker CLI

---

## File Structure

- Create: `.github/workflows/docker-build-push.yml` — the workflow that discovers Dockerfiles, resolves image names, logs in to the registry, builds images, and pushes them.
- Keep unchanged unless explicitly requested: `claude/Dockerfile` — already contains the `# image_name:` declaration used by the workflow.
- Reference only: `docs/superpowers/specs/2026-05-07-docker-image-workflow-design.md` — approved design source.

### Task 1: Add the workflow skeleton and trigger

**Files:**
- Create: `.github/workflows/docker-build-push.yml`
- Test: inspect `.github/workflows/docker-build-push.yml`

- [ ] **Step 1: Write the failing workflow skeleton**

Create `.github/workflows/docker-build-push.yml` with this minimal content:

```yaml
name: docker-build-push

on:
  workflow_dispatch:

jobs:
  docker-build-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
```

- [ ] **Step 2: Verify the workflow file exists but is incomplete**

Run: `Read .github/workflows/docker-build-push.yml`
Expected: File exists and only contains workflow name, trigger, job, and checkout step.

- [ ] **Step 3: Extend the skeleton with the four registry environment variables**

Replace the file content with:

```yaml
name: docker-build-push

on:
  workflow_dispatch:

jobs:
  docker-build-push:
    runs-on: ubuntu-latest
    env:
      REGISTRY_URL: ${{ secrets.REGISTRY_URL }}
      REGISTRY_NAMESPACE: ${{ secrets.REGISTRY_NAMESPACE }}
      REGISTRY_USER: ${{ secrets.REGISTRY_USER }}
      REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
```

- [ ] **Step 4: Verify the job-level environment variables are present**

Run: `Read .github/workflows/docker-build-push.yml`
Expected: File contains the four registry variables under `jobs.docker-build-push.env`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/docker-build-push.yml
git commit -m "feat: add docker workflow skeleton"
```

### Task 2: Add Dockerfile discovery and manifest generation

**Files:**
- Modify: `.github/workflows/docker-build-push.yml`
- Test: inspect `.github/workflows/docker-build-push.yml`

- [ ] **Step 1: Write the discovery step into the workflow**

Insert this step after checkout:

```yaml
      - name: Discover Dockerfiles and resolve image names
        id: filter
        shell: bash
        run: |
          set -euo pipefail

          image_list_file="$RUNNER_TEMP/image-list.txt"
          : > "$image_list_file"

          while IFS= read -r dockerfile; do
            image_line=$(grep -m1 '^# image_name:' "$dockerfile" || true)
            if [ -z "$image_line" ]; then
              echo "Skip $dockerfile because no # image_name: line was found"
              continue
            fi

            raw_image_name=${image_line#'# image_name: '}
            resolved_image_name=$(IMAGE_NAME="$raw_image_name" bash -lc 'eval "printf %s \"$IMAGE_NAME\""')
            full_image_name="${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${resolved_image_name}"

            printf '%s\t%s\n' "$dockerfile" "$full_image_name" >> "$image_list_file"
          done < <(find . -type f -name Dockerfile | sort)

          echo "image_list_file=$image_list_file" >> "$GITHUB_OUTPUT"
```

- [ ] **Step 2: Verify the discovery step is present**

Run: `Read .github/workflows/docker-build-push.yml`
Expected: Workflow contains a `Discover Dockerfiles and resolve image names` step with `id: filter` and writes `image_list_file` to `$GITHUB_OUTPUT`.

- [ ] **Step 3: Check the runtime behavior against the current Dockerfile metadata**

Use this expected input from `claude/Dockerfile`:

```text
# image_name: claude:v-$(date "+%Y%m%d%H%M%S")
```

Expected resolved pattern:

```text
${REGISTRY_URL}/${REGISTRY_NAMESPACE}/claude:v-YYYYMMDDHHMMSS
```

Expected manifest line pattern:

```text
./claude/Dockerfile	${REGISTRY_URL}/${REGISTRY_NAMESPACE}/claude:v-YYYYMMDDHHMMSS
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/docker-build-push.yml
git commit -m "feat: add docker image discovery step"
```

### Task 3: Add registry login, build, and push steps

**Files:**
- Modify: `.github/workflows/docker-build-push.yml`
- Test: inspect `.github/workflows/docker-build-push.yml`

- [ ] **Step 1: Write the login step**

Insert this step after the discovery step:

```yaml
      - name: Log in to registry
        shell: bash
        run: |
          set -euo pipefail
          echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_URL" -u "$REGISTRY_USER" --password-stdin
```

- [ ] **Step 2: Write the build and push step**

Insert this step after the login step:

```yaml
      - name: Build and push images
        shell: bash
        env:
          IMAGE_LIST_FILE: ${{ steps.filter.outputs.image_list_file }}
        run: |
          set -euo pipefail

          while IFS=$'\t' read -r dockerfile full_image_name; do
            [ -n "$dockerfile" ] || continue
            context_dir=$(dirname "$dockerfile")

            docker build -f "$dockerfile" -t "$full_image_name" "$context_dir"
            docker push "$full_image_name"
          done < "$IMAGE_LIST_FILE"
```

- [ ] **Step 3: Verify the workflow now covers discovery, login, build, and push**

Run: `Read .github/workflows/docker-build-push.yml`
Expected: Workflow contains exactly these functional stages in order: checkout, discovery, registry login, build/push.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/docker-build-push.yml
git commit -m "feat: add docker image push workflow"
```

### Task 4: Final validation against the approved design

**Files:**
- Test: `.github/workflows/docker-build-push.yml`
- Reference: `docs/superpowers/specs/2026-05-07-docker-image-workflow-design.md`

- [ ] **Step 1: Verify spec coverage**

Check that the workflow implements all approved requirements:

```text
- scans all Dockerfile files
- reads # image_name: values
- resolves $(...) expressions on Linux
- defines REGISTRY_URL, REGISTRY_NAMESPACE, REGISTRY_USER, REGISTRY_PASSWORD from secrets
- exposes steps.filter.outputs.image_list_file
- defines IMAGE_LIST_FILE from steps.filter.outputs.image_list_file on the consuming step
- prefixes with ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/
- logs in with REGISTRY_USER and REGISTRY_PASSWORD
- pushes every resolved image
```

Expected: Every requirement is directly represented in `.github/workflows/docker-build-push.yml`.

- [ ] **Step 2: Verify the expected generated output shape**

Expected runtime manifest content for the current repo shape:

```text
./claude/Dockerfile	${REGISTRY_URL}/${REGISTRY_NAMESPACE}/claude:v-YYYYMMDDHHMMSS
```

Expected build command shape:

```bash
docker build -f "./claude/Dockerfile" -t "${REGISTRY_URL}/${REGISTRY_NAMESPACE}/claude:v-YYYYMMDDHHMMSS" "./claude"
```

Expected push command shape:

```bash
docker push "${REGISTRY_URL}/${REGISTRY_NAMESPACE}/claude:v-YYYYMMDDHHMMSS"
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/docker-build-push.yml
git commit -m "test: verify docker workflow design coverage"
```
