#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Run as root in freebsd-build. Export a kernel and matching DRM modules together.
set -eu
MODE=${1:-generic}
JOBS=${JOBS:-16}
case "$MODE" in generic|kasan|kmsan) ;; *) echo 'Expected generic, kasan or kmsan' >&2; exit 1 ;; esac
test "$(id -u)" = 0
if [ ! -f /usr/src/sys/conf/kern.opts.mk ]; then
    # Cloud images update PkgBase on first boot; use its matching patched sources.
    pkg install -y -r FreeBSD-base FreeBSD-src FreeBSD-src-sys
fi
test "$(pkg query '%v' FreeBSD-src-sys)" = "$(pkg query '%v' FreeBSD-kernel-generic)"
cd /root/drm-kmod
STAGE=$(mktemp -d /tmp/drm-stage.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM
if [ "$MODE" = generic ]; then
    make -j "$JOBS" KMODS="dmabuf drm virtio" clean
    make -j "$JOBS" KMODS="dmabuf drm virtio" DEBUG_FLAGS=-g
else
    CONFIG=VIRTGPU-$(echo "$MODE" | tr '[:lower:]' '[:upper:]')
    {
        echo "include GENERIC-$(echo "$MODE" | tr '[:lower:]' '[:upper:]')"
        echo "ident $CONFIG"
    } > "/usr/src/sys/amd64/conf/$CONFIG"
    make -C /usr/src -j "$JOBS" -DNO_KERNELCLEAN buildkernel KERNCONF="$CONFIG"
    KERNBUILDDIR=/usr/obj/usr/src/amd64.amd64/sys/$CONFIG
    test -f "$KERNBUILDDIR/kernel"
    # External modules need the same option headers and instrumentation as the kernel.
    make -j "$JOBS" KMODS="dmabuf drm virtio" KERNBUILDDIR="$KERNBUILDDIR" clean
    make -j "$JOBS" KMODS="dmabuf drm virtio" KERNBUILDDIR="$KERNBUILDDIR" DEBUG_FLAGS=-g
    make -C /usr/src installkernel KERNCONF="$CONFIG" DESTDIR="$STAGE"
    mv "$STAGE/boot/kernel" "$STAGE/boot/kernel.$MODE"
    mv "$STAGE/usr/lib/debug/boot/kernel" "$STAGE/usr/lib/debug/boot/kernel.$MODE"
fi
mkdir -p "$STAGE/boot/modules"
cp dmabuf/dmabuf.ko drm/drm.ko virtio/virtio_gpu_drm.ko "$STAGE/boot/modules/"
mkdir -p "$STAGE/usr/lib/debug/boot/modules"
cp dmabuf/dmabuf.ko.debug drm/drm.ko.debug virtio/virtio_gpu_drm.ko.debug \
    "$STAGE/usr/lib/debug/boot/modules/"
{
    freebsd-version -ku
    echo "mode=$MODE"
    sha256 dmabuf/dmabuf.ko drm/drm.ko virtio/virtio_gpu_drm.ko
} > "$STAGE/build.txt"
# Do not archive the mktemp directory itself: extracting '.' would chmod guest / to 0700.
tar -czf "/tmp/drm-$MODE.tar.gz" -C "$STAGE" boot usr build.txt
echo "Artifacts: /tmp/drm-$MODE.tar.gz"
