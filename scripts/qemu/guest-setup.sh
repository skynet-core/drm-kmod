#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Install the test desktops as root; load the module after deployment and reboot.
set -eu
pkg install -y mesa-dri mesa-demos glmark2 drm_info pkgconf vulkan-tools vulkan-headers \
    hyprland plasma6-plasma-desktop plasma6-plasma-workspace \
    plasma6-kwin plasma6-kwin-x11 plasma6-plasma-integration-qt6 \
    plasma6-kactivitymanagerd \
    konsole foot xorg-server xinit xauth \
    dbus seatd dejavu python3
sysrc dbus_enable=YES seatd_enable=YES
pw usermod freebsd -G wheel,video
sysctl kern.evdev.rcpt_mask=12
if ! grep -q '^kern.evdev.rcpt_mask=' /etc/sysctl.conf; then
    echo 'kern.evdev.rcpt_mask=12' >> /etc/sysctl.conf
fi
service dbus start || service dbus status
service seatd start || service seatd status
test -e /usr/local/lib/dri/virtio_gpu_dri.so
echo 'Desktop packages ready. Deploy modules and reboot before starting a session.'
