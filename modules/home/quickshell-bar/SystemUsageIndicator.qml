import QtQuick

// CPU and memory use of the machine in the status island, red from 90%.
// Hovering lists the programs behind the numbers; a click opens htop.
Item {
    id: usageHost
    required property var service

    // nf-oct-cpu (a square chip) and nf-md-chip (a memory module): the two
    // stay apart at 9 px, where most chip icons look alike.
    readonly property string cpuIcon: String.fromCodePoint(0xF4BC)
    readonly property string memoryIcon: String.fromCodePoint(0xF061A)

    width: usageRows.width + 12
    height: parent.height

    // As wide as "100%", so the island does not shift as digits come and go.
    TextMetrics {
        id: widest
        text: `${usageHost.memoryIcon} 100%`
        font: cpuText.font
    }

    Column {
        id: usageRows

        anchors.centerIn: parent
        width: Math.ceil(widest.advanceWidth)
        spacing: -1

        Text {
            id: cpuText
            text: `${usageHost.cpuIcon} ${service.cpuPercent}%`
            color: service.cpuPercent >= 90 ? "@muted@" : "@text@"
            font.family: "@fontFamily@"
            font.pixelSize: 9
            font.weight: Font.DemiBold
        }

        Text {
            text: `${usageHost.memoryIcon} ${service.memoryPercent}%`
            color: service.memoryPercent >= 90 ? "@muted@" : "@text@"
            font: cpuText.font
        }
    }

    MouseArea {
        id: usageMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: service.openMonitor()
        onContainsMouseChanged: service.watching = containsMouse

        HoverPopover {
            anchorItem: usageMouse
            hovered: usageMouse.containsMouse
            text: service.tooltip()
            alignRight: true
        }
    }
}
