-- Temporary, memory-only catalog for inspecting every shared EXUI control.
-- The window host and every visible widget are created by EXUI / ExwindGrid.

local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI or not _G.ExwindGrid then return end

local EXUI = ExwindTools.UI
local Grid = _G.ExwindGrid

-- 4x4 预览只验证这组明确的 UI 单位参数，不修改 Grid 或 SettingsCard 的
-- 全局布局常量。Showcase 本身已有 8px page padding；renderer 再内缩 8px，
-- 得到 16px 页面留边。SettingsCard body 固有 12px padding；测试内容再内缩
-- 4px，得到 16px 内容留边。
local GRID_4X4_RENDERER = "ExwindGUIShowcase.Fixed4x4"
local GRID_4X4_PAGE_SUPPLEMENT = 8
local GRID_4X4_CARD_BODY_PADDING = 12
local GRID_4X4_CONTENT_SUPPLEMENT = 4
local GRID_4X4_COLUMN_GAP = 12
local GRID_4X4_ROW_GAP = 6
local GRID_4X4_ROW_HEIGHTS = { 28, 47, 48, 36 }
local GRID_4X4_CARD_HEADER_HEIGHT = 48

local function Grid4x4BodyHeight()
    local height = GRID_4X4_CONTENT_SUPPLEMENT * 2
        + GRID_4X4_ROW_GAP * (#GRID_4X4_ROW_HEIGHTS - 1)
    for _, rowHeight in ipairs(GRID_4X4_ROW_HEIGHTS) do height = height + rowHeight end
    return height
end

local GRID_4X4_BODY_HEIGHT = Grid4x4BodyHeight()
local GRID_4X4_CARD_HEIGHT = GRID_4X4_CARD_HEADER_HEIGHT
    + GRID_4X4_CARD_BODY_PADDING * 2 + GRID_4X4_BODY_HEIGHT
local GRID_4X4_SECTION_HEIGHT = GRID_4X4_PAGE_SUPPLEMENT * 2 + GRID_4X4_CARD_HEIGHT

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
    grid4x4CheckA = true,
    grid4x4CheckB = false,
    grid4x4CheckC = true,
    grid4x4CheckD = false,
    grid4x4InputA = "Alpha",
    grid4x4InputB = "Bravo",
    grid4x4InputC = "Charlie",
    grid4x4InputD = "Delta",
    grid4x4DropdownA = "balanced",
    grid4x4DropdownB = "manual",
    grid4x4SliderA = 42,
    grid4x4SliderB = 75,
    grid4x4AccentR = 0.216,
    grid4x4AccentG = 0.616,
    grid4x4AccentB = 0.916,
    grid4x4AccentA = 1,
    grid4x4WarningR = 0.94,
    grid4x4WarningG = 0.54,
    grid4x4WarningB = 0.2,
    grid4x4WarningA = 1,
    grid4x4ButtonClicks = 0,
}

local function ReleaseGrid4x4Control(control)
    if not control then return end
    local factory = _G.ExwindFactory
    if factory and factory.ReleaseGridWidget then
        factory:ReleaseGridWidget(control)
    else
        control:Hide()
        control:ClearAllPoints()
        control:SetParent(nil)
    end
end

local function ReleaseGrid4x4Preview(host)
    local preview = host and host._exGrid4x4Preview
    if not preview then return end
    for index = #preview.controls, 1, -1 do
        local control = preview.controls[index]
        -- ColorPickerFrame 是全局浮层。只关闭当前预览自己登记的 transaction
        -- owner，不能让已归池的按钮继续收到 picker 回调，也不能误关别页 picker。
        local picker = _G.ColorPickerFrame
        if picker and picker._exuiColorTransactionOwner == control then
            if picker:IsShown() then
                picker:Hide()
            else
                local token = picker._exuiColorTransactionToken
                picker._exuiColorTransactionOwner = nil
                picker._exuiColorTransactionToken = nil
                control:FinishColorTransaction(token)
            end
        end
        if control._gridType == "GridColorButton" then
            control._currentDb = nil
            control._currentKey = nil
            control._currentOnUpdate = nil
            control._currentChangeFlow = nil
            control._colorPickerSession = nil
        end
        ReleaseGrid4x4Control(control)
        preview.controls[index] = nil
    end
    if preview.card then preview.card:Release() end
    host._exGrid4x4Preview = nil
end

local function CreateGrid4x4Controls(host, ctx)
    ReleaseGrid4x4Preview(host)

    -- Grid item 的右侧还会保留 Grid.Padding（当前 2px）；右补边扣掉该值，
    -- 使 page 8 + renderer 右补边 + Grid.Padding 仍精确合计 16。
    local gridItemRightGap = math.max(0, tonumber(ctx.grid and ctx.grid.Padding) or 0)
    local rightSupplement = math.max(0, GRID_4X4_PAGE_SUPPLEMENT - gridItemRightGap)
    local cardWidth = math.max(640,
        ctx._layoutWidth - GRID_4X4_PAGE_SUPPLEMENT - rightSupplement)
    local card = EXUI:CreateSettingsCard(host, {
        id = "showcase-fixed-4x4",
        title = "四栏×四行布局预览",
        collapsible = false,
        minBodyHeight = GRID_4X4_BODY_HEIGHT,
    })
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", host, "TOPLEFT", GRID_4X4_PAGE_SUPPLEMENT, -GRID_4X4_PAGE_SUPPLEMENT)
    card:SetWidth(cardWidth)
    card:SetContentHeight(GRID_4X4_BODY_HEIGHT)
    card:Show()

    local body = card:GetBody()
    local contentWidth = cardWidth - GRID_4X4_CARD_BODY_PADDING * 2
        - GRID_4X4_CONTENT_SUPPLEMENT * 2
    local columnWidth = (contentWidth - GRID_4X4_COLUMN_GAP * 3) / 4
    local preview = { card = card, controls = {} }
    host._exGrid4x4Preview = preview

    local rowTops = { GRID_4X4_CONTENT_SUPPLEMENT }
    for rowIndex = 2, #GRID_4X4_ROW_HEIGHTS do
        rowTops[rowIndex] = rowTops[rowIndex - 1]
            + GRID_4X4_ROW_HEIGHTS[rowIndex - 1] + GRID_4X4_ROW_GAP
    end

    local function Place(control, rowIndex, columnIndex, labelOffset)
        preview.controls[#preview.controls + 1] = control
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", body, "TOPLEFT",
            GRID_4X4_CONTENT_SUPPLEMENT
                + (columnIndex - 1) * (columnWidth + GRID_4X4_COLUMN_GAP),
            -(rowTops[rowIndex] + (labelOffset or 0)))
        control:SetWidth(columnWidth)
        control:Show()
        return control
    end

    local function Checkbox(key, label, column)
        return Place(EXUI:CreateCheckbox(body, label, sampleDB[key] == true, function(value)
            sampleDB[key] = value == true
        end), 1, column)
    end

    Checkbox("grid4x4CheckA", "启用提示", 1)
    Checkbox("grid4x4CheckB", "显示计时", 2)
    Checkbox("grid4x4CheckC", "锁定位置", 3)
    Checkbox("grid4x4CheckD", "仅战斗中", 4)

    local function Input(key, label, column)
        return Place(EXUI:CreateEditBox(body, sampleDB[key], columnWidth, 28, label, {
            onEnter = function(value) sampleDB[key] = value end,
            onEditFocusLost = function(value) sampleDB[key] = value end,
        }), 2, column, 18)
    end

    Input("grid4x4InputA", "名称 A", 1)
    Input("grid4x4InputB", "名称 B", 2)
    Input("grid4x4InputC", "名称 C", 3)
    Input("grid4x4InputD", "名称 D", 4)

    local function ColorChangeFlow(key)
        return function()
            local function Store(value)
                sampleDB[key .. "R"] = value.r
                sampleDB[key .. "G"] = value.g
                sampleDB[key .. "B"] = value.b
                sampleDB[key .. "A"] = value.a
            end
            return {
                onBegin = function() end,
                onLive = Store,
                onCommit = Store,
            }
        end
    end

    local modeItems = { { "平衡", "balanced" }, { "性能", "performance" }, { "精确", "precise" } }
    Place(EXUI:CreateDropdown(body, columnWidth, "运行模式", modeItems,
        sampleDB.grid4x4DropdownA, function(value) sampleDB.grid4x4DropdownA = value end), 3, 1, 18)
    Place(EXUI:CreateDropdown(body, columnWidth, "触发方式",
        { { "自动", "auto" }, { "手动", "manual" }, { "混合", "hybrid" } },
        sampleDB.grid4x4DropdownB, function(value) sampleDB.grid4x4DropdownB = value end), 3, 2, 18)
    Place(EXUI:CreateSlider(body, columnWidth, "强度", 0, 100, sampleDB.grid4x4SliderA, 1,
        nil, {
            onLive = function(value) sampleDB.grid4x4SliderA = value end,
            onCommit = function(value) sampleDB.grid4x4SliderA = value end,
        }), 3, 3)
    Place(EXUI:CreateSlider(body, columnWidth, "透明度", 0, 100, sampleDB.grid4x4SliderB, 1,
        nil, {
            onLive = function(value) sampleDB.grid4x4SliderB = value end,
            onCommit = function(value) sampleDB.grid4x4SliderB = value end,
        }), 3, 4)

    Place(EXUI:CreateColorButton(body, "强调色", sampleDB, "grid4x4Accent", true, nil,
        { _changeFlow = ColorChangeFlow("grid4x4Accent") }), 4, 1)
    Place(EXUI:CreateColorButton(body, "警告色", sampleDB, "grid4x4Warning", true, nil,
        { _changeFlow = ColorChangeFlow("grid4x4Warning") }), 4, 2)
    Place(EXUI:CreateButton(body, columnWidth, 32, "应用示例", function()
        sampleDB.grid4x4ButtonClicks = sampleDB.grid4x4ButtonClicks + 1
    end, { variant = "primary" }), 4, 3)
    Place(EXUI:CreateButton(body, columnWidth, 32, "重置计数", function()
        sampleDB.grid4x4ButtonClicks = 0
    end), 4, 4)
end

Grid:RegisterCustomRenderer(GRID_4X4_RENDERER, {
    measure = function()
        return GRID_4X4_SECTION_HEIGHT
    end,
    mount = function(host, ctx)
        CreateGrid4x4Controls(host, ctx)
    end,
    release = function(host)
        ReleaseGrid4x4Preview(host)
    end,
})

local layout = {}
local row = 1
local window

local function RefreshShowcase()
    C_Timer.After(0, function()
        if window and window:IsShown() then window:Render(layout, sampleDB, 100, true) end
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
    { type = "button", key = "buttonPrimary", label = "Primary", variant = "primary", x = 1, w = 22 },
    { type = "button", key = "buttonSecondary", label = "Secondary", variant = "secondary", x = 26, w = 22 },
    { type = "button", key = "buttonDanger", label = "Danger", variant = "danger", x = 51, w = 22 },
    { type = "button", key = "buttonDisabled", label = "Disabled", variant = "secondary", disabled = true, x = 76, w = 22 },
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

Chapter("11", "11 · ColorButton")
Add({ type = "color", key = "accentColor", label = "强调色（RGBA）", h = 5 })

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

Chapter("20_1_aura_bars", "20.1 附项 · AuraDuration / AuraApplication")
Add({ type = "auradurationbargroup", key = "durationBar", label = "Aura Duration Bar", measure = true, h = 24 })
Add({ type = "auraapplicationbargroup", key = "applicationBar", label = "Aura Application Bar", measure = true, h = 20 })

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

Chapter("fixed_4x4", "四栏×四行布局预览")
Add({
    type = "custom", key = "fixedGrid4x4", renderer = GRID_4X4_RENDERER,
    measure = true, h = 28,
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
window:SetScript("OnHide", function(self)
    self:Release()
    rendered = false
end)

SLASH_EXWINDGUISHOWCASE1 = "/exuishowcase"
SLASH_EXWINDGUISHOWCASE2 = "/exgui"
SlashCmdList.EXWINDGUISHOWCASE = function()
    if not rendered then
        window:Render(layout, sampleDB, 100)
        rendered = true
    end
    window:Toggle()
end
