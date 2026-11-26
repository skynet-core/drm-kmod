# FreeBSD 15.2 virtio GPU qualification

This run compares the FreeBSD `releng/15.2` and `stable/15` sources available
on 2026-11-26. The release branch identified itself as 15.2-BETA3. The
final 15.2-RELEASE build was still pending. [FreeBSD 15.2 release schedule](https://www.freebsd.org/releases/15.2R/schedule/)

| Input | Release | Control |
| --- | --- | --- |
| FreeBSD source | `85ed13f7b87d8ced32742a05835e8ecc43937522` | `01111efd98158bc3f7f5d5fbb8cf12c86eb643f0` |
| Native kernel configuration | GENERIC with ident `RELENG152` | GENERIC with ident `STABLE15` |
| drm-kmod | `58f67e2067` on `releng/15.2` | `cc97bee0ab` on `virtio-gpu-nvidia`, plus the LinuxKPI compatibility change from `58f67e2067` |
| Bootstrap image | Official 15.2-BETA3 amd64 BASIC-CLOUDINIT, UFS builder and separate ZFS runtime | Official 15.2-STABLE amd64 BASIC-CLOUDINIT UFS snapshot, 2026-11-19 |
| Desktop packages | Mesa 26.2.2_1, Hyprland 0.57.2, glmark2 2023.01_2 | Same versions |

The FreeBSD 2026Q4 amd64 metaport selects `graphics/drm-612-kmod`.
Its upstream source tag is `drm_v6.12.110_1` (`1d054ae556`). The release
branch includes both that tag and the full `virtio-gpu-nvidia` history.
The shared-memory framebuffer helper uses the upstream DRM core's
framebuffer allocation and keeps deferred I/O under its Linux guard.
[Metaport selection](https://github.com/freebsd/freebsd-ports/blob/2026Q4/graphics/drm-kmod/Makefile) · [Port version](https://github.com/freebsd/freebsd-ports/blob/2026Q4/graphics/drm-612-kmod/Makefile.version)

The original control failed to compile against current `stable/15`.
Its compatibility headers redefined `dma_sync_sgtable_for_device` and
expanded the name of LinuxKPI's new `vmemdup_user` declaration. Both
kernels provide these helpers. The compatibility commit uses the
scatterlist and original entry count for DMA sync and LinuxKPI's
`memdup_user` for the FreeBSD command buffer. Only this commit was
applied to the disposable control checkout.

## Hardware rendering results

All eight OpenGL desktop cases completed the 1,000-frame pixel check and
reported direct, accelerated GLX. Both branches exposed OpenGL 4.3 on
the Radeon and 4.2 on the NVIDIA GPU, plus OpenGL ES 3.2 on both.
Hyprland reported a DRM backend and an active 1440×900 output. The table
gives the glmark2-wayland score for the same single scene in each VM.
[Guest renderer and benchmark output](opengl.txt) ·
[Radeon release screenshot](radeon.png) · [NVIDIA release screenshot](nvidia.png)

| Physical GPU | QEMU device | Stable control | Release branch |
| --- | --- | ---: | ---: |
| RTX 3090 | `virtio-vga-gl` | 1221 | 1339 |
| RTX 3090 | `virtio-gpu-gl-pci` | 1280 | 1518 |
| Radeon 610M | `virtio-vga-gl` | 772 | 801 |
| Radeon 610M | `virtio-gpu-gl-pci` | 776 | 819 |

With Venus enabled on `virtio-vga-gl`, each branch also completed 120
Vulkan GPU writes with full buffer readback on each physical GPU. The
guest reported the matching PCI vendor and device IDs and
`DRIVER_ID_MESA_VENUS` in all four runs. [Vulkan output](vulkan.txt)

The default amd64 build installed all seven DRM modules on the release
builder. The test guest booted the transferred kernel and loaded
`dmabuf.ko`, `drm.ko`, and `virtio_gpu_drm.ko` with the same SHA256 hashes
as the build outputs. [Release build record](release-build.txt) · [Control build record](control-build.txt)

## SPICE resolution and pointer motion

A SPICE client sent three monitor configurations to the release guest
on the RTX 3090 using EGL headless and `virtio-vga-gl`. With
`spice-hypr-resize 2` running, `hyprctl monitors` reported 1920×1200,
3840×2160, then 2960×1662, each at scale 2. Four absolute tablet positions
landed within one logical pixel of their expected coordinates. The first
and last input, (320, 240), both produced (159, 119) in Hyprland.
[Requested and observed values](spice.json)

With the guest at 2960×1662, Xwayland glmark2 ran the same seven-second
800×600 `build:use-vbo=false` scene twice. It reported 0.857 ms per frame
with the pointer still and 0.851 ms while the client queued 431 tablet
positions. The capture timestamps each SPICE display invalidation
rectangle and outgoing position relative to the start of its trial.
Several rectangles can describe one displayed frame. The fresh session
started Hyprland directly. The SDDM greeter and the black X reported in
virt-manager require a separate visual check. [Timestamped events (CSV, gzip)](spice-events.csv.gz)

## Reproduce the build

In a fresh guest, put the pinned FreeBSD source in `/usr/src` and check
out the corresponding driver revision. For the control, apply
`git cherry-pick 58f67e2067` in a disposable checkout of `cc97bee0ab`.
The following guest commands use the release configuration. Substitute
`STABLE15` and `kernel.stable15` for the control.

```sh
config=RELENG152
kernel_dir=kernel.releng152
printf 'include GENERIC\nident %s\n' "$config" > "/usr/src/sys/amd64/conf/$config"
make -C /usr/src -j14 buildkernel KERNCONF="$config" WITHOUT_KERNEL_SYMBOLS=yes
make -C /usr/src installkernel KERNCONF="$config" INSTKERNNAME="$kernel_dir" WITHOUT_KERNEL_SYMBOLS=yes

# From the drm-kmod checkout
obj="/usr/obj/usr/src/amd64.amd64/sys/$config"
make -j10 SYSDIR=/usr/src/sys KERNBUILDDIR="$obj"
make install SYSDIR=/usr/src/sys KERNBUILDDIR="$obj"
```

For the original control, add `KMODS="dmabuf drm virtio"` to the two
external-module commands to reproduce its build scope. Install the
kernel, its base modules, and the matching external module set together.
Select the named kernel directory in `/boot/loader.conf`, disable the
base `vtgpu` framebuffer as described in the QEMU guide, and load
`virtio_gpu_drm` at boot. Verify `sysctl kern.ident kern.bootfile` and
`kldstat` after reboot.

During bootstrap, the stock BETA3 UFS kernel panicked in
`ffs_nodealloccg` during package extraction before loading the external
driver. The builder's filesystem was repaired, the pinned source archive
was checked and extracted again, and a clean object directory was used
for the release build. The graphics runtime used a separately provisioned
ZFS guest.

## Reproduce the graphics checks

QEMU 11.1.3 ran with KVM, q35, OVMF, EGL headless, a USB tablet, 14 vCPUs,
and 16 GiB of guest RAM. Select one host render node and one device model
per boot. This host mapped `renderD128` to the Radeon 610M (`1002:13c0`)
and `renderD129` to the RTX 3090 (`10de:2204`). Both appeared at
`/dev/dri/renderD128` inside the guest.

In a terminal inside Hyprland, run the same shader readback, GLX query,
and native Wayland benchmark for each combination.

```sh
cc -Wall -Wextra -Werror scripts/qemu/render-smoke.c -o /tmp/render-smoke \
    $(pkgconf --cflags --libs egl gbm glesv2)
/tmp/render-smoke /dev/dri/renderD128
hyprctl monitors
glxinfo -B
glmark2-wayland --size 640x480 -b build:use-vbo=true:duration=3
```

The readback test checks every pixel in 1,000 alternating 32×32 shader
draws. GLX queries Xwayland and glmark2 opens a native Wayland surface.
The benchmark scores come from a single three-second scene. Use the
renderer, hardware-acceleration flag, and readback result to repeat the
functional comparison.

For the Vulkan checks, use the [Venus setup](../README.md#hardware-vulkan-with-venus)
and select the host ICD for the same physical GPU as the render node.
Both guests used the same Mesa 26.2.2 Venus ICD built in the release
runtime. Inside the guest, select that ICD and run the buffer test.

```sh
export VK_DRIVER_FILES=/opt/mesa-venus/share/vulkan/icd.d/virtio_icd.x86_64.json
vulkaninfo --summary
cc -Wall -Wextra -Werror -I/usr/local/include -L/usr/local/lib \
    scripts/qemu/vulkan-smoke.c -lvulkan -o /tmp/vulkan-smoke
/tmp/vulkan-smoke
```

These runs covered GENERIC, Hyprland, Xwayland, and Vulkan buffer
readback. The earlier 15.1 sanitizer and Plasma results are documented
separately in the QEMU guide.
