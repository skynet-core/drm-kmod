# FreeBSD virtio GPU development guests

These helpers create `freebsd-build` and `freebsd-test` from the official
FreeBSD 15.1 amd64 BASIC-CLOUDINIT image. The compressed image is SHA256
verified, shared read-only, and backed by separate 100 GB qcow2 overlays.
Disks, firmware variables, SSH identities, build artifacts and logs live
under the ignored `.qemu/` directory. Set `QEMU_STATE` to move this directory.

For a developer's introduction to rendering, display control, and how a draw
travels from FreeBSD to the host GPU, see [How graphics works in a FreeBSD 15.1 QEMU guest](graphics-stack.md).

See the [recorded test results and screenshots](results/README.md) for the
Radeon/NVIDIA KASAN and KMSAN desktop matrix.

For an existing libvirt VM, follow the [virt-manager setup](#libvirt-and-virt-manager-setup-for-sddm-and-hyprland)
to configure accelerated graphics and absolute pointer tracking.

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

## FreeBSD 15.1 QEMU install with virtio-gpu + Hyprland

This walkthrough starts from the FreeBSD installer ISO and builds the
driver inside one VM. It uses an x86-64 Linux host and configures virgl
OpenGL/GLES. The separate [Hardware Vulkan with Venus](#hardware-vulkan-with-venus)
section covers Vulkan with the development VM helpers.

### 1. Create and boot the VM (Linux host)

Install QEMU with KVM and virgl/EGL support, `qemu-img`, OVMF (UEFI
firmware), `curl`, and a VNC viewer. Your host account needs access to
`/dev/kvm` and the selected GPU render node. The example uses
`/dev/dri/renderD128`. Use `ls -l /dev/dri/by-path` and `lspci -nn` to
match a render node's PCI address to your Radeon or NVIDIA GPU. The node
number depends on the host. An empty virtual disk is created in a separate
directory under `.qemu/`. Download and verify the ISO before booting it.
[FreeBSD 15.1 installer images and checksums](https://download.freebsd.org/releases/amd64/amd64/ISO-IMAGES/15.1/)

Run the following from the repository root in a host terminal:

```sh
mkdir -p .qemu/freebsd-hyprland
cd .qemu/freebsd-hyprland
mirror=https://download.freebsd.org/releases/amd64/amd64/ISO-IMAGES/15.1
iso=FreeBSD-15.1-RELEASE-amd64-disc1.iso
checksums=CHECKSUM.SHA256-FreeBSD-15.1-RELEASE-amd64
curl -fLO "$mirror/$iso"
curl -fLO "$mirror/$checksums"
sha256sum --check --ignore-missing "$checksums"
```

Continue once the ISO reports `OK`. Use the OVMF paths from your Linux
distribution if they differ. Each VM needs its own writable
`efi-vars.fd`. Run the following in the same host terminal:

```sh
test -e disk.qcow2 || qemu-img create -f qcow2 disk.qcow2 64G
test -e efi-vars.fd || cp /usr/share/OVMF/OVMF_VARS.fd efi-vars.fd
render_node=/dev/dri/renderD128
gpu_device=virtio-vga-gl

run_freebsd() {
    qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp 4 -m 8G \
        -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
        -drive if=pflash,format=raw,unit=1,file=efi-vars.fd \
        -drive file=disk.qcow2,if=virtio,format=qcow2 \
        -netdev user,id=net0,ipv6=off -device virtio-net-pci,netdev=net0 \
        -device qemu-xhci -device usb-tablet -device usb-kbd \
        -vga none -device "$gpu_device,xres=1440,yres=900" \
        -display "egl-headless,rendernode=$render_node" -vnc 127.0.0.1:12 \
        "$@"
}

run_freebsd -cdrom "$iso" -boot once=d -no-reboot
```

QEMU runs in the foreground. Open your VNC viewer and connect to
`127.0.0.1` on TCP port `5912` (TigerVNC accepts `127.0.0.1::5912`).
The `-vga none` option leaves the selected virtio GPU as the only display
device. You can use `virtio-gpu-gl` instead by setting `gpu_device` before
launching the VM.

### 2. Install FreeBSD (VNC console)

1. Boot the default FreeBSD option and choose **Install**. Set your
   keymap and a hostname such as `freebsd-hyprland`.
2. Choose **Packages (Tech Preview)** for this VM. Choose **Network** if
   offered and accept the default base components. For networking,
   choose `vtnet0`, enable IPv4 DHCP, and skip IPv6. QEMU user networking
   supplies the address and Internet access for packages.
3. Choose **Auto (UFS)**, select the VM's 64 GB `vtbd0` disk, and use the
   entire disk with GPT. Confirm the layout and commit the changes.
   The installer writes to `disk.qcow2` on the host.
4. Set a root password and add a normal user named `freebsd`. Keep the
   default login group and enter `wheel video` when invited to add
   supplementary groups. Choose `sh` as the shell and set a password
   for this user. Leave the installer services and hardening at their
   defaults. You can do the whole setup through VNC.
5. At the end, skip manual configuration and select **Reboot**. The
   installation QEMU process exits because of `-no-reboot`. In the same
   host terminal, run `run_freebsd` with no arguments and reconnect
   VNC. This boots the installed disk with the ISO detached.

See the [FreeBSD Handbook installer screens](https://docs.freebsd.org/en/books/handbook/bsdinstall/)
for the menus.

### 3. Update FreeBSD and build the modules (guest)

Log in as `freebsd` at the guest's text console. Run `su -` and enter the
root password to administer the guest. Update the package-based FreeBSD
installation, install the matching sources and desktop packages, then
reboot into the updated kernel. If `pkg` asks to bootstrap itself, accept the prompt.

```sh
pkg update
pkg upgrade -r FreeBSD-base
pkg install -r FreeBSD-base FreeBSD-src FreeBSD-src-sys
pkg install git hyprland foot dejavu dbus seatd mesa-dri glmark2
shutdown -r now
```

After the reboot, log in as `freebsd` again and check the running kernel
and sources. The outputs from `freebsd-version -k` (installed kernel) and
`freebsd-version -r` (running kernel) should match. The two kernel and
source package versions should also match each other. Stop and resolve
any mismatch before building. Reboot if the installed kernel is newer
than the running one. If the package versions differ, update the base
packages and install the matching sources from `FreeBSD-base` again.

```sh
freebsd-version -k
freebsd-version -r
pkg query '%n %v' FreeBSD-kernel-generic FreeBSD-src-sys
test -r /usr/src/sys/conf/kern.opts.mk
```

Build as `freebsd` using the guest's FreeBSD `make` and compiler:

```sh
git clone --depth 1 --branch virtio-gpu-nvidia https://github.com/skynet-core/drm-kmod.git ~/drm-kmod
cd ~/drm-kmod
make -j "$(sysctl -n hw.ncpu)" SYSDIR=/usr/src/sys KMODS="dmabuf drm virtio"
```

The three outputs are `dmabuf/dmabuf.ko`, `drm/drm.ko`, and
`virtio/virtio_gpu_drm.ko`. Build and install them as a set. Rebuild
against the new sources when you update the guest kernel.

### 4. Install and configure the driver (guest, root)

Run `su -` again, then install the three modules and index them. Use
these settings once on a fresh install. If a setting already exists in
`/boot/loader.conf` or `/etc/sysctl.conf`, edit that entry instead.

```sh
cd /home/freebsd/drm-kmod
install -d /boot/modules
install -m 0555 dmabuf/dmabuf.ko drm/drm.ko virtio/virtio_gpu_drm.ko /boot/modules/
kldxref /boot/modules

# /boot/loader.conf: leave the GPU available to the DRM driver.
printf '%s\n' 'hint.vtgpu.0.disabled="1"' >> /boot/loader.conf

# /etc/rc.conf: load DRM during system startup and enable desktop services.
sysrc kld_list+=virtio_gpu_drm
sysrc dbus_enable=YES seatd_enable=YES

# /etc/sysctl.conf: expose keyboard and mouse input through evdev.
printf '%s\n' 'kern.evdev.rcpt_mask=12' >> /etc/sysctl.conf

shutdown -r now
```

Keep the guest's video console enabled so you can log in through VNC.
The loader hint stops the base `vtgpu` framebuffer from claiming the
device. Use either `kld_list` or `virtio_gpu_drm_load="YES"` in
`/boot/loader.conf`. The driver registers after the DRM core initializes.

After reboot, `kldstat` should list `virtio_gpu_drm.ko`, and
`ls -l /dev/dri` should show `card0` and `renderD128`. If the module
failed to load, check `dmesg | grep -E 'virtio_gpu|linker'` in the guest
for errors before trying to start Hyprland. If the module
loaded but `card0` is missing, run `devctl enable vtgpu0` as root and
check again. If that creates the nodes, add this block to `/etc/rc.local`
as root so the retry runs after `kld_list` on subsequent boots:

```sh
if [ ! -c /dev/dri/card0 ]; then
    devctl enable vtgpu0
fi
```

If Hyprland cannot open the GPU or input devices, check that `id` lists
`video` for your normal user and that `service seatd status` and
`service dbus status` report running services. If `video` is missing,
run `pw groupmod video -m freebsd` as root and log out and back in.

### 5. Start Hyprland and verify acceleration (guest, normal user)

Log in as `freebsd` directly at the VNC text console. This gives the
session an active virtual terminal and sets `XDG_RUNTIME_DIR`. The
minimal Lua configuration below works with Hyprland 0.55 and newer. It
opens the Foot terminal automatically and binds Super+Enter to open
another and Super+M to exit. [Hyprland configuration reference](https://wiki.hypr.land/0.57.0/configuring/core/)

```sh
mkdir -p ~/.config/hypr
cat > ~/.config/hypr/qemu.lua <<'LUA'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.on("hyprland.start", function()
    hl.exec_cmd("foot")
end)
hl.bind("SUPER + Return", hl.dsp.exec_cmd("foot"))
hl.bind("SUPER + M", hl.dsp.exit())
LUA

env LIBSEAT_BACKEND=seatd AQ_DRM_DEVICES=/dev/dri/card0 \
    dbus-run-session start-hyprland -- --config "$HOME/.config/hypr/qemu.lua"
```

In the Foot window, run `glmark2-wayland --size 640x480`. The benchmark
should display animated scenes and report `GL_RENDERER: virgl (...)` with
the selected host GPU in the terminal. A renderer containing `llvmpipe`
or `softpipe` indicates CPU rendering. Check that QEMU started with a
`-gl` device and the intended host render node. To switch GPU models or
host nodes later, shut down the guest before changing `gpu_device` or
`render_node` in the host terminal.

### Libvirt and virt-manager setup for SDDM and Hyprland

If the SPICE GL viewer stalls or limits frame updates, pair the local
SPICE console with EGL headless. Virgl still uses the selected host GPU.
EGL headless keeps command processing independent of SPICE GL draw
acknowledgements from the viewer. The USB tablet sends absolute pointer
positions. With the resize helper below, set the SPICE XML mouse mode to
`server`. Libvirt translates this to QEMU's `agent-mouse=off`, so pointer
events keep reaching the tablet while the SPICE agent port is open.

1. Shut down the guest. In virt-manager, open the VM on the **QEMU/KVM**
   system connection (`qemu:///system`).
2. Under **Edit → Preferences → General**, enable **XML editing**. In the
   VM window, choose **Show virtual hardware details → Overview → XML**
   to edit the full domain definition. From a host terminal, the equivalent
   command for the tested VM is `virsh -c qemu:///system edit freebsd15.1`.
3. Under `<devices>`, replace the existing SPICE graphics block and add
   the EGL headless graphics block alongside it. Keep the USB controller
   and add the USB tablet if one is missing. Use one 3D-enabled virtio
   video device. If it already exists, preserve its address and other
   attributes.

```xml
<input type='tablet' bus='usb'/>
<graphics type='spice'>
  <listen type='none'/>
  <image compression='off'/>
  <mouse mode='server'/>
</graphics>
<graphics type='egl-headless'>
  <gl rendernode='/dev/dri/renderD129'/>
</graphics>
<video>
  <model type='virtio' heads='1' primary='yes' blob='on' device='virtio-vga-gl'>
    <acceleration accel3d='yes'/>
  </model>
</video>
```

Set `rendernode` to the **host** render node for your GPU. On the tested
host, `renderD129` was the RTX 3090 and `renderD128` was the Radeon 610M.
Use `ls -l /dev/dri/by-path` and `lspci -nn` to identify yours. Select
`virtio-gpu-gl` for the non-VGA model. The `device` attribute requires libvirt 12.5 or newer.
[Libvirt domain XML reference](https://libvirt.org/formatdomain.html#graphical-framebuffers)

Click **Apply**, start the VM, and open its graphical console. In the guest,
`dmesg | grep -i 'QEMU USB Tablet'` should show the tablet attached to
`hms0`. In Hyprland, run `hyprctl devices` and look for
`qemu-qemu-usb-tablet` under mice. Move the viewer pointer between two
corners and back. The guest pointer should return to the same position.

Install SDDM and Xorg in the guest, add `sddm` and the desktop user to the
`video` group, and enable `sddm`, `seatd`, and `dbus` in `rc.conf`. Use
SDDM's X11 greeter and select Hyprland from its session menu. Xorg should
report `glamor X acceleration enabled on virgl` in `Xorg.0.log`. Inside
Hyprland, use `glmark2-wayland` to check that the renderer names the same
host GPU.

#### Resize the Hyprland desktop with the viewer

Enable **View → Scale Display → Auto resize VM with window** in the
virt-manager console. The [FreeBSD session helper](spice-hypr-resize.c)
opens the SPICE port and advertises support for monitor configuration.
QEMU publishes the requested size as the virtual monitor's preferred
mode. On a FreeBSD DRM hotplug event, the helper applies that mode to
Hyprland. This setup uses one virtual display on `/dev/dri/card0` and
dedicates the SPICE agent channel to resizing.

Under the domain's `<devices>`, keep one SPICE agent channel.

```xml
<channel type='spicevmc'>
  <target type='virtio' name='com.redhat.spice.0'/>
</channel>
```

In the guest, run these commands as root from the repository root.
Replace `vasyl` with the desktop login. The ownership rule grants that
user access to the named channel at boot.

```sh
pkg install libdrm spice-protocol
cc -O2 -I/usr/local/include -I/usr/local/include/libdrm -I/usr/local/include/spice-1 \
    -L/usr/local/lib scripts/qemu/spice-hypr-resize.c -ldrm -lm -o /tmp/spice-hypr-resize
install -m 555 /tmp/spice-hypr-resize /usr/local/libexec/spice-hypr-resize
chown vasyl /dev/vtcon/com.redhat.spice.0
echo 'own vtcon/com.redhat.spice.0 vasyl' >> /etc/devfs.conf
```

Add this to the desktop user's `~/.config/hypr/hyprland.lua` and log in
to Hyprland. Use `2` for a host screen at 200% scale or `1` for 100%.

```lua
hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/local/libexec/spice-hypr-resize 2")
end)
```

Toggle fullscreen and run `hyprctl monitors` in the guest after each
transition. On a 3840×2160 host screen at 200%, fullscreen should report
3840×2160 with scale 2. Leaving fullscreen should select the viewer's
windowed pixel dimensions.

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
