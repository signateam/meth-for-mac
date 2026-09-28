# dmgbuild settings for Meth's install window.
# Usage: dmgbuild -s script/dmg/settings.py -D app=dist/Meth.app -D background=script/dmg/background.tiff Meth dist/Meth.dmg
# The icon positions match the empty spaces in background.html (660x420 points).
import os.path

_here = os.path.dirname(os.path.abspath(globals().get("__file__") or "script/dmg/settings.py"))
application = defines.get("app", "dist/Meth.app")  # noqa: F821 (provided by dmgbuild)
appname = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
size = None
volume_name = "Meth"

files = [application]
symlinks = {"Applications": "/Applications"}
hide_extensions = [appname]

background = defines.get("background", os.path.join(_here, "background.tiff"))  # noqa: F821
window_rect = ((200, 120), (660, 420))
default_view = "icon-view"
show_icon_preview = False
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_tab_view = False
show_pathbar = False
sidebar_width = 0

icon_size = 128
text_size = 13
arrange_by = None
grid_spacing = 100
label_pos = "bottom"
icon_locations = {
    appname: (170, 190),
    "Applications": (490, 190),
}
