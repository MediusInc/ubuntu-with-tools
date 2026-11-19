# Ubuntu with tools

This is an alternative container image for [Ubuntu](https://ubuntu.com/),
extended with some basic utility tools. It has the same tool set as
[rocky-with-tools](https://github.com/MediusInc/rocky-with-tools).

Only Ubuntu LTS releases are built, starting with 26.04.

This container image is generated automatically every night at 3AM and can be pulled from [Dockerhub](
https://hub.docker.com/r/mediussi/ubuntu-with-tools/tags):

```bash
docker pull mediussi/ubuntu-with-tools:26.04
```

Installed tools:
- curl
- wget
- git
- zip
- unzip
- xz
- jq
- yq
- gettext
- jsonnet
- kubectl
- oc
- crane
- which
- git-lfs
- helm
- helm-secrets
- xmlstarlet
- podman
- just
- rsync
- httpie
- telepresence
- argocd
- skopeo
- sops
- glab

Tools available in the official Ubuntu repositories are installed with `apt`.
The rest (`oc`/`kubectl`, `helm`, `helm-secrets`, `sops`, `yq`, `crane`, `just`,
`telepresence`, `argocd`, `glab`) are pinned release downloads kept up to date
by Renovate. `yq`, `just` and `glab` are downloaded even though Ubuntu packages
them: apt's `yq` is a different tool (the Python jq wrapper), and apt's `just`
and `glab` are much older.

## Testing

CI builds each platform on a native runner (amd64 and arm64) and runs `tests/smoke.sh`
in it; the multi-arch tag is only pushed when both platforms pass.

To run it locally:

```bash
docker buildx build . --load --build-arg UBUNTU_VERSION=26.04 -t ubuntu-with-tools:test
docker run --rm --privileged -v "$PWD/tests:/t" ubuntu-with-tools:test bash /t/smoke.sh
```
