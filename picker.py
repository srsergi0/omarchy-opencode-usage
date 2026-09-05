#!/usr/bin/env python3
# GTK folder picker — external process (not inside quickshell) to avoid gvfs crash
# Prints selected folder to stdout, empty on cancel/error
import os, sys
try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk
except Exception as e:
    print("", end="")
    sys.exit(0)

dlg = Gtk.FileChooserDialog(
    title="Select folder for new opencode session",
    action=Gtk.FileChooserAction.SELECT_FOLDER
)
dlg.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, "Open", Gtk.ResponseType.ACCEPT)
dlg.set_default_response(Gtk.ResponseType.ACCEPT)
try:
    dlg.set_current_folder(os.path.expanduser("~"))
except: pass
# Windows-like: show hidden? keep default
# Add extra button to create folder? not needed
resp = dlg.run()
out = ""
if resp == Gtk.ResponseType.ACCEPT:
    try:
        out = dlg.get_filename() or ""
    except: pass
dlg.destroy()
# Ensure we close GTK properly without lingering
try:
    while Gtk.events_pending():
        Gtk.main_iteration()
except: pass
if out:
    print(out, end="")
    sys.stdout.flush()
sys.exit(0)
