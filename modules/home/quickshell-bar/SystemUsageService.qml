import Quickshell
import Quickshell.Io
import QtQuick

// CPU and memory use of the whole machine, read from /proc every two seconds.
// Which programs account for it is only worked out while `watching` (the bar
// item is hovered): that walks every process, about 150 ms of work each time.
Scope {
    id: root

    property bool watching: false

    property int cpuPercent: 0
    property int memoryPercent: 0
    property real memoryUsedKib: 0
    property real memoryTotalKib: 0
    property real swapUsedKib: 0
    // Rows of system-usage.py, kept from the last hover until the next reading.
    property var topMemory: []
    property var topCpu: []

    // /proc/stat counts since boot; use is the change between two readings.
    property real lastCpuTotal: 0
    property real lastCpuIdle: 0

    function update(payload: string): void {
        const memory = {};
        for (const line of payload.split("\n")) {
            if (line.startsWith("cpu ")) {
                // user nice system idle iowait irq softirq steal
                const counts = line.trim().split(/\s+/).slice(1, 9).map(Number);
                const total = counts.reduce((sum, count) => sum + count, 0);
                const idle = counts[3] + counts[4];
                if (lastCpuTotal > 0 && total > lastCpuTotal)
                    cpuPercent = Math.round(100 * (1 - (idle - lastCpuIdle) / (total - lastCpuTotal)));
                lastCpuTotal = total;
                lastCpuIdle = idle;
                continue;
            }
            const field = line.match(/^(MemTotal|MemAvailable|SwapTotal|SwapFree):\s+(\d+) kB/);
            if (field)
                memory[field[1]] = Number(field[2]);
        }
        if (!(memory.MemTotal > 0))
            return;
        memoryTotalKib = memory.MemTotal;
        memoryUsedKib = memory.MemTotal - (memory.MemAvailable ?? 0);
        memoryPercent = Math.round(100 * memoryUsedKib / memoryTotalKib);
        swapUsedKib = (memory.SwapTotal ?? 0) - (memory.SwapFree ?? 0);
    }

    function updatePrograms(payload: string): void {
        try {
            const programs = JSON.parse(payload);
            topMemory = programs.memory ?? [];
            topCpu = programs.cpu ?? [];
        } catch (error) {
            console.warn(`Unable to parse program usage: ${error}`);
        }
    }

    function size(kib: real): string {
        return kib >= 1048576 ? `${(kib / 1048576).toFixed(1)} GB` : `${Math.round(kib / 1024)} MB`;
    }

    function label(program: var): string {
        return program.count > 1 ? `${program.name} ×${program.count}` : program.name;
    }

    function tooltip(): string {
        const lines = [
            `CPU ${cpuPercent}%`,
            `Memory ${size(memoryUsedKib)} of ${size(memoryTotalKib)}`
                + (swapUsedKib >= 102400 ? ` · swap ${size(swapUsedKib)}` : "")
        ];
        if (topMemory.length > 0) {
            lines.push("", "Most memory");
            for (const program of topMemory)
                lines.push(`${label(program)} · ${size(program.kib)}`);
        }
        if (topCpu.length > 0) {
            lines.push("", "Most CPU · 100% is one core");
            for (const program of topCpu)
                lines.push(`${label(program)} · ${program.percent}%`);
        }
        lines.push("", "Click to open htop");
        return lines.join("\n");
    }

    function openMonitor(): void {
        Quickshell.execDetached(["@uwsm@", "app", "--", "@ghostty@", "-e", "@htop@"]);
    }

    Process {
        id: reader
        command: ["@cat@", "/proc/stat", "/proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: root.update(this.text)
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: reader.running = true
    }

    Process {
        id: programReader
        command: ["@python@", "@usageHelper@"]
        stdout: StdioCollector {
            onStreamFinished: root.updatePrograms(this.text)
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.watching
        triggeredOnStart: true
        onTriggered: programReader.running = true
    }
}
