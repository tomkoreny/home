-- Dwindle exposes resize dispatchers, but not its split tree to Lua. Measure
-- their local response and solve for a small joint adjustment: fitting each
-- video independently would make siblings fight over the same split.
-- All probes and their reversals run in one compositor callback, before render.
local function sizes(windows)
    local result = {}
    for i, w in ipairs(windows) do
        result[i] = w.size
    end
    return result
end

local function errors(windows, ratios)
    local result, score, fitted = {}, 0, true
    for _, w in ipairs(windows) do
        local ratio = ratios[w.address]
        if ratio then
            local size = w.size
            local error = math.log(size.x / size.y / ratio)
            result[#result + 1] = error
            score = score + error * error
            fitted = fitted and math.abs(size.x - ratio * size.y) <= math.max(2, 2 * ratio)
        end
    end
    return result, score, fitted
end

local function resize(w, axis, delta)
    local before = w.size[axis]
    hl.dispatch(hl.dsp.window.resize({
        window = w,
        x = axis == "x" and delta or 0,
        y = axis == "y" and delta or 0,
        relative = true,
    }))
    -- At a native split-ratio limit the dispatcher may apply less than asked.
    -- Reverse only the applied movement, not the original (clipped) request.
    return math.min(math.abs(delta), math.abs(w.size[axis] - before)) * (delta < 0 and -1 or 1)
end

local function solve(matrix, rhs)
    local n = #rhs
    for col = 1, n do
        local pivot = col
        for row = col + 1, n do
            if math.abs(matrix[row][col]) > math.abs(matrix[pivot][col]) then
                pivot = row
            end
        end
        if math.abs(matrix[pivot][col]) < 1e-14 then
            return nil
        end
        matrix[col], matrix[pivot] = matrix[pivot], matrix[col]
        rhs[col], rhs[pivot] = rhs[pivot], rhs[col]
        for row = col + 1, n do
            local factor = matrix[row][col] / matrix[col][col]
            for k = col + 1, n do
                matrix[row][k] = matrix[row][k] - factor * matrix[col][k]
            end
            rhs[row] = rhs[row] - factor * rhs[col]
        end
    end
    local result = {}
    for row = n, 1, -1 do
        local value = rhs[row]
        for col = row + 1, n do
            value = value - matrix[row][col] * result[col]
        end
        result[row] = value / matrix[row][row]
    end
    return result
end

local function fit_workspace(windows, ratios)
    local initial = sizes(windows)
    local _, initial_score, fitted = errors(windows, ratios)
    if #windows < 2 or fitted then
        return { before = initial_score, after = initial_score }
    end

    for _ = 1, 6 do
        local baseline, score, done = errors(windows, ratios)
        if done then
            break
        end
        local actions = {}
        for _, w in ipairs(windows) do
            for _, axis in ipairs({ "x", "y" }) do
                local applied = resize(w, axis, 8)
                if applied ~= 0 then
                    local perturbed = errors(windows, ratios)
                    resize(w, axis, -applied)
                    local gradient = {}
                    for i, value in ipairs(baseline) do
                        gradient[i] = (perturbed[i] - value) / applied
                    end
                    actions[#actions + 1] = { window = w, axis = axis, gradient = gradient }
                end
            end
        end

        -- Minimum-norm least squares: J^T (J J^T + damping I)^-1 (-error).
        -- Damping also handles impossible all-video arrangements without
        -- inventing spare space or shrinking ordinary windows to nothing.
        local matrix, rhs = {}, {}
        for i = 1, #baseline do
            matrix[i], rhs[i] = {}, -baseline[i]
            for j = 1, #baseline do
                local value = i == j and 1e-9 or 0
                for _, action in ipairs(actions) do
                    value = value + action.gradient[i] * action.gradient[j]
                end
                matrix[i][j] = value
            end
        end
        local solution = solve(matrix, rhs)
        if not solution then
            break
        end
        local largest = 0
        for _, action in ipairs(actions) do
            action.delta = 0
            for i, value in ipairs(solution) do
                action.delta = action.delta + action.gradient[i] * value
            end
            largest = math.max(largest, math.abs(action.delta))
        end
        if largest < 1 then
            break
        end

        local accepted = false
        for _, fraction in ipairs({ 1, 0.5, 0.25, 0.125 }) do
            local scale = fraction * math.min(1, 400 / largest)
            for _, action in ipairs(actions) do
                local delta = math.floor(math.abs(action.delta * scale) + 0.5)
                delta = delta * (action.delta < 0 and -1 or 1)
                action.applied = delta ~= 0 and resize(action.window, action.axis, delta) or 0
            end
            local safe = true
            for i, w in ipairs(windows) do
                local size = w.size
                -- Do not sacrifice a usable neighbouring tile just to remove
                -- video bars. Already-small tiles are allowed to stay small.
                safe = safe and size.x >= math.min(initial[i].x, 160) and size.y >= math.min(initial[i].y, 90)
            end
            local _, next_score = errors(windows, ratios)
            if safe and next_score < score - 1e-8 then
                accepted = true
                break
            end
            for i = #actions, 1, -1 do
                local action = actions[i]
                if action.applied ~= 0 then
                    resize(action.window, action.axis, -action.applied)
                end
            end
        end
        if not accepted then
            break
        end
    end
    local _, final_score = errors(windows, ratios)
    return { before = initial_score, after = final_score }
end

return function(ratios)
    local workspaces, blocked = {}, {}
    for _, w in ipairs(hl.get_windows()) do
        local ws = w.workspace
        if ws and w.mapped and not w.hidden then
            if w.fullscreen ~= 0 then
                blocked[ws.id] = true
            end
            local layout = w.layout
            if not w.floating and layout and layout.name == "dwindle" then
                workspaces[ws.id] = workspaces[ws.id] or {}
                table.insert(workspaces[ws.id], w)
            end
        end
    end
    local result = {}
    for id, windows in pairs(workspaces) do
        if not blocked[id] then
            result[id] = fit_workspace(windows, ratios)
        end
    end
    return result
end
