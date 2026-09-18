--[[
    In-game rim placement.

    GTA's basketball hoops are baked into the map, not props, so there's no way to
    find a rim from code — the coordinates have to be measured by eye. This tool
    makes that a ten-second job per hoop instead of a config-editing session.

        /bball_place <courtId> [home|away]

    You drop into noclip so you can fly around the rim and check the alignment from
    several angles. WASD flies you; the arrow keys or numpad move the marker.
]]

BB.placing = false

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

-- Windows virtual key codes. Raw-key natives let us read the numpad, which GTA
-- doesn't expose as controls.
local NUMPAD = {
    up = 104, down = 98, left = 100, right = 102,   -- 8 2 4 6
    raise = 107, lower = 109,                       -- + -
}

local hasRawKeys = IsRawKeyDown ~= nil

local function rawDown(vk)
    return hasRawKeys and IsRawKeyDown(vk) or false
end

--- Arrow keys double as the numpad, so either works.
local function markerInput()
    return {
        fwd   = IsDisabledControlPressed(0, 172) or rawDown(NUMPAD.up),
        back  = IsDisabledControlPressed(0, 173) or rawDown(NUMPAD.down),
        left  = IsDisabledControlPressed(0, 174) or rawDown(NUMPAD.left),
        right = IsDisabledControlPressed(0, 175) or rawDown(NUMPAD.right),
        raise = IsDisabledControlPressed(0, 10)  or rawDown(NUMPAD.raise),
        lower = IsDisabledControlPressed(0, 11)  or rawDown(NUMPAD.lower),
    }
end

--------------------------------------------------------------------------------
-- Noclip
--------------------------------------------------------------------------------

local noclip = { active = false, coords = nil }

local function startNoclip()
    local ped = PlayerPedId()

    noclip.active = true
    noclip.coords = GetEntityCoords(ped)

    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
end

local function stopNoclip()
    if not noclip.active then return end
    noclip.active = false

    local ped = PlayerPedId()

    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)

    -- Put you back on the ground rather than leaving you hovering.
    local coords = GetEntityCoords(ped)
    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, false)

    if found then
        SetEntityCoordsNoOffset(ped, coords.x, coords.y, groundZ, false, false, false)
    end
end

local function updateNoclip()
    local ped = PlayerPedId()
    local rot = GetGameplayCamRot(2)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local cosX = math.abs(math.cos(x))

    local fwd   = vec3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
    local right = vec3(math.cos(z), math.sin(z), 0.0)

    local speed = Config.Placement.flySpeed
        * (IsDisabledControlPressed(0, 21) and Config.Placement.flyBoost or 1.0)
        * GetFrameTime()

    local pos = noclip.coords

    if IsDisabledControlPressed(0, 32) then pos = pos + fwd * speed end
    if IsDisabledControlPressed(0, 33) then pos = pos - fwd * speed end
    if IsDisabledControlPressed(0, 34) then pos = pos - right * speed end
    if IsDisabledControlPressed(0, 35) then pos = pos + right * speed end
    if IsDisabledControlPressed(0, 22) then pos = pos + vec3(0.0, 0.0, speed) end
    if IsDisabledControlPressed(0, 36) then pos = pos - vec3(0.0, 0.0, speed) end

    noclip.coords = pos
    SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(ped, rot.z)
end

--- Stops the game reacting to keys we've repurposed: no walking, no shooting, no
--- phone popping up on the arrow keys.
local function suppressControls()
    for _, control in ipairs({
        32, 33, 34, 35,        -- WASD (ped is frozen anyway, but this stops anim twitch)
        21, 22, 36,            -- sprint / jump / duck
        24, 25, 140, 141, 142, -- attack and melee
        172, 173, 174, 175,    -- arrows, which are also the phone
        10, 11,                -- page up / down
        44, 38,                -- Q / E
    }) do
        DisableControlAction(0, control, true)
    end
end

--------------------------------------------------------------------------------
-- Preview
--------------------------------------------------------------------------------

--- Seeds the preview from whatever you're looking at, so it starts near the rim
--- rather than at your feet.
local function raycastSeed()
    local cam    = GetGameplayCamCoord()
    local rot    = GetGameplayCamRot(2)
    local z, x   = math.rad(rot.z), math.rad(rot.x)
    local cosX   = math.abs(math.cos(x))
    local dir    = vec3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
    local far    = cam + dir * 20.0

    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        cam.x, cam.y, cam.z, far.x, far.y, far.z, -1, PlayerPedId(), 4)
    local _, hit, endCoords = GetShapeTestResult(ray)

    if hit == 1 then return endCoords end

    -- Nothing in the way: drop the preview 5m ahead at regulation rim height.
    local ped = GetEntityCoords(PlayerPedId())
    return vec3(ped.x + dir.x * 5.0, ped.y + dir.y * 5.0, ped.z + 3.05)
end

local function drawRim(coords, r, g, b)
    local radius = Config.Scoring.rimRadius

    -- The rim itself.
    DrawMarker(25, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        radius * 2.0, radius * 2.0, radius * 2.0, r, g, b, 170, false, false, 2, false)

    -- The scoring cylinder, so you can see the volume a shot has to pass through.
    for i = 1, 6 do
        local step = i * 0.12
        DrawMarker(28, coords.x, coords.y, coords.z + step, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            radius, radius, radius, r, g, b, 40, false, false, 2, false)
    end

    -- A drop line to the floor for depth perception.
    DrawLine(coords.x, coords.y, coords.z, coords.x, coords.y, coords.z - 3.2, r, g, b, 120)
end

BB.drawRim = drawRim

--- Draws the control list as a native panel, top-left.
---
--- Native rather than ox_lib's text UI: that renders markdown (so a "---" separator
--- silently turns the line above it into a heading) and is designed for one-line
--- transient prompts that auto-hide. This needs a dozen lines pinned on screen for
--- the whole session, which is a different job.
local function drawPanel(lines)
    local x     = 0.016
    local top   = 0.26
    local lineH = 0.021
    local width = 0.215
    local pad   = 0.010

    local height = lineH * #lines + pad * 2

    DrawRect(x - 0.006 + width / 2, top + height / 2 - lineH * 0.4,
        width, height, 0, 0, 0, 175)

    local y = top

    for _, line in ipairs(lines) do
        if line ~= '' then
            SetTextFont(4)
            SetTextScale(0.0, 0.30)
            SetTextColour(200, 205, 215, 235)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(line)
            EndTextCommandDisplayText(x, y)
        end

        y = y + lineH
    end
end

--- Live values, drawn on screen rather than pushed into the text UI. Keeping them
--- separate means the controls list can stay pinned and never re-renders while you
--- nudge the marker.
local function drawReadout(lines)
    local y = 0.855

    for _, line in ipairs(lines) do
        SetTextFont(4)
        SetTextScale(0.0, 0.34)
        SetTextColour(255, 255, 255, 215)
        SetTextOutline()
        SetTextCentre(true)
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(line)
        EndTextCommandDisplayText(0.5, y)
        y = y + 0.028
    end
end

--------------------------------------------------------------------------------
-- Placement loop
--------------------------------------------------------------------------------

local function placementLoop(courtId, team)
    BB.placing = true

    local coords = raycastSeed()

    startNoclip()


    CreateThread(function()
        while BB.placing do
            suppressControls()
            updateNoclip()

            local fine = IsDisabledControlPressed(0, 19) -- LEFT ALT
            local step = (fine and Config.Placement.fineStep or Config.Placement.step)
            local keys = markerInput()

            -- Marker moves relative to the camera, so "up" is always away from you.
            local heading = math.rad(GetGameplayCamRot(2).z)
            local fx, fy = -math.sin(heading), math.cos(heading)

            if keys.fwd   then coords = coords + vec3(fx * step, fy * step, 0.0) end
            if keys.back  then coords = coords - vec3(fx * step, fy * step, 0.0) end
            if keys.left  then coords = coords + vec3(-fy * step, fx * step, 0.0) end
            if keys.right then coords = coords - vec3(-fy * step, fx * step, 0.0) end
            if keys.raise then coords = coords + vec3(0.0, 0.0, step) end
            if keys.lower then coords = coords - vec3(0.0, 0.0, step) end

            drawRim(coords, 90, 220, 130)

            drawPanel(Config.Text.placement_panel)

            drawReadout({
                ('Court: ~y~%s~s~%s'):format(courtId, team and ('   Team: ~y~' .. team .. '~s~') or ''),
                ('%.3f  %.3f  %.3f'):format(coords.x, coords.y, coords.z),
            })

            if IsDisabledControlJustReleased(0, 191) or IsDisabledControlJustReleased(0, 201) then
                BB.placing = false
                TriggerServerEvent('gk_basketball:saveHoop', courtId, BB.plain(coords), team)
            elseif IsDisabledControlJustReleased(0, 194) then -- BACKSPACE
                BB.placing = false
                BB.notify('Placement cancelled.', 'inform')
            end

            Wait(0)
        end

        stopNoclip()
    end)
end

RegisterCommand('bball_place', function(_, args)
    if BB.placing then
        BB.notify('Already placing a hoop.', 'error')
        return
    end

    local courtId = args[1]

    if not courtId then
        -- Default to the court you're standing on, or start a new one.
        local nearest, dist = BB.nearestCourt()
        courtId = (nearest and dist and dist < 60.0) and nearest or 'court1'
        BB.notify(('No court id given, using "%s".'):format(courtId), 'inform')
    end

    local team = args[2]
    if team and team ~= 'home' and team ~= 'away' then
        BB.notify('Team must be "home", "away", or left off for pickup rules.', 'error')
        return
    end

    placementLoop(courtId, team)
end, false)

RegisterCommand('bball_delhoop', function()
    local coords = GetEntityCoords(PlayerPedId())
    local nearest, nearestDist

    for _, hoop in ipairs(BB.hoops) do
        local dist = #(coords - hoop.coords)
        if dist < 15.0 and (not nearestDist or dist < nearestDist) then
            nearest, nearestDist = hoop, dist
        end
    end

    if not nearest then
        BB.notify('No hoop within 15m.', 'error')
        return
    end

    TriggerServerEvent('gk_basketball:deleteHoop', nearest.id)
end, false)

RegisterCommand('bball_hoops', function()
    if #BB.hoops == 0 then
        BB.notify('No hoops placed yet. Use /bball_place to add one.', 'inform')
        return
    end

    print(('^2[gk_basketball]^7 %s hoop(s):'):format(#BB.hoops))
    for _, hoop in ipairs(BB.hoops) do
        print(('  %s  court=%s  team=%s  vec3(%.3f, %.3f, %.3f)'):format(
            hoop.id, hoop.court, hoop.team or '-', hoop.coords.x, hoop.coords.y, hoop.coords.z))
    end

    BB.notify(('%s hoop(s) listed in F8.'):format(#BB.hoops), 'inform')
end, false)

--------------------------------------------------------------------------------
-- Debug rendering
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        if Config.Debug and not BB.placing and #BB.hoops > 0 then
            local coords = GetEntityCoords(PlayerPedId())

            for _, hoop in ipairs(BB.hoops) do
                if #(coords - hoop.coords) < 40.0 then
                    drawRim(hoop.coords, 80, 160, 255)
                end
            end

            Wait(0)
        else
            Wait(1000)
        end
    end
end)

-- Never leave someone stuck in noclip because the resource stopped mid-placement.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    BB.placing = false
    stopNoclip()
end)
