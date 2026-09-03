import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    property var timers: []
    property real now: Date.now()
    property bool loading: true
    property string error: ""
    property var commandQueue: []
    readonly property var nextTimer: timers.find(timer => !timer.paused) ?? null
    readonly property int activeCount: timers.length

    signal timerCreated(string name)
    signal timerCreationFailed(string message)

    function remaining(timer: var): real {
        if (!timer)
            return 0;
        return timer.paused
            ? timer.remainingMs
            : Math.max(0, timer.deadlineMs - now);
    }

    function formatRemaining(milliseconds: real): string {
        const seconds = Math.max(0, Math.ceil(milliseconds / 1000));
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const remainder = seconds % 60;
        if (hours > 0)
            return `${hours}:${String(minutes).padStart(2, "0")}:${String(remainder).padStart(2, "0")}`;
        return `${minutes}:${String(remainder).padStart(2, "0")}`;
    }

    function enqueue(action: string, arguments: var): void {
        commandQueue = commandQueue.concat([{ action: action, arguments: arguments }]);
        startNext();
    }

    function startNext(): void {
        if (backend.running || commandQueue.length === 0)
            return;
        const request = commandQueue[0];
        commandQueue = commandQueue.slice(1);
        backend.action = request.action;
        backend.outputText = "";
        backend.errorText = "";
        backend.exec(["@timerHelper@", request.action].concat(request.arguments));
    }

    function addTimer(query: string): void {
        enqueue("add", [query]);
    }

    function pauseTimer(timerId: string): void {
        enqueue("pause", [timerId]);
    }

    function resumeTimer(timerId: string): void {
        enqueue("resume", [timerId]);
    }

    function cancelTimer(timerId: string): void {
        enqueue("cancel", [timerId]);
    }

    function refresh(): void {
        if (!backend.running)
            enqueue("tick", []);
    }

    function applyResponse(action: string, exitCode: int, output: string, failure: string): void {
        if (exitCode !== 0) {
            const message = failure.trim() || "Timer operation failed";
            error = message;
            if (action === "add")
                timerCreationFailed(message);
            startNext();
            return;
        }
        try {
            const payload = JSON.parse(output);
            timers = payload.timers ?? [];
            now = payload.now ?? Date.now();
            error = "";
            for (const timer of payload.expired ?? []) {
                Quickshell.execDetached([
                    "@notifySend@", "-a", "Timer", "-u", "critical", "-t", "0",
                    "Timer finished", timer.name
                ]);
                Quickshell.execDetached(["@pwPlay@", "@timerSound@"]) ;
            }
            if (action === "add" && timers.length > 0)
                timerCreated(timers[timers.length - 1].name);
        } catch (parseError) {
            error = "Could not read timer state";
            if (action === "add")
                timerCreationFailed(error);
        }
        loading = false;
        startNext();
    }

    Process {
        id: backend

        property string action: ""
        property string outputText: ""
        property string errorText: ""

        stdout: StdioCollector {
            onStreamFinished: backend.outputText = this.text
        }

        stderr: StdioCollector {
            onStreamFinished: backend.errorText = this.text
        }

        onExited: (exitCode, exitStatus) => {
            const completedAction = action;
            const output = outputText;
            const failure = errorText;
            Qt.callLater(() => root.applyResponse(completedAction, exitCode, output, failure));
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            root.now = Date.now();
            if (root.nextTimer && root.remaining(root.nextTimer) <= 0)
                root.refresh();
        }
    }

    Component.onCompleted: refresh()
}
