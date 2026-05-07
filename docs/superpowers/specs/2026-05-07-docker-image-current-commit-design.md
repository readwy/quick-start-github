# Docker Image Current-Commit Build Design

## Goal

Optimize the existing Docker image workflow so it builds and pushes only the `Dockerfile` files changed in the current commit range, instead of scanning and pushing every `Dockerfile` in the repository.

## Confirmed repository context

- The current workflow file is `.github/workflows/docker-build-push.yml`.
- The repository currently contains one Dockerfile at `claude/Dockerfile`.
- That Dockerfile already declares its image metadata with:
  - `# image_name: claude:v-$(date "+%Y%m%d%H%M%S")`
- The existing workflow already supports:
  - resolving `# image_name:` values at runtime on Linux
  - generating an image manifest file
  - logging in to the registry
  - building and pushing each image from the manifest

## Approved requirement

Only Dockerfiles changed in the current commit should be built.

The comparison rule is:

- For `push`: compare the event range from `github.event.before` to `github.sha`
- For `workflow_dispatch`: compare only the current commit (`HEAD`) against its first parent

## Recommended design

Keep the existing workflow structure and change only the discovery logic.

### Why this approach

The current workflow already has a clean split between:

1. discovery/filtering
2. registry login
3. build/push execution

The least risky optimization is to update only the discovery step so it writes changed Dockerfiles into the manifest, while leaving the downstream push logic unchanged.

## Workflow behavior

### 1. Detect changed files for the current run

The workflow will derive a commit comparison range based on the trigger type.

#### Push trigger

For `push`, use the GitHub event range:

- base: `${{ github.event.before }}`
- head: `${{ github.sha }}`

The workflow will gather changed files from that range.

#### Manual trigger

For `workflow_dispatch`, use the current commit only:

- compare `HEAD^` to `HEAD`

This makes the manual run behavior align with the requested “current commit only” rule.

### 2. Filter to changed Dockerfiles only

From the changed file list, keep only paths whose basename is exactly `Dockerfile`.

Examples:

- include: `claude/Dockerfile`
- exclude: `README.md`
- exclude: `docker/Dockerfile.template`

### 3. Resolve image metadata only for changed Dockerfiles

For each changed Dockerfile:

- read the first `# image_name:` line
- skip the file if the line does not exist
- extract the value after `# image_name: `
- evaluate trusted `$(...)` expressions on the Linux runner
- build the final image reference as:

```text
${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${resolved_image_name}
```

### 4. Write the manifest in the existing format

The workflow will keep the current manifest structure so later steps do not need redesign.

Each line will remain:

```text
<dockerfile_path>\t<full_image_ref>
```

Example:

```text
claude/Dockerfile	registry.example.com/team/claude:v-20260507153000
```

### 5. Skip build/push cleanly when no Dockerfile changed

If the current commit range contains no changed Dockerfiles, the workflow should:

- still produce an empty manifest file
- expose the manifest path via `steps.filter.outputs.image_list_file`
- expose an additional boolean-like output such as `has_images=true|false`
- skip the login step when `has_images` is `false`
- skip the build/push step when `has_images` is `false`

This avoids unnecessary registry authentication and makes no-op runs explicit.

## Alternatives considered

### 1. Replace the workflow with a matrix build

Rejected because the repository currently has only one Dockerfile and the existing sequential manifest-based flow is simpler.

### 2. Keep full Dockerfile scan and intersect later

Viable, but less direct. It keeps extra discovery work that is no longer needed when the requirement is explicitly “current commit only”.

### 3. Compare against the default branch

Rejected because you explicitly chose “current commit” rather than “all changes relative to main”.

## Edge-case handling

### Initial push or missing `before`

If `github.event.before` is empty or all zeros, the workflow should fall back to diffing only the current commit contents so the run still behaves deterministically.

### Root commit on workflow_dispatch

If `HEAD` has no parent, the workflow should fall back to treating files introduced by `HEAD` as the changed set.

### Dockerfile changed but missing `# image_name:`

That Dockerfile should be skipped, matching the existing workflow behavior.

### Dockerfile unchanged but dependent files changed

The workflow should not rebuild in this optimization. The rule is strictly based on changed `Dockerfile` paths, not broader build context changes.

## Files to modify during implementation

- Modify: `.github/workflows/docker-build-push.yml`
- No changes required to: `claude/Dockerfile`

## Success criteria

- A push run builds only Dockerfiles changed in the pushed commit range.
- A manual run builds only Dockerfiles changed in the current commit.
- The existing runtime `# image_name:` resolution still works.
- The manifest format remains unchanged.
- Login/build/push steps are skipped cleanly when no Dockerfile changed.
