local config = require 'config.client'
local sharedConfig = require 'config.shared'
local WEAPONS = exports.qbx_core:GetWeapons()
local allowRespawn = true
local plyState = LocalPlayer.state

local function playDeadAnimation()
    local deadAnimDict = 'dead'
    local playerData = QBX.PlayerData
    local metadata = playerData and playerData.metadata
    local deadAnim = metadata and metadata.ishandcuffed and 'dead_f' or 'dead_a'

    local deadVehAnimDict = 'veh@low@front_ps@idle_duck'
    local deadVehAnim = 'sit'

    if cache.vehicle then
        if not IsEntityPlayingAnim(cache.ped, deadVehAnimDict, deadVehAnim, 3) then
            lib.playAnim(cache.ped, deadVehAnimDict, deadVehAnim, 1.0, 1.0, -1, 1, 0, false, false, false)
        end
    elseif not IsEntityPlayingAnim(cache.ped, deadAnimDict, deadAnim, 3) then
        lib.playAnim(cache.ped, deadAnimDict, deadAnim, 1.0, 1.0, -1, 1, 0, false, false, false)
    end
end

exports('PlayDeadAnimation', playDeadAnimation)

---put player in death animation and make invincible
function OnDeath(attacker, weapon)
    SetDeathState(sharedConfig.deathState.DEAD)
    TriggerServerEvent('qbx_medical:server:onPlayerDied', attacker, weapon)
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'demo', 0.1)

    plyState.invBusy = true

    -- [Rewritten, 2026-09-09] Fire the client-only death event immediately
    -- instead of after WaitForPlayerToStopMoving()+ResurrectPlayer() --
    -- those together used to delay fenix-police's WASTED cinematic by
    -- however long ragdoll physics took to settle (up to a couple seconds),
    -- and ResurrectPlayer forces the ped from its ragdoll resting position
    -- into a standing pose facing whatever direction the ragdoll happened
    -- to land facing, then back down into the "dead" anim -- a visible
    -- delay before WASTED even started, then a rotation snap once it had.
    -- Settling the ped now happens only once fenix-police confirms its
    -- screen has faded to black (fenix-police:client:wastedScreenFadedOut,
    -- fired right after its own DoScreenFadeOut completes), with a timeout
    -- fallback if fenix-police isn't installed/running -- so WASTED starts
    -- the instant you die, and the pop (still there, native resurrection
    -- can't avoid it) happens off-screen instead of before or during it.
    TriggerEvent('qbx_medical:client:onPlayerDied', attacker, weapon)

    local resolved = false
    local handler
    local function settle()
        if resolved then return end
        resolved = true
        if handler then RemoveEventHandler(handler) end

        WaitForPlayerToStopMoving()
        ResurrectPlayer()
        playDeadAnimation()
        SetEntityInvincible(cache.ped, true)
        SetEntityHealth(cache.ped, GetEntityMaxHealth(cache.ped))

        CreateThread(function()
            while DeathState == sharedConfig.deathState.DEAD do
                DisableControls()
                SetCurrentPedWeapon(cache.ped, `WEAPON_UNARMED`, true)
                -- A translucent red wash for as long as the player is
                -- actually DEAD (not just during fenix-police's own brief
                -- WASTED cinematic), letting a "lying there dead" roleplay
                -- moment read as one visually even well past the cinematic
                -- ending.
                DrawRect(0.5, 0.5, 1.0, 1.0, 160, 20, 20, 70)
                Wait(0)
            end
        end)

        CheckForRespawn()
    end

    -- Plain client-local event (fenix-police fires it with TriggerEvent,
    -- not TriggerClientEvent) -- no RegisterNetEvent needed, that's only
    -- for events crossing the server/client boundary.
    handler = AddEventHandler('fenix-police:client:wastedScreenFadedOut', settle)

    -- Matches fenix-police's own WASTED_DURATION (4s) + its 1s fade-out +
    -- margin -- only used if fenix-police isn't installed/running and never
    -- fires the event above, so death still resolves without it instead of
    -- leaving the player stuck ragdolled forever.
    CreateThread(function()
        Wait(6000)
        settle()
    end)
end

exports('KillPlayer', OnDeath)

local function respawn()
    -- [Fix, 2026-09-09] qbx_ambulancejob's own hospital-bed placement
    -- (server/hospital.lua's respawn -> client checkedIn ->
    -- putPlayerInBed) teleports and sets a bed camera with no screen fade
    -- of its own -- a jarring pop straight from wherever the player died
    -- into a hospital bed with nothing hiding the cut, whether respawn is
    -- reached by holding the key or waiting out the full timer. Fades out
    -- before the respawn round-trip and back in after.
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end

    local success = lib.callback.await('qbx_medical:server:respawn')
    if not success then
        DoScreenFadeIn(500)
        return
    end
    if QBX.PlayerData.metadata.ishandcuffed then
        TriggerEvent('police:client:GetCuffed', -1)
    end
    TriggerEvent('police:client:DeEscort')
    plyState.invBusy = false

    -- [Changed, 2026-09-09] qbx_ambulancejob's respawn cutscene (real
    -- vanilla walk-out scenes for hospitals that have one) now fades the
    -- screen back in itself, partway through the cutscene, same as vanilla
    -- does -- skip doing it again here so a finished cutscene doesn't get a
    -- redundant fade-in stacked on top of it.
    if not IsScreenFadedIn() and not IsScreenFadingIn() then
        Wait(500) -- lets a plain teleport (no cutscene) settle before revealing it
        DoScreenFadeIn(500)
    end
end

-- [Removed, 2026-09-09] The hold-F AI-medic/ambulance option (and the
-- lib.progressBar -> DrawRect rewrite history that went with it) has been
-- pulled entirely, at the user's explicit request, after it kept failing
-- in ways that didn't reproduce cleanly (the bar not rendering, the
-- ambulance overshooting) even through several rounds of fixes -- most
-- recently traced to an unrelated ebu_trailer native crash possibly
-- starving frame time, but that was never confirmed to actually be the
-- whole story. Hold-E is the only respawn option now. If this gets
-- revisited later: qbx_ambulancejob/client/aimedic.lua (the cutscene),
-- CanCallAiMedic/CallRealEms exports on qbx_ambulancejob/client/
-- setdownedstate.lua, and the "HOLD F..." prompt text there were also
-- removed in the same pass -- see that resource's own git history.
-- [Shrunk, 2026-09-09] The 0.30x0.03 center-screen version (made big
-- specifically to rule out "is it rendering at all" while F existed) was
-- confirmed visible but way oversized now that it's staying permanently --
-- back down to something in scale with the rest of the HUD.
local function drawHoldBar(progress)
    local barW, barH = 0.10, 0.012
    local x, y = 0.5, 0.7
    DrawRect(x, y, barW + 0.006, barH + 0.006, 0, 0, 0, 200)
    DrawRect(x - barW / 2 + (barW * progress) / 2, y, barW * progress, barH, 220, 30, 30, 240)
end

---Holds `controlId` down for `durationMs`, drawing a native progress bar and
---returning false immediately if released early or if the player stops
---being DEAD partway through (e.g. a doctor revives them mid-hold).
---@param controlId number
---@param durationMs number
---@return boolean completed
local function holdToConfirm(controlId, durationMs)
    local startedAt = GetGameTimer()
    while IsControlPressed(0, controlId) do
        if DeathState ~= sharedConfig.deathState.DEAD then return false end
        local elapsed = GetGameTimer() - startedAt
        if elapsed >= durationMs then return true end
        drawHoldBar(elapsed / durationMs)
        Wait(0)
    end
    return false
end

---@return boolean triggered
local function tryRespawnPrompt()
    if not (allowRespawn and IsControlJustPressed(0, 38)) then return false end

    -- [Fix, 2026-09-09] Must read RespawnHoldTime here, at call time, not
    -- as a file-top-level `local X = RespawnHoldTime * 1000` -- fxmanifest's
    -- client_scripts order loads dead.lua BEFORE main.lua (where
    -- RespawnHoldTime is actually defined), so evaluating it at load time
    -- hit a nil-arithmetic error that silently aborted the rest of THIS
    -- FILE's loading -- including the gameEventTriggered handler further
    -- down that's supposed to detect death in the first place. That one
    -- error is why nothing in this whole feature ever fired again after
    -- the resource loaded.
    if holdToConfirm(38, RespawnHoldTime * 1000) then
        respawn()
        return true
    end
    return false
end

---Allow player to respawn
function CheckForRespawn()
    local lastDeathTimeTick = GetGameTimer()
    while DeathState == sharedConfig.deathState.DEAD do
        if tryRespawnPrompt() then return end

        local now = GetGameTimer()
        if now - lastDeathTimeTick >= 1000 then
            lastDeathTimeTick = now
            DeathTime -= 1
            if DeathTime <= 0 and allowRespawn then
                respawn()
                return
            end
        end
        Wait(0)
    end
end

function AllowRespawn()
    allowRespawn = true
end

exports('AllowRespawn', AllowRespawn)

exports('DisableRespawn', function()
    allowRespawn = false
end)

---log the death of a player along with the attacker and the weapon used.
---@param victim number ped
---@param attacker number ped
---@param weapon string weapon hash
local function logDeath(victim, attacker, weapon)
    local playerId = NetworkGetPlayerIndexFromPed(victim)
    local playerName = (' %s (%d)'):format(GetPlayerName(playerId), GetPlayerServerId(playerId)) or locale('info.self_death')
    local killerId = NetworkGetPlayerIndexFromPed(attacker)
    local killerName = ('%s (%d)'):format(GetPlayerName(killerId), GetPlayerServerId(killerId)) or locale('info.self_death')
    local weaponLabel = WEAPONS[weapon]?.label or 'Unknown'
    local weaponName = WEAPONS[weapon]?.name or 'Unknown'
    local message = locale('logs.death_log_message', killerName, playerName, weaponLabel, weaponName)

    lib.callback.await('qbx_medical:server:log', false, 'logDeath', message)
end

---when player is killed by another player, set last stand mode, or if already in last stand mode, set player to dead mode.
---@param event string
---@param data table
AddEventHandler('gameEventTriggered', function(event, data)
    if event ~= 'CEventNetworkEntityDamage' then return end
    if not plyState.isLoggedIn then return end
    local victim, attacker, victimDied, weapon = data[1], data[2], data[4], data[7]
    if not IsEntityAPed(victim) or not victimDied or NetworkGetPlayerIndexFromPed(victim) ~= cache.playerId or not IsEntityDead(cache.ped) then return end
    if DeathState == sharedConfig.deathState.ALIVE then
        -- [Fix, 2026-09-09] LastStand removed from the normal death flow
        -- entirely, for every weapon/cause -- an earlier, narrower pass of
        -- this same fix only skipped it for fatal falls (via a
        -- config.instantKillWeapons table, since removed as dead config
        -- once this covered every cause instead). Every fatal hit now
        -- goes straight to DEAD: the player is left lying there (OnDeath
        -- already does exactly that -- invincible, controls disabled,
        -- dead animation) for EMS to come revive via qbx_ambulancejob's
        -- normal firstaid flow, instead of a self/companion-revivable
        -- knockdown first. StartLastStand/EndLastStand and their exports
        -- are left in place, just unused by this handler -- another
        -- resource can still call StartLastStand directly for its own
        -- mechanic (a taser knockdown, say) without this change touching
        -- that at all.
        logDeath(victim, attacker, weapon)
        DeathTime = config.deathTime
        OnDeath(attacker, weapon)
    elseif DeathState == sharedConfig.deathState.LAST_STAND then
        EndLastStand()
        logDeath(victim, attacker, weapon)
        DeathTime = config.deathTime
        OnDeath(attacker, weapon)
    end
end)

function DisableControls()
    DisableAllControlActions(0)
    EnableControlAction(0, 1, true)
    EnableControlAction(0, 2, true)
    EnableControlAction(0, 245, true)
    EnableControlAction(0, 38, true)
    EnableControlAction(0, 0, true)
    EnableControlAction(0, 322, true)
    EnableControlAction(0, 288, true)
    EnableControlAction(0, 213, true)
    EnableControlAction(0, 249, true)
    EnableControlAction(0, 46, true)
    EnableControlAction(0, 47, true)
end