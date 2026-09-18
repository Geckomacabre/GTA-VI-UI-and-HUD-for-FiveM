-- Thin bridge to the NUI scoreboard. All the layout lives in html/.

local visible = false

--- @param state table|nil Match state from the server, or nil to hide the board
function BB.updateHud(state)
    if not state then
        if visible then
            visible = false
            SendNUIMessage({ action = 'hide' })
        end
        return
    end

    visible = true

    SendNUIMessage({
        action = 'update',
        data = {
            state     = state.state,
            score     = state.score,
            clock     = state.clock,
            countdown = state.countdown,
            players   = state.players,
            myTeam    = BB.myTeam,
            myId      = GetPlayerServerId(PlayerId()),
            result    = state.result,
            teams     = Config.Match.teams,
            scoreLimit = Config.Match.scoreLimit,
        },
    })
end

-- Floating "+2" over the hoop, so a basket reads even if you're not watching the board.
RegisterNetEvent('gk_basketball:scoreFlash', function(hoopId, points, clean)
    local hoop
    for _, candidate in ipairs(BB.hoops) do
        if candidate.id == hoopId then
            hoop = candidate
            break
        end
    end

    if not hoop then return end

    CreateThread(function()
        local text = ('+%s'):format(points)
        if clean then text = text .. '  ' .. Config.Text.swish end

        local finish = GetGameTimer() + 1800

        while GetGameTimer() < finish do
            local rise = 1.0 - (finish - GetGameTimer()) / 1800.0

            SetTextScale(0.0, 0.42)
            SetTextFont(4)
            SetTextColour(255, 205, 80, math.floor(255 * (1.0 - rise)))
            SetTextOutline()
            SetTextCentre(true)
            SetDrawOrigin(hoop.coords.x, hoop.coords.y, hoop.coords.z + 0.5 + rise * 0.8, 0)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(text)
            EndTextCommandDisplayText(0.0, 0.0)
            ClearDrawOrigin()

            Wait(0)
        end
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SendNUIMessage({ action = 'hide' })
end)
