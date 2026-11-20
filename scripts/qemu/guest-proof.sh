#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Run inside a visible terminal in the desktop being tested.
set -eu
cd "$HOME/drm-test"
printf '\033[H\033[2J'
{
echo 'FreeBSD virtio GPU acceleration verification'
date -u
cat /tmp/drm-case.txt
uname -v
printf '\nSession: %s\n\n' "$XDG_SESSION_TYPE"
glxinfo -B | grep -E 'direct rendering:|Device:|Accelerated:|OpenGL.*(vendor|renderer|version) string:'
./render-smoke
if [ "${DRM_TEST_VENUS:-0}" = 1 ]; then
    export VK_DRIVER_FILES=/opt/mesa-venus/share/vulkan/icd.d/virtio_icd.x86_64.json
    # Force the Venus ICD and check that its device is hardware-backed.
    timeout -k 2 30 vulkaninfo --summary > vulkan.log 2>&1
    grep -E 'deviceType.*PHYSICAL_DEVICE_TYPE_(INTEGRATED|DISCRETE)_GPU' vulkan.log
    grep -E 'deviceName.*Virtio-GPU Venus' vulkan.log
    timeout -k 2 30 ./vulkan-smoke
    if [ "$XDG_SESSION_TYPE" = wayland ]; then wsi=wayland; else wsi=xcb; fi
    timeout -k 2 45 vkcube --wsi "$wsi" --c 120 --width 500 --height 500 >> vulkan.log 2>&1
    echo "PASS: 120 Vulkan cube frames presented via $wsi"
    vkcube --wsi "$wsi" --width 500 --height 500 >> vulkan.log 2>&1 &
fi
if [ "$XDG_CURRENT_DESKTOP" = KDE ]; then
    qdbus6 org.kde.KWin /KWin supportInformation > "$HOME/drm-test/compositor.log"
else
    hyprctl systeminfo > "$HOME/drm-test/compositor.log"
    grep -aE 'Using: OpenGL|Vendor:|Renderer:' \
        "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log" >> "$HOME/drm-test/compositor.log"
fi
echo 'Desktop and GPU test logs: ~/drm-test/'
} > "$HOME/drm-test/proof.log" 2>&1
cat "$HOME/drm-test/proof.log"
sleep 86400
