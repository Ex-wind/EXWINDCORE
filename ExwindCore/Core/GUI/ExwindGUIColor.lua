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

    -- Inline FontString fragments used by legacy settings pages. Keeping these
    -- escapes here prevents those pages from reintroducing their own fixed palette.
    markup = {
        accent = "|cffa8d8ff",
        selectedText = "|cffcbe7ff",
        text = "|cffeceef1",
        textDim = "|cffa7adb5",
        placeholder = "|cff6f7680",
        textDisabled = "|cff5f666f",
        danger = "|cfff6a5a5",
    },

    -- Fixed settings-shell surfaces map to the same palette as ordinary controls.
    -- Provider identity accents remain separate because they are selected by the
    -- active provider rather than by the shell itself.
    shell = {
        rail = Hex(0x1b, 0x1e, 0x23),
        header = Hex(0x21, 0x24, 0x29),
        nav = Hex(0x1b, 0x1e, 0x23),
        card = Hex(0x22, 0x26, 0x2c),
        cardAlt = Hex(0x22, 0x26, 0x2c),
        border = Hex(0x34, 0x3a, 0x42),
        borderSoft = Hex(0x2a, 0x2e, 0x34),
        text = Hex(0xec, 0xee, 0xf1),
        muted = Hex(0xa7, 0xad, 0xb5),
        quiet = Hex(0x6f, 0x76, 0x80),
        cyan = { 0.28, 0.80, 0.91, 1 },
        violet = { 0.62, 0.55, 1.00, 1 },
        gold = { 0.95, 0.77, 0.35, 1 },
        toolsSidebar = Hex(0x1b, 0x1e, 0x23),
        toolsSidebarBorder = Hex(0x34, 0x3a, 0x42),
        toolsSidebarDivider = Hex(0x2a, 0x2e, 0x34),
        toolsAmbientMask = Hex(0x14, 0x16, 0x1a),
        toolsTopLine = Hex(0x2a, 0x2e, 0x34),
        toolsBottomLine = Hex(0x2a, 0x2e, 0x34),
        toolsRightPanel = { 0, 0, 0, 0 },
        sidebarDisabledText = Hex(0x5f, 0x66, 0x6f),
        sidebarDisabledRail = Hex(0x30, 0x35, 0x3c),
        sidebarActiveText = Hex(0xff, 0xff, 0xff),
        sidebarActiveRail = { 168 / 255, 216 / 255, 1, 0.14 },
        sidebarHoverText = Hex(0xec, 0xee, 0xf1),
        sidebarHoverRail = Hex(0x3d, 0x44, 0x4d),
        sidebarIdleText = Hex(0xa7, 0xad, 0xb5),
        sidebarIdleRail = Hex(0x34, 0x3a, 0x42),
        sidebarAccent = Hex(0xa8, 0xd8, 0xff),
        railActive = { 168 / 255, 216 / 255, 1, 0.14 },
        railTransparent = { 0, 0, 0, 0 },
        railHover = { 1, 1, 1, 0.05 },
    },
}
