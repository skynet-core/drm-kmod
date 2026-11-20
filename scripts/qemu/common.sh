#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Variables are consumed by the scripts sourcing this file.
# shellcheck disable=SC2034
set -euo pipefail
QEMU_SCRIPTS=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd -- "$QEMU_SCRIPTS/../.." && pwd)
QEMU_STATE=${QEMU_STATE:-$REPO/.qemu}
mkdir -p -- "$QEMU_STATE"
QEMU_STATE=$(cd -- "$QEMU_STATE" && pwd)

die() { echo "$*" >&2; exit 1; }
vm_config() {
    VM=${1:?expected freebsd-build or freebsd-test}
    case "$VM" in
        freebsd-build) SSH_PORT=2222; VNC_DISPLAY=10; CPUS=16 ;;
        freebsd-test) SSH_PORT=2223; VNC_DISPLAY=11; CPUS=8 ;;
        *) die "Unknown VM: $VM (expected freebsd-build or freebsd-test)" ;;
    esac
    VM_DIR=$QEMU_STATE/$VM
}
ssh_options() {
    SSH_OPTS=(-i "$QEMU_STATE/id_ed25519" -p "$SSH_PORT"
        -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10
        -o StrictHostKeyChecking=accept-new
        -o "UserKnownHostsFile=$QEMU_STATE/known_hosts")
}
