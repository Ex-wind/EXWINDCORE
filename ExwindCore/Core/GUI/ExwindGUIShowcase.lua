-- Shared control catalog: /exgui. Demonstration values stay in this file only.
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

-- Only this catalog owns these demonstration values. No module DB is borrowed.
local chapterNumber = 0
local function CatalogChapter(title)
    chapterNumber = chapterNumber + 1
    Chapter(tostring(chapterNumber), tostring(chapterNumber) .. " · " .. title)
end
local function Description(text)
    Add({ type = "description", label = text, h = 4 })
end
local choices = { { "概览", "overview" }, { "详情", "details" }, { "高级", "advanced" } }
local optionItems = {
    { id = "overview", label = "概览" }, { id = "details", label = "详情" },
    { id = "advanced", label = "高级" }, { id = "locked", label = "禁用项", disabled = true },
}
local modeItems = { { "平衡", "balanced" }, { "性能", "performance" }, { "精确", "precise" } }

-- Constructors without a Grid type are still displayed through their real shared API.
-- Native decorations stay with the pooled custom host; pooled controls are released.
local CATALOG_RENDERER = "ExwindGUIShowcase.Catalog"
local function ReleaseCatalog(host)
    for index = #(host._catalogControls or {}), 1, -1 do
        local control = host._catalogControls[index]
        EXUI:RestoreSettingsListControl(control)
        if control._exButtonPresentation == "sidebar" then
            EXUI:ReleaseSidebarNavigationButton(control)
        elseif type(control.Release) == "function" then
            control:Release()
        else
            ReleaseGrid4x4Control(control)
        end
    end
    host._catalogControls = nil
    for _, control in pairs(host._catalogDecorations or {}) do control:Hide() end
end
Grid:RegisterCustomRenderer(CATALOG_RENDERER, {
    measure = function(_, opts) return opts.height end,
    release = ReleaseCatalog,
    mount = function(host, ctx)
        ReleaseCatalog(host)
        host._catalogControls = {}
        host._catalogDecorations = host._catalogDecorations or {}
        local family = ctx.element.opts.family
        local width = ctx._layoutWidth
        local function Place(control, x, y, w, h)
            control:ClearAllPoints()
            control:SetPoint("TOPLEFT", host, "TOPLEFT", x, -y)
            control:SetSize(w, h or control:GetHeight())
            control:Show()
            return control
        end
        local function Owned(control, x, y, w, h)
            host._catalogControls[#host._catalogControls + 1] = control
            return Place(control, x, y, w, h)
        end
        local function Decoration(key, create, x, y, w, h)
            local control = host._catalogDecorations[key]
            if not control then control = create(); host._catalogDecorations[key] = control end
            return Place(control, x, y, w, h)
        end
        if family == "boolean" then
            local cell = (width - 36) / 4
            for index, presentation in ipairs({ "checkbox", "switch", "pill", "card" }) do
                for state = 1, 3 do
                    local key = "boolean_" .. presentation .. state
                    local control = EXUI:CreateCheckbox(host,
                        presentation .. ({ " · 开", " · 关", " · 禁用" })[state], sampleDB[key],
                        function(value) sampleDB[key] = value end)
                    Owned(control, (index - 1) * (cell + 12), (state - 1) * 50, cell, 38)
                    if presentation ~= "checkbox" then
                        EXUI:PrepareSettingsListControl(control, { presentation = presentation, hideLabel = false })
                    end
                    if state == 3 then control.checkbox:Disable() end
                end
            end
        elseif family == "tristate" then
            for index, value in ipairs({ "neutral", "include", "exclude" }) do
                local key = "triState" .. index
                Owned(EXUI:CreateTriStateChip(host, {
                    label = value, value = sampleDB[key], width = 180,
                    onChange = function(nextValue) sampleDB[key] = nextValue end,
                }), (index - 1) * 200, 0, 180, 32)
            end
        elseif family == "sidebar" then
            Decoration("sidebarHeader", function()
                return EXUI:CreateSidebarNavigationHeader(host, "模块分类 / SidebarNavigationHeader")
            end, 0, 0, width, 24)
            for index, spec in ipairs({ { "普通入口", false, true, 0 },
                { "选中入口", true, true, 0 }, { "子项入口", false, true, 1 },
                { "禁用入口", false, false, 0 } }) do
                Owned(EXUI:CreateSidebarNavigationButton(host, spec[1], nil,
                    { selected = spec[2], enabled = spec[3], level = spec[4] }),
                    (index - 1) * (width / 4), 34, width / 4 - 12, 28)
            end
        elseif family == "sections" then
            for index, kind in ipairs({ "page", "section", "subsection", "information" }) do
                local section = EXUI:CreateSettingsSection(host, {
                    kind = kind, title = kind .. " · 标题", description = "共享标题与说明文字",
                })
                local w = width / 2 - 12
                local h = EXUI:UpdateSettingsSectionLayout(section, w)
                Owned(section, ((index - 1) % 2) * (width / 2), math.floor((index - 1) / 2) * 130, w, h)
            end
        elseif family == "rows" then
            local top = 0
            for index = 1, 3 do
                local rowControl = EXUI:CreateSettingsRow(host, {
                    label = "设置行 " .. index, description = index == 2 and "带补充说明的设置行" or nil,
                    isLast = index == 3,
                })
                local h = EXUI:UpdateSettingsRowLayout(rowControl, width, 28)
                Owned(rowControl, 0, top, width, h)
                top = top + h
            end
        elseif family == "table" then
            local header = EXUI:CreateSettingsTableHeader(host, { columns = {
                { title = "名称", weight = 2 }, { title = "状态", weight = 1 }, { title = "说明", weight = 3 },
            } })
            local h, columns = EXUI:UpdateSettingsTableHeaderLayout(header, width)
            Owned(header, 0, 0, width, h)
            for index = 1, 3 do
                local rowControl = EXUI:CreateSettingsTableRow(host, {
                    staticCells = { "示例 " .. index, index == 2 and "关闭" or "开启", "共享表格行与分隔线" },
                    isLast = index == 3,
                })
                local rowHeight = EXUI:UpdateSettingsTableRowLayout(rowControl, width, columns)
                Owned(rowControl, 0, h, width, rowHeight)
                h = h + rowHeight
            end
        elseif family == "cards" then
            for index = 1, 2 do
                local card = EXUI:CreateSettingsCard(host, {
                    id = "catalog-card-" .. index, title = index == 1 and "标准卡片" or "可折叠卡片",
                    collapsible = index == 2, minBodyHeight = 65,
                })
                card:SetContentHeight(65)
                Owned(card, (index - 1) * (width / 2), 0, width / 2 - 12, card:GetHeight())
                local text = EXUI:CreateDescription(card:GetBody(), "SettingsCard · 共享标题、边框与内容背景", width / 2 - 40)
                host._catalogControls[#host._catalogControls + 1] = text
                text:SetPoint("TOPLEFT", 4, -10)
            end
        elseif family == "group" then
            for index = 1, 2 do
                local surface = EXUI:CreateSettingsCardGroupSurface(host)
                EXUI:UpdateSettingsCardGroupSurfaceLayout(surface, width / 2 - 12, 84)
                Owned(surface, (index - 1) * (width / 2), 0, width / 2 - 12, 84)
            end
        elseif family == "images" then
            for index, radius in ipairs({ 4, 10, 20 }) do
                local image = Decoration("rounded" .. index, function()
                    return EXUI:CreateRoundedImage(host, radius)
                end, (index - 1) * 130, 0, 96, 96)
                image:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                image:SetCornerRadius(radius)
            end
        elseif family == "separators" then
            for index = 1, 3 do
                Decoration("separator" .. index, function()
                    return EXUI:CreateSettingsSeparator(host, width)
                end, 0, (index - 1) * 28, width * (1 - (index - 1) * .2), nil)
            end
        elseif family == "palette" then
            local colors = ExwindTools.GUIColors
            for index, name in ipairs({ "page", "panel", "card", "header", "input", "popup" }) do
                local surface = EXUI:CreateCard(host, width / 3 - 12, 76)
                Owned(surface, ((index - 1) % 3) * width / 3, math.floor((index - 1) / 3) * 88, width / 3 - 12, 76)
                EXUI:SetControlSurface(surface, 4, colors[name], colors.cardBorder)
                local label = EXUI:CreateDescription(surface, "GUIColors." .. name, width / 3 - 36)
                host._catalogControls[#host._catalogControls + 1] = label
                label:SetPoint("TOPLEFT", 12, -24)
            end
        end
    end,
})
local function Gallery(title, family, height)
    CatalogChapter(title)
    Add({ type = "custom", key = "catalog_" .. family, renderer = CATALOG_RENDERER,
        opts = { family = family, height = height }, measure = true, h = 5 })
end

CatalogChapter("Dropdown · 单选下拉")
for index = 1, 3 do
    local key = "catalogDropdown" .. index
    sampleDB[key] = index == 2 and "precise" or "balanced"
    Add({ type = "dropdown", key = key, label = ({ "普通下拉", "可搜索下拉", "禁用下拉" })[index],
        items = index == 2 and { { "平衡", "balanced" }, { isMenu = true, text = "更多模式",
            menu = { { "性能", "performance" }, { "精确", "precise" } } } } or modeItems,
        searchable = index == 2, disabled = index == 3, h = 6 })
end
for _, media in ipairs({ { "lsm_font", "字体" }, { "lsm_texture", "状态条材质" },
    { "lsm_border", "边框材质" }, { "lsm_background", "背景材质" }, { "lsm_sound", "声音与试听" } }) do
    CatalogChapter(media[1] .. " · " .. media[2])
    for index = 1, 2 do
        Add({ type = media[1], key = "catalog_" .. media[1] .. index,
            label = media[2] .. (index == 1 and " · 普通" or " · 搜索"), searchable = index == 2, h = 6 })
    end
end
CatalogChapter("MultiSelect · 多选下拉")
for index = 1, 2 do
    local key = "catalogMulti" .. index
    sampleDB[key] = index == 1 and { utility = true, preview = true } or {}
    Add({ type = "multiselect", key = key, label = index == 1 and "已有选项" or "空选项 / 可搜索",
        items = { { "工具", "utility" }, { "预览", "preview" }, { "编辑", "editor" } }, searchable = true, h = 6 })
end
CatalogChapter("Button · 文字按钮")
for _, disabled in ipairs({ false, true }) do
    local items = {}
    for index, variant in ipairs({ "primary", "secondary", "danger", "soft" }) do
        items[#items + 1] = { type = "button", label = variant .. (disabled and " · 禁用" or ""),
            variant = variant, disabled = disabled, x = 1 + (index - 1) * 25, w = 23 }
    end
    AddRow(5, items)
end
CatalogChapter("PicButton · 图片按钮")
for index = 1, 2 do
    Add({ type = "picbutton", key = "catalogPic" .. index, disabled = index == 2,
        iconNormal = "Interface\\Icons\\INV_Misc_QuestionMark", x = 1, w = 7, h = 6 })
end
for _, presentation in ipairs({ "checkbox", "switch", "pill", "card" }) do
    for state = 1, 3 do sampleDB["boolean_" .. presentation .. state] = state ~= 2 end
end
Gallery("Checkbox / Switch / Pill / Card · 布尔控件", "boolean", 154)
CatalogChapter("Slider · 滑块与数字输入")
for index, spec in ipairs({ { 0, 100, 1, 42 }, { 0, 1, .05, .65 }, { -100, 100, 5, -20 } }) do
    local key = "catalogSlider" .. index
    sampleDB[key] = spec[4]
    Add({ type = "slider", key = key, label = ({ "整数", "小数", "正负数 / 禁用" })[index],
        min = spec[1], max = spec[2], step = spec[3], disabled = index == 3, h = 6, measure = true })
end
CatalogChapter("Separator · 渐变分隔线")
for _, width in ipairs({ 100, 70, 40 }) do Add({ type = "divider", w = width, h = 3 }) end
Gallery("SettingsSeparator · 设置列表分隔线", "separators", 80)
CatalogChapter("Header / Subheader / Description · 标题与文字")
for _, kind in ipairs({ "header", "subheader", "description" }) do
    Add({ type = kind, label = kind .. " · 短标题 / 短文字", h = 5 })
    Add({ type = kind, label = kind .. " · 较长的示例文字，用来检查字号、行距、截断与内容区域的实际显示效果。", h = 6 })
end
CatalogChapter("ColorButton · 颜色与透明度")
for index = 1, 3 do
    local key = "catalogColor" .. index
    sampleDB[key .. "R"], sampleDB[key .. "G"], sampleDB[key .. "B"], sampleDB[key .. "A"] = .2, .4, .8, index == 2 and .35 or 1
    Add({ type = "color", key = key, label = ({ "不透明", "半透明", "禁用" })[index], disabled = index == 3, h = 5 })
end
CatalogChapter("EditBox · 输入框")
for index, value in ipairs({ "普通输入", "禁用输入", "多行输入\n第二行示例\n第三行示例" }) do
    local key = "catalogInput" .. index
    sampleDB[key] = value
    Add({ type = "input", key = key, label = "输入示例 " .. index, disabled = index == 2, h = index == 3 and 12 or 4 }, 3)
end
CatalogChapter("SegmentedControl · 分段单选")
for index = 1, 3 do
    local key = "catalogSegment" .. index
    sampleDB[key] = ({ "overview", "details", "advanced" })[index]
    Add({ type = "segmented", key = key, items = choices, disabled = index == 3, h = 5 })
end
CatalogChapter("TabGroup · 页签")
for index = 1, 2 do
    local key = "catalogTabs" .. index
    sampleDB[key] = index == 1 and "overview" or "details"
    Add({ type = "tabgroup", key = key, items = optionItems, disabled = index == 2, h = 5 })
end
CatalogChapter("OptionGroup · 单选与多选外观")
for index, appearance in ipairs({ "connected", "segmented", "compact", "form", "dungeon-aura", "load-card" }) do
    local key = "catalogOptions" .. index
    sampleDB[key] = "details"
    Description(appearance .. " · 单选")
    Add({ type = "optiongroup", key = key, mode = "single", appearance = appearance,
        items = optionItems, wrap = false, h = 5 })
end
sampleDB.catalogMultiple = { overview = true, advanced = true }
Description("默认外观 · 多选")
Add({ type = "optiongroup", key = "catalogMultiple", mode = "multiple", allowEmpty = true,
    items = optionItems, wrap = true, columns = 3, h = 9 })
for index, value in ipairs({ "neutral", "include", "exclude" }) do sampleDB["triState" .. index] = value end
Gallery("TriStateChip · 中立 / 包含 / 排除", "tristate", 44)
Gallery("SidebarNavigation · 侧栏导航", "sidebar", 76)
CatalogChapter("Card · 普通内容卡片")
for index = 1, 2 do
    Add({ type = "card", title = "内容卡片 " .. index,
        desc = index == 1 and "共享卡片背景与边框" or "较长的说明文字，用于检查卡片内部文字的间距与排版。", h = 12 })
end
Gallery("SettingsCard · 模块设置卡片", "cards", 160)
Gallery("SettingsCardGroupSurface · 连续卡片背景", "group", 96)
Gallery("SettingsSection · 分区标题", "sections", 270)
Gallery("SettingsRow · 设置列表行", "rows", 240)
Gallery("SettingsTable · 表头与表格行", "table", 200)
Gallery("RoundedImage · 圆角图片", "images", 110)
CatalogChapter("ItemIdentity / Enabled / Quantity / Delete · 独立物品控件")
for index = 1, 2 do
    local key = "catalogItem" .. index
    sampleDB[key] = { id = index == 1 and 6948 or 0, enabled = index == 1, quantity = index * 2 }
    AddRow(6, {
        { type = "itemenabled", key = key, x = 1, w = 10 },
        { type = "itemidentity", key = key, x = 12, w = 53 },
        { type = "itemquantity", key = key, x = 68, w = 15 },
        { type = "itemdelete", key = key, x = 88, w = 10, canDelete = true,
            onDelete = function(record) record.enabled = false; RefreshShowcase() end },
    })
end
CatalogChapter("PreviewCanvas · 预览画布")
Add({ type = "previewcanvas", key = "preview", h = 24 })
sampleDB.catalogPreviewEmpty = {}
Add({ type = "previewcanvas", key = "catalogPreviewEmpty", h = 18 })

-- Full-width composite examples keep their real measured heights.
for _, spec in ipairs({
    { "fontgroup", "FontGroup · 字体组", 36 },
    { "glow_settings", "GlowSettings · 发光组", 38 },
    { "icongroup", "IconGroup · 图标组", 40 },
    { "soundgroup", "SoundGroup · 声音组", 28 },
    { "timerbargroup", "TimerBarGroup · 计时条组", 40 },
    { "widgetlayout", "WidgetLayoutGroup · 排列与换行", 20 },
    { "modulecommonsettings", "ModuleCommonSettings · 通用设置组", 20 },
    { "anchorgroup", "AnchorGroup · 锚点组", 20 },
    { "texturegroup", "TextureGroup · 材质组", 28 },
    { "auradurationbargroup", "AuraDurationBar · 持续时间条", 28 },
    { "auraapplicationbargroup", "AuraApplicationBar · 层数条", 28 },
    { "auradispelbordergroup", "AuraDispelBorder · 驱散边框", 16 },
    { "aurasortgroup", "AuraSort · 排序组", 16 },
    { "aurachildelementsgroup", "AuraChildElements · 附属元素组", 40 },
}) do
    CatalogChapter(spec[2])
    for index = 1, 2 do
        local key = "catalog_" .. spec[1] .. index
        sampleDB[key] = {}
        local opts = {}
        if spec[1] == "fontgroup" then
            sampleDB[key] = { size = index == 1 and 14 or 20, shadow = index == 2 }
        elseif spec[1] == "widgetlayout" then
            opts.includeWrapDirection = index == 2
        elseif spec[1] == "modulecommonsettings" then
            sampleDB[key] = { enabled = index == 1, name = "演示 " .. index, amount = 50 }
            opts.presentation = index == 2 and "settings-list" or nil
            opts.fields = {
                { type = "checkbox", key = "enabled", label = "启用", presentation = index == 2 and "switch" or nil },
                { type = "input", key = "name", label = "名称" },
                { type = "slider", key = "amount", label = "数值", min = 0, max = 100, step = 1 },
            }
        elseif spec[1] == "aurachildelementsgroup" then
            sampleDB[key] = { children = index == 1 and {} or {
                { type = "text", enabled = true, label = "示例文字", font = "默认", size = 14,
                    r = 1, g = 1, b = 1, a = 1, x = 0, y = 0 },
            } }
            opts.onStructureChanged = RefreshShowcase
        end
        Description(index == 1 and "示例 A" or "示例 B")
        Add({ type = spec[1], key = key, label = spec[2] .. " · " .. index,
            opts = opts, measure = true, h = spec[3] }, 3)
    end
end
Gallery("GUIColors · 共享背景色", "palette", 184)
CatalogChapter("Grid · 四栏四行布局")
Add({ type = "custom", key = "fixedGrid4x4", renderer = GRID_4X4_RENDERER, measure = true, h = 28 })
CatalogChapter("ScrollFrame / ScrollBar · 滚动容器")
Description("本窗口正在使用共享 CreateScrollFrame / CreateScrollBar；滚动长目录即可检查滚动条、滑块、悬停和拖动。")
CatalogChapter("StandardModulePage · 页面控制器")
Description("页面控制器需要真实模块绑定，不作为演示控件实例化。卡片布局的完整交互也可通过 /excards 查看。")

window = EXUI:CreateShowcaseWindow({
    title = "EXUI 共享控件完整目录",
    subtitle = tostring(chapterNumber) .. " 类 · 共享控件与共享配色 · 独立内存样例 · /exgui",
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
