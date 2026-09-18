--[[
    Score detection.

    A hoop is a horizontal circle in the world. A shot counts when the ball crosses
    that circle's plane travelling downward, inside the rim radius.

    Because a hard shot can cover several metres in a single frame, we never test
    "is the ball inside the rim right now" — we take the segment between the ball's
    previous and current position and work out where it punched through the plane.
    That makes detection frame-rate independent and immune to tunnelling.

    Only the client that released the ball tracks it, so exactly one client reports
    each basket. The server still de-duplicates and sanity-checks.
]]

local tracked = {}      -- [netId] = { prev, origin, hoop, accuracy, expires, primed }

--- Starts watching a ball that was just released.
--- @param netId number
--- @param origin vector3 Where the shooter stood when they let go (decides 2 vs 3)
--- @param hoop table|nil The hoop the shot was aimed at, if any
--- @param accuracy number
--- @param aiId number|nil Set when this client is driving an NPC that took the shot,
---        so the basket is credited to the NPC rather than to me.
function BB.trackShot(netId, origin, hoop, accuracy, aiId)
    tracked[netId] = {
        prev     = nil,
        origin   = origin,
        hoop     = hoop,
        accuracy = accuracy,
        aiId     = aiId,
        expires  = GetGameTimer() + Config.Scoring.maxTrackTime * 1000,
        primed   = {},
    }
end

function BB.untrackShot(netId)
    tracked[netId] = nil
end

--- Where a segment crosses a horizontal plane, or nil if it doesn't cross downward.
local function crossingPoint(from, to, planeZ)
    if from.z <= planeZ or to.z > planeZ then return nil end

    local span = from.z - to.z
    if span < 0.0001 then return nil end

    local t = (from.z - planeZ) / span

    return vec3(
        from.x + (to.x - from.x) * t,
        from.y + (to.y - from.y) * t,
        planeZ
    )
end

local function pointsFor(origin, hoop)
    return BB.dist2d(origin, hoop.coords) >= Config.Scoring.threePointDistance and 3 or 2
end

CreateThread(function()
    local scoring = Config.Scoring

    while true do
        local wait = 250

        if next(tracked) then
            wait = 0
            local now = GetGameTimer()
            local hoops = BB.nearbyHoops()

            for netId, shot in pairs(tracked) do
                local ball = NetworkDoesNetworkIdExist(netId) and NetToObj(netId) or 0

                if now > shot.expires or ball == 0 or not DoesEntityExist(ball) then
                    tracked[netId] = nil
                else
                    local pos = GetEntityCoords(ball)

                    if shot.prev then
                        for _, hoop in ipairs(hoops) do
                            local rimZ = hoop.coords.z

                            -- A ball can only score if it got above the rim while
                            -- outside the cylinder, i.e. it arrived over the top.
                            -- Without this you could score by punching one up
                            -- through the net from underneath.
                            if pos.z > rimZ + 0.08 and BB.dist2d(pos, hoop.coords) > scoring.rimRadius then
                                shot.primed[hoop.id] = true
                            end

                            if shot.primed[hoop.id] then
                                local hit = crossingPoint(shot.prev, pos, rimZ)

                                if hit and BB.dist2d(hit, hoop.coords) <= scoring.rimRadius then
                                    tracked[netId] = nil

                                    TriggerServerEvent('gk_basketball:scored', {
                                        court  = hoop.court,
                                        hoop   = hoop.id,
                                        netId  = netId,
                                        points = pointsFor(shot.origin, hoop),
                                        aiId   = shot.aiId,
                                        -- The server re-derives distance from my ped
                                        -- position; this is only for the swish flavour.
                                        clean  = shot.accuracy >= 0.9,
                                    })

                                    break
                                end
                            end
                        end
                    end

                    if tracked[netId] then
                        shot.prev = pos
                    end
                end
            end
        end

        Wait(wait)
    end
end)
