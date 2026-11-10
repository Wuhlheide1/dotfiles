import QtQuick

// Use as `layer.effect: Tint { time: clock }` — recolours the layer with the
// flowing accent gradient while keeping its shape (alpha).
ShaderEffect {
    property real time
    property real period: 600
    readonly property vector2d res: Qt.vector2d(width, height)
    readonly property color c1: Theme.accent1
    readonly property color c2: Theme.accent2
    readonly property color c3: Theme.accent3

    fragmentShader: Qt.resolvedUrl("shaders/tint.frag.qsb")
}
