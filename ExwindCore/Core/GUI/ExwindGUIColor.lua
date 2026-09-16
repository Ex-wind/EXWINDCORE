-- =========================================================
-- ExwindGUIColor.lua
-- EXWIND 设置 GUI / 插件配置面板固定颜色的唯一来源。
--
-- 其它文件只能引用本文件公开的语义 token；不得复制 RGB/RGBA、
-- 十六进制颜色、文字颜色转义、模块 palette 或 fallback 主题常量。
-- 游戏返回的职业/品质色、用户自选色、业务显示和运行时计算色不属于本文件范围。
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
    Menu = RGBA("1c2026"),
}

Color.Border = {
    Default = RGBA("343a42"),
    CardHover = RGBA("3d444d"),
    Interactive = RGBA("4a525c"),
    Hover = RGBA("6f7680"),
    Strong = RGBA("5f6873"),
    Popup = RGBA("525a65"),
    PopupSearch = RGBA("2e343c"),
    PopupDivider = RGBA("2a2f36"),
}
Color.Border.Transparent = Color.Transparent

Color.Text = {
    Primary = RGBA("eceef1"),
    Secondary = RGBA("a7adb5"),
    Placeholder = RGBA("6f7680"),
    ButtonSecondary = RGBA("d5d9de"),
    ButtonPressed = RGBA("b8bec5"),
    MenuSelected = RGBA("cbe7ff"),
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
    Card = {
        Fill = Color.Surface.Card,
        Border = Color.Border.Default,
        HoverBorder = Color.Border.CardHover,
    },
    Input = {
        Fill = Color.Surface.Input,
        Border = Color.Border.Default,
        HoverBorder = Color.Border.Interactive,
        FocusBorder = Color.Accent.Primary,
        Text = Color.Text.Primary,
        Placeholder = Color.Text.Placeholder,
        DisabledFill = RGBA("1a1c20"),
        DisabledBorder = Color.Surface.PanelDivider,
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
        HoverTrack = Color.Border.CardHover,
        Thumb = Color.Accent.Primary,
        HoverThumb = Color.Accent.PrimaryHover,
        PressedThumb = Color.Accent.PrimaryPressed,
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
        IconHover = Color.Text.Primary,
        IconOpen = Color.Accent.Primary,
        DisabledFill = RGBA("1a1c20"),
        DisabledBorder = Color.Surface.PanelDivider,
        DisabledText = Color.Text.Disabled,
        DisabledIcon = Color.Text.Disabled,
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
        Border = Color.Border.Popup,
        SearchFill = RGBA("16191e"),
        SearchBorder = Color.Border.PopupSearch,
        SearchFocusBorder = Color.Accent.Primary,
        Divider = Color.Border.PopupDivider,
        ItemText = Color.Text.Primary,
        Hover = White05,
        Selected = RGBA("a8d8ff", 0.14),
        SelectedHover = RGBA("a8d8ff", 0.20),
        SelectedText = Color.Text.MenuSelected,
        Check = Color.Accent.Primary,
    },
    PanelHeader = {
        Fill = Color.Surface.PanelHeader,
        HoverFill = Color.Surface.PanelHeaderHover,
        Divider = Color.Surface.PanelDivider,
        Text = Color.Text.PanelTitle,
        HoverText = Color.Text.PanelTitleHover,
        Icon = Color.Accent.Primary,
        Chevron = Color.Text.Secondary,
        ChevronHover = Color.Text.Primary,
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
}
Color.Status.Pending = Color.Status.Warning
Color.Status.Inactive = Color.Text.Disabled
Color.Status.Muted = Color.Text.Secondary

-- Fixed alpha variants are also centralized. Callers must not combine a
-- central RGB token with their own literal alpha for a fixed UI state.
Color.Overlay = {
    Page80 = RGBA("14161a", 0.80),
    Panel90 = RGBA("1b1e23", 0.90),
    Panel94 = RGBA("1b1e23", 0.94),
    Panel96 = RGBA("1b1e23", 0.96),
    White05 = White05,
    White16 = RGBA("ffffff", 0.16),
    White20 = RGBA("ffffff", 0.20),
    Black60 = RGBA("000000", 0.60),
    Black80 = RGBA("000000", 0.80),
}

Color.Shadow = {
    MenuWide = RGBA("000000", 0.10),
    MenuMiddle = RGBA("000000", 0.16),
    MenuTight = RGBA("000000", 0.22),
}

Color.Icon = {
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
    Link = Color.Accent.Primary,
}

Color.DynamicFallback = {
    Text = Color.Text.Primary,
    Border = Color.Border.Default,
    Fill = Color.Surface.Input,
}

Color.Composite = {
    Fill = Color.Surface.Panel,
    Border = Color.Border.Default,
    Utility = Color.Surface.Card,
    Text = Color.Text.Primary,
    Value = Color.Accent.Primary,
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
    placeholder = Color.Text.Placeholder,
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
    popupSearch = Color.Control.Menu.SearchFill,
    popupSearchBorder = Color.Control.Menu.SearchBorder,
    popupSearchFocus = Color.Control.Menu.SearchFocusBorder,
    popupDivider = Color.Control.Menu.Divider,
    menuSelected = Color.Control.Menu.Selected,
    menuSelectedHover = Color.Control.Menu.SelectedHover,
    menuSelectedText = Color.Control.Menu.SelectedText,
    menuHover = Color.Control.Menu.Hover,
    menuCheck = Color.Control.Menu.Check,
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

function Color.StripTextColor(text)
    local value = tostring(text or "")
    if _G.StripTextColorMarkup then return _G.StripTextColorMarkup(value) end
    return (string.gsub(string.gsub(value, "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
end

_G.ExwindGUIColor = Color
ExwindTools.UIColor = Color
