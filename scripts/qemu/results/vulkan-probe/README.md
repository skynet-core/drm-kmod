# Vulkan enumeration before the Venus port

All four combinations were booted with the original KASAN kernel,
classic virgl configuration and Mesa 26.2.2. `vulkaninfo --summary` ran as
the unprivileged `freebsd` user. These are negative availability probes;
no hardware Vulkan draw or presentation test passed.

| Host render node | QEMU device | Guest Vulkan result |
|---|---|---|
| Radeon renderD128 | virtio-gpu-gl | [CPU llvmpipe](renderD128-virtio-gpu-gl.txt) |
| Radeon renderD128 | virtio-vga-gl | [CPU llvmpipe](renderD128-virtio-vga-gl.txt) |
| NVIDIA renderD129 | virtio-gpu-gl | [CPU llvmpipe](renderD129-virtio-gpu-gl.txt) |
| NVIDIA renderD129 | virtio-vga-gl | [CPU llvmpipe](renderD129-virtio-vga-gl.txt) |

Each log includes the host/device label, kernel version, negotiated
features/capsets, installed Vulkan ICD filenames and enumeration output.
The guest had Intel, Radeon and lavapipe ICDs, and lacked a Venus ICD.
The original kernel shim did not expose blob resources, host-visible
memory or context initialization.

Reproduce after booting each node/device combination:

```sh
scripts/qemu/ssh.sh freebsd-test \
    'XDG_RUNTIME_DIR=/var/run/user/$(id -u) vulkaninfo --summary'
```

See the [updated report](../venus.md) for the Venus configuration and
hardware Vulkan tests.
