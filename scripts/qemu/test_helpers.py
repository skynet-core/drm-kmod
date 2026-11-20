#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""No VM needed: exercise QMP events/errors and reject invalid guest names."""
import json
import io
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import tarfile
import unittest

from qmp import command
from check_artifact import check_artifact


class HelpersTest(unittest.TestCase):
    def exchange(self, response, client=None):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / 'qmp.sock')
            requests = []
            with socket.socket(socket.AF_UNIX) as server:
                server.bind(path)
                server.listen(1)

                def serve():
                    with server.accept()[0] as connection:
                        with connection.makefile('rwb') as stream:
                            stream.write(b'{"QMP": {}}\n')
                            stream.flush()
                            for reply in ({'return': {}}, response):
                                requests.append(json.loads(stream.readline()))
                                stream.write(b'{"event": "STOP"}\n')
                                stream.write(json.dumps(reply).encode() + b'\n')
                                stream.flush()

                thread = threading.Thread(target=serve)
                thread.start()
                try:
                    if client is not None:
                        return client(path), requests
                    return command(path, 'screendump', {'filename': '/tmp/proof.ppm'}), requests
                finally:
                    thread.join(timeout=5)
                    self.assertFalse(thread.is_alive())

    def test_qmp_skips_events_and_sends_arguments(self):
        reply, requests = self.exchange({'return': {}})
        self.assertEqual(reply, {})
        self.assertEqual(requests, [
            {'execute': 'qmp_capabilities'},
            {'execute': 'screendump', 'arguments': {'filename': '/tmp/proof.ppm'}}])

    def test_qmp_error_is_not_success(self):
        with self.assertRaisesRegex(RuntimeError, 'GenericError'):
            self.exchange({'error': {'class': 'GenericError', 'desc': 'no display'}})

    def test_rejects_unknown_vm_before_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            environment = dict(os.environ, QEMU_STATE=directory)
            result = subprocess.run(
                ['bash', str(Path(__file__).with_name('run.sh')), 'unknown'],
                env=environment, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Unknown VM', result.stderr)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_stale_pid_does_not_block_shutdown(self):
        with tempfile.TemporaryDirectory() as directory:
            vm = Path(directory) / 'freebsd-test'
            vm.mkdir()
            (vm / 'qemu.pid').write_text('2147483647\n')

            def stop(path):
                (vm / 'qmp.sock').symlink_to(path)
                return subprocess.run(
                    ['bash', str(Path(__file__).with_name('stop.sh')), 'freebsd-test'],
                    env=dict(os.environ, QEMU_STATE=directory),
                    capture_output=True, text=True, timeout=3)

            result, requests = self.exchange({'return': {}}, stop)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('stopped', result.stdout)
            self.assertEqual(requests[-1]['execute'], 'system_powerdown')

    def artifact(self, filename, extra=()):
        with tarfile.open(filename, 'w:gz') as archive:
            for name in ('boot/modules/dmabuf.ko', 'boot/modules/drm.ko',
                         'boot/modules/virtio_gpu_drm.ko', 'build.txt', *extra):
                data = b'mode=generic\n' if name == 'build.txt' else b''
                member = tarfile.TarInfo(name)
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))

    def test_accepts_module_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / 'modules.tar.gz')
            self.artifact(path)
            check_artifact(path, 'generic')

    def test_rejects_archive_root_and_parent_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / 'modules.tar.gz')
            for name in ('.', '/', '../outside', '/boot/modules/drm.ko'):
                with self.subTest(name=name):
                    self.artifact(path, (name,))
                    with self.assertRaisesRegex(ValueError, 'unsafe archive path'):
                        check_artifact(path, 'generic')

    def test_requires_matching_kernel(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / 'modules.tar.gz')
            self.artifact(path)
            with self.assertRaisesRegex(ValueError, 'missing artifacts'):
                check_artifact(path, 'kasan')
            for name in ('boot/kernel', 'boot/kernel/kernel'):
                with self.subTest(name=name):
                    self.artifact(path, (name,))
                    with self.assertRaisesRegex(ValueError, 'stock kernel'):
                        check_artifact(path, 'generic')


if __name__ == '__main__':
    unittest.main()
