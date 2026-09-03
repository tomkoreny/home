import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    property bool shown: false
    property var targetScreen: null
    property alias query: queryInput.text
    property int selectedIndex: 0
    readonly property var results: rankedApplications(query)
    readonly property bool visible: shown

    function normalized(value: var): string {
        return String(value ?? "").toLowerCase();
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

    PanelWindow {
        id: overlay

        screen: root.targetScreen ?? Quickshell.screens[0]
        visible: root.targetScreen !== null && (root.shown || shade.opacity > 0.01)
        color: "transparent"
        exclusiveZone: 0
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
                122 + Math.max(64, root.results.length * 57 - 3),
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
                    text: "󰍉"
                    color: "@accent@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 19
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

                    Image {
                        id: applicationIcon

                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 34
                        source: resultRow.entry.icon !== ""
                            ? Quickshell.iconPath(resultRow.entry.icon, true)
                            : ""
                        sourceSize.width: 34
                        sourceSize.height: 34
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: applicationIcon
                        visible: !applicationIcon.visible
                        text: "󰀻"
                        color: resultRow.selected ? "@accent@" : "@subdued@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 22
                    }

                    Column {
                        anchors.left: applicationIcon.right
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

            Text {
                anchors.centerIn: resultsList
                visible: root.results.length === 0
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
                    text: `${root.results.length} result${root.results.length === 1 ? "" : "s"}`
                    color: "@subdued@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 11
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "↑↓ navigate   Enter launch   Esc close"
                    color: "@subdued@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 11
                }
            }
        }
    }
}
