import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Effects

Scope {
    id: root
    required property var timerService
    required property var overlayController
    readonly property string overlayName: "launcher"


    property bool shown: false
    property var targetScreen: null
    property string lockedMode: ""
    property alias query: queryInput.text
    property int selectedIndex: 0
    property int providerRevision: 0
    property bool providerPending: false
    property bool providerCopied: false
    property string providerResult: ""
    property string providerError: ""
    property string providerCopyError: ""
    property string actionError: ""
    readonly property string queryMode: lockedMode !== "" ? lockedMode : modeForQuery(query)
    readonly property string searchText: lockedMode !== "" ? query.trim() : queryWithoutPrefix(query, queryMode)
    readonly property bool calculationMode: queryMode === "calculator" || queryMode === "unit"
    readonly property bool aiMode: queryMode === "ai"
    readonly property bool timerMode: queryMode === "timer"
    readonly property bool commandMode: calculationMode || timerMode
    readonly property bool listMode: queryMode === "applications"
        || queryMode === "clipboard"
        || queryMode === "herdr"
        || queryMode === "cameras"
    readonly property bool externalListMode: listMode && queryMode !== "applications"
    readonly property string providerExpression: calculationMode ? searchText : ""
    readonly property bool providerReady: providerResult !== "" && providerError === ""
    readonly property var results: queryMode === "applications"
        ? rankedApplications(searchText)
        : externalListMode ? rankedExternal(providers.itemsForMode(queryMode), searchText) : []
    readonly property int visibleResultCount: commandMode || aiMode
        ? 1
        : Math.max(1, results.length)
    readonly property bool visible: shown
    readonly property var iconOverrides: @iconOverrides@
    readonly property var customIcons: @customIcons@

    function normalized(value: var): string {
        return String(value ?? "").toLowerCase();
    }

    function modeForQuery(value: string): string {
        const lower = normalized(value);
        if (value.startsWith("="))
            return "calculator";
        if (lower === "u" || lower.startsWith("u "))
            return "unit";
        if (value.startsWith("?"))
            return "ai";
        if (lower === "timer" || lower.startsWith("timer "))
            return "timer";
        if (lower === "clip" || lower.startsWith("clip "))
            return "clipboard";
        if (lower === "h" || lower.startsWith("h "))
            return "herdr";
        if (lower === "cam" || lower.startsWith("cam "))
            return "cameras";
        return "applications";
    }

    function queryWithoutPrefix(value: string, mode: string): string {
        if (mode === "calculator" || mode === "ai")
            return value.slice(1).trim();
        if (mode === "timer")
            return value.slice(value.length > 5 ? 6 : 5).trim();
        if (mode === "unit" || mode === "herdr")
            return value.slice(value.includes(" ") ? 2 : 1).trim();
        if (mode === "clipboard")
            return value.slice(value.length > 4 ? 5 : 4).trim();
        if (mode === "cameras")
            return value.slice(value.length > 3 ? 4 : 3).trim();
        if (value === "@" || value.startsWith("@ "))
            return value.slice(value.length > 1 ? 2 : 1).trim();
        return value.trim();
    }

    function modeIcon(mode: string): string {
        if (mode === "calculator")
            return "=";
        if (mode === "unit")
            return "↔";
        if (mode === "ai")
            return "󰚩";
        if (mode === "timer")
            return "󰔛";
        if (mode === "clipboard")
            return "󰅇";
        if (mode === "herdr")
            return "π";
        if (mode === "cameras")
            return "󰄀";
        return "󰍉";
    }

    function modeTitle(mode: string): string {
        if (mode === "calculator")
            return "Calculator";
        if (mode === "unit")
            return "Unit conversion";
        if (mode === "ai")
            return "AI question";
        if (mode === "timer")
            return "Timer";
        if (mode === "clipboard")
            return "Clipboard";
        if (mode === "herdr")
            return "Herdr panes";
        if (mode === "cameras")
            return "Cameras";
        return "Applications";
    }

    function placeholderForMode(mode: string): string {
        if (mode === "ai")
            return "Ask a question";
        if (mode === "timer")
            return "20m pasta";
        if (mode === "clipboard")
            return "Search clipboard history";
        if (mode === "herdr")
            return "Search Herdr panes";
        if (mode === "cameras")
            return "Search cameras";
        return "Search applications";
    }

    function desktopIconSource(entry: var): string {
        const override = iconOverrides[normalized(entry.id)] ?? "";
        if (override !== "")
            return `file://${override}`;

        const icon = entry.icon;
        if (icon === "")
            return "";
        if (icon.startsWith("/"))
            return `file://${icon}`;
        if (icon.includes("://") || icon.startsWith("qrc:"))
            return icon;
        return Quickshell.iconPath(icon, true);
    }

    function customIconSource(entry: var): string {
        const icon = customIcons[normalized(entry.id)] ?? "";
        return icon === "" ? "" : `file://${icon}`;
    }

    function fuzzyScore(value: string, needle: string): real {
        if (needle === "")
            return 0;

        let cursor = -1;
        let consecutive = 0;
        let score = 0;
        for (let i = 0; i < needle.length; ++i) {
            const next = value.indexOf(needle[i], cursor + 1);
            if (next < 0)
                return -1;

            const gap = next - cursor - 1;
            consecutive = gap === 0 ? consecutive + 1 : 0;
            score += gap === 0
                ? 12 + consecutive * 3
                : Math.max(1, 8 - gap);
            if (next === 0 || " -_.".includes(value[next - 1]))
                score += 12;
            cursor = next;
        }
        return score - (value.length - needle.length) * 0.05;
    }

    function applicationScore(entry: var, needle: string): real {
        if (needle === "")
            return 0;

        const name = normalized(entry.name);
        const genericName = normalized(entry.genericName);
        const keywords = normalized(entry.keywords.join(" "));
        const id = normalized(entry.id);

        if (name === needle)
            return 10000;
        if (name.startsWith(needle))
            return 8000 - name.length;
        const nameWord = name.indexOf(` ${needle}`);
        if (nameWord >= 0)
            return 7000 - nameWord;
        const nameMatch = name.indexOf(needle);
        if (nameMatch >= 0)
            return 6000 - nameMatch;
        if (genericName.startsWith(needle))
            return 5000 - genericName.length;
        const genericMatch = genericName.indexOf(needle);
        if (genericMatch >= 0)
            return 4500 - genericMatch;
        const keywordMatch = keywords.indexOf(needle);
        if (keywordMatch >= 0)
            return 4000 - keywordMatch;
        const idMatch = id.indexOf(needle);
        if (idMatch >= 0)
            return 3500 - idMatch;

        const nameFuzzy = fuzzyScore(name, needle);
        const genericFuzzy = fuzzyScore(genericName, needle);
        const keywordFuzzy = fuzzyScore(keywords, needle);
        const idFuzzy = fuzzyScore(id, needle);
        return Math.max(
            nameFuzzy < 0 ? -1 : 2000 + nameFuzzy,
            genericFuzzy < 0 ? -1 : 1500 + genericFuzzy,
            keywordFuzzy < 0 ? -1 : 1200 + keywordFuzzy,
            idFuzzy < 0 ? -1 : 1000 + idFuzzy
        );
    }

    function resultOrder(left: var, right: var): int {
        const scoreDifference = right.score - left.score;
        if (scoreDifference !== 0)
            return scoreDifference;
        const leftTitle = left.entry ? left.entry.name : left.item.title;
        const rightTitle = right.entry ? right.entry.name : right.item.title;
        return leftTitle.localeCompare(rightTitle);
    }

    function rankedApplications(text: string): var {
        const needle = normalized(text).trim();
        const ranked = [];
        const applications = DesktopEntries.applications.values;
        for (let i = 0; i < applications.length; ++i) {
            const entry = applications[i];
            const score = applicationScore(entry, needle);
            if (score >= 0)
                ranked.push({ entry: entry, score: score });
        }
        ranked.sort(resultOrder);
        if (ranked.length > 10)
            ranked.length = 10;
        return ranked;
    }

    function externalScore(item: var, needle: string): real {
        if (needle === "")
            return 0;
        const title = normalized(item.title);
        const searchable = normalized(item.search || `${item.title} ${item.description}`);
        if (title === needle)
            return 10000;
        if (title.startsWith(needle))
            return 8000 - title.length;
        const titleMatch = title.indexOf(needle);
        if (titleMatch >= 0)
            return 6000 - titleMatch;
        const searchMatch = searchable.indexOf(needle);
        if (searchMatch >= 0)
            return 4000 - searchMatch;
        const fuzzy = fuzzyScore(searchable, needle);
        return fuzzy < 0 ? -1 : 2000 + fuzzy;
    }

    function rankedExternal(items: var, text: string): var {
        const needle = normalized(text).trim();
        const ranked = [];
        if (needle === "") {
            for (let i = 0; i < Math.min(items.length, 10); ++i)
                ranked.push({ item: items[i], score: 0 });
            return ranked;
        }
        for (const item of items) {
            const score = externalScore(item, needle);
            if (score >= 0)
                ranked.push({ item: item, score: score });
        }
        ranked.sort(resultOrder);
        if (ranked.length > 10)
            ranked.length = 10;
        return ranked;
    }

    function cleanProviderOutput(value: var): string {
        return String(value ?? "").trim().replace(/\s*\n\s*/g, " ");
    }

    function clearCalculation(): void {
        providerRevision++;
        providerDebounce.stop();
        providerPending = false;
        providerResult = "";
        providerError = "";
        providerCopyError = "";
        if (qalcProcess.running)
            qalcProcess.running = false;
    }

    function scheduleCalculation(): void {
        clearCalculation();
        providerCopied = false;
        if (!calculationMode || providerExpression === "")
            return;
        providerPending = true;
        providerDebounce.restart();
    }

    function evaluateCalculation(): void {
        if (!calculationMode || providerExpression === "")
            return;
        qalcProcess.activeExpression = providerExpression;
        qalcProcess.activeRevision = providerRevision;
        qalcProcess.outputText = "";
        qalcProcess.errorText = "";
        qalcProcess.running = true;
    }

    function finishCalculation(revision: int, expression: string, exitCode: int, output: string, error: string): void {
        if (revision !== providerRevision || !calculationMode || providerExpression !== expression)
            return;
        providerPending = false;
        const result = cleanProviderOutput(output);
        const failure = cleanProviderOutput(error);
        if (exitCode === 0 && result !== "") {
            providerResult = result;
            providerError = "";
            return;
        }
        providerResult = "";
        providerError = failure !== "" ? failure : "Unable to evaluate this expression";
    }

    function currentTextResult(): string {
        if (calculationMode)
            return providerResult;
        if (aiMode && providers.aiState === "ready")
            return providers.aiAnswer;
        return "";
    }

    function copyTextResult(text: string, keepOpen: bool): void {
        if (text === "" || textCopyProcess.running)
            return;
        providerCopied = false;
        providerCopyError = "";
        textCopyProcess.pendingText = text;
        textCopyProcess.closeAfterSuccess = !keepOpen;
        textCopyProcess.running = true;
    }

    function focusedScreen(): var {
        let monitor = Hyprland.focusedMonitor ?? null;
        if (!monitor) {
            const monitors = Hyprland.monitors.values;
            for (let i = 0; i < monitors.length; ++i) {
                if (monitors[i].focused) {
                    monitor = monitors[i];
                    break;
                }
            }
        }
        if (monitor) {
            for (let i = 0; i < Quickshell.screens.length; ++i) {
                if (Quickshell.screens[i].name === monitor.name)
                    return Quickshell.screens[i];
            }
        }
        return Quickshell.screens[0] ?? null;
    }

    function reveal(): void {
        revealMode("");
    }

    function revealMode(mode: string): void {
        targetScreen = focusedScreen();
        lockedMode = mode;
        queryInput.text = "";
        selectedIndex = 0;
        actionError = "";
        overlayController.claim(overlayName);
        shown = true;
        Qt.callLater(() => queryInput.forceActiveFocus());
    }

    function close(): void {
        shown = false;
        overlayController.release(overlayName);
        clearCalculation();
        providers.resetAi();
        queryInput.text = "";
        lockedMode = "";
        selectedIndex = 0;
        actionError = "";
    }

    function toggle(): void {
        if (shown)
            close();
        else
            reveal();
    }

    function toggleMode(mode: string): void {
        if (shown && lockedMode === mode)
            close();
        else
            revealMode(mode);
    }

    function moveSelection(delta: int): void {
        if (!listMode || results.length === 0)
            return;
        selectedIndex = (selectedIndex + delta + results.length) % results.length;
        resultsList.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function launchApplication(entry: var): void {
        if (!entry)
            return;
        const desktopId = entry.id.endsWith(".desktop")
            ? entry.id
            : `${entry.id}.desktop`;
        close();
        Quickshell.execDetached(["@uwsm@", "app", "--", desktopId]);
    }

    function activateSelected(shift: bool, control: bool): void {
        if (calculationMode) {
            copyTextResult(providerResult, control);
            return;
        }
        if (timerMode) {
            if (searchText !== "" && !providerPending) {
                providerPending = true;
                providerError = "";
                timerService.addTimer(searchText);
            }
            return;
        }
        if (aiMode) {
            if (providers.aiState === "running")
                return;
            if (providers.aiState === "ready") {
                if (shift) {
                    if (providers.resumeAi())
                        close();
                } else {
                    copyTextResult(providers.aiAnswer, control);
                }
                return;
            }
            providers.submitAi(searchText);
            return;
        }
        if (selectedIndex < 0 || selectedIndex >= results.length)
            return;
        if (queryMode === "applications") {
            launchApplication(results[selectedIndex].entry);
            return;
        }
        const item = results[selectedIndex].item;
        if (queryMode === "clipboard") {
            actionError = "";
            providers.copyClipboard(item);
        } else if (queryMode === "herdr") {
            close();
            providers.openHerdr(item, shift);
        } else if (queryMode === "cameras") {
            close();
            providers.openCamera(item);
        }
    }

    function handleEscape(): void {
        if (aiMode && providers.aiState === "running") {
            providers.cancelAi();
            return;
        }
        close();
    }

    function emptyMessage(): string {
        if (providers.loading)
            return "Loading…";
        if (actionError !== "")
            return actionError;
        if (providers.loadError !== "")
            return providers.loadError;
        if (queryMode === "clipboard")
            return "No matching clipboard entries";
        if (queryMode === "herdr")
            return "No matching Herdr panes";
        if (queryMode === "cameras")
            return "No matching cameras";
        return "No matching applications";
    }

    function externalGlyph(item: var): string {
        if (item.kind === "clipboard")
            return item.image ? "󰋩" : "󰅇";
        if (item.kind === "camera")
            return item.all ? "󰕧" : "󰄀";
        if (item.status === "working")
            return "󰔟";
        if (item.status === "blocked")
            return "󰅖";
        return "π";
    }

    onQueryChanged: {
        selectedIndex = 0;
        actionError = "";
        if (calculationMode)
            scheduleCalculation();
        else
            clearCalculation();
        if (aiMode && providers.aiState !== "running" && providers.aiQuestion !== "" && searchText !== providers.aiQuestion)
            providers.resetAi();
        if (listMode)
            Qt.callLater(() => resultsList.positionViewAtBeginning());
    }

    onQueryModeChanged: {
        selectedIndex = 0;
        if (!aiMode && providers.aiState !== "idle")
            providers.resetAi();
    }

    onResultsChanged: {
        if (results.length === 0)
            selectedIndex = 0;
        else if (selectedIndex >= results.length)
            selectedIndex = results.length - 1;
    }

    Connections {
        target: root.overlayController

        function onDismissRequested(except: string): void {
            if (except !== root.overlayName && root.shown)
                root.close();
        }
    }

    LauncherData {
        id: providers

        active: root.shown
        mode: root.queryMode
        onClipboardCopied: root.close()
        onClipboardCopyFailed: message => root.actionError = message
    }
    Connections {
        target: root.timerService

        function onTimerCreated(name: string): void {
            if (root.timerMode)
                root.close();
        }

        function onTimerCreationFailed(message: string): void {
            if (root.timerMode) {
                root.providerPending = false;
                root.providerError = message;
                queryInput.forceActiveFocus();
            }
        }
    }

    Timer {
        id: providerDebounce

        interval: 140
        onTriggered: root.evaluateCalculation()
    }

    Timer {
        id: copiedTimer

        interval: 900
        onTriggered: root.providerCopied = false
    }

    Process {
        id: qalcProcess

        property string activeExpression: ""
        property int activeRevision: 0
        property string outputText: ""
        property string errorText: ""

        command: ["@qalc@", "-t", "-s", "group 2", "-m", "1500", activeExpression]

        stdout: StdioCollector {
            onStreamFinished: qalcProcess.outputText = this.text
        }

        stderr: StdioCollector {
            onStreamFinished: qalcProcess.errorText = this.text
        }

        onExited: (exitCode, exitStatus) => {
            const revision = activeRevision;
            const expression = activeExpression;
            Qt.callLater(() => root.finishCalculation(
                revision,
                expression,
                exitCode,
                qalcProcess.outputText,
                qalcProcess.errorText
            ));
        }
    }

    Process {
        id: textCopyProcess

        property string pendingText: ""
        property bool closeAfterSuccess: false

        command: ["@wlCopy@", "--", pendingText]

        onExited: (exitCode, exitStatus) => {
            if (pendingText !== root.currentTextResult())
                return;
            if (exitCode !== 0) {
                root.providerCopyError = "Could not copy result";
                return;
            }
            root.providerCopied = true;
            copiedTimer.restart();
            if (closeAfterSuccess) {
                root.close();
            } else {
                queryInput.forceActiveFocus();
                queryInput.cursorPosition = queryInput.text.length;
            }
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

        WlrLayershell.namespace: "tom-launcher"
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
                NumberAnimation {
                    duration: 130
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }
        }

        Rectangle {
            id: card

            anchors.centerIn: parent
            width: Math.min(root.aiMode ? 760 : 640, overlay.width - 48)
            height: root.aiMode
                ? Math.min(480, overlay.height - 96)
                : Math.min(
                    122 + Math.max(
                        64,
                        root.visibleResultCount * (root.externalListMode ? 65 : 57) - 3
                    ),
                    overlay.height - 96
                )

            Behavior on height {
                NumberAnimation {
                    duration: 130
                    easing.type: Easing.OutCubic
                }
            }
            radius: 22
            color: "@surface@"
            border.width: 1
            border.color: "@border@"
            scale: root.shown ? 1 : 0.97
            opacity: root.shown ? 1 : 0

            Behavior on scale {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 110
                }
            }

            MouseArea {
                anchors.fill: parent
            }

            Rectangle {
                id: searchField

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 16
                height: 54
                radius: 14
                color: "@cardSurface@"
                border.width: queryInput.activeFocus ? 1 : 0
                border.color: "@accent@"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.modeIcon(root.queryMode)
                    color: "@accent@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 19
                    font.weight: root.queryMode === "applications" ? Font.Normal : Font.DemiBold
                }

                TextInput {
                    id: queryInput

                    anchors.left: parent.left
                    anchors.leftMargin: 50
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: "@text@"
                    selectionColor: "@accent@"
                    selectedTextColor: "#11111b"
                    font.family: "@fontFamily@"
                    font.pixelSize: 18
                    selectByMouse: true
                    clip: true
                    readOnly: root.aiMode && providers.aiState === "running"

                    Keys.onPressed: event => {
                        const control = (event.modifiers & Qt.ControlModifier) !== 0;
                        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                        if (event.key === Qt.Key_Down || (control && event.key === Qt.Key_N)) {
                            root.moveSelection(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || (control && event.key === Qt.Key_P)) {
                            root.moveSelection(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.activateSelected(shift, control);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            root.handleEscape();
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    anchors.left: queryInput.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: queryInput.text.length === 0
                    text: root.placeholderForMode(root.queryMode)
                    color: "@subdued@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 18
                }
            }

            ListView {
                id: resultsList

                anchors.top: searchField.bottom
                anchors.topMargin: 10
                anchors.bottom: footer.top
                anchors.bottomMargin: 8
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                visible: root.listMode
                clip: true
                spacing: 3
                model: root.results

                delegate: Rectangle {
                    id: resultRow

                    required property var modelData
                    required property int index
                    readonly property bool application: root.queryMode === "applications"
                    readonly property bool selected: index === root.selectedIndex
                    readonly property var item: application ? modelData.entry : modelData.item
                    readonly property string description: application
                        ? item.genericName !== "" ? item.genericName : item.comment
                        : item.description

                    width: resultsList.width
                    height: root.externalListMode ? 62 : 54
                    radius: 12
                    color: selected ? "@accentSurface@" : "transparent"
                    border.width: selected ? 1 : 0
                    border.color: "@border@"

                    Item {
                        id: iconSlot

                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: !resultRow.application && resultRow.item.image ? 52 : 34
                        height: !resultRow.application && resultRow.item.image ? 46 : 34

                        Rectangle {
                            anchors.fill: parent
                            radius: 9
                            color: "transparent"
                            border.width: 1
                            border.color: resultRow.selected ? "@accent@" : "@border@"
                        }

                        Image {
                            id: customIconSource

                            anchors.fill: parent
                            anchors.margins: 7
                            source: resultRow.application ? root.customIconSource(resultRow.item) : ""
                            sourceSize.width: 40
                            sourceSize.height: 40
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            visible: false
                        }

                        Image {
                            id: applicationIconSource

                            anchors.fill: parent
                            anchors.margins: 7
                            source: resultRow.application ? root.desktopIconSource(resultRow.item) : ""
                            sourceSize.width: 40
                            sourceSize.height: 40
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            visible: resultRow.application
                                && (customIconSource.status === Image.Null
                                    || customIconSource.status === Image.Error)
                                && status === Image.Ready
                        }

                        MultiEffect {
                            anchors.fill: customIconSource
                            source: customIconSource
                            colorization: 1
                            colorizationColor: "@accent@"
                            visible: resultRow.application && customIconSource.status === Image.Ready
                        }

                        Image {
                            id: clipboardThumbnail

                            anchors.fill: parent
                            anchors.margins: 3
                            source: !resultRow.application && resultRow.item.image && providers.thumbnailRevision > 0
                                ? `file://${resultRow.item.thumbnail}?v=${providers.thumbnailRevision}`
                                : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                            smooth: true
                            visible: status === Image.Ready
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: resultRow.application
                                ? (customIconSource.status === Image.Null
                                    || customIconSource.status === Image.Error)
                                    && applicationIconSource.status !== Image.Ready
                                : !resultRow.item.image || clipboardThumbnail.status !== Image.Ready
                            text: resultRow.application ? "󰀻" : root.externalGlyph(resultRow.item)
                            color: resultRow.selected ? "@accent@" : "@subdued@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 22
                        }
                    }

                    Column {
                        anchors.left: iconSlot.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: resultRow.item.name ?? resultRow.item.title
                            color: "@text@"
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            font.family: "@fontFamily@"
                            font.pixelSize: 15
                            font.weight: resultRow.selected ? Font.DemiBold : Font.Normal
                        }

                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: resultRow.description
                            color: "@subdued@"
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            font.family: "@fontFamily@"
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.selectedIndex = resultRow.index
                        onClicked: mouse => root.activateSelected(
                            (mouse.modifiers & Qt.ShiftModifier) !== 0,
                            (mouse.modifiers & Qt.ControlModifier) !== 0
                        )
                    }

                    Component.onCompleted: {
                        if (!application && item.image)
                            providers.requestThumbnail(item);
                    }
                }
            }

            Rectangle {
                id: calculationRow

                anchors.top: searchField.bottom
                anchors.topMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                height: 54
                visible: root.commandMode
                radius: 12
                color: "@accentSurface@"
                border.width: 1
                border.color: "@border@"

                Rectangle {
                    id: calculationIcon

                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34
                    height: 34
                    radius: 9
                    color: "transparent"
                    border.width: 1
                    border.color: "@accent@"

                    Text {
                        anchors.centerIn: parent
                        text: root.modeIcon(root.queryMode)
                        color: "@accent@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                    }
                }

                Column {
                    anchors.left: calculationIcon.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root.timerMode
                            ? root.providerPending
                                ? "Creating timer…"
                                : root.providerError !== ""
                                    ? "Could not create timer"
                                    : root.searchText !== ""
                                        ? `Start ${root.searchText}`
                                        : "Type a duration and optional name"
                            : root.providerCopied
                                ? "Copied to clipboard"
                                : root.providerCopyError !== ""
                                    ? root.providerCopyError
                                    : root.providerPending
                                        ? root.queryMode === "calculator" ? "Calculating…" : "Converting…"
                                        : root.providerError !== ""
                                            ? "Could not evaluate"
                                            : root.providerReady
                                                ? root.providerResult
                                                : root.queryMode === "calculator"
                                                    ? "Type an expression after ="
                                                    : "Type a conversion after u"
                        color: "@text@"
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        font.family: "@fontFamily@"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: root.providerError !== "" ? root.providerError : root.providerExpression || root.searchText
                        color: "@subdued@"
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        font.family: "@fontFamily@"
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.timerMode ? root.searchText !== "" && !root.providerPending : root.providerReady
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.activateSelected(false, false)
                }
            }

            Rectangle {
                id: aiAnswerCard

                anchors.top: searchField.bottom
                anchors.topMargin: 10
                anchors.bottom: footer.top
                anchors.bottomMargin: 8
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                visible: root.aiMode
                radius: 12
                color: "@accentSurface@"
                border.width: 1
                border.color: "@border@"

                Flickable {
                    id: answerFlick

                    anchors.fill: parent
                    anchors.margins: 16
                    clip: true
                    contentWidth: width
                    contentHeight: Math.max(height, answerText.implicitHeight)
                    boundsBehavior: Flickable.StopAtBounds

                    Text {
                        id: answerText

                        width: answerFlick.width
                        text: root.providerCopied
                            ? "Copied to clipboard"
                            : providers.aiState === "running"
                                ? "Thinking…"
                                : providers.aiState === "error"
                                    ? providers.aiError
                                    : providers.aiState === "ready"
                                        ? providers.aiAnswer
                                        : "Type a question and press Enter"
                        color: "@text@"
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        font.family: "@fontFamily@"
                        font.pixelSize: 15
                        lineHeight: 1.2
                    }
                }
            }

            Text {
                anchors.centerIn: resultsList
                visible: root.listMode && root.results.length === 0
                text: root.emptyMessage()
                color: "@subdued@"
                font.family: "@fontFamily@"
                font.pixelSize: 14
            }

            Item {
                id: footer

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.bottomMargin: 10
                height: 24

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.modeTitle(root.queryMode)
                    color: "@subdued@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 11
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.aiMode
                        ? providers.aiState === "running"
                            ? "Esc cancel"
                            : providers.aiState === "ready"
                                ? "Enter copy   Ctrl+Enter keep   Shift+Enter continue"
                                : "Enter ask   Esc close"
                        : root.timerMode
                            ? "Enter start timer   Esc close"
                            : root.calculationMode
                                ? "Enter copy   Ctrl+Enter copy and keep   Esc close"
                                : root.queryMode === "herdr"
                                    ? "↑↓ navigate   Enter view   Shift+Enter take over"
                                    : root.queryMode === "clipboard"
                                        ? "↑↓ navigate   Enter restore   Esc close"
                                        : "↑↓ navigate   Enter launch   Esc close"
                    color: "@subdued@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 11
                }
            }
        }
    }
}
