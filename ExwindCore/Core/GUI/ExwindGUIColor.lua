-- Fixed colors for ExwindCore settings and configuration surfaces.
-- Dynamic/user-selected colors and runtime/business status colors do not belong here.
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local function Hex(r, g, b, a)
    return { r / 255, g / 255, b / 255, a == nil and 1 or a }
end

ExwindTools.GUIColors = {
    page = Hex(0x14, 0x16, 0x1a),
    panel = Hex(0x1b, 0x1e, 0x23),
    panelBorder = Hex(0x34, 0x3a, 0x42),
    header = Hex(0x21, 0x24, 0x29),
    headerHover = Hex(0x26, 0x2a, 0x30),
    headerDivider = Hex(0x2a, 0x2e, 0x34),
    card = Hex(0x22, 0x26, 0x2c),
    cardHoverBorder = Hex(0x3d, 0x44, 0x4d),

    text = Hex(0xec, 0xee, 0xf1),
    textDim = Hex(0xa7, 0xad, 0xb5),
    textPlaceholder = Hex(0x6f, 0x76, 0x80),
    textDisabled = Hex(0x5f, 0x66, 0x6f),
    white = Hex(0xff, 0xff, 0xff),
    transparent = { 0, 0, 0, 0 },

    accent = Hex(0xa8, 0xd8, 0xff),
    accentHover = Hex(0xc2, 0xe4, 0xff),
    accentActive = Hex(0x8c, 0xc6, 0xf5),
    selectedText = Hex(0xcb, 0xe7, 0xff),

    input = Hex(0x17, 0x19, 0x1d),
    inputHoverBorder = Hex(0x4a, 0x52, 0x5c),
    inputDisabled = Hex(0x1a, 0x1c, 0x20),
    inputDisabledBorder = Hex(0x2a, 0x2e, 0x34),

    popup = Hex(0x1c, 0x20, 0x26),
    popupBorder = Hex(0x52, 0x5a, 0x65),
    popupSearch = Hex(0x16, 0x19, 0x1e),
    popupSearchBorder = Hex(0x2e, 0x34, 0x3c),
    popupDivider = Hex(0x2a, 0x2f, 0x36),
    menuHover = { 1, 1, 1, 0.05 },
    menuSelected = { 168 / 255, 216 / 255, 1, 0.14 },
    menuSelectedHover = { 168 / 255, 216 / 255, 1, 0.20 },

    sliderTrack = Hex(0x36, 0x3c, 0x44),
    sliderTrackHover = Hex(0x3d, 0x44, 0x4d),

    checkboxBorder = Hex(0x4a, 0x52, 0x5c),
    checkboxHoverBorder = Hex(0x6f, 0x76, 0x80),
    checkboxChecked = Hex(0x2a, 0x78, 0xd6),
    checkboxCheckedHover = Hex(0x3a, 0x86, 0xe0),
    checkboxCheckedActive = Hex(0x22, 0x66, 0xb8),
    disabledFill = Hex(0x1f, 0x22, 0x27),
    disabledBorder = Hex(0x30, 0x35, 0x3c),

    primaryText = Hex(0x0f, 0x1a, 0x24),
    secondaryText = Hex(0xd5, 0xd9, 0xde),
    secondaryBorder = Hex(0x4a, 0x52, 0x5c),
    secondaryHoverFill = { 1, 1, 1, 0.05 },
    secondaryHoverBorder = Hex(0x5f, 0x68, 0x73),
    secondaryPressedFill = { 1, 1, 1, 0.09 },
    secondaryPressedText = Hex(0xb8, 0xbe, 0xc5),
    dangerBorder = Hex(0xf2, 0x8b, 0x8b),
    dangerText = Hex(0xf6, 0xa5, 0xa5),
    dangerHoverFill = { 242 / 255, 139 / 255, 139 / 255, 0.12 },
    dangerPressedFill = { 242 / 255, 139 / 255, 139 / 255, 0.20 },

    -- Existing fixed shell colors not specified by the new palette stay unchanged.
    shell = {
        rail = { 0.065, 0.080, 0.110, 1 },
        header = { 0.055, 0.070, 0.095, 0.96 },
        nav = { 0.070, 0.090, 0.120, 1 },
        card = { 0.085, 0.105, 0.140, 0.96 },
        cardAlt = { 0.070, 0.086, 0.118, 0.94 },
        border = { 0.185, 0.225, 0.290, 1 },
        borderSoft = { 0.125, 0.155, 0.205, 0.92 },
        text = { 0.89, 0.92, 0.96, 1 },
        muted = { 0.56, 0.62, 0.70, 1 },
        quiet = { 0.34, 0.40, 0.48, 1 },
        cyan = { 0.28, 0.80, 0.91, 1 },
        violet = { 0.62, 0.55, 1.00, 1 },
        gold = { 0.95, 0.77, 0.35, 1 },
        toolsSidebar = { 0.06, 0.06, 0.08, 1 },
        toolsSidebarBorder = { 0.2, 0.2, 0.25, 1 },
        toolsSidebarDivider = { 0.12, 0.15, 0.20, 0.9 },
        toolsAmbientMask = { 0.078, 0.086, 0.102, 0.38 },
        toolsTopLine = { 0.48, 0.42, 0.70, 0.34 },
        toolsBottomLine = { 0.28, 0.27, 0.35, 0.64 },
        toolsRightPanel = { 0.025, 0.027, 0.04, 0.22 },
        sidebarDisabledText = { 0.38, 0.42, 0.50, 1 },
        sidebarDisabledRail = { 0.18, 0.20, 0.24, 0.35 },
        sidebarActiveText = { 0.92, 0.96, 1.00, 1 },
        sidebarActiveRail = { 0.24, 0.29, 0.38, 0.25 },
        sidebarHoverText = { 0.83, 0.88, 0.97, 1 },
        sidebarHoverRail = { 0.34, 0.40, 0.52, 0.8 },
        sidebarIdleText = { 0.57, 0.63, 0.75, 1 },
        sidebarIdleRail = { 0.24, 0.29, 0.38, 0.55 },
        sidebarAccent = { 0.0, 0.72, 1.0, 1 },
        railActive = { 0.075, 0.12, 0.17, 0.96 },
        railTransparent = { 0.03, 0.04, 0.06, 0 },
        railHover = { 0.10, 0.13, 0.18, 0.78 },
    },
}
