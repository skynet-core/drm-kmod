#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Run the test user on VT 9 so ConsoleKit can grant KWin display-master access."""
import os
import pwd
import subprocess
import sys

if len(sys.argv) != 2 or sys.argv[1] not in ('hyprland', 'plasma-wayland', 'plasma-x11'):
    sys.exit('Usage (as root): guest-vt.py hyprland|plasma-wayland|plasma-x11')
if os.geteuid() != 0:
    sys.exit('Run as root or through passwordless sudo')

user = pwd.getpwnam('freebsd')
terminal = os.open('/dev/ttyv8', os.O_RDWR)
subprocess.run(['conscontrol', 'delete', 'ttyv0'], check=True)
subprocess.run(['conscontrol', 'add', 'ttyv0'], check=True)
with open('/dev/ttyv0', 'rb') as console:
    subprocess.run(['vidcontrol', '-s', '9'], stdin=console, check=True)
os.login_tty(terminal)
os.initgroups(user.pw_name, user.pw_gid)
os.setgid(user.pw_gid)
os.setuid(user.pw_uid)
os.chdir(user.pw_dir)
os.environ.update(HOME=user.pw_dir, USER=user.pw_name, LOGNAME=user.pw_name,
                  SHELL=user.pw_shell)
for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS', 'XDG_SESSION_COOKIE'):
    os.environ.pop(key, None)
log = os.open(f'{user.pw_dir}/drm-test/{sys.argv[1]}.log',
              os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
os.dup2(log, 1)
os.dup2(log, 2)
os.close(log)
os.execv('/bin/sh', ['sh', f'{user.pw_dir}/drm-test/guest-session.sh', sys.argv[1]])
