import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import QtQuick

Scope {
    id: root
    required property var overlayController
    readonly property string overlayName: "notifications"

    property var entries: []
    property bool doNotDisturb: false
    property int unreadCount: 0
    readonly property bool centerVisible: center.shown
    readonly property var bannerEntries: entries
        .filter(entry => entry.bannerVisible)
        .slice(0, 5)
    readonly property bool hasOmpCompletion: entries.some(entry =>
        entry.notification.summary.toLowerCase() === "omp finished"
    )
    readonly property var targetScreen: {
        for (let i = 0; i < Quickshell.screens.length; ++i) {
            const candidate = Quickshell.screens[i];
            if (candidate.name === "@primaryOutput@")
                return candidate;
        }
        return null;
    }

    function herdrContext(agent, snapshot): string {
        const workspaces = snapshot.workspaces ?? [];
        const workspace = workspaces.find(candidate =>
            candidate.workspace_id === agent.workspace_id
        );
        if (!workspace)
            return "";

        let context = `${workspace.label} · ${workspace.number}`;
        const tabs = (snapshot.tabs ?? []).filter(candidate =>
            candidate.workspace_id === workspace.workspace_id
        );
        if (tabs.length > 1) {
            const tab = tabs.find(candidate => candidate.tab_id === agent.tab_id);
            if (tab && tab.label)
                context += ` · ${tab.label}`;
        }
        return context;
    }

    function reconcileHerdr(snapshot, userViewingHerdr): void {
        if (!userViewingHerdr)
            return;

        const focusedAgents = (snapshot.agents ?? []).filter(agent =>
            agent.agent === "omp" && agent.focused
        );
        for (const agent of focusedAgents) {
            const context = herdrContext(agent, snapshot);
            if (context === "")
                continue;
            for (const entry of entries.slice()) {
                const notification = entry.notification;
                if (notification.summary.toLowerCase() === "omp finished"
                        && notification.body === context)
                    notification.dismiss();
            }
        }
    }

    function isCritical(notification): bool {
        return notification.urgency === NotificationUrgency.Critical;
    }

    function addNotification(notification): void {
        notification.tracked = true;

        const now = Date.now();
        const carriedOver = notification.lastGeneration;
        const entry = {
            notification: notification,
            receivedAt: now,
            unread: !carriedOver,
            bannerVisible: !carriedOver
                && (!doNotDisturb || isCritical(notification)),
            bannerDeadline: isCritical(notification) ? 0 : now + 7000,
            pausedAt: 0
        };

        notification.closed.connect(() => root.removeNotification(notification));
        const next = [entry].concat(entries);
        const removed = next.slice(50);
        entries = next.slice(0, 50);

        if (entry.unread)
            unreadCount += 1;
        for (const oldEntry of removed)
            oldEntry.notification.dismiss();
    }

    function entryFor(notification) {
        return entries.find(entry => entry.notification === notification) ?? null;
    }

    function removeNotification(notification): void {
        const entry = entryFor(notification);
        if (!entry)
            return;
        if (entry.unread)
            unreadCount = Math.max(0, unreadCount - 1);
        entries = entries.filter(candidate => candidate !== entry);
    }

    function hideBanner(notification): void {
        const entry = entryFor(notification);
        if (!entry || !entry.bannerVisible)
            return;
        entry.bannerVisible = false;
        entry.pausedAt = 0;
        entries = entries.slice();
    }

    function hideAllBanners(): void {
        let changed = false;
        for (const entry of entries) {
            if (!entry.bannerVisible)
                continue;
            entry.bannerVisible = false;
            entry.pausedAt = 0;
            changed = true;
        }
        if (changed)
            entries = entries.slice();
    }

    function markAllRead(): void {
        for (const entry of entries)
            entry.unread = false;
        unreadCount = 0;
    }

    function clearAll(): void {
        const removed = entries.slice();
        entries = [];
        unreadCount = 0;
        for (const entry of removed)
            entry.notification.dismiss();
    }

    function toggleDoNotDisturb(): void {
        doNotDisturb = !doNotDisturb;
        if (!doNotDisturb)
            return;

        let changed = false;
        for (const entry of entries) {
            if (entry.bannerVisible && !isCritical(entry.notification)) {
                entry.bannerVisible = false;
                entry.pausedAt = 0;
                changed = true;
            }
        }
        if (changed)
            entries = entries.slice();
    }

    function revealCenter(): void {
        overlayController.claim(overlayName);
        center.shown = true;
    }

    function closeCenter(): void {
        center.shown = false;
        overlayController.release(overlayName);
    }

    function toggleCenter(): void {
        if (center.shown)
            closeCenter();
        else
            revealCenter();
    }

    Connections {
        target: root.overlayController

        function onDismissRequested(except: string): void {
            if (except !== root.overlayName && center.shown)
                root.closeCenter();
        }
    }

    NotificationServer {
        id: server

        actionsSupported: true
        bodySupported: true
        bodyImagesSupported: false
        bodyMarkupSupported: false
        imageSupported: true
        keepOnReload: true
        persistenceSupported: true

        onNotification: notification => root.addNotification(notification)
    }

    PanelWindow {
        id: banners

        screen: root.targetScreen ?? Quickshell.screens[0]
        visible: root.targetScreen !== null && root.bannerEntries.length > 0
        color: "transparent"
        implicitWidth: 400
        implicitHeight: bannerColumn.implicitHeight
        exclusiveZone: 0
        aboveWindows: true

        anchors.top: true
        anchors.right: true
        margins.top: 44
        margins.right: 12

        WlrLayershell.namespace: "tom-notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        mask: Region {
            item: bannerColumn
        }

        Column {
            id: bannerColumn

            width: parent.width
            spacing: 8

            Repeater {
                model: root.bannerEntries

                Item {
                    id: bannerHost

                    required property var modelData
                    readonly property bool critical: root.isCritical(modelData.notification)
                    width: bannerColumn.width
                    height: bannerCard.implicitHeight

                    function scheduleDismissal(): void {
                        if (critical || modelData.pausedAt > 0)
                            return;
                        const remaining = Math.max(1, modelData.bannerDeadline - Date.now());
                        dismissTimer.interval = remaining;
                        dismissTimer.start();
                    }

                    function pauseDismissal(): void {
                        if (critical || modelData.pausedAt > 0)
                            return;
                        modelData.pausedAt = Date.now();
                        dismissTimer.stop();
                    }

                    function resumeDismissal(): void {
                        if (critical || modelData.pausedAt === 0)
                            return;
                        modelData.bannerDeadline += Date.now() - modelData.pausedAt;
                        modelData.pausedAt = 0;
                        scheduleDismissal();
                    }

                    Component.onCompleted: scheduleDismissal()

                    NotificationCard {
                        id: bannerCard

                        anchors.left: parent.left
                        anchors.right: parent.right
                        entry: bannerHost.modelData
                        banner: true
                        onCloseRequested: bannerHost.modelData.notification.dismiss()
                        onHoverStateChanged: hovered => {
                            if (hovered)
                                bannerHost.pauseDismissal();
                            else
                                bannerHost.resumeDismissal();
                        }
                    }

                    Timer {
                        id: dismissTimer

                        onTriggered: root.hideBanner(bannerHost.modelData.notification)
                    }
                }
            }
        }
    }

    PanelWindow {
        id: center

        property bool shown: false

        screen: root.targetScreen ?? Quickshell.screens[0]
        visible: root.targetScreen !== null && shown
        color: "transparent"
        exclusiveZone: 0
        aboveWindows: true

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        WlrLayershell.namespace: "tom-notification-center"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: shown
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.None

        onShownChanged: {
            if (!shown)
                return;
            root.markAllRead();
            root.hideAllBanners();
            Qt.callLater(() => centerFocus.forceActiveFocus());
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeCenter()
        }

        Rectangle {
            id: centerPanel

            z: 1
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 44
            anchors.rightMargin: 12
            width: 420
            height: Math.min(620, center.height - 56)
            radius: 8
            color: "@surface@"
            border.width: 1
            border.color: "@border@"

            MouseArea {
                anchors.fill: parent
            }
        }

        FocusScope {
            id: centerFocus

            z: 2
            anchors.fill: centerPanel
            focus: center.shown

            Keys.onEscapePressed: event => {
                root.closeCenter();
                event.accepted = true;
            }

            Item {
                id: header

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                height: 34

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                    color: "@text@"
                    font.family: "@fontFamily@"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    id: clearButton

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 66
                    height: 28
                    radius: 6
                    color: clearMouse.containsMouse && root.entries.length > 0
                        ? "@accentSurface@" : "transparent"
                    border.width: 1
                    border.color: root.entries.length > 0 ? "@border@" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "Clear all"
                        color: root.entries.length > 0 ? "@text@" : "@subdued@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: clearMouse

                        anchors.fill: parent
                        enabled: root.entries.length > 0
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.clearAll()
                    }
                }

                Rectangle {
                    id: dndButton

                    anchors.right: clearButton.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 82
                    height: 28
                    radius: 6
                    color: root.doNotDisturb || dndMouse.containsMouse
                        ? "@accentSurface@" : "transparent"
                    border.width: 1
                    border.color: root.doNotDisturb ? "@accent@" : "@border@"

                    Text {
                        anchors.centerIn: parent
                        text: root.doNotDisturb ? "󰂛  DND" : "󰂚  DND"
                        color: root.doNotDisturb ? "@accent@" : "@text@"
                        font.family: "@fontFamily@"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: dndMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleDoNotDisturb()
                    }
                }
            }

            Rectangle {
                anchors.top: header.bottom
                anchors.topMargin: 8
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: "@border@"
            }

            Flickable {
                id: historyView

                anchors.top: header.bottom
                anchors.topMargin: 18
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                clip: true
                contentWidth: width
                contentHeight: historyColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: historyColumn

                    width: historyView.width
                    spacing: 8

                    Repeater {
                        model: root.entries

                        NotificationCard {
                            required property var modelData
                            width: historyColumn.width
                            entry: modelData
                            onCloseRequested: modelData.notification.dismiss()
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: historyView
                visible: root.entries.length === 0
                text: root.doNotDisturb
                    ? "Do Not Disturb is on\nNo notifications yet"
                    : "No notifications yet"
                color: "@subdued@"
                horizontalAlignment: Text.AlignHCenter
                font.family: "@fontFamily@"
                font.pixelSize: 13
                lineHeight: 1.35
            }
        }
    }
}
