#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# shellcheck source=common.sh
source "$(dirname -- "$0")/common.sh"
MODE=${1:-kasan}
case "$MODE" in generic|kasan|kmsan) ;; *) die 'Expected generic, kasan or kmsan' ;; esac
VENUS=${QEMU_VENUS:-0}
case "$VENUS" in 0|1) ;; *) die 'QEMU_VENUS must be 0 or 1' ;; esac
vm_config freebsd-test
ssh_options
# Callers supply remote shell commands deliberately.
# shellcheck disable=SC2029
root_ssh() { ssh "${SSH_OPTS[@]}" root@127.0.0.1 "$@"; }
RESULTS=$REPO/scripts/qemu/results/$MODE-$(date -u +%Y%m%dT%H%M%SZ)
if [[ $VENUS == 1 ]]; then RESULTS=${RESULTS%/*}/venus-${RESULTS##*/}; fi
mkdir -p "$RESULTS"
echo "Results: $RESULTS"
for node in /dev/dri/renderD128 /dev/dri/renderD129; do
    [[ -c $node && -r $node && -w $node ]] || die "Inaccessible renderer: $node"
done
ready() {
    local deadline=$((SECONDS + 120))
    while (( SECONDS < deadline )); do
        if root_ssh 'test -e /dev/dri/card0' 2>/dev/null; then return; fi
        sleep 2
    done
    die 'Guest did not bring up SSH and DRM within 120 seconds; inspect serial.log'
}
if [[ ! -S $VM_DIR/qmp.sock ]]; then
    QEMU_VENUS=0 "$QEMU_SCRIPTS/run.sh" freebsd-test
    ready
fi
# The first device configuration starts a fresh VM with the installed build.
"$QEMU_SCRIPTS/deploy.sh" "$MODE" --no-reboot
for node in /dev/dri/renderD128 /dev/dri/renderD129; do
    vendor=$(cat "/sys/class/drm/${node##*/}/device/vendor")
    case "$vendor" in
        0x1002) host='AMD Radeon'; icd=${QEMU_RADEON_ICD:-/usr/share/vulkan/icd.d/radeon_icd.x86_64.json} ;;
        0x10de) host=NVIDIA; icd=${QEMU_NVIDIA_ICD:-/usr/share/vulkan/icd.d/nvidia_icd.x86_64.json} ;;
        *) die "Expected Radeon or NVIDIA, found vendor $vendor on $node" ;;
    esac
    for device in virtio-gpu-gl virtio-vga-gl; do
        "$QEMU_SCRIPTS/stop.sh" freebsd-test
        QEMU_VENUS=$VENUS QEMU_VULKAN_ICD=$icd RENDER_NODE=$node GPU_DEVICE=$device \
            "$QEMU_SCRIPTS/run.sh" freebsd-test
        ready
        root_ssh 'uname -v; freebsd-version -ku; cat /build.txt; kldstat; sysctl dev.virtio_gpu_drm.0.queue_state' > "$RESULTS/${node##*/}-$device-boot.txt"
        if [[ $VENUS == 1 ]]; then
            root_ssh 'sha256 /opt/mesa-venus/lib/libvulkan_virtio.so' >> "$RESULTS/${node##*/}-$device-boot.txt"
        fi
        if [[ $MODE != generic ]]; then
            grep -qi "VIRTGPU-$MODE" "$RESULTS/${node##*/}-$device-boot.txt" || die 'Wrong sanitizer kernel booted'
        fi
        tar -C "$QEMU_SCRIPTS" -cf - render-smoke.c vulkan-smoke.c guest-session.sh guest-proof.sh guest-vt.py | \
            root_ssh 'mkdir -p /home/freebsd/drm-test; tar -xf - -C /home/freebsd/drm-test; chown -R freebsd:freebsd /home/freebsd/drm-test'
        for session in hyprland plasma-wayland plasma-x11; do
            prefix=$RESULTS/${node##*/}-$device-$session
            echo "Testing $MODE / $node / $device / $session"
            root_ssh 'for n in 1 2 3; do pkill -KILL -U freebsd || true; sleep 0.2; done; rm -f /home/freebsd/drm-test/proof.log /home/freebsd/drm-test/compositor.log'
            # All interpolated values come from the fixed/validated cases above.
            # shellcheck disable=SC2029
            root_ssh "printf '%s\n' 'Host: $host $node' 'Device: $device' 'Sanitizer: $MODE' > /tmp/drm-case.txt; nohup env DRM_TEST_VENUS=$VENUS python3 /home/freebsd/drm-test/guest-vt.py $session > /tmp/drm-vt-launch.log 2>&1 < /dev/null &"
            deadline=$((SECONDS + 90))
            success=false
            while (( SECONDS < deadline )); do
                if root_ssh 'grep -q "PASS: 1000" /home/freebsd/drm-test/proof.log && grep -q "Desktop and GPU test logs:" /home/freebsd/drm-test/proof.log && ! pgrep -x ksplashqml >/dev/null' 2>/dev/null; then
                    if [[ $session != hyprland ]] && ! root_ssh 'pgrep -x plasmashell >/dev/null && pgrep -f "[k]activitymanagerd" >/dev/null'; then
                        sleep 2
                        continue
                    fi
                    success=true
                    break
                fi
                sleep 2
            done
            root_ssh 'cat /home/freebsd/drm-test/proof.log' > "$prefix.txt" || true
            # shellcheck disable=SC2029
            root_ssh "cat /home/freebsd/drm-test/$session.log; cat /tmp/drm-vt-launch.log" > "$prefix-session.log"
            root_ssh 'dmesg' > "$prefix-dmesg.log"
            root_ssh 'cat /home/freebsd/drm-test/compositor.log' > "$prefix-compositor.log" || true
            if [[ $VENUS == 1 ]]; then
                root_ssh 'cat /home/freebsd/drm-test/vulkan.log' > "$prefix-vulkan.log" || true
            fi
            "$QEMU_SCRIPTS/screenshot.py" 5911 "$prefix.png"
            [[ $success == true ]] || die "Session failed; see $prefix-session.log"
            case "$vendor" in
                0x1002) grep -q 'GL_RENDERER: virgl (AMD' "$prefix.txt" || die 'Guest did not use the AMD renderer' ;;
                0x10de) grep -q 'GL_RENDERER: virgl (NVIDIA' "$prefix.txt" || die 'Guest did not use the NVIDIA renderer' ;;
            esac
            grep -qi virgl "$prefix-compositor.log" || die 'Compositor did not report virgl'
            if [[ $VENUS == 1 ]]; then
                grep -Eq 'driverID.*DRIVER_ID_MESA_VENUS' "$prefix-vulkan.log" || die 'Vulkan did not use Venus'
                grep -Eq "vendorID.*$vendor" "$prefix-vulkan.log" || die 'Venus did not use the selected GPU vendor'
                grep -q 'PASS: 120 Vulkan GPU writes with full readback' "$prefix.txt" || die 'Vulkan readback failed'
                grep -q 'PASS: 120 Vulkan cube frames presented' "$prefix.txt" || die 'Vulkan presentation failed'
                root_ssh 'pgrep -x vkcube >/dev/null' || die 'Vulkan cube exited before capture'
            fi
            if grep -Eq 'KASAN:|KMSAN:|MSan:|panic:' "$prefix-dmesg.log"; then
                die "Sanitizer or panic diagnostic; see $prefix-dmesg.log"
            fi
            if grep -q 'lock order reversal' "$prefix-dmesg.log"; then
                # WITNESS groups the stock device pager lock and kernel_object
                # lock under "vmobject". Preserve this report separately.
                if [[ $VENUS == 1 ]] && awk '
                    /lock order reversal/ {
                        getline
                        if ($0 !~ /1st .* vmobject .*device_pager\.c:/) exit 1
                        getline
                        if ($0 !~ /2nd .* btag lock .*subr_vmem\.c:/) exit 1
                    }' "$prefix-dmesg.log"; then
                    echo "WITNESS device pager warning: $prefix-dmesg.log" | tee -a "$RESULTS/witness.txt"
                else
                    die "Unexpected locking diagnostic; see $prefix-dmesg.log"
                fi
            fi
            echo "PASS $MODE / $node / $device / $session" | tee -a "$RESULTS/passes.txt"
        done
    done
done
echo "Completed all 12 combinations: $RESULTS"
