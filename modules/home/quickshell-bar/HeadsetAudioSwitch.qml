import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Follows the Arctis headset's power switch with the default audio sink.
// Headset off: leave the Arctis for the fallback sink, but only while the
// Arctis is the default. Headset back on after an observed off: return to the
// Arctis, but only while the fallback is still the default. Any other default
// was picked by hand and is left alone.
Scope {
    id: root

    required property var headset
    required property string fallbackSink
    readonly property string headsetSink: "alsa_output.usb-SteelSeries_Arctis_Pro_Wireless-00.analog-stereo"
    // Last observed power state, "on" or "off"; ignores absent/error gaps.
    property string power: ""

    function node(name: string): var {
        return Pipewire.nodes.values.find(candidate => candidate.name === name) ?? null;
    }

    function move(from: string, to: string): void {
        if (Pipewire.defaultAudioSink?.name !== from)
            return;
        const target = node(to);
        if (target === null) {
            console.warn(`Headset audio switch: sink ${to} is unavailable`);
            return;
        }
        Pipewire.preferredDefaultAudioSink = target;
    }

    Connections {
        target: root.headset

        function onStatusChanged(): void {
            const status = root.headset.status;
            if (root.fallbackSink === "" || (status !== "on" && status !== "off"))
                return;
            const previous = root.power;
            root.power = status;
            if (status === "off")
                root.move(root.headsetSink, root.fallbackSink);
            else if (previous === "off")
                root.move(root.fallbackSink, root.headsetSink);
        }
    }
}
