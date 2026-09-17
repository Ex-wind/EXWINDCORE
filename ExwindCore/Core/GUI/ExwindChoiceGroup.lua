-- Pooled tabs and option groups. Ordinary EXUI button skins are unchanged.
local UI = _G.ExwindTools.UI
local Factory = _G.ExwindFactory
local HOST, VIEW, ITEM = "EXUI.ChoiceGroup", "EXUI.ChoiceViewport", "EXUI.ChoiceItem"
local Methods = {}
local Appearance = UI.ControlAppearance
local Paint, Layout

Factory:InitCompositePool(HOST)
Factory:InitPool(VIEW, "Frame")
Factory:InitPool(ITEM, "Button", "BackdropTemplate", function(button)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button:SetFontString(button.label)
    button.label:SetWordWrap(false)
    button.label:SetJustifyH("CENTER")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.line = button:CreateTexture(nil, "OVERLAY")
    button.line:SetColorTexture(unpack(Appearance.colors.focus))
    button.line:SetPoint("BOTTOMLEFT", 0, 0)
    button.line:SetPoint("BOTTOMRIGHT", 0, 0)
    button.line:SetHeight(2)
end)

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for id, selected in pairs(value) do if selected == true then result[id] = true end end
    return result
end

local function Normalize(host, value)
    if host.mode == "multiple" then
        local selected = {}
        for _, item in ipairs(host.items) do
            if type(value) == "table" and value[item.id] == true then selected[item.id] = true end
        end
        if not host.allowEmpty and not next(selected) then
            for _, item in ipairs(host.items) do if not item.disabled then selected[item.id] = true; break end end
        end
        return selected
    end
    for _, item in ipairs(host.items) do if item.id == value then return value end end
    if not host.allowEmpty then
        for _, item in ipairs(host.items) do if not item.disabled then return item.id end end
    end
end

local function Selected(host, id)
    if host.mode == "multiple" then return host.selection[id] == true end
    return host.selection == id
end

local function CloseTooltip(button)
    if _G.GameTooltip and GameTooltip:GetOwner() == button then GameTooltip:Hide() end
end

Paint = function(button)
    local host, item = button._choiceHost, button._choiceItem
    if not host or not item then return end
    local selected = not button._choiceArrow and Selected(host, item.id)
    local disabled = host.disabled or item.disabled
    local hover = button._choiceHover and not disabled
    local pressed = button._choicePressed and not disabled
    button:SetEnabled(not disabled)
    local fill = selected and (pressed and Appearance.colors.menuSelectedHover or Appearance.colors.blueSoft)
        or (pressed and Appearance.colors.secondaryPressedFill
            or (hover and Appearance.colors.hover or Appearance.colors.input))
    local edge = selected and Appearance.colors.focus
        or (pressed and Appearance.colors.secondaryBorder
            or (hover and Appearance.colors.focus or Appearance.colors.border))
    if disabled then fill, edge = Appearance.colors.disabledFill, Appearance.colors.disabledBorder end
    UI:SetControlSurface(button, 4, fill, edge)
    button.label:SetTextColor(unpack(disabled and Appearance.colors.disabledText
        or (selected and Appearance.colors.lightBlue
            or (pressed and Appearance.colors.secondaryPressedText
                or (hover and Appearance.colors.text or Appearance.colors.muted)))))
    button.line:SetColorTexture(unpack(Appearance.colors.focus))
    button.line:SetShown(host.variant == "tabs" and selected and not button._choiceArrow)
    button.icon:SetAlpha(disabled and .35 or 1)
end

function Methods:GetValue() return Copy(self.selection) end

-- SetValue/SetItems are always silent, including calls made inside onChange.
function Methods:SetValue(value)
    if not self._choiceLease then return end
    self.selection = Normalize(self, value)
    self._choiceRevision = self._choiceRevision + 1
    for _, button in ipairs(self.buttons) do Paint(button) end
    Layout(self, true)
end

function Methods:SetDisabled(disabled)
    if not self._choiceLease then return end
    self.disabled = disabled == true
    for _, button in ipairs(self.buttons) do Paint(button) end
end

local function Choose(button)
    local host, item = button._choiceHost, button._choiceItem
    if not host or not host._choiceLease or not host:IsVisible() or host.disabled or item.disabled then return end
    local old, value = host:GetValue(), host:GetValue()
    if host.mode == "multiple" then
        value[item.id] = not value[item.id] or nil
        if not host.allowEmpty and not next(value) then return end
    elseif value == item.id then
        if not host.allowEmpty then return end
        value = nil
    else value = item.id end
    local lease, callback = host._choiceLease, host.onChange
    host:SetValue(value)
    if host._choiceLease ~= lease then return end
    local revision = host._choiceRevision
    if callback then
        local ok, accepted = pcall(callback, host:GetValue(), host)
        if host._choiceLease == lease and host._choiceRevision == revision and (not ok or accepted == false) then
            host:SetValue(old)
        end
        if not ok then error(accepted, 0) end
    end
end

local function AcquireButton(host, parent, item, onClick)
    local button = Factory:Acquire(ITEM, parent)
    button._choiceHost, button._choiceItem, button._choiceHover, button._choicePressed, button._choiceArrow = host, item, false, false, false
    Appearance.ApplyTextRole(button.label, "control", nil, "GameFontNormalSmall")
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", item.icon and 26 or 6, 0)
    button.label:SetPoint("RIGHT", -6, 0)
    button:SetText(item.label)
    button.icon:ClearAllPoints()
    button.icon:SetPoint("LEFT", 6, 0)
    button.icon:SetSize(16, 16)
    button.icon:SetTexture(item.icon)
    button.icon:SetShown(item.icon ~= nil)
    button:SetScript("OnClick", onClick or Choose)
    button:SetScript("OnEnter", function(self)
        self._choiceHover = true; Paint(self)
        if _G.GameTooltip and self._choiceItem then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self._choiceItem.label)
            if self._choiceItem.tooltip then GameTooltip:AddLine(self._choiceItem.tooltip, .8, .85, .9, true) end
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self._choiceHover, self._choicePressed = false, false
        Paint(self)
        CloseTooltip(self)
    end)
    button:SetScript("OnMouseDown", function(self) self._choicePressed = true; Paint(self) end)
    button:SetScript("OnMouseUp", function(self) self._choicePressed = false; Paint(self) end)
    button:SetScript("OnHide", function(self) self._choicePressed = false; CloseTooltip(self) end)
    button:EnableMouseWheel(host.variant == "tabs")
    button:SetScript("OnMouseWheel", function(_, delta) host:ScrollBy(-delta * 80) end)
    Factory:AttachPoolRelease(button, function(self)
        CloseTooltip(self)
        self._choiceHost, self._choiceItem, self._choiceHover, self._choicePressed, self._choiceArrow = nil, nil, nil, nil, nil
        self:SetScript("OnMouseWheel", nil); self:SetScript("OnMouseDown", nil)
        self:SetScript("OnMouseUp", nil); self:SetScript("OnHide", nil)
        self.line:Hide()
    end)
    return button
end

function Methods:ScrollBy(delta)
    if not self._choiceLease or self.variant ~= "tabs" then return end
    self.offset = math.max(0, math.min(self.maxOffset or 0, (self.offset or 0) + delta))
    Layout(self)
end

Layout = function(host, reveal)
    if not host._choiceLease or host._choiceLayout then return end
    host._choiceLayout = true
    local padding = host.choiceStyle == "segmented" and 2 or 0
    local width, gap, height = math.max(1, host:GetWidth() - padding * 2), host.gap, host.itemHeight - padding * 2
    local count = #host.buttons
    local columns = host.columns or (host.wrap and math.min(count, math.max(1, math.floor((width + gap) / (host.minItemWidth + gap)))) or count)
    columns = math.max(1, columns)
    local equalWidth = math.max(1, (width - (columns - 1) * gap) / columns)
    local x, y, lastRight = 0, 0, 0
    for index, button in ipairs(host.buttons) do
        local size = host.sizing == "content" and math.max(host.minItemWidth, button.label:GetUnboundedStringWidth() + (button._choiceItem.icon and 36 or 20)) or equalWidth
        if host.variant == "tabs" then size = math.max(host.minItemWidth, size) else size = math.min(width, size) end
        if host.wrap and x > 0 and (x + size > width + .5 or (host.columns and (index - 1) % columns == 0)) then x, y = 0, y + height + gap end
        button._choiceX, button._choiceY, button._choiceWidth = x, y, size
        x = x + size + gap; lastRight = math.max(lastRight, x - gap)
    end
    local overflow = host.variant == "tabs" and lastRight > width + .5
    local inset = overflow and 20 or 0
    local visibleWidth = math.max(1, width - 2 * inset)
    host.maxOffset = overflow and math.max(0, lastRight - visibleWidth) or 0
    host.offset = math.max(0, math.min(host.maxOffset, host.offset or 0))
    if reveal and overflow then
        for _, button in ipairs(host.buttons) do
            if Selected(host, button._choiceItem.id) then
                if button._choiceX < host.offset then host.offset = button._choiceX
                elseif button._choiceX + button._choiceWidth > host.offset + visibleWidth then
                    host.offset = math.min(host.maxOffset, button._choiceX + button._choiceWidth - visibleWidth)
                end
                break
            end
        end
    end
    host.viewport:ClearAllPoints()
    host.viewport:SetPoint("TOPLEFT", inset + padding, -padding)
    host.viewport:SetSize(visibleWidth, y + height)
    for _, button in ipairs(host.buttons) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", host.viewport, "TOPLEFT", button._choiceX - host.offset, -button._choiceY)
        button:SetSize(button._choiceWidth, height)
        local padding = button._choiceWidth < 32 and 2 or 6
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", button._choiceItem.icon and 26 or padding, 0)
        button.label:SetPoint("RIGHT", -padding, 0)
    end
    host.previous:SetShown(overflow); host.nextButton:SetShown(overflow)
    host.previous:SetSize(18, height); host.nextButton:SetSize(18, height)
    host.previous._choiceItem.disabled = host.offset <= 0
    host.nextButton._choiceItem.disabled = host.offset >= host.maxOffset
    Paint(host.previous); Paint(host.nextButton)
    host:SetHeight(y + height + padding * 2)
    host._choiceLayout = nil
end

local function CopyItems(items)
    local copied, seen = {}, {}
    for _, item in ipairs(items or {}) do
        assert(type(item.id) == "string" or type(item.id) == "number", "Choice item requires a string/number id")
        assert(not seen[item.id], "Duplicate choice id: " .. tostring(item.id))
        seen[item.id] = true
        assert(item.tone == nil or item.tone == "neutral" or item.tone == "include" or item.tone == "exclude", "Unknown choice tone")
        copied[#copied + 1] = { id = item.id, label = tostring(item.label or item.id), icon = item.icon,
            tooltip = item.tooltip, disabled = item.disabled == true, tone = item.tone }
    end
    return copied
end

function Methods:SetItems(items)
    if not self._choiceLease then return end
    local copied = CopyItems(items)
    for index = #self.buttons, 1, -1 do Factory:Release(ITEM, self.buttons[index]); self.buttons[index] = nil end
    self.items = copied
    for _, item in ipairs(copied) do self.buttons[#self.buttons + 1] = AcquireButton(self, self.viewport, item) end
    self:SetValue(self.selection)
end

function Methods:Release() Factory:Release(HOST, self) end

local function Create(parent, options, tabs)
    options = options or {}
    local items = CopyItems(options.items)
    local host = Factory:AcquireCompositeHost(HOST, parent)
    for key, method in pairs(Methods) do host[key] = method end
    host._choiceLease, host._choiceRevision = {}, 0
    host._gridType = "ChoiceGroup"
    host.variant = tabs and "tabs" or "options"
    host.choiceStyle = not tabs and (options.appearance == "compact" or options.appearance == "form" or options.appearance == "dungeon-aura" or options.appearance == "load-card" or options.appearance == "segmented") and options.appearance or nil
    if host.choiceStyle == "segmented" or host.choiceStyle == "compact" or host.choiceStyle == "load-card" then
        UI:SetControlSurface(host, 4, Appearance.colors.input, Appearance.colors.border)
    else
        UI:ClearControlSurface(host)
    end
    host.mode = not tabs and options.mode == "multiple" and "multiple" or "single"
    host.allowEmpty = not tabs and options.allowEmpty == true
    host.sizing = options.sizing == "content" and "content" or "equal"
    host.wrap = not tabs and options.wrap ~= false
    host.columns = options.columns and math.max(1, math.floor(options.columns)) or nil
    host.minItemWidth = math.max(16, options.minItemWidth or 44)
    host.gap = math.max(0, options.gap or (tabs and 0 or 3))
    host.itemHeight = math.max(18, options.itemHeight or (tabs and 32 or 27))
    host.disabled, host.offset, host.buttons, host.items = options.disabled == true, 0, {}, {}
    host.selection = options.value
    host.onChange = options.onChange
    host.viewport = Factory:Acquire(VIEW, host)
    host.viewport:SetClipsChildren(true)
    host.viewport:EnableMouse(false)
    host.previous = AcquireButton(host, host, { id = "previous", label = "‹" }, function() host:ScrollBy(-100) end)
    host.nextButton = AcquireButton(host, host, { id = "next", label = "›" }, function() host:ScrollBy(100) end)
    host.previous._choiceArrow, host.nextButton._choiceArrow = true, true
    host.previous:SetPoint("TOPLEFT"); host.nextButton:SetPoint("TOPRIGHT")
    host:EnableMouseWheel(tabs == true)
    host:SetScript("OnMouseWheel", function(self, delta) self:ScrollBy(-delta * 80) end)
    host:SetScript("OnSizeChanged", function(self) Layout(self, true) end)
    Factory:AttachPoolRelease(host, function(self)
        self._choiceLease, self.onChange = nil, nil
        self:SetScript("OnSizeChanged", nil); self:SetScript("OnMouseWheel", nil)
        for _, button in ipairs(self.buttons) do Factory:Release(ITEM, button) end
        Factory:Release(ITEM, self.previous); Factory:Release(ITEM, self.nextButton)
        Factory:Release(VIEW, self.viewport)
        self.buttons, self.items, self.selection, self.viewport, self.previous, self.nextButton = nil, nil, nil, nil, nil, nil
    end)
    host:SetWidth(options.width or 240)
    host:SetItems(items)
    return host
end

-- appearance = "segmented": shared outer border; only selected items have a border.
-- items = { { id, label, icon?, tooltip?, disabled?, tone? }, ... }
-- single value = id; multiple value = { [id] = true }. onChange may return false.
function UI:CreateTabGroup(parent, options) return Create(parent, options, true) end
function UI:CreateOptionGroup(parent, options) return Create(parent, options, false) end
