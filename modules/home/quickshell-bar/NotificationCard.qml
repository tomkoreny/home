import Quickshell
import Quickshell.Services.Notifications
import QtQuick

Rectangle {
    id: card

    required property var entry
    property bool banner: false
    readonly property var notification: entry ? entry.notification : null
    readonly property var defaultAction: {
        if (!notification)
            return null;
        for (let i = 0; i < notification.actions.length; ++i) {
            const action = notification.actions[i];
            if (action.identifier === "default")
                return action;
        }
        return null;
    }
    readonly property string iconSource: {
        if (!notification)
            return "";
        if (notification.image !== "")
            return notification.image;
        if (notification.appIcon !== "")
            return Quickshell.iconPath(notification.appIcon, true);
        return "";
    }

    signal closeRequested
    signal hoverStateChanged(bool hovered)

    implicitHeight: content.implicitHeight + 20
    radius: 8
    color: banner ? "@surface@" : "@cardSurface@"
    border.width: 1
    border.color: notification
        && notification.urgency === NotificationUrgency.Critical ? "@muted@" : "@border@"

    MouseArea {
        anchors.fill: parent
        enabled: card.defaultAction !== null
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: card.defaultAction.invoke()
    }

    HoverHandler {
        onHoveredChanged: card.hoverStateChanged(hovered)
    }

    Column {
        id: content

        z: 1
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 10
        spacing: 7

        Item {
            width: parent.width
            height: Math.max(38, identity.implicitHeight)

            Image {
                id: appIcon

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36
                visible: card.iconSource !== ""
                source: card.iconSource
                sourceSize.width: 36
                sourceSize.height: 36
                fillMode: Image.PreserveAspectFit
            }

            Rectangle {
                anchors.fill: appIcon
                visible: !appIcon.visible
                radius: 8
                color: "@accentSurface@"

                Text {
                    anchors.centerIn: parent
                    text: "󰂚"
                    color: "@accent@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 18
                }
            }

            Column {
                id: identity

                anchors.left: appIcon.right
                anchors.leftMargin: 10
                anchors.right: closeButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    width: parent.width
                    text: card.notification ? card.notification.appName : ""
                    color: "@subdued@"
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: "@fontFamily@"
                    font.pixelSize: 11
                }

                Text {
                    width: parent.width
                    text: card.notification ? card.notification.summary : ""
                    color: "@text@"
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: "@fontFamily@"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }

            Rectangle {
                id: closeButton

                anchors.top: parent.top
                anchors.right: parent.right
                width: 24
                height: 24
                radius: 6
                color: closeMouse.containsMouse ? "@accentSurface@" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: closeMouse.containsMouse ? "@accent@" : "@subdued@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 17
                }

                MouseArea {
                    id: closeMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.closeRequested()
                }
            }
        }

        Text {
            width: parent.width
            visible: text !== ""
            text: card.notification ? card.notification.body : ""
            color: "@text@"
            wrapMode: Text.Wrap
            maximumLineCount: card.banner ? 4 : 8
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: "@fontFamily@"
            font.pixelSize: 12
            lineHeight: 1.15
        }

        Flow {
            width: parent.width
            spacing: 6
            visible: card.notification && card.notification.actions.length > 0

            Repeater {
                model: card.notification ? card.notification.actions : []

                Rectangle {
                    id: actionButton

                    required property var modelData
                    width: Math.min(actionLabel.implicitWidth + 18, content.width)
                    height: 28
                    radius: 6
                    color: actionMouse.containsMouse ? "@accentSurface@" : "transparent"
                    border.width: 1
                    border.color: actionMouse.containsMouse ? "@accent@" : "@border@"

                    Text {
                        id: actionLabel

                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, content.width - 18)
                        text: actionButton.modelData.text
                        color: actionMouse.containsMouse ? "@accent@" : "@text@"
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        font.family: "@fontFamily@"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: actionMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: actionButton.modelData.invoke()
                    }
                }
            }
        }
    }
}
