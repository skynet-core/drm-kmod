#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Executed once as root by FreeBSD nuageinit. The public key is appended by install.sh.
set -eu
exec > /var/log/drm-qemu-init.log 2>&1
if ! pw usershow freebsd >/dev/null 2>&1; then
    pw useradd freebsd -m -s /bin/sh
fi
pw usermod freebsd -G wheel,video -w none
pw usermod root -w none
install -d -m 700 /root/.ssh /home/freebsd/.ssh
sysrc sshd_enable=YES
sysrc growfs_enable=YES
sysrc dumpdev=AUTO
cat >> /boot/loader.conf <<'LOADER'
hint.vtgpu.0.disabled="1"
autoboot_delay="1"
console="comconsole"
kern.panic_reboot_wait_time="5"
hw.dri.__drm_debug="0"
LOADER
sed -i '' -E '/^[[:space:]#]*(PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication)[[:space:]]/d' /etc/ssh/sshd_config
cat >> /etc/ssh/sshd_config <<'SSH'
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
PerSourcePenalties no
SSH
