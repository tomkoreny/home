import Quickshell
import Quickshell.Io
import QtQuick

// Outcome of the hourly NixOS auto-upgrade, recorded by the system unit's
// ExecStopPost hook. The bar only surfaces it when something needs attention.
Scope {
    id: root

    // An hourly timer that has not finished a run for this long has stalled.
    readonly property int staleSeconds: 24 * 60 * 60

    property string result: ""
    property string error: ""
    property real finishedAt: 0
    property real lastSuccessAt: 0
    property real now: Date.now() / 1000
    property bool notifiedFailure: false

    readonly property bool known: finishedAt > 0
    readonly property bool failed: known && result !== "success"
    readonly property bool stale: known && now - finishedAt > staleSeconds
    readonly property bool needsAttention: failed || stale

    function age(seconds: real): string {
        if (seconds <= 0)
            return "never";
        const minutes = Math.floor((now - seconds) / 60);
        if (minutes < 60)
            return `${minutes} min ago`;
        const hours = Math.floor(minutes / 60);
        if (hours < 48)
            return `${hours} h ago`;
        return `${Math.floor(hours / 24)} days ago`;
    }

    function tooltip(): string {
        const lines = [];
        if (failed)
            lines.push(`NixOS auto-upgrade failed · ${age(finishedAt)}`, error);
        else
            lines.push(`NixOS auto-upgrade has not run · last run ${age(finishedAt)}`);
        lines.push(`Last successful upgrade · ${age(lastSuccessAt)}`, "Click to open the upgrade log");
        return lines.join("\n");
    }

    function openLog(): void {
        Quickshell.execDetached([
            "@uwsm@", "app", "--", "@ghostty@", "-e",
            "@journalctl@", "--unit", "nixos-upgrade.service", "--lines", "300", "--pager-end"
        ]);
    }

    function update(payload: string): void {
        try {
            const status = JSON.parse(payload);
            result = status.result ?? "";
            error = status.error ?? "";
            finishedAt = status.finishedAt ?? 0;
            lastSuccessAt = status.lastSuccessAt ?? 0;
        } catch (parseError) {
            // No run has finished since the recorder was deployed.
            finishedAt = 0;
        }
        now = Date.now() / 1000;
        // Hourly retries keep failing the same way; notify once per failure streak.
        if (failed && !notifiedFailure)
            Quickshell.execDetached([
                "@notifySend@", "-a", "NixOS", "-u", "critical",
                "NixOS auto-upgrade failed", error
            ]);
        notifiedFailure = failed;
    }

    Process {
        id: reader
        command: ["@cat@", "/var/lib/nixos-upgrade-status/status.json"]
        stdout: StdioCollector {
            onStreamFinished: root.update(this.text)
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: reader.running = true
    }
}
