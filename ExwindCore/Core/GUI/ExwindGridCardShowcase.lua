-- Shared settings-card showcase for the Grid v1 container contract.
-- This file registers no page or route by itself. A development surface can
-- call Grid:MountCardShowcase(parent, context) after loading it.

local ExwindTools = _G.ExwindTools
local EXUI = ExwindTools and ExwindTools.UI
local Grid = ExwindTools and ExwindTools.Grid

if not (EXUI and Grid) then
    error("[ExwindGridCardShowcase] ExwindGrid.lua must load first")
end

local RENDERER_KEY = "ExwindGridCardShowcase.DynamicRows"

local function ReleaseControl(control)
    if not control then return end
    local factory = _G.ExwindFactory
    if factory then
        factory:ReleaseGridWidget(control)
    else
        control:Hide()
        control:SetParent(nil)
    end
end

local function LayoutDynamicRows(host, ctx, layoutWidth)
    local width = math.max(1, tonumber(layoutWidth) or ctx:GetContentWidth())
    local controls = host._exCardShowcaseControls
    if not controls then return end
    local buttonGap = 8
    local buttonWidth = math.max(88, (width - buttonGap) * 0.5)

    controls.add:ClearAllPoints()
    controls.add:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    controls.add:SetSize(buttonWidth, 30)
    controls.remove:ClearAllPoints()
    controls.remove:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    controls.remove:SetSize(buttonWidth, 30)

    local top = 40
    for index, row in ipairs(controls.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top)
        row:SetSize(width, 24)
        row.text:SetText("Dynamic shared row " .. tostring(index))
        top = top + 28
    end
    ctx:SetContentHeight(top)
end

local function RebuildDynamicRows(host, ctx)
    local controls = host._exCardShowcaseControls
    for index = #controls.rows, 1, -1 do
        ReleaseControl(controls.rows[index])
        controls.rows[index] = nil
    end
    for index = 1, host._exCardShowcaseRowCount do
        controls.rows[index] = EXUI:CreateDescription(host, "", 1)
    end
    LayoutDynamicRows(host, ctx)
end

Grid:RegisterCustomRenderer(RENDERER_KEY, {
    measure = function(_, opts)
        local rows = math.max(1, math.floor(tonumber(opts.initialRows) or 2))
        return 40 + rows * 28
    end,
    mount = function(host, ctx)
        host._exCardShowcaseRowCount = math.max(1,
            math.floor(tonumber(ctx.element.opts and ctx.element.opts.initialRows) or 2))
        local controls = { rows = {} }
        host._exCardShowcaseControls = controls
        controls.add = EXUI:CreateButton(host, 1, 30, "Add shared row", function()
            host._exCardShowcaseRowCount = host._exCardShowcaseRowCount + 1
            RebuildDynamicRows(host, ctx)
        end)
        controls.remove = EXUI:CreateButton(host, 1, 30, "Remove shared row", function()
            host._exCardShowcaseRowCount = math.max(1, host._exCardShowcaseRowCount - 1)
            RebuildDynamicRows(host, ctx)
        end)
        RebuildDynamicRows(host, ctx)
    end,
    layout = function(host, ctx, width)
        LayoutDynamicRows(host, ctx, width)
    end,
    release = function(host)
        local controls = host._exCardShowcaseControls
        if controls then
            for index = #controls.rows, 1, -1 do ReleaseControl(controls.rows[index]) end
            ReleaseControl(controls.remove)
            ReleaseControl(controls.add)
        end
        host._exCardShowcaseControls = nil
        host._exCardShowcaseRowCount = nil
    end,
})

local function NewShowcaseConfig()
    return {
        enabled = true,
        intensity = 50,
        font = {
            font = "Friz Quadrata TT",
            size = 14,
            r = 1, g = 1, b = 1, a = 1,
            outline = "",
            shadow = false,
            x = 0, y = 0,
        },
    }
end

function Grid:GetCardShowcaseDeclaration()
    local gap = tonumber(self.CardLayoutDefaults and self.CardLayoutDefaults.gap) or 12
    local halfWidth = { ratio = 0.5, offset = -gap * 0.5 }
    return {
        version = 1,
        title = "Grid settings-card showcase",
        cards = {
            {
                id = "declared-grid",
                title = "Declared Grid content",
                collapsible = true,
                placement = {
                    target = "$container",
                    point = "TOPLEFT",
                    relativePoint = "TOPLEFT",
                    width = halfWidth,
                },
                content = {
                    kind = "grid",
                    items = {
                        {
                            type = "checkbox", key = "enabled", label = "Enabled",
                            x = 1, y = 1, w = 96, h = 12,
                        },
                        {
                            type = "slider", key = "intensity", label = "Intensity",
                            min = 0, max = 100, step = 1,
                            x = 101, y = 1, w = 96, h = 12,
                        },
                    },
                },
            },
            {
                id = "shared-composite",
                title = "Shared composite",
                collapsible = true,
                placement = {
                    target = "declared-grid",
                    side = "right",
                    align = "start",
                    gap = gap,
                    width = halfWidth,
                },
                content = {
                    kind = "composite",
                    component = "fontgroup",
                    key = "font",
                },
            },
            {
                id = "dynamic-custom",
                title = "Custom dynamic content",
                collapsible = true,
                placement = {
                    target = "shared-composite",
                    side = "below",
                    align = "end",
                    gap = gap,
                    width = { ratio = 1 },
                },
                content = {
                    kind = "custom",
                    renderer = RENDERER_KEY,
                    opts = { initialRows = 2 },
                },
            },
        },
    }
end

function Grid:MountCardShowcase(parent, context)
    context = type(context) == "table" and context or {}
    local current = self.CardSessions[parent]
    if current and not current.released then current:Release() end
    parent._exCardShowcaseConfig = parent._exCardShowcaseConfig or NewShowcaseConfig()
    local mountContext = {}
    for key, value in pairs(context) do mountContext[key] = value end
    mountContext.pageId = mountContext.pageId or "ExwindCore.CardShowcase"
    mountContext.regionId = mountContext.regionId or "main"
    mountContext.config = mountContext.config or parent._exCardShowcaseConfig
    return self:MountCards(parent, self:GetCardShowcaseDeclaration(), mountContext)
end

local window

local function ReleaseWindowSession()
    if window and window._exCardSession then
        window._exCardSession:Release()
        window._exCardSession = nil
    end
end

local function EnsureShowcaseWindow()
    if window then return window end

    local name = "ExwindGridCardShowcaseWindow"
    window = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    window:SetSize(1040, 720)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetFrameLevel(520)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    EXUI:ApplyModernPanel(window)

    local title = EXUI:CreateVisualFontString(window, EXFONTFRAME, "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 22, -18)
    title:SetText("Exwind Grid 卡片容器展示")
    window.Title = title

    local subtitle = EXUI:CreateVisualFontString(window, EXFONTFRAME, "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetText("三种内容来源 · 相对锚点 · 动态高度 · 折叠与回收复用 · /exgridcards")
    window.Subtitle = subtitle

    local close = EXUI:CreateButton(window, 32, 30, "×", function() window:Hide() end,
        { variant = "soft", compact = true })
    close:SetPoint("TOPRIGHT", -16, -15)
    window.CloseButton = close

    local divider = EXUI:CreateSeparator(window, 996)
    divider:SetPoint("TOPLEFT", 22, -63)
    window.Divider = divider

    local scroll = EXUI:CreateScrollFrame(window)
    scroll:SetPoint("TOPLEFT", 20, -78)
    scroll:SetPoint("BOTTOMRIGHT", -38, 20)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 44)))
    end)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(982, 1)
    content:SetPoint("TOPLEFT")
    scroll:SetScrollChild(content)
    window.ScrollFrame, window.Content = scroll, content

    window:SetScript("OnHide", ReleaseWindowSession)
    window:Hide()
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    table.insert(_G.UISpecialFrames, name)
    return window
end

local function OpenCardShowcase()
    if type(EXUI.CreateSettingsCard) ~= "function" then
        print("|cffff8080[ExwindGrid]|r SettingsCard GUI contract is not loaded yet.")
        return false
    end
    local frame = EnsureShowcaseWindow()
    frame:Show()
    local ok, sessionOrReason = pcall(Grid.MountCardShowcase, Grid, frame.Content, {
        pageId = "ExwindCore.CardShowcase",
        regionId = "window",
        scrollFrame = frame.ScrollFrame,
        layoutDefaults = { left = 8, right = 8, top = 8, bottom = 20, gap = 12 },
    })
    if not ok then
        frame:Hide()
        print("|cffff8080[ExwindGrid]|r " .. tostring(sessionOrReason))
        return false
    end
    frame._exCardSession = sessionOrReason
    return true
end

SLASH_EXWINDGRIDCARDS1 = "/exgridcards"
SLASH_EXWINDGRIDCARDS2 = "/excards"
SlashCmdList.EXWINDGRIDCARDS = function()
    if window and window:IsShown() then
        window:Hide()
    else
        OpenCardShowcase()
    end
end
