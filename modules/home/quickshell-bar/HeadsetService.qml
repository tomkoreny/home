import Quickshell
import Quickshell.Io
import QtQuick

// Arctis Pro Wireless base station state, streamed by the arctis helper.
Scope {
    id: root

    // "absent", "off", "on", or "error"; "absent" until the first report.
    property string status: "absent"
    // Battery bars on the base's 0-4 scale, or -1 when unknown.
    property int headsetBars: -1
    property int spareBars: -1
    property string error: ""

    readonly property bool headsetOn: status === "on"
    // The helper keeps its clock on the base's OLED whenever the base answers.
    readonly property bool displayConnected: status === "on" || status === "off"

    function barsText(bars: int): string {
        return bars < 0 ? "unknown" : `${bars}/4 bars`;
    }

    // Nerd Font battery glyphs for the base's 0-4 bars; stretched so each
    // coarse level reads distinctly.
    function batteryIcon(): string {
        if (status === "error")
            return "󰂃";
        return ["󰂎", "󰁻", "󰁾", "󰂁", "󰁹"][headsetBars] ?? "󰂎";
    }

    function batteryLow(): bool {
        return status === "error" || (headsetBars >= 0 && headsetBars <= 1);
    }

    function tooltip(): string {
        if (status === "error")
            return `Arctis Pro Wireless · ${error}`;
        const spare = spareBars === 0 ? "empty or not inserted" : barsText(spareBars);
        return `Headset · ${barsText(headsetBars)}\nSpare battery in base · ${spare}`;
    }

    function update(line: string): void {
        try {
            const report = JSON.parse(line);
            headsetBars = typeof report.headset === "number" ? report.headset : -1;
            spareBars = typeof report.spare === "number" ? report.spare : -1;
            error = report.error ?? "";
            status = report.state;
        } catch (parseError) {
            status = "error";
            error = `Unreadable helper output: ${parseError}`;
        }
    }

    // Shows up to three lines on the base's OLED for `seconds`, then the
    // helper returns to its clock. The first line is drawn bold.
    function showOnBase(lines: var, seconds: real): void {
        if (watcher.running)
            watcher.write(JSON.stringify({ lines: lines, seconds: seconds }) + "\n");
    }

    Process {
        id: watcher
        command: ["@arctisHelper@", "watch"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.update(line)
        }
        onExited: (exitCode, exitStatus) => {
            root.status = "error";
            root.error = `Helper exited with code ${exitCode}`;
            restart.start();
        }
    }

    Timer {
        id: restart
        interval: 10000
        onTriggered: watcher.running = true
    }
}
