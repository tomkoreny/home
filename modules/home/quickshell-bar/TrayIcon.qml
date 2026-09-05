import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Effects

Item {
    id: root

    required property var item
    readonly property string customSource: {
        if (item.status !== Status.Active)
            return "";

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
}
