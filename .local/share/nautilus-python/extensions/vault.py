"""Nautilus right-click entry for the vault (~/.local/bin/vault).

"Unlock vault" / "Lock vault" in the background menu of your home folder and of
the vault itself, and on the vault folder. Unlocking opens the sudo shape prompt
in a small floating kitty, then shows the vault. Needs nautilus-python; Nautilus
loads it on its next start (nautilus -q).
"""

import os
import subprocess

from gi.repository import GObject, Nautilus

HOME = os.path.expanduser("~")
VAULT = os.path.join(HOME, ".vault")
CMD = os.path.join(HOME, ".local/bin/vault")


def _path(f):
    loc = f.get_location()
    return loc.get_path() if loc else None


class VaultMenu(GObject.GObject, Nautilus.MenuProvider):
    def _item(self, where):
        is_open = os.path.ismount(VAULT)
        item = Nautilus.MenuItem(
            name=f"VaultMenu::{where}",
            label="Lock vault" if is_open else "Unlock vault",
            tip="Your locked folder (~/.vault)",
        )
        item.connect("activate", self._activate, is_open)
        return item

    def _activate(self, _item, is_open):
        args = ["lock"] if is_open else ["open", "--gui", "--show"]
        subprocess.Popen([CMD, *args], stdin=subprocess.DEVNULL, start_new_session=True)

    def get_background_items(self, current_folder):
        p = _path(current_folder)
        if p and (p == HOME or p == VAULT or p.startswith(VAULT + "/")):
            return [self._item("background")]
        return []

    def get_file_items(self, files):
        if len(files) == 1 and _path(files[0]) == VAULT:
            return [self._item("file")]
        return []
