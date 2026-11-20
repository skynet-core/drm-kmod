# Radeon and NVIDIA virtio GPU validation

A separate [Vulkan and OpenGL report](venus.md) covers Venus and virgl
together on the updated driver.

The 2026-11-19 classic virgl baseline had **24 passing OpenGL/GLES desktop
cases**, covering two host GPUs,
two QEMU device models, three desktops and two FreeBSD kernel sanitizers.
These are captures of running guests through QEMU VNC, accompanied by
renderer reports, compositor information and kernel logs.

## Environment and checks

| Component | Tested configuration |
|---|---|
| Host | Fedora 45, Linux 7.3.4-300.fc45.x86_64, Ryzen 9 9950X3D |
| Radeon | Radeon 610M / Granite Ridge, PCI 1002:13c0, amdgpu, host `/dev/dri/renderD128` |
| NVIDIA | GeForce RTX 3090, PCI 10de:2204, nvidia, host `/dev/dri/renderD129` |
| QEMU | 11.1.3, KVM/q35, OVMF, EGL-headless, explicit host render node |
| Guests | Official FreeBSD 15.1 amd64 BASIC-CLOUDINIT UFS image, updated to 15.1-RELEASE-p7 |
| Test VM | 8 vCPUs, 16 GB RAM; separate build VM with 16 vCPUs / 16 GB |
| Userspace | Mesa 26.2.2, Hyprland 0.56.2 / Aquamarine 0.15.1, KWin 6.7.5 |
| Kernels | Stock GENERIC-KASAN and GENERIC-KMSAN configurations with matching external modules |

`virtio-gpu-gl` is the QEMU alias of `virtio-gpu-gl-pci`. Each model was
started with `-vga none`. The guest render node was `/dev/dri/renderD128`
for both host renderers. Radeon reported virgl / OpenGL 4.3; NVIDIA reported
virgl / OpenGL 4.2. Both exposed OpenGL ES 3.2 and hardware acceleration.

For each case, `render-smoke.c` compiled shaders, drew 1,000 alternating
frames into a 32×32 texture, and checked every pixel read back. The test
rejects software renderer strings. glmark2 ran in the desktop alongside
the visible verification terminal. KWin reported active OpenGL compositing;
Hyprland reported its DRM backend and GLES 3.2. The KMSAN run also saved
Aquamarine's native virgl renderer log. No KASAN/KMSAN, panic or lock-order
diagnostics appeared in the collected successful-case kernel logs.

The kernels and all three DRM modules were built together with the same
option headers. Symbol inspection confirmed `__asan_*` references in the
KASAN module and `__msan_*` references in the KMSAN module. See
[instrumentation and module hashes](instrumentation.json). A generic
module build also succeeded; the complete desktop matrices used the two
instrumented kernels.

## Classic virgl baseline coverage

| Path | Result / coverage |
|---|---|
| GLX on X11 / Xwayland | Hardware virgl reported on both host GPUs |
| GBM/EGL surfaceless GLES | Shader draw and full readback passed in all 24 cases |
| Wayland EGL applications | glmark2-wayland ran under Hyprland and Plasma |
| Desktop compositing | Hyprland DRM/GLES and KWin OpenGL were active |
| OpenGL 4.2 / 4.3, GLES 3.2 | Reported versions; full version conformance was not tested |
| Vulkan / Venus | The classic virgl baseline enumerated only a CPU device in all four node/device probes |
| Full Khronos CTS / Piglit, memory pressure, reset recovery | Not run |

The [historical Vulkan probes](vulkan-probe/README.md) record
`PHYSICAL_DEVICE_TYPE_CPU` and `llvmpipe` before the guest driver and
Mesa ICD gained Venus support. Hardware Vulkan requires explicit
blob/hostmem/Venus configuration. See [Mesa's requirements](https://docs.mesa3d.org/drivers/venus.html)
and the [QEMU device documentation](https://www.qemu.org/docs/master/system/devices/virtio/virtio-gpu.html).

## KASAN screenshots: 12 / 12

| Host renderer / QEMU device | Hyprland Wayland | Plasma Wayland | Plasma X11 |
|---|---|---|---|
| Radeon / virtio-gpu-gl | [PNG](kasan-20261119T203537Z/renderD128-virtio-gpu-gl-hyprland.png) | [PNG](kasan-20261119T203537Z/renderD128-virtio-gpu-gl-plasma-wayland.png) | [PNG](kasan-20261119T203537Z/renderD128-virtio-gpu-gl-plasma-x11.png) |
| Radeon / virtio-vga-gl | [PNG](kasan-20261119T203537Z/renderD128-virtio-vga-gl-hyprland.png) | [PNG](kasan-20261119T203537Z/renderD128-virtio-vga-gl-plasma-wayland.png) | [PNG](kasan-20261119T203537Z/renderD128-virtio-vga-gl-plasma-x11.png) |
| NVIDIA / virtio-gpu-gl | [PNG](kasan-20261119T203537Z/renderD129-virtio-gpu-gl-hyprland.png) | [PNG](kasan-20261119T203537Z/renderD129-virtio-gpu-gl-plasma-wayland.png) | [PNG](kasan-20261119T203537Z/renderD129-virtio-gpu-gl-plasma-x11.png) |
| NVIDIA / virtio-vga-gl | [PNG](kasan-20261119T203537Z/renderD129-virtio-vga-gl-hyprland.png) | [PNG](kasan-20261119T203537Z/renderD129-virtio-vga-gl-plasma-wayland.png) | [PNG](kasan-20261119T203537Z/renderD129-virtio-vga-gl-plasma-x11.png) |

[Pass records](kasan-20261119T203537Z/passes.txt) ·
[Independent verification and screenshot hashes](kasan-20261119T203537Z/verified.json)

## KMSAN screenshots: 12 / 12

| Host renderer / QEMU device | Hyprland Wayland | Plasma Wayland | Plasma X11 |
|---|---|---|---|
| Radeon / virtio-gpu-gl | [PNG](kmsan-20261119T205249Z/renderD128-virtio-gpu-gl-hyprland.png) | [PNG](kmsan-20261119T205249Z/renderD128-virtio-gpu-gl-plasma-wayland.png) | [PNG](kmsan-20261119T205249Z/renderD128-virtio-gpu-gl-plasma-x11.png) |
| Radeon / virtio-vga-gl | [PNG](kmsan-20261119T205249Z/renderD128-virtio-vga-gl-hyprland.png) | [PNG](kmsan-20261119T205249Z/renderD128-virtio-vga-gl-plasma-wayland.png) | [PNG](kmsan-20261119T205249Z/renderD128-virtio-vga-gl-plasma-x11.png) |
| NVIDIA / virtio-gpu-gl | [PNG](kmsan-20261119T205249Z/renderD129-virtio-gpu-gl-hyprland.png) | [PNG](kmsan-20261119T205249Z/renderD129-virtio-gpu-gl-plasma-wayland.png) | [PNG](kmsan-20261119T205249Z/renderD129-virtio-gpu-gl-plasma-x11.png) |
| NVIDIA / virtio-vga-gl | [PNG](kmsan-20261119T205249Z/renderD129-virtio-vga-gl-hyprland.png) | [PNG](kmsan-20261119T205249Z/renderD129-virtio-vga-gl-plasma-wayland.png) | [PNG](kmsan-20261119T205249Z/renderD129-virtio-vga-gl-plasma-x11-under-load.png) |

The last X11 link is an additional capture after transfer stress and the
benchmark window-placement correction. Its original matrix capture is
also retained.

[Pass records](kmsan-20261119T205249Z/passes.txt) ·
[Independent verification and screenshot hashes](kmsan-20261119T205249Z/verified.json)

Each screenshot's sibling `.txt`, `-compositor.log`, `-session.log` and
`-dmesg.log` record the renderer/readback result, native compositor,
session startup and kernel diagnostics. Each device also has a
`-boot.txt` with kernel identity, module hashes, loaded modules and queue
state. The independent verification checked all 24 reports and kernel
logs, compositor information, image dimensions and image hashes.

## Fixes and test tooling

The FreeBSD PCI shim now retains the complete PCI class/subclass and
recognizes VGA devices. The PCI framebuffer quirk runs for the shim's PCI
parent, allowing the VGA device to release its conflicting framebuffer.
The capset bitmask uses a 64-bit shift, matching its allowed capset IDs.

The VM helpers install both guests, configure key-only root/user SSH and
passwordless wheel sudo, build matching kernels/modules, select render
nodes, deploy verified artifacts, launch desktops on an active VT, and
capture the matrix. Testing also corrected SSH host-key initialization,
archive root permissions, retained QEMU PID handling, Plasma dependencies,
KWin device discovery, session cleanup and benchmark placement.

Reproduce using the commands in [the helper README](../README.md).
`shellcheck -P scripts/qemu scripts/qemu/*.sh`, Python compilation and
the seven helper regression tests pass. The GLES test compiles in the
guest with `-Wall -Wextra -Werror`.

## Failed attempts and remaining limits

- The [earlier partial KASAN run](kasan-20261119T203058Z/README.md) predates
  the Plasma activity-manager dependency fix and is excluded from the
  final 24 cases.
- An initial custom KASAN+KUBSAN kernel faulted in the base kernel's early
  diagnostic output before the DRM driver loaded. It is excluded from
  coverage. The successful runs use the stock KASAN and KMSAN configurations;
  this report does not claim KUBSAN coverage.
- The KASAN runner completed and recorded all 12 cases, but its final
  summary command failed because the running script was edited. The saved
  evidence was independently checked for all 12 cases. The final KMSAN
  runner completed normally with exit status zero.
- One initial KMSAN archive upload under the KASAN/NVIDIA workload arrived
  with two changed bits. Its cause remains unknown. That deployment and
  subsequent module-load failure are excluded from coverage. Deployment
  now verifies the received archive SHA256 before extraction and verifies
  each installed module against its build manifest. Downloads from the
  builder also check SHA256. Twelve repeated 403 MiB transfers under active
  NVIDIA/Plasma X11 3D load matched exactly: six with
  [KMSAN](transfer-integrity.json) and six with
  [KASAN](transfer-integrity-kasan.json). The anomaly did not recur;
  these checks do not establish its root cause. See the
  [incident record](transfer-incident.json).
- The minimal desktop fixture emits optional portal/audio service warnings;
  those services were not configured or tested. Hyprland warns that its
  `.conf` format will be removed in 0.57. Its test fixture targets 0.56.
- This baseline establishes classic virgl OpenGL/GLES on these two GPUs
  and this software stack. Multi-head, hot-unload and long-duration
  stability are outside this run.
