import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// Sends the track that starts playing to the Arctis base's OLED. The base
// shows its clock between events.
Scope {
    id: root

    required property var headset

    // Same player priority as the OSD's media popup.
    readonly property var player: {
        const players = Mpris.players.values;
        const mpvPlayer = players.find(player =>
            player.dbusName.startsWith("org.mpris.MediaPlayer2.mpv.JellyfinMPVShim")
                && player.playbackState !== MprisPlaybackState.Stopped);
        return mpvPlayer
            ?? players.find(player => player.isPlaying)
            ?? null;
    }
    // Changes only when a new track starts or playback resumes; a string so
    // unrelated player updates that re-evaluate it do not re-announce it.
    readonly property string track: player && player.isPlaying && player.trackTitle !== ""
        ? JSON.stringify([player.trackTitle, player.trackArtist])
        : ""

    onTrackChanged: {
        if (track === "")
            return;
        const [title, artist] = JSON.parse(track);
        headset.showOnBase(["Now playing", title, artist], 6);
    }
}
