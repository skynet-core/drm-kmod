# FreeBSD hardware Vulkan and OpenGL validation

**24 desktop cases passed with the repaired ICD.** Both host render nodes
and both QEMU devices passed OpenGL and hardware Vulkan under KASAN and
KMSAN in Hyprland Wayland, Plasma Wayland and Plasma X11.

The 2026-11-20 run uses FreeBSD 15.1-RELEASE-p7 with stock KASAN and KMSAN
kernel configurations. QEMU 11.1.3 runs with KVM and virglrenderer 1.3.0.
The guest runs Mesa virgl and a native Mesa 26.2.2 Venus ICD.

| Host render node | GPU | Vulkan driver selected by QEMU |
|---|---|---|
| `/dev/dri/renderD128` | AMD Radeon 610M, PCI 1002:13c0 | RADV |
| `/dev/dri/renderD129` | NVIDIA GeForce RTX 3090, PCI 10de:2204 | NVIDIA 620.70.06 |

Both `virtio-gpu-gl` (the alias of `virtio-gpu-gl-pci`) and
`virtio-vga-gl` expose the Venus capset, context initialization, resource
blobs and a 4 GiB host-visible aperture. The tests select only the guest
Venus ICD and verify the expected hardware vendor.
Both GPUs reported Vulkan 1.4.334 and OpenGL ES 3.2.
Radeon reported OpenGL 4.6 and NVIDIA reported OpenGL 4.2.

Each desktop case checks 1,000 OpenGL ES shader draws with full pixel
readback, 120 Vulkan GPU writes with full readback through mapped memory,
and 120 shader-rendered Vulkan cube frames presented through native Wayland
or XCB. The captures show the running cube and test report. The compositor,
renderer, kernel diagnostics, and matching module hashes accompany each
image. See [instrumentation and build hashes](venus-instrumentation.json).

The shared-memory window is reserved and bounds-checked before negotiating
blob support. The port also handles unaligned LinuxKPI command buffers,
correctly initializes new DMA fence chains, and fixes FreeBSD-specific
Wayland clock and thread ID handling in Mesa. The first two issues exposed
by the Vulkan workload caused lost submissions and premature timeline
completion. The Mesa thread ID defect stalled asynchronous presentation.
The tests use the repaired paths with timeline synchronization and
asynchronous presentation enabled.

NVIDIA EGL imported PRIME images with a 32-byte row alignment even when
Mesa passed a different stride. The Mesa patch sets that alignment when
Venus detects the proprietary NVIDIA renderer. Radeon keeps the standard
alignment. The [diagnostic captures](venus-diagnostics/README.md) show the
original corruption and the repaired output at the reproducing width.

## KMSAN screenshots

All 12 cases passed with the repaired ICD. The runner completed with exit
status zero. The independently checked logs include the booted module and
ICD hashes, native WSI, GPU identity, readback and VK presentation results.
The screenshots were checked for the stripe pattern seen before the fix.

[Pass records](venus-kmsan-20261120T082239Z/passes.txt) ·
[Verified screenshot hashes](venus-kmsan-20261120T082239Z/verified.json) ·
[Capture checks](venus-kmsan-20261120T082239Z/capture-checks.txt)

| Renderer / QEMU device | Hyprland Wayland | Plasma Wayland | Plasma X11 |
|---|---|---|---|
| Radeon / virtio-gpu-gl | [PNG](venus-kmsan-20261120T082239Z/renderD128-virtio-gpu-gl-hyprland.png) | [PNG](venus-kmsan-20261120T082239Z/renderD128-virtio-gpu-gl-plasma-wayland.png) | [PNG](venus-kmsan-20261120T082239Z/renderD128-virtio-gpu-gl-plasma-x11.png) |
| Radeon / virtio-vga-gl | [PNG](venus-kmsan-20261120T082239Z/renderD128-virtio-vga-gl-hyprland.png) | [PNG](venus-kmsan-20261120T082239Z/renderD128-virtio-vga-gl-plasma-wayland.png) | [PNG](venus-kmsan-20261120T082239Z/renderD128-virtio-vga-gl-plasma-x11.png) |
| NVIDIA / virtio-gpu-gl | [PNG](venus-kmsan-20261120T082239Z/renderD129-virtio-gpu-gl-hyprland.png) | [PNG](venus-kmsan-20261120T082239Z/renderD129-virtio-gpu-gl-plasma-wayland.png) | [PNG](venus-kmsan-20261120T082239Z/renderD129-virtio-gpu-gl-plasma-x11.png) |
| NVIDIA / virtio-vga-gl | [PNG](venus-kmsan-20261120T082239Z/renderD129-virtio-vga-gl-hyprland.png) | [PNG](venus-kmsan-20261120T082239Z/renderD129-virtio-vga-gl-plasma-wayland.png) | [PNG](venus-kmsan-20261120T082239Z/renderD129-virtio-vga-gl-plasma-x11.png) |

The Radeon X11 run recorded the stock [device-pager WITNESS warning](venus-kmsan-20261120T082239Z/renderD128-virtio-gpu-gl-plasma-x11-dmesg.log).

## KASAN screenshots

All 12 cases passed. The runner, independent checks, and screenshot data
are included below.

[Pass records](venus-kasan-20261120T083040Z/passes.txt) ·
[Verified screenshot hashes](venus-kasan-20261120T083040Z/verified.json) ·
[Capture checks](venus-kasan-20261120T083040Z/capture-checks.txt) ·
[WITNESS reports](venus-kasan-20261120T083040Z/witness.txt)

| Renderer / QEMU device | Hyprland Wayland | Plasma Wayland | Plasma X11 |
|---|---|---|---|
| Radeon / virtio-gpu-gl | [PNG](venus-kasan-20261120T083040Z/renderD128-virtio-gpu-gl-hyprland.png) | [PNG](venus-kasan-20261120T083040Z/renderD128-virtio-gpu-gl-plasma-wayland.png) | [PNG](venus-kasan-20261120T083040Z/renderD128-virtio-gpu-gl-plasma-x11.png) |
| Radeon / virtio-vga-gl | [PNG](venus-kasan-20261120T083040Z/renderD128-virtio-vga-gl-hyprland.png) | [PNG](venus-kasan-20261120T083040Z/renderD128-virtio-vga-gl-plasma-wayland.png) | [PNG](venus-kasan-20261120T083040Z/renderD128-virtio-vga-gl-plasma-x11.png) |
| NVIDIA / virtio-gpu-gl | [PNG](venus-kasan-20261120T083040Z/renderD129-virtio-gpu-gl-hyprland.png) | [PNG](venus-kasan-20261120T083040Z/renderD129-virtio-gpu-gl-plasma-wayland.png) | [PNG](venus-kasan-20261120T083040Z/renderD129-virtio-gpu-gl-plasma-x11.png) |
| NVIDIA / virtio-vga-gl | [PNG](venus-kasan-20261120T083040Z/renderD129-virtio-vga-gl-hyprland.png) | [PNG](venus-kasan-20261120T083040Z/renderD129-virtio-vga-gl-plasma-wayland.png) | [PNG](venus-kasan-20261120T083040Z/renderD129-virtio-vga-gl-plasma-x11.png) |

## Reproduction and limits

The default guest Vulkan loader also discovers the installed hardware
Venus device. The matrix selects the Venus ICD directly and confirms its
hardware device type and vendor. See the [Radeon loader output](venus-default-loader-radeon.txt)
and [NVIDIA loader output](venus-default-loader-nvidia.txt).

The [QEMU helper README](../README.md) covers VM provisioning, kernel and
Mesa builds, and rerunning the matrix. Each PNG has sibling logs for the
Vulkan device, compositor, kernel, native session and complete proof.

No KASAN or KMSAN memory reports or kernel panics appeared in the final
runs. The FreeBSD base device pager emitted a WITNESS lock-order report
while releasing mappings. The traces are preserved and the base kernel
was left unchanged. The tests cover this FreeBSD/QEMU stack and these two
GPUs. Full Khronos conformance, other FreeBSD releases, multi-head, and
long-duration stability were outside this run.
