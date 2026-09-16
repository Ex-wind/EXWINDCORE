-- Temporary, memory-only catalog for inspecting every shared EXUI control.
-- The window host and every visible widget are created by EXUI / ExwindGrid.

local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI or not _G.ExwindGrid then return end

local EXUI = ExwindTools.UI

local sampleDB = {
    dropdown = "balanced",
    multiSelect = { utility = true, preview = true },
    checkbox = true,
    checkboxDisabled = true,
    slider = 42,
    accentColorR = 0.216,
    accentColorG = 0.416,
    accentColorB = 0.816,
    accentColorA = 1,
    inputSingle = "共享单行输入",
    inputMulti = "多行输入同样使用共享深色焦点样式。\n这里仅保存于本次 UI 会话。",
    preview = {
        title = { enabled = true, label = "标题", x = -140, y = 24 },
        icon = { enabled = true, label = "图标", x = 0, y = 0 },
        timer = { enabled = true, label = "计时条", x = 145, y = -28 },
    },
    segmented = "details",
    itemConfig = { id = 6948, enabled = true, quantity = 3 },
    voiceSample = {
        triggers = {
            [0] = { enabled = true, sourceType = "pack", channel = "Master", volume = 1 },
            [1] = { enabled = true, sourceType = "lsm", channel = "SFX", volume = 0.8 },
            [2] = { enabled = false, sourceType = "file", customPath = "", channel = "Dialog", volume = 0.6 },
        },
    },
    moduleCommon = {
        enabled = true,
        threshold = 65,
        mode = "auto",
        name = "Showcase",
    },
    auraChildren = {
        children = {
            {
                type = "text", enabled = true, text = "示例文本", font = "默认", size = 14,
                r = 1, g = 1, b = 1, a = 1, outline = "OUTLINE", shadow = false,
                x = 0, y = 18, justifyH = "CENTER", justifyV = "MIDDLE",
            },
            {
                type = "glow", enabled = true, glowStyle = "Action Button Glow",
                glowColorR = 0.663, glowColorG = 0.792, glowColorB = 1, glowColorA = 1,
                glowOffset = 2, glowFrequency = 1, glowScale = 1,
            },
        },
    },
    choiceTabs = "overview",
    choiceOptions = { alpha = true, gamma = true },
}

local layout = {}
local row = 1
local window

local function RefreshShowcase()
    C_Timer.After(0, function()
        if window then window:Render(layout, sampleDB, 100, true) end
    end)
end

local function Add(item, gap)
    item.x = item.x or 1
    item.y = row
    item.w = item.w or 100
    item.h = item.h or 4
    layout[#layout + 1] = item
    row = row + item.h + (gap == nil and 1 or gap)
end

local function AddRow(height, items, gap)
    for _, item in ipairs(items) do
        item.y = row
        item.h = item.h or height
        layout[#layout + 1] = item
    end
    row = row + height + (gap == nil and 1 or gap)
end

local function Chapter(key, title)
    Add({ type = "subheader", key = "chapter_" .. key, label = title, h = 3 }, 1)
end

Chapter("0", "0 · Dropdown")
Add({
    type = "dropdown", key = "dropdown", label = "通用单选下拉",
    items = {
        { "平衡", "balanced" },
        { "性能", "performance" },
        { isMenu = true, text = "更多", menu = { { "精确", "precise" }, { "实验", "experimental" } } },
    },
    searchable = true, h = 6,
})

Chapter("1", "1 · LSM Font")
Add({ type = "lsm_font", key = "lsmFont", label = "字体", searchable = true, h = 6 })

Chapter("2", "2 · LSM Texture")
AddRow(6, {
    { type = "lsm_texture", key = "lsmStatusbar", label = "Statusbar", searchable = true, x = 1, w = 32 },
    { type = "lsm_border", key = "lsmBorder", label = "Border", searchable = true, x = 35, w = 32 },
    { type = "lsm_background", key = "lsmBackground", label = "Background", searchable = true, x = 69, w = 32 },
})

Chapter("3", "3 · LSM Sound")
Add({ type = "lsm_sound", key = "lsmSound", label = "音效与试听", searchable = true, h = 6 })

Chapter("4", "4 · MultiSelect")
Add({
    type = "multiselect", key = "multiSelect", label = "多选与清空",
    items = { { "工具", "utility" }, { "预览", "preview" }, { "编辑", "editor" }, { "调试", "debug" } },
    searchable = true, h = 6,
})

Chapter("5", "5 · Button")
AddRow(5, {
    { type = "button", key = "buttonPrimary", label = "Primary", variant = "primary", x = 1, w = 30 },
    { type = "button", key = "buttonNeutral", label = "Neutral", x = 35, w = 30 },
    { type = "button", key = "buttonDisabled", label = "Disabled", disabled = true, x = 69, w = 30 },
})

Chapter("5b", "5b · PicButton")
Add({
    type = "picbutton", key = "picButton",
    iconNormal = "Interface\\Icons\\INV_Misc_QuestionMark",
    iconPushed = "Interface\\Icons\\INV_Misc_QuestionMark",
    x = 1, w = 7, h = 5,
})

Chapter("6", "6 · Checkbox")
AddRow(4, {
    { type = "checkbox", key = "checkbox", label = "已启用", x = 1, w = 36 },
    { type = "checkbox", key = "checkboxDisabled", label = "禁用状态", disabled = true, x = 40, w = 36 },
})

Chapter("7", "7 · Slider")
Add({ type = "slider", key = "slider", label = "数值 / 步进 / 输入", min = 0, max = 100, step = 1, h = 2 }, 4)

Chapter("8", "8 · Separator")
Add({ type = "divider", key = "separator", h = 2 })

Add({ type = "header", key = "header", label = "9 · Header", h = 5 }, 2)

Chapter("10", "10 · FontGroup 章节说明")
Add({
    type = "description", key = "fontGroupNote",
    label = "源码第 10 节只有 FontGroup 的说明；真实构造入口位于 10.1，下面展示完整共享组。",
    h = 4,
})

Chapter("10_1", "10.1 · FontGroup")
Add({ type = "fontgroup", key = "fontGroup", label = "字体设置组", measure = true, h = 24 })

Chapter("11", "11 · ColorButton")
Add({ type = "color", key = "accentColor", label = "强调色（RGBA）", h = 5 })

Chapter("12", "12 · SoundGroup")
Add({
    type = "soundgroup", key = "soundGroup", label = "音效设置组", measure = true, h = 20,
    opts = { sources = { "lsm", "file", "tts" }, testLabel = "试听" },
})

Chapter("12_legacy", "旧 12 · GlowSettingsLegacy（兼容别名）")
Add({ type = "glow_settings_legacy", key = "legacyGlow", label = "旧版 LibCustomGlow 参数", h = 29 })

Chapter("12_voice", "12 附项 · VoiceGroup")
Add({ type = "voicegroup", key = "voiceSettings", parentKey = "voiceSample", label = "语音触发设置", h = 18 })

Chapter("13", "13 · EditBox")
Add({ type = "input", key = "inputSingle", label = "单行输入", h = 3 }, 3)
Add({ type = "input", key = "inputMulti", label = "多行输入", h = 12 })

Chapter("14", "14 · PreviewCanvas")
Add({ type = "previewcanvas", key = "preview", h = 20 })

Chapter("15", "15 · SegmentedControl")
Add({
    type = "segmented", key = "segmented",
    items = { { "概览", "overview" }, { "详情", "details" }, { "高级", "advanced" } },
    h = 5,
})

Chapter("16", "16 · ItemConfig")
Add({
    type = "itemconfig", key = "itemConfig", canDelete = true, h = 5,
    onDragUpdate = function(itemID) sampleDB.itemConfig.id = itemID end,
    onDelete = function()
        sampleDB.itemConfig.id = 0
        sampleDB.itemConfig.enabled = false
        RefreshShowcase()
    end,
})

Chapter("17", "17 · IconGroup")
Add({ type = "icongroup", key = "iconGroup", label = "图标设置组", measure = true, h = 24 })

Chapter("18", "18 · TimerBarGroup")
Add({ type = "timerbargroup", key = "timerBar", label = "计时条设置组", measure = true, h = 30 })

Chapter("19", "19 · GlowSettings（当前）")
Add({ type = "glow_settings", key = "modernGlow", label = "Core 原生动画发光", h = 30 })

Chapter("20", "20 · WidgetLayoutGroup")
Add({
    type = "widgetlayout", key = "widgetLayout", label = "排列设置组", measure = true, h = 16,
    opts = { includeMaxPerRow = true, includeWrapDirection = true },
})

Chapter("20_1_common", "20.1 · ModuleCommonSettingsGroup")
Add({
    type = "modulecommonsettings", key = "moduleCommon", label = "模块通用设置", measure = true, h = 18,
    opts = {
        fields = {
            { path = "enabled", type = "checkbox", label = "启用" },
            { path = "threshold", type = "slider", label = "阈值", min = 0, max = 100, step = 1 },
            { path = "mode", type = "dropdown", label = "模式", items = { { "自动", "auto" }, { "手动", "manual" } } },
            { path = "name", type = "input", label = "名称" },
        },
    },
})

Chapter("20_1_aura_bars", "20.1 附项 · AuraDuration / AuraApplication")
Add({ type = "auradurationbargroup", key = "durationBar", label = "Aura Duration Bar", measure = true, h = 24 })
Add({ type = "auraapplicationbargroup", key = "applicationBar", label = "Aura Application Bar", measure = true, h = 20 })

Chapter("20_1_anchor", "20.1 · AnchorGroup（源码同号第二项）")
Add({ type = "anchorgroup", key = "anchor", label = "锚点设置组", measure = true, h = 11 })

Chapter("21", "21 · TextureGroup")
Add({ type = "texturegroup", key = "texture", label = "材质设置组", measure = true, h = 27 })

Chapter("21_1", "21.1 · Aura 语义设置组")
Add({ type = "auradispelbordergroup", key = "auraBorder", label = "Aura Dispel Border", measure = true, h = 14 })
Add({ type = "aurasortgroup", key = "auraSort", label = "Aura Sort", measure = true, h = 12 })
Add({
    type = "aurachildelementsgroup", key = "auraChildren", label = "Aura Child Elements", measure = true, h = 38,
    opts = { onStructureChanged = RefreshShowcase },
})

Chapter("choice", "共享扩展 · Choice Tab / Option")
Add({
    type = "tabgroup", key = "choiceTabs", h = 5,
    items = {
        { id = "overview", label = "概览" },
        { id = "appearance", label = "外观" },
        { id = "behavior", label = "行为" },
        { id = "disabled", label = "禁用页", disabled = true },
    },
})
Add({
    type = "optiongroup", key = "choiceOptions", mode = "multiple", allowEmpty = true,
    appearance = "segmented", wrap = true, columns = 3, h = 8,
    items = {
        { id = "alpha", label = "Alpha" },
        { id = "beta", label = "Beta" },
        { id = "gamma", label = "Gamma" },
        { id = "locked", label = "Locked", disabled = true },
    },
})

Chapter("standard_page", "控制器说明 · StandardModulePage")
Add({
    type = "card", key = "standardModulePageNote", h = 10,
    title = "CreateStandardModulePage 不作为普通 Grid 控件实例化",
    desc = "它要求已登记的 module binding、preview surface 与 slider contract。本页仅核验其继续通过 Grid 与共享 EXUI 控件建立真实模块页面，不伪造业务模块。",
})

window = EXUI:CreateShowcaseWindow({
    title = "EXUI 共享控件展示",
    subtitle = "内存样例 · ExwindGrid 声明式渲染 · /exuishowcase",
})
local rendered = false

SLASH_EXWINDGUISHOWCASE1 = "/exuishowcase"
SLASH_EXWINDGUISHOWCASE2 = "/exgui"
SlashCmdList.EXWINDGUISHOWCASE = function()
    if not rendered then
        window:Render(layout, sampleDB, 100)
        rendered = true
    end
    window:Toggle()
end
