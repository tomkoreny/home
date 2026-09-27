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
    // Last values sent to the base, keyed by the helper's setting names; the
    // base cannot report its own, so changes made in its menu are not seen.
    property var settings: ({})
    property string settingError: ""

    readonly property bool headsetOn: status === "on"
    // The helper keeps its clock on the base's OLED whenever the base answers.
    readonly property bool displayConnected: status === "on" || status === "off"
    readonly property bool showHeadsetBattery: headsetOn || status === "error"
    // 0 bars also means an empty charging slot, so it shows nothing.
    readonly property bool showSpareBattery: displayConnected && spareBars > 0

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

    // Charging glyphs for the spare battery in the base, same stretch as above.
    function spareIcon(): string {
        return ["󰢟", "󰂆", "󰢝", "󰂊", "󰂅"][spareBars] ?? "󰢟";
    }

    function batteryLow(): bool {
        return status === "error" || (headsetBars >= 0 && headsetBars <= 1);
    }

    function tooltip(): string {
        if (status === "error")
            return `Arctis Pro Wireless · ${error}`;
        const headset = status === "off" ? "off" : barsText(headsetBars);
        const spare = spareBars === 0 ? "empty or not inserted" : barsText(spareBars);
        return `Headset · ${headset}\nSpare battery in base · ${spare}`;
    }

    function update(line: string): void {
        try {
            const report = JSON.parse(line);
            if (report.settings !== undefined) {
                settings = report.settings;
                settingError = "";
                return;
            }
            if (report.settingError !== undefined) {
                settingError = report.settingError;
                return;
            }
            headsetBars = typeof report.headset === "number" ? report.headset : -1;
            spareBars = typeof report.spare === "number" ? report.spare : -1;
            error = report.error ?? "";
            status = report.state;
        } catch (parseError) {
            status = "error";
            error = `Unreadable helper output: ${parseError}`;
        }
    }

    // Applies one base setting now and saves it to the base shortly after.
    function setSetting(name: string, value: int): void {
        if (watcher.running)
            watcher.write(JSON.stringify({ set: name, value: value }) + "\n");
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
