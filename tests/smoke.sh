#!/usr/bin/env bash
# Smoke test: run inside the image (privileged, for the podman build check).
set -euxo pipefail

for tool in wget git zip unzip xz jq yq envsubst jsonnet kubectl oc crane which git-lfs \
            helm xmlstarlet podman just rsync http telepresence argocd skopeo sops glab; do
  command -v "$tool"
done

yq --version | grep -q mikefarah

for plugin in secrets secrets-getter secrets-post-renderer; do
  helm plugin list | grep -q "^${plugin}[[:space:]]"
done

test "$(jq -r .disable_update_warnings ~/.config/httpie/config.json)" = true

workdir=$(mktemp -d)
cp "$0" "$workdir/smoke.sh"
printf 'FROM docker.io/library/busybox:latest\nCOPY smoke.sh /\nRUN test -f /smoke.sh\n' > "$workdir/Containerfile"
podman build -t smoke "$workdir"

echo "SMOKE OK"
