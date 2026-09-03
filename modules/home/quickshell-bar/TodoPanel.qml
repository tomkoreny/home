import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls as QQC2

Scope {
    id: root

    required property var service
    readonly property var targetScreen: Quickshell.screens.find(screen => screen.name === "@primaryOutput@") ?? null

    function dueLabel(task: var): string {
        if (!task)
            return "";
        if (!task.overdue)
            return "Today";
        const due = new Date(`${task.due}T12:00:00`);
        return `Overdue · ${Qt.formatDate(due, "d MMM")}`;
    }

    PanelWindow {
        id: panel

        screen: root.targetScreen ?? Quickshell.screens[0]
        visible: root.targetScreen !== null
        implicitWidth: 340
        implicitHeight: todoCard.implicitHeight
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        aboveWindows: false

        anchors.top: true
        anchors.right: true
        margins.top: 48
        margins.right: 12

        WlrLayershell.namespace: "tom-todos"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        mask: Region {
            item: todoCard
            radius: todoCard.radius
        }

        Rectangle {
            id: todoCard

            width: parent.width
            implicitHeight: content.implicitHeight + 20
            radius: 14
            color: "@surface@"
            border.width: 1
            border.color: "@border@"

            Column {
                id: content

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 8

                Row {
                    width: parent.width
                    height: 36
                    spacing: 8

                    Column {
                        width: parent.width - refreshButton.width - 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Text {
                            text: "Today"
                            color: "@text@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: root.service.overdueCount > 0
                                ? `${root.service.overdueCount} overdue · ${root.service.todayCount} today`
                                : root.service.todayCount === 1 ? "1 task" : `${root.service.todayCount} tasks`
                            color: root.service.overdueCount > 0 ? "@muted@" : "@subdued@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 10
                        }
                    }

                    Rectangle {
                        id: refreshButton

                        width: 30
                        height: 30
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 9
                        color: refreshMouse.containsMouse ? "@accentSurface@" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: root.service.loading ? "󰑓" : "󰑐"
                            color: root.service.stale ? "@muted@" : "@subdued@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: refreshMouse

                            anchors.fill: parent
                            enabled: !root.service.loading
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.service.refresh()

                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.delay: 500
                            QQC2.ToolTip.text: root.service.stale
                                ? `Stale · ${root.service.error}`
                                : "Refresh Notion tasks"
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 48
                    visible: root.service.items.length === 0
                    radius: 10
                    color: "@accentSurface@"
                    border.width: 1
                    border.color: "@border@"

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: root.service.loading ? "󰑓" : "󰄬"
                            color: "@accent@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 16
                        }

                        Text {
                            text: root.service.loading
                                ? "Loading tasks…"
                                : root.service.error !== "" && root.service.updatedAt === ""
                                    ? "Notion tasks unavailable"
                                    : "All clear"
                            color: "@text@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }
                }

                ListView {
                    id: taskList

                    width: parent.width
                    height: Math.min(count, 8) * 50
                    visible: count > 0
                    clip: true
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.service.items

                    delegate: Rectangle {
                        id: taskRow

                        required property var modelData
                        width: taskList.width
                        height: 46
                        radius: 10
                        color: titleMouse.containsMouse ? "@accentSurface@" : "transparent"

                        Rectangle {
                            id: checkbox

                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            height: 18
                            radius: 5
                            color: checkMouse.containsMouse ? "@accentSurface@" : "transparent"
                            border.width: 1
                            border.color: taskRow.modelData.overdue ? "@muted@" : "@accent@"

                            MouseArea {
                                id: checkMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.service.completeTask(taskRow.modelData)

                                QQC2.ToolTip.visible: containsMouse
                                QQC2.ToolTip.delay: 500
                                QQC2.ToolTip.text: "Complete"
                            }
                        }

                        Column {
                            anchors.left: checkbox.right
                            anchors.leftMargin: 9
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                text: taskRow.modelData.title
                                color: "@text@"
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                font.family: "@fontFamily@"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: root.dueLabel(taskRow.modelData)
                                color: taskRow.modelData.overdue ? "@muted@" : "@subdued@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 9
                            }
                        }

                        MouseArea {
                            id: titleMouse

                            anchors.left: checkbox.right
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.service.openTask(taskRow.modelData)

                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.delay: 500
                            QQC2.ToolTip.text: "Open in Notion"
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 36
                    visible: root.service.undoAvailable
                    radius: 10
                    color: "@accentSurface@"
                    border.width: 1
                    border.color: "@border@"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: undoButton.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.service.undoTask ? `Completed · ${root.service.undoTask.title}` : ""
                        color: "@subdued@"
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        font.family: "@fontFamily@"
                        font.pixelSize: 10
                    }

                    Text {
                        id: undoButton

                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Undo"
                        color: "@accent@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.service.undoLast()
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: root.service.stale && root.service.items.length > 0
                    text: `󰅖 Cached tasks · ${root.service.error}`
                    color: "@muted@"
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: "@fontFamily@"
                    font.pixelSize: 9
                }
            }
        }
    }
}
