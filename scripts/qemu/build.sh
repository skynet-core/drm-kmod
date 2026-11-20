#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# MODE is validated below before it is passed to the remote shell.
# shellcheck disable=SC2029
# shellcheck source=common.sh
source "$(dirname -- "$0")/common.sh"
MODE=${1:-generic}
case "$MODE" in generic|kasan|kmsan) ;; *) die 'Expected generic, kasan or kmsan' ;; esac
vm_config freebsd-build
ssh_options
ssh "${SSH_OPTS[@]}" root@127.0.0.1 'mkdir -p /root/drm-kmod'
cd "$REPO"
git ls-files -co --exclude-standard -z -- . ':(exclude)scripts/qemu/results' | \
    tar --null -T - -cf - | \
    ssh "${SSH_OPTS[@]}" root@127.0.0.1 'tar -xf - -C /root/drm-kmod'
ssh "${SSH_OPTS[@]}" root@127.0.0.1 "sh /root/drm-kmod/scripts/qemu/guest-build.sh $MODE"
mkdir -p "$QEMU_STATE/artifacts"
ssh "${SSH_OPTS[@]}" root@127.0.0.1 "cat /tmp/drm-$MODE.tar.gz" > "$QEMU_STATE/artifacts/$MODE.tar.gz.part"
ARTIFACT_SHA256=$(ssh "${SSH_OPTS[@]}" root@127.0.0.1 "sha256 -q /tmp/drm-$MODE.tar.gz")
python3 - "$QEMU_STATE/artifacts/$MODE.tar.gz.part" "$ARTIFACT_SHA256" <<'PY'
import hashlib, sys
with open(sys.argv[1], 'rb') as stream:
    if hashlib.file_digest(stream, 'sha256').hexdigest() != sys.argv[2]:
        sys.exit('Artifact checksum mismatch after download')
PY
python3 "$QEMU_SCRIPTS/check_artifact.py" "$QEMU_STATE/artifacts/$MODE.tar.gz.part" "$MODE"
mv "$QEMU_STATE/artifacts/$MODE.tar.gz.part" "$QEMU_STATE/artifacts/$MODE.tar.gz"
echo "Built $QEMU_STATE/artifacts/$MODE.tar.gz"
