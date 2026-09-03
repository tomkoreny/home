import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Controls as QQC2

ShellRoot {
    id: root

    readonly property var outputs: @outputs@
    readonly property var audioNode: Pipewire.defaultAudioSink
    readonly property var audio: audioNode ? audioNode.audio : null
    readonly property bool audioMuted: audio ? audio.muted : false
    readonly property int volumePercent: audio ? Math.round(audio.volume * 100) : 0
    property bool showSeconds: false
    property int herdrWorking: 0
    property int herdrBlocked: 0
    property int herdrIdle: 0
    property string herdrSummary: "Herdr · unavailable"
    property string foregroundAppId: ""
    property var aiUsageProviders: []
    property bool aiUsageStale: false
    property real aiUsageUpdatedAt: 0
    property var timerAnchor: null

    function refreshHerdr(): void {
        if (activeWindowSnapshot.running || herdrSnapshot.running)
            return;
        if (notifications.hasOmpCompletion) {
            activeWindowSnapshot.running = true;
        } else {
            foregroundAppId = "";
            herdrSnapshot.running = true;
        }
    }

    function updateForeground(payload: string): void {
        try {
            foregroundAppId = JSON.parse(payload).class ?? "";
        } catch (error) {
            foregroundAppId = "";
        }
        herdrSnapshot.running = true;
    }

    function updateHerdr(payload: string): void {
        try {
            const snapshot = JSON.parse(payload).result.snapshot;
            const agents = snapshot.agents ?? [];
            notifications.reconcileHerdr(
                snapshot,
                foregroundAppId === "com.mitchellh.ghostty"
            );
            herdrWorking = agents.filter(agent => agent.agent_status === "working").length;
            herdrBlocked = agents.filter(agent => agent.agent_status === "blocked").length;
            herdrIdle = agents.filter(agent => agent.agent_status === "idle"
                || agent.agent_status === "done").length;
            const parts = [];
            if (herdrWorking > 0)
                parts.push(`${herdrWorking} working`);
            if (herdrBlocked > 0)
                parts.push(`${herdrBlocked} blocked`);
            if (herdrIdle > 0)
                parts.push(`${herdrIdle} idle`);
            herdrSummary = parts.length > 0
                ? `Herdr · ${parts.join(" · ")}`
                : "Herdr · no agents";
        } catch (error) {
            herdrWorking = 0;
            herdrBlocked = 0;
            herdrIdle = 0;
            herdrSummary = "Herdr · unavailable";
        }
    }

    function refreshAiUsage(force: bool): void {
        if (aiUsageSnapshot.running || aiUsageInvalidator.running)
            return;
        if (force)
            aiUsageInvalidator.running = true;
        else
            aiUsageSnapshot.running = true;
    }

    function updateAiUsage(payload: string): void {
        try {
            const snapshot = JSON.parse(payload);
            const supportedProviders = ["openai-codex", "anthropic"];
            const reports = (snapshot.reports ?? []).filter(
                report => supportedProviders.includes(report.provider)
            );
            const providers = reports.map(report => {
                const limits = (report.limits ?? []).filter(
                    limit => limit.amount && typeof limit.amount.remaining === "number"
                );
                if (limits.length === 0)
                    return null;

                const windowIds = report.provider === "openai-codex"
                    ? ["7d"]
                    : ["5h", "7d"];
                const barLimits = windowIds.map(windowId => {
                    const limit = limits.find(candidate =>
                        candidate.scope
                        && candidate.scope.windowId === windowId
                        && !candidate.scope.tier
                        && !candidate.scope.modelId
                    ) ?? null;
                    return {
                        windowId: windowId,
                        remaining: limit === null ? null : limit.amount.remaining,
                        resetsAt: limit === null || !limit.window
                            ? null
                            : limit.window.resetsAt ?? null
                    };
                });

                return {
                    id: report.provider,
                    label: report.provider === "openai-codex" ? "OpenAI Codex" : "Claude",
                    barLimits: barLimits,
                    limits: limits
                };
            }).filter(provider => provider !== null);

            if (providers.length === 0)
                throw new Error("No supported provider limits");

            aiUsageProviders = providers;
            aiUsageUpdatedAt = snapshot.generatedAt ?? Date.now();
            aiUsageStale = false;
        } catch (error) {
            aiUsageStale = true;
            console.warn(`Unable to parse AI usage: ${error}`);
        }
    }

    function aiProvider(providerId: string): var {
        return aiUsageProviders.find(provider => provider.id === providerId) ?? null;
    }

    function aiBarLimits(providerId: string): var {
        const provider = aiProvider(providerId);
        if (provider !== null)
            return provider.barLimits;
        const windowIds = providerId === "openai-codex" ? ["7d"] : ["5h", "7d"];
        return windowIds.map(windowId => ({
            windowId: windowId,
            remaining: null,
            resetsAt: null
        }));
    }

    function aiRemainingText(limit: var): string {
        return typeof limit.remaining === "number"
            ? `${Math.round(limit.remaining)}%`
            : "--";
    }

    function aiRemainingColor(remaining: var): string {
        if (typeof remaining !== "number")
            return "@subdued@";
        if (remaining <= 10)
            return "@muted@";
        if (remaining <= 25)
            return "@accent@";
        return "@text@";
    }

    function aiProviderColor(providerId: string): string {
        const numericLimits = aiBarLimits(providerId).filter(
            limit => typeof limit.remaining === "number"
        );
        if (numericLimits.length === 0)
            return "@subdued@";
        let remaining = numericLimits[0].remaining;
        for (const limit of numericLimits)
            remaining = Math.min(remaining, limit.remaining);
        return aiRemainingColor(remaining);
    }

    function relativeDuration(milliseconds: real): string {
        const totalMinutes = Math.max(0, Math.floor(milliseconds / 60000));
        const days = Math.floor(totalMinutes / 1440);
        const hours = Math.floor((totalMinutes % 1440) / 60);
        const minutes = totalMinutes % 60;
        if (days > 0)
            return hours > 0 ? `${days}d ${hours}h` : `${days}d`;
        if (hours > 0)
            return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
        return `${minutes}m`;
    }

    function aiWindowIcon(windowId: string): string {
        return windowId === "5h" ? "󰔛" : "󰃭";
    }

    function aiResetText(limit: var): string {
        if (typeof limit.resetsAt !== "number")
            return "--";
        const remaining = relativeDuration(limit.resetsAt - clock.date.getTime());
        return remaining.replace(/\s/g, "");
    }

    function aiUsageTooltip(): string {
        if (aiUsageProviders.length === 0)
            return aiUsageStale ? "AI limits · unavailable" : "AI limits · loading";

        const now = clock.date.getTime();
        const updated = relativeDuration(now - aiUsageUpdatedAt);
        const lines = [`AI limits · updated ${updated} ago${aiUsageStale ? " · stale" : ""}`];
        for (const provider of aiUsageProviders) {
            lines.push(provider.label);
            for (const limit of provider.limits) {
                const remaining = `${Math.round(limit.amount.remaining)}%`;
                if (!limit.window || typeof limit.window.resetsAt !== "number") {
                    lines.push(`  ${limit.label} · ${remaining} · reset unavailable`);
                    continue;
                }
                const reset = new Date(limit.window.resetsAt);
                const relative = relativeDuration(limit.window.resetsAt - now);
                const exact = Qt.formatDateTime(reset, "ddd d MMM HH:mm");
                lines.push(`  ${limit.label} · ${remaining} · resets in ${relative} (${exact})`);
            }
        }
        return lines.join("\n");
    }

    Process {
        id: activeWindowSnapshot
        command: ["@hyprctl@", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.updateForeground(this.text)
        }
    }

    Process {
        id: herdrSnapshot
        command: ["@herdr@", "api", "snapshot"]
        stdout: StdioCollector {
            onStreamFinished: root.updateHerdr(this.text)
        }
    }

    Process {
        id: aiUsageSnapshot
        command: ["@omp@", "usage", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.updateAiUsage(this.text)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.aiUsageStale = true;
        }
    }

    Process {
        id: aiUsageInvalidator
        command: ["@omp@", "usage", "invalidate"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.aiUsageStale = true;
            aiUsageSnapshot.running = true;
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshHerdr()
    }

    Timer {
        interval: 300000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshAiUsage(false)
    }

    function audioIcon(): string {
        if (audioMuted)
            return "󰖁";
        if (volumePercent < 34)
            return "󰕿";
        if (volumePercent < 67)
            return "󰖀";
        return "󰕾";
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    SystemClock {
        id: clock
        precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Notifications {
        id: notifications
    }
    TimerService {
        id: timers
    }

    TodoService {
        id: todos
    }

    TodoPanel {
        service: todos
    }
    TimerPopup {
        id: timerPopup

        service: timers
        anchorItem: root.timerAnchor
    }



    Launcher {
        id: launcher
        timerService: timers
    }

    IpcHandler {
        target: "launcher"

        function toggle(): bool {
            launcher.toggle();
            return launcher.visible;
        }

        function ai(): bool {
            launcher.toggleMode("ai");
            return launcher.visible;
        }

        function clipboard(): bool {
            launcher.toggleMode("clipboard");
            return launcher.visible;
        }

        function herdr(): bool {
            launcher.toggleMode("herdr");
            return launcher.visible;
        }

        function cameras(): bool {
            launcher.toggleMode("cameras");
            return launcher.visible;
        }
    }
    IpcHandler {
        target: "timers"

        function popup(): bool {
            timerPopup.toggle();
            return timerPopup.shown;
        }
    }


    IpcHandler {
        target: "notifications"

        function toggle(): bool {
            notifications.toggleCenter();
            return notifications.centerVisible;
        }

    }

    Variants {
        model: Quickshell.screens.filter(screen => root.outputs.includes(screen.name))

        PanelWindow {
            id: bar

            required property var modelData
            readonly property var displayMonitor: Hyprland.monitors.values.find(
                monitor => monitor.name === modelData.name
            ) ?? null
            readonly property var displayWorkspace: displayMonitor
                ? displayMonitor.activeWorkspace : null
            readonly property bool singleWindowMode: displayWorkspace !== null
                && displayWorkspace.toplevels.values.length === 1
            readonly property bool primary: modelData.name === "@primaryOutput@"

            screen: modelData
            color: singleWindowMode ? "#000000" : "transparent"
            implicitHeight: 36
            exclusiveZone: 36
            aboveWindows: true

            anchors.top: true
            anchors.left: true
            anchors.right: true

            WlrLayershell.namespace: `tom-bar-${modelData.name}`
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            mask: Region {
                Region {
                    item: workspaceIsland
                    radius: workspaceIsland.radius
                }
                Region {
                    item: statusIsland.visible ? statusIsland : null
                    radius: statusIsland.radius
                }
            }

            Rectangle {
                id: workspaceIsland

                x: 6
                y: 3
                width: workspaceRow.implicitWidth + 10
                height: 30
                radius: bar.singleWindowMode ? 0 : 8
                color: bar.singleWindowMode ? "transparent" : "@surface@"
                border.width: bar.singleWindowMode ? 0 : 1
                border.color: "@border@"

                Row {
                    id: workspaceRow

                    anchors.centerIn: parent
                    spacing: 2

                    Repeater {
                        model: Hyprland.workspaces

                        Rectangle {
                            id: workspaceButton

                            required property var modelData
                            readonly property bool onThisMonitor: modelData.id > 0
                                && modelData.monitor !== null
                                && modelData.monitor.name === bar.modelData.name

                            visible: onThisMonitor
                            width: visible ? 26 : 0
                            height: 26
                            radius: 13
                            color: modelData.active ? "@accentSurface@" : "transparent"
                            border.width: modelData.active ? 1 : 0
                            border.color: "@accent@"

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: workspaceButton.modelData.id
                                color: workspaceButton.modelData.active ? "@accent@" : "@subdued@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 12
                                font.weight: workspaceButton.modelData.active ? Font.DemiBold : Font.Normal
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: workspaceButton.onThisMonitor
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: workspaceButton.modelData.activate()

                                QQC2.ToolTip.visible: containsMouse
                                QQC2.ToolTip.delay: 500
                                QQC2.ToolTip.text: `Workspace ${workspaceButton.modelData.id}`
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: statusIsland

                x: parent.width - width - 6
                y: 3
                width: statusRow.implicitWidth + 12
                height: 30
                radius: bar.singleWindowMode ? 0 : 8
                visible: bar.primary
                color: bar.singleWindowMode ? "transparent" : "@surface@"
                border.width: bar.singleWindowMode ? 0 : 1
                border.color: "@border@"

                Row {
                    id: statusRow

                    anchors.centerIn: parent
                    height: 26
                    spacing: 3

                    Item {
                        width: herdrText.implicitWidth + 12
                        height: parent.height

                        Text {
                            id: herdrText

                            anchors.centerIn: parent
                            text: root.herdrBlocked > 0
                                ? `π ${root.herdrWorking}  󰅖 ${root.herdrBlocked}`
                                : `π ${root.herdrWorking}`
                            color: root.herdrBlocked > 0
                                ? "@muted@"
                                : root.herdrWorking > 0 ? "@accent@" : "@subdued@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: launcher.toggleMode("herdr")

                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.delay: 500
                            QQC2.ToolTip.text: root.herdrSummary
                        }
                    }
                    Rectangle {
                        width: 1
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: "@border@"
                    }

                    Item {
                        id: timerHost

                        width: timerText.implicitWidth + 12
                        height: parent.height
                        Component.onCompleted: {
                            if (bar.primary)
                                root.timerAnchor = timerHost;
                        }


                        Text {
                            id: timerText

                            anchors.centerIn: parent
                            text: timers.nextTimer
                                ? `󰔛 ${timers.formatRemaining(timers.remaining(timers.nextTimer))}${timers.activeCount > 1 ? ` +${timers.activeCount - 1}` : ""}`
                                : "󰔛"
                            color: timers.nextTimer ? "@accent@" : "@subdued@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: timerPopup.toggle()

                            QQC2.ToolTip.visible: containsMouse && !timerPopup.shown
                            QQC2.ToolTip.delay: 500
                            QQC2.ToolTip.text: timers.nextTimer
                                ? `${timers.nextTimer.name} · ${timers.formatRemaining(timers.remaining(timers.nextTimer))}`
                                : "Create a timer"
                        }

                    }


                    Rectangle {
                        width: 1
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: "@border@"
                    }

                    Item {
                        id: aiLimitsHost

                        property bool tooltipVisible: false

                        width: aiLimitsRow.implicitWidth + 12
                        height: parent.height

                        Row {
                            id: aiLimitsRow

                            anchors.centerIn: parent
                            spacing: 8

                            Repeater {
                                model: [
                                    {
                                        providerId: "openai-codex",
                                        logo: "@openaiLogo@"
                                    },
                                    {
                                        providerId: "anthropic",
                                        logo: "@anthropicLogo@"
                                    }
                                ]

                                Row {
                                    id: providerLimit

                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter

                                    spacing: 4

                                    Item {
                                        width: 14
                                        height: 14
                                        anchors.verticalCenter: parent.verticalCenter

                                        Image {
                                            id: providerLogoSource

                                            anchors.fill: parent
                                            source: providerLimit.modelData.logo
                                            sourceSize.width: 14
                                            sourceSize.height: 14
                                            fillMode: Image.PreserveAspectFit
                                            visible: false
                                        }

                                        MultiEffect {
                                            anchors.fill: providerLogoSource
                                            source: providerLogoSource
                                            colorization: 1
                                            colorizationColor: root.aiProviderColor(
                                                providerLimit.modelData.providerId
                                            )
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: -1

                                        Repeater {
                                            model: root.aiBarLimits(providerLimit.modelData.providerId)

                                            Text {
                                                required property var modelData

                                                text: `${root.aiWindowIcon(modelData.windowId)} ${root.aiRemainingText(modelData)} ${root.aiResetText(modelData)}`
                                                color: root.aiRemainingColor(modelData.remaining)
                                                font.family: "@fontFamily@"
                                                font.pixelSize: 9
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.aiUsageStale
                                text: "󰅖"
                                color: "@muted@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            id: aiLimitsMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refreshAiUsage(true)
                            onContainsMouseChanged: {
                                if (containsMouse) {
                                    aiTooltipDelay.restart();
                                } else {
                                    aiTooltipDelay.stop();
                                    aiLimitsHost.tooltipVisible = false;
                                }
                            }
                        }

                        Timer {
                            id: aiTooltipDelay

                            interval: 500
                            onTriggered: {
                                if (aiLimitsMouse.containsMouse)
                                    aiLimitsHost.tooltipVisible = true;
                            }
                        }

                        PopupWindow {
                            anchor.item: aiLimitsHost
                            anchor.rect.x: aiLimitsHost.width - implicitWidth
                            anchor.rect.y: aiLimitsHost.height + 6
                            anchor.rect.width: 1
                            anchor.rect.height: 1
                            implicitWidth: aiTooltipText.implicitWidth + 20
                            implicitHeight: aiTooltipText.implicitHeight + 16
                            color: "@opaqueSurface@"
                            visible: aiLimitsHost.tooltipVisible

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: "transparent"
                                border.width: 1
                                border.color: "@border@"
                            }

                            Text {
                                id: aiTooltipText

                                anchors.centerIn: parent
                                text: root.aiUsageTooltip()
                                color: "@text@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 12
                                lineHeight: 1.25
                            }
                        }
                    }
                    Rectangle {
                        width: 1
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: "@border@"
                    }

                    Item {
                        width: todoText.implicitWidth + 12
                        height: parent.height

                        Text {
                            id: todoText

                            anchors.centerIn: parent
                            text: todos.overdueCount > 0
                                ? `󰄬 ${todos.todayCount}  󰅖 ${todos.overdueCount}`
                                : `󰄬 ${todos.todayCount}`
                            color: todos.overdueCount > 0
                                ? "@muted@"
                                : todos.todayCount > 0 ? "@accent@" : "@subdued@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: todos.refresh()

                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.delay: 500
                            QQC2.ToolTip.text: todos.stale
                                ? `Notion tasks · stale · ${todos.error}`
                                : `${todos.overdueCount} overdue · ${todos.todayCount} today`
                        }
                    }


                    Rectangle {
                        width: 1
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: "@border@"
                    }

                    Item {
                        width: audioText.implicitWidth + 12
                        height: parent.height

                        Text {
                            id: audioText

                            anchors.centerIn: parent
                            text: `${root.audioIcon()}  ${root.volumePercent}%`
                            color: root.audioMuted ? "@muted@" : "@text@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["@pavucontrol@"]) 

                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.delay: 500
                            QQC2.ToolTip.text: root.audioMuted
                                ? `Muted · ${root.volumePercent}%`
                                : `Volume · ${root.volumePercent}%`
                        }
                    }

                    Rectangle {
                        width: 1
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        visible: trayRow.visible
                        color: "@border@"
                    }

                    Row {
                        id: trayRow

                        height: parent.height
                        spacing: 2
                        visible: SystemTray.items.values.length > 0

                        Repeater {
                            model: SystemTray.items

                            Item {
                                id: trayHost

                                required property var modelData
                                width: 24
                                height: parent.height

                                function showMenu(): void {
                                    trayMenu.reset();
                                    trayMenu.visible = true;
                                }

                                Image {
                                    anchors.centerIn: parent
                                    width: 17
                                    height: 17
                                    source: trayHost.modelData.icon
                                    sourceSize.width: 17
                                    sourceSize.height: 17
                                    fillMode: Image.PreserveAspectFit
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.MiddleButton) {
                                            trayHost.modelData.secondaryActivate();
                                        } else if (mouse.button === Qt.RightButton
                                                   || trayHost.modelData.onlyMenu) {
                                            if (trayHost.modelData.hasMenu)
                                                trayHost.showMenu();
                                        } else {
                                            trayHost.modelData.activate();
                                        }
                                    }

                                    QQC2.ToolTip.visible: containsMouse && !trayMenu.visible
                                    QQC2.ToolTip.delay: 500
                                    QQC2.ToolTip.text: trayHost.modelData.tooltipTitle
                                }

                                PopupWindow {
                                    id: trayMenu

                                    property var currentMenu: trayHost.modelData.menu
                                    property var menuStack: []

                                    function reset(): void {
                                        currentMenu = trayHost.modelData.menu;
                                        menuStack = [];
                                    }

                                    function push(menuEntry): void {
                                        const stack = menuStack.slice();
                                        stack.push(currentMenu);
                                        menuStack = stack;
                                        currentMenu = menuEntry;
                                    }

                                    function pop(): void {
                                        if (menuStack.length === 0)
                                            return;

                                        const stack = menuStack.slice();
                                        currentMenu = stack.pop();
                                        menuStack = stack;
                                    }

                                    anchor.item: trayHost
                                    anchor.rect.x: trayHost.width - implicitWidth
                                    anchor.rect.y: trayHost.height + 6
                                    anchor.rect.width: 1
                                    anchor.rect.height: 1
                                    implicitWidth: 200
                                    implicitHeight: menuColumn.implicitHeight + 8
                                    color: "transparent"
                                    grabFocus: true
                                    visible: false

                                    onVisibleChanged: {
                                        if (!visible)
                                            reset();
                                    }

                                    QsMenuOpener {
                                        id: menuOpener
                                        menu: trayMenu.currentMenu
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 10
                                        color: "@surface@"
                                        border.width: 1
                                        border.color: "@border@"
                                    }

                                    FocusScope {
                                        anchors.fill: parent
                                        focus: trayMenu.visible

                                        Keys.onEscapePressed: event => {
                                            trayMenu.visible = false;
                                            event.accepted = true;
                                        }

                                        Column {
                                            id: menuColumn

                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.topMargin: 4
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 4
                                            spacing: 2

                                            Item {
                                                width: menuColumn.width
                                                height: 29
                                                visible: trayMenu.menuStack.length > 0

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 6
                                                    color: backMouse.containsMouse ? "@accentSurface@" : "transparent"
                                                }

                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 6
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 12
                                                    text: `‹  ${trayMenu.currentMenu.text}`
                                                    color: "@accent@"
                                                    elide: Text.ElideRight
                                                    font.family: "@fontFamily@"
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                }

                                                MouseArea {
                                                    id: backMouse

                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: trayMenu.pop()
                                                }
                                            }

                                            Rectangle {
                                                width: menuColumn.width - 8
                                                height: 1
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                visible: trayMenu.menuStack.length > 0
                                                color: "@border@"
                                            }

                                            Repeater {
                                                model: menuOpener.children

                                                Item {
                                                    id: menuEntry

                                                    required property var modelData
                                                    width: menuColumn.width
                                                    height: modelData.isSeparator ? 7 : 29

                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        anchors.leftMargin: 6
                                                        anchors.rightMargin: 6
                                                        height: 1
                                                        visible: menuEntry.modelData.isSeparator
                                                        color: "@border@"
                                                    }

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: 6
                                                        visible: !menuEntry.modelData.isSeparator
                                                        color: entryMouse.containsMouse
                                                            ? "@accentSurface@" : "transparent"
                                                        opacity: menuEntry.modelData.enabled ? 1 : 0.55

                                                        Row {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 6
                                                            anchors.rightMargin: 6
                                                            spacing: 6

                                                            Item {
                                                                id: leadingIndicator

                                                                width: 16
                                                                height: parent.height
                                                                visible: menuEntry.modelData.icon !== ""
                                                                    || menuEntry.modelData.buttonType !== QsMenuButtonType.None

                                                                Image {
                                                                    anchors.centerIn: parent
                                                                    width: 16
                                                                    height: 16
                                                                    visible: menuEntry.modelData.icon !== ""
                                                                    source: menuEntry.modelData.icon
                                                                    sourceSize.width: 16
                                                                    sourceSize.height: 16
                                                                    fillMode: Image.PreserveAspectFit
                                                                }

                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    visible: menuEntry.modelData.icon === ""
                                                                        && menuEntry.modelData.buttonType !== QsMenuButtonType.None
                                                                    text: menuEntry.modelData.checkState === Qt.Checked
                                                                        ? (menuEntry.modelData.buttonType === QsMenuButtonType.RadioButton
                                                                            ? "●" : "✓")
                                                                        : menuEntry.modelData.checkState === Qt.PartiallyChecked ? "−" : ""
                                                                    color: "@accent@"
                                                                    font.family: "@fontFamily@"
                                                                    font.pixelSize: 12
                                                                    font.weight: Font.Bold
                                                                }
                                                            }

                                                            Text {
                                                                width: parent.width
                                                                    - (leadingIndicator.visible ? leadingIndicator.width + parent.spacing : 0)
                                                                    - (submenuArrow.visible ? submenuArrow.width + parent.spacing : 0)
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: menuEntry.modelData.text
                                                                color: menuEntry.modelData.enabled ? "@text@" : "@subdued@"
                                                                elide: Text.ElideRight
                                                                font.family: "@fontFamily@"
                                                                font.pixelSize: 12
                                                            }

                                                            Text {
                                                                id: submenuArrow

                                                                width: 10
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                visible: menuEntry.modelData.hasChildren
                                                                text: "›"
                                                                color: "@subdued@"
                                                                horizontalAlignment: Text.AlignRight
                                                                font.family: "@fontFamily@"
                                                                font.pixelSize: 15
                                                            }
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: entryMouse

                                                        anchors.fill: parent
                                                        enabled: !menuEntry.modelData.isSeparator
                                                            && menuEntry.modelData.enabled
                                                        hoverEnabled: true
                                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                        onClicked: {
                                                            if (menuEntry.modelData.hasChildren) {
                                                                trayMenu.push(menuEntry.modelData);
                                                            } else {
                                                                menuEntry.modelData.triggered();
                                                                trayMenu.visible = false;
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: 1
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: "@border@"
                    }

                    Item {
                        width: clockRows.implicitWidth + 12
                        height: parent.height

                        Column {
                            id: clockRows

                            anchors.centerIn: parent
                            spacing: -1

                            Text {
                                text: `󰥔 ${Qt.formatDateTime(
                                    clock.date,
                                    root.showSeconds ? "HH:mm:ss" : "HH:mm"
                                )}`
                                color: "@text@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: `󰃭 ${Qt.formatDateTime(clock.date, "ddd d MMM")}`
                                color: "@text@"
                                font.family: "@fontFamily@"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showSeconds = !root.showSeconds

                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.delay: 500
                            QQC2.ToolTip.text: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
                        }
                    }

                    Rectangle {
                        width: 1
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: "@border@"
                    }

                    Item {
                        id: notificationBell

                        width: 34
                        height: parent.height

                        Text {
                            anchors.centerIn: parent
                            text: notifications.doNotDisturb ? "󰂛" : "󰂚"
                            color: notifications.doNotDisturb
                                ? "@muted@"
                                : notifications.unreadCount > 0 ? "@accent@" : "@text@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 15
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: 1
                            anchors.rightMargin: 1
                            visible: notifications.unreadCount > 0
                            width: Math.max(14, unreadLabel.implicitWidth + 6)
                            height: 14
                            radius: 7
                            color: "@accent@"

                            Text {
                                id: unreadLabel

                                anchors.centerIn: parent
                                text: notifications.unreadCount
                                color: "#11111b"
                                font.family: "@fontFamily@"
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notifications.toggleCenter()

                            QQC2.ToolTip.visible: containsMouse
                                && !notifications.centerVisible
                            QQC2.ToolTip.delay: 500
                            QQC2.ToolTip.text: notifications.doNotDisturb
                                ? `Do Not Disturb · ${notifications.unreadCount} unread`
                                : `${notifications.unreadCount} unread notifications`
                        }
                    }

                    Rectangle {
                        width: 1
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: "@border@"
                    }

                    Item {
                        width: 28
                        height: parent.height

                        Text {
                            anchors.centerIn: parent
                            text: "󰐥"
                            color: "@muted@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 14
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached([
                                "@qs@", "-c", "tom-osd", "ipc", "call", "session", "reveal"
                            ])

                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.delay: 500
                            QQC2.ToolTip.text: "Session"
                        }
                    }
                }
            }
        }
    }
}
