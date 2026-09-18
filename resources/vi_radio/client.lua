--[[
    VI Radio - client
    FiveM port of the singleplayer "VI Radio" mod by sej0bec.

    The original is a ScriptHookVDotNet plugin that drew its HUD with native
    textures. FiveM cannot load SHVDN assemblies, so the HUD is rebuilt as NUI
    and the game side (stations, slow motion, timecycle, mute) lives here.
]]

local RES = GetCurrentResourceName()
local OD  = Config.OnDemand
local ON_DEMAND = 'ONDEMAND'

-- state ----------------------------------------------------------------------
local stations      = {}     -- ordered list of { name, label, logo, genre }
local index         = 1      -- currently highlighted entry in `stations`
local wheelOpen     = false  -- the hold-to-browse wheel, which owns the effects
local popupOpen     = false  -- the On Demand panel, which owns NUI focus
local keyHeld       = false
local muted         = false
local mutedVehicle  = 0      -- vehicle the mute was applied to
local nowPlaying    = { title = nil, artist = nil }
local timeScaleNow  = 1.0
local navHeldSince  = 0
local navLastStep   = 0
local navDir        = 0
local stickLatched  = false  -- right stick must recentre between station changes
local stickYLatched = false  -- same again vertically, for the On Demand switch
local stationPicked = false  -- a station was browsed to during this wheel session
local panelOnClose  = false  -- On Demand was switched on, so show the panel on release
local openedByControl = false -- opened by the raw radio-wheel control (pad), not our keybind

-- On Demand. Sessions are keyed by vehicle network id and are pushed by the
-- server; nothing in here decides what is playing, only whether this client is
-- close enough to hear it.
local odSessions = {}
local odVolume   = math.min(OD.volume, OD.maxVolume) / 100
local odMuted    = false
-- Tracks the last lowpass state sent per sound id, so the muffle toggle
-- below (which runs every OD.syncInterval) only calls SetLowpassSound on an
-- actual change instead of every tick.
local odLowpassState = {}

-- helpers --------------------------------------------------------------------

local function currentVehicle()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return 0 end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return 0 end
    if Config.DriverOnly and GetPedInVehicleSeat(veh, -1, false) ~= ped then return 0 end
    return veh
end

local function canUseRadio()
    if currentVehicle() ~= 0 then return true end
    return Config.AllowOnFoot and IsMobilePhoneRadioActive()
end

-- On Demand belongs to a vehicle, so it is only offered while sat in one.
local function odAvailable()
    return OD.enabled and currentVehicle() ~= 0
end

local function myNetId()
    local veh = currentVehicle()
    if veh == 0 then return nil end
    return VehToNet(veh)
end

local function odSessionHere()
    local netId = myNetId()
    return netId and odSessions[netId] or nil
end

local function odSoundId(netId)
    return 'vi_radio_od_' .. netId
end

local function odElapsed(sess)
    if not sess or not sess.recvAt then return 0.0 end
    if sess.paused then return sess.position end
    return sess.position + (GetGameTimer() - sess.recvAt) / 1000.0
end

local function stationInfo(name)
    local cfg = Config.Stations[name]
    if cfg then
        return {
            name  = name,
            label = cfg.label,
            logo  = cfg.logo and ('logos/' .. cfg.logo) or nil,
            genre = cfg.genre,
        }
    end
    -- Unknown / add-on station: fall back to a readable version of the raw name.
    local pretty = name:gsub('^RADIO_%d+_', ''):gsub('^DLC_', ''):gsub('_', ' ')
    return { name = name, label = pretty, logo = nil, genre = nil }
end

local function buildStations()
    local list = {}
    local seenOff = false

    for i = 0, GetNumUnlockedRadioStations() - 1 do
        local name = GetRadioStationName(i)
        if name and name ~= '' then
            if name == 'OFF' then
                seenOff = true
            elseif not name:find('^HIDDEN_') then
                local cfg = Config.Stations[name]
                if not (cfg and cfg.hidden) then
                    list[#list + 1] = stationInfo(name)
                end
            end
        end
    end
    if Config.IncludeOff or seenOff then
        list[#list + 1] = { name = 'OFF', label = Config.OffLabel, logo = nil, genre = nil }
    end
    stations = list

    -- keep the highlight on whatever is actually playing
    local playing = GetPlayerRadioStationName() or 'OFF'
    for i, s in ipairs(stations) do
        if s.name == playing then index = i break end
    end
    if index > #stations then index = 1 end
end

local function applyStation(entry)
    local veh = currentVehicle()
    if veh ~= 0 then
        SetVehRadioStation(veh, entry.name)
        -- The vanilla radio is otherwise near-silent the moment you step
        -- outside the vehicle -- SET_VEHICLE_RADIO_LOUD is the same native
        -- used for "big speaker" vehicles (audible outside with the game's
        -- own real distance falloff), so this gives the normal station wheel
        -- the same "carries outside the car" behaviour On Demand already has
        -- via xsound, using the real engine audio instead of reimplementing it.
        SetVehicleRadioLoud(veh, entry.name ~= 'OFF')
    end
    SetRadioToStationName(entry.name)
end

local function applyMute()
    local veh = currentVehicle()
    if veh ~= 0 then
        SetVehicleRadioEnabled(veh, not muted)
        mutedVehicle = muted and veh or 0
    end
    SetMobileRadioEnabledDuringGameplay(not muted)
end

-- NUI ------------------------------------------------------------------------

local function nuiPayload()
    local items = {}
    for i, s in ipairs(stations) do
        items[i] = {
            label = s.label,
            logo  = s.logo,
            genre = s.genre,
            off   = s.name == 'OFF',
        }
    end
    return items
end

-- The title/artist lines come from whatever is playing: an On Demand track when
-- one is, otherwise whatever another resource has pushed in through SetNowPlaying.
-- Returns the station name to show, then the two lines under it.
--
-- While On Demand is on, the highlighted station is not what anyone is hearing,
-- so naming it above an On Demand track would read as that station playing that
-- track. The lines say On Demand instead -- until the player starts browsing,
-- at which point the carousel is a station picker again and the name under it
-- is the one they are about to choose.
local function currentLines()
    local sess = odSessionHere()

    if sess and not stationPicked then
        if not sess.playing then return OD.label, nil, 'Nothing queued' end
        return OD.label, sess.title, sess.paused and 'Paused' or sess.artist
    end

    return nil, nowPlaying.title, nowPlaying.artist
end

-- The left icon is the radio/On Demand switch when On Demand is available, and
-- the original static artwork when it is not.
local function hudPayload()
    local copy = {}
    for k, v in pairs(Config.Hud) do copy[k] = v end
    copy.odSwitch = OD.enabled
    return copy
end

local function pushState(withList)
    if not Config.Hud.enabled then return end
    local label, title, artist = currentLines()
    SendNUIMessage({
        action  = 'state',
        open    = wheelOpen or popupOpen,
        hud     = withList and hudPayload() or nil,
        list    = withList and nuiPayload() or nil,
        index   = index - 1,
        muted   = muted,
        odOn    = odSessionHere() ~= nil,
        label   = label,
        title   = title,
        artist  = artist,
    })
end

local function playSound(file)
    if not Config.RadioSounds or not file then return end
    SendNUIMessage({ action = 'sound', file = file, volume = Config.SoundVolume / 100 })
end

-- On Demand panel ------------------------------------------------------------

local function setStation(name)
    local veh = currentVehicle()
    if veh ~= 0 then
        SetVehRadioStation(veh, name)
        -- Same as applyStation above -- also covers odEngage's setStation('OFF')
        -- (silences the loud vanilla radio while On Demand takes over) and
        -- odDisengage's restore, since both funnel through this function.
        SetVehicleRadioLoud(veh, name ~= 'OFF')
    end
    SetRadioToStationName(name)
end

--[[
    Keeping the vanilla radio audible after you step out of your own car.

    SET_VEHICLE_RADIO_LOUD alone (above) does NOT do this on its own --
    confirmed against real reports, not assumed: forum.cfx.re/t/203276 (a
    2018 thread building the exact same feature) found "when I'm outside and
    my friend's inside the vehicle, I can hear his radio loudly, but doesn't
    work when no one's inside" -- an EMPTY vehicle's radio audio stops
    rendering entirely in the game engine, regardless of the loud flag or the
    engine still running. The only working fix anyone's found for this is
    keeping a ped seated in the vehicle so it never actually reads as empty.

    So: the moment you get out of a vehicle whose station isn't OFF, an
    invisible, harmless placeholder ped is put in your old seat to keep the
    radio "occupied" and therefore audible. It's cleaned up the moment you
    get back in (real ped takes the seat back), the vehicle is gone, or
    you've walked far enough that nothing would be audible anyway.
]]
local radioKeepAlive = {} -- [vehicle] = pedHandle
local lastVehicle = 0

local function despawnRadioKeepAlive(veh)
    local ped = radioKeepAlive[veh]
    if ped then
        if DoesEntityExist(ped) then DeletePed(ped) end
        radioKeepAlive[veh] = nil
    end
end

local function spawnRadioKeepAlive(veh)
    if radioKeepAlive[veh] or not DoesEntityExist(veh) then return end
    if GetPedInVehicleSeat(veh, -1) ~= 0 then return end -- someone real already driving

    local model = `a_m_y_business_01` -- never actually seen -- see SetEntityVisible below
    RequestModel(model)
    local waited = 0
    while not HasModelLoaded(model) and waited < 500 do Wait(0) waited = waited + 1 end
    if not HasModelLoaded(model) then return end

    local ped = CreatePedInsideVehicle(veh, 6, model, -1, true, true)
    SetModelAsNoLongerNeeded(model)
    if not ped or ped == 0 then return end

    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)

    radioKeepAlive[veh] = ped
end

-- The 500ms poll below is too slow to beat GTA's own seat-assignment: if a
-- keep-alive ped is still sitting in seat -1 the instant you start climbing
-- back in, the game reroutes you to another seat before the poll ever gets
-- a chance to despawn it. GET_VEHICLE_PED_IS_TRYING_TO_ENTER catches the
-- entry attempt itself, so the seat is freed before that resolution happens.
CreateThread(function()
    while true do
        Wait(0)
        local tryingVeh = GetVehiclePedIsTryingToEnter(PlayerPedId())
        if tryingVeh ~= 0 and radioKeepAlive[tryingVeh] then
            despawnRadioKeepAlive(tryingVeh)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(500)

        local veh = currentVehicle()
        if veh ~= lastVehicle then
            if lastVehicle ~= 0 and GetPlayerRadioStationName() ~= 'OFF' then
                spawnRadioKeepAlive(lastVehicle)
            end
            if veh ~= 0 then despawnRadioKeepAlive(veh) end -- getting back in
            lastVehicle = veh
        end

        -- Clean up anything too far away to matter, gone, or that picked up a
        -- real driver in the meantime (someone else got in and drove off).
        local here = GetEntityCoords(PlayerPedId())
        for keepVeh, ped in pairs(radioKeepAlive) do
            local gone = not DoesEntityExist(keepVeh)
                or #(GetEntityCoords(keepVeh) - here) > 80.0
                or (DoesEntityExist(ped) and GetPedInVehicleSeat(keepVeh, -1) ~= ped)
            if gone then despawnRadioKeepAlive(keepVeh) end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RES then return end
    for veh in pairs(radioKeepAlive) do despawnRadioKeepAlive(veh) end
end)

local function odPanelState()
    local sess = odSessionHere()
    return {
        inVehicle = currentVehicle() ~= 0,
        engaged   = sess ~= nil,
        playing   = sess ~= nil and sess.playing or false,
        paused    = sess and sess.paused or false,
        index     = sess and sess.index or 0,
        title     = sess and sess.title or nil,
        artist    = sess and sess.artist or nil,
        queue     = sess and sess.queue or {},
        limit     = OD.queueLimit,
        volume    = math.floor(odVolume * 100 + 0.5),
        maxVolume = OD.maxVolume,
        muted     = odMuted,
    }
end

local function pushPanel()
    if not popupOpen then return end
    SendNUIMessage({ action = 'od', open = true, state = odPanelState() })
end

local function openPanel()
    if popupOpen or not odAvailable() then return end
    popupOpen = true
    -- The wheel is hold-to-open and takes no focus, so the panel cannot live
    -- inside it. It latches the HUD open instead -- without the slow motion,
    -- which follows browsing, not the HUD being on screen.
    SetNuiFocus(true, true)
    pushState(false)
    pushPanel()
    TriggerServerEvent('vi_radio:od:sync')
end

local function closePanel()
    if not popupOpen then return end
    popupOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'od', open = false })
    pushState(false)
end

-- the switch -----------------------------------------------------------------
-- On is a session existing on the server for this vehicle. The station playing
-- at the moment it goes on is handed over with it, so that whoever turns it off
-- again -- which need not be the same player -- puts back the right station.

local function odEngage(withPanel)
    if not odAvailable() or odSessionHere() then return end

    TriggerServerEvent('vi_radio:od:engage', GetPlayerRadioStationName() or 'OFF')
    setStation('OFF')
    if withPanel then openPanel() end
end

local function odDisengage(restore)
    if not odSessionHere() then return end

    TriggerServerEvent('vi_radio:od:disengage', restore ~= false)
    closePanel()
end

-- wheel ----------------------------------------------------------------------

local function step(dir)
    if #stations == 0 then return end
    stationPicked = true
    index = index + dir
    if index < 1 then index = #stations elseif index > #stations then index = 1 end

    -- With On Demand on, the game radio is off and a track is already playing.
    -- Applying each station as it is scrolled past would start the radio over
    -- the top of it, so browsing only previews and the choice lands on release.
    if not odSessionHere() then applyStation(stations[index]) end
    if muted then
        muted = false
        applyMute()
    end
    pushState(false)
end

local function openWheel()
    if wheelOpen or popupOpen or not canUseRadio() then return end
    buildStations()
    wheelOpen = true
    stationPicked, panelOnClose = false, false
    navDir, navHeldSince, navLastStep = 0, 0, 0
    playSound(Config.OpenSound)
    pushState(true)
end

local function closeWheel()
    if not wheelOpen then return end
    wheelOpen = false
    stickLatched = false
    stickYLatched = false
    openedByControl = false
    playSound(Config.CloseSound)

    if Config.Timecycle ~= '' then ClearTimecycleModifier() end
    if Config.HideRadar then DisplayRadar(true) end

    -- Releasing the key is the commit. Skipped when the wheel closed because
    -- the player got out, which is not a choice they made.
    if OD.enabled and currentVehicle() ~= 0 then
        if stationPicked and odSessionHere() then
            applyStation(stations[index])
            -- Browsing to a station is the other way of switching On Demand
            -- off, and the station they just landed on is the one they want --
            -- not the one that was playing before the switch went on. Merely
            -- opening and closing the wheel is not browsing, so it leaves an
            -- On Demand queue alone.
            odDisengage(false)
        elseif panelOnClose and odSessionHere() then
            -- Up asked for the panel. It cannot open while the wheel key is
            -- still held -- NUI focus and hold-to-open cannot share a key --
            -- so it waits here for the release.
            openPanel()
        end
    end

    stationPicked, panelOnClose = false, false

    pushState(false)
end

local function toggleMute()
    if not canUseRadio() then return end
    muted = not muted
    applyMute()
    pushState(false)
    if not wheelOpen and not popupOpen and Config.Hud.enabled then
        -- brief HUD flash so the player sees the mute state change
        SendNUIMessage({ action = 'flash', muted = muted })
    end
end

-- keybinds -------------------------------------------------------------------

RegisterCommand('+vi_radio', function() keyHeld = true end, false)
RegisterCommand('-vi_radio', function() keyHeld = false end, false)
RegisterKeyMapping('+vi_radio', 'VI Radio: hold to open the radio wheel', 'keyboard', Config.OpenKey)

RegisterCommand('vi_radio_mute', function() toggleMute() end, false)
RegisterKeyMapping('vi_radio_mute', 'VI Radio: mute / unmute the radio', 'keyboard', Config.MuteKey)

-- main loop ------------------------------------------------------------------

CreateThread(function()
    while true do
        local wait = 200

        -- Controllers do not go through RegisterKeyMapping. A pad binding there
        -- is only a *default*, so it never reaches anyone whose client already
        -- stored a binding for this command. Reading the game's own radio-wheel
        -- control instead always works, needs no binding, and follows whatever
        -- the player has that control set to (D-pad Left by default).
        local ctrlHeld = Config.Controller.enabled and IsDisabledControlPressed(0, 85)
        local wantOpen = (keyHeld or ctrlHeld) and not popupOpen

        if wantOpen and not wheelOpen then
            -- keyHeld means our keyboard bind fired, so arrow keys are safe.
            openedByControl = not keyHeld
            openWheel()
        elseif wheelOpen and (not wantOpen or not canUseRadio()) then
            closeWheel()
        end

        if not wheelOpen and IsPedInAnyVehicle(PlayerPedId(), false) then
            wait = 0  -- poll every frame so the pad opens without lag
        end

        if wheelOpen then
            wait = 0

            -- effects
            if Config.Timecycle ~= '' then
                SetTimecycleModifier(Config.Timecycle)
                SetTimecycleModifierStrength(Config.TimecycleStrength + 0.0)
            end
            if Config.HiDof then SetUseHiDof() end
            if Config.HideRadar then DisplayRadar(false) end

            -- swallow the inputs we are replacing
            DisableControlAction(0, 85, true)   -- VEH_RADIO_WHEEL
            DisableControlAction(0, 81, true)   -- VEH_NEXT_RADIO
            DisableControlAction(0, 82, true)   -- VEH_PREV_RADIO
            DisableControlAction(0, 83, true)   -- VEH_NEXT_RADIO_TRACK
            DisableControlAction(0, 84, true)   -- VEH_PREV_RADIO_TRACK
            DisableControlAction(0, 27, true)   -- PHONE
            DisableControlAction(0, 76, true)   -- VEH_HANDBRAKE (Spacebar = mute here)
            DisableControlAction(0, 172, true)  -- CELLPHONE_UP
            DisableControlAction(0, 173, true)  -- CELLPHONE_DOWN
            DisableControlAction(0, 174, true)  -- CELLPHONE_LEFT  (arrow left)
            DisableControlAction(0, 175, true)  -- CELLPHONE_RIGHT (arrow right)
            if Config.ScrollRadio then
                DisableControlAction(0, 14, true)  -- WEAPON_WHEEL_NEXT
                DisableControlAction(0, 15, true)  -- WEAPON_WHEEL_PREV
            end

            local pad = openedByControl
            local now = GetGameTimer()

            if pad and Config.Controller.lockCamera then
                DisableControlAction(0, 1, true)    -- LOOK_LR
                DisableControlAction(0, 2, true)    -- LOOK_UD
                DisableControlAction(0, 220, true)  -- SCRIPT_RIGHT_AXIS_X
                DisableControlAction(0, 221, true)  -- SCRIPT_RIGHT_AXIS_Y
            end

            -- The radio / On Demand switch, reachable from anywhere in the
            -- wheel -- there is nothing to scroll to. It is thrown the way the
            -- artwork reads: RADIO is the top position and ON DEMAND the
            -- bottom one, so down engages On Demand and up hands the radio
            -- back. Split by device, because the same control id is different
            -- hardware depending on what is being held: 172/173 are the arrow
            -- keys on a keyboard and the D-pad on a pad, and 221 is the right
            -- stick on a pad but the *mouse* on a keyboard, which would throw
            -- the switch every time the player looked around.
            if OD.enabled and OD.switchKeys then
                local up, down = false, false

                if pad then
                    -- Pushing up reads negative, the same way the game's own
                    -- look control does; a pad that reports it the other way
                    -- round is what invertSwitchAxis is for.
                    local y = GetDisabledControlNormal(0, 221)
                    if Config.Controller.invertSwitchAxis then y = -y end

                    if math.abs(y) >= Config.Controller.deadzone then
                        if not stickYLatched then
                            stickYLatched = true
                            if y < 0 then up = true else down = true end
                        end
                    else
                        stickYLatched = false
                    end
                else
                    stickYLatched = false
                    up   = IsDisabledControlJustPressed(0, 172)
                    down = IsDisabledControlJustPressed(0, 173)
                end

                if down then
                    odEngage(false)
                    -- Throwing it to On Demand is almost always followed by
                    -- wanting to queue something. Throwing it down again while
                    -- it is already there is therefore how the panel is
                    -- reopened without a command.
                    panelOnClose  = true
                    stationPicked = false
                elseif up then
                    odDisengage(true)
                    panelOnClose = false
                end
            end

            -- Mute. Spacebar on a keyboard -- the handbrake, which is no loss
            -- while you are reading the radio -- and D-pad Down on a pad, where
            -- nothing else is free. Up and down are the switch on both.
            if Config.MuteInWheel then
                if pad then
                    if IsDisabledControlJustPressed(0, 173) then toggleMute() end
                elseif IsDisabledControlJustPressed(0, 76) then
                    toggleMute()
                end
            end

            -- navigation
            local dir, held = 0, 0

            if pad then
                -- D-pad Left is the button holding the wheel open, so it cannot
                -- double as "previous": right stick, D-pad Right, D-pad Up.
                local axis = GetDisabledControlNormal(0, 220)
                if math.abs(axis) >= Config.Controller.deadzone then
                    held = axis > 0 and 1 or -1
                    if not stickLatched then
                        dir = held
                        stickLatched = true
                    end
                else
                    stickLatched = false
                    if IsDisabledControlJustPressed(0, 175) then dir = 1
                    elseif IsDisabledControlJustPressed(0, 172) then dir = -1 end
                    if IsDisabledControlPressed(0, 175) then held = 1
                    elseif IsDisabledControlPressed(0, 172) then held = -1 end
                end
            else
                stickLatched = false
                if IsDisabledControlJustPressed(0, 175) then dir = 1
                elseif IsDisabledControlJustPressed(0, 174) then dir = -1
                elseif Config.ScrollRadio and IsDisabledControlJustPressed(0, 14) then dir = 1
                elseif Config.ScrollRadio and IsDisabledControlJustPressed(0, 15) then dir = -1 end

                if IsDisabledControlPressed(0, 175) then held = 1
                elseif IsDisabledControlPressed(0, 174) then held = -1 end
            end

            if dir ~= 0 then
                step(dir)
                navDir, navHeldSince, navLastStep = dir, now, now
            elseif Config.ArrowAutoRepeat and held ~= 0 and held == navDir then
                if now - navHeldSince > Config.AutoRepeatDelay
                   and now - navLastStep > Config.AutoRepeatRate then
                    step(held)
                    navLastStep = now
                end
            elseif held == 0 then
                navDir = 0
            end
        end

        Wait(wait)
    end
end)

-- slow motion ----------------------------------------------------------------
-- Kept in its own thread so the easing is smooth and so it can be switched off
-- entirely (Config.TimeScale = 1.0) without touching the rest of the script.
-- It follows `wheelOpen` only: the On Demand panel leaves the world at normal
-- speed, because nobody should be typing a link in 0.075x time.

CreateThread(function()
    if Config.TimeScale >= 1.0 then return end
    while true do
        local target = wheelOpen and Config.TimeScale or 1.0
        if math.abs(timeScaleNow - target) > 0.001 then
            local stepSize = (16 / math.max(Config.TimeScaleFade, 1))
            if timeScaleNow < target then
                timeScaleNow = math.min(target, timeScaleNow + stepSize)
            else
                timeScaleNow = math.max(target, timeScaleNow - stepSize)
            end
            SetTimeScale(timeScaleNow + 0.0)
            Wait(0)
        else
            if timeScaleNow ~= 1.0 and target == 1.0 then
                timeScaleNow = 1.0
                SetTimeScale(1.0)
            end
            Wait(wheelOpen and 0 or 200)
        end
    end
end)

-- vanilla radio HUD and controls ---------------------------------------------
-- The stock wheel shares its button with ours on both keyboard (Q) and pad
-- (D-pad Left), so it has to be suppressed every frame, not only while open.

CreateThread(function()
    if not Config.DisableRadioHUD and not Config.DisableVanillaRadioControls then return end
    while true do
        if Config.DisableRadioHUD then
            HideHudComponentThisFrame(20)  -- HUD_RADIO_STATIONS
        end
        if Config.DisableVanillaRadioControls then
            DisableControlAction(0, 85, true)  -- VEH_RADIO_WHEEL
            DisableControlAction(0, 81, true)  -- VEH_NEXT_RADIO
            DisableControlAction(0, 82, true)  -- VEH_PREV_RADIO
        end
        Wait(0)
    end
end)

-- housekeeping ---------------------------------------------------------------
-- Re-apply mute when the player changes vehicle, and keep the idle HUD in sync
-- with whatever else on the server might have changed the station.

CreateThread(function()
    local lastStation = nil
    while true do
        if muted then
            local veh = currentVehicle()
            if veh ~= mutedVehicle then applyMute() end
        end

        local playing = GetPlayerRadioStationName()
        if playing ~= lastStation then
            lastStation = playing
            if not wheelOpen and #stations > 0 then
                for i, s in ipairs(stations) do
                    if s.name == playing then index = i break end
                end
                pushState(false)
            end
        end

        if popupOpen and currentVehicle() == 0 then closePanel() end

        Wait(500)
    end
end)

-- On Demand ------------------------------------------------------------------
-- The server says what is playing and how far into it; this side only decides
-- whether this player is close enough to hear it, and keeps xsound pointed at
-- the vehicle. xsound itself handles the falloff and the silencing at range.

local function odDestroy(netId)
    if not OD.enabled then return end
    local id = odSoundId(netId)
    if exports['xsound']:soundExists(id) then
        exports['xsound']:Destroy(id)
    end
    odLowpassState[id] = nil
end

RegisterNetEvent('vi_radio:od:state', function(data)
    if type(data) ~= 'table' or type(data.netId) ~= 'number' then return end
    local netId = data.netId

    -- `gone` is the switch going off. Anything else is the switch being on,
    -- whether or not a track happens to be playing right now.
    if data.gone then
        odDestroy(netId)
        odSessions[netId] = nil

        if data.restore and netId == myNetId() then setStation(data.restore) end
    else
        local prev = odSessions[netId]
        local sess = prev or { netId = netId }

        -- A new token means a different track, which needs a fresh player.
        if not prev or prev.token ~= data.token then sess.restart = true end

        sess.playing  = data.playing and true or false
        sess.token    = data.token
        sess.url      = data.url
        sess.title    = data.title
        sess.artist   = data.artist
        sess.duration = data.duration
        sess.index    = data.index
        sess.queue    = data.queue or {}
        sess.paused   = data.paused or false
        sess.position = data.position or 0.0
        sess.recvAt   = GetGameTimer()

        odSessions[netId] = sess
    end

    if netId == myNetId() then
        pushState(false)
        pushPanel()
    end
end)

RegisterNetEvent('vi_radio:od:notify', function(message)
    if popupOpen then
        SendNUIMessage({ action = 'od', notice = message })
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName('~y~VI Radio~s~: ' .. tostring(message))
        EndTextCommandThefeedPostTicker(false, true)
    end
end)

CreateThread(function()
    -- Far enough out that xsound's own caching (which silences and restores a
    -- sound around its falloff radius) does the fine-grained work, and this
    -- only decides whether a player exists at all.
    local keepAlive = OD.distance + 60.0

    -- OD.enabled is re-read every pass rather than once: the startup check
    -- below can switch On Demand off after this thread has already begun.
    while true do
        local here = OD.enabled and GetEntityCoords(PlayerPedId()) or nil

        for netId, sess in pairs(here and odSessions or {}) do
            local id  = odSoundId(netId)
            local veh = NetworkDoesNetworkIdExist(netId) and NetToVeh(netId) or 0
            local pos = (veh ~= 0 and DoesEntityExist(veh)) and GetEntityCoords(veh) or nil
            local audible = sess.playing and pos ~= nil and not odMuted
                            and odVolume > 0.0 and #(pos - here) <= keepAlive

            if audible then
                -- Muffle once outside a tight "in/right next to the vehicle"
                -- radius. No-op for YouTube tracks played through the
                -- embedded iframe (SoundPlayer.js's initLowpass refuses to
                -- run for those) -- this only actually does anything once a
                -- track is playing through the Howl/file path, i.e. a direct
                -- file link or a YouTube link resolved to a raw audio stream
                -- by server.lua's resolveAudioStream.
                local distFromVeh = #(pos - here)
                local shouldMuffle = distFromVeh > (OD.distance * 0.4)
                if odLowpassState[id] ~= shouldMuffle then
                    odLowpassState[id] = shouldMuffle
                    exports['xsound']:SetLowpassSound(id, shouldMuffle)
                end

                local exists = exports['xsound']:soundExists(id)

                if sess.restart or not exists then
                    sess.restart = nil
                    if exists then exports['xsound']:Destroy(id) end

                    local token = sess.token
                    exports['xsound']:PlayUrlPos(id, sess.url, odVolume, pos, false, {
                        -- Seeking before the player has loaded does nothing, so
                        -- the catch-up happens once it reports it is playing.
                        onPlayStart = function()
                            local live = odSessions[netId]
                            if not live or live.token ~= token then return end
                            exports['xsound']:setTimeStamp(id, odElapsed(live))
                            if live.paused then exports['xsound']:Pause(id) end

                            local duration = exports['xsound']:getMaxDuration(id)
                            if duration and duration > 0 and not live.duration then
                                TriggerServerEvent('vi_radio:od:duration', netId, token, duration + 0.0)
                            end
                        end,
                    })
                    exports['xsound']:Distance(id, OD.distance)
                    exports['xsound']:destroyOnFinish(id, false)
                else
                    exports['xsound']:Position(id, pos)

                    local paused = exports['xsound']:isPaused(id)
                    if sess.paused and not paused then
                        exports['xsound']:Pause(id)
                    elseif not sess.paused and paused then
                        exports['xsound']:Resume(id)
                        exports['xsound']:setTimeStamp(id, odElapsed(sess))
                    end

                    if not sess.paused then
                        local at = exports['xsound']:getTimeStamp(id)
                        if at and at >= 0 and math.abs(at - odElapsed(sess)) > OD.resyncDrift then
                            exports['xsound']:setTimeStamp(id, odElapsed(sess))
                        end
                    end

                    if not sess.duration then
                        local duration = exports['xsound']:getMaxDuration(id)
                        if duration and duration > 0 then
                            TriggerServerEvent('vi_radio:od:duration', netId, sess.token, duration + 0.0)
                        end
                    end
                end
            else
                odDestroy(netId)
            end
        end

        Wait(OD.syncInterval)
    end
end)

-- panel callbacks ------------------------------------------------------------

RegisterNUICallback('odClose', function(_, cb)
    closePanel()
    cb('ok')
end)

RegisterNUICallback('odAdd', function(data, cb)
    local url, err = Config.NormalizeUrl(data and data.url)
    if not url then
        cb({ ok = false, error = err })
        return
    end
    TriggerServerEvent('vi_radio:od:add', url, data.playNow and true or false)
    cb({ ok = true })
end)

RegisterNUICallback('odRemove', function(data, cb)
    if data and type(data.index) == 'number' then
        TriggerServerEvent('vi_radio:od:remove', data.index)
    end
    cb('ok')
end)

RegisterNUICallback('odSkip', function(data, cb)
    TriggerServerEvent('vi_radio:od:skip', (data and data.dir == -1) and -1 or 1)
    cb('ok')
end)

RegisterNUICallback('odPause', function(_, cb)
    TriggerServerEvent('vi_radio:od:pause')
    cb('ok')
end)

RegisterNUICallback('odStop', function(_, cb)
    TriggerServerEvent('vi_radio:od:stop')
    cb('ok')
end)

RegisterNUICallback('odDisengage', function(_, cb)
    odDisengage(true)
    cb('ok')
end)

-- Volume and mute are per listener and never leave this client. They are the
-- one protection that does not restrict who may play something: anyone can
-- broadcast, but nobody has to listen at a volume they did not choose.
local function setOdVolume(value)
    value = math.max(0, math.min(OD.maxVolume, tonumber(value) or 0))
    odVolume = value / 100
    SetResourceKvp('vi_radio:od_volume', tostring(value))

    for netId in pairs(odSessions) do
        local id = odSoundId(netId)
        if exports['xsound']:soundExists(id) then
            exports['xsound']:setVolumeMax(id, odVolume)
        end
    end
end

RegisterNUICallback('odVolume', function(data, cb)
    setOdVolume(data and data.volume)
    pushPanel()
    cb('ok')
end)

RegisterNUICallback('odMute', function(data, cb)
    odMuted = data and data.muted and true or false
    SetResourceKvp('vi_radio:od_muted', odMuted and '1' or '0')
    if odMuted then
        for netId in pairs(odSessions) do odDestroy(netId) end
    end
    pushPanel()
    cb('ok')
end)

-- commands -------------------------------------------------------------------

RegisterCommand('ondemand', function(_, args)
    if not OD.enabled then return end
    if currentVehicle() == 0 then
        TriggerEvent('vi_radio:od:notify', 'You have to be in a vehicle')
        return
    end

    if args[1] then
        local url, err = Config.NormalizeUrl(table.concat(args, ' '))
        if not url then
            TriggerEvent('vi_radio:od:notify', err)
            return
        end
        if not odSessionHere() then setStation('OFF') end
        TriggerServerEvent('vi_radio:od:add', url, false)
        return
    end

    -- With the switch already on this just reopens the panel; with it off it
    -- flips it on, which opens the panel anyway.
    if odSessionHere() then openPanel() else odEngage(true) end
end, false)

-- debug ----------------------------------------------------------------------
-- /viradio_debug prints why the wheel is or is not responding.

RegisterCommand('viradio_debug', function()
    local ok, kbm = pcall(function() return IsUsingKeyboardAndMouse(2) end)
    print(('[vi_radio] inVehicle=%s seatAllowed=%s stations=%d open=%s panel=%s viaControl=%s keyHeld=%s ctrl85=%s keyboardAndMouse=%s muted=%s'):format(
        tostring(IsPedInAnyVehicle(PlayerPedId(), false)),
        tostring(currentVehicle() ~= 0),
        #stations,
        tostring(wheelOpen),
        tostring(popupOpen),
        tostring(openedByControl),
        tostring(keyHeld),
        tostring(IsDisabledControlPressed(0, 85)),
        ok and tostring(kbm) or 'n/a',
        tostring(muted)))

    local sessionCount = 0
    for netId, sess in pairs(odSessions) do
        sessionCount = sessionCount + 1
        print(('[vi_radio] on demand netId=%d track=%s at=%.1fs paused=%s queue=%d sound=%s'):format(
            netId,
            tostring(sess.title),
            odElapsed(sess),
            tostring(sess.paused),
            #(sess.queue or {}),
            tostring(OD.enabled and exports['xsound']:soundExists(odSoundId(netId)))))
    end
    print(('[vi_radio] on demand sessions=%d volume=%.2f localMute=%s'):format(
        sessionCount, odVolume, tostring(odMuted)))
end, false)

-- exports --------------------------------------------------------------------
-- FiveM has no native that resolves the current track title, so the title and
-- artist lines are driven from outside. Any resource that knows what is playing
-- (custom streamed stations, xsound, a metadata feed) can push it in here.

local function setNowPlaying(title, artist)
    nowPlaying.title  = title
    nowPlaying.artist = artist
    pushState(false)
end

exports('SetNowPlaying', setNowPlaying)
RegisterNetEvent('vi_radio:setNowPlaying', setNowPlaying)

exports('IsOpen', function() return wheelOpen end)
exports('IsMuted', function() return muted end)
exports('SetMuted', function(state)
    if state == muted then return end
    muted = state and true or false
    applyMute()
    pushState(false)
end)
exports('GetStation', function()
    if odSessionHere() then return ON_DEMAND end
    return GetPlayerRadioStationName()
end)

exports('IsOnDemandOn', function() return odSessionHere() ~= nil end)
exports('IsOnDemandPlaying', function()
    local sess = odSessionHere()
    return sess ~= nil and sess.playing == true
end)
exports('SetOnDemand', function(on)
    if on then odEngage(false) else odDisengage(true) end
end)
exports('GetOnDemandTrack', function()
    local sess = odSessionHere()
    if not sess then return nil end
    return { title = sess.title, artist = sess.artist, paused = sess.paused, position = odElapsed(sess) }
end)
exports('OpenOnDemand', openPanel)

-- cleanup --------------------------------------------------------------------

AddEventHandler('onResourceStop', function(name)
    if name ~= RES then return end
    SetTimeScale(1.0)
    ClearTimecycleModifier()
    DisplayRadar(true)
    SetNuiFocus(false, false)
    if muted then
        muted = false
        applyMute()
    end
    for netId in pairs(odSessions) do odDestroy(netId) end
end)

CreateThread(function()
    -- On Demand is the only part of this resource that needs anything else
    -- installed. Without xsound it switches itself off rather than erroring on
    -- every export call; the radio wheel carries on working.
    if OD.enabled and GetResourceState('xsound') ~= 'started' then
        OD.enabled = false
        print('[vi_radio] xsound is not started, On Demand is disabled')
    end

    local storedVolume = GetResourceKvpString('vi_radio:od_volume')
    if storedVolume then
        odVolume = math.max(0, math.min(OD.maxVolume, tonumber(storedVolume) or OD.volume)) / 100
    end
    odMuted = GetResourceKvpString('vi_radio:od_muted') == '1'

    while not NetworkIsSessionStarted() do Wait(250) end
    buildStations()
    pushState(true)
    if OD.enabled then TriggerServerEvent('vi_radio:od:sync') end
end)
