--[[
    VI Radio - configuration
    This mirrors the "VI Radio.ini" from the original singleplayer mod.
    Anything the .ini exposed is exposed here, plus a few FiveM-only options.
]]

Config = {}

-- ---------------------------------------------------------------------------
-- Controls
-- ---------------------------------------------------------------------------
-- Default key bindings. Players can rebind them in FiveM
-- (Settings -> Key Bindings -> FiveM), these are only the defaults.
Config.OpenKey         = 'Q'    -- hold to open the radio wheel
Config.MuteKey         = 'O'    -- toggle mute / unmute

Config.ScrollRadio     = true   -- mouse wheel also cycles stations while open
Config.ArrowAutoRepeat = true   -- holding left/right keeps cycling
Config.AutoRepeatDelay = 350    -- ms before auto repeat kicks in
Config.AutoRepeatRate  = 120    -- ms between repeats

-- Controller support.
-- The wheel opens on whatever the game has bound to the radio wheel control
-- (INPUT_VEH_RADIO_WHEEL, D-pad Left by default), read directly rather than
-- through a FiveM key binding -- key bindings only ever set a *default*, so a
-- pad binding added after the fact never reaches a client that already stored
-- one. Because D-pad Left is held to keep the wheel open, and is also
-- INPUT_CELLPHONE_LEFT, stations are browsed with the right stick, D-pad Right
-- and D-pad Up instead.
Config.Controller = {
    enabled    = true,
    deadzone   = 0.5,   -- right stick travel before a station change registers
    lockCamera = true,  -- stop the right stick swinging the camera while browsing

    -- The right stick's vertical axis flips the On Demand switch. Pushing up
    -- normally reads negative, the same way the game's own look control does.
    -- If your pad reports it the other way round, set this to true.
    -- Leave lockCamera on unless you like the view tilting as you flip it.
    invertSwitchAxis = false,
}

-- Mute from inside the wheel. Up and down belong to the On Demand switch, so
-- this sits on Spacebar on a keyboard (handbrake, which is not much use while
-- you are reading the radio anyway) and on D-pad Down on a controller, where
-- nothing else is free. The O binding above works everywhere, wheel or not.
Config.MuteInWheel = true

-- Permanently disable the vanilla radio controls (wheel, next/prev station) so
-- the stock wheel cannot flash open on the same button.
Config.DisableVanillaRadioControls = true

-- Who may open the wheel. The wheel is vehicle-only by default, which is what
-- keeps the controller bindings from clashing with anything on foot.
-- DriverOnly also gates the mute key and every On Demand change server-side
-- (see vehicleNetId in server.lua); passengers still hear whatever is playing.
Config.DriverOnly      = true   -- false = driver or passenger; true = driver only
Config.AllowOnFoot     = false  -- true = also works with the mobile radio on foot

-- ---------------------------------------------------------------------------
-- Feel / effects
-- ---------------------------------------------------------------------------
-- NOTE: SetTimeScale is client side only. On a busy server it will visibly
-- desync your vehicle from everyone else while the wheel is open. 1.0 disables
-- the slow-motion entirely and keeps just the HUD.
Config.TimeScale       = 0.075
Config.TimeScaleFade   = 180    -- ms to ease in/out of slow motion

Config.Timecycle         = 'hud_def_blur'
Config.TimecycleStrength = 1.0
Config.HiDof             = true

Config.HideRadar       = true   -- hide the minimap while the wheel is open
Config.DisableRadioHUD = true   -- permanently hide the vanilla radio station HUD

Config.RadioSounds     = true
Config.OpenSound       = 'sfx/radioopen.wav'
Config.CloseSound      = 'sfx/radioclose.wav'
Config.SoundVolume     = 50     -- 0-100

-- ---------------------------------------------------------------------------
-- HUD layout (values are in 1920x1080 reference pixels and scale with the
-- player resolution, same as the original ini)
-- ---------------------------------------------------------------------------
Config.Hud = {
    enabled           = true,
    iconSize          = 103,
    spacing           = 112,
    top               = 32,
    borderSize        = 3.5,
    boxColor          = '0,0,0,170',
    boxActiveColor    = '45,45,45,220',
    borderColor       = '255,255,255,90',
    borderActiveColor = '255,255,255,255',
    slideTime         = 110,    -- ms for the carousel slide animation
    sideIcons         = true,
    sideGap           = 37,
    leftIcon          = 'icons/On_Demand.png',
    rightIcon         = 'icons/Mute.png',
    unmuteIcon        = 'icons/Unmute.png',
    muteColor         = '255,255,255',  -- indicator colour while the radio plays
    mutedColor        = '255,59,48',    -- indicator colour while muted
    muteDim           = true,           -- drain the rest of the HUD of colour when muted
    leftIconHeight    = 55,
    rightIconHeight   = 24,
    infoLineY         = 24,
    infoLineWidth     = 189,
    infoLineHeight    = 6.5,
    stationY          = 34,
    stationScale      = 0.38,
    titleY            = 68,
    titleScale        = 0.33,
    artistY           = 95,
    artistScale       = 0.30,
    fontPx            = 94,     -- base size the *Scale values multiply
    stationLogos      = true,
    -- Secondary line under the station name when no live track info exists.
    -- 'genre' uses the table below, 'none' hides it.
    subtitle          = 'genre',
}

-- ---------------------------------------------------------------------------
-- Stations
-- ---------------------------------------------------------------------------
-- Stations not listed here still appear (using their raw name) as long as the
-- game reports them unlocked. Add hidden = true to drop one from the wheel.
Config.IncludeOff = true        -- include the "Radio Off" entry
Config.OffLabel   = 'RADIO OFF'

Config.Stations = {
    ['RADIO_01_CLASS_ROCK']            = { label = 'Los Santos Rock Radio',     logo = 'LosSantosRockRadio.png',     genre = 'Classic Rock' },
    ['RADIO_02_POP']                   = { label = 'Non-Stop-Pop FM',           logo = 'Non-Stop-PopFM.png',         genre = 'Pop' },
    ['RADIO_03_HIPHOP_NEW']            = { label = 'Radio Los Santos',          logo = 'RadioLosSantos.png',         genre = 'Contemporary Hip Hop' },
    ['RADIO_04_PUNK']                  = { label = 'Channel X',                 logo = 'ChannelX.png',               genre = 'Punk' },
    ['RADIO_05_TALK_01']               = { label = 'West Coast Talk Radio',     logo = 'WestCoastTalkRadio.png',     genre = 'Talk' },
    ['RADIO_06_COUNTRY']               = { label = 'Rebel Radio',               logo = 'RebelRadio.png',             genre = 'Country' },
    ['RADIO_07_DANCE_01']              = { label = 'Soulwax FM',                logo = 'SoulwaxFM.png',              genre = 'Dance' },
    ['RADIO_08_MEXICAN']               = { label = 'East Los FM',               logo = 'EastLosFM.png',              genre = 'Mexican' },
    ['RADIO_09_HIPHOP_OLD']            = { label = 'West Coast Classics',       logo = 'WestCoastClassics.png',      genre = 'Classic Hip Hop' },
    ['RADIO_11_TALK_02']               = { label = 'Blaine County Radio',       logo = 'BlaineCountyRadio.png',      genre = 'Talk' },
    ['RADIO_12_REGGAE']                = { label = 'Blue Ark',                  logo = 'TheBlueArk.png',             genre = 'Reggae' },
    ['RADIO_13_JAZZ']                  = { label = 'Worldwide FM',              logo = 'WorldWideFM.png',            genre = 'Jazz' },
    ['RADIO_14_DANCE_02']              = { label = 'FlyLo FM',                  logo = 'FlyloFM.png',                genre = 'Electronic' },
    ['RADIO_15_MOTOWN']                = { label = 'The Lowdown 91.1',          logo = 'TheLowdown91.1.png',         genre = 'Motown' },
    ['RADIO_16_SILVERLAKE']            = { label = 'Radio Mirror Park',         logo = 'RadioMirrorPark.png',        genre = 'Indie' },
    ['RADIO_17_FUNK']                  = { label = 'Space 103.2',               logo = 'Space103.2.png',             genre = 'Funk' },
    ['RADIO_18_90s_ROCK']              = { label = 'Vinewood Boulevard Radio',  logo = 'VinewoodBoulevardRadio.png', genre = 'Alternative Rock' },
    ['RADIO_19_USER']                  = { label = 'Self Radio',                logo = 'SelfRadio.png',              genre = 'Your Music' },
    ['RADIO_20_THELAB']                = { label = 'The Lab',                   logo = 'TheLab.png',                 genre = 'Experimental' },
    ['RADIO_21_DLC_XM17']              = { label = 'Blonded Los Santos 97.8',   logo = 'BlondedLosSantos.png',       genre = 'Contemporary' },
    ['RADIO_22_DLC_BATTLE_MIX1_RADIO'] = { label = 'LS Underground Radio',      logo = 'LSUndergroundRadio.png',     genre = 'House' },
    ['RADIO_23_DLC_XM19_RADIO']        = { label = 'iFruit Radio',              logo = 'iFruitRadio.png',            genre = 'Alternative' },
    ['RADIO_27_DLC_PRHEI4']            = { label = 'Still Slipping Los Santos', logo = 'StillSlipping.png',          genre = 'Hip Hop' },
    ['RADIO_34_DLC_HEI4_KULT']         = { label = 'Kult FM',                   logo = 'KultFM.png',                 genre = 'Post-Punk' },
    ['RADIO_35_DLC_HEI4_MLR']          = { label = 'The Music Locker',          logo = 'TheMusicLocker.png',         genre = 'House' },
    ['RADIO_36_AUDIOPLAYER']           = { label = 'Media Player',              logo = 'MediaPlayer.png',            genre = 'Custom' },
    ['RADIO_37_MOTOMAMI']              = { label = 'MOTOMAMI Los Santos',       logo = 'MOTOMAMI.png',               genre = 'Latin' },
}

-- ---------------------------------------------------------------------------
-- On Demand
-- ---------------------------------------------------------------------------
-- The On Demand entry plays YouTube links (and direct audio files) through the
-- car radio using xsound. Audio is positioned at the vehicle, so passengers and
-- anyone stood nearby hear the same thing at the same point in the track.
--
-- Note: xsound plays YouTube through the IFrame API. That is not what YouTube's
-- terms of service intend it for. It is how effectively every FiveM audio
-- resource does it, but it is worth knowing before you ship this on a server.
Config.OnDemand = {
    enabled    = true,
    label      = 'ON DEMAND',

    -- The left side icon is a two-position switch, RADIO over ON DEMAND, and it
    -- is thrown the way it reads: down for On Demand, up to hand the radio
    -- back. It works from anywhere in the wheel -- there is nothing to scroll
    -- to. Arrow keys on a keyboard, the right stick on a controller (the D-pad
    -- cannot take it: down is mute, and on a keyboard the right-stick axis is
    -- the mouse). Down also opens the panel once the wheel is released. Set
    -- false to leave up and down alone and reach the switch only through the
    -- panel and /ondemand.
    switchKeys = true,

    queueLimit = 20,       -- tracks a single vehicle may have queued
    -- Lowered from 20.0/35/70 (2026-09-15): reported as too loud, especially
    -- once you'd stepped away from the vehicle. Paired with the xsound
    -- engine's own falloff fix (html/scripts/SoundPlayer.js's updateVolume,
    -- linear -> squared), which is the bigger lever on how it fades with
    -- distance -- this just brings the ceiling down too.
    distance   = 12.0,     -- metres the audio carries from the vehicle
    volume     = 20,       -- default listener volume, 0-100
    maxVolume  = 45,       -- hard cap on what a listener can turn it up to

    -- Look the track title up through YouTube's oEmbed endpoint so the HUD's
    -- title/artist lines show something real. No API key needed. Set false to
    -- keep the server from making any outbound request.
    fetchTitles = true,

    -- Accept plain audio file links as well as YouTube.
    allowDirectFiles = true,
    fileExtensions   = { 'mp3', 'ogg', 'wav', 'm4a', 'aac', 'flac' },

    -- Playback sync. The server tells clients how far into the track it is;
    -- these control how often that is refreshed and how far a listener may
    -- drift before being seeked back into place.
    broadcastInterval = 10000,  -- ms between position rebroadcasts
    syncInterval      = 400,    -- ms between vehicle-position updates
    resyncDrift       = 3.0,    -- seconds of drift before a reseek

    commandCooldown = 400,      -- ms a player must wait between commands
}

-- ---------------------------------------------------------------------------
-- Link parsing (shared, so the client and the server agree on what is valid)
-- ---------------------------------------------------------------------------
-- Returns a canonical URL and its kind ('youtube' | 'file'), or nil plus a
-- reason. xsound's own YouTube parser only understands "?v=" and "youtu.be/",
-- so everything is normalised to the "?v=" form before it is handed over.

local function youtubeId(chunk)
    if not chunk then return nil end
    local id = chunk:sub(1, 11)
    if #id == 11 and id:match('^[%w_%-]+$') then return id end
    return nil
end

function Config.NormalizeUrl(input)
    if type(input) ~= 'string' then return nil, 'No link given' end

    local url = input:gsub('^%s+', ''):gsub('%s+$', '')
    if url == '' then return nil, 'No link given' end
    if #url > 512 then return nil, 'That link is too long' end
    if url:find('[%s"<>]') or url:find("'") or url:find('\\') then
        return nil, 'That does not look like a link'
    end
    if not url:match('^https?://') then url = 'https://' .. url end

    local host, rest = url:match('^https?://([^/?#]+)(.*)$')
    if not host then return nil, 'That does not look like a link' end
    host = host:lower():gsub('^www%.', '')
    rest = rest or ''

    if host == 'youtu.be' then
        local id = youtubeId(rest:match('^/([^/?#&]+)'))
        if id then return 'https://www.youtube.com/watch?v=' .. id, 'youtube' end
        return nil, 'That YouTube link has no video in it'
    end

    if host == 'youtube.com' or host == 'm.youtube.com' or host == 'music.youtube.com'
       or host == 'youtube-nocookie.com' then
        local id = youtubeId(rest:match('[?&]v=([^&#]+)'))
              or youtubeId(rest:match('^/shorts/([^/?#&]+)'))
              or youtubeId(rest:match('^/embed/([^/?#&]+)'))
              or youtubeId(rest:match('^/live/([^/?#&]+)'))
        if id then return 'https://www.youtube.com/watch?v=' .. id, 'youtube' end
        return nil, 'That YouTube link has no video in it'
    end

    if Config.OnDemand.allowDirectFiles then
        local path = rest:match('^([^?#]*)') or ''
        local ext  = path:match('%.(%w+)$')
        if ext then
            ext = ext:lower()
            for _, allowed in ipairs(Config.OnDemand.fileExtensions) do
                if ext == allowed then return url, 'file' end
            end
        end
        return nil, 'Only YouTube links and direct audio files are supported'
    end

    return nil, 'Only YouTube links are supported'
end
