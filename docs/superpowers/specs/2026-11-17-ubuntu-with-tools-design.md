# ubuntu-with-tools — design

Date: 2026-11-17

## Intent

Make an Ubuntu counterpart to `MediusInc/rocky-with-tools`. It is published as
`mediussi/ubuntu-with-tools` with the same tools and the same podman-in-container
behaviour, so CI pipelines can switch between the Rocky and Ubuntu images without
changes. It supports Ubuntu LTS releases from 26.04 on (26.04, 28.04, …).

## Goals

- Same tool set as rocky-with-tools (see README list), same pinned versions.
- Multi-arch image: linux/amd64 and linux/arm64.
- One image tag per Ubuntu LTS version (`26.04`, later `28.04`, …), built nightly at 03:00 and on push.
- Renovate keeps pinned binaries up to date, configured the same way as in the Rocky repo.
- Packages come from the official Ubuntu apt repos where apt has the **same tool at a usable version**.

## Non-goals

- No Ubuntu releases older than 26.04, and no interim (non-LTS) releases such as 26.10.
- No third-party apt repos or PPAs.
- No new tools beyond what rocky-with-tools ships.

## Anti-goals

- A tool that behaves differently from the Rocky image under the same name (for example Python `yq` vs Go `yq`).
- Pinned versions that drift from the Rocky image because apt lags behind.

## Approaches considered

- **A — pinned downloads for yq, glab and just; apt for everything else (picked).** The images behave the same and Renovate updates both repos the same way.
- B — apt for yq, glab and just too. Rejected: apt `yq` is the Python jq wrapper (incompatible syntax), and apt `glab` (1.53) and `just` (1.45) are far behind the pinned 1.130 and 1.59.
- C — apt for glab and just, download only yq. Rejected: older versions drift from the Rocky image.

## Package sources (checked against ubuntu:26.04)

| Source | Tools |
|---|---|
| apt (official) | wget, git, zip, unzip, xz-utils, jq, gettext-base, jsonnet, git-lfs, xmlstarlet, podman, fuse-overlayfs, crun, rsync, skopeo, httpie, findutils, ca-certificates |
| pinned download (Renovate) | oc + kubectl (OKD), helm, helm-secrets plugins, sops, yq (mikefarah), crane, just, telepresence, argocd, glab |

`which` comes from `debianutils`, which is already in the base image. httpie comes
from apt on every version, so the Rocky pip/CRB branching goes away.

## Repo layout (mirrors rocky-with-tools)

- `Dockerfile`: same structure as Rocky (ARM/AMD base stages that set URLs, one download stage per tool, final stage).
  - `ARG UBUNTU_VERSION=""` → `FROM ubuntu${UBUNTU_VERSION:+":$UBUNTU_VERSION"}`.
  - Same `# renovate:` ARG block and download URLs as Rocky.
  - Final stage: `apt-get update && apt-get upgrade -y && apt-get install -y <apt list>`, using `DEBIAN_FRONTEND=noninteractive`, then clean up apt lists and caches.
  - helm-secrets plugin install via the OCI and keyring commands Rocky uses, and the same httpie config that turns off update warnings.
  - `containers.conf` copied to `/etc/containers/containers.conf`.
  - Labels: `org.opencontainers.image.source=https://github.com/MediusInc/ubuntu-with-tools`; authors label is the same as in Rocky.
- `containers.conf`: identical copy (crun runtime, host namespaces, cgroupfs).
- `gpg/helm-secrets.gpg`: copied from Rocky.
- `renovate.json5`: identical.
- `.github/workflows/build.yml`: same as Rocky, with `TAGS="26.04"` (add new LTS versions as they come out), `--build-arg UBUNTU_VERSION=$tag` and image `mediussi/ubuntu-with-tools:$tag`. Uses the same Docker Hub secrets.
- `README.md`: Ubuntu version of the Rocky README.
- `.gitignore`: `/ubuntu-with-tools.iml`.

## Builder's calls

- apt installs keep Recommends. Podman on Ubuntu relies on recommended packages (netavark, passt, uidmap, …), and dnf on Rocky also installs weak deps by default.
- `crun` is installed explicitly because `containers.conf` names it.
- The authors label is copied from the Rocky image (same team and maintainer).

## Verification

- Build `26.04` locally for amd64 (and arm64 via buildx/qemu if it is available).
- Smoke test in each image: run each tool's `--version`, check that `yq` is mikefarah's (`yq --version` mentions mikefarah), check `helm plugin list` shows the secrets plugins, and run a `podman build` of a trivial Containerfile inside a `--privileged` container.
- The workflow is not run until the repo is pushed (Docker Hub secrets must be set on the GitHub repo).
