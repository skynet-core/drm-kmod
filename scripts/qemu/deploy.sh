#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# shellcheck source=common.sh
source "$(dirname -- "$0")/common.sh"
MODE=${1:-generic}
case "$MODE" in generic|kasan|kmsan) ;; *) die 'Expected generic, kasan or kmsan' ;; esac
case "${2:-}" in
    '') REBOOT=1 ;;
    --no-reboot) REBOOT=0 ;;
    *) die 'Expected --no-reboot or no second argument' ;;
esac
[[ -f $QEMU_STATE/artifacts/$MODE.tar.gz ]] || die "Build $MODE first"
python3 "$QEMU_SCRIPTS/check_artifact.py" "$QEMU_STATE/artifacts/$MODE.tar.gz" "$MODE"
ARCHIVE_SHA256=$(python3 - "$QEMU_STATE/artifacts/$MODE.tar.gz" <<'PY'
import hashlib, sys
with open(sys.argv[1], 'rb') as stream:
    print(hashlib.file_digest(stream, 'sha256').hexdigest())
PY
)
vm_config freebsd-test
ssh_options
ssh "${SSH_OPTS[@]}" root@127.0.0.1 'cat > /tmp/drm-deploy.tar.gz' < "$QEMU_STATE/artifacts/$MODE.tar.gz"
# MODE is allowlisted above; it is intentionally expanded on the host.
# shellcheck disable=SC2029
ssh "${SSH_OPTS[@]}" root@127.0.0.1 "MODE=$MODE ARCHIVE_SHA256=$ARCHIVE_SHA256 REBOOT=$REBOOT sh -s" <<'SH'
set -eu
if [ "$(sha256 -q /tmp/drm-deploy.tar.gz)" != "$ARCHIVE_SHA256" ]; then
    echo 'Artifact checksum mismatch after upload; guest files have not been replaced' >&2
    exit 1
fi
tar -xpf /tmp/drm-deploy.tar.gz -C /
grep -qx "mode=$MODE" /build.txt
for module in dmabuf drm virtio_gpu_drm; do
    expected=$(awk -v name="$module.ko)" '{ split($2, path, "/"); if (path[2] == name) print $4 }' /build.txt)
    test -n "$expected"
    test "$(sha256 -q "/boot/modules/$module.ko")" = "$expected"
done
kldxref /boot/modules
kernel=kernel
if [ "$MODE" != generic ]; then kernel=kernel.$MODE; fi
sysrc -f /boot/loader.conf kernel="$kernel"
sysrc -f /boot/loader.conf console=comconsole
sysrc kld_list=virtio_gpu_drm
cat /build.txt
if [ "$REBOOT" = 1 ]; then
    echo 'Rebooting with virtio_gpu_drm enabled.'
    shutdown -r +0
fi
SH
