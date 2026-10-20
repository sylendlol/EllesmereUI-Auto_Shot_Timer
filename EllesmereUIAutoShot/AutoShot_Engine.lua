if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIAutoShot \ AutoShot_Engine.lua
--  The timing: when the next Auto Shot really comes, from what the Forever
--  client tells addons (12.0: no combat log). Rules and numbers measured by
--  AppelSwingsForever 1.7.2 (/asf log, 2026-10-16/17); see its Swing.lua.
--
--  The bar (R): one reload per shot, from PLAYER_SWING (type Ranged, hasted).
--  The wind-up: the reload's last part, where moving holds the shot back:
--    pure  = 0.5s * this reload / the bow's printed speed (= scaled by haste)
--    block = pure + (ping + 0.10s)  with Latency Compensation: the last moment
--            to be standing, since a stop reaches the server a ping later.
--  A late shot (R.lapEnd, "due"): the server retries every 0.5s after a failed
--  try (UNIT_SPELLCAST_FAILED_QUIET), a move inside the running wind-up
--  cancels it (next try 0.70s after the move), a stop too late misses the try,
--  a switch-on fires a wind-up + ping + 0.07s after the press.
--  Restarts with no ranged event: a melee swing, getting up from Feign Death.
--  Quick Shots (+30%): a player UNIT_AURA in the same frame as a shot.
--
--  Only state here; the bar reads it every frame (AutoShot_Bar.lua) and is
--  woken through ns.Wake() whenever something changed.
-------------------------------------------------------------------------------
local _, ns = ...
if not ns.DW then return end

local Get, Plain = ns.Get, ns.Plain

local E = {}
ns.E = E

local C = {
    AUTO_RETRY    = 0.5,   -- the server's retry after a failed try
    CANCEL_RETRY  = 0.70,  -- next try after a move cancelled the running wind-up
    ON_SETTLE     = 0.15,  -- a switch-on counts once Auto Shot stayed on this long
    AUTO_FLICKER  = 0.5,   -- off for less than this (a cast flicks it): no switch-on
    MOVE_JUST_NOW = 0.15,  -- a stop this close to a shot belongs to the new reload
    QS_HASTE      = 1.3, QS_DURATION = 12, QS_END_SLOP = 0.15,
    SHOT_GRACE    = 0.25,  -- the bar stays full this long after the reload, in combat
    PRESS_NEAR    = 0.05, PRESS_KEEP = 5, ON_PRESS = 1,
    SWITCH_EXTRA  = 0.12,  -- switch-on: wind-up + ping + this (0.07 measured +0.08 late on average, 2026-10-20)
    PING_FALLBACK = 0.12,
    RANGED_SLOT   = 18,
    AUTO_SHOT     = 75,
    FEIGN_DEATH   = 5384,
}
E.C = C

local RANGED = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.Ranged) or 2
local SHOT_IDS = { [75] = true, [5019] = true, [3018] = true, [2764] = true } -- Auto Shot, Shoot, Shoot (bow), Throw

-- R: the running ranged reload. start/dur 0 = none known.
--   wuShift (Quick Shots on this reload), lapAt/lapEnd (a late shot: due at
--   lapEnd), waited (why, for /autoshot log), solo (switched on from idle: no
--   reload under the first shot), movedSince (moved during this reload),
--   moveFrom, skippedFor, onAt, onFirstPress, onMoving (switch-on bits).
local R = { start = 0, dur = 0 }
E.R = R

-- G: the rest of the world as the events told it.
local G = {
    moving = false, moveStopAt = -1, casting = false, inCombat = false,
    auto = nil, autoOffAt = 0, pendingOn = nil,
    pressIDs = {}, lastFailID = nil, feigning = false,
    qsEndAt = 0, auraAt = -1, shotAt = -1,
    lastShotAt = nil, lastShotDur = nil, clip = nil, combatAt = -10, openerAt = -10,
    log = false,
}
E.G = G

local function Wake() if ns.Wake then ns.Wake() end end

local function Readable(v) return v ~= nil and Plain(v) end

-- /autoshot log: the moves and failed tries between shots, timed from the
-- last shot, with where the bar now puts the shot.
local function Log(what)
    if not G.log then return end
    local now = GetTime()
    local due = (R.start > 0 and R.dur > 0) and math.max(R.start + R.dur, R.lapEnd or 0) or nil
    ns.Print(string.format("  %+.2fs %s%s", G.lastShotAt and (now - G.lastShotAt) or 0, what,
        due and string.format(" (bar: shot in %.2fs)", due - now) or ""))
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and Readable(n) then return n end
    end
end

local AUTO_SHOT_NAME
local function IsShot(id)
    if not (type(id) == "number" and Readable(id)) then return false end
    if SHOT_IDS[id] then return true end
    AUTO_SHOT_NAME = AUTO_SHOT_NAME or SpellName(C.AUTO_SHOT)
    return AUTO_SHOT_NAME ~= nil and SpellName(id) == AUTO_SHOT_NAME
end

-------------------------------------------------------------------------------
--  Ping, the bow, the wind-up
-------------------------------------------------------------------------------
do
    local pingAt, ping = -1, C.PING_FALLBACK
    local function Num(v) return Readable(v) and type(v) == "number" and v > 0 and v < 2000 and v or nil end
    -- World round trip in seconds, read at most once a second.
    function E.Ping()
        local now = GetTime()
        if now - pingAt < 1 then return ping end
        pingAt = now
        local ok, _, _, home, world = pcall(GetNetStats)
        local ms = ok and (Num(world) or Num(home)) or nil
        if ms then ping = ms / 1000 end
        return ping
    end
end

-- How long before the shot a move still reaches the server in time.
function E.MoveWindow() return E.Ping() + 0.10 end

do
    local bowKey
    function E.BowKey()
        if bowKey == nil then
            local id = GetInventoryItemID and GetInventoryItemID("player", C.RANGED_SLOT)
            bowKey = (Readable(id) and id) or "any"
        end
        return bowKey
    end

    -- The bow's printed speed (tooltip, right column): no haste, slow or
    -- quiver changes it, so reload / printed speed = ranged haste.
    local function ParseSpeed(t, bare)
        if type(t) ~= "string" or not Plain(t) then return nil end
        t = t:gsub(",", ".")
        local s
        if bare then
            s = t:match("^%s*(%d+%.%d+)%s*$")
        else
            local i = (SPEED and t:find(SPEED, 1, true)) or t:find("Speed", 1, true)
            s = i and t:match("(%d+%.?%d*)", i)
        end
        local n = tonumber(s)
        if n and n > 0.5 and n < 10 then return n end
    end
    local function ReadSpeed()
        local d = C_TooltipInfo and C_TooltipInfo.GetInventoryItem("player", C.RANGED_SLOT)
        if not (d and d.lines) then return nil end
        for pass = 1, 2 do
            for _, l in ipairs(d.lines) do
                local n = ParseSpeed(l.rightText, pass == 2)
                if n then return n end
            end
        end
    end
    local speedKey, speed, retryAt = nil, nil, 0
    function E.BowSpeed()
        local key = E.BowKey()
        if key ~= speedKey or (not speed and GetTime() >= retryAt) then
            speedKey = key
            local ok, v = pcall(ReadSpeed)
            speed = ok and v or nil
            -- Item data not loaded yet (login): try again in half a second.
            if not speed then retryAt = GetTime() + 0.5 end
        end
        return speed
    end
    function E.ForgetBow() bowKey, speedKey, speed = nil, nil, nil end
end

-- The extra on top of the wind-up (Latency Compensation).
function E.Extra()
    if Get("asLatency") == false then return 0 end
    return math.max(0, E.MoveWindow() + (tonumber(Get("asLatencyOfs")) or 0) / 1000)
end

-- For a reload of dur: block (where to be standing by, seconds before the
-- shot), pure (the server's wind-up alone).
function E.Windup(dur)
    local base = tonumber(Get("asWindup")) or 0.5
    local extra = E.Extra()
    if not dur or dur <= 0 then return base + extra, base end
    local spd = E.BowSpeed()
    local pure = spd and (base * dur / spd) or base
    return pure + extra, pure
end

-- The running reload's block and pure, a Quick Shots shift included.
function E.RunBlock()
    local s = R.wuShift or 0
    local block, pure = E.Windup(R.dur - s)
    return block + s, pure + s
end

-------------------------------------------------------------------------------
--  Reload memory (UnitRangedDamage is unreadable in combat on Forever): per
--  bow the slowest reload seen this session, kept in the profile.
-------------------------------------------------------------------------------
local sessionMax = {}

local function NoteReload(dur)
    local k = E.BowKey()
    if sessionMax[k] and dur <= sessionMax[k] then return end
    sessionMax[k] = dur
    local p = ns.DB()
    local t = p.asReloads
    if type(t) ~= "table" then
        t = {}
        p.asReloads = t
    end
    t[k] = dur
    t.any = dur
end

function E.SavedReload()
    local t = ns.DB().asReloads
    if type(t) ~= "table" then return nil end
    return t[E.BowKey()] or t.any
end

-- The live speed out of combat; nil when unreadable (in combat: secret).
local function UsableSpeed()
    local s = UnitRangedDamage("player")
    if type(s) == "number" and s > 0.5 and s < 10 then return s end
end
function E.LiveReload()
    if not UnitRangedDamage then return nil end
    local ok, v = pcall(UsableSpeed)
    return ok and v or nil
end

-- A reload length to draw with when none is running.
function E.RefDur()
    if R.dur > 0 then return R.dur end
    return E.LiveReload() or E.SavedReload() or 3
end

-------------------------------------------------------------------------------
--  Late shots ("the lap")
-------------------------------------------------------------------------------
local function StartLap(at, shot, why)
    R.lapAt, R.lapEnd = at, shot
    R.waited = why
end

-- A failed try at now: the shot is the next try plus the wind-up.
local function Retry(now, why)
    local _, pure = E.RunBlock()
    StartLap(now, now + C.AUTO_RETRY + pure, why)
end

-- Restarted with no shot (melee swing, Feign Death): a full reload from now.
local function RestartRanged(now, why)
    R.dur = R.dur - (R.wuShift or 0)
    R.wuShift, R.lapAt, R.lapEnd, R.solo = nil, nil, nil, nil
    if R.dur <= 0 then R.dur = E.SavedReload() or 0 end
    if R.dur > 0 then
        R.start = now
        R.waited = why
    end
    Wake()
end

-- Moves the server reports no failure for: a move in the running wind-up
-- cancels it; a stop that cannot reach the server before the try misses it
-- (and every try 0.5s apart until one it reaches).
local function LapOnMove(started, now)
    if G.auto == false or R.dur <= 0 or R.start <= 0 then return end
    local _, pure = E.RunBlock()
    local shot = math.max(R.start + R.dur, R.lapEnd or 0)
    local try = shot - pure
    if started then
        R.moveFrom = now
        if now >= try and now < shot and shot - now >= E.MoveWindow() then
            StartLap(now, now + C.CANCEL_RETRY + pure, "a move cancelled the wind-up")
        end
        return
    end
    -- The server starts the wind-up once the stop reaches it (stop + ping +
    -- 0.10), not on its next 0.5s retry (the user's /autoshot log 2026-10-20:
    -- stops at +2.25 / +2.09, shots at +2.98 / +2.83, the 0.5s grid said
    -- +3.09 / +2.96, this rule +2.93 / +2.77). Only when the stop reaches
    -- it after the wind-up should have begun; a stop in time changes nothing.
    -- Measured against the reload's own wind-up start, not the 0.5s grid: a
    -- stop that reaches the server before the next retry starts the wind-up
    -- then too (earlier than the grid), one after it later.
    local reach = now + E.MoveWindow()
    local start = R.start + R.dur - pure
    if (R.moveFrom or now) < start and reach > start then
        StartLap(now, reach + pure, "the stop reached the server late")
    end
end

function E.MovedJustNow(now)
    return G.moving or now - G.moveStopAt < C.MOVE_JUST_NOW
end

-- The switch-on, as of the press at now.
local function ApplyStart(now)
    -- Off only for a moment (a cast flicks it): the server kept shooting.
    if now - G.autoOffAt < C.AUTO_FLICKER then
        R.onFirstPress = false
        return
    end
    R.onAt = now
    if R.lapAt and R.lapAt < now then R.lapAt, R.lapEnd = nil, nil end
    R.solo = nil
    if R.dur <= 0 then R.dur = E.SavedReload() or E.LiveReload() or 0 end
    if R.dur <= 0 then return end
    if R.start <= 0 or R.start + R.dur <= now then
        -- From idle: no reload to wait out, only the first shot's wind-up.
        R.solo = true
        if R.wuShift then R.dur, R.wuShift = R.dur - R.wuShift, nil end
        -- A fresh start: a proc noted on an old reload says nothing about this one.
        R.qsProc = nil
        local live = E.LiveReload()
        if live and math.abs(live - R.dur) >= 0.02 then R.dur = live end
        R.start = now - R.dur
    end
    -- Switched on while moving: the first try fails; its failure starts the lap.
    if R.solo and R.onMoving then return end
    local _, pure = E.RunBlock()
    local shot = now + pure + E.Ping() + C.SWITCH_EXTRA
    if shot > math.max(R.start + R.dur, R.lapEnd or 0) then StartLap(now, shot, "switch-on") end
end

-------------------------------------------------------------------------------
--  Quick Shots (buffs are secret in combat; the aura event's timing is not)
-------------------------------------------------------------------------------
local function Shift(by, why)
    R.dur = R.dur + by
    R.wuShift = (R.wuShift or 0) + by
    R.qsNote = why
end

-- QS_COMBAT: entering combat changes player auras too (2026-10-20 log: a
-- "proc" on the pull shot, the next reload not hasted): none counts then.
local QS_COMBAT = 0.5
local function QsOnShotFrame(now)
    if math.abs(now - G.combatAt) < QS_COMBAT or now == G.openerAt then return end
    local active = now < G.qsEndAt
    if active and now >= G.qsEndAt - C.QS_END_SLOP then return end -- ran out on a shot frame
    G.qsEndAt = now + C.QS_DURATION
    if active or R.dur <= 0 then return end -- a refresh: the haste stays
    local _, pure = E.RunBlock()
    Shift(pure / C.QS_HASTE - pure, "Quick Shots proc")
    R.qsProc = true
end

-- Every bar frame: Quick Shots running out before this reload's wind-up.
function E.Tick(now)
    if G.qsEndAt == 0 or now < G.qsEndAt then return end
    G.qsEndAt = 0
    if not (R.dur > 0 and R.start > 0) then return end
    local _, pure = E.RunBlock()
    if now < R.start + R.dur - pure then Shift(pure * C.QS_HASTE - pure, "Quick Shots ended") end
end

-------------------------------------------------------------------------------
--  What the bar reads
-------------------------------------------------------------------------------

-- The shot's time when it is late (past the reload's end), else nil.
function E.Due()
    if R.dur <= 0 or R.start <= 0 then return nil end
    local e = R.start + R.dur
    if R.lapEnd and R.lapEnd > e then return R.lapEnd end
end

-- Whether the bar stays full after its reload ran out: a shot is still coming.
function E.RangedFull(now)
    if R.dur <= 0 or R.start <= 0 or now < R.start + R.dur then return false end
    if G.auto or now - G.autoOffAt < C.AUTO_FLICKER then return true end
    if not G.inCombat then return false end
    return G.auto == nil or now - (R.start + R.dur) < C.SHOT_GRACE
end

-- The firing light: 0..1 over the late shot's own wind-up (the one stretch
-- that is certain), nil before it or with no late shot.
function E.FireProgress(now)
    local due = E.Due()
    if not due then return nil end
    local _, pure = E.RunBlock()
    local from = math.max(due - pure, R.start + R.dur)
    if now < from or due <= from then return nil end
    return math.min(1, (now - from) / (due - from))
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local H = {}

H.PLAYER_SWING = function(dur, swingType)
    if not (Plain(dur) and Plain(swingType)) or type(dur) ~= "number" or dur <= 0 then return end
    local now = GetTime()
    if swingType ~= RANGED then
        -- Forever: every melee swing restarts the ranged reload, with no event for it.
        if Get("asMeleeReset") ~= false and R.dur > 0 and R.start > 0
            and (G.auto or now < R.start + R.dur) then
            RestartRanged(now, "a melee swing restarted the reload")
        end
        return
    end
    local clip, gap = 0, nil
    -- A gap of five reloads or more is a new fight, not a clip.
    if G.lastShotAt and now - G.lastShotAt < G.lastShotDur * 5 then
        gap = now - G.lastShotAt
        clip = math.max(0, gap - G.lastShotDur)
    end
    -- Where the bar said the shot would be (+ = the shot came after the bar's end).
    local barErr
    if R.start > 0 and R.dur > 0 and (G.auto ~= false) then
        barErr = now - (E.Due() or (R.start + R.dur))
    end
    -- A Quick Shots proc is real only if this reload came back hasted.
    local falseQs
    if R.qsProc then
        local base = R.dur - (R.wuShift or 0)
        if dur > base / 1.15 then
            G.qsEndAt = 0
            falseQs = true
        end
    end
    -- The fight's first shot (the pull): its aura changes are not Quick Shots.
    if not gap then G.openerAt = now end
    local waited, qs = R.waited, R.qsNote
    G.lastShotAt, G.lastShotDur, G.clip = now, dur, clip
    R.start, R.dur = now, dur
    R.wuShift, R.lapAt, R.lapEnd, R.waited, R.solo, R.qsNote, R.qsProc = nil, nil, nil, nil, nil, nil, nil
    R.skippedFor, R.moveFrom = nil, nil
    -- Reported half a ping after it fired: a move in that gap is this reload's.
    R.movedSince = E.MovedJustNow(now) or nil
    NoteReload(dur)
    G.shotAt = now
    if G.auraAt == now then QsOnShotFrame(now) end
    if G.log then
        ns.Print(string.format("shot: %s, reload %.2fs, clip %+.2fs, bar %s%s%s%s",
            gap and string.format("%.2fs after the last", gap) or "first",
            dur, clip, barErr and string.format("%+.2fs", barErr) or "-",
            waited and (" - " .. waited) or "", qs and (" - " .. qs) or "",
            falseQs and " - that Quick Shots was a false alarm" or ""))
    end
    if ns.OnShot then ns.OnShot(clip) end
    Wake()
end

H.PLAYER_STARTED_MOVING = function()
    local now = GetTime()
    G.moving = true
    LapOnMove(true, now)
    Log("move")
    -- Any move in a reload hides the move line until the next shot.
    R.movedSince = true
    if G.feigning then
        G.feigning = false
        RestartRanged(now, "got up from Feign Death")
    end
    Wake()
end

H.PLAYER_STOPPED_MOVING = function()
    local now = GetTime()
    G.moving, G.moveStopAt = false, now
    LapOnMove(false, now)
    Log("stop")
    Wake()
end

H.START_AUTOREPEAT_SPELL = function()
    if G.auto then return end -- spamming !Auto Shot while it is on
    if not G.pendingOn then
        R.onFirstPress = (GetTime() - G.autoOffAt < C.AUTO_FLICKER) and false or nil
        R.onMoving = G.moving
    end
    G.pendingOn = G.pendingOn or GetTime()
    local at = G.pendingOn
    C_Timer.After(C.ON_SETTLE, function()
        if G.pendingOn ~= at then return end
        G.pendingOn, G.auto = nil, true
        ApplyStart(at)
        Wake()
    end)
    Wake()
end

H.STOP_AUTOREPEAT_SPELL = function()
    -- Back off before it counted: as if it never came on.
    if G.pendingOn then
        G.pendingOn = nil
        Wake()
        return
    end
    G.auto, G.autoOffAt = false, GetTime()
    Wake()
end

-- unit, target, cast ID, spell ID
H.UNIT_SPELLCAST_SENT = function(_, _, guid, spellID)
    if not IsShot(spellID) then
        if G.feigning and Readable(spellID) and spellID ~= C.FEIGN_DEATH then G.feigning = false end
        return
    end
    if not Readable(guid) then return end
    local now = GetTime()
    for id, at in pairs(G.pressIDs) do
        if now - at > C.PRESS_KEEP then G.pressIDs[id] = nil end
    end
    G.pressIDs[guid] = now
    -- The first press at a switch-on: its failure is a real failed try.
    if R.onFirstPress == nil and (G.pendingOn or (R.onAt and G.auto and now - R.onAt < C.ON_PRESS)) then
        R.onFirstPress = guid
    end
end

local function PressedNear(now, secs)
    for _, at in pairs(G.pressIDs) do
        if math.abs(now - at) <= secs then return true end
    end
    return false
end

-- unit, cast ID, spell ID. Each failure comes twice: only the first is read.
H.UNIT_SPELLCAST_FAILED_QUIET = function(_, guid, spellID)
    if not (IsShot(spellID) and Readable(guid)) then return end
    if guid == G.lastFailID then return end
    G.lastFailID = guid
    local now = GetTime()
    local pressAt = G.pressIDs[guid]
    if pressAt and now - pressAt <= C.PRESS_KEEP then
        -- Your own press: a failed try only at the switch-on, in its own frame.
        if R.onFirstPress == guid and now - pressAt <= C.PRESS_NEAR and R.dur > 0 and R.start > 0 then
            R.onFirstPress = false
            Retry(now, "your switch-on press failed: retry in 0.5s")
            Log("failed: your switch-on press, counted")
            Wake()
        else
            Log("failed: your press, ignored")
        end
        return
    end
    if G.auto == false then return Log("failed: Auto Shot is off, ignored") end
    if R.dur <= 0 or R.start <= 0 then return Log("failed: no reload known yet, ignored") end
    -- In the frame of a press: the press took over.
    if PressedNear(now, C.PRESS_NEAR) then return Log("failed: at your press, ignored") end
    -- A failure right after a stop is real: the server's try came before the
    -- stop reached it, and it tries again 0.5s later (2026-10-20 log: a
    -- failure 0.21s after the stop, the shot 0.92s after it). It overrides the
    -- stop's own guess (LapOnMove), so it is counted below.
    -- After a stop the server can still report one stale failure during the wind-up.
    if not G.moving and now - G.moveStopAt > E.MoveWindow() + 0.15 and now - G.moveStopAt < 1
        and R.skippedFor ~= G.moveStopAt then
        R.skippedFor = G.moveStopAt
        return Log(string.format("failed: %.2fs after your stop, taken as stale, ignored", now - G.moveStopAt))
    end
    local _, pure = E.RunBlock()
    if now + C.AUTO_RETRY + pure <= R.start + R.dur then return Log("failed: mid-reload, no change") end
    Retry(now, G.moving and "server retry (moving)"
        or (G.casting and "server retry (casting)")
        or "server retry (standing: range, facing, line of sight)")
    Log(G.moving and "failed while moving, counted" or "failed, counted")
    Wake()
end

H.UNIT_SPELLCAST_SUCCEEDED = function(_, _, spellID)
    if not Readable(spellID) then return end
    if spellID == C.FEIGN_DEATH then
        G.feigning = true
    elseif not IsShot(spellID) then
        G.casting = false
    end
end

local function CastStart(_, _, spellID)
    if not (Readable(spellID) and IsShot(spellID)) then
        G.casting = true
        Wake()
    end
end
local function CastEnd(_, _, spellID)
    if not (Readable(spellID) and IsShot(spellID)) then
        G.casting = false
        Wake()
    end
end
H.UNIT_SPELLCAST_START = CastStart
H.UNIT_SPELLCAST_CHANNEL_START = CastStart
H.UNIT_SPELLCAST_STOP = CastEnd
H.UNIT_SPELLCAST_FAILED = CastEnd
H.UNIT_SPELLCAST_INTERRUPTED = CastEnd
H.UNIT_SPELLCAST_CHANNEL_STOP = CastEnd

H.UNIT_AURA = function()
    G.auraAt = GetTime()
    if G.auraAt == G.shotAt then QsOnShotFrame(G.auraAt) end
end

H.PLAYER_REGEN_DISABLED = function()
    G.inCombat, G.combatAt = true, GetTime()
end
H.PLAYER_REGEN_ENABLED = function()
    G.inCombat = false
    G.lastShotAt, G.lastShotDur, G.clip = nil, nil, nil
    if ns.OnClipClear then ns.OnClipClear() end
    Wake()
end

H.PLAYER_EQUIPMENT_CHANGED = function() E.ForgetBow() end

H.PLAYER_DEAD = function()
    R.start, R.lapAt, R.lapEnd, R.solo = 0, nil, nil, nil
    G.auto, G.pendingOn, G.casting, G.feigning = false, nil, false, false
    Wake()
end

-- A loading screen can swallow the movement and auto-repeat edges: ask.
H.PLAYER_ENTERING_WORLD = function()
    E.ForgetBow()
    local ok, speed = pcall(GetUnitSpeed, "player")
    if ok and not Plain(speed) then ok = false end
    G.moving = ok and type(speed) == "number" and speed > 0 or false
    G.casting = false
    G.inCombat = UnitAffectingCombat and Plain(UnitAffectingCombat("player")) and UnitAffectingCombat("player") or false
    local okA, on
    if C_Spell and C_Spell.IsAutoRepeatSpell then
        okA, on = pcall(C_Spell.IsAutoRepeatSpell, C.AUTO_SHOT)
    elseif IsAutoRepeatSpell then
        okA, on = pcall(IsAutoRepeatSpell, SpellName(C.AUTO_SHOT) or "Auto Shot")
    end
    G.auto = nil
    if okA and Plain(on) and type(on) == "boolean" then G.auto = on end
    Wake()
end

local EVENTS = {
    "PLAYER_SWING", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
    "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_DEAD", "PLAYER_ENTERING_WORLD",
}
local UNIT_EVENTS = {
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
}

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
    local fn = H[event]
    if fn then fn(...) end
end)

local on = false
-- On while the timer is active; off: no events at all.
function E.Enable(want)
    want = want and true or false
    if want == on then return end
    on = want
    frame:UnregisterAllEvents()
    if not want then return end
    for _, ev in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, ev) end
    for _, ev in ipairs(UNIT_EVENTS) do pcall(frame.RegisterUnitEvent, frame, ev, "player") end
    if ns.CLASS == "HUNTER" then pcall(frame.RegisterUnitEvent, frame, "UNIT_AURA", "player") end
    H.PLAYER_ENTERING_WORLD()
end

-- /autoshot debug
function E.Debug()
    local now = GetTime()
    local block, pure = E.RunBlock()
    local spd = E.BowSpeed()
    local P = ns.Print
    P(string.format("ping %.0f ms, move window %.2fs, bow %s, printed speed %s",
        E.Ping() * 1000, E.MoveWindow(), tostring(E.BowKey()), spd and string.format("%.2f", spd) or "unknown"))
    P(string.format("reload %.2fs (saved %s, live %s), wind-up %.2fs, block %.2fs",
        R.dur, tostring(E.SavedReload() and string.format("%.2f", E.SavedReload())),
        tostring(E.LiveReload() and string.format("%.2f", E.LiveReload())), pure, block))
    P("auto = " .. tostring(G.auto) .. ", moving = " .. tostring(G.moving) .. ", casting = " .. tostring(G.casting)
        .. ", combat = " .. tostring(G.inCombat) .. ", Quick Shots = " .. tostring(G.qsEndAt > now))
    local due = E.Due()
    P(R.start > 0 and string.format("last reload began %.1fs ago%s", now - R.start,
        due and string.format(", late shot due in %.2fs (%s)", due - now, tostring(R.waited)) or "")
        or "no reload yet")
    P("last clip = " .. (G.clip and string.format("%+.2f", G.clip) or "none")
        .. ", moved since the shot = " .. tostring(R.movedSince) .. ", pending switch-on = " .. tostring(G.pendingOn ~= nil))
end
