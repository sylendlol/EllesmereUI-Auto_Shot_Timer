if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIAutoShot.lua  (v2)
--  Dworak > Auto Shot Timer: a Hunter Auto Shot bar with the wind-up window.
--
--  Files (TOC order):
--    EllesmereUIAutoShot.lua   settings store + shared helpers (this file)
--    AutoShot_Engine.lua       the timing: when the next shot really comes
--    AutoShot_Bar.lua          the bar, the options page, Unlock Mode, /autoshot
--    AutoShot_CastExtras.lua   two rows in Resource Bars > Cast Bar > EXTRAS
--
--  The timing model follows AppelSwingsForever 1.7.2 by Appel (its measured
--  Forever server rules: haste-scaled wind-up, the server's 0.5s retries,
--  moves that cancel a wind-up, the switch-on delay, melee / Feign Death
--  restarts, Quick Shots, the clip readout). Re-implemented here for one
--  EllesmereUI bar; no code is shared with it and it is not needed.
--  No EllesmereUI file is changed.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local DW = EllesmereUIDworak
if not DW then return end -- the Dworak core is off: nothing to register into

ns.FOLDER = ADDON_NAME
ns.DW = DW

ns.DEFAULTS = {
    profile = {
        asEnabled    = false,
        asHunterOnly = true,        -- off: also Shoot / Throw of other classes
        -- Timing
        asWindup     = 0.5,         -- unhasted wind-up (Blizzard's 0.5); scaled by ranged haste
        asLatency    = true,        -- the window starts one ping + 0.10s earlier
        asLatencyOfs = 0,           -- ms added to the latency compensation (-100..200)
        asMeleeReset = true,        -- a melee swing restarts the reload (Forever)
        asHideIdle   = true,
        -- Display
        asWidth = 220, asHeight = 14,
        asTexture    = "none",      -- EllesmereUI bar texture key
        asMatchLook  = false,       -- texture, background and border from the player cast bar
        asFont       = "__global",
        asTextSize   = 11,
        asShowLabel  = true,
        asShowTime   = true,
        asShowSpark  = true,
        asGlow       = true,        -- afterglow on every shot
        asBorder     = 1,           -- px, 0 = none
        asBorderR = 0, asBorderG = 0, asBorderB = 0,
        asBgR = 0.05, asBgG = 0.05, asBgB = 0.05, asBgA = 0.6,
        -- Markers
        asShowWindow = true,        -- the wind-up window (line + tinted zone)
        asMoveLine   = true,        -- the "you may move now" line
        asClip       = true,        -- "+0.12" after every shot (Text Size)
        -- Colours
        asReloadColor = "accent",   -- "accent" = UI Accent Color, "custom" = asReloadR/G/B
        asReloadR = 0.80, asReloadG = 0.80, asReloadB = 0.80,
        asWindowR = 0.25, asWindowG = 0.85, asWindowB = 0.35,
        asBlockedR = 0.95, asBlockedG = 0.25, asBlockedB = 0.20,
        asMoveR = 0.45, asMoveG = 0.75, asMoveB = 1.00,
        -- Position
        asAttach     = false,
        asAttachSide = "below",
        asAttachGap  = 2,
        asMatchWidth = true,
        -- asPosition: Unlock Mode; asReloads: [bow itemID | "any"] = slowest reload seen
    },
}
local DEFAULTS = ns.DEFAULTS.profile

local SV_NAME = "EllesmereUIAutoShotDB"
local db = EllesmereUI.Lite.NewDB(SV_NAME, ns.DEFAULTS)

local function DB()
    local active = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
    if db._profileName ~= active then
        db = EllesmereUI.Lite.NewDB(SV_NAME, ns.DEFAULTS)
    end
    return db.profile
end
ns.DB = DB

function ns.Get(key)
    local v = DB()[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

function ns.Set(key, value)
    DB()[key] = value
end

-- Secret values throw on comparison and truth tests: every read passes here.
function ns.Plain(v)
    return not (issecretvalue and issecretvalue(v))
end

function ns.Accent()
    local c = EllesmereUI.ELLESMERE_GREEN
    if c and c.r then return c.r, c.g, c.b end
    return 0.05, 0.82, 0.62
end

function ns.AccentHex()
    local r, g, b = ns.Accent()
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

local _, CLASS = UnitClass("player")
ns.CLASS = CLASS

function ns.Enabled() return ns.Get("asEnabled") == true end
function ns.Active()
    return ns.Enabled() and (not ns.Get("asHunterOnly") or CLASS == "HUNTER")
end

function ns.Print(t)
    EllesmereUI.Print(ns.AccentHex() .. "Auto Shot Timer:|r " .. t)
end
