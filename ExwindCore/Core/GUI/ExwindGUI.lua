-- =========================================================
-- ExwindGUI.lua
-- 封装 LibSharedMedia (LSM) 的原生 Wow 工具组件
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

-- 确保 EXUI 命名空间存在（可能在 ExwindToolsUI.lua 之前加载）
local EXUI = ExwindTools.UI or {}
ExwindTools.UI = EXUI
_G.ExwindToolsUI = EXUI

local LSM = LibStub("LibSharedMedia-3.0")
local L = ExwindTools.L

-- [Core] 严格遵照指令：只许使用游戏默认字体路径，禁止任何硬编码引用
local defaultFontPath, defaultFontSize, defaultFontFlags = _G.GameFontHighlight:GetFont()

-- DropdownButton 的箭头、文字与背景切片以 30px 为一组固定几何。
-- Grid 可以决定它在逻辑网格中占几格，但不能把物理按钮高度拉伸；
-- 否则右侧箭头仍维持模板尺寸，视觉会变形。LSM 与普通下拉共用此几何约束，
-- 数据/菜单实现仍各自独立。
EXUI.GridDropdownHeight = 30
-- Slider 的完整物理高度包含同一控件内的标题行与下方轨道。
-- Grid 与所有组合设置组都复用这个几何，不能再让标题/数值框溢出到控件外。
EXUI.GridSliderHeight = 44

-- 所有 EXUI Collection / PanelPreview 都必须带稳定模块身份。这个身份不是
-- 页面标签，也不能由 DB 开关决定；它用于把 Duration 合同和少数历史例外收在
-- Core，而不是让任一业务模块自行开启 OnUpdate。
local LEGACY_DURATION_OWNERS = {
    ["ExBoss.TimerBar"] = true,
    ["ExBoss.BunBar"] = true,
}
local durationViolations = {}

function EXUI:RequireModuleKey(moduleKey, apiName)
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error((apiName or "EXUI") .. " requires non-empty MODULE_KEY", 3)
    end
    return moduleKey
end

function EXUI:CanUseLegacyDurationPath(moduleKey)
    self:RequireModuleKey(moduleKey, "EXUI legacy-duration gate")
    return LEGACY_DURATION_OWNERS[moduleKey] == true
end

function EXUI:RequireLegacyRuntimeTickOwner(moduleKey, apiName)
    self:RequireModuleKey(moduleKey, apiName or "EXUI legacy runtime tick")
    if not LEGACY_DURATION_OWNERS[moduleKey] then
        error((apiName or "EXUI legacy runtime tick") .. " is reserved for ExBoss.TimerBar and ExBoss.BunBar", 3)
    end
    return true
end

function EXUI:ReportDurationViolation(moduleKey, renderer)
    self:RequireModuleKey(moduleKey, "EXUI duration gate")
    local key = moduleKey .. ":" .. tostring(renderer or "renderer")
    if durationViolations[key] then return false end
    durationViolations[key] = true
    local message = "EXUI Duration violation: " .. moduleKey
        .. " must provide DUR; legacy start/duration and Lua OnUpdate are reserved for ExBoss.TimerBar and ExBoss.BunBar."
    if _G.print then _G.print(message) end
    if _G.geterrorhandler then _G.geterrorhandler()(message) end
    return false
end

-- Grid 只负责把逻辑格转换成像素；复合控件才知道自己的真实最小/首选高度。
-- 这个 registry 是纯测量合同：不得创建 Frame、不得读取屏幕尺寸、不得延迟测量。
-- 页面 schema 以 `measure = true` 显式选择它，未选择的旧页面保持原有 x/y/w/h 行为。
EXUI.GridComponentMeasures = EXUI.GridComponentMeasures or {}

function EXUI:RegisterGridComponentMeasure(componentType, measure)
    if type(componentType) ~= "string" or componentType == "" or type(measure) ~= "function" then
        return false
    end
    self.GridComponentMeasures[string.lower(componentType)] = measure
    return true
end

function EXUI:MeasureGridComponent(componentType, width, opts, db, item)
    local measure = type(componentType) == "string" and self.GridComponentMeasures[string.lower(componentType)]
    if type(measure) ~= "function" then return nil end
    return measure(math.max(1, tonumber(width) or 1), opts or {}, db, item)
end

local function ApplyGridDropdownSize(dropdown, width)
    dropdown:SetSize(width, EXUI.GridDropdownHeight)
    dropdown._exGridFixedHeight = EXUI.GridDropdownHeight
end

-- DropdownButton 的菜单不是子 Frame，而是暴雪 Menu 系统按“按钮自身”的 strata
-- 单独创建。池化控件会保留上一次的 strata；若不在这里同步，组合弹窗虽然在
-- TOOLTIP 层，里面的下拉菜单仍可能以 MEDIUM 层打开并被弹窗遮住。
local function SyncDropdownMenuLayer(dropdown, parent)
    if not dropdown or not dropdown.SetFrameStrata then return end
    if EXUI.ModernMenuStyleMixin then
        dropdown.menuMixin = EXUI.ModernMenuStyleMixin
    end
    local strata = parent and parent.GetFrameStrata and parent:GetFrameStrata() or "MEDIUM"
    dropdown:SetFrameStrata(strata)
    if dropdown.SetFrameLevel and parent and parent.GetFrameLevel then
        dropdown:SetFrameLevel((parent:GetFrameLevel() or 0) + 5)
    end

    -- 下拉控件会被对象池复用；仅在创建时同步，会让它在重新挂到
    -- TOOLTIP 弹窗后仍保留旧层级。打开菜单前再同步一次，确保
    -- Blizzard_Menu 以当前 owner 的 strata / level 创建菜单。
    dropdown._exuiDropdownLayerParent = parent
    if dropdown.OpenMenu and not dropdown._exuiDropdownLayerOpenHook then
        dropdown._exuiDropdownLayerOpenHook = true
        dropdown._exuiBaseOpenMenu = dropdown.OpenMenu
        dropdown.OpenMenu = function(self, ...)
            local owner = self._exuiDropdownLayerParent or self:GetParent()
            if owner and owner.GetFrameStrata then
                self:SetFrameStrata(owner:GetFrameStrata())
                if self.SetFrameLevel and owner.GetFrameLevel then
                    self:SetFrameLevel((owner:GetFrameLevel() or 0) + 5)
                end
            end
            return self._exuiBaseOpenMenu(self, ...)
        end
    end

    -- Blizzard_Menu 生成的真正菜单不是 DropdownButton 的子 Frame，而是 menu:ToProxy()
    -- 返回的独立窗口。它在对象池中借出后有时仍会保留较低的 frame level，造成
    -- 菜单只在组合弹窗的下缘露出。菜单创建完成后直接提升该 Proxy，不能只提升按钮。
    if dropdown.OnMenuOpened and not dropdown._exuiDropdownMenuOpenedHook then
        dropdown._exuiDropdownMenuOpenedHook = true
        dropdown._exuiBaseOnMenuOpened = dropdown.OnMenuOpened
        dropdown.OnMenuOpened = function(self, menu)
            self._exuiBaseOnMenuOpened(self, menu)

            local owner = self._exuiDropdownLayerParent or self:GetParent()
            local proxy = menu and menu.ToProxy and menu:ToProxy()
            if owner and proxy and owner.GetFrameStrata then
                local ownerStrata = owner:GetFrameStrata()
                -- DIALOG 弹窗内的列表必须位于 FULLSCREEN_DIALOG；这不是“调高一点”，
                -- 而是使用暴雪定义的相邻更高 strata，保证不会被弹窗遮住。
                local menuStrata = ownerStrata == "TOOLTIP" and "TOOLTIP" or "FULLSCREEN_DIALOG"
                proxy:SetFrameStrata(menuStrata)
                if proxy.SetFrameLevel and owner.GetFrameLevel then
                    local level = math.max(proxy:GetFrameLevel() or 0, (owner:GetFrameLevel() or 0) + 1000)
                    proxy:SetFrameLevel(level)
                end
                if proxy.SetToplevel then proxy:SetToplevel(true) end
            end
            if EXUI.StyleDropdownMenuProxy then EXUI:StyleDropdownMenuProxy(proxy) end
            if EXUI.RefreshControlAppearance then EXUI:RefreshControlAppearance(self) end
        end
    end
    if dropdown.OnMenuClosed and not dropdown._exuiDropdownMenuClosedHook then
        dropdown._exuiDropdownMenuClosedHook = true
        dropdown._exuiBaseOnMenuClosed = dropdown.OnMenuClosed
        dropdown.OnMenuClosed = function(self, menu, closeReason)
            self._exuiBaseOnMenuClosed(self, menu, closeReason)
            if EXUI.RefreshControlAppearance then EXUI:RefreshControlAppearance(self) end
        end
    end
end


-- [Style] 所有插件共用的扁平化输入/控件背景定义。
EXUI.TooltipBackdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- =========================================================
-- Shared modern control theme
--
-- This is the single visual implementation used by every EXUI constructor.
-- ExwindControlAppearance.lua only keeps the old opt-in API names alive; it
-- no longer owns a second skin or a second set of pools.
-- =========================================================
local MODERN_MEDIA = "Interface\\AddOns\\ExwindCore\\Textures\\GUI\\"
local GC = ExwindTools.GUIColors
if not GC then error("ExwindGUIColor.lua must load before ExwindGUI.lua") end
local MODERN = {
    colors = {
        background = GC.page,
        panel = GC.panel,
        header = GC.header,
        headerHover = GC.headerHover,
        headerDivider = GC.headerDivider,
        subcard = GC.subcard,
        subcardBorder = GC.subcardBorder,
        subcardHoverBorder = GC.subcardHoverBorder,
        input = GC.input,
        inputBorder = GC.inputBorder,
        inputHoverBorder = GC.inputHoverBorder,
        inputFocusBorder = GC.inputFocusBorder,
        inputDisabled = GC.inputDisabled,
        inputDisabledBorder = GC.inputDisabledBorder,
        raised = GC.card,
        cardBorder = GC.cardBorder,
        hover = GC.rowHover,
        rowHover = GC.rowHover,
        cardHoverBorder = GC.cardHoverBorder,
        border = GC.panelBorder,
        text = GC.text,
        muted = GC.textDim,
        placeholder = GC.textPlaceholder,
        disabled = GC.textDisabled,
        blue = GC.accent,
        blueHover = GC.accentHover,
        accentActive = GC.accentActive,
        primaryHover = GC.primaryFillHover,
        primaryPressed = GC.primaryFillActive,
        lightBlue = GC.selectedText,
        blueSoft = GC.menuSelected,
        focus = GC.inputFocusBorder,
        focusRing = GC.focusRing,
        modifiedBorder = GC.modifiedBorder,
        accent = GC.accent,
        sliderTrack = GC.sliderTrack,
        sliderTrackHover = GC.sliderTrackHover,
        sliderThumb = GC.sliderThumb,
        sliderThumbHover = GC.sliderThumbHover,
        sliderThumbActive = GC.sliderThumbActive,
        popup = GC.popup,
        popupBorder = GC.popupBorder,
        popupSearch = GC.popupSearch,
        popupSearchBorder = GC.popupSearchBorder,
        popupDivider = GC.popupDivider,
        menuSelected = GC.menuSelected,
        menuSelectedHover = GC.menuSelectedHover,
        menuHover = GC.menuHover,
        primaryFill = GC.primaryFill,
        primaryText = GC.primaryText,
        secondaryFill = GC.secondaryFill,
        secondaryBorder = GC.secondaryBorder,
        secondaryText = GC.secondaryText,
        secondaryHoverFill = GC.secondaryHoverFill,
        secondaryHoverBorder = GC.secondaryHoverBorder,
        secondaryPressedFill = GC.secondaryPressedFill,
        secondaryPressedText = GC.secondaryPressedText,
        dangerFill = GC.transparent,
        dangerBorder = GC.dangerBorder,
        dangerText = GC.dangerText,
        dangerHoverFill = GC.dangerHoverFill,
        dangerHover = GC.dangerText,
        dangerPressedFill = GC.dangerPressedFill,
        disabledFill = GC.disabledFill,
        disabledBorder = GC.disabledBorder,
        disabledText = GC.textDisabled,
        checkboxBorder = GC.checkboxBorder,
        checkboxHoverBorder = GC.checkboxHoverBorder,
        checkboxChecked = GC.checkboxChecked,
        checkboxCheckedHover = GC.checkboxCheckedHover,
        checkboxCheckedActive = GC.checkboxCheckedActive,
        switchOn = GC.switchOn,
        switchOnHover = GC.switchOnHover,
        switchOff = GC.switchOff,
        switchOffHover = GC.switchOffHover,
        switchKnobOn = GC.switchKnobOn,
        switchKnobOff = GC.switchKnobOff,
        tagBorder = GC.tagBorder,
        tagText = GC.tagText,
        tagHoverBorder = GC.tagHoverBorder,
        tagHoverText = GC.tagHoverText,
        tagSelected = GC.tagSelected,
        tagSelectedBorder = GC.tagSelectedBorder,
        tagSelectedText = GC.tagSelectedText,
        tagSelectedHover = GC.tagSelectedHover,
        segmentSelected = GC.segmentSelected,
        segmentText = GC.segmentText,
        toolHover = GC.toolHover,
        toolActive = GC.toolActive,
        toolOn = GC.toolOn,
        transparent = GC.transparent,
        white = GC.white,
        neutral = { 0.584, 0.616, 0.667, 1 },
        include = { 0.412, 0.620, 0.969, 1 },
        exclude = { 0.933, 0.443, 0.502, 1 },
    },
    metrics = {
        pageTitle = 24,
        title = 15,
        cardTitle = 18,
        section = 15,
        text = 13,
        control = 13,
        fieldValue = 15,
        button = 15,
        hint = 11,
        height = 30,
    },
}
EXUI.ModernTheme = MODERN
EXUI.ControlAppearance = MODERN
local MC = MODERN.colors

local function CompositeThemeColor(base, overlay, alphaOverride)
    local alpha = alphaOverride or overlay[4] or 1
    return {
        overlay[1] * alpha + base[1] * (1 - alpha),
        overlay[2] * alpha + base[2] * (1 - alpha),
        overlay[3] * alpha + base[3] * (1 - alpha),
        1,
    }
end

MODERN.checkboxPressedFill = CompositeThemeColor(MC.input, MC.toolActive)
MODERN.checkboxHoverFill = CompositeThemeColor(MC.input, MC.rowHover)
MODERN.switchOffHoverFill = CompositeThemeColor(MC.switchOff, MC.switchOffHover)
MODERN.settingsCardHoverFill = CompositeThemeColor(MC.subcard, MC.rowHover)
MODERN.settingsCardPressedFill = CompositeThemeColor(MC.subcard, MC.toolActive)
MODERN.settingsCardSelectedFill = CompositeThemeColor(MC.subcard, MC.tagSelected)
MODERN.settingsCardSelectedHoverFill = CompositeThemeColor(MC.subcard, MC.tagSelectedHover)

-- Blizzard_Menu compositor proxies deliberately disallow FontString:SetFont.
-- Build the two menu typography roles while this file is loading, then menu
-- initializers only bind the cached FontObject through the allowed API.
local function CreateModernMenuFontObject(globalName, size)
    local font = _G[globalName] or CreateFont(globalName)
    font:SetFont(defaultFontPath, size, "")
    font:SetTextColor(unpack(GC.white))
    if font.SetShadowOffset then font:SetShadowOffset(0, 0) end
    return font
end

MODERN.menuFonts = {
    control = CreateModernMenuFontObject("ExwindCoreModernMenuControlFont", MODERN.metrics.fieldValue),
    title = CreateModernMenuFontObject("ExwindCoreModernMenuTitleFont", MODERN.metrics.title),
}

-- Compatibility palettes are retained for callers which select a typography
-- role.  Their controls still use the same modern geometry and state painter.
MODERN.DungeonAura = {
    row = 42, buttonWidth = 62, buttonHeight = 24, gap = 8,
    text = MC.text, muted = MC.muted, title = MC.lightBlue, fact = MC.lightBlue,
    value = MC.text, focus = MC.focus, success = MC.lightBlue,
    warning = { .97, .72, .38, 1 }, danger = { .97, .45, .47, 1 },
    input = MC.input, inputBorder = MC.inputBorder, inputFocus = MC.inputFocusBorder,
    header = MC.header, panel = MC.panel, panelDeep = MC.input,
    line = MC.headerDivider, lineStrong = MC.border, button = MC.raised,
    hover = MC.hover, gold = MC.lightBlue,
}
MODERN.LoadCard = setmetatable({
    id = "load-card", row = 52, buttonHeight = 26, buttonWidth = 88,
    text = MC.text, value = MC.text, title = MC.text, muted = MC.muted,
    fact = MC.lightBlue, focus = MC.focus, background = MC.background,
    header = MC.header, panelDeep = MC.input, panel = MC.panel,
    input = MC.input, inputFocus = MC.inputFocusBorder, inputBorder = MC.inputBorder,
    button = MC.raised, hover = MC.hover, line = MC.border,
    lineStrong = MC.border, gold = MC.lightBlue,
    choiceFill = MC.lightBlue, choiceText = MC.background,
}, { __index = MODERN.DungeonAura })

function EXUI:SetControlAppearance(root, appearance)
    assert(appearance == nil or appearance == "flat" or appearance == "default" or appearance == "modern",
        "Unknown control appearance")
    root._exControlAppearance = appearance
end

function EXUI:GetControlAppearance(root)
    while root do
        if root._exControlAppearance then return root._exControlAppearance end
        root = root.GetParent and root:GetParent()
    end
    return "modern"
end

function EXUI:SetControlFontSize(root, size)
    assert(size == nil or (type(size) == "number" and size >= 10 and size <= 24), "Invalid control font size")
    root._exControlFontSize = size
end

function EXUI:GetControlFontSize(root)
    while root do
        if root._exControlFontSize then return root._exControlFontSize end
        root = root.GetParent and root:GetParent()
    end
end

function EXUI:SetControlFontStyle(root, style)
    assert(style == nil or style == "settings" or style == "dungeon-aura" or style == "load-card",
        "Unknown control font style")
    root._exControlFontStyle = style
end

function EXUI:GetControlFontStyle(root)
    while root do
        if root._exControlFontStyle then return root._exControlFontStyle end
        root = root.GetParent and root:GetParent()
    end
end

function MODERN.GetReference(frame)
    local style = EXUI:GetControlFontStyle(frame)
    return style == "load-card" and MODERN.LoadCard
        or (style == "dungeon-aura" and MODERN.DungeonAura or nil)
end

function MODERN.ReferenceText(region, template, size, color, flags)
    if not region then return end
    local font = _G[template] or template
    region:SetFontObject(font)
    if font and font.GetFont then
        local path, referenceSize, referenceFlags = font:GetFont()
        if path and region.SetFont then
            region:SetFont(path, size or referenceSize, flags == nil and (referenceFlags or "") or flags)
        end
    end
    region:SetTextColor(unpack(color or MC.text))
    if region.SetShadowOffset then region:SetShadowOffset(0, 0) end
end

function MODERN.Font(region, size, color, flags, template)
    if not region or not region.SetFont then return end
    local reference = MODERN.GetReference(region)
    if reference then
        MODERN.ReferenceText(region, template or "GameFontHighlight", size, color or reference.text, flags)
        return
    end
    local path = region:GetFont()
    if EXUI:GetControlFontStyle(region) == "settings" then
        path = ExwindTools.MAIN_FONT or path
    end
    path = path or defaultFontPath
    region:SetFont(path, size or MODERN.metrics.text, flags or "")
    region:SetTextColor(unpack(color or MC.text))
    if region.SetShadowOffset then region:SetShadowOffset(0, 0) end
end

MODERN.typography = {
    pageTitle = { size = MODERN.metrics.pageTitle, color = MC.text, template = "GameFontHighlight" },
    title = { size = MODERN.metrics.title, color = MC.text, template = "GameFontHighlight" },
    cardTitle = { size = MODERN.metrics.cardTitle, color = MC.text, template = "GameFontHighlight" },
    body = { size = MODERN.metrics.text, color = MC.text, template = "GameFontHighlight" },
    control = { size = MODERN.metrics.control, color = MC.text, template = "GameFontHighlight" },
    fieldValue = { size = MODERN.metrics.fieldValue, color = MC.text, template = "GameFontHighlight" },
    button = { size = MODERN.metrics.button, color = MC.text, template = "GameFontHighlight" },
    hint = { size = MODERN.metrics.hint, color = MC.placeholder, template = "GameFontHighlightSmall" },
}

function MODERN.ApplyTextRole(region, role, color, template)
    local spec = MODERN.typography[role] or MODERN.typography.body
    MODERN.Font(region, spec.size, color or spec.color, "", template or spec.template)
end

local function StyleModernTitle(region, color)
    MODERN.ApplyTextRole(region, "title", color)
end

-- The former flat appearance allocated parallel pools.  All appearances now
-- resolve to the same pool so a composite can never retain a visually foreign
-- child, while the public compatibility methods remain callable.
function EXUI:ResolveControlPool(poolType)
    return poolType
end

function EXUI:AcquireControl(poolType, parent)
    return _G.ExwindFactory:Acquire(poolType, parent)
end

local function HideControlSkin(frame)
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    if frame.Background then frame.Background:SetAlpha(0) end
    if frame.Arrow then frame.Arrow:SetAlpha(0) end
    -- SharedButtonLargeTemplate is a ThreeSliceButtonTemplate.  Its native
    -- Left/Center/Right art is not returned by GetNormalTexture(), and
    -- ThreeSliceButtonMixin:UpdateButton refreshes the atlas on every state
    -- transition.  Keep the regions owned by that template transparent while
    -- leaving our separately allocated modern surface untouched.
    for _, key in ipairs({ "Left", "Center", "Right" }) do
        local texture = frame[key]
        if texture and texture.SetAlpha then texture:SetAlpha(0) end
    end
    for _, method in ipairs({ "GetNormalTexture", "GetHighlightTexture", "GetPushedTexture", "GetDisabledTexture" }) do
        local texture = frame[method] and frame[method](frame)
        if texture then texture:SetAlpha(0) end
    end
end

local function StripCheckButtonStateTextures(button)
    if not button or button._exModernNativeCheckStripped then return end

    -- MinimalCheckboxTemplate binds its native state textures to the CheckButton.  A
    -- row-wide hit target makes those textures stretch across the label, so
    -- merely lowering their alpha is not sufficient: state changes can show
    -- them again. Clear the asset on every state texture that actually exists.
    -- Button:Set*Texture requires an asset on the current client, so an absent
    -- state is skipped instead of trying to detach it through a nil setter.
    local states = {
        { "GetNormalTexture", "NormalTexture" },
        { "GetPushedTexture", "PushedTexture" },
        { "GetHighlightTexture", "HighlightTexture" },
        { "GetDisabledTexture", "DisabledTexture" },
        { "GetCheckedTexture", "CheckedTexture" },
        { "GetDisabledCheckedTexture", "DisabledCheckedTexture" },
    }
    for _, state in ipairs(states) do
        local texture = button[state[1]] and button[state[1]](button) or button[state[2]]
        if texture then
            texture:SetTexture(nil)
            texture:SetAlpha(0)
            texture:Hide()
        end
    end
    button._exModernNativeCheckStripped = true
end

local modernSurfaceFrames = setmetatable({}, { __mode = "k" })
local modernSurfaceScaleWatcher

local function TrackModernSurfaceFrame(frame)
    modernSurfaceFrames[frame] = true
    if modernSurfaceScaleWatcher then return end
    modernSurfaceScaleWatcher = CreateFrame("Frame")
    modernSurfaceScaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
    modernSurfaceScaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    modernSurfaceScaleWatcher:SetScript("OnEvent", function()
        -- UI scale may change without changing a control's logical width/height.
        -- Re-run every cached surface layout so its logical inset continues to
        -- resolve to one physical pixel at the new effective scale.
        for owner in pairs(modernSurfaceFrames) do
            for _, cachedSkin in pairs(owner._exModernSurfaces or {}) do
                if cachedSkin.Layout then cachedSkin.Layout() end
            end
        end
    end)
end

MODERN.surfaceAtlas = {
    file = MODERN_MEDIA .. "SurfaceBorderAtlas.tga",
    width = 512,
    height = 256,
    cell = 34,
    columns = 15,
    maxRadius = 32,
}

function MODERN.surfaceAtlas:GetPixel(frame)
    local effectiveScale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    effectiveScale = type(effectiveScale) == "number" and effectiveScale > 0 and effectiveScale or 1
    local pixelUtil = _G.PixelUtil
    local pixel = pixelUtil and pixelUtil.GetNearestPixelSize
        and pixelUtil.GetNearestPixelSize(0, effectiveScale, 1)
        or (1 / effectiveScale)
    return type(pixel) == "number" and pixel > 0 and pixel or (1 / effectiveScale)
end

function MODERN.surfaceAtlas:GetMetrics(frame, radius, borderPixels)
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not width or not height or width <= 0 or height <= 0 then return nil end
    local pixel = self:GetPixel(frame)
    local widthPixels = math.max(1, math.floor(width / pixel + .5))
    local heightPixels = math.max(1, math.floor(height / pixel + .5))
    local radiusPixels = math.max(0, math.min(self.maxRadius,
        math.floor((tonumber(radius) or 0) / pixel + .5),
        math.floor(widthPixels / 2), math.floor(heightPixels / 2)))
    local strokePixels = math.max(1, math.min(2, math.floor((tonumber(borderPixels) or 1) + .5)))
    local left, top = frame.GetLeft and frame:GetLeft(), frame.GetTop and frame:GetTop()
    local offsetX, offsetY = 0, 0
    if type(left) == "number" then offsetX = math.floor(left / pixel + .5) * pixel - left end
    if type(top) == "number" then offsetY = math.floor(top / pixel + .5) * pixel - top end
    return {
        pixel = pixel,
        widthPixels = widthPixels,
        heightPixels = heightPixels,
        radiusPixels = radiusPixels,
        strokePixels = strokePixels,
        offsetX = offsetX,
        offsetY = offsetY,
    }
end

function MODERN.surfaceAtlas:ConfigureTexture(texture)
    texture:SetTexture(self.file, "CLAMP", "CLAMP", "NEAREST")
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
end

function MODERN.surfaceAtlas:SetSolidTexCoord(texture)
    texture:SetTexCoord((self.width - 1) / self.width, 1, (self.height - 1) / self.height, 1)
end

function MODERN.surfaceAtlas:SetCornerTexCoord(texture, radiusPixels, band, row, col)
    local index = band * self.maxRadius + radiusPixels - 1
    local x = (index % self.columns) * self.cell + 1
    local y = math.floor(index / self.columns) * self.cell + 1
    local left, right = x / self.width, (x + radiusPixels) / self.width
    local top, bottom = y / self.height, (y + radiusPixels) / self.height
    if col == 3 then left, right = right, left end
    if row == 3 then top, bottom = bottom, top end
    texture:SetTexCoord(left, right, top, bottom)
end

local function GetModernSurface(frame, radius)
    frame._exModernSurfaces = frame._exModernSurfaces or {}
    local skin = frame._exModernSurfaces[radius]
    if skin then
        TrackModernSurfaceFrame(frame)
        return skin
    end

    skin = { pieces = {}, radius = radius, active = false }
    frame._exModernSurfaces[radius] = skin
    TrackModernSurfaceFrame(frame)
    for row = 1, 3 do
        for col = 1, 3 do
            local texture = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
            MODERN.surfaceAtlas:ConfigureTexture(texture)
            skin.pieces[#skin.pieces + 1] = {
                texture = texture, row = row, col = col, layer = 2,
                kind = (row ~= 2 and col ~= 2) and "fillCorner" or "fillSolid",
            }
        end
    end
    for _, corner in ipairs({ { 1, 1 }, { 1, 3 }, { 3, 1 }, { 3, 3 } }) do
        local row, col = corner[1], corner[2]
        local texture = frame:CreateTexture(nil, "BORDER", nil, 0)
        MODERN.surfaceAtlas:ConfigureTexture(texture)
        skin.pieces[#skin.pieces + 1] = {
            texture = texture, row = row, col = col, layer = 1, kind = "borderCorner",
        }
    end
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local texture = frame:CreateTexture(nil, "BORDER", nil, 1)
        MODERN.surfaceAtlas:ConfigureTexture(texture)
        MODERN.surfaceAtlas:SetSolidTexCoord(texture)
        skin.pieces[#skin.pieces + 1] = {
            texture = texture, layer = 1, kind = "borderEdge", side = side,
        }
    end
    skin.Layout = function()
        -- OnSizeChanged / OnShow hooks live for the frame lifetime.  A surface
        -- that was explicitly cleared must stay cleared across later layout
        -- passes instead of letting this cached skin resurrect its pieces.
        if skin.active ~= true then
            for _, piece in ipairs(skin.pieces) do piece.texture:Hide() end
            return
        end
        local metrics = MODERN.surfaceAtlas:GetMetrics(frame, radius, skin.borderPixels)
        if not metrics then return end
        local pixel = metrics.pixel
        local width = metrics.widthPixels * pixel
        local height = metrics.heightPixels * pixel
        local corner = metrics.radiusPixels * pixel
        local thickness = metrics.strokePixels * pixel
        local xs = {
            metrics.offsetX,
            metrics.offsetX + corner,
            metrics.offsetX + width - corner,
            metrics.offsetX + width,
        }
        local ys = { 0, corner, height - corner, height }
        local degenerateBorder = metrics.widthPixels <= metrics.strokePixels * 2
            or metrics.heightPixels <= metrics.strokePixels * 2
        for _, piece in ipairs(skin.pieces) do
            piece.texture:ClearAllPoints()
            if metrics.radiusPixels == 0 and piece.layer == 2 then
                if piece.row == 2 and piece.col == 2 then
                    MODERN.surfaceAtlas:SetSolidTexCoord(piece.texture)
                    piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.offsetX, metrics.offsetY)
                    piece.texture:SetSize(width, height)
                    piece.texture:Show()
                else
                    piece.texture:Hide()
                end
            elseif degenerateBorder and piece.layer == 1 then
                if piece.kind == "borderEdge" and piece.side == "TOP" then
                    MODERN.surfaceAtlas:SetSolidTexCoord(piece.texture)
                    piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.offsetX, metrics.offsetY)
                    piece.texture:SetSize(width, height)
                    piece.texture:Show()
                else
                    piece.texture:Hide()
                end
            elseif piece.kind == "borderEdge" then
                MODERN.surfaceAtlas:SetSolidTexCoord(piece.texture)
                piece.texture:ClearAllPoints()
                if piece.side == "TOP" then
                    piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", xs[2], metrics.offsetY)
                    piece.texture:SetSize(math.max(.001, width - corner * 2), thickness)
                    piece.texture:SetShown(width > corner * 2)
                elseif piece.side == "BOTTOM" then
                    piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", xs[2], metrics.offsetY - height + thickness)
                    piece.texture:SetSize(math.max(.001, width - corner * 2), thickness)
                    piece.texture:SetShown(width > corner * 2)
                elseif piece.side == "LEFT" then
                    piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.offsetX, metrics.offsetY - corner)
                    piece.texture:SetSize(thickness, math.max(.001, height - corner * 2))
                    piece.texture:SetShown(height > corner * 2)
                else
                    piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.offsetX + width - thickness, metrics.offsetY - corner)
                    piece.texture:SetSize(thickness, math.max(.001, height - corner * 2))
                    piece.texture:SetShown(height > corner * 2)
                end
            else
                local pieceWidth = xs[piece.col + 1] - xs[piece.col]
                local pieceHeight = ys[piece.row + 1] - ys[piece.row]
                if piece.kind == "fillCorner" then
                    MODERN.surfaceAtlas:SetCornerTexCoord(piece.texture,
                        metrics.radiusPixels, 0, piece.row, piece.col)
                elseif piece.kind == "borderCorner" then
                    MODERN.surfaceAtlas:SetCornerTexCoord(piece.texture,
                        metrics.radiusPixels, metrics.strokePixels, piece.row, piece.col)
                else
                    MODERN.surfaceAtlas:SetSolidTexCoord(piece.texture)
                end
                piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", xs[piece.col], metrics.offsetY - ys[piece.row])
                piece.texture:SetSize(math.max(.001, pieceWidth), math.max(.001, pieceHeight))
                piece.texture:SetShown(pieceWidth > 0 and pieceHeight > 0)
            end
        end
    end
    frame:HookScript("OnSizeChanged", skin.Layout)
    frame:HookScript("OnShow", skin.Layout)
    return skin
end

function EXUI:SetControlSurface(frame, radius, fill, border)
    if not frame then return end
    radius = radius == 10 and 10 or 4
    HideControlSkin(frame)
    for _, other in pairs(frame._exModernSurfaces or {}) do
        other.active = false
        for _, piece in ipairs(other.pieces) do piece.texture:Hide() end
    end
    local skin = GetModernSurface(frame, radius)
    skin.active = true
    skin.fill = fill or MC.input
    for _, piece in ipairs(skin.pieces) do
        local color = piece.layer == 1 and (border or MC.border) or (fill or MC.input)
        -- Solid pieces stay white so button transitions and settings-list
        -- capture/restore can continue treating vertex color as surface RGBA.
        piece.texture:SetVertexColor(unpack(color))
        piece.texture:Show()
    end
    skin.Layout()
end

function EXUI:ClearControlSurface(frame)
    if not frame then return end
    HideControlSkin(frame)
    for _, skin in pairs(frame._exModernSurfaces or {}) do
        skin.active = false
        for _, piece in ipairs(skin.pieces) do piece.texture:Hide() end
    end
end

function EXUI:ApplyModernPanel(frame, elevated)
    self:SetControlSurface(frame, 10, elevated and MC.raised or MC.panel, MC.border)
    return frame
end

-- Shared text-button geometry and finite native transitions; no Lua frame polling.
local BUTTON_STYLE = { paddingX = 16, paddingY = 6, minWidth = 104, radius = 4, transition = .12 }
MODERN.buttonStyle = BUTTON_STYLE
MODERN.buttonFont = CreateModernMenuFontObject("ExwindCoreModernButtonFont", MODERN.metrics.button)

local function SetButtonRegionColor(region, color, animate, isText)
    local cache = region._exButtonColor
    local target = { color[1], color[2], color[3], color[4] or 1 }
    local function apply(value)
        if isText then region:SetTextColor(unpack(value)) else region:SetVertexColor(unpack(value)) end
    end
    if cache and cache.target then
        local same = true
        for i = 1, 4 do if cache.target[i] ~= target[i] then same = false; break end end
        if same and animate then return end
    end
    if not cache then
        cache = {}
        region._exButtonColor = cache
        cache.group = region:CreateAnimationGroup()
        cache.animation = cache.group:CreateAnimation("VertexColor")
        cache.animation:SetDuration(BUTTON_STYLE.transition)
        cache.animation:SetSmoothing("NONE")
        cache.group:SetScript("OnFinished", function() apply(cache.target) end)
    end
    local start = cache.target or target
    if cache.group:IsPlaying() and cache.start then
        local progress = cache.animation:GetProgress()
        start = {}
        for i = 1, 4 do start[i] = cache.start[i] + (cache.target[i] - cache.start[i]) * progress end
    end
    cache.group:Stop()
    cache.start, cache.target = start, target
    if animate then
        apply(start)
        cache.animation:SetStartColor(CreateColor(unpack(start)))
        cache.animation:SetEndColor(CreateColor(unpack(target)))
        cache.group:Play()
    else
        apply(target)
    end
end

-- Resolve the existing container surface for translucent button state colors.
-- The shared input surface uses an outer fill and an inset fill, so composite
-- alpha here instead of introducing a second rounded-border renderer.
local function GetButtonBackground(frame)
    local parent = frame:GetParent()
    while parent do
        for _, skin in pairs(parent._exModernSurfaces or {}) do
            if skin.fill and skin.pieces[1] and skin.pieces[1].texture:IsShown() then
                return skin.fill
            end
        end
        parent = parent:GetParent()
    end
    return MC.panel
end

local function PaintTextButtonSurface(frame, fill, edge, text, enabled)
    local background = GetButtonBackground(frame)
    local alpha = fill[4] or 1
    local surfaceFill = {
        fill[1] * alpha + background[1] * (1 - alpha),
        fill[2] * alpha + background[2] * (1 - alpha),
        fill[3] * alpha + background[3] * (1 - alpha),
        1,
    }
    local animate = frame:IsShown() and frame._exButtonPainted == true
    -- Exactly the same R4 mask, nine-slice layout and physical-pixel border
    -- as input boxes and dropdown controls. No button-only outline geometry.
    EXUI:SetControlSurface(frame, BUTTON_STYLE.radius, surfaceFill, edge)
    for _, piece in ipairs(frame._exModernSurfaces[BUTTON_STYLE.radius].pieces) do
        SetButtonRegionColor(piece.texture, piece.layer == 1 and edge or surfaceFill, animate)
    end
    local focused = enabled and frame:IsShown() and frame._exButtonKeyboardFocused == true
    local focus = frame._exButtonFocusSurface
    if focused then
        if not focus then
            focus = CreateFrame("Frame", nil, frame:GetParent())
            focus:EnableMouse(false)
            frame._exButtonFocusSurface = focus
        end
        focus:SetParent(frame:GetParent())
        focus:SetFrameStrata(frame:GetFrameStrata())
        focus:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
        local scale = frame:GetEffectiveScale()
        local pixel = PixelUtil and PixelUtil.GetNearestPixelSize(1, scale, 1) or 1 / scale
        focus:ClearAllPoints()
        focus:SetPoint("TOPLEFT", frame, "TOPLEFT", -4 * pixel, 4 * pixel)
        focus:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4 * pixel, -4 * pixel)
        GetModernSurface(focus, BUTTON_STYLE.radius).borderPixels = 2
        EXUI:SetControlSurface(focus, BUTTON_STYLE.radius, background, MC.focusRing)
        focus:Show()
    elseif focus then
        focus:Hide()
    end
    local label = frame:GetFontString()
    if label then SetButtonRegionColor(label, text, animate, true) end
    frame._exButtonPainted = true
end

local function EnsureSidebarNavigationParts(frame)
    -- Hot-reloaded/pooled buttons may still carry the retired rectangular fill.
    -- Keep it hidden; the shared R4 control surface below owns the background.
    if frame._exSidebarBackground then
        if frame._exSidebarBackground._exButtonColor then
            frame._exSidebarBackground._exButtonColor.group:Stop()
        end
        frame._exSidebarBackground:Hide()
    end
    -- Selected navigation now uses the rounded row background alone. Hide the
    -- retired accent on already-created pooled buttons and do not create it for
    -- new leases; label geometry intentionally stays unchanged.
    if frame._exSidebarAccent then
        frame._exSidebarAccent:SetAlpha(0)
        frame._exSidebarAccent:Hide()
    end
end

local function EnsureTextButtonFontString(frame)
    if frame._exButtonPresentation == "sidebar" then
        local label = frame._exSidebarLabel
        if not label then
            label = EXUI:CreateVisualFontString(frame, EXFONTFRAME)
            frame._exSidebarLabel = label
        end
        label:SetFontObject(MODERN.menuFonts.control)
        local nativeLabel = frame.GetFontString and frame:GetFontString()
        if nativeLabel and nativeLabel ~= label then
            nativeLabel:SetText("")
            nativeLabel:Hide()
        end
        label:Show()
        return label
    end
    if frame._exSidebarLabel then
        frame._exSidebarLabel:SetText("")
        frame._exSidebarLabel:Hide()
    end
    local label = frame.GetFontString and frame:GetFontString()
    if label then
        label:Show()
        return label
    end
    label = EXUI:CreateVisualFontString(frame, EXFONTFRAME)
    label:SetFontObject(MODERN.buttonFont)
    frame:SetFontString(label)
    frame._exOwnedButtonFontString = label
    return label
end

local function LayoutSidebarNavigationButton(frame)
    local level = tonumber(frame._exSidebarLevel) or 0
    local label = EnsureTextButtonFontString(frame)
    -- SharedButtonLargeTemplate reapplies its state FontObject after hover,
    -- selection and pooled reuse. Keep every native state on the navigation
    -- font so it cannot restore the ordinary button size mid-session.
    frame:SetNormalFontObject(MODERN.menuFonts.control)
    frame:SetHighlightFontObject(MODERN.menuFonts.control)
    frame:SetDisabledFontObject(MODERN.menuFonts.control)
    local nativeLabel = frame.GetFontString and frame:GetFontString()
    if nativeLabel and nativeLabel ~= label then
        nativeLabel:SetText("")
        nativeLabel:Hide()
    end
    label:ClearAllPoints()
    label:SetPoint("LEFT", frame, "LEFT", level > 0 and 18 or 10, 0)
    label:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    label:SetFontObject(MODERN.menuFonts.control)
    label:SetScale(1)
    frame.label = label
end

local function PaintSidebarNavigationButton(frame, enabled)
    EnsureSidebarNavigationParts(frame)
    LayoutSidebarNavigationButton(frame)

    local selected = frame._exSidebarSelected == true
    local hovered = frame._exModernHover == true
    local fill = MC.transparent
    local text = GC.shell.sidebarIdleText

    if not enabled then
        text = GC.shell.sidebarDisabledText
    elseif selected then
        fill = hovered and MC.menuSelectedHover or MC.menuSelected
        text = GC.shell.sidebarActiveText
    elseif hovered then
        fill = MC.secondaryHoverFill
        text = GC.shell.sidebarHoverText
    end

    local animate = frame:IsShown() and frame._exButtonPainted == true
    -- Use the same R4 nine-slice owned by the shared button implementation.
    -- Border and fill intentionally share one color, so transparent/idle rows
    -- remain borderless while hover and selected backgrounds gain round corners.
    EXUI:SetControlSurface(frame, BUTTON_STYLE.radius, fill, fill)
    local surface = frame._exModernSurfaces and frame._exModernSurfaces[BUTTON_STYLE.radius]
    for _, piece in ipairs(surface and surface.pieces or {}) do
        SetButtonRegionColor(piece.texture, fill, animate)
    end
    if frame._exSidebarAccent then
        frame._exSidebarAccent:SetAlpha(0)
        frame._exSidebarAccent:Hide()
    end
    local label = frame.label or EnsureTextButtonFontString(frame)
    if label then SetButtonRegionColor(label, text, animate, true) end
    if frame._exButtonFocusSurface then frame._exButtonFocusSurface:Hide() end
    frame._exButtonPainted = true
end

local function PaintModernButton(frame)
    local enabled = not frame.IsEnabled or frame:IsEnabled()
    if frame._exButtonPresentation == "sidebar" and frame._gridType == "GridButton" then
        PaintSidebarNavigationButton(frame, enabled)
        return
    end
    if frame._exSidebarBackground then
        if frame._exSidebarBackground._exButtonColor then
            frame._exSidebarBackground._exButtonColor.group:Stop()
        end
        frame._exSidebarBackground:Hide()
    end
    if frame._exSidebarAccent then frame._exSidebarAccent:Hide() end
    local variant = frame._exButtonVariant or "secondary"
    local isColorButton = frame._gridType == "GridColorButton"
    local fill, edge, text

    if isColorButton then
        fill, edge, text = MC.input, MC.inputBorder, MC.text
        if frame._exModernPressed and enabled then
            fill, edge = MC.input, MC.blue
        elseif frame._exModernHover and enabled then
            fill, edge, text = MC.input, MC.inputHoverBorder, MC.text
        end
    elseif variant == "primary" then
        fill, edge, text = MC.primaryFill, MC.primaryFill, MC.primaryText
        if frame._exModernPressed and enabled then
            fill, edge = MC.primaryPressed, MC.primaryPressed
        elseif frame._exModernHover and enabled then
            fill, edge = MC.primaryHover, MC.primaryHover
        end
    elseif variant == "danger" then
        fill, edge, text = MC.dangerFill, MC.dangerBorder, MC.dangerText
        if frame._exModernPressed and enabled then
            fill, edge, text = MC.dangerPressedFill, MC.dangerBorder, MC.dangerBorder
        elseif frame._exModernHover and enabled then
            fill, edge, text = MC.dangerHoverFill, MC.dangerHover, MC.dangerHover
        end
    else
        fill, edge, text = MC.secondaryFill, MC.secondaryBorder, MC.secondaryText
        if frame._exModernPressed and enabled then
            fill, edge, text = MC.secondaryPressedFill, MC.secondaryBorder, MC.secondaryPressedText
        elseif frame._exModernHover and enabled then
            fill, edge, text = MC.secondaryHoverFill, MC.secondaryHoverBorder, MC.white
        end
    end

    if not enabled then
        fill, edge, text = MC.disabledFill, MC.disabledBorder, MC.disabledText
    end
    if not isColorButton then
        PaintTextButtonSurface(frame, fill, edge, text, enabled)
    else
        EXUI:SetControlSurface(frame, 4, fill, edge)
        local label = frame.GetFontString and frame:GetFontString() or frame.label
        if label then label:SetTextColor(unpack(text)) end
    end
    -- 颜色按钮除了整块底色，也让预览色块的细边框一起响应。
    -- 这样即使背景色差在某些显示器上不明显，鼠标提示仍然清楚。
    if isColorButton and frame.swatchBorder then
        if not enabled then
            frame.swatchBorder:SetBackdropBorderColor(unpack(MC.disabledText))
        elseif frame._exModernPressed then
            frame.swatchBorder:SetBackdropBorderColor(unpack(MC.blue))
        elseif frame._exModernHover then
            frame.swatchBorder:SetBackdropBorderColor(unpack(MC.inputHoverBorder))
        else
            frame.swatchBorder:SetBackdropBorderColor(unpack(MC.inputBorder))
        end
    end
end

-- A keyboard-navigation owner supplies focus; this does not install key handlers.
function EXUI:SetButtonKeyboardFocus(button, focused)
    if not button or button._gridType ~= "GridButton" then return end
    button._exButtonKeyboardFocused = focused == true
    PaintModernButton(button)
end

local function ApplyModernButton(frame)
    -- 点击与悬停在新客户端可分别受控。颜色按钮过去只恢复了 EnableMouse，
    -- 因而在部分池化复用路径里会出现“可以点击但没有 OnEnter/OnLeave”。
    -- 这里在所有 EXUI 按钮的共用入口一次补齐；下方只读观察器负责校正池化后的悬停状态。
    if frame.EnableMouse then frame:EnableMouse(true) end
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(true) end
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(true) end
    -- Match inputs and checkboxes: native pointer scripts remain useful for
    -- immediate feedback, while this mouse-disabled observer keeps hover state
    -- correct after a pooled frame has been hidden, reset and borrowed again.
    -- It paints only when enabled/hover state changes and never owns clicks.
    if not frame._exModernButtonVisual then
        local visual = CreateFrame("Frame", nil, frame)
        visual:EnableMouse(false)
        visual:SetScript("OnUpdate", function(self)
            local enabled = not frame.IsEnabled or frame:IsEnabled()
            local hover = enabled and frame:IsMouseOver() or false
            if self.enabled ~= enabled or self.hover ~= hover then
                self.enabled, self.hover = enabled, hover
                frame._exModernHover = hover
                PaintModernButton(frame)
            end
        end)
        visual:SetScript("OnHide", function(self)
            self.enabled, self.hover = nil, nil
            frame._exModernHover = nil
        end)
        frame._exModernButtonVisual = visual
    end
    -- HookScript callbacks live for the frame lifetime; StandardReset only
    -- clears primary SetScript handlers. Keep this marker across pool leases so
    -- pointer painters are installed exactly once instead of accumulating.
    if not frame._exModernButtonPointerHooks then
        frame._exModernButtonPointerHooks = true
        frame:HookScript("OnEnter", function(self) self._exModernHover = true; PaintModernButton(self) end)
        frame:HookScript("OnLeave", function(self) self._exModernHover = false; self._exModernPressed = false; PaintModernButton(self) end)
        frame:HookScript("OnMouseDown", function(self, button) if button == "LeftButton" then self._exModernPressed = true; PaintModernButton(self) end end)
        frame:HookScript("OnMouseUp", function(self) self._exModernPressed = false; PaintModernButton(self) end)
    end
    -- These slots are not cleared by the pool and therefore remain lifetime
    -- hooks. Keeping a separate marker prevents duplicate callbacks on reuse.
    if not frame._exModernButtonLifecycleHooks then
        frame._exModernButtonLifecycleHooks = true
        frame:HookScript("OnEnable", PaintModernButton)
        frame:HookScript("OnDisable", PaintModernButton)
        frame:HookScript("OnShow", PaintModernButton)
        frame:HookScript("OnHide", function(self)
            self._exModernHover = nil
            self._exModernPressed = nil
            self._exButtonKeyboardFocused = nil
            self._exButtonPainted = nil
            if self._exButtonFocusSurface then self._exButtonFocusSurface:Hide() end
            local skin = self._exModernSurfaces and self._exModernSurfaces[BUTTON_STYLE.radius]
            for _, piece in ipairs(skin and skin.pieces or {}) do
                if piece.texture._exButtonColor then piece.texture._exButtonColor.group:Stop() end
            end
            local label = self._exSidebarLabel or self:GetFontString()
            if label and label._exButtonColor then label._exButtonColor.group:Stop() end
        end)
    end
    HideControlSkin(frame)
    if frame._gridType == "GridColorButton" then
        frame:SetPushedTextOffset(0, -1)
        MODERN.ApplyTextRole(frame.GetFontString and frame:GetFontString() or frame.label, "title")
    else
        frame:SetPushedTextOffset(0, 0)
        frame:SetNormalFontObject(MODERN.buttonFont)
        frame:SetHighlightFontObject(MODERN.buttonFont)
        frame:SetDisabledFontObject(MODERN.buttonFont)
        -- FontObject assignment can restore its default text color on a reused button.
        frame._exButtonPainted = nil
    end
    PaintModernButton(frame)
end

local function PaintModernInput(surface, editBox)
    local enabled = not editBox or not editBox.IsEnabled or editBox:IsEnabled()
    local focus = enabled and editBox and editBox.HasFocus and editBox:HasFocus()
    local hover = enabled and editBox and editBox._exModernHover
    local focusBorder = surface and surface._exModernInputFocusBorder or MC.inputFocusBorder
    local idleFill = surface and surface._exModernInputIdleFill or MC.input
    local activeFill = surface and surface._exModernInputActiveFill or idleFill
    local hoverBorder = surface and surface._exModernInputHoverBorder or MC.inputHoverBorder
    local fill = enabled and ((focus or hover) and activeFill or idleFill) or MC.inputDisabled
    local idleBorder = surface and surface._exModernInputIdleBorder or MC.inputBorder
    local edge = enabled and (focus and focusBorder or (hover and hoverBorder or idleBorder))
        or MC.inputDisabledBorder
    EXUI:SetControlSurface(surface, 4, fill, edge)
    -- The input's own focus border above is the complete focus treatment.
    -- Hide a ring left by an earlier hot-reloaded lease instead of drawing a
    -- second translucent outline outside the control.
    if surface and surface._exModernInputFocusRing then
        surface._exModernInputFocusRing:Hide()
    end
    if editBox and editBox.SetTextColor then
        editBox:SetTextColor(unpack(enabled and MC.text or MC.disabledText))
    end
end

local function ApplyModernInput(frame)
    local editBox = frame.editBox or frame
    if not frame._exModernInputVisual then
        -- This non-interactive child only reads native visual state. The page
        -- and pool remain free to replace the EditBox's business scripts.
        local visual = CreateFrame("Frame", nil, editBox)
        visual:EnableMouse(false)
        visual:SetScript("OnUpdate", function(self)
            local enabled = not editBox.IsEnabled or editBox:IsEnabled()
            local hover = enabled and editBox:IsMouseOver() or false
            local focus = enabled and editBox:HasFocus() or false
            if self.enabled ~= enabled or self.hover ~= hover or self.focus ~= focus then
                self.enabled, self.hover, self.focus = enabled, hover, focus
                editBox._exModernHover = hover
                PaintModernInput(frame, editBox)
            end
        end)
        visual:SetScript("OnHide", function(self)
            self.enabled, self.hover, self.focus = nil, nil, nil
            editBox._exModernHover = nil
        end)
        frame._exModernInputVisual = visual
    end
    if editBox.SetTextInsets then editBox:SetTextInsets(9, 9, editBox == frame and 0 or 7, editBox == frame and 0 or 7) end
    MODERN.ApplyTextRole(editBox, "fieldValue")
    MODERN.ApplyTextRole(frame.placeholder, "hint")
    PaintModernInput(frame, editBox)
end

local function PaintModernDropdown(frame)
    local enabled = frame:IsEnabled()
    local menuOpen = enabled and frame.IsMenuOpen and frame:IsMenuOpen()
    local active = enabled and (frame._exModernHover or menuOpen)
    EXUI:SetControlSurface(frame, 4, enabled and MC.input or MC.inputDisabled,
        enabled and (menuOpen and MC.inputFocusBorder or (active and MC.inputHoverBorder or MC.inputBorder))
            or MC.inputDisabledBorder)
    if frame.Text then frame.Text:SetTextColor(unpack(enabled and MC.text or MC.disabledText)) end
    if frame._exModernChevron then
        frame._exModernChevron:SetRotation(menuOpen and math.pi or 0)
        frame._exModernChevron:SetVertexColor(unpack(enabled and (menuOpen and MC.blue
            or (active and MC.white or MC.muted)) or MC.disabledText))
    end
end

local function ApplyModernDropdown(frame)
    frame:SetHeight(MODERN.metrics.height)
    frame._exGridFixedHeight = MODERN.metrics.height
    if not frame._exModernChevron then
        local chevron = frame:CreateTexture(nil, "OVERLAY")
        chevron:SetTexture(MODERN_MEDIA .. "GlyphChevron.tga", "CLAMP", "CLAMP", "LINEAR")
        chevron:SetSize(16, 16)
        chevron:SetPoint("RIGHT", -8, 0)
        frame._exModernChevron = chevron
    end
    frame.Text:ClearAllPoints()
    frame.Text:SetPoint("LEFT", 9, 0)
    frame.Text:SetPoint("RIGHT", -29, 0)
    -- 触发框当前值与 Blizzard_Menu 选项共用同一个 15px FontObject，
    -- 避免两条渲染路径各自取默认字体后产生大小/字面观感差异。
    frame.Text:SetFontObject(MODERN.menuFonts.control)
    if frame.Text.SetShadowOffset then frame.Text:SetShadowOffset(0, 0) end
    if not frame._exModernDropdownHooks then
        frame._exModernDropdownHooks = true
        frame:HookScript("OnEnter", function(self) self._exModernHover = true; PaintModernDropdown(self) end)
        frame:HookScript("OnLeave", function(self) self._exModernHover = false; PaintModernDropdown(self) end)
        frame:HookScript("OnEnable", PaintModernDropdown)
        frame:HookScript("OnDisable", PaintModernDropdown)
        frame:HookScript("OnShow", PaintModernDropdown)
    end
    PaintModernDropdown(frame)
end

local function IsCursorInsideFrame(frame)
    if not frame or not frame.IsVisible or not frame:IsVisible() then return false end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not left or not right or not top or not bottom or not _G.GetCursorPosition then
        return frame.IsMouseOver and frame:IsMouseOver() or false
    end
    local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    local cursorX, cursorY = _G.GetCursorPosition()
    cursorX, cursorY = cursorX / scale, cursorY / scale
    if cursorX < left or cursorX > right or cursorY < bottom or cursorY > top then return false end
    -- The coordinate test immediately rejects a pill which moved away during
    -- this layout pass. Mouse foci then preserve native clipping/occlusion and
    -- child hit semantics instead of treating the raw rectangle as sufficient.
    if _G.GetMouseFoci then
        for _, focus in ipairs(_G.GetMouseFoci()) do
            local region = focus
            while region do
                if region == frame then return true end
                region = region.GetParent and region:GetParent() or nil
            end
        end
        return false
    end
    return frame.IsMouseOver and frame:IsMouseOver() or false
end

local function PaintModernCheckbox(container, skipPillMeasure)
    local box = container.checkbox
    if not box then return end
    HideControlSkin(box)
    local enabled, selected = box:IsEnabled(), box:GetChecked() == true
    local hover = enabled and box._exModernHover
    local pressed = enabled and box._exModernPressed
    local fill, edge
    local isCard = container._exSettingsPresentation == "card"
    if box._exSettingsCardSurface then box._exSettingsCardSurface:SetShown(isCard) end
    if container._exSettingsPresentation == "pill" then
        if box._exModernSwitchKnob then box._exModernSwitchKnob:Hide() end
        local surface = box._exModernCheckSurface
        local visualLabel = box._exSettingsPillLabel
        if visualLabel and not skipPillMeasure then
            visualLabel:SetText(container.label and container.label:GetText() or "")
            local labelWidth = visualLabel.GetUnboundedStringWidth
                and math.ceil(visualLabel:GetUnboundedStringWidth() or 0) or 0
            local naturalWidth = math.max(40, labelWidth + (selected and 44 or 24))
            local previousWidth = container._exSettingsPillNaturalWidth
            container._exSettingsPillNaturalWidth = naturalWidth
            if previousWidth ~= nil and previousWidth ~= naturalWidth then
                -- Keep the old complete visual until Grid can commit the new
                -- width and right-aligned point together in its layout pass.
                -- Painting the checked state at the old point would expose a
                -- one-frame intermediate state during the click.
                container._exSettingsPillVisualPending = true
                local grid = _G.ExwindGrid
                local parent = container:GetParent()
                local willRelayout = grid and grid.RequestReflow and grid:RequestReflow(parent) or false
                if not willRelayout and grid and grid.GetSettingsListSession then
                    local list = grid:GetSettingsListSession(parent)
                    if list then
                        willRelayout = true
                        list:Relayout(nil, true)
                    end
                end
                if willRelayout then return end
                container._exSettingsPillVisualPending = nil
            elseif container._exSettingsPillVisualPending then
                return
            end
        end
        surface:ClearAllPoints()
        surface:SetAllPoints(box)
        if not enabled then
            fill, edge = MC.disabledFill, MC.disabledBorder
        elseif pressed then
            fill = MC.toolActive
            edge = selected and MC.tagSelectedBorder or MC.tagHoverBorder
        elseif selected then
            fill = hover and MC.tagSelectedHover or MC.tagSelected
            edge = MC.tagSelectedBorder
        else
            fill = hover and MC.rowHover or MC.transparent
            edge = hover and MC.tagHoverBorder or MC.tagBorder
        end
        EXUI:SetControlSurface(surface, 10, fill, edge)
        box._exModernCheckMark:ClearAllPoints()
        box._exModernCheckMark:SetPoint("LEFT", surface, "LEFT", 12, 0)
        box._exModernCheckMark:SetSize(14, 14)
        box._exModernCheckMark:SetShown(selected)
        box._exModernCheckMark:SetVertexColor(unpack(enabled and MC.tagSelectedText or MC.disabledText))
        surface:SetAlpha(1)
        if container.label then
            container.label:SetTextColor(unpack(enabled and (selected and MC.tagSelectedText
                or (hover and MC.tagHoverText or MC.tagText)) or MC.disabledText))
        end
        if visualLabel then
            visualLabel:SetTextColor(unpack(enabled and (selected and MC.tagSelectedText
                or (hover and MC.tagHoverText or MC.tagText)) or MC.disabledText))
            visualLabel:ClearAllPoints()
            visualLabel:SetPoint("LEFT", surface, "LEFT", selected and 32 or 12, 0)
            visualLabel:SetPoint("RIGHT", surface, "RIGHT", -12, 0)
        end
        return
    elseif container._exSettingsPresentation == "switch" then
        if not box._exModernSwitchKnob then
            local knob = CreateFrame("Frame", nil, box._exModernCheckSurface)
            knob:SetSize(16, 16)
            knob:EnableMouse(false)
            box._exModernSwitchKnob = knob
        end
        if not enabled then
            fill, edge = MC.disabledFill, MC.disabledBorder
        elseif selected then
            fill = pressed and MC.checkboxCheckedActive or (hover and MC.switchOnHover or MC.switchOn)
            -- The selected track is a single-color capsule. Drawing the same
            -- color through both fill and border masks doubles curved AA pixels.
            edge = MC.transparent
        else
            fill = pressed and MC.checkboxHoverBorder
                or (hover and MODERN.switchOffHoverFill or MC.switchOff)
            edge = MC.secondaryFill
        end
        local surface = box._exModernCheckSurface
        surface:ClearAllPoints()
        surface:SetPoint("CENTER", box, "CENTER", 0, 0)
        surface:SetSize(40, 22)
        EXUI:SetControlSurface(surface, 10, fill, edge)
        box._exModernCheckMark:Hide()
        local knob = box._exModernSwitchKnob
        knob:ClearAllPoints()
        knob:SetPoint(selected and "RIGHT" or "LEFT", surface,
            selected and "RIGHT" or "LEFT", selected and -3 or 3, 0)
        local knobColor = enabled and (selected and MC.switchKnobOn or MC.switchKnobOff) or MC.disabledText
        -- One fill mask produces a clean circular edge; a same-color border
        -- would composite the antialiased rim twice and make it look uneven.
        EXUI:SetControlSurface(knob, 10, knobColor, MC.transparent)
        knob:Show()
        surface:SetAlpha(1)
        if container.label then
            container.label:SetTextColor(unpack(enabled and MC.text or MC.disabledText))
        end
        return
    end
    if box._exModernSwitchKnob then box._exModernSwitchKnob:Hide() end
    box._exModernCheckSurface:ClearAllPoints()
    box._exModernCheckSurface:SetPoint("LEFT", box, "LEFT", 0, 0)
    box._exModernCheckSurface:SetSize(20, 20)
    if isCard then
        local card = box._exSettingsCardSurface
        if not card then
            card = CreateFrame("Frame", nil, box)
            card:EnableMouse(false)
            card:SetAllPoints(box)
            card.Title = EXUI:CreateVisualFontString(card, EXFONTFRAME, "GameFontHighlight")
            card.Title:SetJustifyH("LEFT")
            card.Title:SetWordWrap(false)
            card.Icon = EXUI:CreateVisualTexture(card, EXBASEFRAME)
            card.Icon:SetSize(16, 16)
            box._exSettingsCardSurface = card
        end
        card:SetFrameLevel(box:GetFrameLevel())
        box._exModernCheckSurface:SetFrameLevel(box:GetFrameLevel() + 1)
        local cardFill
        if not enabled then
            cardFill = MC.disabledFill
        elseif pressed then
            cardFill = MODERN.settingsCardPressedFill
        elseif selected then
            cardFill = hover and MODERN.settingsCardSelectedHoverFill or MODERN.settingsCardSelectedFill
        elseif hover then
            cardFill = MODERN.settingsCardHoverFill
        else
            cardFill = MC.subcard
        end
        EXUI:SetControlSurface(card, 4, cardFill,
            not enabled and MC.disabledBorder
                or (selected and MC.modifiedBorder
                    or (hover and MC.subcardHoverBorder or MC.subcardBorder)))
        local hasDescription = container._exSettingsCardDescription == true
        local checkSize = container._exSettingsCardCheckSize or 20
        box._exModernCheckSurface:SetSize(checkSize, checkSize)
        box._exModernCheckSurface:ClearAllPoints()
        box._exModernCheckSurface:SetPoint(hasDescription and "TOPLEFT" or "LEFT", box,
            hasDescription and "TOPLEFT" or "LEFT", 10, hasDescription and -10 or 0)
        card.Icon:ClearAllPoints()
        card.Icon:SetSize(math.min(16, checkSize), math.min(16, checkSize))
        card.Icon:SetPoint("LEFT", box._exModernCheckSurface, "RIGHT", 8, 0)
        card.Icon:SetTexture(container._exSettingsCardIcon)
        card.Icon:SetShown(container._exSettingsCardIcon ~= nil)
        card.Icon:SetAlpha(enabled and 1 or .4)
        card.Title:ClearAllPoints()
        card.Title:SetPoint("LEFT", container._exSettingsCardIcon and card.Icon or box._exModernCheckSurface,
            "RIGHT", 8, 0)
        card.Title:SetPoint("RIGHT", card, hasDescription and "TOPRIGHT" or "RIGHT",
            -10, hasDescription and -(10 + checkSize / 2) or 0)
        card.Title:SetText(container.label and container.label:GetText() or "")
        MODERN.ApplyTextRole(card.Title, "title", enabled and MC.text or MC.disabledText)
        if container._exSettingsCardTextSize then
            local font, _, flags = card.Title:GetFont()
            card.Title:SetFont(font, container._exSettingsCardTextSize, flags)
        end
        card:Show()
    end
    box._exModernCheckMark:ClearAllPoints()
    box._exModernCheckMark:SetAllPoints(box._exModernCheckSurface)
    if not enabled then
        fill, edge = MC.disabledFill, MC.disabledBorder
    elseif selected then
        fill = pressed and MC.checkboxCheckedActive or (hover and MC.checkboxCheckedHover or MC.checkboxChecked)
        edge = fill
    else
        fill = pressed and MODERN.checkboxPressedFill
            or (hover and MODERN.checkboxHoverFill or MC.input)
        edge = hover and MC.checkboxHoverBorder or MC.checkboxBorder
    end
    EXUI:SetControlSurface(box._exModernCheckSurface, 4, fill, edge)
    box._exModernCheckMark:SetShown(selected)
    box._exModernCheckMark:SetVertexColor(unpack(enabled and MC.white or MC.disabledText))
    box._exModernCheckSurface:SetAlpha(1)
    if container.label then
        container.label:SetTextColor(unpack(enabled and MC.text or MC.disabledText))
    end
end

local function ApplyModernCheckbox(container)
    local box = container.checkbox
    if not box then return end
    StripCheckButtonStateTextures(box)
    if not box._exModernCheckSurface then
        local surface = CreateFrame("Frame", nil, box)
        surface:SetSize(20, 20)
        surface:SetPoint("LEFT", box, "LEFT", 0, 0)
        surface:EnableMouse(false)
        box._exModernCheckSurface = surface
        local mark = surface:CreateTexture(nil, "OVERLAY")
        mark:SetTexture(MODERN_MEDIA .. "GlyphCheck.tga", "CLAMP", "CLAMP", "LINEAR")
        mark:SetAllPoints(surface)
        box._exModernCheckMark = mark
        -- Native checked state remains the source of truth. Do not attach
        -- appearance updates to OnClick: callers legitimately replace it.
        local visual = CreateFrame("Frame", nil, box)
        visual:EnableMouse(false)
        visual:SetScript("OnUpdate", function(self)
            local enabled = box:IsEnabled()
            local hover = false
            if enabled then
                if container._exSettingsPresentation == "pill" then
                    hover = IsCursorInsideFrame(box)
                else
                    hover = box:IsMouseOver()
                end
            end
            local checked = box:GetChecked() == true
            if self.enabled ~= enabled or self.hover ~= hover or self.checked ~= checked then
                self.enabled, self.hover, self.checked = enabled, hover, checked
                box._exModernHover = hover
                PaintModernCheckbox(container)
            end
        end)
        visual:SetScript("OnHide", function(self)
            self.enabled, self.hover, self.checked = nil, nil, nil
            box._exModernHover = nil
        end)
        box._exModernCheckVisual = visual
    end
    if not box._exModernCheckPointerHooks then
        box._exModernCheckPointerHooks = true
        box:HookScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and self:IsEnabled() then
                self._exModernPressed = true
                PaintModernCheckbox(container)
            end
        end)
        box:HookScript("OnMouseUp", function(self)
            self._exModernPressed = nil
            PaintModernCheckbox(container)
        end)
        box:HookScript("OnLeave", function(self)
            self._exModernPressed = nil
            PaintModernCheckbox(container)
        end)
    end
    if container.label then
        container.label:ClearAllPoints()
        container.label:SetPoint("LEFT", container, "LEFT", 27, 0)
        container.label:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        container.label:SetJustifyH("LEFT")
        MODERN.ApplyTextRole(container.label, "title")
    end
    PaintModernCheckbox(container)
end

-- Settings-list pill widths can change the final right-aligned geometry after
-- the native checked state has already painted. Re-read only visual state once
-- the layout owner has finished moving every row/card; no click or value
-- callback is invoked here.
function EXUI:RefreshSettingsListPillVisual(container)
    local box = container and container.checkbox
    if not box or container._exSettingsPresentation ~= "pill" then return false end
    local enabled = box:IsEnabled()
    local hover = enabled and IsCursorInsideFrame(box) or false
    local checked = box:GetChecked() == true
    local needsDeferredHoverRefresh = container._exSettingsPillVisualPending == true
    local visual = box._exModernCheckVisual
    if visual then
        visual.enabled, visual.hover, visual.checked = enabled, hover, checked
    end
    container._exSettingsPillVisualPending = nil
    box._exModernHover = hover
    if not enabled then box._exModernPressed = nil end
    PaintModernCheckbox(container)
    return true, needsDeferredHoverRefresh
end

-- One-shot post-layout hover sync. Geometry and checked-state caches stay
-- owned by the completed layout/normal visual watcher; this path neither
-- remeasures the pill nor requests another reflow.
function EXUI:RefreshSettingsListPillHoverVisual(container)
    local box = container and container.checkbox
    if not box or container._exSettingsPresentation ~= "pill"
        or container._exSettingsPillVisualPending then return false end
    local enabled = box:IsEnabled()
    local hover = enabled and IsCursorInsideFrame(box) or false
    local visual = box._exModernCheckVisual
    -- A newer click can occur before this one-shot callback. Do not paint that
    -- unchecked/checked transition at geometry committed for the older state.
    if not visual or visual.checked ~= (box:GetChecked() == true) then return false end
    visual.enabled, visual.hover = enabled, hover
    box._exModernHover = hover
    PaintModernCheckbox(container, true)
    return true
end

local function IsModernSliderEnabled(frame)
    local interactive = frame.Slider or frame
    if frame.IsSliderEnabled then return frame:IsSliderEnabled() end
    if interactive.IsEnabled then return interactive:IsEnabled() end
    return true
end

local SLIDER_NUMBER_INPUT_FONT_SIZE = 11
local SLIDER_NUMBER_INPUT_WIDTH = 54
local SLIDER_NUMBER_INPUT_HEIGHT = 20
local SLIDER_NUMBER_INPUT_INSET = 3

local function ApplySliderNumberInputAppearance(frame)
    local input = frame and frame.numberInput
    if not input then return end
    MODERN.Font(input, SLIDER_NUMBER_INPUT_FONT_SIZE, MC.text, "", "GameFontHighlightSmall")
    input:SetTextInsets(SLIDER_NUMBER_INPUT_INSET, SLIDER_NUMBER_INPUT_INSET, 0, 0)
end

local function SuppressModernSliderSteppers(frame)
    for _, key in ipairs({ "Back", "Forward" }) do
        local stepper = frame[key]
        if stepper then
            stepper:Hide()
            stepper:SetAlpha(0)
            if stepper.EnableMouse then stepper:EnableMouse(false) end
            if stepper.Disable then stepper:Disable() end
        end
    end
end

local function PaintModernSlider(frame)
    SuppressModernSliderSteppers(frame)
    local interactive = frame.Slider or frame
    local enabled = IsModernSliderEnabled(frame)
    local pressed = enabled and (interactive._exModernPressed or frame._exDragging)
    local hover = enabled and (interactive._exModernHover or pressed)
    frame._exModernSliderTrack:SetColorTexture(unpack(hover and MC.sliderTrackHover or MC.sliderTrack))
    local thumb = interactive.GetThumbTexture and interactive:GetThumbTexture()
    if thumb then
        thumb:SetVertexColor(unpack(enabled and (pressed and MC.sliderThumbActive
            or (hover and MC.sliderThumbHover or MC.sliderThumb)) or MC.disabledText))
    end
    if frame.numberInput then
        if enabled and frame.numberInput.Enable then frame.numberInput:Enable()
        elseif not enabled and frame.numberInput.Disable then frame.numberInput:Disable() end
        PaintModernInput(frame.numberInput, frame.numberInput)
    end
    if frame.Title then frame.Title:SetTextColor(unpack(enabled and MC.text or MC.disabledText)) end
    if frame.ValueText then frame.ValueText:SetTextColor(unpack(enabled and MC.lightBlue or MC.disabledText)) end
end

local function ApplyModernSlider(frame)
    local interactive = frame.Slider or frame
    if interactive ~= frame then
        interactive:ClearAllPoints()
        interactive:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        interactive:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        interactive:SetHeight(20)
    end
    SuppressModernSliderSteppers(frame)
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        if interactive[key] then interactive[key]:SetAlpha(0) end
    end
    if not frame._exModernSliderTrack then
        local track = interactive:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT", interactive, "LEFT", 0, 0)
        track:SetPoint("RIGHT", interactive, "RIGHT", 0, 0)
        track:SetHeight(4)
        frame._exModernSliderTrack = track
        local thumb = interactive.GetThumbTexture and interactive:GetThumbTexture()
        if thumb then
            thumb:SetTexture(MODERN_MEDIA .. "KnobR3.tga", "CLAMP", "CLAMP", "LINEAR")
            thumb:SetTexCoord(118 / 256, 138 / 256, 52 / 128, 76 / 128)
            thumb:SetSize(18, 10)
        end
    end
    -- Slider hover hooks are also lifetime hooks. The pool may clear the primary
    -- OnEnter/OnLeave handlers, but must retain this marker because HookScript
    -- callbacks themselves remain attached.
    if not frame._exModernSliderHoverHooks then
        frame._exModernSliderHoverHooks = true
        interactive:HookScript("OnEnter", function(self) self._exModernHover = true; PaintModernSlider(frame) end)
        interactive:HookScript("OnLeave", function(self)
            self._exModernHover = false
            if not frame._exDragging then self._exModernPressed = false end
            PaintModernSlider(frame)
        end)
    end
    -- Pointer/lifecycle slots are preserved by the pool for Slider widgets, so
    -- they stay attached for the frame lifetime and must not be duplicated.
    if not frame._exModernSliderLifetimeHooks then
        frame._exModernSliderLifetimeHooks = true
        interactive:HookScript("OnMouseDown", function(self, button)
            if button == nil or button == "LeftButton" then self._exModernPressed = true; PaintModernSlider(frame) end
        end)
        interactive:HookScript("OnMouseUp", function(self) self._exModernPressed = false; PaintModernSlider(frame) end)
        frame:HookScript("OnEnable", PaintModernSlider)
        frame:HookScript("OnDisable", PaintModernSlider)
        frame:HookScript("OnShow", PaintModernSlider)
        if frame.SetEnabled then
            hooksecurefunc(frame, "SetEnabled", function(self) PaintModernSlider(self) end)
        end
        if frame.UpdateStepperStates then
            hooksecurefunc(frame, "UpdateStepperStates", function(self) PaintModernSlider(self) end)
        end
    end
    if frame.numberInput then
        ApplySliderNumberInputAppearance(frame)
        ApplyModernInput(frame.numberInput)
    end
    MODERN.ApplyTextRole(frame.Title, "title")
    MODERN.ApplyTextRole(frame.ValueText, "hint", MC.lightBlue)
    PaintModernSlider(frame)
end

local function HideModernScrollBarNativePieces(owner)
    if not owner then return end
    for _, key in ipairs({ "Begin", "Middle", "End" }) do
        local texture = owner[key]
        if texture then
            texture:SetAlpha(0)
            texture:Hide()
        end
    end
end

local function SuppressModernScrollBarSteppers(scrollBar)
    for _, key in ipairs({ "Back", "Forward" }) do
        local stepper = scrollBar and scrollBar[key]
        if stepper then
            stepper:Hide()
            stepper:SetAlpha(0)
            if stepper.EnableMouse then stepper:EnableMouse(false) end
            if stepper.SetEnabled then stepper:SetEnabled(false) end
        end
    end
end

local function PaintModernScrollBar(scrollBar)
    if not scrollBar or not scrollBar.GetTrack or not scrollBar.GetThumb then return end
    local track = scrollBar:GetTrack()
    local thumb = scrollBar:GetThumb()
    if not (track and thumb) then return end

    SuppressModernScrollBarSteppers(scrollBar)
    HideModernScrollBarNativePieces(track)
    HideModernScrollBarNativePieces(thumb)

    local scrollEnabled = (not scrollBar.IsScrollAllowed or scrollBar:IsScrollAllowed())
        and (not scrollBar.HasScrollableExtent or scrollBar:HasScrollableExtent())
    local thumbEnabled = scrollEnabled and (not thumb.IsEnabled or thumb:IsEnabled())
    -- MinimalScrollBar keeps its native drag state in `down`; retain our
    -- explicit pressed flag as the immediate fallback around MouseDown/Up.
    -- Idle and hover stay neutral; blue is reserved for an active press/drag.
    local thumbPressed = thumbEnabled and (thumb._exModernPressed or thumb.down)

    EXUI:SetControlSurface(track, 4, MC.transparent, MC.transparent)
    EXUI:SetControlSurface(thumb, 4,
        thumbEnabled and (thumbPressed and MC.blue or MC.secondaryBorder) or MC.disabled,
        thumbEnabled and (thumbPressed and MC.blue or MC.secondaryBorder) or MC.disabled)
end

-- The current Blizzard ScrollFrameTemplate creates one MinimalScrollBar and
-- binds it through ScrollUtil.InitScrollFrameWithScrollBar.  EXUI only changes
-- that native control's geometry and appearance; wheel, page-click,
-- proportional-thumb and drag behavior remain owned by Blizzard.
function EXUI:ApplyModernScrollBar(scrollBar, preserveGeometry)
    if not scrollBar or not scrollBar.GetTrack or not scrollBar.GetThumb then return scrollBar end
    local track = scrollBar:GetTrack()
    local thumb = scrollBar:GetThumb()
    if not (track and thumb) then return scrollBar end

    if not preserveGeometry then
        scrollBar:SetWidth(10)
        track:ClearAllPoints()
        track:SetPoint("TOP", scrollBar, "TOP", 0, 0)
        track:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, 0)
        track:SetWidth(8)
        thumb:SetWidth(8)
    end
    SuppressModernScrollBarSteppers(scrollBar)
    -- Recalculate proportional thumb extent/offset against the full-height
    -- track immediately; later size/range changes continue through Blizzard's
    -- existing Track OnSizeChanged and ScrollUtil callbacks.
    if not preserveGeometry and scrollBar.Update then scrollBar:Update() end

    if not scrollBar._exModernScrollBarHooks then
        scrollBar._exModernScrollBarHooks = true
        track:HookScript("OnEnter", function(self)
            self._exModernHover = true
            PaintModernScrollBar(scrollBar)
        end)
        track:HookScript("OnLeave", function(self)
            self._exModernHover = nil
            PaintModernScrollBar(scrollBar)
        end)
        track:HookScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then self._exModernPressed = true end
            PaintModernScrollBar(scrollBar)
        end)
        track:HookScript("OnMouseUp", function(self)
            self._exModernPressed = nil
            PaintModernScrollBar(scrollBar)
        end)
        thumb:HookScript("OnEnter", function(self)
            self._exModernHover = true
            PaintModernScrollBar(scrollBar)
        end)
        thumb:HookScript("OnLeave", function(self)
            self._exModernHover = nil
            PaintModernScrollBar(scrollBar)
        end)
        thumb:HookScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then self._exModernPressed = true end
            PaintModernScrollBar(scrollBar)
        end)
        thumb:HookScript("OnMouseUp", function(self)
            self._exModernPressed = nil
            PaintModernScrollBar(scrollBar)
        end)
        thumb:HookScript("OnEnable", function() PaintModernScrollBar(scrollBar) end)
        thumb:HookScript("OnDisable", function() PaintModernScrollBar(scrollBar) end)
        thumb:HookScript("OnShow", function() PaintModernScrollBar(scrollBar) end)
        thumb:HookScript("OnHide", function(self)
            self._exModernHover = nil
            self._exModernPressed = nil
            PaintModernScrollBar(scrollBar)
        end)
        scrollBar:HookScript("OnShow", function(self) PaintModernScrollBar(self) end)
        scrollBar:HookScript("OnHide", function(self)
            -- Blizzard stops drag/page-repeat from MouseUp.  A parent can hide
            -- before that callback is delivered, so end the native update loop
            -- through its own lifecycle API and let the next interaction start
            -- from a clean state.
            if self.UnregisterUpdate then self:UnregisterUpdate() end
            track._exModernHover = nil
            track._exModernPressed = nil
            thumb._exModernHover = nil
            thumb._exModernPressed = nil
        end)
    end

    PaintModernScrollBar(scrollBar)
    return scrollBar
end

function EXUI:ApplyModernScrollFrame(scrollFrame)
    if scrollFrame and scrollFrame.ScrollBar then
        self:ApplyModernScrollBar(scrollFrame.ScrollBar)
    end
    return scrollFrame
end

function EXUI:CreateScrollFrame(parent, name)
    local scrollFrame = CreateFrame("ScrollFrame", name, parent, "ScrollFrameTemplate")
    scrollFrame:EnableMouseWheel(true)
    self:ApplyModernScrollFrame(scrollFrame)
    return scrollFrame
end

-- Preview docks sit beside, rather than inside, their page ScrollFrame.  Keep
-- wheel capture on the dock, but forward it only to the owner registered by
-- the currently mounted page.  The owner token prevents an old page teardown
-- from clearing a newer page's registration on a shared dock.
function EXUI:SetPreviewDockScrollOwner(dock, owner, scrollFrame)
    if not dock or type(dock.EnableMouseWheel) ~= "function" then return false end
    if scrollFrame then
        dock._exPreviewWheelOwner = owner
        dock._exPreviewWheelScrollFrame = scrollFrame
        if not dock._exPreviewWheelHooked then
            dock._exPreviewWheelHooked = true
            dock:HookScript("OnMouseWheel", function(self, delta)
                local target = self._exPreviewWheelScrollFrame
                if not target or not target:IsShown() then return end
                local handler = target:GetScript("OnMouseWheel")
                if handler then handler(target, delta) end
            end)
        end
        dock:EnableMouseWheel(true)
        return true
    end
    if owner == nil or dock._exPreviewWheelOwner == owner then
        dock._exPreviewWheelOwner = nil
        dock._exPreviewWheelScrollFrame = nil
        dock:EnableMouseWheel(false)
        return true
    end
    return false
end

function EXUI:CreateScrollBar(parent, name)
    local scrollBar = CreateFrame("EventFrame", name, parent, "MinimalScrollBar")
    self:ApplyModernScrollBar(scrollBar)
    return scrollBar
end

function EXUI:StyleDropdownMenuProxy(proxy)
    -- The menu compositor already reserves and positions its own scrollbar
    -- inside the proxy. Preserve that geometry while sharing the modern thumb
    -- hover/drag state; page ScrollFrame inset rules do not apply here.
    if proxy and proxy.ScrollBar then
        self:ApplyModernScrollBar(proxy.ScrollBar, true)
    end
    return proxy
end

local function PaintModernGridCard(frame)
    EXUI:SetControlSurface(frame, 10, MC.raised,
        frame._exModernHover and MC.cardHoverBorder or MC.cardBorder)
end

if _G.MenuStyleMixin and _G.CreateFromMixins then
    EXUI.ModernMenuStyleMixin = CreateFromMixins(MenuStyleMixin)
    function EXUI.ModernMenuStyleMixin:Generate()
        local radius = 6
        local fillPieces, borderCorners, borderEdges = {}, {}, {}
        -- WoW 没有 CSS blur。三层向下扩散的低透明黑底近似
        -- 0 10px 28px rgba(0,0,0,.55)，只在菜单生成时创建，没有 OnUpdate。
        for shadowIndex, shadow in ipairs({
            { x = 14, top = 4, bottom = 20, alpha = 0.10 },
            { x = 9, top = 2, bottom = 14, alpha = 0.16 },
            { x = 5, top = 1, bottom = 9, alpha = 0.22 },
        }) do
            local texture = self:AttachTexture()
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            texture:SetPoint("TOPLEFT", -shadow.x, shadow.top)
            texture:SetPoint("BOTTOMRIGHT", shadow.x, -shadow.bottom)
            texture:SetVertexColor(0, 0, 0, shadow.alpha)
            texture:SetDrawLayer("BACKGROUND", -8 + shadowIndex)
        end

        for row = 1, 3 do
            for col = 1, 3 do
                local texture = self:AttachTexture()
                MODERN.surfaceAtlas:ConfigureTexture(texture)
                texture:SetVertexColor(unpack(MC.popup))
                texture:SetDrawLayer("BACKGROUND", 0)
                fillPieces[#fillPieces + 1] = { texture = texture, row = row, col = col }
            end
        end
        for _, corner in ipairs({ { 1, 1 }, { 1, 3 }, { 3, 1 }, { 3, 3 } }) do
            local row, col = corner[1], corner[2]
            local texture = self:AttachTexture()
            MODERN.surfaceAtlas:ConfigureTexture(texture)
            texture:SetVertexColor(unpack(MC.popupBorder))
            texture:SetDrawLayer("BORDER", 0)
            borderCorners[#borderCorners + 1] = { texture = texture, row = row, col = col }
        end
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local texture = self:AttachTexture()
            MODERN.surfaceAtlas:ConfigureTexture(texture)
            MODERN.surfaceAtlas:SetSolidTexCoord(texture)
            texture:SetVertexColor(unpack(MC.popupBorder))
            texture:SetDrawLayer("BORDER", 1)
            borderEdges[#borderEdges + 1] = { texture = texture, side = side }
        end
        local function RefreshSurface()
            local metrics = MODERN.surfaceAtlas:GetMetrics(self, radius, 1)
            if not metrics then return end
            local pixel = metrics.pixel
            local width = metrics.widthPixels * pixel
            local height = metrics.heightPixels * pixel
            local corner = metrics.radiusPixels * pixel
            local thickness = metrics.strokePixels * pixel
            local xs = {
                metrics.offsetX,
                metrics.offsetX + corner,
                metrics.offsetX + width - corner,
                metrics.offsetX + width,
            }
            local ys = { 0, corner, height - corner, height }
            for _, piece in ipairs(fillPieces) do
                local texture = piece.texture
                texture:ClearAllPoints()
                if metrics.radiusPixels == 0 then
                    if piece.row == 2 and piece.col == 2 then
                        MODERN.surfaceAtlas:SetSolidTexCoord(texture)
                        texture:SetPoint("TOPLEFT", self, "TOPLEFT", metrics.offsetX, metrics.offsetY)
                        texture:SetSize(width, height)
                        texture:Show()
                    else
                        texture:Hide()
                    end
                else
                    local pieceWidth = xs[piece.col + 1] - xs[piece.col]
                    local pieceHeight = ys[piece.row + 1] - ys[piece.row]
                    if piece.row ~= 2 and piece.col ~= 2 then
                        MODERN.surfaceAtlas:SetCornerTexCoord(texture,
                            metrics.radiusPixels, 0, piece.row, piece.col)
                    else
                        MODERN.surfaceAtlas:SetSolidTexCoord(texture)
                    end
                    texture:SetPoint("TOPLEFT", self, "TOPLEFT", xs[piece.col], metrics.offsetY - ys[piece.row])
                    texture:SetSize(math.max(.001, pieceWidth), math.max(.001, pieceHeight))
                    texture:SetShown(pieceWidth > 0 and pieceHeight > 0)
                end
            end
            local degenerateBorder = metrics.widthPixels <= metrics.strokePixels * 2
                or metrics.heightPixels <= metrics.strokePixels * 2
            for _, piece in ipairs(borderCorners) do
                local texture = piece.texture
                texture:ClearAllPoints()
                if metrics.radiusPixels > 0 and not degenerateBorder then
                    MODERN.surfaceAtlas:SetCornerTexCoord(texture,
                        metrics.radiusPixels, metrics.strokePixels, piece.row, piece.col)
                    texture:SetPoint("TOPLEFT", self, "TOPLEFT", xs[piece.col], metrics.offsetY - ys[piece.row])
                    texture:SetSize(corner, corner)
                    texture:Show()
                else
                    texture:Hide()
                end
            end
            for _, piece in ipairs(borderEdges) do
                local texture = piece.texture
                MODERN.surfaceAtlas:SetSolidTexCoord(texture)
                texture:ClearAllPoints()
                if degenerateBorder then
                    if piece.side == "TOP" then
                        texture:SetPoint("TOPLEFT", self, "TOPLEFT", metrics.offsetX, metrics.offsetY)
                        texture:SetSize(width, height)
                        texture:Show()
                    else
                        texture:Hide()
                    end
                elseif piece.side == "TOP" then
                    texture:SetPoint("TOPLEFT", self, "TOPLEFT", xs[2], metrics.offsetY)
                    texture:SetSize(math.max(.001, width - corner * 2), thickness)
                    texture:SetShown(width > corner * 2)
                elseif piece.side == "BOTTOM" then
                    texture:SetPoint("TOPLEFT", self, "TOPLEFT", xs[2], metrics.offsetY - height + thickness)
                    texture:SetSize(math.max(.001, width - corner * 2), thickness)
                    texture:SetShown(width > corner * 2)
                elseif piece.side == "LEFT" then
                    texture:SetPoint("TOPLEFT", self, "TOPLEFT", metrics.offsetX, metrics.offsetY - corner)
                    texture:SetSize(thickness, math.max(.001, height - corner * 2))
                    texture:SetShown(height > corner * 2)
                else
                    texture:SetPoint("TOPLEFT", self, "TOPLEFT", metrics.offsetX + width - thickness, metrics.offsetY - corner)
                    texture:SetSize(thickness, math.max(.001, height - corner * 2))
                    texture:SetShown(height > corner * 2)
                end
            end
        end
        self:HookScript("OnSizeChanged", RefreshSurface)
        self:HookScript("OnShow", RefreshSurface)
        self:RegisterEvent("UI_SCALE_CHANGED")
        self:RegisterEvent("DISPLAY_SIZE_CHANGED")
        self:HookScript("OnEvent", RefreshSurface)
        RefreshSurface()
    end
    function EXUI.ModernMenuStyleMixin:GetInset()
        return { left = 6, top = 6, right = 6, bottom = 6 }
    end
    function EXUI.ModernMenuStyleMixin:GetChildExtentPadding()
        return { width = 0, height = 0 }
    end
end

function EXUI:ApplyControlAppearance(frame)
    if not frame then return frame end
    local kind = frame._gridType
    if kind == "GridButton" then
        ApplyModernButton(frame)
    elseif kind == "GridPicButton" then
        local highlight = frame.GetHighlightTexture and frame:GetHighlightTexture()
        if highlight then highlight:SetVertexColor(unpack(MC.lightBlue)) end
    elseif kind == "GridDropdown" or kind == "GridLSMDropdown" or kind == "GridMultiselect" then
        ApplyModernDropdown(frame)
        StyleModernTitle(frame.labelText, MC.text)
    elseif kind == "GridCheckbox" then
        ApplyModernCheckbox(frame)
    elseif kind == "GridSlider" then
        ApplyModernSlider(frame)
    elseif kind == "GridInput" then
        ApplyModernInput(frame)
        StyleModernTitle(frame.label, MC.text)
    elseif kind == "GridColorButton" then
        ApplyModernButton(frame)
        StyleModernTitle(frame.labelText or frame.label, MC.text)
    elseif kind == "GridHeader" then
        StyleModernTitle(frame.Title, MC.text)
        if frame.Line then frame.Line:SetColorTexture(unpack(MC.border)) end
    elseif kind == "GridSubheader" then
        StyleModernTitle(frame.text, MC.lightBlue)
    elseif kind == "GridDescription" then
        MODERN.ApplyTextRole(frame.text,
            frame._exSettingsTextRole == "tableText" and "title" or "hint")
    elseif kind == "GridCard" then
        if frame.EnableMouse then frame:EnableMouse(true) end
        if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(true) end
        if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
        if not frame._exModernCardHoverHooks then
            frame._exModernCardHoverHooks = true
            frame:HookScript("OnEnter", function(self)
                self._exModernHover = true
                PaintModernGridCard(self)
            end)
            frame:HookScript("OnLeave", function(self)
                self._exModernHover = nil
                PaintModernGridCard(self)
            end)
        end
        PaintModernGridCard(frame)
        for _, key in ipairs({
            "_exCardFrameGlow", "_exCardTopEdge", "_exCardRightEdge", "_exCardBottomEdge",
            "_exCardGlowHost", "_exCardTopGlow", "_exCardRightGlow", "_exCardBottomGlow",
        }) do
            if frame[key] then frame[key]:Hide() end
        end
        MODERN.ApplyTextRole(frame.Title, "cardTitle", MC.lightBlue)
        MODERN.ApplyTextRole(frame.Desc, "body", MC.muted)
        if frame.Accent then
            frame.Accent:ClearAllPoints()
            frame.Accent:SetWidth(4)
            frame.Accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.Accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            frame.Accent:SetColorTexture(unpack(MC.blue))
            frame.Accent:Show()
        end
        if frame.TitleIcon then frame.TitleIcon:SetVertexColor(unpack(MC.blue)) end
    elseif frame._exMultilineInput == true and frame.editBox and frame.editBox ~= frame then
        ApplyModernInput(frame)
        StyleModernTitle(frame.label, MC.text)
    end
    return frame
end

function EXUI:RefreshControlAppearance(frame)
    return self:ApplyControlAppearance(frame)
end

-- [Helper] 防止 UI 污染的统一清理函数
local function CleanDropdownButton(button)
    if button.playBtn then button.playBtn:Hide() end
    if button.fontString then
        button.fontString:SetAlpha(1)
        button.fontString:SetFontObject(MODERN.menuFonts.control)
    end
    if button.lsmFontPreview and button.lsmFontPreview.fs then
        button.lsmFontPreview.fs:SetText("")
        button.lsmFontPreview.fs:SetFontObject("GameFontHighlight")
        button.lsmFontPreview:Hide()
    end
end

local function SetDropdownDisplayText(dropdown, text)
    local displayText = text or L["请选择..."]
    if dropdown.OverrideText then
        dropdown:OverrideText(displayText)
    else
        dropdown:SetText(displayText)
    end
end

local function NormalizeDropdownSearchText(text)
    if text == nil then
        return ""
    end

    local normalized = tostring(text)
    normalized = normalized:gsub("|c%x%x%x%x%x%x%x%x", "")
    normalized = normalized:gsub("|r", "")
    normalized = normalized:gsub("|T.-|t", " ")
    normalized = normalized:gsub("|A.-|a", " ")
    normalized = normalized:gsub("%s+", " ")
    normalized = strtrim(normalized)

    return string.lower(normalized)
end

local function GetDropdownLeafSearchText(item)
    if type(item) ~= "table" then
        return NormalizeDropdownSearchText(item)
    end

    local parts = {}
    if item.searchText then parts[#parts + 1] = item.searchText end
    if item.label then parts[#parts + 1] = item.label end
    if item.text and not item.isMenu then parts[#parts + 1] = item.text end
    if item[1] ~= nil then parts[#parts + 1] = item[1] end
    if item[2] ~= nil then parts[#parts + 1] = item[2] end

    return NormalizeDropdownSearchText(table.concat(parts, " "))
end

local function DropdownLeafMatchesQuery(item, needle)
    if needle == "" then
        return true
    end

    return GetDropdownLeafSearchText(item):find(needle, 1, true) ~= nil
end

local function CloneDropdownMenuBranch(item, filteredChildren)
    local cloned = {}
    for key, value in pairs(item) do
        cloned[key] = value
    end
    cloned.menu = filteredChildren
    return cloned
end

local function FilterDropdownItemsByNeedle(list, needle)
    if not list then
        return nil
    end

    local filtered = {}

    for _, item in ipairs(list) do
        if type(item) == "table" and item.isMenu then
            local groupText = NormalizeDropdownSearchText(item.searchText or item.text or item.label or item[1] or "")
            if groupText ~= "" and groupText:find(needle, 1, true) then
                filtered[#filtered + 1] = item
            else
                local filteredChildren = FilterDropdownItemsByNeedle(item.menu, needle)
                if filteredChildren and #filteredChildren > 0 then
                    filtered[#filtered + 1] = CloneDropdownMenuBranch(item, filteredChildren)
                end
            end
        elseif DropdownLeafMatchesQuery(item, needle) then
            filtered[#filtered + 1] = item
        end
    end

    return filtered
end

local function FilterDropdownItems(list, query)
    local needle = NormalizeDropdownSearchText(query)
    if needle == "" then
        return list
    end
    return FilterDropdownItemsByNeedle(list, needle)
end

local function PrepareDropdownMenuForRegeneration(dropdown)
    local menu = dropdown and dropdown.menu
    if not menu then
        return
    end

    if menu.ScrollBox and menu.ScrollBox.RemoveDataProvider then
        menu.ScrollBox:RemoveDataProvider()
    end

    if menu.ClearScrollLayout then
        menu:ClearScrollLayout()
    end
end

local function ResetDropdownMenuScroll(dropdown)
    local menu = dropdown and dropdown.menu
    local scrollBox = menu and menu.ScrollBox
    if scrollBox and scrollBox.ScrollToBegin then
        scrollBox:ScrollToBegin(ScrollBoxConstants and ScrollBoxConstants.NoScrollInterpolation or true)
    end
end

local EnsureDropdownFloatingSearchFrame
local EXTERNAL_DROPDOWN_SEARCH_HEIGHT = 42
local MODERN_MENU_ROW_HEIGHT = 28

local function AttachModernMenuSelectionMark(frame, enabled, selected)
    local anchor = frame.leftTexture1
    if not anchor or not frame.AttachTexture then return end

    -- 保留 Blizzard selection texture 的布局占位，但不显示原生黑/黄 radio、checkbox。
    -- 单选与多选统一使用青岚菜单原型的独立白色勾号；它不是 Checkbox 控件，
    -- 因此没有方框、底色或圆点，未选中时该预留列保持为空。
    anchor:SetAlpha(0)
    anchor:Hide()
    if frame.leftTexture2 then
        frame.leftTexture2:SetAlpha(0)
        frame.leftTexture2:Hide()
    end

    if selected then
        local check = frame:AttachTexture()
        check:SetTexture(MODERN_MEDIA .. "GlyphCheck.tga", "CLAMP", "CLAMP", "LINEAR")
        check:SetPoint("LEFT", frame, "LEFT", 10, 0)
        check:SetSize(16, 16)
        check:SetDrawLayer("ARTWORK", 7)
        check:SetVertexColor(unpack(enabled and MC.blue or MC.disabledText))
    end
end

-- 菜单行不能调用 SetControlSurface：它会清除 Blizzard_Menu 自己的状态贴图，
-- 并可能让单选圆点重新接管选中标记。这里直接在 compositor 行上附加一层
-- R4 九宫格，只负责 hover / selected 背景，不碰原生按钮状态与勾号。
local function AttachModernMenuRowHighlight(frame)
    if not frame.AttachTexture then return nil end

    local radius, insetX, insetY = 4, 4, 0
    -- FillR4 的源图左右各有 6px、上下各有 23px 透明 padding。
    -- 菜单会把 attachment 的实体矩形纳入行尺寸测量，因此这里直接裁掉
    -- padding，只把实际可见的圆角 4px 区域锚在行框内部。
    local u = { 6 / 256, (6 + radius) / 256, (250 - radius) / 256, 250 / 256 }
    local v = { 23 / 128, (23 + radius) / 128, (105 - radius) / 128, 105 / 128 }
    local insideX, insideY = insetX + radius, insetY + radius
    local pieces = {}

    for row = 1, 3 do
        for col = 1, 3 do
            local texture = frame:AttachTexture()
            texture:SetTexture(MODERN_MEDIA .. "FillR4.tga", "CLAMP", "CLAMP", "LINEAR")
            texture:SetTexCoord(u[col], u[col + 1], v[row], v[row + 1])
            texture:SetDrawLayer("BACKGROUND", 1)
            if row == 1 and col == 1 then
                texture:SetPoint("TOPLEFT", frame, "TOPLEFT", insetX, -insetY)
                texture:SetSize(radius, radius)
            elseif row == 1 and col == 2 then
                texture:SetPoint("TOPLEFT", frame, "TOPLEFT", insideX, -insetY)
                texture:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -insideX, -insetY)
                texture:SetHeight(radius)
            elseif row == 1 and col == 3 then
                texture:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -insetX, -insetY)
                texture:SetSize(radius, radius)
            elseif row == 2 and col == 1 then
                texture:SetPoint("TOPLEFT", frame, "TOPLEFT", insetX, -insideY)
                texture:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", insetX, insideY)
                texture:SetWidth(radius)
            elseif row == 2 and col == 2 then
                texture:SetPoint("TOPLEFT", frame, "TOPLEFT", insideX, -insideY)
                texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -insideX, insideY)
            elseif row == 2 and col == 3 then
                texture:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -insetX, -insideY)
                texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -insetX, insideY)
                texture:SetWidth(radius)
            elseif row == 3 and col == 1 then
                texture:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", insetX, insetY)
                texture:SetSize(radius, radius)
            elseif row == 3 and col == 2 then
                texture:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", insideX, insetY)
                texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -insideX, insetY)
                texture:SetHeight(radius)
            else
                texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -insetX, insetY)
                texture:SetSize(radius, radius)
            end
            texture:Hide()
            pieces[#pieces + 1] = texture
        end
    end
    return pieces
end

local function RemoveNativeMenuHighlight(frame)
    local nativeHighlight = frame.highlight or (frame.GetHighlightTexture and frame:GetHighlightTexture())
    if nativeHighlight then
        -- 直接清掉黄色 UI-QuestTitleHighlight 的纹理来源；即使外部代码误调用
        -- Show()，这里也没有任何黄色像素可显示。区域几何仍保留给菜单测量。
        nativeHighlight:SetTexture(nil)
        nativeHighlight:SetAlpha(0)
        nativeHighlight:Hide()
    end
end

local function PaintModernMenuRow(frame)
    RemoveNativeMenuHighlight(frame)

    local pieces = frame._exModernMenuHighlightPieces
    if not pieces then return end
    local useSelectedVisual = frame._exModernMenuSelected and not frame._exModernMenuHoverOnly
    local color = useSelectedVisual
        and (frame._exModernMenuHover and MC.menuSelectedHover or MC.menuSelected)
        or (frame._exModernMenuHover and MC.menuHover or nil)
    for _, texture in ipairs(pieces) do
        if color and frame._exModernMenuEnabled then
            texture:SetVertexColor(unpack(color))
            texture:Show()
        else
            texture:Hide()
        end
    end
    local fontString = frame.fontString or frame.Text
    if fontString then
        local textColor = not frame._exModernMenuEnabled and MC.disabledText
            or (useSelectedVisual and MC.lightBlue)
            or (frame._exModernMenuHover and MC.text)
            or MC.text
        fontString:SetTextColor(unpack(textColor))
    end
end

local function ModernMenuRowOnEnter(frame)
    frame._exModernMenuHover = true
    PaintModernMenuRow(frame)
end

local function ModernMenuRowOnLeave(frame)
    frame._exModernMenuHover = false
    PaintModernMenuRow(frame)
end

local function AttachModernMenuSubmenuArrow(frame, enabled, selected)
    local nativeArrow = frame.arrow
    if not nativeArrow or not frame.AttachTexture then return end
    nativeArrow:SetAlpha(0)

    local arrow = frame:AttachTexture()
    arrow:SetTexture(MODERN_MEDIA .. "GlyphChevron.tga", "CLAMP", "CLAMP", "LINEAR")
    arrow:SetPoint("CENTER", nativeArrow, "CENTER", 0, 0)
    arrow:SetSize(14, 14)
    arrow:SetDrawLayer("ARTWORK", 2)
    -- GlyphChevron 的默认方向向下；旋转四分之一圈后用于右侧子菜单指示。
    arrow:SetRotation(math.pi / 2)
    arrow:SetVertexColor(unpack(enabled and (selected and MC.lightBlue or MC.muted) or MC.disabledText))
end

-- Every menu row is still created and reclaimed by Blizzard_Menu.  This
-- initializer only restyles compositor-owned regions after the stock
-- initializer has built them; no global MenuVariants mutation and no
-- persistent proxy-frame textures are involved.
local AttachModernMenuCheckboxMark
local function StyleModernMenuDescription(description, role)
    if not description or not description.AddInitializer then return description end
    description:AddInitializer(function(frame, elementDescription)
        if not frame then return end

        local enabled = not elementDescription.IsEnabled or elementDescription:IsEnabled()
        local selected = elementDescription.IsSelected and elementDescription:IsSelected() == true
        -- compositor:Clear() 已经把上一轮 AttachTexture 归还资源池；这里只丢弃
        -- 旧 Lua 引用，绝不能再 Hide() 它们，否则可能误伤本轮刚租出的勾号或图标。
        frame._exModernMenuHighlightPieces = nil
        frame._exModernMenuHover = frame.IsMouseMotionFocus and frame:IsMouseMotionFocus() or false
        local checkboxRole = role == "multiCheckbox"
        if (role == "button" or checkboxRole) and frame.SetHeight and frame.GetHeight then
            frame:SetHeight(math.max(MODERN_MENU_ROW_HEIGHT, frame:GetHeight() or 0))
        end
        local fontString = frame.fontString or frame.Text
        if fontString then
            local color = not enabled and MC.disabledText
                or (role == "title" and MC.muted)
                or (selected and not checkboxRole and MC.lightBlue)
                or MC.text
            fontString:SetFontObject(role == "title" and MODERN.menuFonts.title or MODERN.menuFonts.control)
            fontString:SetTextColor(unpack(color))
            if fontString.SetShadowOffset then fontString:SetShadowOffset(0, 0) end
            if (role == "button" or checkboxRole) and fontString.ClearAllPoints and fontString.SetPoint then
                -- 勾号占用 x=10..26；文字固定从 x=34 起，保留 8px 间距。
                -- 没有 selection 列的普通按钮则使用标准 10px 左内距。
                fontString:ClearAllPoints()
                fontString:SetPoint("LEFT", frame, "LEFT", frame.leftTexture1 and 34 or 10, 0)
                fontString:SetHeight(20)
            end
        end

        if role == "button" or checkboxRole then
            frame._exModernMenuSelected = selected
            frame._exModernMenuHoverOnly = checkboxRole
            frame._exModernMenuEnabled = enabled
            frame._exModernMenuHighlightPieces = AttachModernMenuRowHighlight(frame)
            -- Blizzard ButtonInitializer 每轮都会把这两个方法重设为显示/隐藏
            -- UI-QuestTitleHighlight。此 initializer 排在其后，直接替换为唯一的
            -- 浅蓝 R4 painter；description 自己的 OnEnter/OnLeave、submenu 与 tooltip
            -- 由 HandleOnEnter/HandleOnLeave 的后续独立步骤执行，不会被跳过。
            frame.OnEnter = ModernMenuRowOnEnter
            frame.OnLeave = ModernMenuRowOnLeave
            PaintModernMenuRow(frame)
        else
            frame._exModernMenuSelected = false
            frame._exModernMenuHoverOnly = false
            frame._exModernMenuEnabled = false
        end

        if checkboxRole then
            AttachModernMenuCheckboxMark(frame, enabled, selected)
        else
            AttachModernMenuSelectionMark(frame, enabled, selected)
        end
        AttachModernMenuSubmenuArrow(frame, enabled, selected)
        if frame.divider then frame.divider:SetVertexColor(unpack(MC.headerDivider)) end
    end)
    return description
end

local function ModernMenuButton(description)
    return StyleModernMenuDescription(description, "button")
end

local function ModernMenuMultiselectCheckbox(description)
    return StyleModernMenuDescription(description, "multiCheckbox")
end

local function ModernMenuTitle(description)
    return StyleModernMenuDescription(description, "title")
end

local function ModernMenuDivider(description)
    return StyleModernMenuDescription(description, "divider")
end

local function ModernMenuThinDivider(description)
    if not description or not description.AddInitializer then return description end
    description:AddInitializer(function(frame)
        if not frame then return end
        if frame.divider then frame.divider:SetAlpha(0); frame.divider:Hide() end
        if not frame.AttachTexture then return end
        local line = frame:AttachTexture()
        line:SetTexture(MODERN_MEDIA .. "FillR4.tga", "CLAMP", "CLAMP", "LINEAR")
        line:SetTexCoord(.49, .51, .49, .51)
        line:SetPoint("LEFT", frame, "LEFT", 8, 0)
        line:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
        scale = type(scale) == "number" and scale > 0 and scale or 1
        local factor = PixelUtil and PixelUtil.GetPixelToUIUnitFactor
            and PixelUtil.GetPixelToUIUnitFactor() or 1
        factor = type(factor) == "number" and factor > 0 and factor or 1
        line:SetHeight(factor / scale)
        line:SetDrawLayer("ARTWORK", 1)
        line:SetVertexColor(unpack(MC.headerDivider))
    end)
    return description
end

local function IsModernMenuSoundPreviewPlaying(handle)
    if not handle then return false end
    if _G.C_Sound and type(_G.C_Sound.IsPlaying) == "function" then
        return _G.C_Sound.IsPlaying(handle) == true
    end
    -- 无 IsPlaying 的旧客户端仍可在第二次点击时用保存的 handle 停止。
    return true
end

local function StopModernMenuSoundPreview()
    local state = EXUI._modernMenuSoundPreview
    if not state then return end
    if state.handle and type(_G.StopSound) == "function" then
        _G.StopSound(state.handle)
    end
    state.handle, state.path = nil, nil
end

local function PaintModernMenuSoundPreviewButton(button)
    local enabled = not button.IsEnabled or button:IsEnabled()
    local hover = enabled and button._exModernHover
    if button._exModernSoundIcon then
        if not enabled then
            button._exModernSoundIcon:SetVertexColor(unpack(MC.disabledText))
        elseif hover then
            button._exModernSoundIcon:SetVertexColor(unpack(MC.white))
        else
            button._exModernSoundIcon:SetVertexColor(unpack(MC.secondaryPressedText))
        end
        button._exModernSoundIcon:SetAlpha(1)
    end
end


local function AttachModernMenuSoundPreviewButton(row, path)
    local playButton = MenuTemplates.AttachBasicButton(row, 22, 20)
    playButton:SetPoint("RIGHT", -3, 0)
    playButton._exSoundPath = path

    local icon = playButton:AttachTexture()
    icon:SetPoint("CENTER")
    icon:SetSize(18, 18)
    icon:SetTexture(MODERN_MEDIA .. "GlyphSpeaker.tga", "CLAMP", "CLAMP", "LINEAR")
    -- 原生 18px 透明图形：默认浅灰，悬停纯白；不叠加按钮底色。
    icon:SetBlendMode("BLEND")
    icon:SetDrawLayer("ARTWORK", 2)
    playButton._exModernSoundIcon = icon

    playButton:SetScript("OnEnter", function(self)
        self._exModernHover = true
        PaintModernMenuSoundPreviewButton(self)
    end)
    playButton:SetScript("OnLeave", function(self)
        self._exModernHover = false
        PaintModernMenuSoundPreviewButton(self)
    end)
    if playButton.SetEnabled then playButton:SetEnabled(type(path) == "string" and path ~= "") end
    if MenuTemplates.SetUtilityButtonTooltipText then
        MenuTemplates.SetUtilityButtonTooltipText(playButton, L["试听 / 停止"])
    end
    MenuTemplates.SetUtilityButtonClickHandler(playButton, function()
        local state = EXUI._modernMenuSoundPreview or {}
        EXUI._modernMenuSoundPreview = state
        if state.handle and not IsModernMenuSoundPreviewPlaying(state.handle) then
            state.handle, state.path = nil, nil
        end

        if state.handle then
            local wasSameSound = state.path == path
            StopModernMenuSoundPreview()
            if wasSameSound then
                PaintModernMenuSoundPreviewButton(playButton)
                return
            end
        end

        if type(path) == "string" and path ~= "" then
            local willPlay, soundHandle = PlaySoundFile(path, "Master")
            if willPlay ~= false and soundHandle then
                state.path, state.handle = path, soundHandle
            end
        end
        PaintModernMenuSoundPreviewButton(playButton)
    end)
    row.playBtn = playButton
    PaintModernMenuSoundPreviewButton(playButton)
    return playButton
end

local function AddSearchSpacer(rootDescription)
    local spacer = ModernMenuButton(rootDescription:CreateButton(""))
    spacer:AddInitializer(function(button)
        if not button then return end
        button:SetHeight(EXTERNAL_DROPDOWN_SEARCH_HEIGHT)
        button:SetAlpha(0)
    end)
end

local function ResolveDropdownSearchEnabled(searchConfig)
    if type(searchConfig) == "table" then
        if searchConfig.searchable ~= nil then
            return searchConfig.searchable == true
        end
        if searchConfig.search ~= nil then
            return searchConfig.search == true
        end
    elseif searchConfig ~= nil then
        return searchConfig == true
    end

    return true
end

local function SetDropdownDefaultMenuAnchor(dropdown)
    if dropdown and dropdown.SetMenuAnchor and AnchorUtil and AnchorUtil.CreateAnchor then
        dropdown:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -4))
    end
end

local function EnsureDropdownSearchHooks(dropdown)
    if dropdown._exSearchHooksInstalled or not dropdown.RegisterCallback or not DropdownButtonMixin then
        return
    end

    dropdown._exSearchHooksInstalled = true
    dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuOpen, function(owner)
        local target = owner
        if type(target) ~= "table" then
            target = dropdown
        end

        if target._externalSearchEnabled then
            EnsureDropdownFloatingSearchFrame():ShowForDropdown(target)
        end
    end)
    dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuClose, function(owner, menu, closeReason)
        local target = owner
        if type(target) ~= "table" then
            target = dropdown
        end

        EnsureDropdownFloatingSearchFrame():HideForDropdown(target)
        target._searchText = nil
    end)
end

local function RefreshDropdownSearch(dropdown, newText)
    if not dropdown or not dropdown.GenerateMenu then
        return
    end

    local trimmed = strtrim(newText or "")
    local normalizedText = trimmed ~= "" and trimmed or nil
    if dropdown._searchText == normalizedText then
        return
    end

    dropdown._searchText = normalizedText
    PrepareDropdownMenuForRegeneration(dropdown)
    dropdown:GenerateMenu()
    ResetDropdownMenuScroll(dropdown)
end

EnsureDropdownFloatingSearchFrame = function()
    if EXUI.DropdownFloatingSearchFrame then
        return EXUI.DropdownFloatingSearchFrame
    end

    local frame = CreateFrame("Frame", "ExwindDropdownFloatingSearchFrame", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(300)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetSize(220, EXTERNAL_DROPDOWN_SEARCH_HEIGHT)
    frame:Hide()
    -- 这个 frame 只承载输入框并覆盖菜单首行占位，本身完全透明。
    -- 唯一外壳是 Blizzard_Menu 的 popup；搜索区不再另画第二层 panel。
    local searchBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    searchBox:SetPoint("TOPLEFT", 8, -6)
    searchBox:SetPoint("BOTTOMRIGHT", -8, 6)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(64)
    local searchIcon = EXUI:CreateVisualTexture(searchBox, EXBASEFRAME)
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", 7, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetVertexColor(unpack(MC.muted))
    local instructions = EXUI:CreateVisualFontString(searchBox, EXFONTFRAME)
    MODERN.ApplyTextRole(instructions, "fieldValue", MC.muted)
    instructions:SetPoint("LEFT", 26, 0)
    instructions:SetText(L["搜索..."])
    searchBox.Instructions = instructions
    searchBox:SetTextInsets(26, 6, 0, 0)
    local clearBtn = CreateFrame("Button", nil, searchBox)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", -5, 0)
    clearBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    clearBtn:GetNormalTexture():SetVertexColor(unpack(MC.muted))
    clearBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
    clearBtn:GetHighlightTexture():SetVertexColor(unpack(MC.lightBlue))
    clearBtn:Hide()
    clearBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:SetFocus()
    end)
    searchBox.ClearButton = clearBtn
    frame.SearchBox = searchBox
    searchBox._exModernInputFocusBorder = MC.blue
    searchBox._exModernInputIdleFill = MC.popupSearch
    searchBox._exModernInputActiveFill = MC.popupSearch
    searchBox._exModernInputHoverBorder = MC.popupSearchBorder
    ApplyModernInput(searchBox)

    local divider = EXUI:CreateVisualTexture(frame, EXBORDERFRAME)
    divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 0)
    divider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(unpack(MC.popupDivider))
    frame.Divider = divider

    function frame:AnchorToDropdown(dropdown)
        self:ClearAllPoints()
        local menu = dropdown and dropdown.menu
        local opensUpward = false
        if menu and menu.GetBottom and dropdown and dropdown.GetTop then
            local menuBottom = menu:GetBottom()
            local dropdownTop = dropdown:GetTop()
            if menuBottom and dropdownTop and menuBottom >= (dropdownTop - 2) then
                opensUpward = true
            end
        end

        self:SetParent(UIParent)
        if menu and menu.GetTop then
            -- 搜索承载层直接跟随 popup 的左右边界；不要再给它独立最小宽度，
            -- 否则窄菜单会被搜索框从两侧撑出去。
            self:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
            self:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, 0)
        elseif opensUpward then
            self:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 4)
            self:SetWidth(math.max(dropdown:GetWidth() or 0, 1))
        else
            self:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -4)
            self:SetWidth(math.max(dropdown:GetWidth() or 0, 1))
        end
        if menu and menu.GetFrameStrata and menu.GetFrameLevel then
            self:SetFrameStrata(menu:GetFrameStrata())
            self:SetFrameLevel(menu:GetFrameLevel() + 50)
        elseif dropdown and dropdown.GetFrameStrata and dropdown.GetFrameLevel then
            self:SetFrameStrata(dropdown:GetFrameStrata())
            self:SetFrameLevel(dropdown:GetFrameLevel() + 600)
        end
    end

    function frame:ShowForDropdown(dropdown)
        if not dropdown then
            return
        end

        self.ownerDropdown = dropdown
        self:SetHeight(EXTERNAL_DROPDOWN_SEARCH_HEIGHT)
        self.SearchBox:SetHeight(EXTERNAL_DROPDOWN_SEARCH_HEIGHT - 12)
        local menu = dropdown and dropdown.menu
        self.SearchBox:ClearFocus()
        PaintModernInput(self.SearchBox, self.SearchBox)
        self:AnchorToDropdown(dropdown)
        self:Show()
        self._suppressSearchChange = true
        self.SearchBox:SetText(dropdown._searchText or "")
        self._suppressSearchChange = nil
        self.SearchBox:SetCursorPosition(string.len(self.SearchBox:GetText() or ""))
        C_Timer.After(0, function()
            if self:IsShown() and self.ownerDropdown == dropdown then
                self:AnchorToDropdown(dropdown)
            end
        end)
    end

    function frame:HideForDropdown(dropdown)
        if dropdown and self.ownerDropdown ~= dropdown then
            return
        end

        self.ownerDropdown = nil
        self:SetParent(UIParent)
        self.SearchBox:ClearFocus()
        self.SearchBox:SetText("")
        self:Hide()
    end

    frame.SearchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if self.Instructions then self.Instructions:SetShown(text == "") end
        if self.ClearButton then self.ClearButton:SetShown(text ~= "") end
        if frame._suppressSearchChange then return end
        local dropdown = frame.ownerDropdown
        if dropdown then
            RefreshDropdownSearch(dropdown, self:GetText())
            C_Timer.After(0, function()
                if frame:IsShown() and frame.ownerDropdown == dropdown and dropdown.menu and dropdown.menu:IsShown() then
                    frame:AnchorToDropdown(dropdown)
                    self:SetFocus()
                    self:SetCursorPosition(string.len(self:GetText() or ""))
                end
            end)
        end
    end)
    frame.SearchBox:SetScript("OnEditFocusLost", function(self)
        if self.Instructions then self.Instructions:SetShown((self:GetText() or "") == "") end
    end)
    frame.SearchBox:SetScript("OnEditFocusGained", function(self)
        if self.Instructions then self.Instructions:Hide() end
    end)
    frame.SearchBox:SetScript("OnEscapePressed", function(self)
        local dropdown = frame.ownerDropdown
        self:ClearFocus()
        if dropdown and dropdown.CloseMenu then
            dropdown:CloseMenu()
        else
            frame:HideForDropdown()
        end
    end)
    frame.SearchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    EXUI.DropdownFloatingSearchFrame = frame
    return frame
end

local function ConfigureDropdownExternalSearch(dropdown)
    if not dropdown then
        return
    end

    dropdown._externalSearchEnabled = true
    EnsureDropdownSearchHooks(dropdown)

    if dropdown.SetMenuAnchor and AnchorUtil and AnchorUtil.CreateAnchor then
        dropdown:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -4))
    end
end

local function SetDropdownSearchEnabled(dropdown, searchConfig)
    if not dropdown then
        return
    end

    local enabled = ResolveDropdownSearchEnabled(searchConfig)
    dropdown._externalSearchEnabled = enabled
    dropdown._searchText = nil

    if enabled then
        ConfigureDropdownExternalSearch(dropdown)
    else
        local searchFrame = EXUI.DropdownFloatingSearchFrame
        if searchFrame then
            searchFrame:HideForDropdown(dropdown)
        end
        EnsureDropdownSearchHooks(dropdown)
        SetDropdownDefaultMenuAnchor(dropdown)
    end
end

-- =========================================================
-- [Core] 统一标签样式更新 (ExwindGrid 编辑器专用)
-- =========================================================
function EXUI:UpdateLabelStyle(widget, size, pos)
    if not widget then return end

    -- `size` remains accepted for configuration compatibility, but typography
    -- is owned exclusively by ApplyControlAppearance's semantic text roles.
    local label = widget.labelText or widget.label or widget.Title
    if not label then return end

    widget._exLabel = label
    local gType = widget._gridType and widget._gridType:lower() or ""

    -- Shared composite controls own their label geometry as well as typography.
    if gType:find("fontgroup") or gType:find("header") or gType:find("soundgroup") or gType:find("modulecommonsettings")
        or gType:find("description") or gType:find("card") or gType:find("checkbox") or gType:find("slider") then
        return
    end

    -- [Fix] 对于特定的组组件，不碰位置
    if gType == "fontgroup" or gType == "gridfontgroup" or gType == "header" or gType == "gridheader"
        or gType == "soundgroup" or gType == "subheader" or gType == "gridsubheader" or gType == "icongroup" or gType == "glow_settings"
        or gType == "color" or gType == "colorbutton" or gType == "gridcolorbutton"
        or gType == "description" or gType == "griddescription" or gType == "card" or gType == "gridcard" then
        return
    end

    -- Grid controls may still choose label placement and wrapping.
    if not pos then pos = "top" end
    label:ClearAllPoints()

    if pos == "left" then
        label:SetPoint("RIGHT", widget, "LEFT", -5, 0)
        label:SetJustifyH("RIGHT")
    elseif pos == "right" then
        label:SetPoint("LEFT", widget, "RIGHT", 5, 0)
        label:SetJustifyH("LEFT")
    else -- top
        label:SetPoint("BOTTOMLEFT", widget, "TOPLEFT", 0, 3)
        if widget._exLabelWrap == true then
            label:SetPoint("BOTTOMRIGHT", widget, "TOPRIGHT", 0, 3)
        end
        label:SetJustifyH("LEFT")
    end
    label:SetWordWrap(widget._exLabelWrap == true)
    if label.SetMaxLines then
        label:SetMaxLines(tonumber(widget._exLabelMaxLines) or 0)
    end
end

-- =========================================================
-- 0. 通用单选下拉菜单 (Generic Dropdown) - [v4.3.1] 支持池化
-- items 格式: { "选项1", "选项2" } 或 { {"显示文字", "实际值"}, ... }
-- =========================================================
function EXUI:CreateDropdown(parent, width, label, items, currentValue, onSelect, searchConfig)
    local EXFactory = _G.ExwindFactory
    local dropdown

    if EXFactory then
        -- 从池获取
        dropdown = self:AcquireControl("GridDropdown", parent)
    else
        -- 兜底：传统创建
        dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown._gridType = "GridDropdown"
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME)
        dropdown.labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
        if dropdown.Text then
            dropdown.Text:ClearAllPoints()
            dropdown.Text:SetPoint("LEFT", 8, 0)
            dropdown.Text:SetPoint("RIGHT", dropdown.Arrow, "LEFT", -2, 0)
        end
        if dropdown.Arrow then
            dropdown.Arrow:ClearAllPoints()
            dropdown.Arrow:SetPoint("RIGHT", -2, 0)
        end
    end

    ApplyGridDropdownSize(dropdown, width)
    SyncDropdownMenuLayer(dropdown, parent)
    -- GridDropdown 来自对象池。上一次页面可能为“未启用条件”调用过 Disable()；
    -- 每次借用必须先恢复，当前调用方若确需禁用会在创建后自行 Disable()。
    if dropdown.Enable then
        dropdown:Enable()
    end
    if dropdown.EnableMouse then
        dropdown:EnableMouse(true)
    end
    self:ApplyControlAppearance(dropdown)
    dropdown.labelText:SetText(label or "")

    -- [v4.3.2 Fix] 将状态挂载到 Self，避免 SetupMenu 闭包捕获导致内存泄漏
    dropdown._currentValue = currentValue
    dropdown._onSelect = onSelect
    dropdown._items = items
    SetDropdownSearchEnabled(dropdown, searchConfig)

    -- [Fix] 递归查找选定值的显示文本
    local function GetEntry(val, list)
        for _, item in ipairs(list or items) do
            if type(item) == "table" then
                if item.isMenu then
                    local found, v = GetEntry(val, item.menu)
                    if found ~= L["请选择..."] then return found, v end
                elseif item[2] == val or (tonumber(item[2]) and tonumber(item[2]) == tonumber(val)) then
                    return item[1], item[2]
                end
            else
                if item == val or (tonumber(item) and tonumber(item) == tonumber(val)) then return item, item end
            end
        end
        return L["请选择..."], nil
    end

    local initialText = GetEntry(currentValue)
    SetDropdownDisplayText(dropdown, initialText)

    -- [Fix] 使用 Self 引用构建菜单
    dropdown:SetupMenu(function(self, rootDescription)
        rootDescription:SetScrollMode(400)
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) end

        local function BuildMenu(rootDesc, list)
            if not list then return end -- [Fix] 防止复用初始化间隙导致的 nil 报错
            for _, item in ipairs(list) do
                if type(item) == "table" and item.isMenu then
                    local subMenu = ModernMenuButton(rootDesc:CreateButton(item.text, function() end))
                    BuildMenu(subMenu, item.menu)
                else
                    local text, value
                    if type(item) == "table" then
                        text, value = item[1], item[2]
                    else
                        text, value = item, item
                    end

                    ModernMenuButton(rootDesc:CreateRadio(text,
                        function()
                            -- [Fix] 必须在闭包内动态获取 self._currentValue，否则状态会死锁
                            return (self._currentValue == value) or (tostring(self._currentValue) == tostring(value))
                        end,
                        function()
                            self._currentValue = value
                            SetDropdownDisplayText(self, text)
                            if self._onSelect then self._onSelect(value, text) end
                        end
                    ))
                end
            end
        end

        local filteredItems = FilterDropdownItems(self._items, self._searchText)
        if filteredItems and #filteredItems > 0 then
            BuildMenu(rootDescription, filteredItems)
        else
            ModernMenuTitle(rootDescription:CreateTitle(L["无匹配结果"]))
        end
    end)

    return dropdown
end

-- =========================================================
-- 1. 字体下拉菜单 (LSM Font) - [v4.3.1] 支持池化
-- =========================================================
function EXUI:CreateLSMDropdown(parent, mediaType, width, label, currentValue, onSelect, searchConfig)
    -- [Fix] 兼容性处理
    if type(currentValue) == "function" and onSelect == nil then
        onSelect = currentValue
        currentValue = nil
    end

    local EXFactory = _G.ExwindFactory
    local dropdown

    if EXFactory then
        -- 复用 GridLSMDropdown 池
        dropdown = self:AcquireControl("GridLSMDropdown", parent)
    else
        -- 兜底
        dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown._gridType = "GridLSMDropdown"
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME)
        dropdown.labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
    end

    ApplyGridDropdownSize(dropdown, width)
    SyncDropdownMenuLayer(dropdown, parent)
    -- GridDropdown 来自对象池。上一次页面可能为“未启用条件”调用过 Disable()；
    -- 每次借用必须先恢复，当前调用方若确需禁用会在创建后自行 Disable()。
    if dropdown.Enable then
        dropdown:Enable()
    end
    if dropdown.EnableMouse then
        dropdown:EnableMouse(true)
    end
    self:ApplyControlAppearance(dropdown)
    dropdown.labelText:SetText(label or "")

    -- [v4.3.2 Fix] 将状态挂载到 Self
    dropdown._selectedValue = currentValue or LSM:GetDefault(mediaType)
    dropdown._onSelect = onSelect
    dropdown._mediaType = mediaType
    SetDropdownSearchEnabled(dropdown, searchConfig)

    SetDropdownDisplayText(dropdown, dropdown._selectedValue)

    dropdown:SetupMenu(function(self, rootDescription)
        if not self._mediaType then return end -- [Fix] 防止复用时 nil 报错
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) else ModernMenuTitle(rootDescription:CreateTitle(L["选择"] .. (self._mediaType == "font" and L["字体"] or self._mediaType))) end
        if rootDescription.SetScrollMode then rootDescription:SetScrollMode(400) end

        local list = LSM:HashTable(self._mediaType)
        local sortedKeys = LSM:List(self._mediaType)
        local searchNeedle = NormalizeDropdownSearchText(self._searchText)
        local hasMatch = false

        for _, key in ipairs(sortedKeys) do
            if searchNeedle == "" or NormalizeDropdownSearchText(key):find(searchNeedle, 1, true) then
                local path = list[key]
                hasMatch = true
                ModernMenuButton(rootDescription:CreateRadio(key, function() return self._selectedValue == key end, function()
                    self._selectedValue = key
                    SetDropdownDisplayText(self, key)
                    if self._onSelect then self._onSelect(key, path) end
                end))
            end
        end

        if not hasMatch then
            ModernMenuTitle(rootDescription:CreateTitle(L["无匹配结果"]))
        end
    end)
    return dropdown
end

-- =========================================================
-- 2. 材质下拉菜单 (LSM Texture/Border/Background/Statusbar) - [v4.3.1] 支持池化
-- =========================================================
function EXUI:CreateLSMTextureDropdown(parent, mediaType, width, label, currentValue, onSelect, searchConfig)
    -- [Fix] 兼容性处理
    if type(currentValue) == "function" and onSelect == nil then
        onSelect = currentValue
        currentValue = nil
    end

    local EXFactory = _G.ExwindFactory
    local dropdown

    if EXFactory then
        -- 复用 GridLSMDropdown 池
        dropdown = self:AcquireControl("GridLSMDropdown", parent)
    else
        -- 兜底
        dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown._gridType = "GridLSMDropdown"
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME)
        dropdown.labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
    end

    ApplyGridDropdownSize(dropdown, width)
    SyncDropdownMenuLayer(dropdown, parent)
    if dropdown.EnableMouse then
        dropdown:EnableMouse(true)
    end
    self:ApplyControlAppearance(dropdown)
    dropdown.labelText:SetText(label or "")

    local selectedValue = currentValue or LSM:GetDefault(mediaType)
    -- 如果所选 key 在 LSM 中不存在（如用户未安装 SharedMedia），fallback 到 "Solid"
    if selectedValue and not LSM:HashTable(mediaType)[selectedValue] then
        selectedValue = LSM:HashTable(mediaType)["Solid"] and "Solid" or LSM:GetDefault(mediaType)
    end
    dropdown._selectedValue = selectedValue
    dropdown._onSelect = onSelect
    dropdown._mediaType = mediaType
    SetDropdownSearchEnabled(dropdown, searchConfig)
    SetDropdownDisplayText(dropdown, selectedValue or "None")

    dropdown:SetupMenu(function(self, rootDescription)
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) else ModernMenuTitle(rootDescription:CreateTitle(L["选择材质"])) end
        if rootDescription.SetScrollMode then rootDescription:SetScrollMode(400) end

        local list = LSM:HashTable(self._mediaType)
        local sortedKeys = LSM:List(self._mediaType)
        local searchNeedle = NormalizeDropdownSearchText(self._searchText)
        local hasMatch = false

        for _, key in ipairs(sortedKeys) do
            if searchNeedle == "" or NormalizeDropdownSearchText(key):find(searchNeedle, 1, true) then
                local path = list[key]
                local shortKey = #key > 24 and (string.sub(key, 1, 23) .. "..") or key

                local displayText = shortKey
                if path then
                    if self._mediaType == "statusbar" then
                        displayText = string.format("|T%s:14:100:0:0:64:64:5:59:5:59|t %s", path, shortKey)
                    elseif self._mediaType == "background" then
                        displayText = string.format("|T%s:20:20:0:0:64:64:5:59:5:59|t %s", path, shortKey)
                    elseif self._mediaType == "border" then
                        -- 边框材质通常需要完整显示，不应用内裁剪
                        displayText = string.format("|T%s:14:100|t %s", path, shortKey)
                    else
                        displayText = string.format("|T%s:16:16:0:0:64:64:5:59:5:59|t %s", path, shortKey)
                    end
                end

                hasMatch = true
                local btn = rootDescription:CreateRadio(displayText,
                    function() return self._selectedValue == key end,
                    function()
                        self._selectedValue = key
                        SetDropdownDisplayText(self, key)
                        if self._onSelect then self._onSelect(key, path) end
                    end
                )

                btn:AddInitializer(function(button)
                    CleanDropdownButton(button)
                end)
                ModernMenuButton(btn)
            end
        end

        if not hasMatch then
            ModernMenuTitle(rootDescription:CreateTitle(L["无匹配结果"]))
        end
    end)

    return dropdown
end

-- =========================================================
-- 3. 音效下拉菜单 (LSM Sound with Groups)
-- =========================================================
function EXUI:CreateLSMSoundDropdown(parent, width, label, currentValue, onSelect, searchConfig)
    -- [Fix] 兼容性处理：如果第四个参数是函数，说明是 legacy 调用 (onSelect 放在了 currentValue 位置)
    if type(currentValue) == "function" and onSelect == nil then
        onSelect = currentValue
        currentValue = nil
    end

    local EXFactory = _G.ExwindFactory
    local dropdown
    if EXFactory then
        dropdown = self:AcquireControl("GridLSMDropdown", parent)
    else
        dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown._gridType = "GridLSMDropdown"
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME)
        dropdown.labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
    end
    ApplyGridDropdownSize(dropdown, width)
    SyncDropdownMenuLayer(dropdown, parent)
    if dropdown.EnableMouse then
        dropdown:EnableMouse(true)
    end
    self:ApplyControlAppearance(dropdown)

    -- [池化关键] 将状态挂到 self，避免每次 Render 生成新闭包链
    dropdown._selectedValue = type(currentValue) == "string" and currentValue or LSM:GetDefault("sound")
    dropdown._onSelect = onSelect
    dropdown.labelText:SetText(label or "")
    SetDropdownSearchEnabled(dropdown, searchConfig)

    SetDropdownDisplayText(dropdown, dropdown._selectedValue or "None")

    dropdown:SetupMenu(function(self, rootDescription)
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) else ModernMenuTitle(rootDescription:CreateTitle(L["选择音效"])) end
        if rootDescription.SetScrollMode then rootDescription:SetScrollMode(400) end

        local list = LSM:HashTable("sound")
        local keys = LSM:List("sound")
        local searchNeedle = NormalizeDropdownSearchText(self._searchText)

        -- 分类逻辑
        local exKeys = {}
        local otherKeys = {}
        for _, key in ipairs(keys) do
            if searchNeedle == "" or NormalizeDropdownSearchText(key):find(searchNeedle, 1, true) then
                if key:find("^%(EX%)") then
                    table.insert(exKeys, key)
                else
                    table.insert(otherKeys, key)
                end
            end
        end

        local hasMatch = (#exKeys > 0) or (#otherKeys > 0)
        if not hasMatch then
            ModernMenuTitle(rootDescription:CreateTitle(L["无匹配结果"]))
            return
        end

        local function AddSoundToMenu(targetDescription, key, path)
            local shortKey = #key > 50 and (string.sub(key, 1, 49) .. ".") or key
            local btn = targetDescription:CreateRadio(shortKey,
                function() return self._selectedValue == key end,
                function()
                    self._selectedValue = key
                    SetDropdownDisplayText(self, key)
                    if self._onSelect then self._onSelect(key, path) end
                end
            )

            btn:AddInitializer(function(button, description, menu)
                CleanDropdownButton(button)
                AttachModernMenuSoundPreviewButton(button, path)
            end)
            ModernMenuButton(btn)
        end

        if #exKeys > 0 then
            local submenu = ModernMenuButton(rootDescription:CreateButton(L["EXWIND音效"]))
            for _, key in ipairs(exKeys) do
                AddSoundToMenu(submenu, key, list[key])
            end
            if #otherKeys > 0 then
                ModernMenuDivider(rootDescription:CreateDivider())
            end
        end

        for _, key in ipairs(otherKeys) do
            AddSoundToMenu(rootDescription, key, list[key])
        end
    end)

    return dropdown
end

-- =========================================================
-- 4. 多选下拉菜单 (Multi-Select)
-- =========================================================
function EXUI:CreateMultiSelectDropdown(parent, width, label, options, selections, onUpdate, searchConfig)
    local EXFactory = _G.ExwindFactory
    local dropdown

    if EXFactory then
        -- 复用 GridDropdown 池 (它本身就是 DropdownButton + Label)
        dropdown = self:AcquireControl("GridDropdown", parent)
    else
        -- 兜底
        dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown._gridType = "GridDropdown"
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME)
        dropdown.labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
    end

    ApplyGridDropdownSize(dropdown, width)
    SyncDropdownMenuLayer(dropdown, parent)
    if dropdown.EnableMouse then
        dropdown:EnableMouse(true)
    end
    self:ApplyControlAppearance(dropdown)
    dropdown.labelText:SetText(label or "")

    -- [v4.3.2] 将状态挂载到 Self，防止闭包泄漏
    dropdown._options = options
    dropdown._selections = selections
    dropdown._onUpdate = onUpdate
    local effectiveSearchConfig = searchConfig
    if effectiveSearchConfig == nil then
        -- Short menus open directly; long specialization lists retain search.
        -- This threshold affects presentation only, never option data.
        effectiveSearchConfig = { searchable = #(options or {}) > 8 }
    end
    SetDropdownSearchEnabled(dropdown, effectiveSearchConfig)

    local function GetOptionLabel(option)
        if type(option) == "table" then
            return tostring(option[1] or option.label or option[2] or option.value or "")
        end
        return tostring(option or "")
    end

    local function GetOptionValue(option)
        if type(option) == "table" then
            return option[2] ~= nil and option[2] or option.value or option[1] or option.label
        end
        return option
    end

    local function CountSelected(owner)
        local selected, total = 0, 0
        for _, option in ipairs(owner._options or {}) do
            total = total + 1
            if owner._selections[GetOptionValue(option)] then selected = selected + 1 end
        end
        return selected, total
    end

    -- [Fix] 重命名为 RefreshSelectionDisplay 避免与 Blizzard 内部方法冲突导致栈溢出
    function dropdown:RefreshSelectionDisplay()
        local selectedLabels = {}
        for _, option in ipairs(self._options) do
            local optionValue = GetOptionValue(option)
            if self._selections[optionValue] then
                table.insert(selectedLabels, GetOptionLabel(option))
            end
        end
        local display = L["未选择"]
        if #selectedLabels > 0 and #selectedLabels == #(self._options or {}) then
            display = L["全部"]
        elseif #selectedLabels > 0 then
            if #selectedLabels <= 2 then
                display = table.concat(selectedLabels, ", ")
            else
                display = string.format(L["已选 %d 项"], #selectedLabels)
            end
        end
        SetDropdownDisplayText(self, display)
        if self._onUpdate then self._onUpdate(self._selections) end
    end

    dropdown:RefreshSelectionDisplay()

    dropdown:SetupMenu(function(self, rootDescription)
        rootDescription:SetScrollMode(400)
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) else ModernMenuTitle(rootDescription:CreateTitle(label)) end

        if not self._options then return end

        local searchNeedle = NormalizeDropdownSearchText(self._searchText)
        local hasMatch = false
        for _, option in ipairs(self._options) do
            local optionLabel = GetOptionLabel(option)
            local optionValue = GetOptionValue(option)
            if searchNeedle == "" or NormalizeDropdownSearchText(optionLabel):find(searchNeedle, 1, true) then
                hasMatch = true
                local optionDescription = rootDescription:CreateCheckbox(optionLabel,
                    function() return self._selections[optionValue] == true end,
                    function()
                        self._selections[optionValue] = not self._selections[optionValue]
                        self:RefreshSelectionDisplay()
                        return MenuResponse.Refresh
                    end
                )
                ModernMenuMultiselectCheckbox(optionDescription)
            end
        end

        if not hasMatch then
            ModernMenuTitle(rootDescription:CreateTitle(L["无匹配结果"]))
        end
        ModernMenuThinDivider(rootDescription:CreateDivider())
        local selectedCount, totalCount = CountSelected(self)
        local footer = ModernMenuButton(rootDescription:CreateButton(L["清空"], function()
            for key in pairs(self._selections) do self._selections[key] = nil end
            self:RefreshSelectionDisplay()
            return MenuResponse.Refresh
        end))
        footer:AddInitializer(function(frame)
            if not frame or not frame.AttachFontString then return end
            frame:SetHeight(math.max(MODERN_MENU_ROW_HEIGHT, frame:GetHeight() or 0))
            local clearText = frame.fontString or frame.Text
            if clearText then
                clearText:ClearAllPoints()
                clearText:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
                clearText:SetTextColor(unpack(MC.lightBlue))
            end
            local countText = frame:AttachFontString()
            countText:SetPoint("LEFT", frame, "LEFT", 10, 0)
            countText:SetFontObject(MODERN.menuFonts.control)
            countText:SetText(string.format(L["已选 %d/%d"], selectedCount, totalCount))
            countText:SetTextColor(unpack(MC.muted))
        end)
    end)

    -- 兼容旧接口
    dropdown.dropdown = dropdown

    return dropdown
end

-- =========================================================
-- 5. 通用按钮 (Button) - [v4.3.1] 支持池化
-- =========================================================
function EXUI:CreateButton(parent, width, height, text, onClick, options)
    local EXFactory = _G.ExwindFactory
    local btn

    if EXFactory then
        -- 从池获取
        btn = self:AcquireControl("GridButton", parent)
        -- 清理旧的 OnClick
        btn:SetScript("OnClick", nil)
        btn:SetScript("PreClick", nil)
        btn:SetScript("PostClick", nil)
        btn:SetScript("OnMouseDown", nil)
        btn:SetScript("OnMouseUp", nil)
    else
        -- 兜底
        btn = CreateFrame("Button", nil, parent, "SharedButtonLargeTemplate")
        btn._gridType = "GridButton"
    end

    -- Existing compact utility buttons keep their explicit small footprint.
    -- Standard text buttons share the minimum and padding; no per-page colors.
    local requestedPresentation = type(options) == "table" and options.presentation or nil
    btn._exButtonPresentation = requestedPresentation == "sidebar" and "sidebar" or nil
    btn._exSidebarSelected = nil
    btn._exSidebarLevel = type(options) == "table" and tonumber(options.level) or nil
    local label = EnsureTextButtonFontString(btn)
    if btn._exButtonPresentation ~= "sidebar" then
        btn.label = nil
    end
    btn._exButtonCompact = type(options) == "table" and options.compact == true
    btn._exButtonPainted = nil
    btn._exButtonKeyboardFocused = nil
    btn:SetSize(btn._exButtonCompact and width or math.max(BUTTON_STYLE.minWidth, width or 120),
        btn._exButtonCompact and (height or 32) or math.max(MODERN.metrics.button + BUTTON_STYLE.paddingY * 2, height or 32))
    local requestedVariant = type(options) == "table" and options.variant or nil
    -- 旧 soft / neutral 调用继续有效，但统一落到新的“次要按钮”语义。
    if requestedVariant == "primary" or requestedVariant == "danger" then
        btn._exButtonVariant = requestedVariant
    else
        btn._exButtonVariant = "secondary"
    end
    if btn.EnableMouse then
        btn:EnableMouse(true)
    end
    if btn.Enable then
        btn:Enable()
    end
    if btn.RegisterForClicks then
        btn:RegisterForClicks("LeftButtonUp")
    end

    btn:SetText(text or "")
    if btn._exButtonPresentation == "sidebar" then
        label:SetText(text or "")
    end
    self:ApplyControlAppearance(btn)
    label = EnsureTextButtonFontString(btn)
    if label then
        label:ClearAllPoints()
        if btn._exButtonPresentation == "sidebar" then
            LayoutSidebarNavigationButton(btn)
        elseif btn._exButtonCompact then
            label:SetPoint("CENTER", btn, "CENTER")
        else
            label:SetPoint("TOPLEFT", btn, "TOPLEFT", BUTTON_STYLE.paddingX, -BUTTON_STYLE.paddingY)
            label:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -BUTTON_STYLE.paddingX, BUTTON_STYLE.paddingY)
        end
        label:SetJustifyH(btn._exButtonPresentation == "sidebar" and "LEFT" or "CENTER")
        label:SetJustifyV("MIDDLE")
    end

    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    return btn
end

-- Sidebar navigation is a presentation of the shared GridButton lease, not a
-- separate button implementation or pool. Consumers provide text/click/state;
-- hover, selected visuals and pooled-state cleanup remain owned by EXUI.
function EXUI:CreateSidebarNavigationButton(parent, text, onClick, options)
    options = type(options) == "table" and options or {}
    local level = tonumber(options.level) or 0
    local height = tonumber(options.height) or (level > 0 and 24 or 28)
    local btn = self:CreateButton(parent, tonumber(options.width) or 1, height, text or "", onClick, {
        compact = true,
        presentation = "sidebar",
        level = level,
    })
    btn:SetHeight(height)
    self:SetSidebarNavigationButtonState(btn, options.selected == true, options.enabled ~= false)
    return btn
end

function EXUI:SetSidebarNavigationButtonLevel(button, level)
    if not button or button._exButtonPresentation ~= "sidebar" then return end
    button._exSidebarLevel = tonumber(level) or 0
    button:SetHeight(button._exSidebarLevel > 0 and 24 or 28)
    LayoutSidebarNavigationButton(button)
    PaintModernButton(button)
end

function EXUI:SetSidebarNavigationButtonState(button, selected, enabled)
    if not button or button._exButtonPresentation ~= "sidebar" then return end
    button._exSidebarSelected = selected == true
    if enabled == false then
        button._exModernHover = nil
        button._exModernPressed = nil
        button:Disable()
    else
        button:Enable()
    end
    PaintModernButton(button)
end

function EXUI:ReleaseSidebarNavigationButton(button)
    if not button or button._exButtonPresentation ~= "sidebar" then return false end
    if button._exSidebarLabel then
        button._exSidebarLabel:SetText("")
        button._exSidebarLabel:ClearAllPoints()
        button._exSidebarLabel:Hide()
    end
    button:SetScript("OnClick", nil)
    button:SetScript("PreClick", nil)
    button:SetScript("PostClick", nil)
    local factory = _G.ExwindFactory
    if button._fromPool and factory then
        factory:Release(button._fromPool, button)
    else
        button:Hide()
        button:ClearAllPoints()
        button:SetParent(nil)
    end
    return true
end

function EXUI:CreateSidebarNavigationHeader(parent, text, options)
    options = type(options) == "table" and options or {}
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(tonumber(options.height) or 24)
    header.label = self:CreateVisualFontString(header, EXFONTFRAME)
    header.label:SetPoint("LEFT", header, "LEFT", 0, 0)
    header.label:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    header.label:SetJustifyH("LEFT")
    header.label:SetJustifyV("MIDDLE")
    header.label:SetFontObject(MODERN.menuFonts.title)
    header.label:SetTextColor(unpack(GC.text))
    header.label:SetText(text or "")
    return header
end

-- =========================================================
-- 5b. 图片按钮 (PicButton) - 支持 Normal/Pushed/Highlight 贴图
-- =========================================================
function EXUI:CreatePicButton(parent, width, height, normalTex, pushedTex, highlightTex, onClick, noCrop)
    local btn = CreateFrame("Button", nil, parent)
    btn._gridType = "GridPicButton"
    btn:SetSize(width or 32, height or 32)

    local crop = (not noCrop) and { 0.08, 0.92, 0.08, 0.92 } or { 0, 1, 0, 1 }

    -- 1. 正常状态贴图
    if normalTex then
        local n = EXUI:CreateVisualTexture(btn, EXBASEFRAME)
        n:SetTexture(normalTex)
        n:SetAllPoints()
        n:SetTexCoord(unpack(crop))
        btn:SetNormalTexture(n)
        btn.Normal = n
    end

    -- 2. 按下状态贴图
    if pushedTex then
        local p = EXUI:CreateVisualTexture(btn, EXBASEFRAME)
        p:SetTexture(pushedTex)
        p:SetAllPoints()
        p:SetTexCoord(unpack(crop))
        btn:SetPushedTexture(p)
        btn.Pushed = p
    else
        -- ...
        -- 自动生成按下效果：稍微缩小并位移
        btn:SetPushedTextOffset(1, -1)
        if btn.Normal then
            -- 如果没有 Pushed 贴图，按下时给 Normal 加点暗色滤镜
            btn:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)
        end
    end

    -- 3. 高亮(滑过)状态贴图
    if highlightTex then
        local h = EXUI:CreateVisualTexture(btn, EXEDITORFRAME)
        h:SetTexture(highlightTex)
        h:SetAllPoints()
        h:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn:SetHighlightTexture(h)
    else
        -- 自动生成高亮效果：半透明白光
        local h = EXUI:CreateVisualTexture(btn, EXEDITORFRAME)
        h:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
        h:SetAllPoints()
        h:SetBlendMode("ADD")
        btn:SetHighlightTexture(h)
    end

    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end

-- =========================================================
-- 6. 通用勾选框 (CheckBox) - [v4.3.1] 支持池化
-- =========================================================
function EXUI:CreateCheckbox(parent, text, initialValue, onClick)
    local EXFactory = _G.ExwindFactory
    local container

    if EXFactory then
        -- 从池获取（池中已预创建 checkbox 和 label）
        container = self:AcquireControl("GridCheckbox", parent)
    else
        -- 兜底：传统创建
        container = CreateFrame("Frame", nil, parent)
        container._gridType = "GridCheckbox"
        container:SetSize(200, 28)

        local cb = CreateFrame("CheckButton", nil, container, "MinimalCheckboxTemplate")
        cb:SetSize(28, 28)
        cb:SetPoint("LEFT", container, "LEFT", 0, 0)
        -- 移除旧版硬编码贴图，使用模板自带的现代 Atlas
        container.checkbox = cb

        local label = EXUI:CreateVisualFontString(container, EXFONTFRAME)
        label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        container.label = label

        function container:SetChecked(v) self.checkbox:SetChecked(v) end

        function container:GetChecked() return self.checkbox:GetChecked() end
    end

    if container._exSettingsListVisualState then self:RestoreSettingsListControl(container) end
    self:ApplyControlAppearance(container)

    -- 设置当前值
    container:SetSize(200, 28)
    container.checkbox:SetChecked(initialValue)
    container.label:SetText(text or "")
    if container.EnableMouse then
        container:EnableMouse(false)
    end
    container:SetScript("OnEnter", nil)
    container:SetScript("OnLeave", nil)
    if container.checkbox.EnableMouse then
        container.checkbox:EnableMouse(true)
    end
    container.checkbox:SetScript("OnEnter", nil)
    container.checkbox:SetScript("OnLeave", nil)
    container.checkbox:SetScript("PreClick", nil)
    container.checkbox:SetScript("PostClick", nil)

    -- 设置回调
    container.checkbox:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if onClick then onClick(self:GetChecked() == true) end
    end)

    return container
end

-- =========================================================
-- 7. 通用拖动条 (Slider)
--
-- 旧接口保持不变：
--   CreateSlider(parent, width, label, min, max, value, step, formatter, onValueChanged)
--
-- 新接口可以把最后一个参数换成 callbacks 表（或作为第十个参数传入）：
--   { onValueChanged = fn, onBegin = fn, onLive = fn, onCommit = fn }
--
-- onValueChanged 仍在 Slider 的每一次值变化时调用，保证旧页面行为不变。
-- onBegin/onLive/onCommit 只描述用户交互：按下、拖动、放开/输入提交。
-- 程序化静默回填使用 slider:SetEXUIValue(value, "silent")。
-- =========================================================
function EXUI:CreateSlider(parent, width, label, minVal, maxVal, curVal, step, formatter, onValueChanged, callbacks)
    local EXFactory = _G.ExwindFactory
    local slider

    if EXFactory then
        slider = self:AcquireControl("GridSlider", parent)
    else
        slider = CreateFrame("Slider", nil, parent, "MinimalSliderWithSteppersTemplate")
        slider._gridType = "GridSlider"
    end

    -- 青岚原始结构：标题位于左上、数字输入框位于右上，完整轨道在下一行。
    -- 三者都收在 slider 自身的固定高度内；width 表示整个控件宽度。
    local controlWidth = tonumber(width) or 200
    local numberInputWidth = SLIDER_NUMBER_INPUT_WIDTH
    slider:SetSize(controlWidth, EXUI.GridSliderHeight)
    slider._exGridFixedHeight = EXUI.GridSliderHeight

    -- 不覆盖 Frame:SetPoint。MinimalSliderWithSteppersTemplate 的原生布局和
    -- 鼠标命中都依赖该 API；设置页需要微调时，必须在各自的布局常量中显式
    -- 修改，而不能在控件实例上劫持 SetPoint。

    -- 旧热重载/池化实例可能还带着上一版的 root。它不再参与布局，必须
    -- 主动隐藏和解绑，避免一个已隐藏的旧子树在复用时留下错误锚点。
    if slider._exControlRoot then
        slider._exControlRoot:Hide()
        slider._exControlRoot:ClearAllPoints()
    end
    if slider.EnableMouse then
        slider:EnableMouse(true)
    end
    if slider.SetEnabled then
        slider:SetEnabled(true)
    elseif slider.Enable then
        slider:Enable()
    end

    -- [池化关键] 将回调存到 slider 属性。第九参数接受 table，能穿过
    -- ElvUI 对 CreateSlider 的旧签名包装；第十参数是原生路径的可选别名。
    local lifecycle = type(onValueChanged) == "table" and onValueChanged
        or (type(callbacks) == "table" and callbacks)
        or nil
    slider._onValueChanged = type(onValueChanged) == "function" and onValueChanged
        or (lifecycle and lifecycle.onValueChanged)
    slider._onBegin = lifecycle and lifecycle.onBegin or nil
    slider._onLive = lifecycle and lifecycle.onLive or nil
    slider._onCommit = lifecycle and lifecycle.onCommit or nil
    slider._exControlWidth = controlWidth
    -- GridSlider 来自对象池时不能继承上一次拖动的交互状态。
    slider._exDragging = false
    slider._exSetPhase = nil
    slider._exNormalizing = false
    slider._exSyncingInput = false
    slider._exModernHover = nil
    slider._exModernPressed = nil
    local interactiveSlider = slider.Slider or slider
    interactiveSlider._exModernHover = nil
    interactiveSlider._exModernPressed = nil
    for _, key in ipairs({ "Back", "Forward" }) do
        if slider[key] then
            slider[key]._exModernHover = nil
            slider[key]._exModernPressed = nil
        end
    end
    -- 组合控件复用时用这份参数静默回填当前规则的数据。
    slider._exCompositeMin = tonumber(minVal) or 0
    slider._exCompositeMax = tonumber(maxVal) or slider._exCompositeMin

    -- [v4.3.15 Fix] 智能格式化：如果启用了小数步长，自动显示相应的小数位
    local precision = 0
    local numericStep = tonumber(step) or 1
    if numericStep <= 0 then numericStep = 1 end
    slider._exCompositeSteps = (slider._exCompositeMax - slider._exCompositeMin) / numericStep
    if numericStep > 0 and numericStep < 1 then
        -- 0.05/0.001 等步长均以最小必要小数位显示，并避免浮点尾巴。
        while precision < 6 do
            local scale = 10 ^ precision
            if math.abs(numericStep * scale - math.floor(numericStep * scale + 0.5)) < 0.000001 then
                break
            end
            precision = precision + 1
        end
    end
    slider._exStep = numericStep
    slider._exPrecision = precision

    slider._formatter = (type(formatter) == "function") and formatter or function(v)
        if precision > 0 then
            return string.format("%." .. precision .. "f", v)
        else
            return math.floor(v + 0.5) -- 整数模式使用四舍五入
        end
    end

    -- 池化滑块可能已预创建 ValueText/Title；仅在缺失时补建，避免拖动时叠字残影
    if not slider.ValueText then
        slider.ValueText = EXUI:CreateVisualFontString(slider, EXFONTFRAME)
        slider.ValueText:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", -2, 1)
        slider.ValueText:SetJustifyH("RIGHT")
    end
    if not slider.Title then
        slider.Title = EXUI:CreateVisualFontString(slider, EXFONTFRAME)
        slider.Title:SetJustifyH("LEFT")
        slider.Title:SetWordWrap(false)
    end
    slider.labelText = slider.Title

    -- 保留 ValueText 属性给旧皮肤/旧样式代码，但正式可编辑数值由 numberInput 显示。
    slider.ValueText:Hide()

    if not slider.numberInput then
        local input = CreateFrame("EditBox", nil, slider, "BackdropTemplate")
        input:SetAutoFocus(false)
        input:SetJustifyH("CENTER")
        input:SetTextInsets(SLIDER_NUMBER_INPUT_INSET, SLIDER_NUMBER_INPUT_INSET, 0, 0)
        -- 不使用 SetNumeric(true)：部分客户端会因此拒绝负号，而 X/Y 偏移是合法负值。
        input:SetMaxLetters(16)
        slider.numberInput = input
    end

    local numberInput = slider.numberInput
    -- 对象池复用时明确回到当前 slider；不能继承已废弃 control root 的 parent。
    numberInput:SetParent(slider)
    -- 若对象池归还时输入框仍有焦点，先禁止旧闭包在 ClearFocus 期间提交旧 DB。
    numberInput._exSkipLostCommit = true
    numberInput:ClearFocus()
    numberInput._exSkipLostCommit = nil
    numberInput._exModernHover = nil
    numberInput:ClearAllPoints()
    numberInput:SetPoint("TOPRIGHT", slider, "TOPRIGHT", 0, 0)
    numberInput:SetSize(numberInputWidth, SLIDER_NUMBER_INPUT_HEIGHT)
    numberInput:Show()

    -- 标题与数值输入框共用上方 header row；下方轨道保留完整宽度。
    slider.Title:ClearAllPoints()
    slider.Title:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, 0)
    slider.Title:SetPoint("BOTTOMRIGHT", numberInput, "BOTTOMLEFT", -12, 0)
    slider.Title:SetJustifyH("LEFT")
    slider.Title:SetJustifyV("MIDDLE")

    local function NormalizeValue(s, value)
        value = tonumber(value)
        if not value then return nil end

        local minValue = tonumber(s._exCompositeMin) or 0
        local maxValue = tonumber(s._exCompositeMax) or minValue
        if minValue > maxValue then minValue, maxValue = maxValue, minValue end
        value = math.max(minValue, math.min(maxValue, value))

        local increment = tonumber(s._exStep) or 1
        if increment > 0 then
            local units = (value - minValue) / increment
            if units >= 0 then
                units = math.floor(units + 0.5)
            else
                units = math.ceil(units - 0.5)
            end
            value = minValue + units * increment
            value = math.max(minValue, math.min(maxValue, value))
        end

        -- 让 0.1 + 0.2 之类的值回到可显示/可保存的稳定精度。
        local displayPrecision = tonumber(s._exPrecision) or 0
        if displayPrecision > 0 then
            local scale = 10 ^ displayPrecision
            if value >= 0 then
                value = math.floor(value * scale + 0.5) / scale
            else
                value = math.ceil(value * scale - 0.5) / scale
            end
        end
        return value
    end

    local function UpdateDisplayedValue(s, value)
        if s.ValueText and s._formatter then
            s.ValueText:SetText(s._formatter(value))
        end
        local input = s.numberInput
        if input and s._formatter then
            s._exSyncingInput = true
            input:SetText(s._formatter(value))
            input:SetCursorPosition(0)
            s._exSyncingInput = false
        end
    end

    -- MinimalSliderWithSteppersTemplate 的外层是布局/CallbackRegistry 容器，
    -- 实际轨道值属于它的 Slider 子对象。所有读取必须从同一个原生轨道
    -- 取得，不能把外层残留值再写回轨道；否则鼠标放开时会跳回旧值。
    local function GetInnerValue(s)
        local interactiveSlider = s.Slider or s
        return interactiveSlider:GetValue()
    end

    -- 供 Grid/模块在未来接入实时预览时使用；这里不广播、不重建。
    function slider:SetLifecycleCallbacks(newCallbacks)
        newCallbacks = type(newCallbacks) == "table" and newCallbacks or {}
        self._onBegin = newCallbacks.onBegin
        self._onLive = newCallbacks.onLive
        self._onCommit = newCallbacks.onCommit
        if type(newCallbacks.onValueChanged) == "function" then
            self._onValueChanged = newCallbacks.onValueChanged
        end
    end

    function slider:SetEXUIValue(value, phase)
        local normalized = NormalizeValue(self, value)
        if normalized == nil then return false end
        self._exSetPhase = phase
        self._exSilent = phase == "silent"
        local previous = GetInnerValue(self)
        self:SetValue(normalized)
        -- SetValue 不会在相同数值时触发 CallbackRegistry；输入提交仍应有 commit。
        if previous == normalized then
            UpdateDisplayedValue(self, normalized)
            if phase == "commit" and self._onCommit then self._onCommit(normalized) end
        end
        self._exSetPhase = nil
        self._exSilent = nil
        return true
    end

    -- 首次注册回调（只注册一次）
    if not slider._sliderInit then
        -- [v4.3.13 Fix] 传入 slider 作为 owner
        -- CallbackRegistryMixin 的 TriggerEvent 会以 callback(owner, value) 形式调用
        -- 所以第一个参数 s 就是 slider 自身
        slider:RegisterCallback("OnValueChanged", function(s, value)
            local normalized = NormalizeValue(s, value)
            if normalized == nil then return end

            -- 原生轨道可能给出带浮点尾巴的值；只让标准化后的值进入 DB。
            if math.abs(normalized - value) > 0.000001 then
                if not s._exNormalizing then
                    s._exNormalizing = true
                    s:SetValue(normalized)
                    s._exNormalizing = false
                end
                return
            end

            UpdateDisplayedValue(s, normalized)
            if not s._exSilent and s._onValueChanged then s._onValueChanged(normalized) end

            local phase = s._exSetPhase
            if phase == "commit" then
                if s._onCommit then s._onCommit(normalized) end
            elseif s._exDragging or phase == "live" then
                if s._onLive then s._onLive(normalized) end
            end
        end, slider)

        -- MinimalSliderWithSteppersTemplate 本身只是承载 Frame；真正接收轨道
        -- 鼠标的对象是它的 Slider 子项。此前把 Hook 挂在外层，拖动时
        -- _exDragging 永远不会设为 true，生命周期式 Slider 因而既不 live
        -- 也不 commit（输入框的显式 commit 则仍正常），这正是“能输入、
        -- 不能拖动”的根因。
        local interactiveSlider = slider.Slider or slider
        local function BeginDrag(_, button)
            if button ~= nil and button ~= "LeftButton" then return end
            -- 同一次按下可能同时经过模板和外层；begin 只能发一次。
            if slider._exDragging then return end
            slider._exDragging = true
            slider._exDragStartValue = GetInnerValue(slider)
            if slider._onBegin then slider._onBegin(slider._exDragStartValue) end
        end

        interactiveSlider:HookScript("OnMouseDown", BeginDrag)
        -- 原生轨道已经 ObeyStepOnDrag；放开时只提交它的当前值。绝不能在
        -- 此处 Normalize/SetValue，否则会把外层的旧值回写造成鼠标放开跳值。
        interactiveSlider:HookScript("OnMouseUp", function()
            if not slider._exDragging then return end
            slider._exDragging = false
            local value = GetInnerValue(slider)
            local changed = value ~= slider._exDragStartValue
            slider._exDragStartValue = nil
            UpdateDisplayedValue(slider, value)
            -- 仅按下而没有改变值，不发生 DB 写入，也不能触发全量重套造成闪烁。
            if changed and slider._onCommit then slider._onCommit(value) end
        end)

        slider._sliderInit = true
    end

    -- 输入框仅在回车/失焦时提交，输入过程中绝不触发页面全量刷新。
    numberInput:SetScript("OnEditFocusGained", nil)
    numberInput:SetScript("OnEditFocusLost", function(self)
        if self._exSkipLostCommit then
            self._exSkipLostCommit = nil
            return
        end
        if slider._exSyncingInput then return end
        local text = self:GetText():gsub("^%s+", ""):gsub("%s+$", ""):gsub(",", ".")
        local value = NormalizeValue(slider, text)
        if value == nil then
            UpdateDisplayedValue(slider, NormalizeValue(slider, GetInnerValue(slider)))
            return
        end
        slider:SetEXUIValue(value, "commit")
    end)
    numberInput:SetScript("OnEnterPressed", function(self)
        self._exSkipLostCommit = true
        local text = self:GetText():gsub("^%s+", ""):gsub("%s+$", ""):gsub(",", ".")
        local value = NormalizeValue(slider, text)
        if value == nil then
            UpdateDisplayedValue(slider, NormalizeValue(slider, GetInnerValue(slider)))
        else
            slider:SetEXUIValue(value, "commit")
        end
        self:ClearFocus()
    end)
    numberInput:SetScript("OnEscapePressed", function(self)
        self._exSkipLostCommit = true
        UpdateDisplayedValue(slider, NormalizeValue(slider, GetInnerValue(slider)))
        self:ClearFocus()
    end)

    self:ApplyControlAppearance(slider)

    -- 每次调用都更新：标题、数值显示、滑动条值
    if slider.Title then slider.Title:SetText(label or "") end
    local initialValue = NormalizeValue(slider, curVal) or slider._exCompositeMin
    UpdateDisplayedValue(slider, initialValue)

    if slider.Init then
        -- 构造/对象池回填只是显示初值，不能反向触发 DB 广播或模块刷新。
        slider._exSilent = true
        slider:Init(initialValue, slider._exCompositeMin, slider._exCompositeMax, slider._exCompositeSteps)
        slider._exSilent = nil
    elseif slider.SetValue then
        slider._exSilent = true
        slider:SetValue(initialValue)
        slider._exSilent = nil
    end

    return slider
end

-- =========================================================
-- 8. 通用分隔线 (Separator)
-- =========================================================
function EXUI:CreateSeparator(parent, width)
    local line = EXUI:CreateVisualTexture(parent, EXBASEFRAME)
    -- 分隔线必须是一个真实物理像素；UI 缩放下逻辑单位 1 不等于屏幕 1px。
    -- Grid 会在最终布局与 scale 变化时再次重套，非 Grid 调用也在首次创建时正确。
    local PixelUtil = _G.PixelUtil
    if PixelUtil and PixelUtil.SetSize then
        PixelUtil.SetSize(line, width or 200, 1, 1, 1)
    else
        line:SetSize(width or 200, 1)
    end
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetGradient("HORIZONTAL", CreateColor(MC.border[1], MC.border[2], MC.border[3], .95),
        CreateColor(MC.border[1], MC.border[2], MC.border[3], .08))
    return line
end

-- Grid decorations use the same public construction boundary as interactive
-- controls.  Their pooled shells remain owned by Grid, but pages no longer
-- borrow those pools directly and therefore cannot bypass the shared theme.
function EXUI:CreateDivider(parent, width)
    local frame = self:AcquireControl("GridDivider", parent)
    frame:SetSize(width or 200, 20)
    -- Grid needs a frame-shaped pooled host, while the visible one-pixel
    -- region remains the public CreateSeparator implementation.
    if frame.line then frame.line:Hide() end
    if not frame.separator then
        frame.separator = self:CreateSeparator(frame, width or 200)
        frame.separator:ClearAllPoints()
        frame.separator:SetPoint("LEFT")
        frame.separator:SetPoint("RIGHT")
    end
    frame.separator:Show()
    return frame
end

function EXUI:CreateSubheader(parent, text, width)
    local frame = self:AcquireControl("GridSubheader", parent)
    frame:SetSize(width or 200, 24)
    self:ApplyControlAppearance(frame)
    frame.text:SetText(text or "")
    frame.labelText = frame.text
    return frame
end

function EXUI:CreateDescription(parent, text, width)
    local frame = self:AcquireControl("GridDescription", parent)
    frame:SetSize(width or 200, 40)
    self:ApplyControlAppearance(frame)
    frame.text:SetText(text or "")
    frame.labelText = frame.text
    return frame
end

function EXUI:CreateCard(parent, width, height)
    local frame = self:AcquireControl("GridCard", parent)
    frame:SetSize(width or 400, height or 120)
    return self:ApplyControlAppearance(frame)
end

-- =========================================================
-- 9. 分段标题 (Header with Line) - [v4.3.1] 支持池化
-- =========================================================
function EXUI:CreateHeader(parent, text, width)
    local EXFactory = _G.ExwindFactory
    local container

    if EXFactory then
        -- 从池获取（池中已预创建 Title 和 Line）
        container = self:AcquireControl("GridHeader", parent)
    else
        -- 兜底：传统创建
        container = CreateFrame("Frame", nil, parent)
        container._gridType = "GridHeader"
        container:SetSize(width or 550, 40)

        local title = EXUI:CreateVisualFontString(container, EXFONTFRAME)
        title:SetPoint("TOPLEFT", 0, -5)
        container.Title = title

        local line = EXUI:CreateVisualTexture(container, EXBASEFRAME)
        line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
        line:SetPoint("RIGHT", 0, 0)
        local PixelUtil = _G.PixelUtil
        if PixelUtil and PixelUtil.SetHeight then
            PixelUtil.SetHeight(line, 1, 1)
        else
            line:SetHeight(1)
        end
        container.Line = line
    end

    container:SetSize(width or 550, 40)
    self:ApplyControlAppearance(container)
    container.Title:SetText(text or "")

    return container
end

-- =========================================================
-- 10. 复合字体设置组 (Font Setting Group)
-- 传入一个 db 表(需包含 .font, .size, .outline)，会自动创建一整套设置
-- =========================================================
-- =========================================================
-- 11. 颜色选择按钮 (Color Button)
-- =========================================================
-- ColorPickerFrame 是暴雪全局窗口，XML 固定在 DIALOG strata。组合弹窗也在 DIALOG，
-- 因而从组合弹窗打开颜色选择器时，必须临时提升到 FULLSCREEN_DIALOG，否则会被父弹窗盖住。
-- 关闭后恢复原本 strata/level，不能污染暴雪或其他插件的普通颜色选择器。
local function PromoteColorPickerForOwner(owner)
    local picker = _G.ColorPickerFrame
    if not picker or not owner or not owner.GetFrameStrata then return end

    local ownerStrata = owner:GetFrameStrata()
    local ownerLevel = owner.GetFrameLevel and owner:GetFrameLevel() or 0
    if ownerStrata ~= "DIALOG" and ownerStrata ~= "TOOLTIP" and ownerStrata ~= "FULLSCREEN_DIALOG" then return end

    if not picker._exuiColorPickerRestoreHook then
        picker._exuiColorPickerRestoreHook = true
        picker:HookScript("OnHide", function(self)
            local restore = self._exuiColorPickerRestoreLayer
            if not restore then return end
            self:SetFrameStrata(restore.strata)
            self:SetFrameLevel(restore.level)
            self._exuiColorPickerRestoreLayer = nil
        end)
    end

    if not picker._exuiColorPickerRestoreLayer then
        picker._exuiColorPickerRestoreLayer = {
            strata = picker:GetFrameStrata(),
            level = picker:GetFrameLevel(),
        }
    end
    local pickerStrata = ownerStrata == "DIALOG" and "FULLSCREEN_DIALOG" or ownerStrata
    picker:SetFrameStrata(pickerStrata)
    picker:SetFrameLevel(math.max(ownerLevel + 600, picker:GetFrameLevel()))
    if picker.SetToplevel then picker:SetToplevel(true) end
end

function EXUI:CreateColorButton(parent, label, db, key, hasAlpha, onUpdate, options)
    local EXFactory = _G.ExwindFactory
    local btn

    if EXFactory then
        btn = self:AcquireControl("GridColorButton", parent)
    else
        btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        if not btn.swatch then
            btn.swatch = EXUI:CreateVisualTexture(btn, EXBORDERFRAME)
            btn.swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        if not btn.labelText then
            local txt = EXUI:CreateVisualFontString(btn, EXFONTFRAME)
            btn.labelText = txt
        end
        btn._gridType = "GridColorButton"
    end

    -- 1. 主容器
    btn:SetSize(225, 36)
    if btn.EnableMouse then
        btn:EnableMouse(true)
    end
    if btn.SetMouseMotionEnabled then
        btn:SetMouseMotionEnabled(true)
    end
    if btn.SetMouseClickEnabled then
        btn:SetMouseClickEnabled(true)
    end
    if btn.RegisterForClicks then
        btn:RegisterForClicks("LeftButtonUp")
    end

    -- 2. 左侧预览色块
    local swatch = btn.swatch
    if swatch then
        swatch:ClearAllPoints()
        swatch:SetSize(16, 16)
        swatch:SetPoint("LEFT", btn, "LEFT", 10, 0)
        swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
    end

    if not btn.swatchBorder then
        btn.swatchBorder = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        btn.swatchBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        btn.swatchBorder:EnableMouse(false)
        if btn.swatchBorder.SetMouseMotionEnabled then btn.swatchBorder:SetMouseMotionEnabled(false) end
        if btn.swatchBorder.SetMouseClickEnabled then btn.swatchBorder:SetMouseClickEnabled(false) end
    end
    btn.swatchBorder:ClearAllPoints()
    btn.swatchBorder:SetPoint("TOPLEFT", swatch, -1, 1)
    btn.swatchBorder:SetPoint("BOTTOMRIGHT", swatch, 1, -1)
    btn.swatchBorder:SetBackdropBorderColor(0, 0, 0, 0.8)

    -- 3. 文本标签
    if not btn.labelText then
        btn.labelText = btn.label
    end
    if not btn.labelText then
        btn.labelText = EXUI:CreateVisualFontString(btn, EXFONTFRAME)
    end
    local text = btn.labelText
    self:ApplyControlAppearance(btn)
    text:ClearAllPoints()
    text:SetPoint("LEFT", swatch, "RIGHT", 10, 0)
    text:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    text:SetJustifyH("LEFT")
    text:SetText(label or "")

    -- [关键] 属性挂载，以便池化复用时更新
    btn._currentDb = db
    btn._currentKey = key
    btn._currentOnUpdate = onUpdate
    btn._hasAlpha = hasAlpha
    btn._currentChangeFlow = type(options) == "table" and options._changeFlow or nil

    if not btn.UpdateColor then
        function btn:UpdateColor(nr, ng, nb, na)
            local r, g, b, a
            if type(nr) == "number" then
                r, g, b, a = nr, ng, nb, na
            else
                local d, k = self._currentDb, self._currentKey
                if not d then return end
                if not k or k == "" then
                    r, g, b, a = d.r or 1, d.g or 1, d.b or 1, d.a or 1
                else
                    r, g, b, a = d[k .. "R"] or 1, d[k .. "G"] or 1, d[k .. "B"] or 1, d[k .. "A"] or 1
                end
            end
            if self.swatch then
                self.swatch:SetVertexColor(r, g, b, a)
            end
        end
    end

    btn:UpdateColor()

    if not btn.FinishColorTransaction then
        function btn:FinishColorTransaction(token)
            local session = self._colorPickerSession
            if not session or (token ~= nil and session.token ~= token) then return false end
            self._colorPickerSession = nil
            session.transaction.onCommit(session.current)
            return true
        end
    end

    btn:SetScript("OnClick", function(self)
        local d, k = self._currentDb, self._currentKey
        if type(d) ~= "table" then return end

        local function GetDBColor()
            if not k or k == "" then
                return d.r or 1, d.g or 1, d.b or 1, d.a or 1
            else
                return d[k .. "R"] or 1, d[k .. "G"] or 1, d[k .. "B"] or 1, d[k .. "A"] or 1
            end
        end

        local function SetDBColor(r, g, b, a)
            if not k or k == "" then
                d.r, d.g, d.b, d.a = r, g, b, a
            else
                d[k .. "R"], d[k .. "G"], d[k .. "B"], d[k .. "A"] = r, g, b, a
            end
        end

        local currR, currG, currB, currA = GetDBColor()
        local factory = self._currentChangeFlow
        local transaction = type(factory) == "function" and factory() or nil
        local token
        if transaction then
            token = (self._colorPickerToken or 0) + 1
            self._colorPickerToken = token
            self._colorPickerSession = {
                token = token,
                transaction = transaction,
                original = { r = currR, g = currG, b = currB, a = currA },
                current = { r = currR, g = currG, b = currB, a = currA },
            }
            transaction.onBegin()
            if not ColorPickerFrame._exuiColorTransactionHook then
                ColorPickerFrame._exuiColorTransactionHook = true
                ColorPickerFrame:HookScript("OnHide", function(frame)
                    local owner, ownerToken = frame._exuiColorTransactionOwner, frame._exuiColorTransactionToken
                    frame._exuiColorTransactionOwner, frame._exuiColorTransactionToken = nil, nil
                    if owner and type(owner.FinishColorTransaction) == "function" then
                        owner:FinishColorTransaction(ownerToken)
                    end
                end)
            end
            local previousOwner, previousToken = ColorPickerFrame._exuiColorTransactionOwner, ColorPickerFrame._exuiColorTransactionToken
            if previousOwner and type(previousOwner.FinishColorTransaction) == "function" then
                previousOwner:FinishColorTransaction(previousToken)
            end
            ColorPickerFrame._exuiColorTransactionOwner, ColorPickerFrame._exuiColorTransactionToken = nil, nil
        end

        -- 打开 picker 只 Begin 一次；连续 swatch/opacity 回调只写 DB 并 Patch
        -- 当前 Panel。OnHide 才统一 Commit，取消会先恢复打开时的值再受控结束。
        local function ApplyColor(r, g, b, a)
            if transaction then
                local value = { r = r, g = g, b = b, a = a }
                transaction.onLive(value)
                local session = self._colorPickerSession
                if session and session.token == token then session.current = value end
            else
                SetDBColor(r, g, b, a)
                if self._currentOnUpdate then self._currentOnUpdate(d) end
            end
            self:UpdateColor()
        end

        local info = {
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = self._hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
                ApplyColor(r, g, b, a)
            end,
            opacityFunc = self._hasAlpha and function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = ColorPickerFrame:GetColorAlpha()
                ApplyColor(r, g, b, a)
            end or nil,
            cancelFunc = function(prev)
                local session = self._colorPickerSession
                local original = session and session.original
                local r = (prev and prev.r) or (original and original.r) or currR
                local g = (prev and prev.g) or (original and original.g) or currG
                local b = (prev and prev.b) or (original and original.b) or currB
                local a = (prev and (prev.a or prev.opacity)) or (original and original.a) or currA
                ApplyColor(r, g, b, a)
                if transaction then self:FinishColorTransaction(token) end
            end,
            hasOpacity = self._hasAlpha,
            opacity = self._hasAlpha and currA or 1,
            r = currR,
            g = currG,
            b = currB,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
        if transaction then
            ColorPickerFrame._exuiColorTransactionOwner = self
            ColorPickerFrame._exuiColorTransactionToken = token
        end
        PromoteColorPickerForOwner(self)
    end)
    return btn
end

-- =========================================================
-- 10.1 文字设置组（图标设置同款布局）
-- 纯文字样式：时间格式由独立 CreateTimeFormatGroup 负责。
-- =========================================================
-- 组合控件的子控件会常驻在宿主下面。代理把读写转发到“本次借用”的数据表，
-- 这样复用后的 Slider / Dropdown / ColorButton 不会继续引用上一条规则。
local function CompositePathValue(db, path)
    if path == nil or path == "" then return db end
    local value = db
    for part in string.gmatch(path, "[^%.]+") do
        value = type(value) == "table" and value[part] or nil
    end
    return value
end

local function CompositePathSet(db, path, value)
    if type(db) ~= "table" or type(path) ~= "string" or path == "" then return false end
    local target, last = db, nil
    for part in string.gmatch(path, "[^%.]+") do
        if last then
            target[last] = type(target[last]) == "table" and target[last] or {}
            target = target[last]
        end
        last = part
    end
    if not last then return false end
    target[last] = value
    return true
end

local function CreateCompositeProxy(host, path)
    return setmetatable({}, {
        __index = function(_, field)
            local target = CompositePathValue(host._exCompositeDb, path)
            return type(target) == "table" and target[field] or nil
        end,
        __newindex = function(_, field, value)
            local target = CompositePathValue(host._exCompositeDb, path)
            if type(target) == "table" then target[field] = value end
        end,
    })
end

local function AcquireCompositeGroup(poolType, parent)
    local factory = _G.ExwindFactory
    if factory and factory.AcquireCompositeHost then
        return factory:AcquireCompositeHost(poolType, parent)
    end
    return CreateFrame("Frame", nil, parent, "BackdropTemplate"), true
end

-- 右侧弹出面板不能作为 ScrollChild 的子对象：即使设为高层也会被滚动区域裁切。
-- 统一挂在 UIParent 的 DIALOG 层。内部 Dropdown 的列表由 Blizzard_Menu 自动创建在
-- FULLSCREEN_DIALOG，层级天然高于弹窗本身，避免同 TOOLTIP 层互相遮挡。
-- CompositeFontGroup / IconGroup / TimerBarGroup 都从这里取得弹层；层级恢复
-- 必须是这一处的统一职责，不能由各组的右侧按钮各自补丁。
local function RaiseCompositePopupHost(popup)
    if not popup then return end
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(math.max(1000, (UIParent:GetFrameLevel() or 1) + 1000))
    if popup.SetToplevel then popup:SetToplevel(true) end
    -- 同 strata 的浮层会随着点击顺序而重叠；空白区点击也必须把当前 popup
    -- 放回最前，不能让它落到设置主框或另一张已存在 popup 后面。
    if popup.Raise then popup:Raise() end
end

local function CreateCompositePopupHost(owner, width, height)
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    if EXUI.SetControlAppearance then
        EXUI:SetControlAppearance(popup, EXUI:GetControlAppearance(owner))
    end
    popup:SetSize(width, height)
    -- 主面板和它的 ModalLayer 同样在 DIALOG；弹窗必须明显高于二者，
    -- 而其下拉列表再由 FULLSCREEN_DIALOG 覆盖。
    RaiseCompositePopupHost(popup)
    popup:HookScript("OnShow", function(self)
        RaiseCompositePopupHost(self)
        EXUI:ApplyModernPanel(self, true)
    end)
    popup:HookScript("OnMouseDown", RaiseCompositePopupHost)
    popup._exPopupOwner = owner
    return popup
end

-- Composite 控件除自身字段外，允许以纯数据声明“同一 DB、同一次 commit”必须
-- 一并写入的字段。它不是回调、也不保存模块函数；标准 Slider binder 只消费
-- 这份公开元数据，因而接管生命周期后不会丢失控件固有语义。
local function ValidateCompositeCommitWritesMetadata(metadata)
    if metadata == nil then return nil end
    if type(metadata) ~= "table" then
        error("composite control metadata must be table", 3)
    end
    for key in pairs(metadata) do
        if key ~= "commitWrites" then
            error("composite control metadata only supports commitWrites", 3)
        end
    end
    if type(metadata.commitWrites) ~= "table" or #metadata.commitWrites == 0 then
        error("composite control commitWrites must be a non-empty array", 3)
    end
    for index, write in ipairs(metadata.commitWrites) do
        if type(write) ~= "table" or type(write.path) ~= "string" or write.path == "" then
            error("composite control commitWrites entry requires path", 3)
        end
        for key in pairs(write) do
            if key ~= "path" and key ~= "value" then
                error("composite control commitWrites entry only supports path/value", 3)
            end
        end
        local valueType = type(write.value)
        if valueType ~= "boolean" and valueType ~= "number" and valueType ~= "string" then
            error("composite control commitWrites value must be scalar: " .. tostring(index), 3)
        end
    end
    return metadata.commitWrites
end

local function RegisterCompositeControl(host, control, path, kind, metadata)
    if not control then return control end
    local commitWrites = ValidateCompositeCommitWritesMetadata(metadata)
    host._exCompositeControls = host._exCompositeControls or {}
    host._exCompositeControls[#host._exCompositeControls + 1] = {
        control = control, path = path, kind = kind,
        -- 仅允许声明式 commitWrites；禁止把私有 callback 塞进控件 metadata。
        commitWrites = commitWrites,
    }
    return control
end

local function CompositeDropdownText(value, items)
    for _, item in ipairs(items or {}) do
        if type(item) == "table" then
            if item.isMenu then
                local text = CompositeDropdownText(value, item.menu)
                if text then return text end
            elseif item[2] == value or tostring(item[2]) == tostring(value) then
                return item[1]
            end
        elseif item == value or tostring(item) == tostring(value) then
            return item
        end
    end
    return nil
end

local function RefreshCompositeControl(entry, db)
    local control, value = entry.control, CompositePathValue(db, entry.path)
    if not control then return end
    if entry.kind == "color" then
        -- 颜色按钮保存的是嵌套目标表引用。组合组从对象池复用时，必须像其它
        -- 控件一样重绑到本轮 DB；仅 UpdateColor 会继续写入上一次页面的表。
        local colorDB, colorKey = db, entry.path
        local parentPath, directKey = tostring(entry.path or ""):match("^(.*)%.([^%.]+)$")
        if parentPath and directKey then
            for part in string.gmatch(parentPath, "[^%.]+") do
                colorDB = type(colorDB) == "table" and colorDB[part] or nil
            end
            colorKey = directKey
        end
        if type(colorDB) == "table" then
            control._currentDb = colorDB
            control._currentKey = colorKey
        end
        if control.UpdateColor then control:UpdateColor() end
    elseif entry.kind == "check" then
        if control.SetChecked then control:SetChecked(value == true) end
    elseif entry.kind == "slider" then
        local callback = control._onValueChanged
        control._onValueChanged = nil
        if control.Init and control._exCompositeMin ~= nil then
            control:Init(tonumber(value) or control._exCompositeMin, control._exCompositeMin,
                control._exCompositeMax, control._exCompositeSteps)
        elseif control.SetValue then
            control:SetValue(tonumber(value) or 0)
        end
        control._onValueChanged = callback
        if control.ValueText and control._formatter then
            control.ValueText:SetText(control._formatter(tonumber(value) or 0))
        end
    elseif entry.kind == "dropdown" then
        if control._mediaType then
            control._selectedValue = value
            SetDropdownDisplayText(control, value or L["请选择..."])
        else
            control._currentValue = value
            SetDropdownDisplayText(control, CompositeDropdownText(value, control._items) or L["请选择..."])
        end
    elseif entry.kind == "edit" then
        if control.SetText then control:SetText(tostring(value or "")) end
    end
end

local function BindCompositeGroup(host, db, onUpdate, opts)
    host._exCompositeDb = db
    host._exCompositeOnUpdate = onUpdate
    host._exCompositeOpts = opts or {}
    for _, entry in ipairs(host._exCompositeControls or {}) do
        RefreshCompositeControl(entry, db)
    end
    if host._exCompositeTitle and host._exCompositeLabel then
        host._exCompositeTitle:SetText(host._exCompositeLabel)
    end
    if type(host._exCompositeHeaderRefresh) == "function" then
        host:_exCompositeHeaderRefresh()
    end
    if type(host._exCompositeConfigure) == "function" then
        host:_exCompositeConfigure()
    end
end

-- Composite Host 会被 FramePool 交给不同宽度的 Grid 项目复用。仅 SetSize 会让
-- 内部卡片保留上一次借用时的绝对坐标/宽度，因此把“宿主尺寸 + 内部重排”收口。
-- 这里不保存视觉状态，也不触发配置回调；每一种 Composite 在创建时登记自己的
-- 窄布局函数，复用时只按当前实际宽高重新锚定已有控件。
-- Layout cached skins even when SetSize does not fire OnSizeChanged (same-size
-- pool reuse, or a different parent scale). Keep colors, alpha and active state;
-- this pass must not create a new panel or revive an explicitly cleared skin.
function EXUI:RefreshCompositeSurfaces(host)
    local visited = {}
    local function Refresh(frame)
        if not frame or visited[frame] then return end
        visited[frame] = true
        for _, skin in pairs(frame._exModernSurfaces or {}) do
            if type(skin.Layout) == "function" then skin.Layout() end
        end
        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do Refresh(child) end
        end
        for _, popup in ipairs(frame._exCompositePopups or {}) do Refresh(popup) end
    end
    Refresh(host)
end

function EXUI:LayoutCompositeGroup(host, width, height)
    host:SetSize(width, height)
    if type(host._exCompositeReflow) == "function" then
        host:_exCompositeReflow(width, height)
    end
    self:RefreshCompositeSurfaces(host)
end

-- Older preview/item shells explicitly use a panel. Settings groups call the
-- public geometry-only entry above so reuse cannot add a different background.
local function ReflowCompositeGroup(host, width, height)
    EXUI:LayoutCompositeGroup(host, width, height)
    if EXUI.ApplyModernPanel then EXUI:ApplyModernPanel(host) end
end

-- 预览拖动会由模块直接写回同一份 ModuleDB；当前可见 Grid 不能等到重开页面
-- 才重新绑定。组合控件统一从自己已绑定的 DB 回读，避免每个模块分别触碰
-- Slider / Dropdown / Checkbox 私有实现，也不引入第二张预览配置表。
function EXUI:RefreshCompositeGroupFromDB(host)
    if type(host) ~= "table" or type(host._exCompositeDb) ~= "table" then return false end
    BindCompositeGroup(host, host._exCompositeDb, host._exCompositeOnUpdate, host._exCompositeOpts)
    return true
end

local function AttachCompositeRelease(host)
    local factory = _G.ExwindFactory
    -- FramePool 在每次 Release 后都会清空 frame._exPoolRelease；因此组合宿主
    -- 每次 Acquire/重绑都必须重新登记本轮清理，不能用永久 attached 标记跳过。
    if not factory or not factory.AttachPoolRelease then return end
    factory:AttachPoolRelease(host, function(frame)
        if frame._exCancelItemIdentityLoad then frame:_exCancelItemIdentityLoad() end
        for _, popup in ipairs(frame._exCompositePopups or {}) do popup:Hide() end
        -- modulecommonsettings 的字段由模块动态声明；宿主归池时必须先归还
        -- 本轮借用的标准子控件，不能把上一模块的字段树带进下一模块。
        if frame._exClearModuleCommonEntries then
            frame:_exClearModuleCommonEntries()
        end
        frame._exCompositeDb = nil
        frame._exCompositeOnUpdate = nil
        frame._exCompositeOpts = nil
        frame._moduleCommonDb = nil
        frame._soundGroupKey = nil
        frame._soundState = nil
        frame._itemDb = nil
        frame._itemOnChange = nil
        frame._itemOnDelete = nil
        frame._itemID = nil
        frame._itemIdentityID = nil
        frame._itemIdentityCompletedID = nil
        frame._previewCallbacks = nil
        frame._previewData = nil
    end)
end

local function CompositeEmitUpdate(host)
    if host._exCompositeOnUpdate then host._exCompositeOnUpdate(host._exCompositeDb) end
end

local COMPOSITE_HEADER_FILL = MC.header
local SETTINGS_CARD_HEADER_HEIGHT = 32
local SETTINGS_CARD_BODY_PADDING = 12

local function CreateHeaderIconSlot(parent, size)
    local slot = CreateFrame("Frame", nil, parent)
    slot:SetSize(size, size)
    slot:EnableMouse(false)
    EXUI:SetControlSurface(slot, 4, MC.blue, MC.blue)
    local icon = EXUI:CreateVisualTexture(slot, EXBASEFRAME)
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    slot._exHeaderIcon = icon
    return slot
end

local function SetHeaderIcon(slot, iconPath)
    local icon = slot and slot._exHeaderIcon
    if not icon then return end
    if (type(iconPath) == "string" and iconPath ~= "") or type(iconPath) == "number" then
        icon:SetTexture(iconPath)
        icon:Show()
    else
        icon:SetTexture(nil)
        icon:Hide()
    end
end

-- 真正供 Grid:MountCards 使用的共享卡片。标题、图标占位、折叠状态和高度
-- 都由这一层拥有；Card body 内的 composite 只负责渲染无外壳内容。
function EXUI:CreateSettingsCard(parent, options)
    options = type(options) == "table" and options or {}
    local card, isNew = AcquireCompositeGroup("CompositeSettingsCard", parent)

    if isNew then
        local initialWidth = parent and parent.GetWidth and tonumber(parent:GetWidth()) or nil
        card:SetSize(math.max(64, initialWidth or 320), SETTINGS_CARD_HEADER_HEIGHT)
        EXUI:SetControlSurface(card, 10, MC.raised, MC.cardBorder)

        local header = CreateFrame("Frame", nil, card)
        header:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
        header:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)
        header:SetHeight(SETTINGS_CARD_HEADER_HEIGHT - 1)
        header:EnableMouse(true)
        if header.SetMouseMotionEnabled then header:SetMouseMotionEnabled(true) end
        if header.SetMouseClickEnabled then header:SetMouseClickEnabled(true) end
        EXUI:SetControlSurface(header, 10, COMPOSITE_HEADER_FILL, COMPOSITE_HEADER_FILL)

        local squareBottom = EXUI:CreateVisualTexture(header, EXBASEFRAME)
        squareBottom:SetPoint("BOTTOMLEFT", 0, 0)
        squareBottom:SetPoint("BOTTOMRIGHT", 0, 0)
        squareBottom:SetHeight(10)
        squareBottom:SetColorTexture(unpack(COMPOSITE_HEADER_FILL))

        local divider = EXUI:CreateVisualTexture(header, EXBORDERFRAME)
        divider:SetPoint("BOTTOMLEFT", 0, 0)
        divider:SetPoint("BOTTOMRIGHT", 0, 0)
        divider:SetHeight(1)
        divider:SetColorTexture(unpack(MC.headerDivider))

        local iconSlot = CreateHeaderIconSlot(header, 18)
        iconSlot:SetPoint("LEFT", 12, 0)

        local title = EXUI:CreateVisualFontString(header, EXFONTFRAME, "GameFontNormalHuge")
        title:SetPoint("LEFT", iconSlot, "RIGHT", 8, 0)
        title:SetPoint("RIGHT", header, "RIGHT", -36, 0)
        title:SetJustifyH("LEFT")
        MODERN.ApplyTextRole(title, "cardTitle")

        local toggle = CreateFrame("Button", nil, header)
        toggle:SetSize(24, 22)
        toggle:SetPoint("RIGHT", -6, 0)
        toggle:RegisterForClicks("LeftButtonUp")
        local glyph = EXUI:CreateVisualFontString(toggle, EXFONTFRAME, "GameFontHighlight")
        glyph:SetPoint("CENTER", 0, 1)
        MODERN.ApplyTextRole(glyph, "title", MC.muted)
        toggle._exGlyph = glyph
        local function PaintHeader()
            local listHeader = card._exSettingsListGroupMember or card._exSettingsListExternalHeader
            if listHeader then
                EXUI:ClearControlSurface(header)
                squareBottom:Hide()
                divider:Hide()
                title:SetTextColor(unpack(listHeader.titleColor))
                glyph:SetTextColor(unpack(listHeader.glyphColor))
                return
            end
            local hovered = header._exModernHover == true
            local fill = hovered and MC.headerHover or MC.header
            EXUI:SetControlSurface(header, 10, fill, fill)
            squareBottom:SetColorTexture(unpack(fill))
            title:SetTextColor(unpack(hovered and MC.white or MC.text))
            glyph:SetTextColor(unpack(hovered and MC.text or MC.muted))
        end
        card._exSettingsCardPaintHeader = PaintHeader
        header:SetScript("OnEnter", function(self)
            self._exModernHover = true
            PaintHeader()
        end)
        header:SetScript("OnLeave", function(self)
            self._exModernHover = nil
            PaintHeader()
        end)
        toggle:SetScript("OnEnter", function(self)
            header._exModernHover = true
            PaintHeader()
        end)
        toggle:SetScript("OnLeave", function(self)
            header._exModernHover = nil
            PaintHeader()
        end)
        local function ToggleCollapsed()
            if not card._exSettingsCardCollapsible then return end
            card:SetCollapsed(not card._exSettingsCardCollapsed)
        end
        header:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then ToggleCollapsed() end
        end)
        toggle:SetScript("OnClick", ToggleCollapsed)

        local body = CreateFrame("Frame", nil, card)
        body:SetPoint("TOPLEFT", card, "TOPLEFT", SETTINGS_CARD_BODY_PADDING,
            -(SETTINGS_CARD_HEADER_HEIGHT + SETTINGS_CARD_BODY_PADDING))
        body:SetPoint("TOPRIGHT", card, "TOPRIGHT", -SETTINGS_CARD_BODY_PADDING,
            -(SETTINGS_CARD_HEADER_HEIGHT + SETTINGS_CARD_BODY_PADDING))
        body:SetHeight(1)

        card._exSettingsCardHeader = header
        card._exSettingsCardIcon = iconSlot
        card._exSettingsCardTitle = title
        card._exSettingsCardToggle = toggle
        card._exSettingsCardDivider = divider
        card._exSettingsCardSquareBottom = squareBottom
        card._exSettingsCardBody = body

        function card:GetBody()
            return self._exSettingsCardBody
        end

        function card:SetLayoutInvalidationHandler(handler)
            if handler ~= nil and type(handler) ~= "function" then
                error("SettingsCard layout invalidation handler must be a function or nil", 2)
            end
            self._exSettingsCardInvalidation = handler
        end

        function card:SetContentHeight(height)
            height = math.max(0, tonumber(height) or 0)
            local minimum = math.max(0, tonumber(self._exSettingsCardMinBodyHeight) or 0)
            local maximum = tonumber(self._exSettingsCardMaxBodyHeight)
            if maximum then height = math.min(height, math.max(minimum, maximum)) end
            height = math.max(minimum, height)
            self._exSettingsCardContentHeight = height
            self._exSettingsCardBody:SetHeight(math.max(1, height))
            self:SetHeight(self:GetPreferredHeight())
        end

        function card:GetPreferredHeight()
            if self._exSettingsListCardMode == "flat" then
                return math.max(1, tonumber(self._exSettingsCardContentHeight) or 0)
            elseif self._exSettingsListCardMode == "external" then
                local headerHeight = self._exSettingsListExternalHeader
                    and self._exSettingsListExternalHeader.height or SETTINGS_CARD_HEADER_HEIGHT
                local footerPadding = self._exSettingsListExternalHeader
                    and self._exSettingsListExternalHeader.footerPadding or 0
                if self._exSettingsCardCollapsed then return headerHeight end
                return headerHeight
                    + math.max(1, tonumber(self._exSettingsCardContentHeight) or 0) + footerPadding
            elseif self._exSettingsListCardMode == "group" then
                local headerHeight = self._exSettingsListGroupMember
                    and self._exSettingsListGroupMember.headerHeight or SETTINGS_CARD_HEADER_HEIGHT
                if self._exSettingsCardCollapsed then return headerHeight end
                return headerHeight + math.max(1, tonumber(self._exSettingsCardContentHeight) or 0) + 12
            elseif self._exSettingsListCardMode == "header" then
                if self._exSettingsCardCollapsed then return SETTINGS_CARD_HEADER_HEIGHT end
                return SETTINGS_CARD_HEADER_HEIGHT
                    + math.max(1, tonumber(self._exSettingsCardContentHeight) or 0)
            end
            if self._exSettingsCardCollapsed then return SETTINGS_CARD_HEADER_HEIGHT end
            return SETTINGS_CARD_HEADER_HEIGHT + SETTINGS_CARD_BODY_PADDING
                + (tonumber(self._exSettingsCardContentHeight) or 0) + SETTINGS_CARD_BODY_PADDING
        end

        function card:SetCollapsed(collapsed, silent)
            collapsed = collapsed == true and self._exSettingsCardCollapsible == true
            local changed = self._exSettingsCardCollapsed ~= collapsed
            self._exSettingsCardCollapsed = collapsed
            self._exSettingsCardBody:SetShown(not collapsed)
            self._exSettingsCardDivider:SetShown(not collapsed
                and self._exSettingsListExternalHeader == nil
                and self._exSettingsListGroupMember == nil)
            self._exSettingsCardSquareBottom:SetShown(not collapsed
                and self._exSettingsListExternalHeader == nil
                and self._exSettingsListGroupMember == nil)
            self._exSettingsCardToggle._exGlyph:SetText(collapsed and "v" or "^")
            self:SetHeight(self:GetPreferredHeight())
            if changed and silent ~= true and self._exSettingsCardInvalidation then
                self._exSettingsCardInvalidation(self)
            end
            return changed
        end

        function card:Release()
            self._exSettingsCardInvalidation = nil
            self._exSettingsCardBody:Hide()
            local factory = _G.ExwindFactory
            if factory and factory.ReleaseCompositeHost then
                return factory:ReleaseCompositeHost(self)
            end
            self:Hide()
            self:ClearAllPoints()
            self:SetParent(nil)
            return true
        end
    end

    card._exSettingsCardId = options.id
    card._exSettingsCardCollapsible = options.collapsible == true
    card._exSettingsCardMinBodyHeight = math.max(0, tonumber(options.minBodyHeight) or 0)
    local maximum = tonumber(options.maxBodyHeight)
    card._exSettingsCardMaxBodyHeight = maximum and math.max(0, maximum) or nil
    card._exSettingsCardOwnsScroll = options.ownsScroll == true
    card._exSettingsCardContentHeight = card._exSettingsCardMinBodyHeight
    card._exSettingsCardInvalidation = nil
    MODERN.ApplyTextRole(card._exSettingsCardTitle, "cardTitle")
    card._exSettingsCardTitle:SetJustifyH("LEFT")
    card._exSettingsCardTitle:SetJustifyV("MIDDLE")
    card._exSettingsCardTitle:SetWordWrap(false)
    card._exSettingsCardTitle:SetText(tostring(options.title or ""))
    SetHeaderIcon(card._exSettingsCardIcon, options.headerIcon or options.icon)
    card._exSettingsCardToggle:SetShown(card._exSettingsCardCollapsible)
    card._exSettingsCardBody:Show()
    card._exSettingsCardBody:SetHeight(math.max(1, card._exSettingsCardContentHeight))
    -- 有高度上限（或内容自己持有滚动区）时，卡片必须成为真正的裁切边界；
    -- 否则超高子控件仍会绘制并命中到下一张 Grid 卡片上。
    if card._exSettingsCardBody.SetClipsChildren then
        card._exSettingsCardBody:SetClipsChildren(
            card._exSettingsCardMaxBodyHeight ~= nil or card._exSettingsCardOwnsScroll
        )
    end
    EXUI:SetControlSurface(card, 10, MC.raised, MC.cardBorder)
    card._exSettingsCardHeader._exModernHover = nil
    card._exSettingsCardPaintHeader()
    card:SetCollapsed(options.collapsed == true, true)
    return card
end

AttachModernMenuCheckboxMark = function(frame, enabled, selected)
    AttachModernMenuSelectionMark(frame, enabled, selected)
end

-- =========================================================
-- Settings list presentation
--
-- These hosts own geometry and decoration only. They never receive a config,
-- binding, getter, setter or notification callback. Grid keeps ownership of
-- the original controls and only anchors them beside these visual siblings.
-- =========================================================
local SETTINGS_LIST_ROW_PADDING_X = 20
local SETTINGS_LIST_ROW_PADDING_Y = 8
local SETTINGS_LIST_COLUMN_GAP = 20
local SETTINGS_LIST_MIN_TEXT_WIDTH = 160
local SETTINGS_LIST_STANDARD_ROW_HEIGHT = 50
local SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT = 28
local SETTINGS_LIST_DESCRIPTION_MIN_HEIGHT = 64
local SETTINGS_LIST_DESCRIPTION_GAP = 6
local SETTINGS_LIST_EXTERNAL_HEADER_HEIGHT = 56
local SETTINGS_LIST_SECTION_TOP = 8
local SETTINGS_LIST_SECTION_TITLE_TO_CARD_GAP = 8
local SETTINGS_LIST_SECTION_GROUP_GAP = 16
local SETTINGS_LIST_FIELD_ROW_BREAKPOINT = 440
local SETTINGS_LIST_COMPACT_VOICE_BREAKPOINT = 510
local SETTINGS_LIST_COMPACT_VOICE_SOURCE_BREAKPOINT = 360
local SETTINGS_LIST_NARROW_CONTROL_INDENT = 28
local SETTINGS_LIST_EXBOSS_SKILL_PROFILE = "exbossSkill"
local SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X = 18
local SETTINGS_LIST_EXBOSS_HEADER_HEIGHT = 53
local SETTINGS_LIST_EXBOSS_FOOTER_PADDING = 16
local SETTINGS_LIST_EXBOSS_SIMPLE_PADDING_Y = 9
local SETTINGS_LIST_EXBOSS_SIMPLE_ROW_HEIGHT = 46
local SETTINGS_LIST_EXBOSS_FIELD_PADDING_Y = 7
local SETTINGS_LIST_EXBOSS_FIELD_ROW_HEIGHT = 47
local SETTINGS_LIST_EXBOSS_FIELD_COLUMN_GAP = 14
local SETTINGS_LIST_EXBOSS_VOICE_PADDING_Y = 10
local SETTINGS_LIST_EXBOSS_VOICE_ROW_HEIGHT = 48
local SETTINGS_LIST_EXBOSS_VOICE_COLUMN_GAP = 10
local SETTINGS_LIST_EXBOSS_VOICE_CONTROL_GAP = 6
local SETTINGS_LIST_EXBOSS_PILL_GAP = 7
local SETTINGS_LIST_EXBOSS_PILL_STACK_BREAKPOINT = 365
-- The screenshots define structure and rhythm, not a replacement palette.
-- Settings lists stay on the project's existing shared visual theme.
local SETTINGS_LIST_CARD_FILL = MC.raised
local SETTINGS_LIST_CARD_BORDER = MC.cardBorder
local SETTINGS_LIST_TITLE = MC.text
local SETTINGS_LIST_DESCRIPTION = MC.muted

local function ResolveSettingsRowColumns(innerWidth, explicitWidth, controlKind, inputWidthPercent)
    local legacyDefault = math.min(260, innerWidth * 0.42)
    -- Ordinary right-side controls use one shared visual width. This is based
    -- on the original row-column budget, not on another settings-page scale.
    local ordinaryDefault = legacyDefault * 0.75
    local requested = tonumber(explicitWidth)
    if not requested or requested <= 0 then requested = nil end
    if not requested and (controlKind == "ordinary" or controlKind == "input") then
        local percent = tonumber(inputWidthPercent)
        percent = percent and percent > 0 and percent or 100
        requested = ordinaryDefault * percent / 100
    end
    requested = requested or legacyDefault
    local maximum = math.max(1, innerWidth - SETTINGS_LIST_COLUMN_GAP - SETTINGS_LIST_MIN_TEXT_WIDTH)
    local controlWidth = math.max(1, math.min(requested, maximum))
    return controlWidth, math.max(1, innerWidth - SETTINGS_LIST_COLUMN_GAP - controlWidth)
end

local settingsListMeasureHost = CreateFrame("Frame", nil, UIParent)
settingsListMeasureHost:SetSize(1, 1)
settingsListMeasureHost:Hide()
settingsListMeasureHost.title = EXUI:CreateVisualFontString(settingsListMeasureHost, EXFONTFRAME, "GameFontHighlight")
settingsListMeasureHost.title:SetWordWrap(true)
settingsListMeasureHost.description = EXUI:CreateVisualFontString(settingsListMeasureHost, EXFONTFRAME, "GameFontHighlightSmall")
settingsListMeasureHost.description:SetWordWrap(true)

local function MeasureSettingsListText(text, width, role)
    text = tostring(text or "")
    if text == "" then return 0 end
    local region = role == "description" and settingsListMeasureHost.description or settingsListMeasureHost.title
    if role == "description" then
        MODERN.Font(region, 13, MC.muted, "", "GameFontHighlightSmall")
    else
        MODERN.ApplyTextRole(region, role == "cardTitle" and "cardTitle" or "title")
    end
    region:SetWidth(math.max(1, tonumber(width) or 1))
    region:SetText(text)
    return math.max(1, math.ceil(region:GetStringHeight() or 0))
end

local function ReleaseSettingsListDecoration(frame)
    local factory = _G.ExwindFactory
    if factory and factory.ReleaseCompositeHost then
        return factory:ReleaseCompositeHost(frame)
    end
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(nil)
    return true
end

local function SettingsTextHeight(region, width)
    if not region or not region:IsShown() then return 0 end
    region:SetWidth(math.max(1, width))
    return math.max(1, math.ceil(region:GetStringHeight() or 0))
end

-- Reuse the exact self-drawn FillR4 surface path used by the stable modern
-- input and dropdown controls. Settings-list dividers are not native lines.
local settingsDividerFrames = setmetatable({}, { __mode = "k" })
local settingsDividerScaleWatcher
local function ApplySettingsDividerPhysicalHeight(divider)
    local effectiveScale = divider.GetEffectiveScale and divider:GetEffectiveScale() or 1
    effectiveScale = type(effectiveScale) == "number" and effectiveScale > 0 and effectiveScale or 1
    local pixelUtil = _G.PixelUtil
    local factor = pixelUtil and pixelUtil.GetPixelToUIUnitFactor
        and pixelUtil.GetPixelToUIUnitFactor() or 1
    factor = type(factor) == "number" and factor > 0 and factor or 1
    local pixel = factor / effectiveScale
    divider:SetHeight(type(pixel) == "number" and pixel > 0 and pixel or (1 / effectiveScale))
end
local function CreateSettingsDivider(parent)
    local divider = CreateFrame("Frame", nil, parent)
    divider:EnableMouse(false)
    settingsDividerFrames[divider] = true
    if not settingsDividerScaleWatcher then
        settingsDividerScaleWatcher = CreateFrame("Frame")
        settingsDividerScaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
        settingsDividerScaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
        settingsDividerScaleWatcher:SetScript("OnEvent", function()
            for frame in pairs(settingsDividerFrames) do ApplySettingsDividerPhysicalHeight(frame) end
        end)
    end
    ApplySettingsDividerPhysicalHeight(divider)
    EXUI:SetControlSurface(divider, 4, MC.headerDivider, MC.headerDivider)
    local skin = divider._exModernSurfaces and divider._exModernSurfaces[4]
    for _, piece in ipairs(skin and skin.pieces or {}) do
        piece.texture:SetAlpha(piece.layer == 1 and 1 or 0)
    end
    return divider
end

function EXUI:CreateSettingsSeparator(parent, width)
    local divider = CreateSettingsDivider(parent)
    divider:SetWidth(width or 200)
    return divider
end

-- Nine image slices preserve source-image UVs while each corner uses only one
-- circular mask. Mask UVs stay untouched; the corner image covers one quadrant.
function EXUI:CreateRoundedImage(parent, radius, matchSurface)
    local image = CreateFrame("Frame", nil, parent)
    image:EnableMouse(false)
    image._radius = math.max(0, tonumber(radius) or 9)
    image._uv = { 0, 1, 0, 1 }
    image._pieces = {}
    for row = 1, 3 do
        for col = 1, 3 do
            local texture = self:CreateVisualTexture(image, EXBASEFRAME)
            if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
            if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
            local piece = { texture = texture, row = row, col = col }
            if row ~= 2 and col ~= 2 then
                local mask = image:CreateMaskTexture(nil, "ARTWORK")
                mask:SetTexture(matchSurface and (MODERN_MEDIA .. "FillR10ImageMask.tga")
                    or "Interface\\CharacterFrame\\TempPortraitAlphaMask",
                    "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
                -- Keep the circular edge on the same fractional coordinates as
                -- its image quadrant so their sampled edges stay aligned.
                if mask.SetSnapToPixelGrid then mask:SetSnapToPixelGrid(false) end
                if mask.SetTexelSnappingBias then mask:SetTexelSnappingBias(0) end
                texture:AddMaskTexture(mask)
                piece.mask = mask
            end
            image._pieces[#image._pieces + 1] = piece
        end
    end
    local function Layout()
        local width, height = image:GetWidth(), image:GetHeight()
        if width <= 0 or height <= 0 then return end
        local r = math.min(image._radius, width / 2, height / 2)
        local x, y = { 0, r, width - r, width }, { 0, r, height - r, height }
        local uv = image._uv
        for _, piece in ipairs(image._pieces) do
            local col, row, texture = piece.col, piece.row, piece.texture
            local w, h = x[col + 1] - x[col], y[row + 1] - y[row]
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", image, "TOPLEFT", x[col], -y[row])
            texture:SetSize(math.max(.001, w), math.max(.001, h))
            texture:SetTexCoord(uv[1] + (uv[2] - uv[1]) * x[col] / width,
                uv[1] + (uv[2] - uv[1]) * x[col + 1] / width,
                uv[3] + (uv[4] - uv[3]) * y[row] / height,
                uv[3] + (uv[4] - uv[3]) * y[row + 1] / height)
            texture:SetShown(w > 0 and h > 0)
            if piece.mask then
                local point = (row == 1 and "TOP" or "BOTTOM") .. (col == 1 and "LEFT" or "RIGHT")
                piece.mask:ClearAllPoints()
                -- The surface-matched asset retains FillR10's 12px padding
                -- around its 20px source radius. Preserve that sampling scale.
                local padding = matchSurface and r * 12 / 20 or 0
                local size = 2 * (r + padding)
                piece.mask:SetPoint(point, image, point,
                    col == 1 and -padding or padding, row == 1 and padding or -padding)
                piece.mask:SetSize(math.max(.001, size), math.max(.001, size))
            end
        end
    end
    function image:SetTexture(texture)
        for _, piece in ipairs(self._pieces) do
            piece.texture:SetTexture(texture, "CLAMP", "CLAMP", "LINEAR")
        end
    end
    function image:SetTexCoord(left, right, top, bottom)
        self._uv = { left, right, top, bottom }
        Layout()
    end
    function image:SetDesaturated(desaturated)
        for _, piece in ipairs(self._pieces) do piece.texture:SetDesaturated(desaturated) end
    end
    function image:SetVertexColor(r, g, b, a)
        for _, piece in ipairs(self._pieces) do piece.texture:SetVertexColor(r, g, b, a or 1) end
    end
    function image:SetCornerRadius(nextRadius)
        self._radius = math.max(0, tonumber(nextRadius) or 0)
        Layout()
    end
    image:SetScript("OnSizeChanged", Layout)
    image:SetScript("OnShow", Layout)
    return image
end

local function ResolveSettingsListRoleRegion(widget)
    if not widget then return nil end
    if widget.text then return widget.text end
    if widget.labelText then return widget.labelText end
    if widget.IsObjectType and widget:IsObjectType("FontString") then return widget end
    return nil
end

function EXUI:CreateSettingsSection(parent, options)
    options = type(options) == "table" and options or {}
    if options.presentationProfile ~= nil
        and options.presentationProfile ~= SETTINGS_LIST_EXBOSS_SKILL_PROFILE then
        error("unknown settings section presentation profile: " .. tostring(options.presentationProfile), 2)
    end
    local section, isNew = AcquireCompositeGroup("CompositeSettingsListSection", parent)
    if isNew then
        section:EnableMouse(false)
        local title = EXUI:CreateVisualFontString(section, EXFONTFRAME, "GameFontHighlight")
        title:SetJustifyH("LEFT")
        title:SetJustifyV("TOP")
        title:SetWordWrap(true)
        local description = EXUI:CreateVisualFontString(section, EXFONTFRAME, "GameFontHighlightSmall")
        description:SetJustifyH("LEFT")
        description:SetJustifyV("TOP")
        description:SetWordWrap(true)
        local divider = CreateSettingsDivider(section)
        section._exSettingsSectionTitle = title
        section._exSettingsSectionDescription = description
        section._exSettingsSectionDivider = divider
        section.Release = ReleaseSettingsListDecoration
    end
    section:EnableMouse(false)
    section._exSettingsSectionKind = options.kind == "page" and "page"
        or (options.kind == "subsection" and "subsection"
        or (options.kind == "information" and "information" or "section"))
    section._exSettingsSectionPresentationProfile = options.presentationProfile
    section._exSettingsSectionTitle:SetText(tostring(options.title or ""))
    section._exSettingsSectionTitle:SetShown(options.title ~= nil and tostring(options.title) ~= "")
    section._exSettingsSectionDescription:SetText(tostring(options.description or ""))
    section._exSettingsSectionDescription:SetShown(options.description ~= nil and tostring(options.description) ~= "")
    section._exSettingsSectionDescriptionWidgets = type(options.descriptionWidgets) == "table"
        and options.descriptionWidgets or {}
    -- Category headings sit outside the continuous card. The card's own border
    -- supplies the visual boundary; an extra full-width rule is not part of the
    -- reference hierarchy.
    section._exSettingsSectionDivider:Hide()
    if section._exSettingsSectionKind == "page" then
        MODERN.ApplyTextRole(section._exSettingsSectionTitle, "pageTitle", SETTINGS_LIST_TITLE)
    elseif section._exSettingsSectionKind == "section" then
        MODERN.ApplyTextRole(section._exSettingsSectionTitle, "cardTitle", SETTINGS_LIST_TITLE)
    else
        MODERN.ApplyTextRole(section._exSettingsSectionTitle, "title", SETTINGS_LIST_TITLE)
    end
    MODERN.Font(section._exSettingsSectionDescription, 13, SETTINGS_LIST_DESCRIPTION,
        "", "GameFontHighlightSmall")
    return section
end

function EXUI:UpdateSettingsSectionLayout(section, width)
    if not section then return 0 end
    width = math.max(1, tonumber(width) or 1)
    section:SetWidth(width)
    local title = section._exSettingsSectionTitle
    local description = section._exSettingsSectionDescription
    local divider = section._exSettingsSectionDivider
    local page = section._exSettingsSectionKind == "page"
    local information = section._exSettingsSectionKind == "information"
    local cardSection = section._exSettingsSectionKind == "section"
    local top = page and 0 or SETTINGS_LIST_SECTION_TOP
    local insetX = information and (section._exSettingsSectionPresentationProfile
        == SETTINGS_LIST_EXBOSS_SKILL_PROFILE and SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
        or SETTINGS_LIST_ROW_PADDING_X) or 0
    local contentTop = information and SETTINGS_LIST_ROW_PADDING_Y or 0
    local textWidth = math.max(1, width - insetX * 2)
    title:ClearAllPoints()
    local height = 0
    if title:IsShown() then
        local titleTop = information and contentTop or top
        title:SetPoint("TOPLEFT", section, "TOPLEFT", insetX, -titleTop)
        title:SetPoint("TOPRIGHT", section, "TOPRIGHT", -insetX, -titleTop)
        local measured = SettingsTextHeight(title, textWidth)
        if title.GetText then
            measured = math.max(measured, MeasureSettingsListText(title:GetText(), textWidth,
                cardSection and "cardTitle" or "title"))
        end
        height = titleTop + measured
    end
    if description:IsShown() then
        local descriptionTop = height > 0 and (height + SETTINGS_LIST_DESCRIPTION_GAP) or contentTop
        description:ClearAllPoints()
        description:SetPoint("TOPLEFT", section, "TOPLEFT", insetX, -descriptionTop)
        description:SetPoint("TOPRIGHT", section, "TOPRIGHT", -insetX, -descriptionTop)
        height = descriptionTop + SettingsTextHeight(description, textWidth)
    end
    for _, widget in ipairs(section._exSettingsSectionDescriptionWidgets or {}) do
        if widget and widget.IsShown and widget:IsShown() then
            local region = ResolveSettingsListRoleRegion(widget)
            if region then
                local widgetTop = height > 0 and (height + SETTINGS_LIST_DESCRIPTION_GAP) or contentTop
                widget:SetWidth(textWidth)
                local text = region.GetText and tostring(region:GetText() or "") or nil
                local widgetHeight = text == "" and 1 or SettingsTextHeight(region, textWidth)
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", section, "TOPLEFT", insetX, -widgetTop)
                widget:SetSize(textWidth, widgetHeight)
                if text ~= "" then height = widgetTop + widgetHeight end
            end
        end
    end
    if height > 0 then
        height = height + (information and SETTINGS_LIST_ROW_PADDING_Y
            or (cardSection and SETTINGS_LIST_SECTION_TITLE_TO_CARD_GAP or 18))
    end
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", section, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", 0, 0)
    ApplySettingsDividerPhysicalHeight(divider)
    section:SetSize(width, math.max(1, height))
    return height
end

function EXUI:GetSettingsSectionGroupGap()
    return SETTINGS_LIST_SECTION_GROUP_GAP
end

function EXUI:CreateSettingsRow(parent, options)
    options = type(options) == "table" and options or {}
    local row, isNew = AcquireCompositeGroup("CompositeSettingsListRow", parent)
    if isNew then
        row:EnableMouse(false)
        local title = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlight")
        title:SetJustifyH("LEFT")
        title:SetJustifyV("TOP")
        title:SetWordWrap(true)
        local description = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlightSmall")
        description:SetJustifyH("LEFT")
        description:SetJustifyV("TOP")
        description:SetWordWrap(true)
        local divider = CreateSettingsDivider(row)
        row._exSettingsRowTitle = title
        row._exSettingsRowDescription = description
        row._exSettingsRowDivider = divider
        row.Release = ReleaseSettingsListDecoration
    end
    row:EnableMouse(false)
    if parent and row.SetFrameLevel and parent.GetFrameLevel then
        row:SetFrameLevel(parent:GetFrameLevel())
    end
    row._exSettingsRowFullWidth = options.fullWidth == true
    local controlWidth = tonumber(options.controlWidth)
    row._exSettingsRowControlWidth = controlWidth and controlWidth > 0 and controlWidth or nil
    row._exSettingsRowControlKind = options.controlKind
    row._exSettingsRowInputWidthPercent = tonumber(options.inputWidthPercent)
    row._exSettingsRowContentWidth = options.contentWidth
    row._exSettingsRowSingleLineControls = options.singleLineControls == true
    row._exSettingsRowHTMLControlsLayout = options.htmlControlsLayout
    if options.presentationProfile ~= nil
        and options.presentationProfile ~= SETTINGS_LIST_EXBOSS_SKILL_PROFILE then
        error("unknown settings row presentation profile: " .. tostring(options.presentationProfile), 2)
    end
    row._exSettingsRowPresentationProfile = options.presentationProfile
    -- Settings-list modules declare content only.  A legacy Grid h/minHeight
    -- must not make otherwise identical ordinary rows use different heights.
    row._exSettingsRowMinHeight = options.presentationProfile == SETTINGS_LIST_EXBOSS_SKILL_PROFILE
        and SETTINGS_LIST_EXBOSS_SIMPLE_ROW_HEIGHT or SETTINGS_LIST_STANDARD_ROW_HEIGHT
    row._exSettingsRowIsLast = options.isLast == true
    row._exSettingsRowTitle:SetText(tostring(options.label or ""))
    row._exSettingsRowTitle:SetShown(options.label ~= nil and tostring(options.label) ~= "")
    row._exSettingsRowDescription:SetText(tostring(options.description or ""))
    row._exSettingsRowDescription:SetShown(options.description ~= nil and tostring(options.description) ~= "")
    MODERN.ApplyTextRole(row._exSettingsRowTitle, "title", SETTINGS_LIST_TITLE)
    MODERN.Font(row._exSettingsRowDescription, 13, SETTINGS_LIST_DESCRIPTION,
        "", "GameFontHighlightSmall")
    row._exSettingsRowDivider:SetShown(not row._exSettingsRowIsLast)
    EXUI:ClearControlSurface(row)
    return row
end

function EXUI:UpdateSettingsRowLayout(row, width, controlHeight, descriptionWidget)
    if not row then return 0, 0, 0, 0 end
    width = math.max(1, tonumber(width) or 1)
    controlHeight = math.max(1, tonumber(controlHeight) or MODERN.metrics.height)
    local exbossProfile = row._exSettingsRowPresentationProfile == SETTINGS_LIST_EXBOSS_SKILL_PROFILE
    local rowPaddingX = exbossProfile and SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
        or SETTINGS_LIST_ROW_PADDING_X
    local innerWidth = math.max(1, width - rowPaddingX * 2)
    local title = row._exSettingsRowTitle
    local description = descriptionWidget
        and (descriptionWidget.text or descriptionWidget.labelText)
        or row._exSettingsRowDescription
    local descriptionShown = descriptionWidget and descriptionWidget:IsShown()
        or (not descriptionWidget and description:IsShown())
    local rowPaddingY = exbossProfile
        and SETTINGS_LIST_EXBOSS_SIMPLE_PADDING_Y or SETTINGS_LIST_ROW_PADDING_Y
    local textWidth, textHeight, controlX, controlY, controlWidth, height
    if row._exSettingsRowFullWidth then
        textWidth = innerWidth
        local titleHeight = SettingsTextHeight(title, textWidth)
        textHeight = titleHeight
        if descriptionShown then
            if descriptionWidget then descriptionWidget:SetWidth(textWidth) end
            textHeight = textHeight + (textHeight > 0 and SETTINGS_LIST_DESCRIPTION_GAP or 0)
                + SettingsTextHeight(description, textWidth)
        end
        controlX = 0
        controlY = textHeight > 0 and (rowPaddingY + textHeight + 10) or 0
        controlWidth = width
        local bottomPadding = textHeight > 0 and rowPaddingY or 0
        height = math.max(textHeight > 0 and row._exSettingsRowMinHeight or 0,
            controlY + controlHeight + bottomPadding)
    else
        controlWidth, textWidth = ResolveSettingsRowColumns(innerWidth,
            row._exSettingsRowControlWidth, row._exSettingsRowControlKind,
            row._exSettingsRowInputWidthPercent)
        local titleHeight = SettingsTextHeight(title, textWidth)
        textHeight = titleHeight
        if descriptionShown then
            if descriptionWidget then descriptionWidget:SetWidth(textWidth) end
            textHeight = textHeight + (textHeight > 0 and SETTINGS_LIST_DESCRIPTION_GAP or 0)
                + SettingsTextHeight(description, textWidth)
        end
        height = math.max(row._exSettingsRowMinHeight,
            rowPaddingY * 2 + math.max(textHeight, controlHeight))
        if descriptionShown then
            height = math.max(height, SETTINGS_LIST_DESCRIPTION_MIN_HEIGHT)
        end
        controlX = width - rowPaddingX - controlWidth
        controlY = math.floor((height - controlHeight) * 0.5 + 0.5)
    end
    local textTop = rowPaddingY
    if not row._exSettingsRowFullWidth and textHeight > 0 then
        textTop = math.floor((height - textHeight) * 0.5 + 0.5)
    end
    title:ClearAllPoints()
    if title:IsShown() then
        title:SetPoint("TOPLEFT", row, "TOPLEFT", rowPaddingX, -textTop)
        title:SetWidth(textWidth)
    end
    if descriptionShown then
        local descriptionHeight = SettingsTextHeight(description, textWidth)
        if descriptionWidget then
            descriptionWidget:ClearAllPoints()
            if title:IsShown() then
                descriptionWidget:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -SETTINGS_LIST_DESCRIPTION_GAP)
            else
                descriptionWidget:SetPoint("TOPLEFT", row, "TOPLEFT", rowPaddingX, -textTop)
            end
            descriptionWidget:SetSize(textWidth, descriptionHeight)
        else
            description:ClearAllPoints()
            if title:IsShown() then
                description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -SETTINGS_LIST_DESCRIPTION_GAP)
            else
                description:SetPoint("TOPLEFT", row, "TOPLEFT", rowPaddingX, -textTop)
            end
            description:SetWidth(textWidth)
        end
    end
    row:SetSize(width, height)
    local divider = row._exSettingsRowDivider
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", rowPaddingX, 0)
    divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -rowPaddingX, 0)
    divider:SetShown(not row._exSettingsRowIsLast)
    EXUI:ClearControlSurface(row)
    return height, controlX, controlY, controlWidth
end

local function SettingsControlTextWidth(region)
    if not region or not region.IsShown or not region:IsShown() then return 0 end
    local width = region.GetUnboundedStringWidth and region:GetUnboundedStringWidth()
        or (region.GetStringWidth and region:GetStringWidth())
        or 0
    return math.max(0, math.ceil(tonumber(width) or 0))
end

local function ResolveSettingsSingleLineSlot(metric)
    local widget = metric and metric.widget
    if metric.slotKind == "specQueue" and widget and widget._gridType == "GridInput" then
        local labelWidth = SettingsControlTextWidth(widget.label or widget.labelText)
        local bodyWidth = 56
        return labelWidth + 5 + bodyWidth, bodyWidth
    end
    if metric.slotKind == "specAlpha" and widget and widget._gridType == "GridSlider" then
        local titleWidth = SettingsControlTextWidth(widget.Title)
        local numberWidth = widget.numberInput and widget.numberInput:GetWidth() or 48
        return math.max(80, titleWidth + 12 + math.max(1, tonumber(numberWidth) or 48)), nil
    end
    error("unsupported settings single-line control slot: " .. tostring(metric and metric.slotKind), 2)
end

local function UpdateSettingsSingleLineControlsLayout(row, width, metrics)
    local gap = 8
    local innerWidth = math.max(1, width - SETTINGS_LIST_ROW_PADDING_X * 2)
    local title = row._exSettingsRowTitle
    local description = row._exSettingsRowDescription
    local hasText = title:IsShown() or description:IsShown()
    local textWidth = 0
    if hasText then
        textWidth = math.max(SettingsControlTextWidth(title), SettingsControlTextWidth(description)) + 12
    end
    local controlsX = SETTINGS_LIST_ROW_PADDING_X
    local controlsWidth = innerWidth
    if hasText then
        controlsX = controlsX + textWidth + SETTINGS_LIST_COLUMN_GAP
        controlsWidth = math.max(0, innerWidth - textWidth - SETTINGS_LIST_COLUMN_GAP)
    end

    local visibleIndexes, slotMinimums, bodyWidths = {}, {}, {}
    local minimumControlsWidth, controlsHeight = 0, 0
    for index, metric in ipairs(metrics) do
        if metric.visible ~= false then
            local slotMinimum, bodyWidth = ResolveSettingsSingleLineSlot(metric)
            visibleIndexes[#visibleIndexes + 1] = index
            slotMinimums[index], bodyWidths[index] = slotMinimum, bodyWidth
            minimumControlsWidth = minimumControlsWidth + slotMinimum
            controlsHeight = math.max(controlsHeight, math.max(1, tonumber(metric.height) or 28))
        end
    end
    minimumControlsWidth = minimumControlsWidth + math.max(0, #visibleIndexes - 1) * gap
    local requiredWidth = SETTINGS_LIST_ROW_PADDING_X * 2 + minimumControlsWidth
        + (hasText and (textWidth + SETTINGS_LIST_COLUMN_GAP) or 0)
    local fits = width + 0.5 >= requiredWidth
    local extraPerSlot = fits and #visibleIndexes > 0
        and math.max(0, controlsWidth - minimumControlsWidth) / #visibleIndexes or 0

    local textHeight = SettingsTextHeight(title, math.max(1, textWidth))
    if description:IsShown() then
        textHeight = textHeight + (textHeight > 0 and SETTINGS_LIST_DESCRIPTION_GAP or 0)
            + SettingsTextHeight(description, math.max(1, textWidth))
    end
    local height = math.max(row._exSettingsRowMinHeight,
        SETTINGS_LIST_ROW_PADDING_Y * 2 + math.max(textHeight, controlsHeight))
    if description:IsShown() then height = math.max(height, SETTINGS_LIST_DESCRIPTION_MIN_HEIGHT) end

    local rects, slotX = {}, controlsX
    for _, index in ipairs(visibleIndexes) do
        local metric = metrics[index]
        local slotWidth = slotMinimums[index] + extraPerSlot
        local bodyWidth = bodyWidths[index] or slotWidth
        local bodyX = slotX + slotWidth - bodyWidth
        local controlHeight = math.max(1, tonumber(metric.height) or 28)
        rects[index] = {
            slotX = slotX, slotWidth = slotWidth,
            x = bodyX,
            y = math.floor((height - controlHeight) * 0.5 + 0.5),
            width = bodyWidth, height = controlHeight,
        }
        slotX = slotX + slotWidth + gap
    end
    for index, metric in ipairs(metrics) do
        if metric.visible == false then
            rects[index] = {
                slotX = controlsX + controlsWidth, slotWidth = 1,
                x = controlsX + controlsWidth,
                y = math.floor(height * 0.5 + 0.5),
                width = 1, height = math.max(1, tonumber(metric.height) or 1),
            }
        end
    end

    if hasText then
        local textTop = math.floor((height - textHeight) * 0.5 + 0.5)
        title:ClearAllPoints()
        if title:IsShown() then
            title:SetPoint("TOPLEFT", row, "TOPLEFT", SETTINGS_LIST_ROW_PADDING_X, -textTop)
            title:SetWidth(textWidth)
        end
        description:ClearAllPoints()
        if description:IsShown() then
            if title:IsShown() then
                description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -SETTINGS_LIST_DESCRIPTION_GAP)
            else
                description:SetPoint("TOPLEFT", row, "TOPLEFT", SETTINGS_LIST_ROW_PADDING_X, -textTop)
            end
            description:SetWidth(textWidth)
        end
    end
    row:SetSize(width, height)
    local divider = row._exSettingsRowDivider
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", SETTINGS_LIST_ROW_PADDING_X, 0)
    divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -SETTINGS_LIST_ROW_PADDING_X, 0)
    divider:SetShown(not row._exSettingsRowIsLast)
    EXUI:ClearControlSurface(row)
    return height, rects, {
        fits = fits,
        requiredWidth = requiredWidth,
        availableWidth = width,
    }
end

local function ResolveSettingsControlLine(metrics, indexes, x, availableWidth, y, controlGap, flexWeights)
    local gap, fixedWidth, flexibleWeight = math.max(0, tonumber(controlGap) or 8), 0, 0
    local rightAlign = false
    for _, index in ipairs(indexes) do
        local metric = metrics[index]
        local requested = tonumber(metric.width)
        if requested and requested > 0 then
            fixedWidth = fixedWidth + requested
        else
            flexibleWeight = flexibleWeight + math.max(0.001,
                tonumber(type(flexWeights) == "table" and flexWeights[index]) or 1)
        end
        if metric.presentation == "pill" or metric.align == "right" then rightAlign = true end
    end
    local contentWidth = math.max(1, availableWidth - math.max(0, #indexes - 1) * gap)
    local flexibleAvailable = math.max(0, contentWidth - fixedWidth)
    local widths = {}
    for _, index in ipairs(indexes) do
        local metric = metrics[index]
        local controlWidth = tonumber(metric.width)
        if not controlWidth or controlWidth <= 0 then
            local weight = math.max(0.001,
                tonumber(type(flexWeights) == "table" and flexWeights[index]) or 1)
            controlWidth = flexibleWeight > 0 and math.max(80,
                flexibleAvailable * weight / flexibleWeight) or 0
        end
        controlWidth = math.max(1, controlWidth)
        if controlWidth > availableWidth + 0.5 then
            error("responsive settings control " .. tostring(index)
                .. " resolved width exceeds its available line width", 2)
        end
        widths[index] = controlWidth
    end
    local rawRects, lineWidths, lineHeights, lineIndexes = {}, {}, {}, {}
    local cursorX, cursorY, lineHeight, line = 0, 0, 0, 1
    for _, index in ipairs(indexes) do
        local metric = metrics[index]
        local controlHeight = math.max(1, tonumber(metric.height) or 28)
        local controlWidth = widths[index]
        if cursorX > 0 and cursorX + controlWidth > availableWidth + 0.5 then
            lineWidths[line] = math.max(0, cursorX - gap)
            lineHeights[line] = lineHeight
            cursorY = cursorY + lineHeight + gap
            cursorX, lineHeight, line = 0, 0, line + 1
        end
        rawRects[index] = { x = cursorX, y = cursorY, width = controlWidth, height = controlHeight }
        lineIndexes[index] = line
        cursorX = cursorX + controlWidth + gap
        lineHeight = math.max(lineHeight, controlHeight)
    end
    if #indexes > 0 then
        lineWidths[line] = math.max(0, cursorX - gap)
        lineHeights[line] = lineHeight
    end
    local rects = {}
    for _, index in ipairs(indexes) do
        local raw = rawRects[index]
        local physicalLine = lineIndexes[index]
        rects[index] = {
            x = x + (rightAlign
                and math.max(0, availableWidth - (lineWidths[physicalLine] or availableWidth)) or 0) + raw.x,
            y = y + raw.y
                + math.max(0, ((lineHeights[physicalLine] or raw.height) - raw.height) * 0.5),
            width = raw.width, height = raw.height,
        }
    end
    return rects, (#indexes > 0 and (cursorY + lineHeight) or 0)
end

local function FinishSettingsHTMLControlsLayout(row, width, metrics, rects, height)
    local paddingX = row._exSettingsRowPresentationProfile == SETTINGS_LIST_EXBOSS_SKILL_PROFILE
        and SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X or SETTINGS_LIST_ROW_PADDING_X
    for index, metric in ipairs(metrics) do
        if metric.visible == false then
            rects[index] = {
                x = width - paddingX,
                y = math.floor(height * 0.5 + 0.5),
                width = 1, height = math.max(1, tonumber(metric.height) or 1),
            }
        end
    end
    row:SetSize(width, height)
    local divider = row._exSettingsRowDivider
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", paddingX, 0)
    divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -paddingX, 0)
    divider:SetShown(not row._exSettingsRowIsLast)
    EXUI:ClearControlSurface(row)
    return height, rects
end

local function ResolveSettingsVoiceFlexWeights(metrics, indexes)
    local includesSource = false
    local flexibleContent = {}
    for _, index in ipairs(indexes) do
        if index == 2 then
            includesSource = true
        elseif index >= 3 and index < #metrics then
            local requested = tonumber(metrics[index].width)
            if not requested or requested <= 0 then flexibleContent[#flexibleContent + 1] = index end
        end
    end
    if not includesSource or #flexibleContent == 0 then return nil end
    local weights = { [2] = 1.08 }
    local candidateWeight = 1 / #flexibleContent
    for _, index in ipairs(flexibleContent) do weights[index] = candidateWeight end
    return weights
end

local function UpdateSettingsExbossPillChoicesLayout(row, width, metrics, containerWidth)
    local visible = {}
    for index, metric in ipairs(metrics) do
        if metric.visible ~= false then
            if metric.presentation ~= "pill" then return nil end
            visible[#visible + 1] = index
        end
    end
    if #visible ~= 3 then return nil end
    local paddingX = SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
    local paddingY = SETTINGS_LIST_EXBOSS_SIMPLE_PADDING_Y
    local gap = SETTINGS_LIST_EXBOSS_PILL_GAP
    local innerWidth = math.max(1, width - paddingX * 2)
    local stacked = containerWidth <= SETTINGS_LIST_EXBOSS_PILL_STACK_BREAKPOINT
    local controlWidth = stacked and innerWidth or math.max(1, (innerWidth - gap * 2) / 3)
    local rects, y, maxHeight = {}, paddingY, 0
    for position, index in ipairs(visible) do
        local controlHeight = math.max(1, tonumber(metrics[index].height) or 28)
        if stacked then
            rects[index] = { x = paddingX, y = y, width = controlWidth, height = controlHeight }
            y = y + controlHeight + (position < #visible and gap or 0)
        else
            rects[index] = {
                x = paddingX + (position - 1) * (controlWidth + gap),
                y = paddingY, width = controlWidth, height = controlHeight,
            }
        end
        maxHeight = math.max(maxHeight, controlHeight)
    end
    local contentHeight = stacked and (y - paddingY) or maxHeight
    local height = math.max(row._exSettingsRowMinHeight, paddingY * 2 + contentHeight)
    return FinishSettingsHTMLControlsLayout(row, width, metrics, rects, height)
end

local function UpdateSettingsHTMLWideControlsLayout(row, width, metrics, mode)
    local label = metrics[1]
    if not label or label.visible == false or label.role ~= "label" then
        error("responsive settings controls require declared control 1 to be the visible label", 2)
    end
    local controls = {}
    for index = 2, #metrics do
        if metrics[index].visible ~= false then controls[#controls + 1] = index end
    end
    local paddingX = SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
    local innerWidth = math.max(1, width - paddingX * 2)
    local columnGap = mode == "compactVoice"
        and SETTINGS_LIST_EXBOSS_VOICE_COLUMN_GAP or SETTINGS_LIST_EXBOSS_FIELD_COLUMN_GAP
    local labelRatio = mode == "compactVoice" and (0.66 / 2.66) or (0.83 / 2)
    local columnsWidth = math.max(1, innerWidth - columnGap)
    local labelWidth = math.max(1, columnsWidth * labelRatio)
    local controlsX = paddingX + labelWidth + columnGap
    local controlsWidth = math.max(1, columnsWidth - labelWidth)
    local paddingY = mode == "compactVoice"
        and SETTINGS_LIST_EXBOSS_VOICE_PADDING_Y or SETTINGS_LIST_EXBOSS_FIELD_PADDING_Y
    local controlGap = mode == "compactVoice" and SETTINGS_LIST_EXBOSS_VOICE_CONTROL_GAP or 8
    local flexWeights = mode == "compactVoice"
        and ResolveSettingsVoiceFlexWeights(metrics, controls) or nil
    local controlRects, controlsHeight = ResolveSettingsControlLine(
        metrics, controls, controlsX, controlsWidth, paddingY, controlGap, flexWeights)
    local labelHeight = math.max(1, tonumber(label.height) or 28)
    local contentHeight = math.max(labelHeight, controlsHeight)
    local minimum = mode == "compactVoice"
        and SETTINGS_LIST_EXBOSS_VOICE_ROW_HEIGHT or SETTINGS_LIST_EXBOSS_FIELD_ROW_HEIGHT
    local height = math.max(minimum, paddingY * 2 + contentHeight)
    local rects = controlRects
    rects[1] = {
        x = paddingX,
        y = math.floor((height - labelHeight) * 0.5 + 0.5),
        width = labelWidth, height = labelHeight,
    }
    local controlsOffset = math.max(0, math.floor((height - controlsHeight) * 0.5 + 0.5) - paddingY)
    if controlsOffset > 0 then
        for _, index in ipairs(controls) do controlRects[index].y = controlRects[index].y + controlsOffset end
    end
    return FinishSettingsHTMLControlsLayout(row, width, metrics, rects, height)
end

local function UpdateSettingsHTMLControlsLayout(row, width, metrics, mode, containerWidth)
    local label = metrics[1]
    if not label or label.visible == false or label.role ~= "label" then
        error("responsive settings controls require declared control 1 to be the visible label", 2)
    end
    local lines = { { 1 } }
    if mode == "compactVoice" and containerWidth <= SETTINGS_LIST_COMPACT_VOICE_SOURCE_BREAKPOINT then
        local source = metrics[2]
        if source and source.visible ~= false then lines[#lines + 1] = { 2 } end
        local contentLine = {}
        for index = 3, #metrics do
            if metrics[index].visible ~= false then contentLine[#contentLine + 1] = index end
        end
        if #contentLine > 0 then lines[#lines + 1] = contentLine end
    else
        local controlsLine = {}
        for index = 2, #metrics do
            if metrics[index].visible ~= false then controlsLine[#controlsLine + 1] = index end
        end
        if #controlsLine > 0 then lines[#lines + 1] = controlsLine end
    end

    local exbossProfile = row._exSettingsRowPresentationProfile == SETTINGS_LIST_EXBOSS_SKILL_PROFILE
    local paddingY = exbossProfile and (mode == "fieldRow" and 10
        or SETTINGS_LIST_EXBOSS_VOICE_PADDING_Y) or SETTINGS_LIST_ROW_PADDING_Y
    local lineGap = exbossProfile and (mode == "compactVoice" and 7 or 8) or 8
    local controlGap = exbossProfile and mode == "compactVoice"
        and SETTINGS_LIST_EXBOSS_VOICE_CONTROL_GAP or 8
    local rects = {}
    local y = paddingY
    local paddingX = exbossProfile and SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
        or SETTINGS_LIST_ROW_PADDING_X
    for lineIndex, indexes in ipairs(lines) do
        local x = lineIndex == 1 and paddingX
            or (paddingX + SETTINGS_LIST_NARROW_CONTROL_INDENT)
        local availableWidth = math.max(1, width - x - paddingX)
        local flexWeights = mode == "compactVoice"
            and ResolveSettingsVoiceFlexWeights(metrics, indexes) or nil
        local lineRects, lineHeight = ResolveSettingsControlLine(
            metrics, indexes, x, availableWidth, y, controlGap, flexWeights)
        for index, rect in pairs(lineRects) do rects[index] = rect end
        y = y + lineHeight
        if lineIndex < #lines then y = y + lineGap end
    end
    local height = math.max(row._exSettingsRowMinHeight, y + paddingY)
    return FinishSettingsHTMLControlsLayout(row, width, metrics, rects, height)
end

function EXUI:UpdateSettingsRowControlsLayout(row, width, metrics, containerWidth)
    if not row then return 0, {} end
    metrics = type(metrics) == "table" and metrics or {}
    width = math.max(1, tonumber(width) or 1)
    containerWidth = math.max(1, tonumber(containerWidth) or width)
    local htmlLayout = row._exSettingsRowHTMLControlsLayout
    local exbossProfile = row._exSettingsRowPresentationProfile == SETTINGS_LIST_EXBOSS_SKILL_PROFILE
    if exbossProfile then
        local pillHeight, pillRects = UpdateSettingsExbossPillChoicesLayout(
            row, width, metrics, containerWidth)
        if pillHeight then return pillHeight, pillRects end
    end
    if exbossProfile and (htmlLayout == "fieldRow" or htmlLayout == "compactVoice") then
        local breakpoint = htmlLayout == "fieldRow" and SETTINGS_LIST_FIELD_ROW_BREAKPOINT
            or SETTINGS_LIST_COMPACT_VOICE_BREAKPOINT
        if containerWidth > breakpoint then
            return UpdateSettingsHTMLWideControlsLayout(row, width, metrics, htmlLayout)
        end
        return UpdateSettingsHTMLControlsLayout(row, width, metrics, htmlLayout, containerWidth)
    end
    local narrowHTML = htmlLayout == "fieldRow" and containerWidth <= SETTINGS_LIST_FIELD_ROW_BREAKPOINT
        or htmlLayout == "compactVoice" and containerWidth <= SETTINGS_LIST_COMPACT_VOICE_BREAKPOINT
    if narrowHTML then
        return UpdateSettingsHTMLControlsLayout(row, width, metrics, htmlLayout, containerWidth)
    end
    if row._exSettingsRowContentWidth == "intrinsic"
        and row._exSettingsRowSingleLineControls == true then
        return UpdateSettingsSingleLineControlsLayout(row, width, metrics)
    end
    local gap = 8
    local rowPaddingX = exbossProfile and SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
        or SETTINGS_LIST_ROW_PADDING_X
    local innerWidth = math.max(1, width - rowPaddingX * 2)
    local title = row._exSettingsRowTitle
    local description = row._exSettingsRowDescription
    local hasText = title:IsShown() or description:IsShown()
    local labelIndex, rightAlign
    for index, metric in ipairs(metrics) do
        local visible = metric.visible ~= false
        if visible and (metric.presentation == "pill" or metric.align == "right") then rightAlign = true end
        if metric.role ~= nil and metric.role ~= "label" then
            error("unknown settings row control role: " .. tostring(metric.role), 2)
        elseif visible and metric.role == "label" then
            if labelIndex then error("settings row controls only support one label role", 2) end
            labelIndex = index
        end
    end
    local hasLeft = hasText or labelIndex ~= nil
    local textWidth = hasLeft and math.max(80,
        math.min(280, innerWidth * 0.38)) or 0
    local controlsX = rowPaddingX
    local controlsWidth = innerWidth
    if hasLeft then
        controlsX = controlsX + textWidth + SETTINGS_LIST_COLUMN_GAP
        controlsWidth = math.max(1, innerWidth - textWidth - SETTINGS_LIST_COLUMN_GAP)
    end
    local controlIndexes, fixedWidth, flexible = {}, 0, 0
    for index, metric in ipairs(metrics) do
        if metric.visible ~= false and index ~= labelIndex then
            controlIndexes[#controlIndexes + 1] = index
            local metricWidth = tonumber(metric.width)
            if metricWidth and metricWidth > 0 then fixedWidth = fixedWidth + metricWidth
            else flexible = flexible + 1 end
        end
    end
    local available = math.max(1,
        controlsWidth - math.max(0, #controlIndexes - 1) * gap)
    local flexibleWidth = flexible > 0
        and math.max(80, (available - fixedWidth) / flexible) or 0
    local rawRects, lines, lineHeights, lineIndexes, x, y, lineHeight, line = {}, {}, {}, {}, 0, 0, 0, 1
    for _, index in ipairs(controlIndexes) do
        local metric = metrics[index]
        local controlWidth = tonumber(metric.width)
        if not controlWidth or controlWidth <= 0 then controlWidth = flexibleWidth end
        controlWidth = math.min(controlsWidth, math.max(1, controlWidth))
        local controlHeight = math.max(1, tonumber(metric.height) or 28)
        if x > 0 and x + controlWidth > controlsWidth + 0.5 then
            lines[line] = math.max(0, x - gap)
            lineHeights[line] = lineHeight
            y = y + lineHeight + gap
            x, lineHeight, line = 0, 0, line + 1
        end
        rawRects[index] = { x = x, y = y, width = controlWidth, height = controlHeight }
        lineIndexes[index] = line
        x = x + controlWidth + gap
        lineHeight = math.max(lineHeight, controlHeight)
    end
    if #controlIndexes > 0 then
        lines[line] = math.max(0, x - gap)
        lineHeights[line] = lineHeight
    end
    local controlsHeight = #controlIndexes > 0 and (y + lineHeight) or 0
    local labelHeight = labelIndex and math.max(1, tonumber(metrics[labelIndex].height) or 28) or 0
    local textHeight = SettingsTextHeight(title, math.max(1, textWidth))
    if description:IsShown() then
        textHeight = textHeight + (textHeight > 0 and SETTINGS_LIST_DESCRIPTION_GAP or 0)
            + SettingsTextHeight(description, math.max(1, textWidth))
    end
    local rowPaddingY = exbossProfile and SETTINGS_LIST_EXBOSS_SIMPLE_PADDING_Y
        or SETTINGS_LIST_ROW_PADDING_Y
    local height = math.max(row._exSettingsRowMinHeight,
        rowPaddingY * 2 + math.max(textHeight, labelHeight, controlsHeight))
    if description:IsShown() then height = math.max(height, SETTINGS_LIST_DESCRIPTION_MIN_HEIGHT) end
    local rects = {}
    local controlsTop = math.floor((height - controlsHeight) * 0.5 + 0.5)
    for _, index in ipairs(controlIndexes) do
        local rect = rawRects[index]
        rects[index] = {
            x = controlsX + (rightAlign
                and math.max(0, controlsWidth - (lines[lineIndexes[index]] or controlsWidth)) or 0) + rect.x,
            y = controlsTop + rect.y
                + math.max(0, ((lineHeights[lineIndexes[index]] or rect.height) - rect.height) * 0.5),
            width = rect.width,
            height = rect.height,
        }
    end
    if labelIndex then
        rects[labelIndex] = {
            x = rowPaddingX,
            y = math.floor((height - labelHeight) * 0.5 + 0.5),
            width = textWidth,
            height = labelHeight,
        }
    end
    for index, metric in ipairs(metrics) do
        if metric.visible == false then
            rects[index] = {
                x = controlsX + controlsWidth,
                y = math.floor(height * 0.5 + 0.5),
                width = 1,
                height = math.max(1, tonumber(metric.height) or 1),
            }
        end
    end
    if hasText then
        local textTop = math.floor((height - textHeight) * 0.5 + 0.5)
        title:ClearAllPoints()
        if title:IsShown() then
            title:SetPoint("TOPLEFT", row, "TOPLEFT", rowPaddingX, -textTop)
            title:SetWidth(textWidth)
        end
        description:ClearAllPoints()
        if description:IsShown() then
            if title:IsShown() then
                description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -SETTINGS_LIST_DESCRIPTION_GAP)
            else description:SetPoint("TOPLEFT", row, "TOPLEFT", rowPaddingX, -textTop) end
            description:SetWidth(textWidth)
        end
    end
    row:SetSize(width, height)
    local divider = row._exSettingsRowDivider
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", rowPaddingX, 0)
    divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -rowPaddingX, 0)
    divider:SetShown(not row._exSettingsRowIsLast)
    EXUI:ClearControlSurface(row)
    return height, rects
end

-- Settings-list owners may recompute the last visible row after dynamic layout.
-- This changes only the shared decorative divider, never widget visibility.
function EXUI:SetSettingsRowLast(row, isLast)
    if not row then return false end
    if row._exSettingsRowDivider then
        row._exSettingsRowIsLast = isLast == true
        row._exSettingsRowDivider:SetShown(not row._exSettingsRowIsLast)
        return true
    end
    if row._exSettingsTableDivider then
        row._exSettingsTableIsLast = isLast == true
        row._exSettingsTableDivider:SetShown(not row._exSettingsTableIsLast)
        return true
    end
    return false
end

function EXUI:SetSettingsCardGroupMemberLast(card, isLast)
    if not card or not card._exSettingsGroupDivider then return false end
    card._exSettingsGroupDivider:SetShown(isLast ~= true)
    return true
end

local function ResolveSettingsTableColumns(width, columns)
    width = math.max(1, tonumber(width) or 1)
    columns = type(columns) == "table" and columns or {}
    local gap = 12
    local available = math.max(1,
        width - SETTINGS_LIST_ROW_PADDING_X * 2 - math.max(0, #columns - 1) * gap)
    local fixed, totalWeight = 0, 0
    for _, column in ipairs(columns) do
        local columnWidth = tonumber(column.width)
        if columnWidth and columnWidth > 0 then fixed = fixed + columnWidth
        else totalWeight = totalWeight + math.max(0.01, tonumber(column.weight) or 1) end
    end
    local weighted = math.max(1, available - fixed)
    local rects, x = {}, SETTINGS_LIST_ROW_PADDING_X
    for index, column in ipairs(columns) do
        local columnWidth = tonumber(column.width)
        if not columnWidth or columnWidth <= 0 then
            columnWidth = weighted * math.max(0.01, tonumber(column.weight) or 1) / totalWeight
        end
        rects[index] = { x = x, width = math.max(1, columnWidth) }
        x = x + columnWidth + gap
    end
    return rects
end

-- Pure shared column geometry for settings-form groups whose original controls
-- remain mounted in separate card bodies. No frames, bindings or values are
-- created or changed here.
function EXUI:ResolveSettingsTableColumns(width, columns)
    return ResolveSettingsTableColumns(width, columns)
end

function EXUI:CreateSettingsTableHeader(parent, options)
    options = type(options) == "table" and options or {}
    local header, isNew = AcquireCompositeGroup("CompositeSettingsTableHeader", parent)
    if isNew then
        header:EnableMouse(false)
        header._exSettingsTableLabels = {}
        header.Release = ReleaseSettingsListDecoration
    end
    header._exSettingsTableColumns = {}
    for index, column in ipairs(options.columns or {}) do
        header._exSettingsTableColumns[index] = {
            title = tostring(column.title or ""),
            width = tonumber(column.width),
            weight = tonumber(column.weight),
        }
        local label = header._exSettingsTableLabels[index]
        if not label then
            label = EXUI:CreateVisualFontString(header, EXFONTFRAME, "GameFontHighlightSmall")
            header._exSettingsTableLabels[index] = label
        end
        label:SetJustifyH("CENTER")
        label:SetText(header._exSettingsTableColumns[index].title)
        label:Show()
        MODERN.Font(label, 14, SETTINGS_LIST_TITLE, "", "GameFontHighlightSmall")
    end
    for index = #(options.columns or {}) + 1, #header._exSettingsTableLabels do
        header._exSettingsTableLabels[index]:Hide()
    end
    return header
end

function EXUI:UpdateSettingsTableHeaderLayout(header, width)
    if not header then return 0, {} end
    local rects = ResolveSettingsTableColumns(width, header._exSettingsTableColumns)
    local height = 38
    header:SetSize(math.max(1, tonumber(width) or 1), height)
    for index, rect in ipairs(rects) do
        local label = header._exSettingsTableLabels[index]
        label:ClearAllPoints()
        label:SetPoint("LEFT", header, "LEFT", rect.x, 0)
        label:SetWidth(rect.width)
    end
    return height, rects
end

function EXUI:CreateSettingsTableRow(parent, options)
    options = type(options) == "table" and options or {}
    local row, isNew = AcquireCompositeGroup("CompositeSettingsTableRow", parent)
    if isNew then
        row:EnableMouse(false)
        row._exSettingsTableStaticLabels = {}
        local divider = CreateSettingsDivider(row)
        row._exSettingsTableDivider = divider
        row.Release = ReleaseSettingsListDecoration
    end
    row._exSettingsTableIsLast = options.isLast == true
    local shown = {}
    for column, value in pairs(options.staticCells or {}) do
        if type(column) == "number" and value ~= nil then
            local label = row._exSettingsTableStaticLabels[column]
            if not label then
                label = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlight")
                label:SetJustifyH("LEFT")
                row._exSettingsTableStaticLabels[column] = label
            end
            label:SetText(tostring(value))
            label:Show()
            MODERN.ApplyTextRole(label, "title", SETTINGS_LIST_TITLE)
            shown[column] = true
        end
    end
    for column, label in pairs(row._exSettingsTableStaticLabels) do
        if not shown[column] then label:Hide() end
    end
    row._exSettingsTableDivider:SetShown(not row._exSettingsTableIsLast)
    EXUI:ClearControlSurface(row)
    return row
end

function EXUI:UpdateSettingsTableRowLayout(row, width, columns, metrics)
    if not row then return 0, {} end
    columns = type(columns) == "table" and columns or {}
    metrics = type(metrics) == "table" and metrics or {}
    local height = 48
    for _, metric in ipairs(metrics) do
        if not metric or metric.visible ~= false then
            height = math.max(height, math.max(1, tonumber(metric and metric.height) or 1) + 16)
        end
    end
    row:SetSize(math.max(1, tonumber(width) or 1), height)
    local rects = {}
    for index, column in ipairs(columns) do
        local metric = metrics[index] or {}
        local cellHeight = math.max(1, tonumber(metric.height) or 28)
        rects[index] = {
            x = column.x + 4,
            y = math.floor((height - cellHeight) * 0.5 + 0.5),
            width = math.max(1, column.width - 8),
            height = cellHeight,
        }
        local label = row._exSettingsTableStaticLabels[index]
        if label and label:IsShown() then
            label:ClearAllPoints()
            label:SetPoint("LEFT", row, "LEFT", column.x + 4, 0)
            label:SetWidth(math.max(1, column.width - 8))
        end
    end
    local divider = row._exSettingsTableDivider
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", SETTINGS_LIST_ROW_PADDING_X, 0)
    divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -SETTINGS_LIST_ROW_PADDING_X, 0)
    divider:SetShown(not row._exSettingsTableIsLast)
    return height, rects
end

local function CaptureRegionPoints(region)
    local points = {}
    if not region or not region.GetNumPoints then return points end
    for index = 1, region:GetNumPoints() do
        points[index] = { region:GetPoint(index) }
    end
    return points
end

local function RestoreRegionPoints(region, points)
    if not region or not region.ClearAllPoints then return end
    region:ClearAllPoints()
    for _, point in ipairs(points or {}) do region:SetPoint(unpack(point)) end
end

local function CaptureControlSurfaceState(frame)
    local state = {}
    for radius, skin in pairs(frame and frame._exModernSurfaces or {}) do
        local saved = { pieces = {} }
        for index, piece in ipairs(skin.pieces or {}) do
            local r, g, b, a = piece.texture:GetVertexColor()
            saved.pieces[index] = {
                shown = piece.texture:IsShown(), alpha = piece.texture:GetAlpha(),
                color = { r, g, b, a },
            }
        end
        state[radius] = saved
    end
    return state
end

local function RestoreControlSurfaceState(frame, state)
    for radius, skin in pairs(frame and frame._exModernSurfaces or {}) do
        local saved = state and state[radius]
        if skin.Layout then skin.Layout() end
        for index, piece in ipairs(skin.pieces or {}) do
            local pieceState = saved and saved.pieces[index]
            if pieceState then
                piece.texture:SetVertexColor(unpack(pieceState.color))
                piece.texture:SetAlpha(pieceState.alpha)
                piece.texture:SetShown(pieceState.shown)
            else
                piece.texture:SetAlpha(0)
                piece.texture:Hide()
            end
        end
    end
end

local function SetControlSurfaceAlpha(frame, alpha)
    for _, skin in pairs(frame and frame._exModernSurfaces or {}) do
        for _, piece in ipairs(skin.pieces or {}) do piece.texture:SetAlpha(alpha) end
    end
end

function EXUI:PrepareSettingsListCard(card, options)
    if not card or not card._exSettingsCardBody then return false, "not-settings-card" end
    if card._exSettingsListCardState then return true end
    options = type(options) == "table" and options or {}
    local presentationProfile = options.presentationProfile
    if presentationProfile ~= nil and presentationProfile ~= SETTINGS_LIST_EXBOSS_SKILL_PROFILE then
        return false, "unknown-presentation-profile"
    end
    local exbossProfile = presentationProfile == SETTINGS_LIST_EXBOSS_SKILL_PROFILE
    local groupMember = options.groupMember == true
    local descriptionOnly = options.descriptionOnly == true and not groupMember
    local groupCollapsible = not groupMember or options.groupCollapsible ~= false
    local externalCollapsible = options.externalCollapsible == true and not groupMember
    local preserveHeader = options.preserveHeader == true or externalCollapsible or groupMember
    if exbossProfile and (groupMember or options.preserveHeader ~= true) then
        return false, "exboss-skill-profile-requires-external-header"
    end
    if not preserveHeader and not descriptionOnly and card._exSettingsCardCollapsible == true then
        return false, "collapsible-card"
    end
    if not preserveHeader and not descriptionOnly and card._exSettingsCardCollapsed == true then
        return false, "collapsed-card"
    end
    local body = card._exSettingsCardBody
    card._exSettingsListCardState = {
        mode = groupMember and (groupCollapsible and "group" or "flat")
            or (preserveHeader and "external" or "flat"),
        headerShown = card._exSettingsCardHeader:IsShown(),
        headerHeight = card._exSettingsCardHeader:GetHeight(),
        headerMouseEnabled = card._exSettingsCardHeader:IsMouseEnabled(),
        bodyShown = body:IsShown(),
        bodyPoints = CaptureRegionPoints(body),
        bodyWidth = body:GetWidth(),
        bodyHeight = body:GetHeight(),
        cardWidth = card:GetWidth(),
        cardHeight = card:GetHeight(),
        surfaces = CaptureControlSurfaceState(card),
        bodySurfaces = CaptureControlSurfaceState(body),
        headerSurfaces = CaptureControlSurfaceState(card._exSettingsCardHeader),
        titleShown = card._exSettingsCardTitle:IsShown(),
        titlePoints = CaptureRegionPoints(card._exSettingsCardTitle),
        iconShown = card._exSettingsCardIcon:IsShown(),
        iconPoints = CaptureRegionPoints(card._exSettingsCardIcon),
        toggleShown = card._exSettingsCardToggle:IsShown(),
        togglePoints = CaptureRegionPoints(card._exSettingsCardToggle),
        dividerShown = card._exSettingsCardDivider:IsShown(),
        squareBottomShown = card._exSettingsCardSquareBottom:IsShown(),
        collapsible = card._exSettingsCardCollapsible,
        collapsed = card._exSettingsCardCollapsed,
    }
    card._exSettingsListPresentationProfile = presentationProfile
    card._exSettingsListCardMode = card._exSettingsListCardState.mode
    if groupMember and groupCollapsible then
        local headerHeight = 52
        card._exSettingsListGroupMember = {
            titleColor = MC.text,
            glyphColor = MC.muted,
            headerHeight = headerHeight,
        }
        card._exSettingsCardCollapsible = true
        local header = card._exSettingsCardHeader
        header:SetHeight(headerHeight)
        header:Show()
        header:EnableMouse(true)
        card._exSettingsCardIcon:Hide()
        card._exSettingsCardTitle:ClearAllPoints()
        card._exSettingsCardTitle:SetPoint("LEFT", header, "LEFT", 20, 0)
        card._exSettingsCardTitle:SetPoint("RIGHT", card._exSettingsCardToggle, "LEFT", -8, 0)
        card._exSettingsCardTitle:Show()
        card._exSettingsCardToggle:ClearAllPoints()
        card._exSettingsCardToggle:SetPoint("RIGHT", header, "RIGHT", -16, 0)
        card._exSettingsCardToggle:Show()
        card._exSettingsCardDivider:Hide()
        card._exSettingsCardSquareBottom:Hide()
        if not card._exSettingsGroupDivider then
            card._exSettingsGroupDivider = CreateSettingsDivider(card)
        end
        local groupDivider = card._exSettingsGroupDivider
        groupDivider:ClearAllPoints()
        groupDivider:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 20, 0)
        groupDivider:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -20, 0)
        groupDivider:SetShown(options.isLast ~= true)
        SetControlSurfaceAlpha(header, 0)
        card._exSettingsCardPaintHeader()
    elseif groupMember then
        -- An explicitly non-collapsible settings group contributes only its
        -- existing body to the shared outer group surface.  Header interaction,
        -- configuration ownership and child controls remain untouched.
        local header = card._exSettingsCardHeader
        header:Hide()
        header:EnableMouse(externalCollapsible)
        card._exSettingsCardIcon:Hide()
        card._exSettingsCardTitle:Hide()
        card._exSettingsCardToggle:Hide()
        card._exSettingsCardDivider:Hide()
        card._exSettingsCardSquareBottom:Hide()
        card._exSettingsCardCollapsible = false
        card._exSettingsCardCollapsed = false
        body:Show()
        if not card._exSettingsGroupDivider then
            card._exSettingsGroupDivider = CreateSettingsDivider(card)
        end
        local groupDivider = card._exSettingsGroupDivider
        groupDivider:ClearAllPoints()
        groupDivider:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 20, 0)
        groupDivider:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -20, 0)
        groupDivider:SetShown(options.isLast ~= true)
        SetControlSurfaceAlpha(header, 0)
    elseif preserveHeader then
        -- The existing toggle remains the original object with the original
        -- click scripts. Only its geometry and the surrounding paint change.
        local title = card._exSettingsCardTitle
        local externalHeaderHeight = exbossProfile and SETTINGS_LIST_EXBOSS_HEADER_HEIGHT
            or SETTINGS_LIST_EXTERNAL_HEADER_HEIGHT
        if not exbossProfile then
            MODERN.ApplyTextRole(title, "title", SETTINGS_LIST_TITLE)
            title:SetJustifyH("LEFT")
            title:SetJustifyV("TOP")
            title:SetWordWrap(true)
            local titleWidth = math.max(1, (tonumber(card:GetWidth()) or 1)
                - (externalCollapsible and 32 or 0))
            externalHeaderHeight = 8 + SettingsTextHeight(title, titleWidth) + 18
        end
        card._exSettingsListExternalHeader = {
            titleColor = SETTINGS_LIST_TITLE,
            glyphColor = SETTINGS_LIST_DESCRIPTION,
            height = externalHeaderHeight,
            footerPadding = exbossProfile and SETTINGS_LIST_EXBOSS_FOOTER_PADDING or 0,
        }
        local header = card._exSettingsCardHeader
        header:SetHeight(card._exSettingsListExternalHeader.height)
        header:Show()
        header:EnableMouse(false)
        if exbossProfile then
            card._exSettingsCardIcon:ClearAllPoints()
            card._exSettingsCardIcon:SetPoint("LEFT", header, "LEFT", SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X, 0)
            card._exSettingsCardIcon:Show()
        else
            card._exSettingsCardIcon:Hide()
        end
        card._exSettingsCardTitle:ClearAllPoints()
        if exbossProfile then
            card._exSettingsCardTitle:SetPoint("LEFT", card._exSettingsCardIcon, "RIGHT", 8, 0)
            card._exSettingsCardTitle:SetPoint("RIGHT", header, "RIGHT", -SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X, 0)
        else
            title:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -8)
            if externalCollapsible then
                title:SetPoint("TOPRIGHT", card._exSettingsCardToggle, "TOPLEFT", -8, -8)
            else
                title:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, -8)
            end
        end
        card._exSettingsCardTitle:Show()
        card._exSettingsCardToggle:ClearAllPoints()
        card._exSettingsCardToggle:SetPoint("RIGHT", header, "RIGHT", 0, 0)
        -- Collapsible typed sections keep this same transparent external title
        -- geometry and the same flat body surface. The original header/toggle
        -- scripts remain the sole interaction owner; only their visibility and
        -- the existing card flag change.
        card._exSettingsCardCollapsible = externalCollapsible
        if not externalCollapsible then card._exSettingsCardCollapsed = false end
        card._exSettingsCardToggle:SetShown(externalCollapsible)
        body:SetShown(not card._exSettingsCardCollapsed)
        card._exSettingsCardDivider:Hide()
        card._exSettingsCardSquareBottom:Hide()
        SetControlSurfaceAlpha(header, 0)
        card._exSettingsCardPaintHeader()
    else
        local header = card._exSettingsCardHeader
        header:Hide()
        if descriptionOnly then
            header:EnableMouse(false)
            card._exSettingsCardIcon:Hide()
            card._exSettingsCardTitle:Hide()
            card._exSettingsCardToggle:Hide()
            card._exSettingsCardDivider:Hide()
            card._exSettingsCardSquareBottom:Hide()
            card._exSettingsCardCollapsible = false
            card._exSettingsCardCollapsed = false
            body:Show()
            SetControlSurfaceAlpha(header, 0)
        end
    end
    body:ClearAllPoints()
    local bodyTop = groupMember and (groupCollapsible and 52 or 0)
        or (preserveHeader and (card._exSettingsListExternalHeader
            and card._exSettingsListExternalHeader.height
            or (exbossProfile and SETTINGS_LIST_EXBOSS_HEADER_HEIGHT
                or SETTINGS_LIST_EXTERNAL_HEADER_HEIGHT)) or 0)
    local bodyInset = groupMember and groupCollapsible and 12 or 0
    body:SetPoint("TOPLEFT", card, "TOPLEFT", bodyInset, -bodyTop)
    body:SetPoint("TOPRIGHT", card, "TOPRIGHT", -bodyInset, -bodyTop)
    if (groupMember and groupCollapsible) or externalCollapsible then
        body:SetShown(not card._exSettingsCardCollapsed)
    else
        body:Show()
    end
    EXUI:SetControlSurface(body, 10,
        groupMember and MC.raised or SETTINGS_LIST_CARD_FILL, SETTINGS_LIST_CARD_BORDER)
    if exbossProfile then
        EXUI:SetControlSurface(card, 10, SETTINGS_LIST_CARD_FILL, SETTINGS_LIST_CARD_BORDER)
        SetControlSurfaceAlpha(card, 1)
        SetControlSurfaceAlpha(body, 0)
    else
        SetControlSurfaceAlpha(card, 0)
        SetControlSurfaceAlpha(body,
            (descriptionOnly or (groupMember and not groupCollapsible)) and 0 or 1)
    end
    if (groupMember and groupCollapsible) or externalCollapsible then
        card:SetCollapsed(options.collapsed == true, true)
    end
    card:SetHeight(card:GetPreferredHeight())
    return true
end

function EXUI:RestoreSettingsListCard(card)
    local state = card and card._exSettingsListCardState
    if not state then return false end
    local body = card._exSettingsCardBody
    card._exSettingsListCardMode = nil
    card._exSettingsListExternalHeader = nil
    card._exSettingsListGroupMember = nil
    card._exSettingsListPresentationProfile = nil
    card._exSettingsCardCollapsible = state.collapsible == true
    card._exSettingsCardCollapsed = state.collapsed == true
    card:SetSize(state.cardWidth, state.cardHeight)
    RestoreRegionPoints(body, state.bodyPoints)
    body:SetHeight(state.bodyHeight)
    body:SetShown(state.bodyShown)
    RestoreControlSurfaceState(body, state.bodySurfaces)
    card._exSettingsCardHeader:SetShown(state.headerShown)
    card._exSettingsCardHeader:SetHeight(state.headerHeight)
    card._exSettingsCardHeader:EnableMouse(state.headerMouseEnabled ~= false)
    RestoreControlSurfaceState(card._exSettingsCardHeader, state.headerSurfaces)
    RestoreRegionPoints(card._exSettingsCardTitle, state.titlePoints)
    MODERN.ApplyTextRole(card._exSettingsCardTitle, "cardTitle")
    card._exSettingsCardTitle:SetJustifyH("LEFT")
    card._exSettingsCardTitle:SetJustifyV("MIDDLE")
    card._exSettingsCardTitle:SetWordWrap(false)
    card._exSettingsCardTitle:SetShown(state.titleShown)
    RestoreRegionPoints(card._exSettingsCardIcon, state.iconPoints)
    card._exSettingsCardIcon:SetShown(state.iconShown)
    RestoreRegionPoints(card._exSettingsCardToggle, state.togglePoints)
    card._exSettingsCardToggle:SetShown(state.toggleShown)
    card._exSettingsCardDivider:SetShown(state.dividerShown)
    card._exSettingsCardSquareBottom:SetShown(state.squareBottomShown)
    card._exSettingsCardToggle._exGlyph:SetText(state.collapsed and "v" or "^")
    RestoreControlSurfaceState(card, state.surfaces)
    card._exSettingsListCardState = nil
    if card._exSettingsGroupDivider then card._exSettingsGroupDivider:Hide() end
    card._exSettingsCardPaintHeader()
    return true
end

function EXUI:CreateSettingsCardGroupSurface(parent, options)
    local surface, isNew = AcquireCompositeGroup("CompositeSettingsCardGroupSurface", parent)
    if isNew then
        surface:EnableMouse(false)
        surface.Release = ReleaseSettingsListDecoration
    end
    if parent and surface.SetFrameLevel and parent.GetFrameLevel then
        surface:SetFrameLevel(parent:GetFrameLevel())
    end
    if parent and surface.SetFrameStrata and parent.GetFrameStrata then
        surface:SetFrameStrata(parent:GetFrameStrata())
    end
    EXUI:SetControlSurface(surface, 10, MC.panel, MC.border)
    surface:Show()
    return surface
end

function EXUI:UpdateSettingsCardGroupSurfaceLayout(surface, width, height)
    if not surface then return 0 end
    width = math.max(1, tonumber(width) or 1)
    height = math.max(1, tonumber(height) or 1)
    surface:SetSize(width, height)
    EXUI:SetControlSurface(surface, 10, MC.panel, MC.border)
    return height
end

local SETTINGS_LIST_BORROWED_KINDS = {
    input = true, switch = true, select = true, color = true,
    button = true, text = true, multiline = true,
}

function EXUI:RestoreSettingsListControl(widget)
    local state = widget and widget._exSettingsListVisualState
    if not state then return false end
    if state.hasSettingsListHeight then
        widget._exGridFixedHeight = state.settingsListFixedHeight
        widget:SetHeight(state.settingsListHeight)
    end
    widget._exSettingsOrdinaryControl = state.ordinaryControl
    widget._exSettingsTextRole = state.textRole
    widget._exSettingsBorrowedKind = state.borrowedKind
    for _, entry in ipairs(state.labels or {}) do
        if entry.region and entry.region.SetShown then entry.region:SetShown(entry.shown) end
    end
    local role = state.roleLabel
    if role and role.region then
        local region = role.region
        region:SetText(role.text)
        RestoreRegionPoints(region, role.points)
        if role.fontPath then region:SetFont(role.fontPath, role.fontSize, role.fontFlags) end
        region:SetTextColor(unpack(role.color))
        if region.SetShadowColor and role.shadowColor then region:SetShadowColor(unpack(role.shadowColor)) end
        if region.SetShadowOffset and role.shadowX then region:SetShadowOffset(role.shadowX, role.shadowY) end
        if region.SetJustifyH and role.justifyH then region:SetJustifyH(role.justifyH) end
        if region.SetJustifyV and role.justifyV then region:SetJustifyV(role.justifyV) end
        if role.widgetHeight then widget:SetHeight(role.widgetHeight) end
    end
    local tableTextRole = state.roleTableText
    if tableTextRole and tableTextRole.region then
        local region = tableTextRole.region
        RestoreRegionPoints(region, tableTextRole.points)
        if tableTextRole.fontPath then
            region:SetFont(tableTextRole.fontPath, tableTextRole.fontSize, tableTextRole.fontFlags)
        end
        region:SetTextColor(unpack(tableTextRole.color))
        if region.SetShadowColor and tableTextRole.shadowColor then
            region:SetShadowColor(unpack(tableTextRole.shadowColor))
        end
        if region.SetShadowOffset and tableTextRole.shadowX then
            region:SetShadowOffset(tableTextRole.shadowX, tableTextRole.shadowY)
        end
        region:SetJustifyH(tableTextRole.justifyH or "LEFT")
        region:SetJustifyV(tableTextRole.justifyV or "TOP")
        region:SetWordWrap(tableTextRole.wordWrap == true)
        if region.SetMaxLines and tableTextRole.maxLines ~= nil then
            region:SetMaxLines(tableTextRole.maxLines)
        end
    end
    local descriptionRole = state.roleDescription
    if descriptionRole and descriptionRole.region then
        local region = descriptionRole.region
        region:SetSize(descriptionRole.width, descriptionRole.height)
        RestoreRegionPoints(region, descriptionRole.points)
        if descriptionRole.fontPath then
            region:SetFont(descriptionRole.fontPath, descriptionRole.fontSize, descriptionRole.fontFlags)
        end
        region:SetTextColor(unpack(descriptionRole.color))
        if region.SetShadowColor and descriptionRole.shadowColor then
            region:SetShadowColor(unpack(descriptionRole.shadowColor))
        end
        if region.SetShadowOffset and descriptionRole.shadowX then
            region:SetShadowOffset(descriptionRole.shadowX, descriptionRole.shadowY)
        end
        region:SetJustifyH(descriptionRole.justifyH or "LEFT")
        region:SetJustifyV(descriptionRole.justifyV or "TOP")
        region:SetWordWrap(descriptionRole.wordWrap == true)
        if region.SetMaxLines and descriptionRole.maxLines ~= nil then
            region:SetMaxLines(descriptionRole.maxLines)
        end
    end
    local box = widget.checkbox
    if box and state.checkbox then
        widget._exSettingsPresentation = state.presentation
        widget._exSettingsCardDescription = state.cardDescription
        widget._exSettingsCardIcon = state.cardIcon
        widget._exSettingsCardCheckSize = state.cardCheckSize
        widget._exSettingsCardTextSize = state.cardTextSize
        widget._exSettingsPillNaturalWidth = state.pillNaturalWidth
        widget._exSettingsPillVisualPending = nil
        box:SetSize(state.checkbox.width, state.checkbox.height)
        RestoreRegionPoints(box, state.checkbox.points)
        if widget.label and state.checkbox.labelPoints then
            RestoreRegionPoints(widget.label, state.checkbox.labelPoints)
            widget.label:SetJustifyH(state.checkbox.labelJustify or "LEFT")
            widget.label:SetShown(state.checkbox.labelShown ~= false)
        end
        if box._exSettingsPillLabel then box._exSettingsPillLabel:Hide() end
        PaintModernCheckbox(widget)
    end
    if state.buttonVariant then
        widget._exButtonVariant = state.buttonVariant
        PaintModernButton(widget)
    end
    if state.sliderLayout then
        local sliderState = state.sliderLayout
        widget._exSettingsValuePosition = sliderState.valuePosition
        widget._exGridFixedHeight = sliderState.fixedHeight
        widget:SetSize(sliderState.width, sliderState.height)
        local input = widget.numberInput
        if input then
            RestoreRegionPoints(input, sliderState.inputPoints)
            input:SetSize(sliderState.inputWidth, sliderState.inputHeight)
        end
        local interactive = widget.Slider
        if interactive and sliderState.interactivePoints then
            RestoreRegionPoints(interactive, sliderState.interactivePoints)
            interactive:SetSize(sliderState.interactiveWidth, sliderState.interactiveHeight)
        end
    end
    widget._exSettingsListVisualState = nil
    return true
end

-- Reflow only the original GridSlider and its original number EditBox.  The
-- numeric value, formatter, interaction scripts and lifecycle callbacks remain
-- owned by CreateSlider.
function EXUI:UpdateSettingsListControlLayout(widget, width)
    if not widget then return 0 end
    width = math.max(1, tonumber(width) or widget:GetWidth() or 1)
    local borrowedKind = widget._exSettingsBorrowedKind
    if widget._exSettingsOrdinaryControl == true and borrowedKind ~= nil then
        widget:SetSize(width, SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT)
        widget._exGridFixedHeight = SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT
        return SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT, width
    elseif borrowedKind == "text" or borrowedKind == "multiline" then
        widget:SetWidth(width)
        return math.max(1, widget:GetHeight()), width
    end
    if widget._gridType == "GridSlider" and widget._exSettingsValuePosition == "right"
        and widget.numberInput then
        local height = SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT
        local gap, inputWidth, trackWidth
        if widget._exSettingsOrdinaryControl == true then
            gap = math.min(10, math.max(0, width - 2))
            inputWidth = math.min(SLIDER_NUMBER_INPUT_WIDTH, math.max(1, width - gap - 1))
            trackWidth = math.max(1, width - gap - inputWidth)
        else
            gap, inputWidth = 10, SLIDER_NUMBER_INPUT_WIDTH
            trackWidth = math.max(80, width - gap - inputWidth)
        end
        widget:SetSize(trackWidth, height)
        widget._exGridFixedHeight = height
        local input = widget.numberInput
        input:ClearAllPoints()
        input:SetPoint("LEFT", widget, "RIGHT", gap, 0)
        input:SetSize(inputWidth, SLIDER_NUMBER_INPUT_HEIGHT)
        local interactive = widget.Slider
        if interactive then
            interactive:ClearAllPoints()
            interactive:SetPoint("LEFT", widget, "LEFT", 0, 0)
            interactive:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
            interactive:SetHeight(20)
        end
        return height, width
    end
    if widget._exSettingsOrdinaryControl == true
        and (widget._gridType == "GridInput" or widget._gridType == "GridDropdown"
            or widget._gridType == "GridLSMDropdown" or widget._gridType == "GridMultiselect"
            or widget._gridType == "GridColorButton") then
        widget:SetSize(width, SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT)
        widget._exGridFixedHeight = SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT
        -- Repaint against the final first-pass geometry as well as later
        -- reflows. This synchronizes the surface slices even when a pooled
        -- dropdown happens to be assigned the same root width it held before.
        if widget._gridType == "GridInput" then
            PaintModernInput(widget, widget)
        elseif widget._gridType == "GridColorButton" then
            PaintModernButton(widget)
        else
            PaintModernDropdown(widget)
        end
        return SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT, width
    end
    widget:SetWidth(width)
    return math.max(1, widget:GetHeight()), width
end

function EXUI:PrepareSettingsListControl(widget, options)
    if not widget then return false end
    options = type(options) == "table" and options or {}
    if widget._exSettingsListVisualState then self:RestoreSettingsListControl(widget) end
    local borrowedKind = options.borrowedKind
    if borrowedKind ~= nil then
        if SETTINGS_LIST_BORROWED_KINDS[borrowedKind] ~= true then
            error("unknown borrowed settings-list control kind: " .. tostring(borrowedKind), 2)
        end
        if widget._gridType ~= nil then
            error("borrowed settings-list control kind requires an original control without _gridType", 2)
        end
    end
    local state = {
        labels = {},
        presentation = widget._exSettingsPresentation,
        cardDescription = widget._exSettingsCardDescription,
        cardIcon = widget._exSettingsCardIcon,
        cardCheckSize = widget._exSettingsCardCheckSize,
        cardTextSize = widget._exSettingsCardTextSize,
        pillNaturalWidth = widget._exSettingsPillNaturalWidth,
        ordinaryControl = widget._exSettingsOrdinaryControl,
        textRole = widget._exSettingsTextRole,
        borrowedKind = widget._exSettingsBorrowedKind,
    }
    widget._exSettingsBorrowedKind = borrowedKind
    local function SetSettingsListHeight(height)
        if not state.hasSettingsListHeight then
            state.hasSettingsListHeight = true
            state.settingsListHeight = widget:GetHeight()
            state.settingsListFixedHeight = widget._exGridFixedHeight
        end
        widget._exGridFixedHeight = height
        widget:SetHeight(height)
    end
    local isSingleLineInput = widget._gridType == "GridInput"
        and widget.IsMultiLine and not widget:IsMultiLine()
    local isOrdinaryRectangle = isSingleLineInput or widget._gridType == "GridDropdown"
        or widget._gridType == "GridLSMDropdown" or widget._gridType == "GridMultiselect"
        or widget._gridType == "GridColorButton"
    local isOrdinarySlider = widget._gridType == "GridSlider" and options.valuePosition == "right"
    local isBorrowedOrdinary = borrowedKind ~= nil
        and borrowedKind ~= "text" and borrowedKind ~= "multiline"
    widget._exSettingsOrdinaryControl = options.ordinaryControl == true
        and (isOrdinaryRectangle or isOrdinarySlider or isBorrowedOrdinary) or nil
    if widget._exSettingsOrdinaryControl and (isOrdinaryRectangle or isBorrowedOrdinary) then
        SetSettingsListHeight(SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT)
    elseif isSingleLineInput or widget._gridType == "GridColorButton" then
        SetSettingsListHeight(isSingleLineInput and 28 or 36)
    elseif widget._gridType == "GridButton" then
        SetSettingsListHeight(28)
    elseif widget._gridType == "GridCheckbox" then
        SetSettingsListHeight(options.presentation == "card" and 38 or (options.presentation == "pill" and 32 or 28))
    end
    if options.presentation == "primary" and widget._gridType == "GridButton" then
        state.buttonVariant = widget._exButtonVariant or "secondary"
        widget._exButtonVariant = "primary"
        PaintModernButton(widget)
    end
    if options.width == "content" and widget._gridType == "GridButton" then
        local label = widget.GetFontString and widget:GetFontString() or nil
        local textWidth = label and label.GetUnboundedStringWidth
            and math.ceil(label:GetUnboundedStringWidth() or 0) or 0
        widget:SetWidth(math.max(BUTTON_STYLE.minWidth, textWidth + BUTTON_STYLE.paddingX * 2))
    end
    if options.valuePosition == "right" and widget._gridType == "GridSlider" and widget.numberInput then
        local input = widget.numberInput
        local interactive = widget.Slider
        state.sliderLayout = {
            valuePosition = widget._exSettingsValuePosition,
            fixedHeight = widget._exGridFixedHeight,
            width = widget:GetWidth(), height = widget:GetHeight(),
            inputPoints = CaptureRegionPoints(input),
            inputWidth = input:GetWidth(), inputHeight = input:GetHeight(),
            interactivePoints = interactive and CaptureRegionPoints(interactive) or nil,
            interactiveWidth = interactive and interactive:GetWidth() or nil,
            interactiveHeight = interactive and interactive:GetHeight() or nil,
        }
        widget._exSettingsValuePosition = "right"
        self:UpdateSettingsListControlLayout(widget, widget:GetWidth())
    end
    if options.role == "label" then
        local region = ResolveSettingsListRoleRegion(widget)
        if region and region.GetText and region.SetText then
            local fontPath, fontSize, fontFlags = region:GetFont()
            local shadowR, shadowG, shadowB, shadowA = region:GetShadowColor()
            local shadowX, shadowY = region:GetShadowOffset()
            state.roleLabel = {
                region = region, text = region:GetText(), points = CaptureRegionPoints(region),
                widgetHeight = widget:GetHeight(),
                fontPath = fontPath, fontSize = fontSize, fontFlags = fontFlags,
                color = { region:GetTextColor() }, shadowColor = { shadowR, shadowG, shadowB, shadowA },
                shadowX = shadowX, shadowY = shadowY,
                justifyH = region:GetJustifyH(), justifyV = region:GetJustifyV(),
            }
            local plain = tostring(region:GetText() or "")
                :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            region:SetText(plain)
            if region ~= widget then
                region:ClearAllPoints()
                region:SetPoint("LEFT", widget, "LEFT", 0, 0)
                region:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
            end
            region:SetJustifyH("LEFT")
            region:SetJustifyV("MIDDLE")
            MODERN.ApplyTextRole(region, "title", SETTINGS_LIST_TITLE)
            SetSettingsListHeight(28)
        end
    elseif options.role == "tableText" then
        local region = ResolveSettingsListRoleRegion(widget)
        if region and region.GetText then
            local fontPath, fontSize, fontFlags = region:GetFont()
            local shadowR, shadowG, shadowB, shadowA = region:GetShadowColor()
            local shadowX, shadowY = region:GetShadowOffset()
            state.roleTableText = {
                region = region, points = CaptureRegionPoints(region),
                fontPath = fontPath, fontSize = fontSize, fontFlags = fontFlags,
                color = { region:GetTextColor() },
                shadowColor = { shadowR, shadowG, shadowB, shadowA },
                shadowX = shadowX, shadowY = shadowY,
                justifyH = region:GetJustifyH(), justifyV = region:GetJustifyV(),
                wordWrap = region:CanWordWrap(),
                maxLines = region.GetMaxLines and region:GetMaxLines() or nil,
            }
            widget._exSettingsTextRole = "tableText"
            if region ~= widget then
                region:ClearAllPoints()
                region:SetPoint("LEFT", widget, "LEFT", 0, 0)
                region:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
            end
            region:SetJustifyH("CENTER")
            region:SetJustifyV("MIDDLE")
            MODERN.ApplyTextRole(region, "title", SETTINGS_LIST_TITLE)
            SetSettingsListHeight(28)
        end
    elseif options.role == "description" then
        local region = ResolveSettingsListRoleRegion(widget)
        if region and region.GetText then
            local fontPath, fontSize, fontFlags = region:GetFont()
            local shadowR, shadowG, shadowB, shadowA = region:GetShadowColor()
            local shadowX, shadowY = region:GetShadowOffset()
            state.roleDescription = {
                region = region, points = CaptureRegionPoints(region),
                width = region:GetWidth(), height = region:GetHeight(),
                fontPath = fontPath, fontSize = fontSize, fontFlags = fontFlags,
                color = { region:GetTextColor() },
                shadowColor = { shadowR, shadowG, shadowB, shadowA },
                shadowX = shadowX, shadowY = shadowY,
                justifyH = region:GetJustifyH(), justifyV = region:GetJustifyV(),
                wordWrap = region:CanWordWrap(),
                maxLines = region.GetMaxLines and region:GetMaxLines() or nil,
            }
            if region ~= widget then
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)
                region:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 0, 0)
            end
            region:SetJustifyH("LEFT")
            region:SetJustifyV("TOP")
            region:SetWordWrap(true)
            if region.SetMaxLines then region:SetMaxLines(0) end
            MODERN.Font(region, 13, SETTINGS_LIST_DESCRIPTION, "", "GameFontHighlightSmall")
        end
    end
    if options.hideLabel == true then
        local seen = {}
        for _, field in ipairs({ "labelText", "label", "Title" }) do
            local region = widget[field]
            if region and not seen[region] and region.IsShown and region.SetShown then
                seen[region] = true
                state.labels[#state.labels + 1] = { region = region, shown = region:IsShown() }
                region:Hide()
            end
        end
    end
    local box = widget.checkbox
    if (options.presentation == "switch" or options.presentation == "pill" or options.presentation == "card") and box then
        state.checkbox = {
            width = box:GetWidth(), height = box:GetHeight(), points = CaptureRegionPoints(box),
            labelPoints = widget.label and CaptureRegionPoints(widget.label) or nil,
            labelJustify = widget.label and widget.label:GetJustifyH() or nil,
            labelShown = widget.label and widget.label:IsShown(),
        }
        widget._exSettingsPresentation = options.presentation
        box:ClearAllPoints()
        if options.presentation == "card" then
            widget._exSettingsCardDescription = options.cardDescription == true
            widget._exSettingsCardIcon = options.cardIcon
            widget._exSettingsCardCheckSize = tonumber(options.cardCheckSize)
            widget._exSettingsCardTextSize = tonumber(options.cardTextSize)
            box:SetAllPoints(widget)
            if widget.label then widget.label:Hide() end
        elseif options.presentation == "pill" then
            widget:SetHeight(32)
            box:SetAllPoints(widget)
            if widget.label then
                widget.label:ClearAllPoints()
                widget.label:SetPoint("LEFT", widget, "LEFT", 27, 0)
                widget.label:SetPoint("RIGHT", widget, "RIGHT", -10, 0)
                widget.label:SetJustifyH("LEFT")
                widget.label:Hide()
            end
            if not box._exSettingsPillLabel then
                local visualLabel = EXUI:CreateVisualFontString(box._exModernCheckSurface,
                    EXFONTFRAME, "GameFontHighlight")
                visualLabel:SetJustifyH("LEFT")
                visualLabel:SetJustifyV("MIDDLE")
                box._exSettingsPillLabel = visualLabel
            end
            local visualLabel = box._exSettingsPillLabel
            visualLabel:SetText(widget.label and widget.label:GetText() or "")
            MODERN.ApplyTextRole(visualLabel, "title")
            visualLabel:Show()
        else
            box:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
            box:SetSize(40, 24)
        end
        PaintModernCheckbox(widget)
    end
    widget._exSettingsListVisualState = state
    return true
end

local function ResolveFontGroupHeight(width)
    return (tonumber(width) or 750) < 720 and 420 or 204
end

function EXUI:CreateFontGroup(parent, width, label, db, onUpdate, opts)
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    local offsetMin = tonumber(opts.offsetMin) or -200
    local offsetMax = tonumber(opts.offsetMax) or 200
    local shadowOffsetMin = tonumber(opts.shadowOffsetMin) or -20
    local shadowOffsetMax = tonumber(opts.shadowOffsetMax) or 20

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local defaultFont = (LSM and LSM.GetDefault and LSM:GetDefault("font")) or "Friz Quadrata TT"
    local defaults = {
        enabled = true,
        font = defaultFont,
        size = 14,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        x = 0, y = 0,
        shadow = false,
        shadowX = 1, shadowY = -1,
        shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1,
        autoWidth = false,
        maxWidth = 0,
        fixedWidth = 200,
        justifyH = "LEFT", justifyV = "MIDDLE",
        gradientEnabled = false,
        gradientStart = 0, gradientLength = 0,
        -- drawLayer / drawSubLevel 是旧存档导入兼容字段：不再补默认值、
        -- 不再暴露设置控件，所有 FontString 统一由 EXFONTFRAME 接管。
        rotation = 0,
    }
    for field, value in pairs(defaults) do
        if db[field] == nil then db[field] = value end
    end
    local groupWidth = width or 750
    local narrowLayout = groupWidth < 720
    -- 窄卡把右侧功能区移到字段下方，避免半宽 SettingsCard 产生负 Slider 宽度。
    local groupHeight = ResolveFontGroupHeight(groupWidth)
    -- 与 IconGroup 共用同一组层级；两种复合控件只保留内容差异。
    local palette = {
        panel = MC.panel,
        card = MC.raised,
        utility = MC.raised,
        border = MC.border,
        borderSoft = MC.border,
        text = MC.text,
        value = MC.blue,
        accent = MC.blue,
    }
    local group, isNew = AcquireCompositeGroup("CompositeFontGroup", parent)
    group._exCompositeLabel = label or L["文字设置"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        if group._exSetUnboundedWidthControls then group:_exSetUnboundedWidthControls(opts) end
        AttachCompositeRelease(group)
        -- FontGroup owns its internal surfaces; the generic reuse helper adds
        -- an outer panel that a freshly constructed FontGroup does not have.
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy

    local function EmitUpdate() CompositeEmitUpdate(group) end

    -- FontGroup 控件写入同一份 ModuleDB 后仅经统一通知重套既有表面。
    local function GetFontInputMetadata()
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateFontGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateFontGroup Grid write context requires pathPrefix", 2)
        end
        local commitAPI = EXUI.CommitModuleValue
        if type(commitAPI) ~= "function" then
            error("CreateFontGroup requires its Core commit API", 2)
        end
        return metadata.moduleKey, prefix
    end
    local function CommitFontValue(field, value, onWrite)
        local moduleKey, prefix = GetFontInputMetadata()
        local function Write(nextValue)
            db[field] = nextValue
            if onWrite then onWrite(nextValue) end
        end
        if moduleKey then
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. field,
                readValue = function() return db[field] end, writeValue = Write,
            }
            return EXUI:CommitModuleValue(payload, value)
        end
        Write(value)
        EmitUpdate()
        return true
    end
    local function CreateFontColorTransaction(colorKey)
        local fields = colorKey == "shadowColor"
            and { "shadowColorR", "shadowColorG", "shadowColorB", "shadowColorA" }
            or { "r", "g", "b", "a" }
        return function()
            -- ColorButton 是池化对象；必须在每次打开色盘时读取本次页面的合同，
            -- 不能把首次创建它的模块 key / path 闭包带到后续页面。
            local moduleKey, prefix = GetFontInputMetadata()
            if not moduleKey then return nil end
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. colorKey,
                readValue = function()
                    return { r = db[fields[1]], g = db[fields[2]], b = db[fields[3]], a = db[fields[4]] }
                end,
                writeValue = function(value)
                    db[fields[1]], db[fields[2]], db[fields[3]], db[fields[4]] = value.r, value.g, value.b, value.a
                end,
            }
            return EXUI:CreateModuleNotifyFlow(payload)
        end
    end
    local function SetFontValue(field, value, phase, onWrite)
        db[field] = value
        if onWrite then onWrite(value) end
        if phase ~= "live" then EmitUpdate() end
    end

    -- 旧 RegisterModuleLayout 的 FontGroup 可以声明 registry 生命周期。每次按下
    -- 都从当前 pooled group 的 opts 取合同，避免把上一个模块的 moduleKey/path
    -- 闭包带到本页面；拖动只写真实 DB 并 patch 已挂载 Panel，commit 才正式刷新。
    local function CreateFontPreviewLifecycle(field, onWrite)
        local activeOpts = group._exCompositeOpts or {}
        local transaction = activeOpts._exWriteContext
        if transaction ~= nil then
            if type(transaction) ~= "table" or type(transaction.moduleKey) ~= "string" or transaction.moduleKey == "" then
                error("CreateFontGroup requires Grid write context", 2)
            end
            local prefix = transaction.pathPrefix or transaction.path
            if type(prefix) ~= "string" or prefix == "" then
                error("CreateFontGroup Grid write context requires pathPrefix", 2)
            end
            local createAPI = EXUI.CreateModuleNotifyFlow
            if type(createAPI) ~= "function" then
                error("CreateFontGroup requires its Core transaction API", 2)
            end
            local function Write(value)
                db[field] = value
                if onWrite then onWrite(value) end
            end
            local payload = {
                moduleKey = transaction.moduleKey,
                path = prefix .. "." .. field,
                readValue = function() return db[field] end,
                writeValue = Write,
            }
            return createAPI(EXUI, payload)
        end
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateFontGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateFontGroup Grid write context requires pathPrefix", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateFontGroup requires CreateModuleNotifyFlow", 2)
        end
        local function Write(value)
            db[field] = value
            if onWrite then onWrite(value) end
        end
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = prefix .. "." .. field,
            readValue = function() return db[field] end,
            writeValue = Write,
            commit = function(value)
                Write(value)
                EmitUpdate()
            end,
        })
    end

    local function CreateFontSlider(host, sliderWidth, titleText, field, minValue, maxValue, value, stepValue, onWrite)
        local lifecycle
        local slider = self:CreateSlider(host, sliderWidth, titleText, minValue, maxValue, value, stepValue, nil, {
            onBegin = function()
                lifecycle = CreateFontPreviewLifecycle(field, onWrite)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(v)
                if lifecycle and lifecycle.onLive then lifecycle.onLive(v) else SetFontValue(field, v, "live", onWrite) end
            end,
            onCommit = function(v)
                -- 输入框不会触发原生轨道的 OnMouseDown；标准模块仍必须在这里
                -- 输入框同样读取当前 Grid 写入上下文。
                local inputOpts = group._exCompositeOpts or {}
                if not lifecycle and inputOpts._exWriteContext ~= nil then
                    lifecycle = CreateFontPreviewLifecycle(field, onWrite)
                end
                if lifecycle and lifecycle.onCommit then
                    lifecycle.onCommit(v)
                    lifecycle = nil
                else
                    SetFontValue(field, v, "commit", onWrite)
                end
            end,
        })
        return slider
    end
    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local content = CreateFrame("Frame", nil, group)
    content:SetSize(groupWidth, groupHeight)
    content:SetPoint("TOPLEFT", 0, 0)

    local padding, gap, controlsGap = 15, 12, 18
    local controlWidth = narrowLayout and (groupWidth - padding * 2)
        or math.min(416, math.max(364, math.floor(groupWidth * 0.40)))
    local metricsWidth = narrowLayout and (groupWidth - padding * 2)
        or (groupWidth - padding * 2 - controlsGap - controlWidth)
    local itemWidth = math.floor((metricsWidth - gap) / 2)
    local col1, col2 = padding, padding + itemWidth + gap
    -- 下拉框包含“标题 + 选择框”两层内容；卡片统一加高，
    -- 让三列卡片与右侧功能区的上下边界完整对齐。
    local row1, row2, row3 = -8, -76, -144
    local metricCardHeight = 60
    local controlX = narrowLayout and padding or (padding + metricsWidth + controlsGap)

    local sectionHeight = math.abs(row3 - row1) + metricCardHeight
    local controlY = narrowLayout and (row3 - metricCardHeight - gap) or row1

    local function CreateMetricCard(x, y)
        local card = CreateFrame("Frame", nil, content)
        card:SetPoint("TOPLEFT", x, y)
        card:SetSize(itemWidth, metricCardHeight)
        EXUI:SetControlSurface(card, 10, palette.card, palette.border)
        return card
    end

    -- 三行两列：颜色/大小、字体/X、描边/Y。
    local colorCard = CreateMetricCard(col1, row1)
    local sizeCard = CreateMetricCard(col2, row1)
    local fontCard = CreateMetricCard(col1, row2)
    local xCard = CreateMetricCard(col2, row2)
    local outlineCard = CreateMetricCard(col1, row3)
    local yCard = CreateMetricCard(col2, row3)
    group._exFontGroupMetricCards = { colorCard, sizeCard, fontCard, xCard, outlineCard, yCard }
    local sliderWidth = itemWidth - 20

    -- 字体、颜色和描边属于日常选项，直接展示在主面板，不再藏进弹窗。
    local colorBtn = self:CreateColorButton(colorCard, L["文字颜色"], db, "", true, EmitUpdate,
        { _changeFlow = CreateFontColorTransaction("color") })
    colorBtn:SetPoint("TOPLEFT", 10, -8)

    local fontDrop = self:CreateLSMDropdown(fontCard, "font", sliderWidth, L["字体样式"], db.font, function(key)
        CommitFontValue("font", key)
    end)
    -- 下拉框的标签绘制在本体上方；下移本体以让标签留在同一张 52px 卡片内。
    fontDrop:SetPoint("TOPLEFT", 10, -26)

    local outlineItems = { { L["无"], "" }, { L["细"], "OUTLINE" }, { L["粗"], "THICKOUTLINE" }, { L["无锯齿"], "MONOCHROME" } }
    local outlineDrop = self:CreateDropdown(outlineCard, sliderWidth, L["文字描边"], outlineItems, db.outline, function(v)
        CommitFontValue("outline", v)
    end)
    outlineDrop:SetPoint("TOPLEFT", 10, -26)

    local sizeSlider = CreateFontSlider(sizeCard, sliderWidth, L["文字大小"], "size", 4, 100, db.size, 1)
    sizeSlider:SetPoint("TOPLEFT", 10, -8)

    local xSlider = CreateFontSlider(xCard, sliderWidth, L["X 轴偏移"], "x", offsetMin, offsetMax, db.x, 1)
    xSlider:SetPoint("TOPLEFT", 10, -8)

    local ySlider = CreateFontSlider(yCard, sliderWidth, L["Y 轴偏移"], "y", offsetMin, offsetMax, db.y, 1)
    ySlider:SetPoint("TOPLEFT", 10, -8)

    -- 右侧功能区沿用 IconGroup 的 utility 卡片。
    local controlCard = CreateFrame("Frame", nil, content)
    controlCard:SetPoint("TOPLEFT", controlX, controlY)
    controlCard:SetSize(controlWidth, sectionHeight)
    EXUI:SetControlSurface(controlCard, 10, palette.utility, palette.border)
    group._exFontGroupActionCard = controlCard

    local showText = self:CreateCheckbox(controlCard, L["显示文字"], db.enabled, function(v)
        CommitFontValue("enabled", v)
    end)
    showText:SetPoint("TOPLEFT", 12, -4)
    showText:SetSize(156, 28)

    local shadowCheck = self:CreateCheckbox(controlCard, L["启用阴影"], db.shadow, function(v)
        CommitFontValue("shadow", v)
    end)
    shadowCheck:SetPoint("TOPLEFT", 12, -45)
    shadowCheck:SetSize(156, 28)

    local alignmentWidth = math.min(156, math.floor(controlWidth * 0.45))
    local justifyHItems = { { L["左对齐"], "LEFT" }, { L["居中"], "CENTER" }, { L["右对齐"], "RIGHT" } }
    local justifyH = self:CreateDropdown(controlCard, alignmentWidth, L["水平对齐"], justifyHItems, db.justifyH, function(v)
        CommitFontValue("justifyH", v)
    end)
    justifyH:SetPoint("TOPLEFT", 12, -100)

    local justifyVItems = { { L["顶部"], "TOP" }, { L["居中"], "MIDDLE" }, { L["底部"], "BOTTOM" } }
    local justifyV = self:CreateDropdown(controlCard, alignmentWidth, L["垂直对齐"], justifyVItems, db.justifyV, function(v)
        CommitFontValue("justifyV", v)
    end)
    justifyV:SetPoint("TOPLEFT", 12, -151)

    local gradientCheck = self:CreateCheckbox(controlCard, L["启用文字渐隐"], db.gradientEnabled, function(v)
        CommitFontValue("gradientEnabled", v)
    end)
    gradientCheck:SetPoint("TOPLEFT", 12, -127)
    gradientCheck:SetSize(176, 28)
    -- 当前文字 Region 没有可靠的跨版本渐隐/旋转实现；不把未消费字段暴露给用户。
    gradientCheck:Hide()

    local function CreatePopup(titleText, popupWidth, popupHeight)
        local popup = CreateCompositePopupHost(group, popupWidth, popupHeight)
        EXUI:SetControlSurface(popup, 10, palette.panel, palette.border)
        popup:Hide()
        local popupTitle = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontHighlight")
        popupTitle:SetPoint("TOPLEFT", 13, -9)
        popupTitle:SetText(titleText)
        StyleModernTitle(popupTitle)
        local close = self:CreateButton(popup, 28, 24, "×", function() popup:Hide() end, { compact = true })
        close:SetPoint("TOPRIGHT", -7, -4)
        return popup
    end

    local popupScale = 1.3
    local popupWidth = math.floor(400 * popupScale)
    local shadowPopup = CreatePopup(L["阴影设置"], popupWidth, 140)
    local layoutPopup = CreatePopup(L["布局设置"], popupWidth, 156)
    local advancedPopup = CreatePopup(L["高级文字设置"], popupWidth, 210)
    local popupPad, popupGap = 14, 18
    local popupItemW = math.floor((popupWidth - popupPad * 2 - popupGap) / 2)
    local popupCol2 = popupPad + popupItemW + popupGap

    local shadowColor = self:CreateColorButton(shadowPopup, L["阴影颜色"], db, "shadowColor", true, EmitUpdate,
        { _changeFlow = CreateFontColorTransaction("shadowColor") })
    shadowColor:SetPoint("TOPLEFT", popupPad, -46)
    local shadowX = CreateFontSlider(shadowPopup, popupItemW, L["阴影 X 偏移"], "shadowX", shadowOffsetMin, shadowOffsetMax, db.shadowX, 0.1)
    shadowX:SetPoint("TOPLEFT", popupCol2, -42)
    local shadowY = CreateFontSlider(shadowPopup, popupItemW, L["阴影 Y 偏移"], "shadowY", shadowOffsetMin, shadowOffsetMax, db.shadowY, 0.1)
    shadowY:SetPoint("TOPLEFT", popupCol2, -95)

    local autoWidthCheck
    local fixedWidth = CreateFontSlider(layoutPopup, popupItemW, L["固定宽度"], "fixedWidth", 0, 1000, db.fixedWidth, 1, function()
        -- 用户调整固定宽度即明确选择固定宽度模式；数值 0 的语义是“按文字自身宽度”。
        -- 不自动关掉该模式会让滑条看似没有作用。
        db.autoWidth = false
        if autoWidthCheck.SetChecked then autoWidthCheck:SetChecked(false) end
    end)
    fixedWidth:SetPoint("TOPLEFT", popupPad, -42)
    local maxWidth = CreateFontSlider(layoutPopup, popupItemW, L["最大宽度 (0=不限)"], "maxWidth", 0, 1000, db.maxWidth, 1)
    maxWidth:SetPoint("TOPLEFT", popupCol2, -42)
    autoWidthCheck = self:CreateCheckbox(layoutPopup, L["自动宽度"], db.autoWidth, function(v)
        CommitFontValue("autoWidth", v)
    end)
    autoWidthCheck:SetPoint("TOPLEFT", popupPad, -96)
    autoWidthCheck:SetSize(156, 28)

    local gradientStart = CreateFontSlider(advancedPopup, popupItemW, L["渐隐起点"], "gradientStart", 0, 1000, db.gradientStart, 1)
    gradientStart:SetPoint("TOPLEFT", popupPad, -42)
    local gradientLength = CreateFontSlider(advancedPopup, popupItemW, L["渐隐长度"], "gradientLength", 0, 1000, db.gradientLength, 1)
    gradientLength:SetPoint("TOPLEFT", popupCol2, -42)
    local rotation = CreateFontSlider(advancedPopup, popupItemW, L["文字旋转"], "rotation", -180, 180, db.rotation, 1)
    rotation:SetPoint("TOPLEFT", popupPad, -150)

    local function TogglePopup(popup, anchor)
        local shouldShow = not popup:IsShown()
        shadowPopup:Hide()
        layoutPopup:Hide()
        advancedPopup:Hide()
        if shouldShow then
            popup:ClearAllPoints()
            popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
            popup:Show()
        end
    end
    local function CreateUtilityButton(text, buttonWidth, onClick)
        return EXUI:CreateButton(controlCard, buttonWidth, 28, text, onClick, { variant = "soft" })
    end

    local buttonWidth = math.min(187, math.floor(controlWidth * 0.45))
    local shadowButton = CreateUtilityButton(L["阴影设置"], buttonWidth, function(self) TogglePopup(shadowPopup, self) end)
    shadowButton:SetPoint("TOPRIGHT", controlCard, "TOPRIGHT", -10, -4)
    local layoutButton = CreateUtilityButton(L["布局设置"], buttonWidth, function(self) TogglePopup(layoutPopup, self) end)
    layoutButton:SetPoint("TOPRIGHT", controlCard, "TOPRIGHT", -10, -45)
    local advancedButton = CreateUtilityButton(L["高级设置"], buttonWidth, function(self) TogglePopup(advancedPopup, self) end)
    advancedButton:SetPoint("TOPRIGHT", controlCard, "TOPRIGHT", -10, -86)

    -- 单行公告等明确声明为无界文本的模块不能暴露会制造宽度限制的控件。
    -- 该组会被对象池复用，因而每次绑定都必须显式恢复/隐藏，不能把上一个
    -- 无界模块的可见性残留给普通文字模块。
    group._exFontAutoWidthCheck = autoWidthCheck
    group._exFontLayoutButton = layoutButton
    group._exSetUnboundedWidthControls = function(self, activeOpts)
        local unbounded = type(activeOpts) == "table" and activeOpts.unboundedWidth == true
        if self._exFontAutoWidthCheck then self._exFontAutoWidthCheck:SetShown(not unbounded) end
        if self._exFontLayoutButton then self._exFontLayoutButton:SetShown(not unbounded) end
    end
    group:_exSetUnboundedWidthControls(opts)

    group:HookScript("OnHide", function()
        shadowPopup:Hide()
        layoutPopup:Hide()
        advancedPopup:Hide()
    end)
    RegisterCompositeControl(group, colorBtn, "", "color")
    RegisterCompositeControl(group, fontDrop, "font", "dropdown")
    RegisterCompositeControl(group, outlineDrop, "outline", "dropdown")
    RegisterCompositeControl(group, sizeSlider, "size", "slider")
    RegisterCompositeControl(group, xSlider, "x", "slider")
    RegisterCompositeControl(group, ySlider, "y", "slider")
    RegisterCompositeControl(group, showText, "enabled", "check")
    RegisterCompositeControl(group, shadowCheck, "shadow", "check")
    RegisterCompositeControl(group, autoWidthCheck, "autoWidth", "check")
    RegisterCompositeControl(group, gradientCheck, "gradientEnabled", "check")
    RegisterCompositeControl(group, shadowColor, "shadowColor", "color")
    RegisterCompositeControl(group, shadowX, "shadowX", "slider")
    RegisterCompositeControl(group, shadowY, "shadowY", "slider")
    -- 固定宽度是 FontGroup 的公开控件语义：调整它必定切出自动宽度模式。
    -- 旧页面仍由上面的 Slider callback 保持此行为；标准生命周期接管时则
    -- 读取这份声明式 metadata，在同一 DB、同一次 commit 写入 autoWidth=false。
    RegisterCompositeControl(group, fixedWidth, "fixedWidth", "slider", {
        commitWrites = {
            { path = "autoWidth", value = false },
        },
    })
    RegisterCompositeControl(group, maxWidth, "maxWidth", "slider")
    RegisterCompositeControl(group, justifyH, "justifyH", "dropdown")
    RegisterCompositeControl(group, justifyV, "justifyV", "dropdown")
    RegisterCompositeControl(group, gradientStart, "gradientStart", "slider")
    RegisterCompositeControl(group, gradientLength, "gradientLength", "slider")
    RegisterCompositeControl(group, rotation, "rotation", "slider")
    group._exCompositePopups = { shadowPopup, layoutPopup, advancedPopup }

    group._fontGroupDb = proxy
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local nextNarrow = nextWidth < 720
        nextHeight = ResolveFontGroupHeight(nextWidth)
        local nextControlWidth = nextNarrow and (nextWidth - padding * 2)
            or math.min(416, math.max(364, math.floor(nextWidth * 0.40)))
        local nextMetricsWidth = nextNarrow and (nextWidth - padding * 2)
            or (nextWidth - padding * 2 - controlsGap - nextControlWidth)
        local nextItemWidth = math.floor((nextMetricsWidth - gap) / 2)
        local nextCol2 = padding + nextItemWidth + gap
        local nextControlX = nextNarrow and padding or (padding + nextMetricsWidth + controlsGap)
        local nextControlY = nextNarrow and (row3 - metricCardHeight - gap) or row1
        local nextSliderWidth = nextItemWidth - 20

        self:SetSize(nextWidth, nextHeight)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, nextHeight)
        EXUI:ClearControlSurface(self)
        for _, card in ipairs({ colorCard, fontCard, outlineCard }) do card:SetSize(nextItemWidth, metricCardHeight) end
        for _, card in ipairs({ sizeCard, xCard, yCard }) do card:SetSize(nextItemWidth, metricCardHeight) end
        colorCard:ClearAllPoints(); colorCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row1)
        sizeCard:ClearAllPoints(); sizeCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row1)
        fontCard:ClearAllPoints(); fontCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row2)
        xCard:ClearAllPoints(); xCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row2)
        outlineCard:ClearAllPoints(); outlineCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row3)
        yCard:ClearAllPoints(); yCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row3)
        for _, slider in ipairs({ sizeSlider, xSlider, ySlider }) do slider:SetWidth(nextSliderWidth) end
        fontDrop:SetWidth(nextSliderWidth); outlineDrop:SetWidth(nextSliderWidth)
        colorBtn:SetWidth(nextSliderWidth)
        controlCard:ClearAllPoints(); controlCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextControlX, nextControlY)
        controlCard:SetSize(nextControlWidth, math.abs(row3 - row1) + metricCardHeight)
        local nextButtonWidth = math.min(187, math.floor(nextControlWidth * 0.45))
        local nextAlignmentWidth = math.min(156, math.floor(nextControlWidth * 0.45))
        justifyH:SetWidth(nextAlignmentWidth); justifyV:SetWidth(nextAlignmentWidth)
        shadowButton:SetWidth(nextButtonWidth); layoutButton:SetWidth(nextButtonWidth); advancedButton:SetWidth(nextButtonWidth)
        -- Run after every layout, including a same-size pooled reuse: parent
        -- scale and cached surface geometry can change without OnSizeChanged.
        -- Reuse the existing skins; SetControlSurface explicitly lays them out.
        for _, card in ipairs(self._exFontGroupMetricCards) do
            EXUI:SetControlSurface(card, 10, palette.card, palette.border)
        end
        EXUI:SetControlSurface(controlCard, 10, palette.utility, palette.border)
        for _, popup in ipairs(self._exCompositePopups or {}) do
            EXUI:SetControlSurface(popup, 10, palette.panel, palette.border)
        end
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    -- 预览画布拖动会直接写入 db；提供统一回刷入口，让下方 X/Y 滑杆
    -- 立即同步，而不是下一次手动调整时从旧值跳回去。
    group.RefreshFromDB = function(self)
        BindCompositeGroup(self, self._exCompositeDb, self._exCompositeOnUpdate, self._exCompositeOpts)
    end
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 12. 音效设置复合组件 (Sound Settings Group)
-- 扁平前缀字段：<key>Enabled/Source/Label/LSM/Path/TtsText/Channel。
-- 来源集合由调用方 opts.sources 声明；未声明时绝不开放语音包。
-- =========================================================
local function ResolveSoundGroupSecondaryCheckbox(opts)
    local spec = type(opts) == "table" and opts.secondaryCheckbox or nil
    if spec == nil then return nil end
    if type(spec) ~= "table" then
        error("soundgroup secondaryCheckbox must be table", 3)
    end
    for field in pairs(spec) do
        if field ~= "key" and field ~= "label" then
            error("soundgroup secondaryCheckbox only supports key/label", 3)
        end
    end
    if type(spec.key) ~= "string" or spec.key == "" then
        error("soundgroup secondaryCheckbox requires non-empty key", 3)
    end
    if type(spec.label) ~= "string" or spec.label == "" then
        error("soundgroup secondaryCheckbox requires non-empty label", 3)
    end
    return spec
end

-- SoundGroup 的测量和控件重排必须共用同一份纯布局结果。额外复选框由组件
-- 自己占据第二行，因而能与“启用”使用完全相同的父级和水平内边距；未声明
-- secondaryCheckbox 的现有调用者仍保持无额外行时的 64/140 高度。
function EXUI:BuildSoundGroupLayout(width, opts)
    local groupWidth = math.max(1, tonumber(width) or 750)
    local secondaryCheckbox = ResolveSoundGroupSecondaryCheckbox(opts)
    local extraHeight = secondaryCheckbox and 56 or 0
    if groupWidth >= 760 then
        return {
            height = 64 + extraHeight,
            isWide = true,
            secondaryCheckbox = secondaryCheckbox,
            enabledY = -4,
            secondaryY = -60,
            sourceY = -4,
            channelY = -4,
            testY = -4,
        }
    end
    return {
        height = 140 + extraHeight,
        isWide = false,
        secondaryCheckbox = secondaryCheckbox,
        enabledY = -8,
        secondaryY = -45,
        sourceY = -45 - extraHeight,
        channelY = -101 - extraHeight,
        testY = -104 - extraHeight,
    }
end

function EXUI:CreateSoundGroup(parent, width, label, db, key, onUpdate, opts)
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    key = tostring(key or "sound")

    local function HasUsablePackItems(items)
        if type(items) ~= "table" then return false end
        for _, item in ipairs(items) do
            if type(item) == "string" and item ~= "" then return true end
            if type(item) == "table" and item[1] ~= nil and item[2] ~= nil then return true end
        end
        return false
    end
    local function ResolveInitialPackItems()
        local packItems = opts.packItems
        if type(packItems) == "function" then
            local ok, result = pcall(packItems, db, key)
            packItems = ok and result or nil
        end
        return packItems
    end

    local allowed = {}
    local sources = {}
    local requestedSources = type(opts.sources) == "table" and opts.sources or { "lsm", "file", "tts" }
    local packAvailable = HasUsablePackItems(ResolveInitialPackItems())
    for _, source in ipairs(requestedSources) do
        if source == "pack" and not packAvailable then
            -- pack 没有本轮可用条目时不能成为可选来源，更不能被选为默认值。
        elseif (source == "pack" or source == "lsm" or source == "file" or source == "tts") and not allowed[source] then
            allowed[source] = true
            sources[#sources + 1] = source
        end
    end
    if #sources == 0 then
        sources = { "lsm", "file", "tts" }
        allowed = { lsm = true, file = true, tts = true }
    end

    local sourceItems = {
        pack = { L["语音包"], "pack" },
        lsm = { L["LSM音效"], "lsm" },
        file = { L["自定义路径"], "file" },
        tts = { L["TTS语音"], "tts" },
    }
    local dropdownSources = {}
    local defaultSource
    for _, source in ipairs(sources) do
        dropdownSources[#dropdownSources + 1] = sourceItems[source]
        if not defaultSource and source ~= "pack" then defaultSource = source end
    end
    defaultSource = defaultSource or sources[1]

    local group
    local suffix = {
        enabled = "Enabled", source = "Source", label = "Label", lsm = "LSM",
        path = "Path", tts = "TtsText", channel = "Channel",
    }
    local function Field(name) return ((group and group._soundGroupKey) or key) .. suffix[name] end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local defaultLSM = (LSM and LSM.GetDefault and LSM:GetDefault("sound")) or "None"
    local defaults = {
        enabled = false, source = defaultSource, label = "", lsm = defaultLSM,
        path = "", tts = "", channel = "Master",
    }
    for name, value in pairs(defaults) do
        local field = Field(name)
        if db[field] == nil then db[field] = value end
    end
    if not allowed[db[Field("source")]] then db[Field("source")] = defaultSource end

    -- 宽版标准页面统一使用一行：启用 / 来源 / 当前音效 / 输出 / 试听。
    -- 窄宿主仍保留两列，以免控件相互覆盖。
    local groupWidth = width or 750
    local soundLayout = self:BuildSoundGroupLayout(groupWidth, opts)
    local groupHeight = soundLayout.height
    local isNew
    group, isNew = AcquireCompositeGroup("CompositeSoundGroup", parent)
    group._exCompositeLabel = label or L["音效设置"]
    group._soundGroupKey = key
    group._soundState = {
        allowed = allowed, defaultSource = defaultSource, dropdownSources = dropdownSources,
        requestedSources = requestedSources,
    }
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        group:_exCompositeConfigure()
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        EXUI:ClearControlSurface(group)
        return group
    end

    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local content = CreateFrame("Frame", nil, group)
    content:SetPoint("TOPLEFT", 0, 0)
    local settingsCard = CreateFrame("Frame", nil, content)

    local function ActiveDB() return type(group._exCompositeDb) == "table" and group._exCompositeDb or nil end
    local function SetValue(name, value)
        local active = ActiveDB()
        if active then active[Field(name)] = value end
    end
    local function GetValue(name)
        local active = ActiveDB()
        return active and active[Field(name)] or defaults[name]
    end
    local function EmitUpdate() CompositeEmitUpdate(group) end

    local enabled = self:CreateCheckbox(settingsCard, L["启用"], GetValue("enabled"), function(value)
        SetValue("enabled", value); EmitUpdate()
    end)
    local secondaryCheckbox = self:CreateCheckbox(settingsCard, "", false, function(value)
        local activeOpts = group._exCompositeOpts or {}
        local spec = ResolveSoundGroupSecondaryCheckbox(activeOpts)
        local active = ActiveDB()
        if spec and active and CompositePathSet(active, spec.key, value) then
            EmitUpdate()
        end
    end)
    local sourceDrop = self:CreateDropdown(settingsCard, 200, L["音效来源"], dropdownSources, GetValue("source"), function(value)
        SetValue("source", value)
        group:_exCompositeConfigure()
        EmitUpdate()
    end)
    local packDrop = self:CreateDropdown(settingsCard, 200, L["语音包标签"], {}, GetValue("label"), function(value)
        SetValue("label", value); EmitUpdate()
    end)
    local lsmDrop = self:CreateLSMSoundDropdown(settingsCard, 200, L["选择音效 (LSM)"], GetValue("lsm"), function(value)
        SetValue("lsm", value); EmitUpdate()
    end)
    lsmDrop._mediaType = "sound"
    local pathInput = self:CreateEditBox(settingsCard, GetValue("path"), 200, 28, L["自定义路径"], {
        placeholder = L["示例: Interface\\AddOns\\MySound\\test.ogg"],
        onEnter = function(value) SetValue("path", value); EmitUpdate() end,
        onEditFocusLost = function(value) SetValue("path", value); EmitUpdate() end,
    })
    local ttsInput = self:CreateEditBox(settingsCard, GetValue("tts"), 200, 28, L["TTS文本"], {
        placeholder = L["输入要朗读的文字"],
        onEnter = function(value) SetValue("tts", value); EmitUpdate() end,
        onEditFocusLost = function(value) SetValue("tts", value); EmitUpdate() end,
    })
    local channels = {
        { L["主音量 (Master)"], "Master" }, { L["音效 (SFX)"], "SFX" },
        { L["环境 (Ambience)"], "Ambience" }, { L["音乐 (Music)"], "Music" },
        { L["对话 (Dialog)"], "Dialog" },
    }
    local channelDrop = self:CreateDropdown(settingsCard, 200, L["音频通道"], channels, GetValue("channel"), function(value)
        SetValue("channel", value); EmitUpdate()
    end)
    local testButton = self:CreateButton(settingsCard, 110, 28, opts.testLabel or L["试听"], function()
        local activeOpts = group._exCompositeOpts or {}
        if type(activeOpts.onTest) == "function" then
            activeOpts.onTest(group._exCompositeDb, group._soundGroupKey)
            return
        end
        -- Module declarations are pure data, so Grid soundgroup cannot carry a
        -- callback.  An explicit testButtonKey reuses the established module
        -- click-state contract; the module still owns the actual playback.
        local clickKey = activeOpts.testButtonKey
        local writeContext = activeOpts._exWriteContext
        if type(clickKey) == "string" and clickKey ~= ""
            and type(writeContext) == "table" and type(writeContext.moduleKey) == "string"
            and writeContext.moduleKey ~= "" then
            ExwindTools:UpdateState(writeContext.moduleKey .. ".ButtonClicked", {
                key = clickKey,
                fullPath = writeContext.pathPrefix,
                ts = GetTime(),
            })
        end
    end)

    enabled._soundField = "enabled"
    sourceDrop._soundField = "source"
    packDrop._soundField = "label"
    lsmDrop._soundField = "lsm"
    pathInput._soundField = "path"
    ttsInput._soundField = "tts"
    channelDrop._soundField = "channel"
    RegisterCompositeControl(group, enabled, Field("enabled"), "check")
    RegisterCompositeControl(group, sourceDrop, Field("source"), "dropdown")
    RegisterCompositeControl(group, packDrop, Field("label"), "dropdown")
    RegisterCompositeControl(group, lsmDrop, Field("lsm"), "dropdown")
    RegisterCompositeControl(group, pathInput, Field("path"), "edit")
    RegisterCompositeControl(group, ttsInput, Field("tts"), "edit")
    RegisterCompositeControl(group, channelDrop, Field("channel"), "dropdown")

    local function ResolvePackItems()
        local activeOpts = group._exCompositeOpts or {}
        local packItems = activeOpts.packItems
        if type(packItems) == "function" then
            local ok, result = pcall(packItems, group._exCompositeDb, group._soundGroupKey)
            packItems = ok and result or nil
        end
        return type(packItems) == "table" and packItems or {}
    end
    local function RebuildSourceState(state, packItems)
        local nextAllowed, nextItems, nextDefault = {}, {}, nil
        for _, candidate in ipairs(state.requestedSources or {}) do
            if candidate == "pack" and not HasUsablePackItems(packItems) then
                -- 动态 provider 本轮为空时，pack 必须从来源菜单消失。
            elseif (candidate == "pack" or candidate == "lsm" or candidate == "file" or candidate == "tts") and not nextAllowed[candidate] then
                nextAllowed[candidate] = true
                nextItems[#nextItems + 1] = sourceItems[candidate]
                if not nextDefault and candidate ~= "pack" then nextDefault = candidate end
            end
        end
        if #nextItems == 0 then
            nextAllowed = { lsm = true, file = true, tts = true }
            nextItems = { sourceItems.lsm, sourceItems.file, sourceItems.tts }
            nextDefault = "lsm"
        end
        state.allowed, state.dropdownSources, state.defaultSource = nextAllowed, nextItems, nextDefault or nextItems[1][2]
    end
    group._exCompositeConfigure = function(self)
        local state = self._soundState or {}
        local activeOpts = self._exCompositeOpts or {}
        local secondarySpec = ResolveSoundGroupSecondaryCheckbox(activeOpts)
        if testButton.SetText then testButton:SetText(activeOpts.testLabel or L["试听"]) end
        secondaryCheckbox:SetShown(secondarySpec ~= nil)
        if secondarySpec then
            secondaryCheckbox.label:SetText(secondarySpec.label)
            secondaryCheckbox:SetChecked(CompositePathValue(self._exCompositeDb, secondarySpec.key) == true)
        end
        -- 同一 CompositeHost 可被不同 key/来源集合的页面复用；先将每个已建立
        -- 控件的扁平字段映射重绑到本轮 key，再刷新显示，不能沿用上一页路径。
        for _, entry in ipairs(self._exCompositeControls or {}) do
            local fieldName = entry.control and entry.control._soundField
            if fieldName then
                entry.path = Field(fieldName)
                RefreshCompositeControl(entry, self._exCompositeDb)
            end
        end
        local packItems = ResolvePackItems()
        RebuildSourceState(state, packItems)
        local source = GetValue("source")
        if not state.allowed or not state.allowed[source] then
            source = state.defaultSource
            SetValue("source", source)
        end
        sourceDrop._items = state.dropdownSources or {}
        sourceDrop._currentValue = source
        SetDropdownDisplayText(sourceDrop, CompositeDropdownText(source, sourceDrop._items) or L["请选择..."])
        packDrop._items = packItems
        packDrop._currentValue = GetValue("label")
        SetDropdownDisplayText(packDrop, CompositeDropdownText(packDrop._currentValue, packItems) or L["请选择..."])
        if #packItems > 0 then
            if packDrop.Enable then packDrop:Enable() end
        elseif packDrop.Disable then
            packDrop:Disable()
        end
        if packDrop.EnableMouse then packDrop:EnableMouse(#packItems > 0) end
        packDrop:SetShown(source == "pack")
        lsmDrop:SetShown(source == "lsm")
        pathInput:SetShown(source == "file")
        ttsInput:SetShown(source == "tts")
    end
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local layout = EXUI:BuildSoundGroupLayout(nextWidth, self._exCompositeOpts)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, math.max(1, nextHeight))
        EXUI:ClearControlSurface(self)
        if layout.isWide then
            -- 对应在线编辑器的标准比例：20 / 35 / 62 / 30 / 25。
            -- 当前音效位只会显示 LSM、路径或 TTS 三者之一。
            local padding = 15
            local scale = math.max(1, (nextWidth - padding * 2) / 193)
            local checkWidth = math.floor(20 * scale)
            local sourceWidth = math.floor(35 * scale)
            local soundWidth = math.floor(62 * scale)
            local channelWidth = math.floor(30 * scale)
            local testWidth = math.floor(25 * scale)
            local sourceX = padding + 24 * scale
            local soundX = padding + 62 * scale
            local channelX = padding + 128 * scale
            local testX = padding + 168 * scale
            settingsCard:ClearAllPoints(); settingsCard:SetPoint("TOPLEFT", content, "TOPLEFT")
            settingsCard:SetSize(nextWidth, math.max(1, nextHeight))

            enabled:ClearAllPoints(); enabled:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", padding, layout.enabledY); enabled:SetWidth(checkWidth)
            secondaryCheckbox:ClearAllPoints(); secondaryCheckbox:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", padding, layout.secondaryY); secondaryCheckbox:SetWidth(checkWidth)
            sourceDrop:ClearAllPoints(); sourceDrop:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", sourceX, layout.sourceY); sourceDrop:SetWidth(sourceWidth)
            for _, control in ipairs({ packDrop, lsmDrop, pathInput, ttsInput }) do
                control:ClearAllPoints(); control:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", soundX, layout.sourceY); control:SetWidth(soundWidth)
            end
            channelDrop:ClearAllPoints(); channelDrop:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", channelX, layout.channelY); channelDrop:SetWidth(channelWidth)
            testButton:ClearAllPoints(); testButton:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", testX, layout.testY); testButton:SetWidth(testWidth)
            return
        end

        local padding, gap = 15, 18
        local itemWidth = math.max(140, math.floor((nextWidth - padding * 2 - gap) / 2))
        local col1, col2 = padding, padding + itemWidth + gap
        settingsCard:ClearAllPoints(); settingsCard:SetPoint("TOPLEFT", content, "TOPLEFT", padding, -8)
        settingsCard:SetSize(nextWidth - padding * 2,
            math.max(1, nextHeight - 16))
        enabled:ClearAllPoints(); enabled:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", 10, layout.enabledY)
        secondaryCheckbox:ClearAllPoints(); secondaryCheckbox:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", 10, layout.secondaryY)
        sourceDrop:ClearAllPoints(); sourceDrop:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", col1, layout.sourceY); sourceDrop:SetWidth(itemWidth)
        for _, control in ipairs({ packDrop, lsmDrop, pathInput, ttsInput }) do
            control:ClearAllPoints(); control:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", col2, layout.sourceY); control:SetWidth(itemWidth)
        end
        channelDrop:ClearAllPoints(); channelDrop:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", col1, layout.channelY); channelDrop:SetWidth(itemWidth)
        testButton:ClearAllPoints(); testButton:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", col2, layout.testY)
    end
    group:_exCompositeConfigure()
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end


-- =========================================================
-- 13. 输入框与多行文本框 (EditBox)
-- Options: .bgColor, .borderColor, .textColor
-- =========================================================
function EXUI:CreateEditBox(parent, text, w, h, labelText, options)
    local isMultiLine = h > 40
    options = options or {}

    local function SetPixelSize(region, width, height)
        local pixelUtil = _G.PixelUtil
        if pixelUtil and pixelUtil.SetSize then
            pixelUtil.SetSize(region, width, height, 1, 1)
        else
            region:SetSize(width, height)
        end
    end

    local EXFactory = _G.ExwindFactory

    -- [v4.3.2] 单行模式走池化通道
    if EXFactory and not isMultiLine then
        local container = self:AcquireControl("GridInput", parent)

        -- 清理旧回调
        container:SetScript("OnTextChanged", nil)
        container:SetScript("OnEditFocusLost", nil)
        container:SetScript("OnEnterPressed", nil)

        -- 兼容旧接口
        container.editBox = container
        if container.Enable then container:Enable() end
        self:ApplyControlAppearance(container)

        -- 基础配置
        -- GridInput is shared by ordinary text fields and quantity editors.
        -- Quantity editors deliberately switch their own lease to CENTER, so
        -- every ordinary single-line lease must restore the visual baseline.
        -- This changes geometry only: cursor, accepted input and callbacks are
        -- left untouched.
        container:SetJustifyH("LEFT")
        container:SetJustifyV("MIDDLE")
        SetPixelSize(container, w or 180, h or 28)
        if container.EnableMouse then
            container:EnableMouse(true)
        end
        container:SetAutoFocus(false)
        container:SetText(text or "")
        container:SetCursorPosition(0)

        -- 标签设置
        if labelText then
            local label = container.label
            label:Show()
            label:SetText(labelText)
            label:ClearAllPoints()

            if options.labelPos == "left" then
                label:SetPoint("RIGHT", container, "LEFT", -5, 0)
                label:SetJustifyH("RIGHT")
            else
                label:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 3)
                label:SetJustifyH("LEFT")
            end

        else
            container.label:Hide()
        end

        -- 占位符
        if not container.placeholder then
            container.placeholder = EXUI:CreateVisualFontString(container, EXFONTFRAME)
            container.placeholder:SetPoint("LEFT", 3, 0)
        end
        MODERN.ApplyTextRole(container.placeholder, "hint")
        container.placeholder:SetText(options.placeholder or "")

        local function UpdatePlaceholder()
            if container:GetText() == "" then container.placeholder:Show() else container.placeholder:Hide() end
        end
        UpdatePlaceholder()

        -- 回调逻辑
        container:SetScript("OnTextChanged", function(self, userInput)
            UpdatePlaceholder()
            if options.onChanged then options.onChanged(self:GetText(), userInput) end
        end)

        container:SetScript("OnEditFocusGained", nil)

        container:SetScript("OnEditFocusLost", function(self)
            UpdatePlaceholder()
            if options.onEditFocusLost then options.onEditFocusLost(self:GetText()) end
        end)

        container:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            if options.onEnter then options.onEnter(self:GetText()) end
        end)

        container:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        return container
    end

    -- =========================================================
    -- 多行模式或无工厂模式 (Legacy Path)
    -- =========================================================

    -- 1. 主容器
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container._exMultilineInput = true
    SetPixelSize(container, w, h)

    -- 简化的标签逻辑
    if labelText then
        local label = EXUI:CreateVisualFontString(container, EXFONTFRAME)
        if options.labelPos == "left" then
            label:SetPoint("RIGHT", container, "LEFT", -5, 0)
            label:SetJustifyH("RIGHT")
        else
            label:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 3)
        end
        StyleModernTitle(label)
        label:SetText(labelText)
        container.label = label
    end

    -- 多行模式特有逻辑: ScrollFrame
    local eb
    local sf = CreateFrame("ScrollFrame", nil, container)
    sf:SetPoint("TOPLEFT", 5, -5)
    sf:SetPoint("BOTTOMRIGHT", -5, 5)

    -- [Fix] 使用一个容器 Frame 作为 ScrollChild，EditBox 放在里面
    -- 这样可以更精确控制 EditBox 的行为，避免 ScrollFrame 对 EditBox 的奇异约束
    local scrollContent = CreateFrame("Frame", nil, sf)
    scrollContent:SetSize(w - 20, 2000) -- 给一个巨大的高度，确保能滚动
    sf:SetScrollChild(scrollContent)

    eb = CreateFrame("EditBox", nil, scrollContent)
    eb:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, 0)
    eb:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, 0)
    eb:SetHeight(2000) -- 让 EditBox 同样巨大
    eb:SetMultiLine(true)
    eb:SetTextInsets(4, 4, 4, 4)
    eb:SetJustifyH("LEFT")
    eb:SetJustifyV("TOP") -- 必须顶部对齐！

    -- 自动滚动逻辑
    eb:SetScript("OnCursorChanged", function(self, x, y, width, height)
        local vs = sf:GetVerticalScroll()
        local h = sf:GetHeight()
        -- y 是相对于 EditBox 顶部的负值
        local cursorY = -y

        if cursorY < vs then
            sf:SetVerticalScroll(cursorY)
        elseif (cursorY + height) > (vs + h) then
            sf:SetVerticalScroll(cursorY + height - h)
        end
    end)
    sf:EnableMouseWheel(true)
    container.scrollFrame = sf

    -- [Fix] 增加点击区域屏蔽，确保点击容器任何地方都能聚焦 EditBox
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)

    -- [Fix] 解决多行输入框拦截滚轮的问题：将滚动事件透传给父级
    local function ForwardWheelToPage(_, delta)
        local parentScroll = EXUI.RightScrollFrame
        if parentScroll and parentScroll:IsShown() then
            local current = parentScroll:GetVerticalScroll()
            parentScroll:SetVerticalScroll(current - (delta * 25))
        end
    end
    sf:SetScript("OnMouseWheel", ForwardWheelToPage)
    eb:EnableMouseWheel(true)
    eb:HookScript("OnMouseWheel", ForwardWheelToPage)

    eb:SetAutoFocus(false)
    MODERN.ApplyTextRole(eb, "fieldValue")
    eb:SetText(text or "")
    eb:SetTextInsets(8, 8, 8, 8) -- 增加边距，更有呼吸感

    -- [Fix] 更新高度以适应内容，确保滚动条逻辑生效
    eb:SetScript("OnTextChanged", function(self, userInput)
        -- 自动伸缩高度：取可视高度和内容高度的较大者
        local contentH = self:GetNumLetters() * 15 -- 粗略估算，或者直接保持固定大高度
        -- 更好的做法：不做自动伸缩，只依赖 ScrollFrame。但为了点击体验，保持 SetSize(..., h)
        if options.onChanged then options.onChanged(self:GetText(), userInput) end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", nil)
    eb:SetScript("OnEditFocusLost", function(self)
        if options.onEditFocusLost then options.onEditFocusLost(self:GetText()) end
    end)

    container.editBox = eb
    function container:GetText() return self.editBox:GetText() end

    function container:SetText(t) self.editBox:SetText(t or "") end

    return container
end

-- =========================================================
-- 14. 交互式预览画板 (Interactive Preview Canvas)
-- =========================================================
function EXUI:CreatePreviewCanvas(parent, width, height, elementsData, callbacks)
    local canvas, isNew = AcquireCompositeGroup("CompositePreviewCanvas", parent)
    canvas._previewCallbacks = callbacks or {}
    canvas._previewData = elementsData or {}
    canvas:SetSize(width, height)
    if not isNew then
        canvas.selectedKey = nil
        canvas:UpdateElements(canvas._previewData)
        ReflowCompositeGroup(canvas, width, height)
        AttachCompositeRelease(canvas)
        return canvas
    end

    -- 画板背景 (网格或深色背景)
    canvas:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tileSize = 16,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    EXUI:ApplyModernPanel(canvas, true)

    -- 网格参考线 (辅助对齐)
    local gridLine = EXUI:CreateVisualTexture(canvas, EXBACKGROUNDFRAME)
    gridLine:SetAllPoints()
    gridLine:SetColorTexture(1, 1, 1, 0.05)

    local centerLineH = EXUI:CreateVisualTexture(canvas, EXBASEFRAME)
    centerLineH:SetHeight(1)
    centerLineH:SetPoint("LEFT"); centerLineH:SetPoint("RIGHT")
    centerLineH:SetPoint("CENTER")
    centerLineH:SetColorTexture(1, 1, 1, 0.2)

    local centerLineV = EXUI:CreateVisualTexture(canvas, EXBASEFRAME)
    centerLineV:SetWidth(1)
    centerLineV:SetPoint("TOP"); centerLineV:SetPoint("BOTTOM")
    centerLineV:SetPoint("CENTER")
    centerLineV:SetColorTexture(1, 1, 1, 0.2)

    canvas.elements = {}
    canvas.selectedKey = nil

    -- 内部方法：创建/更新子元素
    function canvas:UpdateElements(dataMap)
        -- 1. 隐藏所有旧元素
        for _, el in pairs(self.elements) do el:Hide() end

        -- 2. 遍历数据创建/显示元素
        for key, data in pairs(dataMap) do
            if data.enabled then
                local el = self.elements[key]
                if not el then
                    local elementKey = key
                    el = CreateFrame("Button", nil, self, "BackdropTemplate")
                    el:SetSize(100, 24) -- 默认基准大小
                    el:SetBackdrop(nil)

                    el.text = EXUI:CreateVisualFontString(el, EXFONTFRAME, "GameFontHighlightSmall")
                    el.text:SetPoint("CENTER")

                    -- 拖拽逻辑
                    el:SetMovable(true)
                    el:RegisterForDrag("LeftButton")
                    el:SetScript("OnDragStart", function(s)
                        if self.selectedKey ~= elementKey then self:Select(elementKey) end
                        s:StartMoving()
                    end)
                    el:SetScript("OnDragStop", function(s)
                        s:StopMovingOrSizing()
                        local cx, cy = self:GetCenter()
                        local ex, ey = s:GetCenter()

                        if not cx or not ex then return end

                        -- 计算相对坐标 (相对于 Canvas 中心)
                        local relX = ex - cx
                        local relY = ey - cy

                        -- 吸附逻辑 (简单取整)
                        relX = math.floor(relX + 0.5)
                        relY = math.floor(relY + 0.5)

                        s:ClearAllPoints()
                        s:SetPoint("CENTER", self, "CENTER", relX, relY)

                        local activeCallbacks = self._previewCallbacks
                        if activeCallbacks and activeCallbacks.onMove then
                            activeCallbacks.onMove(elementKey, relX, relY)
                        end
                    end)

                    -- 点击选择
                    el:SetScript("OnClick", function() self:Select(elementKey) end)

                    self.elements[key] = el
                end

                -- 更新样式与位置
                el:Show()
                el.text:SetText(data.label or key)
                el:ClearAllPoints()
                el:SetPoint("CENTER", self, "CENTER", data.x or 0, data.y or 0)

                -- 根据是否选中设置外观
                if self.selectedKey == key then
                    EXUI:SetControlSurface(el, 4, MC.blueSoft, MC.focus)
                    el.text:SetTextColor(unpack(MC.lightBlue))
                else
                    EXUI:SetControlSurface(el, 4, MC.input, MC.border)
                    el.text:SetTextColor(unpack(MC.text))
                end
            end
        end
    end

    function canvas:Select(key)
        self.selectedKey = key
        -- 刷新外观
        for k, el in pairs(self.elements) do
            if k == key then
                EXUI:SetControlSurface(el, 4, MC.blueSoft, MC.focus)
                el.text:SetTextColor(unpack(MC.lightBlue))
            else
                EXUI:SetControlSurface(el, 4, MC.input, MC.border)
                el.text:SetTextColor(unpack(MC.text))
            end
        end
        local activeCallbacks = self._previewCallbacks
        if activeCallbacks and activeCallbacks.onSelect then activeCallbacks.onSelect(key) end
    end

    function canvas:ClearSelection()
        self:Select(nil)
    end

    canvas:UpdateElements(canvas._previewData)
    canvas._exCompositeReflow = function(self, nextWidth, nextHeight) self:SetSize(nextWidth, nextHeight) end
    ReflowCompositeGroup(canvas, width, height)
    AttachCompositeRelease(canvas)
    return canvas
end

-- =========================================================
-- 15. 分段控制器 (Segmented Control / Tabs)
-- items: { {label, value}, ... }
-- =========================================================
function EXUI:CreateSegmentedControl(parent, width, items, currentValue, onChange)
    if type(self.CreateOptionGroup) ~= "function" then
        error("CreateSegmentedControl requires ExwindChoiceGroup", 2)
    end
    local choiceItems = {}
    for _, item in ipairs(items or {}) do
        choiceItems[#choiceItems + 1] = { id = item[2], label = item[1] }
    end
    local container = self:CreateOptionGroup(parent, {
        width = width,
        items = choiceItems,
        value = currentValue,
        appearance = "segmented",
        wrap = false,
        itemHeight = 32,
        gap = 3,
        onChange = function(value)
            if onChange then onChange(value) end
        end,
    })
    function container:Refresh() self:SetValue(self:GetValue()) end
    return container
end

-- =========================================================
-- 16. 只读物品身份 (Item Identity)
-- 仅显示现有 itemID 的图标、名称与 tooltip；不持有配置、不接收拖放、
-- 不创建默认值，也不发出任何状态或数据通知。
-- =========================================================
local ITEM_IDENTITY_PENDING = {}
local ItemIdentityLoader

local function StopItemIdentityLoaderIfIdle()
    if ItemIdentityLoader and next(ITEM_IDENTITY_PENDING) == nil then
        ItemIdentityLoader:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end

local function CancelItemIdentityLoad(container)
    local id = container._itemIdentityPendingID
    local waiters = id and ITEM_IDENTITY_PENDING[id]
    if waiters then
        waiters[container] = nil
        if next(waiters) == nil then ITEM_IDENTITY_PENDING[id] = nil end
    end
    container._itemIdentityPendingID = nil
    container._itemIdentityLoadTicket = nil
    StopItemIdentityLoaderIfIdle()
end

local function EnsureItemIdentityLoader()
    if ItemIdentityLoader then return ItemIdentityLoader end
    local loader = CreateFrame("Frame")
    loader:SetScript("OnEvent", function(_, _, itemID, success)
        itemID = tonumber(itemID)
        local waiters = itemID and ITEM_IDENTITY_PENDING[itemID]
        if not waiters then return end
        ITEM_IDENTITY_PENDING[itemID] = nil
        for container, ticket in pairs(waiters) do
            if container._itemIdentityPendingID == itemID
                and container._itemIdentityLoadTicket == ticket
                and container._itemIdentityID == itemID then
                container._itemIdentityPendingID = nil
                container._itemIdentityLoadTicket = nil
                if success then
                    -- The event is the single completion opportunity for this
                    -- lease. If the cache still has no record, show a stable
                    -- fallback instead of opening another request loop.
                    container:_exUpdateItemIdentity(true)
                else
                    container:_exSetItemIdentityUnavailable()
                end
            end
        end
        StopItemIdentityLoaderIfIdle()
    end)
    ItemIdentityLoader = loader
    return loader
end

local function RequestItemIdentityLoad(container, itemID)
    CancelItemIdentityLoad(container)
    local waiters = ITEM_IDENTITY_PENDING[itemID]
    local firstRequest = waiters == nil
    if firstRequest then
        waiters = setmetatable({}, { __mode = "k" })
        ITEM_IDENTITY_PENDING[itemID] = waiters
    end
    local ticket = {}
    container._itemIdentityPendingID = itemID
    container._itemIdentityLoadTicket = ticket
    waiters[container] = ticket
    EnsureItemIdentityLoader():RegisterEvent("GET_ITEM_INFO_RECEIVED")
    if firstRequest then C_Item.RequestLoadItemDataByID(itemID) end
end

function EXUI:CreateItemIdentity(parent, width, height, itemID)
    local w, h = width or 320, height or 40
    local container, isNew = AcquireCompositeGroup("CompositeItemIdentity", parent)
    local nextItemID = tonumber(itemID) or 0
    if container._itemIdentityID ~= nextItemID then
        container._itemIdentityCompletedID = nil
    end
    container._itemIdentityID = nextItemID

    if isNew then
        local iconButton = CreateFrame("Button", nil, container)
        iconButton:EnableMouse(true)
        local icon = EXUI:CreateVisualTexture(iconButton, EXBASEFRAME)
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        container.iconButton, container.icon = iconButton, icon

        local name = EXUI:CreateVisualFontString(container, EXFONTFRAME, "GameFontHighlightSmall")
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        container.nameText = name

        local function ShowTooltip(owner)
            local id = container._itemIdentityID
            if id and id > 0 then
                GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(id)
                GameTooltip:Show()
            end
        end
        local function HideTooltip() GameTooltip:Hide() end
        container._exItemIdentityShowTooltip = ShowTooltip
        container._exItemIdentityHideTooltip = HideTooltip
        container._exCancelItemIdentityLoad = CancelItemIdentityLoad

        function container:_exSetItemIdentityUnavailable()
            self._itemIdentityCompletedID = self._itemIdentityID
            self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            self.nameText:SetText(string.format("ID %d", self._itemIdentityID or 0))
            self.nameText:SetTextColor(unpack(MC.muted))
        end

        function container:_exUpdateItemIdentity(loadCompleted)
            local id = self._itemIdentityID
            if self._itemIdentityPendingID and self._itemIdentityPendingID ~= id then
                CancelItemIdentityLoad(self)
            end
            if not id or id == 0 then
                CancelItemIdentityLoad(self)
                self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                self.nameText:SetText("")
                self.nameText:SetTextColor(unpack(MC.muted))
                return
            end
            local itemName, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(id)
            if itemName then
                CancelItemIdentityLoad(self)
                self._itemIdentityCompletedID = nil
                self.icon:SetTexture(texture)
                self.nameText:SetText(itemName)
                local r, g, b = C_Item.GetItemQualityColor(quality or 1)
                self.nameText:SetTextColor(r, g, b, 1)
            else
                if loadCompleted or self._itemIdentityCompletedID == id then
                    self:_exSetItemIdentityUnavailable()
                    return
                end
                self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                self.nameText:SetText(L["数据加载中..."])
                self.nameText:SetTextColor(unpack(MC.muted))
                -- RefreshValues may re-read this cell while the same request is
                -- pending. Keep its lease ticket instead of restarting I/O.
                if self._itemIdentityPendingID ~= id or not self._itemIdentityLoadTicket then
                    RequestItemIdentityLoad(self, id)
                end
            end
        end

        container._exCompositeReflow = function(self, nextWidth, nextHeight)
            local iconSize = math.max(24, math.min(32, nextHeight - 8))
            self.iconButton:ClearAllPoints()
            self.iconButton:SetPoint("LEFT", self, "LEFT", 0, 0)
            self.iconButton:SetSize(iconSize, iconSize)
            self.nameText:ClearAllPoints()
            self.nameText:SetPoint("LEFT", self.iconButton, "RIGHT", 8, 0)
            self.nameText:SetPoint("RIGHT", self, "RIGHT", 0, 0)
        end
    end

    -- StandardReset clears scripts on the pooled host. Rebind the read-only
    -- tooltip on every lease; neither region accepts clicks or drag payloads.
    container:EnableMouse(true)
    container:SetScript("OnEnter", container._exItemIdentityShowTooltip)
    container:SetScript("OnLeave", container._exItemIdentityHideTooltip)
    container:SetScript("OnReceiveDrag", nil)
    container.iconButton:SetScript("OnEnter", container._exItemIdentityShowTooltip)
    container.iconButton:SetScript("OnLeave", container._exItemIdentityHideTooltip)
    container.iconButton:SetScript("OnClick", nil)
    container:_exUpdateItemIdentity()
    ReflowCompositeGroup(container, w, h)
    -- ReflowCompositeGroup reapplies the generic panel surface. Item identity
    -- is a read-only icon/name cell, so clear that host outline afterwards;
    -- the table row and all interactive controls keep their own surfaces.
    EXUI:ClearControlSurface(container)
    AttachCompositeRelease(container)
    return container
end

-- =========================================================
-- 17. 物品配置组件 (Item Config Widget)
-- 包含：Checkbox + Icon + ItemName + Input(Count) + DeleteBtn
-- 支持：物品拖拽（OnReceiveDrag）
-- =========================================================
function EXUI:CreateItemConfig(parent, width, height, itemID, db, onChange, onDelete)
    db = type(db) == "table" and db or { enabled = true, quantity = 1 }
    local w, h = width or 320, height or 40
    local container, isNew = AcquireCompositeGroup("CompositeItemConfig", parent)
    container._itemDb = db
    container._itemID = tonumber(itemID) or 0
    container._itemOnChange = onChange
    container._itemOnDelete = onDelete
    container._exCompositeDb = db

    if isNew then
        local enabled = EXUI:CreateCheckbox(container, "", true, function(value)
            local active = container._itemDb
            if not active then return end
            active.enabled = value == true
            if container._itemOnChange then container._itemOnChange(active) end
        end)
        enabled:SetSize(28, 28)
        enabled:SetPoint("LEFT", 5, 0)
        container.enabledControl = enabled
        container.checkbox = enabled.checkbox

        local iconButton = EXUI:CreatePicButton(container, 30, 30, nil, nil, nil, nil, true)
        iconButton:SetPoint("LEFT", enabled.checkbox, "RIGHT", 6, 0)
        local icon = EXUI:CreateVisualTexture(iconButton, EXBASEFRAME)
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        container.iconButton, container.icon = iconButton, icon

        local name = EXUI:CreateVisualFontString(container, EXFONTFRAME, "GameFontHighlightSmall")
        name:SetPoint("LEFT", iconButton, "RIGHT", 8, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        container.nameText = name

        local quantity = EXUI:CreateEditBox(container, "1", 44, 26, nil, {})
        quantity:SetPoint("RIGHT", -38, 0)
        quantity:SetJustifyH("CENTER")
        quantity:SetNumeric(true)
        container.editBox = quantity
        local qtyLabel = EXUI:CreateVisualFontString(container, EXFONTFRAME, "GameFontDisableSmall")
        qtyLabel:SetPoint("RIGHT", quantity, "LEFT", -6, 0)
        qtyLabel:SetText(L["数量"])
        MODERN.ApplyTextRole(qtyLabel, "hint")

        local deleteButton = EXUI:CreateButton(container, 26, 26, "×", function()
            local moduleKey, elementKey = container.moduleKey, container.elementKey
            if moduleKey and elementKey then
                ExwindTools:UpdateState(moduleKey .. ".ItemConfigDelete", { key = elementKey })
            end
            if type(container._itemOnDelete) == "function" then container._itemOnDelete() end
        end, { variant = "danger", compact = true })
        deleteButton:SetPoint("RIGHT", -5, 0)
        container.delBtn = deleteButton

        local function ShowTooltip(owner)
            local id = container._itemID
            if id and id > 0 then
                GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(id)
                GameTooltip:Show()
            end
        end
        local function HideTooltip() GameTooltip:Hide() end
        local function ReadCursorItem()
            local infoType, info1 = GetCursorInfo()
            if infoType == "item" then return tonumber(info1) end
            if infoType == "merchant" then return GetMerchantItemID(info1) end
        end
        local function AcceptCursorItem()
            local id = ReadCursorItem()
            if not id then return end
            ClearCursor()
            container._itemID = id
            container:_exUpdateItem()
            local moduleKey, elementKey = container.moduleKey, container.elementKey
            if moduleKey and elementKey then
                ExwindTools:UpdateState(moduleKey .. ".ItemConfigUpdate", { key = elementKey, itemID = id })
            end
            if container._itemOnChange then container._itemOnChange(container._itemDb, id) end
        end
        container._exItemShowTooltip = ShowTooltip
        container._exItemHideTooltip = HideTooltip
        container._exItemAcceptCursorItem = AcceptCursorItem
        container:EnableMouse(true)
        container:SetScript("OnEnter", ShowTooltip)
        container:SetScript("OnLeave", HideTooltip)
        container:SetScript("OnReceiveDrag", AcceptCursorItem)
        iconButton:SetScript("OnEnter", ShowTooltip)
        iconButton:SetScript("OnLeave", HideTooltip)
        iconButton:SetScript("OnClick", AcceptCursorItem)

        quantity:SetScript("OnEnterPressed", function(self)
            local active = container._itemDb
            if not active then return end
            active.quantity = tonumber(self:GetText()) or 1
            self:ClearFocus()
            if container._itemOnChange then container._itemOnChange(active) end
        end)
        quantity:SetScript("OnEditFocusLost", function(self)
            local active = container._itemDb
            if not active then return end
            active.quantity = tonumber(self:GetText()) or 1
            if container._itemOnChange then container._itemOnChange(active) end
        end)

        function container:_exUpdateItem()
            local id = self._itemID
            if not id or id == 0 then
                self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                self.nameText:SetText(L["可将消耗品拖进来添加"])
                self.nameText:SetTextColor(unpack(MC.muted))
                return
            end
            local itemName, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(id)
            if itemName then
                self.icon:SetTexture(texture)
                self.nameText:SetText(itemName)
                local r, g, b = C_Item.GetItemQualityColor(quality or 1)
                self.nameText:SetTextColor(r, g, b, 1)
            else
                C_Item.RequestLoadItemDataByID(id)
                self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                self.nameText:SetText(L["数据加载中..."])
                local expected = id
                C_Timer.After(0.5, function()
                    if container._itemDb and container._itemID == expected then container:_exUpdateItem() end
                end)
            end
        end
        container._exCompositeConfigure = function(self)
            local active = self._itemDb
            if not active then return end
            self.enabledControl:SetChecked(active.enabled == true)
            self.editBox:SetText(tostring(active.quantity or 1))
            self.delBtn:SetShown(type(self._itemOnDelete) == "function")
            self:_exUpdateItem()
        end
        container._exCompositeReflow = function(self, nextWidth, nextHeight)
            self.iconButton:SetSize(math.max(24, nextHeight - 10), math.max(24, nextHeight - 10))
            self.nameText:SetWidth(math.max(40, nextWidth - 178))
        end
    end

    -- StandardReset clears scripts on the outer pooled host.  Persistent child
    -- controls keep their stable closures, while host tooltip/drop handlers are
    -- deliberately rebound on every lease.
    container:EnableMouse(true)
    container:SetScript("OnEnter", container._exItemShowTooltip)
    container:SetScript("OnLeave", container._exItemHideTooltip)
    container:SetScript("OnReceiveDrag", container._exItemAcceptCursorItem)
    container:SetSize(w, h)
    container:_exCompositeConfigure()
    ReflowCompositeGroup(container, w, h)
    AttachCompositeRelease(container)
    return container
end

-- =========================================================
-- 12. Glow 设置复合组件 (Glow Settings Group)
-- =========================================================
function EXUI:CreateGlowSettings(parent, width, label, db, key, onUpdate)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local groupWidth = width or 750
    local groupHeight = 240

    container:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(container)

    -- 内容容器
    local content = CreateFrame("Frame", nil, container)
    content:SetSize(groupWidth, groupHeight)
    content:SetPoint("TOPLEFT", 0, 0)

    -- 布局坐标
    local col1, col2, col3 = 15, 275, 535
    local row1, row2, row3 = -25, -95, -165
    local itemW = 225

    local enableKey = key .. "Enabled"
    if db[enableKey] == nil then db[enableKey] = true end

    local cb = EXUI:CreateCheckbox(content, L["启用发光"], db[enableKey], function(checked)
        db[enableKey] = checked
        if onUpdate then onUpdate() end
    end)
    -- 注意：CreateCheckbox 返回一个容器，不是简单的 Button
    cb:SetPoint("TOPLEFT", col1, row1 - 5)


    -- 1. 样式选择 (Style Dropdown)
    local styleKey = key .. "Style"
    local styles = {
        { L["标准 (Classic)"], "Action Button Glow" },
        { L["像素 (Pixel)"], "Pixel Glow" },
        { L["自动施法 (AutoCast)"], "Autocast Shine" },
        { L["新版触发 (Proc)"], "Proc Glow" },
    }

    local styleDropdown = EXUI:CreateDropdown(content, itemW, L["样式类型"], styles, db[styleKey] or "Action Button Glow",
        function(val)
            db[styleKey] = val
            container:RefreshLayout()
            if onUpdate then onUpdate() end
        end)
    styleDropdown:SetPoint("TOPLEFT", col2, row1 - 10)

    -- 2. 颜色选择
    local colorBtn = EXUI:CreateColorButton(content, L["发光颜色"], db, key .. "Color", true, function()
        if onUpdate then onUpdate() end
    end)
    -- Color button matches generic button height
    colorBtn:SetPoint("TOPLEFT", col3, row1 - 10)

    -- 3. Sliders
    local sliders = {}
    local function CreateGlowSlider(sLabel, sKey, min, max, step, def)
        local itemKey = key .. sKey
        local s = EXUI:CreateSlider(content, itemW, sLabel, min, max, db[itemKey] or def, step, nil, function(v)
            db[itemKey] = v
            if onUpdate then onUpdate() end
        end)
        return s
    end

    sliders.Frequency = CreateGlowSlider(L["频率 (Frequency)"], "Frequency", 0.1, 5, 0.1, 0.25)
    sliders.Lines = CreateGlowSlider(L["线条 (Lines)"], "Lines", 1, 30, 1, 8)
    sliders.Scale = CreateGlowSlider(L["大小/粗细 (Scale)"], "Scale", 0.5, 3, 0.1, 1)
    sliders.Offset = CreateGlowSlider(L["边距 (Offset)"], "Offset", -50, 50, 1, 0)
    if db[key .. "Offset"] == nil then db[key .. "Offset"] = 0 end

    container.Sliders = sliders

    function container:RefreshLayout()
        local style = db[styleKey] or "Action Button Glow"

        if style == "Proc Glow" then colorBtn:Hide() else colorBtn:Show() end

        for _, s in pairs(sliders) do s:Hide() end

        -- Row 2 placement
        if style == "Action Button Glow" then
            sliders.Frequency:Show(); sliders.Frequency.Title:SetText(L["闪烁速度"]); sliders.Frequency:SetPoint("TOPLEFT", col1,
                row2)
        elseif style == "Pixel Glow" then
            sliders.Frequency:Show(); sliders.Frequency.Title:SetText(L["流动速度"]); sliders.Frequency:SetPoint("TOPLEFT", col1,
                row2)
            sliders.Lines:Show(); sliders.Lines.Title:SetText(L["线条数量"]); sliders.Lines:SetPoint("TOPLEFT", col2, row2)
            sliders.Scale:Show(); sliders.Scale.Title:SetText(L["线条粗细"]); sliders.Scale:SetPoint("TOPLEFT", col3, row2)
        elseif style == "Autocast Shine" then
            sliders.Frequency:Show(); sliders.Frequency.Title:SetText(L["闪烁速度"]); sliders.Frequency:SetPoint("TOPLEFT", col1,
                row2)
            sliders.Lines:Show(); sliders.Lines.Title:SetText(L["粒子数量"]); sliders.Lines:SetPoint("TOPLEFT", col2, row2)
            sliders.Scale:Show(); sliders.Scale.Title:SetText(L["粒子大小"]); sliders.Scale:SetPoint("TOPLEFT", col3, row2)
        end

        -- Row 3 placement (Offset)
        if style ~= "Proc Glow" then
            sliders.Offset:Show(); sliders.Offset:SetPoint("TOPLEFT", col1, row3)
        end
    end

    container:RefreshLayout()
    container._exGridOwnedControls = {
        cb, styleDropdown, colorBtn,
        sliders.Frequency, sliders.Lines, sliders.Scale, sliders.Offset,
    }
    EXUI:ClearControlSurface(container)
    return container
end

-- =========================================================
-- 17. 图标设置组 (Icon Settings Group)
-- =========================================================
function EXUI:CreateIconGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    local groupWidth = width or 750
    local narrowLayout = groupWidth < 720
    -- 窄卡把功能区移到 2x2 字段下方；宽卡继续保持原来的左右结构。
    local groupHeight = narrowLayout and 296 or 150

    -- [关键修复] 获取嵌套子表，如果不存在则初始化
    db = type(db) == "table" and db or {}
    if key and not db[key] then db[key] = {} end
    local iconDb = key and db[key] or db

    -- 图标四项开关的默认状态。nil 视为开启，既兼容旧配置，也让首次打开
    -- 设置页时与当前默认视觉保持一致。
    if iconDb.showIcon == nil then iconDb.showIcon = true end
    if iconDb.showBorder == nil then iconDb.showBorder = true end
    if iconDb.enableCrop == nil then iconDb.enableCrop = true end
    if iconDb.showCooldown == nil then iconDb.showCooldown = true end
    if iconDb.reverse == nil then iconDb.reverse = false end
    if type(iconDb.cooldown) ~= "table" then iconDb.cooldown = {} end
    local cooldownDb = iconDb.cooldown
    if cooldownDb.showSwipe == nil then cooldownDb.showSwipe = true end
    if cooldownDb.swipeAlpha == nil then cooldownDb.swipeAlpha = 0.65 end
    if cooldownDb.showEdge == nil then cooldownDb.showEdge = true end
    if cooldownDb.edgeAlpha == nil then cooldownDb.edgeAlpha = 1 end
    if cooldownDb.showBling == nil then cooldownDb.showBling = false end

    local palette = {
        panel = MC.panel,
        card = MC.raised,
        utility = MC.raised,
        border = MC.border,
        borderSoft = MC.border,
        text = MC.text,
        value = MC.blue,
        accent = MC.blue,
    }

    local container, isNew = AcquireCompositeGroup("CompositeIconGroup", parent)
    container._exCompositeLabel = label or L["图标设置"]
    BindCompositeGroup(container, iconDb, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(container)
        EXUI:LayoutCompositeGroup(container, groupWidth, groupHeight)
        EXUI:ClearControlSurface(container)
        for _, card in ipairs(container._exIconMetricCards or {}) do
            EXUI:SetControlSurface(card, 10, palette.card, palette.border)
        end
        if container._exIconActionCard then
            EXUI:SetControlSurface(container._exIconActionCard, 10, palette.utility, palette.border)
        end
        for _, popup in ipairs(container._exCompositePopups or {}) do
            EXUI:SetControlSurface(popup, 10, palette.panel, palette.border)
        end
        for _, line in ipairs(container.crispOutline or {}) do line:Hide() end
        container.crispOutline = nil
        return container
    end
    iconDb = CreateCompositeProxy(container)
    cooldownDb = CreateCompositeProxy(container, "cooldown")
    opts = setmetatable({}, { __index = function(_, field)
        return (container._exCompositeOpts or {})[field]
    end })
    onUpdate = function() CompositeEmitUpdate(container) end

    local function GetIconInputMetadata()
        local activeOpts = container._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateIconGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateIconGroup Grid write context requires pathPrefix", 2)
        end
        local commitAPI = EXUI.CommitModuleValue
        if type(commitAPI) ~= "function" then
            error("CreateIconGroup requires its Core commit API", 2)
        end
        return metadata.moduleKey, prefix
    end

    -- IconGroup 的写入上下文只由 Grid 注入；每次值变化都经统一 ModuleDB
    -- 通知重套已存在表面。
    local function WriteIconSliderValue(field, value)
        local target, key = iconDb, field
        local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
        if parentPath == "cooldown" then
            target, key = cooldownDb, childKey
        end
        target[key] = value
    end

    local function ReadIconValue(field)
        local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
        if parentPath == "cooldown" then return cooldownDb[childKey] end
        return iconDb[field]
    end

    local function CommitIconValue(field, value)
        local moduleKey, prefix = GetIconInputMetadata()
        if moduleKey then
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. field,
                readValue = function() return ReadIconValue(field) end,
                writeValue = function(nextValue) WriteIconSliderValue(field, nextValue) end,
            }
            return EXUI:CommitModuleValue(payload, value)
        end
        WriteIconSliderValue(field, value)
        if onUpdate then onUpdate() end
        return true
    end

    local function CreateIconColorTransaction(colorKey)
        local fields = colorKey == "borderColor"
            and { "borderColorR", "borderColorG", "borderColorB", "borderColorA" }
            or { "colorR", "colorG", "colorB", "colorA" }
        return function()
            -- 同 FontGroup：池化色盘必须在点击当下解析当前模块声明。
            local moduleKey, prefix = GetIconInputMetadata()
            if not moduleKey then return nil end
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. colorKey,
                readValue = function()
                    return { r = iconDb[fields[1]], g = iconDb[fields[2]], b = iconDb[fields[3]], a = iconDb[fields[4]] }
                end,
                writeValue = function(value)
                    iconDb[fields[1]], iconDb[fields[2]], iconDb[fields[3]], iconDb[fields[4]] = value.r, value.g, value.b, value.a
                end,
            }
            return EXUI:CreateModuleNotifyFlow(payload)
        end
    end

    local function SetIconSliderValue(field, value, phase)
        WriteIconSliderValue(field, value)
        if phase ~= "live" and onUpdate then onUpdate() end
    end

    -- 旧 RegisterModuleLayout 的 IconGroup 可声明公开 registry 生命周期。每次
    -- 按下均从当前 pooled group 的 opts 解析，绝不复用上一模块的 moduleKey/path；
    local function CreateIconNotifyFlow(field)
        local activeOpts = container._exCompositeOpts or {}
        local transaction = activeOpts._exWriteContext
        if transaction ~= nil then
            if type(transaction) ~= "table" or type(transaction.moduleKey) ~= "string" or transaction.moduleKey == "" then
                error("CreateIconGroup requires Grid write context", 2)
            end
            local prefix = transaction.pathPrefix or transaction.path
            if type(prefix) ~= "string" or prefix == "" then
                error("CreateIconGroup Grid write context requires pathPrefix", 2)
            end
            local createAPI = EXUI.CreateModuleNotifyFlow
            if type(createAPI) ~= "function" then
                error("CreateIconGroup requires its Core transaction API", 2)
            end
            local payload = {
                moduleKey = transaction.moduleKey,
                path = prefix .. "." .. field,
                readValue = function()
                    local target, fieldKey = iconDb, field
                    local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
                    if parentPath == "cooldown" then target, fieldKey = cooldownDb, childKey end
                    return target[fieldKey]
                end,
                writeValue = function(value) WriteIconSliderValue(field, value) end,
            }
            return createAPI(EXUI, payload)
        end
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateIconGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateIconGroup Grid write context requires pathPrefix", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateIconGroup requires CreateModuleNotifyFlow", 2)
        end
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = prefix .. "." .. field,
            readValue = function()
                local target, fieldKey = iconDb, field
                local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
                if parentPath == "cooldown" then target, fieldKey = cooldownDb, childKey end
                return target[fieldKey]
            end,
            writeValue = function(value)
                WriteIconSliderValue(field, value)
            end,
            commit = function(value)
                WriteIconSliderValue(field, value)
                if onUpdate then onUpdate() end
            end,
        })
    end

    local function CreateIconSlider(parentFrame, sliderWidth, titleText, field, minValue, maxValue, value, stepValue)
        local lifecycle
        return EXUI:CreateSlider(parentFrame, sliderWidth, titleText, minValue, maxValue, value, stepValue, nil, {
            onBegin = function()
                lifecycle = CreateIconNotifyFlow(field)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(v)
                if lifecycle and lifecycle.onLive then lifecycle.onLive(v) else SetIconSliderValue(field, v, "live") end
            end,
            onCommit = function(v)
                -- 同 FontGroup：数字输入是一次性提交，没有拖动期的 onBegin。
                local inputOpts = container._exCompositeOpts or {}
                if not lifecycle and inputOpts._exWriteContext ~= nil then
                    lifecycle = CreateIconNotifyFlow(field)
                end
                if lifecycle and lifecycle.onCommit then
                    lifecycle.onCommit(v)
                    lifecycle = nil
                else
                    SetIconSliderValue(field, v, "commit")
                end
            end,
        })
    end

    container:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(container)

    local content = CreateFrame("Frame", nil, container)
    content:SetSize(groupWidth, groupHeight)
    content:SetPoint("TOPLEFT", 0, 0)

    -- 左侧默认是 2x2 几何滑条；不需要模块局部图标偏移时可显式隐藏
    -- Position 控件，根锚点仍是该模块唯一的位置来源。
    local padding, gap = 15, 12
    local controlsGap = 18
    local controlWidth = narrowLayout and (groupWidth - padding * 2)
        or math.min(416, math.max(364, math.floor(groupWidth * 0.40)))
    local metricsWidth = narrowLayout and (groupWidth - padding * 2)
        or (groupWidth - padding * 2 - controlsGap - controlWidth)
    local itemWidth = math.floor((metricsWidth - gap) / 2)
    local col1 = padding
    local col2 = col1 + itemWidth + gap
    local row1, row2 = -8, -78
    local controlX = narrowLayout and padding or (padding + metricsWidth + controlsGap)
    local controlY = narrowLayout and (row2 - 64 - gap) or row1

    -- 每个几何参数保留独立深色卡片，避免滑条直接裸排在内容区。
    local function CreateMetricCard(x, y)
        local card = CreateFrame("Frame", nil, content)
        card:SetPoint("TOPLEFT", x, y)
        card:SetSize(itemWidth, 64)
        EXUI:SetControlSurface(card, 10, palette.card, palette.border)
        return card
    end

    local widthCard = CreateMetricCard(col1, row1)
    local heightCard = CreateMetricCard(col2, row1)
    local sliderWidth = itemWidth - 20

    local sWidth = CreateIconSlider(widthCard, sliderWidth, L["宽度 (Width)"], "width", 10, 300, iconDb.width or 64, 1)
    sWidth:SetPoint("TOPLEFT", 10, -10)

    local sHeight = CreateIconSlider(heightCard, sliderWidth, L["高度 (Height)"], "height", 10, 300, iconDb.height or 64, 1)
    sHeight:SetPoint("TOPLEFT", 10, -10)

    local sPosX, sPosY, xCard, yCard
    if opts.hidePositionControls ~= true then
        xCard = CreateMetricCard(col1, row2)
        yCard = CreateMetricCard(col2, row2)
        -- Aura 图标可用较细的偏移范围；排序和间距属于另一张“排序”卡片，绝不由这里重算。
        local offsetMin = tonumber(opts.offsetMin) or -1000
        local offsetMax = tonumber(opts.offsetMax) or 1000
        local offsetStep = tonumber(opts.offsetStep) or 1
        sPosX = CreateIconSlider(xCard, sliderWidth, L["水平偏移 (X)"], "x", offsetMin, offsetMax, iconDb.x or 0, offsetStep)
        sPosX:SetPoint("TOPLEFT", 10, -10)

        sPosY = CreateIconSlider(yCard, sliderWidth, L["垂直偏移 (Y)"], "y", offsetMin, offsetMax, iconDb.y or 0, offsetStep)
        sPosY:SetPoint("TOPLEFT", 10, -10)
    end
    container._exIconMetricCards = { widthCard, heightCard }
    if xCard then container._exIconMetricCards[#container._exIconMetricCards + 1] = xCard end
    if yCard then container._exIconMetricCards[#container._exIconMetricCards + 1] = yCard end

    -- 四项功能控制区：每一行左侧开关、右侧对应设置按钮。
    local actionCard = CreateFrame("Frame", nil, content)
    actionCard:SetPoint("TOPLEFT", controlX, controlY)
    actionCard:SetSize(controlWidth, math.abs(row2 - row1) + 64)
    EXUI:SetControlSurface(actionCard, 10, palette.utility, palette.border)
    container._exIconActionCard = actionCard

    local cbShow = EXUI:CreateCheckbox(actionCard, L["显示图标"], iconDb.showIcon, function(v)
        CommitIconValue("showIcon", v)
    end)
    cbShow:SetPoint("TOPLEFT", 12, -4)
    cbShow:SetSize(132, 28)
    local cbShowBorder = EXUI:CreateCheckbox(actionCard, L["显示边框"], iconDb.showBorder, function(v)
        CommitIconValue("showBorder", v)
    end)
    cbShowBorder:SetPoint("TOPLEFT", 12, -38)
    cbShowBorder:SetSize(132, 28)
    local cbCrop = EXUI:CreateCheckbox(actionCard, L["裁切图标"], iconDb.enableCrop, function(v)
        CommitIconValue("enableCrop", v)
    end)
    cbCrop:SetPoint("TOPLEFT", 12, -72)
    cbCrop:SetSize(132, 28)
    local cbCooldown = EXUI:CreateCheckbox(actionCard, L["图标倒数"], iconDb.showCooldown, function(v)
        CommitIconValue("showCooldown", v)
    end)
    cbCooldown:SetPoint("TOPLEFT", 12, -106)
    cbCooldown:SetSize(132, 28)
    local function CreatePopup(titleText, width, height)
        local popup = CreateCompositePopupHost(container, width, height)
        EXUI:SetControlSurface(popup, 10, palette.panel, palette.border)
        popup:Hide()

        local popupTitle = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontHighlight")
        popupTitle:SetPoint("TOPLEFT", 13, -9)
        popupTitle:SetText(titleText)
        StyleModernTitle(popupTitle)

        local close = EXUI:CreateButton(popup, 28, 24, "×", function()
            popup:Hide()
        end, { compact = true })
        close:SetPoint("TOPRIGHT", -7, -4)
        return popup
    end

    local popupScale = 1.3
    local appearancePopupW = math.floor(400 * popupScale)
    local appearancePopup = CreatePopup(L["外观设置"], appearancePopupW, 254)
    local countdownPopupW, countdownPopupH = math.floor(400 * popupScale), 212
    local countdownPopup = CreatePopup(L["倒数设置"], countdownPopupW, countdownPopupH)
    local appearancePad, appearanceGap = 14, 18
    local appearanceItemW = math.floor((appearancePopupW - appearancePad * 2 - appearanceGap) / 2)

    -- central basicIcon 的图标来源属于业务 item，不是外观 DB；该中央分支不许
    -- CreateIconGroup 偷建/编辑 legacy iconID。旧页面保持原来的可选输入框。
    if opts.hideIconID ~= true then
        local inputIcon = EXUI:CreateEditBox(
            appearancePopup,
            tostring(iconDb.iconID or ""),
            appearanceItemW,
            32,
            L["图标ID (可选)"],
            {
                onEnter = function(v)
                    CommitIconValue("iconID", tonumber(v) or nil)
                end,
                onEditFocusLost = function(v)
                    CommitIconValue("iconID", tonumber(v) or nil)
                end,
                labelPos = "top"
            }
        )
        inputIcon:SetPoint("TOPLEFT", appearancePad, -44)
    end

    local alpha = CreateIconSlider(appearancePopup, appearanceItemW, L["图标透明度"], "alpha", 0, 1,
        tonumber(iconDb.alpha) or 1, 0.05)
    alpha:SetPoint("TOPLEFT", appearancePad + appearanceItemW + appearanceGap, -40)

    local cbDesaturated = EXUI:CreateCheckbox(appearancePopup, L["图标变灰"], iconDb.desaturated, function(v)
        CommitIconValue("desaturated", v)
    end)
    cbDesaturated:SetPoint("TOPLEFT", appearancePad, -92)
    local iconColor = EXUI:CreateColorButton(appearancePopup, L["图标染色"], iconDb, "color", true, onUpdate,
        { _changeFlow = CreateIconColorTransaction("color") })
    iconColor:SetPoint("TOPLEFT", appearancePad, -128)

    local blendDrop = EXUI:CreateDropdown(appearancePopup, appearanceItemW, L["混合模式"], {
        { "BLEND", "BLEND" },
        { "ADD", "ADD" },
        { "MOD", "MOD" },
        { "ALPHAKEY", "ALPHAKEY" },
        { "DISABLE", "DISABLE" },
    }, iconDb.blendMode or "BLEND", function(v)
        CommitIconValue("blendMode", v)
    end)
    blendDrop:SetPoint("TOPLEFT", appearancePad + appearanceItemW + appearanceGap, -132)

    local rotation = CreateIconSlider(appearancePopup, appearanceItemW, L["旋转角度"], "rotation", -180, 180,
        tonumber(iconDb.rotation) or 0, 1)
    rotation:SetPoint("TOPLEFT", appearancePad, -202)

    local popupW, popupH = math.floor(580 * popupScale), 154
    local cropPopup = CreatePopup(L["裁切设置"], popupW, popupH)
    local borderPopup = CreatePopup(L["边框设置"], popupW, popupH)
    local popupPad, popupGap = 14, 18
    local popupItemW = math.floor((popupW - popupPad * 2 - popupGap) / 2)
    local popupCol1 = popupPad
    local popupCol2 = popupCol1 + popupItemW + popupGap

    local cropLeft = CreateIconSlider(cropPopup, popupItemW, L["裁切左 (Crop Left)"], "cropLeft", 0, 1,
        tonumber(iconDb.cropLeft) or 0.08, 0.01)
    cropLeft:SetPoint("TOPLEFT", popupCol1, -48)

    local cropRight = CreateIconSlider(cropPopup, popupItemW, L["裁切右 (Crop Right)"], "cropRight", 0, 1,
        tonumber(iconDb.cropRight) or 0.92, 0.01)
    cropRight:SetPoint("TOPLEFT", popupCol2, -48)

    local cropTop = CreateIconSlider(cropPopup, popupItemW, L["裁切上 (Crop Top)"], "cropTop", 0, 1,
        tonumber(iconDb.cropTop) or 0.08, 0.01)
    cropTop:SetPoint("TOPLEFT", popupCol1, -101)

    local cropBottom = CreateIconSlider(cropPopup, popupItemW, L["裁切下 (Crop Bottom)"], "cropBottom", 0, 1,
        tonumber(iconDb.cropBottom) or 0.92, 0.01)
    cropBottom:SetPoint("TOPLEFT", popupCol2, -101)

    local borderBtn = EXUI:CreateColorButton(borderPopup, L["边框颜色"], iconDb, "borderColor", true, onUpdate,
        { _changeFlow = CreateIconColorTransaction("borderColor") })
    borderBtn:SetPoint("TOPLEFT", popupCol1, -48)

    local borderDrop = EXUI:CreateLSMTextureDropdown(borderPopup, "border", popupItemW, L["边框材质"],
        iconDb.borderTexture or "None",
        function(k)
            CommitIconValue("borderTexture", k)
        end)
    borderDrop:SetPoint("TOPLEFT", popupCol2, -48)

    local sBorderSize = CreateIconSlider(borderPopup, popupItemW, L["边框粗细"], "borderSize", -10, 10,
        iconDb.borderSize or 1, 0.1)
    sBorderSize:SetPoint("TOPLEFT", popupCol1, -101)

    local sBorderPad = CreateIconSlider(borderPopup, popupItemW, L["边框间距 (Padding)"], "borderPadding", -10, 10,
        iconDb.borderPadding or 0, 0.1)
    sBorderPad:SetPoint("TOPLEFT", popupCol2, -101)

    -- 图标倒数的原生扇形视觉全部收口于此；数字文本由统一文本控件接管。
    local cbReverse = EXUI:CreateCheckbox(countdownPopup, L["倒数反转"], iconDb.reverse, function(v)
        CommitIconValue("reverse", v)
    end)
    cbReverse:SetPoint("TOPLEFT", 14, -42)
    cbReverse:SetSize(156, 28)
    local countdownPad, countdownGap = 14, 18
    local countdownItemW = math.floor((countdownPopupW - countdownPad * 2 - countdownGap) / 2)
    local countdownCol2 = countdownPad + countdownItemW + countdownGap

    local cbSwipe = EXUI:CreateCheckbox(countdownPopup, L["启用扇形倒数"], cooldownDb.showSwipe, function(v)
        CommitIconValue("cooldown.showSwipe", v)
    end)
    cbSwipe:SetPoint("TOPLEFT", countdownCol2, -42)
    cbSwipe:SetSize(156, 28)
    local cbEdge = EXUI:CreateCheckbox(countdownPopup, L["显示边缘光"], cooldownDb.showEdge, function(v)
        CommitIconValue("cooldown.showEdge", v)
    end)
    cbEdge:SetPoint("TOPLEFT", countdownPad, -76)
    cbEdge:SetSize(156, 28)
    local cbBling = EXUI:CreateCheckbox(countdownPopup, L["倒数结束闪光"], cooldownDb.showBling, function(v)
        CommitIconValue("cooldown.showBling", v)
    end)
    cbBling:SetPoint("TOPLEFT", countdownCol2, -76)
    cbBling:SetSize(176, 28)
    local swipeAlpha = CreateIconSlider(countdownPopup, countdownItemW, L["扇形透明度"], "cooldown.swipeAlpha", 0, 1,
        cooldownDb.swipeAlpha, 0.05)
    swipeAlpha:SetPoint("TOPLEFT", countdownPad, -128)

    local edgeAlpha = CreateIconSlider(countdownPopup, countdownItemW, L["边缘光透明度"], "cooldown.edgeAlpha", 0, 1,
        cooldownDb.edgeAlpha, 0.05)
    edgeAlpha:SetPoint("TOPLEFT", countdownCol2, -128)

    local function TogglePopup(popup, anchor, point, relativePoint)
        local shouldShow = not popup:IsShown()
        appearancePopup:Hide()
        cropPopup:Hide()
        borderPopup:Hide()
        countdownPopup:Hide()
        if shouldShow then
            popup:ClearAllPoints()
            popup:SetPoint(point, anchor, relativePoint, 0, -6)
            popup:Show()
        end
    end

    -- 功能按钮与普通页面按钮共享同一构造器和状态 painter。
    local function CreateUtilityButton(text, width, onClick)
        return EXUI:CreateButton(actionCard, width, 28, text, onClick, { variant = "soft" })
    end

    local buttonWidth = math.min(187, math.floor(controlWidth * 0.45))
    local appearanceButton = CreateUtilityButton(L["外观设置"], buttonWidth, function(self)
        TogglePopup(appearancePopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)
    appearanceButton:SetPoint("TOPRIGHT", actionCard, "TOPRIGHT", -10, -4)

    local borderButton = CreateUtilityButton(L["边框设置"], buttonWidth, function(self)
        TogglePopup(borderPopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)
    borderButton:SetPoint("TOPRIGHT", actionCard, "TOPRIGHT", -10, -38)

    local cropButton = CreateUtilityButton(L["裁切设置"], buttonWidth, function(self)
        TogglePopup(cropPopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)
    cropButton:SetPoint("TOPRIGHT", actionCard, "TOPRIGHT", -10, -72)

    local countdownButton = CreateUtilityButton(L["倒数设置"], buttonWidth, function(self)
        TogglePopup(countdownPopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)
    countdownButton:SetPoint("TOPRIGHT", actionCard, "TOPRIGHT", -10, -106)

    container:HookScript("OnHide", function()
        appearancePopup:Hide()
        cropPopup:Hide()
        borderPopup:Hide()
        countdownPopup:Hide()
    end)

    RegisterCompositeControl(container, sWidth, "width", "slider")
    RegisterCompositeControl(container, sHeight, "height", "slider")
    if sPosX then RegisterCompositeControl(container, sPosX, "x", "slider") end
    if sPosY then RegisterCompositeControl(container, sPosY, "y", "slider") end
    RegisterCompositeControl(container, cbShow, "showIcon", "check")
    RegisterCompositeControl(container, cbShowBorder, "showBorder", "check")
    RegisterCompositeControl(container, cbCrop, "enableCrop", "check")
    RegisterCompositeControl(container, cbCooldown, "showCooldown", "check")
    RegisterCompositeControl(container, inputIcon, "iconID", "edit")
    RegisterCompositeControl(container, alpha, "alpha", "slider")
    RegisterCompositeControl(container, cbDesaturated, "desaturated", "check")
    RegisterCompositeControl(container, iconColor, "color", "color")
    RegisterCompositeControl(container, blendDrop, "blendMode", "dropdown")
    RegisterCompositeControl(container, rotation, "rotation", "slider")
    RegisterCompositeControl(container, cropLeft, "cropLeft", "slider")
    RegisterCompositeControl(container, cropRight, "cropRight", "slider")
    RegisterCompositeControl(container, cropTop, "cropTop", "slider")
    RegisterCompositeControl(container, cropBottom, "cropBottom", "slider")
    RegisterCompositeControl(container, borderBtn, "borderColor", "color")
    RegisterCompositeControl(container, borderDrop, "borderTexture", "dropdown")
    RegisterCompositeControl(container, sBorderSize, "borderSize", "slider")
    RegisterCompositeControl(container, sBorderPad, "borderPadding", "slider")
    RegisterCompositeControl(container, cbReverse, "reverse", "check")
    RegisterCompositeControl(container, cbSwipe, "cooldown.showSwipe", "check")
    RegisterCompositeControl(container, cbEdge, "cooldown.showEdge", "check")
    RegisterCompositeControl(container, cbBling, "cooldown.showBling", "check")
    RegisterCompositeControl(container, swipeAlpha, "cooldown.swipeAlpha", "slider")
    RegisterCompositeControl(container, edgeAlpha, "cooldown.edgeAlpha", "slider")
    container._exCompositePopups = { appearancePopup, cropPopup, borderPopup, countdownPopup }
    container._iconGroupDb = iconDb
    container._exCompositeReflow = function(self, nextWidth, nextHeight)
        local nextNarrow = nextWidth < 720
        local nextControlWidth = nextNarrow and (nextWidth - padding * 2)
            or math.min(416, math.max(364, math.floor(nextWidth * 0.40)))
        local nextMetricsWidth = nextNarrow and (nextWidth - padding * 2)
            or (nextWidth - padding * 2 - controlsGap - nextControlWidth)
        local nextItemWidth = math.floor((nextMetricsWidth - gap) / 2)
        local nextCol2 = padding + nextItemWidth + gap
        local nextControlX = nextNarrow and padding or (padding + nextMetricsWidth + controlsGap)
        local nextControlY = nextNarrow and (row2 - 64 - gap) or row1
        local nextSliderWidth = nextItemWidth - 20

        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, nextHeight)
        EXUI:ClearControlSurface(self)
        local metricCards = { widthCard, heightCard }
        if xCard then metricCards[#metricCards + 1] = xCard end
        if yCard then metricCards[#metricCards + 1] = yCard end
        for _, card in ipairs(metricCards) do card:SetSize(nextItemWidth, 64) end
        widthCard:ClearAllPoints(); widthCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row1)
        heightCard:ClearAllPoints(); heightCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row1)
        if xCard then xCard:ClearAllPoints(); xCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row2) end
        if yCard then yCard:ClearAllPoints(); yCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row2) end
        local metricSliders = { sWidth, sHeight }
        if sPosX then metricSliders[#metricSliders + 1] = sPosX end
        if sPosY then metricSliders[#metricSliders + 1] = sPosY end
        for _, slider in ipairs(metricSliders) do slider:SetWidth(nextSliderWidth) end
        actionCard:ClearAllPoints(); actionCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextControlX, nextControlY)
        actionCard:SetSize(nextControlWidth, math.abs(row2 - row1) + 64)
        local nextButtonWidth = math.min(187, math.floor(nextControlWidth * 0.45))
        appearanceButton:SetWidth(nextButtonWidth); borderButton:SetWidth(nextButtonWidth)
        cropButton:SetWidth(nextButtonWidth); countdownButton:SetWidth(nextButtonWidth)
    end
    EXUI:LayoutCompositeGroup(container, groupWidth, groupHeight)
    AttachCompositeRelease(container)

    return container
end

-- =========================================================
-- 18. 计时条设置组（TimerBarWidget 对应的配置 GUI）
-- =========================================================
function EXUI:CreateTimerBarGroup(parent, width, label, db, key, onUpdate, opts)
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    local iconOffsetMin = tonumber(opts.iconOffsetMin) or -200
    local iconOffsetMax = tonumber(opts.iconOffsetMax) or 200
    local defaults = {
        width = 240, height = 24, x = 0, y = 0,
        texture = "Clean",
        barColorR = 1, barColorG = 0.7, barColorB = 0, barColorA = 1,
        barBgColorR = 0, barBgColorG = 0, barBgColorB = 0, barBgColorA = 0.5,
        showBorder = true, borderTexture = "None", borderSize = 1, borderPadding = 0,
        borderColorR = 1, borderColorG = 1, borderColorB = 1, borderColorA = 1,
        showIcon = true, iconWidth = 24, iconHeight = 24, iconSide = "LEFT",
        iconOffsetX = -5, iconOffsetY = 0,
        showIconBorder = true, iconBorderTexture = "None", iconBorderSize = 1, iconBorderPadding = 0,
        iconBorderColorR = 1, iconBorderColorG = 1, iconBorderColorB = 1, iconBorderColorA = 1,
        fillMode = opts.fillModeOnly == true and "LTR_FILL" or "RTL_DRAIN", fillDirection = "LEFT_TO_RIGHT", progressMode = "REMAINING",
    }
    if opts.fillModeOnly == true then
        defaults.fillDirection, defaults.progressMode = nil, nil
    end
    for field, value in pairs(defaults) do
        if db[field] == nil then db[field] = value end
    end
    local groupWidth = width or 975
    local groupHeight = 242
    -- 层数条复用计时条的尺寸／材质／颜色／边框控件，但没有 duration、图标或填充模式语义。
    -- 使用独立对象池，避免普通计时条和层数条之间残留可见控件。
    local poolType = opts.applicationBar == true and "CompositeTimerBarApplicationGroup" or "CompositeTimerBarGroup"
    local group, isNew = AcquireCompositeGroup(poolType, parent)
    group._exCompositeLabel = label or L["计时条设置"]
    BindCompositeGroup(group, db, onUpdate, opts)
    -- TimerBar 的真实 DB 路径只由 Grid 的私有写入上下文提供。
    local function CreateTimerBarNotifyFlow(field)
        local metadata = group._exCompositeOpts and group._exCompositeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == ""
            or type(metadata.pathPrefix) ~= "string" then
            error("CreateTimerBarGroup requires Grid write context", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateTimerBarGroup requires CreateModuleNotifyFlow", 2)
        end
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = metadata.pathPrefix .. "." .. field,
            readValue = function() return db[field] end,
            writeValue = function(value) db[field] = value end,
            commit = function(value)
                db[field] = value
                CompositeEmitUpdate(group)
            end,
        })
    end
    -- 已声明的 TimerBarGroup 全部控件均走统一通知流。
    local function CreateTimerBarNotifyFlowForValue(field, readValue, writeValue)
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == ""
            or type(metadata.pathPrefix) ~= "string" or metadata.pathPrefix == "" then
            error("CreateTimerBarGroup requires Grid write context", 2)
        end
        local createAPI = EXUI.CreateModuleNotifyFlow
        if type(createAPI) ~= "function" then
            error("CreateTimerBarGroup requires CreateModuleNotifyFlow", 2)
        end
        return createAPI(EXUI, {
            moduleKey = metadata.moduleKey,
            path = metadata.pathPrefix .. "." .. field,
            readValue = readValue or function() return db[field] end,
            writeValue = writeValue or function(value) db[field] = value end,
        })
    end
    group._timerBarFillModeOnly = opts.fillModeOnly == true
    if not isNew then
        -- 下拉菜单由对象池复用，但严格 TimerBar 与旧模块的 fill 值集合不同。
        -- 每次借用都必须覆盖菜单与当前值，不能保留上一次页面的项目或闭包语义。
        local fillMode = group._timerBarFillModeDropdown
        if not fillMode then
            error("CreateTimerBarGroup: pooled group is missing fillMode dropdown", 2)
        end
        fillMode._items = group._timerBarFillModeOnly and {
            { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_FADE" },
            { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_FADE" },
        } or {
            { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_DRAIN" },
            { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_DRAIN" },
        }
        fillMode._currentValue = db.fillMode
        SetDropdownDisplayText(fillMode, CompositeDropdownText(db.fillMode, fillMode._items) or L["请选择..."])
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        EXUI:ClearControlSurface(group)
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy

    local function EmitUpdate() CompositeEmitUpdate(group) end
    local function GetTimerBarInputMetadata()
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == ""
            or type(metadata.pathPrefix) ~= "string" or metadata.pathPrefix == "" then
            error("CreateTimerBarGroup requires Grid write context", 2)
        end
        local commitAPI = EXUI.CommitModuleValue
        if type(commitAPI) ~= "function" then
            error("CreateTimerBarGroup requires CommitModuleValue", 2)
        end
        return metadata.moduleKey, metadata.pathPrefix
    end
    local function CommitTimerBarValue(field, value, writeValue)
        local moduleKey, prefix = GetTimerBarInputMetadata()
        local Write = writeValue or function(nextValue) db[field] = nextValue end
        if moduleKey then
            return EXUI:CommitModuleValue({
                moduleKey = moduleKey, path = prefix .. "." .. field,
                readValue = function() return db[field] end, writeValue = Write,
            }, value)
        end
        Write(value)
        EmitUpdate()
        return true
    end
    local palette = {
        panel = MC.panel, card = MC.raised,
        utility = MC.input, border = MC.border,
        text = MC.text, value = MC.blue,
    }
    local flatBackdrop = {
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    }
    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local content = CreateFrame("Frame", nil, group)
    content:SetSize(groupWidth, groupHeight); content:SetPoint("TOPLEFT", 0, 0)
    local padding, gap, controlsGap = 15, 12, 18
    local controlWidth = math.min(416, math.max(364, math.floor(groupWidth * 0.40)))
    local metricsWidth = groupWidth - padding * 2 - controlsGap - controlWidth
    local itemWidth = math.floor((metricsWidth - gap) / 2)
    local col1, col2 = padding, padding + itemWidth + gap
    local row1, row2, row3 = -8, -76, -144
    local controlX = padding + metricsWidth + controlsGap

    local function CreateMetricCard(x, y)
        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetPoint("TOPLEFT", x, y); card:SetSize(itemWidth, 60)
        card:SetBackdrop(flatBackdrop); card:SetBackdropColor(unpack(palette.card)); card:SetBackdropBorderColor(unpack(palette.border))
        return card
    end
    local widthCard, heightCard = CreateMetricCard(col1, row1), CreateMetricCard(col2, row1)
    local xCard, yCard = CreateMetricCard(col1, row2), CreateMetricCard(col2, row2)
    local colorCard, textureCard = CreateMetricCard(col1, row3), CreateMetricCard(col2, row3)
    local sliderWidth = itemWidth - 20
    local function AddSlider(card, titleText, field, min, max, step)
        local lifecycle, transaction
        local slider = EXUI:CreateSlider(card, sliderWidth, titleText, min, max, db[field], step, nil, {
            onBegin = function()
                transaction = CreateTimerBarNotifyFlowForValue(field)
                if transaction then transaction.onBegin(); return end
                lifecycle = CreateTimerBarNotifyFlow(field)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(value)
                if transaction then return transaction.onLive(value) end
                if lifecycle and lifecycle.onLive then return lifecycle.onLive(value) end
                db[field] = value
            end,
            onCommit = function(value)
                -- 输入框路径没有 onBegin；按提交当下的声明建立同一事务。
                if not transaction then transaction = CreateTimerBarNotifyFlowForValue(field) end
                if transaction then
                    local result = transaction.onCommit(value)
                    transaction = nil
                    return result
                end
                if lifecycle and lifecycle.onCommit then
                    local result = lifecycle.onCommit(value)
                    lifecycle = nil
                    return result
                end
                db[field] = value
                EmitUpdate()
            end,
        })
        slider:SetPoint("TOPLEFT", 10, -8)
        return RegisterCompositeControl(group, slider, field, "slider")
    end
    -- 边框/图标弹窗里的数值控件也必须遵守与主面板同一 live 合同：
    -- 拖动仅重套已物化视觉，松手才统一广播 DatabaseChanged。
    local function AddPopupSlider(parent, sliderWidth, titleText, field, min, max, step)
        local lifecycle, transaction
        local slider = EXUI:CreateSlider(parent, sliderWidth, titleText, min, max, db[field], step, nil, {
            onBegin = function()
                transaction = CreateTimerBarNotifyFlowForValue(field)
                if transaction then transaction.onBegin(); return end
                lifecycle = CreateTimerBarNotifyFlow(field)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(value)
                if transaction then return transaction.onLive(value) end
                if lifecycle and lifecycle.onLive then return lifecycle.onLive(value) end
                db[field] = value
            end,
            onCommit = function(value)
                -- 弹窗 Slider 的数字输入也必须走同一条事务。
                if not transaction then transaction = CreateTimerBarNotifyFlowForValue(field) end
                if transaction then
                    local result = transaction.onCommit(value)
                    transaction = nil
                    return result
                end
                if lifecycle and lifecycle.onCommit then
                    local result = lifecycle.onCommit(value)
                    lifecycle = nil
                    return result
                end
                db[field] = value
                EmitUpdate()
            end,
        })
        return slider
    end
    AddSlider(widthCard, L["宽度 (Width)"], "width", 50, 800, 1)
    AddSlider(heightCard, L["高度 (Height)"], "height", 8, 120, 1)
    AddSlider(xCard, L["X 轴偏移"], "x", -1000, 1000, 1)
    AddSlider(yCard, L["Y 轴偏移"], "y", -1000, 1000, 1)

    -- 第三行：两个半宽颜色按钮 + 一项 LSM 条体材质。
    local colorHalfWidth = math.floor((itemWidth - 30) / 2)
    local function CreateColorTransaction(field)
        return function()
            return CreateTimerBarNotifyFlowForValue(field,
                function()
                    return { r = db[field .. "R"], g = db[field .. "G"], b = db[field .. "B"], a = db[field .. "A"] }
                end,
                function(value)
                    db[field .. "R"], db[field .. "G"], db[field .. "B"], db[field .. "A"] = value.r, value.g, value.b, value.a
                end)
        end
    end
    local fgButton = EXUI:CreateColorButton(colorCard, L["前景"], db, "barColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("barColor") })
    fgButton:SetSize(colorHalfWidth, 36); fgButton:SetPoint("TOPLEFT", 10, -12)
    local bgButton = EXUI:CreateColorButton(colorCard, L["背景"], db, "barBgColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("barBgColor") })
    bgButton:SetSize(colorHalfWidth, 36); bgButton:SetPoint("TOPLEFT", 15 + colorHalfWidth, -12)
    local textureDrop = EXUI:CreateLSMTextureDropdown(textureCard, "statusbar", sliderWidth, L["LSM皮肤"], db.texture, function(value)
        CommitTimerBarValue("texture", value)
    end)
    textureDrop:SetPoint("TOPLEFT", 10, -26)

    local actionCard = CreateFrame("Frame", nil, content, "BackdropTemplate")
    actionCard:SetPoint("TOPLEFT", controlX, row1); actionCard:SetSize(controlWidth, 196)
    actionCard:SetBackdrop(flatBackdrop); actionCard:SetBackdropColor(unpack(palette.utility)); actionCard:SetBackdropBorderColor(unpack(palette.border))
    local function ActionButton(text, y, callback)
        local button = EXUI:CreateButton(actionCard, math.min(187, math.floor(controlWidth * 0.45)), 28,
            text, callback, { variant = "soft" })
        button:SetPoint("TOPRIGHT", -10, y)
        return button
    end

    local popupList = {}
    local function CreatePopup(titleText, popupWidth, popupHeight)
        local popup = CreateCompositePopupHost(group, popupWidth, popupHeight)
        popup:SetBackdrop(flatBackdrop); popup:SetBackdropColor(unpack(palette.panel)); popup:SetBackdropBorderColor(unpack(palette.border)); popup:Hide()
        local popupTitle = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontHighlight")
        popupTitle:SetPoint("TOPLEFT", 13, -9); popupTitle:SetText(titleText)
        StyleModernTitle(popupTitle)
        local close = EXUI:CreateButton(popup, 28, 24, "×", function() popup:Hide() end, { compact = true })
        close:SetPoint("TOPRIGHT", -7, -4)
        popupList[#popupList + 1] = popup
        return popup
    end
    local function TogglePopup(popup, anchor)
        local show = not popup:IsShown()
        for _, other in ipairs(popupList) do other:Hide() end
        if show then popup:ClearAllPoints(); popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6); popup:Show() end
    end

    local borderPopup = CreatePopup(L["边框设置"], 540, 166)
    local borderTexture = EXUI:CreateLSMTextureDropdown(borderPopup, "border", 245, L["边框材质"], db.borderTexture, function(value)
        CommitTimerBarValue("borderTexture", value)
    end)
    borderTexture:SetPoint("TOPLEFT", 14, -46)
    local borderColor = EXUI:CreateColorButton(borderPopup, L["边框颜色"], db, "borderColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("borderColor") })
    borderColor:SetPoint("TOPLEFT", 280, -42)
    local borderSize = AddPopupSlider(borderPopup, 245, L["边框粗细"], "borderSize", 0, 20, 0.1)
    borderSize:SetPoint("TOPLEFT", 14, -112)
    local borderPad = AddPopupSlider(borderPopup, 245, L["边框间距 (Padding)"], "borderPadding", -10, 10, 0.1)
    borderPad:SetPoint("TOPLEFT", 280, -112)

    local iconPopup = CreatePopup(L["图标设置"], 700, 306)
    local iconColumnWidth, iconColumn2 = 320, 362
    local iconSides = { { L["左侧"], "LEFT" }, { L["中间"], "CENTER" }, { L["右侧"], "RIGHT" } }
    local iconSide = EXUI:CreateDropdown(iconPopup, iconColumnWidth, L["图标位置"], iconSides, db.iconSide, function(value)
        CommitTimerBarValue("iconSide", value)
    end)
    iconSide:SetPoint("TOPLEFT", 14, -46)
    -- 坐标最终由 Widget 按物理像素对齐；和条/文字/材质的其它位置控件一致，
    -- 必须使用整数步进。0.1 会把 -200..200 扩成 4,000 个原生 Slider 档位，
    -- 但不会产生额外可见位置，反而只让这两个拖动控件异常迟滞。
    local iconOffsetX = AddPopupSlider(iconPopup, iconColumnWidth, L["图标 X 轴偏移"], "iconOffsetX", iconOffsetMin, iconOffsetMax, 1)
    iconOffsetX:SetPoint("TOPLEFT", iconColumn2, -46)
    local iconWidth = AddPopupSlider(iconPopup, iconColumnWidth, L["图标宽度"], "iconWidth", 8, 160, 1)
    iconWidth:SetPoint("TOPLEFT", 14, -100)
    local iconHeight = AddPopupSlider(iconPopup, iconColumnWidth, L["图标高度"], "iconHeight", 8, 160, 1)
    iconHeight:SetPoint("TOPLEFT", iconColumn2, -100)
    local iconOffsetY = AddPopupSlider(iconPopup, iconColumnWidth, L["图标 Y 轴偏移"], "iconOffsetY", iconOffsetMin, iconOffsetMax, 1)
    iconOffsetY:SetPoint("TOPLEFT", 14, -154)
    local showIconBorder = EXUI:CreateCheckbox(iconPopup, L["显示图标边框"], db.showIconBorder, function(value)
        CommitTimerBarValue("showIconBorder", value)
    end)
    showIconBorder:SetPoint("TOPLEFT", iconColumn2, -154)
    local iconBorderTexture = EXUI:CreateLSMTextureDropdown(iconPopup, "border", iconColumnWidth, L["图标边框材质"], db.iconBorderTexture, function(value)
        CommitTimerBarValue("iconBorderTexture", value)
    end)
    iconBorderTexture:SetPoint("TOPLEFT", 14, -208)
    local iconBorderColor = EXUI:CreateColorButton(iconPopup, L["图标边框颜色"], db, "iconBorderColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("iconBorderColor") })
    iconBorderColor:SetPoint("TOPLEFT", iconColumn2, -204)
    local iconBorderSize = AddPopupSlider(iconPopup, iconColumnWidth, L["图标边框粗细"], "iconBorderSize", 0, 20, 0.1)
    iconBorderSize:SetPoint("TOPLEFT", 14, -262)
    local iconBorderPad = AddPopupSlider(iconPopup, iconColumnWidth, L["图标边框间距"], "iconBorderPadding", -10, 10, 0.1)
    iconBorderPad:SetPoint("TOPLEFT", iconColumn2, -262)

    local fillPopup = CreatePopup(L["填充设置"], 540, 126)
    local fillOptions = opts.fillModeOnly == true and {
        { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_FADE" },
        { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_FADE" },
    } or {
        { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_DRAIN" },
        { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_DRAIN" },
    }
    local fillMode = EXUI:CreateDropdown(fillPopup, 510, L["填充方式"], fillOptions, db.fillMode, function(value)
        local function WriteFillMode(nextValue)
            db.fillMode = nextValue
            if group._timerBarFillModeOnly == true then return end
            if nextValue == "LTR_FILL" then db.fillDirection, db.progressMode = "LEFT_TO_RIGHT", "ELAPSED"
            elseif nextValue == "LTR_DRAIN" then db.fillDirection, db.progressMode = "RIGHT_TO_LEFT", "REMAINING"
            elseif nextValue == "RTL_FILL" then db.fillDirection, db.progressMode = "RIGHT_TO_LEFT", "ELAPSED"
            else db.fillDirection, db.progressMode = "LEFT_TO_RIGHT", "REMAINING" end
        end
        if group._timerBarFillModeOnly == true then
            CommitTimerBarValue("fillMode", value, WriteFillMode)
            return
        end
        CommitTimerBarValue("fillMode", value, WriteFillMode)
    end)
    fillMode:SetPoint("TOPLEFT", 14, -46)
    group._timerBarFillModeDropdown = fillMode

    local showIcon = EXUI:CreateCheckbox(actionCard, L["显示图标"], db.showIcon, function(value)
        CommitTimerBarValue("showIcon", value)
    end)
    showIcon:SetPoint("TOPLEFT", 12, -4); showIcon:SetSize(150, 28)
    local iconButton = ActionButton(L["图标设置"], -4, function(self) TogglePopup(iconPopup, self) end)

    local showBorder = EXUI:CreateCheckbox(actionCard, L["显示边框"], db.showBorder, function(value)
        CommitTimerBarValue("showBorder", value)
    end)
    showBorder:SetPoint("TOPLEFT", 12, -72); showBorder:SetSize(150, 28)
    local borderButton = ActionButton(L["边框设置"], -72, function(self) TogglePopup(borderPopup, self) end)

    local fillLabel = EXUI:CreateVisualFontString(actionCard, EXFONTFRAME, "GameFontHighlight")
    -- LEFT 锚点的 Y 偏移从垂直中线计算，会把文字推到卡片外；必须以 TOPLEFT 定位。
    fillLabel:SetPoint("TOPLEFT", actionCard, "TOPLEFT", 48, -140); fillLabel:SetText(L["填充方式"])
    StyleModernTitle(fillLabel)
    local fillButton = ActionButton(L["填充设置"], -140, function(self) TogglePopup(fillPopup, self) end)

    if opts.applicationBar == true then
        -- ApplicationBar 的进度和法术图标由原生 Aura 绑定决定；这些控制项写入数据却
        -- 不会影响原生条，故不向用户显示。
        showIcon:Hide()
        iconButton:Hide()
        fillLabel:Hide()
        fillButton:Hide()
        iconPopup:Hide()
        fillPopup:Hide()
        actionCard:SetHeight(128)
    end

    RegisterCompositeControl(group, fgButton, "barColor", "color")
    RegisterCompositeControl(group, bgButton, "barBgColor", "color")
    RegisterCompositeControl(group, textureDrop, "texture", "dropdown")
    RegisterCompositeControl(group, borderTexture, "borderTexture", "dropdown")
    RegisterCompositeControl(group, borderColor, "borderColor", "color")
    RegisterCompositeControl(group, borderSize, "borderSize", "slider")
    RegisterCompositeControl(group, borderPad, "borderPadding", "slider")
    RegisterCompositeControl(group, iconSide, "iconSide", "dropdown")
    RegisterCompositeControl(group, iconOffsetX, "iconOffsetX", "slider")
    RegisterCompositeControl(group, iconWidth, "iconWidth", "slider")
    RegisterCompositeControl(group, iconHeight, "iconHeight", "slider")
    RegisterCompositeControl(group, iconOffsetY, "iconOffsetY", "slider")
    RegisterCompositeControl(group, showIconBorder, "showIconBorder", "check")
    RegisterCompositeControl(group, iconBorderTexture, "iconBorderTexture", "dropdown")
    RegisterCompositeControl(group, iconBorderColor, "iconBorderColor", "color")
    RegisterCompositeControl(group, iconBorderSize, "iconBorderSize", "slider")
    RegisterCompositeControl(group, iconBorderPad, "iconBorderPadding", "slider")
    RegisterCompositeControl(group, fillMode, "fillMode", "dropdown")
    RegisterCompositeControl(group, showIcon, "showIcon", "check")
    RegisterCompositeControl(group, showBorder, "showBorder", "check")
    group._exCompositePopups = popupList
    group._timerBarDb = proxy
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local nextControlWidth = math.min(416, math.max(364, math.floor(nextWidth * 0.40)))
        local nextMetricsWidth = nextWidth - padding * 2 - controlsGap - nextControlWidth
        local nextItemWidth = math.floor((nextMetricsWidth - gap) / 2)
        local nextCol2 = padding + nextItemWidth + gap
        local nextControlX = padding + nextMetricsWidth + controlsGap
        local nextSliderWidth = nextItemWidth - 20
        local nextColorHalfWidth = math.floor((nextItemWidth - 30) / 2)

        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, nextHeight)
        EXUI:ClearControlSurface(self)
        for _, card in ipairs({ widthCard, heightCard, xCard, yCard, colorCard, textureCard }) do card:SetSize(nextItemWidth, 60) end
        widthCard:ClearAllPoints(); widthCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row1)
        heightCard:ClearAllPoints(); heightCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row1)
        xCard:ClearAllPoints(); xCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row2)
        yCard:ClearAllPoints(); yCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row2)
        colorCard:ClearAllPoints(); colorCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row3)
        textureCard:ClearAllPoints(); textureCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row3)
        for _, entry in ipairs(self._exCompositeControls or {}) do
            if entry.kind == "slider" and entry.control:GetParent() ~= borderPopup and entry.control:GetParent() ~= iconPopup then
                entry.control:SetWidth(nextSliderWidth)
            end
        end
        fgButton:SetSize(nextColorHalfWidth, 36)
        bgButton:SetSize(nextColorHalfWidth, 36)
        bgButton:ClearAllPoints(); bgButton:SetPoint("TOPLEFT", colorCard, "TOPLEFT", 15 + nextColorHalfWidth, -12)
        textureDrop:SetWidth(nextSliderWidth)
        actionCard:ClearAllPoints(); actionCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextControlX, row1)
        actionCard:SetWidth(nextControlWidth)
        local nextActionButtonWidth = math.min(187, math.floor(nextControlWidth * 0.45))
        iconButton:SetWidth(nextActionButtonWidth); borderButton:SetWidth(nextActionButtonWidth); fillButton:SetWidth(nextActionButtonWidth)
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 19. Glow 设置组（Core 原生动画引擎）
-- 旧版 CreateGlowSettings 对应 LibCustomGlow 参数；保留别名仅作代码参考，
-- 公开入口改为 EXUI Glow 的 Pulse / Translation 线条 / Proc 三种样式。
-- =========================================================
EXUI.CreateGlowSettingsLegacy = EXUI.CreateGlowSettings

function EXUI:CreateGlowSettings(parent, width, label, db, key, onUpdate, opts)
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    key = key or "glow"

    local legacyStyles = {
        ["Action Button Glow"] = "PULSE",
        ["Pixel Glow"] = "EDGE_FLOW",
        ["Autocast Shine"] = "EDGE_FLOW",
        ["Proc Glow"] = "PROC_FLIPBOOK",
        ["Proc Alt Glow"] = "PROC_FLIPBOOK",
    }
    local function SetDefault(suffix, value)
        local field = key .. suffix
        if db[field] == nil then db[field] = value end
    end
    SetDefault("Enabled", true)
    SetDefault("Style", "EDGE_FLOW")
    SetDefault("Frequency", 1)
    SetDefault("Lines", 1)
    SetDefault("Length", 32)
    SetDefault("Thickness", 2)
    SetDefault("Direction", "CLOCKWISE")
    SetDefault("Scale", 1)
    SetDefault("Offset", 3)
    SetDefault("ColorR", 1)
    SetDefault("ColorG", 0.82)
    SetDefault("ColorB", 0.20)
    SetDefault("ColorA", 1)
    db[key .. "Style"] = legacyStyles[db[key .. "Style"]] or db[key .. "Style"]

    local groupWidth = width or 750
    local groupHeight = 250
    local group = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    group:SetSize(groupWidth, groupHeight)
    -- 标准 Slider 合同元数据：只暴露既有控件与其真实 DB 路径，
    -- 不改变视觉、写入时机或原有回调。
    group._exStandardSliderControls = {}
    group._exStandardSliderDB = db
    EXUI:ClearControlSurface(group)

    local content = CreateFrame("Frame", nil, group)
    content:SetPoint("TOPLEFT", 0, 0)
    content:SetSize(groupWidth, groupHeight)
    local padding, gap = 15, 16
    local itemWidth = math.floor((groupWidth - padding * 2 - gap * 2) / 3)
    local col1, col2, col3 = padding, padding + itemWidth + gap, padding + (itemWidth + gap) * 2

    local function EmitUpdate()
        if onUpdate then onUpdate(db) end
    end
    local function MakeSlider(text, suffix, min, max, step, x, y)
        local slider = EXUI:CreateSlider(content, itemWidth, text, min, max, db[key .. suffix], step, nil, function(value)
            db[key .. suffix] = value
            EmitUpdate()
        end)
        slider:SetPoint("TOPLEFT", x, y)
        table.insert(group._exStandardSliderControls, {
            control = slider,
            path = key .. suffix,
        })
        return slider
    end

    local enabled = EXUI:CreateCheckbox(content, L["启用发光"], db[key .. "Enabled"], function(value)
        db[key .. "Enabled"] = value
        EmitUpdate()
    end)
    enabled:SetPoint("TOPLEFT", col2, -8)
    enabled:SetSize(itemWidth, 28)

    local styles = {
        { L["呼吸发光（Alpha + Scale）"], "PULSE" },
        { L["边框线条流光（原生 Translation）"], "EDGE_FLOW" },
        { L["触发光环（原生 Proc）"], "PROC_FLIPBOOK" },
    }
    local styleDrop = EXUI:CreateDropdown(content, itemWidth, L["发光样式"], styles, db[key .. "Style"], function(value)
        db[key .. "Style"] = value
        group:RefreshLayout()
        EmitUpdate()
    end)
    styleDrop:SetPoint("TOPLEFT", col3, -14)
    local color = EXUI:CreateColorButton(content, L["发光颜色"], db, key .. "Color", true, EmitUpdate)
    color:SetPoint("TOPLEFT", col1, -14)

    local lines = MakeSlider(L["数量"], "Lines", 1, 36, 1, col1, -76)
    local length = MakeSlider(L["长度"], "Length", 8, 120, 1, col2, -76)
    local thickness = MakeSlider(L["粗度"], "Thickness", 1, 20, 0.5, col3, -76)
    local frequency = MakeSlider(L["速度"], "Frequency", 0.1, 5, 0.1, col1, -138)
    local scale = MakeSlider(L["大小倍率"], "Scale", 0.25, 3, 0.05, col2, -138)
    local offset = MakeSlider(L["间距（负值向内）"], "Offset", -20, 50, 1, col2, -138)
    local directionItems = {
        { L["顺时针"], "CLOCKWISE" },
        { L["逆时针"], "COUNTERCLOCKWISE" },
    }
    local direction = EXUI:CreateDropdown(content, itemWidth, L["方向"], directionItems, db[key .. "Direction"], function(value)
        db[key .. "Direction"] = value
        EmitUpdate()
    end)
    direction:SetPoint("TOPLEFT", col3, -144)
    local info = EXUI:CreateVisualFontString(content, EXFONTFRAME, "GameFontNormalSmall")
    info:SetPoint("TOPLEFT", col1, -204)
    info:SetPoint("TOPRIGHT", -15, -204)
    info:SetJustifyH("LEFT")
    MODERN.ApplyTextRole(info, "hint")

    function group:RefreshLayout()
        local style = db[key .. "Style"]
        local isTrail = style == "EDGE_FLOW"
        local function Place(control, shown, x, y)
            control:ClearAllPoints()
            control:SetShown(shown)
            if shown then control:SetPoint("TOPLEFT", x, y) end
        end

        -- 线条样式有线条专属参数；Pulse 与 Proc 共用速度、大小、外扩边距。
        Place(lines, isTrail, col1, -76)
        Place(length, isTrail, col2, -76)
        Place(thickness, isTrail, col3, -76)
        Place(frequency, true, col1, isTrail and -138 or -76)
        Place(scale, not isTrail, col2, -76)
        Place(offset, true, isTrail and col2 or col3, isTrail and -138 or -76)
        direction:ClearAllPoints()
        direction:SetShown(isTrail)
        if isTrail then direction:SetPoint("TOPLEFT", col3, -144) end
        if isTrail then
            info:SetText(L["数量 = 同时环绕的线条数；间距可为负，负值让线条向图标内部收。四边移动完全由原生 Translation 处理。"])
        elseif style == "PROC_FLIPBOOK" then
            info:SetText(L["使用暴雪原生 Proc FlipBook；速度同时控制起手段与循环段，大小与外扩边距控制光环范围。"])
        else
            info:SetText(L["使用 Alpha + Scale 原生循环；速度控制呼吸节奏，大小与外扩边距控制发光范围。"])
        end
    end
    group:RefreshLayout()
    group._glowDb = db
    group._exGridOwnedControls = {
        enabled, styleDrop, color, lines, length, thickness,
        frequency, scale, offset, direction,
    }
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        itemWidth = math.floor((nextWidth - padding * 2 - gap * 2) / 3)
        col1, col2, col3 = padding, padding + itemWidth + gap, padding + (itemWidth + gap) * 2
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, nextHeight)
        enabled:SetSize(itemWidth, 28)
        enabled:ClearAllPoints(); enabled:SetPoint("TOPLEFT", content, "TOPLEFT", col2, -8)
        styleDrop:SetWidth(itemWidth)
        styleDrop:ClearAllPoints(); styleDrop:SetPoint("TOPLEFT", content, "TOPLEFT", col3, -14)
        color:SetWidth(itemWidth)
        color:ClearAllPoints(); color:SetPoint("TOPLEFT", content, "TOPLEFT", col1, -14)
        for _, control in ipairs({ lines, length, thickness, frequency, scale, offset, direction }) do
            control:SetWidth(itemWidth)
        end
        self:RefreshLayout()
        EXUI:ClearControlSurface(self)
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    return group
end

-- =========================================================
-- 20. Widget 排列设置组
-- 只管理同一规则内多个 Widget 的增长方向、间距、最大显示数量与可选换行方向。
-- 整体 X/Y 属于模块 AnchorController，不能放在这里。
-- =========================================================
-- 只描述排列组的视觉字段；不参与配置构造、绑定或提交。
local function BuildWidgetLayoutSettingsFlow(width, opts)
    opts = type(opts) == "table" and opts or {}
    local fields = {
        { path = "direction", type = "dropdown", label = L["增长方向"] },
        { path = "spacing", type = "slider", label = L["间距"] },
        { path = "maxVisible", type = "slider", label = L["最大显示"] },
    }
    if opts.includeMaxPerRow ~= false then
        fields[#fields + 1] = { path = "maxPerRow", type = "slider", label = L["每行最多"] }
    end
    if opts.includeWrapDirection == true then
        fields[#fields + 1] = { path = "wrapDirection", type = "dropdown", label = L["换行方向"] }
    end
    return EXUI:BuildModuleCommonSettingsFlow(width, { presentation = "settings-list", fields = fields })
end

function EXUI:CreateWidgetLayoutGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    local allowedDirections = type(opts.allowedDirections) == "table" and opts.allowedDirections or {
        "RIGHT", "LEFT", "DOWN", "UP", "CENTER_HORIZONTAL", "CENTER_VERTICAL",
    }
    local defaultDirection = allowedDirections[1] or "RIGHT"
    local wrapDirections = type(opts.wrapDirections) == "table" and opts.wrapDirections or {
        "DOWN", "UP",
    }
    local defaultWrapDirection = tostring(opts.defaultWrapDirection or wrapDirections[1] or "DOWN")
    local maxVisibleMin = math.max(1, tonumber(opts.maxVisibleMin) or 1)
    local maxVisibleMax = math.max(maxVisibleMin, tonumber(opts.maxVisibleMax) or 40)
    local defaultMaxVisible = tonumber(opts.defaultMaxVisible) or 8
    defaultMaxVisible = math.max(maxVisibleMin, math.min(defaultMaxVisible, maxVisibleMax))
    if db.direction == nil then db.direction = defaultDirection end
    if db.spacing == nil then db.spacing = 4 end
    if db.maxVisible == nil then db.maxVisible = defaultMaxVisible end
    if db.maxPerRow == nil then db.maxPerRow = 8 end
    if db.wrapDirection == nil then db.wrapDirection = defaultWrapDirection end

    local includeMaxPerRow = opts.includeMaxPerRow ~= false
    local includeWrapDirection = opts.includeWrapDirection == true
    local groupWidth = width or 760
    local groupHeight = BuildWidgetLayoutSettingsFlow(groupWidth, opts).height
    -- 二维换行卡有额外的下拉控件，必须使用已注册的独立宿主池；
    -- 不能让它和普通单轴卡复用，也不能接受任意外部池名。
    local poolType = includeWrapDirection and "CompositeWidgetLayoutGroupWithWrap" or "CompositeWidgetLayoutGroup"
    local group, isNew = AcquireCompositeGroup(poolType, parent)
    group._exCompositeLabel = label or L["排序"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(group)
        local maxVisible = group._exWidgetLayoutMaxVisible
        if maxVisible then
            maxVisible:SetMinMaxValues(maxVisibleMin, maxVisibleMax)
            local value = tonumber(db.maxVisible) or defaultMaxVisible
            value = math.max(maxVisibleMin, math.min(value, maxVisibleMax))
            db.maxVisible = value
            maxVisible:SetValue(value)
        end
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        EXUI:ClearControlSurface(group)
        if group._exWidgetLayoutHint then group._exWidgetLayoutHint:Hide() end
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy
    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local function EmitUpdate() CompositeEmitUpdate(group) end

    -- Layout 卡片本身会从对象池复用；每次输入都必须从当前宿主读取
    -- Grid 写入上下文，不能捕获第一次（通常是 TimerBar）创建时的 moduleKey。
    local function CreateLayoutInputTransaction(field)
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateWidgetLayoutGroup requires Grid write context", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateWidgetLayoutGroup requires CreateModuleNotifyFlow", 2)
        end
        local prefix = metadata.pathPrefix
        if prefix ~= nil and type(prefix) ~= "string" then
            error("CreateWidgetLayoutGroup Grid write context pathPrefix must be string or nil", 2)
        end
        local path = type(prefix) == "string" and prefix ~= "" and (prefix .. "." .. field) or field
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = path,
            readValue = function() return group._widgetLayoutDb[field] end,
            writeValue = function(value) group._widgetLayoutDb[field] = value end,
        })
    end

    local function CommitLayoutValue(field, value)
        local transaction = CreateLayoutInputTransaction(field)
        if transaction and transaction.onCommit then return transaction.onCommit(value) end
        group._widgetLayoutDb[field] = value
        EmitUpdate()
        return true
    end

    local directionLabels = {
        RIGHT = L["向右"], LEFT = L["向左"], DOWN = L["向下"], UP = L["向上"],
        CENTER_HORIZONTAL = L["左右居中"], CENTER_VERTICAL = L["上下居中"],
    }
    local directionItems = {}
    for _, directionKey in ipairs(allowedDirections) do
        directionItems[#directionItems + 1] = { directionLabels[directionKey] or tostring(directionKey), directionKey }
    end
    local direction = EXUI:CreateDropdown(group, math.min(220, groupWidth - 40), L["增长方向"], directionItems, db.direction, function(value)
        CommitLayoutValue("direction", value)
    end)
    direction:SetPoint("TOPLEFT", 16, -42)
    RegisterCompositeControl(group, direction, "direction", "dropdown")

    local spacing = EXUI:CreateSlider(group, math.min(180, math.max(120, groupWidth * 0.24)), L["间距"], -10, 20,
        tonumber(db.spacing) or 4, 0.1, nil, CreateLayoutInputTransaction("spacing") or function(value)
            db.spacing = value
            EmitUpdate()
        end)
    spacing:SetPoint("TOPLEFT", math.min(255, groupWidth * 0.36), -46)
    RegisterCompositeControl(group, spacing, "spacing", "slider")

    local maxVisible = EXUI:CreateSlider(group, math.min(180, math.max(120, groupWidth * 0.24)), L["最大显示"], maxVisibleMin, maxVisibleMax,
        tonumber(db.maxVisible) or defaultMaxVisible, 1, nil, CreateLayoutInputTransaction("maxVisible") or function(value)
            db.maxVisible = value
            EmitUpdate()
        end)
    maxVisible:SetPoint("TOPLEFT", math.min(470, groupWidth * 0.64), -46)
    RegisterCompositeControl(group, maxVisible, "maxVisible", "slider")
    group._exWidgetLayoutMaxVisible = maxVisible

    local maxPerRow
    if includeMaxPerRow then
        maxPerRow = EXUI:CreateSlider(group, math.min(180, math.max(120, groupWidth * 0.24)), L["每行最多"], 1, 40,
            tonumber(db.maxPerRow) or 8, 1, nil, CreateLayoutInputTransaction("maxPerRow") or function(value)
                db.maxPerRow = value
                EmitUpdate()
            end)
        maxPerRow:SetPoint("TOPLEFT", 16, -92)
        RegisterCompositeControl(group, maxPerRow, "maxPerRow", "slider")
    end

    local wrapDirection
    if includeWrapDirection then
        local wrapItems = {}
        for _, directionKey in ipairs(wrapDirections) do
            wrapItems[#wrapItems + 1] = { directionLabels[directionKey] or tostring(directionKey), directionKey }
        end
        wrapDirection = EXUI:CreateDropdown(group, math.min(180, math.max(120, groupWidth * 0.24)), L["换行方向"], wrapItems,
            db.wrapDirection, function(value)
                db.wrapDirection = value
                EmitUpdate()
            end)
        wrapDirection:SetPoint("TOPLEFT", math.min(255, groupWidth * 0.36), -88)
        RegisterCompositeControl(group, wrapDirection, "wrapDirection", "dropdown")
    end

    group._widgetLayoutDb = proxy
    group._exCompositeConfigure = function(self)
        local activeOpts = self._exCompositeOpts or {}
        local activeDirections = type(activeOpts.allowedDirections) == "table" and activeOpts.allowedDirections or {
            "RIGHT", "LEFT", "DOWN", "UP", "CENTER_HORIZONTAL", "CENTER_VERTICAL",
        }
        local activeItems = {}
        for _, directionKey in ipairs(activeDirections) do
            activeItems[#activeItems + 1] = { directionLabels[directionKey] or tostring(directionKey), directionKey }
        end
        direction._items = activeItems
        direction._currentValue = self._widgetLayoutDb.direction
        direction._onSelect = function(value) CommitLayoutValue("direction", value) end
        SetDropdownDisplayText(direction, CompositeDropdownText(direction._currentValue, activeItems) or L["请选择..."])

        local function RebindSlider(control, field)
            -- SetLifecycleCallbacks only replaces onValueChanged when given a
            -- function, so explicitly clear the fallback callback from a
            -- possible no-context first creation.
            control._onValueChanged = nil
            control:SetLifecycleCallbacks(CreateLayoutInputTransaction(field) or {})
        end
        RebindSlider(spacing, "spacing")
        RebindSlider(maxVisible, "maxVisible")
        if maxPerRow then RebindSlider(maxPerRow, "maxPerRow") end
    end
    group:_exCompositeConfigure()
    local settingsControls = {
        direction = direction, spacing = spacing, maxVisible = maxVisible,
        maxPerRow = maxPerRow, wrapDirection = wrapDirection,
    }
    local settingsRows = {}
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local flow = BuildWidgetLayoutSettingsFlow(nextWidth, self._exCompositeOpts)
        self._exGridFixedHeight = flow.height
        self:SetHeight(flow.height)
        EXUI:ClearControlSurface(self)
        for _, row in pairs(settingsRows) do row:Hide() end
        for _, control in pairs(settingsControls) do control:Hide() end
        for index, entry in ipairs(flow.entries) do
            local field = entry.field
            local control = settingsControls[field.path]
            if control then
                local row = settingsRows[field.path]
                if not row then
                    row = EXUI:CreateSettingsRow(self, { label = field.label, controlKind = "ordinary" })
                    settingsRows[field.path] = row
                end
                row._exSettingsRowIsLast = index == #flow.entries
                row:Show()
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, entry.y)
                EXUI:PrepareSettingsListControl(control, {
                    hideLabel = true, ordinaryControl = true,
                    valuePosition = field.type == "slider" and "right" or nil,
                })
                local _, x, y, controlWidth = EXUI:UpdateSettingsRowLayout(row, entry.width, entry.controlHeight)
                control:SetWidth(controlWidth)
                EXUI:UpdateSettingsListControlLayout(control, controlWidth)
                control:ClearAllPoints()
                control:SetPoint("TOPLEFT", self, "TOPLEFT", x,
                    entry.y - y - math.max(0, (entry.controlHeight - control:GetHeight()) * 0.5))
                control:Show()
            end
        end
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 20.1 模块通用设置卡片：统一紧凑 Flow
--
-- 模块运行逻辑自身的开关、阈值等非外观字段统一收进这里；外观一律使用对应封装组。
-- 新标准最低以三到四列密排；
-- 新声明如确有内容宽度需要，可使用 field.span / field.minWidth / field.fullWidth，
-- 而不是给模块私写另一套布局。
-- =========================================================
local function CollectModuleCommonFields(opts)
    local result = {}
    for _, field in ipairs((type(opts) == "table" and opts.fields) or {}) do
        local path = tostring(field.path or field.key or "")
        if path ~= "" or field.type == "button" then
            result[#result + 1] = field
        end
    end
    return result
end

local function IsModuleCommonOrdinaryField(field)
    if type(field) ~= "table" or field.fullWidth == true
        or field.presentation == "pill" or field.presentation == "switch" then
        return false
    end
    local kind = field.type
    if kind == "slider" then return field.valuePosition ~= "top" end
    return kind == "input" or kind == "dropdown" or kind == "color"
        or kind == "lsm_background" or kind == "lsm_border" or kind == "lsm_texture"
end

local function GetModuleCommonFieldMinWidth(field)
    local explicit = tonumber(field.minWidth or field.preferredWidth or field.width)
    if explicit and explicit > 0 then return explicit end

    local kind = tostring(field.type or "slider")
    local base = {
        checkbox = 176, color = 172, button = 188,
        slider = 228, dropdown = 244, input = 244,
        lsm_background = 260, lsm_border = 260, lsm_texture = 260,
    }
    local minWidth = base[kind] or 228
    -- 标签不截断优先于凑列数。中文字节数仅作保守视觉估算，
    -- 不参与任何业务数据或 DB 逻辑。
    local labelBytes = #(tostring(field.label or field.path or field.key or ""))
    if labelBytes > 30 then
        minWidth = math.max(minWidth, math.min(380, 150 + labelBytes * 5))
    end
    return minWidth
end

-- 公共纯布局计算：Grid 在创建 widget 前也调用它，以相同规则压缩布局占位。
function EXUI:BuildModuleCommonSettingsFlow(width, opts)
    opts = type(opts) == "table" and opts or {}
    local fields = CollectModuleCommonFields(opts)
    local groupWidth = math.max(1, tonumber(width) or 760)

    if opts.presentation == "settings-list" then
        local entries, cursor = {}, 0
        local rowGap = 0
        local innerWidth = math.max(1, groupWidth - SETTINGS_LIST_ROW_PADDING_X * 2)
        local controlHeightByType = {
            checkbox = 28, color = 36, button = 28,
            slider = EXUI.GridSliderHeight, dropdown = 30, input = 28,
            lsm_background = 30, lsm_border = 30, lsm_texture = 30,
        }
        for _, field in ipairs(fields) do
            local ordinaryControl = IsModuleCommonOrdinaryField(field)
            local controlHeight = ordinaryControl and SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT
                or controlHeightByType[field.type] or EXUI.GridSliderHeight
            local controlWidth, textWidth = ResolveSettingsRowColumns(innerWidth,
                field.controlWidth, ordinaryControl and "ordinary" or nil,
                field.inputWidthPercent)
            local titleHeight = MeasureSettingsListText(field.label or field.path or field.key, textWidth, "title")
            local descriptionHeight = MeasureSettingsListText(field.description, textWidth, "description")
            local textHeight = titleHeight + (descriptionHeight > 0
                and ((titleHeight > 0 and SETTINGS_LIST_DESCRIPTION_GAP or 0) + descriptionHeight) or 0)
            local rowHeight = math.max(SETTINGS_LIST_STANDARD_ROW_HEIGHT,
                SETTINGS_LIST_ROW_PADDING_Y * 2 + math.max(textHeight, controlHeight))
            if descriptionHeight > 0 then
                rowHeight = math.max(rowHeight, SETTINGS_LIST_DESCRIPTION_MIN_HEIGHT)
            end
            entries[#entries + 1] = {
                field = field,
                row = #entries,
                column = 0,
                span = 1,
                x = 0,
                y = -cursor,
                width = groupWidth,
                height = rowHeight,
                controlHeight = controlHeight,
            }
            cursor = cursor + rowHeight + rowGap
        end
        local height = #entries > 0 and (cursor - rowGap) or 1
        return {
            fields = fields,
            entries = entries,
            columns = 1,
            rows = math.max(1, #entries),
            width = groupWidth,
            padding = 0,
            contentTopInset = 0,
            entryOriginX = 0,
            cardInsetX = 0,
            cardInsetY = 0,
            cardBottomInset = 0,
            settingsList = true,
            height = math.max(1, height),
        }
    end

    -- 模块声明 fixedLayout 时使用固定的逻辑网格；不声明的历史调用者继续走
    -- 下方原有动态 Flow。逻辑尺寸只在这里按实际 groupWidth 转为物理像素，
    -- 让 Grid measure 与复合控件重排始终共享同一份高度合同。
    if type(opts.fixedLayout) == "table" then
        local fixed = opts.fixedLayout
        local logicalWidth = math.max(1, tonumber(fixed.logicalWidth) or 200)
        local controlW = math.max(1, tonumber(fixed.controlW) or 40)
        local controlH = math.max(1, tonumber(fixed.controlH) or 6)
        local slotX = type(fixed.slotX) == "table" and fixed.slotX or { 1, 51, 101, 151 }
        local firstY = tonumber(fixed.firstY) or 5
        local rowStep = math.max(controlH, tonumber(fixed.rowStep) or 12)
        local cardTopLogical = math.max(0, tonumber(fixed.cardTopInset) or 1)
        local cardBottomLogical = math.max(0, tonumber(fixed.cardBottomInset) or 5)
        local scale = groupWidth / logicalWidth
        -- 控件框的逻辑几何保持 40×6；但它们的 WoW 模板可见区域是固定像素，
        -- 例如 checkbox=28、color=36，slider 还包含标题、轨道和数值输入框。
        -- 因此测量时逐行记录实际可见底边，绝不能只用 6×scale 截断末行。
        local visibleBottomByType = {
            checkbox = 11 + 28,
            color = 14 + 36,
            slider = 8 + EXUI.GridSliderHeight,
            dropdown = 25 + 30,
            lsm_background = 25 + 30,
            lsm_border = 25 + 30,
            lsm_texture = 25 + 30,
            input = 16 + 28,
            button = 16 + 28,
        }
        local bottomSafety = math.max(2, (tonumber(fixed.visibleBottomSafety) or 2) * scale)
        local entries, rowColumns, rowVisibleBottoms, maxRow, cardHeight = {}, {}, {}, 1, 1

        for _, field in ipairs(fields) do
            -- 固定布局只相信调用方声明的 row；不再根据 label 或控件类型猜语义。
            local row = math.max(1, math.floor(tonumber(field.row) or 1))
            local nextColumn = rowColumns[row] or 0
            local declaredColumn = tonumber(field.column)
            local column = declaredColumn
                and math.max(1, math.min(#slotX, math.floor(declaredColumn))) - 1
                or nextColumn
            rowColumns[row] = math.max(nextColumn, column + 1)
            maxRow = math.max(maxRow, row)
            local slotTop = (firstY + (row - 1) * rowStep) * scale
            local visibleBottom = math.max(controlH * scale,
                tonumber(visibleBottomByType[field.type]) or visibleBottomByType.slider)
            local rowBottom = slotTop + visibleBottom
            rowVisibleBottoms[row] = math.max(rowVisibleBottoms[row] or 0, rowBottom)
            cardHeight = math.max(cardHeight, rowBottom + bottomSafety)
            entries[#entries + 1] = {
                field = field,
                row = row,
                column = column,
                span = 1,
                x = (tonumber(slotX[column + 1]) or tonumber(slotX[#slotX]) or 5) * scale,
                y = -slotTop,
                width = controlW * scale,
                height = controlH * scale,
            }
        end

        return {
            fields = fields,
            entries = entries,
            columns = #slotX,
            rows = maxRow,
            width = groupWidth,
            padding = 0,
            contentTopInset = 0,
            entryOriginX = 0,
            headerHeight = 0,
            cardInsetX = 0,
            cardInsetY = cardTopLogical * scale,
            cardBottomInset = cardBottomLogical * scale,
            rowVisibleBottoms = rowVisibleBottoms,
            cardHeight = cardHeight,
            height = math.max(1, cardTopLogical * scale
                + cardHeight + cardBottomLogical * scale),
        }
    end

    local padding, gap = 16, 12
    local available = math.max(1, groupWidth - padding * 2)
    -- 新标准：正常空间优先四列。若声明确有语义上限，只能使用 maxColumns；
    -- 不读取旧 columns，避免形成旧布局的转译/兼容分支。
    local maxColumns = math.max(1, math.min(4, tonumber(opts.maxColumns) or 4))
    local minCellWidth = math.max(160, tonumber(opts.minCellWidth) or 220)
    local columns = math.max(1, math.min(maxColumns, math.floor((available + gap) / (minCellWidth + gap))))
    local unitWidth = math.floor((available - gap * (columns - 1)) / columns)
    local rowHeight = math.max(1, tonumber(opts.rowHeight) or 52)
    local firstRowHeight = math.max(1, tonumber(opts.firstRowHeight) or rowHeight)
    local rowStep = math.max(rowHeight, tonumber(opts.rowStep) or 60)
    local firstRowStep = math.max(firstRowHeight, tonumber(opts.firstRowStep) or rowStep)
    local contentTopInset = math.max(0, tonumber(opts.contentTopInset) or 44)
    local heightOffset = tonumber(opts.heightOffset) or 0
    local row, occupied = 0, 0
    local entries = {}

    for _, field in ipairs(fields) do
        local span
        if field.fullWidth == true then
            span = columns
        else
            span = math.max(1, math.ceil(GetModuleCommonFieldMinWidth(field) / math.max(1, unitWidth)))
            span = math.max(span, math.floor(tonumber(field.span) or 1))
            span = math.min(columns, span)
        end
        if occupied > 0 and occupied + span > columns then
            row, occupied = row + 1, 0
        end
        entries[#entries + 1] = {
            field = field,
            row = row,
            column = occupied,
            span = span,
            x = padding + occupied * (unitWidth + gap),
            y = -contentTopInset - (row == 0 and 0 or (firstRowStep + (row - 1) * rowStep)),
            width = unitWidth * span + gap * (span - 1),
            height = row == 0 and firstRowHeight or rowHeight,
        }
        occupied = occupied + span
        if occupied >= columns then row, occupied = row + 1, 0 end
    end

    local rows = math.max(1, #entries > 0 and (entries[#entries].row + 1) or 1)
    return {
        fields = fields,
        entries = entries,
        columns = columns,
        rows = rows,
        width = groupWidth,
        padding = padding,
        contentTopInset = contentTopInset,
        entryOriginX = padding,
        headerHeight = 0,
        cardInsetX = padding,
        cardInsetY = 8,
        cardBottomInset = 8,
        -- 保留原来的外框总高度基线；紧凑首行只把后续行上移，留下底部安全
        -- 留白，避免 slider 的数值输入框贴住外框。
        height = math.max(1, 68 + (rows - 1) * rowStep + heightOffset),
    }
end

function EXUI:CreateModuleCommonSettingsGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and opts.bindRoot ~= true and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    local groupWidth = width or 760
    local flow = self:BuildModuleCommonSettingsFlow(groupWidth, opts)
    local groupHeight = flow.height
    local group, isNew = AcquireCompositeGroup(opts.poolType or "CompositeModuleCommonSettingsGroup", parent)
    EXUI:ClearControlSurface(group)
    group._exCompositeLabel = label or L["模块通用设置"]
    -- modulecommonsettings 的 fields 是模块声明的动态结构，不能像字体/计时条/图标
    -- 等固定结构组那样整树复用。先归还上一轮的子控件，再按本轮 fields 建立；外壳
    -- 仍是 CompositeHost 池，标准 checkbox/dropdown/slider/input/color 仍各自回到既有池。
    if not isNew and group._exClearModuleCommonEntries then
        group:_exClearModuleCommonEntries()
    end
    BindCompositeGroup(group, db, onUpdate, opts)
    group._moduleCommonDb = db
    -- Grid 容器可能在同一帧被其他页面激活；页面需要能把实际显示的宿主
    -- 明确重绑回本次渲染的模块 DB，不能依赖对象池残留引用。
    group.RebindDB = function(self, nextDB)
        if type(nextDB) ~= "table" then return false end
        BindCompositeGroup(self, nextDB, self._exCompositeOnUpdate, self._exCompositeOpts)
        self._moduleCommonDb = nextDB
        return true
    end
    if not isNew then
        group:_exBuildModuleCommonEntries(flow)
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        return group
    end

    group:SetSize(groupWidth, groupHeight)

    local content = CreateFrame("Frame", nil, group)
    content:SetPoint("TOPLEFT", 0, 0)
    local settingsCard = CreateFrame("Frame", nil, content)

    local function EmitUpdate() CompositeEmitUpdate(group) end
    -- Root-bound ModuleCommon cards have no group prefix.  Their Checkbox /
    -- Dropdown / Input controls still need a real leaf path; forwarding the
    -- empty group path makes NotifyModuleValueChanged reject the change.
    local function NotifyModuleCommonField(path)
        local metadata = group._exCompositeOpts and group._exCompositeOpts._exWriteContext
        if metadata == nil then return false end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateModuleCommonSettingsGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix
        if prefix ~= nil and type(prefix) ~= "string" then
            error("CreateModuleCommonSettingsGroup Grid write context pathPrefix must be string or nil", 2)
        end
        local fullPath = type(prefix) == "string" and prefix ~= "" and (prefix .. "." .. path) or path
        EXUI:NotifyModuleValueChanged(metadata.moduleKey, fullPath, "committed")
        return true
    end
    local function SetValue(path, value, phase)
        CompositePathSet(group._exCompositeDb, path, value)
        -- 外部 DatabaseChanged 监听负责运行时同步；页面自己的预览则不应依赖那条
        -- 异步链。允许宿主在“字段已写入同一份 DB”的瞬间直接重套预览样式。
        if phase ~= "live" and type(group._exCompositeOpts.onFieldChanged) == "function" then
            group._exCompositeOpts.onFieldChanged(group._exCompositeDb, path, value)
        end
        if phase ~= "live" and not NotifyModuleCommonField(path) then EmitUpdate() end
    end

    -- ModuleCommonSettings 的连续 Slider 通过唯一 ModuleDB 通知流重套表面。
    local function CreateModuleCommonNotifyFlow(path)
        local metadata = group._exCompositeOpts and group._exCompositeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateModuleCommonSettingsGroup requires Grid write context", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateModuleCommonSettingsGroup requires CreateModuleNotifyFlow", 2)
        end
        local prefix = metadata.pathPrefix
        if prefix ~= nil and type(prefix) ~= "string" then
            error("CreateModuleCommonSettingsGroup Grid write context pathPrefix must be string or nil", 2)
        end
        local fullPath = type(prefix) == "string" and prefix ~= "" and (prefix .. "." .. path) or path
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = fullPath,
            readValue = function() return CompositePathValue(group._exCompositeDb, path) end,
            -- Core controller owns the only commit refresh.  live writes must
            -- not broadcast DatabaseChanged or rebuild this page.
            writeValue = function(value) SetValue(path, value, "live") end,
        })
    end

    group._exClearModuleCommonEntries = function(self)
        local factory = _G.ExwindFactory
        for _, mounted in ipairs(self._exModuleCommonEntries or {}) do
            local control = mounted.control
            if control then EXUI:RestoreSettingsListControl(control) end
            if mounted.row and mounted.row.Release then mounted.row:Release() end
            if control and control._fromPool and factory then
                factory:Release(control._fromPool, control)
            elseif control then
                control:Hide()
                control:ClearAllPoints()
            end
            if mounted.card then
                mounted.card:Hide()
                mounted.card:ClearAllPoints()
            end
        end
        self._exModuleCommonEntries = {}
        self._exCompositeControls = {}
    end

    group._exBuildModuleCommonEntries = function(self, nextFlow)
        local activeFields = nextFlow.fields or {}
        local activeDb = self._exCompositeDb or {}
        self._exModuleCommonEntries = {}
        self._exModuleCommonCards = self._exModuleCommonCards or {}
        for index, field in ipairs(activeFields) do
            local path = tostring(field.path or field.key or "")
            if path ~= "" or field.type == "button" then
                local flowEntry = nextFlow.entries[index]
                local value = CompositePathValue(activeDb, path)
            local control, kind = nil, nil
            -- 保留每个控件的独立承载 Frame（下拉/对象池会依赖它的局部父级），
            -- 但取消背景与边框：视觉上只保留模块通用设置的外层卡片，不再出现小方格。
            local card = self._exModuleCommonCards[index]
            if not card then
                card = CreateFrame("Frame", nil, settingsCard, "BackdropTemplate")
                self._exModuleCommonCards[index] = card
                card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                card:SetBackdropColor(0, 0, 0, 0)
                card:SetBackdropBorderColor(0, 0, 0, 0)
            end
            card:SetParent(settingsCard)
            card:Show()
            card:SetSize(flowEntry.width, flowEntry.height)
            card:SetPoint("TOPLEFT", flowEntry.x, flowEntry.y)
            local row
            if nextFlow.settingsList then
                row = EXUI:CreateSettingsRow(card, {
                    label = field.label or field.path or field.key,
                    description = field.description,
                    controlWidth = field.controlWidth,
                    controlKind = IsModuleCommonOrdinaryField(field) and "ordinary" or nil,
                    inputWidthPercent = field.inputWidthPercent,
                    isLast = index == #activeFields,
                })
            end
            if field.type == "button" then
                control = EXUI:CreateButton(card, flowEntry.width - 20, 28, field.label or path, function()
                    local structureResult
                    if type(field.onClick) == "function" then
                        structureResult = field.onClick(self._exCompositeDb)
                    end
                    CompositeEmitUpdate(self)
                    if type(self._exCompositeOpts.onStructureChanged) == "function" then
                        self._exCompositeOpts.onStructureChanged(structureResult)
                    end
                end, { variant = field.variant })
                control:SetPoint("TOPLEFT", 10, -16)
                kind = "button"
            elseif field.type == "checkbox" then
                control = EXUI:CreateCheckbox(card, field.label or path, value == true, function(v) self._exModuleCommonSetValue(path, v == true) end)
                control:SetPoint("TOPLEFT", 10, -11)
                kind = "check"
            elseif field.type == "dropdown" then
                control = EXUI:CreateDropdown(card, flowEntry.width - 20, field.label or path, field.items or {}, value, function(v) self._exModuleCommonSetValue(path, v) end)
                control:SetPoint("TOPLEFT", 10, -25)
                kind = "dropdown"
            elseif field.type == "lsm_background" or field.type == "lsm_border" or field.type == "lsm_texture" then
                local mediaType = field.type == "lsm_background" and "background"
                    or (field.type == "lsm_border" and "border" or "statusbar")
                control = EXUI:CreateLSMTextureDropdown(card, mediaType, flowEntry.width - 20, field.label or path, value, function(v)
                    self._exModuleCommonSetValue(path, v)
                end)
                control:SetPoint("TOPLEFT", 10, -25)
                kind = "dropdown"
            elseif field.type == "input" then
                control = EXUI:CreateEditBox(card, tostring(value or ""), flowEntry.width - 20, 28, field.label or path, {
                    labelPos = "top",
                    onEnter = function(v) SetValue(path, v or "") end,
                    onEditFocusLost = function(v) SetValue(path, v or "") end,
                })
                control:SetPoint("TOPLEFT", 10, -16)
                kind = "edit"
            elseif field.type == "color" then
                -- 颜色值仍按现有 R/G/B/A 字段保存；仅由通用封装组承载，
                -- 不让模块退回为四个散装滑动条。
                local colorDB, colorKey = self._exCompositeDb, path
                local colorParentPath, directColorKey = path:match("^(.*)%.([^%.]+)$")
                if colorParentPath and directColorKey then
                    local target = self._exCompositeDb
                    for part in string.gmatch(colorParentPath, "[^%.]+") do
                        target[part] = type(target[part]) == "table" and target[part] or {}
                        target = target[part]
                    end
                    colorDB, colorKey = target, directColorKey
                end
                control = EXUI:CreateColorButton(card, field.label or path, colorDB, colorKey, true, function()
                    if type(self._exCompositeOpts.onFieldChanged) == "function" then
                        self._exCompositeOpts.onFieldChanged(self._exCompositeDb, path)
                    end
                    if not NotifyModuleCommonField(path) then CompositeEmitUpdate(self) end
                end)
                control:SetPoint("TOPLEFT", 10, -14)
                kind = "color"
            else
                local lifecycle = CreateModuleCommonNotifyFlow(path)
                if lifecycle then
                    control = EXUI:CreateSlider(card, flowEntry.width - 20, field.label or path,
                        tonumber(field.min) or 0, tonumber(field.max) or 100, tonumber(value) or tonumber(field.min) or 0,
                        tonumber(field.step) or 1, nil, lifecycle)
                else
                    control = EXUI:CreateSlider(card, flowEntry.width - 20, field.label or path,
                        tonumber(field.min) or 0, tonumber(field.max) or 100, tonumber(value) or tonumber(field.min) or 0,
                        tonumber(field.step) or 1, nil, function(v) self._exModuleCommonSetValue(path, v) end)
                end
                control:SetPoint("TOPLEFT", 10, -8)
                kind = "slider"
            end
            if field.type ~= "button" then
                RegisterCompositeControl(self, control, path, kind)
            end
                if row and control then
                    EXUI:PrepareSettingsListControl(control, {
                        hideLabel = true,
                        presentation = field.presentation or ((self._exCompositeOpts
                            and self._exCompositeOpts._exTypedSettings == true
                            and field.type == "checkbox") and "switch" or nil),
                        ordinaryControl = IsModuleCommonOrdinaryField(field),
                        valuePosition = field.type == "slider" and (field.valuePosition or "right") or nil,
                    })
                end
                self._exModuleCommonEntries[index] = {
                    card = card, control = control, kind = kind, field = field, row = row,
                }
            end
        end
    end
    group._exModuleCommonSetValue = SetValue
    group:_exBuildModuleCommonEntries(flow)

    group._exApplyModuleCommonFlow = function(self, nextFlow)
        self._exModuleCommonFlow = nextFlow
        -- 只有在线编辑器新增的空背景卡片允许其 layout.h 控制高度。其余
        -- ModuleCommon 仍由真实 fields Flow 固定高度，避免正式页面产生空白或裁切。
        if self._exCompositeOpts and self._exCompositeOpts.gridEditableHeight == true then
            self._exGridFixedHeight = nil
        else
            self._exGridFixedHeight = nextFlow.height
        end
        self:SetSize(nextFlow.width, nextFlow.height)
        EXUI:ClearControlSurface(self)
        local cardInsetX = tonumber(nextFlow.cardInsetX)
        if cardInsetX == nil then cardInsetX = nextFlow.padding or 0 end
        local cardInsetY = tonumber(nextFlow.cardInsetY) or 8
        local cardBottomInset = tonumber(nextFlow.cardBottomInset) or cardInsetY
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", 0, 0)
        content:SetSize(nextFlow.width, math.max(1, nextFlow.height))
        settingsCard:ClearAllPoints()
        settingsCard:SetPoint("TOPLEFT", content, "TOPLEFT", cardInsetX, -cardInsetY)
        local cardHeight = tonumber(nextFlow.cardHeight)
            or math.max(1, nextFlow.height - cardInsetY - cardBottomInset)
        settingsCard:SetSize(nextFlow.width - cardInsetX * 2, cardHeight)
        if nextFlow.settingsList then
            settingsCard:SetSize(nextFlow.width, nextFlow.height)
            for index, entry in ipairs(nextFlow.entries) do
                local mounted = self._exModuleCommonEntries[index]
                if mounted then
                    local rowHeight, controlX, controlY, controlWidth = EXUI:UpdateSettingsRowLayout(
                        mounted.row, entry.width, entry.controlHeight)
                    mounted.card:ClearAllPoints()
                    mounted.card:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", 0, entry.y)
                    mounted.card:SetSize(entry.width, rowHeight)
                    mounted.row:ClearAllPoints()
                    mounted.row:SetPoint("TOPLEFT", mounted.card, "TOPLEFT", 0, 0)
                    local control = mounted.control
                    if control then
                        if control.SetWidth then control:SetWidth(controlWidth) end
                        EXUI:UpdateSettingsListControlLayout(control, controlWidth)
                        control:ClearAllPoints()
                        local actualHeight = control.GetHeight and control:GetHeight() or entry.controlHeight
                        local visualInset = math.max(0, (entry.controlHeight - actualHeight) * 0.5)
                        control:SetPoint("TOPLEFT", mounted.card, "TOPLEFT", controlX, -(controlY + visualInset))
                    end
                end
            end
            return
        end
        for index, entry in ipairs(nextFlow.entries) do
            local mounted = self._exModuleCommonEntries[index]
            if mounted then
                mounted.card:ClearAllPoints()
                mounted.card:SetPoint("TOPLEFT", settingsCard, "TOPLEFT",
                    entry.x - (nextFlow.entryOriginX or nextFlow.padding or 0), entry.y + nextFlow.contentTopInset)
                mounted.card:SetSize(entry.width, entry.height)
                local control = mounted.control
                if control then
                    if control.SetWidth then control:SetWidth(math.max(1, entry.width - 20)) end
                    control:ClearAllPoints()
                    if mounted.kind == "button" or mounted.kind == "edit" then
                        control:SetPoint("TOPLEFT", 10, -16)
                    elseif mounted.kind == "check" then
                        control:SetPoint("TOPLEFT", 10, -11)
                    elseif mounted.kind == "color" then
                        control:SetPoint("TOPLEFT", 10, -14)
                    else
                        control:SetPoint("TOPLEFT", 10, -25)
                    end
                end
            end
        end
    end
    group._exCompositeReflow = function(self, nextWidth)
        self:_exApplyModuleCommonFlow(EXUI:BuildModuleCommonSettingsFlow(nextWidth, self._exCompositeOpts))
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)

    group.RefreshFromDB = function(self)
        BindCompositeGroup(self, self._exCompositeDb, self._exCompositeOnUpdate, self._exCompositeOpts)
    end
    AttachCompositeRelease(group)
    return group
end

-- Aura Application Bar 是独立原生 Region：它只接收 maxApplications，
-- 不能借用普通计时条的 duration/fill/icon 设置，避免产生“能改但不会生效”的假控件。
-- Aura Duration Bar 同样是 AuraButton Adapter 绑定的原生 Region，而不是
-- TimerBarWidget。它故意不暴露图标、图标边框、填充模式等 TimerBar 专属字段：
-- 这些 Region 在原生 Aura Duration Bar 中不存在，暴露它们就是假 GUI。
function EXUI:CreateAuraDurationBarGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    local fields = {
        { path = "enabled", type = "checkbox", label = L["启用计时条"] },
        { path = "texture", type = "input", label = L["条体材质"] },
        { path = "width", type = "slider", label = L["宽度"], min = 1, max = 800, step = 1 },
        { path = "height", type = "slider", label = L["高度"], min = 1, max = 120, step = 1 },
        { path = "x", type = "slider", label = L["X 偏移"], min = -1000, max = 1000, step = 1 },
        { path = "y", type = "slider", label = L["Y 偏移"], min = -1000, max = 1000, step = 1 },
        { path = "barColor", type = "color", label = L["前景颜色"] },
        { path = "barBgColor", type = "color", label = L["背景颜色"] },
        { path = "showBorder", type = "checkbox", label = L["显示边框"] },
        { path = "borderTexture", type = "input", label = L["边框材质"] },
        { path = "borderSize", type = "slider", label = L["边框粗细"], min = 0.1, max = 16, step = 0.1 },
        { path = "borderPadding", type = "slider", label = L["边框内距"], min = -32, max = 32, step = 1 },
        { path = "borderColor", type = "color", label = L["边框颜色"] },
    }
    if opts.forceEnabled and type(db) == "table" then
        local targetKey = key or "durationBar"
        db[targetKey] = type(db[targetKey]) == "table" and db[targetKey] or {}
        db[targetKey].enabled = true
        table.remove(fields, 1)
    end
    return self:CreateModuleCommonSettingsGroup(parent, width, label or L["计时条（原生 Aura Duration Bar）"], db, key or "durationBar", onUpdate, {
        columns = 3,
        poolType = opts.forceEnabled and "CompositeAuraDurationBarMainGroup" or "CompositeAuraDurationBarGroup",
        fields = fields,
    })
end

function EXUI:CreateAuraApplicationBarGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    local fields = {
        { path = "enabled", type = "checkbox", label = L["启用层数条"] },
            { path = "maxApplications", type = "slider", label = L["最大层数"], min = 1, max = 99, step = 1 },
            { path = "texture", type = "input", label = L["条体材质"] },
            { path = "width", type = "slider", label = L["宽度"], min = 1, max = 800, step = 1 },
            { path = "height", type = "slider", label = L["高度"], min = 1, max = 120, step = 1 },
            { path = "x", type = "slider", label = L["X 偏移"], min = -1000, max = 1000, step = 1 },
            { path = "y", type = "slider", label = L["Y 偏移"], min = -1000, max = 1000, step = 1 },
            { path = "barColor", type = "color", label = L["前景颜色"] },
            { path = "barBgColor", type = "color", label = L["背景颜色"] },
    }
    if opts.forceEnabled and type(db) == "table" then
        local targetKey = key or "applicationBar"
        db[targetKey] = type(db[targetKey]) == "table" and db[targetKey] or {}
        db[targetKey].enabled = true
        table.remove(fields, 1)
    end
    return self:CreateModuleCommonSettingsGroup(parent, width, label or L["层数条（原生 Aura Application Bar）"], db, key or "applicationBar", onUpdate, {
        columns = 3,
        poolType = opts.forceEnabled and "CompositeAuraApplicationBarMainGroup" or "CompositeAuraApplicationBarGroup",
        fields = fields,
    })
end

-- =========================================================
-- 20.1 通用锚点设置组
-- 只管理 DB 字段与页面操作；实际 Frame 创建、拖动与依附仍由 AnchorController 负责。
-- =========================================================
function EXUI:CreateAnchorGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}

    local xKey = opts.offsetXKey or "x"
    local yKey = opts.offsetYKey or "y"
    local attachKey = opts.attachEnabledKey or "attachToCustom"
    local targetKey = opts.attachTargetKey or "customAttachTarget"
    local supportsCustomAttach = opts.allowCustomAttach ~= false
    local defaultX = tonumber(opts.defaultOffsetX) or 0
    local defaultY = tonumber(opts.defaultOffsetY) or 0
    local groupWidth = width or 760
    local groupHeight = 52

    if db[xKey] == nil then db[xKey] = defaultX end
    if db[yKey] == nil then db[yKey] = defaultY end
    if supportsCustomAttach and db[attachKey] == nil then db[attachKey] = false end
    if supportsCustomAttach and db[targetKey] == nil then db[targetKey] = "" end

    local group, isNew = AcquireCompositeGroup("CompositeAnchorGroup", parent)
    group._exCompositeLabel = label or L["锚点设置"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        EXUI:ClearControlSurface(group)
        if group._exAnchorRefresh then group:_exAnchorRefresh() end
        return group
    end

    local proxy = CreateCompositeProxy(group)
    db = proxy
    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local function EmitUpdate() CompositeEmitUpdate(group) end
    -- 锚点是否启用只控制是否跟随目标；X/Y 仍是模块自身的控件配置，不能在此覆盖。
    -- 输入框与选择器常驻，方便先填路径再启用，不因勾选状态造成控件跳动。
    local attach, target, picker
    if supportsCustomAttach then
        attach = EXUI:CreateCheckbox(group, L["启用"], db[attachKey] == true, function(value)
            db[attachKey] = value == true
            EmitUpdate()
        end)
        attach:SetPoint("TOPLEFT", 16, -15)
        RegisterCompositeControl(group, attach, attachKey, "check")

        local targetWidth = math.max(180, groupWidth - 330)
        target = EXUI:CreateEditBox(group, tostring(db[targetKey] or ""), targetWidth, 28, nil, {
            onEnter = function(value) db[targetKey] = value or ""; EmitUpdate() end,
            onEditFocusLost = function(value) db[targetKey] = value or ""; EmitUpdate() end,
        })
        target:SetPoint("TOPLEFT", 142, -10)
        RegisterCompositeControl(group, target, targetKey, "edit")

        picker = EXUI:CreateButton(group, 108, 28, L["选择框架"], function()
            if type(group._exCompositeOpts.onPickFrame) == "function" then
                group._exCompositeOpts.onPickFrame(group._exCompositeDb)
            end
        end)
        picker:SetPoint("TOPRIGHT", -16, -10)
        picker:SetShown(type(opts.onPickFrame) == "function")
    end

    group._anchorDb = proxy
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        EXUI:ClearControlSurface(self)
        if not supportsCustomAttach then return end
        local nextTargetWidth = math.max(180, nextWidth - 330)
        target:SetWidth(nextTargetWidth)
        attach:ClearAllPoints(); attach:SetPoint("LEFT", self, "LEFT", 16, 0)
        target:ClearAllPoints(); target:SetPoint("LEFT", self, "LEFT", 142, 0)
        picker:ClearAllPoints(); picker:SetPoint("RIGHT", self, "RIGHT", -16, 0)
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 21. 通用材质设置组
-- 用于普通 / Aura 显示的静态材质外观；宿主决定数据来源与生命周期。
-- =========================================================
function EXUI:CreateTextureGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    local defaults = {
        fileID = "", width = 128, height = 128, x = 0, y = 0,
        alpha = 1, scale = 1, rotation = 0, flipH = false, flipV = false,
        colorR = 1, colorG = 1, colorB = 1, colorA = 1, blendMode = "BLEND",
    }
    for field, value in pairs(defaults) do
        if db[field] == nil then db[field] = value end
    end

    local groupWidth = width or 760
    local group, isNew = AcquireCompositeGroup("CompositeTextureGroup", parent)
    group._exCompositeLabel = label or L["材质"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, 250)
        if group._exTextureConfigure then group:_exTextureConfigure() end
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy
    group:SetSize(groupWidth, 250)
    group:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    group:SetBackdropColor(unpack(MC.panel))
    group:SetBackdropBorderColor(unpack(MC.border))

    local accent = EXUI:CreateVisualTexture(group, EXBASEFRAME)
    accent:SetPoint("TOPLEFT", 7, -11)
    accent:SetSize(3, 20)
    accent:SetColorTexture(unpack(MC.blue))
    local title = EXUI:CreateVisualFontString(group, EXFONTFRAME, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -8)
    title:SetText(group._exCompositeLabel)
    StyleModernTitle(title)
    group._exCompositeTitle = title

    local function EmitUpdate() CompositeEmitUpdate(group) end
    local function AddSlider(field, titleText, minValue, maxValue, step, x, y, controlWidth)
        local slider = EXUI:CreateSlider(group, controlWidth or 170, titleText, minValue, maxValue, db[field], step, nil,
            function(value)
                db[field] = value
                EmitUpdate()
            end)
        slider:SetPoint("TOPLEFT", x, y)
        return RegisterCompositeControl(group, slider, field, "slider")
    end

    local fileInput = EXUI:CreateEditBox(group, tostring(db.fileID or ""), math.min(310, groupWidth - 48), 28,
        L["FileDataID / 路径"], {
            onEnter = function(value)
                db.fileID = tostring(value or "")
                EmitUpdate()
            end,
            onEditFocusLost = function(value)
                db.fileID = tostring(value or "")
                EmitUpdate()
            end,
            labelPos = "top",
        })
    fileInput:SetPoint("TOPLEFT", 16, -54)
    RegisterCompositeControl(group, fileInput, "fileID", "edit")

    -- 选择器是材质组件本身的可选能力。模块只能提供“如何挑选”的
    -- 回调，不能在自己的 Editor 里再创建/定位一枚私有按钮；这样池化
    -- 后也始终读取本次绑定的 DB 与回调。
    local texturePicker = EXUI:CreateButton(group, 108, 28, opts.pickerLabel or L["选择材质"], function()
        local activeOpts = group._exCompositeOpts or {}
        if type(activeOpts.onPickTexture) ~= "function" then return end
        activeOpts.onPickTexture(group._exCompositeDb and group._exCompositeDb.fileID, function(textureID)
            if type(group._exCompositeDb) ~= "table" then return end
            group._exCompositeDb.fileID = tostring(textureID or "")
            EXUI:RefreshCompositeGroupFromDB(group)
            CompositeEmitUpdate(group)
        end)
    end)
    texturePicker:SetPoint("TOPRIGHT", -16, -54)
    group._exTexturePickerButton = texturePicker
    group._exTextureConfigure = function(self)
        local activeOpts = self._exCompositeOpts or {}
        local picker = self._exTexturePickerButton
        if not picker then return end
        if picker.SetText then picker:SetText(activeOpts.pickerLabel or L["选择材质"]) end
        picker:SetShown(type(activeOpts.onPickTexture) == "function")
    end
    group:_exTextureConfigure()

    local widthSlider = AddSlider("width", L["宽度"], 1, 1024, 1, 16, -116)
    local heightSlider = AddSlider("height", L["高度"], 1, 1024, 1, 204, -116)
    local xSlider = AddSlider("x", L["X 偏移"], -1000, 1000, 1, 392, -116)
    local ySlider = AddSlider("y", L["Y 偏移"], -1000, 1000, 1, 580, -116)
    local alphaSlider = AddSlider("alpha", L["透明度"], 0, 1, 0.05, 16, -176)
    local scaleSlider = AddSlider("scale", L["缩放"], 0.05, 5, 0.05, 204, -176)
    local rotationSlider = AddSlider("rotation", L["旋转"], -180, 180, 1, 392, -176)

    local color = EXUI:CreateColorButton(group, L["材质颜色"], db, "color", true, EmitUpdate)
    color:SetPoint("TOPLEFT", 580, -164)
    RegisterCompositeControl(group, color, "", "color")
    local blend = EXUI:CreateDropdown(group, math.min(220, groupWidth - 48), L["混合模式"], {
        { "BLEND", "BLEND" }, { "ADD", "ADD" }, { "MOD", "MOD" },
        { "ALPHAKEY", "ALPHAKEY" }, { "DISABLE", "DISABLE" },
    }, db.blendMode, function(value)
        db.blendMode = value
        EmitUpdate()
    end)
    blend:SetPoint("TOPLEFT", 16, -226)
    RegisterCompositeControl(group, blend, "blendMode", "dropdown")

    local flipH = EXUI:CreateCheckbox(group, L["水平翻转"], db.flipH, function(value)
        db.flipH = value
        EmitUpdate()
    end)
    flipH:SetPoint("TOPLEFT", 254, -222)
    RegisterCompositeControl(group, flipH, "flipH", "check")
    local flipV = EXUI:CreateCheckbox(group, L["垂直翻转"], db.flipV, function(value)
        db.flipV = value
        EmitUpdate()
    end)
    flipV:SetPoint("TOPLEFT", 394, -222)
    RegisterCompositeControl(group, flipV, "flipV", "check")
    group._textureDb = proxy
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local columnWidth = math.max(120, math.floor((nextWidth - 68) / 4))
        local col1 = 16
        local col2 = col1 + columnWidth + 18
        local col3 = col2 + columnWidth + 18
        local col4 = col3 + columnWidth + 18
        local fileWidth = math.min(310, math.max(160, nextWidth - 48))
        fileInput:SetWidth(fileWidth)
        texturePicker:ClearAllPoints(); texturePicker:SetPoint("TOPRIGHT", self, "TOPRIGHT", -16, -54)
        local top = { widthSlider, heightSlider, xSlider, ySlider }
        local topX = { col1, col2, col3, col4 }
        for index, slider in ipairs(top) do
            slider:SetWidth(columnWidth)
            slider:ClearAllPoints(); slider:SetPoint("TOPLEFT", self, "TOPLEFT", topX[index], -116)
        end
        for index, slider in ipairs({ alphaSlider, scaleSlider, rotationSlider }) do
            slider:SetWidth(columnWidth)
            slider:ClearAllPoints(); slider:SetPoint("TOPLEFT", self, "TOPLEFT", topX[index], -176)
        end
        color:ClearAllPoints(); color:SetPoint("TOPLEFT", self, "TOPLEFT", col4, -164)
        blend:SetWidth(math.min(220, math.max(120, nextWidth - 48)))
        flipH:ClearAllPoints(); flipH:SetPoint("TOPLEFT", self, "TOPLEFT", col2 + 50, -222)
        flipV:ClearAllPoints(); flipV:SetPoint("TOPLEFT", self, "TOPLEFT", col3 + 2, -222)
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, 250)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 21.1 Aura 语义设置组
-- EXAura 只声明它要使用哪一种能力；控件树、对象池重绑与释放全部归 EXUI。
-- =========================================================
function EXUI:CreateAuraDispelBorderGroup(parent, width, label, db, key, onUpdate)
    return self:CreateModuleCommonSettingsGroup(parent, width, label or L["驱散边框"], db, key or "auraBorder", onUpdate, {
        columns = 3,
        poolType = "CompositeAuraDispelBorderGroup",
        fields = {
            { path = "enabled", type = "checkbox", label = L["启用驱散边框"] },
            { path = "showIcon", type = "checkbox", label = L["驱散边框带图标"] },
            { path = "style", type = "dropdown", label = L["驱散边框样式"], items = { { "Atlas", 0 }, { "Color", 1 } } },
        },
    })
end

function EXUI:CreateAuraSortGroup(parent, width, label, db, key, onUpdate)
    return self:CreateModuleCommonSettingsGroup(parent, width, label or L["Aura 内容排序"], db, key or "sort", onUpdate, {
        columns = 2,
        poolType = "CompositeAuraSortGroup",
        fields = {
            { path = "method", type = "dropdown", label = L["排序方式"], items = {
                { "默认", 0 }, { L["大减伤"], 1 }, { L["单位框减益"], 2 }, { L["仅重要"], 3 }, { L["到期"], 4 },
                { L["仅按到期"], 5 }, { L["名称"], 6 }, { L["仅按名称"], 7 }, { L["Aura 实例 ID"], 8 },
            } },
            { path = "direction", type = "dropdown", label = L["排序方向"], items = { { L["正常"], 0 }, { L["反向"], 1 } } },
        },
        onFieldChanged = function(target, path, value)
            if path == "method" or path == "direction" then target[path] = tonumber(value) or 0 end
        end,
    })
end

-- 这是 Aura 子元素的唯一结构性编辑器。它与 FontGroup/通用字段组一样
-- 由 Composite Host 管理，借用、重绑、释放不会把上一个规则的回调遗留在页面上。
function EXUI:CreateAuraChildElementsGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    local target = db
    if key and type(target) == "table" then
        target[key] = type(target[key]) == "table" and target[key] or {}
        target = target[key]
    end
    target = type(target) == "table" and target or {}
    target.children = type(target.children) == "table" and target.children or {}

    local function NewChild(kind)
        if kind == "glow" then
            return { type = "glow", enabled = true, glowStyle = "Action Button Glow", glowColorR = 1, glowColorG = 1, glowColorB = 1, glowColorA = 1, glowOffset = 0, glowFrequency = 1, glowScale = 1 }
        end
        return { type = "text", enabled = true, text = L["文本"], font = "默认", size = 14, r = 1, g = 1, b = 1, a = 1, outline = "OUTLINE", shadow = false, x = 0, y = 0, justifyH = "CENTER", justifyV = "MIDDLE" }
    end
    local fields = {
        { type = "button", label = L["+ 文本"], onClick = function(activeTarget)
            activeTarget.children = type(activeTarget.children) == "table" and activeTarget.children or {}
            activeTarget.children[#activeTarget.children + 1] = NewChild("text")
            return #activeTarget.children
        end },
        { type = "button", label = L["+ 发光"], onClick = function(activeTarget)
            activeTarget.children = type(activeTarget.children) == "table" and activeTarget.children or {}
            activeTarget.children[#activeTarget.children + 1] = NewChild("glow")
            return #activeTarget.children
        end },
    }
    for index, child in ipairs(target.children) do
        local prefix = "children." .. tostring(index)
        fields[#fields + 1] = { path = prefix .. ".enabled", type = "checkbox", label = (child.type == "glow" and L["发光"] or L["文本"]) .. L[" 子元素 "] .. tostring(index) .. L[" · 启用"] }
        fields[#fields + 1] = { type = "button", variant = "danger", label = L["删除 子元素 "] .. tostring(index), onClick = function(activeTarget)
            if type(activeTarget.children) == "table" then table.remove(activeTarget.children, index) end
        end }
        if child.type == "glow" then
            fields[#fields + 1] = { path = prefix .. ".glowStyle", type = "dropdown", label = L["发光 "] .. tostring(index) .. L[" · 样式"], items = { { L["动作条发光"], "Action Button Glow" }, { L["Proc 发光"], "Proc Alt Glow" } } }
            fields[#fields + 1] = { path = prefix .. ".glowColor", type = "color", label = L["发光 "] .. tostring(index) .. L[" · 颜色"] }
            fields[#fields + 1] = { path = prefix .. ".glowFrequency", type = "slider", label = L["发光 "] .. tostring(index) .. L[" · 频率"], min = 0.1, max = 5, step = 0.1 }
            fields[#fields + 1] = { path = prefix .. ".glowScale", type = "slider", label = L["发光 "] .. tostring(index) .. L[" · 大小"], min = 0.5, max = 3, step = 0.1 }
            fields[#fields + 1] = { path = prefix .. ".glowOffset", type = "slider", label = L["发光 "] .. tostring(index) .. L[" · 边距"], min = -50, max = 50, step = 1 }
        else
            -- 子元素必须仍是这一个 Composite Host 的字段，而不是 Editor 再在
            -- 外面拼一组 FontGroup。结构变化由 onStructureChanged 请求整页
            -- 重渲染；每一次渲染都只有一个可测量、可回收的根。
            fields[#fields + 1] = { path = prefix .. ".text", type = "input", label = L["文本 "] .. tostring(index) .. L[" · 示例"] }
            fields[#fields + 1] = { path = prefix .. ".font", type = "input", label = L["文本 "] .. tostring(index) .. L[" · 字体"] }
            fields[#fields + 1] = { path = prefix .. ".size", type = "slider", label = L["文本 "] .. tostring(index) .. L[" · 大小"], min = 6, max = 72, step = 1 }
            fields[#fields + 1] = { path = prefix .. ".color", type = "color", label = L["文本 "] .. tostring(index) .. L[" · 颜色"] }
            fields[#fields + 1] = { path = prefix .. ".x", type = "slider", label = L["文本 "] .. tostring(index) .. L[" · X 偏移"], min = -1000, max = 1000, step = 1 }
            fields[#fields + 1] = { path = prefix .. ".y", type = "slider", label = L["文本 "] .. tostring(index) .. L[" · Y 偏移"], min = -1000, max = 1000, step = 1 }
        end
    end
    -- 每一种子元素序列各有稳定的池键；同一种结构复用时只 Rebind，
    -- 增删元素后则借用匹配新字段数的宿主，绝不让旧字段树伪装成新结构。
    local signature = {}
    for _, child in ipairs(target.children) do signature[#signature + 1] = child.type == "glow" and "g" or "t" end
    local manager = self:CreateModuleCommonSettingsGroup(parent, width, label or L["子元素"], target, nil, onUpdate, {
        columns = 2,
        poolType = "CompositeAuraChildElementsGroup_" .. table.concat(signature, ""),
        fields = fields,
        onStructureChanged = opts.onStructureChanged,
    })
    return manager
end

-- 标准组合控件的无副作用 Grid 测量。数值与各 Create*Group 的实际 SetSize
-- 完全一致；将来修改控件高度时，必须同时改这里或改成共享常量，不能让 schema
-- 猜测内部控件树的高度。
local function FixedGridMeasure(height)
    return function()
        return { minHeight = height, preferredHeight = height }
    end
end

EXUI:RegisterGridComponentMeasure("slider", FixedGridMeasure(EXUI.GridSliderHeight))
EXUI:RegisterGridComponentMeasure("fontgroup", function(width)
    local height = ResolveFontGroupHeight(width)
    return { minHeight = height, preferredHeight = height }
end)
EXUI:RegisterGridComponentMeasure("icongroup", function(width)
    local narrow = (tonumber(width) or 750) < 720
    local height = narrow and 296 or 150
    return { minHeight = height, preferredHeight = height }
end)
EXUI:RegisterGridComponentMeasure("timerbargroup", FixedGridMeasure(242))
EXUI:RegisterGridComponentMeasure("texturegroup", FixedGridMeasure(250))
EXUI:RegisterGridComponentMeasure("anchorgroup", FixedGridMeasure(52))
EXUI:RegisterGridComponentMeasure("glow_settings", FixedGridMeasure(250))
EXUI:RegisterGridComponentMeasure("soundgroup", function(width, opts)
    local height = EXUI:BuildSoundGroupLayout(width, opts).height
    return { minHeight = height, preferredHeight = height }
end)
EXUI:RegisterGridComponentMeasure("widgetlayout", function(width, opts)
    local height = BuildWidgetLayoutSettingsFlow(width, opts).height
    return { minHeight = height, preferredHeight = height }
end)
EXUI:RegisterGridComponentMeasure("modulecommonsettings", function(width, opts)
    local flow = EXUI:BuildModuleCommonSettingsFlow(width, opts)
    return { minHeight = flow.height, preferredHeight = flow.height }
end)
-- Aura 专用语义组同样是标准 Composite Host；高度只从同一 Flow 合同推导。
-- 页面 schema 不得复制字段数或手写像素高度。
local function AuraMeasureFields(count)
    local fields = {}
    for index = 1, count do fields[index] = { path = "field" .. tostring(index), type = "slider" } end
    return fields
end
local function AuraFlowMeasure(countResolver)
    return function(width, _, db, item)
        return EXUI:BuildModuleCommonSettingsFlow(width, { fields = AuraMeasureFields(countResolver(db, item)), maxColumns = 4 })
    end
end
EXUI:RegisterGridComponentMeasure("auradurationbargroup", AuraFlowMeasure(function() return 13 end))
EXUI:RegisterGridComponentMeasure("auraapplicationbargroup", AuraFlowMeasure(function() return 9 end))
EXUI:RegisterGridComponentMeasure("auradispelbordergroup", AuraFlowMeasure(function() return 3 end))
EXUI:RegisterGridComponentMeasure("aurasortgroup", AuraFlowMeasure(function() return 2 end))
EXUI:RegisterGridComponentMeasure("aurachildelementsgroup", AuraFlowMeasure(function(db, item)
    local source = type(db) == "table" and db or {}
    local target = item and item.key and type(source[item.key]) == "table" and source[item.key] or source
    local count = 2 -- add text / add glow
    for _, child in ipairs(type(target.children) == "table" and target.children or {}) do
        count = count + 2 + (child.type == "glow" and 5 or 6)
    end
    return count
end))

-- =========================================================
-- StandardModulePage
-- =========================================================
-- 显示模块设置页的唯一非业务外壳。它不读取模块 state、不创建 renderer，也不
-- 解释 layout 内的任何业务字段；模块只能交出正式 binding、既有 Grid layout 与
-- 已存在的 preview surface。页面的 Dock、Scroll、延迟 Grid Render、状态 watch
-- 与释放次序则必须统一由这里拥有，不能再由每一个 EXBoss/EXAura Page 手写一遍。
--
-- preview 合同（StandardPreviewSurface 完成前的最窄过渡接口）：
--   render(dock, context)  -- 必须可重复调用，未来由 StandardPreviewSurface 复用 session
--   release(dock, context) -- 释放该模块的唯一 Panel session
--   refresh(dock, context) -- 可选；未提供时复用 render
-- 以上只接收 Dock 和上下文，不能创建私有 Dock、DB 或业务 renderer。
-- C_Timer.After callbacks do not retain the synchronous call stack that led to
-- Page:Render.  A failure used to look like a silent empty PreviewDock because
-- it could stop between Grid Render and preview.render.  Keep the four public
-- lifecycle stages explicit so the game error has a stable, searchable contract
-- instead of an anonymous delayed-callback stack.
MODERN.standardModulePage = {
    stages = {
        grid = "grid",
        slider = "slider",
        audit = "audit",
        preview = "preview",
    },
}

function MODERN.standardModulePage.BuildStageError(moduleKey, stage, original)
    local stack
    if type(_G.debugstack) == "function" then
        stack = _G.debugstack(3, 40, 40)
    elseif _G.debug and type(_G.debug.traceback) == "function" then
        stack = _G.debug.traceback("", 3)
    else
        stack = "<debug stack unavailable>"
    end
    return "EXUI StandardModulePage stage failed"
        .. " | moduleKey=" .. tostring(moduleKey)
        .. " | stage=" .. tostring(stage)
        .. "\noriginal=" .. tostring(original)
        .. "\nstack=" .. tostring(stack)
end

function MODERN.standardModulePage.RequireFunction(value, name)
    if type(value) ~= "function" then
        error("CreateStandardModulePage requires " .. name .. " function", 3)
    end
    return value
end

function MODERN.standardModulePage.ApplyPreviewDockStyle(dock)
    if not dock then
        error("StandardModulePage requires BackdropTemplate PreviewDock", 3)
    end
    EXUI:ApplyModernPanel(dock, true)
end

MODERN.standardPreview = {
    shellTop = 6,
    shellBottom = 8,
    shellInset = 10,
    canvasGap = 8,
    leftRailWidth = 190,
    rightRailWidth = 54,
    backgroundPresets = {
        { 0.22, 0.25, 0.29 },
        { 0.16, 0.18, 0.21 },
        { 0.11, 0.13, 0.16 },
        { 0.18, 0.21, 0.20 },
    },
}

function MODERN.standardPreview.RefreshBackgroundButtons(canvas)
    local controls = canvas and canvas._exPreviewBackgroundControls
    if not controls then return end
    local selected = tonumber(canvas._exPreviewBackgroundSelection) or 1
    for index, button in ipairs(controls.buttons) do
        if button.selection then button.selection:SetShown(index == selected) end
    end
    local current = canvas._exPreviewBackgroundColor
    if current and controls.customSwatch then
        controls.customSwatch:SetVertexColor(current.r, current.g, current.b, 1)
    end
end

function MODERN.standardPreview.SetBackground(canvas, r, g, b, selection)
    if not canvas then return end
    canvas._exPreviewBackgroundColor = { r = r, g = g, b = b }
    canvas._exPreviewBackgroundSelection = selection
    canvas:SetBackdropColor(r, g, b, 1)
    MODERN.standardPreview.RefreshBackgroundButtons(canvas)
end

function MODERN.standardPreview.OpenBackgroundPicker(canvas)
    local picker = _G.ColorPickerFrame
    if not canvas or not picker or type(picker.SetupColorPickerAndShow) ~= "function" then return end
    local current = canvas._exPreviewBackgroundColor or { r = 0.16, g = 0.18, b = 0.21 }
    local original = { r = current.r, g = current.g, b = current.b }
    local originalSelection = tonumber(canvas._exPreviewBackgroundSelection) or 1
    local function ApplyPickerColor()
        local r, g, b = picker:GetColorRGB()
        MODERN.standardPreview.SetBackground(canvas, r, g, b, 5)
    end
    picker:SetupColorPickerAndShow({
        r = current.r,
        g = current.g,
        b = current.b,
        hasOpacity = false,
        swatchFunc = ApplyPickerColor,
        cancelFunc = function(previous)
            MODERN.standardPreview.SetBackground(canvas,
                previous and previous.r or original.r,
                previous and previous.g or original.g,
                previous and previous.b or original.b,
                originalSelection)
        end,
    })
end

function MODERN.standardPreview.ApplyCanvasStyle(canvas)
    canvas:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    canvas:SetBackdropBorderColor(0.30, 0.34, 0.39, 1)
    if not canvas._exPreviewBackgroundColor then
        local preset = MODERN.standardPreview.backgroundPresets[1]
        MODERN.standardPreview.SetBackground(canvas, preset[1], preset[2], preset[3], 1)
    else
        local color = canvas._exPreviewBackgroundColor
        canvas:SetBackdropColor(color.r, color.g, color.b, 1)
    end
end

function MODERN.standardPreview.CreateToolbar(shell, canvas)
    local toolbar = CreateFrame("Frame", nil, shell)
    toolbar:SetPoint("TOPLEFT", shell, "TOPLEFT", MODERN.standardPreview.shellInset, -MODERN.standardPreview.shellTop)
    toolbar:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -MODERN.standardPreview.shellInset,
        MODERN.standardPreview.shellBottom)

    local label = EXUI:CreateVisualFontString(toolbar, EXFONTFRAME, "GameFontHighlightSmall")
    label:SetText(L["预览背景"] or "预览背景")
    label:SetTextColor(unpack(MC.muted))

    local controls = { buttons = {}, label = label }
    canvas._exPreviewBackgroundControls = controls
    for index = 1, 5 do
        local button = EXUI:CreateButton(toolbar, 26, 26, "", nil, { compact = true })
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT", -14, -16 - ((index - 1) * 28))
        local swatch = EXUI:CreateVisualTexture(button, EXBORDERFRAME)
        swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        swatch:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4)
        swatch:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)
        local selection = CreateFrame("Frame", nil, button, "BackdropTemplate")
        selection:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        selection:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        selection:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        selection:SetBackdropBorderColor(0.42, 0.73, 1, 1)
        selection:EnableMouse(false)
        button.selection = selection
        button.swatch = swatch
        controls.buttons[index] = button
        if index <= #MODERN.standardPreview.backgroundPresets then
            local presetIndex = index
            local preset = MODERN.standardPreview.backgroundPresets[index]
            swatch:SetVertexColor(preset[1], preset[2], preset[3], 1)
            button:SetScript("OnClick", function()
                MODERN.standardPreview.SetBackground(canvas, preset[1], preset[2], preset[3], presetIndex)
            end)
            button:SetScript("OnEnter", function(self)
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText((L["预览背景"] or "预览背景") .. " " .. tostring(presetIndex))
                    GameTooltip:Show()
                end
            end)
        else
            controls.customSwatch = swatch
            button:SetScript("OnClick", function() MODERN.standardPreview.OpenBackgroundPicker(canvas) end)
            button:SetScript("OnEnter", function(self)
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(L["自定义预览背景"] or "自定义预览背景")
                    GameTooltip:Show()
                end
            end)
        end
        button:SetScript("OnLeave", function(self)
            if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        end)
    end
    label:SetPoint("TOP", toolbar, "TOPRIGHT", -(MODERN.standardPreview.rightRailWidth * 0.5), -1)
    MODERN.standardPreview.RefreshBackgroundButtons(canvas)
    return toolbar
end

function MODERN.standardModulePage.ResolveLayout(layout, context)
    local resolved = type(layout) == "function" and layout(context) or layout
    if type(resolved) ~= "table" then
        error("StandardModulePage layout must resolve to a table", 3)
    end
    if resolved.version ~= 1 or type(resolved.sections) ~= "table" or resolved.cards ~= nil then
        error("StandardModulePage accepts only version=1 sections declarations; special cards use their owning page", 3)
    end
    return resolved
end

--- Creates the common page lifecycle for a display module.
--- The returned controller is intentionally the only object a Page may call:
--- `controller:Render(contentFrame)` and `controller:Hide()`.
--- @param options table
---   moduleKey string (required)
---   page table (required; state holder only, no Page methods are replaced)
---   layout table|function(context) -> table (required)
---   binding StandardConfigBinding (optional only when already registered)
---   preview { render=function, release=function, refresh=function?, height=number? }
---   previewDock { dockPolicy="internal-top"|"external-left", ... }
---     external-left requires anchorResolver(contentFrame, context) -> Frame,
---     width=number, offsetX=number and offsetY=number.  EXUI owns the Dock;
---     modules cannot create/re-anchor a private external PreviewDock.
---   getColumns function|number (optional, defaults to 200 logical columns)
---   sliderContract table|function(context)->table (required; Core owns StandardSliderNotify)
---   afterGridLayout function(context) (optional; layout-only, never binders/preview handlers)
function EXUI:CreateStandardModulePage(options)
    if type(options) ~= "table" then error("CreateStandardModulePage requires options table", 2) end
    local moduleKey = self:RequireModuleKey(options.moduleKey, "CreateStandardModulePage")
    local page = options.page
    if type(page) ~= "table" then error("CreateStandardModulePage requires page table", 2) end
    if page._standardModulePage then
        error("StandardModulePage already exists for page: " .. moduleKey, 2)
    end
    if type(options.layout) ~= "table" and type(options.layout) ~= "function" then
        error("CreateStandardModulePage requires layout table/function", 2)
    end

    local binding = options.binding
    if not binding and type(self.GetStandardConfigBinding) == "function" then
        binding = self:GetStandardConfigBinding(moduleKey)
    end
    if type(binding) ~= "table" or binding.moduleKey ~= moduleKey then
        error("CreateStandardModulePage requires registered binding for " .. moduleKey, 2)
    end
    MODERN.standardModulePage.RequireFunction(binding.getConfig, "binding.getConfig")

    local preview = options.preview
    if type(preview) ~= "table" then error("CreateStandardModulePage requires preview surface", 2) end
    local previewRender = MODERN.standardModulePage.RequireFunction(preview.render or preview.Render, "preview.render")
    local previewRelease = MODERN.standardModulePage.RequireFunction(preview.release or preview.Release, "preview.release")

    local previewDockOptions = options.previewDock or {}
    if type(previewDockOptions) ~= "table" then
        error("CreateStandardModulePage previewDock must be table", 2)
    end
    local dockPolicy = previewDockOptions.dockPolicy or "internal-top"
    if dockPolicy ~= "internal-top" and dockPolicy ~= "external-left" then
        error("CreateStandardModulePage previewDock.dockPolicy must be internal-top or external-left", 2)
    end
    local externalDockResolver, externalDockWidth, externalDockOffsetX, externalDockOffsetY
    if dockPolicy == "external-left" then
        externalDockResolver = previewDockOptions.anchorResolver
        externalDockWidth = tonumber(previewDockOptions.width)
        externalDockOffsetX = previewDockOptions.offsetX
        externalDockOffsetY = previewDockOptions.offsetY
        if type(externalDockResolver) ~= "function" then
            error("external-left PreviewDock requires anchorResolver", 2)
        end
        if not externalDockWidth or externalDockWidth <= 0 then
            error("external-left PreviewDock requires fixed positive width", 2)
        end
        if type(externalDockOffsetX) ~= "number" or type(externalDockOffsetY) ~= "number" then
            error("external-left PreviewDock requires fixed numeric offsetX/offsetY", 2)
        end
    end

    local getColumns = options.getColumns or 200
    if type(getColumns) ~= "number" and type(getColumns) ~= "function" then
        error("CreateStandardModulePage getColumns must be number/function", 2)
    end
    local sliderContract = options.sliderContract
    if type(sliderContract) ~= "table" and type(sliderContract) ~= "function" then
        error("CreateStandardModulePage requires sliderContract table/function", 2)
    end
    local afterGridLayout = options.afterGridLayout
    if afterGridLayout ~= nil and type(afterGridLayout) ~= "function" then
        error("CreateStandardModulePage afterGridLayout must be function", 2)
    end
    local applyScrollSkin = options.applyScrollSkin
    if applyScrollSkin ~= nil and type(applyScrollSkin) ~= "function" then
        error("CreateStandardModulePage applyScrollSkin must be function", 2)
    end

    local controller = {
        moduleKey = moduleKey,
        page = page,
        binding = binding,
        layout = options.layout,
        preview = preview,
        previewRender = previewRender,
        previewRelease = previewRelease,
        dockHeight = math.max(1, tonumber(preview.height) or 160),
        dockPolicy = dockPolicy,
        externalDockResolver = externalDockResolver,
        externalDockWidth = externalDockWidth,
        externalDockOffsetX = externalDockOffsetX,
        externalDockOffsetY = externalDockOffsetY,
        getColumns = getColumns,
        sliderContract = sliderContract,
        afterGridLayout = afterGridLayout,
        applyScrollSkin = applyScrollSkin,
        renderGeneration = 0,
        gridRendered = false,
        cardSession = nil,
        previewMounted = false,
    }
    -- Startup audit validates that every module registered a Page and a Slider
    -- declaration.  The resolver is intentionally kept until first Render,
    -- where the actual Grid controls are validated by the lifecycle binder.
    binding.contract.page = true
    binding.contract.slider = sliderContract

    local function BuildContext(self)
        return {
            moduleKey = self.moduleKey,
            page = self.page,
            controller = self,
            dock = self.previewDock,
            scrollFrame = self.scrollFrame,
            scrollChild = self.scrollChild,
            grid = _G.ExwindGrid,
            config = self.binding.getConfig(),
            cardSession = self.cardSession,
        }
    end

    function controller:SetDockHeight(height)
        height = tonumber(height)
        if not height or height <= 0 then error("StandardModulePage dock height must be positive", 2) end
        self.dockHeight = height
        if self.previewDock then self.previewDock:SetHeight(height) end
    end

    function controller:SyncInternalPreviewShellHeight()
        if self.dockPolicy ~= "internal-top" or not self.previewDock or not self.previewShell then return end
        local canvasHeight = math.max(1, tonumber(self.previewDock:GetHeight()) or self.dockHeight)
        local shellHeight = MODERN.standardPreview.shellTop + canvasHeight + MODERN.standardPreview.shellBottom
        self.previewShell:SetHeight(shellHeight)
        if self.previewRow then self.previewRow:SetHeight(shellHeight) end
    end

    function controller:RefreshGridControls()
        local session = self.cardSession
        if session and not session.released and type(session.RefreshValues) == "function" then
            return session:RefreshValues()
        end
        local grid = _G.ExwindGrid
        if grid and self.scrollChild and type(grid.RefreshContainerControlsFromDB) == "function" then
            return grid:RefreshContainerControlsFromDB(self.scrollChild)
        end
        return false
    end

    function controller:ClearActiveOwnership()
        if EXUI.ActivePageScrollFrame == self.scrollFrame then
            EXUI.ActivePageScrollFrame = nil
        end
        if EXUI.ActivePageFrame == self.scrollChild then
            EXUI.ActivePageFrame = nil
            EXUI.CurrentModule = nil
        end
    end

    function controller:ReleasePreview()
        if not self.previewMounted then return end
        self.previewMounted = false
        self.previewRelease(self.previewDock, BuildContext(self))
    end

    function controller:ReleaseGrid()
        local grid = _G.ExwindGrid
        local session = self.cardSession
        self.cardSession = nil
        self.gridRendered = false
        if session then
            if type(session.Release) ~= "function" then
                error("StandardModulePage card session does not implement Release", 2)
            end
            session:Release()
        elseif grid and self.scrollChild and type(grid.ReleaseContainerWidgets) == "function" then
            grid:ReleaseContainerWidgets(self.scrollChild)
        end
    end

    -- A delayed stage failure must leave no live half-page behind.  Cleanup is
    -- deliberately best-effort: its own failure must never replace the actual
    -- Grid/Slider/Audit/Preview exception reported to the developer.
    function controller:AbortFailedRender(generation)
        if self.renderGeneration == generation then
            self.renderGeneration = self.renderGeneration + 1
        end
        pcall(function()
            if self.previewDock then
                -- preview.render can fail after acquiring a session but before
                -- previewMounted becomes true; release unconditionally here.
                self.previewRelease(self.previewDock, BuildContext(self))
            end
        end)
        self.previewMounted = false
        pcall(function() self:ReleaseGrid() end)
        pcall(function() self:ClearActiveOwnership() end)
        pcall(function()
            EXUI:SetPreviewDockScrollOwner(self.previewDock, self, nil)
        end)
        pcall(function()
            if self.previewRow then self.previewRow:Hide() end
            if self.previewShell and self.previewShell ~= self.previewDock then self.previewShell:Hide() end
            if self.previewDock then self.previewDock:Hide() end
        end)
    end

    function controller:RaiseStageFailure(generation, stage, original, isDiagnostic)
        local diagnostic = isDiagnostic and original
            or MODERN.standardModulePage.BuildStageError(self.moduleKey, stage, original)
        self.lastFailedStage = stage
        self.lastFailedError = diagnostic
        self:AbortFailedRender(generation)

        -- Report through WoW's formal error path before rethrowing.  pcall only
        -- protects the error reporter itself; the original stage error is never
        -- swallowed and execution cannot continue with a partial page.
        local handler
        if type(_G.geterrorhandler) == "function" then
            local ok, value = pcall(_G.geterrorhandler)
            if ok and type(value) == "function" then handler = value end
        end
        if handler then pcall(handler, diagnostic) end
        error(diagnostic, 0)
    end

    function controller:RunDelayedStage(generation, stage, callback)
        local ok, result = xpcall(callback, function(original)
            return MODERN.standardModulePage.BuildStageError(self.moduleKey, stage, original)
        end)
        if not ok then
            -- The xpcall error is already structured and includes the original
            -- message/stack.  Keep it intact when sending it to the game handler.
            self:RaiseStageFailure(generation, stage, result, true)
        end
        return result
    end

    function controller:Teardown()
        -- generation 是 C_Timer.After 的取消令牌；不保留页面离开后的延迟 Render。
        self.renderGeneration = self.renderGeneration + 1
        self:ReleasePreview()
        self:ReleaseGrid()
        self:ClearActiveOwnership()
        EXUI:SetPreviewDockScrollOwner(self.previewDock, self, nil)
        if self.previewRow then self.previewRow:Hide() end
        if self.previewShell and self.previewShell ~= self.previewDock then self.previewShell:Hide() end
        if self.previewDock then self.previewDock:Hide() end
    end

    function controller:SyncScrollChildWidth(allowFallback)
        local contentFrame, scrollFrame, scrollChild = self.contentFrame, self.scrollFrame, self.scrollChild
        if not contentFrame or not scrollFrame or not scrollChild then return false end
        if allowFallback ~= true and not scrollFrame:IsShown() then return false end
        local width = tonumber(contentFrame:GetWidth()) or 0
        if width < 100 then
            if allowFallback ~= true then return false end
            width = 820
        end
        local childWidth = math.max(1, width - 16)
        if math.abs((tonumber(scrollChild:GetWidth()) or 0) - childWidth) < 0.5 then return false end
        scrollChild:SetWidth(childWidth)
        return true
    end

    function controller:EnsureFrames(contentFrame)
        if not contentFrame or type(contentFrame.SetPoint) ~= "function" then
            error("StandardModulePage Render requires contentFrame", 2)
        end
        self.contentFrame = contentFrame
        if self.scrollFrame then return end

        local scrollFrame = EXUI:CreateScrollFrame(contentFrame)
        if self.applyScrollSkin then self.applyScrollSkin(scrollFrame) end
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetHeight(1)
        scrollFrame:SetScrollChild(scrollChild)

        local previewRow, previewShell, dock, previewToolbar
        if self.dockPolicy == "internal-top" then
            previewRow = CreateFrame("Frame", nil, contentFrame)
            previewShell = CreateFrame("Frame", nil, previewRow, "BackdropTemplate")
            MODERN.standardModulePage.ApplyPreviewDockStyle(previewShell)
            dock = CreateFrame("Frame", nil, previewShell, "BackdropTemplate")
            MODERN.standardPreview.ApplyCanvasStyle(dock)
            previewToolbar = MODERN.standardPreview.CreateToolbar(previewShell, dock)
            dock:SetPoint("TOPLEFT", previewToolbar, "TOPLEFT",
                MODERN.standardPreview.leftRailWidth + MODERN.standardPreview.canvasGap, 0)
            dock:SetPoint("TOPRIGHT", previewToolbar, "TOPRIGHT",
                -(MODERN.standardPreview.rightRailWidth + MODERN.standardPreview.canvasGap), 0)
            dock:SetHeight(self.dockHeight)
        else
            dock = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
            previewShell = dock
            MODERN.standardModulePage.ApplyPreviewDockStyle(dock)
            dock:SetHeight(self.dockHeight)
        end

        self.scrollFrame = scrollFrame
        self.scrollChild = scrollChild
        self.previewRow = previewRow
        self.previewShell = previewShell
        self.previewToolbar = previewToolbar
        self.previewDock = dock
        self:SyncInternalPreviewShellHeight()
        if previewToolbar and type(EXUI.SetPanelStylePresetControlsHost) == "function" then
            EXUI:SetPanelStylePresetControlsHost(dock, previewToolbar, "preview-rail")
        end
        -- 页面只保存标准宿主引用，不能保留 module private preview/session。
        self.page._scrollFrame = scrollFrame
        self.page._scrollChild = scrollChild
        self.page._previewDock = dock
        self.page._previewShell = previewShell

        if self.dockPolicy == "internal-top" then
            dock:HookScript("OnSizeChanged", function()
                self:SyncInternalPreviewShellHeight()
            end)
            contentFrame:HookScript("OnSizeChanged", function()
                if self.contentFrame ~= contentFrame then return end
                self:SyncScrollChildWidth(true)
                self:PlacePreviewDock(contentFrame)
            end)
        end

        scrollFrame:HookScript("OnHide", function()
            self:Teardown()
        end)
        scrollFrame:HookScript("OnShow", function()
            if self._suppressOnShow or self.gridRendered or not self.contentFrame then return end
            self:Render(self.contentFrame)
        end)
        scrollFrame:HookScript("OnSizeChanged", function()
            self:SyncScrollChildWidth(false)
        end)
    end

    function controller:PlacePreviewDock(contentFrame)
        local dock = self.previewDock
        if self.dockPolicy == "external-left" then
            local context = BuildContext(self)
            local anchor = self.externalDockResolver(contentFrame, context)
            if not anchor or type(anchor.SetPoint) ~= "function" then
                error("external-left PreviewDock anchorResolver must return Frame", 2)
            end
            -- The external dock is a Core-owned sibling of the main panel.  It
            -- never becomes a child of a module Page and preserves the target
            -- panel's strata/level across page switches and pool reuse.
            dock:SetParent(UIParent)
            if type(anchor.GetFrameStrata) == "function" then dock:SetFrameStrata(anchor:GetFrameStrata()) end
            if type(anchor.GetFrameLevel) == "function" then dock:SetFrameLevel((anchor:GetFrameLevel() or 1) + 10) end
            dock:ClearAllPoints()
            dock:SetPoint("TOPRIGHT", anchor, "TOPLEFT", self.externalDockOffsetX, self.externalDockOffsetY)
            dock:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", self.externalDockOffsetX, self.externalDockOffsetY)
            dock:SetWidth(self.externalDockWidth)
            return
        end
        local row, shell = self.previewRow, self.previewShell
        if not row or not shell then error("internal-top PreviewDock requires preview row and shell", 2) end
        self:SyncScrollChildWidth(true)
        local grid = _G.ExwindGrid
        if not grid or type(grid.ResolveSettingsListWidth) ~= "function" then
            error("internal-top PreviewDock requires ExwindGrid:ResolveSettingsListWidth", 2)
        end
        local defaults = type(grid.CardLayoutDefaults) == "table" and grid.CardLayoutDefaults or {}
        local rawAvailableWidth = math.max(1, (tonumber(self.scrollChild:GetWidth()) or 1)
            - math.max(0, tonumber(defaults.left) or 0)
            - math.max(0, tonumber(defaults.right) or 0))
        local previewWidth = grid:ResolveSettingsListWidth(rawAvailableWidth, 75)

        row:SetParent(contentFrame)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
        -- ScrollChild 从 contentFrame 左侧 +4 起算且比 contentFrame 窄 16px；
        -- row 以 -12 收口后中心与下方 75% 普通设置卡中心完全一致。
        row:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -12, -4)
        shell:SetParent(row)
        shell:ClearAllPoints()
        shell:SetPoint("TOP", row, "TOP", 0, 0)
        shell:SetWidth(previewWidth)
        self:SyncInternalPreviewShellHeight()
    end

    function controller:Render(contentFrame)
        self:EnsureFrames(contentFrame)
        -- 同一页被路由重复 Render 时不会触发 OnHide；必须先交还上一轮
        -- Grid/preview，才能重新绑定本轮唯一 container/session。
        if self.gridRendered or self.cardSession or self.previewMounted then
            self:ReleasePreview()
            self:ReleaseGrid()
        end
        self.renderGeneration = self.renderGeneration + 1
        local generation = self.renderGeneration
        local scrollFrame, scrollChild, dock = self.scrollFrame, self.scrollChild, self.previewDock

        -- 外壳沿公共设置卡宽度规则居中；画布背景是页面预览态，不写模块配置。
        self:PlacePreviewDock(contentFrame)
        MODERN.standardModulePage.ApplyPreviewDockStyle(self.previewShell or dock)
        EXUI:SetPreviewDockScrollOwner(dock, self, scrollFrame)
        if self.previewRow then self.previewRow:Show() end
        if self.previewShell then self.previewShell:Show() end
        dock:Show()

        scrollFrame:SetParent(contentFrame)
        scrollFrame:ClearAllPoints()
        if self.dockPolicy == "external-left" then
            scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
        else
            scrollFrame:SetPoint("TOPLEFT", self.previewRow, "BOTTOMLEFT", 0, -6)
        end
        scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -18, 4)
        scrollFrame:SetVerticalScroll(0)
        self._suppressOnShow = true
        scrollFrame:Show()
        self._suppressOnShow = false

        C_Timer.After(0, function()
            if self.renderGeneration ~= generation
                or not scrollFrame:IsShown()
                or scrollFrame:GetParent() ~= contentFrame then
                return
            end
            local grid = _G.ExwindGrid
            local config, context, columns, slider

            self:RunDelayedStage(generation, MODERN.standardModulePage.stages.grid, function()
                if not grid then error("StandardModulePage requires ExwindGrid", 2) end
                config = self.binding.getConfig()
                if type(config) ~= "table" then error("StandardModulePage binding getConfig returned non-table", 2) end
                self:SyncScrollChildWidth(true)
                scrollChild:SetParent(scrollFrame)
                scrollChild:ClearAllPoints()
                scrollChild:SetPoint("TOPLEFT", 0, 0)
                scrollChild:Show()

                EXUI.ActivePageFrame = scrollChild
                EXUI.ActivePageScrollFrame = scrollFrame
                EXUI.CurrentModule = self.moduleKey
                context = BuildContext(self)
                context.config = config
                local declaration = MODERN.standardModulePage.ResolveLayout(self.layout, context)
                if type(grid.MountSettingsDeclaration) ~= "function" then
                    error("StandardModulePage requires ExwindGrid:MountSettingsDeclaration", 2)
                end
                self.cardSession = grid:MountSettingsDeclaration(scrollChild, declaration, {
                    pageId = self.moduleKey,
                    regionId = "standard-module",
                    binding = self.binding,
                    config = config,
                    moduleKey = self.moduleKey,
                    scrollFrame = scrollFrame,
                })
                self.gridRendered = true
                context = BuildContext(self)
                context.config = config
                context.columns = columns
            end)

            self.binding.contract.page = true

            -- Surface 是允许懒创建的正式声明：首次 preview mount 才会把同一个
            -- surface 写入 binding.contract.surface。故必须先 mount 当前模块，
            -- 再审计当前模块；不能为通过 audit 在模块加载期虚构 session。
            self:RunDelayedStage(generation, MODERN.standardModulePage.stages.preview, function()
                if self.afterGridLayout then self.afterGridLayout(context) end
                self.previewRender(dock, context)
                self.previewMounted = true
            end)

            self:RunDelayedStage(generation, MODERN.standardModulePage.stages.audit, function()
                if type(EXUI.AssertRegisteredDisplayModules) == "function" then
                    EXUI:AssertRegisteredDisplayModules({ self.moduleKey }, {
                        requireSurface = true,
                        requirePage = true,
                        requireSlider = true,
                    })
                end
            end)
        end)
    end

    function controller:Hide()
        self:Teardown()
        if self.scrollFrame and self.scrollFrame:IsShown() then self.scrollFrame:Hide() end
    end

    page._standardModulePage = controller
    return controller
end

-- Minimal shared window/scroll host for temporary EXUI inspection pages.
-- The caller supplies only Grid declarations and an in-memory config table;
-- all native frames, styling, scrolling and release behavior stay in Core.
function EXUI:CreateShowcaseWindow(options)
    options = type(options) == "table" and options or {}
    if self._showcaseWindow then
        self._showcaseWindow.title:SetText(options.title or "EXUI Control Showcase")
        return self._showcaseWindow
    end

    local name = "ExwindGUIShowcaseWindow"
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(1120, 760)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(500)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    self:ApplyModernPanel(frame)

    local title = self:CreateVisualFontString(frame, EXFONTFRAME, "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 22, -18)
    title:SetText(options.title or "EXUI Control Showcase")
    StyleModernTitle(title)
    frame.title = title

    local subtitle = self:CreateVisualFontString(frame, EXFONTFRAME, "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetText(options.subtitle or "Shared constructors rendered through ExwindGrid")
    MODERN.ApplyTextRole(subtitle, "hint")
    frame.subtitle = subtitle

    local close = self:CreateButton(frame, 32, 30, "×", function() frame:Hide() end, { variant = "soft", compact = true })
    close:SetPoint("TOPRIGHT", -16, -15)

    local divider = self:CreateSeparator(frame, 1076)
    divider:SetPoint("TOPLEFT", 22, -63)

    local scroll = self:CreateScrollFrame(frame)
    scroll:SetPoint("TOPLEFT", 20, -78)
    scroll:SetPoint("BOTTOMRIGHT", -18, 20)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 44)))
    end)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1038, 1)
    child:SetPoint("TOPLEFT")
    scroll:SetScrollChild(child)
    frame.scrollFrame, frame.content = scroll, child

    function frame:Render(layout, db, columns, preserveScroll)
        local grid = _G.ExwindGrid
        if not grid then error("CreateShowcaseWindow requires ExwindGrid", 2) end
        local previousScroll = preserveScroll and self.scrollFrame:GetVerticalScroll() or 0
        self._showcaseLayout, self._showcaseDB = layout, db
        grid:SetContainerCols(self.content, tonumber(columns) or 100)
        grid:SetContainerPadding(self.content, { left = 8, right = 8, top = 8, bottom = 20 })
        grid:Render(self.content, layout, db, nil)
        local range = self.scrollFrame:GetVerticalScrollRange() or 0
        self.scrollFrame:SetVerticalScroll(math.max(0, math.min(range, previousScroll)))
    end

    function frame:Release()
        local grid = _G.ExwindGrid
        if grid then grid:ReleaseContainerWidgets(self.content) end
        self._showcaseLayout, self._showcaseDB = nil, nil
    end

    function frame:Toggle()
        if self:IsShown() then self:Hide() else self:Show() end
    end

    frame:Hide()
    self._showcaseWindow = frame
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    table.insert(_G.UISpecialFrames, name)
    return frame
end
