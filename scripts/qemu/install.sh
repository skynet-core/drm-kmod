#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Create both guests; rerunning preserves existing disks and SSH identities.
# shellcheck source=common.sh
source "$(dirname -- "$0")/common.sh"
for tool in curl xz qemu-img ssh-keygen python3 xorriso; do
    command -v "$tool" >/dev/null || die "Missing host tool: $tool"
done
umask 077
mkdir -p "$QEMU_STATE/cache"
IMAGE=FreeBSD-15.1-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2
IMAGE_SHA256=e4ca4db889f8559c9b9dfcacc70405c038476f4b6d41649b152d3809a2ed9e1f
BASE=$QEMU_STATE/cache/$IMAGE
if [[ ! -f $BASE ]]; then
    curl -fL --retry 3 --continue-at - -o "$BASE.xz" \
        "https://download.freebsd.org/releases/VM-IMAGES/15.1-RELEASE/amd64/Latest/$IMAGE.xz"
    python3 - "$BASE.xz" "$IMAGE_SHA256" <<'PY'
import hashlib, sys
with open(sys.argv[1], 'rb') as f:
    digest = hashlib.file_digest(f, 'sha256').hexdigest()
if digest != sys.argv[2]:
    sys.exit('FreeBSD image SHA256 mismatch; remove the cached .xz and retry')
PY
    xz -dc "$BASE.xz" > "$BASE.part"
    qemu-img check -f qcow2 "$BASE.part"
    mv "$BASE.part" "$BASE"
    chmod 400 "$BASE"
fi
if [[ ! -f $QEMU_STATE/id_ed25519 ]]; then
    ssh-keygen -q -t ed25519 -N '' -C drm-qemu -f "$QEMU_STATE/id_ed25519"
fi
for VM in freebsd-build freebsd-test; do
    vm_config "$VM"
    mkdir -p "$VM_DIR/seed"
    if [[ -f $VM_DIR/disk.qcow2 ]]; then
        echo "$VM already installed: $VM_DIR"
        continue
    fi
    printf 'instance-id: %s\nlocal-hostname: %s\n' "$VM" "$VM" > "$VM_DIR/seed/meta-data"
    # nuageinit accepts a shell script as user-data on the cidata filesystem.
    cat "$QEMU_SCRIPTS/guest-init.sh" > "$VM_DIR/seed/user-data"
    {
        printf 'sysrc hostname=%s\nhostname %s\n' "$VM" "$VM"
        echo "cat > /root/.ssh/authorized_keys <<'DRM_QEMU_KEY'"
        cat "$QEMU_STATE/id_ed25519.pub"
        echo DRM_QEMU_KEY
        cat <<'SH'
cp /root/.ssh/authorized_keys /home/freebsd/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys /home/freebsd/.ssh/authorized_keys
chown -R freebsd:freebsd /home/freebsd/.ssh
ssh-keygen -A
service sshd restart
env ASSUME_ALWAYS_YES=yes pkg bootstrap
pkg install -y sudo
install -d -m 750 /usr/local/etc/sudoers.d
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /usr/local/etc/sudoers.d/drm-qemu
chmod 440 /usr/local/etc/sudoers.d/drm-qemu
visudo -cf /usr/local/etc/sudoers
touch /var/db/drm-qemu-ready
SH
    } >> "$VM_DIR/seed/user-data"
    xorriso -as mkisofs -quiet -V cidata -o "$VM_DIR/seed.iso" "$VM_DIR/seed"
    qemu-img create -f qcow2 -F qcow2 -b "$BASE" "$VM_DIR/disk.qcow2" 100G
    echo "Installed $VM; SSH port $SSH_PORT, key $QEMU_STATE/id_ed25519"
done
