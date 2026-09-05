import Quickshell
import QtQuick

PopupWindow {
    id: root

    required property Item anchorItem
    required property bool hovered
    required property string text
    property bool alignRight: false
    property int delay: 500
    property bool shown: false

    anchor.item: anchorItem
    anchor.rect.x: alignRight ? anchorItem.width - implicitWidth : 0
    anchor.rect.y: anchorItem.height + 6
    anchor.rect.width: 1
    anchor.rect.height: 1
    implicitWidth: label.width + 24
    implicitHeight: label.implicitHeight + 16
    color: "transparent"
    visible: shown && text !== ""

    onHoveredChanged: {
        if (hovered && text !== "")
            revealDelay.restart();
        else {
            revealDelay.stop();
            shown = false;
        }
    }

    onTextChanged: {
        if (text === "")
            shown = false;
    }

    Timer {
        id: revealDelay
        interval: root.delay
        onTriggered: root.shown = root.hovered && root.text !== ""
    }

    Rectangle {
        anchors.fill: parent
        radius: 9
        color: "@opaqueSurface@"
        border.width: 1
        border.color: "@border@"

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: Math.max(8, parent.height - 12)
            radius: 1
            color: "@accent@"
            opacity: 0.75
        }
    }

    Text {
        id: label

        anchors.centerIn: parent
        width: Math.min(400, implicitWidth)
        text: root.text
        color: "@text@"
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        font.family: "@fontFamily@"
        font.pixelSize: 11
        lineHeight: 1.25
    }
}
