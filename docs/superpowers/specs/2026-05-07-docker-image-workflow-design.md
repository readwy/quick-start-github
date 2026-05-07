# Docker Image Workflow Design

## Goal

Add a GitHub Actions workflow that scans all `Dockerfile` files in the repository, reads each `# image_name:` declaration, resolves any embedded Linux command substitutions such as `$(date "+%Y%m%d%H%M%S")` on the runner at execution time, and builds then pushes each resulting image to the configured registry.

## Confirmed repository context

- The repository currently contains one Dockerfile at `claude/Dockerfile`.
- `claude/Dockerfile` already uses the target metadata pattern with an inline tag expression:
  - `# image_name: claude:v-$(date "+%Y%m%d%H%M%S")`
- `.github/workflows/` does not yet contain any workflows.

## Inputs and secrets

The workflow will define and use these variables exactly as requested:

- `REGISTRY_URL: "${{ secrets.REGISTRY_URL }}"`
- `REGISTRY_NAMESPACE: "${{ secrets.REGISTRY_NAMESPACE }}"`
- `REGISTRY_USER: "${{ secrets.REGISTRY_USER }}"`
- `REGISTRY_PASSWORD: "${{ secrets.REGISTRY_PASSWORD }}"`
- `IMAGE_LIST_FILE: "${{ steps.filter.outputs.image_list_file }}"`

## Workflow behavior

### 1. Discover Dockerfiles

The workflow will recursively search the repository for every file named `Dockerfile`.

### 2. Extract declared image names

For each Dockerfile, the workflow will read the first matching line that starts with `# image_name:` and extract the value after the prefix.

Example:

```text
# image_name: claude:v-$(date "+%Y%m%d%H%M%S")
```

Extracted raw value:

```text
claude:v-$(date "+%Y%m%d%H%M%S")
```

### 3. Resolve embedded Linux commands

The workflow will evaluate the extracted string with `bash` on the Linux runner so command substitutions like `$(date "+%Y%m%d%H%M%S")` become real tag values at runtime.

Example resolved value:

```text
claude:v-20260507153000
```

### 4. Build final registry image references

Each resolved image name will be prefixed with:

```text
${REGISTRY_URL}/${REGISTRY_NAMESPACE}/
```

Example:

```text
registry.example.com/team/claude:v-20260507153000
```

### 5. Persist discovered build list

The workflow will write a newline-delimited build manifest file and expose its path through `steps.filter.outputs.image_list_file` so later steps can consume it via `IMAGE_LIST_FILE`.

Each line in the manifest will contain the Dockerfile path and the fully resolved image reference, separated by a tab.

Example line:

```text
claude/Dockerfile	registry.example.com/team/claude:v-20260507153000
```

### 6. Authenticate and push

The workflow will:

- log in to the target registry with `docker login`
- iterate over the manifest entries
- run `docker build -f <dockerfile> -t <full-image> <dockerfile-directory>`
- run `docker push <full-image>`

## Design choices

### Recommended approach: one workflow with shell-based discovery and iteration

This design keeps the source of truth inside each Dockerfile and avoids duplicating image-name or tag logic in workflow YAML. Adding a new Dockerfile only requires adding a matching `# image_name:` line.

### Alternatives considered

1. Hardcode a build matrix in workflow YAML.
   - Rejected because every new Dockerfile would require updating the workflow.
2. Split image metadata into a separate manifest file.
   - Rejected because it would duplicate data already intended to live next to each Dockerfile.
3. Parse but not execute `$(...)` expressions.
   - Rejected because the requested tag format depends on runtime Linux command execution.

## Constraints and safety assumptions

- The workflow assumes `# image_name:` values are trusted repository content.
- Command substitution is intentionally executed with `bash` because this is a repository-controlled automation rule.
- Dockerfiles without a `# image_name:` line will be skipped.
- The workflow targets GitHub-hosted Linux runners.

## Files to create or modify during implementation

- Create: `.github/workflows/docker-build-push.yml`
- Possibly modify: `claude/Dockerfile` only if the current `# image_name:` line needs normalization to match the agreed format exactly.

## Success criteria

- A workflow can be triggered in GitHub Actions.
- It finds all repository Dockerfiles.
- It resolves `$(...)` expressions from each `# image_name:` line on Linux.
- It builds every discovered image.
- It pushes every built image to `${REGISTRY_URL}/${REGISTRY_NAMESPACE}`.
- It exposes the generated manifest path via `steps.filter.outputs.image_list_file` and `IMAGE_LIST_FILE`.
