import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Effects

Item {
    id: root

    required property var item
    // Komai's pinned tooltip carries its attention-room count, not unread messages.
    // Unknown/localized formats and counts too wide for this badge remain native.
    readonly property int komaiAttentionCount: {
        if (item.id.toLowerCase() !== "komai")
            return -1;
        const title = item.tooltipTitle;
        const description = item.tooltipDescription;
        const tooltip = description ? `${title}\n${description}` : title;
        const match = /^Komai(?: \| [A-Za-z_][A-Za-z0-9_-]*)?(?:\n([1-9][0-9]?) room(?:\(s\)|s)? needs? attention)?$/.exec(tooltip);
        return match ? (match[1] ? Number(match[1]) : 0) : -1;
    }
    readonly property string customSource: {
        if (item.status !== Status.Active)
            return "";
        if (komaiAttentionCount >= 0)
            return "file://@komaiIcon@";

        const id = item.id.toLowerCase();
        const nativeSource = item.icon;
        // Only Steam's ordinary named icon is replaceable. Notification,
        // offline and composed bitmap variants keep their native artwork.
        const plainSteam = id === "steam" && nativeSource.split("?")[0] === "image://icon/steam_tray_mono";
        // The pinned Jellyfin tray publishes a single static logo via pystray.
        // Do not apply this rule to opaque pixmaps or other applications.
        const plainJellyfin = id === "jellyfin-mpv-shim" && nativeSource.startsWith("image://icon//tmp/jms-tray-");
        if (plainSteam)
            return "file://@steamIcon@";
        if (plainJellyfin)
            return "file://@jellyfinIcon@";
        return "";
    }

    implicitWidth: 17
    implicitHeight: 17

    Image {
        id: customImage

        anchors.fill: parent
        source: root.customSource
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        visible: false
    }

    MultiEffect {
        anchors.fill: customImage
        source: customImage
        colorization: 1
        colorizationColor: "@accent@"
        visible: customImage.status === Image.Ready
    }

    Image {
        anchors.fill: parent
        source: customImage.status === Image.Ready ? "" : root.item.icon
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        visible: customImage.status !== Image.Ready
    }

    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -2
        anchors.bottomMargin: -1
        width: Math.max(10, countLabel.implicitWidth + 4)
        height: 10
        radius: 5
        color: "#f38ba8"
        border.width: 1
        border.color: "#11111b"
        visible: root.komaiAttentionCount > 0 && customImage.status === Image.Ready

        Text {
            id: countLabel
            anchors.centerIn: parent
            text: root.komaiAttentionCount
            color: "#11111b"
            font.family: "@fontFamily@"
            font.pixelSize: 8
            font.weight: Font.Bold
        }
    }
}
