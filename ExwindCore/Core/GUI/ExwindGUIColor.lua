-- =========================================================
-- ExwindGUIColor.lua
-- EXWIND 自有 GUI 固定颜色的唯一来源。
--
-- 其它文件只能引用本文件公开的语义 token；不得复制 RGB/RGBA、
-- 十六进制颜色、文字颜色转义、模块 palette 或 fallback 主题常量。
-- 游戏返回的职业/品质色、用户自选色和运行时计算色不属于固定主题色。
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then
    error("ExwindGUIColor requires Core/ExwindTools.lua to load first")
end

local function RGBA(hex, alpha)
    assert(type(hex) == "string" and string.len(hex) == 6, "GUI color must be a six-digit hex string")
    return {
        tonumber(string.sub(hex, 1, 2), 16) / 255,
        tonumber(string.sub(hex, 3, 4), 16) / 255,
        tonumber(string.sub(hex, 5, 6), 16) / 255,
        alpha == nil and 1 or alpha,
    }
end

local Color = {}

Color.Transparent = RGBA("000000", 0)
Color.TransparentWhite = RGBA("ffffff", 0)
Color.White = RGBA("ffffff")

Color.Surface = {
    Page = RGBA("14161a"),
    Panel = RGBA("1b1e23"),
    PanelHeader = RGBA("212429"),
    PanelHeaderHover = RGBA("262a30"),
    PanelDivider = RGBA("2a2e34"),
    Card = RGBA("22262c"),
    Input = RGBA("17191d"),
    ControlHover = RGBA("2a3038"),
    Menu = RGBA("2a2f36"),
}

Color.Border = {
    Default = RGBA("343a42"),
    Interactive = RGBA("4a525c"),
    Hover = RGBA("6f7680"),
    Strong = RGBA("5f6873"),
}
Color.Border.Transparent = Color.Transparent

Color.Text = {
    Primary = RGBA("eceef1"),
    Secondary = RGBA("a7adb5"),
    ButtonSecondary = RGBA("d5d9de"),
    ButtonPressed = RGBA("b8bec5"),
    Inverse = RGBA("0f1a24"),
    Disabled = RGBA("5f666f"),
    Danger = RGBA("f6a5a5"),
}
Color.Text.White = Color.White
Color.Text.PanelTitle = Color.Text.Primary
Color.Text.PanelTitleHover = Color.White

Color.Accent = {
    Primary = RGBA("a8d8ff"),
    PrimaryHover = RGBA("c2e4ff"),
    PrimaryPressed = RGBA("8cc6f5"),
    CheckboxSelected = RGBA("2a78d6"),
    CheckboxSelectedHover = RGBA("3a86e0"),
    CheckboxPressed = RGBA("2266b8"),
}

local DangerBorder = RGBA("f28b8b")
local White05 = RGBA("ffffff", 0.05)

Color.Disabled = {
    Fill = RGBA("1f2227"),
    Border = RGBA("30353c"),
    Text = Color.Text.Disabled,
    Check = Color.Text.Disabled,
}

Color.Control = {
    Input = {
        Fill = Color.Surface.Input,
        Border = Color.Border.Default,
        HoverBorder = Color.Border.Interactive,
        FocusBorder = Color.Accent.Primary,
        Text = Color.Text.Primary,
        DisabledText = Color.Text.Disabled,
    },
    Checkbox = {
        UncheckedFill = Color.Surface.Input,
        UncheckedBorder = Color.Border.Interactive,
        UncheckedHoverBorder = Color.Border.Hover,
        CheckedFill = Color.Accent.CheckboxSelected,
        CheckedBorder = Color.Accent.CheckboxSelected,
        CheckedHoverFill = Color.Accent.CheckboxSelectedHover,
        CheckedHoverBorder = Color.Accent.CheckboxSelectedHover,
        PressedFill = Color.Accent.CheckboxPressed,
        PressedBorder = Color.Accent.CheckboxPressed,
        Check = Color.White,
        DisabledFill = Color.Disabled.Fill,
        DisabledBorder = Color.Disabled.Border,
        DisabledCheck = Color.Disabled.Check,
        Label = Color.Text.Primary,
        LabelHover = Color.Text.PanelTitleHover,
        LabelDisabled = Color.Text.Disabled,
    },
    Slider = {
        Track = RGBA("363c44"),
        Thumb = Color.Accent.Primary,
        Disabled = Color.Text.Disabled,
    },
    ScrollBar = {
        TrackFill = Color.Transparent,
        TrackBorder = Color.Transparent,
        Thumb = Color.Border.Interactive,
        ThumbHover = Color.Accent.Primary,
        ThumbDisabled = Color.Text.Disabled,
    },
    Dropdown = {
        Fill = Color.Surface.Input,
        ActiveFill = Color.Surface.Input,
        Border = Color.Border.Default,
        HoverBorder = Color.Border.Interactive,
        OpenBorder = Color.Accent.Primary,
        Text = Color.Text.Primary,
        Icon = Color.Text.Secondary,
        IconHover = Color.Accent.Primary,
        Disabled = Color.Text.Disabled,
    },
    Button = {
        Primary = {
            Fill = Color.Accent.Primary,
            Border = Color.Accent.Primary,
            Text = Color.Text.Inverse,
            HoverFill = Color.Accent.PrimaryHover,
            HoverBorder = Color.Accent.PrimaryHover,
            PressedFill = Color.Accent.PrimaryPressed,
            PressedBorder = Color.Accent.PrimaryPressed,
        },
        Secondary = {
            Fill = Color.Transparent,
            Border = Color.Border.Interactive,
            Text = Color.Text.ButtonSecondary,
            HoverFill = White05,
            HoverBorder = Color.Border.Strong,
            HoverText = Color.White,
            PressedFill = RGBA("ffffff", 0.09),
            PressedBorder = Color.Border.Interactive,
            PressedText = Color.Text.ButtonPressed,
        },
        Danger = {
            Fill = Color.Transparent,
            Border = DangerBorder,
            Text = Color.Text.Danger,
            HoverFill = RGBA("f28b8b", 0.12),
            HoverBorder = Color.Text.Danger,
            HoverText = Color.Text.Danger,
            PressedFill = RGBA("f28b8b", 0.20),
            PressedBorder = DangerBorder,
            PressedText = DangerBorder,
        },
        Disabled = {
            Fill = Color.Disabled.Fill,
            Border = Color.Disabled.Border,
            Text = Color.Disabled.Text,
        },
    },
    Menu = {
        Fill = Color.Surface.Menu,
        Border = Color.Border.Interactive,
        Selected = RGBA("a8d8ff", 0.18),
        Hover = RGBA("a8d8ff", 0.26),
        Check = Color.White,
    },
    PanelHeader = {
        Fill = Color.Surface.PanelHeader,
        HoverFill = Color.Surface.PanelHeaderHover,
        Divider = Color.Surface.PanelDivider,
        Text = Color.Text.PanelTitle,
        HoverText = Color.Text.PanelTitleHover,
        Icon = Color.Accent.Primary,
    },
}

-- Fixed semantic state colors. These are not substitutes for Blizzard-provided
-- class/quality colors or user-selected colors.
Color.Status = {
    Success = RGBA("21c45e"),
    Warning = RGBA("f7b861"),
    Error = RGBA("de4242"),
    Danger = DangerBorder,
    Info = Color.Accent.Primary,
    Gold = RGBA("ffd100"),
    Brand = RGBA("a330c9"),
    Debug = RGBA("ff9900"),
    Diagnostic = RGBA("88ff00"),
}
Color.Status.Pending = Color.Status.Warning
Color.Status.Inactive = Color.Text.Disabled
Color.Status.Muted = Color.Text.Secondary

-- Fixed alpha variants are also centralized. Callers must not combine a
-- central RGB token with their own literal alpha for a fixed UI state.
Color.Overlay = {
    Page35 = RGBA("14161a", 0.35),
    Page80 = RGBA("14161a", 0.80),
    Page95 = RGBA("14161a", 0.95),
    Page98 = RGBA("14161a", 0.98),
    Panel90 = RGBA("1b1e23", 0.90),
    Panel94 = RGBA("1b1e23", 0.94),
    Panel96 = RGBA("1b1e23", 0.96),
    Card95 = RGBA("22262c", 0.95),
    White05 = White05,
    White08 = RGBA("ffffff", 0.08),
    White10 = RGBA("ffffff", 0.10),
    White16 = RGBA("ffffff", 0.16),
    White20 = RGBA("ffffff", 0.20),
    Black60 = RGBA("000000", 0.60),
    Black80 = RGBA("000000", 0.80),
    Accent12 = RGBA("a8d8ff", 0.12),
    Accent18 = RGBA("a8d8ff", 0.18),
    Accent20 = RGBA("a8d8ff", 0.20),
    Accent40 = RGBA("a8d8ff", 0.40),
    Success18 = RGBA("21c45e", 0.18),
}

Color.Shadow = {
    MenuWide = RGBA("000000", 0.10),
    MenuMiddle = RGBA("000000", 0.16),
    MenuTight = RGBA("000000", 0.22),
}

Color.Icon = {
    Opaque = Color.White,
    Hidden = Color.TransparentWhite,
    Header = Color.Accent.Primary,
    Sound = {
        Default = Color.Text.ButtonPressed,
        Hover = Color.White,
        Disabled = Color.Text.Disabled,
    },
    ImageButtonPressedTint = RGBA("b3b3b3"),
}

Color.Decoration = {
    Divider = Color.Surface.PanelDivider,
    DividerStrong = RGBA("343a42", 0.95),
    DividerFade = RGBA("343a42", 0.08),
    ColorSwatchBorder = Color.Overlay.Black80,
}

Color.Selection = {
    Fill = Color.Control.Menu.Selected,
    HoverFill = Color.Control.Menu.Hover,
    Border = Color.Accent.Primary,
    Bar = Color.Accent.Primary,
}

Color.Preview = {
    Dock = Color.Surface.Page,
    ToolsDock = RGBA("94a5fc"),
    Grid = Color.Overlay.White05,
    Axis = Color.Overlay.White20,
}

Color.Preview.NameplateHealth = { 0.78, 0.08, 0.08, 1 }
Color.Preview.NameplateBackground = { 0.08, 0.08, 0.08, 1 }
Color.Preview.NameplateBorder = RGBA("000000")

Color.Editor = {
    SelectionFill = RGBA("a8d8ff", 0.10),
    SelectionBorder = Color.Accent.Primary,
    DragFill = RGBA("a8d8ff", 0.15),
    DraggingFill = RGBA("ffd100", 0.18),
    DraggingBorder = Color.Status.Gold,
    ResizeHandle = RGBA("ffd100", 0.50),
    GridLine = RGBA("ffffff", 0.15),
    Surface = Color.Surface.Panel,
    SurfaceBorder = Color.Border.Default,
    ModuleOverlay = {
        EXBoss = {
            Fill = RGBA("ffcc4d", 0.18),
            Border = RGBA("ffebad"),
            Title = RGBA("fff7d6"),
            TitleShadow = RGBA("331f05"),
        },
        ExwindTools = {
            Fill = RGBA("8547e0", 0.18),
            Border = RGBA("d6a8ff"),
            Title = RGBA("ebd6ff"),
            TitleShadow = RGBA("1f083d"),
        },
        EXAura = {
            Fill = RGBA("8f40e0", 0.16),
            Border = RGBA("d69eff"),
            Title = RGBA("f5e0ff"),
            TitleShadow = RGBA("1f0538"),
        },
    },
}

Color.Tooltip = {
    Fill = Color.Surface.Panel,
    Border = Color.Border.Default,
    Primary = Color.Text.Primary,
    Secondary = Color.Text.Secondary,
}

Color.List = {
    Row = Color.Surface.Panel,
    Alternate = Color.Surface.Card,
    Hover = Color.Surface.PanelHeaderHover,
    Selected = Color.Control.Menu.Selected,
    SummaryGradientStart = Color.Surface.Card,
    SummaryGradientEnd = Color.Surface.Panel,
}

Color.Changelog = {
    Body = Color.Text.Primary,
    Bullet = Color.Text.Secondary,
    Note = Color.Status.Info,
    Heading1 = Color.Text.Primary,
    Heading2 = Color.Accent.Primary,
    Divider = Color.Surface.PanelDivider,
    Tab = Color.Surface.PanelHeader,
    TabHover = Color.Surface.PanelHeaderHover,
    TabSelected = Color.Surface.Card,
}

Color.DynamicFallback = {
    Text = Color.Text.Primary,
    Class = Color.Text.Primary,
    Border = Color.Border.Default,
    Fill = Color.Surface.Input,
}

Color.Chat = {
    Brand = Color.Status.Brand,
    Debug = Color.Status.Debug,
    Diagnostic = Color.Status.Diagnostic,
    Success = Color.Status.Success,
    Warning = Color.Status.Warning,
    Error = Color.Status.Error,
}

Color.Gameplay = {
    SpellLink = Color.Accent.Primary,
    FiveSecondMarker = RGBA("ffe659", 0.85),
    HealthDanger = RGBA("ff0000"),
    HealthWarning = RGBA("ffff00"),
    HealthHealthy = RGBA("00ff00"),
    ComparisonMarker = { 1, 0.85, 0, 1 },
}

Color.VoiceScheme = {
    Tank = RGBA("c69b6c"),
    Heal = RGBA("5fff9d"),
    Target = RGBA("ff3b30"),
    Cooldown = Color.White,
    Mechanic = RGBA("da5bff"),
    CustomDefault = { 1.00, 0.82, 0.25, 1 },
    Extra = {
        { 0.35, 0.72, 1.00, 1 },
        { 1.00, 0.58, 0.25, 1 },
        { 0.78, 0.64, 1.00, 1 },
    },
    LegacyCooldown = RGBA("a5afa2"),
}

Color.Creature = {
    Normal = Color.Text.Primary,
    Elite = Color.Status.Warning,
    Boss = Color.Status.Danger,
}

Color.Stat = {
    Crit = Color.Status.Danger,
    Haste = Color.Status.Success,
    Mastery = Color.Status.Brand,
    Versatility = Color.Accent.Primary,
}

Color.Composite = {
    Fill = Color.Surface.Panel,
    Border = Color.Border.Default,
    Utility = Color.Surface.Card,
    Text = Color.Text.Primary,
    Value = Color.Accent.Primary,
}

Color.GlassDemo = {
    LabelShadow = RGBA("000000", 0.70),
    MessageShadow = RGBA("000000", 0.18),
    Greeting = RGBA("e6e6e3"),
    Message = RGBA("f7f7f5"),
    Dismiss = RGBA("f2f2f0"),
    ControlTop = RGBA("1f1f1f", 0.93),
    ControlBottom = RGBA("121212", 0.93),
    BodyTop = RGBA("4a4a47"),
    BodyBottom = RGBA("30302e"),
    CapsuleTop = RGBA("52524d"),
    CapsuleBottom = RGBA("474742"),
    RimTop = RGBA("f0f0e8"),
    RimBottom = RGBA("d1d1c9"),
    CapsuleRimTop = RGBA("fafaf0"),
    CapsuleRimBottom = RGBA("e6e6de"),
    Light = RGBA("edede3"),
    DismissHover = RGBA("fffffa"),
    CapsuleHoverTop = RGBA("70706b"),
    CapsuleHoverBottom = RGBA("5c5c57"),
    Hint = RGBA("c2c2bd"),
}

-- Compatibility views are declared here, never reconstructed by consumers.
Color.PanelTheme = {
    panel = Color.Surface.Page,
    rail = Color.Surface.Panel,
    header = Color.Surface.PanelHeader,
    nav = Color.Surface.Panel,
    content = Color.Surface.Page,
    card = Color.Surface.Card,
    cardAlt = Color.Surface.Panel,
    border = Color.Border.Default,
    borderSoft = Color.Border.Default,
    text = Color.Text.Primary,
    muted = Color.Text.Secondary,
    quiet = Color.Text.Disabled,
    cyan = Color.Accent.Primary,
    violet = Color.Status.Brand,
    gold = Color.Status.Gold,
    success = Color.Status.Success,
    danger = Color.Status.Danger,
}

-- Compatibility view for the existing EXUI appearance API. Every entry is a
-- reference to a semantic token above; no color values are duplicated here.
Color.EXUI = {
    background = Color.Surface.Page,
    panel = Color.Surface.Panel,
    panelHeader = Color.Surface.PanelHeader,
    panelHeaderHover = Color.Surface.PanelHeaderHover,
    panelDivider = Color.Surface.PanelDivider,
    input = Color.Surface.Input,
    raised = Color.Surface.Card,
    hover = Color.Surface.ControlHover,
    border = Color.Border.Default,
    text = Color.Text.Primary,
    muted = Color.Text.Secondary,
    disabled = Color.Text.Disabled,
    blue = Color.Accent.Primary,
    blueHover = Color.Accent.PrimaryHover,
    primaryHover = Color.Accent.PrimaryHover,
    primaryPressed = Color.Accent.PrimaryPressed,
    lightBlue = Color.Accent.Primary,
    blueSoft = Color.Surface.PanelHeader,
    focus = Color.Accent.Primary,
    accent = Color.Accent.Primary,
    sliderTrack = Color.Control.Slider.Track,
    popup = Color.Control.Menu.Fill,
    popupBorder = Color.Control.Menu.Border,
    menuSelected = Color.Control.Menu.Selected,
    menuHover = Color.Control.Menu.Hover,
    primaryFill = Color.Control.Button.Primary.Fill,
    primaryText = Color.Control.Button.Primary.Text,
    secondaryBorder = Color.Control.Button.Secondary.Border,
    secondaryText = Color.Control.Button.Secondary.Text,
    secondaryHoverFill = Color.Control.Button.Secondary.HoverFill,
    secondaryHoverBorder = Color.Control.Button.Secondary.HoverBorder,
    secondaryPressedFill = Color.Control.Button.Secondary.PressedFill,
    secondaryPressedText = Color.Control.Button.Secondary.PressedText,
    dangerFill = Color.Control.Button.Danger.Fill,
    dangerBorder = Color.Control.Button.Danger.Border,
    dangerText = Color.Control.Button.Danger.Text,
    dangerHoverFill = Color.Control.Button.Danger.HoverFill,
    dangerHover = Color.Control.Button.Danger.HoverText,
    dangerPressedFill = Color.Control.Button.Danger.PressedFill,
    disabledFill = Color.Disabled.Fill,
    disabledBorder = Color.Disabled.Border,
    disabledText = Color.Disabled.Text,
    transparent = Color.Transparent,
    white = Color.White,
    neutral = Color.Text.Secondary,
    include = Color.Accent.CheckboxSelected,
    exclude = Color.Status.Danger,
}

local function ClampByte(component)
    return math.max(0, math.min(255, math.floor((component or 0) * 255 + 0.5)))
end

function Color.TextCode(color)
    assert(type(color) == "table", "TextCode requires a central color token")
    return string.format("|cff%02x%02x%02x", ClampByte(color[1]), ClampByte(color[2]), ClampByte(color[3]))
end

function Color.WrapText(color, text)
    return Color.TextCode(color) .. tostring(text or "") .. "|r"
end

function Color.WrapDynamicRGB(r, g, b, text)
    return string.format("|cff%02x%02x%02x%s|r",
        ClampByte(r), ClampByte(g), ClampByte(b), tostring(text or ""))
end

function Color.WrapDynamicHex(hex, text)
    local value = tostring(hex or ""):gsub("^#", ""):gsub("^|c", "")
    if string.len(value) == 6 then value = "ff" .. value end
    assert(string.len(value) == 8 and not string.find(value, "[^%x]"),
        "WrapDynamicHex requires a six- or eight-digit dynamic color")
    return "|c" .. value .. tostring(text or "") .. "|r"
end

function Color.StripTextColor(text)
    local value = tostring(text or "")
    if _G.StripTextColorMarkup then return _G.StripTextColorMarkup(value) end
    return (string.gsub(string.gsub(value, "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
end

_G.ExwindGUIColor = Color
ExwindTools.UIColor = Color
