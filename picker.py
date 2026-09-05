#!/usr/bin/env python3
# GTK folder picker — external process (avoids quickshell gvfs crash)
# Uses FileChooserNative (portal, floating via Omarchy's xdg-desktop-portal-gtk rule)
# Falls back to FileChooserDialog if Native unavailable
# Prints selected folder to stdout, empty on cancel/error
# Force portal to get floating window on any machine (no Hyprland rule needed)
import os, sys
os.environ.setdefault("GTK_USE_PORTAL", "1")
# Ensure portal sees correct desktop
os.environ.setdefault("XDG_CURRENT_DESKTOP", "Hyprland")
try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk
except Exception:
    print("", end="")
    sys.exit(0)

out = ""
dlg = None

def _ensure_fallback_floating(win):
    try:
        try:
            win.set_wmclass("TUI.float", "TUI.float")
        except: pass
        try:
            win.set_default_size(900, 600)
        except: pass
        try:
            import subprocess, threading, time
            def _float():
                time.sleep(0.3)
                subprocess.run(["hyprctl", "dispatch", "togglefloating", "active"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.run(["hyprctl", "dispatch", "centerwindow"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            threading.Thread(target=_float, daemon=True).start()
        except: pass
    except: pass

try:
    # Try Native (portal) — floating by default via Omarchy's system.lua
    if hasattr(Gtk, "FileChooserNative"):
        dlg = Gtk.FileChooserNative.new(
            "Select folder for new opencode session",
            None,
            Gtk.FileChooserAction.SELECT_FOLDER,
            "_Open",
            "_Cancel"
        )
        try:
            dlg.set_current_folder(os.path.expanduser("~"))
        except: pass
        resp = dlg.run()
        if resp == Gtk.ResponseType.ACCEPT:
            try:
                out = dlg.get_filename() or ""
            except: pass
        try:
            dlg.destroy()
        except: pass
    else:
        raise Exception("no native")
except Exception:
    # Fallback to Dialog (requires Hyprland float rule, but Native should cover most)
    try:
        if dlg:
            try: dlg.destroy()
            except: pass
        dlg2 = Gtk.FileChooserDialog(
            title="Select folder for new opencode session",
            action=Gtk.FileChooserAction.SELECT_FOLDER
        )
        dlg2.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, "Open", Gtk.ResponseType.ACCEPT)
        dlg2.set_default_response(Gtk.ResponseType.ACCEPT)
        try:
            dlg2.set_current_folder(os.path.expanduser("~"))
        except: pass
        _ensure_fallback_floating(dlg2)
        resp2 = dlg2.run()
        if resp2 == Gtk.ResponseType.ACCEPT:
            try:
                out = dlg2.get_filename() or ""
            except: pass
        try:
            dlg2.destroy()
        except: pass
    except: pass

# Drain GTK events
try:
    while Gtk.events_pending():
        Gtk.main_iteration()
except: pass

if out:
    print(out, end="")
    sys.stdout.flush()
sys.exit(0)
