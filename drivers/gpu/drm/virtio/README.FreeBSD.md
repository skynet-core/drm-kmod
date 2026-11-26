# virtio-gpu DRM driver for FreeBSD

A port of Linux's `drivers/gpu/drm/virtio/` paravirtual display driver
into the drm-kmod framework, for FreeBSD 15.1 guests under QEMU/UTM
with a virtio GPU device. Developed on aarch64 (Apple-silicon UTM,
QEMU/hvf), and tested on amd64 QEMU/KVM with Radeon and NVIDIA renderers.

The driver supports atomic KMS, dumb buffers, the framebuffer console,
and PRIME self-import. QEMU GL devices can expose OpenGL/GLES through
virgl and Vulkan through Venus. Venus uses resource blobs, a host-visible
PCI memory window and context initialization. Multi-head is out of scope.

Upstream base: Linux v6.12 driver sources against drm-kmod
`drm_v6.12.85_2` (DRM core 6.12.85).  The upstream `virtgpu_*.c` files
carry minimal, commented diffs; all FreeBSD-specific code lives in
separate files (see Architecture).

For reproducible amd64 development VMs, explicit Radeon/NVIDIA host render
node selection, `virtio-gpu-gl-pci` / `virtio-vga-gl` runs, sanitizer builds
and desktop capture helpers, see [scripts/qemu](../../../../scripts/qemu/README.md).
The [amd64 test report](../../../../scripts/qemu/results/README.md) includes
KASAN/KMSAN logs and real Hyprland and Plasma Wayland/X11 screenshots for
both host renderers and both GL device models.

## Build

Requirements: `/usr/src` matching the running kernel, drm-kmod checkout.

```sh
cd ~/src/drm-kmod
make SYSDIR=/usr/src/sys -C dmabuf
make SYSDIR=/usr/src/sys -C drm
make SYSDIR=/usr/src/sys -C virtio      # -> virtio/virtio_gpu_drm.ko
```

Note: BSD make does not rebuild on CFLAGS changes — `make clean` first
when switching options.

## Install on a guest

The base `vtgpu(4)` framebuffer driver is compiled into GENERIC and
claims the device at boot.  Disable it and let this driver take over:

1. `/boot/loader.conf`:

   ```
   hint.vtgpu.0.disabled="1"
   ```

   (Console falls back to `vt_efifb` until the module loads, then
   hands off to `vt_drmfb`.)

   No interrupt tunable is needed.  The driver is purely
   interrupt-driven, like every other virtio driver.  (On FreeBSD
   under UTM/hvf, MSI/MSI-X is not allocated for any PCI device — a
   firmware/IORT quirk unrelated to this driver — so every device,
   this one included, runs on shared wired INTx, which delivers
   completions correctly.)

2. Copy `dmabuf.ko`, `drm.ko`, `virtio_gpu_drm.ko` to the guest
   (e.g. `/usr/local/kmods`).

3. `/etc/rc.conf`:

   ```
   kld_list="/path/to/dmabuf.ko /path/to/drm.ko /path/to/virtio_gpu_drm.ko"
   seatd_enable="YES"
   ```

   With the modules in `/boot/modules`, use `kld_list="virtio_gpu_drm"`
   in `/etc/rc.conf` or `virtio_gpu_drm_load="YES"` in `/boot/loader.conf`.
   Module dependencies load `dmabuf.ko` and `drm.ko` automatically. The
   driver registers with newbus after DRM core initialization. From any
   other directory, list all three absolute paths in `kld_list` as above.

4. If `/dev/dri/card0` is missing and the `vtgpu` hint disabled the newbus
   child, re-enable it after loading the module:

   ```sh
   devctl enable vtgpu0
   ```

After reboot: `/dev/dri/card0` exists, the console is on the DRM
framebuffer, and `drm_info` enumerates the connector/modes.

On plain QEMU (non-UTM), configure the display as `-vga virtio`
rather than a bare `-device virtio-gpu-pci`: with the latter, QEMU
also instantiates its default std-VGA device and X picks the wrong
one as primary.

Manual load (same order, then `devctl enable vtgpu0`) works too.
DRM device-node teardown is not survivable on drm-kmod, so the driver
**refuses to unload once attached**: `kldunload` (and `devctl detach`)
return EBUSY — reboot to unload.  A FAILED kldload also requires a
reboot before retrying (stale driver registration).

## Running sway

```sh
mkdir -p /tmp/xdg && chmod 700 /tmp/xdg
env XDG_RUNTIME_DIR=/tmp/xdg WLR_RENDERER=pixman LIBSEAT_BACKEND=seatd sway
```

`WLR_RENDERER=pixman` is required only on a plain (non-GL) host
device, where the render node has no accelerated driver behind it and
wlroots' default EGL path cannot allocate buffers.  With a virgl
host device (see below) sway runs on its default GLES2 renderer and
the variable can be dropped.

Confirmed working: sway + swaybar + swaybg render, foot opens, keyboard
input works, `grim` screencopy works, live mode switching and custom
modes work.

HiDPI on a Mac host (UTM): enable the display's "Retina Mode" (maps
guest pixels 1:1 to panel pixels), keep the UTM window at its normal
point size, and let the guest render at 2x in `~/.config/sway/config`:

```
output Virtual-1 mode --custom 2560x1600@60Hz
output Virtual-1 scale 2
```

(2x the window's point size — or 2x the Mac's "looks like" resolution
when running fullscreen.  UTM does not push window-size changes to
plain virtio-gpu-pci, so the resolution is chosen guest-side.  Also
raise the default fonts, which read tiny at this density: foot.ini
`font=monospace:size=12` and sway `font pango:DejaVu Sans 11`.)

## 3D acceleration

If the host display device offers `VIRTIO_GPU_F_VIRGL`, the driver
negotiates it. Mesa's virgl driver
(`virtio_gpu_dri.so`, in `graphics/mesa-dri`) renders through the
host GPU, and sway runs on its default GLES2 renderer with no
environment overrides.

Host side: UTM — enable the GPU-accelerated display device
(`virtio-gpu-gl-pci`); plain QEMU — `-vga none -device virtio-gpu-gl-pci` (or
`-vga none -device virtio-vga-gl`) with virglrenderer support built
in.  On a host without virgl the feature simply does not negotiate
and the driver behaves exactly as the 2D configuration.

Verified under UTM on Apple silicon (virglrenderer over ANGLE/Metal):
`eglinfo` reports `virgl (ANGLE (Apple, ... Metal))`, `kmscube` runs
at several hundred fps, and the 2D paths (console, kmstest, dumb
buffers) are unaffected with 3D active.  Note the GL device model
shows up with a larger control ring (256 vs 64 slots).

For Vulkan, enable QEMU's Venus and blob properties and allocate a
host memory window. The FreeBSD shim only negotiates blob support after
reserving a valid shared-memory BAR. Install the native Mesa Venus ICD
in the guest and select the Vulkan ICD corresponding to the host render
node. The [QEMU helpers](../../../../scripts/qemu/README.md#hardware-vulkan-with-venus)
build the guest ICD and configure these settings on Linux hosts.

## Architecture

Two-translation-unit shim — both kernels define `struct virtqueue`, so
no single file may see both:

- `drivers/gpu/drm/virtio/virtgpu_freebsd.c` — FreeBSD-native newbus
  virtio child driver (`BUS_PROBE_VENDOR`, outranks vtgpu).  Owns the
  virtio 1.x status ladder for kldload-time attach, virtqueue
  allocation and interrupt arming, and its own notify-window mapping.
- `drivers/gpu/drm/virtio/linux_virtio.c` — the Linux virtio API
  surface (`virtqueue_add_sgs`, `virtqueue_get_buf`, kicks,
  `virtio_find_vqs`, shim `virtio_device`).  Talks to the native TU
  only through the opaque wrappers in `freebsd/virtgpu_freebsd.h`.
- `drivers/gpu/drm/virtio/freebsd/linux/*.h` — include-path-override
  shim headers (virtio core, config space access, dma-buf export).
- `drivers/gpu/drm/drm_gem_shmem_helper.c`, `drm_fbdev_shmem.c`,
  `drm_format_helper.c`, `drm_simple_kms_helper.c` — DRM-core pieces
  virtio needs that drm-kmod did not build; ported/enabled from Linux
  6.12 under their upstream licenses (the tree already builds
  GPL-2.0 helpers such as drm_writeback.c and sync_file.c).

Platform quirks the driver works around:

- vtpci's boot-created notify sub-map faults on UTM/QEMU-hvf — the
  driver maps the notify window itself and never calls
  `virtqueue_notify(9)`.
- FreeBSD virtqueues are created with interrupts disabled and native
  drivers arm them explicitly; Linux vrings start enabled.  The glue
  bridges this by calling virtqueue_enable_intr() at setup — without
  it no completion interrupt is ever delivered.
- FreeBSD allocates no MSI-X for any PCI device under UTM/hvf (QEMU
  exposes an ITS IORT node on this GICv2-only machine and the ACPI
  PCI host prefers IORT over the GICv2m fallback — unrelated to this
  driver), so the device runs on shared wired INTx like the guest's
  other virtio devices.
- Physically-contiguous segments must not coalesce across the
  device-readable/device-writable boundary (upstream's inline command
  responses); the shim's flattener enforces the split.

Diagnostics: `sysctl dev.virtio_gpu_drm.0.{reaps,queue_state}`.

## Files

| Path | Role |
|---|---|
| `virtio/Makefile` | kmod build (`virtio_gpu_drm.ko`) |
| `drivers/gpu/drm/virtio/virtgpu_*.c,h` | upstream driver, minimal diff |
| `drivers/gpu/drm/virtio/virtgpu_freebsd.c` | native attach/transport TU |
| `drivers/gpu/drm/virtio/linux_virtio.c` | Linux virtio API shim TU |
| `drivers/gpu/drm/virtio/freebsd/` | shim headers + cross-TU contract |
