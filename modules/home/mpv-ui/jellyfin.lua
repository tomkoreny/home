local mp = require("mp")
local utils = require("mp.utils")

-- The library browser and legacy Jellyfin settings menu own this same window.
-- Neither should acquire uosc's mouse regions or controls over their content.
local menu_open = false
local elements = "timeline,controls,volume,top_bar,window_border,idle_indicator,audio_indicator,pause_indicator,buffering_indicator"

local function update()
    local hidden = menu_open or mp.get_property_native("idle-active", true)
    mp.commandv("script-message-to", "uosc", "disable-elements", "jellyfin", hidden and elements or "")
    if hidden then
        mp.commandv("script-message-to", "uosc", "close-menu")
    end
end

local function menu()
    if menu_open or mp.get_property_native("idle-active", true) then
        return
    end
    -- Do not expose uosc's directory/playlist actions for Shim's server queue.
    mp.commandv("script-message-to", "uosc", "open-menu", utils.format_json({
        type = "jellyfin-playback",
        title = "Playback",
        items = {
            { title = "Subtitles", value = "script-binding uosc/subtitles" },
            { title = "Audio tracks", value = "script-binding uosc/audio" },
            { title = "Chapters", value = "script-binding uosc/chapters" },
            { title = "Previous item", value = "keypress PREV" },
            { title = "Next item", value = "keypress NEXT" },
            { title = "Jellyfin settings", value = "keypress c" },
            { title = "Screenshot", value = "screenshot" },
        },
    }))
end

local function initialize()
    mp.commandv("script-message-to", "uosc", "overwrite-binding", "next", "keypress NEXT")
    mp.commandv("script-message-to", "uosc", "overwrite-binding", "prev", "keypress PREV")
    update()
end

mp.register_script_message("tom-jellyfin-menu", menu)
mp.add_key_binding("MBTN_RIGHT", "menu", menu)

mp.observe_property("idle-active", "bool", update)
mp.register_script_message("shim-menu-enable", function(value)
    menu_open = value == "True"
    update()
end)
mp.register_script_message("uosc-version", function()
    mp.add_timeout(0, initialize)
end)
mp.add_timeout(0, initialize)
