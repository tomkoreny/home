import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    required property string primaryOutput
    required property string statusOutput
    required property int barHeight
    property bool active: false

    function benefits(snapshot): bool {
        const primary = snapshot.monitors.find(monitor => monitor.name === primaryOutput);
        const destination = snapshot.monitors.find(monitor => monitor.name === statusOutput);
        if (!primary || !destination || primary.disabled || destination.disabled
                || !primary.dpmsStatus || !destination.dpmsStatus
                || primary.specialWorkspace.id !== 0 || destination.specialWorkspace.id !== 0)
            return false;

        const windows = snapshot.clients.filter(client => client.mapped && !client.hidden
            && client.monitor === primary.id
            && (client.workspace.id === primary.activeWorkspace.id || client.pinned));
        if (windows.length !== 1)
            return false;
        const window = windows[0];
        const ratio = snapshot.ratios[window.address];
        if (window.floating || window.fullscreen !== 0 || window.grouped.length > 1
                || !Number.isFinite(ratio) || ratio <= 0)
            return false;
        // A fullscreen window on the destination could cover the relocated controls.
        if (snapshot.clients.some(client => client.mapped && !client.hidden
                && client.monitor === destination.id
                && client.workspace.id === destination.activeWorkspace.id
                && client.fullscreen === 2))
            return false;

        // Single tiled windows use the compositor's borderless, zero-gap rules.
        // Always reconstruct BOTH layouts from monitor geometry, not the resized
        // window or our current active state, to avoid a hide/show feedback loop.
        const rotated = primary.transform % 2 !== 0;
        const width = Math.round((rotated ? primary.height : primary.width) / primary.scale)
            - primary.reserved[0] - primary.reserved[2];
        const height = Math.round((rotated ? primary.width : primary.height) / primary.scale)
            - primary.reserved[3];
        const withBar = height - Math.max(barHeight, primary.reserved[1]);
        const withoutBar = height - Math.max(0, primary.reserved[1] - barHeight);
        return Math.min(withoutBar, width / ratio) - Math.min(withBar, width / ratio) > 1;
    }

    Process {
        id: playback
        command: ["@aspectController@", "--watch-playback"]
        running: root.statusOutput !== ""
        stdout: SplitParser {
            onRead: line => {
                // python-xlib can print an Xauthority warning before its first snapshot.
                if (!line.startsWith("{"))
                    return;
                try {
                    root.active = root.benefits(JSON.parse(line));
                } catch (error) {
                    root.active = false;
                    console.warn(`Unable to read video bar state: ${error}`);
                }
            }
        }
        onExited: root.active = false
    }
}
