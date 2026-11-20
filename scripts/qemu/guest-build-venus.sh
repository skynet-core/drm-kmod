#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
set -eu

cd /root/mesa-venus
if [ "$(sha256 -q mesa-26.2.2.tar.xz)" != \
    eeb29ca7e56cfaa8e8a79538dcf834e3b18e501c31bef5145e959ea437cc4216 ]; then
    echo 'Mesa source SHA256 mismatch' >&2
    exit 1
fi
pkg install -y meson ninja pkgconf libdrm wayland wayland-protocols \
    libX11 libxcb libxshmfence libXrandr libXfixes libXext libXdamage \
    xorgproto expat bison flex py312-mako py312-pyyaml py312-packaging \
    glslang spirv-tools evdev-proto

work=$(mktemp -d /tmp/drm-venus.XXXXXX)
trap 'rm -rf "$work"' EXIT
tar -xf mesa-26.2.2.tar.xz -C "$work"
cd "$work/mesa-26.2.2"
patch -p1 < /root/mesa-venus/mesa-venus-freebsd.patch
meson setup out --prefix=/opt/mesa-venus -Dbuildtype=release \
    -Dvulkan-drivers=virtio -Dgallium-drivers= -Dplatforms=x11,wayland \
    -Dllvm=disabled -Degl=disabled -Dglx=disabled -Dgbm=disabled \
    -Dopengl=false -Dgles1=disabled -Dgles2=disabled \
    -Dgallium-mediafoundation=disabled -Dvalgrind=disabled -Dlibunwind=disabled
ninja -C out -j "${JOBS:-16}"
DESTDIR="$work/stage" meson install -C out --no-rebuild
tar -czf /root/mesa-venus/venus.tar.gz -C "$work/stage" opt/mesa-venus
