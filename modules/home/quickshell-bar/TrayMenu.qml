import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

PopupWindow {
    id: trayMenu
    required property var trayHost
    required property var overlayController
    required property string overlayName

    property var currentMenu: trayHost.modelData.menu
    property var menuStack: []

    function reset(): void {
        currentMenu = trayHost.modelData.menu;
        menuStack = [];
    }
    function reveal(): void {
        reset();
        overlayController.claim(overlayName);
        visible = true;
    }

    function closeMenu(): void {
        visible = false;
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
        if (!visible) {
            reset();
            overlayController.release(overlayName);
        }
    }

    Connections {
        target: trayMenu.overlayController

        function onDismissRequested(except: string): void {
            if (except !== trayMenu.overlayName && trayMenu.visible)
                trayMenu.closeMenu();
        }
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
            trayMenu.closeMenu();
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
                        color: entryMouse.containsMouse ? "@accentSurface@" : "transparent"
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
                                visible: menuEntry.modelData.icon !== "" || menuEntry.modelData.buttonType !== QsMenuButtonType.None

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
                                    visible: menuEntry.modelData.icon === "" && menuEntry.modelData.buttonType !== QsMenuButtonType.None
                                    text: menuEntry.modelData.checkState === Qt.Checked ? (menuEntry.modelData.buttonType === QsMenuButtonType.RadioButton ? "●" : "✓") : menuEntry.modelData.checkState === Qt.PartiallyChecked ? "−" : ""
                                    color: "@accent@"
                                    font.family: "@fontFamily@"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                            }

                            Text {
                                width: parent.width - (leadingIndicator.visible ? leadingIndicator.width + parent.spacing : 0) - (submenuArrow.visible ? submenuArrow.width + parent.spacing : 0)
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
                        enabled: !menuEntry.modelData.isSeparator && menuEntry.modelData.enabled
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (menuEntry.modelData.hasChildren) {
                                trayMenu.push(menuEntry.modelData);
                            } else {
                                menuEntry.modelData.triggered();
                                trayMenu.closeMenu();
                            }
                        }
                    }
                }
            }
        }
    }
}
