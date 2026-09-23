-- V2 owns presentation only. Existing owners retain controls, records and writes.
local UI, Factory = _G.ExwindTools.UI, _G.ExwindFactory
local Pages, Session = {}, {}
local POOL, GAP, PAD = "EXUI.SettingsV2.Node", 8, 12
Factory:InitCompositePool(POOL)

local Fields = {
    card = "title collapsible collapsed children",
    group = "title children", row = "children separator", cell = "children",
    actions = "children position align", columns = "columns children",
    ["repeat"] = "source template",
    control = "ref controlType mode", component = "ref",
    text = "text textSource", hint = "text textSource",
    button = "text action presentation",
}
local Common = "id kind visible enabled width weight height"
local ControlTypes = { input=true, multiline=true, checkbox=true, pill=true,
    choice=true, tristate=true, select=true, slider=true, color=true }
local AdapterMethods = { "mount", "update", "measure", "layout", "setEnabled", "setVisible", "release" }
local ControlMethods = { "mount", "release" }
local Build, ReleaseNode, RefreshNode, LayoutNode

local function Check(ok, message)
    if not ok then error("SettingsV2: " .. message, 3) end
end

local function Name(value)
    return type(value) == "string" and value ~= ""
end

local function Number(value)
    return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function Keys(value, fields, where)
    Check(type(value) == "table" and getmetatable(value) == nil, where .. " must be a plain table")
    local allowed = {}
    for field in fields:gmatch("%S+") do allowed[field] = true end
    for field in pairs(value) do Check(allowed[field], where .. ": unknown field " .. tostring(field)) end
end

local function Array(value, where)
    Check(type(value) == "table" and getmetatable(value) == nil, where .. " must be an array")
    local count = 0
    for key in pairs(value) do
        Check(type(key) == "number" and key >= 1 and key % 1 == 0, where .. ": invalid array index")
        count = count + 1
    end
    for i = 1, count do Check(value[i] ~= nil, where .. ": sparse array") end
    return count
end

-- Copy declarations only; never used for owner data or records.
local function DeclarationCopy(value, seen)
    local kind = type(value)
    Check(kind == "table" or kind == "string" or kind == "number" or kind == "boolean" or kind == "nil",
        "declarations must contain only data")
    if kind ~= "table" then return value end
    Check(not seen[value] and getmetatable(value) == nil, "cyclic/metatable declaration")
    seen[value] = true
    local copy = {}
    for key, entry in pairs(value) do
        Check(type(key) == "string" or type(key) == "number", "invalid declaration key")
        copy[key] = DeclarationCopy(entry, seen)
    end
    seen[value] = nil
    return copy
end

local function Reference(owner, bucket, name, where)
    Check(Name(name), where .. " requires a named reference")
    if not owner then return end
    local value = owner[bucket] and owner[bucket][name]
    Check(type(value) == "function", where .. ": missing " .. bucket .. "." .. name)
end

local function ValidateNode(node, owner, ids, depth, location, columnCount)
    Check(type(node) == "table" and Fields[node.kind], "unknown node kind")
    Keys(node, Common .. " " .. Fields[node.kind], tostring(node.id or node.kind))
    Check(Name(node.id) and not ids[node.id], "missing/duplicate node id " .. tostring(node.id))
    ids[node.id] = true
    local kind = node.kind
    if kind == "row" then
        Check(node.separator == nil or type(node.separator) == "boolean", node.id .. ": separator must be boolean")
    end
    if location == "page" then
        Check(kind == "card" or kind == "repeat", "page accepts only card/repeat")
    else
        Check(kind ~= "card", "card must be at page level")
    end
    if kind == "actions" then Check(location == "row" and not columnCount, "actions requires a non-column row") end
    if kind == "cell" then Check(location == "row" and columnCount, "cell requires a shared-column row") end
    if kind == "row" and columnCount then
        Check(Array(node.children, node.id) == columnCount, node.id .. ": cell count differs from columns")
        for _, cell in ipairs(node.children) do Check(cell.kind == "cell", node.id .. ": expected cells") end
    end
    for _, field in ipairs({ "width", "weight", "height" }) do
        Check(node[field] == nil or Number(node[field]), node.id .. ": invalid " .. field)
    end
    Check(not (node.width and node.weight), node.id .. ": width and weight are exclusive")
    if node.width or node.weight then
        Check((location == "row" or location == "actions") and not columnCount,
            node.id .. ": width/weight belong to flow-row items; shared cells use column widths")
    end
    Check(node.height == nil or kind == "control" or kind == "component" or kind == "button"
        or kind == "text" or kind == "hint", node.id .. ": height is leaf-only")
    for _, field in ipairs({ "visible", "enabled" }) do
        if node[field] ~= nil then Reference(owner, "predicates", node[field], node.id) end
    end
    if kind == "card" or kind == "group" then
        Check(type(node.title) == "string", node.id .. ": title required")
        if kind == "card" then
            Check(node.collapsible == nil or type(node.collapsible) == "boolean", "invalid collapsible")
            Check(node.collapsed == nil or type(node.collapsed) == "boolean", "invalid collapsed")
            Check(not node.collapsed or node.collapsible, "collapsed requires collapsible")
        end
    elseif kind == "control" or kind == "component" then
        Check(Name(node.ref), node.id .. ": ref required")
        if kind == "control" then Check(ControlTypes[node.controlType], node.id .. ": invalid controlType") end
        if node.mode then
            Check(node.controlType == "choice" and (node.mode == "single" or node.mode == "multiple"),
                node.id .. ": mode belongs to a single/multiple choice")
        end
        if owner then
            local bucket = kind == "control" and owner.controls or owner.components
            local adapter = bucket and bucket[node.ref]
            Check(type(adapter) == "table", node.id .. ": missing owner adapter " .. node.ref)
            for _, method in ipairs(kind == "control" and ControlMethods or AdapterMethods) do
                Check(type(adapter[method]) == "function", node.id .. ": adapter missing " .. method)
            end
            for _, method in ipairs(AdapterMethods) do
                Check(adapter[method] == nil or type(adapter[method]) == "function", node.id .. ": invalid " .. method)
            end
        end
    elseif kind == "button" then
        Check(type(node.text) == "string", node.id .. ": text required")
        Reference(owner, "actions", node.action, node.id)
        Check(node.presentation == nil or node.presentation == "primary" or node.presentation == "secondary"
            or node.presentation == "danger", node.id .. ": invalid button presentation")
    elseif kind == "text" or kind == "hint" then
        Check((node.text ~= nil) ~= (node.textSource ~= nil), node.id .. ": use text or textSource")
        if node.text ~= nil then Check(type(node.text) == "string", node.id .. ": text must be string") end
        if node.textSource then Reference(owner, "texts", node.textSource, node.id) end
    elseif kind == "actions" then
        for _, field in ipairs({ "position", "align" }) do
            local value = node[field]
            Check(value == nil or value == "start" or value == "center" or value == "end", "invalid " .. field)
        end
    elseif kind == "columns" then
        columnCount = Array(node.columns, node.id .. ".columns")
        Check(columnCount > 0, "empty columns")
        for _, column in ipairs(node.columns) do
            Keys(column, "width weight", "column")
            Check(not (column.width and column.weight), "column width and weight are exclusive")
            Check(column.width == nil or Number(column.width), "invalid column width")
            Check(column.weight == nil or Number(column.weight), "invalid column weight")
        end
    elseif kind == "repeat" then
        Check(depth < 2, node.id .. ": at most two nested repeats")
        Reference(owner, "sources", node.source, node.id)
        Check(type(node.template) == "table", node.id .. ": template required")
        if location == "page" then Check(node.template.kind == "card", "page repeat template must be card") end
        if columnCount then Check(node.template.kind == "row", "column repeat template must be row") end
        ValidateNode(node.template, owner, ids, depth + 1, location, columnCount)
    end
    if node.children then
        Array(node.children, node.id .. ".children")
        local actions = 0
        for _, child in ipairs(node.children) do
            if kind == "columns" then Check(child.kind == "row" or child.kind == "repeat", "columns accepts row/repeat") end
            if child.kind == "actions" then actions = actions + 1 end
            ValidateNode(child, owner, ids, depth, kind,
                (kind == "columns" or kind == "row") and columnCount or nil)
        end
        Check(actions <= 1, "a row supports one actions region")
        if actions == 1 then Check(node.children[#node.children].kind == "actions", "actions must be last in row") end
    elseif kind == "card" or kind == "group" or kind == "row" or kind == "cell"
        or kind == "actions" or kind == "columns" then
        Check(false, node.id .. ": children required")
    end
end

local function Validate(declaration, owner)
    Keys(declaration, "version cards", "page")
    Check(declaration.version == 2, "version must be 2")
    Array(declaration.cards, "cards")
    local ids = {}
    for _, node in ipairs(declaration.cards) do ValidateNode(node, owner, ids, 0, "page") end
end

function UI:RegisterSettingsPageV2(pageId, declaration)
    Check(Name(pageId) and Pages[pageId] == nil, "missing/duplicate page id")
    local copy = DeclarationCopy(declaration, {})
    Validate(copy)
    Pages[pageId] = copy
end

local function Acquire(parent)
    local host = Factory:AcquireCompositeHost(POOL, parent)
    if host._v2Label then host._v2Label:Hide() end
    if host._v2SettingsSeparator then host._v2SettingsSeparator:Hide() end
    host:SetScript("OnMouseWheel", nil)
    host:EnableMouseWheel(false)
    host:SetSize(1, 1)
    host:Show()
    return host
end

local function Place(frame, parent, x, y, width, height)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    frame:SetSize(math.max(1, width), math.max(1, height))
end

local function Records(node)
    local records = node.session.owner.sources[node.spec.source](node.scope)
    Array(records, node.spec.id .. " source")
    local seen = {}
    for _, record in ipairs(records) do
        Check(type(record) == "table" and not seen[record], node.spec.id .. ": records must be unique original tables")
        seen[record] = true
    end
    return records
end

local function Current(node)
    if not node.alive or not node.session.alive then return false end
    local scope = node.scope
    while scope do
        local repeatNode = scope._repeatNode
        if not repeatNode.alive then return false end
        local records = Records(repeatNode)
        if records[scope.index] ~= scope.item then return false end
        scope = scope.parent
    end
    return true
end

local function Interactive(node)
    if not Current(node) or not node.session.root:IsVisible() then return false end
    while node do
        if node.visible == false or node.enabled == false then return false end
        if node.spec.kind == "card" and node.frame._exSettingsCardCollapsed then return false end
        node = node.parent
    end
    return true
end

local function Context(node)
    local ctx = { scope = node.scope }
    function ctx:IsCurrent() return Current(node) end
    function ctx:Guard(callback)
        Check(type(callback) == "function", "Guard expects a callback")
        return function(...)
            if Interactive(node) then return callback(...) end
        end
    end
    function ctx:ReportHeight(height)
        if not Current(node) then return false end
        Check(type(height) == "number" and height >= 0 and height < math.huge, "invalid reported height")
        if node.reportedHeight ~= height then
            node.reportedHeight = height
            node.session:Invalidate()
        end
        return true
    end
    function ctx:Invalidate()
        if not Current(node) then return false end
        node.reportedHeight = nil
        node.session:Invalidate()
        return true
    end
    return ctx
end

local function Text(node)
    local text = node.spec.text
    if node.spec.textSource then text = node.session.owner.texts[node.spec.textSource](node.scope) end
    Check(type(text) == "string", node.spec.id .. ": text source must return string")
    node.label:SetText(text)
end

-- Defaults operate on an existing EXUI control, never a value/configuration.
local ControlDefaults = {}
function ControlDefaults.update() end
function ControlDefaults.measure(widget, context, width)
    widget:SetWidth(width)
    return widget:GetHeight()
end
function ControlDefaults.layout(widget, context, width, height)
    Place(widget, widget:GetParent(), 0, 0, width, height)
end
function ControlDefaults.setEnabled(widget, context, enabled)
    local target = widget.checkbox or widget.editBox or widget
    if widget.SetDisabled then widget:SetDisabled(not enabled)
    elseif target.SetEnabled then target:SetEnabled(enabled)
    else Check(enabled, "control needs an owner setEnabled implementation") end
end
function ControlDefaults.setVisible(widget, context, visible)
    if not visible then
        if widget.CloseMenu then widget:CloseMenu() end
        local editBox = widget.editBox or widget
        if editBox.ClearFocus then editBox:ClearFocus() end
    end
    widget:SetShown(visible)
end

local function ControlAdapter(provider)
    return setmetatable({}, { __index=function(_, method) return provider[method] or ControlDefaults[method] end })
end

Build = function(session, spec, parentFrame, scope, parent)
    local node = { session=session, spec=spec, scope=scope, parent=parent, alive=true, children={} }
    -- Attach before callbacks so failures can be released by the owning session.
    local list = parent and parent.children or session.nodes
    list[#list + 1] = node
    if spec.kind == "card" then
        node.frame = UI:CreateSettingsCard(parentFrame, spec)
        UI:PrepareSettingsListCard(node.frame, {
            preserveHeader=true, externalCollapsible=spec.collapsible == true, collapsed=spec.collapsed,
        })
        node.body = Acquire(node.frame:GetBody())
        node.body:SetPoint("TOPLEFT", PAD, -PAD)
        node.body:SetPoint("TOPRIGHT", -PAD, -PAD)
        if spec.collapsible then
            node.toggleFont = { node.frame._exSettingsCardToggle._exGlyph:GetFont() }
            node.toggleSize = { node.frame._exSettingsCardToggle:GetSize() }
        end
        node.frame:SetLayoutInvalidationHandler(function(card)
            if spec.collapsible then
                card._exSettingsCardToggle._exGlyph:SetText(card._exSettingsCardCollapsed and "+" or "−")
            end
            session:Refresh()
        end)
    else
        node.frame = Acquire(parentFrame)
        node.body = node.frame
    end
    node.context = Context(node)
    if spec.kind == "row" and spec.separator then
        if not node.frame._v2SettingsSeparator then
            node.frame._v2SettingsSeparator = UI:CreateSettingsSeparator(node.frame, 1)
        end
        node.separator = node.frame._v2SettingsSeparator
        node.separator:Show()
    end
    if spec.kind == "control" or spec.kind == "component" then
        local provider = (spec.kind == "control" and session.owner.controls or session.owner.components)[spec.ref]
        node.adapter = spec.kind == "control" and ControlAdapter(provider) or provider
        node.instance = node.adapter.mount(node.frame, node.context, spec)
        Check(node.instance ~= nil, spec.id .. ": mount must return instance")
        -- Keep the owner's original GUI width, not the width assigned by a prior layout.
        node.naturalWidth = node.instance.GetWidth and node.instance:GetWidth() or nil
        if spec.kind == "control" then
            Check(node.instance.GetParent and node.instance:GetParent() == node.frame,
                spec.id .. ": return original control hosted in the supplied GUI host")
            if node.instance.SetPageScroll then node.instance:SetPageScroll() end
            if spec.mode then
                Check(node.instance.mode == spec.mode, spec.id .. ": original choice mode differs")
            end
            if spec.controlType == "pill" then
                Check(node.instance.checkbox ~= nil, spec.id .. ": pill requires existing Checkbox")
                UI:PrepareSettingsListControl(node.instance, { presentation="pill", hideLabel=false })
            end
        end
    elseif spec.kind == "button" then
        node.button = UI:CreateButton(node.frame, spec.width or 100, spec.height or 28, spec.text,
            node.context:Guard(function(_, mouseButton)
                session.owner.actions[spec.action](node.context, mouseButton)
            end), { variant=spec.presentation or "secondary", compact=true })
    elseif spec.kind == "text" or spec.kind == "hint" or spec.kind == "group" then
        if not node.frame._v2Label then
            node.frame._v2Label = UI:CreateVisualFontString(node.frame, _G.EXFONTFRAME, "GameFontHighlight")
        end
        node.label = node.frame._v2Label
        node.label:SetFontObject(spec.kind == "group" and "GameFontNormal" or "GameFontHighlight")
        node.label:SetJustifyH("LEFT")
        node.label:SetJustifyV("TOP")
        node.label:SetWordWrap(true)
        node.label:Show()
        local colors = UI.ControlAppearance.colors
        node.label:SetTextColor(unpack(spec.kind == "hint" and colors.muted or colors.text))
        if spec.kind == "group" then node.label:SetText(spec.title) else Text(node) end
    end
    if spec.kind ~= "repeat" then
        for _, child in ipairs(spec.children or {}) do Build(session, child, node.body, scope, node) end
    end
    return node
end

local function Retire(node)
    node.alive = false
    for _, child in ipairs(node.children) do Retire(child) end
end

ReleaseNode = function(node)
    Retire(node)
    for _, child in ipairs(node.children) do ReleaseNode(child) end
    node.children = {}
    if node.adapter and node.instance ~= nil then
        if node.spec.kind == "control" and node.spec.controlType == "pill" then
            UI:RestoreSettingsListControl(node.instance)
        end
        node.adapter.release(node.instance, node.context)
    end
    if node.button then Factory:Release(node.button._fromPool, node.button) end
    if node.label then node.label:Hide(); node.label:SetText("") end
    if node.frame then
        if node.spec.kind == "card" then
            Factory:ReleaseCompositeHost(node.body)
            if node.toggleFont then
                node.frame._exSettingsCardToggle._exGlyph:SetFont(unpack(node.toggleFont))
                node.frame._exSettingsCardToggle:SetSize(unpack(node.toggleSize))
            end
            UI:RestoreSettingsListCard(node.frame)
            node.frame:Release()
        else Factory:ReleaseCompositeHost(node.frame) end
    end
    node.instance = nil
end

local function SyncRepeat(node)
    local records = Records(node)
    local changed = #records ~= #node.children
    if not changed then
        for i, child in ipairs(node.children) do
            if child.scope.item ~= records[i] then changed = true; break end
        end
    end
    if not changed then return end
    -- No index-based reuse: reset only this repeat region, preserving other nodes.
    for _, child in ipairs(node.children) do Retire(child) end
    for _, child in ipairs(node.children) do ReleaseNode(child) end
    node.children = {}
    for i, record in ipairs(records) do
        local scope = { item=record, index=i, parent=node.scope, _repeatNode=node }
        Build(node.session, node.spec.template, node.body, scope, node)
    end
end

local function Predicate(node, field)
    local ref = node.spec[field]
    if not ref then return true end
    local result = node.session.owner.predicates[ref](node.scope)
    Check(type(result) == "boolean", node.spec.id .. ": predicate must return ordinary boolean")
    return result
end

RefreshNode = function(node, parentVisible, parentEnabled)
    node.visible = parentVisible and Predicate(node, "visible")
    node.enabled = parentEnabled and Predicate(node, "enabled")
    node.managesEnabled = node.spec.enabled ~= nil or (node.parent and node.parent.managesEnabled)
    node.frame:SetShown(node.visible)
    if node.spec.kind == "repeat" then SyncRepeat(node) end
    if node.adapter then
        node.reportedHeight = nil
        node.adapter.update(node.instance, node.context, node.spec)
        if node.managesEnabled then node.adapter.setEnabled(node.instance, node.context, node.enabled) end
        node.adapter.setVisible(node.instance, node.context, node.visible)
    elseif node.button then
        node.button:SetEnabled(node.enabled)
    elseif node.spec.kind == "text" or node.spec.kind == "hint" then Text(node) end
    local childrenVisible = node.visible and not (node.spec.kind == "card" and node.frame._exSettingsCardCollapsed)
    for _, child in ipairs(node.children) do RefreshNode(child, childrenVisible, node.enabled) end
end

local function HideNode(node)
    node.visible = false
    node.frame:Hide()
    if node.adapter then node.adapter.setVisible(node.instance, node.context, false) end
    for _, child in ipairs(node.children) do HideNode(child) end
end

local function Align(value, spare)
    if value == "end" then return math.max(0, spare) end
    if value == "center" then return math.max(0, spare) / 2 end
    return 0
end

local function Natural(node)
    if node.spec.width then return node.spec.width end
    local kind = node.spec.kind
    if kind == "button" then return 100 end
    if kind == "text" or kind == "hint" then
        return math.max(1, node.label:GetUnboundedStringWidth())
    end
    if kind == "control" and (node.spec.controlType == "choice" or node.spec.controlType == "tristate") then
        local widget = node.instance
        if widget.buttons and widget.minItemWidth then
            -- The existing ChoiceGroup uses these label/icon insets and item gap.
            local width, rowWidth, count, maximum = 0, 0, 0, 0
            for _, button in ipairs(widget.buttons) do
                local itemWidth = math.max(widget.minItemWidth,
                    button.label:GetUnboundedStringWidth() + (button._choiceItem.icon and 36 or 20))
                maximum = math.max(maximum, itemWidth)
                if count > 0 then rowWidth = rowWidth + widget.gap end
                rowWidth, count = rowWidth + itemWidth, count + 1
                if widget.columns and count == widget.columns then
                    width, rowWidth, count = math.max(width, rowWidth), 0, 0
                end
            end
            width = math.max(width, rowWidth)
            if widget.sizing ~= "content" then
                count = math.min(#widget.buttons, widget.columns or #widget.buttons)
                width = count * maximum + math.max(0, count - 1) * widget.gap
            end
            return math.max(1, width
                + ((widget.choiceStyle == "segmented" or widget.choiceStyle == "connected") and 4 or 0))
        end
    end
    if node.adapter then return math.max(160, node.naturalWidth or 0) end
    if kind == "columns" then
        local width = 0
        for _, column in ipairs(node.spec.columns) do width = width + (column.width or 160) + GAP end
        return math.max(1, width - GAP)
    end
    if node.spec.children or kind == "repeat" then
        local width, count = 0, 0
        local horizontal = kind == "row" or kind == "actions"
        for _, child in ipairs(node.children) do
            if child.visible then
                local childWidth = Natural(child)
                if horizontal then
                    width = width + childWidth + (count > 0 and GAP or 0)
                else width = math.max(width, childWidth) end
                count = count + 1
            end
        end
        if kind == "group" and node.spec.title ~= "" then
            width = math.max(width, node.label:GetUnboundedStringWidth())
        end
        return math.max(1, width)
    end
    return 160
end

local function Flexible(node)
    if node.spec.width then return false end
    local kind = node.spec.kind
    return node.spec.weight ~= nil or kind == "group" or kind == "row" or kind == "actions"
        or kind == "columns" or kind == "repeat" or kind == "component" or kind == "hint"
        or (kind == "control" and (node.spec.controlType == "choice" or node.spec.controlType == "multiline"))
end

local function Grow(node)
    if node.spec.width then return 0 end
    if node.spec.weight then return node.spec.weight end
    local kind = node.spec.kind
    -- Action regions keep their requested placement; their child containers may grow.
    if kind == "group" or kind == "row" or kind == "columns" or kind == "repeat"
        or kind == "component" or kind == "hint" then return 1 end
    return 0
end

local function Stack(node, width, columns, offset)
    local y, any = offset or 0, false
    local lastRepeatRow
    if node.spec.kind == "repeat" then
        for index, child in ipairs(node.children) do
            if child.visible then lastRepeatRow = index end
        end
    end
    for index, child in ipairs(node.children) do
        if child.visible then
            child.hideTrailingSeparator = index == lastRepeatRow
            if any then y = y + GAP end
            local height = LayoutNode(child, width, columns)
            Place(child.frame, node.body, 0, y, width, height)
            y, any = y + height, true
        end
    end
    return y
end

local function ColumnWidths(specs, width)
    local gap = math.min(GAP, width / (#specs * 2))
    local room = math.max(1, width - gap * (#specs - 1))
    local fixed, weight, flexible = 0, 0, 0
    for _, spec in ipairs(specs) do
        if spec.width then fixed = fixed + spec.width
        else weight = weight + (spec.weight or 1); flexible = flexible + 1 end
    end
    local fixedBudget = room - flexible * math.min(80, room / #specs)
    local scale = fixed > fixedBudget and fixedBudget / fixed or 1
    local widths = { gap=gap }
    for i, spec in ipairs(specs) do
        widths[i] = spec.width and spec.width * scale
            or math.max(1, room - fixed * scale) * (spec.weight or 1) / math.max(1, weight)
    end
    return widths
end

local function Flow(node, width)
    local lines, line, used = {}, {}, 0
    for _, child in ipairs(node.children) do
        if child.visible then
            local wanted = math.min(width, Natural(child))
            if child.spec.kind == "actions" and not child.spec.width then
                wanted = math.min(width, math.max(wanted, width * 0.55))
            end
            local minimum = Flexible(child) and math.min(wanted, 160) or wanted
            if #line > 0 and used + GAP + minimum > width then
                lines[#lines + 1], line, used = line, {}, 0
            end
            if #line > 0 then used = used + GAP end
            line[#line + 1] = { node=child, width=minimum, preferred=wanted }
            used = used + minimum
        end
    end
    if #line > 0 then lines[#lines + 1] = line end
    local y = 0
    for _, entries in ipairs(lines) do
        local occupied, demand, weight, height = GAP * (#entries - 1), 0, 0, 0
        for _, entry in ipairs(entries) do
            occupied = occupied + entry.width
            demand = demand + entry.preferred - entry.width
            weight = weight + Grow(entry.node)
        end
        local available = math.max(0, width - occupied)
        local preferredSpace = math.min(available, demand)
        local extra = available - preferredSpace
        local x = Align(node.spec.align, weight == 0 and extra or 0)
        for _, entry in ipairs(entries) do
            local child = entry.node
            local childWidth = entry.width
                + (demand > 0 and preferredSpace * (entry.preferred - entry.width) / demand or 0)
                + (weight > 0 and extra * Grow(child) / weight or 0)
            -- Position the actions region independently of its internal alignment.
            if child.spec.kind == "actions" and weight == 0 then
                local free = math.max(0, width - x - childWidth)
                x = x + Align(child.spec.position, free)
            end
            entry.x, entry.width = x, childWidth
            entry.height = LayoutNode(child, childWidth)
            height = math.max(height, entry.height)
            x = x + childWidth + GAP
        end
        for _, entry in ipairs(entries) do
            Place(entry.node.frame, node.body, entry.x, y + (height - entry.height) / 2, entry.width, entry.height)
        end
        y = y + height + GAP
    end
    return math.max(0, y - GAP)
end

LayoutNode = function(node, width, columns)
    width = math.max(1, width)
    node.frame:SetWidth(width)
    local kind, height = node.spec.kind, 0
    if node.adapter then
        if node.width ~= width then node.reportedHeight = nil end
        node.width = width
        local measured = node.adapter.measure(node.instance, node.context, width)
        Check(type(measured) == "number" and measured >= 0 and measured < math.huge, node.spec.id .. ": invalid measure")
        height = math.max(node.spec.height or 0, node.reportedHeight or measured)
        node.adapter.layout(node.instance, node.context, width, height)
    elseif node.button then
        height = node.spec.height or 28
        Place(node.button, node.frame, 0, 0, width, height)
    elseif kind == "text" or kind == "hint" then
        node.label:ClearAllPoints()
        node.label:SetPoint("TOPLEFT")
        node.label:SetWidth(width)
        height = math.max(node.spec.height or 0, node.label:GetStringHeight())
    elseif kind == "row" and columns then
        local x, heights = 0, {}
        for i, child in ipairs(node.children) do
            heights[i] = child.visible and LayoutNode(child, columns[i]) or 0
            height = math.max(height, heights[i])
        end
        for i, child in ipairs(node.children) do
            Place(child.frame, node.body, x, (height - heights[i]) / 2, columns[i], heights[i])
            x = x + columns[i] + columns.gap
        end
    elseif kind == "row" or kind == "actions" then
        height = Flow(node, width)
    elseif kind == "card" then
        local innerWidth = math.max(1, width - PAD * 2)
        height = Stack(node, innerWidth)
        node.body:SetHeight(math.max(1, height))
        local card, title = node.frame, node.frame._exSettingsCardTitle
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", card._exSettingsCardHeader, "TOPLEFT", 0, -8)
        title:SetWidth(math.max(1, math.min(title:GetUnboundedStringWidth(),
            width - (node.spec.collapsible and 36 or 0))))
        if node.spec.collapsible then
            local toggle = card._exSettingsCardToggle
            toggle:ClearAllPoints()
            toggle:SetPoint("LEFT", title, "RIGHT", 8, 0)
            toggle:SetSize(28, 28)
            UI.ControlAppearance.ApplyTextRole(toggle._exGlyph, "pageTitle")
            toggle._exGlyph:SetText(card._exSettingsCardCollapsed and "+" or "−")
        end
        local hasHeader = (title:GetText() or "") ~= "" or node.spec.collapsible == true
        local headerHeight = hasHeader and (title:GetStringHeight() + 26) or 0
        card._exSettingsListExternalHeader.height = headerHeight
        card._exSettingsCardHeader:SetShown(hasHeader)
        card._exSettingsCardHeader:SetHeight(math.max(1, headerHeight))
        card:GetBody():ClearAllPoints()
        card:GetBody():SetPoint("TOPLEFT", card, "TOPLEFT", 0, -headerHeight)
        card:GetBody():SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -headerHeight)
        node.frame:SetContentHeight(height + PAD * 2)
        return node.frame:GetPreferredHeight()
    elseif kind == "columns" then
        height = Stack(node, width, ColumnWidths(node.spec.columns, width))
    elseif kind == "group" then
        node.label:ClearAllPoints()
        node.label:SetPoint("TOPLEFT")
        node.label:SetWidth(width)
        local hasTitle = node.spec.title ~= ""
        node.label:SetShown(hasTitle)
        height = Stack(node, width, nil, hasTitle and (node.label:GetStringHeight() + GAP) or 0)
    else
        height = Stack(node, width, columns)
    end
    if node.separator then
        node.separator:SetShown(not node.hideTrailingSeparator)
        if not node.hideTrailingSeparator then
            node.separator:ClearAllPoints()
            node.separator:SetPoint("TOPLEFT", node.frame, "TOPLEFT", 0, -(height + GAP / 2))
            node.separator:SetWidth(width)
            height = height + GAP
        end
    end
    node.frame:SetHeight(math.max(1, height))
    return height
end

function Session:GetHeight() return self.height or 0 end

function Session:Layout()
    if not self.alive or self.layingOut then return end
    self.layingOut = true
    local width, y = math.max(1, self.root:GetWidth() - PAD * 2), PAD
    for _, node in ipairs(self.nodes) do
        if node.visible then
            local height = LayoutNode(node, width)
            Place(node.frame, self.root, PAD, y, width, height)
            y = y + height + GAP
        end
    end
    local height = math.max(PAD * 2, y - GAP + PAD)
    self.root:SetHeight(height)
    self.layingOut = false
    if self.height ~= height then
        self.height = height
        if self.owner.onHeightChanged then self.owner.onHeightChanged(height) end
    end
end

function Session:Invalidate()
    if not self.alive or self.pending then return end
    self.pending = true
    C_Timer.After(0, function()
        if not self.alive then return end
        self.pending = false
        self:Layout()
    end)
end

function Session:Refresh()
    if not self.alive then return end
    for _, node in ipairs(self.nodes) do RefreshNode(node, true, true) end
    self:Invalidate()
end

function Session:Release()
    if not self.alive then return end
    self.alive = false
    self.root:SetScript("OnSizeChanged", nil)
    self.root:SetScript("OnHide", nil)
    self.root:SetScript("OnShow", nil)
    for _, node in ipairs(self.nodes) do Retire(node) end
    for _, node in ipairs(self.nodes) do ReleaseNode(node) end
    self.nodes = {}
    Factory:ReleaseCompositeHost(self.root)
end

function UI:MountSettingsPageV2(parent, pageId, owner)
    local declaration = Pages[pageId]
    Check(declaration ~= nil, "unregistered page " .. tostring(pageId))
    Check(parent and parent.GetWidth and type(owner) == "table", "parent and owner required")
    Check(owner.onHeightChanged == nil or type(owner.onHeightChanged) == "function", "invalid height handler")
    declaration = DeclarationCopy(declaration, {})
    Validate(declaration, owner)
    local session = setmetatable({ alive=true, owner=owner, nodes={} }, { __index=Session })
    session.root = Acquire(parent)
    session.root:SetPoint("TOPLEFT")
    session.root:SetPoint("TOPRIGHT")
    session.root:SetScript("OnSizeChanged", function(_, width)
        if session.width ~= width then session.width = width; session:Invalidate() end
    end)
    -- Hiding a page closes transient controls; the owner must still Release on departure.
    session.root:SetScript("OnHide", function()
        if not session.alive then return end
        for _, node in ipairs(session.nodes) do HideNode(node) end
    end)
    session.root:SetScript("OnShow", function() session:Refresh() end)
    local ok, failure = pcall(function()
        for _, spec in ipairs(declaration.cards) do Build(session, spec, session.root) end
        session:Refresh()
        session:Layout()
    end)
    if not ok then
        -- Do not leave a partially mounted page alive or suppress the original error.
        local released, releaseFailure = pcall(function() session:Release() end)
        error(tostring(failure) .. (released and "" or "\nRelease: " .. tostring(releaseFailure)), 0)
    end
    return session
end
