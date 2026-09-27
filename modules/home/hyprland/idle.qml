import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    readonly property var outputs: ["DP-2", "HDMI-A-2", "DP-3"]
    property string mode: "awake"
    property bool inputArmed: false

    function blank(): bool {
        // hypridle's own blank stage also fires after Super+L; keep the
        // running power-off countdown instead of restarting it.
        if (mode === "blank")
            return true;
        mode = "blank";
        inputArmed = false;
        armInput.restart();
        powerOff.restart();
        return true;
    }

    function wake(): bool {
        mode = "awake";
        inputArmed = false;
        powerOff.stop();
        return true;
    }

    function requestWake(): void {
        if (mode !== "blank" || !inputArmed)
            return;
        inputArmed = false;
        Quickshell.execDetached(["@oledIdle@", "wake"]);
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Timer {
        id: armInput
        interval: 500
        onTriggered: root.inputArmed = true
    }

    // The clock stage lasts ten minutes however it was entered (idle or
    // Super+L), then every output powers off.
    Timer {
        id: powerOff
        interval: 600000
        onTriggered: Quickshell.execDetached(["@oledIdle@", "dpms-off"])
    }

    IpcHandler {
        target: "idle"

        function blank(): bool {
            return root.blank();
        }

        function wake(): bool {
            return root.wake();
        }
    }

    Variants {
        model: Quickshell.screens.filter(screen => root.outputs.includes(screen.name))

        PanelWindow {
            id: saver

            required property var modelData
            // Drift the clock to a new spot every minute so no pixels stay lit.
            readonly property int clockStep: Math.floor(clock.date.getTime() / 60000)

            screen: modelData
            visible: root.mode === "blank"
            color: "#000000"
            aboveWindows: true
            exclusiveZone: 0

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            WlrLayershell.namespace: `tom-idle-${modelData.name}`
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: root.mode === "blank"
                && modelData.name === "DP-2"
                ? WlrKeyboardFocus.Exclusive
                : WlrKeyboardFocus.None

            FocusScope {
                anchors.fill: parent
                focus: saver.visible

                Keys.onPressed: event => {
                    if (!root.inputArmed)
                        return;
                    event.accepted = true;
                    root.requestWake();
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.BlankCursor
                    onPositionChanged: root.requestWake()
                    onPressed: mouse => {
                        mouse.accepted = true;
                        root.requestWake();
                    }
                }

                Text {
                    visible: saver.modelData.name === "DP-2"
                    x: 96 + (saver.clockStep * 7919 % 101) / 100 * (parent.width - width - 192)
                    y: 96 + (saver.clockStep * 104729 % 89) / 88 * (parent.height - height - 192)
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    color: "#262626"
                    font.family: "@fontFamily@"
                    font.pixelSize: 64
                    font.weight: Font.Light
                }
            }
        }
    }
}
