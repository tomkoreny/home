import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    property bool active: false
    property string mode: "applications"
    property bool loading: false
    property string loadError: ""
    property var clipboardItems: []
    property var herdrItems: []
    property var cameraItems: []
    property var thumbnailQueue: []
    property var thumbnailRequested: ({})
    property var activeThumbnail: null
    property int thumbnailRevision: 0
    property int aiRevision: 0
    property string aiState: "idle"
    property string aiQuestion: ""
    property string aiAnswer: ""
    property string aiSessionId: ""
    property string aiError: ""

    signal clipboardCopied()
    signal clipboardCopyFailed(string message)

    function itemsForMode(value: string): var {
        if (value === "clipboard")
            return clipboardItems;
        if (value === "herdr")
            return herdrItems;
        if (value === "cameras")
            return cameraItems;
        return [];
    }

    function refreshMode(): void {
        if (!active)
            return;
        loadError = "";
        if (mode === "clipboard") {
            loading = clipboardItems.length === 0;
            thumbnailQueue = [];
            thumbnailRequested = ({});
            activeThumbnail = null;
            if (thumbnailProcess.running)
                thumbnailProcess.running = false;
            clipboardListProcess.exec(["@clipboardHelper@", "list"]);
        } else if (mode === "herdr") {
            loading = herdrItems.length === 0;
            herdrProcess.exec(["@herdr@", "api", "snapshot"]);
        } else if (mode === "cameras") {
            loading = cameraItems.length === 0;
            cameraProcess.exec(["@camera@", "--list"]);
        } else {
            loading = false;
        }
    }

    function stopModeProcesses(): void {
        if (clipboardListProcess.running)
            clipboardListProcess.running = false;
        if (herdrProcess.running)
            herdrProcess.running = false;
        if (cameraProcess.running)
            cameraProcess.running = false;
        if (thumbnailProcess.running)
            thumbnailProcess.running = false;
    }

    function parseClipboard(payload: string): void {
        try {
            const rows = JSON.parse(payload);
            clipboardItems = rows.map(row => ({
                kind: "clipboard",
                id: String(row.id),
                title: row.image ? "Image" : String(row.preview ?? ""),
                description: row.image ? String(row.preview ?? "Image") : `Clipboard · ${row.id}`,
                image: Boolean(row.image),
                thumbnail: String(row.thumbnail ?? ""),
                search: `${row.preview ?? ""} ${row.id}`
            }));
            loadError = "";
        } catch (error) {
            clipboardItems = [];
            loadError = "Could not read clipboard history";
        }
        loading = false;
    }

    function parseHerdr(payload: string): void {
        try {
            const snapshot = JSON.parse(payload).result.snapshot;
            const workspaces = {};
            for (const workspace of snapshot.workspaces ?? [])
                workspaces[workspace.workspace_id] = workspace.label || workspace.workspace_id;
            herdrItems = (snapshot.panes ?? []).map(pane => {
                const status = pane.agent_status || "terminal";
                const workspace = workspaces[pane.workspace_id] || pane.workspace_id;
                const title = pane.terminal_title_stripped || pane.terminal_title || pane.pane_id;
                return {
                    kind: "herdr",
                    id: pane.pane_id,
                    title: title,
                    description: `${workspace} · ${pane.agent || "terminal"} · ${status}`,
                    status: status,
                    search: `${title} ${workspace} ${pane.agent || ""} ${status} ${pane.pane_id}`
                };
            });
            loadError = "";
        } catch (error) {
            herdrItems = [];
            loadError = "Could not read Herdr panes";
        }
        loading = false;
    }

    function parseCameras(payload: string): void {
        const names = payload.split("\n").map(value => value.trim()).filter(value => value !== "");
        cameraItems = [{
            kind: "camera",
            id: "__all__",
            title: "All cameras",
            description: "Open an automatically arranged camera grid",
            all: true,
            search: "all cameras grid"
        }].concat(names.map(name => ({
            kind: "camera",
            id: name,
            title: name,
            description: "Open live camera stream",
            all: false,
            search: name
        })));
        loadError = names.length === 0 ? "No cameras available" : "";
        loading = false;
    }

    function requestThumbnail(item: var): void {
        if (!item || !item.image || item.thumbnail === "" || thumbnailRequested[item.id])
            return;
        const requested = Object.assign({}, thumbnailRequested);
        requested[item.id] = true;
        thumbnailRequested = requested;
        thumbnailQueue = thumbnailQueue.concat([item]);
        Qt.callLater(() => root.startNextThumbnail());
    }

    function startNextThumbnail(): void {
        if (thumbnailProcess.running || thumbnailQueue.length === 0)
            return;
        activeThumbnail = thumbnailQueue[0];
        thumbnailQueue = thumbnailQueue.slice(1);
        thumbnailProcess.exec(["@clipboardHelper@", "thumbnail", activeThumbnail.id]);
    }

    function copyClipboard(item: var): void {
        if (!item || clipboardCopyProcess.running)
            return;
        clipboardCopyProcess.exec(["@clipboardHelper@", "copy", item.id]);
    }

    function openHerdr(item: var, takeover: bool): void {
        if (!item)
            return;
        const command = ["@herdrView@"];
        if (takeover)
            command.push("--takeover");
        command.push(item.id);
        Quickshell.execDetached(command);
    }

    function openCamera(item: var): void {
        if (!item)
            return;
        Quickshell.execDetached(item.all
            ? ["@camera@", "--all"]
            : ["@camera@", item.id]);
    }

    function resetAi(): void {
        aiRevision++;
        if (aiProcess.running)
            aiProcess.running = false;
        aiState = "idle";
        aiQuestion = "";
        aiAnswer = "";
        aiSessionId = "";
        aiError = "";
    }

    function cancelAi(): void {
        if (aiState !== "running")
            return;
        resetAi();
        aiError = "Cancelled";
    }

    function submitAi(question: string): void {
        const trimmed = question.trim();
        if (trimmed === "" || aiProcess.running)
            return;
        aiRevision++;
        aiState = "running";
        aiQuestion = trimmed;
        aiAnswer = "";
        aiSessionId = "";
        aiError = "";
        aiProcess.activeRevision = aiRevision;
        aiProcess.activeQuestion = trimmed;
        aiProcess.outputText = "";
        aiProcess.errorText = "";
        aiProcess.running = true;
    }

    function finishAi(revision: int, exitCode: int, payload: string, errorOutput: string): void {
        if (revision !== aiRevision || aiState !== "running")
            return;
        let sessionId = "";
        let answer = "";
        for (const line of payload.split("\n")) {
            if (line.trim() === "")
                continue;
            try {
                const event = JSON.parse(line);
                if (event.type === "session" && event.id)
                    sessionId = event.id;
                if (event.type === "message_end" && event.message?.role === "assistant") {
                    answer = (event.message.content ?? [])
                        .filter(part => part.type === "text")
                        .map(part => part.text ?? "")
                        .join("\n")
                        .trim();
                }
            } catch (error) {
                // OMP JSON mode is newline-delimited; ignore non-event diagnostics.
            }
        }
        if (exitCode === 0 && sessionId !== "" && answer !== "") {
            aiSessionId = sessionId;
            aiAnswer = answer;
            aiState = "ready";
            return;
        }
        aiState = "error";
        const failure = errorOutput.trim().replace(/\s*\n\s*/g, " ");
        aiError = failure !== "" ? failure : "Could not get an AI answer";
    }

    function resumeAi(): bool {
        if (aiState !== "ready" || aiSessionId === "")
            return false;
        Quickshell.execDetached(["@launcherAi@", "resume", aiSessionId]);
        return true;
    }

    onActiveChanged: {
        if (active)
            refreshMode();
        else
            stopModeProcesses();
    }

    onModeChanged: {
        if (active)
            refreshMode();
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.active && root.mode === "herdr"
        onTriggered: root.refreshMode()
    }

    Process {
        id: clipboardListProcess

        stdout: StdioCollector {
            onStreamFinished: root.parseClipboard(this.text)
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.loading = false;
                root.loadError = "Could not read clipboard history";
            }
        }
    }

    Process {
        id: herdrProcess

        stdout: StdioCollector {
            onStreamFinished: root.parseHerdr(this.text)
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.loading = false;
                root.loadError = "Could not read Herdr panes";
            }
        }
    }

    Process {
        id: cameraProcess

        stdout: StdioCollector {
            onStreamFinished: root.parseCameras(this.text)
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.loading = false;
                root.loadError = "Could not read camera names";
            }
        }
    }

    Process {
        id: thumbnailProcess

        onExited: (exitCode, exitStatus) => {
            root.activeThumbnail = null;
            if (root.thumbnailQueue.length === 0)
                root.thumbnailRevision++;
            Qt.callLater(() => root.startNextThumbnail());
        }
    }

    Process {
        id: clipboardCopyProcess

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root.clipboardCopied();
            else
                root.clipboardCopyFailed("Could not restore clipboard entry");
        }
    }

    Process {
        id: aiProcess

        property int activeRevision: 0
        property string activeQuestion: ""
        property string outputText: ""
        property string errorText: ""

        command: ["@launcherAi@", "ask", activeQuestion]

        stdout: StdioCollector {
            onStreamFinished: aiProcess.outputText = this.text
        }

        stderr: StdioCollector {
            onStreamFinished: aiProcess.errorText = this.text
        }

        onExited: (exitCode, exitStatus) => {
            const revision = activeRevision;
            Qt.callLater(() => root.finishAi(
                revision,
                exitCode,
                aiProcess.outputText,
                aiProcess.errorText
            ));
        }
    }
}
