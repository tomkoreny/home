import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

ShellRoot {
    id: root

    readonly property var outputs: @outputs@
    readonly property string primaryOutput: @primaryOutput@
    readonly property string videoStatusOutput: @videoStatusOutput@
    readonly property int barHeight: 36
    readonly property bool videoMode: videoPolicy.active
        && Quickshell.screens.some(screen => screen.name === root.videoStatusOutput)
    readonly property string statusOutput: videoMode ? videoStatusOutput : primaryOutput

    onStatusOutputChanged: overlays.dismissAll()

    VideoBarPolicy {
        id: videoPolicy
        primaryOutput: root.primaryOutput
        statusOutput: root.videoStatusOutput
        barHeight: root.barHeight
    }
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
    property var aiUsageAccounts: []
    property bool aiUsageStale: false
    property real aiUsageUpdatedAt: 0
    property var timerAnchor: null

    Connections {
        target: Hyprland

        function onRawEvent(event): void {
            // Quickshell 0.3 updates membership, but not these IPC-only window states.
            // Group selection only emits a focus event, so refresh grouped focus changes.
            switch (event.name) {
            case "openwindow":
            case "closewindow":
            case "changefloatingmode":
            case "movewindowv2":
            case "togglegroup":
            case "moveintogroup":
            case "moveoutofgroup":
                Hyprland.refreshToplevels();
                break;
            case "activewindowv2":
                if ((Hyprland.activeToplevel?.lastIpcObject.grouped?.length ?? 0) > 1)
                    Hyprland.refreshToplevels();
                break;
            }
        }
    }

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

    readonly property var aiProviders: [
        { id: "openai-codex", label: "OpenAI Codex", windowIds: ["7d"] },
        { id: "anthropic", label: "Claude", windowIds: ["5h", "7d"] }
    ]

    function aiPlaceholderLimits(provider: var): var {
        return provider.windowIds.map(windowId => ({
            windowId: windowId,
            remaining: null,
            resetsAt: null
        }));
    }

    function updateAiUsage(payload: string): void {
        try {
            const snapshot = JSON.parse(payload);
            const accounts = [];
            (snapshot.reports ?? []).forEach((report, index) => {
                const provider = aiProviders.find(candidate => candidate.id === report.provider);
                if (!provider)
                    return;
                const limits = (report.limits ?? []).filter(
                    limit => limit.amount && typeof limit.amount.remaining === "number"
                );
                if (limits.length === 0)
                    return;

                const barLimits = provider.windowIds.map(windowId => {
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

                // One report per authenticated account; the same provider can
                // appear several times, so identify accounts, not providers.
                const metadata = report.metadata ?? {};
                const email = typeof metadata.email === "string" ? metadata.email : "";
                const accountId = typeof metadata.accountId === "string" ? metadata.accountId : "";
                accounts.push({
                    id: `${provider.id}:${accountId || email || index}`,
                    providerId: provider.id,
                    label: email ? `${provider.label} · ${email}` : provider.label,
                    email: email,
                    barLimits: barLimits,
                    limits: limits
                });
            });

            if (accounts.length === 0)
                throw new Error("No supported provider limits");

            const providerOrder = aiProviders.map(provider => provider.id);
            accounts.sort((a, b) =>
                providerOrder.indexOf(a.providerId) - providerOrder.indexOf(b.providerId)
                || a.email.localeCompare(b.email)
            );
            aiUsageAccounts = accounts;
            aiUsageUpdatedAt = snapshot.generatedAt ?? Date.now();
            aiUsageStale = false;
        } catch (error) {
            aiUsageStale = true;
            console.warn(`Unable to parse AI usage: ${error}`);
        }
    }

    // Bar entries: every known account, or one placeholder per provider until
    // the first snapshot arrives.
    function aiBarAccounts(): var {
        if (aiUsageAccounts.length > 0)
            return aiUsageAccounts;
        return aiProviders.map(provider => ({
            id: provider.id,
            providerId: provider.id,
            label: provider.label,
            email: "",
            barLimits: aiPlaceholderLimits(provider),
            limits: []
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

    function aiAccountColor(account: var): string {
        const numericLimits = account.barLimits.filter(
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
        if (aiUsageAccounts.length === 0)
            return aiUsageStale ? "AI limits · unavailable" : "AI limits · loading";

        const now = clock.date.getTime();
        const updated = relativeDuration(now - aiUsageUpdatedAt);
        const lines = [`AI limits · updated ${updated} ago${aiUsageStale ? " · stale" : ""}`];
        for (const account of aiUsageAccounts) {
            lines.push(account.label);
            for (const limit of account.limits) {
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
        overlayController: overlays
        targetOutput: root.statusOutput
    }
    OverlayController {
        id: overlays
    }
    TimerService {
        id: timers
    }

    Connections {
        target: overlays

        function onDismissRequested(except: string): void {
            if (except !== "")
                Quickshell.execDetached([
                    "@qs@", "-c", "tom-osd", "ipc", "call", "session", "close"
                ]);
        }
    }
    TodoService {
        id: todos
    }

    TodoPanel {
        service: todos
    }
    TodoManager {
        id: todoManager

        widgetService: todos
        overlayController: overlays
    }
    WorkTaskService {
        id: workTasks
        enabled: @workTasksEnabled@
    }
    WorkTaskManager {
        id: workManager
        service: workTasks
        overlayController: overlays
    }
    TimerPopup {
        id: timerPopup

        service: timers
        overlayController: overlays
        anchorItem: root.timerAnchor
    }



    Launcher {
        id: launcher
        timerService: timers
        overlayController: overlays
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
        target: "todos"

        function toggle(): bool {
            todoManager.toggle();
            return todoManager.visible;
        }

        function capture(): bool {
            todoManager.capture();
            return todoManager.visible;
        }
    }
    IpcHandler {
        target: "workTasks"

        function toggle(): bool {
            if (workTasks.enabled)
                workManager.toggle();
            return workManager.visible;
        }
    }



    IpcHandler {
        target: "notifications"

        function toggle(): bool {
            notifications.toggleCenter();
            return notifications.centerVisible;
        }

    }

    IpcHandler {
        target: "overlays"

        function close(): void {
            overlays.dismissAll();
        }
    }

    Variants {
        model: Quickshell.screens.filter(screen => root.outputs.includes(screen.name))

        DesktopBar {
            shellRoot: root
            clockService: clock
            launcherController: launcher
            notificationService: notifications
            overlayController: overlays
            timerPopupController: timerPopup
            timerService: timers
            todoManagerController: todoManager
            todoService: todos
            workManagerController: workManager
            workService: workTasks
        }
    }
}
