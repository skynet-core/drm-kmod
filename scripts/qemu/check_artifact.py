#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Reject archives that could replace guest / permissions or contain a mismatched kernel."""
from pathlib import PurePosixPath
import sys
import tarfile


def check_artifact(filename, mode):
    if mode not in ('generic', 'kasan', 'kmsan'):
        raise ValueError('unknown build mode')
    with tarfile.open(filename) as archive:
        paths = set()
        for member in archive:
            path = PurePosixPath(member.name)
            if (path.is_absolute() or '..' in path.parts or not path.parts or
                    path.parts[0] not in ('boot', 'usr', 'build.txt')):
                raise ValueError(f'unsafe archive path: {member.name!r}')
            paths.add(str(path))
        required = {'boot/modules/' + name + '.ko'
                    for name in ('dmabuf', 'drm', 'virtio_gpu_drm')}
        if mode != 'generic':
            required.add(f'boot/kernel.{mode}/kernel')
        if not required <= paths:
            raise ValueError(f'missing artifacts: {required - paths}')
        if any(path == 'boot/kernel' or path.startswith('boot/kernel/') for path in paths):
            raise ValueError('archive would overwrite the stock kernel')
        stamp = archive.extractfile('build.txt').read().decode()
        if f'mode={mode}\n' not in stamp:
            raise ValueError('build mode does not match the archive')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('Usage: check-artifact.py ARCHIVE generic|kasan|kmsan')
    check_artifact(sys.argv[1], sys.argv[2])
