pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ~/.config/circle/settings.json — the model picker writes `model`; the rest
// is hand-editable (add models, change the translate language). Each model:
//   id       stable key stored in `model`
//   label    shown in the picker
//   note     second line in the picker
//   provider antigravity | claude | gemini | local   (see backend.py)
//   model    the provider's model name
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/circle`
    property alias model: adapter.model
    property alias translateTo: adapter.translateTo
    property alias models: adapter.models

    readonly property var current: models.find(m => m.id === model) ?? models[0]

    function choose(id: string): void {
        adapter.model = id;
        file.writeAdapter();
    }

    FileView {
        id: file

        path: `${root.dir}/settings.json`
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter

            property string model: "gemini"
            property string translateTo: "English"
            property var models: [
                { id: "gemini", label: "Gemini 3.8 Flash", note: "Google AI Pro · quick, searches the web", provider: "antigravity", model: "gemini-3.8-flash-low" },
                { id: "gemini-argon", label: "Gemini 4 Argon", note: "Google AI Pro · smartest, ~10 s", provider: "antigravity", model: "gemini-4-argon-low" },
                { id: "gemini-lite", label: "Gemini Flash-Lite", note: "Google · free key, instant", provider: "gemini", model: "gemini-flash-lite-latest" },
                { id: "local", label: "Gemma 4 12B", note: "This PC · free, private", provider: "local", model: "gemma4:12b" },
                { id: "haiku", label: "Claude Haiku", note: "Claude Pro · light on usage", provider: "claude", model: "haiku" },
                { id: "sonnet", label: "Claude Sonnet", note: "Claude Pro · heavier on usage", provider: "claude", model: "sonnet" }
            ]
        }
    }
}
