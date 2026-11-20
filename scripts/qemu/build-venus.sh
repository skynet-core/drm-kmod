#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# shellcheck source=common.sh
source "$(dirname -- "$0")/common.sh"

image=mesa-26.2.2.tar.xz
mkdir -p "$QEMU_STATE/cache" "$QEMU_STATE/artifacts"
if [[ ! -f $QEMU_STATE/cache/$image ]]; then
    curl -fL --retry 3 -o "$QEMU_STATE/cache/$image.part" \
        "https://archive.mesa3d.org/$image"
    mv "$QEMU_STATE/cache/$image.part" "$QEMU_STATE/cache/$image"
fi
vm_config freebsd-build
ssh_options
ssh "${SSH_OPTS[@]}" root@127.0.0.1 'mkdir -p /root/mesa-venus'
tar -cf - -C "$QEMU_STATE/cache" "$image" -C "$QEMU_SCRIPTS" mesa-venus-freebsd.patch guest-build-venus.sh | \
    ssh "${SSH_OPTS[@]}" root@127.0.0.1 'tar -xf - -C /root/mesa-venus'
ssh "${SSH_OPTS[@]}" root@127.0.0.1 'sh /root/mesa-venus/guest-build-venus.sh'
digest=$(ssh "${SSH_OPTS[@]}" root@127.0.0.1 'sha256 -q /root/mesa-venus/venus.tar.gz')
artifact=$QEMU_STATE/artifacts/venus.tar.gz
ssh "${SSH_OPTS[@]}" root@127.0.0.1 'cat /root/mesa-venus/venus.tar.gz' > "$artifact.part"
printf '%s  %s\n' "$digest" "$artifact.part" | sha256sum -c
mv "$artifact.part" "$artifact"
echo "Built $artifact"
