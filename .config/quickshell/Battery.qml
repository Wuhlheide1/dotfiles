import Quickshell
import Quickshell.Services.UPower
import QtQuick

// Laptop battery indicator. Self-hides entirely on desktops (no battery
// device) — driven by UPower.displayDevice, which is the same aggregate
// device `upower -i /org/freedesktop/UPower/devices/DisplayDevice` reports.
Item {
    id: root

    property string fontFamily: "Adwaita Sans"
    property int fontSize: 14

    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev !== null && dev.ready && dev.isPresent
                                     && dev.type === UPowerDeviceType.Battery
    readonly property int pct: present ? Math.round(dev.percentage * 100) : 0
    readonly property bool charging: present
        && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.PendingCharge)
    readonly property bool low: present && !charging && pct <= 15

    visible: present
    implicitWidth: visible ? row.implicitWidth + 6 : 0
    implicitHeight: 26

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Text {
            // nf-fa battery-full/three-quarters/half/quarter/empty, or bolt while charging
            text: root.charging ? ""
                : root.pct >= 90 ? ""
                : root.pct >= 60 ? ""
                : root.pct >= 35 ? ""
                : root.pct >= 15 ? ""
                : ""
            color: root.low ? Colors.error : (root.charging ? Colors.primary : Colors.on_surface)
            font { family: "JetBrainsMono Nerd Font"; pixelSize: root.fontSize + 1 }
        }
        Text {
            text: root.pct + "%"
            color: root.low ? Colors.error : Colors.on_surface
            font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
        }
    }

    // hover tooltip: time to empty/full, when UPower actually reports one
    readonly property string eta: {
        if (!present) return ""
        var secs = charging ? dev.timeToFull : dev.timeToEmpty
        if (!secs || secs <= 0) return ""
        var h = Math.floor(secs / 3600), m = Math.round((secs % 3600) / 60)
        return (charging ? "Full in " : "Empty in ") + (h > 0 ? h + "h " : "") + m + "m"
    }

    HoverHandler { id: hover }
    Rectangle {
        visible: hover.hovered && root.eta.length > 0
        anchors.top: parent.bottom
        anchors.topMargin: 4
        anchors.horizontalCenter: parent.horizontalCenter
        width: tip.implicitWidth + 14
        height: tip.implicitHeight + 8
        radius: 8
        color: Colors.surface_container_high
        border.color: Colors.outline_variant
        border.width: 1
        Text {
            id: tip
            anchors.centerIn: parent
            text: root.eta
            color: Colors.on_surface
            font { family: root.fontFamily; pixelSize: 11 }
        }
    }
}
