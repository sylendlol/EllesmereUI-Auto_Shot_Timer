if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIDworak.lua
--  Owns the "Dworak" sidebar section of the EllesmereUI panel. The Plugin API
--  (EllesmereUI\PLUGINS_API.md) gives one section per plugin and takes its
--  module list as a snapshot, so every Dworak addon hands its module spec to
--  this one, and the section is registered once, at login, with all of them.
--  Each Dworak addon stays independent: switch one off and only its row goes.
--
--  A Dworak addon:
--    ## Dependencies: EllesmereUI, EllesmereUIDworak
--    EllesmereUIDworak.AddModule({ key = "...", title = "...", order = 10, pages = {...},
--        buildPage = function(pageName, parent, yOffset) ... end, ... })
--    EllesmereUIDworak.Open("<key>")      -- from its slash command
--  The spec is a Plugin API module spec. The rows are listed alphabetically by
--  title. Optional: pin = true keeps a module above the alphabetical list
--  (pinned modules sort among themselves by order, lower first). order alone
--  no longer moves a row.
-------------------------------------------------------------------------------
local PLUGIN_ID = "EllesmereUIDworak"

EllesmereUIDworak = EllesmereUIDworak or {}
local D = EllesmereUIDworak

D.ID            = PLUGIN_ID
D.SECTION_LABEL = "Dworak"   -- EllesmereUI sidebar section
D.POSITION      = "top"      -- "top": above EUI's own sections, "bottom": below
D.UNLOCK_GROUP  = "Dworak"   -- group in EllesmereUI Unlock Mode

local specs, registered = {}, false

function D.AddModule(spec)
    if registered then
        geterrorhandler()("EllesmereUIDworak.AddModule(" .. tostring(spec and spec.key)
            .. "): too late, the Dworak section is registered at login.")
        return false
    end
    specs[#specs + 1] = spec
    return true
end

function D.Open(moduleKey, pageName)
    if InCombatLockdown() then
        EllesmereUI.Print((EllesmereUI.COLOR_CODES and EllesmereUI.COLOR_CODES.BRAND or "|cff0cd29d")
            .. "Dworak:|r the settings open after combat.")
        return false
    end
    return EllesmereUI.OpenPlugin and EllesmereUI.OpenPlugin(PLUGIN_ID, moduleKey, pageName) or false
end

-- Spec fields used only here; they are not passed on to the Plugin API.
local INTERNAL_KEYS = { order = true, pin = true, _dworakIndex = true, _dworakName = true }

-- The text the sidebar row shows, made comparable: colour codes and textures
-- removed, lower-cased, surrounding spaces trimmed.
local function SortName(spec)
    local t = spec.title or spec.label or spec.key or ""
    if type(t) == "function" then
        local ok, r = pcall(t)
        t = ok and r or ""
    end
    t = tostring(t)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    return t:lower()
end

local function Register()
    registered = true
    if #specs == 0 then return end
    if not EllesmereUI.RegisterPlugin then
        EllesmereUI.Print("|cff0cd29dDworak:|r this EllesmereUI version has no plugin support, so the Dworak settings cannot be shown.")
        return
    end
    -- Pinned modules first (by order), then everything else alphabetically by
    -- the shown title (colour codes stripped, case-insensitive). Ties fall back
    -- to the order the addons added themselves, so the sort stays stable.
    for i, s in ipairs(specs) do
        s._dworakIndex = i
        s._dworakName  = SortName(s)
    end
    table.sort(specs, function(a, b)
        local pa, pb = a.pin and true or false, b.pin and true or false
        if pa ~= pb then return pa end
        if pa then
            local oa, ob = a.order or 100, b.order or 100
            if oa ~= ob then return oa < ob end
        end
        if a._dworakName ~= b._dworakName then return a._dworakName < b._dworakName end
        return a._dworakIndex < b._dworakIndex
    end)
    local modules = {}
    for i, s in ipairs(specs) do
        local m = {}
        for k, v in pairs(s) do
            if not INTERNAL_KEYS[k] then m[k] = v end
        end
        modules[i] = m
    end
    EllesmereUI.RegisterPlugin(PLUGIN_ID, {
        label    = D.SECTION_LABEL,
        position = D.POSITION,
        modules  = modules,
    })
end

-- PLAYER_LOGIN: every addon has loaded by then, so every module is in.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Register()
end)
