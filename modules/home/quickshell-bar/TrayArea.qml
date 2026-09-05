import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Controls as QQC2

Row {
    id: trayRow
    required property var overlays

    height: parent.height
    spacing: 2
    visible: SystemTray.items.values.length > 0

    Repeater {
        model: SystemTray.items

        Item {
            id: trayHost

            required property var modelData
            required property int index
            width: 24
            height: parent.height

            function showMenu(): void {
                trayMenu.reveal();
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
                    } else if (mouse.button === Qt.RightButton || trayHost.modelData.onlyMenu) {
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

            TrayMenu {
                id: trayMenu
                trayHost: trayHost
                overlayController: overlays
                overlayName: `tray-${trayHost.index}`
            }
        }
    }
}
