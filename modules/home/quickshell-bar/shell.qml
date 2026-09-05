import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

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
        overlayController: overlays
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
        }
    }
}
