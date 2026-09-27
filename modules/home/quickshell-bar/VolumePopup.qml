import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Output and input volume, device choice, and per-app volume.
Scope {
    id: root

    required property Item anchorItem
    required property var overlayController
    readonly property string overlayName: "volume"
    property bool shown: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var audioNodes: Pipewire.nodes.values.filter(node => node.audio !== null)
    readonly property var sinks: audioNodes.filter(node => !node.isStream && node.isSink)
    readonly property var sources: audioNodes.filter(node => !node.isStream && !node.isSink)
    // For streams, isSink means the stream plays into a sink
    // (Stream/Output/Audio); the others are recording.
    readonly property var playing: audioNodes.filter(node => node.isStream && node.isSink)
    readonly property var recording: audioNodes.filter(node => node.isStream && !node.isSink)

    function reveal(): void {
        overlayController.claim(overlayName);
        shown = true;
    }

    function close(): void {
        shown = false;
        overlayController.release(overlayName);
    }

    function toggle(): void {
        if (shown)
            close();
        else
            reveal();
    }

    function deviceName(node): string {
        return node.description || node.nickname || node.name;
    }

    function appName(node): string {
        return node.properties["application.name"] || node.description || node.name;
    }

    function micStatus(): string {
        if (recording.length === 0)
            return "Not in use";
        const names = [...new Set(recording.map(node => appName(node)))];
        return `In use by ${names.join(", ")}`;
    }

    // Volumes and names are only filled in for tracked nodes.
    PwObjectTracker {
        objects: root.shown ? root.audioNodes : [root.sink, root.source].filter(node => node)
    }

    Connections {
        target: root.overlayController

        function onDismissRequested(except: string): void {
            if (except !== root.overlayName && root.shown)
                root.close();
        }
    }

    component SectionTitle: Text {
        color: "@subdued@"
        font.family: "@fontFamily@"
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }

    component MuteButton: Rectangle {
        id: muteButton

        required property var audio
        required property string icon
        required property string mutedIcon
        readonly property bool muted: audio ? audio.muted : false

        width: 28
        height: 28
        radius: 8
        color: muted ? "@accentSurface@" : muteMouse.containsMouse ? "@surface@" : "transparent"
        border.width: 1
        border.color: muted ? "@muted@" : "@border@"

        Text {
            anchors.centerIn: parent
            text: muteButton.muted ? muteButton.mutedIcon : muteButton.icon
            color: muteButton.muted ? "@muted@" : "@text@"
            font.family: "@fontFamily@"
            font.pixelSize: 14
        }

        MouseArea {
            id: muteMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (muteButton.audio)
                    muteButton.audio.muted = !muteButton.audio.muted;
            }
        }
    }

    // Drag, click, or scroll to set a node's volume from 0 to 100%.
    component VolumeSlider: Item {
        id: slider

        required property var audio
        readonly property real level: audio ? Math.max(0, Math.min(1, audio.volume)) : 0
        readonly property bool muted: audio ? audio.muted : false

        height: 28

        function set(fraction: real): void {
            if (audio)
                audio.volume = Math.max(0, Math.min(1, fraction));
        }

        Rectangle {
            id: track

            anchors.left: parent.left
            anchors.right: percent.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: 3
            color: "@surface@"
            border.width: 1
            border.color: "@border@"

            Rectangle {
                width: parent.width * slider.level
                height: parent.height
                radius: parent.radius
                color: slider.muted ? "@subdued@" : "@accent@"
            }

            Rectangle {
                x: parent.width * slider.level - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                radius: 7
                color: slider.muted ? "@subdued@" : "@text@"
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -10
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => slider.set((mouse.x - 10) / track.width)
                onPositionChanged: mouse => {
                    if (pressed)
                        slider.set((mouse.x - 10) / track.width);
                }
                onWheel: wheel => slider.set(slider.level + (wheel.angleDelta.y > 0 ? 0.02 : -0.02))
            }
        }

        Text {
            id: percent

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(slider.level * 100)}%`
            color: slider.muted ? "@subdued@" : "@text@"
            font.family: "@fontFamily@"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }

    // One volume row: mute button, then the slider.
    component VolumeRow: Row {
        id: volumeRow

        required property var audio
        required property string icon
        required property string mutedIcon

        width: parent.width
        spacing: 10

        MuteButton {
            audio: volumeRow.audio
            icon: volumeRow.icon
            mutedIcon: volumeRow.mutedIcon
        }

        VolumeSlider {
            width: volumeRow.width - 38
            audio: volumeRow.audio
        }
    }

    // The device list for one direction; the default one is highlighted.
    component DeviceList: Column {
        id: deviceList

        required property var nodes
        required property var current
        signal chosen(var node)

        width: parent.width
        spacing: 2

        Repeater {
            model: deviceList.nodes

            Rectangle {
                id: deviceRow

                required property var modelData
                readonly property bool selected: modelData === deviceList.current

                width: deviceList.width
                height: 28
                radius: 8
                color: selected ? "@accentSurface@" : deviceMouse.containsMouse ? "@surface@" : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.deviceName(deviceRow.modelData)
                    color: deviceRow.selected ? "@accent@" : "@text@"
                    elide: Text.ElideRight
                    font.family: "@fontFamily@"
                    font.pixelSize: 12
                    font.weight: deviceRow.selected ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    id: deviceMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: deviceList.chosen(deviceRow.modelData)
                }
            }
        }
    }

    PopupWindow {
        anchor.item: root.anchorItem
        anchor.rect.x: root.anchorItem ? root.anchorItem.width - implicitWidth : 0
        anchor.rect.y: root.anchorItem ? root.anchorItem.height + 8 : 0
        anchor.rect.width: 1
        anchor.rect.height: 1
        implicitWidth: 380
        implicitHeight: card.implicitHeight
        color: "transparent"
        visible: root.shown && root.anchorItem !== null

        Rectangle {
            id: card

            width: parent.width
            implicitHeight: content.implicitHeight + 24
            radius: 14
            color: "@opaqueSurface@"
            border.width: 1
            border.color: "@border@"

            Column {
                id: content

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        width: parent.width - closeButton.width - 8
                        text: "Sound"
                        color: "@text@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }

                    Text {
                        id: closeButton

                        width: 22
                        text: "󰅖"
                        color: "@subdued@"
                        horizontalAlignment: Text.AlignHCenter
                        font.family: "@fontFamily@"
                        font.pixelSize: 14

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                SectionTitle {
                    text: "Output"
                }

                VolumeRow {
                    audio: root.sink ? root.sink.audio : null
                    icon: "󰕾"
                    mutedIcon: "󰖁"
                }

                DeviceList {
                    nodes: root.sinks
                    current: root.sink
                    onChosen: node => Pipewire.preferredDefaultAudioSink = node
                }

                Item {
                    width: 1
                    height: 4
                }

                SectionTitle {
                    text: "Input"
                }

                VolumeRow {
                    audio: root.source ? root.source.audio : null
                    icon: "󰍬"
                    mutedIcon: "󰍭"
                }

                Text {
                    width: parent.width
                    text: root.micStatus()
                    color: root.recording.length > 0 ? "@accent@" : "@subdued@"
                    elide: Text.ElideRight
                    font.family: "@fontFamily@"
                    font.pixelSize: 11
                }

                DeviceList {
                    nodes: root.sources
                    current: root.source
                    onChosen: node => Pipewire.preferredDefaultAudioSource = node
                }

                Item {
                    width: 1
                    height: 4
                    visible: root.playing.length > 0
                }

                SectionTitle {
                    visible: root.playing.length > 0
                    text: "Apps"
                }

                Repeater {
                    model: root.playing

                    Column {
                        id: appRow

                        required property var modelData

                        width: content.width
                        spacing: 2

                        Text {
                            width: parent.width
                            text: root.appName(appRow.modelData)
                            color: "@text@"
                            elide: Text.ElideRight
                            font.family: "@fontFamily@"
                            font.pixelSize: 12
                        }

                        VolumeRow {
                            audio: appRow.modelData.audio
                            icon: "󰕾"
                            mutedIcon: "󰖁"
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 30

                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: moreText.implicitWidth + 20
                        height: 26
                        radius: 8
                        color: moreMouse.containsMouse ? "@accentSurface@" : "transparent"
                        border.width: 1
                        border.color: "@border@"

                        Text {
                            id: moreText

                            anchors.centerIn: parent
                            text: "More settings"
                            color: "@text@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: moreMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close();
                                Quickshell.execDetached(["@pavucontrol@"]);
                            }
                        }
                    }
                }
            }
        }
    }
}
