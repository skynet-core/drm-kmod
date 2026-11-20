#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# shellcheck source=common.sh
source "$(dirname -- "$0")/common.sh"
vm_config "${1:-}"
shift
ssh_options
exec ssh "${SSH_OPTS[@]}" "${QEMU_USER:-freebsd}@127.0.0.1" "$@"
