import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    property bool enabled: false
    property var items: []
    property var statusOptions: []
    property string updatedAt: ""
    property bool stale: true
    property string error: ""
    property bool loading: false
    property bool busy: false
    property string pendingId: ""
    readonly property int actionableCount: items.filter(item => item.actionable).length

    property bool ready: false
    property bool initialized: false
    property bool refreshPending: false

    function start(action: string, arguments: var, context: var): void {
        busy = true;
        loading = action !== "transition";
        backend.action = action;
        backend.context = context;
        backend.outputText = "";
        backend.errorText = "";
        backend.exec(["@workHelper@", action].concat(arguments));
    }

    function initialize(): void {
        if (!ready || !enabled || initialized || busy)
            return;
        initialized = true;
        refreshPending = true;
        start("cache", [], null);
    }

    function refresh(): void {
        if (!enabled)
            return;
        if (!initialized) {
            initialize();
            return;
        }
        if (busy) {
            refreshPending = true;
            return;
        }
        refreshPending = false;
        start("list", [], null);
    }

    function ordered(values: var): var {
        return values.slice().sort((left, right) => {
            const rank = left.rank - right.rank;
            if (rank !== 0)
                return rank;
            const date = String(right.updatedAt).localeCompare(String(left.updatedAt));
            return date !== 0 ? date : String(left.id).localeCompare(String(right.id));
        });
    }

    function transition(task: var, action: var): void {
        if (!enabled || stale || busy || !task || !action)
            return;
        const current = items.find(item => item.id === task.id);
        if (!current || !current.actionable || current.statusId !== task.statusId)
            return;
        const allowed = current.actions.find(candidate => candidate.id === action.id);
        if (!allowed)
            return;
        const original = items.slice();
        const optimistic = Object.assign({}, current, {
            statusId: allowed.statusId,
            statusName: allowed.statusName,
            actionable: allowed.actionable
        });
        pendingId = current.id;
        error = "";
        items = items.map(item => item.id === current.id ? optimistic : item).filter(item => item.actionable);
        start("transition", [current.id, allowed.id, current.statusId], {
            id: current.id,
            original: original
        });
    }

    function openTask(task: var): void {
        if (task && task.url)
            Quickshell.execDetached(["@xdgOpen@", task.url]);
    }

    function applyList(action: string, payload: var): void {
        if (!payload || !Array.isArray(payload.items) || !Array.isArray(payload.statusOptions) || typeof payload.stale !== "boolean" || !Array.isArray(payload.events))
            throw new Error("Invalid work task response");
        const live = action === "list" && !payload.stale && !payload.error;
        // A stale backend cache may predate a committed transition. Keep our newer state.
        if (action === "cache" || live) {
            items = ordered(payload.items.filter(item => item.actionable));
            statusOptions = payload.statusOptions;
            updatedAt = String(payload.updatedAt ?? "");
        }
        stale = !live;
        error = String(payload.error ?? "");
        if (live) {
            for (const event of payload.events) {
                if (event.kind === "assigned")
                    Quickshell.execDetached(["@workNotify@", String(event.title), String(event.url)]);
            }
        }
    }

    function finish(action: string, context: var, exitCode: int, output: string, failure: string): void {
        try {
            if (exitCode !== 0)
                throw new Error(failure.trim() || "Work task operation failed");
            const payload = JSON.parse(output);
            if (action === "transition") {
                const item = payload.item;
                if (!item || item.id !== context.id || typeof item.actionable !== "boolean")
                    throw new Error("Invalid work task transition response");
                items = ordered(items.filter(candidate => candidate.id !== context.id).concat(item.actionable ? [item] : []));
                error = "";
                refreshPending = true;
            } else {
                applyList(action, payload);
            }
        } catch (failureError) {
            if (action === "transition" && context)
                items = context.original;
            stale = true;
            error = String(failureError.message || "Could not read work task response");
        }
        pendingId = "";
        loading = false;
        busy = false;
        if (enabled && refreshPending)
            refresh();
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
            Qt.callLater(() => root.finish(completedAction, completedContext, exitCode, output, failure));
        }
    }

    Timer {
        interval: 300000
        repeat: true
        running: root.enabled
        onTriggered: root.refresh()
    }

    onEnabledChanged: {
        if (enabled) {
            if (initialized)
                refresh();
            else
                initialize();
        }
    }
    Component.onCompleted: {
        ready = true;
        initialize();
    }
}
