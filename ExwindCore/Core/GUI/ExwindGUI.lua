-- =========================================================
-- ExwindGUI.lua: 基础控件、公共绘制、菜单及标准页面辅助。
-- SettingsCard/Row/Table 与通用 Flow: ExwindGUISettingsList.lua。
-- Font/Icon/Sound 等组合封装: ExwindGUIComposite.lua。
-- 加载顺序: 本文件 -> SettingsList -> Composite -> ControlAppearance。
-- 定位: CreateCheckbox(含 Switch/Pill/Card 外观)、CreateSlider、CreateColorButton、
-- CreateEditBox、CreateDropdown/LSM、CreateButton；页面辅助 CreateStandardModulePage。
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
MODERN.switchOnEdge = CompositeThemeColor(MC.switchOn, MC.white, .32)
MODERN.switchOnHoverEdge = CompositeThemeColor(MC.switchOnHover, MC.white, .32)
MODERN.switchOnPressedEdge = CompositeThemeColor(MC.checkboxCheckedActive, MC.white, .32)
MODERN.switchOffEdge = CompositeThemeColor(MC.switchOff, MC.white, .12)
MODERN.switchOffHoverEdge = CompositeThemeColor(MODERN.switchOffHoverFill, MC.white, .12)
MODERN.switchOffPressedEdge = CompositeThemeColor(MC.checkboxHoverBorder, MC.white, .12)
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

function MODERN.PaintSwitchTrack(surface, fill, edge)
    -- A 22-high capsule needs radius 11; the public surface presets are R4/R10.
    -- Reuse the same atlas/layout with a Switch-only half-height radius, so the
    -- end caps meet without the former two-unit vertical straight segment.
    EXUI:ClearControlSurface(surface)
    local skin = GetModernSurface(surface, surface:GetHeight() / 2)
    skin.active, skin.fill = true, fill
    for _, piece in ipairs(skin.pieces) do
        piece.texture:SetVertexColor(unpack(piece.layer == 1 and edge or fill))
    end
    skin.Layout()
end

function MODERN.StopSwitchMotion(knob)
    local motion = knob._exSwitchMotion
    if not motion then return end
    motion.generation = motion.generation + 1
    motion.group:SetScript("OnFinished", nil)
    motion.group:Stop()
    motion.selected, motion.startX, motion.targetX = nil, nil, nil
end

function MODERN.PositionSwitchKnob(container, selected, snap)
    local knob = container.checkbox._exModernSwitchKnob
    local surface = container.checkbox._exModernCheckSurface
    local motion = knob._exSwitchMotion
    if not motion then
        local group = knob:CreateAnimationGroup()
        local translation = group:CreateAnimation("Translation")
        translation:SetDuration(.12)
        translation:SetSmoothing("OUT")
        motion = { group = group, translation = translation, generation = 0 }
        knob._exSwitchMotion = motion
        -- This private visual child survives pool resets; hiding any ancestor
        -- invalidates the old completion before the checkbox can be reused.
        knob:SetScript("OnHide", MODERN.StopSwitchMotion)
    end
    local targetX = selected and 21 or 3
    snap = snap or motion.selected == nil or not container:IsVisible()
    if not snap and motion.selected == selected then return end
    local currentX = motion.targetX or targetX
    if not snap and motion.group:IsPlaying() then
        -- Sample the native eased progress once on reversal, never per frame.
        currentX = motion.startX + (motion.targetX - motion.startX)
            * motion.translation:GetSmoothProgress()
    end
    MODERN.StopSwitchMotion(knob)
    motion.selected = selected
    motion.startX, motion.targetX = snap and targetX or currentX, targetX
    knob:ClearAllPoints()
    knob:SetPoint("LEFT", surface, "LEFT", motion.startX, 0)
    if snap or currentX == targetX then return end
    local generation = motion.generation
    motion.translation:SetOffset(targetX - currentX, 0)
    motion.group:SetScript("OnFinished", function(group)
        if motion.generation ~= generation or container._exSettingsPresentation ~= "switch"
            or not knob:IsVisible() then return end
        group:SetScript("OnFinished", nil)
        group:Stop()
        -- Translation is temporary; commit its endpoint to the actual anchor.
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", surface, "LEFT", targetX, 0)
        motion.startX = targetX
    end)
    motion.group:Play()
end

local function PaintModernCheckbox(container, skipPillMeasure, snapSwitch)
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
            edge = pressed and MODERN.switchOnPressedEdge
                or (hover and MODERN.switchOnHoverEdge or MODERN.switchOnEdge)
        else
            fill = pressed and MC.checkboxHoverBorder
                or (hover and MODERN.switchOffHoverFill or MC.switchOff)
            edge = pressed and MODERN.switchOffPressedEdge
                or (hover and MODERN.switchOffHoverEdge or MODERN.switchOffEdge)
        end
        local surface = box._exModernCheckSurface
        surface:ClearAllPoints()
        surface:SetPoint("CENTER", box, "CENTER", 0, 0)
        surface:SetSize(40, 22)
        MODERN.PaintSwitchTrack(surface, fill, edge)
        box._exModernCheckMark:Hide()
        local knob = box._exModernSwitchKnob
        MODERN.PositionSwitchKnob(container, selected, snapSwitch)
        local knobColor = enabled and MC.switchKnobOn or MC.disabledText
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
        visual:SetScript("OnShow", function()
            if container._exSettingsPresentation == "switch" then
                PaintModernCheckbox(container, nil, true)
            end
        end)
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
    PaintModernCheckbox(container, nil, true)
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

-- ScrollFrameTemplate creates its MinimalScrollBar outside the viewport.  Keep
-- the shared geometry explicit so every consumer reserves the same strip:
-- 10px bar + 6px template gap + 2px panel-edge inset = 18px.
local MODERN_SCROLL_BAR_WIDTH = 10
local MODERN_SCROLL_BAR_TRACK_WIDTH = 8
local MODERN_SCROLL_BAR_OFFSET_X = 6
local MODERN_SCROLL_BAR_OFFSET_TOP = 2
local MODERN_SCROLL_BAR_OFFSET_BOTTOM = 5
EXUI.MODERN_SCROLL_FRAME_RIGHT_INSET = 18

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
        scrollBar:SetWidth(MODERN_SCROLL_BAR_WIDTH)
        track:ClearAllPoints()
        track:SetPoint("TOP", scrollBar, "TOP", 0, 0)
        track:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, 0)
        track:SetWidth(MODERN_SCROLL_BAR_TRACK_WIDTH)
        thumb:SetWidth(MODERN_SCROLL_BAR_TRACK_WIDTH)
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
        local scrollBar = scrollFrame.ScrollBar
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT",
            MODERN_SCROLL_BAR_OFFSET_X, MODERN_SCROLL_BAR_OFFSET_TOP)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT",
            MODERN_SCROLL_BAR_OFFSET_X, MODERN_SCROLL_BAR_OFFSET_BOTTOM)
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

-- SettingsList 和 Composite 共用的原宿主获取入口。
local function AcquireCompositeGroup(poolType, parent)
    local factory = _G.ExwindFactory
    if factory and factory.AcquireCompositeHost then
        return factory:AcquireCompositeHost(poolType, parent)
    end
    return CreateFrame("Frame", nil, parent, "BackdropTemplate"), true
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
        -- GridInput is also leased by item quantity fields, which enable numeric
        -- mode. Restore text input before applying this lease's value.
        container:SetNumeric(false)
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
    rightRailWidth = 190,
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
    label:SetText(L["背景"] or "背景")
    label:SetTextColor(unpack(MC.muted))

    local controls = { buttons = {}, label = label }
    canvas._exPreviewBackgroundControls = controls
    for index = 1, 5 do
        local button = EXUI:CreateButton(toolbar, 26, 26, "", nil, { compact = true })
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT",
            -(MODERN.standardPreview.rightRailWidth * 0.5 - 13), -16 - ((index - 1) * 28))
        local swatch = EXUI:CreateVisualTexture(button, EXBORDERFRAME)
        swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        swatch:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4)
        swatch:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)
        local selection = CreateFrame("Frame", nil, button)
        selection:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        selection:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        EXUI:SetControlSurface(selection, 4, MC.transparent, { 0.42, 0.73, 1, 1 })
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

-- 仅供同一 GUI 实现的后续文件使用；保存原函数/常量，不承载配置或页面状态。
EXUI._GUIInternal = {
    StyleModernTitle = StyleModernTitle,
    SetDropdownDisplayText = SetDropdownDisplayText,
    AcquireCompositeGroup = AcquireCompositeGroup,
    AttachModernMenuCheckboxMark = AttachModernMenuCheckboxMark,
    AttachModernMenuSelectionMark = AttachModernMenuSelectionMark,
    MODERN_MEDIA = MODERN_MEDIA,
    PaintModernCheckbox = PaintModernCheckbox,
    PaintModernButton = PaintModernButton,
    SLIDER_NUMBER_INPUT_WIDTH = SLIDER_NUMBER_INPUT_WIDTH,
    SLIDER_NUMBER_INPUT_HEIGHT = SLIDER_NUMBER_INPUT_HEIGHT,
    PaintModernInput = PaintModernInput,
    PaintModernDropdown = PaintModernDropdown,
    BUTTON_STYLE = BUTTON_STYLE,
}
