import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    required property var service
    required property var overlayController
    readonly property string overlayName: "workTasks"
    property bool shown: false
    readonly property bool visible: shown
    property var targetScreen: null
    property string searchText: ""
    property string statusFilter: ""
    property string popupKind: ""
    property var popupTask: null
    property real popupX: 0
    property real popupY: 0
    readonly property bool popupVisible: popupKind !== ""
    readonly property var displayRows: service.items.filter(task => {
        const query = searchText.trim().toLocaleLowerCase();
        return (statusFilter === "" || task.statusId === statusFilter) && (query === "" || (task.title + " " + task.searchTerms).toLocaleLowerCase().includes(query));
    })
    readonly property var popupOptions: popupKind === "filter" ? [
        {
            id: "",
            label: "All statuses"
        }
    ].concat(service.statusOptions.map(option => ({
                id: option.id,
                label: option.name
            }))) : popupTask ? popupTask.actions : []
    readonly property string filterLabel: statusFilter === "" ? "All statuses" : (service.statusOptions.find(option => option.id === statusFilter)?.name ?? "Selected status")

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

    function toggle(): void {
        if (shown) {
            close();
        } else {
            targetScreen = focusedScreen();
            overlayController.claim(overlayName);
            shown = true;
            service.refresh();
            Qt.callLater(() => searchInput.forceActiveFocus());
        }
    }

    function close(): void {
        popupKind = "";
        popupTask = null;
        shown = false;
        overlayController.release(overlayName);
        searchText = "";
        searchInput.text = "";
    }

    function closePopup(): void {
        const wasFilter = popupKind === "filter";
        popupKind = "";
        popupTask = null;
        if (wasFilter)
            filterButton.forceActiveFocus();
        else
            taskList.forceActiveFocus();
    }

    function showPopup(kind: string, task: var, anchor: var): void {
        if (kind === "actions" && (service.stale || service.busy || !task.actions.length))
            return;
        const point = anchor.mapToItem(card, 0, anchor.height + 6);
        popupX = point.x;
        popupY = point.y;
        popupTask = task;
        popupKind = kind;
        choiceList.currentIndex = kind === "filter" ? Math.max(0, popupOptions.findIndex(option => option.id === statusFilter)) : 0;
        Qt.callLater(() => {
            choiceList.forceActiveFocus();
            choiceList.positionViewAtIndex(choiceList.currentIndex, ListView.Contain);
        });
    }

    function choose(index: int): void {
        const option = popupOptions[index];
        if (!option)
            return;
        if (popupKind === "filter")
            statusFilter = option.id;
        else
            service.transition(popupTask, option);
        closePopup();
    }

    function moveSelection(delta: int): void {
        if (!displayRows.length)
            return;
        taskList.currentIndex = Math.max(0, Math.min(displayRows.length - 1, taskList.currentIndex + delta));
        taskList.forceActiveFocus();
        taskList.positionViewAtIndex(taskList.currentIndex, ListView.Contain);
    }

    function openSelected(): void {
        const task = displayRows[taskList.currentIndex];
        if (task)
            service.openTask(task);
    }

    onDisplayRowsChanged: {
        if (!taskList)
            return;
        taskList.currentIndex = displayRows.length ? Math.min(Math.max(taskList.currentIndex, 0), displayRows.length - 1) : -1;
        if (popupKind === "actions")
            closePopup();
    }

    Connections {
        target: root.overlayController
        function onDismissRequested(except: string): void {
            if (except !== root.overlayName && root.shown)
                root.close();
        }
    }

    Connections {
        target: root.service
        function onBusyChanged(): void {
            if (root.service.busy && root.popupKind === "actions")
                root.closePopup();
        }
        function onStaleChanged(): void {
            if (root.service.stale && root.popupKind === "actions")
                root.closePopup();
        }
    }

    component ActionButton: Rectangle {
        id: button
        property string label: ""
        property bool selected: false
        signal triggered
        implicitWidth: Math.min(190, buttonText.implicitWidth + 24)
        implicitHeight: 32
        radius: 9
        color: selected || buttonMouse.containsMouse || activeFocus ? "@accentSurface@" : "@cardSurface@"
        border.width: activeFocus ? 1 : 0
        border.color: "@accent@"
        opacity: enabled ? 1 : 0.5
        activeFocusOnTab: true
        Keys.onReturnPressed: triggered()
        Keys.onEnterPressed: triggered()
        Keys.onSpacePressed: triggered()
        Text {
            id: buttonText
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: button.label
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font.family: "@fontFamily@"
            font.pixelSize: 11
            color: "@accent@"
        }
        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                button.forceActiveFocus();
                button.triggered();
            }
        }
    }

    PanelWindow {
        id: overlay
        screen: root.targetScreen ?? Quickshell.screens[0]
        visible: root.targetScreen !== null && root.shown
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        aboveWindows: true
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        WlrLayershell.namespace: "tom-work-task-manager"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: "#99000000"
            MouseArea {
                anchors.fill: parent
                onClicked: root.popupVisible ? root.closePopup() : root.close()
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.max(0, Math.min(780, overlay.width - 32))
            height: Math.max(0, Math.min(720, overlay.height - 48))
            radius: 22
            color: "@surface@"
            border.width: 1
            border.color: "@border@"
            clip: true
            MouseArea {
                anchors.fill: parent
            }

            FocusScope {
                id: content
                anchors.fill: parent
                focus: root.shown
                enabled: !root.popupVisible
                Keys.onEscapePressed: root.close()
                Keys.onDownPressed: root.moveSelection(1)
                Keys.onUpPressed: root.moveSelection(-1)
                Keys.onReturnPressed: root.openSelected()
                Keys.onEnterPressed: root.openSelected()

                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 20
                    anchors.right: refreshButton.left
                    anchors.rightMargin: 12
                    text: "Work tasks"
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: "@text@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
                ActionButton {
                    id: refreshButton
                    anchors.right: closeButton.left
                    anchors.rightMargin: 8
                    anchors.top: parent.top
                    anchors.topMargin: 16
                    label: root.service.loading ? "Refreshing…" : "Refresh"
                    enabled: root.service.enabled
                    onTriggered: root.service.refresh()
                }
                ActionButton {
                    id: closeButton
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    label: "Esc"
                    onTriggered: root.close()
                }

                Rectangle {
                    id: searchBox
                    anchors.left: parent.left
                    anchors.right: filterButton.left
                    anchors.top: parent.top
                    anchors.leftMargin: 20
                    anchors.rightMargin: 10
                    anchors.topMargin: 66
                    height: 38
                    radius: 12
                    color: "@cardSurface@"
                    border.width: searchInput.activeFocus ? 1 : 0
                    border.color: "@accent@"
                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: "@text@"
                        selectionColor: "@accent@"
                        selectedTextColor: "@surface@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 12
                        clip: true
                        selectByMouse: true
                        activeFocusOnTab: true
                        onTextChanged: root.searchText = text
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: searchInput.text === ""
                            text: "Search work tasks"
                            color: "@subdued@"
                            font: searchInput.font
                            elide: Text.ElideRight
                        }
                    }
                }
                ActionButton {
                    id: filterButton
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: searchBox.verticalCenter
                    width: Math.min(190, card.width * 0.3)
                    height: 38
                    label: root.filterLabel
                    selected: root.statusFilter !== ""
                    onTriggered: root.showPopup("filter", null, filterButton)
                }

                ListView {
                    id: taskList
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: searchBox.bottom
                    anchors.bottom: footer.top
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    anchors.topMargin: 14
                    anchors.bottomMargin: 12
                    clip: true
                    spacing: 5
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.displayRows
                    currentIndex: count ? 0 : -1
                    activeFocusOnTab: count > 0
                    keyNavigationEnabled: false
                    Keys.onTabPressed: event => {
                        if (currentItem && currentItem.statusControl.enabled)
                            currentItem.statusControl.forceActiveFocus();
                        else
                            event.accepted = false;
                    }

                    delegate: Rectangle {
                        id: taskRow
                        required property var modelData
                        required property int index
                        property alias statusControl: statusButton
                        width: taskList.width
                        height: 52
                        radius: 11
                        color: titleMouse.containsMouse || taskList.currentIndex === index ? "@accentSurface@" : "@cardSurface@"
                        border.width: taskList.activeFocus && taskList.currentIndex === index ? 1 : 0
                        border.color: "@accent@"

                        Item {
                            id: titleButton
                            anchors.left: parent.left
                            anchors.right: statusButton.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            activeFocusOnTab: true
                            onActiveFocusChanged: {
                                if (activeFocus)
                                    taskList.currentIndex = taskRow.index;
                            }
                            Keys.onReturnPressed: root.service.openTask(taskRow.modelData)
                            Keys.onEnterPressed: root.service.openTask(taskRow.modelData)
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: taskRow.modelData.title
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: titleButton.activeFocus ? "@accent@" : "@text@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: titleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    taskList.currentIndex = taskRow.index;
                                    root.service.openTask(taskRow.modelData);
                                }
                            }
                        }
                        ActionButton {
                            id: statusButton
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(200, taskRow.width * 0.35)
                            label: root.service.pendingId === taskRow.modelData.id ? taskRow.modelData.statusName + " · Saving…" : taskRow.modelData.statusName
                            enabled: !root.service.stale && !root.service.busy && taskRow.modelData.actions.length > 0
                            onActiveFocusChanged: {
                                if (activeFocus)
                                    taskList.currentIndex = taskRow.index;
                            }
                            onTriggered: root.showPopup("actions", taskRow.modelData, statusButton)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: taskList.count === 0
                        text: root.service.loading ? "Loading work tasks…" : root.service.items.length === 0 ? (root.service.stale ? "No cached work tasks" : "No actionable work tasks") : "No matching tasks"
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: "@subdued@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 13
                    }
                }

                Column {
                    id: footer
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 20
                    spacing: 6
                    Text {
                        width: parent.width
                        visible: root.service.error !== ""
                        text: root.service.error
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        color: "@muted@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 11
                    }
                    Text {
                        width: parent.width
                        text: (root.service.pendingId !== "" ? "Saving status…" : root.service.loading ? "Refreshing work tasks…" : root.service.actionableCount + " actionable tasks") + (root.service.stale ? " · Stale — refresh before changing status" : "")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: root.service.stale ? "@muted@" : "@subdued@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 11
                    }
                    Text {
                        width: parent.width
                        text: (root.service.updatedAt ? "Updated " + root.service.updatedAt + " · " : "") + "↑↓ select · Enter open · Tab status · Esc close"
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: "@subdued@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 10
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                visible: root.popupVisible
                onClicked: root.closePopup()
            }
            Rectangle {
                id: chooser
                visible: root.popupVisible
                width: Math.min(320, Math.max(0, card.width - 24))
                height: Math.min(choiceList.contentHeight + 16, 300, Math.max(0, card.height - 24))
                x: Math.max(12, Math.min(root.popupX, card.width - width - 12))
                y: Math.max(12, Math.min(root.popupY, card.height - height - 12))
                radius: 12
                color: "@cardSurface@"
                border.width: 1
                border.color: "@border@"
                clip: true
                MouseArea {
                    anchors.fill: parent
                }
                ListView {
                    id: choiceList
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    spacing: 3
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.popupOptions
                    activeFocusOnTab: root.popupVisible
                    keyNavigationEnabled: false
                    Keys.onEscapePressed: root.closePopup()
                    Keys.onReturnPressed: root.choose(currentIndex)
                    Keys.onEnterPressed: root.choose(currentIndex)
                    Keys.onSpacePressed: root.choose(currentIndex)
                    Keys.onPressed: event => {
                        let delta = 0;
                        if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab)
                            delta = (event.modifiers & Qt.ShiftModifier) ? -1 : 1;
                        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)
                            delta = -1;
                        if (delta !== 0 && count > 0) {
                            currentIndex = (currentIndex + delta + count) % count;
                            positionViewAtIndex(currentIndex, ListView.Contain);
                            event.accepted = true;
                        }
                    }
                    delegate: Rectangle {
                        id: choiceRow
                        required property var modelData
                        required property int index
                        width: choiceList.width
                        height: 36
                        radius: 8
                        color: choiceList.currentIndex === index || choiceMouse.containsMouse ? "@accentSurface@" : "transparent"
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: Text.AlignVCenter
                            text: choiceRow.modelData.label
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: "@text@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: choiceMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.choose(choiceRow.index)
                        }
                    }
                }
            }
        }
    }
}
