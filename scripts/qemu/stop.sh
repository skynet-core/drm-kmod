#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# shellcheck source=common.sh
source "$(dirname -- "$0")/common.sh"
vm_config "${1:-}"
[[ -S $VM_DIR/qmp.sock ]] || die "$VM has no QMP socket"
python3 "$QEMU_SCRIPTS/qmp.py" "$VM_DIR/qmp.sock" system_powerdown
for ((attempt=0; attempt<60; attempt++)); do
    if [[ ! -f $VM_DIR/qemu.pid ]] || ! kill -0 "$(cat "$VM_DIR/qemu.pid")" 2>/dev/null; then
        echo "$VM stopped"
        exit 0
    fi
    sleep 1
done
die "$VM has not powered off after 60 seconds; inspect $VM_DIR/serial.log"
