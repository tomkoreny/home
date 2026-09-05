import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls as QQC2

PanelWindow {
    id: bar
    required property var shellRoot
    required property var clockService
    required property var launcherController
    required property var notificationService
    required property var overlayController
    required property var timerPopupController
    required property var timerService
    required property var todoManagerController
    required property var todoService

    required property var modelData
    readonly property var displayMonitor: Hyprland.monitors.values.find(monitor => monitor.name === modelData.name) ?? null
    readonly property var displayWorkspace: displayMonitor ? displayMonitor.activeWorkspace : null
    readonly property bool singleWindowMode: displayWorkspace !== null && displayWorkspace.toplevels.values.length === 1
    readonly property bool primary: modelData.name === "@primaryOutput@"

    screen: modelData
    color: singleWindowMode ? "#000000" : "transparent"
    implicitHeight: 36
    exclusiveZone: 36
    aboveWindows: true

    anchors.top: true
    anchors.left: true
    anchors.right: true

    WlrLayershell.namespace: `tom-bar-${modelData.name}`
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        Region {
            item: workspaceIsland
            radius: workspaceIsland.radius
        }
        Region {
            item: statusIsland.visible ? statusIsland : null
            radius: statusIsland.radius
        }
    }

    WorkspaceStrip {
        id: workspaceIsland
        bar: bar
    }
    Rectangle {
        id: statusIsland

        x: parent.width - width - 6
        y: 3
        width: statusRow.implicitWidth + 12
        height: 30
        radius: bar.singleWindowMode ? 0 : 8
        visible: bar.primary
        color: bar.singleWindowMode ? "transparent" : "@surface@"
        border.width: bar.singleWindowMode ? 0 : 1
        border.color: "@border@"

        Row {
            id: statusRow

            anchors.centerIn: parent
            height: 26
            spacing: 3

            Item {
                width: herdrText.implicitWidth + 12
                height: parent.height

                Text {
                    id: herdrText

                    anchors.centerIn: parent
                    text: shellRoot.herdrBlocked > 0 ? `π ${shellRoot.herdrWorking}  󰅖 ${shellRoot.herdrBlocked}` : `π ${shellRoot.herdrWorking}`
                    color: shellRoot.herdrBlocked > 0 ? "@muted@" : shellRoot.herdrWorking > 0 ? "@accent@" : "@subdued@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: launcherController.toggleMode("herdr")

                    QQC2.ToolTip.visible: containsMouse
                    QQC2.ToolTip.delay: 500
                    QQC2.ToolTip.text: shellRoot.herdrSummary
                }
            }
            Rectangle {
                width: 1
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                color: "@border@"
            }

            Item {
                id: timerHost

                width: timerText.implicitWidth + 12
                height: parent.height
                Component.onCompleted: {
                    if (bar.primary)
                        shellRoot.timerAnchor = timerHost;
                }

                Text {
                    id: timerText

                    anchors.centerIn: parent
                    text: timerService.nextTimer ? `󰔛 ${timerService.formatRemaining(timerService.remaining(timerService.nextTimer))}${timerService.activeCount > 1 ? ` +${timerService.activeCount - 1}` : ""}` : "󰔛"
                    color: timerService.nextTimer ? "@accent@" : "@subdued@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: timerPopupController.toggle()

                    QQC2.ToolTip.visible: containsMouse && !timerPopupController.shown
                    QQC2.ToolTip.delay: 500
                    QQC2.ToolTip.text: timerService.nextTimer ? `${timerService.nextTimer.name} · ${timerService.formatRemaining(timerService.remaining(timerService.nextTimer))}` : "Create a timer"
                }
            }

            Rectangle {
                width: 1
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                color: "@border@"
            }

            AiUsageIndicator {
                root: shellRoot
            }
            Rectangle {
                width: 1
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                color: "@border@"
            }

            Item {
                width: todoText.implicitWidth + 12
                height: parent.height

                Text {
                    id: todoText

                    anchors.centerIn: parent
                    text: todoService.overdueCount > 0 ? `󰄬 ${todoService.todayCount}  󰅖 ${todoService.overdueCount}` : `󰄬 ${todoService.todayCount}`
                    color: todoService.overdueCount > 0 ? "@muted@" : todoService.todayCount > 0 ? "@accent@" : "@subdued@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: todoManagerController.toggle()

                    QQC2.ToolTip.visible: containsMouse
                    QQC2.ToolTip.delay: 500
                    QQC2.ToolTip.text: todoService.stale ? `Notion tasks · stale · ${todoService.error}` : `${todoService.overdueCount} overdue · ${todoService.todayCount} today`
                }
            }

            Rectangle {
                width: 1
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                color: "@border@"
            }

            Item {
                width: audioText.implicitWidth + 12
                height: parent.height

                Text {
                    id: audioText

                    anchors.centerIn: parent
                    text: `${shellRoot.audioIcon()}  ${shellRoot.volumePercent}%`
                    color: shellRoot.audioMuted ? "@muted@" : "@text@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["@pavucontrol@"])

                    QQC2.ToolTip.visible: containsMouse
                    QQC2.ToolTip.delay: 500
                    QQC2.ToolTip.text: shellRoot.audioMuted ? `Muted · ${shellRoot.volumePercent}%` : `Volume · ${shellRoot.volumePercent}%`
                }
            }

            Rectangle {
                width: 1
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                visible: trayRow.visible
                color: "@border@"
            }

            TrayArea {
                id: trayRow
                overlays: overlayController
            }
            Rectangle {
                width: 1
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                color: "@border@"
            }

            Item {
                width: clockRows.implicitWidth + 12
                height: parent.height

                Column {
                    id: clockRows

                    anchors.centerIn: parent
                    spacing: -1

                    Text {
                        text: `󰥔 ${Qt.formatDateTime(clockService.date, shellRoot.showSeconds ? "HH:mm:ss" : "HH:mm")}`
                        color: "@text@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: `󰃭 ${Qt.formatDateTime(clockService.date, "ddd d MMM")}`
                        color: "@text@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shellRoot.showSeconds = !shellRoot.showSeconds

                    QQC2.ToolTip.visible: containsMouse
                    QQC2.ToolTip.delay: 500
                    QQC2.ToolTip.text: Qt.formatDateTime(clockService.date, "dddd, d MMMM yyyy")
                }
            }

            Rectangle {
                width: 1
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                color: "@border@"
            }

            Item {
                id: notificationBell

                width: 34
                height: parent.height

                Text {
                    anchors.centerIn: parent
                    text: notificationService.doNotDisturb ? "󰂛" : "󰂚"
                    color: notificationService.doNotDisturb ? "@muted@" : notificationService.unreadCount > 0 ? "@accent@" : "@text@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 15
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 1
                    anchors.rightMargin: 1
                    visible: notificationService.unreadCount > 0
                    width: Math.max(14, unreadLabel.implicitWidth + 6)
                    height: 14
                    radius: 7
                    color: "@accent@"

                    Text {
                        id: unreadLabel

                        anchors.centerIn: parent
                        text: notificationService.unreadCount
                        color: "#11111b"
                        font.family: "@fontFamily@"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: notificationService.toggleCenter()

                    QQC2.ToolTip.visible: containsMouse && !notificationService.centerVisible
                    QQC2.ToolTip.delay: 500
                    QQC2.ToolTip.text: notificationService.doNotDisturb ? `Do Not Disturb · ${notificationService.unreadCount} unread` : `${notificationService.unreadCount} unread notifications`
                }
            }

            Rectangle {
                width: 1
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                color: "@border@"
            }

            Item {
                width: 28
                height: parent.height

                Text {
                    anchors.centerIn: parent
                    text: "󰐥"
                    color: "@muted@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 14
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        overlayController.dismissAll();
                        Quickshell.execDetached(["@qs@", "-c", "tom-osd", "ipc", "call", "session", "reveal"]);
                    }

                    QQC2.ToolTip.visible: containsMouse
                    QQC2.ToolTip.delay: 500
                    QQC2.ToolTip.text: "Session"
                }
            }
        }
    }
}
