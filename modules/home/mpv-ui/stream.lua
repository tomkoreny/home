local mp = require("mp")

-- Live demuxers can report a growing duration without supporting seeks.
local function update()
    local seekable = mp.get_property_native("seekable", false)
    mp.commandv("script-message-to", "uosc", "disable-elements", "non-seekable", seekable and "" or "timeline")
end

mp.observe_property("seekable", "bool", update)
mp.register_script_message("uosc-version", function()
    mp.add_timeout(0, update)
end)
mp.add_timeout(0, update)
