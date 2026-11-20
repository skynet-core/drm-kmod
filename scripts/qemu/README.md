# FreeBSD virtio GPU development guests

These helpers create `freebsd-build` and `freebsd-test` from the official
FreeBSD 15.1 amd64 BASIC-CLOUDINIT image. The compressed image is SHA256
verified, shared read-only, and backed by separate 100 GB qcow2 overlays.
Disks, firmware variables, SSH identities, build artifacts and logs live
under the ignored `.qemu/` directory. Set `QEMU_STATE` to move this directory.

See the [recorded test results and screenshots](results/README.md) for the
Radeon/NVIDIA KASAN and KMSAN desktop matrix.

The Linux host needs KVM access, QEMU with virgl and EGL-headless support,
OVMF, Bash, Python 3.11+, curl, xz, xorriso and OpenSSH. Screenshot capture
uses the system Python's GtkVnc 2.0 / Gtk 3 introspection bindings and an
available graphical display (or Xvfb). On Fedora the additional capture
dependencies are `python3-gobject` and `gtk-vnc2`.

## Install and run

From the repository root:

```sh
scripts/qemu/install.sh
scripts/qemu/run.sh freebsd-build
RENDER_NODE=/dev/dri/renderD128 GPU_DEVICE=virtio-gpu-gl-pci \
    scripts/qemu/run.sh freebsd-test
```

First boot updates PkgBase, runs nuageinit, and can reboot automatically.
Wait for `/var/db/drm-qemu-ready` in each guest. The `freebsd` user belongs
to `wheel` and `video` and has passwordless sudo. Root and `freebsd` accept
the dedicated `.qemu/id_ed25519` key; SSH password authentication is disabled.
SSH and VNC listen only on host loopback.

| Guest | SSH port | VNC port | Default CPUs / memory |
|---|---:|---:|---|
| freebsd-build | 2222 | none | 16 / 16 GB |
| freebsd-test | 2223 | 5911 | 8 / 16 GB |

```sh
scripts/qemu/ssh.sh freebsd-build 'sudo -n id'
QEMU_USER=root scripts/qemu/ssh.sh freebsd-test 'id'
```

Set `QEMU_CPUS` / `QEMU_MEMORY` to override sizing. Firmware defaults to
`/usr/share/OVMF/OVMF_CODE.fd` and `OVMF_VARS.fd`; override these using
`QEMU_FIRMWARE_CODE` and `QEMU_FIRMWARE_VARS` on other distributions.
Each VM has its own writable firmware variables. The guests use IPv4 user
networking; no host bridge or root networking configuration is needed.

Both `GPU_DEVICE=virtio-vga-gl` and `GPU_DEVICE=virtio-gpu-gl-pci` are
supported; `virtio-gpu-gl` is QEMU's alias for the latter. `-vga none`
prevents QEMU from adding an unrelated default VGA device. Select each
host render node explicitly; identify the GPU behind a node using
`/sys/class/drm/renderD*/device/driver` and `lspci -nn`.
The guest sees a virtio GPU and normally uses `/dev/dri/renderD128` even
when the host renderer is `/dev/dri/renderD129`.

## Build and deploy

```sh
scripts/qemu/build.sh generic
QEMU_USER=root scripts/qemu/ssh.sh freebsd-test 'sh -s' < scripts/qemu/guest-setup.sh
scripts/qemu/deploy.sh generic
```

The builder installs PkgBase sources matching its kernel package and
copies the working tree, including uncommitted changes, into the build VM.
It builds `dmabuf`, `drm` and `virtio_gpu_drm` together. Deployment validates
the archive, installs those modules, enables module loading, and reboots
the test VM. A base `vtgpu` device disabled by the loader hint can need
`devctl enable vtgpu0` after loading the module; check `/dev/dri/card0`.

Build and run real instrumented kernels using FreeBSD's stock debug
configurations:

```sh
scripts/qemu/build.sh kasan
scripts/qemu/deploy.sh kasan
# Separately:
scripts/qemu/build.sh kmsan
scripts/qemu/deploy.sh kmsan
```

The kernel, its base modules and the external DRM modules use matching
option headers and sanitizer flags. KASAN and KMSAN artifacts install into
`/boot/kernel.kasan` and `/boot/kernel.kmsan`; the stock `/boot/kernel`
remains available for recovery. Symbols accompany the artifacts.
Repeat builds reuse kernel objects and clean the external modules before
changing configurations. Deployment of `generic` selects the stock kernel
again. Do not upgrade guest base packages between building and testing.

## Desktop tests and screenshots

Copy the session helpers into the test user's home once (repeat after edits):

```sh
tar -C scripts/qemu -cf - render-smoke.c guest-session.sh guest-proof.sh guest-vt.py | \
    QEMU_USER=root scripts/qemu/ssh.sh freebsd-test \
    'mkdir -p /home/freebsd/drm-test; tar -xf - -C /home/freebsd/drm-test; chown -R freebsd:freebsd /home/freebsd/drm-test'
```

Write the actual host/device/kernel test label to `/tmp/drm-case.txt`.
Launch a desktop on a real VT so ConsoleKit grants KWin an active seat.
The launcher makes the video console primary while retaining serial logging:

```sh
QEMU_USER=root scripts/qemu/ssh.sh freebsd-test \
    'printf "Host: Radeon renderD128\nDevice: virtio-gpu-gl-pci\n" > /tmp/drm-case.txt'
QEMU_USER=root scripts/qemu/ssh.sh freebsd-test \
    'nohup python3 /home/freebsd/drm-test/guest-vt.py hyprland > /tmp/drm-vt-launch.log 2>&1 < /dev/null &'
```

Use `plasma-wayland` or `plasma-x11` in place of `hyprland` for the other
sessions. All sessions open a visible acceleration report and glmark2.
`render-smoke.c` creates a GBM/EGL GLES context on the guest render node,
compiles shaders, draws 1,000 alternating frames and checks every pixel
read back. It requires virgl and rejects software renderer strings.
`~/drm-test/proof.log` records the renderer, kernel and result.

```sh
scripts/qemu/screenshot.py 5911 /absolute/path/to/proof.png
QEMU_USER=root scripts/qemu/ssh.sh freebsd-test 'dmesg' > /absolute/path/to/dmesg.log
```

VNC capture reads QEMU's actual GL scanout. QMP `screendump` alone can report
`no surface` until a VNC client connects to an EGL-headless display.
Check the image together with the renderer log and sanitizer output.
For every host render node and both QEMU device models, test Hyprland
Wayland, Plasma Wayland and Plasma X11. Preserve failures as well as passes.

The default launch tests classic virgl OpenGL/GLES. The optional Venus
configuration also tests the host-visible memory path and hardware Vulkan.

Switch desktops by terminating the dedicated test user's processes and
launching the next session. Use the root SSH connection for this operation:

```sh
QEMU_USER=root scripts/qemu/ssh.sh freebsd-test 'pkill -KILL -U freebsd || true'
```

Stop the VM before changing its renderer or GPU device:

```sh
scripts/qemu/stop.sh freebsd-test
RENDER_NODE=/dev/dri/renderD129 GPU_DEVICE=virtio-vga-gl scripts/qemu/run.sh freebsd-test
```

The complete matrix runner deploys the requested build, starts both device
models on each host renderer, and records all three desktops in a new
timestamped directory under `scripts/qemu/results/`:

```sh
scripts/qemu/matrix.sh kasan
scripts/qemu/matrix.sh kmsan
```

This operates on the dedicated test VM and terminates the test user's desktop
between sessions. Sanitizer diagnostics, unexpected lock-order reports and
failed readback stop the run and keep the collected evidence.

`serial.log`, `serial.sock`, `qemu.log` and `qmp.sock` are in each VM's state
directory. The serial socket accepts console input for loader recovery.
For example, interrupt autoboot, `unload`, then `load /boot/kernel/kernel`
and `boot` to recover a bad sanitizer kernel. Keep the console connection
open until commands are acknowledged. The driver deliberately refuses
unload after attachment; reboot the guest to change the running driver.

## Hardware Vulkan with Venus

Build the native Venus ICD in `freebsd-build`. The helper verifies the
Mesa 26.2.2 source archive and applies FreeBSD fixes for Wayland clock IDs
and the Venus presentation thread ID, plus the PRIME stride workaround for
proprietary NVIDIA hosts. Install it under `/opt/mesa-venus`
on the test guest. The loader selects it explicitly for the Vulkan tests.

```sh
scripts/qemu/build-venus.sh
artifact=${QEMU_STATE:-.qemu}/artifacts/venus.tar.gz
digest=$(sha256sum "$artifact" | cut -d ' ' -f 1)
QEMU_USER=root scripts/qemu/ssh.sh freebsd-test \
    "cat > /tmp/drm-venus.tar.gz && test \"\$(sha256 -q /tmp/drm-venus.tar.gz)\" = '$digest' && tar -xpf /tmp/drm-venus.tar.gz -C /" \
    < "$artifact"
```

For Vulkan applications launched outside the test fixture, set
`VK_DRIVER_FILES` to the installed Venus JSON, or register the ICD with
the guest's default Vulkan loader:

```sh
QEMU_USER=root scripts/qemu/ssh.sh freebsd-test \
    'ln -sf /opt/mesa-venus/share/vulkan/icd.d/virtio_icd.x86_64.json /usr/local/share/vulkan/icd.d/drm-kmod-venus.json'
```

QEMU must support `blob`, `hostmem` and `venus` on both GL devices.
`QEMU_VENUS=1` enables a 4 GiB PCI aperture and shared memfd guest RAM.
Set `QEMU_VULKAN_ICD` to the host Vulkan ICD JSON for the same physical
GPU as `RENDER_NODE`. For example, for Radeon on Fedora:

```sh
QEMU_VENUS=1 QEMU_VULKAN_ICD=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json \
    RENDER_NODE=/dev/dri/renderD128 GPU_DEVICE=virtio-gpu-gl \
    scripts/qemu/run.sh freebsd-test
scripts/qemu/ssh.sh freebsd-test \
    'env VK_DRIVER_FILES=/opt/mesa-venus/share/vulkan/icd.d/virtio_icd.x86_64.json vulkaninfo --summary'
```

The matrix selects the Radeon and NVIDIA ICDs by the render node's PCI
vendor. Override their paths with `QEMU_RADEON_ICD` or `QEMU_NVIDIA_ICD`.

```sh
QEMU_VENUS=1 scripts/qemu/matrix.sh kasan
QEMU_VENUS=1 scripts/qemu/matrix.sh kmsan
```

Each case checks the expected hardware Vulkan vendor, runs GPU writes
with full readback through a mapped buffer and presents 120 cube frames
through the session's native Wayland or XCB surface. It captures a live
cube alongside the verification report and also checks the virgl renderer.
The runner logs the stock FreeBSD device-pager/allocator WITNESS warning
in `witness.txt` if it occurs and retains the original kernel trace.

Helper regression tests (no guests required):

```sh
shellcheck -P scripts/qemu scripts/qemu/*.sh
python3 scripts/qemu/test_helpers.py
```
