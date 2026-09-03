import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls as QQC2

Scope {
    id: root

    required property var service
    required property var anchorItem
    property bool shown: false
    property string inputError: ""

    function toggle(): void {
        shown = !shown;
        if (shown)
            Qt.callLater(() => timerInput.forceActiveFocus());
    }

    function add(value: string): void {
        const query = value.trim();
        if (query === "")
            return;
        inputError = "";
        service.addTimer(query);
    }

    Connections {
        target: root.service

        function onTimerCreated(name: string): void {
            timerInput.text = "";
            root.inputError = "";
            timerInput.forceActiveFocus();
        }

        function onTimerCreationFailed(message: string): void {
            root.inputError = message;
            timerInput.forceActiveFocus();
        }
    }

    PopupWindow {
        anchor.item: root.anchorItem
        anchor.rect.x: root.anchorItem.width - implicitWidth
        anchor.rect.y: root.anchorItem.height + 8
        anchor.rect.width: 1
        anchor.rect.height: 1
        implicitWidth: 360
        implicitHeight: timerCard.implicitHeight
        color: "transparent"
        visible: root.shown

        WlrLayershell.keyboardFocus: root.shown
            ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None

        Rectangle {
            id: timerCard

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
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        width: parent.width - closeButton.width - 8
                        text: root.service.activeCount === 0
                            ? "Timers"
                            : `Timers · ${root.service.activeCount} active`
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
                            onClicked: root.shown = false
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 40
                    radius: 10
                    color: "@surface@"
                    border.width: timerInput.activeFocus ? 1 : 0
                    border.color: "@accent@"

                    TextInput {
                        id: timerInput

                        anchors.left: parent.left
                        anchors.right: addButton.left
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        color: "@text@"
                        selectionColor: "@accent@"
                        selectedTextColor: "#11111b"
                        font.family: "@fontFamily@"
                        font.pixelSize: 14
                        clip: true

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.add(text);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.shown = false;
                                event.accepted = true;
                            }
                        }
                    }

                    Text {
                        anchors.left: timerInput.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: timerInput.text.length === 0
                        text: "20m pasta"
                        color: "@subdued@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 14
                    }

                    Rectangle {
                        id: addButton

                        anchors.right: parent.right
                        anchors.rightMargin: 5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 56
                        height: 30
                        radius: 8
                        color: "@accentSurface@"
                        border.width: 1
                        border.color: "@border@"

                        Text {
                            anchors.centerIn: parent
                            text: "Add"
                            color: "@accent@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.add(timerInput.text)
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: ["5m", "10m", "25m", "1h"]

                        Rectangle {
                            required property string modelData
                            width: (content.width - 18) / 4
                            height: 28
                            radius: 8
                            color: presetMouse.containsMouse ? "@accentSurface@" : "@surface@"
                            border.width: 1
                            border.color: "@border@"

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: "@text@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 12
                            }

                            MouseArea {
                                id: presetMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.add(parent.modelData)
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: root.inputError !== ""
                    text: root.inputError
                    color: "@muted@"
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.family: "@fontFamily@"
                    font.pixelSize: 11
                }

                Text {
                    width: parent.width
                    visible: root.service.activeCount === 0
                    text: "No active timers"
                    color: "@subdued@"
                    horizontalAlignment: Text.AlignHCenter
                    font.family: "@fontFamily@"
                    font.pixelSize: 13
                }

                ListView {
                    id: timerList

                    width: parent.width
                    height: Math.min(count, 5) * 54
                    visible: count > 0
                    clip: true
                    spacing: 4
                    model: root.service.timers

                    delegate: Rectangle {
                        id: timerRow

                        required property var modelData
                        width: timerList.width
                        height: 50
                        radius: 10
                        color: "@surface@"

                        Column {
                            anchors.left: parent.left
                            anchors.right: controls.left
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                text: timerRow.modelData.name
                                color: "@text@"
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                font.family: "@fontFamily@"
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: timerRow.modelData.paused
                                    ? `${root.service.formatRemaining(root.service.remaining(timerRow.modelData))} · paused`
                                    : root.service.formatRemaining(root.service.remaining(timerRow.modelData))
                                color: timerRow.modelData.paused ? "@subdued@" : "@accent@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 11
                            }
                        }

                        Row {
                            id: controls

                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Repeater {
                                model: [
                                    {
                                        glyph: timerRow.modelData.paused ? "󰐊" : "󰏤",
                                        action: timerRow.modelData.paused ? "resume" : "pause"
                                    },
                                    { glyph: "󰅖", action: "cancel" }
                                ]

                                Rectangle {
                                    required property var modelData
                                    width: 30
                                    height: 30
                                    radius: 8
                                    color: actionMouse.containsMouse ? "@accentSurface@" : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData.glyph
                                        color: parent.modelData.action === "cancel" ? "@muted@" : "@subdued@"
                                        font.family: "@fontFamily@"
                                        font.pixelSize: 13
                                    }

                                    MouseArea {
                                        id: actionMouse

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (parent.modelData.action === "pause")
                                                root.service.pauseTimer(timerRow.modelData.id);
                                            else if (parent.modelData.action === "resume")
                                                root.service.resumeTimer(timerRow.modelData.id);
                                            else
                                                root.service.cancelTimer(timerRow.modelData.id);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
