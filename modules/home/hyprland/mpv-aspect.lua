local mp = require("mp")
local utils = require("mp.utils")

local runtime = os.getenv("XDG_RUNTIME_DIR")
if not runtime or runtime:sub(1, 1) ~= "/" then
    mp.msg.warn("Aspect metadata requires an absolute XDG_RUNTIME_DIR")
    return
end

local pid = utils.getpid()
local directory = utils.join_path(runtime, "hyprland-aspect")
local path = utils.join_path(directory, string.format("mpv-%d.json", pid))
local temporary = path .. "." .. mp.get_script_name() .. ".tmp"
local directory_ready = false
local last_aspect
local ended = false
local shutting_down = false

local function remove_metadata()
    os.remove(temporary)
    os.remove(path)
    last_aspect = nil
end

local function positive_finite(value)
    return type(value) == "number" and value > 0 and value < math.huge
end

local function display_aspect()
    local title = mp.get_property("options/title", "")
    if
        title:sub(1, 8) ~= "Camera: "
        or ended
        or shutting_down
        or mp.get_property_bool("idle-active", false)
        or mp.get_property_bool("eof-reached", false)
        or mp.get_property("vid") == "no"
    then
        return nil
    end

    local params = mp.get_property_native("video-out-params")
    if type(params) ~= "table" or not positive_finite(params.aspect) then
        return nil
    end

    -- Post-filter aspect includes pixel aspect correction, aspect overrides,
    -- and cropping; it is not the size of the tiled window. mpv exposes the
    -- remaining display rotation separately (a filter may already apply it).
    -- Match mpv's display-size calculation: swap axes for quarter turns only.
    local rotation = params.rotate
    if type(rotation) ~= "number" or rotation ~= rotation or math.abs(rotation) == math.huge then
        return nil
    end
    local aspect = params.aspect
    if rotation % 180 == 90 then
        aspect = 1 / aspect
    end
    if positive_finite(aspect) then
        return aspect
    end
end

local function publish(aspect)
    if not directory_ready then
        local result = mp.command_native({
            name = "subprocess",
            args = { "@mkdir@", "-p", "-m", "700", "--", directory },
            playback_only = false,
            capture_stdout = true,
            capture_stderr = true,
        })
        if not result or result.status ~= 0 then
            return false
        end
        directory_ready = true
    end

    local json = utils.format_json({ pid = pid, aspect = aspect })
    if not json then
        return false
    end
    local file = io.open(temporary, "wb")
    if not file then
        directory_ready = false
        return false
    end
    local written = file:write(json, "\n")
    local closed = file:close()
    if not written or not closed then
        os.remove(temporary)
        return false
    end
    if not os.rename(temporary, path) then
        os.remove(temporary)
        return false
    end
    return true
end

local function update()
    local aspect = display_aspect()
    if not aspect then
        remove_metadata()
    elseif aspect ~= last_aspect then
        if publish(aspect) then
            last_aspect = aspect
        else
            remove_metadata()
            mp.msg.warn("Could not publish camera aspect metadata")
        end
    end
end

-- Initial observer notifications also cover load-script during playback.
mp.observe_property("video-out-params", "native", update)
mp.observe_property("options/title", "string", update)
mp.observe_property("idle-active", "bool", update)
mp.observe_property("eof-reached", "bool", update)
mp.observe_property("vid", "string", update)

local function end_video()
    ended = true
    remove_metadata()
end

mp.register_event("start-file", end_video)
mp.register_event("end-file", end_video)
mp.register_event("file-loaded", function()
    ended = false
    update()
end)
mp.register_event("shutdown", function()
    shutting_down = true
    remove_metadata()
end)
