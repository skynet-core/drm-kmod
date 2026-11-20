#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Run as freebsd, after guest-setup.sh and loading virtio_gpu_drm.
set -eu
SESSION=${1:?expected hyprland, plasma-wayland or plasma-x11}
case "$SESSION" in hyprland|plasma-wayland|plasma-x11) ;; *) exit 1 ;; esac
cd "$HOME/drm-test"
XDG_RUNTIME_DIR=/var/run/user/$(id -u)
export XDG_RUNTIME_DIR
sudo -n install -d -o "$(id -un)" -g "$(id -gn)" -m 700 "$XDG_RUNTIME_DIR"
export LIBSEAT_BACKEND=seatd
unset LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE
# pkg-config returns compiler arguments, which must be split into words.
# shellcheck disable=SC2046
cc -Wall -Wextra -Werror render-smoke.c -o render-smoke $(pkg-config --cflags --libs egl glesv2 gbm)
if [ "${DRM_TEST_VENUS:-0}" = 1 ]; then
    cc -Wall -Wextra -Werror -I/usr/local/include -L/usr/local/lib \
        vulkan-smoke.c -o vulkan-smoke -lvulkan
fi
if [ "$SESSION" = hyprland ]; then
    export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=Hyprland
    export AQ_DRM_DEVICES=/dev/dri/card0
    # shortcut: Hyprland 0.56 supports .conf; migrate this fixture to Lua for 0.57+.
    benchmark="exec-once = glmark2-wayland --run-forever --size 640x480"
    if [ "${DRM_TEST_VENUS:-0}" = 1 ]; then
        benchmark=
    fi
    cat > hyprland.conf <<EOF
monitor = ,1440x900@60,auto,1
exec-once = foot --font=monospace:size=10 --title=GPU-verification sh $HOME/drm-test/guest-proof.sh
$benchmark
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
}
animations {
    enabled = false
}
bind = SUPER, Q, exit,
EOF
    exec dbus-run-session start-hyprland -- --config "$HOME/drm-test/hyprland.conf"
fi
mkdir -p "$HOME/.config/autostart"
kwriteconfig6 --file ksmserverrc --group General --key loginMode emptySession
cat > "$HOME/.config/kwinrulesrc" <<'RULES'
[General]
count=2
rules=gpu-proof,gpu-benchmark
[gpu-proof]
Description=GPU verification terminal
wmclass=.*konsole.*
wmclassmatch=3
position=0,0
positionrule=3
size=880,840
sizerule=3
[gpu-benchmark]
Description=GPU benchmark
title=(glmark2|[Vv]kcube).*
titlematch=3
wmclassmatch=0
position=890,150
positionrule=2
size=520,600
sizerule=3
RULES
cat > "$HOME/.config/autostart/drm-proof.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=GPU verification
Exec=konsole --separate -e sh $HOME/drm-test/guest-proof.sh
EOF
if [ "$SESSION" = plasma-wayland ]; then
    export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=KDE
    export KWIN_DRM_DEVICES=/dev/dri/card0
    BENCHMARK=glmark2-wayland
else
    export XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=KDE
    BENCHMARK=glmark2
fi
if [ "${DRM_TEST_VENUS:-0}" = 1 ]; then
    rm -f "$HOME/.config/autostart/drm-benchmark.desktop"
else
    cat > "$HOME/.config/autostart/drm-benchmark.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=GPU benchmark
Exec=$BENCHMARK --run-forever --size 640x480
EOF
fi
if [ "$SESSION" = plasma-wayland ]; then
    exec dbus-run-session ck-launch-session -- startplasma-wayland
fi
exec startx /usr/local/bin/ck-launch-session /usr/local/bin/dbus-run-session /usr/local/bin/startplasma-x11 -- :1 -nolisten tcp
