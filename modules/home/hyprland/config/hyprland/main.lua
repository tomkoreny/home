-- Tom's Hyprland config (seat0, NVIDIA).

-- Environment
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
-- The connected displays are on this NVIDIA DRM node. AQ_DRM_DEVICES uses
-- ':' as a separator, so the PCI by-path symlink cannot be used here.
hl.env("AQ_DRM_DEVICES", "/dev/dri/card2")
hl.env("HYPRCURSOR_THEME", "BreezeX-RosePine-Linux")
hl.env("HYPRCURSOR_SIZE", "32")
hl.env("XCURSOR_THEME", "BreezeX-RosePine-Linux")
hl.env("XCURSOR_SIZE", "32")

-- Autostart only on compositor startup, not on config reload.
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start --no-block waybar.service jellyfin-mpv-shim.service")
    hl.exec_cmd("uwsm app -- teams-for-linux --minimized")
    hl.exec_cmd("uwsm app -- discord --start-minimized")
    hl.exec_cmd("uwsm app -- element-desktop --hidden")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)

-- Monitors: portrait ViewSonics flank the landscape Alienware in an H.
-- Their rotations put each panel's lower lip on the outside edge. Scale 1.25
-- on the 27-inch side panels gives approximately the same physical UI size as
-- 1.666667 on the higher-density 32-inch 4K panel.
-- Keep unrecognized outputs usable as a safe fallback.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- Left portrait ViewSonic (lip facing left).
hl.monitor({
    output = "HDMI-A-2",
    mode = "highres",
    position = "0x0",
    scale = 1.25,
    transform = 1,
})

-- Centre QD-OLED, 4K240, HDR. Its logical 2304x1296 area is vertically
-- centred against the side panels' logical 1152x2048 areas.
hl.monitor({
    output = "desc:Dell Inc. AW3225QF 6D12YZ3",
    mode = "highres",
    position = "1152x376",
    scale = "1.666667",
    vrr = 3,
    bitdepth = 10,
    cm = "hdredid",
    sdrbrightness = 1.5,
    sdrsaturation = 0.98,
})

-- Right portrait ViewSonic (lip facing right).
hl.monitor({
    output = "DP-3",
    mode = "highres",
    position = "3456x0",
    scale = 1.25,
    transform = 3,
})

hl.config({
    xwayland = { force_zero_scaling = true },
    general = {
        gaps_in = 2,
        gaps_out = 10,
        border_size = 1,
        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding = 0,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        shadow = {
            enabled = true,
            range = 4,
            render_power = 3,
        },
        blur = {
            enabled = false,
            size = 3,
            passes = 1,
            vibrancy = 0.1696,
        },
    },
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    master = { new_status = "master" },
    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo = false,
        -- Keep the OLED off on mouse movement, but wake it on a key press.
        mouse_move_enables_dpms = false,
        key_press_enables_dpms = true,
    },
    render = {
        -- Treat sRGB and gamma2.2 as interchangeable where possible so the
        -- colour-management shader can be skipped for direct scanout.
        non_shader_cm = 2,
    },
    cursor = {
        -- Hardware cursor avoids NVIDIA/Wayland browser flicker while moving.
        no_hardware_cursors = 0,
    },
    input = {
        -- QMK handles Colemak-DH and Czech diacritics; the OS stays US.
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = { natural_scroll = false },
    },
})

-- Curves and animations
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 1.79, bezier = "default" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 1.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.14, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.14, bezier = "almostLinear", style = "fade" })

-- Smart gaps
for _, workspace in ipairs({ "w[t1]", "w[tg1]", "f[1]" }) do
    hl.workspace_rule({ workspace = workspace, gaps_out = 0, gaps_in = 0 })
    hl.window_rule({
        name = "smart-gaps-" .. workspace,
        match = { float = false, workspace = workspace },
        border_size = 0,
        rounding = 0,
    })
end

-- Per-device layouts for regular keyboards.
hl.device({ name = "usb-usb-keyboard", kb_layout = "us,cz" })
hl.device({ name = "razer-razer-blackwidow-ultimate-keyboard", kb_layout = "us,cz" })

-- Programs and keybindings
local mainMod = "SUPER"
local terminal = "uwsm app -- ghostty"
local fileManager = "uwsm app -- nautilus"
local menu = "uwsm app -- $(wofi --show drun --define=drun-print_desktop_file=true)"

hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exit())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("uwsm app -- helium-browser"))
hl.bind(mainMod .. " + U", hl.dsp.exec_cmd("uwsm app -- unifi-cam"))
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("cliphist list | wofi --dmenu | cliphist decode | wl-copy"))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("diacritics-fix"))

hl.bind("Print", hl.dsp.exec_cmd("hyprshot -m region"))
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd("hyprshot -m output"))
hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd("hyprshot -m window"))
hl.bind(mainMod .. " + V", hl.dsp.window.float())
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

local repeatLocked = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), repeatLocked)
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), repeatLocked)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), repeatLocked)
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), repeatLocked)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s 10%+"), repeatLocked)
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 10%-"), repeatLocked)

local locked = { locked = true }
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), locked)
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), locked)
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), locked)
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), locked)

hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen_state({ internal = 3, client = 1 }))
-- Delay until the lock shortcut's key event has finished, otherwise that same
-- key press can immediately wake DPMS again.
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("sleep 1 && hypr-dpms off"))

-- Window rules
-- The 1px accent focus border reads as a stray blue line across the top of
-- the browser when it tiles flush under waybar; drop it for Helium only and
-- keep the border as the focus cue for everything else.
hl.window_rule({
    name = "no-border-helium",
    match = { class = "helium" },
    border_size = 0,
})

hl.window_rule({
    name = "camera-grid",
    match = { title = ".*CameraGrid .*" },
    float = true,
    border_size = 0,
})

hl.window_rule({
    name = "suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})

for _, class in ipairs({ "(?i)^(discord)$", "(?i)^(teams-for-linux)$", "(?i)^(element)$" }) do
    hl.window_rule({
        name = "chat-workspace-" .. class,
        match = { class = class },
        workspace = "3 silent",
    })
end

-- Stable workspace-to-monitor columns. Workspaces advance left-to-right in
-- rows: 1/2/3, 4/5/6, 7/8/9. Keep 1-9 alive so every assigned workspace is
-- always visible and clickable in the Waybar on its own monitor.
local left = "HDMI-A-2"
local primary = "desc:Dell Inc. AW3225QF 6D12YZ3"
local right = "DP-3"
for _, id in ipairs({ 1, 4, 7 }) do
    hl.workspace_rule({
        workspace = tostring(id),
        monitor = left,
        default = id == 1,
        persistent = true,
    })
end
for _, id in ipairs({ 2, 5, 8 }) do
    hl.workspace_rule({
        workspace = tostring(id),
        monitor = primary,
        default = id == 2,
        persistent = true,
    })
end
for _, id in ipairs({ 3, 6, 9 }) do
    hl.workspace_rule({
        workspace = tostring(id),
        monitor = right,
        default = id == 3,
        persistent = true,
    })
end
