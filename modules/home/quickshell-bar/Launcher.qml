import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Effects

Scope {
    id: root

    property bool shown: false
    property var targetScreen: null
    property alias query: queryInput.text
    property int selectedIndex: 0
    property int providerRevision: 0
    property bool providerPending: false
    property bool providerCopied: false
    property string providerResult: ""
    property string providerError: ""
    property string providerCopyError: ""
    readonly property string queryMode: query.startsWith("=")
        ? "calculator"
        : normalized(query).startsWith("u ") ? "unit" : "applications"
    readonly property bool providerMode: queryMode !== "applications"
    readonly property string providerExpression: providerMode
        ? query.slice(queryMode === "calculator" ? 1 : 2).trim()
        : ""
    readonly property bool providerReady: providerResult !== "" && providerError === ""
    readonly property var results: providerMode ? [] : rankedApplications(query)
    readonly property int visibleResultCount: providerMode ? 1 : results.length
    readonly property bool visible: shown
    readonly property var iconOverrides: @iconOverrides@
    readonly property var customIcons: @customIcons@

    function normalized(value: var): string {
        return String(value ?? "").toLowerCase();
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

    function applicationOrder(left: var, right: var): int {
        const scoreDifference = right.score - left.score;
        if (scoreDifference !== 0)
            return scoreDifference;
        return left.entry.name.localeCompare(right.entry.name);
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
        ranked.sort(applicationOrder);
        if (ranked.length > 10)
            ranked.length = 10;
        return ranked;
    }

    function cleanProviderOutput(value: var): string {
        return String(value ?? "").trim().replace(/\s*\n\s*/g, " ");
    }

    function scheduleProvider(): void {
        providerRevision++;
        providerDebounce.stop();
        providerCopied = false;
        providerResult = "";
        providerError = "";
        providerCopyError = "";
        if (qalcProcess.running)
            qalcProcess.running = false;
        if (!providerMode || providerExpression === "") {
            providerPending = false;
            return;
        }
        providerPending = true;
        providerDebounce.restart();
    }

    function evaluateProvider(): void {
        if (!providerMode || providerExpression === "")
            return;
        qalcProcess.activeExpression = providerExpression;
        qalcProcess.activeRevision = providerRevision;
        qalcProcess.outputText = "";
        qalcProcess.errorText = "";
        qalcProcess.running = true;
    }

    function finishProvider(revision: int, expression: string, exitCode: int, output: string, error: string): void {
        if (revision !== providerRevision || !providerMode || providerExpression !== expression)
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

    function copyProviderResult(keepOpen: bool): void {
        if (!providerReady || clipboardProcess.running)
            return;
        providerCopied = false;
        providerCopyError = "";
        clipboardProcess.pendingText = providerResult;
        clipboardProcess.closeAfterSuccess = !keepOpen;
        clipboardProcess.running = true;
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
        targetScreen = focusedScreen();
        queryInput.text = "";
        selectedIndex = 0;
        shown = true;
        Qt.callLater(() => queryInput.forceActiveFocus());
    }

    function close(): void {
        shown = false;
        queryInput.text = "";
        selectedIndex = 0;
    }

    function toggle(): void {
        if (shown)
            close();
        else
            reveal();
    }

    function moveSelection(delta: int): void {
        if (results.length === 0)
            return;
        selectedIndex = (selectedIndex + delta + results.length) % results.length;
        resultsList.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function launch(entry): void {
        if (!entry)
            return;
        const desktopId = entry.id.endsWith(".desktop")
            ? entry.id
            : `${entry.id}.desktop`;
        close();
        Quickshell.execDetached(["@uwsm@", "app", "--", desktopId]);
    }

    function launchSelected(): void {
        if (providerMode) {
            copyProviderResult(false);
            return;
        }
        if (selectedIndex < 0 || selectedIndex >= results.length)
            return;
        launch(results[selectedIndex].entry);
    }

    onResultsChanged: {
        if (results.length === 0)
            selectedIndex = 0;
        else if (selectedIndex >= results.length)
            selectedIndex = results.length - 1;
    }

    Timer {
        id: providerDebounce

        interval: 140
        onTriggered: root.evaluateProvider()
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

        command: ["@qalc@", "-t", "-m", "1500", activeExpression]

        stdout: StdioCollector {
            onStreamFinished: qalcProcess.outputText = this.text
        }

        stderr: StdioCollector {
            onStreamFinished: qalcProcess.errorText = this.text
        }

        onExited: (exitCode, exitStatus) => {
            const revision = activeRevision;
            const expression = activeExpression;
            Qt.callLater(() => root.finishProvider(
                revision,
                expression,
                exitCode,
                qalcProcess.outputText,
                qalcProcess.errorText
            ));
        }
    }

    Process {
        id: clipboardProcess

        property string pendingText: ""
        property bool closeAfterSuccess: false

        command: ["@wlCopy@", "--", pendingText]

        onExited: (exitCode, exitStatus) => {
            if (pendingText !== root.providerResult)
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
            width: Math.min(640, overlay.width - 48)
            height: Math.min(
                122 + Math.max(64, root.visibleResultCount * 57 - 3),
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
                    text: root.queryMode === "calculator"
                        ? "="
                        : root.queryMode === "unit" ? "↔" : "󰍉"
                    color: "@accent@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 19
                    font.weight: root.providerMode ? Font.DemiBold : Font.Normal
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

                    onTextChanged: {
                        root.selectedIndex = 0;
                        root.scheduleProvider();
                        if (!root.providerMode)
                            Qt.callLater(() => resultsList.positionViewAtBeginning());
                    }

                    Keys.onPressed: event => {
                        const control = (event.modifiers & Qt.ControlModifier) !== 0;
                        if (event.key === Qt.Key_Down || (control && event.key === Qt.Key_N)) {
                            root.moveSelection(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || (control && event.key === Qt.Key_P)) {
                            root.moveSelection(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (root.providerMode)
                                root.copyProviderResult(control);
                            else
                                root.launchSelected();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            root.close();
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    anchors.left: queryInput.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: queryInput.text.length === 0
                    text: "Search applications"
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
                clip: true
                spacing: 3
                model: root.results

                delegate: Rectangle {
                    id: resultRow

                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.selectedIndex
                    readonly property var entry: modelData.entry
                    readonly property string description: entry.genericName !== ""
                        ? entry.genericName
                        : entry.comment

                    width: resultsList.width
                    height: 54
                    radius: 12
                    color: selected ? "@accentSurface@" : "transparent"
                    border.width: selected ? 1 : 0
                    border.color: "@border@"

                    Item {
                        id: iconSlot

                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 34

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
                            source: root.customIconSource(resultRow.entry)
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
                            source: root.desktopIconSource(resultRow.entry)
                            sourceSize.width: 40
                            sourceSize.height: 40
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            visible: (customIconSource.status === Image.Null
                                || customIconSource.status === Image.Error)
                                && status === Image.Ready
                        }

                        MultiEffect {
                            anchors.fill: customIconSource
                            source: customIconSource
                            colorization: 1
                            colorizationColor: "@accent@"
                            visible: customIconSource.status === Image.Ready
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: (customIconSource.status === Image.Null
                                || customIconSource.status === Image.Error)
                                && applicationIconSource.status !== Image.Ready
                            text: "󰀻"
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
                            text: resultRow.entry.name
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
                        onClicked: root.launch(resultRow.entry)
                    }
                }
            }

            Rectangle {
                id: providerRow

                anchors.top: searchField.bottom
                anchors.topMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                height: 54
                visible: root.providerMode
                radius: 12
                color: "@accentSurface@"
                border.width: 1
                border.color: "@border@"

                Rectangle {
                    id: providerIcon

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
                        text: root.queryMode === "calculator" ? "=" : "↔"
                        color: "@accent@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                    }
                }

                Column {
                    anchors.left: providerIcon.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root.providerCopied
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
                        text: root.providerError !== ""
                            ? root.providerError
                            : root.providerExpression
                        color: "@subdued@"
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        font.family: "@fontFamily@"
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.providerReady
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.copyProviderResult(false)
                }
            }

            Text {
                anchors.centerIn: resultsList
                visible: !root.providerMode && root.results.length === 0
                text: "No matching applications"
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
                    text: root.queryMode === "calculator"
                        ? "Calculator"
                        : root.queryMode === "unit"
                            ? "Unit conversion"
                            : `${root.results.length} result${root.results.length === 1 ? "" : "s"}`
                    color: "@subdued@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 11
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.providerMode
                        ? "Enter copy   Ctrl+Enter copy and keep   Esc close"
                        : "↑↓ navigate   Enter launch   Esc close"
                    color: "@subdued@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 11
                }
            }
        }
    }
}
