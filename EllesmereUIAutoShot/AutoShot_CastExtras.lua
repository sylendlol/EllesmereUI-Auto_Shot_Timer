if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIAutoShot \ AutoShot_CastExtras.lua
--  "Auto Shot Timer" rows in the EXTRAS section at the bottom of Resource
--  Bars > Cast Bar: switch the timer on and attach it to the cast bar right
--  where the cast bar is set up. Everything else: Dworak > Auto Shot Timer.
--  Settings are the Auto Shot Timer's own (EllesmereUIAutoShot API).
--
--  EXTRAS is the shared Cast Bar host (ns._EUICastExtras, see
--  EllesmereUI_CastRank): this file carries the same block and registers
--  with order 20 (Spell Rank = 10); it never wraps the page builder itself.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local A = _G.EllesmereUIAutoShot
local ns = EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
if not (A and ns) then return end -- Resource Bars off: the Dworak page has every setting

-------------------------------------------------------------------------------
--  Shared Cast Bar EXTRAS host (same block in every cast bar extras add-on;
--  the first one loaded creates it, the others reuse it).
-------------------------------------------------------------------------------
local X = ns._EUICastExtras
if not X then
    X = { builders = {} }
    ns._EUICastExtras = X
end
if not X.Install then
    function X.Register(id, order, fn)
        X.builders[id] = { order = order, fn = fn }
    end
    function X.Header(parent, y, W)
        if X.headerDone then return y end
        X.headerDone = true
        local _, h = W:SectionHeader(parent, "EXTRAS", y)
        return y - h
    end
    function X.Install()
        if X.hooked then return true end
        local orig = ns.ERB_BuildCastBarPage
        if type(orig) ~= "function" then return false end
        X.hooked = true
        ns.ERB_BuildCastBarPage = function(pageName, parent, yOffset, ...)
            local total = orig(pageName, parent, yOffset, ...)
            -- The page returns its height (math.abs of its running y).
            if type(total) ~= "number" then return total end
            local y = -total
            X.headerDone = false
            local list = {}
            for _, b in pairs(X.builders) do list[#list + 1] = b end
            table.sort(list, function(a, b) return a.order < b.order end)
            for _, b in ipairs(list) do
                local ok, newY = pcall(b.fn, parent, y)
                if ok and type(newY) == "number" then
                    y = newY
                elseif not ok then
                    geterrorhandler()(newY)
                end
            end
            return math.abs(y)
        end
        return true
    end
end

-------------------------------------------------------------------------------
--  Auto Shot Timer rows
-------------------------------------------------------------------------------
local function BuildAutoShot(parent, y)
    local W = EllesmereUI.Widgets
    if not W then return y end
    local _, h
    local function Set(k, v, page)
        A.Set(k, v)
        if k == "asEnabled" then A.Apply() else A.Refresh() end
        if page then EllesmereUI:RefreshPage() end
    end
    local function off() return not A.Get("asEnabled") end
    local function attachOff() return off() or not A.Get("asAttach") end

    y = X.Header(parent, y, W)

    -- Auto Shot Timer | Attach to Cast Bar
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Auto Shot Timer",
          tooltip = "The Hunter Auto Shot bar with the wind-up window (Dworak > Auto Shot Timer has every setting; /autoshot).",
          getValue = function() return A.Get("asEnabled") == true end,
          setValue = function(v) Set("asEnabled", v and true or false, true) end },
        { type = "toggle", text = "Attach to Cast Bar",
          tooltip = "Anchors the Auto Shot bar to this cast bar.",
          disabled = off, disabledTooltip = "Auto Shot Timer",
          getValue = function() return A.Get("asAttach") == true end,
          setValue = function(v) Set("asAttach", v and true or false, true) end }
    );  y = y - h

    -- Side | Gap
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Auto Shot Side",
          values = { below = "Below the Cast Bar", above = "Above the Cast Bar" }, order = { "below", "above" },
          disabled = attachOff, disabledTooltip = "Attach to Cast Bar",
          getValue = function() return A.Get("asAttachSide") or "below" end,
          setValue = function(v) Set("asAttachSide", v) end },
        { type = "slider", text = "Auto Shot Gap", min = 0, max = 30, step = 1,
          disabled = attachOff, disabledTooltip = "Attach to Cast Bar",
          getValue = function() return A.Get("asAttachGap") end,
          setValue = function(v) Set("asAttachGap", v) end }
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h
    return y
end

X.Register("AutoShot", 20, BuildAutoShot)

local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
if not (IsLoaded and IsLoaded("EllesmereUIOptions") and X.Install()) then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        if name == "EllesmereUIOptions" then
            X.Install()
            self:UnregisterAllEvents()
        end
    end)
end
