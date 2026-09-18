-- Shared namespace. Every client/server file hangs its helpers off this so we
-- don't leak globals into the resource's Lua state.
BB = BB or {}

--- Global state key the hoops are published under. Shared so the server that
--- writes it and the client that reads it cannot disagree about the name.
BB.STATE_HOOPS = 'gk_basketball:hoops'

function BB.round(n, places)
    local mult = 10 ^ (places or 0)
    return math.floor(n * mult + 0.5) / mult
end

function BB.clamp(n, min, max)
    if n < min then return min end
    if n > max then return max end
    return n
end

--- 2D (ground plane) distance. Basketball is played on a floor, so almost every
--- distance question here wants to ignore height.
function BB.dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

function BB.vec(t)
    return vec3(t.x + 0.0, t.y + 0.0, t.z + 0.0)
end

function BB.plain(v)
    return { x = BB.round(v.x, 4), y = BB.round(v.y, 4), z = BB.round(v.z, 4) }
end

--- Groups a flat hoop list into courts and works out each court's centre.
--- Used identically on both sides, so it lives here.
--- @param hoops table Array of { id, court, coords, team? }
--- @return table courts Keyed by court id: { id, label, hoops = {}, centre = vec3 }
function BB.buildCourts(hoops)
    local courts = {}

    for _, hoop in ipairs(hoops or {}) do
        local id = hoop.court or 'court'
        local court = courts[id]

        if not court then
            court = {
                id    = id,
                label = (Config.Courts[id] and Config.Courts[id].label) or Config.Text.court_label,
                hoops = {},
            }
            courts[id] = court
        end

        court.hoops[#court.hoops + 1] = hoop
    end

    for _, court in pairs(courts) do
        local sx, sy, sz = 0.0, 0.0, 0.0
        for _, hoop in ipairs(court.hoops) do
            sx, sy, sz = sx + hoop.coords.x, sy + hoop.coords.y, sz + hoop.coords.z
        end
        local n = #court.hoops
        -- Drop the centre to roughly floor level; rims sit ~3m up and the centre
        -- is used for blips and the interaction zone.
        court.centre = vec3(sx / n, sy / n, (sz / n) - 2.6)
    end

    return courts
end

--- Picks the hoop a shot should target.
--- @param hoops table Array of hoops
--- @param from vector3 Shooter position
--- @param forward vector3 Shooter facing (normalised, z ignored)
--- @param maxRange number
--- @param team string|nil When set, hoops locked to the shooter's own team are skipped
--- @return table|nil hoop, number|nil distance
function BB.pickTargetHoop(hoops, from, forward, maxRange, team)
    local best, bestScore, bestDist

    --[[
        Flatten the aim direction onto the ground plane before comparing.

        Callers pass a camera vector whose x/y are already scaled by cos(pitch),
        and the facing test below dots it against a unit direction — so `facing`
        could never exceed cos(pitch). Looking up 60 degrees capped it at 0.5;
        past about 78 it could never clear the 0.2 threshold at all.

        Which meant aim assist got harder the more you aimed at the basket, and
        eventually dropped out entirely — sending the shot down the no-target
        path as a full-power loose toss, straight up and back down on your head.
    ]]
    local fLen = math.sqrt(forward.x * forward.x + forward.y * forward.y)
    if fLen < 0.0001 then return nil end

    local fx, fy = forward.x / fLen, forward.y / fLen

    for _, hoop in ipairs(hoops) do
        -- A hoop tagged with a team is that team's basket to defend, so you
        -- score on the other one. Untagged hoops are fair game (pickup rules).
        if not (team and hoop.team and hoop.team == team) then
            local dist = BB.dist2d(from, hoop.coords)

            if dist <= maxRange then
                local dx, dy = hoop.coords.x - from.x, hoop.coords.y - from.y
                local len = math.sqrt(dx * dx + dy * dy)
                -- Favour hoops in front of the player, then nearer ones. Both
                -- sides of this dot product are unit vectors on the ground plane,
                -- so it's a straight cosine of the angle off your aim — camera
                -- pitch doesn't enter into it.
                local facing = len > 0.01 and ((dx / len) * fx + (dy / len) * fy) or 1.0

                if facing > 0.2 then
                    local score = facing - (dist / maxRange) * 0.5
                    if not bestScore or score > bestScore then
                        best, bestScore, bestDist = hoop, score, dist
                    end
                end
            end
        end
    end

    return best, bestDist
end
