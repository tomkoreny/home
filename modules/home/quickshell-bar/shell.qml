import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls as QQC2

ShellRoot {
    id: root

    readonly property var outputs: @outputs@
    readonly property var audioNode: Pipewire.defaultAudioSink
    readonly property var audio: audioNode ? audioNode.audio : null
    readonly property bool audioMuted: audio ? audio.muted : false
    readonly property int volumePercent: audio ? Math.round(audio.volume * 100) : 0
    property bool showDate: false

    function audioIcon(): string {
        if (audioMuted)
            return "󰖁";
        if (volumePercent < 34)
            return "󰕿";
        if (volumePercent < 67)
            return "󰖀";
        return "󰕾";
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Notifications {
        id: notifications
    }

    IpcHandler {
        target: "notifications"

        function toggle(): bool {
            notifications.toggleCenter();
            return notifications.centerVisible;
        }

    }

    Variants {
        model: Quickshell.screens.filter(screen => root.outputs.includes(screen.name))

        PanelWindow {
            id: bar

            required property var modelData
            readonly property var displayMonitor: Hyprland.monitors.values.find(
                monitor => monitor.name === modelData.name
            ) ?? null
            readonly property var displayWorkspace: displayMonitor
                ? displayMonitor.activeWorkspace : null
            readonly property bool singleWindowMode: displayWorkspace !== null
                && displayWorkspace.toplevels.values.length === 1
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

            Rectangle {
                id: workspaceIsland

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
                            readonly property bool onThisMonitor: modelData.id > 0
                                && modelData.monitor !== null
                                && modelData.monitor.name === bar.modelData.name

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
                        width: audioText.implicitWidth + 12
                        height: parent.height

                        Text {
                            id: audioText

                            anchors.centerIn: parent
                            text: `${root.audioIcon()}  ${root.volumePercent}%`
                            color: root.audioMuted ? "@muted@" : "@text@"
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
                            QQC2.ToolTip.text: root.audioMuted
                                ? `Muted · ${root.volumePercent}%`
                                : `Volume · ${root.volumePercent}%`
                        }
                    }

                    Rectangle {
                        width: 1
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        visible: trayRow.visible
                        color: "@border@"
                    }

                    Row {
                        id: trayRow

                        height: parent.height
                        spacing: 2
                        visible: SystemTray.items.values.length > 0

                        Repeater {
                            model: SystemTray.items

                            Item {
                                id: trayHost

                                required property var modelData
                                width: 24
                                height: parent.height

                                function showMenu(): void {
                                    trayMenu.reset();
                                    trayMenu.visible = true;
                                }

                                Image {
                                    anchors.centerIn: parent
                                    width: 17
                                    height: 17
                                    source: trayHost.modelData.icon
                                    sourceSize.width: 17
                                    sourceSize.height: 17
                                    fillMode: Image.PreserveAspectFit
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.MiddleButton) {
                                            trayHost.modelData.secondaryActivate();
                                        } else if (mouse.button === Qt.RightButton
                                                   || trayHost.modelData.onlyMenu) {
                                            if (trayHost.modelData.hasMenu)
                                                trayHost.showMenu();
                                        } else {
                                            trayHost.modelData.activate();
                                        }
                                    }

                                    QQC2.ToolTip.visible: containsMouse && !trayMenu.visible
                                    QQC2.ToolTip.delay: 500
                                    QQC2.ToolTip.text: trayHost.modelData.tooltipTitle
                                }

                                PopupWindow {
                                    id: trayMenu

                                    property var currentMenu: trayHost.modelData.menu
                                    property var menuStack: []

                                    function reset(): void {
                                        currentMenu = trayHost.modelData.menu;
                                        menuStack = [];
                                    }

                                    function push(menuEntry): void {
                                        const stack = menuStack.slice();
                                        stack.push(currentMenu);
                                        menuStack = stack;
                                        currentMenu = menuEntry;
                                    }

                                    function pop(): void {
                                        if (menuStack.length === 0)
                                            return;

                                        const stack = menuStack.slice();
                                        currentMenu = stack.pop();
                                        menuStack = stack;
                                    }

                                    anchor.item: trayHost
                                    anchor.rect.x: trayHost.width - implicitWidth
                                    anchor.rect.y: trayHost.height + 6
                                    anchor.rect.width: 1
                                    anchor.rect.height: 1
                                    implicitWidth: 200
                                    implicitHeight: menuColumn.implicitHeight + 8
                                    color: "transparent"
                                    grabFocus: true
                                    visible: false

                                    onVisibleChanged: {
                                        if (!visible)
                                            reset();
                                    }

                                    QsMenuOpener {
                                        id: menuOpener
                                        menu: trayMenu.currentMenu
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 10
                                        color: "@surface@"
                                        border.width: 1
                                        border.color: "@border@"
                                    }

                                    FocusScope {
                                        anchors.fill: parent
                                        focus: trayMenu.visible

                                        Keys.onEscapePressed: event => {
                                            trayMenu.visible = false;
                                            event.accepted = true;
                                        }

                                        Column {
                                            id: menuColumn

                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.topMargin: 4
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 4
                                            spacing: 2

                                            Item {
                                                width: menuColumn.width
                                                height: 29
                                                visible: trayMenu.menuStack.length > 0

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 6
                                                    color: backMouse.containsMouse ? "@accentSurface@" : "transparent"
                                                }

                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 6
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 12
                                                    text: `‹  ${trayMenu.currentMenu.text}`
                                                    color: "@accent@"
                                                    elide: Text.ElideRight
                                                    font.family: "@fontFamily@"
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                }

                                                MouseArea {
                                                    id: backMouse

                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: trayMenu.pop()
                                                }
                                            }

                                            Rectangle {
                                                width: menuColumn.width - 8
                                                height: 1
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                visible: trayMenu.menuStack.length > 0
                                                color: "@border@"
                                            }

                                            Repeater {
                                                model: menuOpener.children

                                                Item {
                                                    id: menuEntry

                                                    required property var modelData
                                                    width: menuColumn.width
                                                    height: modelData.isSeparator ? 7 : 29

                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        anchors.leftMargin: 6
                                                        anchors.rightMargin: 6
                                                        height: 1
                                                        visible: menuEntry.modelData.isSeparator
                                                        color: "@border@"
                                                    }

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: 6
                                                        visible: !menuEntry.modelData.isSeparator
                                                        color: entryMouse.containsMouse
                                                            ? "@accentSurface@" : "transparent"
                                                        opacity: menuEntry.modelData.enabled ? 1 : 0.55

                                                        Row {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 6
                                                            anchors.rightMargin: 6
                                                            spacing: 6

                                                            Item {
                                                                id: leadingIndicator

                                                                width: 16
                                                                height: parent.height
                                                                visible: menuEntry.modelData.icon !== ""
                                                                    || menuEntry.modelData.buttonType !== QsMenuButtonType.None

                                                                Image {
                                                                    anchors.centerIn: parent
                                                                    width: 16
                                                                    height: 16
                                                                    visible: menuEntry.modelData.icon !== ""
                                                                    source: menuEntry.modelData.icon
                                                                    sourceSize.width: 16
                                                                    sourceSize.height: 16
                                                                    fillMode: Image.PreserveAspectFit
                                                                }

                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    visible: menuEntry.modelData.icon === ""
                                                                        && menuEntry.modelData.buttonType !== QsMenuButtonType.None
                                                                    text: menuEntry.modelData.checkState === Qt.Checked
                                                                        ? (menuEntry.modelData.buttonType === QsMenuButtonType.RadioButton
                                                                            ? "●" : "✓")
                                                                        : menuEntry.modelData.checkState === Qt.PartiallyChecked ? "−" : ""
                                                                    color: "@accent@"
                                                                    font.family: "@fontFamily@"
                                                                    font.pixelSize: 12
                                                                    font.weight: Font.Bold
                                                                }
                                                            }

                                                            Text {
                                                                width: parent.width
                                                                    - (leadingIndicator.visible ? leadingIndicator.width + parent.spacing : 0)
                                                                    - (submenuArrow.visible ? submenuArrow.width + parent.spacing : 0)
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: menuEntry.modelData.text
                                                                color: menuEntry.modelData.enabled ? "@text@" : "@subdued@"
                                                                elide: Text.ElideRight
                                                                font.family: "@fontFamily@"
                                                                font.pixelSize: 12
                                                            }

                                                            Text {
                                                                id: submenuArrow

                                                                width: 10
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                visible: menuEntry.modelData.hasChildren
                                                                text: "›"
                                                                color: "@subdued@"
                                                                horizontalAlignment: Text.AlignRight
                                                                font.family: "@fontFamily@"
                                                                font.pixelSize: 15
                                                            }
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: entryMouse

                                                        anchors.fill: parent
                                                        enabled: !menuEntry.modelData.isSeparator
                                                            && menuEntry.modelData.enabled
                                                        hoverEnabled: true
                                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                        onClicked: {
                                                            if (menuEntry.modelData.hasChildren) {
                                                                trayMenu.push(menuEntry.modelData);
                                                            } else {
                                                                menuEntry.modelData.triggered();
                                                                trayMenu.visible = false;
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

                    Rectangle {
                        width: 1
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: "@border@"
                    }

                    Item {
                        width: clockText.implicitWidth + 12
                        height: parent.height

                        Text {
                            id: clockText

                            anchors.centerIn: parent
                            text: root.showDate
                                ? Qt.formatDateTime(clock.date, "yyyy-MM-dd")
                                : `󰥔  ${Qt.formatDateTime(clock.date, "HH:mm")}`
                            color: "@text@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showDate = !root.showDate

                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.delay: 500
                            QQC2.ToolTip.text: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
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
                            text: notifications.doNotDisturb ? "󰂛" : "󰂚"
                            color: notifications.doNotDisturb
                                ? "@muted@"
                                : notifications.unreadCount > 0 ? "@accent@" : "@text@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 15
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: 1
                            anchors.rightMargin: 1
                            visible: notifications.unreadCount > 0
                            width: Math.max(14, unreadLabel.implicitWidth + 6)
                            height: 14
                            radius: 7
                            color: "@accent@"

                            Text {
                                id: unreadLabel

                                anchors.centerIn: parent
                                text: notifications.unreadCount
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
                            onClicked: notifications.toggleCenter()

                            QQC2.ToolTip.visible: containsMouse
                                && !notifications.centerVisible
                            QQC2.ToolTip.delay: 500
                            QQC2.ToolTip.text: notifications.doNotDisturb
                                ? `Do Not Disturb · ${notifications.unreadCount} unread`
                                : `${notifications.unreadCount} unread notifications`
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
                            onClicked: Quickshell.execDetached([
                                "@qs@", "-c", "tom-osd", "ipc", "call", "session", "reveal"
                            ])

                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.delay: 500
                            QQC2.ToolTip.text: "Session"
                        }
                    }
                }
            }
        }
    }
}
