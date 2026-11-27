/*-
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2026 Denis Borovikov <denis.borovikov@gmail.com>
 */

#ifndef _VIRTGPU_SHIM_LINUX_UUID_H
#define	_VIRTGPU_SHIM_LINUX_UUID_H

#include_next <linux/uuid.h>

/* Newer LinuxKPI maps uuid_t to its Linux-compatible type. */
#ifndef uuid_t
typedef struct {
	__u8 b[UUID_SIZE];
} lkpi_shim_uuid_t;
#define	uuid_t	lkpi_shim_uuid_t

static inline void
uuid_copy(uuid_t *dst, const uuid_t *src)
{
	memcpy(dst, src, sizeof(uuid_t));
}

static inline void
import_uuid(uuid_t *dst, const __u8 *src)
{
	memcpy(dst->b, src, UUID_SIZE);
}
#endif

#endif /* _VIRTGPU_SHIM_LINUX_UUID_H */
