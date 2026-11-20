#!/usr/bin/python3
# SPDX-License-Identifier: BSD-2-Clause
"""Capture QEMU GL scanout via VNC, using system GtkVnc (no visible host window)."""
from pathlib import Path
import sys


def capture(port, filename):
    import gi
    gi.require_version('GtkVnc', '2.0')
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, GtkVnc, GLib

    window = Gtk.OffscreenWindow()
    display = GtkVnc.Display.new()
    window.add(display)
    window.show_all()
    saved = False

    def save():
        nonlocal saved
        pixbuf = display.get_pixbuf()
        if pixbuf is not None:
            pixbuf.savev(str(Path(filename).resolve()), 'png', [], [])
            print(f'{filename}: {pixbuf.get_width()}x{pixbuf.get_height()}')
            saved = True
        Gtk.main_quit()
        return False

    display.connect('vnc-initialized', lambda *args: GLib.timeout_add(2000, save))
    display.connect('vnc-disconnected', lambda *args: Gtk.main_quit())
    GLib.timeout_add_seconds(15, lambda: (Gtk.main_quit(), False)[1])
    display.open_host('127.0.0.1', str(port))
    Gtk.main()
    display.close()
    window.destroy()
    if not saved:
        raise RuntimeError('VNC disconnected or timed out before capture')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('Usage: screenshot.py VNC_PORT OUTPUT.png')
    capture(int(sys.argv[1]), sys.argv[2])
