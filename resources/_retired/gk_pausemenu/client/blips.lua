--[[
    Scans every currently active NATIVE blip on the whole server -- from
    every resource, not just this one -- instead of maintaining a hand-typed
    Config.Locations list. Replaces an earlier version of this file that did
    exactly that (a curated list matched by grepping each job resource for
    its own AddBlipForCoord call): keeping that list in sync by hand every
    time a resource added/moved/removed a blip was already showing cracks
    (a stale Trucking Depot coordinate that had drifted from um_truckerjob's
    own config, categories that didn't mean anything once qbx_garages'
    dynamically-added garages were mixed in) -- scanning the real blips
    directly means there is nothing to keep in sync at all.

    HOW THE SCAN WORKS -- there is no native that lists every active blip
    directly. GET_FIRST_BLIP_INFO_ID(sprite)/GET_NEXT_BLIP_INFO_ID(sprite)
    only walk blips of ONE sprite id at a time, so this loops every sprite id
    GTA V's own blip image list defines (see html/data/blip_sprites.json,
    fetched from docs.fivem.net/docs/game-references/blips/ -- the same
    source used to pick the handful of icons rendered for real, see
    html/app.js's ICON_LOCAL_FALLBACK) and walks each one's chain. This is
    the standard community technique for "find every blip regardless of
    which resource made it" (the same trick admin blip-finder resources
    use) -- there being no shortcut is a real platform limitation, not
    something this implementation missed.

    WHAT GETS FILTERED OUT -- HUD::GET_BLIP_INFO_ID_TYPE tells you what a
    blip is attached to: 1 Vehicle, 2 Ped, 3 Object, 4 Coord, 5 unknown,
    6 Pickup, 7 Radius. Only 4 (Coord) is a genuine static point of interest
    -- a Locations list of "places to go" showing every other player's blip,
    every vehicle blip, or the wanted-radius circle would be actively wrong,
    not just cluttered. EXCLUDED_SPRITES below additionally drops sprite 8
    (the player's own current waypoint) even though it IS type Coord --
    showing "your own waypoint" as a location to travel to is circular.

    WHAT THIS CANNOT DO -- there is no native that reads a blip's own name
    back (BeginTextCommandSetBlipName/EndTextCommandSetBlipName is
    write-only from script's perspective). A discovered blip's label here is
    therefore built from what IS readable: the sprite's own generic name
    (html/app.js turns "radar_police_station" into "Police Station") plus
    GET_NAME_OF_ZONE's district name (e.g. "Mission Row") -- close to what
    you'd actually want ("Police Station (Mission Row)"), but it cannot
    recover a specific custom name a script gave its own blip (e.g. it
    cannot tell two different police stations apart beyond their zone).
]]

GK = GK or {}

-- HUD::GET_BLIP_INFO_ID_TYPE's own documented enum (docs.fivem.net) --
-- only Coord is a real static point of interest, see this file's header.
local BLIP_TYPE_COORD = 4

-- Sprite 8 = radar_waypoint (the player's own current waypoint) -- excluded
-- even though it's type Coord, see this file's header comment.
local EXCLUDED_SPRITES = { [8] = true }

-- html/data/blip_sprites.json's highest defined id as of the build docs.
-- fivem.net documents (its own page's <!--commented-out--> gaps are
-- reserved/removed indices, not evidence the list continues past this).
local MAX_SPRITE = 965

--[[
    GET_NAME_OF_ZONE(x, y, z) returns a short internal zone CODE (e.g.
    "SKID"), not a display name -- there's no native that resolves a GXT
    label key to display text from script (checked _tools/nativedb: no such
    native exists, only the write-only text-command pipeline used for
    on-screen UI). This table is docs.fivem.net's own documented code->name
    list for GET_NAME_OF_ZONE, copied verbatim rather than reconstructed.
]]
local ZONE_NAMES = {
    AIRP = 'Los Santos International Airport', ALAMO = 'Alamo Sea', ALTA = 'Alta',
    ARMYB = 'Fort Zancudo', BANHAMC = 'Banham Canyon Dr', BANNING = 'Banning',
    BEACH = 'Vespucci Beach', BHAMCA = 'Banham Canyon', BRADP = 'Braddock Pass',
    BRADT = 'Braddock Tunnel', BURTON = 'Burton', CALAFB = 'Calafia Bridge',
    CANNY = 'Raton Canyon', CCREAK = 'Cassidy Creek', CHAMH = 'Chamberlain Hills',
    CHIL = 'Vinewood Hills', CHU = 'Chumash', CMSW = 'Chiliad Mountain State Wilderness',
    CYPRE = 'Cypress Flats', DAVIS = 'Davis', DELBE = 'Del Perro Beach',
    DELPE = 'Del Perro', DELSOL = 'La Puerta', DESRT = 'Grand Senora Desert',
    DOWNT = 'Downtown', DTVINE = 'Downtown Vinewood', EAST_V = 'East Vinewood',
    EBURO = 'El Burro Heights', ELGORL = 'El Gordo Lighthouse', ELYSIAN = 'Elysian Island',
    GALFISH = 'Galilee', GOLF = 'GWC and Golfing Society', GRAPES = 'Grapeseed',
    GREATC = 'Great Chaparral', HARMO = 'Harmony', HAWICK = 'Hawick',
    HORS = 'Vinewood Racetrack', HUMLAB = 'Humane Labs and Research', JAIL = 'Bolingbroke Penitentiary',
    KOREAT = 'Little Seoul', LACT = 'Land Act Reservoir', LAGO = 'Lago Zancudo',
    LDAM = 'Land Act Dam', LEGSQU = 'Legion Square', LMESA = 'La Mesa',
    LOSPUER = 'La Puerta', MIRR = 'Mirror Park', MORN = 'Morningwood',
    MOVIE = 'Richards Majestic', MTCHIL = 'Mount Chiliad', MTGORDO = 'Mount Gordo',
    MTJOSE = 'Mount Josiah', MURRI = 'Murrieta Heights', NCHU = 'North Chumash',
    NOOSE = 'N.O.O.S.E', OCEANA = 'Pacific Ocean', PALCOV = 'Paleto Cove',
    PALETO = 'Paleto Bay', PALFOR = 'Paleto Forest', PALHIGH = 'Palomino Highlands',
    PALMPOW = 'Palmer-Taylor Power Station', PBLUFF = 'Pacific Bluffs', PBOX = 'Pillbox Hill',
    PROCOB = 'Procopio Beach', RANCHO = 'Rancho', RGLEN = 'Richman Glen',
    RICHM = 'Richman', ROCKF = 'Rockford Hills', RTRAK = 'Redwood Lights Track',
    SANAND = 'San Andreas', SANCHIA = 'San Chianski Mountain Range', SANDY = 'Sandy Shores',
    SKID = 'Mission Row', SLAB = 'Stab City', STAD = 'Maze Bank Arena',
    STRAW = 'Strawberry', TATAMO = 'Tataviam Mountains', TERMINA = 'Terminal',
    TEXTI = 'Textile City', TONGVAH = 'Tongva Hills', TONGVAV = 'Tongva Valley',
    VCANA = 'Vespucci Canals', VESP = 'Vespucci', VINE = 'Vinewood',
    WINDF = 'Ron Alternates Wind Farm', WVINE = 'West Vinewood', ZANCUDO = 'Zancudo River',
    ZP_ORT = 'Port of South Los Santos', ZQ_UAR = 'Davis Quartz', PROL = 'Prologue / North Yankton',
    ISHeist = 'Cayo Perico Island',
}

---Scans every active native blip server-wide (see this file's header for
---the technique and its real limitations) into a flat list for the NUI Map
---tab's Locations panel. Called fresh each time that panel is opened (see
---client/main.lua's showNui) rather than cached -- blips genuinely come and
---go (garages, job depots that only exist mid-shift, etc), and the scan is
---a few thousand cheap native calls, not something worth caching staleness
---bugs to save.
function GK.ScanBlips()
    local out = {}
    for sprite = 0, MAX_SPRITE do
        if not EXCLUDED_SPRITES[sprite] then
            local blip = GetFirstBlipInfoId(sprite)
            while DoesBlipExist(blip) do
                if GetBlipInfoIdType(blip) == BLIP_TYPE_COORD then
                    local coords = GetBlipCoords(blip)
                    local zoneCode = GetNameOfZone(coords.x, coords.y, coords.z)
                    out[#out + 1] = {
                        sprite = sprite,
                        colour = GetBlipColour(blip),
                        coords = { x = coords.x, y = coords.y, z = coords.z },
                        zone = ZONE_NAMES[zoneCode] or zoneCode,
                    }
                end
                blip = GetNextBlipInfoId(sprite)
            end
        end
    end
    return out
end
