import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls as QQC2

Rectangle {
    id: workspaceIsland
    required property var bar

    x: 6
    y: 3
    width: workspaceRow.implicitWidth + 10
    height: 30
    radius: bar.singleWindowMode ? 0 : 8
    color: bar.singleWindowMode ? "transparent" : "@surface@"
    border.width: bar.singleWindowMode ? 0 : 1
    border.color: "@border@"

    Row {
        id: workspaceRow

        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: Hyprland.workspaces

            Rectangle {
                id: workspaceButton

                required property var modelData
                readonly property bool onThisMonitor: modelData.id > 0 && modelData.monitor !== null && modelData.monitor.name === bar.modelData.name

                visible: onThisMonitor
                width: visible ? 26 : 0
                height: 26
                radius: 13
                color: modelData.active ? "@accentSurface@" : "transparent"
                border.width: modelData.active ? 1 : 0
                border.color: "@accent@"

                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: workspaceButton.modelData.id
                    color: workspaceButton.modelData.active ? "@accent@" : "@subdued@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 12
                    font.weight: workspaceButton.modelData.active ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: workspaceButton.onThisMonitor
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: workspaceButton.modelData.activate()

                    QQC2.ToolTip.visible: containsMouse
                    QQC2.ToolTip.delay: 500
                    QQC2.ToolTip.text: `Workspace ${workspaceButton.modelData.id}`
                }
            }
        }
    }
}
