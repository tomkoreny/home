import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    readonly property var outputs: ["DP-2", "HDMI-A-2", "DP-3"]
    property string mode: "awake"
    property bool inputArmed: false

    function dim(): bool {
        mode = "awake";
        inputArmed = false;
        return true;
    }

    function blank(): bool {
        mode = "blank";
        inputArmed = false;
        armInput.restart();
        return true;
    }

    function wake(): bool {
        mode = "awake";
        inputArmed = false;
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

    IpcHandler {
        target: "idle"

        function dim(): bool {
            return root.dim();
        }

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
            readonly property int clockSlot: Math.floor(clock.date.getTime() / 300000) % 4

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
                    onPositionChanged: root.requestWake()
                    onPressed: mouse => {
                        mouse.accepted = true;
                        root.requestWake();
                    }
                }

                Text {
                    visible: saver.modelData.name === "DP-3"
                    x: saver.clockSlot % 2 === 0 ? 48 : parent.width - width - 48
                    y: saver.clockSlot < 2 ? 64 : parent.height - height - 64
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    color: "#6c7086"
                    font.family: "@fontFamily@"
                    font.pixelSize: 28
                    font.weight: Font.Medium
                }
            }
        }
    }
}
