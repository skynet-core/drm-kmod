#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# shellcheck source=common.sh
source "$(dirname -- "$0")/common.sh"
vm_config "${1:-}"
[[ -f $VM_DIR/disk.qcow2 ]] || die "Run scripts/qemu/install.sh first"
if [[ -f $VM_DIR/qemu.pid ]] && kill -0 "$(cat "$VM_DIR/qemu.pid")" 2>/dev/null; then
    die "$VM is already running"
fi
QEMU_FIRMWARE_CODE=${QEMU_FIRMWARE_CODE:-/usr/share/OVMF/OVMF_CODE.fd}
QEMU_FIRMWARE_VARS=${QEMU_FIRMWARE_VARS:-/usr/share/OVMF/OVMF_VARS.fd}
[[ -r $QEMU_FIRMWARE_CODE && -r $QEMU_FIRMWARE_VARS ]] || \
    die 'Install OVMF or set QEMU_FIRMWARE_CODE and QEMU_FIRMWARE_VARS'
if [[ ! -f $VM_DIR/efi-vars.fd ]]; then
    cp "$QEMU_FIRMWARE_VARS" "$VM_DIR/efi-vars.fd"
fi
args=(-name "$VM" -machine "q35,accel=kvm" -cpu host
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$QEMU_FIRMWARE_CODE"
    -drive "if=pflash,format=raw,unit=1,file=$VM_DIR/efi-vars.fd"
    -smp "${QEMU_CPUS:-$CPUS}" -m "${QEMU_MEMORY:-16G}"
    -drive "file=$VM_DIR/disk.qcow2,if=virtio,format=qcow2,discard=unmap"
    -drive "file=$VM_DIR/seed.iso,media=cdrom,readonly=on"
    -device virtio-rng-pci -device qemu-xhci -device usb-tablet -device usb-kbd
    -netdev "user,id=net0,ipv6=off,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22"
    -device "virtio-net-pci,netdev=net0"
    -chardev "socket,id=serial0,path=$VM_DIR/serial.sock,server=on,wait=off,logfile=$VM_DIR/serial.log,logappend=on"
    -serial chardev:serial0
    -qmp "unix:$VM_DIR/qmp.sock,server=on,wait=off"
    -pidfile "$VM_DIR/qemu.pid" -daemonize)
if [[ $VM == freebsd-test ]]; then
    GPU_DEVICE=${GPU_DEVICE:-virtio-gpu-gl-pci}
    case "$GPU_DEVICE" in
        virtio-gpu-gl|virtio-gpu-gl-pci|virtio-vga-gl) ;;
        *) die 'GPU_DEVICE must be virtio-gpu-gl-pci, virtio-gpu-gl or virtio-vga-gl' ;;
    esac
    RENDER_NODE=${RENDER_NODE:-/dev/dri/renderD128}
    [[ $RENDER_NODE == /dev/dri/renderD* && -c $RENDER_NODE && -r $RENDER_NODE && -w $RENDER_NODE ]] || \
        die "Render node must be an accessible /dev/dri/renderD* character device: $RENDER_NODE"
    gpu="$GPU_DEVICE,xres=1440,yres=900"
    if [[ ${QEMU_VENUS:-0} == 1 ]]; then
        [[ -n ${QEMU_VULKAN_ICD:-} && -r $QEMU_VULKAN_ICD ]] || \
            die 'Set QEMU_VULKAN_ICD to the host Vulkan ICD JSON for the selected GPU'
        # The EGL render node selects virgl's GPU. Venus uses the Vulkan loader.
        export VK_DRIVER_FILES=$QEMU_VULKAN_ICD
        args+=(-object "memory-backend-memfd,id=venus-ram,size=${QEMU_MEMORY:-16G},share=on"
            -machine memory-backend=venus-ram)
        gpu+=,hostmem=4G,blob=on,venus=on
    fi
    args+=(-vga none -device "$gpu"
        -display "egl-headless,rendernode=$RENDER_NODE"
        -vnc "127.0.0.1:$VNC_DISPLAY")
else
    args+=(-vga none -display none)
fi
if ! qemu-system-x86_64 "${args[@]}" 2> "$VM_DIR/qemu.log"; then
    cat "$VM_DIR/qemu.log" >&2
    exit 1
fi
printf '%s\n' "${RENDER_NODE:-none}" > "$VM_DIR/render-node"
printf '%s\n' "${GPU_DEVICE:-none}" > "$VM_DIR/gpu-device"
echo "$VM started; SSH localhost:$SSH_PORT; logs in $VM_DIR"
