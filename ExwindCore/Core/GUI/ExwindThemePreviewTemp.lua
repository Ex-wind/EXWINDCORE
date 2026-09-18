-- TEMPORARY: remove this file and its TOC entry after choosing a theme.
-- Paint-only preview: never changes GUIColors, configuration, bindings or routes.
local ET = _G.ExwindTools
local UI, Shell, GC = ET.UI, ET.UnifiedPanel, ET.GUIColors
local selected, tool, status, painting, pending
local records = setmetatable({}, { __mode = "k" })
local watchedFrames = setmetatable({}, { __mode = "k" })
local menus = setmetatable({}, { __mode = "k" })

local function RGB(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1 }
end

local function Blend(base, overlay)
    local alpha = overlay[4]
    return { base[1] * (1 - alpha) + overlay[1] * alpha,
        base[2] * (1 - alpha) + overlay[2] * alpha,
        base[3] * (1 - alpha) + overlay[3] * alpha, 1 }
end

-- All ten choices keep the former #02 GitHub base. Only control/menu fills vary.
-- name, input/dropdown/unchecked checkbox, popup, popup search
local definitions = {
    { "微亮", "1C222B", "252D38", "202833" },
    { "均衡", "242C36", "2D3743", "28323E" },
    { "柔亮", "2B3541", "35414F", "303B49" },
    { "明亮", "343F4D", "3E4B5B", "384555" },
    { "高亮", "3E4B5A", "485769", "425163" },
    { "中性灰", "2C3036", "363C44", "30363E" },
    { "冷蓝灰", "293748", "344459", "2E3D50" },
    { "柔暖灰", "35322F", "403C38", "393632" },
    { "控件亮·菜单柔", "3A4655", "2D3743", "35414F" },
    { "控件柔·菜单亮", "28323E", "414E5F", "344151" },
}
local themes = {}
for index, definition in ipairs(definitions) do
    local theme = { name = definition[1], page = RGB("0D1117"), panel = RGB("161B22"),
        card = RGB("21262D"), header = RGB("1C2128"), border = RGB("444C56"),
        text = RGB("E6EDF3"), muted = RGB("9DA7B3"),
        input = RGB(definition[2]), popup = RGB(definition[3]), search = RGB(definition[4]),
        disabledInput = RGB("0D1117") }
    theme.borderHover = Blend(theme.border, { 1, 1, 1, 0.18 })
    theme.cardSelected = Blend(theme.card, GC.menuSelected)
    theme.cardHover = Blend(theme.card, GC.menuHover)
    themes[index] = theme
end

local roles = {
    { GC.page, "page" }, { GC.panel, "panel" }, { GC.card, "card" },
    { GC.header, "header" }, { GC.headerHover, "card" },
    { GC.input, "input" }, { GC.popup, "popup" }, { GC.popupSearch, "search" },
    { GC.inputDisabled, "disabledInput" }, { GC.disabledFill, "header" },
    { GC.panelBorder, "border" }, { GC.headerDivider, "border" },
    { GC.inputHoverBorder, "borderHover" }, { GC.cardHoverBorder, "borderHover" },
    { GC.secondaryBorder, "border" }, { GC.secondaryHoverBorder, "borderHover" },
    { GC.popupBorder, "border" }, { GC.popupSearchBorder, "border" },
    { GC.popupDivider, "border" }, { GC.disabledBorder, "border" },
    { GC.text, "text" }, { GC.textDim, "muted" },
    { Blend(GC.card, GC.menuSelected), "cardSelected" },
    { Blend(GC.card, GC.menuHover), "cardHover" },
}

local function InScope(object)
    for _ = 1, 64 do
        if not object then return false end
        if object == tool or object == Shell.PreviewDock or object._exPreviewWheelOwner then return false end
        if object == Shell.Frame then return true end
        local owner = object.GetOwnerRegion and object:GetOwnerRegion()
        object = owner or (object.GetParent and object:GetParent())
    end
    return false
end

local function FindRole(r, g, b, a)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return end
    if issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b) or issecretvalue(a)) then return end
    if a ~= nil and a < 0.99 then return end -- Preserve translucent selections and status overlays.
    for _, entry in ipairs(roles) do
        local color = entry[1]
        if math.abs(r - color[1]) < 0.0001 and math.abs(g - color[2]) < 0.0001
            and math.abs(b - color[3]) < 0.0001 then return entry[2] end
    end
end

local function Paint(object, method, entry)
    if not entry.source then return end
    local color = selected and InScope(object) and themes[selected][entry.role] or entry.source
    painting = true
    object[method](object, color[1], color[2], color[3], entry.source[4])
    painting = false
end

local function Remember(object, method, r, g, b, a)
    if painting then return end
    local entry = records[object][method]
    local role = InScope(object) and FindRole(r, g, b, a)
    entry.source = role and { r, g, b, a == nil and 1 or a } or nil
    entry.role = role
    if selected and role then Paint(object, method, entry) end
end

local function Watch(object, method, getter)
    local methods = records[object]
    if not methods then methods = {}; records[object] = methods end
    if methods[method] then return end
    methods[method] = {}
    hooksecurefunc(object, method, function(self, r, g, b, a) Remember(self, method, r, g, b, a) end)
    if getter then Remember(object, method, object[getter](object)) end
end

local function WatchSurface(frame)
    if not InScope(frame) then return end
    for _, skin in pairs(frame._exModernSurfaces or {}) do
        if skin.active then
            for _, piece in ipairs(skin.pieces) do
                Watch(piece.texture, "SetVertexColor", "GetVertexColor")
            end
        end
    end
end

local Scan, QueueScan
local function Visit(frame, menuSurface)
    if not InScope(frame) then return end
    if not watchedFrames[frame] then
        watchedFrames[frame] = true
        frame:HookScript("OnShow", function() if selected then QueueScan() end end)
    end
    if frame.GetBackdrop and frame:GetBackdrop() then
        Watch(frame, "SetBackdropColor", "GetBackdropColor")
        Watch(frame, "SetBackdropBorderColor", "GetBackdropBorderColor")
    end
    WatchSurface(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsObjectType("FontString") then
            Watch(region, "SetTextColor", "GetTextColor")
        elseif menuSurface and region:IsObjectType("Texture") then
            Watch(region, "SetVertexColor", "GetVertexColor")
            if not records[region].SetVertexColor.source then
                Remember(region, "SetVertexColor", region:GetVertexColor())
            end
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do Visit(child, menuSurface) end
end

Scan = function()
    if Shell.Frame then Visit(Shell.Frame) end
    for menu in pairs(menus) do
        if menu:IsShown() and InScope(menu) then Visit(menu, true) end
    end
end
QueueScan = function()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if selected and Shell.Frame and Shell.Frame:IsShown() then Scan() end
    end)
end

local function SelectTheme(index)
    Scan()
    selected = index
    for object, methods in pairs(records) do
        for method, entry in pairs(methods) do Paint(object, method, entry) end
    end
    if status then status:SetText(index and ("当前：" .. themes[index].name) or "当前：原配色") end
end

-- Capture solid decorative backgrounds at their existing creation/paint point.
-- No constructor replacement, palette mutation or settings-page reconstruction.
hooksecurefunc(UI, "CreateVisualTexture", function(_, parent)
    if not parent or not InScope(parent) then return end
    for _, region in ipairs({ parent:GetRegions() }) do
        if region:IsObjectType("Texture") then Watch(region, "SetColorTexture") end
    end
end)
hooksecurefunc(UI, "SetControlSurface", function(_, frame)
    WatchSurface(frame)
    if selected and InScope(frame) then QueueScan() end
end)
hooksecurefunc(Shell, "SelectProvider", function() if selected then QueueScan() end end)
-- Blizzard menus live outside the settings frame tree. Follow their actual owner.
-- OwnerRegion is assigned after Generate, so inspect once on the next UI tick.
hooksecurefunc(UI.ModernMenuStyleMixin, "Generate", function(menu)
    menus[menu] = true
    C_Timer.After(0, function()
        if menu:IsShown() and InScope(menu) then Visit(menu, true) end
    end)
end)

local function CreateTool()
    if tool or not Shell.Frame then return end
    -- Existing shared card and button constructors; no private button skin.
    tool = UI:CreateSettingsCard(Shell.Frame, { title = "02 基础 · 控件配色" })
    tool:SetWidth(202)
    tool:SetPoint("TOPLEFT", Shell.Frame, "TOPRIGHT", 10, 0)
    tool:SetFrameStrata("DIALOG")
    tool:SetFrameLevel(Shell.Frame:GetFrameLevel() + 150)
    tool:SetClampedToScreen(true)
    local body = tool:GetBody()
    status = UI:CreateVisualFontString(body, EXFONTFRAME, "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 12, -8)
    status:SetText("当前：原配色")
    for index, theme in ipairs(themes) do
        local choice = index
        local button = UI:CreateButton(body, 178, 28, string.format("%02d  %s", index, theme.name),
            function() SelectTheme(choice) end)
        button:SetPoint("TOPLEFT", 12, -30 - (index - 1) * 32)
    end
    local restore = UI:CreateButton(body, 178, 28, "恢复当前配色", function() SelectTheme(nil) end)
    restore:SetPoint("TOPLEFT", 12, -354)
    local hint = UI:CreateVisualFontString(body, EXFONTFRAME, "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 12, -391)
    hint:SetWidth(178)
    hint:SetText("仅预览，不保存\n关闭总面板或重载即恢复")
    tool:SetContentHeight(428)
    Shell.Frame:HookScript("OnHide", function() SelectTheme(nil) end)
    Shell.Frame:HookScript("OnShow", function() tool:Show() end)
    tool:Show()
end
hooksecurefunc(Shell, "CreateFrame", CreateTool)
if Shell.Frame then CreateTool() end
