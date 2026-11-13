import Quickshell
import Quickshell.Io
import QtQuick

// Agents in the Herdr app, whose terminals run in herdr-core and not in the
// Herdr TUI's server. Counted every two seconds from `hc ls`, through a helper
// that prints nothing while no herdr-core is running.
Scope {
    id: root

    property bool enabled: true

    property bool running: false
    property int working: 0
    property int blocked: 0
    property int idle: 0

    function update(payload: string): void {
        let terminals = null;
        try {
            if (payload.trim() !== "")
                terminals = JSON.parse(payload).terminals ?? [];
        } catch (error) {
            console.warn(`Unable to parse Herdr app terminals: ${error}`);
        }
        running = terminals !== null;
        // A terminal is an agent once its program reports a status. One that
        // reports an error waits for the user as a blocked one does.
        const count = statuses => (terminals ?? []).filter(terminal => statuses.includes(terminal.status)).length;
        working = count(["working"]);
        blocked = count(["blocked", "error"]);
        idle = count(["idle", "done"]);
    }

    Process {
        id: reader
        command: ["@herdrAppAgents@"]
        stdout: StdioCollector {
            onStreamFinished: root.update(this.text)
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.enabled
        triggeredOnStart: true
        onTriggered: reader.running = true
    }
}
