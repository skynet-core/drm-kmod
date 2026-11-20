#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Send one QMP command. For EGL/GL scanout screenshots, use screenshot.py."""
import json
import socket
import sys


def command(path, name, arguments):
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(30)
        sock.connect(path)
        with sock.makefile('rwb') as stream:
            greeting = json.loads(stream.readline())
            if 'QMP' not in greeting:
                raise RuntimeError(greeting)
            for request in ({'execute': 'qmp_capabilities'},
                            {'execute': name, 'arguments': arguments}):
                stream.write(json.dumps(request).encode() + b'\n')
                stream.flush()
                while True:
                    reply = json.loads(stream.readline())
                    if 'event' not in reply:
                        break
                if 'error' in reply:
                    raise RuntimeError(reply['error'])
            return reply['return']


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit('Usage: qmp.py SOCKET COMMAND [ARGUMENTS_JSON]')
    print(json.dumps(command(sys.argv[1], sys.argv[2],
                             json.loads(sys.argv[3]) if len(sys.argv) > 3 else {})))
