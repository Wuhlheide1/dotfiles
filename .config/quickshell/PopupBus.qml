pragma Singleton

import Quickshell
import QtQuick

// Coordinates the bar's flyout menus so only ONE is ever open at a time.
// Each menu picks a unique id string and:
//   * binds its overlay  `visible: PopupBus.current === "<id>"`
//   * toggles on its bar button with  PopupBus.toggle("<id>")
//   * closes (click-outside / Esc) with  PopupBus.close()
// Because every menu's visibility is bound to the same `current`, opening one
// instantly hides any other — and clicking a different bar button switches
// straight to it instead of leaving both open.
Singleton {
    id: bus

    property string current: ""

    function toggle(id) { current = (current === id ? "" : id) }
    function open(id)   { current = id }
    function close()    { current = "" }
    function isOpen(id) { return current === id }
}
