-- =========================================================
-- ExwindGUIComposite.lua: 组合设置组、固定复合宿主及对应测量/释放。
-- 复用 ExwindGUI 的同一 UI/外观表；不创建新的配置或对象池系统。
-- 定位: 私有组合支撑 -> Font/Sound -> Preview/Item -> Glow/Icon/TimerBar ->
-- WidgetLayout/ModuleCommon -> Aura/Anchor/Texture -> Grid 测量登记。
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local L = ExwindTools.L
local MODERN = EXUI.ControlAppearance
local MC = MODERN.colors
local Internal = EXUI._GUIInternal
local StyleModernTitle = Internal.StyleModernTitle
local SetDropdownDisplayText = Internal.SetDropdownDisplayText
local AcquireCompositeGroup = Internal.AcquireCompositeGroup
local IsModuleCommonOrdinaryField = Internal.IsModuleCommonOrdinaryField

-- 组合组只用列间竖线区分字段；线锚定原有容器，重排时不移动控件。
local function CreateCompositeColumnDivider(parent, topFrame, bottomFrame, side, offset)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(ExwindTools.GUIColors.sectionDivider))
    line:SetWidth(1)
    line:SetPoint("TOP", topFrame, side == "LEFT" and "TOPLEFT" or "TOPRIGHT", offset, 0)
    line:SetPoint("BOTTOM", bottomFrame, side == "LEFT" and "BOTTOMLEFT" or "BOTTOMRIGHT", offset, 0)
    return line
end

-- =========================================================
-- 组合组内部支撑：原路径访问、绑定、弹层、刷新与释放。
-- =========================================================
-- 组合控件的子控件会常驻在宿主下面。代理把读写转发到“本次借用”的数据表，
-- 这样复用后的 Slider / Dropdown / ColorButton 不会继续引用上一条规则。
local function CompositePathValue(db, path)
    if path == nil or path == "" then return db end
    local value = db
    for part in string.gmatch(path, "[^%.]+") do
        value = type(value) == "table" and value[part] or nil
    end
    return value
end

local function CompositePathSet(db, path, value)
    if type(db) ~= "table" or type(path) ~= "string" or path == "" then return false end
    local target, last = db, nil
    for part in string.gmatch(path, "[^%.]+") do
        if last then
            target[last] = type(target[last]) == "table" and target[last] or {}
            target = target[last]
        end
        last = part
    end
    if not last then return false end
    target[last] = value
    return true
end

local function CreateCompositeProxy(host, path)
    return setmetatable({}, {
        __index = function(_, field)
            local target = CompositePathValue(host._exCompositeDb, path)
            return type(target) == "table" and target[field] or nil
        end,
        __newindex = function(_, field, value)
            local target = CompositePathValue(host._exCompositeDb, path)
            if type(target) == "table" then target[field] = value end
        end,
    })
end

-- 右侧弹出面板不能作为 ScrollChild 的子对象：即使设为高层也会被滚动区域裁切。
-- 统一挂在 UIParent 的 DIALOG 层。内部 Dropdown 的列表由 Blizzard_Menu 自动创建在
-- FULLSCREEN_DIALOG，层级天然高于弹窗本身，避免同 TOOLTIP 层互相遮挡。
-- CompositeFontGroup / IconGroup / TimerBarGroup 都从这里取得弹层；层级恢复
-- 必须是这一处的统一职责，不能由各组的右侧按钮各自补丁。
local function RaiseCompositePopupHost(popup)
    if not popup then return end
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(math.max(1000, (UIParent:GetFrameLevel() or 1) + 1000))
    if popup.SetToplevel then popup:SetToplevel(true) end
    -- 同 strata 的浮层会随着点击顺序而重叠；空白区点击也必须把当前 popup
    -- 放回最前，不能让它落到设置主框或另一张已存在 popup 后面。
    if popup.Raise then popup:Raise() end
end

local function CreateCompositePopupHost(owner, width, height)
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    if EXUI.SetControlAppearance then
        EXUI:SetControlAppearance(popup, EXUI:GetControlAppearance(owner))
    end
    popup:SetSize(width, height)
    -- 主面板和它的 ModalLayer 同样在 DIALOG；弹窗必须明显高于二者，
    -- 而其下拉列表再由 FULLSCREEN_DIALOG 覆盖。
    RaiseCompositePopupHost(popup)
    popup:HookScript("OnShow", function(self)
        RaiseCompositePopupHost(self)
        EXUI:ApplyModernPanel(self, true)
    end)
    popup:HookScript("OnMouseDown", RaiseCompositePopupHost)
    popup._exPopupOwner = owner
    return popup
end

-- Composite 控件除自身字段外，允许以纯数据声明“同一 DB、同一次 commit”必须
-- 一并写入的字段。它不是回调、也不保存模块函数；标准 Slider binder 只消费
-- 这份公开元数据，因而接管生命周期后不会丢失控件固有语义。
local function ValidateCompositeCommitWritesMetadata(metadata)
    if metadata == nil then return nil end
    if type(metadata) ~= "table" then
        error("composite control metadata must be table", 3)
    end
    for key in pairs(metadata) do
        if key ~= "commitWrites" then
            error("composite control metadata only supports commitWrites", 3)
        end
    end
    if type(metadata.commitWrites) ~= "table" or #metadata.commitWrites == 0 then
        error("composite control commitWrites must be a non-empty array", 3)
    end
    for index, write in ipairs(metadata.commitWrites) do
        if type(write) ~= "table" or type(write.path) ~= "string" or write.path == "" then
            error("composite control commitWrites entry requires path", 3)
        end
        for key in pairs(write) do
            if key ~= "path" and key ~= "value" then
                error("composite control commitWrites entry only supports path/value", 3)
            end
        end
        local valueType = type(write.value)
        if valueType ~= "boolean" and valueType ~= "number" and valueType ~= "string" then
            error("composite control commitWrites value must be scalar: " .. tostring(index), 3)
        end
    end
    return metadata.commitWrites
end

local function RegisterCompositeControl(host, control, path, kind, metadata)
    if not control then return control end
    local commitWrites = ValidateCompositeCommitWritesMetadata(metadata)
    host._exCompositeControls = host._exCompositeControls or {}
    host._exCompositeControls[#host._exCompositeControls + 1] = {
        control = control, path = path, kind = kind,
        -- 仅允许声明式 commitWrites；禁止把私有 callback 塞进控件 metadata。
        commitWrites = commitWrites,
    }
    return control
end

local function CompositeDropdownText(value, items)
    for _, item in ipairs(items or {}) do
        if type(item) == "table" then
            if item.isMenu then
                local text = CompositeDropdownText(value, item.menu)
                if text then return text end
            elseif item[2] == value or tostring(item[2]) == tostring(value) then
                return item[1]
            end
        elseif item == value or tostring(item) == tostring(value) then
            return item
        end
    end
    return nil
end

local function RefreshCompositeControl(entry, db)
    local control, value = entry.control, CompositePathValue(db, entry.path)
    if not control then return end
    if entry.kind == "color" then
        -- 颜色按钮保存的是嵌套目标表引用。组合组从对象池复用时，必须像其它
        -- 控件一样重绑到本轮 DB；仅 UpdateColor 会继续写入上一次页面的表。
        local colorDB, colorKey = db, entry.path
        local parentPath, directKey = tostring(entry.path or ""):match("^(.*)%.([^%.]+)$")
        if parentPath and directKey then
            for part in string.gmatch(parentPath, "[^%.]+") do
                colorDB = type(colorDB) == "table" and colorDB[part] or nil
            end
            colorKey = directKey
        end
        if type(colorDB) == "table" then
            control._currentDb = colorDB
            control._currentKey = colorKey
        end
        if control.UpdateColor then control:UpdateColor() end
    elseif entry.kind == "check" then
        if control.SetChecked then control:SetChecked(value == true) end
    elseif entry.kind == "slider" then
        local callback = control._onValueChanged
        control._onValueChanged = nil
        if control.Init and control._exCompositeMin ~= nil then
            control:Init(tonumber(value) or control._exCompositeMin, control._exCompositeMin,
                control._exCompositeMax, control._exCompositeSteps)
        elseif control.SetValue then
            control:SetValue(tonumber(value) or 0)
        end
        control._onValueChanged = callback
        if control.ValueText and control._formatter then
            control.ValueText:SetText(control._formatter(tonumber(value) or 0))
        end
    elseif entry.kind == "dropdown" then
        if control._mediaType then
            control._selectedValue = value
            SetDropdownDisplayText(control, value or L["请选择..."])
        else
            control._currentValue = value
            SetDropdownDisplayText(control, CompositeDropdownText(value, control._items) or L["请选择..."])
        end
    elseif entry.kind == "edit" then
        if control.SetText then control:SetText(tostring(value or "")) end
    end
end

local function BindCompositeGroup(host, db, onUpdate, opts)
    host._exCompositeDb = db
    host._exCompositeOnUpdate = onUpdate
    host._exCompositeOpts = opts or {}
    for _, entry in ipairs(host._exCompositeControls or {}) do
        RefreshCompositeControl(entry, db)
    end
    if host._exCompositeTitle and host._exCompositeLabel then
        host._exCompositeTitle:SetText(host._exCompositeLabel)
    end
    if type(host._exCompositeHeaderRefresh) == "function" then
        host:_exCompositeHeaderRefresh()
    end
    if type(host._exCompositeConfigure) == "function" then
        host:_exCompositeConfigure()
    end
end

-- Composite Host 会被 FramePool 交给不同宽度的 Grid 项目复用。仅 SetSize 会让
-- 内部卡片保留上一次借用时的绝对坐标/宽度，因此把“宿主尺寸 + 内部重排”收口。
-- 这里不保存视觉状态，也不触发配置回调；每一种 Composite 在创建时登记自己的
-- 窄布局函数，复用时只按当前实际宽高重新锚定已有控件。
-- Layout cached skins even when SetSize does not fire OnSizeChanged (same-size
-- pool reuse, or a different parent scale). Keep colors, alpha and active state;
-- this pass must not create a new panel or revive an explicitly cleared skin.
function EXUI:RefreshCompositeSurfaces(host)
    local visited = {}
    local function Refresh(frame)
        if not frame or visited[frame] then return end
        visited[frame] = true
        for _, skin in pairs(frame._exModernSurfaces or {}) do
            if type(skin.Layout) == "function" then skin.Layout() end
        end
        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do Refresh(child) end
        end
        for _, popup in ipairs(frame._exCompositePopups or {}) do Refresh(popup) end
    end
    Refresh(host)
end

function EXUI:LayoutCompositeGroup(host, width, height)
    host:SetSize(width, height)
    if type(host._exCompositeReflow) == "function" then
        host:_exCompositeReflow(width, height)
    end
    self:RefreshCompositeSurfaces(host)
end

-- Older preview/item shells explicitly use a panel. Settings groups call the
-- public geometry-only entry above so reuse cannot add a different background.
local function ReflowCompositeGroup(host, width, height)
    EXUI:LayoutCompositeGroup(host, width, height)
    if EXUI.ApplyModernPanel then EXUI:ApplyModernPanel(host) end
end

-- 预览拖动会由模块直接写回同一份 ModuleDB；当前可见 Grid 不能等到重开页面
-- 才重新绑定。组合控件统一从自己已绑定的 DB 回读，避免每个模块分别触碰
-- Slider / Dropdown / Checkbox 私有实现，也不引入第二张预览配置表。
function EXUI:RefreshCompositeGroupFromDB(host)
    if type(host) ~= "table" or type(host._exCompositeDb) ~= "table" then return false end
    BindCompositeGroup(host, host._exCompositeDb, host._exCompositeOnUpdate, host._exCompositeOpts)
    return true
end

local function AttachCompositeRelease(host)
    local factory = _G.ExwindFactory
    -- FramePool 在每次 Release 后都会清空 frame._exPoolRelease；因此组合宿主
    -- 每次 Acquire/重绑都必须重新登记本轮清理，不能用永久 attached 标记跳过。
    if not factory or not factory.AttachPoolRelease then return end
    factory:AttachPoolRelease(host, function(frame)
        if frame._exCancelItemIdentityLoad then frame:_exCancelItemIdentityLoad() end
        for _, popup in ipairs(frame._exCompositePopups or {}) do popup:Hide() end
        -- modulecommonsettings 的字段由模块动态声明；宿主归池时必须先归还
        -- 本轮借用的标准子控件，不能把上一模块的字段树带进下一模块。
        if frame._exClearModuleCommonEntries then
            frame:_exClearModuleCommonEntries()
        end
        frame._exCompositeDb = nil
        frame._exCompositeOnUpdate = nil
        frame._exCompositeOpts = nil
        frame._moduleCommonDb = nil
        frame._soundGroupKey = nil
        frame._soundState = nil
        frame._itemIdentityID = nil
        frame._itemIdentityCompletedID = nil
        frame._previewCallbacks = nil
        frame._previewData = nil
    end)
end

local function CompositeEmitUpdate(host)
    if host._exCompositeOnUpdate then host._exCompositeOnUpdate(host._exCompositeDb) end
end

-- =========================================================
-- 字体设置组：CreateFontGroup。
-- =========================================================
local function ResolveFontGroupHeight(width)
    return (tonumber(width) or 750) < 720 and 420 or 204
end

function EXUI:CreateFontGroup(parent, width, label, db, onUpdate, opts)
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    local offsetMin = tonumber(opts.offsetMin) or -200
    local offsetMax = tonumber(opts.offsetMax) or 200
    local shadowOffsetMin = tonumber(opts.shadowOffsetMin) or -20
    local shadowOffsetMax = tonumber(opts.shadowOffsetMax) or 20

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local defaultFont = (LSM and LSM.GetDefault and LSM:GetDefault("font")) or "Friz Quadrata TT"
    local defaults = {
        enabled = true,
        font = defaultFont,
        size = 14,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        x = 0, y = 0,
        shadow = false,
        shadowX = 1, shadowY = -1,
        shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1,
        autoWidth = false,
        maxWidth = 0,
        fixedWidth = 200,
        justifyH = "LEFT", justifyV = "MIDDLE",
        gradientEnabled = false,
        gradientStart = 0, gradientLength = 0,
        -- drawLayer / drawSubLevel 是旧存档导入兼容字段：不再补默认值、
        -- 不再暴露设置控件，所有 FontString 统一由 EXFONTFRAME 接管。
        rotation = 0,
    }
    for field, value in pairs(defaults) do
        if db[field] == nil then db[field] = value end
    end
    local groupWidth = width or 750
    local narrowLayout = groupWidth < 720
    -- 窄卡把右侧功能区移到字段下方，避免半宽 SettingsCard 产生负 Slider 宽度。
    local groupHeight = ResolveFontGroupHeight(groupWidth)
    -- 与 IconGroup 共用同一组层级；两种复合控件只保留内容差异。
    local palette = {
        panel = MC.panel,
        card = MC.raised,
        utility = MC.raised,
        border = MC.border,
        borderSoft = MC.border,
        text = MC.text,
        value = MC.blue,
        accent = MC.blue,
    }
    local group, isNew = AcquireCompositeGroup("CompositeFontGroup", parent)
    group._exCompositeLabel = label or L["文字设置"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        if group._exSetUnboundedWidthControls then group:_exSetUnboundedWidthControls(opts) end
        AttachCompositeRelease(group)
        -- FontGroup owns its internal surfaces; the generic reuse helper adds
        -- an outer panel that a freshly constructed FontGroup does not have.
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy

    local function EmitUpdate() CompositeEmitUpdate(group) end

    -- FontGroup 控件写入同一份 ModuleDB 后仅经统一通知重套既有表面。
    local function GetFontInputMetadata()
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateFontGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateFontGroup Grid write context requires pathPrefix", 2)
        end
        local commitAPI = EXUI.CommitModuleValue
        if type(commitAPI) ~= "function" then
            error("CreateFontGroup requires its Core commit API", 2)
        end
        return metadata.moduleKey, prefix
    end
    local function CommitFontValue(field, value, onWrite)
        local moduleKey, prefix = GetFontInputMetadata()
        local function Write(nextValue)
            db[field] = nextValue
            if onWrite then onWrite(nextValue) end
        end
        if moduleKey then
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. field,
                readValue = function() return db[field] end, writeValue = Write,
            }
            return EXUI:CommitModuleValue(payload, value)
        end
        Write(value)
        EmitUpdate()
        return true
    end
    local function CreateFontColorTransaction(colorKey)
        local fields = colorKey == "shadowColor"
            and { "shadowColorR", "shadowColorG", "shadowColorB", "shadowColorA" }
            or { "r", "g", "b", "a" }
        return function()
            -- ColorButton 是池化对象；必须在每次打开色盘时读取本次页面的合同，
            -- 不能把首次创建它的模块 key / path 闭包带到后续页面。
            local moduleKey, prefix = GetFontInputMetadata()
            if not moduleKey then return nil end
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. colorKey,
                readValue = function()
                    return { r = db[fields[1]], g = db[fields[2]], b = db[fields[3]], a = db[fields[4]] }
                end,
                writeValue = function(value)
                    db[fields[1]], db[fields[2]], db[fields[3]], db[fields[4]] = value.r, value.g, value.b, value.a
                end,
            }
            return EXUI:CreateModuleNotifyFlow(payload)
        end
    end
    local function SetFontValue(field, value, phase, onWrite)
        db[field] = value
        if onWrite then onWrite(value) end
        if phase ~= "live" then EmitUpdate() end
    end

    -- 旧 RegisterModuleLayout 的 FontGroup 可以声明 registry 生命周期。每次按下
    -- 都从当前 pooled group 的 opts 取合同，避免把上一个模块的 moduleKey/path
    -- 闭包带到本页面；拖动只写真实 DB 并 patch 已挂载 Panel，commit 才正式刷新。
    local function CreateFontPreviewLifecycle(field, onWrite)
        local activeOpts = group._exCompositeOpts or {}
        local transaction = activeOpts._exWriteContext
        if transaction ~= nil then
            if type(transaction) ~= "table" or type(transaction.moduleKey) ~= "string" or transaction.moduleKey == "" then
                error("CreateFontGroup requires Grid write context", 2)
            end
            local prefix = transaction.pathPrefix or transaction.path
            if type(prefix) ~= "string" or prefix == "" then
                error("CreateFontGroup Grid write context requires pathPrefix", 2)
            end
            local createAPI = EXUI.CreateModuleNotifyFlow
            if type(createAPI) ~= "function" then
                error("CreateFontGroup requires its Core transaction API", 2)
            end
            local function Write(value)
                db[field] = value
                if onWrite then onWrite(value) end
            end
            local payload = {
                moduleKey = transaction.moduleKey,
                path = prefix .. "." .. field,
                readValue = function() return db[field] end,
                writeValue = Write,
            }
            return createAPI(EXUI, payload)
        end
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateFontGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateFontGroup Grid write context requires pathPrefix", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateFontGroup requires CreateModuleNotifyFlow", 2)
        end
        local function Write(value)
            db[field] = value
            if onWrite then onWrite(value) end
        end
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = prefix .. "." .. field,
            readValue = function() return db[field] end,
            writeValue = Write,
            commit = function(value)
                Write(value)
                EmitUpdate()
            end,
        })
    end

    local function CreateFontSlider(host, sliderWidth, titleText, field, minValue, maxValue, value, stepValue, onWrite)
        local lifecycle
        local slider = self:CreateSlider(host, sliderWidth, titleText, minValue, maxValue, value, stepValue, nil, {
            onBegin = function()
                lifecycle = CreateFontPreviewLifecycle(field, onWrite)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(v)
                if lifecycle and lifecycle.onLive then lifecycle.onLive(v) else SetFontValue(field, v, "live", onWrite) end
            end,
            onCommit = function(v)
                -- 输入框不会触发原生轨道的 OnMouseDown；标准模块仍必须在这里
                -- 输入框同样读取当前 Grid 写入上下文。
                local inputOpts = group._exCompositeOpts or {}
                if not lifecycle and inputOpts._exWriteContext ~= nil then
                    lifecycle = CreateFontPreviewLifecycle(field, onWrite)
                end
                if lifecycle and lifecycle.onCommit then
                    lifecycle.onCommit(v)
                    lifecycle = nil
                else
                    SetFontValue(field, v, "commit", onWrite)
                end
            end,
        })
        return slider
    end
    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local content = CreateFrame("Frame", nil, group)
    content:SetSize(groupWidth, groupHeight)
    content:SetPoint("TOPLEFT", 0, 0)

    local padding, gap, controlsGap = 15, 12, 18
    local controlWidth = narrowLayout and (groupWidth - padding * 2)
        or math.min(416, math.max(364, math.floor(groupWidth * 0.40)))
    local metricsWidth = narrowLayout and (groupWidth - padding * 2)
        or (groupWidth - padding * 2 - controlsGap - controlWidth)
    local itemWidth = math.floor((metricsWidth - gap) / 2)
    local col1, col2 = padding, padding + itemWidth + gap
    -- 下拉框包含“标题 + 选择框”两层内容；卡片统一加高，
    -- 让三列卡片与右侧功能区的上下边界完整对齐。
    local row1, row2, row3 = -8, -76, -144
    local metricCardHeight = 60
    local controlX = narrowLayout and padding or (padding + metricsWidth + controlsGap)

    local sectionHeight = math.abs(row3 - row1) + metricCardHeight
    local controlY = narrowLayout and (row3 - metricCardHeight - gap) or row1

    local function CreateMetricCard(x, y)
        local card = CreateFrame("Frame", nil, content)
        card:SetPoint("TOPLEFT", x, y)
        card:SetSize(itemWidth, metricCardHeight)
        return card
    end

    -- 三行两列：颜色/大小、字体/X、描边/Y。
    local colorCard = CreateMetricCard(col1, row1)
    local sizeCard = CreateMetricCard(col2, row1)
    local fontCard = CreateMetricCard(col1, row2)
    local xCard = CreateMetricCard(col2, row2)
    local outlineCard = CreateMetricCard(col1, row3)
    local yCard = CreateMetricCard(col2, row3)
    group._exFontGroupMetricCards = { colorCard, sizeCard, fontCard, xCard, outlineCard, yCard }
    local sliderWidth = itemWidth - 20

    -- 字体、颜色和描边属于日常选项，直接展示在主面板，不再藏进弹窗。
    local colorBtn = self:CreateColorButton(colorCard, L["文字颜色"], db, "", true, EmitUpdate,
        { _changeFlow = CreateFontColorTransaction("color") })
    colorBtn:SetPoint("TOPLEFT", 10, -8)

    local fontDrop = self:CreateLSMDropdown(fontCard, "font", sliderWidth, L["字体样式"], db.font, function(key)
        CommitFontValue("font", key)
    end)
    -- 下拉框的标签绘制在本体上方；下移本体以让标签留在同一张 52px 卡片内。
    fontDrop:SetPoint("TOPLEFT", 10, -26)

    local outlineItems = { { L["无"], "" }, { L["细"], "OUTLINE" }, { L["粗"], "THICKOUTLINE" }, { L["无锯齿"], "MONOCHROME" } }
    local outlineDrop = self:CreateDropdown(outlineCard, sliderWidth, L["文字描边"], outlineItems, db.outline, function(v)
        CommitFontValue("outline", v)
    end)
    outlineDrop:SetPoint("TOPLEFT", 10, -26)

    local sizeSlider = CreateFontSlider(sizeCard, sliderWidth, L["文字大小"], "size", 4, 100, db.size, 1)
    sizeSlider:SetPoint("TOPLEFT", 10, -8)

    local xSlider = CreateFontSlider(xCard, sliderWidth, L["X 轴偏移"], "x", offsetMin, offsetMax, db.x, 1)
    xSlider:SetPoint("TOPLEFT", 10, -8)

    local ySlider = CreateFontSlider(yCard, sliderWidth, L["Y 轴偏移"], "y", offsetMin, offsetMax, db.y, 1)
    ySlider:SetPoint("TOPLEFT", 10, -8)

    -- 右侧功能区沿用 IconGroup 的 utility 卡片。
    local controlCard = CreateFrame("Frame", nil, content)
    controlCard:SetPoint("TOPLEFT", controlX, controlY)
    controlCard:SetSize(controlWidth, sectionHeight)
    group._exFontGroupActionCard = controlCard
    CreateCompositeColumnDivider(content, colorCard, outlineCard, "RIGHT", gap / 2)
    local actionDivider = CreateCompositeColumnDivider(content, controlCard, controlCard, "LEFT", -controlsGap / 2)
    actionDivider:SetShown(not narrowLayout)

    local showText = self:CreateCheckbox(controlCard, L["显示文字"], db.enabled, function(v)
        CommitFontValue("enabled", v)
    end)
    showText:SetPoint("TOPLEFT", 12, -4)
    showText:SetSize(156, 28)

    local shadowCheck = self:CreateCheckbox(controlCard, L["启用阴影"], db.shadow, function(v)
        CommitFontValue("shadow", v)
    end)
    shadowCheck:SetPoint("TOPLEFT", 12, -45)
    shadowCheck:SetSize(156, 28)

    local alignmentWidth = math.min(156, math.floor(controlWidth * 0.45))
    local justifyHItems = { { L["左对齐"], "LEFT" }, { L["居中"], "CENTER" }, { L["右对齐"], "RIGHT" } }
    local justifyH = self:CreateDropdown(controlCard, alignmentWidth, L["水平对齐"], justifyHItems, db.justifyH, function(v)
        CommitFontValue("justifyH", v)
    end)
    justifyH:SetPoint("TOPLEFT", 12, -94)

    local justifyVItems = { { L["顶部"], "TOP" }, { L["居中"], "MIDDLE" }, { L["底部"], "BOTTOM" } }
    local justifyV = self:CreateDropdown(controlCard, alignmentWidth, L["垂直对齐"], justifyVItems, db.justifyV, function(v)
        CommitFontValue("justifyV", v)
    end)
    justifyV:SetPoint("TOPLEFT", 12, -162)

    local gradientCheck = self:CreateCheckbox(controlCard, L["启用文字渐隐"], db.gradientEnabled, function(v)
        CommitFontValue("gradientEnabled", v)
    end)
    gradientCheck:SetPoint("TOPLEFT", 12, -127)
    gradientCheck:SetSize(176, 28)
    -- 当前文字 Region 没有可靠的跨版本渐隐/旋转实现；不把未消费字段暴露给用户。
    gradientCheck:Hide()

    local function CreatePopup(titleText, popupWidth, popupHeight)
        local popup = CreateCompositePopupHost(group, popupWidth, popupHeight)
        EXUI:SetControlSurface(popup, 10, palette.panel, palette.border)
        popup:Hide()
        local popupTitle = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontHighlight")
        popupTitle:SetPoint("TOPLEFT", 13, -9)
        popupTitle:SetText(titleText)
        StyleModernTitle(popupTitle)
        local close = self:CreateButton(popup, 28, 24, "×", function() popup:Hide() end, { compact = true })
        close:SetPoint("TOPRIGHT", -7, -4)
        return popup
    end

    local popupScale = 1.3
    local popupWidth = math.floor(400 * popupScale)
    local shadowPopup = CreatePopup(L["阴影设置"], popupWidth, 140)
    local layoutPopup = CreatePopup(L["布局设置"], popupWidth, 156)
    local advancedPopup = CreatePopup(L["高级文字设置"], popupWidth, 210)
    local popupPad, popupGap = 14, 18
    local popupItemW = math.floor((popupWidth - popupPad * 2 - popupGap) / 2)
    local popupCol2 = popupPad + popupItemW + popupGap

    local shadowColor = self:CreateColorButton(shadowPopup, L["阴影颜色"], db, "shadowColor", true, EmitUpdate,
        { _changeFlow = CreateFontColorTransaction("shadowColor") })
    shadowColor:SetPoint("TOPLEFT", popupPad, -46)
    local shadowX = CreateFontSlider(shadowPopup, popupItemW, L["阴影 X 偏移"], "shadowX", shadowOffsetMin, shadowOffsetMax, db.shadowX, 0.1)
    shadowX:SetPoint("TOPLEFT", popupCol2, -42)
    local shadowY = CreateFontSlider(shadowPopup, popupItemW, L["阴影 Y 偏移"], "shadowY", shadowOffsetMin, shadowOffsetMax, db.shadowY, 0.1)
    shadowY:SetPoint("TOPLEFT", popupCol2, -95)

    local autoWidthCheck
    local fixedWidth = CreateFontSlider(layoutPopup, popupItemW, L["固定宽度"], "fixedWidth", 0, 1000, db.fixedWidth, 1, function()
        -- 用户调整固定宽度即明确选择固定宽度模式；数值 0 的语义是“按文字自身宽度”。
        -- 不自动关掉该模式会让滑条看似没有作用。
        db.autoWidth = false
        if autoWidthCheck.SetChecked then autoWidthCheck:SetChecked(false) end
    end)
    fixedWidth:SetPoint("TOPLEFT", popupPad, -42)
    local maxWidth = CreateFontSlider(layoutPopup, popupItemW, L["最大宽度 (0=不限)"], "maxWidth", 0, 1000, db.maxWidth, 1)
    maxWidth:SetPoint("TOPLEFT", popupCol2, -42)
    autoWidthCheck = self:CreateCheckbox(layoutPopup, L["自动宽度"], db.autoWidth, function(v)
        CommitFontValue("autoWidth", v)
    end)
    autoWidthCheck:SetPoint("TOPLEFT", popupPad, -96)
    autoWidthCheck:SetSize(156, 28)

    local gradientStart = CreateFontSlider(advancedPopup, popupItemW, L["渐隐起点"], "gradientStart", 0, 1000, db.gradientStart, 1)
    gradientStart:SetPoint("TOPLEFT", popupPad, -42)
    local gradientLength = CreateFontSlider(advancedPopup, popupItemW, L["渐隐长度"], "gradientLength", 0, 1000, db.gradientLength, 1)
    gradientLength:SetPoint("TOPLEFT", popupCol2, -42)
    local rotation = CreateFontSlider(advancedPopup, popupItemW, L["文字旋转"], "rotation", -180, 180, db.rotation, 1)
    rotation:SetPoint("TOPLEFT", popupPad, -150)

    local function TogglePopup(popup, anchor)
        local shouldShow = not popup:IsShown()
        shadowPopup:Hide()
        layoutPopup:Hide()
        advancedPopup:Hide()
        if shouldShow then
            popup:ClearAllPoints()
            popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
            popup:Show()
        end
    end
    local function CreateUtilityButton(text, buttonWidth, onClick)
        return EXUI:CreateButton(controlCard, buttonWidth, 28, text, onClick, { variant = "soft" })
    end

    local buttonWidth = math.min(187, math.floor(controlWidth * 0.45))
    local shadowButton = CreateUtilityButton(L["阴影设置"], buttonWidth, function(self) TogglePopup(shadowPopup, self) end)
    shadowButton:SetPoint("TOPRIGHT", controlCard, "TOPRIGHT", -10, -4)
    local layoutButton = CreateUtilityButton(L["布局设置"], buttonWidth, function(self) TogglePopup(layoutPopup, self) end)
    layoutButton:SetPoint("TOPRIGHT", controlCard, "TOPRIGHT", -10, -45)
    local advancedButton = CreateUtilityButton(L["高级设置"], buttonWidth, function(self) TogglePopup(advancedPopup, self) end)
    advancedButton:SetPoint("TOPRIGHT", controlCard, "TOPRIGHT", -10, -86)

    -- 单行公告等明确声明为无界文本的模块不能暴露会制造宽度限制的控件。
    -- 该组会被对象池复用，因而每次绑定都必须显式恢复/隐藏，不能把上一个
    -- 无界模块的可见性残留给普通文字模块。
    group._exFontAutoWidthCheck = autoWidthCheck
    group._exFontLayoutButton = layoutButton
    group._exSetUnboundedWidthControls = function(self, activeOpts)
        local unbounded = type(activeOpts) == "table" and activeOpts.unboundedWidth == true
        if self._exFontAutoWidthCheck then self._exFontAutoWidthCheck:SetShown(not unbounded) end
        if self._exFontLayoutButton then self._exFontLayoutButton:SetShown(not unbounded) end
    end
    group:_exSetUnboundedWidthControls(opts)

    group:HookScript("OnHide", function()
        shadowPopup:Hide()
        layoutPopup:Hide()
        advancedPopup:Hide()
    end)
    RegisterCompositeControl(group, colorBtn, "", "color")
    RegisterCompositeControl(group, fontDrop, "font", "dropdown")
    RegisterCompositeControl(group, outlineDrop, "outline", "dropdown")
    RegisterCompositeControl(group, sizeSlider, "size", "slider")
    RegisterCompositeControl(group, xSlider, "x", "slider")
    RegisterCompositeControl(group, ySlider, "y", "slider")
    RegisterCompositeControl(group, showText, "enabled", "check")
    RegisterCompositeControl(group, shadowCheck, "shadow", "check")
    RegisterCompositeControl(group, autoWidthCheck, "autoWidth", "check")
    RegisterCompositeControl(group, gradientCheck, "gradientEnabled", "check")
    RegisterCompositeControl(group, shadowColor, "shadowColor", "color")
    RegisterCompositeControl(group, shadowX, "shadowX", "slider")
    RegisterCompositeControl(group, shadowY, "shadowY", "slider")
    -- 固定宽度是 FontGroup 的公开控件语义：调整它必定切出自动宽度模式。
    -- 旧页面仍由上面的 Slider callback 保持此行为；标准生命周期接管时则
    -- 读取这份声明式 metadata，在同一 DB、同一次 commit 写入 autoWidth=false。
    RegisterCompositeControl(group, fixedWidth, "fixedWidth", "slider", {
        commitWrites = {
            { path = "autoWidth", value = false },
        },
    })
    RegisterCompositeControl(group, maxWidth, "maxWidth", "slider")
    RegisterCompositeControl(group, justifyH, "justifyH", "dropdown")
    RegisterCompositeControl(group, justifyV, "justifyV", "dropdown")
    RegisterCompositeControl(group, gradientStart, "gradientStart", "slider")
    RegisterCompositeControl(group, gradientLength, "gradientLength", "slider")
    RegisterCompositeControl(group, rotation, "rotation", "slider")
    group._exCompositePopups = { shadowPopup, layoutPopup, advancedPopup }

    group._fontGroupDb = proxy
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local nextNarrow = nextWidth < 720
        nextHeight = ResolveFontGroupHeight(nextWidth)
        local nextControlWidth = nextNarrow and (nextWidth - padding * 2)
            or math.min(416, math.max(364, math.floor(nextWidth * 0.40)))
        local nextMetricsWidth = nextNarrow and (nextWidth - padding * 2)
            or (nextWidth - padding * 2 - controlsGap - nextControlWidth)
        local nextItemWidth = math.floor((nextMetricsWidth - gap) / 2)
        local nextCol2 = padding + nextItemWidth + gap
        local nextControlX = nextNarrow and padding or (padding + nextMetricsWidth + controlsGap)
        local nextControlY = nextNarrow and (row3 - metricCardHeight - gap) or row1
        local nextSliderWidth = nextItemWidth - 20

        self:SetSize(nextWidth, nextHeight)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, nextHeight)
        EXUI:ClearControlSurface(self)
        for _, card in ipairs({ colorCard, fontCard, outlineCard }) do card:SetSize(nextItemWidth, metricCardHeight) end
        for _, card in ipairs({ sizeCard, xCard, yCard }) do card:SetSize(nextItemWidth, metricCardHeight) end
        colorCard:ClearAllPoints(); colorCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row1)
        sizeCard:ClearAllPoints(); sizeCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row1)
        fontCard:ClearAllPoints(); fontCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row2)
        xCard:ClearAllPoints(); xCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row2)
        outlineCard:ClearAllPoints(); outlineCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row3)
        yCard:ClearAllPoints(); yCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row3)
        for _, slider in ipairs({ sizeSlider, xSlider, ySlider }) do slider:SetWidth(nextSliderWidth) end
        fontDrop:SetWidth(nextSliderWidth); outlineDrop:SetWidth(nextSliderWidth)
        colorBtn:SetWidth(nextSliderWidth)
        controlCard:ClearAllPoints(); controlCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextControlX, nextControlY)
        controlCard:SetSize(nextControlWidth, math.abs(row3 - row1) + metricCardHeight)
        actionDivider:SetShown(not nextNarrow)
        local nextButtonWidth = math.min(187, math.floor(nextControlWidth * 0.45))
        local nextAlignmentWidth = math.min(156, math.floor(nextControlWidth * 0.45))
        justifyH:SetWidth(nextAlignmentWidth); justifyV:SetWidth(nextAlignmentWidth)
        shadowButton:SetWidth(nextButtonWidth); layoutButton:SetWidth(nextButtonWidth); advancedButton:SetWidth(nextButtonWidth)
        for _, card in ipairs(self._exFontGroupMetricCards) do
            EXUI:ClearControlSurface(card)
        end
        EXUI:ClearControlSurface(controlCard)
        for _, popup in ipairs(self._exCompositePopups or {}) do
            EXUI:SetControlSurface(popup, 10, palette.panel, palette.border)
        end
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    -- 预览画布拖动会直接写入 db；提供统一回刷入口，让下方 X/Y 滑杆
    -- 立即同步，而不是下一次手动调整时从旧值跳回去。
    group.RefreshFromDB = function(self)
        BindCompositeGroup(self, self._exCompositeDb, self._exCompositeOnUpdate, self._exCompositeOpts)
    end
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 12. 音效设置复合组件 (Sound Settings Group)
-- 扁平前缀字段：<key>Enabled/Source/Label/LSM/Path/TtsText/Channel。
-- 来源集合由调用方 opts.sources 声明；未声明时绝不开放语音包。
-- =========================================================
local function ResolveSoundGroupSecondaryCheckbox(opts)
    local spec = type(opts) == "table" and opts.secondaryCheckbox or nil
    if spec == nil then return nil end
    if type(spec) ~= "table" then
        error("soundgroup secondaryCheckbox must be table", 3)
    end
    for field in pairs(spec) do
        if field ~= "key" and field ~= "label" then
            error("soundgroup secondaryCheckbox only supports key/label", 3)
        end
    end
    if type(spec.key) ~= "string" or spec.key == "" then
        error("soundgroup secondaryCheckbox requires non-empty key", 3)
    end
    if type(spec.label) ~= "string" or spec.label == "" then
        error("soundgroup secondaryCheckbox requires non-empty label", 3)
    end
    return spec
end

-- SoundGroup 的测量和控件重排必须共用同一份纯布局结果。额外复选框由组件
-- 自己占据第二行，因而能与“启用”使用完全相同的父级和水平内边距；未声明
-- secondaryCheckbox 的现有调用者仍保持无额外行时的 64/140 高度。
function EXUI:BuildSoundGroupLayout(width, opts)
    local groupWidth = math.max(1, tonumber(width) or 750)
    local secondaryCheckbox = ResolveSoundGroupSecondaryCheckbox(opts)
    local extraHeight = secondaryCheckbox and 56 or 0
    if groupWidth >= 760 then
        return {
            height = 64 + extraHeight,
            isWide = true,
            secondaryCheckbox = secondaryCheckbox,
            enabledY = -4,
            secondaryY = -60,
            sourceY = -4,
            channelY = -4,
            testY = -4,
        }
    end
    return {
        height = 140 + extraHeight,
        isWide = false,
        secondaryCheckbox = secondaryCheckbox,
        enabledY = -8,
        secondaryY = -45,
        sourceY = -45 - extraHeight,
        channelY = -101 - extraHeight,
        testY = -104 - extraHeight,
    }
end

function EXUI:CreateSoundGroup(parent, width, label, db, key, onUpdate, opts)
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    key = tostring(key or "sound")

    local function HasUsablePackItems(items)
        if type(items) ~= "table" then return false end
        for _, item in ipairs(items) do
            if type(item) == "string" and item ~= "" then return true end
            if type(item) == "table" and item[1] ~= nil and item[2] ~= nil then return true end
        end
        return false
    end
    local function ResolveInitialPackItems()
        local packItems = opts.packItems
        if type(packItems) == "function" then
            local ok, result = pcall(packItems, db, key)
            packItems = ok and result or nil
        end
        return packItems
    end

    local allowed = {}
    local sources = {}
    local requestedSources = type(opts.sources) == "table" and opts.sources or { "lsm", "file", "tts" }
    local packAvailable = HasUsablePackItems(ResolveInitialPackItems())
    for _, source in ipairs(requestedSources) do
        if source == "pack" and not packAvailable then
            -- pack 没有本轮可用条目时不能成为可选来源，更不能被选为默认值。
        elseif (source == "pack" or source == "lsm" or source == "file" or source == "tts") and not allowed[source] then
            allowed[source] = true
            sources[#sources + 1] = source
        end
    end
    if #sources == 0 then
        sources = { "lsm", "file", "tts" }
        allowed = { lsm = true, file = true, tts = true }
    end

    local sourceItems = {
        pack = { L["语音包"], "pack" },
        lsm = { L["LSM音效"], "lsm" },
        file = { L["自定义路径"], "file" },
        tts = { L["TTS语音"], "tts" },
    }
    local dropdownSources = {}
    local defaultSource
    for _, source in ipairs(sources) do
        dropdownSources[#dropdownSources + 1] = sourceItems[source]
        if not defaultSource and source ~= "pack" then defaultSource = source end
    end
    defaultSource = defaultSource or sources[1]

    local group
    local suffix = {
        enabled = "Enabled", source = "Source", label = "Label", lsm = "LSM",
        path = "Path", tts = "TtsText", channel = "Channel",
    }
    local function Field(name) return ((group and group._soundGroupKey) or key) .. suffix[name] end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local defaultLSM = (LSM and LSM.GetDefault and LSM:GetDefault("sound")) or "None"
    local defaults = {
        enabled = false, source = defaultSource, label = "", lsm = defaultLSM,
        path = "", tts = "", channel = "Master",
    }
    for name, value in pairs(defaults) do
        local field = Field(name)
        if db[field] == nil then db[field] = value end
    end
    if not allowed[db[Field("source")]] then db[Field("source")] = defaultSource end

    -- 宽版标准页面统一使用一行：启用 / 来源 / 当前音效 / 输出 / 试听。
    -- 窄宿主仍保留两列，以免控件相互覆盖。
    local groupWidth = width or 750
    local soundLayout = self:BuildSoundGroupLayout(groupWidth, opts)
    local groupHeight = soundLayout.height
    local isNew
    group, isNew = AcquireCompositeGroup("CompositeSoundGroup", parent)
    group._exCompositeLabel = label or L["音效设置"]
    group._soundGroupKey = key
    group._soundState = {
        allowed = allowed, defaultSource = defaultSource, dropdownSources = dropdownSources,
        requestedSources = requestedSources,
    }
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        group:_exCompositeConfigure()
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        EXUI:ClearControlSurface(group)
        return group
    end

    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local content = CreateFrame("Frame", nil, group)
    content:SetPoint("TOPLEFT", 0, 0)
    local settingsCard = CreateFrame("Frame", nil, content)

    local function ActiveDB() return type(group._exCompositeDb) == "table" and group._exCompositeDb or nil end
    local function SetValue(name, value)
        local active = ActiveDB()
        if active then active[Field(name)] = value end
    end
    local function GetValue(name)
        local active = ActiveDB()
        return active and active[Field(name)] or defaults[name]
    end
    local function EmitUpdate() CompositeEmitUpdate(group) end

    local enabled = self:CreateCheckbox(settingsCard, L["启用"], GetValue("enabled"), function(value)
        SetValue("enabled", value); EmitUpdate()
    end)
    local secondaryCheckbox = self:CreateCheckbox(settingsCard, "", false, function(value)
        local activeOpts = group._exCompositeOpts or {}
        local spec = ResolveSoundGroupSecondaryCheckbox(activeOpts)
        local active = ActiveDB()
        if spec and active and CompositePathSet(active, spec.key, value) then
            EmitUpdate()
        end
    end)
    local sourceDrop = self:CreateDropdown(settingsCard, 200, L["音效来源"], dropdownSources, GetValue("source"), function(value)
        SetValue("source", value)
        group:_exCompositeConfigure()
        EmitUpdate()
    end)
    local packDrop = self:CreateDropdown(settingsCard, 200, L["语音包标签"], {}, GetValue("label"), function(value)
        SetValue("label", value); EmitUpdate()
    end)
    local lsmDrop = self:CreateLSMSoundDropdown(settingsCard, 200, L["选择音效 (LSM)"], GetValue("lsm"), function(value)
        SetValue("lsm", value); EmitUpdate()
    end)
    lsmDrop._mediaType = "sound"
    local pathInput = self:CreateEditBox(settingsCard, GetValue("path"), 200, 28, L["自定义路径"], {
        placeholder = L["示例: Interface\\AddOns\\MySound\\test.ogg"],
        onEnter = function(value) SetValue("path", value); EmitUpdate() end,
        onEditFocusLost = function(value) SetValue("path", value); EmitUpdate() end,
    })
    local ttsInput = self:CreateEditBox(settingsCard, GetValue("tts"), 200, 28, L["TTS文本"], {
        placeholder = L["输入要朗读的文字"],
        onEnter = function(value) SetValue("tts", value); EmitUpdate() end,
        onEditFocusLost = function(value) SetValue("tts", value); EmitUpdate() end,
    })
    local channels = {
        { L["主音量 (Master)"], "Master" }, { L["音效 (SFX)"], "SFX" },
        { L["环境 (Ambience)"], "Ambience" }, { L["音乐 (Music)"], "Music" },
        { L["对话 (Dialog)"], "Dialog" },
    }
    local channelDrop = self:CreateDropdown(settingsCard, 200, L["音频通道"], channels, GetValue("channel"), function(value)
        SetValue("channel", value); EmitUpdate()
    end)
    local testButton = self:CreateButton(settingsCard, 110, 28, "", function()
        local activeOpts = group._exCompositeOpts or {}
        if type(activeOpts.onTest) == "function" then
            activeOpts.onTest(group._exCompositeDb, group._soundGroupKey)
            return
        end
        -- Module declarations are pure data, so Grid soundgroup cannot carry a
        -- callback.  An explicit testButtonKey reuses the established module
        -- click-state contract; the module still owns the actual playback.
        local clickKey = activeOpts.testButtonKey
        local writeContext = activeOpts._exWriteContext
        if type(clickKey) == "string" and clickKey ~= ""
            and type(writeContext) == "table" and type(writeContext.moduleKey) == "string"
            and writeContext.moduleKey ~= "" then
            ExwindTools:UpdateState(writeContext.moduleKey .. ".ButtonClicked", {
                key = clickKey,
                fullPath = writeContext.pathPrefix,
                ts = GetTime(),
            })
        end
    end)
    local playIcon = testButton:CreateTexture(nil, "ARTWORK")
    playIcon:SetAtlas("charactercreate-customize-playbutton")
    playIcon:SetSize(20, 20)
    playIcon:SetPoint("CENTER")

    enabled._soundField = "enabled"
    sourceDrop._soundField = "source"
    packDrop._soundField = "label"
    lsmDrop._soundField = "lsm"
    pathInput._soundField = "path"
    ttsInput._soundField = "tts"
    channelDrop._soundField = "channel"
    RegisterCompositeControl(group, enabled, Field("enabled"), "check")
    RegisterCompositeControl(group, sourceDrop, Field("source"), "dropdown")
    RegisterCompositeControl(group, packDrop, Field("label"), "dropdown")
    RegisterCompositeControl(group, lsmDrop, Field("lsm"), "dropdown")
    RegisterCompositeControl(group, pathInput, Field("path"), "edit")
    RegisterCompositeControl(group, ttsInput, Field("tts"), "edit")
    RegisterCompositeControl(group, channelDrop, Field("channel"), "dropdown")

    local function ResolvePackItems()
        local activeOpts = group._exCompositeOpts or {}
        local packItems = activeOpts.packItems
        if type(packItems) == "function" then
            local ok, result = pcall(packItems, group._exCompositeDb, group._soundGroupKey)
            packItems = ok and result or nil
        end
        return type(packItems) == "table" and packItems or {}
    end
    local function RebuildSourceState(state, packItems)
        local nextAllowed, nextItems, nextDefault = {}, {}, nil
        for _, candidate in ipairs(state.requestedSources or {}) do
            if candidate == "pack" and not HasUsablePackItems(packItems) then
                -- 动态 provider 本轮为空时，pack 必须从来源菜单消失。
            elseif (candidate == "pack" or candidate == "lsm" or candidate == "file" or candidate == "tts") and not nextAllowed[candidate] then
                nextAllowed[candidate] = true
                nextItems[#nextItems + 1] = sourceItems[candidate]
                if not nextDefault and candidate ~= "pack" then nextDefault = candidate end
            end
        end
        if #nextItems == 0 then
            nextAllowed = { lsm = true, file = true, tts = true }
            nextItems = { sourceItems.lsm, sourceItems.file, sourceItems.tts }
            nextDefault = "lsm"
        end
        state.allowed, state.dropdownSources, state.defaultSource = nextAllowed, nextItems, nextDefault or nextItems[1][2]
    end
    group._exCompositeConfigure = function(self)
        local state = self._soundState or {}
        local activeOpts = self._exCompositeOpts or {}
        local secondarySpec = ResolveSoundGroupSecondaryCheckbox(activeOpts)
        if testButton.SetText then testButton:SetText("") end
        secondaryCheckbox:SetShown(secondarySpec ~= nil)
        if secondarySpec then
            secondaryCheckbox.label:SetText(secondarySpec.label)
            secondaryCheckbox:SetChecked(CompositePathValue(self._exCompositeDb, secondarySpec.key) == true)
        end
        -- 同一 CompositeHost 可被不同 key/来源集合的页面复用；先将每个已建立
        -- 控件的扁平字段映射重绑到本轮 key，再刷新显示，不能沿用上一页路径。
        for _, entry in ipairs(self._exCompositeControls or {}) do
            local fieldName = entry.control and entry.control._soundField
            if fieldName then
                entry.path = Field(fieldName)
                RefreshCompositeControl(entry, self._exCompositeDb)
            end
        end
        local packItems = ResolvePackItems()
        RebuildSourceState(state, packItems)
        local source = GetValue("source")
        if not state.allowed or not state.allowed[source] then
            source = state.defaultSource
            SetValue("source", source)
        end
        sourceDrop._items = state.dropdownSources or {}
        sourceDrop._currentValue = source
        SetDropdownDisplayText(sourceDrop, CompositeDropdownText(source, sourceDrop._items) or L["请选择..."])
        packDrop._items = packItems
        packDrop._currentValue = GetValue("label")
        SetDropdownDisplayText(packDrop, CompositeDropdownText(packDrop._currentValue, packItems) or L["请选择..."])
        if #packItems > 0 then
            if packDrop.Enable then packDrop:Enable() end
        elseif packDrop.Disable then
            packDrop:Disable()
        end
        if packDrop.EnableMouse then packDrop:EnableMouse(#packItems > 0) end
        packDrop:SetShown(source == "pack")
        lsmDrop:SetShown(source == "lsm")
        pathInput:SetShown(source == "file")
        ttsInput:SetShown(source == "tts")
    end
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local layout = EXUI:BuildSoundGroupLayout(nextWidth, self._exCompositeOpts)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, math.max(1, nextHeight))
        EXUI:ClearControlSurface(self)
        if layout.isWide then
            -- 对应在线编辑器的标准比例：20 / 35 / 62 / 30 / 25。
            -- 当前音效位只会显示 LSM、路径或 TTS 三者之一。
            local padding = 15
            local scale = math.max(1, (nextWidth - padding * 2) / 193)
            local checkWidth = math.floor(20 * scale)
            local sourceWidth = math.floor(35 * scale)
            local soundWidth = math.floor(62 * scale)
            local channelWidth = math.floor(30 * scale)
            local testWidth = math.floor(25 * scale)
            local sourceX = padding + 24 * scale
            local soundX = padding + 62 * scale
            local channelX = padding + 128 * scale
            local testX = padding + 168 * scale
            settingsCard:ClearAllPoints(); settingsCard:SetPoint("TOPLEFT", content, "TOPLEFT")
            settingsCard:SetSize(nextWidth, math.max(1, nextHeight))

            enabled:ClearAllPoints(); enabled:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", padding, layout.enabledY); enabled:SetWidth(checkWidth)
            secondaryCheckbox:ClearAllPoints(); secondaryCheckbox:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", padding, layout.secondaryY); secondaryCheckbox:SetWidth(checkWidth)
            sourceDrop:ClearAllPoints(); sourceDrop:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", sourceX, layout.sourceY); sourceDrop:SetWidth(sourceWidth)
            for _, control in ipairs({ packDrop, lsmDrop, pathInput, ttsInput }) do
                control:ClearAllPoints(); control:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", soundX, layout.sourceY); control:SetWidth(soundWidth)
            end
            channelDrop:ClearAllPoints(); channelDrop:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", channelX, layout.channelY); channelDrop:SetWidth(channelWidth)
            testButton:ClearAllPoints(); testButton:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", testX, layout.testY); testButton:SetWidth(testWidth)
            return
        end

        local padding, gap = 15, 18
        local itemWidth = math.max(140, math.floor((nextWidth - padding * 2 - gap) / 2))
        local col1, col2 = padding, padding + itemWidth + gap
        settingsCard:ClearAllPoints(); settingsCard:SetPoint("TOPLEFT", content, "TOPLEFT", padding, -8)
        settingsCard:SetSize(nextWidth - padding * 2,
            math.max(1, nextHeight - 16))
        enabled:ClearAllPoints(); enabled:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", 10, layout.enabledY)
        secondaryCheckbox:ClearAllPoints(); secondaryCheckbox:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", 10, layout.secondaryY)
        sourceDrop:ClearAllPoints(); sourceDrop:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", col1, layout.sourceY); sourceDrop:SetWidth(itemWidth)
        for _, control in ipairs({ packDrop, lsmDrop, pathInput, ttsInput }) do
            control:ClearAllPoints(); control:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", col2, layout.sourceY); control:SetWidth(itemWidth)
        end
        channelDrop:ClearAllPoints(); channelDrop:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", col1, layout.channelY); channelDrop:SetWidth(itemWidth)
        testButton:ClearAllPoints(); testButton:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", col2, layout.testY)
    end
    group:_exCompositeConfigure()
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 14. 交互式预览画板 (Interactive Preview Canvas)
-- =========================================================
function EXUI:CreatePreviewCanvas(parent, width, height, elementsData, callbacks)
    local canvas, isNew = AcquireCompositeGroup("CompositePreviewCanvas", parent)
    canvas._previewCallbacks = callbacks or {}
    canvas._previewData = elementsData or {}
    canvas:SetSize(width, height)
    if not isNew then
        canvas.selectedKey = nil
        canvas:UpdateElements(canvas._previewData)
        ReflowCompositeGroup(canvas, width, height)
        AttachCompositeRelease(canvas)
        return canvas
    end

    -- 画板背景 (网格或深色背景)
    canvas:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tileSize = 16,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    EXUI:ApplyModernPanel(canvas, true)

    -- 网格参考线 (辅助对齐)
    local gridLine = EXUI:CreateVisualTexture(canvas, EXBACKGROUNDFRAME)
    gridLine:SetAllPoints()
    gridLine:SetColorTexture(1, 1, 1, 0.05)

    local centerLineH = EXUI:CreateVisualTexture(canvas, EXBASEFRAME)
    centerLineH:SetHeight(1)
    centerLineH:SetPoint("LEFT"); centerLineH:SetPoint("RIGHT")
    centerLineH:SetPoint("CENTER")
    centerLineH:SetColorTexture(1, 1, 1, 0.2)

    local centerLineV = EXUI:CreateVisualTexture(canvas, EXBASEFRAME)
    centerLineV:SetWidth(1)
    centerLineV:SetPoint("TOP"); centerLineV:SetPoint("BOTTOM")
    centerLineV:SetPoint("CENTER")
    centerLineV:SetColorTexture(1, 1, 1, 0.2)

    canvas.elements = {}
    canvas.selectedKey = nil

    -- 内部方法：创建/更新子元素
    function canvas:UpdateElements(dataMap)
        -- 1. 隐藏所有旧元素
        for _, el in pairs(self.elements) do el:Hide() end

        -- 2. 遍历数据创建/显示元素
        for key, data in pairs(dataMap) do
            if data.enabled then
                local el = self.elements[key]
                if not el then
                    local elementKey = key
                    el = CreateFrame("Button", nil, self, "BackdropTemplate")
                    el:SetSize(100, 24) -- 默认基准大小
                    el:SetBackdrop(nil)

                    el.text = EXUI:CreateVisualFontString(el, EXFONTFRAME, "GameFontHighlightSmall")
                    el.text:SetPoint("CENTER")

                    -- 拖拽逻辑
                    el:SetMovable(true)
                    el:RegisterForDrag("LeftButton")
                    el:SetScript("OnDragStart", function(s)
                        if self.selectedKey ~= elementKey then self:Select(elementKey) end
                        s:StartMoving()
                    end)
                    el:SetScript("OnDragStop", function(s)
                        s:StopMovingOrSizing()
                        local cx, cy = self:GetCenter()
                        local ex, ey = s:GetCenter()

                        if not cx or not ex then return end

                        -- 计算相对坐标 (相对于 Canvas 中心)
                        local relX = ex - cx
                        local relY = ey - cy

                        -- 吸附逻辑 (简单取整)
                        relX = math.floor(relX + 0.5)
                        relY = math.floor(relY + 0.5)

                        s:ClearAllPoints()
                        s:SetPoint("CENTER", self, "CENTER", relX, relY)

                        local activeCallbacks = self._previewCallbacks
                        if activeCallbacks and activeCallbacks.onMove then
                            activeCallbacks.onMove(elementKey, relX, relY)
                        end
                    end)

                    -- 点击选择
                    el:SetScript("OnClick", function() self:Select(elementKey) end)

                    self.elements[key] = el
                end

                -- 更新样式与位置
                el:Show()
                el.text:SetText(data.label or key)
                el:ClearAllPoints()
                el:SetPoint("CENTER", self, "CENTER", data.x or 0, data.y or 0)

                -- 根据是否选中设置外观
                if self.selectedKey == key then
                    EXUI:SetControlSurface(el, 4, MC.blueSoft, MC.focus)
                    el.text:SetTextColor(unpack(MC.lightBlue))
                else
                    EXUI:SetControlSurface(el, 4, MC.input, MC.border)
                    el.text:SetTextColor(unpack(MC.text))
                end
            end
        end
    end

    function canvas:Select(key)
        self.selectedKey = key
        -- 刷新外观
        for k, el in pairs(self.elements) do
            if k == key then
                EXUI:SetControlSurface(el, 4, MC.blueSoft, MC.focus)
                el.text:SetTextColor(unpack(MC.lightBlue))
            else
                EXUI:SetControlSurface(el, 4, MC.input, MC.border)
                el.text:SetTextColor(unpack(MC.text))
            end
        end
        local activeCallbacks = self._previewCallbacks
        if activeCallbacks and activeCallbacks.onSelect then activeCallbacks.onSelect(key) end
    end

    function canvas:ClearSelection()
        self:Select(nil)
    end

    canvas:UpdateElements(canvas._previewData)
    canvas._exCompositeReflow = function(self, nextWidth, nextHeight) self:SetSize(nextWidth, nextHeight) end
    ReflowCompositeGroup(canvas, width, height)
    AttachCompositeRelease(canvas)
    return canvas
end

-- =========================================================
-- 16. 只读物品身份 (Item Identity)
-- 仅显示现有 itemID 的图标、名称与 tooltip；不持有配置、不接收拖放、
-- 不创建默认值，也不发出任何状态或数据通知。
-- =========================================================
local ITEM_IDENTITY_PENDING = {}
local ItemIdentityLoader

local function StopItemIdentityLoaderIfIdle()
    if ItemIdentityLoader and next(ITEM_IDENTITY_PENDING) == nil then
        ItemIdentityLoader:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end

local function CancelItemIdentityLoad(container)
    local id = container._itemIdentityPendingID
    local waiters = id and ITEM_IDENTITY_PENDING[id]
    if waiters then
        waiters[container] = nil
        if next(waiters) == nil then ITEM_IDENTITY_PENDING[id] = nil end
    end
    container._itemIdentityPendingID = nil
    container._itemIdentityLoadTicket = nil
    StopItemIdentityLoaderIfIdle()
end

local function EnsureItemIdentityLoader()
    if ItemIdentityLoader then return ItemIdentityLoader end
    local loader = CreateFrame("Frame")
    loader:SetScript("OnEvent", function(_, _, itemID, success)
        itemID = tonumber(itemID)
        local waiters = itemID and ITEM_IDENTITY_PENDING[itemID]
        if not waiters then return end
        ITEM_IDENTITY_PENDING[itemID] = nil
        for container, ticket in pairs(waiters) do
            if container._itemIdentityPendingID == itemID
                and container._itemIdentityLoadTicket == ticket
                and container._itemIdentityID == itemID then
                container._itemIdentityPendingID = nil
                container._itemIdentityLoadTicket = nil
                if success then
                    -- The event is the single completion opportunity for this
                    -- lease. If the cache still has no record, show a stable
                    -- fallback instead of opening another request loop.
                    container:_exUpdateItemIdentity(true)
                else
                    container:_exSetItemIdentityUnavailable()
                end
            end
        end
        StopItemIdentityLoaderIfIdle()
    end)
    ItemIdentityLoader = loader
    return loader
end

local function RequestItemIdentityLoad(container, itemID)
    CancelItemIdentityLoad(container)
    local waiters = ITEM_IDENTITY_PENDING[itemID]
    local firstRequest = waiters == nil
    if firstRequest then
        waiters = setmetatable({}, { __mode = "k" })
        ITEM_IDENTITY_PENDING[itemID] = waiters
    end
    local ticket = {}
    container._itemIdentityPendingID = itemID
    container._itemIdentityLoadTicket = ticket
    waiters[container] = ticket
    EnsureItemIdentityLoader():RegisterEvent("GET_ITEM_INFO_RECEIVED")
    if firstRequest then C_Item.RequestLoadItemDataByID(itemID) end
end

function EXUI:CreateItemIdentity(parent, width, height, itemID)
    local w, h = width or 320, height or 40
    local container, isNew = AcquireCompositeGroup("CompositeItemIdentity", parent)
    local nextItemID = tonumber(itemID) or 0
    if container._itemIdentityID ~= nextItemID then
        container._itemIdentityCompletedID = nil
    end
    container._itemIdentityID = nextItemID

    if isNew then
        local iconButton = CreateFrame("Button", nil, container)
        iconButton:EnableMouse(true)
        local icon = EXUI:CreateVisualTexture(iconButton, EXBASEFRAME)
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        container.iconButton, container.icon = iconButton, icon

        local name = EXUI:CreateVisualFontString(container, EXFONTFRAME, "GameFontHighlightSmall")
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        container.nameText = name

        local function ShowTooltip(owner)
            local id = container._itemIdentityID
            if id and id > 0 then
                GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(id)
                GameTooltip:Show()
            end
        end
        local function HideTooltip() GameTooltip:Hide() end
        container._exItemIdentityShowTooltip = ShowTooltip
        container._exItemIdentityHideTooltip = HideTooltip
        container._exCancelItemIdentityLoad = CancelItemIdentityLoad

        function container:_exSetItemIdentityUnavailable()
            self._itemIdentityCompletedID = self._itemIdentityID
            self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            self.nameText:SetText(string.format("ID %d", self._itemIdentityID or 0))
            self.nameText:SetTextColor(unpack(MC.muted))
        end

        function container:_exUpdateItemIdentity(loadCompleted)
            local id = self._itemIdentityID
            if self._itemIdentityPendingID and self._itemIdentityPendingID ~= id then
                CancelItemIdentityLoad(self)
            end
            if not id or id == 0 then
                CancelItemIdentityLoad(self)
                self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                self.nameText:SetText("")
                self.nameText:SetTextColor(unpack(MC.muted))
                return
            end
            local itemName, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(id)
            if itemName then
                CancelItemIdentityLoad(self)
                self._itemIdentityCompletedID = nil
                self.icon:SetTexture(texture)
                self.nameText:SetText(itemName)
                local r, g, b = C_Item.GetItemQualityColor(quality or 1)
                self.nameText:SetTextColor(r, g, b, 1)
            else
                if loadCompleted or self._itemIdentityCompletedID == id then
                    self:_exSetItemIdentityUnavailable()
                    return
                end
                self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                self.nameText:SetText(L["数据加载中..."])
                self.nameText:SetTextColor(unpack(MC.muted))
                -- RefreshValues may re-read this cell while the same request is
                -- pending. Keep its lease ticket instead of restarting I/O.
                if self._itemIdentityPendingID ~= id or not self._itemIdentityLoadTicket then
                    RequestItemIdentityLoad(self, id)
                end
            end
        end

        container._exCompositeReflow = function(self, nextWidth, nextHeight)
            local iconSize = math.max(24, math.min(32, nextHeight - 8))
            self.iconButton:ClearAllPoints()
            self.iconButton:SetPoint("LEFT", self, "LEFT", 0, 0)
            self.iconButton:SetSize(iconSize, iconSize)
            self.nameText:ClearAllPoints()
            self.nameText:SetPoint("LEFT", self.iconButton, "RIGHT", 8, 0)
            self.nameText:SetPoint("RIGHT", self, "RIGHT", 0, 0)
        end
    end

    -- StandardReset clears scripts on the pooled host. Rebind the read-only
    -- tooltip on every lease; neither region accepts clicks or drag payloads.
    container:EnableMouse(true)
    container:SetScript("OnEnter", container._exItemIdentityShowTooltip)
    container:SetScript("OnLeave", container._exItemIdentityHideTooltip)
    container:SetScript("OnReceiveDrag", nil)
    container.iconButton:SetScript("OnEnter", container._exItemIdentityShowTooltip)
    container.iconButton:SetScript("OnLeave", container._exItemIdentityHideTooltip)
    container.iconButton:SetScript("OnClick", nil)
    container:_exUpdateItemIdentity()
    ReflowCompositeGroup(container, w, h)
    -- ReflowCompositeGroup reapplies the generic panel surface. Item identity
    -- is a read-only icon/name cell, so clear that host outline afterwards;
    -- the table row and all interactive controls keep their own surfaces.
    EXUI:ClearControlSurface(container)
    AttachCompositeRelease(container)
    return container
end

-- =========================================================
-- 12. Glow 设置复合组件 (Glow Settings Group)
-- =========================================================
function EXUI:CreateGlowSettings(parent, width, label, db, key, onUpdate)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local groupWidth = width or 750
    local groupHeight = 240

    container:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(container)

    -- 内容容器
    local content = CreateFrame("Frame", nil, container)
    content:SetSize(groupWidth, groupHeight)
    content:SetPoint("TOPLEFT", 0, 0)

    -- 布局坐标
    local col1, col2, col3 = 15, 275, 535
    local row1, row2, row3 = -25, -95, -165
    local itemW = 225

    local enableKey = key .. "Enabled"
    if db[enableKey] == nil then db[enableKey] = true end

    local cb = EXUI:CreateCheckbox(content, L["启用发光"], db[enableKey], function(checked)
        db[enableKey] = checked
        if onUpdate then onUpdate() end
    end)
    -- 注意：CreateCheckbox 返回一个容器，不是简单的 Button
    cb:SetPoint("TOPLEFT", col1, row1 - 5)


    -- 1. 样式选择 (Style Dropdown)
    local styleKey = key .. "Style"
    local styles = {
        { L["标准 (Classic)"], "Action Button Glow" },
        { L["像素 (Pixel)"], "Pixel Glow" },
        { L["自动施法 (AutoCast)"], "Autocast Shine" },
        { L["新版触发 (Proc)"], "Proc Glow" },
    }

    local styleDropdown = EXUI:CreateDropdown(content, itemW, L["样式类型"], styles, db[styleKey] or "Action Button Glow",
        function(val)
            db[styleKey] = val
            container:RefreshLayout()
            if onUpdate then onUpdate() end
        end)
    styleDropdown:SetPoint("TOPLEFT", col2, row1 - 10)

    -- 2. 颜色选择
    local colorBtn = EXUI:CreateColorButton(content, L["发光颜色"], db, key .. "Color", true, function()
        if onUpdate then onUpdate() end
    end)
    -- Color button matches generic button height
    colorBtn:SetPoint("TOPLEFT", col3, row1 - 10)

    -- 3. Sliders
    local sliders = {}
    local function CreateGlowSlider(sLabel, sKey, min, max, step, def)
        local itemKey = key .. sKey
        local s = EXUI:CreateSlider(content, itemW, sLabel, min, max, db[itemKey] or def, step, nil, function(v)
            db[itemKey] = v
            if onUpdate then onUpdate() end
        end)
        return s
    end

    sliders.Frequency = CreateGlowSlider(L["频率 (Frequency)"], "Frequency", 0.1, 5, 0.1, 0.25)
    sliders.Lines = CreateGlowSlider(L["线条 (Lines)"], "Lines", 1, 30, 1, 8)
    sliders.Scale = CreateGlowSlider(L["大小/粗细 (Scale)"], "Scale", 0.5, 3, 0.1, 1)
    sliders.Offset = CreateGlowSlider(L["边距 (Offset)"], "Offset", -50, 50, 1, 0)
    if db[key .. "Offset"] == nil then db[key .. "Offset"] = 0 end

    container.Sliders = sliders

    function container:RefreshLayout()
        local style = db[styleKey] or "Action Button Glow"

        if style == "Proc Glow" then colorBtn:Hide() else colorBtn:Show() end

        for _, s in pairs(sliders) do s:Hide() end

        -- Row 2 placement
        if style == "Action Button Glow" then
            sliders.Frequency:Show(); sliders.Frequency.Title:SetText(L["闪烁速度"]); sliders.Frequency:SetPoint("TOPLEFT", col1,
                row2)
        elseif style == "Pixel Glow" then
            sliders.Frequency:Show(); sliders.Frequency.Title:SetText(L["流动速度"]); sliders.Frequency:SetPoint("TOPLEFT", col1,
                row2)
            sliders.Lines:Show(); sliders.Lines.Title:SetText(L["线条数量"]); sliders.Lines:SetPoint("TOPLEFT", col2, row2)
            sliders.Scale:Show(); sliders.Scale.Title:SetText(L["线条粗细"]); sliders.Scale:SetPoint("TOPLEFT", col3, row2)
        elseif style == "Autocast Shine" then
            sliders.Frequency:Show(); sliders.Frequency.Title:SetText(L["闪烁速度"]); sliders.Frequency:SetPoint("TOPLEFT", col1,
                row2)
            sliders.Lines:Show(); sliders.Lines.Title:SetText(L["粒子数量"]); sliders.Lines:SetPoint("TOPLEFT", col2, row2)
            sliders.Scale:Show(); sliders.Scale.Title:SetText(L["粒子大小"]); sliders.Scale:SetPoint("TOPLEFT", col3, row2)
        end

        -- Row 3 placement (Offset)
        if style ~= "Proc Glow" then
            sliders.Offset:Show(); sliders.Offset:SetPoint("TOPLEFT", col1, row3)
        end
    end

    container:RefreshLayout()
    container._exGridOwnedControls = {
        cb, styleDropdown, colorBtn,
        sliders.Frequency, sliders.Lines, sliders.Scale, sliders.Offset,
    }
    EXUI:ClearControlSurface(container)
    return container
end

-- =========================================================
-- 17. 图标设置组 (Icon Settings Group)
-- =========================================================
function EXUI:CreateIconGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    local groupWidth = width or 750
    local narrowLayout = groupWidth < 720
    -- 窄卡把功能区移到 2x2 字段下方；宽卡继续保持原来的左右结构。
    local groupHeight = narrowLayout and 296 or 150

    -- [关键修复] 获取嵌套子表，如果不存在则初始化
    db = type(db) == "table" and db or {}
    if key and not db[key] then db[key] = {} end
    local iconDb = key and db[key] or db

    -- 图标四项开关的默认状态。nil 视为开启，既兼容旧配置，也让首次打开
    -- 设置页时与当前默认视觉保持一致。
    if iconDb.showIcon == nil then iconDb.showIcon = true end
    if iconDb.showBorder == nil then iconDb.showBorder = true end
    if iconDb.enableCrop == nil then iconDb.enableCrop = true end
    if iconDb.showCooldown == nil then iconDb.showCooldown = true end
    if iconDb.reverse == nil then iconDb.reverse = false end
    if type(iconDb.cooldown) ~= "table" then iconDb.cooldown = {} end
    local cooldownDb = iconDb.cooldown
    if cooldownDb.showSwipe == nil then cooldownDb.showSwipe = true end
    if cooldownDb.swipeAlpha == nil then cooldownDb.swipeAlpha = 0.65 end
    if cooldownDb.showEdge == nil then cooldownDb.showEdge = true end
    if cooldownDb.edgeAlpha == nil then cooldownDb.edgeAlpha = 1 end
    if cooldownDb.showBling == nil then cooldownDb.showBling = false end

    local palette = {
        panel = MC.panel,
        card = MC.raised,
        utility = MC.raised,
        border = MC.border,
        borderSoft = MC.border,
        text = MC.text,
        value = MC.blue,
        accent = MC.blue,
    }

    local container, isNew = AcquireCompositeGroup("CompositeIconGroup", parent)
    container._exCompositeLabel = label or L["图标设置"]
    BindCompositeGroup(container, iconDb, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(container)
        EXUI:LayoutCompositeGroup(container, groupWidth, groupHeight)
        EXUI:ClearControlSurface(container)
        for _, card in ipairs(container._exIconMetricCards or {}) do
            EXUI:ClearControlSurface(card)
        end
        if container._exIconActionCard then
            EXUI:ClearControlSurface(container._exIconActionCard)
        end
        for _, popup in ipairs(container._exCompositePopups or {}) do
            EXUI:SetControlSurface(popup, 10, palette.panel, palette.border)
        end
        for _, line in ipairs(container.crispOutline or {}) do line:Hide() end
        container.crispOutline = nil
        return container
    end
    iconDb = CreateCompositeProxy(container)
    cooldownDb = CreateCompositeProxy(container, "cooldown")
    opts = setmetatable({}, { __index = function(_, field)
        return (container._exCompositeOpts or {})[field]
    end })
    onUpdate = function() CompositeEmitUpdate(container) end

    local function GetIconInputMetadata()
        local activeOpts = container._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateIconGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateIconGroup Grid write context requires pathPrefix", 2)
        end
        local commitAPI = EXUI.CommitModuleValue
        if type(commitAPI) ~= "function" then
            error("CreateIconGroup requires its Core commit API", 2)
        end
        return metadata.moduleKey, prefix
    end

    -- IconGroup 的写入上下文只由 Grid 注入；每次值变化都经统一 ModuleDB
    -- 通知重套已存在表面。
    local function WriteIconSliderValue(field, value)
        local target, key = iconDb, field
        local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
        if parentPath == "cooldown" then
            target, key = cooldownDb, childKey
        end
        target[key] = value
    end

    local function ReadIconValue(field)
        local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
        if parentPath == "cooldown" then return cooldownDb[childKey] end
        return iconDb[field]
    end

    local function CommitIconValue(field, value)
        local moduleKey, prefix = GetIconInputMetadata()
        if moduleKey then
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. field,
                readValue = function() return ReadIconValue(field) end,
                writeValue = function(nextValue) WriteIconSliderValue(field, nextValue) end,
            }
            return EXUI:CommitModuleValue(payload, value)
        end
        WriteIconSliderValue(field, value)
        if onUpdate then onUpdate() end
        return true
    end

    local function CreateIconColorTransaction(colorKey)
        local fields = colorKey == "borderColor"
            and { "borderColorR", "borderColorG", "borderColorB", "borderColorA" }
            or { "colorR", "colorG", "colorB", "colorA" }
        return function()
            -- 同 FontGroup：池化色盘必须在点击当下解析当前模块声明。
            local moduleKey, prefix = GetIconInputMetadata()
            if not moduleKey then return nil end
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. colorKey,
                readValue = function()
                    return { r = iconDb[fields[1]], g = iconDb[fields[2]], b = iconDb[fields[3]], a = iconDb[fields[4]] }
                end,
                writeValue = function(value)
                    iconDb[fields[1]], iconDb[fields[2]], iconDb[fields[3]], iconDb[fields[4]] = value.r, value.g, value.b, value.a
                end,
            }
            return EXUI:CreateModuleNotifyFlow(payload)
        end
    end

    local function SetIconSliderValue(field, value, phase)
        WriteIconSliderValue(field, value)
        if phase ~= "live" and onUpdate then onUpdate() end
    end

    -- 旧 RegisterModuleLayout 的 IconGroup 可声明公开 registry 生命周期。每次
    -- 按下均从当前 pooled group 的 opts 解析，绝不复用上一模块的 moduleKey/path；
    local function CreateIconNotifyFlow(field)
        local activeOpts = container._exCompositeOpts or {}
        local transaction = activeOpts._exWriteContext
        if transaction ~= nil then
            if type(transaction) ~= "table" or type(transaction.moduleKey) ~= "string" or transaction.moduleKey == "" then
                error("CreateIconGroup requires Grid write context", 2)
            end
            local prefix = transaction.pathPrefix or transaction.path
            if type(prefix) ~= "string" or prefix == "" then
                error("CreateIconGroup Grid write context requires pathPrefix", 2)
            end
            local createAPI = EXUI.CreateModuleNotifyFlow
            if type(createAPI) ~= "function" then
                error("CreateIconGroup requires its Core transaction API", 2)
            end
            local payload = {
                moduleKey = transaction.moduleKey,
                path = prefix .. "." .. field,
                readValue = function()
                    local target, fieldKey = iconDb, field
                    local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
                    if parentPath == "cooldown" then target, fieldKey = cooldownDb, childKey end
                    return target[fieldKey]
                end,
                writeValue = function(value) WriteIconSliderValue(field, value) end,
            }
            return createAPI(EXUI, payload)
        end
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateIconGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateIconGroup Grid write context requires pathPrefix", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateIconGroup requires CreateModuleNotifyFlow", 2)
        end
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = prefix .. "." .. field,
            readValue = function()
                local target, fieldKey = iconDb, field
                local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
                if parentPath == "cooldown" then target, fieldKey = cooldownDb, childKey end
                return target[fieldKey]
            end,
            writeValue = function(value)
                WriteIconSliderValue(field, value)
            end,
            commit = function(value)
                WriteIconSliderValue(field, value)
                if onUpdate then onUpdate() end
            end,
        })
    end

    local function CreateIconSlider(parentFrame, sliderWidth, titleText, field, minValue, maxValue, value, stepValue)
        local lifecycle
        return EXUI:CreateSlider(parentFrame, sliderWidth, titleText, minValue, maxValue, value, stepValue, nil, {
            onBegin = function()
                lifecycle = CreateIconNotifyFlow(field)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(v)
                if lifecycle and lifecycle.onLive then lifecycle.onLive(v) else SetIconSliderValue(field, v, "live") end
            end,
            onCommit = function(v)
                -- 同 FontGroup：数字输入是一次性提交，没有拖动期的 onBegin。
                local inputOpts = container._exCompositeOpts or {}
                if not lifecycle and inputOpts._exWriteContext ~= nil then
                    lifecycle = CreateIconNotifyFlow(field)
                end
                if lifecycle and lifecycle.onCommit then
                    lifecycle.onCommit(v)
                    lifecycle = nil
                else
                    SetIconSliderValue(field, v, "commit")
                end
            end,
        })
    end

    container:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(container)

    local content = CreateFrame("Frame", nil, container)
    content:SetSize(groupWidth, groupHeight)
    content:SetPoint("TOPLEFT", 0, 0)

    -- 左侧默认是 2x2 几何滑条；不需要模块局部图标偏移时可显式隐藏
    -- Position 控件，根锚点仍是该模块唯一的位置来源。
    local padding, gap = 15, 12
    local controlsGap = 18
    local controlWidth = narrowLayout and (groupWidth - padding * 2)
        or math.min(416, math.max(364, math.floor(groupWidth * 0.40)))
    local metricsWidth = narrowLayout and (groupWidth - padding * 2)
        or (groupWidth - padding * 2 - controlsGap - controlWidth)
    local itemWidth = math.floor((metricsWidth - gap) / 2)
    local col1 = padding
    local col2 = col1 + itemWidth + gap
    local row1, row2 = -8, -78
    local controlX = narrowLayout and padding or (padding + metricsWidth + controlsGap)
    local controlY = narrowLayout and (row2 - 64 - gap) or row1

    -- 每个几何参数保留独立深色卡片，避免滑条直接裸排在内容区。
    local function CreateMetricCard(x, y)
        local card = CreateFrame("Frame", nil, content)
        card:SetPoint("TOPLEFT", x, y)
        card:SetSize(itemWidth, 64)
        return card
    end

    local widthCard = CreateMetricCard(col1, row1)
    local heightCard = CreateMetricCard(col2, row1)
    local sliderWidth = itemWidth - 20

    local sWidth = CreateIconSlider(widthCard, sliderWidth, L["宽度 (Width)"], "width", 10, 300, iconDb.width or 64, 1)
    sWidth:SetPoint("TOPLEFT", 10, -10)

    local sHeight = CreateIconSlider(heightCard, sliderWidth, L["高度 (Height)"], "height", 10, 300, iconDb.height or 64, 1)
    sHeight:SetPoint("TOPLEFT", 10, -10)

    local sPosX, sPosY, xCard, yCard
    if opts.hidePositionControls ~= true then
        xCard = CreateMetricCard(col1, row2)
        yCard = CreateMetricCard(col2, row2)
        -- Aura 图标可用较细的偏移范围；排序和间距属于另一张“排序”卡片，绝不由这里重算。
        local offsetMin = tonumber(opts.offsetMin) or -1000
        local offsetMax = tonumber(opts.offsetMax) or 1000
        local offsetStep = tonumber(opts.offsetStep) or 1
        sPosX = CreateIconSlider(xCard, sliderWidth, L["水平偏移 (X)"], "x", offsetMin, offsetMax, iconDb.x or 0, offsetStep)
        sPosX:SetPoint("TOPLEFT", 10, -10)

        sPosY = CreateIconSlider(yCard, sliderWidth, L["垂直偏移 (Y)"], "y", offsetMin, offsetMax, iconDb.y or 0, offsetStep)
        sPosY:SetPoint("TOPLEFT", 10, -10)
    end
    container._exIconMetricCards = { widthCard, heightCard }
    if xCard then container._exIconMetricCards[#container._exIconMetricCards + 1] = xCard end
    if yCard then container._exIconMetricCards[#container._exIconMetricCards + 1] = yCard end

    -- 四项功能控制区：每一行左侧开关、右侧对应设置按钮。
    local actionCard = CreateFrame("Frame", nil, content)
    actionCard:SetPoint("TOPLEFT", controlX, controlY)
    actionCard:SetSize(controlWidth, math.abs(row2 - row1) + 64)
    container._exIconActionCard = actionCard
    CreateCompositeColumnDivider(content, widthCard, xCard or widthCard, "RIGHT", gap / 2)
    local actionDivider = CreateCompositeColumnDivider(content, actionCard, actionCard, "LEFT", -controlsGap / 2)
    actionDivider:SetShown(not narrowLayout)

    local cbShow = EXUI:CreateCheckbox(actionCard, L["显示图标"], iconDb.showIcon, function(v)
        CommitIconValue("showIcon", v)
    end)
    cbShow:SetPoint("TOPLEFT", 12, -4)
    cbShow:SetSize(132, 28)
    local cbShowBorder = EXUI:CreateCheckbox(actionCard, L["显示边框"], iconDb.showBorder, function(v)
        CommitIconValue("showBorder", v)
    end)
    cbShowBorder:SetPoint("TOPLEFT", 12, -38)
    cbShowBorder:SetSize(132, 28)
    local cbCrop = EXUI:CreateCheckbox(actionCard, L["裁切图标"], iconDb.enableCrop, function(v)
        CommitIconValue("enableCrop", v)
    end)
    cbCrop:SetPoint("TOPLEFT", 12, -72)
    cbCrop:SetSize(132, 28)
    local cbCooldown = EXUI:CreateCheckbox(actionCard, L["图标倒数"], iconDb.showCooldown, function(v)
        CommitIconValue("showCooldown", v)
    end)
    cbCooldown:SetPoint("TOPLEFT", 12, -106)
    cbCooldown:SetSize(132, 28)
    local function CreatePopup(titleText, width, height)
        local popup = CreateCompositePopupHost(container, width, height)
        EXUI:SetControlSurface(popup, 10, palette.panel, palette.border)
        popup:Hide()

        local popupTitle = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontHighlight")
        popupTitle:SetPoint("TOPLEFT", 13, -9)
        popupTitle:SetText(titleText)
        StyleModernTitle(popupTitle)

        local close = EXUI:CreateButton(popup, 28, 24, "×", function()
            popup:Hide()
        end, { compact = true })
        close:SetPoint("TOPRIGHT", -7, -4)
        return popup
    end

    local popupScale = 1.3
    local appearancePopupW = math.floor(400 * popupScale)
    local appearancePopup = CreatePopup(L["外观设置"], appearancePopupW, 254)
    local countdownPopupW, countdownPopupH = math.floor(400 * popupScale), 212
    local countdownPopup = CreatePopup(L["倒数设置"], countdownPopupW, countdownPopupH)
    local appearancePad, appearanceGap = 14, 18
    local appearanceItemW = math.floor((appearancePopupW - appearancePad * 2 - appearanceGap) / 2)

    -- central basicIcon 的图标来源属于业务 item，不是外观 DB；该中央分支不许
    -- CreateIconGroup 偷建/编辑 legacy iconID。旧页面保持原来的可选输入框。
    if opts.hideIconID ~= true then
        local inputIcon = EXUI:CreateEditBox(
            appearancePopup,
            tostring(iconDb.iconID or ""),
            appearanceItemW,
            32,
            L["图标ID (可选)"],
            {
                onEnter = function(v)
                    CommitIconValue("iconID", tonumber(v) or nil)
                end,
                onEditFocusLost = function(v)
                    CommitIconValue("iconID", tonumber(v) or nil)
                end,
                labelPos = "top"
            }
        )
        inputIcon:SetPoint("TOPLEFT", appearancePad, -44)
    end

    local alpha = CreateIconSlider(appearancePopup, appearanceItemW, L["图标透明度"], "alpha", 0, 1,
        tonumber(iconDb.alpha) or 1, 0.05)
    alpha:SetPoint("TOPLEFT", appearancePad + appearanceItemW + appearanceGap, -40)

    local cbDesaturated = EXUI:CreateCheckbox(appearancePopup, L["图标变灰"], iconDb.desaturated, function(v)
        CommitIconValue("desaturated", v)
    end)
    cbDesaturated:SetPoint("TOPLEFT", appearancePad, -92)
    local iconColor = EXUI:CreateColorButton(appearancePopup, L["图标染色"], iconDb, "color", true, onUpdate,
        { _changeFlow = CreateIconColorTransaction("color") })
    iconColor:SetPoint("TOPLEFT", appearancePad, -128)

    local blendDrop = EXUI:CreateDropdown(appearancePopup, appearanceItemW, L["混合模式"], {
        { "BLEND", "BLEND" },
        { "ADD", "ADD" },
        { "MOD", "MOD" },
        { "ALPHAKEY", "ALPHAKEY" },
        { "DISABLE", "DISABLE" },
    }, iconDb.blendMode or "BLEND", function(v)
        CommitIconValue("blendMode", v)
    end)
    blendDrop:SetPoint("TOPLEFT", appearancePad + appearanceItemW + appearanceGap, -132)

    local rotation = CreateIconSlider(appearancePopup, appearanceItemW, L["旋转角度"], "rotation", -180, 180,
        tonumber(iconDb.rotation) or 0, 1)
    rotation:SetPoint("TOPLEFT", appearancePad, -202)

    local popupW, popupH = math.floor(580 * popupScale), 154
    local cropPopup = CreatePopup(L["裁切设置"], popupW, popupH)
    local borderPopup = CreatePopup(L["边框设置"], popupW, popupH)
    local popupPad, popupGap = 14, 18
    local popupItemW = math.floor((popupW - popupPad * 2 - popupGap) / 2)
    local popupCol1 = popupPad
    local popupCol2 = popupCol1 + popupItemW + popupGap

    local cropLeft = CreateIconSlider(cropPopup, popupItemW, L["裁切左 (Crop Left)"], "cropLeft", 0, 1,
        tonumber(iconDb.cropLeft) or 0.08, 0.01)
    cropLeft:SetPoint("TOPLEFT", popupCol1, -48)

    local cropRight = CreateIconSlider(cropPopup, popupItemW, L["裁切右 (Crop Right)"], "cropRight", 0, 1,
        tonumber(iconDb.cropRight) or 0.92, 0.01)
    cropRight:SetPoint("TOPLEFT", popupCol2, -48)

    local cropTop = CreateIconSlider(cropPopup, popupItemW, L["裁切上 (Crop Top)"], "cropTop", 0, 1,
        tonumber(iconDb.cropTop) or 0.08, 0.01)
    cropTop:SetPoint("TOPLEFT", popupCol1, -101)

    local cropBottom = CreateIconSlider(cropPopup, popupItemW, L["裁切下 (Crop Bottom)"], "cropBottom", 0, 1,
        tonumber(iconDb.cropBottom) or 0.92, 0.01)
    cropBottom:SetPoint("TOPLEFT", popupCol2, -101)

    local borderBtn = EXUI:CreateColorButton(borderPopup, L["边框颜色"], iconDb, "borderColor", true, onUpdate,
        { _changeFlow = CreateIconColorTransaction("borderColor") })
    borderBtn:SetPoint("TOPLEFT", popupCol1, -48)

    local borderDrop = EXUI:CreateLSMTextureDropdown(borderPopup, "border", popupItemW, L["边框材质"],
        iconDb.borderTexture or "None",
        function(k)
            CommitIconValue("borderTexture", k)
        end)
    borderDrop:SetPoint("TOPLEFT", popupCol2, -48)

    local sBorderSize = CreateIconSlider(borderPopup, popupItemW, L["边框粗细"], "borderSize", -10, 10,
        iconDb.borderSize or 1, 0.1)
    sBorderSize:SetPoint("TOPLEFT", popupCol1, -101)

    local sBorderPad = CreateIconSlider(borderPopup, popupItemW, L["边框间距 (Padding)"], "borderPadding", -10, 10,
        iconDb.borderPadding or 0, 0.1)
    sBorderPad:SetPoint("TOPLEFT", popupCol2, -101)

    -- 图标倒数的原生扇形视觉全部收口于此；数字文本由统一文本控件接管。
    local cbReverse = EXUI:CreateCheckbox(countdownPopup, L["倒数反转"], iconDb.reverse, function(v)
        CommitIconValue("reverse", v)
    end)
    cbReverse:SetPoint("TOPLEFT", 14, -42)
    cbReverse:SetSize(156, 28)
    local countdownPad, countdownGap = 14, 18
    local countdownItemW = math.floor((countdownPopupW - countdownPad * 2 - countdownGap) / 2)
    local countdownCol2 = countdownPad + countdownItemW + countdownGap

    local cbSwipe = EXUI:CreateCheckbox(countdownPopup, L["启用扇形倒数"], cooldownDb.showSwipe, function(v)
        CommitIconValue("cooldown.showSwipe", v)
    end)
    cbSwipe:SetPoint("TOPLEFT", countdownCol2, -42)
    cbSwipe:SetSize(156, 28)
    local cbEdge = EXUI:CreateCheckbox(countdownPopup, L["显示边缘光"], cooldownDb.showEdge, function(v)
        CommitIconValue("cooldown.showEdge", v)
    end)
    cbEdge:SetPoint("TOPLEFT", countdownPad, -76)
    cbEdge:SetSize(156, 28)
    local cbBling = EXUI:CreateCheckbox(countdownPopup, L["倒数结束闪光"], cooldownDb.showBling, function(v)
        CommitIconValue("cooldown.showBling", v)
    end)
    cbBling:SetPoint("TOPLEFT", countdownCol2, -76)
    cbBling:SetSize(176, 28)
    local swipeAlpha = CreateIconSlider(countdownPopup, countdownItemW, L["扇形透明度"], "cooldown.swipeAlpha", 0, 1,
        cooldownDb.swipeAlpha, 0.05)
    swipeAlpha:SetPoint("TOPLEFT", countdownPad, -128)

    local edgeAlpha = CreateIconSlider(countdownPopup, countdownItemW, L["边缘光透明度"], "cooldown.edgeAlpha", 0, 1,
        cooldownDb.edgeAlpha, 0.05)
    edgeAlpha:SetPoint("TOPLEFT", countdownCol2, -128)

    local function TogglePopup(popup, anchor, point, relativePoint)
        local shouldShow = not popup:IsShown()
        appearancePopup:Hide()
        cropPopup:Hide()
        borderPopup:Hide()
        countdownPopup:Hide()
        if shouldShow then
            popup:ClearAllPoints()
            popup:SetPoint(point, anchor, relativePoint, 0, -6)
            popup:Show()
        end
    end

    -- 功能按钮与普通页面按钮共享同一构造器和状态 painter。
    local function CreateUtilityButton(text, width, onClick)
        return EXUI:CreateButton(actionCard, width, 28, text, onClick, { variant = "soft" })
    end

    local buttonWidth = math.min(187, math.floor(controlWidth * 0.45))
    local appearanceButton = CreateUtilityButton(L["外观设置"], buttonWidth, function(self)
        TogglePopup(appearancePopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)
    appearanceButton:SetPoint("TOPRIGHT", actionCard, "TOPRIGHT", -10, -4)

    local borderButton = CreateUtilityButton(L["边框设置"], buttonWidth, function(self)
        TogglePopup(borderPopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)
    borderButton:SetPoint("TOPRIGHT", actionCard, "TOPRIGHT", -10, -38)

    local cropButton = CreateUtilityButton(L["裁切设置"], buttonWidth, function(self)
        TogglePopup(cropPopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)
    cropButton:SetPoint("TOPRIGHT", actionCard, "TOPRIGHT", -10, -72)

    local countdownButton = CreateUtilityButton(L["倒数设置"], buttonWidth, function(self)
        TogglePopup(countdownPopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)
    countdownButton:SetPoint("TOPRIGHT", actionCard, "TOPRIGHT", -10, -106)

    container:HookScript("OnHide", function()
        appearancePopup:Hide()
        cropPopup:Hide()
        borderPopup:Hide()
        countdownPopup:Hide()
    end)

    RegisterCompositeControl(container, sWidth, "width", "slider")
    RegisterCompositeControl(container, sHeight, "height", "slider")
    if sPosX then RegisterCompositeControl(container, sPosX, "x", "slider") end
    if sPosY then RegisterCompositeControl(container, sPosY, "y", "slider") end
    RegisterCompositeControl(container, cbShow, "showIcon", "check")
    RegisterCompositeControl(container, cbShowBorder, "showBorder", "check")
    RegisterCompositeControl(container, cbCrop, "enableCrop", "check")
    RegisterCompositeControl(container, cbCooldown, "showCooldown", "check")
    RegisterCompositeControl(container, inputIcon, "iconID", "edit")
    RegisterCompositeControl(container, alpha, "alpha", "slider")
    RegisterCompositeControl(container, cbDesaturated, "desaturated", "check")
    RegisterCompositeControl(container, iconColor, "color", "color")
    RegisterCompositeControl(container, blendDrop, "blendMode", "dropdown")
    RegisterCompositeControl(container, rotation, "rotation", "slider")
    RegisterCompositeControl(container, cropLeft, "cropLeft", "slider")
    RegisterCompositeControl(container, cropRight, "cropRight", "slider")
    RegisterCompositeControl(container, cropTop, "cropTop", "slider")
    RegisterCompositeControl(container, cropBottom, "cropBottom", "slider")
    RegisterCompositeControl(container, borderBtn, "borderColor", "color")
    RegisterCompositeControl(container, borderDrop, "borderTexture", "dropdown")
    RegisterCompositeControl(container, sBorderSize, "borderSize", "slider")
    RegisterCompositeControl(container, sBorderPad, "borderPadding", "slider")
    RegisterCompositeControl(container, cbReverse, "reverse", "check")
    RegisterCompositeControl(container, cbSwipe, "cooldown.showSwipe", "check")
    RegisterCompositeControl(container, cbEdge, "cooldown.showEdge", "check")
    RegisterCompositeControl(container, cbBling, "cooldown.showBling", "check")
    RegisterCompositeControl(container, swipeAlpha, "cooldown.swipeAlpha", "slider")
    RegisterCompositeControl(container, edgeAlpha, "cooldown.edgeAlpha", "slider")
    container._exCompositePopups = { appearancePopup, cropPopup, borderPopup, countdownPopup }
    container._iconGroupDb = iconDb
    container._exCompositeReflow = function(self, nextWidth, nextHeight)
        local nextNarrow = nextWidth < 720
        local nextControlWidth = nextNarrow and (nextWidth - padding * 2)
            or math.min(416, math.max(364, math.floor(nextWidth * 0.40)))
        local nextMetricsWidth = nextNarrow and (nextWidth - padding * 2)
            or (nextWidth - padding * 2 - controlsGap - nextControlWidth)
        local nextItemWidth = math.floor((nextMetricsWidth - gap) / 2)
        local nextCol2 = padding + nextItemWidth + gap
        local nextControlX = nextNarrow and padding or (padding + nextMetricsWidth + controlsGap)
        local nextControlY = nextNarrow and (row2 - 64 - gap) or row1
        local nextSliderWidth = nextItemWidth - 20

        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, nextHeight)
        EXUI:ClearControlSurface(self)
        local metricCards = { widthCard, heightCard }
        if xCard then metricCards[#metricCards + 1] = xCard end
        if yCard then metricCards[#metricCards + 1] = yCard end
        for _, card in ipairs(metricCards) do card:SetSize(nextItemWidth, 64) end
        widthCard:ClearAllPoints(); widthCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row1)
        heightCard:ClearAllPoints(); heightCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row1)
        if xCard then xCard:ClearAllPoints(); xCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row2) end
        if yCard then yCard:ClearAllPoints(); yCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row2) end
        local metricSliders = { sWidth, sHeight }
        if sPosX then metricSliders[#metricSliders + 1] = sPosX end
        if sPosY then metricSliders[#metricSliders + 1] = sPosY end
        for _, slider in ipairs(metricSliders) do slider:SetWidth(nextSliderWidth) end
        actionCard:ClearAllPoints(); actionCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextControlX, nextControlY)
        actionCard:SetSize(nextControlWidth, math.abs(row2 - row1) + 64)
        actionDivider:SetShown(not nextNarrow)
        local nextButtonWidth = math.min(187, math.floor(nextControlWidth * 0.45))
        appearanceButton:SetWidth(nextButtonWidth); borderButton:SetWidth(nextButtonWidth)
        cropButton:SetWidth(nextButtonWidth); countdownButton:SetWidth(nextButtonWidth)
    end
    EXUI:LayoutCompositeGroup(container, groupWidth, groupHeight)
    AttachCompositeRelease(container)

    return container
end

-- =========================================================
-- 18. 计时条设置组（TimerBarWidget 对应的配置 GUI）
-- =========================================================
function EXUI:CreateTimerBarGroup(parent, width, label, db, key, onUpdate, opts)
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    local iconOffsetMin = tonumber(opts.iconOffsetMin) or -200
    local iconOffsetMax = tonumber(opts.iconOffsetMax) or 200
    local defaults = {
        width = 240, height = 24, x = 0, y = 0,
        texture = "Clean",
        barColorR = 1, barColorG = 0.7, barColorB = 0, barColorA = 1,
        barBgColorR = 0, barBgColorG = 0, barBgColorB = 0, barBgColorA = 0.5,
        showBorder = true, borderTexture = "None", borderSize = 1, borderPadding = 0,
        borderColorR = 1, borderColorG = 1, borderColorB = 1, borderColorA = 1,
        showIcon = true, iconWidth = 24, iconHeight = 24, iconSide = "LEFT",
        iconOffsetX = -5, iconOffsetY = 0,
        showIconBorder = true, iconBorderTexture = "None", iconBorderSize = 1, iconBorderPadding = 0,
        iconBorderColorR = 1, iconBorderColorG = 1, iconBorderColorB = 1, iconBorderColorA = 1,
        fillMode = opts.fillModeOnly == true and "LTR_FILL" or "RTL_DRAIN", fillDirection = "LEFT_TO_RIGHT", progressMode = "REMAINING",
    }
    if opts.fillModeOnly == true then
        defaults.fillDirection, defaults.progressMode = nil, nil
    end
    for field, value in pairs(defaults) do
        if db[field] == nil then db[field] = value end
    end
    local groupWidth = width or 975
    local groupHeight = 204
    -- 层数条复用计时条的尺寸／材质／颜色／边框控件，但没有 duration、图标或填充模式语义。
    -- 使用独立对象池，避免普通计时条和层数条之间残留可见控件。
    local poolType = opts.applicationBar == true and "CompositeTimerBarApplicationGroup" or "CompositeTimerBarGroup"
    local group, isNew = AcquireCompositeGroup(poolType, parent)
    group._exCompositeLabel = label or L["计时条设置"]
    BindCompositeGroup(group, db, onUpdate, opts)
    -- TimerBar 的真实 DB 路径只由 Grid 的私有写入上下文提供。
    local function CreateTimerBarNotifyFlow(field)
        local metadata = group._exCompositeOpts and group._exCompositeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == ""
            or type(metadata.pathPrefix) ~= "string" then
            error("CreateTimerBarGroup requires Grid write context", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateTimerBarGroup requires CreateModuleNotifyFlow", 2)
        end
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = metadata.pathPrefix .. "." .. field,
            readValue = function() return db[field] end,
            writeValue = function(value) db[field] = value end,
            commit = function(value)
                db[field] = value
                CompositeEmitUpdate(group)
            end,
        })
    end
    -- 已声明的 TimerBarGroup 全部控件均走统一通知流。
    local function CreateTimerBarNotifyFlowForValue(field, readValue, writeValue)
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == ""
            or type(metadata.pathPrefix) ~= "string" or metadata.pathPrefix == "" then
            error("CreateTimerBarGroup requires Grid write context", 2)
        end
        local createAPI = EXUI.CreateModuleNotifyFlow
        if type(createAPI) ~= "function" then
            error("CreateTimerBarGroup requires CreateModuleNotifyFlow", 2)
        end
        return createAPI(EXUI, {
            moduleKey = metadata.moduleKey,
            path = metadata.pathPrefix .. "." .. field,
            readValue = readValue or function() return db[field] end,
            writeValue = writeValue or function(value) db[field] = value end,
        })
    end
    group._timerBarFillModeOnly = opts.fillModeOnly == true
    if not isNew then
        -- 下拉菜单由对象池复用，但严格 TimerBar 与旧模块的 fill 值集合不同。
        -- 每次借用都必须覆盖菜单与当前值，不能保留上一次页面的项目或闭包语义。
        local fillMode = group._timerBarFillModeDropdown
        if not fillMode then
            error("CreateTimerBarGroup: pooled group is missing fillMode dropdown", 2)
        end
        fillMode._items = group._timerBarFillModeOnly and {
            { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_FADE" },
            { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_FADE" },
        } or {
            { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_DRAIN" },
            { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_DRAIN" },
        }
        fillMode._currentValue = db.fillMode
        SetDropdownDisplayText(fillMode, CompositeDropdownText(db.fillMode, fillMode._items) or L["请选择..."])
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        EXUI:ClearControlSurface(group)
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy

    local function EmitUpdate() CompositeEmitUpdate(group) end
    local function GetTimerBarInputMetadata()
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == ""
            or type(metadata.pathPrefix) ~= "string" or metadata.pathPrefix == "" then
            error("CreateTimerBarGroup requires Grid write context", 2)
        end
        local commitAPI = EXUI.CommitModuleValue
        if type(commitAPI) ~= "function" then
            error("CreateTimerBarGroup requires CommitModuleValue", 2)
        end
        return metadata.moduleKey, metadata.pathPrefix
    end
    local function CommitTimerBarValue(field, value, writeValue)
        local moduleKey, prefix = GetTimerBarInputMetadata()
        local Write = writeValue or function(nextValue) db[field] = nextValue end
        if moduleKey then
            return EXUI:CommitModuleValue({
                moduleKey = moduleKey, path = prefix .. "." .. field,
                readValue = function() return db[field] end, writeValue = Write,
            }, value)
        end
        Write(value)
        EmitUpdate()
        return true
    end
    local palette = {
        panel = MC.panel, card = MC.raised,
        utility = MC.input, border = MC.border,
        text = MC.text, value = MC.blue,
    }
    local flatBackdrop = {
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    }
    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local content = CreateFrame("Frame", nil, group)
    content:SetSize(groupWidth, groupHeight); content:SetPoint("TOPLEFT", 0, 0)
    local padding, gap, controlsGap = 15, 12, 18
    local controlWidth = math.min(416, math.max(364, math.floor(groupWidth * 0.40)))
    local metricsWidth = groupWidth - padding * 2 - controlsGap - controlWidth
    local itemWidth = math.floor((metricsWidth - gap) / 2)
    local col1, col2 = padding, padding + itemWidth + gap
    local row1, row2, row3 = -8, -76, -144
    local controlX = padding + metricsWidth + controlsGap

    local function CreateMetricCard(x, y)
        local card = CreateFrame("Frame", nil, content)
        card:SetPoint("TOPLEFT", x, y); card:SetSize(itemWidth, 60)
        return card
    end
    local widthCard, heightCard = CreateMetricCard(col1, row1), CreateMetricCard(col2, row1)
    local xCard, yCard = CreateMetricCard(col1, row2), CreateMetricCard(col2, row2)
    local colorCard, textureCard = CreateMetricCard(col1, row3), CreateMetricCard(col2, row3)
    local sliderWidth = itemWidth - 20
    local function AddSlider(card, titleText, field, min, max, step)
        local lifecycle, transaction
        local slider = EXUI:CreateSlider(card, sliderWidth, titleText, min, max, db[field], step, nil, {
            onBegin = function()
                transaction = CreateTimerBarNotifyFlowForValue(field)
                if transaction then transaction.onBegin(); return end
                lifecycle = CreateTimerBarNotifyFlow(field)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(value)
                if transaction then return transaction.onLive(value) end
                if lifecycle and lifecycle.onLive then return lifecycle.onLive(value) end
                db[field] = value
            end,
            onCommit = function(value)
                -- 输入框路径没有 onBegin；按提交当下的声明建立同一事务。
                if not transaction then transaction = CreateTimerBarNotifyFlowForValue(field) end
                if transaction then
                    local result = transaction.onCommit(value)
                    transaction = nil
                    return result
                end
                if lifecycle and lifecycle.onCommit then
                    local result = lifecycle.onCommit(value)
                    lifecycle = nil
                    return result
                end
                db[field] = value
                EmitUpdate()
            end,
        })
        slider:SetPoint("TOPLEFT", 10, -8)
        return RegisterCompositeControl(group, slider, field, "slider")
    end
    -- 边框/图标弹窗里的数值控件也必须遵守与主面板同一 live 合同：
    -- 拖动仅重套已物化视觉，松手才统一广播 DatabaseChanged。
    local function AddPopupSlider(parent, sliderWidth, titleText, field, min, max, step)
        local lifecycle, transaction
        local slider = EXUI:CreateSlider(parent, sliderWidth, titleText, min, max, db[field], step, nil, {
            onBegin = function()
                transaction = CreateTimerBarNotifyFlowForValue(field)
                if transaction then transaction.onBegin(); return end
                lifecycle = CreateTimerBarNotifyFlow(field)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(value)
                if transaction then return transaction.onLive(value) end
                if lifecycle and lifecycle.onLive then return lifecycle.onLive(value) end
                db[field] = value
            end,
            onCommit = function(value)
                -- 弹窗 Slider 的数字输入也必须走同一条事务。
                if not transaction then transaction = CreateTimerBarNotifyFlowForValue(field) end
                if transaction then
                    local result = transaction.onCommit(value)
                    transaction = nil
                    return result
                end
                if lifecycle and lifecycle.onCommit then
                    local result = lifecycle.onCommit(value)
                    lifecycle = nil
                    return result
                end
                db[field] = value
                EmitUpdate()
            end,
        })
        return slider
    end
    AddSlider(widthCard, L["宽度 (Width)"], "width", 50, 800, 1)
    AddSlider(heightCard, L["高度 (Height)"], "height", 8, 120, 1)
    AddSlider(xCard, L["X 轴偏移"], "x", -1000, 1000, 1)
    AddSlider(yCard, L["Y 轴偏移"], "y", -1000, 1000, 1)

    -- 第三行：两个半宽颜色按钮 + 一项 LSM 条体材质。
    local colorHalfWidth = math.floor((itemWidth - 30) / 2)
    local function CreateColorTransaction(field)
        return function()
            return CreateTimerBarNotifyFlowForValue(field,
                function()
                    return { r = db[field .. "R"], g = db[field .. "G"], b = db[field .. "B"], a = db[field .. "A"] }
                end,
                function(value)
                    db[field .. "R"], db[field .. "G"], db[field .. "B"], db[field .. "A"] = value.r, value.g, value.b, value.a
                end)
        end
    end
    local fgButton = EXUI:CreateColorButton(colorCard, L["前景"], db, "barColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("barColor") })
    fgButton:SetSize(colorHalfWidth, 36); fgButton:SetPoint("TOPLEFT", 10, -22)
    local bgButton = EXUI:CreateColorButton(colorCard, L["背景"], db, "barBgColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("barBgColor") })
    bgButton:SetSize(colorHalfWidth, 36); bgButton:SetPoint("TOPLEFT", 15 + colorHalfWidth, -22)
    local textureDrop = EXUI:CreateLSMTextureDropdown(textureCard, "statusbar", sliderWidth, L["LSM皮肤"], db.texture, function(value)
        CommitTimerBarValue("texture", value)
    end)
    textureDrop:SetPoint("TOPLEFT", 10, -26)

    local actionCard = CreateFrame("Frame", nil, content)
    actionCard:SetPoint("TOPLEFT", controlX, row1); actionCard:SetSize(controlWidth, 196)
    CreateCompositeColumnDivider(content, widthCard, colorCard, "RIGHT", gap / 2)
    CreateCompositeColumnDivider(content, actionCard, actionCard, "LEFT", -controlsGap / 2)
    local function ActionButton(text, y, callback)
        local button = EXUI:CreateButton(actionCard, math.min(187, math.floor(controlWidth * 0.45)), 28,
            text, callback, { variant = "soft" })
        button:SetPoint("TOPRIGHT", -10, y)
        return button
    end

    local popupList = {}
    local function CreatePopup(titleText, popupWidth, popupHeight)
        local popup = CreateCompositePopupHost(group, popupWidth, popupHeight)
        popup:SetBackdrop(flatBackdrop); popup:SetBackdropColor(unpack(palette.panel)); popup:SetBackdropBorderColor(unpack(palette.border)); popup:Hide()
        local popupTitle = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontHighlight")
        popupTitle:SetPoint("TOPLEFT", 13, -9); popupTitle:SetText(titleText)
        StyleModernTitle(popupTitle)
        local close = EXUI:CreateButton(popup, 28, 24, "×", function() popup:Hide() end, { compact = true })
        close:SetPoint("TOPRIGHT", -7, -4)
        popupList[#popupList + 1] = popup
        return popup
    end
    local function TogglePopup(popup, anchor)
        local show = not popup:IsShown()
        for _, other in ipairs(popupList) do other:Hide() end
        if show then popup:ClearAllPoints(); popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6); popup:Show() end
    end

    local borderPopup = CreatePopup(L["边框设置"], 540, 166)
    local borderTexture = EXUI:CreateLSMTextureDropdown(borderPopup, "border", 245, L["边框材质"], db.borderTexture, function(value)
        CommitTimerBarValue("borderTexture", value)
    end)
    borderTexture:SetPoint("TOPLEFT", 14, -46)
    local borderColor = EXUI:CreateColorButton(borderPopup, L["边框颜色"], db, "borderColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("borderColor") })
    borderColor:SetPoint("TOPLEFT", 280, -42)
    local borderSize = AddPopupSlider(borderPopup, 245, L["边框粗细"], "borderSize", 0, 20, 0.1)
    borderSize:SetPoint("TOPLEFT", 14, -112)
    local borderPad = AddPopupSlider(borderPopup, 245, L["边框间距 (Padding)"], "borderPadding", -10, 10, 0.1)
    borderPad:SetPoint("TOPLEFT", 280, -112)

    local iconPopup = CreatePopup(L["图标设置"], 700, 306)
    local iconColumnWidth, iconColumn2 = 320, 362
    local iconSides = { { L["左侧"], "LEFT" }, { L["中间"], "CENTER" }, { L["右侧"], "RIGHT" } }
    local iconSide = EXUI:CreateDropdown(iconPopup, iconColumnWidth, L["图标位置"], iconSides, db.iconSide, function(value)
        CommitTimerBarValue("iconSide", value)
    end)
    iconSide:SetPoint("TOPLEFT", 14, -46)
    -- 坐标最终由 Widget 按物理像素对齐；和条/文字/材质的其它位置控件一致，
    -- 必须使用整数步进。0.1 会把 -200..200 扩成 4,000 个原生 Slider 档位，
    -- 但不会产生额外可见位置，反而只让这两个拖动控件异常迟滞。
    local iconOffsetX = AddPopupSlider(iconPopup, iconColumnWidth, L["图标 X 轴偏移"], "iconOffsetX", iconOffsetMin, iconOffsetMax, 1)
    iconOffsetX:SetPoint("TOPLEFT", iconColumn2, -46)
    local iconWidth = AddPopupSlider(iconPopup, iconColumnWidth, L["图标宽度"], "iconWidth", 8, 160, 1)
    iconWidth:SetPoint("TOPLEFT", 14, -100)
    local iconHeight = AddPopupSlider(iconPopup, iconColumnWidth, L["图标高度"], "iconHeight", 8, 160, 1)
    iconHeight:SetPoint("TOPLEFT", iconColumn2, -100)
    local iconOffsetY = AddPopupSlider(iconPopup, iconColumnWidth, L["图标 Y 轴偏移"], "iconOffsetY", iconOffsetMin, iconOffsetMax, 1)
    iconOffsetY:SetPoint("TOPLEFT", 14, -154)
    local showIconBorder = EXUI:CreateCheckbox(iconPopup, L["显示图标边框"], db.showIconBorder, function(value)
        CommitTimerBarValue("showIconBorder", value)
    end)
    showIconBorder:SetPoint("TOPLEFT", iconColumn2, -154)
    local iconBorderTexture = EXUI:CreateLSMTextureDropdown(iconPopup, "border", iconColumnWidth, L["图标边框材质"], db.iconBorderTexture, function(value)
        CommitTimerBarValue("iconBorderTexture", value)
    end)
    iconBorderTexture:SetPoint("TOPLEFT", 14, -208)
    local iconBorderColor = EXUI:CreateColorButton(iconPopup, L["图标边框颜色"], db, "iconBorderColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("iconBorderColor") })
    iconBorderColor:SetPoint("TOPLEFT", iconColumn2, -204)
    local iconBorderSize = AddPopupSlider(iconPopup, iconColumnWidth, L["图标边框粗细"], "iconBorderSize", 0, 20, 0.1)
    iconBorderSize:SetPoint("TOPLEFT", 14, -262)
    local iconBorderPad = AddPopupSlider(iconPopup, iconColumnWidth, L["图标边框间距"], "iconBorderPadding", -10, 10, 0.1)
    iconBorderPad:SetPoint("TOPLEFT", iconColumn2, -262)

    local fillPopup = CreatePopup(L["填充设置"], 540, 126)
    local fillOptions = opts.fillModeOnly == true and {
        { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_FADE" },
        { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_FADE" },
    } or {
        { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_DRAIN" },
        { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_DRAIN" },
    }
    local fillMode = EXUI:CreateDropdown(fillPopup, 510, L["填充方式"], fillOptions, db.fillMode, function(value)
        local function WriteFillMode(nextValue)
            db.fillMode = nextValue
            if group._timerBarFillModeOnly == true then return end
            if nextValue == "LTR_FILL" then db.fillDirection, db.progressMode = "LEFT_TO_RIGHT", "ELAPSED"
            elseif nextValue == "LTR_DRAIN" then db.fillDirection, db.progressMode = "RIGHT_TO_LEFT", "REMAINING"
            elseif nextValue == "RTL_FILL" then db.fillDirection, db.progressMode = "RIGHT_TO_LEFT", "ELAPSED"
            else db.fillDirection, db.progressMode = "LEFT_TO_RIGHT", "REMAINING" end
        end
        if group._timerBarFillModeOnly == true then
            CommitTimerBarValue("fillMode", value, WriteFillMode)
            return
        end
        CommitTimerBarValue("fillMode", value, WriteFillMode)
    end)
    fillMode:SetPoint("TOPLEFT", 14, -46)
    group._timerBarFillModeDropdown = fillMode

    local showIcon = EXUI:CreateCheckbox(actionCard, L["显示图标"], db.showIcon, function(value)
        CommitTimerBarValue("showIcon", value)
    end)
    showIcon:SetPoint("TOPLEFT", 12, -13); showIcon:SetSize(150, 28)
    local iconButton = ActionButton(L["图标设置"], -13, function(self) TogglePopup(iconPopup, self) end)

    local showBorder = EXUI:CreateCheckbox(actionCard, L["显示边框"], db.showBorder, function(value)
        CommitTimerBarValue("showBorder", value)
    end)
    showBorder:SetPoint("TOPLEFT", 12, -82); showBorder:SetSize(150, 28)
    local borderButton = ActionButton(L["边框设置"], -82, function(self) TogglePopup(borderPopup, self) end)

    local fillLabel = EXUI:CreateVisualFontString(actionCard, EXFONTFRAME, "GameFontHighlight")
    -- LEFT 锚点的 Y 偏移从垂直中线计算，会把文字推到卡片外；必须以 TOPLEFT 定位。
    fillLabel:SetPoint("TOPLEFT", actionCard, "TOPLEFT", 36, -148); fillLabel:SetText(L["填充方式"])
    StyleModernTitle(fillLabel)
    local fillButton = ActionButton(L["填充设置"], -156, function(self) TogglePopup(fillPopup, self) end)

    local actionDivider = actionCard:CreateTexture(nil, "ARTWORK")
    actionDivider:SetColorTexture(unpack(ExwindTools.GUIColors.sectionDivider))
    actionDivider:SetWidth(1)
    local function LayoutActionDivider(width)
        local buttonWidth = math.min(187, math.floor(width * 0.45))
        local leftEdge = 12 + 150
        local rightEdge = width - 10 - buttonWidth
        local dividerX = math.floor((leftEdge + rightEdge) / 2)
        actionDivider:ClearAllPoints()
        actionDivider:SetPoint("TOPLEFT", actionCard, "TOPLEFT", dividerX, 0)
        actionDivider:SetPoint("BOTTOMLEFT", actionCard, "BOTTOMLEFT", dividerX, 0)
    end
    LayoutActionDivider(controlWidth)

    if opts.applicationBar == true then
        -- ApplicationBar 的进度和法术图标由原生 Aura 绑定决定；这些控制项写入数据却
        -- 不会影响原生条，故不向用户显示。
        showIcon:Hide()
        iconButton:Hide()
        fillLabel:Hide()
        fillButton:Hide()
        iconPopup:Hide()
        fillPopup:Hide()
        actionCard:SetHeight(128)
    end

    RegisterCompositeControl(group, fgButton, "barColor", "color")
    RegisterCompositeControl(group, bgButton, "barBgColor", "color")
    RegisterCompositeControl(group, textureDrop, "texture", "dropdown")
    RegisterCompositeControl(group, borderTexture, "borderTexture", "dropdown")
    RegisterCompositeControl(group, borderColor, "borderColor", "color")
    RegisterCompositeControl(group, borderSize, "borderSize", "slider")
    RegisterCompositeControl(group, borderPad, "borderPadding", "slider")
    RegisterCompositeControl(group, iconSide, "iconSide", "dropdown")
    RegisterCompositeControl(group, iconOffsetX, "iconOffsetX", "slider")
    RegisterCompositeControl(group, iconWidth, "iconWidth", "slider")
    RegisterCompositeControl(group, iconHeight, "iconHeight", "slider")
    RegisterCompositeControl(group, iconOffsetY, "iconOffsetY", "slider")
    RegisterCompositeControl(group, showIconBorder, "showIconBorder", "check")
    RegisterCompositeControl(group, iconBorderTexture, "iconBorderTexture", "dropdown")
    RegisterCompositeControl(group, iconBorderColor, "iconBorderColor", "color")
    RegisterCompositeControl(group, iconBorderSize, "iconBorderSize", "slider")
    RegisterCompositeControl(group, iconBorderPad, "iconBorderPadding", "slider")
    RegisterCompositeControl(group, fillMode, "fillMode", "dropdown")
    RegisterCompositeControl(group, showIcon, "showIcon", "check")
    RegisterCompositeControl(group, showBorder, "showBorder", "check")
    group._exCompositePopups = popupList
    group._timerBarDb = proxy
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local nextControlWidth = math.min(416, math.max(364, math.floor(nextWidth * 0.40)))
        local nextMetricsWidth = nextWidth - padding * 2 - controlsGap - nextControlWidth
        local nextItemWidth = math.floor((nextMetricsWidth - gap) / 2)
        local nextCol2 = padding + nextItemWidth + gap
        local nextControlX = padding + nextMetricsWidth + controlsGap
        local nextSliderWidth = nextItemWidth - 20
        local nextColorHalfWidth = math.floor((nextItemWidth - 30) / 2)

        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, nextHeight)
        EXUI:ClearControlSurface(self)
        for _, card in ipairs({ widthCard, heightCard, xCard, yCard, colorCard, textureCard }) do card:SetSize(nextItemWidth, 60) end
        widthCard:ClearAllPoints(); widthCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row1)
        heightCard:ClearAllPoints(); heightCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row1)
        xCard:ClearAllPoints(); xCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row2)
        yCard:ClearAllPoints(); yCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row2)
        colorCard:ClearAllPoints(); colorCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row3)
        textureCard:ClearAllPoints(); textureCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row3)
        for _, entry in ipairs(self._exCompositeControls or {}) do
            if entry.kind == "slider" and entry.control:GetParent() ~= borderPopup and entry.control:GetParent() ~= iconPopup then
                entry.control:SetWidth(nextSliderWidth)
            end
        end
        fgButton:SetSize(nextColorHalfWidth, 36)
        bgButton:SetSize(nextColorHalfWidth, 36)
        bgButton:ClearAllPoints(); bgButton:SetPoint("TOPLEFT", colorCard, "TOPLEFT", 15 + nextColorHalfWidth, -22)
        textureDrop:SetWidth(nextSliderWidth)
        actionCard:ClearAllPoints(); actionCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextControlX, row1)
        actionCard:SetWidth(nextControlWidth)
        local nextActionButtonWidth = math.min(187, math.floor(nextControlWidth * 0.45))
        iconButton:SetWidth(nextActionButtonWidth); borderButton:SetWidth(nextActionButtonWidth); fillButton:SetWidth(nextActionButtonWidth)
        LayoutActionDivider(nextControlWidth)
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 19. Glow 设置组（Core 原生动画引擎）
-- 旧版 CreateGlowSettings 对应 LibCustomGlow 参数；保留别名仅作代码参考，
-- 公开入口改为 EXUI Glow 的 Pulse / Translation 线条 / Proc 三种样式。
-- =========================================================
EXUI.CreateGlowSettingsLegacy = EXUI.CreateGlowSettings

function EXUI:CreateGlowSettings(parent, width, label, db, key, onUpdate, opts)
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    key = key or "glow"

    local legacyStyles = {
        ["Action Button Glow"] = "PULSE",
        ["Pixel Glow"] = "EDGE_FLOW",
        ["Autocast Shine"] = "EDGE_FLOW",
        ["Proc Glow"] = "PROC_FLIPBOOK",
        ["Proc Alt Glow"] = "PROC_FLIPBOOK",
    }
    local function SetDefault(suffix, value)
        local field = key .. suffix
        if db[field] == nil then db[field] = value end
    end
    SetDefault("Enabled", true)
    SetDefault("Style", "EDGE_FLOW")
    SetDefault("Frequency", 1)
    SetDefault("Lines", 1)
    SetDefault("Length", 32)
    SetDefault("Thickness", 2)
    SetDefault("Direction", "CLOCKWISE")
    SetDefault("Scale", 1)
    SetDefault("Offset", 3)
    SetDefault("ColorR", 1)
    SetDefault("ColorG", 0.82)
    SetDefault("ColorB", 0.20)
    SetDefault("ColorA", 1)
    db[key .. "Style"] = legacyStyles[db[key .. "Style"]] or db[key .. "Style"]

    local groupWidth = width or 750
    local groupHeight = 250
    local group = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    group:SetSize(groupWidth, groupHeight)
    -- 标准 Slider 合同元数据：只暴露既有控件与其真实 DB 路径，
    -- 不改变视觉、写入时机或原有回调。
    group._exStandardSliderControls = {}
    group._exStandardSliderDB = db
    EXUI:ClearControlSurface(group)

    local content = CreateFrame("Frame", nil, group)
    content:SetPoint("TOPLEFT", 0, 0)
    content:SetSize(groupWidth, groupHeight)
    local padding, gap = 15, 16
    local itemWidth = math.floor((groupWidth - padding * 2 - gap * 2) / 3)
    local col1, col2, col3 = padding, padding + itemWidth + gap, padding + (itemWidth + gap) * 2

    local function EmitUpdate()
        if onUpdate then onUpdate(db) end
    end
    local function MakeSlider(text, suffix, min, max, step, x, y)
        local slider = EXUI:CreateSlider(content, itemWidth, text, min, max, db[key .. suffix], step, nil, function(value)
            db[key .. suffix] = value
            EmitUpdate()
        end)
        slider:SetPoint("TOPLEFT", x, y)
        table.insert(group._exStandardSliderControls, {
            control = slider,
            path = key .. suffix,
        })
        return slider
    end

    local enabled = EXUI:CreateCheckbox(content, L["启用发光"], db[key .. "Enabled"], function(value)
        db[key .. "Enabled"] = value
        EmitUpdate()
    end)
    enabled:SetPoint("TOPLEFT", col2, -8)
    enabled:SetSize(itemWidth, 28)

    local styles = {
        { L["呼吸发光（Alpha + Scale）"], "PULSE" },
        { L["边框线条流光（原生 Translation）"], "EDGE_FLOW" },
        { L["触发光环（原生 Proc）"], "PROC_FLIPBOOK" },
    }
    local styleDrop = EXUI:CreateDropdown(content, itemWidth, L["发光样式"], styles, db[key .. "Style"], function(value)
        db[key .. "Style"] = value
        group:RefreshLayout()
        EmitUpdate()
    end)
    styleDrop:SetPoint("TOPLEFT", col3, -14)
    local color = EXUI:CreateColorButton(content, L["发光颜色"], db, key .. "Color", true, EmitUpdate)
    color:SetPoint("TOPLEFT", col1, -14)

    local lines = MakeSlider(L["数量"], "Lines", 1, 36, 1, col1, -76)
    local length = MakeSlider(L["长度"], "Length", 8, 120, 1, col2, -76)
    local thickness = MakeSlider(L["粗度"], "Thickness", 1, 20, 0.5, col3, -76)
    local frequency = MakeSlider(L["速度"], "Frequency", 0.1, 5, 0.1, col1, -138)
    local scale = MakeSlider(L["大小倍率"], "Scale", 0.25, 3, 0.05, col2, -138)
    local offset = MakeSlider(L["间距（负值向内）"], "Offset", -20, 50, 1, col2, -138)
    local directionItems = {
        { L["顺时针"], "CLOCKWISE" },
        { L["逆时针"], "COUNTERCLOCKWISE" },
    }
    local direction = EXUI:CreateDropdown(content, itemWidth, L["方向"], directionItems, db[key .. "Direction"], function(value)
        db[key .. "Direction"] = value
        EmitUpdate()
    end)
    direction:SetPoint("TOPLEFT", col3, -144)
    local info = EXUI:CreateVisualFontString(content, EXFONTFRAME, "GameFontNormalSmall")
    info:SetPoint("TOPLEFT", col1, -204)
    info:SetPoint("TOPRIGHT", -15, -204)
    info:SetJustifyH("LEFT")
    MODERN.ApplyTextRole(info, "hint")

    function group:RefreshLayout()
        local style = db[key .. "Style"]
        local isTrail = style == "EDGE_FLOW"
        local function Place(control, shown, x, y)
            control:ClearAllPoints()
            control:SetShown(shown)
            if shown then control:SetPoint("TOPLEFT", x, y) end
        end

        -- 线条样式有线条专属参数；Pulse 与 Proc 共用速度、大小、外扩边距。
        Place(lines, isTrail, col1, -76)
        Place(length, isTrail, col2, -76)
        Place(thickness, isTrail, col3, -76)
        Place(frequency, true, col1, isTrail and -138 or -76)
        Place(scale, not isTrail, col2, -76)
        Place(offset, true, isTrail and col2 or col3, isTrail and -138 or -76)
        direction:ClearAllPoints()
        direction:SetShown(isTrail)
        if isTrail then direction:SetPoint("TOPLEFT", col3, -144) end
        if isTrail then
            info:SetText(L["数量 = 同时环绕的线条数；间距可为负，负值让线条向图标内部收。四边移动完全由原生 Translation 处理。"])
        elseif style == "PROC_FLIPBOOK" then
            info:SetText(L["使用暴雪原生 Proc FlipBook；速度同时控制起手段与循环段，大小与外扩边距控制光环范围。"])
        else
            info:SetText(L["使用 Alpha + Scale 原生循环；速度控制呼吸节奏，大小与外扩边距控制发光范围。"])
        end
    end
    group:RefreshLayout()
    group._glowDb = db
    group._exGridOwnedControls = {
        enabled, styleDrop, color, lines, length, thickness,
        frequency, scale, offset, direction,
    }
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        itemWidth = math.floor((nextWidth - padding * 2 - gap * 2) / 3)
        col1, col2, col3 = padding, padding + itemWidth + gap, padding + (itemWidth + gap) * 2
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, nextHeight)
        enabled:SetSize(itemWidth, 28)
        enabled:ClearAllPoints(); enabled:SetPoint("TOPLEFT", content, "TOPLEFT", col2, -8)
        styleDrop:SetWidth(itemWidth)
        styleDrop:ClearAllPoints(); styleDrop:SetPoint("TOPLEFT", content, "TOPLEFT", col3, -14)
        color:SetWidth(itemWidth)
        color:ClearAllPoints(); color:SetPoint("TOPLEFT", content, "TOPLEFT", col1, -14)
        for _, control in ipairs({ lines, length, thickness, frequency, scale, offset, direction }) do
            control:SetWidth(itemWidth)
        end
        self:RefreshLayout()
        EXUI:ClearControlSurface(self)
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    return group
end

-- =========================================================
-- 20. Widget 排列设置组
-- 只管理同一规则内多个 Widget 的增长方向、间距、最大显示数量与可选换行方向。
-- 整体 X/Y 属于模块 AnchorController，不能放在这里。
-- =========================================================
-- 只描述排列组的视觉字段；不参与配置构造、绑定或提交。
local function BuildWidgetLayoutSettingsFlow(width, opts)
    opts = type(opts) == "table" and opts or {}
    local fields = {
        { path = "direction", type = "dropdown", label = L["增长方向"] },
        { path = "spacing", type = "slider", label = L["间距"] },
        { path = "maxVisible", type = "slider", label = L["最大显示"] },
    }
    if opts.includeMaxPerRow ~= false then
        fields[#fields + 1] = { path = "maxPerRow", type = "slider", label = L["每行最多"] }
    end
    if opts.includeWrapDirection == true then
        fields[#fields + 1] = { path = "wrapDirection", type = "dropdown", label = L["换行方向"] }
    end
    return EXUI:BuildModuleCommonSettingsFlow(width, { presentation = "settings-list", fields = fields })
end

function EXUI:CreateWidgetLayoutGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    local allowedDirections = type(opts.allowedDirections) == "table" and opts.allowedDirections or {
        "RIGHT", "LEFT", "DOWN", "UP", "CENTER_HORIZONTAL", "CENTER_VERTICAL",
    }
    local defaultDirection = allowedDirections[1] or "RIGHT"
    local wrapDirections = type(opts.wrapDirections) == "table" and opts.wrapDirections or {
        "DOWN", "UP",
    }
    local defaultWrapDirection = tostring(opts.defaultWrapDirection or wrapDirections[1] or "DOWN")
    local maxVisibleMin = math.max(1, tonumber(opts.maxVisibleMin) or 1)
    local maxVisibleMax = math.max(maxVisibleMin, tonumber(opts.maxVisibleMax) or 40)
    local defaultMaxVisible = tonumber(opts.defaultMaxVisible) or 8
    defaultMaxVisible = math.max(maxVisibleMin, math.min(defaultMaxVisible, maxVisibleMax))
    if db.direction == nil then db.direction = defaultDirection end
    if db.spacing == nil then db.spacing = 4 end
    if db.maxVisible == nil then db.maxVisible = defaultMaxVisible end
    if db.maxPerRow == nil then db.maxPerRow = 8 end
    if db.wrapDirection == nil then db.wrapDirection = defaultWrapDirection end

    local includeMaxPerRow = opts.includeMaxPerRow ~= false
    local includeWrapDirection = opts.includeWrapDirection == true
    local groupWidth = width or 760
    local groupHeight = BuildWidgetLayoutSettingsFlow(groupWidth, opts).height
    -- 二维换行卡有额外的下拉控件，必须使用已注册的独立宿主池；
    -- 不能让它和普通单轴卡复用，也不能接受任意外部池名。
    local poolType = includeWrapDirection and "CompositeWidgetLayoutGroupWithWrap" or "CompositeWidgetLayoutGroup"
    local group, isNew = AcquireCompositeGroup(poolType, parent)
    group._exCompositeLabel = label or L["排序"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(group)
        local maxVisible = group._exWidgetLayoutMaxVisible
        if maxVisible then
            maxVisible:SetMinMaxValues(maxVisibleMin, maxVisibleMax)
            local value = tonumber(db.maxVisible) or defaultMaxVisible
            value = math.max(maxVisibleMin, math.min(value, maxVisibleMax))
            db.maxVisible = value
            maxVisible:SetValue(value)
        end
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        EXUI:ClearControlSurface(group)
        if group._exWidgetLayoutHint then group._exWidgetLayoutHint:Hide() end
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy
    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local function EmitUpdate() CompositeEmitUpdate(group) end

    -- Layout 卡片本身会从对象池复用；每次输入都必须从当前宿主读取
    -- Grid 写入上下文，不能捕获第一次（通常是 TimerBar）创建时的 moduleKey。
    local function CreateLayoutInputTransaction(field)
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateWidgetLayoutGroup requires Grid write context", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateWidgetLayoutGroup requires CreateModuleNotifyFlow", 2)
        end
        local prefix = metadata.pathPrefix
        if prefix ~= nil and type(prefix) ~= "string" then
            error("CreateWidgetLayoutGroup Grid write context pathPrefix must be string or nil", 2)
        end
        local path = type(prefix) == "string" and prefix ~= "" and (prefix .. "." .. field) or field
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = path,
            readValue = function() return group._widgetLayoutDb[field] end,
            writeValue = function(value) group._widgetLayoutDb[field] = value end,
        })
    end

    local function CommitLayoutValue(field, value)
        local transaction = CreateLayoutInputTransaction(field)
        if transaction and transaction.onCommit then return transaction.onCommit(value) end
        group._widgetLayoutDb[field] = value
        EmitUpdate()
        return true
    end

    local directionLabels = {
        RIGHT = L["向右"], LEFT = L["向左"], DOWN = L["向下"], UP = L["向上"],
        CENTER_HORIZONTAL = L["左右居中"], CENTER_VERTICAL = L["上下居中"],
    }
    local directionItems = {}
    for _, directionKey in ipairs(allowedDirections) do
        directionItems[#directionItems + 1] = { directionLabels[directionKey] or tostring(directionKey), directionKey }
    end
    local direction = EXUI:CreateDropdown(group, math.min(220, groupWidth - 40), L["增长方向"], directionItems, db.direction, function(value)
        CommitLayoutValue("direction", value)
    end)
    direction:SetPoint("TOPLEFT", 16, -42)
    RegisterCompositeControl(group, direction, "direction", "dropdown")

    local spacing = EXUI:CreateSlider(group, math.min(180, math.max(120, groupWidth * 0.24)), L["间距"], -10, 20,
        tonumber(db.spacing) or 4, 0.1, nil, CreateLayoutInputTransaction("spacing") or function(value)
            db.spacing = value
            EmitUpdate()
        end)
    spacing:SetPoint("TOPLEFT", math.min(255, groupWidth * 0.36), -46)
    RegisterCompositeControl(group, spacing, "spacing", "slider")

    local maxVisible = EXUI:CreateSlider(group, math.min(180, math.max(120, groupWidth * 0.24)), L["最大显示"], maxVisibleMin, maxVisibleMax,
        tonumber(db.maxVisible) or defaultMaxVisible, 1, nil, CreateLayoutInputTransaction("maxVisible") or function(value)
            db.maxVisible = value
            EmitUpdate()
        end)
    maxVisible:SetPoint("TOPLEFT", math.min(470, groupWidth * 0.64), -46)
    RegisterCompositeControl(group, maxVisible, "maxVisible", "slider")
    group._exWidgetLayoutMaxVisible = maxVisible

    local maxPerRow
    if includeMaxPerRow then
        maxPerRow = EXUI:CreateSlider(group, math.min(180, math.max(120, groupWidth * 0.24)), L["每行最多"], 1, 40,
            tonumber(db.maxPerRow) or 8, 1, nil, CreateLayoutInputTransaction("maxPerRow") or function(value)
                db.maxPerRow = value
                EmitUpdate()
            end)
        maxPerRow:SetPoint("TOPLEFT", 16, -92)
        RegisterCompositeControl(group, maxPerRow, "maxPerRow", "slider")
    end

    local wrapDirection
    if includeWrapDirection then
        local wrapItems = {}
        for _, directionKey in ipairs(wrapDirections) do
            wrapItems[#wrapItems + 1] = { directionLabels[directionKey] or tostring(directionKey), directionKey }
        end
        wrapDirection = EXUI:CreateDropdown(group, math.min(180, math.max(120, groupWidth * 0.24)), L["换行方向"], wrapItems,
            db.wrapDirection, function(value)
                db.wrapDirection = value
                EmitUpdate()
            end)
        wrapDirection:SetPoint("TOPLEFT", math.min(255, groupWidth * 0.36), -88)
        RegisterCompositeControl(group, wrapDirection, "wrapDirection", "dropdown")
    end

    group._widgetLayoutDb = proxy
    group._exCompositeConfigure = function(self)
        local activeOpts = self._exCompositeOpts or {}
        local activeDirections = type(activeOpts.allowedDirections) == "table" and activeOpts.allowedDirections or {
            "RIGHT", "LEFT", "DOWN", "UP", "CENTER_HORIZONTAL", "CENTER_VERTICAL",
        }
        local activeItems = {}
        for _, directionKey in ipairs(activeDirections) do
            activeItems[#activeItems + 1] = { directionLabels[directionKey] or tostring(directionKey), directionKey }
        end
        direction._items = activeItems
        direction._currentValue = self._widgetLayoutDb.direction
        direction._onSelect = function(value) CommitLayoutValue("direction", value) end
        SetDropdownDisplayText(direction, CompositeDropdownText(direction._currentValue, activeItems) or L["请选择..."])

        local function RebindSlider(control, field)
            -- SetLifecycleCallbacks only replaces onValueChanged when given a
            -- function, so explicitly clear the fallback callback from a
            -- possible no-context first creation.
            control._onValueChanged = nil
            control:SetLifecycleCallbacks(CreateLayoutInputTransaction(field) or {})
        end
        RebindSlider(spacing, "spacing")
        RebindSlider(maxVisible, "maxVisible")
        if maxPerRow then RebindSlider(maxPerRow, "maxPerRow") end
    end
    group:_exCompositeConfigure()
    local settingsControls = {
        direction = direction, spacing = spacing, maxVisible = maxVisible,
        maxPerRow = maxPerRow, wrapDirection = wrapDirection,
    }
    local settingsRows = {}
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local flow = BuildWidgetLayoutSettingsFlow(nextWidth, self._exCompositeOpts)
        self._exGridFixedHeight = flow.height
        self:SetHeight(flow.height)
        EXUI:ClearControlSurface(self)
        for _, row in pairs(settingsRows) do row:Hide() end
        for _, control in pairs(settingsControls) do control:Hide() end
        for index, entry in ipairs(flow.entries) do
            local field = entry.field
            local control = settingsControls[field.path]
            if control then
                local row = settingsRows[field.path]
                if not row then
                    row = EXUI:CreateSettingsRow(self, { label = field.label, controlKind = "ordinary" })
                    settingsRows[field.path] = row
                end
                row._exSettingsRowIsLast = index == #flow.entries
                row:Show()
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, entry.y)
                EXUI:PrepareSettingsListControl(control, {
                    hideLabel = true, ordinaryControl = true,
                    valuePosition = field.type == "slider" and "right" or nil,
                })
                local _, x, y, controlWidth = EXUI:UpdateSettingsRowLayout(row, entry.width, entry.controlHeight)
                control:SetWidth(controlWidth)
                EXUI:UpdateSettingsListControlLayout(control, controlWidth)
                control:ClearAllPoints()
                control:SetPoint("TOPLEFT", self, "TOPLEFT", x,
                    entry.y - y - math.max(0, (entry.controlHeight - control:GetHeight()) * 0.5))
                control:Show()
            end
        end
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 模块通用设置组；纯布局 BuildModuleCommonSettingsFlow 位于 SettingsList 文件。
-- =========================================================
function EXUI:CreateModuleCommonSettingsGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and opts.bindRoot ~= true and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    local groupWidth = width or 760
    local flow = self:BuildModuleCommonSettingsFlow(groupWidth, opts)
    local groupHeight = flow.height
    local group, isNew = AcquireCompositeGroup(opts.poolType or "CompositeModuleCommonSettingsGroup", parent)
    EXUI:ClearControlSurface(group)
    group._exCompositeLabel = label or L["模块通用设置"]
    -- modulecommonsettings 的 fields 是模块声明的动态结构，不能像字体/计时条/图标
    -- 等固定结构组那样整树复用。先归还上一轮的子控件，再按本轮 fields 建立；外壳
    -- 仍是 CompositeHost 池，标准 checkbox/dropdown/slider/input/color 仍各自回到既有池。
    if not isNew and group._exClearModuleCommonEntries then
        group:_exClearModuleCommonEntries()
    end
    BindCompositeGroup(group, db, onUpdate, opts)
    group._moduleCommonDb = db
    -- Grid 容器可能在同一帧被其他页面激活；页面需要能把实际显示的宿主
    -- 明确重绑回本次渲染的模块 DB，不能依赖对象池残留引用。
    group.RebindDB = function(self, nextDB)
        if type(nextDB) ~= "table" then return false end
        BindCompositeGroup(self, nextDB, self._exCompositeOnUpdate, self._exCompositeOpts)
        self._moduleCommonDb = nextDB
        return true
    end
    if not isNew then
        group:_exBuildModuleCommonEntries(flow)
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        return group
    end

    group:SetSize(groupWidth, groupHeight)

    local content = CreateFrame("Frame", nil, group)
    content:SetPoint("TOPLEFT", 0, 0)
    local settingsCard = CreateFrame("Frame", nil, content)

    local function EmitUpdate() CompositeEmitUpdate(group) end
    -- Root-bound ModuleCommon cards have no group prefix.  Their Checkbox /
    -- Dropdown / Input controls still need a real leaf path; forwarding the
    -- empty group path makes NotifyModuleValueChanged reject the change.
    local function NotifyModuleCommonField(path)
        local metadata = group._exCompositeOpts and group._exCompositeOpts._exWriteContext
        if metadata == nil then return false end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateModuleCommonSettingsGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix
        if prefix ~= nil and type(prefix) ~= "string" then
            error("CreateModuleCommonSettingsGroup Grid write context pathPrefix must be string or nil", 2)
        end
        local fullPath = type(prefix) == "string" and prefix ~= "" and (prefix .. "." .. path) or path
        EXUI:NotifyModuleValueChanged(metadata.moduleKey, fullPath, "committed")
        return true
    end
    local function SetValue(path, value, phase)
        CompositePathSet(group._exCompositeDb, path, value)
        -- 外部 DatabaseChanged 监听负责运行时同步；页面自己的预览则不应依赖那条
        -- 异步链。允许宿主在“字段已写入同一份 DB”的瞬间直接重套预览样式。
        if phase ~= "live" and type(group._exCompositeOpts.onFieldChanged) == "function" then
            group._exCompositeOpts.onFieldChanged(group._exCompositeDb, path, value)
        end
        if phase ~= "live" and not NotifyModuleCommonField(path) then EmitUpdate() end
    end

    -- ModuleCommonSettings 的连续 Slider 通过唯一 ModuleDB 通知流重套表面。
    local function CreateModuleCommonNotifyFlow(path)
        local metadata = group._exCompositeOpts and group._exCompositeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateModuleCommonSettingsGroup requires Grid write context", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateModuleCommonSettingsGroup requires CreateModuleNotifyFlow", 2)
        end
        local prefix = metadata.pathPrefix
        if prefix ~= nil and type(prefix) ~= "string" then
            error("CreateModuleCommonSettingsGroup Grid write context pathPrefix must be string or nil", 2)
        end
        local fullPath = type(prefix) == "string" and prefix ~= "" and (prefix .. "." .. path) or path
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = fullPath,
            readValue = function() return CompositePathValue(group._exCompositeDb, path) end,
            -- Core controller owns the only commit refresh.  live writes must
            -- not broadcast DatabaseChanged or rebuild this page.
            writeValue = function(value) SetValue(path, value, "live") end,
        })
    end

    group._exClearModuleCommonEntries = function(self)
        local factory = _G.ExwindFactory
        for _, mounted in ipairs(self._exModuleCommonEntries or {}) do
            local control = mounted.control
            if control then EXUI:RestoreSettingsListControl(control) end
            if mounted.row and mounted.row.Release then mounted.row:Release() end
            if control and control._fromPool and factory then
                factory:Release(control._fromPool, control)
            elseif control then
                control:Hide()
                control:ClearAllPoints()
            end
            if mounted.card then
                mounted.card:Hide()
                mounted.card:ClearAllPoints()
            end
        end
        self._exModuleCommonEntries = {}
        self._exCompositeControls = {}
    end

    group._exBuildModuleCommonEntries = function(self, nextFlow)
        local activeFields = nextFlow.fields or {}
        local activeDb = self._exCompositeDb or {}
        self._exModuleCommonEntries = {}
        self._exModuleCommonCards = self._exModuleCommonCards or {}
        for index, field in ipairs(activeFields) do
            local path = tostring(field.path or field.key or "")
            if path ~= "" or field.type == "button" then
                local flowEntry = nextFlow.entries[index]
                local value = CompositePathValue(activeDb, path)
            local control, kind = nil, nil
            -- 保留每个控件的独立承载 Frame（下拉/对象池会依赖它的局部父级），
            -- 但取消背景与边框：视觉上只保留模块通用设置的外层卡片，不再出现小方格。
            local card = self._exModuleCommonCards[index]
            if not card then
                card = CreateFrame("Frame", nil, settingsCard, "BackdropTemplate")
                self._exModuleCommonCards[index] = card
                card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                card:SetBackdropColor(0, 0, 0, 0)
                card:SetBackdropBorderColor(0, 0, 0, 0)
            end
            card:SetParent(settingsCard)
            card:Show()
            card:SetSize(flowEntry.width, flowEntry.height)
            card:SetPoint("TOPLEFT", flowEntry.x, flowEntry.y)
            local row
            if nextFlow.settingsList then
                row = EXUI:CreateSettingsRow(card, {
                    label = field.label or field.path or field.key,
                    description = field.description,
                    controlWidth = field.controlWidth,
                    controlKind = IsModuleCommonOrdinaryField(field) and "ordinary" or nil,
                    inputWidthPercent = field.inputWidthPercent,
                    isLast = index == #activeFields,
                })
            end
            if field.type == "button" then
                control = EXUI:CreateButton(card, flowEntry.width - 20, 28, field.label or path, function()
                    local structureResult
                    if type(field.onClick) == "function" then
                        structureResult = field.onClick(self._exCompositeDb)
                    end
                    CompositeEmitUpdate(self)
                    if type(self._exCompositeOpts.onStructureChanged) == "function" then
                        self._exCompositeOpts.onStructureChanged(structureResult)
                    end
                end, { variant = field.variant })
                control:SetPoint("TOPLEFT", 10, -16)
                kind = "button"
            elseif field.type == "checkbox" then
                control = EXUI:CreateCheckbox(card, field.label or path, value == true, function(v) self._exModuleCommonSetValue(path, v == true) end)
                control:SetPoint("TOPLEFT", 10, -11)
                kind = "check"
            elseif field.type == "dropdown" then
                control = EXUI:CreateDropdown(card, flowEntry.width - 20, field.label or path, field.items or {}, value, function(v) self._exModuleCommonSetValue(path, v) end)
                control:SetPoint("TOPLEFT", 10, -25)
                kind = "dropdown"
            elseif field.type == "lsm_background" or field.type == "lsm_border" or field.type == "lsm_texture" then
                local mediaType = field.type == "lsm_background" and "background"
                    or (field.type == "lsm_border" and "border" or "statusbar")
                control = EXUI:CreateLSMTextureDropdown(card, mediaType, flowEntry.width - 20, field.label or path, value, function(v)
                    self._exModuleCommonSetValue(path, v)
                end)
                control:SetPoint("TOPLEFT", 10, -25)
                kind = "dropdown"
            elseif field.type == "input" then
                control = EXUI:CreateEditBox(card, tostring(value or ""), flowEntry.width - 20, 28, field.label or path, {
                    labelPos = "top",
                    onEnter = function(v) SetValue(path, v or "") end,
                    onEditFocusLost = function(v) SetValue(path, v or "") end,
                })
                control:SetPoint("TOPLEFT", 10, -16)
                kind = "edit"
            elseif field.type == "color" then
                -- 颜色值仍按现有 R/G/B/A 字段保存；仅由通用封装组承载，
                -- 不让模块退回为四个散装滑动条。
                local colorDB, colorKey = self._exCompositeDb, path
                local colorParentPath, directColorKey = path:match("^(.*)%.([^%.]+)$")
                if colorParentPath and directColorKey then
                    local target = self._exCompositeDb
                    for part in string.gmatch(colorParentPath, "[^%.]+") do
                        target[part] = type(target[part]) == "table" and target[part] or {}
                        target = target[part]
                    end
                    colorDB, colorKey = target, directColorKey
                end
                control = EXUI:CreateColorButton(card, field.label or path, colorDB, colorKey, true, function()
                    if type(self._exCompositeOpts.onFieldChanged) == "function" then
                        self._exCompositeOpts.onFieldChanged(self._exCompositeDb, path)
                    end
                    if not NotifyModuleCommonField(path) then CompositeEmitUpdate(self) end
                end)
                control:SetPoint("TOPLEFT", 10, -14)
                kind = "color"
            else
                local lifecycle = CreateModuleCommonNotifyFlow(path)
                if lifecycle then
                    control = EXUI:CreateSlider(card, flowEntry.width - 20, field.label or path,
                        tonumber(field.min) or 0, tonumber(field.max) or 100, tonumber(value) or tonumber(field.min) or 0,
                        tonumber(field.step) or 1, nil, lifecycle)
                else
                    control = EXUI:CreateSlider(card, flowEntry.width - 20, field.label or path,
                        tonumber(field.min) or 0, tonumber(field.max) or 100, tonumber(value) or tonumber(field.min) or 0,
                        tonumber(field.step) or 1, nil, function(v) self._exModuleCommonSetValue(path, v) end)
                end
                control:SetPoint("TOPLEFT", 10, -8)
                kind = "slider"
            end
            if field.type ~= "button" then
                RegisterCompositeControl(self, control, path, kind)
            end
                if row and control then
                    EXUI:PrepareSettingsListControl(control, {
                        hideLabel = true,
                        presentation = field.presentation or ((self._exCompositeOpts
                            and self._exCompositeOpts._exTypedSettings == true
                            and field.type == "checkbox") and "switch" or nil),
                        ordinaryControl = IsModuleCommonOrdinaryField(field),
                        valuePosition = field.type == "slider" and (field.valuePosition or "right") or nil,
                    })
                end
                self._exModuleCommonEntries[index] = {
                    card = card, control = control, kind = kind, field = field, row = row,
                }
            end
        end
    end
    group._exModuleCommonSetValue = SetValue
    group:_exBuildModuleCommonEntries(flow)

    group._exApplyModuleCommonFlow = function(self, nextFlow)
        self._exModuleCommonFlow = nextFlow
        -- 只有在线编辑器新增的空背景卡片允许其 layout.h 控制高度。其余
        -- ModuleCommon 仍由真实 fields Flow 固定高度，避免正式页面产生空白或裁切。
        if self._exCompositeOpts and self._exCompositeOpts.gridEditableHeight == true then
            self._exGridFixedHeight = nil
        else
            self._exGridFixedHeight = nextFlow.height
        end
        self:SetSize(nextFlow.width, nextFlow.height)
        EXUI:ClearControlSurface(self)
        local cardInsetX = tonumber(nextFlow.cardInsetX)
        if cardInsetX == nil then cardInsetX = nextFlow.padding or 0 end
        local cardInsetY = tonumber(nextFlow.cardInsetY) or 8
        local cardBottomInset = tonumber(nextFlow.cardBottomInset) or cardInsetY
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", 0, 0)
        content:SetSize(nextFlow.width, math.max(1, nextFlow.height))
        settingsCard:ClearAllPoints()
        settingsCard:SetPoint("TOPLEFT", content, "TOPLEFT", cardInsetX, -cardInsetY)
        local cardHeight = tonumber(nextFlow.cardHeight)
            or math.max(1, nextFlow.height - cardInsetY - cardBottomInset)
        settingsCard:SetSize(nextFlow.width - cardInsetX * 2, cardHeight)
        if nextFlow.settingsList then
            settingsCard:SetSize(nextFlow.width, nextFlow.height)
            for index, entry in ipairs(nextFlow.entries) do
                local mounted = self._exModuleCommonEntries[index]
                if mounted then
                    local rowHeight, controlX, controlY, controlWidth = EXUI:UpdateSettingsRowLayout(
                        mounted.row, entry.width, entry.controlHeight)
                    mounted.card:ClearAllPoints()
                    mounted.card:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", 0, entry.y)
                    mounted.card:SetSize(entry.width, rowHeight)
                    mounted.row:ClearAllPoints()
                    mounted.row:SetPoint("TOPLEFT", mounted.card, "TOPLEFT", 0, 0)
                    local control = mounted.control
                    if control then
                        if control.SetWidth then control:SetWidth(controlWidth) end
                        EXUI:UpdateSettingsListControlLayout(control, controlWidth)
                        control:ClearAllPoints()
                        local actualHeight = control.GetHeight and control:GetHeight() or entry.controlHeight
                        local visualInset = math.max(0, (entry.controlHeight - actualHeight) * 0.5)
                        control:SetPoint("TOPLEFT", mounted.card, "TOPLEFT", controlX, -(controlY + visualInset))
                    end
                end
            end
            return
        end
        for index, entry in ipairs(nextFlow.entries) do
            local mounted = self._exModuleCommonEntries[index]
            if mounted then
                mounted.card:ClearAllPoints()
                mounted.card:SetPoint("TOPLEFT", settingsCard, "TOPLEFT",
                    entry.x - (nextFlow.entryOriginX or nextFlow.padding or 0), entry.y + nextFlow.contentTopInset)
                mounted.card:SetSize(entry.width, entry.height)
                local control = mounted.control
                if control then
                    if control.SetWidth then control:SetWidth(math.max(1, entry.width - 20)) end
                    control:ClearAllPoints()
                    if mounted.kind == "button" or mounted.kind == "edit" then
                        control:SetPoint("TOPLEFT", 10, -16)
                    elseif mounted.kind == "check" then
                        control:SetPoint("TOPLEFT", 10, -11)
                    elseif mounted.kind == "color" then
                        control:SetPoint("TOPLEFT", 10, -14)
                    else
                        control:SetPoint("TOPLEFT", 10, -25)
                    end
                end
            end
        end
    end
    group._exCompositeReflow = function(self, nextWidth)
        self:_exApplyModuleCommonFlow(EXUI:BuildModuleCommonSettingsFlow(nextWidth, self._exCompositeOpts))
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)

    group.RefreshFromDB = function(self)
        BindCompositeGroup(self, self._exCompositeDb, self._exCompositeOnUpdate, self._exCompositeOpts)
    end
    AttachCompositeRelease(group)
    return group
end

-- Aura Application Bar 是独立原生 Region：它只接收 maxApplications，
-- 不能借用普通计时条的 duration/fill/icon 设置，避免产生“能改但不会生效”的假控件。
-- Aura Duration Bar 同样是 AuraButton Adapter 绑定的原生 Region，而不是
-- TimerBarWidget。它故意不暴露图标、图标边框、填充模式等 TimerBar 专属字段：
-- 这些 Region 在原生 Aura Duration Bar 中不存在，暴露它们就是假 GUI。
function EXUI:CreateAuraDurationBarGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    local fields = {
        { path = "enabled", type = "checkbox", label = L["启用计时条"] },
        { path = "texture", type = "input", label = L["条体材质"] },
        { path = "width", type = "slider", label = L["宽度"], min = 1, max = 800, step = 1 },
        { path = "height", type = "slider", label = L["高度"], min = 1, max = 120, step = 1 },
        { path = "x", type = "slider", label = L["X 偏移"], min = -1000, max = 1000, step = 1 },
        { path = "y", type = "slider", label = L["Y 偏移"], min = -1000, max = 1000, step = 1 },
        { path = "barColor", type = "color", label = L["前景颜色"] },
        { path = "barBgColor", type = "color", label = L["背景颜色"] },
        { path = "showBorder", type = "checkbox", label = L["显示边框"] },
        { path = "borderTexture", type = "input", label = L["边框材质"] },
        { path = "borderSize", type = "slider", label = L["边框粗细"], min = 0.1, max = 16, step = 0.1 },
        { path = "borderPadding", type = "slider", label = L["边框内距"], min = -32, max = 32, step = 1 },
        { path = "borderColor", type = "color", label = L["边框颜色"] },
    }
    if opts.forceEnabled and type(db) == "table" then
        local targetKey = key or "durationBar"
        db[targetKey] = type(db[targetKey]) == "table" and db[targetKey] or {}
        db[targetKey].enabled = true
        table.remove(fields, 1)
    end
    return self:CreateModuleCommonSettingsGroup(parent, width, label or L["计时条（原生 Aura Duration Bar）"], db, key or "durationBar", onUpdate, {
        columns = 3,
        poolType = opts.forceEnabled and "CompositeAuraDurationBarMainGroup" or "CompositeAuraDurationBarGroup",
        fields = fields,
    })
end

function EXUI:CreateAuraApplicationBarGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    local fields = {
        { path = "enabled", type = "checkbox", label = L["启用层数条"] },
            { path = "maxApplications", type = "slider", label = L["最大层数"], min = 1, max = 99, step = 1 },
            { path = "texture", type = "input", label = L["条体材质"] },
            { path = "width", type = "slider", label = L["宽度"], min = 1, max = 800, step = 1 },
            { path = "height", type = "slider", label = L["高度"], min = 1, max = 120, step = 1 },
            { path = "x", type = "slider", label = L["X 偏移"], min = -1000, max = 1000, step = 1 },
            { path = "y", type = "slider", label = L["Y 偏移"], min = -1000, max = 1000, step = 1 },
            { path = "barColor", type = "color", label = L["前景颜色"] },
            { path = "barBgColor", type = "color", label = L["背景颜色"] },
    }
    if opts.forceEnabled and type(db) == "table" then
        local targetKey = key or "applicationBar"
        db[targetKey] = type(db[targetKey]) == "table" and db[targetKey] or {}
        db[targetKey].enabled = true
        table.remove(fields, 1)
    end
    return self:CreateModuleCommonSettingsGroup(parent, width, label or L["层数条（原生 Aura Application Bar）"], db, key or "applicationBar", onUpdate, {
        columns = 3,
        poolType = opts.forceEnabled and "CompositeAuraApplicationBarMainGroup" or "CompositeAuraApplicationBarGroup",
        fields = fields,
    })
end

-- =========================================================
-- 20.1 通用锚点设置组
-- 只管理 DB 字段与页面操作；实际 Frame 创建、拖动与依附仍由 AnchorController 负责。
-- =========================================================
function EXUI:CreateAnchorGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}

    local xKey = opts.offsetXKey or "x"
    local yKey = opts.offsetYKey or "y"
    local attachKey = opts.attachEnabledKey or "attachToCustom"
    local targetKey = opts.attachTargetKey or "customAttachTarget"
    local supportsCustomAttach = opts.allowCustomAttach ~= false
    local defaultX = tonumber(opts.defaultOffsetX) or 0
    local defaultY = tonumber(opts.defaultOffsetY) or 0
    local groupWidth = width or 760
    local groupHeight = 52

    if db[xKey] == nil then db[xKey] = defaultX end
    if db[yKey] == nil then db[yKey] = defaultY end
    if supportsCustomAttach and db[attachKey] == nil then db[attachKey] = false end
    if supportsCustomAttach and db[targetKey] == nil then db[targetKey] = "" end

    local group, isNew = AcquireCompositeGroup("CompositeAnchorGroup", parent)
    group._exCompositeLabel = label or L["锚点设置"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        EXUI:ClearControlSurface(group)
        if group._exAnchorRefresh then group:_exAnchorRefresh() end
        return group
    end

    local proxy = CreateCompositeProxy(group)
    db = proxy
    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local function EmitUpdate() CompositeEmitUpdate(group) end
    -- 锚点是否启用只控制是否跟随目标；X/Y 仍是模块自身的控件配置，不能在此覆盖。
    -- 输入框与选择器常驻，方便先填路径再启用，不因勾选状态造成控件跳动。
    local attach, target, picker
    if supportsCustomAttach then
        attach = EXUI:CreateCheckbox(group, L["启用"], db[attachKey] == true, function(value)
            db[attachKey] = value == true
            EmitUpdate()
        end)
        attach:SetPoint("TOPLEFT", 16, -15)
        RegisterCompositeControl(group, attach, attachKey, "check")

        local targetWidth = math.max(180, groupWidth - 330)
        target = EXUI:CreateEditBox(group, tostring(db[targetKey] or ""), targetWidth, 28, nil, {
            onEnter = function(value) db[targetKey] = value or ""; EmitUpdate() end,
            onEditFocusLost = function(value) db[targetKey] = value or ""; EmitUpdate() end,
        })
        target:SetPoint("TOPLEFT", 142, -10)
        RegisterCompositeControl(group, target, targetKey, "edit")

        picker = EXUI:CreateButton(group, 108, 28, L["选择框架"], function()
            if type(group._exCompositeOpts.onPickFrame) == "function" then
                group._exCompositeOpts.onPickFrame(group._exCompositeDb)
            end
        end)
        picker:SetPoint("TOPRIGHT", -16, -10)
        picker:SetShown(type(opts.onPickFrame) == "function")
    end

    group._anchorDb = proxy
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        EXUI:ClearControlSurface(self)
        if not supportsCustomAttach then return end
        local nextTargetWidth = math.max(180, nextWidth - 330)
        target:SetWidth(nextTargetWidth)
        attach:ClearAllPoints(); attach:SetPoint("LEFT", self, "LEFT", 16, 0)
        target:ClearAllPoints(); target:SetPoint("LEFT", self, "LEFT", 142, 0)
        picker:ClearAllPoints(); picker:SetPoint("RIGHT", self, "RIGHT", -16, 0)
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 21. 通用材质设置组
-- 用于普通 / Aura 显示的静态材质外观；宿主决定数据来源与生命周期。
-- =========================================================
function EXUI:CreateTextureGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    local defaults = {
        fileID = "", width = 128, height = 128, x = 0, y = 0,
        alpha = 1, scale = 1, rotation = 0, flipH = false, flipV = false,
        colorR = 1, colorG = 1, colorB = 1, colorA = 1, blendMode = "BLEND",
    }
    for field, value in pairs(defaults) do
        if db[field] == nil then db[field] = value end
    end

    local groupWidth = width or 760
    local group, isNew = AcquireCompositeGroup("CompositeTextureGroup", parent)
    group._exCompositeLabel = label or L["材质"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, 250)
        if group._exTextureConfigure then group:_exTextureConfigure() end
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy
    group:SetSize(groupWidth, 250)
    group:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    group:SetBackdropColor(unpack(MC.panel))
    group:SetBackdropBorderColor(unpack(MC.border))

    local accent = EXUI:CreateVisualTexture(group, EXBASEFRAME)
    accent:SetPoint("TOPLEFT", 7, -11)
    accent:SetSize(3, 20)
    accent:SetColorTexture(unpack(MC.blue))
    local title = EXUI:CreateVisualFontString(group, EXFONTFRAME, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -8)
    title:SetText(group._exCompositeLabel)
    StyleModernTitle(title)
    group._exCompositeTitle = title

    local function EmitUpdate() CompositeEmitUpdate(group) end
    local function AddSlider(field, titleText, minValue, maxValue, step, x, y, controlWidth)
        local slider = EXUI:CreateSlider(group, controlWidth or 170, titleText, minValue, maxValue, db[field], step, nil,
            function(value)
                db[field] = value
                EmitUpdate()
            end)
        slider:SetPoint("TOPLEFT", x, y)
        return RegisterCompositeControl(group, slider, field, "slider")
    end

    local fileInput = EXUI:CreateEditBox(group, tostring(db.fileID or ""), math.min(310, groupWidth - 48), 28,
        L["FileDataID / 路径"], {
            onEnter = function(value)
                db.fileID = tostring(value or "")
                EmitUpdate()
            end,
            onEditFocusLost = function(value)
                db.fileID = tostring(value or "")
                EmitUpdate()
            end,
            labelPos = "top",
        })
    fileInput:SetPoint("TOPLEFT", 16, -54)
    RegisterCompositeControl(group, fileInput, "fileID", "edit")

    -- 选择器是材质组件本身的可选能力。模块只能提供“如何挑选”的
    -- 回调，不能在自己的 Editor 里再创建/定位一枚私有按钮；这样池化
    -- 后也始终读取本次绑定的 DB 与回调。
    local texturePicker = EXUI:CreateButton(group, 108, 28, opts.pickerLabel or L["选择材质"], function()
        local activeOpts = group._exCompositeOpts or {}
        if type(activeOpts.onPickTexture) ~= "function" then return end
        activeOpts.onPickTexture(group._exCompositeDb and group._exCompositeDb.fileID, function(textureID)
            if type(group._exCompositeDb) ~= "table" then return end
            group._exCompositeDb.fileID = tostring(textureID or "")
            EXUI:RefreshCompositeGroupFromDB(group)
            CompositeEmitUpdate(group)
        end)
    end)
    texturePicker:SetPoint("TOPRIGHT", -16, -54)
    group._exTexturePickerButton = texturePicker
    group._exTextureConfigure = function(self)
        local activeOpts = self._exCompositeOpts or {}
        local picker = self._exTexturePickerButton
        if not picker then return end
        if picker.SetText then picker:SetText(activeOpts.pickerLabel or L["选择材质"]) end
        picker:SetShown(type(activeOpts.onPickTexture) == "function")
    end
    group:_exTextureConfigure()

    local widthSlider = AddSlider("width", L["宽度"], 1, 1024, 1, 16, -116)
    local heightSlider = AddSlider("height", L["高度"], 1, 1024, 1, 204, -116)
    local xSlider = AddSlider("x", L["X 偏移"], -1000, 1000, 1, 392, -116)
    local ySlider = AddSlider("y", L["Y 偏移"], -1000, 1000, 1, 580, -116)
    local alphaSlider = AddSlider("alpha", L["透明度"], 0, 1, 0.05, 16, -176)
    local scaleSlider = AddSlider("scale", L["缩放"], 0.05, 5, 0.05, 204, -176)
    local rotationSlider = AddSlider("rotation", L["旋转"], -180, 180, 1, 392, -176)

    local color = EXUI:CreateColorButton(group, L["材质颜色"], db, "color", true, EmitUpdate)
    color:SetPoint("TOPLEFT", 580, -164)
    RegisterCompositeControl(group, color, "", "color")
    local blend = EXUI:CreateDropdown(group, math.min(220, groupWidth - 48), L["混合模式"], {
        { "BLEND", "BLEND" }, { "ADD", "ADD" }, { "MOD", "MOD" },
        { "ALPHAKEY", "ALPHAKEY" }, { "DISABLE", "DISABLE" },
    }, db.blendMode, function(value)
        db.blendMode = value
        EmitUpdate()
    end)
    blend:SetPoint("TOPLEFT", 16, -226)
    RegisterCompositeControl(group, blend, "blendMode", "dropdown")

    local flipH = EXUI:CreateCheckbox(group, L["水平翻转"], db.flipH, function(value)
        db.flipH = value
        EmitUpdate()
    end)
    flipH:SetPoint("TOPLEFT", 254, -222)
    RegisterCompositeControl(group, flipH, "flipH", "check")
    local flipV = EXUI:CreateCheckbox(group, L["垂直翻转"], db.flipV, function(value)
        db.flipV = value
        EmitUpdate()
    end)
    flipV:SetPoint("TOPLEFT", 394, -222)
    RegisterCompositeControl(group, flipV, "flipV", "check")
    group._textureDb = proxy
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local columnWidth = math.max(120, math.floor((nextWidth - 68) / 4))
        local col1 = 16
        local col2 = col1 + columnWidth + 18
        local col3 = col2 + columnWidth + 18
        local col4 = col3 + columnWidth + 18
        local fileWidth = math.min(310, math.max(160, nextWidth - 48))
        fileInput:SetWidth(fileWidth)
        texturePicker:ClearAllPoints(); texturePicker:SetPoint("TOPRIGHT", self, "TOPRIGHT", -16, -54)
        local top = { widthSlider, heightSlider, xSlider, ySlider }
        local topX = { col1, col2, col3, col4 }
        for index, slider in ipairs(top) do
            slider:SetWidth(columnWidth)
            slider:ClearAllPoints(); slider:SetPoint("TOPLEFT", self, "TOPLEFT", topX[index], -116)
        end
        for index, slider in ipairs({ alphaSlider, scaleSlider, rotationSlider }) do
            slider:SetWidth(columnWidth)
            slider:ClearAllPoints(); slider:SetPoint("TOPLEFT", self, "TOPLEFT", topX[index], -176)
        end
        color:ClearAllPoints(); color:SetPoint("TOPLEFT", self, "TOPLEFT", col4, -164)
        blend:SetWidth(math.min(220, math.max(120, nextWidth - 48)))
        flipH:ClearAllPoints(); flipH:SetPoint("TOPLEFT", self, "TOPLEFT", col2 + 50, -222)
        flipV:ClearAllPoints(); flipV:SetPoint("TOPLEFT", self, "TOPLEFT", col3 + 2, -222)
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, 250)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 21.1 Aura 语义设置组
-- EXAura 只声明它要使用哪一种能力；控件树、对象池重绑与释放全部归 EXUI。
-- =========================================================
function EXUI:CreateAuraDispelBorderGroup(parent, width, label, db, key, onUpdate)
    return self:CreateModuleCommonSettingsGroup(parent, width, label or L["驱散边框"], db, key or "auraBorder", onUpdate, {
        columns = 3,
        poolType = "CompositeAuraDispelBorderGroup",
        fields = {
            { path = "enabled", type = "checkbox", label = L["启用驱散边框"] },
            { path = "showIcon", type = "checkbox", label = L["驱散边框带图标"] },
            { path = "style", type = "dropdown", label = L["驱散边框样式"], items = { { "Atlas", 0 }, { "Color", 1 } } },
        },
    })
end

function EXUI:CreateAuraSortGroup(parent, width, label, db, key, onUpdate)
    return self:CreateModuleCommonSettingsGroup(parent, width, label or L["Aura 内容排序"], db, key or "sort", onUpdate, {
        columns = 2,
        poolType = "CompositeAuraSortGroup",
        fields = {
            { path = "method", type = "dropdown", label = L["排序方式"], items = {
                { "默认", 0 }, { L["大减伤"], 1 }, { L["单位框减益"], 2 }, { L["仅重要"], 3 }, { L["到期"], 4 },
                { L["仅按到期"], 5 }, { L["名称"], 6 }, { L["仅按名称"], 7 }, { L["Aura 实例 ID"], 8 },
            } },
            { path = "direction", type = "dropdown", label = L["排序方向"], items = { { L["正常"], 0 }, { L["反向"], 1 } } },
        },
        onFieldChanged = function(target, path, value)
            if path == "method" or path == "direction" then target[path] = tonumber(value) or 0 end
        end,
    })
end

-- 这是 Aura 子元素的唯一结构性编辑器。它与 FontGroup/通用字段组一样
-- 由 Composite Host 管理，借用、重绑、释放不会把上一个规则的回调遗留在页面上。
function EXUI:CreateAuraChildElementsGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    local target = db
    if key and type(target) == "table" then
        target[key] = type(target[key]) == "table" and target[key] or {}
        target = target[key]
    end
    target = type(target) == "table" and target or {}
    target.children = type(target.children) == "table" and target.children or {}

    local function NewChild(kind)
        if kind == "glow" then
            return { type = "glow", enabled = true, glowStyle = "Action Button Glow", glowColorR = 1, glowColorG = 1, glowColorB = 1, glowColorA = 1, glowOffset = 0, glowFrequency = 1, glowScale = 1 }
        end
        return { type = "text", enabled = true, text = L["文本"], font = "默认", size = 14, r = 1, g = 1, b = 1, a = 1, outline = "OUTLINE", shadow = false, x = 0, y = 0, justifyH = "CENTER", justifyV = "MIDDLE" }
    end
    local fields = {
        { type = "button", label = L["+ 文本"], onClick = function(activeTarget)
            activeTarget.children = type(activeTarget.children) == "table" and activeTarget.children or {}
            activeTarget.children[#activeTarget.children + 1] = NewChild("text")
            return #activeTarget.children
        end },
        { type = "button", label = L["+ 发光"], onClick = function(activeTarget)
            activeTarget.children = type(activeTarget.children) == "table" and activeTarget.children or {}
            activeTarget.children[#activeTarget.children + 1] = NewChild("glow")
            return #activeTarget.children
        end },
    }
    for index, child in ipairs(target.children) do
        local prefix = "children." .. tostring(index)
        fields[#fields + 1] = { path = prefix .. ".enabled", type = "checkbox", label = (child.type == "glow" and L["发光"] or L["文本"]) .. L[" 子元素 "] .. tostring(index) .. L[" · 启用"] }
        fields[#fields + 1] = { type = "button", variant = "danger", label = L["删除 子元素 "] .. tostring(index), onClick = function(activeTarget)
            if type(activeTarget.children) == "table" then table.remove(activeTarget.children, index) end
        end }
        if child.type == "glow" then
            fields[#fields + 1] = { path = prefix .. ".glowStyle", type = "dropdown", label = L["发光 "] .. tostring(index) .. L[" · 样式"], items = { { L["动作条发光"], "Action Button Glow" }, { L["Proc 发光"], "Proc Alt Glow" } } }
            fields[#fields + 1] = { path = prefix .. ".glowColor", type = "color", label = L["发光 "] .. tostring(index) .. L[" · 颜色"] }
            fields[#fields + 1] = { path = prefix .. ".glowFrequency", type = "slider", label = L["发光 "] .. tostring(index) .. L[" · 频率"], min = 0.1, max = 5, step = 0.1 }
            fields[#fields + 1] = { path = prefix .. ".glowScale", type = "slider", label = L["发光 "] .. tostring(index) .. L[" · 大小"], min = 0.5, max = 3, step = 0.1 }
            fields[#fields + 1] = { path = prefix .. ".glowOffset", type = "slider", label = L["发光 "] .. tostring(index) .. L[" · 边距"], min = -50, max = 50, step = 1 }
        else
            -- 子元素必须仍是这一个 Composite Host 的字段，而不是 Editor 再在
            -- 外面拼一组 FontGroup。结构变化由 onStructureChanged 请求整页
            -- 重渲染；每一次渲染都只有一个可测量、可回收的根。
            fields[#fields + 1] = { path = prefix .. ".text", type = "input", label = L["文本 "] .. tostring(index) .. L[" · 示例"] }
            fields[#fields + 1] = { path = prefix .. ".font", type = "input", label = L["文本 "] .. tostring(index) .. L[" · 字体"] }
            fields[#fields + 1] = { path = prefix .. ".size", type = "slider", label = L["文本 "] .. tostring(index) .. L[" · 大小"], min = 6, max = 72, step = 1 }
            fields[#fields + 1] = { path = prefix .. ".color", type = "color", label = L["文本 "] .. tostring(index) .. L[" · 颜色"] }
            fields[#fields + 1] = { path = prefix .. ".x", type = "slider", label = L["文本 "] .. tostring(index) .. L[" · X 偏移"], min = -1000, max = 1000, step = 1 }
            fields[#fields + 1] = { path = prefix .. ".y", type = "slider", label = L["文本 "] .. tostring(index) .. L[" · Y 偏移"], min = -1000, max = 1000, step = 1 }
        end
    end
    -- 每一种子元素序列各有稳定的池键；同一种结构复用时只 Rebind，
    -- 增删元素后则借用匹配新字段数的宿主，绝不让旧字段树伪装成新结构。
    local signature = {}
    for _, child in ipairs(target.children) do signature[#signature + 1] = child.type == "glow" and "g" or "t" end
    local manager = self:CreateModuleCommonSettingsGroup(parent, width, label or L["子元素"], target, nil, onUpdate, {
        columns = 2,
        poolType = "CompositeAuraChildElementsGroup_" .. table.concat(signature, ""),
        fields = fields,
        onStructureChanged = opts.onStructureChanged,
    })
    return manager
end

-- 标准组合控件的无副作用 Grid 测量。数值与各 Create*Group 的实际 SetSize
-- 完全一致；将来修改控件高度时，必须同时改这里或改成共享常量，不能让 schema
-- 猜测内部控件树的高度。
local function FixedGridMeasure(height)
    return function()
        return { minHeight = height, preferredHeight = height }
    end
end

EXUI:RegisterGridComponentMeasure("slider", FixedGridMeasure(EXUI.GridSliderHeight))
EXUI:RegisterGridComponentMeasure("fontgroup", function(width)
    local height = ResolveFontGroupHeight(width)
    return { minHeight = height, preferredHeight = height }
end)
EXUI:RegisterGridComponentMeasure("icongroup", function(width)
    local narrow = (tonumber(width) or 750) < 720
    local height = narrow and 296 or 150
    return { minHeight = height, preferredHeight = height }
end)
EXUI:RegisterGridComponentMeasure("timerbargroup", FixedGridMeasure(204))
EXUI:RegisterGridComponentMeasure("texturegroup", FixedGridMeasure(250))
EXUI:RegisterGridComponentMeasure("anchorgroup", FixedGridMeasure(52))
EXUI:RegisterGridComponentMeasure("glow_settings", FixedGridMeasure(250))
EXUI:RegisterGridComponentMeasure("soundgroup", function(width, opts)
    local height = EXUI:BuildSoundGroupLayout(width, opts).height
    return { minHeight = height, preferredHeight = height }
end)
EXUI:RegisterGridComponentMeasure("widgetlayout", function(width, opts)
    local height = BuildWidgetLayoutSettingsFlow(width, opts).height
    return { minHeight = height, preferredHeight = height }
end)
EXUI:RegisterGridComponentMeasure("modulecommonsettings", function(width, opts)
    local flow = EXUI:BuildModuleCommonSettingsFlow(width, opts)
    return { minHeight = flow.height, preferredHeight = flow.height }
end)
-- Aura 专用语义组同样是标准 Composite Host；高度只从同一 Flow 合同推导。
-- 页面 schema 不得复制字段数或手写像素高度。
local function AuraMeasureFields(count)
    local fields = {}
    for index = 1, count do fields[index] = { path = "field" .. tostring(index), type = "slider" } end
    return fields
end
local function AuraFlowMeasure(countResolver)
    return function(width, _, db, item)
        return EXUI:BuildModuleCommonSettingsFlow(width, { fields = AuraMeasureFields(countResolver(db, item)), maxColumns = 4 })
    end
end
EXUI:RegisterGridComponentMeasure("auradurationbargroup", AuraFlowMeasure(function() return 13 end))
EXUI:RegisterGridComponentMeasure("auraapplicationbargroup", AuraFlowMeasure(function() return 9 end))
EXUI:RegisterGridComponentMeasure("auradispelbordergroup", AuraFlowMeasure(function() return 3 end))
EXUI:RegisterGridComponentMeasure("aurasortgroup", AuraFlowMeasure(function() return 2 end))
EXUI:RegisterGridComponentMeasure("aurachildelementsgroup", AuraFlowMeasure(function(db, item)
    local source = type(db) == "table" and db or {}
    local target = item and item.key and type(source[item.key]) == "table" and source[item.key] or source
    local count = 2 -- add text / add glow
    for _, child in ipairs(type(target.children) == "table" and target.children or {}) do
        count = count + 2 + (child.type == "glow" and 5 or 6)
    end
    return count
end))

