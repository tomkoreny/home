import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    property var items: []
    property int todayCount: 0
    property int overdueCount: 0
    property string updatedAt: ""
    property bool stale: false
    property bool loading: true
    property string error: ""
    property var undoTask: null
    property var commandQueue: []
    readonly property int actionableCount: todayCount + overdueCount
    readonly property bool undoAvailable: undoTask !== null

    function enqueue(action: string, arguments: var, context: var): void {
        commandQueue = commandQueue.concat([{
            action: action,
            arguments: arguments,
            context: context
        }]);
        startNext();
    }

    function startNext(): void {
        if (backend.running || commandQueue.length === 0)
            return;
        const request = commandQueue[0];
        commandQueue = commandQueue.slice(1);
        backend.action = request.action;
        backend.context = request.context;
        backend.outputText = "";
        backend.errorText = "";
        backend.exec(["@todoHelper@", request.action].concat(request.arguments));
    }

    function refresh(): void {
        if (!backend.running && !commandQueue.some(request => request.action === "list")) {
            loading = items.length === 0;
            enqueue("list", [], null);
        }
    }

    function recalculate(nextItems: var): void {
        const sorted = nextItems.slice().sort((left, right) => {
            const dateOrder = String(left.due).localeCompare(String(right.due));
            return dateOrder !== 0 ? dateOrder : String(left.title).localeCompare(String(right.title));
        });
        items = sorted;
        overdueCount = sorted.filter(item => item.overdue).length;
        todayCount = sorted.length - overdueCount;
    }

    function completeTask(task: var): void {
        if (!task)
            return;
        recalculate(items.filter(item => item.id !== task.id));
        undoTask = task;
        undoExpiry.restart();
        enqueue("complete", [task.id], task);
    }

    function undoLast(): void {
        const task = undoTask;
        if (!task)
            return;
        undoExpiry.stop();
        undoTask = null;
        recalculate(items.concat([task]));
        enqueue("undo", [task.id], task);
    }

    function openTask(task: var): void {
        if (task && task.url)
            Quickshell.execDetached(["@xdgOpen@", task.url]);
    }

    function applyList(payload: var): void {
        items = payload.items ?? [];
        todayCount = payload.todayCount ?? 0;
        overdueCount = payload.overdueCount ?? 0;
        updatedAt = payload.updatedAt ?? "";
        stale = Boolean(payload.stale);
        error = String(payload.error ?? "");
        loading = false;
    }

    function restoreFailedMutation(action: string, task: var): void {
        if (!task)
            return;
        if (action === "complete" && !items.some(item => item.id === task.id))
            recalculate(items.concat([task]));
        if (action === "undo")
            recalculate(items.filter(item => item.id !== task.id));
    }

    function finish(action: string, context: var, exitCode: int, output: string, failure: string): void {
        if (exitCode !== 0) {
            error = failure.trim() || "Notion operation failed";
            stale = true;
            restoreFailedMutation(action, context);
            if (undoTask && context && undoTask.id === context.id)
                undoTask = null;
            loading = false;
            startNext();
            return;
        }
        try {
            const payload = JSON.parse(output);
            if (action === "list") {
                applyList(payload);
            } else {
                if (action === "complete" && context)
                    recalculate(items.filter(item => item.id !== context.id));
                else if (action === "undo" && context
                         && !items.some(item => item.id === context.id))
                    recalculate(items.concat([context]));
                error = "";
            }
        } catch (parseError) {
            error = "Could not read Notion response";
            stale = true;
            restoreFailedMutation(action, context);
        }
        startNext();
    }

    Process {
        id: backend

        property string action: ""
        property var context: null
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
            const completedContext = context;
            const output = outputText;
            const failure = errorText;
            Qt.callLater(() => root.finish(
                completedAction,
                completedContext,
                exitCode,
                output,
                failure
            ));
        }
    }

    Timer {
        interval: 300000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Timer {
        id: undoExpiry

        interval: 8000
        onTriggered: root.undoTask = null
    }

    Component.onCompleted: refresh()
}
