-- Fixed colors for ExwindCore settings and configuration surfaces.
-- Dynamic/user-selected colors and runtime/business status colors do not belong here.
--
-- =========================================================================
-- 基底：Radix Slate (dark) 的 12 階骨架。
--   調校參數 {"c":10,"b":80,"l":13,"d":56,"h":261,"i":-10,"ib":-12}
--   = 色味 0.010、色相 261、整體亮度 +1.3、卡片階距 Δ5.0、
--     輸入框比卡片微凹 0.9、輸入框邊框比卡片邊框柔 1.2。
--
-- 階級用途沿用 Radix 規範：
--   1-2 背景 / 3-5 元件三態 / 6-8 邊框 / 9-10 實心填充 / 11-12 文字
-- 深藍 = 實心填充（上面壓白色）；淺藍 = 前景（壓在深底上）。
-- =========================================================================
--
-- 實心藍的取捨。白字壓在藍底上的 WCAG 對比：
--     #0090ff (Radix blue-9)  3.26  未過 AA
--     #2870bd (Radix blue-8)  5.07  過 AA
-- true  = 所有實心填充統一用 #2870bd，白字與白勾都過 AA（建議）
-- false = 用較亮的 #0090ff，勾選框更跳，但主按鈕白字未達 AA
local SOLID_AA = true
--
-- =========================================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local function Hex(r, g, b, a)
    return { r / 255, g / 255, b / 255, a == nil and 1 or a }
end

local function H(s, a)
    return Hex(tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16), a)
end

-- =========================================================================
-- 原始值。每個都標了 CIE L*，改動時請維持相鄰階的距離。
-- =========================================================================
local C = {
    canvas    = "131518",  -- L*  6.7   最外層背景
    panel     = "16191e",  -- L*  8.7   側欄 / 導覽 / 標題列
    card      = "1d1f24",  -- L* 11.7   卡片，與 canvas 只差 5.0 以求融合
    cardAlt   = "202328",  -- L* 13.4   交替底色
    head      = "212328",  -- L* 13.7   卡片標題列 / 子卡
    ctrl      = "1b1d22",  -- L* 10.8   輸入框，微凹 0.9，仍高於 canvas
    ctrlHover = "212328",  -- L* 13.7
    pop       = "2b2d33",  -- L* 18.5   彈出層，必須高於它蓋住的東西
    popSearch = "1b1e22",  -- L* 11.1

    bSubtle   = "2a2d31",  -- L* 18.3   分隔線 / 非互動邊框
    bDef      = "3c3f45",  -- L* 26.6   卡片邊框
    bHover    = "505359",  -- L* 35.2
    bStrong   = "696d72",  -- L* 45.8
    iBorder   = "393d42",  -- L* 25.6   輸入框邊框，比卡片邊框柔一階
    iHover    = "4d5156",  -- L* 34.3

    text      = "f0f2f4",  -- L* 95.4   對卡片 14.69
    dim       = "b6b8ba",  -- L* 74.7   對卡片  8.29
    ph        = "7b7e84",  -- L* 52.7   對卡片  4.05
    dis       = "6e7177",  -- L* 47.6   對卡片  3.37

    aFg       = "70b8ff",  -- L* 72.9   淺藍：前景、focus、圖示、裝飾條
    aText     = "c2e6ff",  -- L* 89.5   選中文字 / 卡片標題
    aBright   = "0090ff",  -- L* 59.1   Radix blue-9
    aSolid    = "2870bd",  -- L* 46.6   Radix blue-8，白字 5.07
    aHover    = "3b9eff",  -- L* 63.8
    aDeep     = "1f5d9e",  -- 比 aSolid 再深一階，按下時用

    danger    = "ff9592",
    dangerB   = "e5484d",
}

-- 實心填充三態，由 SOLID_AA 決定
local SOLID        = SOLID_AA and C.aSolid  or C.aBright
local SOLID_HOVER  = SOLID_AA and "3178ce" or C.aHover
local SOLID_ACTIVE = SOLID_AA and C.aDeep   or C.aSolid

-- 疊層用中性灰 + alpha，在深底上比純白 alpha 穩定
local function NeutralA(a) local c = H(C.dim);    return { c[1], c[2], c[3], a } end
local function AccentA(a)  local c = H(C.aFg);    return { c[1], c[2], c[3], a } end
local function DangerA(a)  local c = H(C.danger); return { c[1], c[2], c[3], a } end

ExwindTools.GUIColors = {
    -- ---------- 表面 ----------
    page            = H(C.canvas),
    panel           = H(C.panel),
    panelBorder     = H(C.bDef),
    header          = H(C.panel),
    headerHover     = H(C.head),
    headerDivider   = H(C.bSubtle),
    card            = H(C.card),
    cardBorder      = H(C.bDef),          -- 新增
    cardHoverBorder = H(C.bHover),

    -- ---------- 文字 ----------
    text            = H(C.text),
    textDim         = H(C.dim),
    textPlaceholder = H(C.ph),
    textDisabled    = H(C.dis),
    white           = Hex(0xff, 0xff, 0xff),
    transparent     = { 0, 0, 0, 0 },

    -- ---------- 強調色 ----------
    accent       = H(C.aFg),
    accentHover  = H(C.aText),
    accentActive = H(C.aHover),
    selectedText = H(C.aText),
    focusRing    = AccentA(0.20),         -- 新增，全域唯一

    primaryFill       = H(SOLID),
    primaryFillHover  = H(SOLID_HOVER),
    primaryFillActive = H(SOLID_ACTIVE),
    primaryText       = Hex(0xff, 0xff, 0xff),

    -- ---------- 輸入框 ----------
    input               = H(C.ctrl),
    inputBorder         = H(C.iBorder),   -- 新增
    inputHover          = H(C.ctrlHover),
    inputHoverBorder    = H(C.iHover),
    inputFocusBorder    = H(C.aFg),       -- 新增
    inputDisabled       = H(C.ctrl),
    inputDisabledBorder = H(C.bSubtle),

    -- ---------- 彈出層 ----------
    popup             = H(C.pop),
    popupBorder       = H(C.bStrong),
    popupSearch       = H(C.popSearch),
    popupSearchBorder = H(C.bSubtle),
    popupDivider      = H(C.bSubtle),
    menuHover         = NeutralA(0.08),
    menuSelected      = AccentA(0.13),
    menuSelectedHover = AccentA(0.20),

    -- ---------- 滑桿 ----------
    sliderTrack      = H(C.bDef),
    sliderTrackHover = H(C.bHover),

    -- ---------- 核取方塊 ----------
    checkboxBorder        = H(C.iHover),
    checkboxHoverBorder   = H(C.aFg),
    checkboxChecked       = H(SOLID),
    checkboxCheckedHover  = H(SOLID_HOVER),
    checkboxCheckedActive = H(SOLID_ACTIVE),
    disabledFill          = H(C.ctrl),
    disabledBorder        = H(C.bSubtle),

    -- ---------- 次要 / 危險 ----------
    secondaryFill        = H(C.ctrl),
    secondaryText        = H(C.text),
    secondaryBorder      = H(C.bDef),
    secondaryHoverFill   = H(C.head),
    secondaryHoverBorder = H(C.bHover),
    secondaryPressedFill = H(C.bSubtle),
    secondaryPressedText = H(C.dim),
    dangerBorder      = H(C.dangerB),
    dangerText        = H(C.danger),
    dangerHoverFill   = DangerA(0.14),
    dangerPressedFill = DangerA(0.22),

    -- ---------- FontString 內嵌色 ----------
    markup = {
        accent       = "|cff" .. C.aFg,
        selectedText = "|cff" .. C.aText,
        text         = "|cff" .. C.text,
        textDim      = "|cff" .. C.dim,
        placeholder  = "|cff" .. C.ph,
        textDisabled = "|cff" .. C.dis,
        danger       = "|cff" .. C.danger,
    },

    -- ---------- Shell ----------
    -- 六個原本重複的 divider 全部指向同一個 borderSoft。
    shell = {
        rail       = H(C.panel),
        header     = H(C.panel),
        nav        = H(C.panel),
        card       = H(C.card),
        cardAlt    = H(C.cardAlt),        -- 不再與 card 同值
        border     = H(C.bDef),
        borderSoft = H(C.bSubtle),
        text       = H(C.text),
        muted      = H(C.dim),
        quiet      = H(C.ph),

        -- Provider 身分色，不屬於中性階梯，維持原值
        cyan   = { 0.28, 0.80, 0.91, 1 },
        violet = { 0.62, 0.55, 1.00, 1 },
        gold   = { 0.95, 0.77, 0.35, 1 },

        toolsSidebar        = H(C.panel),
        toolsSidebarBorder  = H(C.bDef),
        toolsSidebarDivider = H(C.bSubtle),
        toolsAmbientMask    = H(C.canvas),
        toolsTopLine        = H(C.bSubtle),
        toolsBottomLine     = H(C.bSubtle),
        toolsRightPanel     = { 0, 0, 0, 0 },

        sidebarDisabledText = H(C.dis),
        sidebarDisabledRail = H(C.bSubtle),
        sidebarActiveText   = H(C.aText),
        sidebarActiveRail   = AccentA(0.13),
        sidebarHoverText    = H(C.text),
        sidebarHoverRail    = H(C.bHover),
        sidebarIdleText     = H(C.dim),
        sidebarIdleRail     = H(C.bDef),
        sidebarAccent       = H(C.aFg),

        railActive      = AccentA(0.13),
        railTransparent = { 0, 0, 0, 0 },
        railHover       = NeutralA(0.08),
    },
}