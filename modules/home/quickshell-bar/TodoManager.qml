import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    required property var widgetService
    required property var overlayController
    readonly property string overlayName: "todos"

    property bool shown: false
    property var targetScreen: null
    property string activeView: "mine"
    property var items: []
    property var completedItems: []
    property var statusOptions: []
    property var priorityOptions: []
    property bool loading: false
    property bool captureExpanded: false
    property string capturePriority: ""
    property string searchText: ""
    property string editingId: ""
    property string error: ""
    property bool completedExpanded: false
    readonly property bool visible: shown
    readonly property var displayRows: buildRows()

    function focusedScreen(): var {
        let monitor = Hyprland.focusedMonitor ?? null;
        if (!monitor) {
            for (const candidate of Hyprland.monitors.values) {
                if (candidate.focused) {
                    monitor = candidate;
                    break;
                }
            }
        }
        if (monitor) {
            for (const screen of Quickshell.screens) {
                if (screen.name === monitor.name)
                    return screen;
            }
        }
        return Quickshell.screens[0] ?? null;
    }

    function reveal(capture: bool): void {
        targetScreen = focusedScreen();
        overlayController.claim(overlayName);
        shown = true;
        error = "";
        if (capture) {
            Qt.callLater(() => captureInput.forceActiveFocus());
        } else {
            loadView(activeView);
            Qt.callLater(() => searchInput.forceActiveFocus());
        }
    }

    function toggle(): void {
        if (shown)
            close();
        else
            reveal(false);
    }

    function capture(): void {
        if (!shown)
            reveal(true);
        else
            Qt.callLater(() => captureInput.forceActiveFocus());
    }

    function close(): void {
        shown = false;
        overlayController.release(overlayName);
        searchText = "";
        searchInput.text = "";
        editingId = "";
        captureExpanded = false;
        error = "";
    }

    Connections {
        target: root.overlayController

        function onDismissRequested(except: string): void {
            if (except !== root.overlayName && root.shown)
                root.close();
        }
    }

    function run(action: string, arguments: var, context: var): bool {
        if (backend.running)
            return false;
        backend.action = action;
        backend.context = context;
        backend.outputText = "";
        backend.errorText = "";
        error = "";
        backend.exec(["@todoHelper@", action].concat(arguments));
        return true;
    }

    function loadView(view: string): void {
        if (backend.running)
            return;
        activeView = view;
        loading = true;
        editingId = "";
        run("list", [view], null);
    }

    function replaceItem(item: var): void {
        items = items.map(candidate => candidate.id === item.id ? item : candidate);
    }

    function appendItem(item: var): void {
        if (!items.some(candidate => candidate.id === item.id))
            items = items.concat([item]);
    }

    function taskData(task: var): var {
        const value = Object.assign({}, task);
        delete value.kind;
        return value;
    }

    function optimisticUpdate(task: var, field: string, value: string): void {
        const updated = taskData(task);
        if (field === "title")
            updated.title = value;
        else if (field === "due") {
            updated.due = value;
            updated.overdue = value !== "" && value < todayString();
        } else if (field === "priority") {
            const priority = priorityOptions.find(option => option.id === value) ?? null;
            updated.priorityId = priority ? priority.id : "";
            updated.priorityName = priority ? priority.name : "";
        } else if (field === "status") {
            const status = statusOptions.find(option => option.id === value) ?? null;
            updated.statusId = status ? status.id : "";
            updated.statusName = status ? status.name : "";
        }
        replaceItem(updated);
    }

    function updateTask(task: var, field: string, value: string): void {
        if (!task || backend.running)
            return;
        const normalized = String(value).trim();
        if (field === "title" && normalized === "") {
            error = "Task title is required";
            return;
        }
        const original = taskData(task);
        optimisticUpdate(task, field, normalized);
        if (!run("update", [task.id, field, normalized], {
            kind: "update",
            original: original
        }))
            replaceItem(original);
    }

    function completeTask(task: var): void {
        if (!task || backend.running)
            return;
        const original = taskData(task);
        editingId = "";
        items = items.filter(candidate => candidate.id !== task.id);
        const completed = Object.assign({}, original, {
            completedDate: todayString()
        });
        completedItems = [completed].concat(
            completedItems.filter(candidate => candidate.id !== task.id)
        );
        run("complete", [task.id], {
            kind: "complete",
            original: original
        });
    }

    function reopenTask(task: var): void {
        if (!task || backend.running)
            return;
        const original = taskData(task);
        completedItems = completedItems.filter(candidate => candidate.id !== task.id);
        if (activeView === "mine")
            appendItem(original);
        run("reopen", [task.id], {
            kind: "reopen",
            original: original
        });
    }

    function assignToMe(task: var): void {
        if (!task || backend.running)
            return;
        const original = taskData(task);
        items = items.filter(candidate => candidate.id !== task.id);
        run("assign", [task.id], {
            kind: "assign",
            original: original
        });
    }

    function openTask(task: var): void {
        if (task && task.url)
            Quickshell.execDetached(["@xdgOpen@", task.url]);
    }

    function nextOption(options: var, currentId: string, includeEmpty: bool): string {
        const ids = includeEmpty ? [""].concat(options.map(option => option.id))
            : options.map(option => option.id);
        if (ids.length === 0)
            return "";
        const current = ids.indexOf(currentId);
        return ids[(current + 1 + ids.length) % ids.length];
    }

    function cyclePriority(task: var): void {
        updateTask(task, "priority", nextOption(priorityOptions, task.priorityId, true));
    }

    function cycleStatus(task: var): void {
        const nextId = nextOption(statusOptions, task.statusId, false);
        const next = statusOptions.find(option => option.id === nextId) ?? null;
        if (next && next.completed)
            completeTask(task);
        else
            updateTask(task, "status", nextId);
    }

    function todayString(): string {
        return Qt.formatDateTime(new Date(), "yyyy-MM-dd");
    }

    function isoDate(value: var): string {
        return Qt.formatDateTime(value, "yyyy-MM-dd");
    }

    function parsedCapture(value: string): var {
        const parts = value.trim().split(/\s+/).filter(part => part !== "");
        const title = [];
        let due = "";
        let priority = "";
        const weekdays = {
            "mon": 1,
            "tue": 2,
            "wed": 3,
            "thu": 4,
            "fri": 5,
            "sat": 6,
            "sun": 0
        };
        for (const part of parts) {
            const lower = part.toLowerCase();
            const dateToken = lower.match(/^@(today|tomorrow|mon|tue|wed|thu|fri|sat|sun|\d{4}-\d{2}-\d{2})$/);
            const priorityToken = lower.match(/^!(high|medium|low)$/);
            if (dateToken && due === "") {
                const token = dateToken[1];
                const now = new Date();
                if (token === "today")
                    due = isoDate(now);
                else if (token === "tomorrow") {
                    now.setDate(now.getDate() + 1);
                    due = isoDate(now);
                } else if (weekdays[token] !== undefined) {
                    const distance = (weekdays[token] - now.getDay() + 7) % 7;
                    now.setDate(now.getDate() + distance);
                    due = isoDate(now);
                } else {
                    due = token;
                }
            } else if (priorityToken && priority === "") {
                priority = priorityToken[1];
            } else {
                title.push(part);
            }
        }
        return {
            title: title.join(" "),
            due: due,
            priority: priority
        };
    }

    function expandCapture(): void {
        const parsed = parsedCapture(captureInput.text);
        captureInput.text = parsed.title;
        captureDue.text = parsed.due;
        capturePriority = parsed.priority;
        captureExpanded = true;
        Qt.callLater(() => captureDue.forceActiveFocus());
    }

    function captureText(): string {
        let value = captureInput.text.trim();
        if (captureExpanded && captureDue.text.trim() !== "")
            value += ` @${captureDue.text.trim()}`;
        if (captureExpanded && capturePriority !== "")
            value += ` !${capturePriority}`;
        return value;
    }

    function submitCapture(keepOpen: bool): void {
        const value = captureText();
        if (value === "") {
            error = "Task title is required";
            return;
        }
        if (!run("create", [value], {
            kind: "create",
            keepOpen: keepOpen
        }))
            return;
        loading = true;
    }

    function clearCapture(): void {
        captureInput.text = "";
        captureDue.text = "";
        capturePriority = "";
        captureExpanded = false;
    }

    function filtered(values: var): var {
        const needle = searchText.trim().toLowerCase();
        if (needle === "")
            return values;
        return values.filter(task => String(task.title).toLowerCase().includes(needle));
    }

    function buildRows(): var {
        const rows = [];
        const visible = filtered(items);
        const addSection = (title, values) => {
            if (values.length === 0)
                return;
            rows.push({
                kind: "section",
                id: `section-${title}`,
                title: title,
                count: values.length
            });
            for (const task of values)
                rows.push(Object.assign({}, task, {kind: "task"}));
        };
        if (activeView === "mine") {
            const today = todayString();
            const completed = filtered(completedItems);
            if (completed.length > 0) {
                rows.push({
                    kind: "completed-section",
                    id: "section-completed",
                    title: "Completed today",
                    count: completed.length
                });
                if (completedExpanded) {
                    for (const task of completed)
                        rows.push(Object.assign({}, task, {kind: "completed"}));
                }
            }
            addSection("Overdue", visible.filter(task => task.due !== "" && task.due < today));
            addSection("Today", visible.filter(task => task.due === today));
            addSection("Upcoming", visible.filter(task => task.due !== "" && task.due > today));
            addSection("Inbox", visible.filter(task => task.due === ""));
        } else {
            addSection(activeView === "unassigned" ? "Unassigned" : "All open tasks", visible);
        }
        return rows;
    }

    function restore(context: var): void {
        if (!context)
            return;
        if (context.kind === "update")
            replaceItem(context.original);
        else if (context.kind === "complete") {
            completedItems = completedItems.filter(task => task.id !== context.original.id);
            appendItem(context.original);
        } else if (context.kind === "reopen") {
            items = items.filter(task => task.id !== context.original.id);
            completedItems = [context.original].concat(completedItems);
        } else if (context.kind === "assign") {
            appendItem(context.original);
        }
    }

    function finish(action: string, context: var, exitCode: int, output: string, failure: string): void {
        loading = false;
        if (exitCode !== 0) {
            error = failure.trim() || "Notion operation failed";
            restore(context);
            return;
        }
        try {
            const payload = JSON.parse(output);
            if (action === "list") {
                items = payload.items ?? [];
                completedItems = payload.completedToday ?? [];
                statusOptions = payload.statusOptions ?? [];
                priorityOptions = payload.priorityOptions ?? [];
                error = String(payload.error ?? "");
            } else if (action === "create") {
                if (activeView === "mine")
                    appendItem(payload.item);
                clearCapture();
                widgetService.refresh();
                if (context.keepOpen)
                    Qt.callLater(() => captureInput.forceActiveFocus());
                else
                    close();
            } else if (action === "update") {
                replaceItem(payload.item);
                widgetService.refresh();
            } else if (action === "assign") {
                if (activeView === "mine")
                    appendItem(payload.item);
                widgetService.refresh();
            } else if (action === "complete") {
                widgetService.refresh();
            } else if (action === "reopen") {
                if (activeView === "mine")
                    replaceItem(payload.item);
                widgetService.refresh();
            }
        } catch (parseError) {
            error = "Could not read Notion response";
            restore(context);
        }
    }

    Connections {
        target: root.widgetService

        function onTasksChanged(): void {
            if (root.shown && !backend.running)
                root.loadView(root.activeView);
        }
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
            const action = backend.action;
            const context = backend.context;
            const output = backend.outputText;
            const failure = backend.errorText;
            Qt.callLater(() => root.finish(action, context, exitCode, output, failure));
        }
    }

    PanelWindow {
        id: overlay

        screen: root.targetScreen ?? Quickshell.screens[0]
        visible: root.targetScreen !== null && (root.shown || shade.opacity > 0.01)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        aboveWindows: true

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        WlrLayershell.namespace: "tom-todo-manager"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.None

        Rectangle {
            id: shade

            anchors.fill: parent
            color: "#99000000"
            opacity: root.shown ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 130 }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }
        }

        Rectangle {
            id: card

            anchors.centerIn: parent
            width: Math.min(780, overlay.width - 48)
            height: Math.min(720, overlay.height - 80)
            radius: 22
            color: "@surface@"
            border.width: 1
            border.color: "@border@"
            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.97

            Behavior on opacity { NumberAnimation { duration: 110 } }
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }

            FocusScope {
                anchors.fill: parent
                focus: root.shown
                Keys.onEscapePressed: root.close()

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    anchors.top: parent.top
                    anchors.topMargin: 17
                    text: "Tasks"
                    color: "@text@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.top: parent.top
                    anchors.topMargin: 19
                    text: "Esc"
                    color: "@subdued@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 11
                }

                Row {
                    id: tabs

                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.top: parent.top
                    anchors.topMargin: 54
                    spacing: 6

                    Repeater {
                        model: [
                            {id: "mine", label: "My tasks"},
                            {id: "unassigned", label: "Unassigned"},
                            {id: "all", label: "All"}
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            width: tabLabel.implicitWidth + 24
                            height: 32
                            radius: 10
                            color: root.activeView === modelData.id ? "@accentSurface@" : "transparent"
                            border.width: root.activeView === modelData.id ? 1 : 0
                            border.color: "@border@"

                            Text {
                                id: tabLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                color: root.activeView === modelData.id ? "@accent@" : "@subdued@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !backend.running
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.loadView(modelData.id)
                            }
                        }
                    }
                }

                Rectangle {
                    id: captureBox

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.top: tabs.bottom
                    anchors.topMargin: 10
                    height: root.captureExpanded ? 92 : 52
                    radius: 14
                    color: "@cardSurface@"
                    border.width: captureInput.activeFocus ? 1 : 0
                    border.color: "@accent@"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 15
                        anchors.top: parent.top
                        anchors.topMargin: 15
                        text: "+"
                        color: "@accent@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }

                    TextInput {
                        id: captureInput

                        anchors.left: parent.left
                        anchors.leftMargin: 42
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: 15
                        color: "@text@"
                        selectionColor: "@accent@"
                        selectedTextColor: "#11111b"
                        font.family: "@fontFamily@"
                        font.pixelSize: 14
                        clip: true

                        Text {
                            anchors.fill: parent
                            visible: captureInput.text === "" && !captureInput.activeFocus
                            text: "Quick capture · @tomorrow !high"
                            color: "@subdued@"
                            font: captureInput.font
                        }

                        Keys.onPressed: event => {
                            const control = (event.modifiers & Qt.ControlModifier) !== 0;
                            if (event.key === Qt.Key_Tab) {
                                root.expandCapture();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.submitCapture(control);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.close();
                                event.accepted = true;
                            }
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 42
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10
                        spacing: 10
                        visible: root.captureExpanded

                        Rectangle {
                            width: 150
                            height: 28
                            radius: 8
                            color: "@accentSurface@"

                            TextInput {
                                id: captureDue
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                verticalAlignment: TextInput.AlignVCenter
                                color: "@text@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 11
                                selectByMouse: true
                                Text {
                                    visible: captureDue.text === ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "No due date"
                                    color: "@subdued@"
                                    font: captureDue.font
                                }
                                Keys.onReturnPressed: root.submitCapture(false)
                                Keys.onEnterPressed: root.submitCapture(false)
                            }
                        }

                        Rectangle {
                            width: 112
                            height: 28
                            radius: 8
                            color: "@accentSurface@"

                            Text {
                                anchors.centerIn: parent
                                text: root.capturePriority === ""
                                    ? "No priority"
                                    : root.capturePriority[0].toUpperCase() + root.capturePriority.slice(1)
                                color: root.capturePriority === "" ? "@subdued@" : "@text@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 11
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const values = ["", "high", "medium", "low"];
                                    root.capturePriority = values[(values.indexOf(root.capturePriority) + 1) % values.length];
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Enter create · Ctrl+Enter keep open"
                            color: "@subdued@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 10
                        }
                    }
                }

                Rectangle {
                    id: searchBox

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.top: captureBox.bottom
                    anchors.topMargin: 10
                    height: 40
                    radius: 12
                    color: "@cardSurface@"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 13
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍉"
                        color: "@subdued@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 14
                    }

                    TextInput {
                        id: searchInput
                        anchors.left: parent.left
                        anchors.leftMargin: 38
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        color: "@text@"
                        selectionColor: "@accent@"
                        selectedTextColor: "#11111b"
                        font.family: "@fontFamily@"
                        font.pixelSize: 12
                        clip: true
                        onTextChanged: root.searchText = text
                        Keys.onEscapePressed: root.close()

                        Text {
                            anchors.fill: parent
                            visible: searchInput.text === ""
                            text: "Filter tasks"
                            color: "@subdued@"
                            font: searchInput.font
                        }
                    }
                }

                ListView {
                    id: taskList

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: searchBox.bottom
                    anchors.bottom: footer.top
                    anchors.margins: 16
                    anchors.topMargin: 10
                    clip: true
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.displayRows

                    delegate: Rectangle {
                        id: row

                        required property var modelData
                        readonly property bool section: modelData.kind === "section"
                            || modelData.kind === "completed-section"
                        readonly property bool completed: modelData.kind === "completed"
                        readonly property bool editable: !completed && Boolean(modelData.assignedToMe)
                        readonly property bool editing: root.editingId === modelData.id
                        width: taskList.width
                        height: section ? 30 : editing ? 94 : 50
                        radius: section ? 0 : 11
                        color: section ? "transparent" : rowMouse.containsMouse ? "@accentSurface@" : "@cardSurface@"

                        Text {
                            visible: row.section
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: `${row.modelData.title}  ${row.modelData.count}`
                            color: row.modelData.kind === "completed-section" ? "@accent@" : "@subdued@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            visible: row.modelData.kind === "completed-section"
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.completedExpanded = !root.completedExpanded
                        }

                        Rectangle {
                            visible: !row.section
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.top: parent.top
                            anchors.topMargin: 15
                            width: 20
                            height: 20
                            radius: 6
                            color: "transparent"
                            border.width: 1
                            border.color: row.completed ? "@accent@" : row.modelData.overdue ? "@muted@" : "@subdued@"

                            Text {
                                anchors.centerIn: parent
                                text: row.completed ? "✓" : ""
                                color: "@accent@"
                                font.pixelSize: 12
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !backend.running && (row.completed || row.editable)
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: row.completed
                                    ? root.reopenTask(row.modelData)
                                    : root.completeTask(row.modelData)
                            }
                        }

                        Column {
                            visible: !row.section && !row.editing
                            anchors.left: parent.left
                            anchors.leftMargin: 42
                            anchors.right: actions.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: row.modelData.title
                                color: row.completed ? "@subdued@" : "@text@"
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                font.family: "@fontFamily@"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                font.strikeout: row.completed
                            }

                            Text {
                                width: parent.width
                                text: {
                                    const parts = [];
                                    if (row.modelData.due)
                                        parts.push(row.modelData.overdue ? `Overdue · ${row.modelData.due}` : row.modelData.due);
                                    else
                                        parts.push("Inbox");
                                    if (row.modelData.priorityName)
                                        parts.push(row.modelData.priorityName);
                                    if (row.modelData.statusName)
                                        parts.push(row.modelData.statusName);
                                    if (!row.modelData.assignedToMe && !row.modelData.unassigned)
                                        parts.push((row.modelData.assignees ?? []).map(person => person.name).join(", "));
                                    return parts.join("  ·  ");
                                }
                                color: row.modelData.overdue ? "@muted@" : "@subdued@"
                                elide: Text.ElideRight
                                font.family: "@fontFamily@"
                                font.pixelSize: 9
                            }
                        }

                        Row {
                            id: actions
                            visible: !row.section && !row.editing
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Text {
                                visible: Boolean(row.modelData.unassigned) && !row.completed
                                text: "Assign to me"
                                color: "@accent@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -7
                                    enabled: !backend.running
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.assignToMe(row.modelData)
                                }
                            }

                            Text {
                                visible: row.editable
                                text: "󰏫"
                                color: "@subdued@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 13
                            }

                            Text {
                                text: "󰏌"
                                color: "@subdued@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 13

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -7
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openTask(row.modelData)
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            visible: !row.section && !row.editing
                            anchors.left: parent.left
                            anchors.leftMargin: 38
                            anchors.right: actions.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            hoverEnabled: true
                            cursorShape: row.editable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (row.editable)
                                    root.editingId = row.modelData.id;
                            }
                        }

                        TextInput {
                            id: titleEditor
                            visible: row.editing
                            anchors.left: parent.left
                            anchors.leftMargin: 42
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            height: 28
                            text: row.modelData.title ?? ""
                            color: "@text@"
                            selectionColor: "@accent@"
                            selectedTextColor: "#11111b"
                            font.family: "@fontFamily@"
                            font.pixelSize: 12
                            selectByMouse: true
                            Keys.onReturnPressed: root.updateTask(row.modelData, "title", text)
                            Keys.onEnterPressed: root.updateTask(row.modelData, "title", text)
                            Keys.onEscapePressed: root.editingId = ""
                        }

                        Row {
                            visible: row.editing
                            anchors.left: parent.left
                            anchors.leftMargin: 42
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            spacing: 8

                            Rectangle {
                                width: 132
                                height: 28
                                radius: 8
                                color: "@accentSurface@"

                                TextInput {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: row.modelData.due ?? ""
                                    color: "@text@"
                                    font.family: "@fontFamily@"
                                    font.pixelSize: 10
                                    selectByMouse: true
                                    Keys.onReturnPressed: root.updateTask(row.modelData, "due", text)
                                    Keys.onEnterPressed: root.updateTask(row.modelData, "due", text)
                                }
                            }

                            Rectangle {
                                width: 100
                                height: 28
                                radius: 8
                                color: "@accentSurface@"

                                Text {
                                    anchors.centerIn: parent
                                    text: row.modelData.priorityName || "No priority"
                                    color: row.modelData.priorityName ? "@text@" : "@subdued@"
                                    font.family: "@fontFamily@"
                                    font.pixelSize: 10
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !backend.running
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.cyclePriority(row.modelData)
                                }
                            }

                            Rectangle {
                                width: 112
                                height: 28
                                radius: 8
                                color: "@accentSurface@"

                                Text {
                                    anchors.centerIn: parent
                                    text: row.modelData.statusName || "Status"
                                    color: "@text@"
                                    font.family: "@fontFamily@"
                                    font.pixelSize: 10
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !backend.running
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.cycleStatus(row.modelData)
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Done"
                                color: "@accent@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -7
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.editingId = ""
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !root.loading && root.displayRows.length === 0
                        text: root.searchText === "" ? "All clear" : "No matching tasks"
                        color: "@subdued@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 13
                    }
                }

                Row {
                    id: footer

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    anchors.bottomMargin: 12
                    height: 22

                    Text {
                        width: parent.width - refreshText.width
                        text: root.error !== ""
                            ? root.error
                            : root.loading ? "Syncing with Notion…" : `${root.items.length} open tasks`
                        color: root.error !== "" ? "@muted@" : "@subdued@"
                        elide: Text.ElideRight
                        font.family: "@fontFamily@"
                        font.pixelSize: 10
                    }

                    Text {
                        id: refreshText
                        text: "Refresh"
                        color: "@accent@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -7
                            enabled: !backend.running
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.loadView(root.activeView)
                        }
                    }
                }
            }
        }
    }
}
