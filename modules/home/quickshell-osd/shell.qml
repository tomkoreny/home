import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    property bool shown: false
    property string kind: "volume"
    property real level: 0
    property bool muted: false
    readonly property var targetScreen: {
        for (let i = 0; i < Quickshell.screens.length; ++i) {
            const candidate = Quickshell.screens[i];
            if (candidate.name === "@output@")
                return candidate;
        }
        return null;
    }
    readonly property var mediaPlayer: {
        const players = Mpris.players.values;
        return players.find(player => player.isPlaying)
            ?? players.find(player => player.trackTitle !== "")
            ?? players[0]
            ?? null;
    }

    function reveal(nextKind: string, nextLevel: real, nextMuted: bool): void {
        mediaPopup.shown = false;
        kind = nextKind;
        level = Math.max(0, Math.min(1, nextLevel));
        muted = nextMuted;
        shown = true;
        dismiss.restart();
    }

    function icon(): string {
        if (kind === "brightness")
            return "󰃠";
        if (muted)
            return "󰖁";
        if (level < 0.34)
            return "󰕿";
        if (level < 0.67)
            return "󰖀";
        return "󰕾";
    }

    function formatDuration(seconds: real): string {
        const total = Math.max(0, Math.floor(seconds));
        const minutes = Math.floor(total / 60);
        const remainder = total % 60;
        return `${minutes}:${remainder < 10 ? "0" : ""}${remainder}`;
    }

    screen: targetScreen ?? Quickshell.screens[0]
    visible: targetScreen !== null && (shown || panel.opacity > 0.01)
    color: "transparent"
    mask: Region {}
    implicitWidth: 420
    implicitHeight: 68
    exclusiveZone: 0
    aboveWindows: true

    anchors.bottom: true
    margins.bottom: 72

    WlrLayershell.namespace: "tom-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: panel

        anchors.fill: parent
        radius: height / 2
        color: "@surface@"
        border.width: 1
        border.color: root.muted ? "@muted@" : "@border@"
        opacity: root.shown ? 1 : 0
        transform: Translate {
            y: root.shown ? 0 : 18
            Behavior on y {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 20
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                radius: 21
                color: root.muted ? "@mutedSurface@" : "@accentSurface@"

                Text {
                    anchors.centerIn: parent
                    text: root.icon()
                    color: root.muted ? "@muted@" : "@accent@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 22
                }
            }

            Rectangle {
                id: track

                Layout.fillWidth: true
                Layout.preferredHeight: 8
                radius: 4
                color: "@track@"

                Rectangle {
                    height: parent.height
                    width: parent.width * root.level
                    radius: parent.radius
                    color: root.muted ? "@muted@" : "@accent@"

                    Behavior on width {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            Text {
                Layout.preferredWidth: 54
                horizontalAlignment: Text.AlignRight
                text: root.muted ? "MUTE" : `${Math.round(root.level * 100)}%`
                color: root.muted ? "@muted@" : "@text@"
                font.family: "@fontFamily@"
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
        }
    }

    PanelWindow {
        id: mediaPopup

        property bool shown: false
        readonly property real progress: {
            if (!root.mediaPlayer || root.mediaPlayer.length <= 0)
                return 0;
            return Math.max(0, Math.min(1, root.mediaPlayer.position / root.mediaPlayer.length));
        }

        function reveal(): void {
            if (!root.mediaPlayer || root.mediaPlayer.trackTitle === "")
                return;
            root.shown = false;
            shown = true;
            mediaDismiss.restart();
        }

        screen: root.targetScreen ?? Quickshell.screens[0]
        visible: root.targetScreen !== null
            && root.mediaPlayer !== null
            && (shown || mediaPanel.opacity > 0.01)
        color: "transparent"
        mask: Region {}
        implicitWidth: 560
        implicitHeight: 116
        exclusiveZone: 0
        aboveWindows: true

        anchors.bottom: true
        margins.bottom: 72

        WlrLayershell.namespace: "tom-media"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            id: mediaPanel

            anchors.fill: parent
            radius: 24
            color: "@surface@"
            border.width: 1
            border.color: "@border@"
            opacity: mediaPopup.shown ? 1 : 0
            transform: Translate {
                y: mediaPopup.shown ? 0 : 18
                Behavior on y {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14

                Rectangle {
                    id: artworkFrame

                    Layout.preferredWidth: 88
                    Layout.preferredHeight: 88
                    radius: 18
                    color: "@accentSurface@"
                    clip: true

                    Image {
                        id: albumArt

                        anchors.fill: parent
                        source: root.mediaPlayer ? root.mediaPlayer.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: albumArt.status !== Image.Ready
                        text: "󰎆"
                        color: "@accent@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 30
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 5

                    Text {
                        Layout.fillWidth: true
                        text: root.mediaPlayer ? root.mediaPlayer.trackTitle : ""
                        color: "@text@"
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: "@fontFamily@"
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.mediaPlayer
                            ? (root.mediaPlayer.trackArtist || "Unknown artist")
                            : ""
                        color: "@text@"
                        opacity: 0.72
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: "@fontFamily@"
                        font.pixelSize: 13
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 5
                        radius: 3
                        color: "@track@"

                        Rectangle {
                            height: parent.height
                            width: parent.width * mediaPopup.progress
                            radius: parent.radius
                            color: "@accent@"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: root.mediaPlayer
                                ? (root.mediaPlayer.identity || "MEDIA").toUpperCase()
                                : ""
                            color: "@accent@"
                            elide: Text.ElideRight
                            font.family: "@fontFamily@"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: root.mediaPlayer
                                ? `${root.formatDuration(root.mediaPlayer.position)} / ${root.formatDuration(root.mediaPlayer.length)}`
                                : ""
                            color: "@text@"
                            opacity: 0.68
                            font.family: "@fontFamily@"
                            font.pixelSize: 10
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: 21
                    color: "@accentSurface@"

                    Text {
                        anchors.centerIn: parent
                        text: root.mediaPlayer && root.mediaPlayer.isPlaying ? "󰏤" : "󰐊"
                        color: "@accent@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 20
                    }
                }
            }
        }

        Timer {
            id: mediaDismiss
            interval: 3000
            onTriggered: mediaPopup.shown = false
        }

        Timer {
            interval: 1000
            repeat: true
            running: mediaPopup.shown && root.mediaPlayer && root.mediaPlayer.isPlaying
            onTriggered: root.mediaPlayer.positionChanged()
        }
    }

    Timer {
        id: dismiss
        interval: 1500
        onTriggered: root.shown = false
    }

    IpcHandler {
        target: "osd"

        function showVolume(value: real, isMuted: bool): void {
            root.reveal("volume", value, isMuted);
        }

        function showBrightness(percent: int): void {
            root.reveal("brightness", percent / 100, false);
        }
    }

    Connections {
        target: root.mediaPlayer
        ignoreUnknownSignals: true

        function onTrackChanged(): void {
            mediaPopup.reveal();
        }

        function onPlaybackStateChanged(): void {
            mediaPopup.reveal();
        }
    }

    IpcHandler {
        target: "media"

        function reveal(): void {
            mediaPopup.reveal();
        }
    }
}
