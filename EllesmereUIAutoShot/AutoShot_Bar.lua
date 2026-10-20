if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIAutoShot \ AutoShot_Bar.lua
--  The bar, its options page (Dworak > Auto Shot Timer), Unlock Mode, /autoshot.
--
--  One fill colour (the Reload Color) runs over the reload. The wind-up
--  window is a line and a tinted zone at the bar's right end: be standing by
--  the line. Moving / casting inside it tints the zone and the line in the
--  Blocked colour. The move line (light blue) is the point from which you may
--  move again and the shot still goes out (only while you stood still this
--  reload). A late shot (a failed try, a cancelled wind-up, a switch-on) keeps
--  the bar full and runs a light over the shot's own wind-up up to the shot.
--  Every shot flashes the bar (afterglow) and prints its clip ("+0.12": how
--  much later than one reload after the previous shot it fired).
--
--  Look: an EllesmereUI bar texture, pixel-perfect border (EllesmereUI.PP)
--  and the EUI cast spark; Match Cast Bar Look takes texture, background and
--  border from Resource Bars > Cast Bar.
-------------------------------------------------------------------------------
local _, ns = ...
local DW, E = ns.DW, ns.E
if not (DW and E) then return end

local Get, Set = ns.Get, ns.Set

local UNLOCK_KEY  = "EUI_DworakAutoShot"
local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = -190 }
local PAGE        = "Auto Shot Timer"
local OFF_TIP     = "Auto Shot Timer"
local WHITE       = "Interface\\Buttons\\WHITE8x8"
local SPARK_TEX   = "Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga"
local GLOW_TIME   = 0.35

-- Look constants in one table (keeps the main chunk's locals few).
local K = {
    ZONE_A = 0.22, ZONE_BLOCKED_A = 0.45, LIGHT_A = 0.85, GLOW_A = 0.45,
    CLIP_GOOD = { 0.72, 1.00, 0.72 }, CLIP_MED = { 1.00, 0.76, 0.25 }, CLIP_BAD = { 1.00, 0.36, 0.30 },
}

-- EllesmereUI bar textures (+ SharedMedia at login).
local TEX, TEX_NAMES, TEX_ORDER = {}, { none = "None" }, { "none" }
if EllesmereUI.BuildBarTextureTables then
    TEX, TEX_NAMES, TEX_ORDER = EllesmereUI.BuildBarTextureTables(true)
end

local S = { unlocked = false, glowAt = -10, model = {} }
local frame, preview
local RefreshPreview -- defined with the preview

-------------------------------------------------------------------------------
--  Settings helpers
-------------------------------------------------------------------------------
local function FontPath()
    local f = Get("asFont")
    if f and f ~= "__global" and EllesmereUI.ResolveFontName then
        local path = EllesmereUI.ResolveFontName(f)
        if path then return path end
    end
    return EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
end

local function ReloadColor()
    if Get("asReloadColor") == "custom" then
        return Get("asReloadR"), Get("asReloadG"), Get("asReloadB")
    end
    return ns.Accent()
end
local function WindowColor() return Get("asWindowR"), Get("asWindowG"), Get("asWindowB") end
local function BlockedColor() return Get("asBlockedR"), Get("asBlockedG"), Get("asBlockedB") end
local function MoveColor() return Get("asMoveR"), Get("asMoveG"), Get("asMoveB") end

-- The player cast bar's settings (Resource Bars), or nil.
local function CastCfg()
    local rb = EllesmereUI._ModuleNS and EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
    local ERB = rb and rb.ERB
    local p = ERB and ERB.db and ERB.db.profile
    return p and p.castBar or nil
end

local function CastBar()
    local cb = _G.ERB_CastBarFrame
    if cb and cb.GetWidth and (cb:GetWidth() or 0) > 0 then return cb end
end

local function BarSize()
    local w = Get("asWidth")
    if Get("asAttach") and Get("asMatchWidth") then
        local cb = CastBar()
        if cb then w = cb:GetWidth() end
    end
    return w, Get("asHeight")
end

-- Texture, background, border: our own, or the cast bar's.
local function Look()
    local L = {}
    local cb = Get("asMatchLook") and CastCfg()
    if cb then
        local path = EllesmereUI.ResolveTexturePath and EllesmereUI.ResolveTexturePath(_G._ERB_CastBarTextures, cb.texture, nil)
        L.tex = (path and path ~= "ATLAS") and path or WHITE
        L.bgR, L.bgG, L.bgB, L.bgA = cb.bgR or 0, cb.bgG or 0, cb.bgB or 0, cb.bgA or 0.7
        L.bs = (cb.texture == "blizzard") and 1 or (cb.borderSize or 0)
        L.bR, L.bG, L.bB, L.bA = cb.borderR or 0, cb.borderG or 0, cb.borderB or 0, cb.borderA or 1
    else
        L.tex = EllesmereUI.ResolveTexturePath and EllesmereUI.ResolveTexturePath(TEX, Get("asTexture"), WHITE) or WHITE
        L.bgR, L.bgG, L.bgB, L.bgA = Get("asBgR"), Get("asBgG"), Get("asBgB"), Get("asBgA")
        L.bs = Get("asBorder") or 1
        L.bR, L.bG, L.bB, L.bA = Get("asBorderR"), Get("asBorderG"), Get("asBorderB"), 1
    end
    return L
end

-------------------------------------------------------------------------------
--  The bar (the live frame and the options preview are both made here)
-------------------------------------------------------------------------------
local function Line(top, layer)
    local l = {}
    l.rim = top:CreateTexture(nil, "OVERLAY", nil, layer)
    l.rim:SetColorTexture(0, 0, 0, 0.8)
    l.core = top:CreateTexture(nil, "OVERLAY", nil, layer + 1)
    l.core:SetTexture(WHITE)
    return l
end

local function PlaceLine(f, l, frac, r, g, b)
    if not frac then
        l.rim:Hide(); l.core:Hide()
        return
    end
    local w, h = f:GetWidth() or 0, f:GetHeight() or 0
    local x = math.floor(w * frac + 0.5)
    l.core:ClearAllPoints()
    l.core:SetSize(2, math.max(1, h - 2))
    l.core:SetPoint("CENTER", f, "LEFT", x, 0)
    l.rim:ClearAllPoints()
    l.rim:SetSize(4, math.max(1, h - 2))
    l.rim:SetPoint("CENTER", l.core, "CENTER")
    l.core:SetVertexColor(r, g, b, 1)
    l.rim:Show(); l.core:Show()
end

local function MakeBar(f)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()

    f.fill = CreateFrame("StatusBar", nil, f)
    f.fill:SetAllPoints()
    f.fill:SetStatusBarTexture(WHITE)
    f.fill:SetMinMaxValues(0, 1)
    f.fill:SetValue(0)

    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f.fill:GetFrameLevel() + 2)
    f.top = top

    -- The wind-up zone (from the line to the bar's end).
    f.zone = top:CreateTexture(nil, "ARTWORK", nil, 0)
    f.zone:SetTexture(WHITE)
    f.zone:SetPoint("TOPRIGHT")
    f.zone:SetPoint("BOTTOMRIGHT")
    -- The firing light over a late shot's wind-up, and the afterglow.
    f.light = top:CreateTexture(nil, "ARTWORK", nil, 1)
    f.light:SetBlendMode("ADD")
    f.light:SetPoint("TOPLEFT")
    f.light:SetPoint("BOTTOMLEFT")
    f.light:Hide()
    f.glow = top:CreateTexture(nil, "ARTWORK", nil, 2)
    f.glow:SetBlendMode("ADD")
    f.glow:SetAllPoints()
    f.glow:Hide()

    f.wline = Line(top, 0)
    f.mline = Line(top, 2)

    f.spark = top:CreateTexture(nil, "OVERLAY", nil, 5)
    if not f.spark:SetTexture(SPARK_TEX) then f.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark") end
    f.spark:SetBlendMode("ADD")
    f.spark:Hide()

    f.label = top:CreateFontString(nil, "OVERLAY")
    f.label:SetFontObject(GameFontHighlightSmall) -- a font before the first SetText
    f.label:SetPoint("LEFT", 4, 0)
    f.label:SetShadowOffset(1, -1)
    f.label:SetText("Auto Shot")
    f.time = top:CreateFontString(nil, "OVERLAY")
    f.time:SetFontObject(GameFontHighlightSmall)
    f.time:SetPoint("RIGHT", -4, 0)
    f.time:SetShadowOffset(1, -1)
    f.time:SetText("")
    f.clip = top:CreateFontString(nil, "OVERLAY")
    f.clip:SetFontObject(GameFontHighlightSmall)
    f.clip:SetPoint("CENTER")
    f.clip:SetShadowOffset(1, -1)
    f.clip:SetText("")

    -- Pixel-perfect border (EllesmereUI.PP), above the fill and the markers.
    local PP = EllesmereUI.PP
    if PP and PP.CreateBorder then
        f.border = PP.CreateBorder(f, 0, 0, 0, 1, 1)
        if f.border then f.border:SetFrameLevel(top:GetFrameLevel() + 1) end
    end
    return f
end

local function StyleBar(f, w, h)
    local L = Look()
    f:SetSize(w, h)
    f.bg:SetColorTexture(L.bgR, L.bgG, L.bgB, L.bgA)
    f.fill:SetStatusBarTexture(L.tex)
    f.fill:SetStatusBarColor(ReloadColor())
    f.light:SetTexture(L.tex)
    f.glow:SetTexture(L.tex)
    local wr, wg, wb = WindowColor()
    f.light:SetVertexColor(wr, wg, wb, K.LIGHT_A)
    f.glow:SetVertexColor(wr, wg, wb, 1)
    if f.border then
        local PP = EllesmereUI.PP
        if L.bs > 0 then
            PP.SetBorderSize(f, L.bs)
            PP.SetBorderColor(f, L.bR, L.bG, L.bB, L.bA)
            f.border:Show()
        else
            f.border:Hide()
        end
    end
    local size = Get("asTextSize")
    EllesmereUI.ApplyModuleFont(f.label, FontPath(), size)
    EllesmereUI.ApplyModuleFont(f.time, FontPath(), size)
    EllesmereUI.ApplyModuleFont(f.clip, FontPath(), size)
    f.label:SetShown(Get("asShowLabel") ~= false)
    f.time:SetShown(Get("asShowTime") ~= false)
    f.spark:SetSize(8, h)
end

-- m: frac (fill 0..1), state ("reload" | "ready" | "blocked" | "idle"), line
-- (the wind-up line 0..1), move (the move line 0..1), fire (the firing light
-- 0..1), solo (no fill under it), rem (seconds to the shot), glow (0..1).
local function Draw(f, m)
    local w = f:GetWidth() or 0
    local blocked = m.state == "blocked"
    local frac = math.max(0, math.min(1, m.frac or 0))
    f.fill:SetValue(m.solo and 0 or frac)

    if m.line and Get("asShowWindow") ~= false then
        local zw = math.max(1, w * (1 - m.line))
        f.zone:SetWidth(zw)
        if blocked then
            local r, g, b = BlockedColor()
            f.zone:SetVertexColor(r, g, b, K.ZONE_BLOCKED_A)
            PlaceLine(f, f.wline, m.line, r, g, b)
        else
            local r, g, b = WindowColor()
            f.zone:SetVertexColor(r, g, b, K.ZONE_A)
            PlaceLine(f, f.wline, m.line, r, g, b)
        end
        f.zone:Show()
    else
        f.zone:Hide()
        PlaceLine(f, f.wline, nil)
    end

    if m.move and Get("asMoveLine") ~= false then
        PlaceLine(f, f.mline, m.move, MoveColor())
    else
        PlaceLine(f, f.mline, nil)
    end

    -- The spark rides the fill's edge in the reload, the light's edge while firing.
    local sparkOn = Get("asShowSpark") ~= false
    if m.fire then
        local lw = math.max(1, w * m.fire)
        f.light:SetWidth(lw)
        f.light:Show()
        if sparkOn then
            f.spark:ClearAllPoints()
            f.spark:SetPoint("CENTER", f, "LEFT", lw, 0)
            f.spark:Show()
        else
            f.spark:Hide()
        end
    else
        f.light:Hide()
        if sparkOn and m.state == "reload" and frac > 0 and frac < 1 then
            f.spark:ClearAllPoints()
            f.spark:SetPoint("CENTER", f, "LEFT", w * frac, 0)
            f.spark:Show()
        else
            f.spark:Hide()
        end
    end

    local g = m.glow or 0
    if g > 0 and Get("asGlow") ~= false then
        f.glow:SetAlpha(g * K.GLOW_A)
        f.glow:Show()
    else
        f.glow:Hide()
    end

    if blocked then
        f.time:SetText("hold")
    elseif m.rem and m.rem >= 0.05 then
        f.time:SetFormattedText("%.1f", m.rem)
    else
        f.time:SetText("")
    end
end

local function ShowClip(f, clip)
    if not (f and clip and Get("asClip") ~= false) then
        if f then f.clip:SetText("") end
        return
    end
    clip = math.floor(clip * 100 + 0.5) / 100
    local c = (clip >= 0.50 and K.CLIP_BAD) or (clip >= 0.25 and K.CLIP_MED) or K.CLIP_GOOD
    f.clip:SetFormattedText("+%.2f", clip)
    f.clip:SetTextColor(c[1], c[2], c[3], 1)
end

-------------------------------------------------------------------------------
--  Live model
-------------------------------------------------------------------------------
local function LineFor(dur, block)
    if not (dur and dur > 0) then return nil end
    return 1 - math.min(block / dur, 0.9)
end

local function LiveModel(now)
    local m, R, G = S.model, E.R, E.G
    E.Tick(now)
    m.frac, m.state, m.line, m.move, m.fire, m.solo, m.rem = 0, "idle", nil, nil, nil, nil, nil
    m.glow = math.max(0, 1 - (now - S.glowAt) / GLOW_TIME)
    if R.dur > 0 and R.start > 0 then
        local e = R.start + R.dur
        local block = E.RunBlock()
        m.line = LineFor(R.dur, block)
        local held = (G.moving or G.casting) and G.auto ~= false
        if now < e then
            m.frac = (now - R.start) / R.dur
            m.state = (held and m.frac >= m.line) and "blocked" or "reload"
            if G.auto and not R.movedSince and not E.Due() then
                m.move = LineFor(R.dur, E.MoveWindow())
            end
        elseif E.RangedFull(now) then
            m.frac, m.solo = 1, R.solo
            m.state = held and "blocked" or "ready"
            m.fire = E.FireProgress(now)
        end
        if m.state ~= "idle" then
            local shot = E.Due() or e
            if shot - now >= 0.05 then m.rem = shot - now end
        end
    end
    return m
end

-- No cycle running: the window line on an empty bar.
local function IdleModel()
    local m = S.model
    m.frac, m.state, m.move, m.fire, m.solo, m.rem, m.glow = 0, "idle", nil, nil, nil, nil, 0
    local dur = E.RefDur()
    m.line = LineFor(dur, (E.Windup(dur)))
    return m
end

local function SampleModel()
    local m = IdleModel()
    m.frac, m.state, m.rem = 0.62, "reload", 1.2
    m.move = LineFor(E.RefDur(), E.MoveWindow())
    return m
end

-------------------------------------------------------------------------------
--  Position: attached to the cast bar, else the Unlock Mode position
-------------------------------------------------------------------------------
local function SavedPos()
    local pos = Get("asPosition")
    return pos and pos.point and pos or DEFAULT_POS
end

local hookedCastBar
local function Place()
    if not frame then return end
    local w, h = BarSize()
    StyleBar(frame, w, h)
    frame:ClearAllPoints()
    local cb = Get("asAttach") and CastBar()
    if cb then
        local gap = Get("asAttachGap") or 2
        if Get("asAttachSide") == "above" then
            frame:SetPoint("BOTTOM", cb, "TOP", 0, gap)
        else
            frame:SetPoint("TOP", cb, "BOTTOM", 0, -gap)
        end
        if not hookedCastBar then
            hookedCastBar = true
            cb:HookScript("OnSizeChanged", function()
                if Get("asAttach") and Get("asMatchWidth") then Place() end
            end)
        end
        return
    end
    local pos = SavedPos()
    frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "EUI_DworakAutoShotBar", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(20)
    frame:SetClampedToScreen(true)
    MakeBar(frame)
    frame:Hide()
    Place()
    return frame
end

-- The paint with no cycle running: hidden, or the idle bar.
local function Idle()
    if not frame then return end
    frame:SetScript("OnUpdate", nil)
    if S.unlocked then
        frame:Show()
        Draw(frame, SampleModel())
        return
    end
    Draw(frame, IdleModel())
    frame:SetShown(ns.Active() and not Get("asHideIdle"))
end

local function OnUpdate()
    local now = GetTime()
    local m = LiveModel(now)
    if m.state == "idle" and m.glow <= 0 then
        Idle()
        return
    end
    Draw(frame, m)
end

-- Something changed: paint every frame until the cycle is over.
function ns.Wake()
    if not (frame and ns.Active()) or S.unlocked then return end
    frame:SetAlpha(1)
    frame:Show()
    frame:SetScript("OnUpdate", OnUpdate)
end

function ns.OnShot(clip)
    S.glowAt = GetTime()
    ShowClip(frame, clip)
end

function ns.OnClipClear()
    ShowClip(frame, nil)
end

local function Apply()
    E.Enable(ns.Active())
    if not ns.Active() then
        if frame then
            frame:SetScript("OnUpdate", nil)
            frame:Hide()
        end
        if RefreshPreview then RefreshPreview() end
        return
    end
    Build()
    Place()
    ns.Wake()
    if RefreshPreview then RefreshPreview() end
end

-- Every setting change: the live bar and the preview.
local function Refresh()
    if frame then
        Place()
        if not frame:GetScript("OnUpdate") then Idle() end
    end
    if RefreshPreview then RefreshPreview() end
end

-------------------------------------------------------------------------------
--  Options preview: the bar in the content header running a scripted fight:
--  a clean shot, then a move inside the window (the shot waits, fires late).
-------------------------------------------------------------------------------
local PREVIEW_H, PREVIEW_MARGIN = 96, 14
local SAMPLE = { dur = 2.4, line = 0.79, move = 0.94, moveFrom = 2.05, moveTo = 2.65, wait = 0.3, fire = 0.5 }

local function PreviewTick(self)
    local box, P = self.box, SAMPLE
    local total = P.dur * 2 + P.wait + P.fire
    local t = (GetTime() - self.t0) % total
    local m = S.model
    m.line, m.move, m.fire, m.solo, m.rem = P.line, nil, nil, nil, nil
    local hint
    if t < P.dur then
        -- 1: a clean shot
        m.frac, m.state, m.rem, m.move = t / P.dur, "reload", P.dur - t, P.move
        m.glow = math.max(0, 1 - t / GLOW_TIME)
        hint = "Reload: move and cast freely"
        if m.frac >= P.line then hint = "Wind-up: stand still, no casts" end
        if t < GLOW_TIME then ShowClip(box, 0) end
    else
        local u = t - P.dur
        m.glow = math.max(0, 1 - u / GLOW_TIME)
        if u < P.dur then
            -- 2: moving across the line holds the shot
            m.frac, m.rem = u / P.dur, P.dur + P.wait + P.fire - u
            local moving = u >= P.moveFrom and u < P.moveTo
            m.state = (moving and m.frac >= P.line) and "blocked" or "reload"
            hint = moving and "Moving inside the window: the shot waits" or "Reload: move and cast freely"
        elseif u < P.dur + P.wait then
            m.frac, m.state, m.rem = 1, "ready", P.dur + P.wait + P.fire - u
            hint = "Stopped: the server retries the shot"
        else
            m.frac, m.state = 1, "ready"
            m.fire = (u - P.dur - P.wait) / P.fire
            m.rem = P.dur + P.wait + P.fire - u
            hint = "Firing: the late shot's wind-up"
        end
        if u < GLOW_TIME then ShowClip(box, 0.80) end
    end
    Draw(box, m)
    self.hint:SetText(ns.Enabled() and hint or "Preview (the timer is off)")
end

function RefreshPreview()
    if not (preview and preview:IsShown()) then return end
    local box = preview.box
    local w, h = Get("asWidth"), Get("asHeight")
    local avail = (preview:GetWidth() or 0) - PREVIEW_MARGIN * 2
    StyleBar(box, w, h)
    box:SetScale((avail > 50 and w > avail) and (avail / w) or 1)
    box:SetAlpha(ns.Enabled() and 1 or 0.5)
end

local function HeaderBuilder(header, width)
    if not preview then
        preview = CreateFrame("Frame", nil, header)
        preview.box = MakeBar(CreateFrame("Frame", nil, preview))
        preview.box:SetPoint("CENTER", 0, 8)
        preview.hint = preview:CreateFontString(nil, "OVERLAY")
        preview.hint:SetFontObject(GameFontDisableSmall)
        preview.hint:SetPoint("BOTTOM", preview, "BOTTOM", 0, 8)
        preview.t0 = GetTime()
        preview:SetScript("OnUpdate", PreviewTick)
    end
    preview:SetParent(header)
    preview:SetFrameStrata(header:GetFrameStrata())
    preview:SetFrameLevel(header:GetFrameLevel() + 5)
    preview.box:SetFrameLevel(preview:GetFrameLevel() + 1)
    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", header, "TOPLEFT")
    preview:SetPoint("TOPRIGHT", header, "TOPRIGHT")
    if width and width > 0 then preview:SetWidth(width) end
    preview:SetHeight(PREVIEW_H)
    preview:Show()
    RefreshPreview()
    return PREVIEW_H
end

-------------------------------------------------------------------------------
--  Options page (Dworak > Auto Shot Timer)
-------------------------------------------------------------------------------
local function BuildPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    parent._showRowDivider = true
    local function off() return not ns.Enabled() end
    local function lookOff() return off() or Get("asMatchLook") == true end
    local prebuilding = EllesmereUI.IsSearchPrebuild()
    if not prebuilding then EllesmereUI:SetContentHeader(HeaderBuilder) end

    -- A setter: store, then repaint (page = refresh the page's disabled states).
    local function S_(key, page, after)
        return function(v)
            Set(key, v)
            if after then after(v) end
            Refresh()
            if page then EllesmereUI:RefreshPage() end
        end
    end
    local function Toggle(text, key, tip, extra)
        local c = { type = "toggle", text = text, tooltip = tip,
            disabled = off, disabledTooltip = OFF_TIP,
            getValue = function() return Get(key) ~= false end,
            setValue = S_(key) }
        if extra then for k, v in pairs(extra) do c[k] = v end end
        return c
    end
    local function Swatch(tip, kR, kG, kB, disabled)
        return {
            tooltip = tip, disabled = disabled,
            getValue = function() return Get(kR), Get(kG), Get(kB), 1 end,
            setValue = function(r, g, b)
                Set(kR, r); Set(kG, g); Set(kB, b)
                Refresh()
            end,
        }
    end

    _, h = W:SectionHeader(parent, "AUTO SHOT", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Auto Shot Timer",
          tooltip = "A bar for the Auto Shot cycle. The line near its right end is the wind-up: "
              .. "be standing still by it. Moving or casting past it holds the shot back. "
              .. "Cast Aimed Shot / Multi-Shot right after a shot.\nMove it in Unlock Mode, or attach it to the cast bar.",
          getValue = function() return ns.Enabled() end,
          setValue = function(v)
              Set("asEnabled", v)
              Apply()
              EllesmereUI:RefreshPage()
          end },
        Toggle("Hunters Only", "asHunterOnly", "Off: also for the ranged auto-repeat of other classes (Shoot, Throw).",
            { setValue = function(v) Set("asHunterOnly", v); Apply() end })
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("Hide When Idle", "asHideIdle", "Hidden while Auto Shot is off and nothing reloads."),
        Toggle("Melee Resets Reload", "asMeleeReset",
            "On WoW Forever every melee swing restarts the Auto Shot reload (no event says so). The bar restarts with it.")
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "WIND-UP", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Base Wind-up", min = 0.3, max = 0.8, step = 0.05,
          tooltip = "The unhasted wind-up in seconds (Blizzard: 0.5). Ranged haste shortens it: "
              .. "the timer scales it by this reload over your bow's printed speed.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("asWindup") end,
          setValue = S_("asWindup") },
        Toggle("Latency Compensation", "asLatency",
            "Moves the line one ping + 0.10s earlier: your stop reaches the server that much later, "
                .. "so this is the last moment to be standing.", { setValue = S_("asLatency", true) })
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Latency Offset (ms)", min = -100, max = 200, step = 5,
          tooltip = "Added to the latency compensation. Shots that still clip: raise it.",
          disabled = function() return off() or Get("asLatency") == false end,
          disabledTooltip = "Latency Compensation",
          getValue = function() return Get("asLatencyOfs") end,
          setValue = S_("asLatencyOfs") },
        Toggle("Mark Window", "asShowWindow", "The wind-up line and the tinted zone after it.")
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("Move Line", "asMoveLine",
            "A light blue line close to the bar's end: from there you may start moving and the shot still goes out. "
                .. "Shown only while you stood still since the last shot."),
        Toggle("Clip Text", "asClip",
            "After every shot \"+0.12\" in the middle of the bar: how much later than one reload after the previous "
                .. "shot it fired. Green under 0.25, amber under 0.50, red above. Cleared when combat ends.",
            { setValue = S_("asClip", false, function(v) if not v then ns.OnClipClear() end end) })
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Texture", values = TEX_NAMES, order = TEX_ORDER,
          disabled = lookOff, disabledTooltip = "Match Cast Bar Look",
          getValue = function() return Get("asTexture") or "none" end,
          setValue = S_("asTexture") },
        Toggle("Match Cast Bar Look", "asMatchLook",
            "Takes the texture, background and border of Resource Bars > Cast Bar.",
            { getValue = function() return Get("asMatchLook") == true end, setValue = S_("asMatchLook", true) })
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Width", min = 60, max = 600, step = 1,
          disabled = function() return off() or (Get("asAttach") and Get("asMatchWidth")) end,
          disabledTooltip = "Match Cast Bar Width",
          getValue = function() return Get("asWidth") end,
          setValue = S_("asWidth") },
        { type = "slider", text = "Height", min = 4, max = 40, step = 1,
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("asHeight") end,
          setValue = S_("asHeight") }
    );  y = y - h

    local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Font", values = fontValues, order = fontOrder,
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("asFont") or "__global" end,
          setValue = S_("asFont") },
        { type = "slider", text = "Text Size", min = 6, max = 24, step = 1,
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("asTextSize") end,
          setValue = S_("asTextSize") }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("Show Label", "asShowLabel", "\"Auto Shot\" on the left of the bar."),
        Toggle("Show Time", "asShowTime", "Seconds to the next shot on the right (\"hold\" while moving holds it).")
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("Show Spark", "asShowSpark"),
        Toggle("Afterglow", "asGlow", "Every shot flashes the bar in the Window color.")
    );  y = y - h

    local bdRow
    bdRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Border", min = 0, max = 4, step = 1, trackWidth = 120,
          tooltip = "Border thickness in pixels. 0 shows none.",
          disabled = lookOff, disabledTooltip = "Match Cast Bar Look",
          getValue = function() return Get("asBorder") end,
          setValue = S_("asBorder") },
        { type = "slider", text = "Background", min = 0, max = 100, step = 1, trackWidth = 120,
          tooltip = "Opacity of the bar's background.",
          disabled = lookOff, disabledTooltip = "Match Cast Bar Look",
          getValue = function() return math.floor(Get("asBgA") * 100 + 0.5) end,
          setValue = function(v)
              Set("asBgA", v / 100)
              Refresh()
          end }
    );  y = y - h
    if not prebuilding and bdRow and EllesmereUI.BuildInlineSwatches then
        if bdRow._leftRegion then
            EllesmereUI.BuildInlineSwatches(bdRow._leftRegion,
                { Swatch("Border Color", "asBorderR", "asBorderG", "asBorderB") },
                { disabled = lookOff, disabledTooltip = "Match Cast Bar Look" })
        end
        if bdRow._rightRegion then
            EllesmereUI.BuildInlineSwatches(bdRow._rightRegion,
                { Swatch("Background Color", "asBgR", "asBgG", "asBgB") },
                { disabled = lookOff, disabledTooltip = "Match Cast Bar Look" })
        end
    end

    local colRow
    colRow, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Reload Color",
          tooltip = "The fill. UI Accent Color follows Global Settings; Custom uses the color next to it.",
          values = { accent = "UI Accent Color", custom = "Custom" }, order = { "accent", "custom" },
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("asReloadColor") or "accent" end,
          setValue = S_("asReloadColor", true) },
        { type = "multiSwatch", text = "Marker Colors",
          tooltip = "Window (line, zone, firing light, afterglow), Blocked (moving or casting inside the window), Move Line.",
          disabled = off, disabledTooltip = OFF_TIP,
          swatches = {
              Swatch("Window Color", "asWindowR", "asWindowG", "asWindowB"),
              Swatch("Blocked Color", "asBlockedR", "asBlockedG", "asBlockedB"),
              Swatch("Move Line Color", "asMoveR", "asMoveG", "asMoveB"),
          } }
    );  y = y - h
    if not prebuilding and colRow and colRow._leftRegion and EllesmereUI.BuildInlineSwatches then
        EllesmereUI.BuildInlineSwatches(colRow._leftRegion, { Swatch("Custom Reload Color",
            "asReloadR", "asReloadG", "asReloadB",
            function() return off() or Get("asReloadColor") ~= "custom" end) },
            { disabled = off, disabledTooltip = OFF_TIP })
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "POSITION", y);  y = y - h

    local function attachOff() return off() or not Get("asAttach") end
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Attach to Cast Bar",
          tooltip = "Anchors the bar to the EllesmereUI player cast bar (Resource Bars > Cast Bar). "
              .. "Off: its own Unlock Mode position.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("asAttach") == true end,
          setValue = S_("asAttach", true) },
        { type = "dropdown", text = "Side",
          values = { below = "Below the Cast Bar", above = "Above the Cast Bar" }, order = { "below", "above" },
          disabled = attachOff, disabledTooltip = "Attach to Cast Bar",
          getValue = function() return Get("asAttachSide") or "below" end,
          setValue = S_("asAttachSide") }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Gap", min = 0, max = 30, step = 1,
          disabled = attachOff, disabledTooltip = "Attach to Cast Bar",
          getValue = function() return Get("asAttachGap") end,
          setValue = S_("asAttachGap") },
        { type = "toggle", text = "Match Cast Bar Width",
          disabled = attachOff, disabledTooltip = "Attach to Cast Bar",
          getValue = function() return Get("asMatchWidth") ~= false end,
          setValue = S_("asMatchWidth", true) }
    );  y = y - h

    return math.abs(y)
end

DW.AddModule({
    key         = "AutoShot",
    title       = "Auto Shot Timer",
    order       = 30,
    description = "Auto Shot cycle with the wind-up window for Hunters.",
    pages       = { PAGE },
    buildPage   = BuildPage,
    getHeaderBuilder = function() return HeaderBuilder end,
    onPageCacheRestore = function() if RefreshPreview then RefreshPreview() end end,
})

-- Shared with AutoShot_CastExtras.lua (Cast Bar > EXTRAS).
EllesmereUIAutoShot = {
    Get = Get, Set = Set, Apply = Apply, Refresh = Refresh,
    Open = function() return DW.Open("AutoShot") end,
}

-- /autoshot           the page
-- /autoshot debug     what the timer knows right now
-- /autoshot log       every shot in chat: reload, clip, why it was late
SLASH_EUIAUTOSHOT1 = "/euiautoshot"
SLASH_EUIAUTOSHOT2 = "/autoshot"
SlashCmdList.EUIAUTOSHOT = function(msg)
    msg = msg and msg:lower() or ""
    if msg:match("debug") then
        ns.Print("enabled = " .. tostring(ns.Enabled()) .. ", active = " .. tostring(ns.Active())
            .. ", class = " .. tostring(ns.CLASS) .. ", cast bar = " .. (CastBar() and "found" or "not found"))
        E.Debug()
        if frame then
            local c = frame.clip
            local font, size = c:GetFont()
            ns.Print(string.format("clip text \"%s\": visible = %s, width = %.0f, font = %s %s, Clip Text = %s",
                tostring(c:GetText()), tostring(c:IsVisible()), c:GetStringWidth() or 0,
                tostring(font), tostring(size), tostring(Get("asClip"))))
            local l = frame.mline.core
            ns.Print("move line: shown = " .. tostring(l:IsShown()) .. ", Move Line = " .. tostring(Get("asMoveLine")))
        end
        return
    elseif msg:match("log") then
        E.G.log = not E.G.log
        ns.Print("shot log " .. (E.G.log and "on" or "off"))
        return
    end
    DW.Open("AutoShot")
end

-- The UI Accent Color (Global Settings) repaints the reload fill live.
if EllesmereUI.RegAccent then
    EllesmereUI.RegAccent({ type = "callback", fn = function() Refresh() end })
end

-------------------------------------------------------------------------------
--  Login: apply, then the Unlock Mode element
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(TEX_NAMES, TEX_ORDER, nil, TEX)
    end
    Apply()
    C_Timer.After(1, function() if frame then Place() end end) -- the cast bar is built late
    if not (EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    EllesmereUI:RegisterUnlockElements({
        EllesmereUI.MakeUnlockElement({
            key      = UNLOCK_KEY,
            label    = "Auto Shot Timer",
            group    = DW.UNLOCK_GROUP,
            order    = 920,
            noResize = true,
            -- Attached to the cast bar: it moves with the cast bar.
            isHidden = function() return not ns.Active() or (Get("asAttach") and CastBar() ~= nil) end,
            getFrame = function()
                if not ns.Active() then return nil end
                Build()
                return frame
            end,
            getSize = function() return BarSize() end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                Set("asPosition", { point = point, relPoint = relPoint, x = x, y = y })
                if not (EllesmereUI.IsUnlockModeActive and EllesmereUI:IsUnlockModeActive()) then Place() end
            end,
            loadPos = SavedPos,
            clearPos = function()
                Set("asPosition", nil)
                Place()
            end,
            applyPos = function()
                if ns.Active() then
                    Build()
                    Place()
                end
            end,
        }),
    }, ns.FOLDER)
    if EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener(UNLOCK_KEY, function(active)
            S.unlocked = active and ns.Active() or false
            if not frame then return end
            if S.unlocked then Idle() else Idle(); ns.Wake() end
        end)
    end
end)
