# ubuntu-with-tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `mediussi/ubuntu-with-tools`, a multi-arch Ubuntu LTS image with the same tools and podman setup as `rocky-with-tools`.

**Architecture:** A single multi-stage Dockerfile that mirrors `../rocky-with-tools/Dockerfile`: per-arch base stages set the download URLs, there is one download stage per pinned binary, and a final stage installs the rest from apt. Renovate updates the pinned versions, and a GitHub Actions workflow builds and pushes one tag per LTS version every night.

**Tech Stack:** Docker buildx, Ubuntu 26.04 apt, podman/crun, Renovate, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-17-ubuntu-with-tools-design.md`

**Reference repo:** `/home/usatko/projects/usatko/MediusINC/rocky-with-tools` (read its Dockerfile before starting).

## Global Constraints

- Ubuntu LTS only, starting at 26.04: no interim releases (26.10 and so on).
- Platforms: linux/amd64 and linux/arm64.
- apt: official Ubuntu repos only. No PPAs and no third-party repos.
- apt packages: wget git zip unzip xz-utils jq gettext-base jsonnet git-lfs xmlstarlet podman fuse-overlayfs crun rsync skopeo httpie findutils ca-certificates (keep Recommends).
- Pinned downloads: oc+kubectl, helm, helm-secrets (3 OCI plugins), sops, yq (mikefarah), crane, just, telepresence, argocd, glab. The versions, URLs and `# renovate:` comments must be byte-identical to the Rocky Dockerfile.
- Image name `mediussi/ubuntu-with-tools`, build arg `UBUNTU_VERSION`, source label `https://github.com/MediusInc/ubuntu-with-tools`.

## Review Focus

- **`yq` is the mikefarah Go build.** Apt's Python `yq` must never end up installed: `yq --version` has to mention mikefarah. (Smoke test.)
- **podman builds work inside a CI container** (privileged, host namespaces, fuse-overlayfs). A trivial `podman build` must succeed. (Smoke test.)
- **No apt prompts during the build.** Use `DEBIAN_FRONTEND=noninteractive` so tzdata and similar packages can't hang the build.
- **helm-secrets plugins are installed and verified with the keyring.** `helm plugin list` must show `secrets`, `secrets-getter` and `secrets-post-renderer`. (Smoke test.)
- **arm64 binary names differ from amd64** (oc URL, crane `x86_64` vs `arm64`, just `aarch64`). Do a buildx arm64 build if qemu is available; otherwise check the URLs against the Rocky ones line by line.

---

### Task 1: Image (Dockerfile, podman config, smoke test)

**Files:**
- Create: `tests/smoke.sh` (runs inside the image and exits non-zero on the first failure)
- Create: `Dockerfile`
- Create: `containers.conf` (identical copy of the Rocky file)
- Create: `gpg/helm-secrets.gpg` (identical copy of the Rocky file)

**Interfaces:**
- Produces: `docker buildx build . --build-arg UBUNTU_VERSION=26.04` → working image; `tests/smoke.sh` is used by Task 2's README and any CI.

- [ ] **Step 1: Write `tests/smoke.sh`** (`#!/usr/bin/env bash`, `set -euxo pipefail`):
  - For each of `wget git zip unzip xz jq yq envsubst jsonnet kubectl oc crane which git-lfs helm xmlstarlet podman just rsync http telepresence argocd skopeo sops glab`: `command -v <tool>`.
  - `yq --version | grep -q mikefarah`
  - `helm plugin list | grep -q '^secrets '`, the same for `secrets-getter` and `secrets-post-renderer`
  - `test "$(jq -r .disable_update_warnings ~/.config/httpie/config.json)" = true`
  - `printf 'FROM scratch\nCOPY smoke.sh /\n' > /tmp/Containerfile && cp "$0" /tmp/smoke.sh && podman build -t smoke /tmp`
  - Print `SMOKE OK` at the end.

- [ ] **Step 2: Run against a bare image to verify it fails**

Run: `docker run --rm -v "$PWD/tests:/t" ubuntu:26.04 bash /t/smoke.sh`
Expected: FAIL at `command -v wget`.

- [ ] **Step 3: Copy `containers.conf` and `gpg/helm-secrets.gpg` from the Rocky repo** (`cp`, unchanged).

- [ ] **Step 4: Write `Dockerfile`**, starting from the Rocky Dockerfile and changing only the following:
  - `ARG UBUNTU_VERSION=""`. Both base stages use `FROM --platform=<arch> ubuntu${UBUNTU_VERSION:+":$UBUNTU_VERSION"}`.
  - The `# renovate:` ARG block, URL ENVs, download stages and `COPY --from` lines stay as they are.
  - `LABEL org.opencontainers.image.source="https://github.com/MediusInc/ubuntu-with-tools"`. The authors label stays the same.
  - The final `RUN` uses `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` and `ENV DEBIAN_FRONTEND=noninteractive` for this stage only (set `ARG DEBIAN_FRONTEND=noninteractive` so it isn't kept in the image), then runs `apt-get update && apt-get upgrade -y && apt-get install -y <Global Constraints apt list> && apt-get clean && rm -rf /var/lib/apt/lists/*`, then the same three `helm plugin install … --keyring` commands as Rocky.
  - The httpie config `RUN` and `ADD containers.conf /etc/containers/containers.conf` are kept as they are.
  - Drop the Rocky httpie, epel and crb branching entirely.

- [ ] **Step 5: Build and run the smoke test**

Run: `docker buildx build . --load --build-arg UBUNTU_VERSION=26.04 -t ubuntu-with-tools:test && docker run --rm --privileged -v "$PWD/tests:/t" ubuntu-with-tools:test bash /t/smoke.sh`
Expected: the last line is `SMOKE OK`.

- [ ] **Step 6: arm64 build check**

Run: `docker buildx build . --platform linux/arm64 --build-arg UBUNTU_VERSION=26.04 -t ubuntu-with-tools:test-arm64` (only if `docker buildx ls` lists linux/arm64).
Expected: the build succeeds. If arm64 isn't available, say so and diff the arm64 ENV block against Rocky's (`diff <(grep -A12 'AS base-arm64' ../rocky-with-tools/Dockerfile) <(grep -A12 'AS base-arm64' Dockerfile)`). The only expected difference is the `FROM` line.

- [ ] **Step 7: Commit**

```bash
git add Dockerfile containers.conf gpg tests
git commit -m "feat: add ubuntu-with-tools image"
```

### Task 2: CI, Renovate, docs

**Files:**
- Create: `.github/workflows/build.yml` (copy from Rocky, with changes)
- Create: `renovate.json5` (identical copy)
- Create: `README.md`
- Create: `.gitignore` (`/ubuntu-with-tools.iml`)

**Interfaces:**
- Consumes: Task 1's `Dockerfile` (build arg `UBUNTU_VERSION`) and `tests/smoke.sh`.

- [ ] **Step 1: Write `build.yml`.** Same as Rocky, except `TAGS="26.04"` with a comment `# Ubuntu LTS versions only; add new LTS releases here`, `--build-arg "UBUNTU_VERSION=$tag"` and `mediussi/ubuntu-with-tools:$tag`.

- [ ] **Step 2: Copy `renovate.json5`** and write `.gitignore`.

- [ ] **Step 3: Write `README.md`.** Use the Rocky README with the Ubuntu name, the Docker Hub link `https://hub.docker.com/r/mediussi/ubuntu-with-tools/tags` and the same tool list. Add a line saying only LTS releases (26.04+) are built, and a "Testing locally" section with the Task 1 Step 5 commands.

- [ ] **Step 4: Validate**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/build.yml'))" && grep -c 'ubuntu-with-tools' .github/workflows/build.yml && diff renovate.json5 ../rocky-with-tools/renovate.json5`
Expected: no YAML error, count ≥ 2, diff is empty.

- [ ] **Step 5: Commit**

```bash
git add .github renovate.json5 README.md .gitignore
git commit -m "ci: add nightly build, renovate and README"
```
