/*-
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2026 Denis Borovikov <denis.borovikov@gmail.com>
 */

#ifndef _VIRTGPU_SHIM_LINUX_UACCESS_H
#define	_VIRTGPU_SHIM_LINUX_UACCESS_H

#include_next <linux/uaccess.h>

#ifdef VIRTGPU_NEED_STRNCPY_FROM_USER
static inline long
strncpy_from_user(char *dst, const char __user *src, long count)
{
	size_t done;
	int error;

	if (count <= 0)
		return (0);
	error = copyinstr(src, dst, count, &done);
	if (error == 0)
		return ((long)done - 1);	/* done includes the NUL */
	if (error == ENAMETOOLONG)
		return (count);			/* truncated, as Linux */
	return (-EFAULT);
}
#endif

#endif /* _VIRTGPU_SHIM_LINUX_UACCESS_H */
