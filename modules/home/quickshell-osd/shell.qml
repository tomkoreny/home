import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    property bool shown: false
    property string kind: "volume"
    property real level: 0
    property bool muted: false
    readonly property var targetScreen: {
        for (let i = 0; i < Quickshell.screens.length; ++i) {
            const candidate = Quickshell.screens[i];
            if (candidate.name === "@output@")
                return candidate;
        }
        return null;
    }

    function reveal(nextKind: string, nextLevel: real, nextMuted: bool): void {
        kind = nextKind;
        level = Math.max(0, Math.min(1, nextLevel));
        muted = nextMuted;
        shown = true;
        dismiss.restart();
    }

    function icon(): string {
        if (kind === "brightness")
            return "󰃠";
        if (muted)
            return "󰖁";
        if (level < 0.34)
            return "󰕿";
        if (level < 0.67)
            return "󰖀";
        return "󰕾";
    }

    screen: targetScreen ?? Quickshell.screens[0]
    visible: targetScreen !== null && (shown || panel.opacity > 0.01)
    color: "transparent"
    mask: Region {}
    implicitWidth: 420
    implicitHeight: 68
    exclusiveZone: 0
    aboveWindows: true

    anchors.bottom: true
    margins.bottom: 72

    WlrLayershell.namespace: "tom-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: panel

        anchors.fill: parent
        radius: height / 2
        color: "@surface@"
        border.width: 1
        border.color: root.muted ? "@muted@" : "@border@"
        opacity: root.shown ? 1 : 0
        transform: Translate {
            y: root.shown ? 0 : 18
            Behavior on y {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 20
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                radius: 21
                color: root.muted ? "@mutedSurface@" : "@accentSurface@"

                Text {
                    anchors.centerIn: parent
                    text: root.icon()
                    color: root.muted ? "@muted@" : "@accent@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 22
                }
            }

            Rectangle {
                id: track

                Layout.fillWidth: true
                Layout.preferredHeight: 8
                radius: 4
                color: "@track@"

                Rectangle {
                    height: parent.height
                    width: parent.width * root.level
                    radius: parent.radius
                    color: root.muted ? "@muted@" : "@accent@"

                    Behavior on width {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            Text {
                Layout.preferredWidth: 54
                horizontalAlignment: Text.AlignRight
                text: root.muted ? "MUTE" : `${Math.round(root.level * 100)}%`
                color: root.muted ? "@muted@" : "@text@"
                font.family: "@fontFamily@"
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
        }
    }

    Timer {
        id: dismiss
        interval: 1500
        onTriggered: root.shown = false
    }

    IpcHandler {
        target: "osd"

        function showVolume(value: real, isMuted: bool): void {
            root.reveal("volume", value, isMuted);
        }

        function showBrightness(percent: int): void {
            root.reveal("brightness", percent / 100, false);
        }
    }
}
