-- =========================================================
-- ExwindGrid.lua - 可视化网格布局引擎 (v4.2 增强版)
-- =========================================================

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

if not ExwindTools then
    error(L["[ExwindGrid] 错误: ExwindTools.lua 必须在 ExwindGrid.lua 之前加载!"])
end

-- 确保 EXUI 命名空间存在（可能在 ExwindToolsUI.lua 之前加载）
local EXUI = ExwindTools.UI or {}
ExwindTools.UI = EXUI

local Grid = {
    Cols = 50,
    CellSize = 0,
    Padding = 2,
    ActiveLayout = {},
    Widgets = {},
    CustomRenderers = {},
    ExportReferences = setmetatable({}, { __mode = "k" }),
    IsLiveEditing = false,
    ContainerCols = setmetatable({}, { __mode = "k" }),
    ContainerPadding = setmetatable({}, { __mode = "k" }),
    ContainerStates = setmetatable({}, { __mode = "k" }),
    CardSessions = setmetatable({}, { __mode = "k" }),
    CardSessionOwners = setmetatable({}, { __mode = "k" }),
    CardScrollSessions = setmetatable({}, { __mode = "k" }),
    CardBodyOnlyComponents = {
        fontgroup = true,
        icongroup = true,
        soundgroup = true,
        timerbargroup = true,
        widgetlayout = true,
        modulecommonsettings = true,
        anchorgroup = true,
        glow_settings = true,
    },
    EditorGridLinesByContainer = setmetatable({}, { __mode = "k" }),
    EditorRowGuidesByContainer = setmetatable({}, { __mode = "k" }),
    _effectiveCols = 50,
}

-- 挂载到多个位置方便访问
ExwindTools.Grid = Grid
EXUI.Grid = Grid
_G.ExwindGrid = Grid

local function NormalizeCols(cols)
    local n = tonumber(cols)
    if not n then return nil end
    n = math.floor(n)
    if n < 10 then n = 10 end
    if n > 200 then n = 200 end
    return n
end

local function GetContainerState(self, container)
    if not container then return nil end
    local state = self.ContainerStates[container]
    if not state then
        state = {
            widgets = {},
            instances = {},
            widgetMap = {},
            layout = nil,
            config = nil,
            moduleKey = nil,
        }
        self.ContainerStates[container] = state
    end
    return state
end

local function ActivateContainerState(self, container, state)
    if not container or not state then return end
    self._activeContainer = container
    self.Widgets = state.widgets
    self.WidgetInstances = state.instances
    self.WidgetMap = state.widgetMap
    self.ActiveLayout = state.layout or {}
    self.LastConfig = state.config
    self.ModuleKey = state.moduleKey
end

local function WalkLayoutItems(items, callback)
    for _, item in ipairs(items or {}) do
        callback(item)
        if type(item.children) == "table" then WalkLayoutItems(item.children, callback) end
    end
end

local function GetExportSession(grid)
    local container = grid and (grid.LiveEditContainer or grid.LiveContainer)
    local state = container and grid.ContainerStates[container]
    return state and state.exportSession or nil
end

-- 在线编辑器看到的是测量后的工作布局，不能把它整表当成源码 GUI 导出。
-- 会话开始时只给现有项分配稳定标识；后续只记录用户真正改过的字段。
function Grid:BeginModuleSpecExportSession(container)
    local state = GetContainerState(self, container)
    if not state then return end
    local session = { nextID = 0, baseline = {}, changes = {}, added = {}, addedOrder = {}, deleted = {} }
    WalkLayoutItems(state.layout, function(item)
        session.nextID = session.nextID + 1
        local id = "existing:" .. session.nextID
        item._exGridExportID = id
        session.baseline[id] = {
            sourceKey = item.key,
            declaredY = tonumber(item._declaredY) or tonumber(item.y) or 1,
            renderedY = tonumber(item.y) or 1,
            declaredH = tonumber(item._declaredH) or tonumber(item.h) or 1,
            renderedH = tonumber(item.h) or 1,
        }
    end)
    state.exportSession = session
end

function Grid:RecordModuleSpecLayoutChange(item, changes)
    if type(item) ~= "table" or type(changes) ~= "table" then return end

    -- Card 编辑器操作的是测量后的 Body 工作副本。把允许编辑的字段同步回
    -- session.declaration 内对应的纯声明 item；否则下一次 Card reflow 会从
    -- 原声明重建并吞掉用户刚完成的拖动/改名/缩放。
    local cardSource = item._exCardSourceItem
    if type(cardSource) == "table" then
        for field, value in pairs(changes) do
            if field == "y" and type(value) == "number" then
                value = math.max(1, math.floor(value
                    + (tonumber(item._declaredY) or tonumber(cardSource.y) or 1)
                    - (tonumber(item._exCardRenderedY) or tonumber(item.y) or 1)))
            elseif field == "h" and type(value) == "number" then
                value = math.max(1, math.floor(value
                    + (tonumber(item._declaredH) or tonumber(cardSource.h) or 1)
                    - (tonumber(item._exCardRenderedH) or tonumber(item.h) or 1)))
            end
            cardSource[field] = value
        end
        return
    end

    local session, id = GetExportSession(self), item._exGridExportID
    local baseline = session and id and session.baseline[id]
    if not baseline then return end
    local target = session.changes[id] or {}
    for field, value in pairs(changes) do
        if field == "y" and type(value) == "number" then
            value = math.max(1, math.floor(value + baseline.declaredY - baseline.renderedY))
        elseif field == "h" and type(value) == "number" then
            value = math.max(1, math.floor(value + baseline.declaredH - baseline.renderedH))
        end
        target[field] = value
    end
    session.changes[id] = target
end

function Grid:RecordModuleSpecLayoutAddition(item)
    if type(item) ~= "table" then return end
    local session = GetExportSession(self)
    if not session then return end
    session.nextID = session.nextID + 1
    local id = "added:" .. session.nextID
    item._exGridExportID = id
    session.added[id] = true
    session.addedOrder[#session.addedOrder + 1] = id
end

function Grid:RecordModuleSpecLayoutDeletion(item)
    if type(item) ~= "table" then return end
    local session, id = GetExportSession(self), item._exGridExportID
    if session and id then session.deleted[id] = true end
end

-- 编辑覆盖层不能作为卡片子 Frame：Unified Shell 的内容 host 与卡片不在同一
-- 层级树中，低层 GridCard 的子 Frame 无法越过 Shell 内容层接收鼠标。覆盖层
-- 必须作为当前 Grid 容器的 sibling，并在卡片回池前显式解除临时交互状态。
local function ReleaseEditOverlay(widget)
    local overlay = widget and widget.dragOverlay
    if not overlay then return end

    overlay:SetScript("OnUpdate", nil)
    overlay:SetScript("OnMouseDown", nil)
    overlay:SetScript("OnMouseUp", nil)
    overlay.isResizing = nil
    overlay:Hide()
    overlay:ClearAllPoints()

    if overlay.resizer then
        overlay.resizer:SetScript("OnUpdate", nil)
        overlay.resizer:SetScript("OnMouseDown", nil)
        overlay.resizer:SetScript("OnMouseUp", nil)
        overlay.resizer:Hide()
    end

    -- 卡片仍是覆盖层的持久 owner；下一次进入编辑模式会重新挂到目标 container。
    overlay:SetParent(widget)
end

-- 普通 GridCard 的 backdrop 属于卡片本体。卡片内容若由更高 frame level 的
-- sibling 渲染（例如 virtual list），会局部盖住 backdrop 的细边框。需要完整
-- 外框的卡片可通过 keepBorderVisible 启用这个无背景轮廓层。
local function ReleaseCardOutline(widget)
    local outline = widget and widget._gridCardOutline
    if not outline then return end
    outline:Hide()
    outline:ClearAllPoints()
    outline:SetParent(nil)
end

-- Grid 只承载设置页的静态 GUI。cellSize 来自容器宽度 / 列数，通常是浮点数；
-- 若最后仍以普通 SetPoint/SetSize 落地，输入框、按钮、卡片边框与分隔线会落在
-- 半个物理像素上。不要把这套修正扩散到 runtime renderer：这里只对 Grid widget
-- 的最终宿主 Frame 生效。
local function SetPhysicalPoint(region, point, relativeTo, relativePoint, x, y)
    local PixelUtil = _G.PixelUtil
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(region, point, relativeTo, relativePoint, x or 0, y or 0, 0, 0)
    else
        region:SetPoint(point, relativeTo, relativePoint, x or 0, y or 0)
    end
end

local function SetPhysicalSize(region, width, height)
    local PixelUtil = _G.PixelUtil
    if PixelUtil and PixelUtil.SetSize then
        PixelUtil.SetSize(region, width, height, 1, 1)
    else
        region:SetSize(width, height)
    end
end

local function SetPhysicalLineThickness(line)
    if not line then return end
    local PixelUtil = _G.PixelUtil
    if line.SetThickness then
        local scale = line:GetEffectiveScale() or 1
        local thickness = PixelUtil and PixelUtil.GetNearestPixelSize
            and PixelUtil.GetNearestPixelSize(1, scale, 1) or 1
        line:SetThickness(thickness)
    elseif line.SetHeight then
        if PixelUtil and PixelUtil.SetHeight then
            PixelUtil.SetHeight(line, 1, 1)
        else
            line:SetHeight(1)
        end
    end
end

local function RefreshCardOutlineGeometry(outline)
    if not outline then return end

    SetPhysicalLineThickness(outline.top)
    outline.top:ClearAllPoints()
    SetPhysicalPoint(outline.top, "TOPLEFT", outline, "TOPLEFT", 0, 0)
    SetPhysicalPoint(outline.top, "TOPRIGHT", outline, "TOPRIGHT", 0, 0)

    local PixelUtil = _G.PixelUtil
    if PixelUtil and PixelUtil.SetWidth then
        PixelUtil.SetWidth(outline.right, 1, 1)
    else
        outline.right:SetWidth(1)
    end
    outline.right:ClearAllPoints()
    SetPhysicalPoint(outline.right, "TOPRIGHT", outline, "TOPRIGHT", 0, 0)
    SetPhysicalPoint(outline.right, "BOTTOMRIGHT", outline, "BOTTOMRIGHT", 0, 0)

    SetPhysicalLineThickness(outline.bottom)
    outline.bottom:ClearAllPoints()
    SetPhysicalPoint(outline.bottom, "BOTTOMLEFT", outline, "BOTTOMLEFT", 0, 0)
    SetPhysicalPoint(outline.bottom, "BOTTOMRIGHT", outline, "BOTTOMRIGHT", 0, 0)

    if PixelUtil and PixelUtil.SetWidth then
        PixelUtil.SetWidth(outline.left, 1, 1)
    else
        outline.left:SetWidth(1)
    end
    outline.left:ClearAllPoints()
    SetPhysicalPoint(outline.left, "TOPLEFT", outline, "TOPLEFT", 0, 0)
    SetPhysicalPoint(outline.left, "BOTTOMLEFT", outline, "BOTTOMLEFT", 0, 0)
end

local function EnsureCardOutline(widget, container, color)
    if not (widget and container) then return end
    local outline = widget._gridCardOutline
    if not outline then
        outline = CreateFrame("Frame", nil, container)
        outline:EnableMouse(false)
        outline.top = EXUI:CreateVisualTexture(outline, EXBORDERFRAME)
        outline.right = EXUI:CreateVisualTexture(outline, EXBORDERFRAME)
        outline.bottom = EXUI:CreateVisualTexture(outline, EXBORDERFRAME)
        outline.left = EXUI:CreateVisualTexture(outline, EXBORDERFRAME)
        outline.top:SetPoint("TOPLEFT")
        outline.top:SetPoint("TOPRIGHT")
        outline.top:SetHeight(1)
        outline.right:SetPoint("TOPRIGHT")
        outline.right:SetPoint("BOTTOMRIGHT")
        outline.right:SetWidth(1)
        outline.bottom:SetPoint("BOTTOMLEFT")
        outline.bottom:SetPoint("BOTTOMRIGHT")
        outline.bottom:SetHeight(1)
        outline.left:SetPoint("TOPLEFT")
        outline.left:SetPoint("BOTTOMLEFT")
        outline.left:SetWidth(1)
        widget._gridCardOutline = outline
    end

    outline:SetParent(container)
    outline:SetFrameStrata(container:GetFrameStrata() or "LOW")
    outline:SetFrameLevel((container:GetFrameLevel() or 1) + 30)
    outline:ClearAllPoints()
    outline:SetAllPoints(widget)
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    outline.top:SetColorTexture(r, g, b, a)
    outline.right:SetColorTexture(r, g, b, a)
    outline.bottom:SetColorTexture(r, g, b, a)
    outline.left:SetColorTexture(r, g, b, a)

    -- 参考 Blizzard NamePlateBorderTemplateMixin：1px 边线的锚点和厚度
    -- 都经 PixelUtil 量化，避免 UI Scale / 非整数 Grid Cell 使纹理落在半像素。
    RefreshCardOutlineGeometry(outline)
    outline:Show()
end

function Grid:SetContainerCols(container, cols)
    if not container then return false end
    local n = NormalizeCols(cols)
    if not n then
        self.ContainerCols[container] = nil
        return false
    end
    self.ContainerCols[container] = n
    return true
end

function Grid:ClearContainerCols(container)
    if not container then return end
    self.ContainerCols[container] = nil
end

function Grid:GetContainerCols(container)
    if not container then return nil end
    return self.ContainerCols[container]
end

function Grid:SetContainerPadding(container, padding)
    if not container then return false end
    if type(padding) ~= "table" then
        self.ContainerPadding[container] = nil
        return false
    end
    self.ContainerPadding[container] = {
        left = tonumber(padding.left) or 10,
        right = tonumber(padding.right) or 10,
        top = tonumber(padding.top) or 10,
        bottom = tonumber(padding.bottom) or 0,
    }
    return true
end

function Grid:ClearContainerPadding(container)
    if not container then return end
    self.ContainerPadding[container] = nil
end

function Grid:GetContainerPadding(container)
    if not container then
        return { left = 10, right = 10, top = 10, bottom = 0 }
    end
    return self.ContainerPadding[container] or { left = 10, right = 10, top = 10, bottom = 0 }
end

function Grid:UpdateMetrics(containerWidth, container)
    local cols = self:GetContainerCols(container) or self.Cols
    local padding = self:GetContainerPadding(container)
    self._effectiveCols = cols
    self.CellSize = (containerWidth - padding.left - padding.right) / cols
end

function Grid:GetPixelRect(x, y, w, h, container)
    local padding = self:GetContainerPadding(container or self._activeContainer)
    local px = (x - 1) * self.CellSize + padding.left
    local py = -(y - 1) * self.CellSize - padding.top
    local pw = w * self.CellSize - self.Padding
    local ph = (h or 2) * self.CellSize - self.Padding
    return px, py, pw, ph
end

-- 这是 Grid 唯一的最终布局落点。所有由 Grid 承载的都是设置页静态 GUI；
-- 不在这里出现 runtime 条、图标或文字 renderer。用 PixelUtil 同时量化位置和尺寸，
-- 避免只量化 1px 线却仍把其父 Frame 放在半像素上的伪修复。
function Grid:ApplyPixelLayout(widget, container, element)
    if not (widget and container and element) then return end

    local px, py, pw, ph = self:GetPixelRect(element.x, element.y, element.w, element.h, container)
    local width = widget._exGridWidth or pw
    local height = widget._exGridFixedHeight or widget._exGridCardMeasuredHeight or ph

    -- CreateButton 已按共享主题钳制普通文字按钮；Grid 是最终尺寸落点，不能再
    -- 用声明格尺寸把它缩回主题下限以下。compact 必须由调用方显式声明，不能
    -- 根据窄宽度猜测，否则普通按钮会绕过统一语义。
    if element.type == "button" and widget._exButtonCompact ~= true then
        local theme = EXUI and EXUI.ModernTheme
        local style = theme and theme.buttonStyle
        local metrics = theme and theme.metrics
        local minimumWidth = style and tonumber(style.minWidth)
        local paddingY = style and tonumber(style.paddingY)
        local textHeight = metrics and tonumber(metrics.button)
        if minimumWidth then width = math.max(width, minimumWidth) end
        if paddingY and textHeight then
            height = math.max(height, textHeight + paddingY * 2)
        end
    end

    widget:ClearAllPoints()
    SetPhysicalPoint(widget, "TOPLEFT", container, "TOPLEFT", px, py)
    SetPhysicalSize(widget, width, height)

    -- Factory 创建的 Header/Divider 分别使用 Texture / SimpleLine；两者都以
    -- 同一个真实物理像素为粗细，且在每次最终布局时重套。
    if element.type == "divider" then
        if widget.separator then
            if _G.PixelUtil and _G.PixelUtil.SetHeight then
                _G.PixelUtil.SetHeight(widget.separator, 1, 1)
            else
                widget.separator:SetHeight(1)
            end
        else
            SetPhysicalLineThickness(widget.line)
        end
    elseif element.type == "header" then
        SetPhysicalLineThickness(widget.Line)
    end
    RefreshCardOutlineGeometry(widget._gridCardOutline)
end

function Grid:RefreshPixelLayout(container)
    local state = self.ContainerStates[container]
    if not (container and state and state.instances) then return end
    if container._exGridPixelLayoutBusy then return end
    if not container.GetWidth or container:GetWidth() <= 0 then return end

    container._exGridPixelLayoutBusy = true
    -- Grid 的 metrics 是历史共享字段。临时切到目标容器计算后必须还原，不能把
    -- 当前编辑容器的 metrics 偷换为另一个已显示页面的 metrics。
    local previousCellSize, previousCols = self.CellSize, self._effectiveCols
    self:UpdateMetrics(container:GetWidth(), container)

    for _, widget in ipairs(state.instances) do
        local element = widget and widget._exGridPixelElement
        if element and widget.GetParent and widget:GetParent() == container then
            self:ApplyPixelLayout(widget, container, element)
        end
    end

    self.CellSize, self._effectiveCols = previousCellSize, previousCols
    container._exGridPixelLayoutBusy = nil
end

function Grid:EnsurePixelLayoutHooks(container)
    if not container or container._exGridPixelLayoutHooksInstalled then return end
    container._exGridPixelLayoutHooksInstalled = true

    container:HookScript("OnShow", function(host)
        if not Grid:RequestReflow(host) then
            Grid:RefreshPixelLayout(host)
        end
    end)
    container:HookScript("OnSizeChanged", function(host)
        if not Grid:RequestReflow(host) then
            Grid:RefreshPixelLayout(host)
        end
    end)

    if not self._pixelLayoutWatcher then
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("UI_SCALE_CHANGED")
        watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
        watcher:SetScript("OnEvent", function()
            for host in pairs(Grid.ContainerStates) do
                if host and host.IsShown and host:IsShown() then
                    if not Grid:RequestReflow(host) then
                        Grid:RefreshPixelLayout(host)
                    end
                end
            end
        end)
        self._pixelLayoutWatcher = watcher
    end
end

function Grid:GetGridPos(lx, ly, container)
    local padding = self:GetContainerPadding(container or self._activeContainer)
    local gx = math.floor((lx - (padding.left * 0.5)) / self.CellSize) + 1
    local gy = math.floor((math.abs(ly) - (padding.top * 0.5)) / self.CellSize) + 1
    local cols = self._effectiveCols or self.Cols
    return math.max(1, math.min(gx, cols)), math.max(1, gy)
end

function Grid:RegisterCustomRenderer(key, renderer)
    if type(key) ~= "string" or key == "" then
        return false
    end
    if type(renderer) ~= "table" then
        return false
    end
    self.CustomRenderers[key] = renderer
    return true
end

function Grid:GetCustomRenderer(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end
    return self.CustomRenderers[key]
end

function Grid:ReleaseWidgetInstance(widget)
    if not widget then
        return
    end
    ReleaseEditOverlay(widget)
    ReleaseCardOutline(widget)
    local renderer = widget._customRenderer
    local rendererReleaseReason
    if renderer and type(renderer.release) == "function" then
        local released, reason = pcall(renderer.release, widget, widget._customContext)
        if not released then rendererReleaseReason = reason end
    end
    widget._customRenderer = nil
    widget._customRendererKey = nil
    widget._customContext = nil
    widget._exGridCardMeasuredHeight = nil
    local EXFactory = _G.ExwindFactory
    -- A few historical composite shells (the two GlowSettings definitions)
    -- are intentionally not pooled, but their standard child controls are.
    -- Return those children first; the shell then follows Release's existing
    -- _fromPool == nil path and is hidden/detached without inventing a pool.
    if EXFactory and widget._exGridOwnedControls then
        for index = #widget._exGridOwnedControls, 1, -1 do
            local control = widget._exGridOwnedControls[index]
            if control then EXFactory:ReleaseGridWidget(control) end
            widget._exGridOwnedControls[index] = nil
        end
        widget._exGridOwnedControls = nil
    end
    -- 组合控件宿主由其构造器登记清理函数。必须优先走这里，先断开子控件
    -- 回调/DB 引用，再归还外层宿主；不能把带旧闭包的控件直接塞回通用池。
    if EXFactory and widget._isCompositeHost then
        EXFactory:ReleaseCompositeHost(widget)
        if rendererReleaseReason then error(rendererReleaseReason, 0) end
        return
    end
    if EXFactory and widget._gridType then
        EXFactory:ReleaseGridWidget(widget)
    else
        widget:Hide()
        widget:SetParent(nil)
    end
    if rendererReleaseReason then error(rendererReleaseReason, 0) end
end

-- 布局导出无法从运行时 table 反查其 Lua 局部变量名。模块可显式登记规格表
-- 对应的源码表达式，使 ExportLayout 输出 `opts = MODULE_OPTIONS`，而不是静默丢失
-- 含函数的 opts 配置。
function Grid:RegisterExportReference(value, expression)
    if type(value) ~= "table" or type(expression) ~= "string" or expression == "" then
        return false
    end
    self.ExportReferences[value] = expression
    return true
end

-- 控件查找索引（Widgets）允许同一 key 被后续控件覆盖；生命周期不能依赖它。
-- 所有实际创建的实例均记录在 instances，按 AceGUI 的 children 模式逐个归还。
function Grid:ReleaseContainerWidgets(container)
    local state = GetContainerState(self, container)
    if not state then
        return false
    end
    local instances = state.instances or {}
    local released = {}
    local firstReleaseReason
    for i = #instances, 1, -1 do
        local widget = instances[i]
        instances[i] = nil
        if widget and not released[widget] then
            released[widget] = true
            local ok, reason = pcall(self.ReleaseWidgetInstance, self, widget)
            if not ok and firstReleaseReason == nil then firstReleaseReason = reason end
        end
    end
    table.wipe(state.widgets)
    table.wipe(state.widgetMap)
    if firstReleaseReason ~= nil then error(firstReleaseReason, 0) end
    return true
end

-- 模块通过标准预览 intent 写入自己的同一份 DB 后，页面需要让正在显示的
-- 组合控件立刻回读该 DB。Card root 先分发到各 Body，Body/旧 flat container
-- 仍只调 EXUI 的公开组合控件回刷入口；Grid 不解释模块字段、预览元素或路径。
function Grid:RefreshContainerControlsFromDB(container)
    local cardSession = self.CardSessions and self.CardSessions[container] or nil
    if cardSession and not cardSession.released then
        return cardSession:RefreshValues()
    end
    local state = GetContainerState(self, container)
    if not state then return false end
    local refreshed = false
    local ui = ExwindTools.UI
    for _, widget in ipairs(state.instances or {}) do
        refreshed = ui:RefreshCompositeGroupFromDB(widget) or refreshed
    end
    return refreshed
end

function Grid:AcquireCompositeHost(compositeType, parent)
    local EXFactory = _G.ExwindFactory
    local poolType = EXFactory and EXFactory.CompositePoolMap and EXFactory.CompositePoolMap[compositeType]
    if not poolType then
        return nil, false
    end
    return EXFactory:AcquireCompositeHost(poolType, parent)
end

function Grid:AttachCompositeRelease(host, releaseFn)
    local EXFactory = _G.ExwindFactory
    if not EXFactory then
        return false
    end
    return EXFactory:AttachPoolRelease(host, releaseFn)
end

local function ItemAllowsOverlap(item)
    return type(item) == "table" and (item.allowOverlap == true or item.type == "card")
end

function Grid:IsAreaEmpty(x, y, w, h, excludeKey, layout)
    -- [v2.0] 支持传入指定的 layout 子集（用于 TableGroup 内部排版检测）
    -- 但由于 v2.0 采用绝对坐标，其实还是应该检测全局
    -- 只是为了编辑器逻辑，可能需要调整
    local targetLayout = layout or self.ActiveLayout

    local function findByKey(items, key)
        if not key then return nil end
        for _, item in ipairs(items or {}) do
            if item.key == key then
                return item
            end
            if item.children then
                local found = findByKey(item.children, key)
                if found then
                    return found
                end
            end
        end
        return nil
    end

    local excludeItem = findByKey(targetLayout, excludeKey)
    if ItemAllowsOverlap(excludeItem) then
        return true
    end

    -- 递归检查函数
    local function checkRecursive(items)
        for _, item in ipairs(items) do
            if item.key ~= excludeKey and not ItemAllowsOverlap(item) then
                -- 核心：所有组件在运行时都使用绝对坐标 (item.x, item.y)
                -- 所以直接比较坐标即可，无需关心层级
                if not (x + w <= item.x or x >= item.x + item.w or
                        y + (h or 2) <= item.y or y >= item.y + (item.h or 2)) then
                    return false
                end

                -- 如果是 TableGroup，递归检查其子元素
                if item.children then
                    if not checkRecursive(item.children) then return false end
                end
            end
        end
        return true
    end

    if layout then
        -- 如果指定了子集，只检查子集（通常用于局部重排）
        return checkRecursive(layout)
    else
        -- 默认检查全局所有元素
        return checkRecursive(self.ActiveLayout)
    end
end

-- [Core] 提前声明 Helper，供 ValidateContext 调用
local function GetConfigPath(config, path)
    if not config or not path then return config end
    local keys = { strsplit(".", path) }
    local curr = config
    for i = 1, #keys do
        local k = tonumber(keys[i]) or keys[i]
        if type(curr) ~= "table" then return nil end
        curr = curr[k]
    end
    return curr
end

-- [v2.0 New] 数据有效性验证
function Grid:ValidateContext(config, contextPath)
    if not contextPath or contextPath == "" then return true end
    local data = GetConfigPath(config, contextPath)
    return (data ~= nil)
end

-- [v2.0 New] 递归渲染核心
function Grid:RenderItems(container, items, contextPath, config, moduleKey)
    for _, item in ipairs(items) do
        -- 1. 计算当前组件的绝对数据路径 (Scoped Context)
        local currentPath = contextPath
        if item.parentKey then
            if currentPath then
                currentPath = currentPath .. "." .. item.parentKey
            else
                currentPath = item.parentKey
            end
        end

        -- 2. 数据有效性熔断保护
        -- 如果当前路径无效（例如 rows.5 已被删除），则跳过渲染或回退
        if currentPath and not self:ValidateContext(config, currentPath) then

        else
            if item.type == "TableGroup" then
                -- [逻辑容器模式]
                -- Header/Label 渲染 (如果有)
                if item.label then
                    -- TableGroup 自身作为一个 Label/Header 组件存在
                    self:CreateWidget(container, item, config, moduleKey, currentPath)
                end

                -- 递归渲染子元素
                -- 关键：container 保持不变 (MainFrame)，传递新的 ContextPath
                if item.children then
                    self:RenderItems(container, item.children, currentPath, config, moduleKey)
                end
            else
                -- [普通组件]
                -- 使用计算好的 Absolute Path 进行数据绑定
                -- 传递 currentPath 给 CreateWidget，它将用作 fullKey
                self:CreateWidget(container, item, config, moduleKey, currentPath)
            end
        end

        -- 在协程内每处理完一个 item 就 yield，让 LibAsync 分帧执行
        if coroutine.running() then
            coroutine.yield()
        end
    end
end

-- 组件可在 schema 上声明 `measure`：
--   true       使用 EXUI 已登记的标准组件测量器；
--   function   measure(pixelWidth, opts, scopedDB, item) -> height 或高度表；
--   table      { minHeight = n, preferredHeight = n }。
-- 这是创建 Frame 前的纯合同，禁止依赖屏幕扫描、OnUpdate 或延迟布局。测量到的
-- h 仅作用于本次渲染副本，布局声明本身仍是唯一的 x/y/w/h 真源。
local function NormalizeMeasuredHeight(measurement)
    if type(measurement) == "number" then
        return measurement
    end
    if type(measurement) ~= "table" then return nil end
    local preferred = tonumber(measurement.preferredHeight or measurement.height)
    local minimum = tonumber(measurement.minHeight)
    if preferred and minimum then return math.max(preferred, minimum) end
    return preferred or minimum
end

local function GetMeasureResult(grid, item, pixelWidth, scopedDB)
    local declaration = item.measure
    if type(declaration) == "function" then
        return declaration(pixelWidth, item.opts or {}, scopedDB, item)
    end
    if type(declaration) == "table" then
        return declaration
    end
    if declaration ~= true then return nil end

    if item.type == "custom" then
        local renderer = grid:GetCustomRenderer(item.renderer or item.customType or item.widgetType)
        if renderer and type(renderer.measure) == "function" then
            return renderer.measure(pixelWidth, item.opts or {}, scopedDB, item)
        end
    end
    if EXUI and type(EXUI.MeasureGridComponent) == "function" then
        return EXUI:MeasureGridComponent(item.type, pixelWidth, item.opts or {}, scopedDB, item)
    end
    return nil
end

local function CopyMeasuredItems(grid, container, sourceItems, config, contextPath)
    local measured, shift = {}, 0
    for _, source in ipairs(sourceItems or {}) do
        local item = {}
        for key, value in pairs(source) do item[key] = value end

        local currentPath = contextPath
        if item.parentKey then
            currentPath = currentPath and (currentPath .. "." .. item.parentKey) or item.parentKey
        end
        local scopedDB = currentPath and GetConfigPath(config, currentPath) or config
        local isEditorModuleCommonCard = item.type == "modulecommonsettings"
            and type(item.key) == "string"
            and item.key:match("^modulecommonsettings_%d+$") ~= nil

        -- 旧会话里已经创建的在线编辑器卡片仍带有旧的 measure=true；在渲染
        -- 副本上收窄移除，让它和新的自由背景卡片一样保留手动 h。
        if isEditorModuleCommonCard then item.measure = false end

        -- modulecommonsettings 早已有动态高度行为；迁到同一公开 measure 合同，
        -- 保持全宽模块卡片的既有紧凑 Flow，而其他历史控件不会因本改动改变。
        if item.measure == nil
            and item.type == "modulecommonsettings"
            and type(item.opts) == "table"
            and (tonumber(item.w) or 0) == grid._effectiveCols then
            item.measure = true
        end

        -- Slider 的共享封装拥有固定的“标题/数值 header row + 下方轨道”高度。
        -- 默认用同一 measure 合同扩展逻辑占位，避免旧 h=2 声明让下一项压住轨道；
        -- 明确 measure=false 的在线编辑布局仍可保留人工高度。
        if item.measure == nil and item.type == "slider" then
            item.measure = true
        end

        if item.y then
            local declaredY = tonumber(source.y) or 1
            item._declaredY = declaredY
            item.y = math.max(1, declaredY - shift)
        end

        local oldHeight = math.max(1, tonumber(source.h) or 2)
        local _, _, pixelWidth = grid:GetPixelRect(item.x, item.y, item.w, item.h, container)
        local pixelHeight = NormalizeMeasuredHeight(GetMeasureResult(grid, item, pixelWidth, scopedDB))
        if pixelHeight and pixelHeight > 0 and grid.CellSize > 0 then
            local measuredHeight = math.max(1, math.ceil((pixelHeight + grid.Padding) / grid.CellSize))
            item._declaredH = oldHeight
            item.h = measuredHeight
            -- 每个声明项都是一个 section；后续项维持其相对于这个 section
            -- 的原始留白。显式 measure 才启用此重排，因此不会影响旧 schema。
            shift = shift + (oldHeight - measuredHeight)
        end

        if source.children then
            item.children = CopyMeasuredItems(grid, container, source.children, config, currentPath)
        end
        measured[#measured + 1] = item
    end
    return measured
end

local function BuildMeasuredLayout(grid, container, layoutData, config)
    return CopyMeasuredItems(grid, container, layoutData, config, nil)
end

function Grid:Render(container, layoutData, config, moduleKey, onFinished)
    if not container or not layoutData then return end

    if type(config) == "string" then
        moduleKey = config
        config = ExwindTools:GetModuleDB(moduleKey)
    end

    self:UpdateMetrics(container:GetWidth(), container)
    local renderedLayout = BuildMeasuredLayout(self, container, layoutData, config)
    local state = GetContainerState(self, container)
    state.layout = renderedLayout
    state.config = config
    state.moduleKey = moduleKey
    ActivateContainerState(self, container, state)
    self:EnsurePixelLayoutHooks(container)

    -- 仅归还当前容器的旧组件。必须遍历实际实例列表，不能只遍历 key 索引；
    -- TableGroup 的同名字段会覆盖 Widgets[key]，但每个实例都必须各自回池。
    self:ReleaseContainerWidgets(container)

    -- [v2.0] 启动递归渲染
    self:RenderItems(container, renderedLayout, nil, config, moduleKey)

    -- 计算最大高度 (需要递归遍历所有元素)
    local maxH = 1
    local function findMaxH(items)
        for _, ele in ipairs(items) do
            if ele.y then
                maxH = math.max(maxH, ele.y + (ele.h or 2))
            end
            if ele.children then findMaxH(ele.children) end
        end
    end
    findMaxH(renderedLayout)

    local contentHeight = maxH * self.CellSize + 80
    local PixelUtil = _G.PixelUtil
    if PixelUtil and PixelUtil.SetHeight then
        PixelUtil.SetHeight(container, contentHeight, 1)
    else
        container:SetHeight(contentHeight)
    end

    -- live edit 是容器级上下文。即使别的容器在运行时重渲染，
    -- 也不能把当前编辑会话的 ActiveLayout / WidgetMap / ModuleKey 偷换掉。
    local liveContainer = self.LiveEditContainer or self.LiveContainer
    if self.IsLiveEditing and liveContainer and liveContainer ~= container then
        local liveState = GetContainerState(self, liveContainer)
        if liveState then
            ActivateContainerState(self, liveContainer, liveState)
            if liveContainer.GetWidth then
                self:UpdateMetrics(liveContainer:GetWidth(), liveContainer)
            end
        end
    end

    if onFinished then onFinished() end
end

-- (GetConfigPath moved to top)

local function GetConfigValue(config, ele)
    if not config then return nil end

    local curr = config
    if ele.parentKey then
        curr = GetConfigPath(config, ele.parentKey)
    end

    if not curr or type(curr) ~= "table" then return nil end

    -- [Core] setKey 优先级最高，用于分离 GridKey 和 DBKey
    if ele.setKey then
        local sk = tonumber(ele.setKey) or ele.setKey
        return curr[sk]
    end

    -- [v4.3.2 Fix] subKey 优先级高于 ele.key
    -- 用法: parentKey="current", subKey="iconSize" → 读取 config.current.iconSize
    -- ele.key (如 "current_iconSize") 仅用于 Grid 组件标识，不参与数据路径
    if ele.subKey then
        local sk = tonumber(ele.subKey) or ele.subKey
        return curr[sk]
    end

    local key = ele.key
    local numKey = tonumber(key)
    local finalKey = numKey or key

    return curr[finalKey]
end

-- [v4.3.1] 递归查找布局项
local function FindLayoutItem(items, key)
    for _, item in ipairs(items) do
        if item.key == key then return item end
        if item.children then
            local found = FindLayoutItem(item.children, key)
            if found then return found end
        end
    end
    return nil
end

local function BindTooltip(target, ele, enableMouse)
    if not target or not target.SetScript then
        return
    end
    if ele.tooltip or ele.spellID then
        if enableMouse and target.EnableMouse then
            target:EnableMouse(true)
        end
        target:SetScript("OnEnter", function(self)
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if ele.spellID then
                _G.GameTooltip:SetSpellByID(ele.spellID)
            elseif ele.tooltip then
                _G.GameTooltip:SetText(ele.tooltip, 1, 1, 1, 1, true)
            end
            _G.GameTooltip:Show()
        end)
        target:SetScript("OnLeave", function()
            _G.GameTooltip:Hide()
        end)
    else
        if enableMouse and target.EnableMouse then
            target:EnableMouse(false)
        end
        target:SetScript("OnEnter", nil)
        target:SetScript("OnLeave", nil)
    end
end


local function SetConfigValue(config, ele, val, moduleKey, fullKey, phase)
    if not config then return end

    -- [Core] setKey 优先级最高 (Force Global/Local Override)
    if ele.setKey then
        local sk = tonumber(ele.setKey) or ele.setKey
        if config[sk] == val then return false end
        config[sk] = val
        if moduleKey and phase ~= "silent" then EXUI:NotifyModuleValueChanged(moduleKey, tostring(ele.setKey), phase == "live" and "changing" or "committed") end
        return true
    end

    -- 解析路径并赋值
    local finalPath = fullKey
    if finalPath then
        local parts = { strsplit(".", finalPath) }
        local ptr = config
        for i = 1, #parts - 1 do
            local k = tonumber(parts[i]) or parts[i]
            if not ptr[k] then ptr[k] = {} end
            ptr = ptr[k]
        end
        local lastKey = tonumber(parts[#parts]) or parts[#parts]
        if ptr[lastKey] == val then return false end
        ptr[lastKey] = val
    else
        local fk = tonumber(ele.key) or ele.key
        if config[fk] == val then return false end
        config[fk] = val
    end

    if moduleKey and phase ~= "silent" then EXUI:NotifyModuleValueChanged(moduleKey, fullKey or tostring(ele.key), phase == "live" and "changing" or "committed") end
    return true
end

-- Grid is the only place that combines a module's identity with the resolved
-- ModuleDB path.  Composite controls receive this private Core context; layout
-- declarations never carry input or refresh wiring.
local function BuildCompositeOptions(sourceOpts, moduleKey, pathPrefix)
    local opts = {}
    if type(sourceOpts) == "table" then
        for key, value in pairs(sourceOpts) do opts[key] = value end
    end
    if moduleKey then
        opts._exWriteContext = { moduleKey = moduleKey, pathPrefix = pathPrefix }
    end
    return opts
end

-- 旧版的 `condition and nil or key` 在 Lua 中永远回退到 key，因此已经声明
-- bindRoot 的 AnchorGroup 仍会多写出一层 `anchor` / `anchorGroup`。修正后，
-- 把那层旧表保留原样；仅在真实字段为空时，接回旧输入框中可能手动填写的目标。
-- 已由选择器写入的真实目标优先级最高，绝不覆盖。
local function MigrateLegacyDirectAnchorInput(anchorConfig, widgetKey, opts)
    if type(anchorConfig) ~= "table" or type(widgetKey) ~= "string" or widgetKey == "" then
        return false
    end

    local legacy = anchorConfig[widgetKey]
    if type(legacy) ~= "table" or legacy.__exAnchorDirectBindingMigrated then
        return false
    end
    legacy.__exAnchorDirectBindingMigrated = true

    opts = type(opts) == "table" and opts or {}
    local targetKey = opts.attachTargetKey or "customAttachTarget"
    local enabledKey = opts.attachEnabledKey or "attachToCustom"
    local legacyTarget = legacy[targetKey]
    local currentTarget = anchorConfig[targetKey]
    if (currentTarget == nil or currentTarget == "")
        and type(legacyTarget) == "string" and legacyTarget ~= "" then
        anchorConfig[targetKey] = legacyTarget
        if anchorConfig[enabledKey] ~= true then
            anchorConfig[enabledKey] = legacy[enabledKey] == true
        end
        return true
    end

    return false
end

local function NotifyCompositeWrite(moduleKey, fullPath)
    if moduleKey then EXUI:NotifyModuleValueChanged(moduleKey, fullPath, "committed") end
end

function Grid:CreateWidget(container, ele, config, moduleKey, contextPath)
    -- [v4.3.2] 构造当前组件的完整数据路径
    -- 关键: 当有 subKey 时，使用 subKey 作为数据键 (ele.key 仅用于 Grid 组件标识)
    local fullPath
    local dataKey = ele.subKey or ele.key -- subKey 优先级高于 key

    if contextPath then
        fullPath = contextPath .. "." .. dataKey
    else
        if ele.parentKey then
            fullPath = ele.parentKey .. "." .. dataKey
        else
            fullPath = tostring(dataKey)
        end
    end

    local px, py, pw, ph = self:GetPixelRect(ele.x, ele.y, ele.w, ele.h, container)
    local widget

    -- [v4.3.2] 获取值：setKey 最高优先，然后使用构造好的 fullPath
    local curVal
    if ele.setKey then
        curVal = config[ele.setKey]
    else
        curVal = GetConfigPath(config, fullPath)
    end

    local function Setter(v)
        SetConfigValue(config, ele, v, moduleKey, fullPath, "commit")
    end

    local function LiveSetter(v)
        SetConfigValue(config, ele, v, moduleKey, fullPath, "live")
    end

    local function ReadCurrentValue()
        if ele.setKey then return config[tonumber(ele.setKey) or ele.setKey] end
        return GetConfigPath(config, fullPath)
    end

    -- ... (Create Logic) ...
    if ele.type == "header" then
        local text = ele.label
        if type(text) == "function" then text = text() end
        widget = EXUI:CreateHeader(container, text or "", pw)
    elseif ele.type == "subheader" then
        local text = ele.label
        if type(text) == "function" then text = text() end
        widget = EXUI:CreateSubheader(container, text or "", pw)
    elseif ele.type == "divider" then
        widget = EXUI:CreateDivider(container, pw)
    elseif ele.type == "button" then
        widget = EXUI:CreateButton(container, pw, ph, ele.label, function()
            if ele.func then ele.func() end
            if ele.key and moduleKey then
                ExwindTools:UpdateState(moduleKey .. ".ButtonClicked",
                    { key = ele.key, fullPath = fullPath, ts = GetTime() })
            end
        end, { variant = ele.variant, compact = ele.compact == true })
    elseif ele.type == "picbutton" then
        local nTex, pTex = ele.iconNormal, ele.iconPushed
        if ele.atlas then
            nTex = ele.atlas .. "_Normal"; pTex = ele.atlas .. "_Pushed"
        end
        widget = EXUI:CreatePicButton(container, pw, ph, nTex, pTex, ele.iconHighlight, function()
            if ele.key and moduleKey then
                ExwindTools:UpdateState(moduleKey .. ".ButtonClicked",
                    { key = ele.key, fullPath = fullPath, ts = GetTime() })
            end
        end)
    elseif ele.type == "checkbox" then
        widget = EXUI:CreateCheckbox(container, ele.label, curVal == true, function(v)
            Setter(v == true)
        end)
    elseif ele.type == "slider" then
        widget = EXUI:CreateSlider(container, pw, ele.label, ele.min or 0, ele.max or 100, curVal or 0, ele.step or 1,
            nil, {
                onLive = LiveSetter,
                onCommit = Setter,
            })
    elseif ele.type == "input" then
        widget = EXUI:CreateEditBox(container, curVal or "", pw, ph, ele.label, {
            onChanged = nil,
            onEnter = Setter,
            onEditFocusLost = Setter,
            labelPos = ele.labelPos,
            labelSize = ele.labelSize
        })
    elseif ele.type == "color" then
        local subConfig = config
        if contextPath then
            subConfig = GetConfigPath(config, contextPath) or config
        end
        widget = EXUI:CreateColorButton(container, ele.label, subConfig, ele.key, true, function()
            NotifyCompositeWrite(moduleKey, fullPath)
        end)
    elseif ele.type == "label" or ele.type == "description" then
        local text = ele.label
        if type(text) == "function" then text = text() end

        widget = EXUI:CreateDescription(container, text or "", pw)

        widget.text:ClearAllPoints()
        widget.text:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)
        widget.text:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 0, 0)
        widget.text:SetJustifyH("LEFT")
        widget.text:SetJustifyV("TOP")
        widget.text:SetWordWrap(ele.wordWrap ~= false)
        if widget.text.SetMaxLines then
            widget.text:SetMaxLines(tonumber(ele.maxLines) or 0)
        end
        widget.text:SetText(text or "")
        widget.labelText = widget.text -- 兼容

        -- [v4.3.13] 支持 tooltip
        BindTooltip(widget, ele, true)
    elseif ele.type == "card" then
        widget = EXUI:CreateCard(container, pw, ph)
        ReleaseCardOutline(widget)

        local title = ele.title
        if title == nil or title == "" then
            title = ele.label or ""
        end
        if type(title) == "function" then
            title = title()
        end
        local desc = ele.desc
        if desc == nil or desc == "" then
            desc = ele.descriptionText or ""
        end
        if type(desc) == "function" then
            desc = desc()
        end

        local padding = math.max(0, tonumber(ele.padding) or 12)
        local leftInset = padding + 8

        -- Grid Card 原生支持标题图标：调用方只提供 titleIcon 图片路径。
        -- 图标尺寸、左侧留白、文字间距和与标题底边对齐均在这里统一处理。
        local titleIcon = ele.titleIcon
        if type(titleIcon) == "function" then
            titleIcon = titleIcon()
        end
        local hasTitleIcon = type(titleIcon) == "string" and titleIcon ~= ""
        local titleIconSize = 22
        local titleIconLeft = 14
        local titleIconGap = 4
        local titleLeftInset = leftInset
        if hasTitleIcon and widget.Title then
            titleLeftInset = math.max(leftInset, titleIconLeft + titleIconSize + titleIconGap)
        end

        if widget.Title then
            widget.Title:ClearAllPoints()
            widget.Title:SetPoint("TOPLEFT", titleLeftInset, -padding)
            widget.Title:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -padding, -padding)
            widget.Title:SetText(tostring(title or ""))
        end

        if hasTitleIcon and widget.Title then
            if not widget.TitleIcon then
                widget.TitleIcon = EXUI:CreateVisualTexture(widget, EXBASEFRAME)
            end
            widget.TitleIcon:ClearAllPoints()
            widget.TitleIcon:SetSize(titleIconSize, titleIconSize)
            widget.TitleIcon:SetPoint("BOTTOMLEFT", widget.Title, "BOTTOMLEFT", titleIconLeft - titleLeftInset, 0)
            widget.TitleIcon:SetTexture(titleIcon)
            widget.TitleIcon:Show()
        elseif widget.TitleIcon then
            widget.TitleIcon:Hide()
        end
        if widget.Desc then
            widget.Desc:ClearAllPoints()
            if widget.Title then
                widget.Desc:SetPoint("TOPLEFT", widget.Title, "BOTTOMLEFT", 0, -6)
            else
                widget.Desc:SetPoint("TOPLEFT", widget, "TOPLEFT", leftInset, -padding)
            end
            widget.Desc:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -padding, 0)
            widget.Desc:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", padding, padding)
            widget.Desc:SetText(tostring(desc or ""))
        end

        if ele.mouse == true then
            if widget.EnableMouse then
                widget:EnableMouse(true)
            end
        else
            if widget.EnableMouse then
                widget:EnableMouse(false)
            end
        end

        if widget.SetFrameStrata then
            widget:SetFrameStrata("LOW")
        end
        if widget.SetFrameLevel then
            widget:SetFrameLevel(math.max(0, (container:GetFrameLevel() or 0) - 5))
        end

        if ele.frameLevelOffset and widget.SetFrameLevel then
            widget:SetFrameLevel((container:GetFrameLevel() or 0) + tonumber(ele.frameLevelOffset))
        end
    elseif ele.type == "custom" then
        local rendererKey = ele.renderer or ele.customType or ele.widgetType
        local renderer = self:GetCustomRenderer(rendererKey)
        if renderer then
            local EXFactory = _G.ExwindFactory
            if EXFactory then
                widget = EXFactory:Acquire("GridCustomHost", container)
                widget._gridType = "GridCustomHost"
            else
                widget = CreateFrame("Frame", nil, container, "BackdropTemplate")
            end

            -- 自定义渲染器由对象池复用，必须在每次挂载时恢复当前 Grid 容器的
            -- strata/level，不能保留上一页的 LOW/MEDIUM 层级。
            if widget.SetFrameStrata then
                widget:SetFrameStrata(container:GetFrameStrata() or "MEDIUM")
            end
            if widget.SetFrameLevel then
                widget:SetFrameLevel((container:GetFrameLevel() or 0) + 1)
            end

            local ctx = {
                grid = self,
                widget = widget,
                element = ele,
                container = container,
                config = config,
                moduleKey = moduleKey,
                fullPath = fullPath,
                contextPath = contextPath,
                currentValue = curVal,
                setter = Setter,
                value = curVal,
                _layoutWidth = pw,
                _layoutHeight = ph,
            }

            -- Card custom content keeps the established renderer signature, but
            -- receives geometry notification helpers through the same ctx.  The
            -- owner lookup is container-scoped so pooled custom hosts never keep
            -- a previous card/session closure after ReleaseContainerWidgets.
            local cardOwner = self.CardSessionOwners[container]
            if cardOwner and cardOwner.session and cardOwner.card then
                local contentGeneration = cardOwner.card.contentGeneration
                local function IsCurrentCardContent()
                    return not cardOwner.session.released
                        and cardOwner.card.contentGeneration == contentGeneration
                end
                ctx.session = cardOwner.session
                ctx.cardId = cardOwner.card.id
                ctx.pageId = cardOwner.session.context and cardOwner.session.context.pageId
                ctx.regionId = cardOwner.session.context and cardOwner.session.context.regionId
                ctx.IsCurrent = IsCurrentCardContent
                local activeSetter = ctx.setter
                ctx.setter = function(first, second)
                    if not IsCurrentCardContent() then return false end
                    local value
                    if first == ctx then value = second else value = first end
                    return activeSetter(value)
                end
                ctx.SetContentHeight = function(first, second)
                    if not IsCurrentCardContent() then return false end
                    local height
                    if first == ctx then height = second else height = first end
                    return cardOwner.session:_SetReportedContentHeight(cardOwner.card, height)
                end
                ctx.GetContentWidth = function()
                    if not IsCurrentCardContent() then return 0 end
                    return tonumber(ctx._layoutWidth) or pw
                end
                ctx.RequestReflow = function()
                    if not IsCurrentCardContent() then return false end
                    return self:RequestReflow(container)
                end
            end

            if widget._customRendererKey ~= rendererKey and widget._customRenderer and type(widget._customRenderer.release) == "function" then
                local released, releaseReason = pcall(widget._customRenderer.release,
                    widget, widget._customContext)
                if not released then
                    widget._customRenderer = nil
                    widget._customRendererKey = nil
                    widget._customContext = nil
                    local cleaned, cleanupReason = pcall(self.ReleaseWidgetInstance, self, widget)
                    if not cleaned then
                        error(tostring(releaseReason) .. "; stale custom cleanup failed: "
                            .. tostring(cleanupReason), 0)
                    end
                    error(releaseReason, 0)
                end
            end

            widget._customRenderer = renderer
            widget._customRendererKey = rendererKey
            widget._customContext = ctx

            if type(renderer.mount) == "function" then
                local mounted, mountReason = pcall(renderer.mount, widget, ctx)
                if not mounted then
                    local cleaned, cleanupReason = pcall(self.ReleaseWidgetInstance, self, widget)
                    if not cleaned then
                        error(tostring(mountReason) .. "; custom cleanup failed: "
                            .. tostring(cleanupReason), 0)
                    end
                    error(mountReason, 0)
                end
            end
        else
            widget = EXUI:CreateHeader(container, L["未注册的自定义组件"], pw)
        end
    elseif ele.type == "dropdown" or ele.type == "select" then
        local rawItems = ele.items
        if rawItems == nil and type(ele.options) == "table" then
            rawItems = {}
            local optionKeys = {}
            for value in pairs(ele.options) do optionKeys[#optionKeys + 1] = value end
            table.sort(optionKeys, function(a, b) return tostring(a) < tostring(b) end)
            for _, value in ipairs(optionKeys) do
                rawItems[#rawItems + 1] = { ele.options[value], value }
            end
        end
        local itemsList = {}
        local function ParseInlineDropdownItems(rawText)
            local parsed = {}
            for s in string.gmatch(rawText or "", "([^,]+)") do
                local value, display = s:match("^([^:]+):(.+)$")
                if value and display then
                    table.insert(parsed, { display, value })
                else
                    table.insert(parsed, s)
                end
            end
            return parsed
        end

        if type(rawItems) == "string" and rawItems:sub(1, 5) == "func:" then
            local funcPath = rawItems:match("func:(.+%(%))") or rawItems:sub(6)
            funcPath = funcPath:gsub("%(%)", "")
            local func = _G
            for part in string.gmatch(funcPath, "([^%.]+)") do
                if func then func = func[part] else break end
            end
            local dynamicData = (type(func) == "function" and func()) or "Run_Time_Generated"
            if type(dynamicData) == "table" then
                itemsList = dynamicData
            else
                itemsList = ParseInlineDropdownItems(dynamicData)
            end
        else
            if type(rawItems) == "table" then
                itemsList = rawItems
            elseif type(rawItems) == "string" then
                itemsList = ParseInlineDropdownItems(rawItems)
            end
        end

        widget = EXUI:CreateDropdown(container, pw, ele.label, itemsList, curVal, Setter, ele)
    elseif ele.type == "multiselect" then
        local itemsList = {}
        -- (Complex items logic omitted for brevity, use existing)
        local rawItems = ele.items
        if type(rawItems) == "string" and rawItems:sub(1, 5) == "func:" then
            local funcPath = rawItems:match("func:(.+%(%))") or rawItems:sub(6)
            funcPath = funcPath:gsub("%(%)", "") -- clean ()
            local func = _G
            for part in string.gmatch(funcPath, "([^%.]+)") do
                if func then func = func[part] else break end
            end
            local dynamicStr = (type(func) == "function" and func()) or "Run_Time_Generated"
            for s in string.gmatch(dynamicStr, "([^,]+)") do table.insert(itemsList, s) end
        else
            if type(rawItems) == "table" then
                itemsList = rawItems
            elseif type(rawItems) == "string" then
                for s in string.gmatch(rawItems, "([^,]+)") do table.insert(itemsList, s) end
            end
        end

        if not curVal then
            SetConfigValue(config, ele, {}, moduleKey, fullPath, "silent"); curVal = GetConfigPath(config, fullPath)
        end
        -- Multiselect 的回调比较特殊，它不需要传值，而是当内部状态变更时触发 StateUpdate
        widget = EXUI:CreateMultiSelectDropdown(container, pw, ele.label, itemsList, curVal, function()
            NotifyCompositeWrite(moduleKey, fullPath)
        end, ele)
    elseif ele.type == "itemconfig" then
        local itemID = tonumber(ele.itemID) or (curVal and curVal.id) or 0
        local widgetSize = ele.labelSize or ele.size or 18
        local onDelete
        if ele.canDelete == true or type(ele.onDelete) == "function" then
            onDelete = function()
                if type(ele.onDelete) == "function" then ele.onDelete(curVal, config) end
            end
        end
        widget = EXUI:CreateItemConfig(container, pw, ph, itemID, curVal or { enabled = true, quantity = 1 },
            function(newDB, newItemID)
                if newItemID and ele.onDragUpdate then
                    ele.onDragUpdate(newItemID)
                else
                    Setter(newDB)
                end
            end,
            onDelete
        )
        widget.moduleKey = moduleKey
        widget.elementKey = ele.key
    elseif ele.type == "segmented" then
        widget = EXUI:CreateSegmentedControl(container, pw, ele.items or {}, curVal, Setter)
    elseif ele.type == "previewcanvas" then
        local elements = type(curVal) == "table" and curVal or (ele.elements or {})
        widget = EXUI:CreatePreviewCanvas(container, pw, ph, elements, {
            onSelect = ele.onSelect,
            onMove = function(key, relX, relY)
                local target = type(elements[key]) == "table" and elements[key] or nil
                if target then target.x, target.y = relX, relY end
                NotifyCompositeWrite(moduleKey, fullPath)
                if ele.onMove then ele.onMove(key, relX, relY, elements) end
            end,
        })
    elseif ele.type == "tabgroup" then
        widget = EXUI:CreateTabGroup(container, {
            width = pw,
            items = ele.items or {},
            value = curVal,
            disabled = ele.disabled,
            sizing = ele.sizing,
            minItemWidth = ele.minItemWidth,
            itemHeight = ele.itemHeight,
            onChange = Setter,
        })
    elseif ele.type == "optiongroup" then
        if ele.mode == "multiple" and type(curVal) ~= "table" then
            SetConfigValue(config, ele, {}, moduleKey, fullPath, "silent")
            curVal = ReadCurrentValue() or {}
        end
        widget = EXUI:CreateOptionGroup(container, {
            width = pw,
            items = ele.items or {},
            value = curVal,
            mode = ele.mode,
            allowEmpty = ele.allowEmpty,
            disabled = ele.disabled,
            appearance = ele.appearance,
            wrap = ele.wrap,
            columns = ele.columns,
            sizing = ele.sizing,
            minItemWidth = ele.minItemWidth,
            itemHeight = ele.itemHeight,
            onChange = Setter,
        })
    elseif ele.type == "lsm_font" then
        widget = EXUI:CreateLSMDropdown(container, "font", pw, ele.label, curVal, Setter, ele)
    elseif ele.type == "lsm_sound" then
        widget = EXUI:CreateLSMSoundDropdown(container, pw, ele.label, curVal, Setter, ele)
    elseif ele.type == "lsm_texture" then
        widget = EXUI:CreateLSMTextureDropdown(container, "statusbar", pw, ele.label, curVal, Setter, ele)
    elseif ele.type == "lsm_border" then
        widget = EXUI:CreateLSMTextureDropdown(container, "border", pw, ele.label, curVal, Setter, ele)
    elseif ele.type == "lsm_background" then
        widget = EXUI:CreateLSMTextureDropdown(container, "background", pw, ele.label, curVal, Setter, ele)
    elseif ele.type == "fontgroup" then
        if not curVal then
            local defaultFontTable = { font = "Friz Quadrata TT", size = 14, r = 1, g = 1, b = 1, a = 1, outline = "", shadow = false, x = 0, y = 0 }
            Setter(defaultFontTable)
            curVal = defaultFontTable
        end
        local fontGroupWidth = pw
        widget = EXUI:CreateFontGroup(container, fontGroupWidth, ele.label, curVal, function() NotifyCompositeWrite(moduleKey, fullPath) end, BuildCompositeOptions(ele.opts, moduleKey, fullPath))
        widget._exGridWidth = fontGroupWidth
    elseif ele.type == "glow_settings" then
        local subConfig = config
        if contextPath then
            subConfig = GetConfigPath(config, contextPath) or config
        end
        widget = EXUI:CreateGlowSettings(container, pw, ele.label, subConfig, ele.key,
            function() NotifyCompositeWrite(moduleKey, fullPath) end,
            BuildCompositeOptions(ele.opts, moduleKey, fullPath))
    elseif ele.type == "glow_settings_legacy" then
        local subConfig = config
        if contextPath then subConfig = GetConfigPath(config, contextPath) or config end
        widget = EXUI.CreateGlowSettingsLegacy(EXUI, container, pw, ele.label, subConfig, ele.key,
            function() NotifyCompositeWrite(moduleKey, fullPath) end)
    elseif ele.type == "widgetlayout" then
        local subConfig = config
        if contextPath then
            subConfig = GetConfigPath(config, contextPath) or config
        end
        local layoutWidth = pw
        widget = EXUI:CreateWidgetLayoutGroup(container, layoutWidth, ele.label, subConfig, ele.key, function() NotifyCompositeWrite(moduleKey, fullPath) end, BuildCompositeOptions(ele.opts, moduleKey, fullPath))
        widget._exGridWidth = layoutWidth
    elseif ele.type == "modulecommonsettings" then
        local commonConfig = config
        if contextPath then
            commonConfig = GetConfigPath(config, contextPath) or config
        end
        local bindKey = (type(ele.opts) == "table" and ele.opts.bindRoot == true) and nil or ele.key
        local commonPath = bindKey and fullPath or (contextPath or "")
        local commonOpts = BuildCompositeOptions(ele.opts, moduleKey, commonPath)
        -- 新增元素的 key 是编辑器唯一生成的；仅这类背景卡片允许 Grid h 覆盖
        -- 内容 Flow 的高度，正式模块通用设置组继续自动测高。
        if type(ele.key) == "string" and ele.key:match("^modulecommonsettings_%d+$") then
            commonOpts.gridEditableHeight = true
        end
        widget = EXUI:CreateModuleCommonSettingsGroup(container, pw, ele.label, commonConfig, bindKey, function() NotifyCompositeWrite(moduleKey, commonPath) end, commonOpts)
        widget._exGridWidth = pw
    elseif ele.type == "anchorgroup" then
        local anchorConfig = config
        if contextPath then
            anchorConfig = GetConfigPath(config, contextPath) or config
        end
        local bindRoot = type(ele.opts) == "table" and ele.opts.bindRoot == true
        local bindKey = nil
        local migratedLegacyInput = false
        if bindRoot then
            migratedLegacyInput = MigrateLegacyDirectAnchorInput(anchorConfig, ele.key, ele.opts)
        else
            bindKey = ele.key
        end
        local anchorPath = fullPath
        if not bindKey then
            local targetKey = type(ele.opts) == "table" and ele.opts.attachTargetKey or nil
            targetKey = type(targetKey) == "string" and targetKey ~= "" and targetKey or "customAttachTarget"
            anchorPath = contextPath and (contextPath .. "." .. targetKey) or targetKey
        end
        widget = EXUI:CreateAnchorGroup(container, pw, ele.label, anchorConfig, bindKey, function() NotifyCompositeWrite(moduleKey, anchorPath) end, BuildCompositeOptions(ele.opts, moduleKey, anchorPath))
        widget._exGridWidth = pw
        if migratedLegacyInput then
            NotifyCompositeWrite(moduleKey, anchorPath)
        end
    elseif ele.type == "texturegroup" then
        local bindValue = type(ele.opts) == "table" and ele.opts.bindValue == true
        local subConfig = bindValue and curVal or config
        if not bindValue and contextPath then
            subConfig = GetConfigPath(config, contextPath) or config
        end
        local textureWidth = pw
        widget = EXUI:CreateTextureGroup(container, textureWidth, ele.label, subConfig,
            bindValue and nil or ele.key, function() NotifyCompositeWrite(moduleKey, fullPath) end,
            BuildCompositeOptions(ele.opts, moduleKey, fullPath))
        widget._exGridWidth = textureWidth
    elseif ele.type == "icongroup" then
        local bindRoot = type(ele.opts) == "table" and ele.opts.bindRoot == true
        local bindValue = type(ele.opts) == "table" and ele.opts.bindValue == true
        -- bindRoot is a persistence contract, not merely a key-elision hint:
        -- a root-bound IconGroup must receive the page binding root even if a
        -- surrounding Grid context path is present.
        local subConfig = bindValue and curVal or config
        if not bindValue and not bindRoot and contextPath then
            subConfig = GetConfigPath(config, contextPath) or config
        end
        -- Composite groups normally own a nested table named after their Grid
        -- key.  Some pages (EXAura B1/C1) deliberately bind the icon visual
        -- directly to the supplied display root instead.  Mirror the
        -- established modulecommonsettings/anchorgroup bindRoot contract so
        -- this never creates a synthetic `display.icon` table.
        -- Lua 的 `condition and nil or fallback` 会永远落到 fallback；
        -- root 绑定必须显式保留 nil，不能把 Grid key "icon" 传进去。
        local bindKey = nil
        if not bindRoot and not bindValue then bindKey = ele.key end
        local iconGroupWidth = pw
        local iconPath = bindValue and fullPath or (bindKey and fullPath or (contextPath or ""))
        widget = EXUI:CreateIconGroup(container, iconGroupWidth, ele.label, subConfig, bindKey, function() NotifyCompositeWrite(moduleKey, iconPath) end, BuildCompositeOptions(ele.opts, moduleKey, iconPath))
        widget._exGridWidth = iconGroupWidth
    elseif ele.type == "soundgroup" then
        local subConfig = config
        if contextPath then
            subConfig = GetConfigPath(config, contextPath) or config
        end
        widget = EXUI:CreateSoundGroup(container, pw, ele.label, subConfig, ele.key, function() NotifyCompositeWrite(moduleKey, fullPath) end, BuildCompositeOptions(ele.opts, moduleKey, fullPath))
        widget._exGridWidth = pw
    elseif ele.type == "timerBarGroup" or ele.type == "timerbargroup" then
        -- The timer-bar composite has the same root-binding contract as the
        -- icon composite.  In root mode its defaults and all edits apply to
        -- `config` itself, never to an incidental table named after the Grid
        -- component (for example display.timerBar).
        local bindRoot = type(ele.opts) == "table" and ele.opts.bindRoot == true
        if bindRoot then
            curVal = config
        end
        if not curVal then
            local defaultTimerTable = {
                width = 240,
                height = 24,
                texture = "Clean",
                barColorR = 1,
                barColorG = 0.7,
                barColorB = 0,
                barColorA = 1,
                barBgColorR = 0,
                barBgColorG = 0,
                barBgColorB = 0,
                barBgColorA = 0.5,
                showIcon = true,
                iconSide = "LEFT",
                iconWidth = 24,
                iconHeight = 24,
                iconOffsetX = -5,
                iconOffsetY = 0,
            }
            Setter(defaultTimerTable)
            curVal = defaultTimerTable
        end
        local timerBarGroupWidth = pw
        local timerBarPath = bindRoot and (contextPath or "") or fullPath
        widget = EXUI:CreateTimerBarGroup(container, timerBarGroupWidth, ele.label, curVal, nil, function() NotifyCompositeWrite(moduleKey, timerBarPath) end, BuildCompositeOptions(ele.opts, moduleKey, timerBarPath))
        widget._exGridWidth = timerBarGroupWidth
    elseif ele.type == "auradurationbargroup" then
        local auraConfig = contextPath and (GetConfigPath(config, contextPath) or config) or config
        widget = EXUI:CreateAuraDurationBarGroup(container, pw, ele.label, auraConfig, ele.key, function() NotifyCompositeWrite(moduleKey, fullPath) end, BuildCompositeOptions(ele.opts, moduleKey, fullPath))
        widget._exGridWidth = pw
    elseif ele.type == "auraapplicationbargroup" then
        local auraConfig = contextPath and (GetConfigPath(config, contextPath) or config) or config
        widget = EXUI:CreateAuraApplicationBarGroup(container, pw, ele.label, auraConfig, ele.key, function() NotifyCompositeWrite(moduleKey, fullPath) end, BuildCompositeOptions(ele.opts, moduleKey, fullPath))
        widget._exGridWidth = pw
    elseif ele.type == "auradispelbordergroup" then
        local auraConfig = contextPath and (GetConfigPath(config, contextPath) or config) or config
        widget = EXUI:CreateAuraDispelBorderGroup(container, pw, ele.label, auraConfig, ele.key, function() NotifyCompositeWrite(moduleKey, fullPath) end)
        widget._exGridWidth = pw
    elseif ele.type == "aurasortgroup" then
        local auraConfig = contextPath and (GetConfigPath(config, contextPath) or config) or config
        widget = EXUI:CreateAuraSortGroup(container, pw, ele.label, auraConfig, ele.key, function() NotifyCompositeWrite(moduleKey, fullPath) end)
        widget._exGridWidth = pw
    elseif ele.type == "aurachildelementsgroup" then
        local auraConfig = contextPath and (GetConfigPath(config, contextPath) or config) or config
        -- Aura child elements can be bound directly to display.aura.  In
        -- root mode `key` remains the Grid identity only; passing it through
        -- would create the invalid aura.children.children table.
        local bindKey = (type(ele.opts) == "table" and ele.opts.bindRoot == true) and nil or ele.key
        widget = EXUI:CreateAuraChildElementsGroup(container, pw, ele.label, auraConfig, bindKey, function() NotifyCompositeWrite(moduleKey, fullPath) end, BuildCompositeOptions(ele.opts, moduleKey, fullPath))
        widget._exGridWidth = pw
    elseif ele.type == "voicegroup" or ele.type == "encounter_voice_group" then
        local subConfig = config
        if contextPath then
            subConfig = GetConfigPath(config, contextPath) or config
        end
        widget = EXUI:CreateVoiceGroup(container, pw, ele.label, subConfig, ele.key, function() NotifyCompositeWrite(moduleKey, fullPath) end)
    end

    if widget then
        widget:SetParent(container)
        if ele.type ~= "card" and widget.SetFrameStrata then
            widget:SetFrameStrata(container:GetFrameStrata() or "MEDIUM")
        end
        if ele.type ~= "card" and widget.SetFrameLevel then
            widget:SetFrameLevel((container:GetFrameLevel() or 0) + 1)
        end
        if widget.checkbox then
            if widget.checkbox.SetFrameStrata then
                widget.checkbox:SetFrameStrata(container:GetFrameStrata() or "MEDIUM")
            end
            if widget.checkbox.SetFrameLevel then
                widget.checkbox:SetFrameLevel((widget:GetFrameLevel() or 0) + 1)
            end
        end
        -- 下拉菜单的 logical h 仍用于 Grid 的占位/碰撞计算；但 DropdownButton
        -- 的物理高度由模板固定，不能被 h 拉伸（箭头与背景切片不会等比例缩放）。
        -- 其余控件继续使用原本的全尺寸行为。
        -- 所有 Grid 元素均为静态 GUI；这里是唯一最终落点，不能再按 schema
        -- 的 pixelPerfect 标记分裂成两条布局链。
        widget._exGridPixelElement = ele
        self:ApplyPixelLayout(widget, container, ele)

        if ele.type == "custom" and widget._customRenderer then
            widget._customContext = widget._customContext or {}
            widget._customContext.currentValue = curVal
            widget._customContext.value = curVal
            local updated, updateReason = true
            if type(widget._customRenderer.update) == "function" then
                updated, updateReason = pcall(widget._customRenderer.update,
                    widget, widget._customContext)
            elseif type(widget._customRenderer.render) == "function" then
                updated, updateReason = pcall(widget._customRenderer.render,
                    widget, widget._customContext)
            end
            if not updated then
                local cleaned, cleanupReason = pcall(self.ReleaseWidgetInstance, self, widget)
                if not cleaned then
                    error(tostring(updateReason) .. "; custom cleanup failed: "
                        .. tostring(cleanupReason), 0)
                end
                error(updateReason, 0)
            end
        end

        if ele.frameLevelOffset and widget.SetFrameLevel then
            widget:SetFrameLevel((container:GetFrameLevel() or 0) + tonumber(ele.frameLevelOffset))
        end

        if ele.type == "checkbox" then
            if widget.EnableMouse then
                widget:EnableMouse(false)
            end
            widget:SetScript("OnEnter", nil)
            widget:SetScript("OnLeave", nil)
            if widget.checkbox then
                if widget.checkbox.EnableMouse then
                    widget.checkbox:EnableMouse(true)
                end
                widget.checkbox:SetScript("OnEnter", nil)
                widget.checkbox:SetScript("OnLeave", nil)
                widget.checkbox:SetScript("PreClick", nil)
                widget.checkbox:SetScript("PostClick", nil)
            end
        end

        widget:Show()
        if ele.disabled ~= nil and widget.SetDisabled then
            widget:SetDisabled(ele.disabled == true)
        elseif ele.disabled == true then
            if widget.checkbox and widget.checkbox.Disable then widget.checkbox:Disable()
            elseif widget.SetEnabled then widget:SetEnabled(false)
            elseif widget.Disable then widget:Disable() end
        elseif ele.disabled == false then
            if widget.checkbox and widget.checkbox.Enable then widget.checkbox:Enable()
            elseif widget.SetEnabled then widget:SetEnabled(true)
            elseif widget.Enable then widget:Enable() end
        end
        -- [v4.3.1] 映射到池类型
        local EXFactory = _G.ExwindFactory
        local gridType = ele.type == "select" and "dropdown" or ele.type
        if EXFactory and EXFactory.GridTypeMap then
            widget._gridType = EXFactory.GridTypeMap[gridType] or gridType
        else
            widget._gridType = gridType
        end
        self.Widgets[ele.key] = widget
        self.WidgetInstances = self.WidgetInstances or {}
        self.WidgetInstances[#self.WidgetInstances + 1] = widget

        -- [v2.0] 反向索引注册
        -- 这里我们不再在 Widgets 表里只存 key，而是存下所有 meta 信息
        -- 核心：编辑器交互（拖拽）需要读取这些信息
        if not self.WidgetMap then self.WidgetMap = {} end
        -- [v4.3 Fix] 移除 parentContainer 引用，避免循环引用导致内存泄漏
        -- 所有 widget 都同一个 container 下，无需单独存储
        self.WidgetMap[widget] = {
            item = ele,     -- 引用 Layout Item
            path = fullPath -- 完整数据路径
        }

        widget._exLabelWrap = (ele.labelWrap == true)
        widget._exLabelMaxLines = tonumber(ele.labelMaxLines) or nil

        if ele.type ~= "card" and ele.type ~= "custom" then
            EXUI:UpdateLabelStyle(widget, ele.labelSize, ele.labelPos)
        end
        if EXUI.ApplyControlAppearance then EXUI:ApplyControlAppearance(widget) end

        if self.IsLiveEditing and (self.LiveEditContainer or self.LiveContainer) == container then
            self:WrapWidgetForEdit(widget, ele.key, container)
        end
    end

    return widget
end

-- =========================================================
-- Settings Card containers (gui.version = 1)
-- =========================================================
-- This is an explicit opt-in path. Historical type="card" Grid items remain
-- plain background widgets and are never promoted into content owners.

Grid.CardLayoutDefaults = Grid.CardLayoutDefaults or {
    gap = 12,
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
}

local CARD_GRID_COLS = 200
-- SettingsCard body 左右各有 12px 内边距；Font/Icon 的窄版内部仍需至少
-- 110px 才能维持两列字段为正宽。用外壳最小 136px 留出边框取整余量。
local CARD_COMPOSITE_MIN_OUTER_WIDTH = 136
local CARD_CONTAINER_TARGET = "$container"
local CARD_POINT_FACTORS = {
    TOPLEFT = { 0, 0 }, TOP = { 0.5, 0 }, TOPRIGHT = { 1, 0 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 1 }, BOTTOM = { 0.5, 1 }, BOTTOMRIGHT = { 1, 1 },
}

local CardSessionMixin = {}

local function CopyShallow(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        copy[key] = value
    end
    return copy
end

local function CardLocation(context, cardId)
    context = type(context) == "table" and context or {}
    return tostring(context.pageId or "<page>") .. "/"
        .. tostring(context.regionId or "<region>") .. "/"
        .. tostring(cardId or "<card>")
end

local function ValidateGridCardItems(items, location)
    if type(items) ~= "table" then
        return nil, location .. ": grid content requires an items array"
    end
    for index, item in ipairs(items) do
        local itemLocation = location .. "/item[" .. tostring(index) .. "]"
        if type(item) ~= "table" then
            return nil, itemLocation .. ": item must be a table"
        end
        if type(item.type) ~= "string" or item.type == "" then
            return nil, itemLocation .. ": item.type must be a non-empty string"
        end
        if item.key == nil then
            return nil, itemLocation .. ": item.key is required"
        end
        for _, field in ipairs({ "x", "y", "w", "h" }) do
            if type(item[field]) ~= "number" or item[field] <= 0 then
                return nil, itemLocation .. ": item." .. field .. " must be greater than zero"
            end
        end
        if item.children then
            local ok, reason = ValidateGridCardItems(item.children, itemLocation)
            if not ok then return nil, reason end
        end
    end
    return true
end

local function ValidateCardContent(grid, content, location)
    if type(content) ~= "table" then
        return nil, location .. ": content must be a table"
    end
    local kind = content.kind
    if kind ~= "grid" and kind ~= "composite" and kind ~= "custom" then
        return nil, location .. ": content.kind must be grid, composite, or custom"
    end
    if kind == "grid" then
        if content.component ~= nil or content.renderer ~= nil then
            return nil, location .. ": grid content cannot declare component or renderer"
        end
        if content.ownsScroll ~= nil then
            return nil, location .. ": grid content cannot declare ownsScroll"
        end
        return ValidateGridCardItems(content.items, location)
    end
    if kind == "composite" then
        if content.items ~= nil or content.renderer ~= nil then
            return nil, location .. ": composite content cannot declare items or renderer"
        end
        if content.ownsScroll ~= nil then
            return nil, location .. ": composite content cannot declare ownsScroll"
        end
        if type(content.component) ~= "string" or content.component == "" then
            return nil, location .. ": composite content requires component"
        end
        local component = string.lower(content.component)
        if not grid.CardBodyOnlyComponents[component] then
            return nil, location .. ": composite component does not implement the Card bodyOnly contract: "
                .. tostring(content.component)
        end
        local measures = EXUI and EXUI.GridComponentMeasures
        if type(measures) ~= "table" or type(measures[component]) ~= "function" then
            return nil, location .. ": composite component has no registered Grid measure: "
                .. tostring(content.component)
        end
        if content.key == nil then
            return nil, location .. ": composite content requires key"
        end
        return true
    end
    if content.items ~= nil or content.component ~= nil then
        return nil, location .. ": custom content cannot declare items or component"
    end
    if type(content.renderer) ~= "string" or content.renderer == "" then
        return nil, location .. ": custom content requires renderer"
    end
    if content.ownsScroll ~= nil and type(content.ownsScroll) ~= "boolean" then
        return nil, location .. ": custom content.ownsScroll must be boolean"
    end
    if not grid:GetCustomRenderer(content.renderer) then
        return nil, location .. ": unregistered custom renderer: " .. tostring(content.renderer)
    end
    if content.height ~= nil and (type(content.height) ~= "number" or content.height < 0) then
        return nil, location .. ": custom content.height must be zero or greater"
    end
    if content.height ~= nil and content.measure ~= nil then
        return nil, location .. ": custom content cannot declare both height and measure"
    end
    if content.measure ~= nil and type(content.measure) ~= "function"
        and type(content.measure) ~= "table" and content.measure ~= true then
        return nil, location .. ": custom content.measure must be true, a function, or a table"
    end
    return true
end

function Grid:ValidateCardDeclaration(declaration, context)
    context = type(context) == "table" and context or {}
    if type(declaration) ~= "table" then
        return nil, "[ExwindGrid] settings-card declaration must be a table"
    end
    if declaration.version ~= 1 then
        return nil, "[ExwindGrid] settings-card declaration requires version = 1"
    end
    if declaration.static ~= nil or declaration.fields ~= nil or declaration.groups ~= nil then
        return nil, "[ExwindGrid] settings-card declaration cannot contain legacy static/fields/groups"
    end
    if type(declaration.cards) ~= "table" then
        return nil, "[ExwindGrid] settings-card declaration requires cards"
    end

    local arrayCount, maxIndex = 0, 0
    for key in pairs(declaration.cards) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            return nil, "[ExwindGrid] settings-card cards must be an ordered array"
        end
        arrayCount = arrayCount + 1
        maxIndex = math.max(maxIndex, key)
    end
    if maxIndex ~= arrayCount then
        return nil, "[ExwindGrid] settings-card cards array cannot contain holes"
    end

    local ids = {}
    for index, definition in ipairs(declaration.cards) do
        local definitionId = type(definition) == "table" and definition.id or nil
        local base = "[ExwindGrid] " .. CardLocation(context, definitionId)
        if type(definition) ~= "table" then
            return nil, base .. ": card entry " .. tostring(index) .. " must be a table"
        end
        if type(definition.id) ~= "string" or definition.id == "" then
            return nil, base .. ": card.id must be a non-empty string"
        end
        if ids[definition.id] then return nil, base .. ": duplicate card.id" end
        ids[definition.id] = true
        for _, field in ipairs({ "icon", "headerIcon" }) do
            local icon = definition[field]
            if icon ~= nil and type(icon) ~= "string" and type(icon) ~= "number" then
                return nil, base .. ": card." .. field .. " must be a string or number"
            end
        end
        if definition.collapsed == true and definition.collapsible ~= true then
            return nil, base .. ": collapsed=true requires collapsible=true"
        end
        if definition.minBodyHeight ~= nil and type(definition.minBodyHeight) ~= "number" then
            return nil, base .. ": minBodyHeight must be a number"
        end
        if definition.maxBodyHeight ~= nil and type(definition.maxBodyHeight) ~= "number" then
            return nil, base .. ": maxBodyHeight must be a number"
        end
        local minimum = definition.minBodyHeight or 0
        local maximum = definition.maxBodyHeight
        if minimum < 0 or (maximum and maximum < 0) or (maximum and minimum > maximum) then
            return nil, base .. ": invalid minBodyHeight/maxBodyHeight"
        end
        local placement = definition.placement
        if placement ~= nil then
            if type(placement) ~= "table" then return nil, base .. ": placement must be a table" end
            if placement.target ~= nil and type(placement.target) ~= "string" then
                return nil, base .. ": placement.target must be a string"
            end
            if placement.side ~= nil and placement.side ~= "below" and placement.side ~= "right" then
                return nil, base .. ": placement.side must be below or right"
            end
            if placement.align ~= nil
                and placement.align ~= "start" and placement.align ~= "center" and placement.align ~= "end" then
                return nil, base .. ": placement.align must be start, center, or end"
            end
            if placement.point ~= nil and not CARD_POINT_FACTORS[placement.point] then
                return nil, base .. ": unknown placement.point"
            end
            if placement.relativePoint ~= nil and not CARD_POINT_FACTORS[placement.relativePoint] then
                return nil, base .. ": unknown placement.relativePoint"
            end
            for _, field in ipairs({ "x", "y", "gap" }) do
                if placement[field] ~= nil and type(placement[field]) ~= "number" then
                    return nil, base .. ": placement." .. field .. " must be a number"
                end
            end
            if placement.gap ~= nil and placement.gap < 0 then
                return nil, base .. ": placement.gap cannot be negative"
            end
            local width = placement.width
            if width ~= nil then
                if type(width) == "number" then
                    if width <= 0 then return nil, base .. ": placement.width must be greater than zero" end
                elseif type(width) == "table" then
                    if type(width.ratio) ~= "number" or width.ratio <= 0 then
                        return nil, base .. ": placement.width.ratio must be greater than zero"
                    end
                    if width.offset ~= nil and type(width.offset) ~= "number" then
                        return nil, base .. ": placement.width.offset must be a number"
                    end
                else
                    return nil, base .. ": placement.width must be a number or { ratio, offset }"
                end
            end
        end
        local ok, reason = ValidateCardContent(self, definition.content, base)
        if not ok then return nil, reason end
        if maximum ~= nil
            and not (definition.content.kind == "custom" and definition.content.ownsScroll == true) then
            return nil, base .. ": maxBodyHeight requires custom content with ownsScroll=true"
        end
        if definition.content.kind == "composite" and type(placement) == "table"
            and type(placement.width) == "number"
            and placement.width < CARD_COMPOSITE_MIN_OUTER_WIDTH then
            return nil, base .. ": composite Card width must be at least "
                .. tostring(CARD_COMPOSITE_MIN_OUTER_WIDTH)
        end
    end
    return true
end

local function ResolveCardBinding(session, definition, content)
    local context = session.context
    local bindingName = definition.binding
    if bindingName == nil then bindingName = context.defaultBinding end
    local binding
    if type(bindingName) == "table" then
        binding = bindingName
    elseif bindingName ~= nil then
        binding = type(context.bindings) == "table" and context.bindings[bindingName] or nil
        if not binding then
            error("[ExwindGrid] " .. CardLocation(context, definition.id)
                .. ": binding not found: " .. tostring(bindingName), 0)
        end
    else
        binding = context.binding or context
    end
    if type(binding) ~= "table" then
        error("[ExwindGrid] " .. CardLocation(context, definition.id)
            .. ": binding must be a table", 0)
    end

    local config
    if type(binding.getConfig) == "function" then
        config = binding.getConfig(binding, context, definition.id)
    else
        config = binding.config
    end
    if config == nil and binding == context then config = context.config end
    if config == nil and content.kind == "custom" then
        session._emptyConfig = session._emptyConfig or {}
        config = session._emptyConfig
    end
    if type(config) ~= "table" then
        error("[ExwindGrid] " .. CardLocation(context, definition.id)
            .. ": content binding must resolve to a table", 0)
    end
    return {
        source = binding,
        config = config,
        moduleKey = binding.moduleKey or context.moduleKey,
    }
end

local function BuildCardContentSource(cardState, content)
    if content.kind == "grid" then return content.items end

    local opts = CopyShallow(content.opts)
    if content.kind == "composite" then opts.bodyOnly = true end
    local item = {
        type = content.kind == "composite" and string.lower(content.component) or "custom",
        key = content.key or ("__card_custom_" .. cardState.id),
        renderer = content.renderer,
        label = content.label or cardState.definition.title,
        x = 1, y = 1, w = CARD_GRID_COLS, h = 1,
        opts = opts,
        parentKey = content.parentKey,
        subKey = content.subKey,
        setKey = content.setKey,
        _exCardState = cardState,
    }
    if content.kind == "composite" then
        item.measure = true
    elseif content.height ~= nil then
        item.measure = { preferredHeight = content.height, minHeight = content.height }
    elseif content.measure ~= nil then
        item.measure = content.measure
    else
        item.measure = true
    end
    return { item }
end

local function CardContentOwnsScroll(content)
    return type(content) == "table" and content.kind == "custom"
        and content.ownsScroll == true
end

-- Card bodies deliberately do not use CopyMeasuredItems: every relayout starts
-- from the immutable declaration and never accumulates the previous pass's y/h
-- offsets. Fixed Grid rows remain fixed; shared slots contribute one maximum
-- bottom edge instead of being summed repeatedly.
local function BuildCardMeasuredItems(grid, container, sourceItems, config, contextPath, cardState)
    local measured = {}
    for _, source in ipairs(sourceItems or {}) do
        local item = CopyShallow(source)
        item._exCardSourceItem = source
        item._declaredY = math.max(1, tonumber(source.y) or 1)
        item._declaredH = math.max(1, tonumber(source.h) or 1)
        local currentPath = contextPath
        if item.parentKey then
            currentPath = currentPath and (currentPath .. "." .. item.parentKey) or item.parentKey
        end
        local scopedDB = currentPath and GetConfigPath(config, currentPath) or config
        local isEditorModuleCommonCard = item.type == "modulecommonsettings"
            and type(item.key) == "string" and item.key:match("^modulecommonsettings_%d+$") ~= nil
        if isEditorModuleCommonCard then item.measure = false end
        if item.measure == nil and item.type == "modulecommonsettings"
            and type(item.opts) == "table" and (tonumber(item.w) or 0) == grid._effectiveCols then
            item.measure = true
        end
        if item.measure == nil and item.type == "slider" then item.measure = true end

        local pixelHeight
        if item._exCardState == cardState and cardState.reportedHeight ~= nil then
            pixelHeight = cardState.reportedHeight
        else
            local _, _, pixelWidth = grid:GetPixelRect(item.x, item.y, item.w, item.h, container)
            pixelHeight = NormalizeMeasuredHeight(GetMeasureResult(grid, item, pixelWidth, scopedDB))
        end
        if pixelHeight and pixelHeight >= 0 and grid.CellSize > 0 then
            item.h = math.max(1, math.ceil((pixelHeight + grid.Padding) / grid.CellSize))
            item._exMeasuredPixelHeight = pixelHeight
        end
        item._exCardRenderedY = math.max(1, tonumber(item.y) or 1)
        item._exCardRenderedH = math.max(1, tonumber(item.h) or 1)
        if source.children then
            item.children = BuildCardMeasuredItems(grid, container, source.children, config, currentPath, cardState)
        end
        measured[#measured + 1] = item
    end
    return measured
end

local function WalkRenderableCardItems(grid, items, config, contextPath, callback)
    for _, item in ipairs(items or {}) do
        local currentPath = contextPath
        if item.parentKey then
            currentPath = currentPath and (currentPath .. "." .. item.parentKey) or item.parentKey
        end
        if not currentPath or grid:ValidateContext(config, currentPath) then
            if item.type == "TableGroup" then
                if item.label then callback(item, currentPath) end
                if item.children then
                    WalkRenderableCardItems(grid, item.children, config, currentPath, callback)
                end
            else
                callback(item, currentPath)
            end
        end
    end
end

local function CurrentCardItemValue(config, item, fullPath)
    if item.setKey then return config[item.setKey] end
    return GetConfigPath(config, fullPath)
end

local function CardItemIdentity(item, contextPath)
    local function Part(value)
        return type(value) .. ":" .. tostring(value)
    end
    local dataKey = item.subKey or item.key
    local fullPath
    if contextPath then
        fullPath = contextPath .. "." .. tostring(dataKey)
    elseif item.parentKey then
        fullPath = tostring(item.parentKey) .. "." .. tostring(dataKey)
    else
        fullPath = tostring(dataKey)
    end
    return table.concat({
        Part(item.type),
        Part(item.key),
        Part(item.subKey),
        Part(item.setKey),
        Part(item.renderer or item.customType or item.widgetType),
        Part(fullPath),
    }, "\30")
end

local function ReflowCardBody(grid, cardState, bodyWidth)
    local body = cardState.body
    local state = GetContainerState(grid, body)
    grid:SetContainerCols(body, CARD_GRID_COLS)
    grid:SetContainerPadding(body, { left = 0, right = 0, top = 0, bottom = 0 })
    grid:UpdateMetrics(math.max(1, bodyWidth), body)

    local layout = BuildCardMeasuredItems(grid, body, cardState.sourceItems,
        cardState.binding.config, nil, cardState)
    state.config = cardState.binding.config
    state.moduleKey = cardState.binding.moduleKey

    local renderables = {}
    WalkRenderableCardItems(grid, layout, cardState.binding.config, nil, function(item, contextPath)
        renderables[#renderables + 1] = {
            item = item,
            identity = CardItemIdentity(item, contextPath),
        }
    end)
    if #renderables ~= cardState.renderableCount then
        cardState.session:_Diagnostic(cardState, "structure",
            "content structure changed; call ReplaceCardContent(cardId, content) to rebuild only this card")
        return cardState.lastContentHeight or 0
    end
    for ordinal, entry in ipairs(renderables) do
        if cardState.identityByOrdinal[ordinal] ~= entry.identity then
            cardState.session:_Diagnostic(cardState, "structure",
                "content identity changed; call ReplaceCardContent(cardId, content) to rebuild only this card")
            return cardState.lastContentHeight or 0
        end
    end

    state.layout = layout
    if grid.IsLiveEditing and grid.LiveEditContainer == body then
        grid.ActiveLayout = layout
    end
    local maxBottom = 0
    for ordinal, entry in ipairs(renderables) do
        local item = entry.item
        local widget = cardState.widgetsByOrdinal[ordinal]
        local _, py, pw, ph = grid:GetPixelRect(item.x, item.y, item.w, item.h, body)
        if widget then
            local meta = state.widgetMap and state.widgetMap[widget]
            if meta then meta.item = item end
            if type(widget._exCompositeReflow) == "function" then
                widget._exGridWidth = pw
                widget:_exCompositeReflow(pw, item._exMeasuredPixelHeight or ph)
            end
            widget._exGridCardMeasuredHeight = widget._exGridFixedHeight == nil
                and item._exMeasuredPixelHeight or nil
            widget._exGridPixelElement = item
            grid:ApplyPixelLayout(widget, body, item)
            if item.type == "custom" and widget._customRenderer then
                local ctx = widget._customContext or {}
                ctx._layoutWidth = pw
                ctx._layoutHeight = item._exMeasuredPixelHeight or ph
                if type(widget._customRenderer.layout) == "function" then
                    widget._customRenderer.layout(widget, ctx,
                        ctx._layoutWidth, ctx._layoutHeight)
                end
            end
            local actualHeight = item._exMeasuredPixelHeight
                or widget._exGridFixedHeight
                or (widget.GetHeight and widget:GetHeight())
                or ph
            maxBottom = math.max(maxBottom, -py + math.max(0, tonumber(actualHeight) or ph))
        end
    end
    return math.max(0, maxBottom)
end

local function MountCardBody(grid, cardState)
    local body = cardState.body
    local state = GetContainerState(grid, body)
    cardState.contentGeneration = (cardState.contentGeneration or 0) + 1
    grid:ReleaseContainerWidgets(body)
    state.layout = nil
    state.config = cardState.binding.config
    state.moduleKey = cardState.binding.moduleKey
    ActivateContainerState(grid, body, state)
    grid:SetContainerCols(body, CARD_GRID_COLS)
    grid:SetContainerPadding(body, { left = 0, right = 0, top = 0, bottom = 0 })
    grid:UpdateMetrics(math.max(1, body:GetWidth()), body)
    cardState.widgetsByOrdinal = {}
    cardState.identityByOrdinal = {}
    cardState.renderableCount = 0

    local layout = BuildCardMeasuredItems(grid, body, cardState.sourceItems,
        cardState.binding.config, nil, cardState)
    state.layout = layout
    WalkRenderableCardItems(grid, layout, cardState.binding.config, nil, function(item, contextPath)
        cardState.renderableCount = cardState.renderableCount + 1
        local widget = grid:CreateWidget(body, item, cardState.binding.config,
            cardState.binding.moduleKey, contextPath)
        cardState.widgetsByOrdinal[cardState.renderableCount] = widget or false
        cardState.identityByOrdinal[cardState.renderableCount] = CardItemIdentity(item, contextPath)
    end)
    grid:EnsurePixelLayoutHooks(body)
end

local function CardLayoutMetrics(session)
    local defaults = Grid.CardLayoutDefaults
    local shared = type(EXUI.GetSettingsCardLayoutDefaults) == "function"
        and EXUI:GetSettingsCardLayoutDefaults() or nil
    shared = type(shared) == "table" and shared or {}
    local supplied = type(session.context.layoutDefaults) == "table" and session.context.layoutDefaults or {}
    local function Metric(key)
        local value = supplied[key]
        if value == nil then value = shared[key] end
        if value == nil then value = defaults[key] end
        return tonumber(value) or 0
    end
    return {
        gap = math.max(0, Metric("gap")),
        left = math.max(0, Metric("left")),
        right = math.max(0, Metric("right")),
        top = math.max(0, Metric("top")),
        bottom = math.max(0, Metric("bottom")),
    }
end

local function ResolveDeclaredWidth(widthDeclaration, availableWidth)
    if type(widthDeclaration) == "number" then return math.max(1, widthDeclaration) end
    if type(widthDeclaration) == "table" then
        return math.max(1, availableWidth * widthDeclaration.ratio + (tonumber(widthDeclaration.offset) or 0))
    end
    return nil
end

function CardSessionMixin:_Diagnostic(cardState, code, detail)
    if self.released then return end
    local key = tostring(cardState and cardState.id) .. ":" .. tostring(code)
    if self._diagnosticKeys[key] then return end
    self._diagnosticKeys[key] = true
    local message = "[ExwindGrid] " .. CardLocation(self.context, cardState and cardState.id)
        .. ": " .. tostring(detail)
    self.diagnostics[#self.diagnostics + 1] = {
        cardId = cardState and cardState.id,
        code = code,
        message = message,
    }
    if type(self.context.onDiagnostic) == "function" then
        self.context.onDiagnostic(message, cardState and cardState.id, code)
    elseif _G.print then
        _G.print(message)
    end
end

function CardSessionMixin:GetDiagnostics()
    local result = {}
    for index, diagnostic in ipairs(self.diagnostics) do result[index] = diagnostic end
    return result
end

function CardSessionMixin:_SetReportedContentHeight(cardState, height)
    if self.released or not cardState then return false end
    height = tonumber(height)
    if not height or height ~= height or height < 0 then
        self:_Diagnostic(cardState, "height", "SetContentHeight requires a finite value >= 0")
        return false
    end
    if cardState.reportedHeight ~= nil and math.abs(cardState.reportedHeight - height) < 0.01 then
        return false
    end
    cardState.reportedHeight = height
    self.grid:RequestReflow(cardState.body)
    return true
end

function CardSessionMixin:_QueueRelayout()
    if self.released then return false end
    if self.reflowBusy then
        self.reflowPending = true
        return true
    end
    if self.reflowScheduled then return true end
    self.reflowScheduled = true
    self.reflowTicket = (self.reflowTicket or 0) + 1
    local ticket = self.reflowTicket
    local generation = self.generation
    local function Run()
        if self.released or self.generation ~= generation or self.reflowTicket ~= ticket then return end
        self.reflowScheduled = nil
        self:Relayout()
    end
    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, Run)
    else
        Run()
    end
    return true
end

function Grid:RequestReflow(container)
    local owner = container and self.CardSessionOwners[container]
    local session = owner and owner.session or (container and self.CardSessions[container])
    if not session or session.released then return false end
    return session:_QueueRelayout()
end

local function RestoreGridActivation(grid, snapshot)
    grid.CellSize = snapshot.cellSize
    grid._effectiveCols = snapshot.cols
    grid._activeContainer = snapshot.container
    grid.Widgets = snapshot.widgets
    grid.WidgetInstances = snapshot.instances
    grid.WidgetMap = snapshot.widgetMap
    grid.ActiveLayout = snapshot.layout
    grid.LastConfig = snapshot.config
    grid.ModuleKey = snapshot.moduleKey
end

local function SnapshotGridActivation(grid)
    return {
        cellSize = grid.CellSize,
        cols = grid._effectiveCols,
        container = grid._activeContainer,
        widgets = grid.Widgets,
        instances = grid.WidgetInstances,
        widgetMap = grid.WidgetMap,
        layout = grid.ActiveLayout,
        config = grid.LastConfig,
        moduleKey = grid.ModuleKey,
    }
end

local function SetCardWidth(card, width)
    local PixelUtil = _G.PixelUtil
    if PixelUtil and PixelUtil.SetWidth then
        PixelUtil.SetWidth(card, width, 1)
    else
        card:SetWidth(width)
    end
end

local function SetCardHeight(card, height)
    local PixelUtil = _G.PixelUtil
    height = math.max(1, height)
    if PixelUtil and PixelUtil.SetHeight then
        PixelUtil.SetHeight(card, height, 1)
    else
        card:SetHeight(height)
    end
end

local function MeasureSessionCards(session, availableWidth)
    local grid = session.grid
    for _, cardState in ipairs(session.cards) do
        local placement = cardState.definition.placement or {}
        local width = ResolveDeclaredWidth(placement.width, availableWidth)
        if not width then width = availableWidth end
        cardState.width = math.max(1, width)
        if cardState.content.kind == "composite"
            and cardState.width < CARD_COMPOSITE_MIN_OUTER_WIDTH then
            error("[ExwindGrid] " .. CardLocation(session.context, cardState.id)
                .. ": resolved composite Card width must be at least "
                .. tostring(CARD_COMPOSITE_MIN_OUTER_WIDTH), 0)
        end
        SetCardWidth(cardState.card, cardState.width)

        local bodyWidth = cardState.body:GetWidth()
        if not bodyWidth or bodyWidth <= 1 then bodyWidth = cardState.width end
        local contentHeight = ReflowCardBody(grid, cardState, bodyWidth)
        if cardState.lastContentHeight == nil
            or math.abs(cardState.lastContentHeight - contentHeight) >= 0.01 then
            cardState.lastContentHeight = contentHeight
            cardState.card:SetContentHeight(contentHeight)
        end
        local preferred = cardState.card:GetPreferredHeight(cardState.width)
        if type(preferred) ~= "number" or preferred ~= preferred or preferred <= 0 then
            error("[ExwindGrid] " .. CardLocation(session.context, cardState.id)
                .. ": Card:GetPreferredHeight(width) returned an invalid height", 0)
        end
        cardState.outerHeight = preferred
        cardState.layoutHeight = cardState.visible and preferred or 0
        SetCardHeight(cardState.card, preferred)
    end
end

local function SetRelativeCardAnchor(cardState, target, placement, gap, parent)
    local side = placement.side or "below"
    local align = placement.align or "start"
    local x = tonumber(placement.x) or 0
    local y = tonumber(placement.y) or 0
    if side == "right" then
        cardState.x = target.x + target.width + gap + x
        if align == "center" then
            cardState.y = target.y + (target.layoutHeight - cardState.layoutHeight) * 0.5 - y
        elseif align == "end" then
            cardState.y = target.y + target.layoutHeight - cardState.layoutHeight - y
        else
            cardState.y = target.y - y
        end
    else
        if align == "center" then
            cardState.x = target.x + (target.width - cardState.width) * 0.5 + x
        elseif align == "end" then
            cardState.x = target.x + target.width - cardState.width + x
        else
            cardState.x = target.x + x
        end
        cardState.y = target.y + target.layoutHeight + gap - y
    end
    cardState.card:ClearAllPoints()
    cardState.card:SetPoint("TOPLEFT", parent, "TOPLEFT", cardState.x, -cardState.y)
end

local function ResolveSessionPositions(session, metrics, parentWidth, parentHeight)
    local status = {}
    local gap = metrics.gap
    local contentWidth = math.max(1, parentWidth - metrics.left - metrics.right)
    local contentHeight = math.max(1, parentHeight - metrics.top - metrics.bottom)
    for _, cardState in ipairs(session.cards) do cardState.usedFallback = nil end

    local function Fallback(cardState, code, detail)
        session:_Diagnostic(cardState, code, detail)
        cardState.usedFallback = true
        status[cardState] = "done"
    end

    local Resolve
    Resolve = function(cardState)
        if status[cardState] == "done" then return end
        if status[cardState] == "visiting" then
            Fallback(cardState, "cycle", "card placement cycle detected; using safe vertical fallback")
            return
        end
        status[cardState] = "visiting"
        local placement = cardState.definition.placement
        local targetId
        if placement then
            targetId = placement.target or CARD_CONTAINER_TARGET
        elseif cardState.previous then
            -- 默认纵排只在可见 Card 之间留一个 gap。隐藏 Card 仍保留稳定
            -- id/内容与显式 placement 语义，但不能作为隐式前驱累计空白。
            local previousVisible = cardState.previous
            while previousVisible and not previousVisible.visible do
                previousVisible = previousVisible.previous
            end
            if not previousVisible then
                targetId = CARD_CONTAINER_TARGET
                placement = {
                    target = targetId,
                    point = "TOPLEFT",
                    relativePoint = "TOPLEFT",
                    x = 0,
                    y = 0,
                }
            else
                targetId = previousVisible.id
                placement = { target = targetId, side = "below", align = "start" }
            end
        else
            targetId = CARD_CONTAINER_TARGET
            placement = {
                target = targetId,
                point = "TOPLEFT",
                relativePoint = "TOPLEFT",
                x = 0,
                y = 0,
            }
        end

        if targetId ~= CARD_CONTAINER_TARGET then
            if targetId == cardState.id then
                Fallback(cardState, "self",
                    "card placement cannot target itself; using safe vertical fallback")
                return
            end
            local target = session.byId[targetId]
            if not target then
                Fallback(cardState, "missing", "card placement target not found: "
                    .. tostring(targetId) .. "; using safe vertical fallback")
                return
            end
            Resolve(target)
            if status[cardState] == "done" then return end
            if target.usedFallback then
                Fallback(cardState, "dependency",
                    "card placement target used fallback; using the same safe vertical fallback")
                return
            end
            local actualGap = placement.gap ~= nil and placement.gap or gap
            SetRelativeCardAnchor(cardState, target, placement, actualGap, session.parent)
        else
            local point = placement.point or "TOPLEFT"
            local relativePoint = placement.relativePoint or point
            local x, y = tonumber(placement.x) or 0, tonumber(placement.y) or 0
            local ownFactor = CARD_POINT_FACTORS[point]
            local relativeFactor = CARD_POINT_FACTORS[relativePoint]
            cardState.x = metrics.left + contentWidth * relativeFactor[1]
                + x - cardState.width * ownFactor[1]
            cardState.y = metrics.top + contentHeight * relativeFactor[2] - y
                - cardState.layoutHeight * ownFactor[2]
            cardState.card:ClearAllPoints()
            cardState.card:SetPoint("TOPLEFT", session.parent, "TOPLEFT", cardState.x, -cardState.y)
        end
        status[cardState] = "done"
    end

    for _, cardState in ipairs(session.cards) do Resolve(cardState) end

    local fallbackY = metrics.top
    for _, cardState in ipairs(session.cards) do
        if not cardState.usedFallback and cardState.visible then
            fallbackY = math.max(fallbackY, cardState.y + cardState.layoutHeight + gap)
        end
    end
    for _, cardState in ipairs(session.cards) do
        if cardState.usedFallback then
            cardState.card:ClearAllPoints()
            cardState.card:SetPoint("TOPLEFT", session.parent, "TOPLEFT", metrics.left, -fallbackY)
            cardState.x, cardState.y = metrics.left, fallbackY
            if cardState.layoutHeight > 0 then fallbackY = fallbackY + cardState.layoutHeight + gap end
        end
    end
end

local function ClampSessionScroll(session, totalHeight)
    local scrollFrame = session.context.scrollFrame
    if not scrollFrame or type(scrollFrame.GetVerticalScroll) ~= "function"
        or type(scrollFrame.SetVerticalScroll) ~= "function" then return end
    local current = tonumber(scrollFrame:GetVerticalScroll()) or 0
    local viewport = type(scrollFrame.GetHeight) == "function" and scrollFrame:GetHeight() or 0
    local maximum = math.max(0, totalHeight - (tonumber(viewport) or 0))
    local clamped = math.max(0, math.min(current, maximum))
    if math.abs(clamped - current) >= 0.01 then scrollFrame:SetVerticalScroll(clamped) end
end

local function PerformSessionRelayout(session)
    local parent = session.parent
    local parentWidth = math.max(1, parent:GetWidth())
    local metrics = CardLayoutMetrics(session)
    local availableWidth = math.max(1, parentWidth - metrics.left - metrics.right)
    local parentHeight = tonumber(session.context.viewportHeight)
        or (session.context.scrollFrame and session.context.scrollFrame:GetHeight())
        or parent:GetHeight()
        or 1

    local snapshot = SnapshotGridActivation(session.grid)
    local measured, measureReason = pcall(MeasureSessionCards, session, availableWidth)
    RestoreGridActivation(session.grid, snapshot)
    if not measured then error(measureReason, 0) end
    ResolveSessionPositions(session, metrics, parentWidth, math.max(1, parentHeight))

    local maxBottom = metrics.top
    for _, cardState in ipairs(session.cards) do
        cardState.card:SetShown(cardState.visible)
        if cardState.visible then
            maxBottom = math.max(maxBottom, cardState.y + cardState.layoutHeight)
        end
    end
    local totalHeight = math.max(1, maxBottom + metrics.bottom)
    if session.totalHeight == nil or math.abs(session.totalHeight - totalHeight) >= 0.01 then
        session.totalHeight = totalHeight
        SetCardHeight(parent, totalHeight)
        if type(session.context.onContentHeightChanged) == "function" then
            session.context.onContentHeightChanged(totalHeight, session)
        end
    end
    ClampSessionScroll(session, totalHeight)
end

function CardSessionMixin:Relayout()
    if self.released then return false end
    if self.reflowBusy then
        self.reflowPending = true
        return false
    end
    self.reflowScheduled = nil
    self.reflowTicket = (self.reflowTicket or 0) + 1
    self.reflowBusy = true
    local ok, reason = pcall(PerformSessionRelayout, self)
    self.reflowBusy = nil
    if not ok then error(reason, 0) end
    if self.reflowPending then
        self.reflowPending = nil
        self:_QueueRelayout()
    end
    return true
end

function CardSessionMixin:RefreshValues()
    if self.released then return false end
    for _, cardState in ipairs(self.cards) do
        self.grid:RefreshContainerControlsFromDB(cardState.body)
        local state = self.grid.ContainerStates[cardState.body]
        for _, widget in ipairs(state and state.instances or {}) do
            if widget._customRenderer then
                local ctx = widget._customContext or {}
                local meta = state.widgetMap and state.widgetMap[widget]
                ctx.currentValue = CurrentCardItemValue(cardState.binding.config,
                    ctx.element or {}, meta and meta.path)
                ctx.value = ctx.currentValue
                if type(widget._customRenderer.update) == "function" then
                    widget._customRenderer.update(widget, ctx)
                elseif type(widget._customRenderer.render) == "function" then
                    widget._customRenderer.render(widget, ctx)
                end
            end
        end
    end
    return true
end

function CardSessionMixin:GetWidget(cardId, widgetKey)
    if self.released then return nil end
    local cardState = self.byId[cardId]
    if not cardState then return nil end
    local state = self.grid.ContainerStates[cardState.body]
    return state and state.widgets and state.widgets[widgetKey] or nil
end

function CardSessionMixin:FindWidget(widgetKey)
    if self.released then return nil end
    local found, foundCardId
    for _, cardState in ipairs(self.cards) do
        local state = self.grid.ContainerStates[cardState.body]
        local widget = state and state.widgets and state.widgets[widgetKey]
        if widget then
            if found and found ~= widget then
                error("[ExwindGrid] widget key is not unique across cards: "
                    .. tostring(widgetKey) .. "; pass cardId to GetWidget", 2)
            end
            found, foundCardId = widget, cardState.id
        end
    end
    return found, foundCardId
end

local function ReleaseCardBody(session, cardState)
    cardState.contentGeneration = (cardState.contentGeneration or 0) + 1
    local released, releaseReason = pcall(session.grid.ReleaseContainerWidgets,
        session.grid, cardState.body)
    session.grid.ContainerStates[cardState.body] = nil
    session.grid:ClearContainerCols(cardState.body)
    session.grid:ClearContainerPadding(cardState.body)
    cardState.widgetsByOrdinal = {}
    cardState.identityByOrdinal = {}
    cardState.renderableCount = 0
    cardState.reportedHeight = nil
    cardState.lastContentHeight = nil
    if not released then error(releaseReason, 0) end
end

function CardSessionMixin:ReplaceCardContent(cardId, content)
    if self.released then return false end
    local cardState = self.byId[cardId]
    if not cardState then error("[ExwindGrid] unknown cardId: " .. tostring(cardId), 2) end
    local ok, reason = ValidateCardContent(self.grid, content,
        "[ExwindGrid] " .. CardLocation(self.context, cardId))
    if not ok then error(reason, 2) end
    if CardContentOwnsScroll(content) ~= CardContentOwnsScroll(cardState.content) then
        error("[ExwindGrid] " .. CardLocation(self.context, cardId)
            .. ": changing content.ownsScroll requires releasing and remounting the card session", 2)
    end
    local previousContent = cardState.content
    local previousBinding = cardState.binding
    local previousSourceItems = cardState.sourceItems
    local nextBinding = ResolveCardBinding(self, cardState.definition, content)
    local nextSourceItems = BuildCardContentSource(cardState, content)
    local released, releaseReason = pcall(ReleaseCardBody, self, cardState)
    if not released then
        local activation = SnapshotGridActivation(self.grid)
        local restored, restoreReason = pcall(MountCardBody, self.grid, cardState)
        RestoreGridActivation(self.grid, activation)
        if not restored then
            local invalidated, invalidateReason = pcall(self.Release, self)
            local message = tostring(releaseReason) .. "; rollback failed: " .. tostring(restoreReason)
            if not invalidated then
                message = message .. "; session invalidation failed: " .. tostring(invalidateReason)
            end
            error(message, 2)
        end
        error(releaseReason, 2)
    end
    cardState.content = content
    cardState.binding = nextBinding
    cardState.sourceItems = nextSourceItems
    local activation = SnapshotGridActivation(self.grid)
    local mounted, mountReason = pcall(MountCardBody, self.grid, cardState)
    RestoreGridActivation(self.grid, activation)
    if not mounted then
        local cleaned, cleanupReason = pcall(ReleaseCardBody, self, cardState)
        cardState.content = previousContent
        cardState.binding = previousBinding
        cardState.sourceItems = previousSourceItems
        activation = SnapshotGridActivation(self.grid)
        local restored, restoreReason = pcall(MountCardBody, self.grid, cardState)
        RestoreGridActivation(self.grid, activation)
        if not restored then
            local message = tostring(mountReason)
            if not cleaned then
                message = message .. "; failed-content cleanup failed: " .. tostring(cleanupReason)
            end
            message = message .. "; rollback failed: " .. tostring(restoreReason)
            local invalidated, invalidateReason = pcall(self.Release, self)
            if not invalidated then
                message = message .. "; session invalidation failed: " .. tostring(invalidateReason)
            end
            error(message, 2)
        end
        if not cleaned then
            error(tostring(mountReason) .. "; failed-content cleanup failed: "
                .. tostring(cleanupReason), 2)
        end
        error(mountReason, 2)
    end
    self.grid:RequestReflow(cardState.body)
    return true
end

function CardSessionMixin:RebindCardContent(cardId)
    if self.released then return false end
    local cardState = self.byId[cardId]
    if not cardState then error("[ExwindGrid] unknown cardId: " .. tostring(cardId), 2) end
    return self:ReplaceCardContent(cardId, cardState.content)
end

function CardSessionMixin:SetCardVisible(cardId, visible)
    if self.released then return false end
    local cardState = self.byId[cardId]
    if not cardState then error("[ExwindGrid] unknown cardId: " .. tostring(cardId), 2) end
    visible = visible ~= false
    if cardState.visible == visible then return false end
    cardState.visible = visible
    self.grid:RequestReflow(cardState.card)
    return true
end

function CardSessionMixin:SetCardCollapsed(cardId, collapsed, silent)
    if self.released then return false end
    local cardState = self.byId[cardId]
    if not cardState then error("[ExwindGrid] unknown cardId: " .. tostring(cardId), 2) end
    cardState.card:SetCollapsed(collapsed == true, silent == true)
    if silent == true then self.grid:RequestReflow(cardState.card) end
    return true
end

function CardSessionMixin:Release()
    if self.released then return false end
    self.released = true
    self.generation = self.generation + 1
    self.reflowScheduled = nil
    self.reflowPending = nil
    self.reflowTicket = (self.reflowTicket or 0) + 1
    local scrollFrame = self.context and self.context.scrollFrame
    local scrollSessions = scrollFrame and self.grid.CardScrollSessions[scrollFrame]
    if scrollSessions then scrollSessions[self] = nil end
    local firstReleaseReason
    local function Capture(ok, reason)
        if not ok and firstReleaseReason == nil then firstReleaseReason = reason end
    end
    for index = #self.cards, 1, -1 do
        local cardState = self.cards[index]
        if type(cardState.card.SetLayoutInvalidationHandler) == "function" then
            Capture(pcall(cardState.card.SetLayoutInvalidationHandler, cardState.card, nil))
        end
        Capture(pcall(ReleaseCardBody, self, cardState))
        self.grid.CardSessionOwners[cardState.body] = nil
        self.grid.CardSessionOwners[cardState.card] = nil
        if type(cardState.card.Release) == "function" then
            Capture(pcall(cardState.card.Release, cardState.card))
        end
        self.cards[index] = nil
    end
    if self.grid.CardSessions[self.parent] == self then self.grid.CardSessions[self.parent] = nil end
    self.grid.CardSessionOwners[self.parent] = nil
    self.byId = {}
    if firstReleaseReason ~= nil then error(firstReleaseReason, 0) end
    return true
end

function Grid:MountCards(parent, declaration, context)
    if not parent then error("[ExwindGrid] MountCards requires parent", 2) end
    context = type(context) == "table" and context or {}
    local ok, reason = self:ValidateCardDeclaration(declaration, context)
    if not ok then error(reason, 2) end
    if type(EXUI.CreateSettingsCard) ~= "function" then
        error("[ExwindGrid] EXUI:CreateSettingsCard is not available", 2)
    end
    local existing = self.CardSessions[parent]
    if existing and not existing.released then
        error("[ExwindGrid] parent already owns an active card session; Release it before remounting", 2)
    end

    local session = setmetatable({
        grid = self,
        parent = parent,
        declaration = declaration,
        context = context,
        cards = {},
        byId = {},
        diagnostics = {},
        _diagnosticKeys = {},
        generation = 1,
    }, { __index = CardSessionMixin })
    self.CardSessions[parent] = session
    self.CardSessionOwners[parent] = { session = session }

    local snapshot = SnapshotGridActivation(self)
    local mounted, mountReason = pcall(function()
        local previous
        for _, definition in ipairs(declaration.cards) do
            local card = EXUI:CreateSettingsCard(parent, {
                id = definition.id,
                title = definition.title,
                icon = definition.icon,
                headerIcon = definition.headerIcon,
                collapsible = definition.collapsible == true,
                collapsed = definition.collapsed == true,
                minBodyHeight = tonumber(definition.minBodyHeight) or 0,
                maxBodyHeight = definition.maxBodyHeight and tonumber(definition.maxBodyHeight) or nil,
                ownsScroll = CardContentOwnsScroll(definition.content),
            })
            if not card then
                error("[ExwindGrid] " .. CardLocation(context, definition.id)
                    .. ": CreateSettingsCard returned nil", 0)
            end
            if type(card.GetBody) ~= "function"
                or type(card.SetContentHeight) ~= "function"
                or type(card.SetLayoutInvalidationHandler) ~= "function"
                or type(card.GetPreferredHeight) ~= "function"
                or type(card.SetCollapsed) ~= "function"
                or type(card.Release) ~= "function" then
                if type(card.Release) == "function" then
                    pcall(card.Release, card)
                else
                    if type(card.Hide) == "function" then pcall(card.Hide, card) end
                    if type(card.SetParent) == "function" then pcall(card.SetParent, card, nil) end
                end
                error("[ExwindGrid] " .. CardLocation(context, definition.id)
                    .. ": SettingsCard does not implement the required layout contract", 0)
            end
            local gotBody, body = pcall(card.GetBody, card)
            if not gotBody or not body then
                pcall(card.Release, card)
                error("[ExwindGrid] " .. CardLocation(context, definition.id)
                    .. ": SettingsCard:GetBody() did not return a body frame", 0)
            end
            local cardState = {
                session = session,
                id = definition.id,
                definition = definition,
                content = definition.content,
                card = card,
                body = body,
                previous = previous,
                visible = definition.hidden ~= true and definition.visible ~= false,
                widgetsByOrdinal = {},
            }
            session.cards[#session.cards + 1] = cardState
            session.byId[cardState.id] = cardState
            previous = cardState
            self.CardSessionOwners[card] = { session = session, card = cardState }
            self.CardSessionOwners[body] = { session = session, card = cardState }
            cardState.binding = ResolveCardBinding(session, definition, definition.content)
            cardState.sourceItems = BuildCardContentSource(cardState, definition.content)
            card:SetCollapsed(definition.collapsed == true, true)
            card:SetLayoutInvalidationHandler(function()
                self:RequestReflow(card)
            end)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
            SetCardWidth(card, math.max(1, parent:GetWidth()))
            card:SetShown(cardState.visible)
            MountCardBody(self, cardState)
        end
    end)
    RestoreGridActivation(self, snapshot)
    if not mounted then
        local released, releaseReason = pcall(session.Release, session)
        if not released then
            error(tostring(mountReason) .. "; session cleanup failed: "
                .. tostring(releaseReason), 0)
        end
        error(mountReason, 0)
    end

    if not parent._exCardSessionSizeHook then
        parent._exCardSessionSizeHook = true
        parent:HookScript("OnSizeChanged", function(host, width)
            local owner = Grid.CardSessionOwners[host]
            local active = owner and owner.session
            if active and not active.released then
                width = tonumber(width) or host:GetWidth()
                if active._lastParentWidth == nil
                    or math.abs(active._lastParentWidth - width) >= 0.01 then
                    active._lastParentWidth = width
                    Grid:RequestReflow(host)
                end
            end
        end)
    end
    session._lastParentWidth = parent:GetWidth()

    local scrollFrame = context.scrollFrame
    if scrollFrame and type(scrollFrame.HookScript) == "function" then
        local scrollSessions = self.CardScrollSessions[scrollFrame]
        if not scrollSessions then
            scrollSessions = setmetatable({}, { __mode = "k" })
            self.CardScrollSessions[scrollFrame] = scrollSessions
        end
        scrollSessions[session] = true
        if not scrollFrame._exGridCardSessionSizeHook then
            scrollFrame._exGridCardSessionSizeHook = true
            scrollFrame:HookScript("OnSizeChanged", function(host)
                local activeSessions = Grid.CardScrollSessions[host]
                if not activeSessions then return end
                for active in pairs(activeSessions) do
                    if not active.released then Grid:RequestReflow(active.parent) end
                end
            end)
        end
    end
    local laidOut, layoutReason = pcall(session.Relayout, session)
    if not laidOut then
        local released, releaseReason = pcall(session.Release, session)
        if not released then
            error(tostring(layoutReason) .. "; session cleanup failed: "
                .. tostring(releaseReason), 0)
        end
        error(layoutReason, 0)
    end
    return session
end

-- Unified mounted-page accessors.  Shared page/preview code should use these
-- instead of assuming that every control lives directly in ContainerStates.
-- The legacy single-grid route remains the fallback when no card session owns
-- the supplied container.
function Grid:GetMountedCardSession(container)
    local session = container and self.CardSessions[container] or nil
    if session and not session.released then return session end
    return nil
end

function Grid:GetMountedOwner(container)
    local session = self:GetMountedCardSession(container)
    if session then return session end
    return container and self.ContainerStates[container] or nil
end

function Grid:IsMountedOwnerCurrent(container, owner)
    if not container or not owner then return false end
    local session = self:GetMountedCardSession(container)
    if session then return session == owner end
    return self.ContainerStates[container] == owner
end

function Grid:GetMountedContainerStates(container)
    local mounted = {}
    local session = self:GetMountedCardSession(container)
    if session then
        for _, cardState in ipairs(session.cards) do
            local state = self.ContainerStates[cardState.body]
            if state then
                mounted[#mounted + 1] = {
                    state = state,
                    container = cardState.body,
                    cardId = cardState.id,
                }
            end
        end
        return mounted, session
    end

    local state = container and self.ContainerStates[container] or nil
    if state then
        mounted[1] = { state = state, container = container }
    end
    return mounted, state
end

function Grid:FindMountedWidget(container, widgetKey, cardId)
    local session = self:GetMountedCardSession(container)
    if session then
        local widget, resolvedCardId
        if cardId ~= nil then
            widget = session:GetWidget(cardId, widgetKey)
            resolvedCardId = cardId
        else
            widget, resolvedCardId = session:FindWidget(widgetKey)
        end
        local cardState = resolvedCardId and session.byId[resolvedCardId] or nil
        local body = cardState and cardState.body or nil
        local state = body and self.ContainerStates[body] or nil
        return widget, state, resolvedCardId, body
    end

    local state = container and self.ContainerStates[container] or nil
    local widget = state and state.widgets and state.widgets[widgetKey] or nil
    return widget, state, nil, container
end

function Grid:RefreshMountedValues(container)
    local session = self:GetMountedCardSession(container)
    if session then
        session:RefreshValues()
        return true
    end
    if container and self.ContainerStates[container] then
        self:RefreshContainerControlsFromDB(container)
        return true
    end
    return false
end

function Grid:GetLiveCardSession()
    local session = self.LiveCardSession
    if session and not session.released then return session end
    session = self.LiveContainer and self:GetMountedCardSession(self.LiveContainer) or nil
    return session
end

local function HideEditorGuideSet(lines)
    for _, region in ipairs(lines or {}) do
        if region and region.Hide then region:Hide() end
    end
end

function Grid:ActivateLiveEditContainer(container)
    if not self.IsLiveEditing or not container then return false end
    local state = self.ContainerStates[container]
    if not state then return false end

    if self.LiveEditContainer ~= container then
        HideEditorGuideSet(self.GridLines)
        HideEditorGuideSet(self.RowGuides)
    end
    ActivateContainerState(self, container, state)
    self.LiveEditContainer = container
    self:UpdateMetrics(container:GetWidth(), container)
    self:DrawEditorGrid(container)
    self:DrawRowGuides(container)
    return true
end

function Grid:WrapCardBodyForLiveEdit(cardState)
    if not cardState or not cardState.body or cardState.content.kind ~= "grid" then return false end
    local state = self.ContainerStates[cardState.body]
    if not state then return false end
    for key, widget in pairs(state.widgets or {}) do
        self:WrapWidgetForEdit(widget, key, cardState.body)
    end
    return true
end

-- Flat 页面继续直接 Render；Card 页面则只重建被编辑的 Body，并继续使用原
-- Card session 做测量、定位与回收。这样在线编辑不会把多卡声明压成一张平面表。
function Grid:RefreshLiveEditLayout(container)
    container = container or self.LiveEditContainer or self.LiveContainer
    local owner = container and self.CardSessionOwners[container]
    if owner and owner.session and owner.card and not owner.session.released then
        local session, cardState = owner.session, owner.card
        if cardState.content.kind ~= "grid" then return false end
        session:ReplaceCardContent(cardState.id, cardState.content)
        self:ActivateLiveEditContainer(cardState.body)
        self:WrapCardBodyForLiveEdit(cardState)
        if self.PropPanel then self.PropPanel:Hide() end
        self.Cur = nil
        return true
    end

    if not container then return false end
    self:Render(container, self.ActiveLayout, self.LastConfig, self.ModuleKey)
    return true
end

function Grid:ToggleLiveEdit(container)
    local cardSession = container and self:GetMountedCardSession(container) or nil
    if container and not cardSession then
        local state = GetContainerState(self, container)
        ActivateContainerState(self, container, state)
    end
    self.IsLiveEditing = not self.IsLiveEditing
    self.LiveContainer = container

    if self.IsLiveEditing then
        self.LiveCardSession = cardSession
        if cardSession then
            local firstEditable
            for _, cardState in ipairs(cardSession.cards) do
                if cardState.content.kind == "grid" then
                    firstEditable = firstEditable or cardState.body
                    self:WrapCardBodyForLiveEdit(cardState)
                end
            end
            if firstEditable then self:ActivateLiveEditContainer(firstEditable) end
        elseif container then
            self._activeContainer = container
            self.LiveEditContainer = container
            self:UpdateMetrics(container:GetWidth(), container)
            self:BeginModuleSpecExportSession(container)
            self:DrawEditorGrid(container)
            self:DrawRowGuides(container) -- [新增] 绘制行号尺
            for k, w in pairs(self.Widgets) do self:WrapWidgetForEdit(w, k, container) end
        end
        self:ShowToolbar(); self:ShowPalette(); self:CreatePropertyPanel()

        print(L["|cff00ffff[ExwindGrid]|r 编辑模式已激活。请在左侧点击行号进行管理。"])
    else
        HideEditorGuideSet(self.GridLines)
        HideEditorGuideSet(self.RowGuides)

        -- 恢复容器状态
        if container and not self.LiveCardSession then
            container:EnableMouse(false)
            -- 清理脚本以防万一
            if container.SetScript then
            end
        end

        if self.LiveCardSession and not self.LiveCardSession.released then
            for _, cardState in ipairs(self.LiveCardSession.cards) do
                local state = self.ContainerStates[cardState.body]
                for _, widget in ipairs(state and state.instances or {}) do
                    if widget.dragOverlay then widget.dragOverlay:Hide() end
                end
            end
        else
            for _, w in pairs(self.Widgets) do if w.dragOverlay then w.dragOverlay:Hide() end end
        end
        if self.LiveToolbar then self.LiveToolbar:Hide() end
        if self.Palette then self.Palette:Hide() end
        if self.PropPanel then self.PropPanel:Hide() end
        self.LiveCardSession = nil
        self.LiveEditContainer = nil
        self.Cur = nil
    end
end

function Grid:ShiftRows(startY, delta)
    for _, item in ipairs(self.ActiveLayout) do
        if item.y >= startY then
            item.y = item.y + delta
            self:RecordModuleSpecLayoutChange(item, { y = item.y })
        end
    end
    -- 修正可能的负数 y
    for _, item in ipairs(self.ActiveLayout) do
        if item.y < 1 then
            item.y = 1
            self:RecordModuleSpecLayoutChange(item, { y = item.y })
        end
    end
    self:RefreshLiveEditLayout(self.LiveEditContainer or self.LiveContainer)
end

function Grid:ShowRowContextMenu(row, x, y)
    if not self.ContextMenu then
        local cm = CreateFrame("Frame", "ExwindGridContextMenu", UIParent, "BackdropTemplate")
        cm:SetSize(140, 75)
        cm:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        cm:SetBackdropColor(0.05, 0.05, 0.1, 0.95)

        -- 保持高层级，确保在任何 Frame 之上
        cm:SetFrameStrata("TOOLTIP")
        cm:SetFrameLevel(9500)

        local function CreateMenuBtn(text, parent, yOff)
            local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
            btn:SetSize(125, 26)
            btn:SetPoint("TOP", 0, yOff)
            btn:SetText(text)
            return btn
        end

        cm.InsertBtn = CreateMenuBtn(L["插入行"], cm, -10)
        cm.InsertBtn:SetScript("OnClick", function()
            local targetRow = Grid.ContextMenu.targetRow
            Grid:ShiftRows(targetRow, 1)
            Grid.ContextMenu:Hide()
            if Grid.MenuCloser then Grid.MenuCloser:Hide() end
        end)

        cm.DeleteBtn = CreateMenuBtn(L["删除行"], cm, -38)
        cm.DeleteBtn:SetScript("OnClick", function()
            local targetRow = Grid.ContextMenu.targetRow
            Grid:ShiftRows(targetRow + 1, -1)
            Grid.ContextMenu:Hide()
            if Grid.MenuCloser then Grid.MenuCloser:Hide() end
        end)

        self.ContextMenu = cm
    end

    self.ContextMenu.targetRow = row
    self.ContextMenu:ClearAllPoints()
    self.ContextMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    self.ContextMenu:Show()

    if not self.MenuCloser then
        self.MenuCloser = CreateFrame("Button", nil, UIParent)
        self.MenuCloser:SetAllPoints()
        self.MenuCloser:SetFrameStrata("FULLSCREEN_DIALOG")
        self.MenuCloser:SetFrameLevel(9000)
        self.MenuCloser:SetScript("OnClick", function(f)
            f:Hide()
            Grid.ContextMenu:Hide()
        end)
    end
    self.MenuCloser:SetFrameLevel(9000)
    self.ContextMenu:SetFrameLevel(9500)

    self.MenuCloser:Show()
end

function Grid:WrapWidgetForEdit(widget, key, container)
    local drag = widget.dragOverlay or CreateFrame("Button", nil, container, "BackdropTemplate")
    drag:SetParent(container)
    drag:ClearAllPoints()
    drag:SetPoint("TOPLEFT", widget, "TOPLEFT")
    drag:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT")
    drag:SetFrameStrata(container:GetFrameStrata())
    drag:SetFrameLevel((container:GetFrameLevel() or 0) + 20)
    drag:EnableMouse(true)
    drag:RegisterForClicks("LeftButtonUp", "RightButtonUp"); drag:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); drag
        :SetBackdropColor(0, 0.5, 1, 0.15); drag:Show(); widget.dragOverlay = drag
    if widget.SetMovable then widget:SetMovable(true) end
    drag:SetScript("OnMouseDown",
        function(f, b)
            Grid:ActivateLiveEditContainer(container)
            if b == "LeftButton" then
                widget:StartMoving(); widget.isDragging = true
            end
        end)
    drag:SetScript("OnMouseUp", function(f, b)
        if b == "RightButton" then
            Grid:ShowPropertyPanelFor(key); return
        end
        if widget.isDragging then
            widget:StopMovingOrSizing(); widget.isDragging = false
            local lx, ly = widget:GetLeft() - container:GetLeft(), widget:GetTop() - container:GetTop()
            local nx, ny = Grid:GetGridPos(lx + 2, ly - 2, container)

            -- [v2.0 Fix] 使用反向索引查找 LayoutItem，不再遍历 ActiveLayout
            -- 这样即便是 TableGroup 深层子元素也能被正确更新位置
            if Grid.WidgetMap and Grid.WidgetMap[widget] then
                local meta = Grid.WidgetMap[widget]
                local item = meta.item

                -- 检测碰撞
                -- 严格来说 IsAreaEmpty 应该检测全局防止重叠
                if Grid:IsAreaEmpty(nx, ny, item.w, item.h, item.key) then -- 这里暂时检测全局
                    item.x, item.y = nx, ny
                    Grid:RecordModuleSpecLayoutChange(item, { x = item.x, y = item.y })
                    Grid:RefreshPropertyPanelPosition(item)
                end

                -- 刷新
                Grid:RefreshLiveEditLayout(container)
            end
        end
    end)

    -- [Resizer] 右下角调整大小手柄
    if not drag.resizer then
        local r = CreateFrame("Button", nil, drag)
        r:SetSize(12, 12)
        r:SetPoint("BOTTOMRIGHT", 0, 0)
        r:EnableMouse(true)
        r:RegisterForClicks("LeftButtonUp")
        r:SetFrameLevel(drag:GetFrameLevel() + 1)
        local t = EXUI:CreateVisualTexture(r, EXEDITORFRAME)
        t:SetAllPoints(); t:SetColorTexture(1, 1, 0, 0.5)
        drag.resizer = r
    end

    -- GridCard 会经对象池复用；这里每次进入编辑模式都重新绑定手柄，避免旧
    -- 卡片/旧容器的闭包残留，同时不干预卡片本身的拖动路径。
    local r = drag.resizer
    r:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        Grid:ActivateLiveEditContainer(container)
        widget.isDragging = false
        drag.isResizing = true
        r:SetScript("OnUpdate", function()
            local mx, my = GetCursorPosition()
            local s = widget:GetEffectiveScale()
            mx, my = mx / s, my / s
            local wx, wy = widget:GetLeft(), widget:GetTop()
            local newW = (mx - wx) + 5
            local newH = (wy - my) + 5

            -- Dropdown/LSM 的固定高度不仅是最终渲染规则，也是 Grid 编辑
            -- 规则；否则预览会在重绘后回到 30px，但逻辑 h 已扩大，留下
            -- 看不见的碰撞占位。固定高度控件在编辑时只允许调整宽度。
            local fixedHeight = widget._exGridFixedHeight
            local previewHeight = fixedHeight or math.max(10, newH)
            widget:SetSize(math.max(10, newW), previewHeight)

            -- 可选：显示 Tooltip 提示当前 Grid 网格大小
            local gw = math.max(1, math.floor(newW / Grid.CellSize + 0.5))
            local meta = Grid.WidgetMap and Grid.WidgetMap[widget]
            local gh = fixedHeight and (meta and meta.item.h or 1)
                or math.max(1, math.floor(newH / Grid.CellSize + 0.5))
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            GameTooltip:SetText(string.format("W: %d  H: %d", gw, gh))
            GameTooltip:Show()
        end)
    end)
    r:SetScript("OnMouseUp", function()
        if drag.isResizing then
            drag.isResizing = false
            r:SetScript("OnUpdate", nil)
            GameTooltip:Hide()

            local mx, my = GetCursorPosition()
            local s = widget:GetEffectiveScale()
            mx, my = mx / s, my / s
            local wx, wy = widget:GetLeft(), widget:GetTop()

            -- Calculate new Width/Height in Grid Units
            local gw = math.max(1, math.floor(((mx - wx) + 10) / Grid.CellSize))
            local gh = math.max(1, math.floor(((wy - my) + 10) / Grid.CellSize))

            -- Update using Reverse Index
            if Grid.WidgetMap and Grid.WidgetMap[widget] then
                local meta = Grid.WidgetMap[widget]
                local item = meta.item
                if widget._exGridFixedHeight then
                    gh = item.h
                end
                if Grid:IsAreaEmpty(item.x, item.y, gw, gh, item.key) then
                    item.w, item.h = gw, gh
                    Grid:RecordModuleSpecLayoutChange(item, { w = item.w, h = item.h })
                end
                Grid:RefreshLiveEditLayout(container)
            end
        end
    end)
    drag.resizer:SetFrameLevel(drag:GetFrameLevel() + 1)
    drag.resizer:Show()
end

-- [新增] 绘制左侧行号 Excel 风格
function Grid:DrawRowGuides(container)
    local rowGuides = self.EditorRowGuidesByContainer[container]
    if not rowGuides then
        rowGuides = {}
        self.EditorRowGuidesByContainer[container] = rowGuides
    end
    self.RowGuides = rowGuides
    -- 先隐藏旧的
    for _, b in ipairs(rowGuides) do b:Hide() end

    local rowsToDraw = 100 -- 默认画 100 行，如果内容更多可以扩展

    for i = 1, rowsToDraw do
        local btn = rowGuides[i]
        if not btn then
            -- 使用 Button 模板，天生支持 OnClick，无报错风险
            btn = CreateFrame("Button", nil, container, "BackdropTemplate")
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            btn:SetBackdropColor(0.2, 0.2, 0.2, 0.8) -- 深灰色背景
            btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.3)
            btn:RegisterForClicks("RightButtonUp")   -- 只响右键即可，或者左键也没事

            -- 行号文字
            btn.text = EXUI:CreateVisualFontString(btn, EXFONTFRAME, "GameFontHighlightSmall")
            btn.text:SetPoint("CENTER", 0, 0)

            rowGuides[i] = btn
        end

        -- 更新以适应当前的 Parent (container)
        btn:SetParent(container)
        btn:SetSize(20, self.CellSize) --稍微变窄一点，减少遮挡
        -- 位置：x = 0 (Canvas左侧内部), y = 对应行的 grid y
        local padding = self:GetContainerPadding(container)
        local py = -(i - 1) * self.CellSize - padding.top
        btn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, py)

        btn.text:SetText(i)

        -- 交互逻辑
        btn:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                Grid:ActivateLiveEditContainer(container)
                -- 呼出菜单
                local mx, my = GetCursorPosition()
                local s = self:GetEffectiveScale()
                mx, my = mx / s, my / s
                Grid:ShowRowContextMenu(i, mx, my)
            end
        end)

        -- 鼠标悬停变色效果
        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0, 0.6, 1, 0.8) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.2, 0.2, 0.8) end)

        btn:Show()
    end
end

-- [v4.3.2] 统一物理像素线宽计算 (参考暴雪源码)
local function SetupLineThickness(line, pixelWidth)
    local scale = line:GetEffectiveScale()
    if _G.PixelUtil and _G.PixelUtil.GetNearestPixelSize then
        line:SetThickness(_G.PixelUtil.GetNearestPixelSize(pixelWidth, scale, pixelWidth))
    else
        line:SetThickness(pixelWidth)
    end
end

function Grid:DrawEditorGrid(canvas)
    local gridLines = self.EditorGridLinesByContainer[canvas]
    if not gridLines then
        gridLines = {}
        self.EditorGridLinesByContainer[canvas] = gridLines
    end
    self.GridLines = gridLines
    -- 清理旧的（由于 Line 和 Texture 是不同对象，需要彻底重置）
    for _, l in ipairs(gridLines) do
        if l.Hide then l:Hide() end
    end

    local idx = 1
    local linePixelWidth = 1.2 -- 稍微加粗，确保可见
    local gridAlpha = 0.15     -- 提高透明度，确保在深色背景下可见
    local padding = self:GetContainerPadding(canvas)
    local cols = self:GetContainerCols(canvas) or self.Cols

    -- 绘制垂直线
    for i = 0, cols do
        local l = gridLines[idx]
        if not l or (l.GetObjectType and l:GetObjectType() ~= "Line") then
            l = canvas:CreateLine(nil, "BACKGROUND")
            gridLines[idx] = l
        end

        l:SetColorTexture(1, 1, 1, gridAlpha)
        -- [Fix] 显式传入 canvas 作为锚点目标，防止坐标偏移
        l:SetStartPoint("TOPLEFT", canvas, padding.left + i * self.CellSize, 0)
        l:SetEndPoint("BOTTOMLEFT", canvas, padding.left + i * self.CellSize, -3000)
        SetupLineThickness(l, linePixelWidth)
        l:Show()
        idx = idx + 1
    end

    -- 绘制水平线
    for i = 0, 150 do
        local l = gridLines[idx]
        if not l or (l.GetObjectType and l:GetObjectType() ~= "Line") then
            l = canvas:CreateLine(nil, "BACKGROUND")
            gridLines[idx] = l
        end

        l:SetColorTexture(1, 1, 1, gridAlpha)
        -- [Fix] 显式传入 canvas 作为锚点目标
        l:SetStartPoint("TOPLEFT", canvas, 0, -padding.top - i * self.CellSize)
        l:SetEndPoint("TOPRIGHT", canvas, 0, -padding.top - i * self.CellSize)
        SetupLineThickness(l, linePixelWidth)
        l:Show()
        idx = idx + 1
    end
end

function Grid:ShowToolbar()
    if self.LiveToolbar then
        if self.LiveToolbar.ExportButton then
            self.LiveToolbar.ExportButton:SetText(self:GetLiveCardSession()
                and L["导出 Card 包"] or L["导出导入包"])
        end
        self.LiveToolbar:Show(); return
    end
    local tb = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    tb:SetSize(500, 44)
    tb:SetPoint("TOP", 0, -10)
    tb:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    tb:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    tb:SetFrameStrata("HIGH")

    local b1 = CreateFrame("Button", nil, tb, "UIPanelButtonTemplate")
    b1:SetSize(140, 28); b1:SetPoint("LEFT", 10, 0)
    b1:SetText(self:GetLiveCardSession() and L["导出 Card 包"] or L["导出导入包"])
    b1:SetScript("OnClick", function() Grid:ExportImportPackage() end)
    tb.ExportButton = b1

    local b2 = CreateFrame("Button", nil, tb, "UIPanelButtonTemplate")
    b2:SetSize(100, 28); b2:SetPoint("LEFT", 155, 0); b2:SetText(L["保存退出"])
    b2:SetScript("OnClick", function() Grid:ToggleLiveEdit(Grid.LiveContainer) end)

    local b3 = CreateFrame("Button", nil, tb, "UIPanelButtonTemplate")
    b3:SetSize(100, 28); b3:SetPoint("LEFT", 260, 0); b3:SetText(L["组件库"])
    b3:SetScript("OnClick",
        function() if Grid.Palette:IsShown() then Grid.Palette:Hide() else Grid.Palette:Show() end end)

    local b4 = CreateFrame("Button", nil, tb, "UIPanelButtonTemplate")
    b4:SetSize(125, 28); b4:SetPoint("LEFT", 365, 0); b4:SetText(L["导出默认值"])
    b4:SetScript("OnClick", function() Grid:ExportDefaultsImportPackage() end)

    self.LiveToolbar = tb
end

function Grid:ShowPalette()
    if self.Palette then
        self.Palette:Show(); return
    end
    local p = CreateFrame("Frame", nil, UIParent, "BackdropTemplate"); p:SetSize(160, 500); p:SetPoint("RIGHT", -20, 0); p
        :SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }); p
        :SetBackdropColor(0.1, 0.1, 0.1, 0.95); p:SetFrameStrata("HIGH"); p:EnableMouse(true); p:SetMovable(true); p
        :RegisterForDrag("LeftButton"); p:SetScript("OnDragStart", p.StartMoving); p:SetScript("OnDragStop",
        p.StopMovingOrSizing)
    local types = {
        { t = "checkbox", n = L["勾选框"] }, { t = "button", n = L["按钮"] }, { t = "slider", n = L["滑动条"] }, { t = "input", n = L["输入框"] },
        { t = "header", n = L["大标题"] }, { t = "subheader", n = L["中标题"] }, { t = "divider", n = L["分隔线"] },
        { t = "label", n = L["文本"] }, { t = "description", n = L["描述"] }, { t = "card", n = L["卡片"] }, { t = "modulecommonsettings", n = L["模块通用设置"] }, { t = "custom", n = L["自定义宿主"] }, { t = "color", n = L["颜色"] },
        { t = "dropdown", n = L["单选下拉"] }, { t = "multiselect", n = L["多选下拉"] },
        { t = "lsm_font", n = L["LSM字体"] }, { t = "lsm_sound", n = L["LSM音效"] },
        { t = "lsm_texture", n = L["LSM材质"] }, { t = "lsm_border", n = L["LSM边框"] }, { t = "lsm_background", n = L["LSM背景"] },
        { t = "fontgroup", n = L["字体组"] },
        { t = "widgetlayout", n = L["Widget排列"] }, { t = "texturegroup", n = L["材质组"] }
    }
    local y = -15
    for _, i in ipairs(types) do
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate"); b:SetSize(140, 24); b:SetPoint("TOP", 0, y); b
            :SetText(i.n); b:SetScript("OnClick", function()
                Grid:AddNewWidget(i.t, Grid.LiveEditContainer or Grid.LiveContainer)
            end)
        y = y - 28
    end
    self.Palette = p
end

function Grid:AddNewWidget(t, c)
    c = c or self.LiveEditContainer or self.LiveContainer
    if c then self:ActivateLiveEditContainer(c) end
    local k = t .. "_" .. math.random(1000, 9999); local w, h = 12, 2
    if t == "checkbox" then
        w, h = 2, 2
    elseif t:find("header") or t == "divider" then
        w, h = 47, 1
    elseif t == "card" or t == "custom" or t == "modulecommonsettings" then
        w, h = 24, 8
    elseif t == "fontgroup" then
        w, h =
            47, 10
    elseif t == "widgetlayout" then
        w, h = 47, 10
    elseif t == "texturegroup" then
        w, h = 47, 21
    end
    local e = { key = k, type = t, x = 1, y = 1, w = w, h = h, label = L["新组件"] }
    if t == "card" then
        e.title = L["卡片标题"]
        e.desc = L["卡片描述"]
        e.allowOverlap = true
        e.accentAlign = "left"
    elseif t == "custom" then
        e.renderer = "Module.RendererKey"
        e.allowOverlap = false
    elseif t == "modulecommonsettings" then
        -- 直接使用正式 ModuleCommon 组件，不复制它的视觉常量；因此新增卡片的
        -- 背景、标题、绿色强调线与所有已封装设置组严格一致。
        e.label = L["模块通用设置"]
        -- 在线编辑器新增的它是可自由调整的背景卡片：与 card 一样不占用物理
        -- 碰撞格，也不把空 fields 的 20px 测量结果覆写用户声明的高度。
        e.allowOverlap = true
        e.measure = false
        e.opts = { bindRoot = true, fields = {}, gridEditableHeight = true }
    end
    if t == "slider" then
        e.min = 0; e.max = 100
    elseif t:find("dropdown") or t == "multiselect" then
        e.items = "A,B,C"
    end
    for i = 1, 200 do
        if t == "card" or t == "modulecommonsettings" or Grid:IsAreaEmpty(1, i, w, h) then
            e.y = i
            local owner = c and Grid.CardSessionOwners[c]
            if owner and owner.card and owner.card.content.kind == "grid" then
                table.insert(owner.card.content.items, e)
            else
                table.insert(Grid.ActiveLayout, e)
                Grid:RecordModuleSpecLayoutAddition(e)
            end
            break
        end
    end
    Grid:RefreshLiveEditLayout(c)
end

local function RemoveCardSourceItem(items, target)
    for index, item in ipairs(items or {}) do
        if item == target then
            table.remove(items, index)
            return true
        end
        if type(item.children) == "table" and RemoveCardSourceItem(item.children, target) then
            return true
        end
    end
    return false
end

function Grid:CreatePropertyPanel()
    if self.PropPanel then return end
    local p = CreateFrame("Frame", nil, UIParent, "BackdropTemplate"); p:SetSize(320, 780); p:SetPoint("LEFT", 20, 0); p
        :SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }); p
        :SetBackdropColor(0.05, 0.05, 0.1, 0.98); p:SetFrameStrata("DIALOG"); p:EnableMouse(true); p:SetMovable(true); p
        :RegisterForDrag("LeftButton"); p:SetScript("OnDragStart", p.StartMoving); p:SetScript("OnDragStop",
        p.StopMovingOrSizing)
    local function CI(l, y)
        local f = CreateFrame("Frame", nil, p); f:SetSize(280, 50); f:SetPoint("TOPLEFT", 20, y)
        local fs = EXUI:CreateVisualFontString(f, EXFONTFRAME, "GameFontHighlightSmall"); fs:SetPoint("TOPLEFT", 0, 0); fs
            :SetText(l)
        local eb = EXUI:CreateEditBox(f, "", 280, 26); eb:SetPoint("TOPLEFT", 0, -18); f.eb = eb; f.fs = fs; return f
    end

    -- [UI Polish] 压缩纵向间距 (从 60px -> 50px)，让底部内容上移
    p.k = CI(L["唯一 Key (Grid ID):"], -40)
    p.sk = CI(L["DB Key (setKey, 可选):"], -90)
    p.l = CI(L["显示标签:"], -140)
    p.w = CI(L["宽度 (1-50):"], -190); p.h = CI(L["高度:"], -240)
    -- Grid 的实时拖动和此面板必须共用 layout item 的 x/y；不要把它们映射到
    -- 模块 AnchorController 的世界坐标，二者是不同层级的唯一位置来源。
    p.x = CI(L["X轴:"], -290); p.y = CI(L["Y轴:"], -340)
    p.i = CI(L["选项列表 (逗号分隔):"], -390)
    p.min = CI(L["Slider 最小值:"], -440); p.max = CI(L["Slider 最大值:"], -490)

    -- [New] 标签位置与大小 (现在整体上移了约 100px)
    p.lpos = CI("Label Pos (left / top...):", -540)
    p.lsize = CI("Label Size (10-30):", -590)

    -- [Core] 切换为实时交互模式：隐藏输入框
    p.lpos.eb:Hide(); p.lsize.eb:Hide()

    -- [New] 标签大小滑块 (实时生效)
    p.lsize.slider = EXUI:CreateSlider(p.lsize, 260, nil, 10, 32, 16, 1, nil, function(v)
        local e = Grid.Cur
        if e then
            e.labelSize = v
            Grid:RecordModuleSpecLayoutChange(e, { labelSize = e.labelSize })
            p.lsize.fs:SetText("Label Size: " .. v)
            if Grid.Widgets[e.key] then
                -- [Real-time] 立即更新样式
                EXUI:UpdateLabelStyle(Grid.Widgets[e.key], e.labelSize, e.labelPos)
            end
        end
    end)
    p.lsize.slider:SetPoint("TOPLEFT", 0, -20) -- 稍微靠左对齐

    -- 标签位置切换按钮 (实时生效)
    local function CreatePosBtn(txt, val, x)
        local b = CreateFrame("Button", nil, p.lpos, "UIPanelButtonTemplate")
        b:SetSize(60, 22)
        -- 紧贴 label 下方布局
        b:SetPoint("TOPLEFT", x, -18)
        b:SetText(txt)
        b:SetScript("OnClick", function()
            local e = Grid.Cur
            if e then
                e.labelPos = val
                if e._exCardSourceItem then e._exCardSourceItem.labelPos = val end
                Grid:RecordModuleSpecLayoutChange(e, { labelPos = e.labelPos })
                -- [Real-time] 立即更新样式
                if Grid.Widgets[e.key] then
                    EXUI:UpdateLabelStyle(Grid.Widgets[e.key], e.labelSize, e.labelPos)
                end
            end
        end)
        return b
    end
    p.lpos.b1 = CreatePosBtn("Left", "left", 0)
    p.lpos.b2 = CreatePosBtn("Top", "top", 70)
    p.lpos.b3 = CreatePosBtn("Right", "right", 140)
    p.lpos.b4 = CreatePosBtn("Default", nil, 210); p.lpos.b4:SetWidth(60)

    local s = CreateFrame("Button", nil, p, "UIPanelButtonTemplate"); s:SetSize(130, 32); s:SetPoint("BOTTOMLEFT", 20, 20); s
        :SetText(L["保存设置"]); s:SetScript("OnClick", function()
        local e = Grid.Cur; if e then
            local before = { key = e.key, label = e.label, w = e.w, h = e.h, x = e.x, y = e.y }
            e.key = p.k.eb:GetText();
            -- [New] 保存 setKey
            local sk = p.sk.eb:GetText()
            e.setKey = (sk ~= "" and sk) or nil

            -- [修复] 将 UI 中的转义管道还原为普通管道存储
            e.label = p.l.eb:GetText():gsub("||", "|");
            e.w = tonumber(p.w.eb:GetText()) or e.w;
            e.h = tonumber(p.h.eb:GetText()) or e.h;
            -- 与 WrapWidgetForEdit 的拖动提交共用同一份 Grid layout 坐标。手输
            -- 坐标在保存后走 Render，因此页面会立即按新位置重新投影。
            e.x = math.max(1, math.floor(tonumber(p.x.eb:GetText()) or e.x or 1));
            e.y = math.max(1, math.floor(tonumber(p.y.eb:GetText()) or e.y or 1));
            if e.type == "slider" then
                e.min = tonumber(p.min.eb:GetText());
                e.max = tonumber(p.max.eb:GetText())
                -- [Revert] 移除 Step 保存逻辑
            end
            if p.i:IsShown() then
                local rawItems = p.i.eb:GetText():gsub("||", "|")
                if type(e.items) == "table" then
                    -- 表型下拉项用于结构化选项；属性面板当前仅做展示，不在这里降级成字符串
                else
                    e.items = rawItems
                end
            end

            local changes = {}
            for _, field in ipairs({ "key", "label", "w", "h", "x", "y" }) do
                if e[field] ~= before[field] then changes[field] = e[field] end
            end
            Grid:RecordModuleSpecLayoutChange(e, changes)
            if e._exCardSourceItem then
                -- nil 不能进入 changes 表；Card 纯声明需显式同步这些属性，
                -- 同时保持 legacy MODULE_SPEC 只接受原有可编辑字段的白名单。
                e._exCardSourceItem.setKey = e.setKey
                e._exCardSourceItem.min = e.min
                e._exCardSourceItem.max = e.max
                e._exCardSourceItem.items = e.items
            end

            -- [Core] Label 属性已由实时控件更新到 'e' 中，此处**不要**从隐藏的 EditBox 覆盖它们
        end
        p:Hide(); Grid:RefreshLiveEditLayout(Grid.LiveEditContainer or Grid.LiveContainer)
    end)


    local d = CreateFrame("Button", nil, p, "UIPanelButtonTemplate"); d:SetSize(130, 32); d:SetPoint("BOTTOMRIGHT", -20,
        20); d:SetText(L["|cffff0000删除组件|r"]); d:SetScript("OnClick", function()
        local current = Grid.Cur
        local source = current and current._exCardSourceItem
        local owner = Grid.LiveEditContainer and Grid.CardSessionOwners[Grid.LiveEditContainer]
        if source and owner and owner.card and owner.card.content.kind == "grid" then
            RemoveCardSourceItem(owner.card.content.items, source)
        else
            for i, e in ipairs(Grid.ActiveLayout) do
                if current and e.key == current.key then
                    Grid:RecordModuleSpecLayoutDeletion(e)
                    table.remove(Grid.ActiveLayout, i); break
                end
            end
        end
        p:Hide(); Grid:RefreshLiveEditLayout(Grid.LiveEditContainer or Grid.LiveContainer)
    end)
    self.PropPanel = p
end

-- 拖动的写入点在 WrapWidgetForEdit；属性面板若正显示该 layout item，必须立刻
-- 回读同一 x/y，不能维护第二份面板位置缓存。
function Grid:RefreshPropertyPanelPosition(item)
    local panel = self.PropPanel
    if not panel or not panel:IsShown() or self.Cur ~= item then
        return
    end
    panel.x.eb:SetText(tostring(item.x or 1))
    panel.y.eb:SetText(tostring(item.y or 1))
end

function Grid:ShowPropertyPanelFor(key)
    if not self.IsLiveEditing then return end

    -- [v4.3.1] 递归查找，支持 TableGroup 内部组件
    local item = FindLayoutItem(self.ActiveLayout, key)
    if not item then
        print(L["[ExwindGrid] 错误: 未找到组件配置: "] .. key); return
    end

    local panel = self.PropPanel
    if not panel then
        self:CreatePropertyPanel(); panel = self.PropPanel
    end
    Grid.Cur = item

    -- [修复] 使用双管道转义，防止 UI 引擎在 EditBox 内直接渲染图标代码
    panel.k.eb:SetText(item.key or "")
    panel.sk.eb:SetText(item.setKey or item.subKey or "")
    panel.l.eb:SetText((item.label or ""):gsub("|", "||"))
    panel.w.eb:SetText(tostring(item.w or 10))
    panel.h.eb:SetText(tostring(item.h or 2))
    panel.x.eb:SetText(tostring(item.x or 1))
    panel.y.eb:SetText(tostring(item.y or 1))

    panel.i:Hide(); panel.min:Hide(); panel.max:Hide()
    if item.type:find("dropdown") or item.type == "multiselect" then
        panel.i:Show()
        local itemsText = ""
        if type(item.items) == "string" then
            itemsText = item.items
        elseif type(item.items) == "table" then
            local parts = {}
            for _, entry in ipairs(item.items) do
                if type(entry) == "table" then
                    local label = tostring(entry[1] or "")
                    local value = tostring(entry[2] or entry[1] or "")
                    if value ~= "" and value ~= label then
                        parts[#parts + 1] = label .. "=" .. value
                    else
                        parts[#parts + 1] = label
                    end
                else
                    parts[#parts + 1] = tostring(entry)
                end
            end
            itemsText = table.concat(parts, ", ")
        end
        panel.i.eb:SetText(itemsText:gsub("|", "||"))
    end
    if item.type == "slider" then
        panel.min:Show(); panel.max:Show()
        panel.min.eb:SetText(tostring(item.min or 0))
        panel.max.eb:SetText(tostring(item.max or 100))
    end

    -- [New] 回填实时控件的状态
    if panel.lsize and panel.lsize.slider then
        panel.lsize.slider:SetValue(item.labelSize or 16)
        panel.lsize.fs:SetText("Label Size: " .. (item.labelSize or 16))
    end
    -- LabelPos 按钮不需要回填状态，点击即生效

    panel:Raise()
    panel:Show()
end

function Grid:ExportLayout()
    if self:GetLiveCardSession() then
        error(L["[ExwindGrid] Card 页面必须导出完整 version=1/cards 声明，不能扁平化为 legacy layout"], 2)
    end
    local layoutStr = "local layout = {\n"
    local defaults = {}

    local replacements = self.ExportReplacements or {}
    local exportReferences = self.ExportReferences or {}
    local localeAPI = _G.ExwindLocale
    local localeReverseMap

    local function ShouldForceLocaleLabelExport()
        if type(localeAPI) ~= "table" then
            return false
        end

        local currentLocale = type(localeAPI.GetCurrentLocale) == "function" and localeAPI.GetCurrentLocale() or
            localeAPI._currentLocale
        return currentLocale == "zhCN" or currentLocale == "zhTW"
    end

    local function BuildLocaleReverseMap()
        if localeReverseMap then
            return localeReverseMap
        end

        localeReverseMap = {}
        if type(localeAPI) ~= "table" or type(localeAPI._stores) ~= "table" then
            return localeReverseMap
        end

        local function AddStore(store)
            if type(store) ~= "table" then
                return
            end
            for key, value in pairs(store) do
                if type(key) == "string" and type(value) == "string" and localeReverseMap[value] == nil then
                    localeReverseMap[value] = key
                end
            end
        end

        AddStore(localeAPI._stores[localeAPI._currentLocale])
        AddStore(localeAPI._stores[localeAPI._defaultLocale])

        return localeReverseMap
    end

    local function TryFormatLocalizedLabel(labelValue)
        if type(labelValue) ~= "string" or labelValue == "" then
            return nil
        end

        local reverseMap = BuildLocaleReverseMap()
        local localeKey = reverseMap[labelValue]
        if type(localeKey) == "string" and localeKey ~= "" then
            return string.format(", label = L[%q]", localeKey)
        end

        if ShouldForceLocaleLabelExport() then
            return string.format(", label = L[%q]", labelValue)
        end

        return nil
    end

    local function FormatLabelValue(item)
        if type(item.labelExpr) == "string" and item.labelExpr ~= "" then
            return ", label = " .. item.labelExpr
        end

        if type(item.baseLabel) == "string" and item.baseLabel ~= "" then
            if item.baseLabel:match("^L%[.*%]$") then
                return ", label = " .. item.baseLabel
            end
            local localizedBaseLabel = TryFormatLocalizedLabel(item.baseLabel)
            if localizedBaseLabel then
                return localizedBaseLabel
            end
            return string.format(", label = %q", item.baseLabel)
        end

        local localizedLabel = TryFormatLocalizedLabel(item.label)
        if localizedLabel then
            return localizedLabel
        end

        if type(item.label) == "string" then
            return string.format(", label = %q", item.label)
        end
        if type(item.label) == "number" then
            return string.format(", label = %q", tostring(item.label))
        end
        return ", label = \"--[[ Function ]]\""
    end

    -- Helper: 格式化值
    local function formatVal(val, keyName)
        if type(val) == "string" and replacements[val] then
            return ", " .. keyName .. " = " .. replacements[val]
        else
            return ", " .. keyName .. " = " .. string.format("%q", val)
        end
    end

    -- 递归导出核心
    local function recursiveExport(items, indent, contextPath)
        local str = ""
        local pad = string.rep("    ", indent)

        for _, e in ipairs(items) do
            -- 1. 确定当前组件的数据上下文
            local itemScope = contextPath
            if e.parentKey then
                itemScope = itemScope and (itemScope .. "." .. e.parentKey) or e.parentKey
            end
            local fullPath = itemScope and (itemScope .. "." .. e.key) or tostring(e.key)

            -- 2. 导出属性字符串构造
            local ex = ""
            if e.min then ex = ex .. ", min = " .. e.min end; if e.max then ex = ex .. ", max = " .. e.max end

            if e.opts ~= nil then
                local optsExpression = exportReferences[e.opts] or replacements[e.opts]
                if type(optsExpression) == "string" and optsExpression ~= "" then
                    ex = ex .. ", opts = " .. optsExpression
                elseif type(e.opts) == "table" then
                    -- table 内含函数时不能安全反序列化；留下可见标记，要求模块登记命名引用，
                    -- 禁止像旧实现那样静默丢掉 opts。
                    ex = ex .. ", --[[ opts: use Grid:RegisterExportReference(table, \"MODULE_OPTS\") ]]"
                end
            end

            if e.items and e.items ~= "" then
                if replacements[e.items] then
                    ex = ex .. ", items = " .. replacements[e.items]
                elseif type(e.items) == "string" and e.items:sub(1, 5) == "func:" then
                    ex = ex .. ", items = " .. string.format("%q", e.items)
                elseif type(e.items) == "table" then
                    local function serializeTable(t)
                        local s = "{"
                        for k, v in ipairs(t) do
                            if type(v) == "table" then
                                s = s .. serializeTable(v)
                            else
                                s = s .. string.format("%q", v)
                            end
                            if k < #t then s = s .. ", " end
                        end
                        return s .. "}"
                    end
                    ex = ex .. ", items = " .. serializeTable(e.items)
                else
                    ex = ex .. ", items = " .. string.format("%q", e.items)
                end
            end

            if e.parentKey then ex = ex .. formatVal(e.parentKey, "parentKey") end
            if e.setKey then ex = ex .. formatVal(e.setKey, "setKey") end
            if e.subKey then ex = ex .. formatVal(e.subKey, "subKey") end
            if e.labelPos then ex = ex .. ", labelPos = " .. string.format("%q", e.labelPos) end
            if e.labelSize and e.labelSize ~= 16 then ex = ex .. ", labelSize = " .. e.labelSize end

            local labelStr = FormatLabelValue(e)

            local keyExport = (type(e.key) == "number") and tostring(e.key) or string.format("%q", tostring(e.key))

            -- 3. 收集默认值（核心更新：全量收集与颜色处理）
            local function AddToDefaults(path, val)
                if val == nil then return end
                local pathKeys = { strsplit(".", tostring(path)) }
                local ptr = defaults
                for i = 1, #pathKeys - 1 do
                    local k = tonumber(pathKeys[i]) or pathKeys[i]
                    if not ptr[k] then ptr[k] = {} end
                    ptr = ptr[k]
                end
                local lastK = tonumber(pathKeys[#pathKeys]) or pathKeys[#pathKeys]
                ptr[lastK] = val
            end

            local keyStr = tostring(e.key)
            if keyStr and not keyStr:find("^header") and not keyStr:find("^divider") and e.type ~= "TableGroup" then
                -- 颜色组件特殊处理：导出后缀格式 (xxxR, xxxG, xxxB, xxxA)
                if e.type == "color" then
                    local colorConfig = contextPath and GetConfigPath(self.LastConfig, contextPath) or self.LastConfig
                    if colorConfig then
                        local colorKey = tostring(e.key)
                        local basePath = contextPath and (contextPath .. ".") or ""
                        AddToDefaults(basePath .. colorKey .. "R", colorConfig[colorKey .. "R"] or 1)
                        AddToDefaults(basePath .. colorKey .. "G", colorConfig[colorKey .. "G"] or 1)
                        AddToDefaults(basePath .. colorKey .. "B", colorConfig[colorKey .. "B"] or 1)
                        AddToDefaults(basePath .. colorKey .. "A", colorConfig[colorKey .. "A"] or 1)
                    end
                else
                    AddToDefaults(e.setKey or fullPath,
                        (e.setKey and self.LastConfig[e.setKey]) or GetConfigPath(self.LastConfig, fullPath))
                end
            end

            -- 4. 处理递归与动态列表补全
            if e.type == "TableGroup" then
                if e.children and #e.children > 0 then
                    -- 动态索引探测：如果当前是 rows.1，则扫描 rows.2, 3... 补全 defaults 表
                    local prefix, idx = tostring(e.parentKey):match("^(.-)%.(%d+)$")
                    if prefix and idx then
                        local collection = GetConfigPath(self.LastConfig, prefix)
                        if type(collection) == "table" then
                            for i in pairs(collection) do recursiveExport(e.children, indent + 1, prefix .. "." .. i) end
                        end
                    end
                    str = str ..
                        string.format(
                            "%s{ key = %s, type = %q, x = %d, y = %d, w = %d, h = %d%s%s, children = {\n%s%s} },\n",
                            pad, keyExport, e.type, e.x, e.y, e.w, e.h, labelStr, ex,
                            recursiveExport(e.children, indent + 1, itemScope), pad)
                end
            else
                str = str ..
                    string.format("%s{ key = %s, type = %q, x = %d, y = %d, w = %d, h = %d%s%s },\n", pad, keyExport,
                        e.type,
                        e.x, e.y, e.w, e.h, labelStr, ex)
            end
        end
        return str
    end

    layoutStr = layoutStr .. recursiveExport(self.ActiveLayout, 1, nil)
    layoutStr = layoutStr .. "}\n"

    -- 自动补充顶层必要字段（如 pos）
    if self.LastConfig and self.LastConfig.pos and not defaults.pos then
        defaults.pos = self.LastConfig.pos
    end

    return layoutStr, defaults
end

-- 序列化表为 Lua 代码字符串
local function serializeTable(t, indent, localizeLabels)
    local s = "{\n"

    -- 检测是否是连续数组
    local isArray = true
    local maxIndex = 0
    for k, _ in pairs(t) do
        if type(k) == "number" and k > 0 and math.floor(k) == k then
            if k > maxIndex then maxIndex = k end
        else
            isArray = false
            break
        end
    end
    if isArray and maxIndex > 0 then
        for i = 1, maxIndex do
            if t[i] == nil then
                isArray = false; break
            end
        end
    end

    if isArray and maxIndex > 0 then
        -- 连续数组：使用隐式索引
        for i = 1, maxIndex do
            local v = t[i]
            s = s .. string.rep("    ", indent)
            if type(v) == "table" then
                s = s .. serializeTable(v, indent + 1, localizeLabels) .. ",\n"
            elseif type(v) == "string" then
                s = s .. string.format("%q", v) .. ",\n"
            else
                s = s .. tostring(v) .. ",\n"
            end
        end
    else
        -- 非连续表：使用显式键
        local keys = {}
        for k in pairs(t) do table.insert(keys, k) end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

        for _, k in ipairs(keys) do
            local v = t[k]
            local keyStr
            if type(k) == "number" then
                keyStr = "[" .. k .. "]"
            elseif type(k) == "string" and k:match("^[%a_][%w_]*$") then
                keyStr = k
            else
                keyStr = "[" .. string.format("%q", k) .. "]"
            end
            s = s .. string.rep("    ", indent) .. keyStr .. " = "
            if type(v) == "table" then
                s = s .. serializeTable(v, indent + 1, localizeLabels) .. ",\n"
            elseif type(v) == "string" then
                if localizeLabels and k == "label" then
                    s = s .. "L[" .. string.format("%q", v) .. "],\n"
                else
                    s = s .. string.format("%q", v) .. ",\n"
                end
            else
                s = s .. tostring(v) .. ",\n"
            end
        end
    end
    return s .. string.rep("    ", indent - 1) .. "}"
end

-- Card session 的 declaration 是登记纯声明的运行副本，也是在线编辑的结构真源。
-- 导出必须整棵保留 version/cards/placement/content，禁止把各 Body 拼回 legacy layout。
function Grid:BuildCardPageExportData()
    local session = self:GetLiveCardSession()
    if not session then return nil end
    local moduleKey = session.context and session.context.moduleKey or self.ModuleKey
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error(L["[ExwindGrid] 导出失败：当前页面没有模块标识"], 2)
    end
    local ok, reason = self:ValidateCardDeclaration(session.declaration, session.context)
    if not ok then error(reason, 2) end

    local defaults
    local declarations = ExwindTools.ModuleDefaultDeclarations
    if type(declarations) == "table" and declarations[moduleKey] then
        defaults = ExwindTools:ExportModuleDefaults(moduleKey)
    end
    return {
        moduleKey = moduleKey,
        gui = session.declaration,
        defaults = defaults,
    }
end

local function CopyModuleSpecExportValue(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error(L["[ExwindGrid] MODULE_SPEC 导出不支持循环表"], 3) end
    local copied = {}
    seen[value] = true
    for key, child in pairs(value) do
        copied[CopyModuleSpecExportValue(key, seen)] = CopyModuleSpecExportValue(child, seen)
    end
    seen[value] = nil
    return copied
end

local function CopyAddedLayoutItem(value, seen)
    if type(value) ~= "table" then
        if type(value) == "function" then error(L["[ExwindGrid] 新增组件不能导出运行时回调"], 3) end
        return value
    end
    seen = seen or {}
    if seen[value] then error(L["[ExwindGrid] 新增组件不能导出循环表"], 3) end
    local copied = {}
    seen[value] = true
    for key, child in pairs(value) do
        if type(key) ~= "string" or key:sub(1, 1) ~= "_" then
            copied[CopyAddedLayoutItem(key, seen)] = CopyAddedLayoutItem(child, seen)
        end
    end
    seen[value] = nil
    return copied
end

local function IndexModuleSpecGuiItems(items, index)
    for _, item in ipairs(items or {}) do
        if type(item) == "table" then
            local key = item.key and tostring(item.key) or nil
            if key then
                if index[key] then error(L["[ExwindGrid] MODULE_SPEC.gui 中存在重复 key："] .. key, 3) end
                index[key] = item
            end
            if type(item.children) == "table" then IndexModuleSpecGuiItems(item.children, index) end
        end
    end
end

local function PruneModuleSpecGuiItems(items, deletedKeys)
    local kept = {}
    for _, item in ipairs(items or {}) do
        if not deletedKeys[tostring(item.key)] then
            if type(item.children) == "table" then item.children = PruneModuleSpecGuiItems(item.children, deletedKeys) end
            kept[#kept + 1] = item
        end
    end
    return kept
end

local function ResolveCurrentModuleSpec(moduleKey)
    local getController = EXUI and EXUI.GetCentralModuleController
    local controller = type(getController) == "function" and getController(EXUI, moduleKey) or nil
    if type(controller) ~= "table" or type(controller.spec) ~= "table" then return nil end
    return CopyModuleSpecExportValue(controller.spec)
end

-- 将编辑会话投影回原 MODULE_SPEC 的可编辑部分。原始 gui 表是唯一真源：
-- 已有行仅允许改名称与格子位置/尺寸；删除与新增整行是仅有的结构性操作。
function Grid:BuildModuleSpecExportData()
    local moduleKey = self.ModuleKey
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error(L["[ExwindGrid] 导出失败：当前页面没有模块标识"], 2)
    end

    local spec = ResolveCurrentModuleSpec(moduleKey)
    if not spec then return nil, L["当前页面没有可导出的模块定义"] end
    if type(spec.gui) ~= "table" or type(spec.gui.static) ~= "table" or type(spec.gui.fields) ~= "table" then
        error(L["[ExwindGrid] 当前 MODULE_SPEC 缺少 gui.static/gui.fields"], 2)
    end

    -- 正式 defaults 声明决定可导出的字段；这里读的是当前游戏内 ModuleDB，
    -- 不会把运行时缓存或未声明字段混进源码。
    spec.defaults = ExwindTools:ExportModuleDefaults(moduleKey)

    local session = GetExportSession(self)
    if session then
        local deletedKeys = {}
        for id in pairs(session.deleted) do
            local baseline = session.baseline[id]
            if baseline then deletedKeys[tostring(baseline.sourceKey)] = true end
        end
        spec.gui.static = PruneModuleSpecGuiItems(spec.gui.static, deletedKeys)
        spec.gui.fields = PruneModuleSpecGuiItems(spec.gui.fields, deletedKeys)

        local sourceByKey = {}
        IndexModuleSpecGuiItems(spec.gui.static, sourceByKey)
        IndexModuleSpecGuiItems(spec.gui.fields, sourceByKey)
        for id, changes in pairs(session.changes) do
            local baseline = session.baseline[id]
            local target = baseline and sourceByKey[tostring(baseline.sourceKey)] or nil
            if target then
                for _, field in ipairs({ "label", "x", "y", "w", "h" }) do
                    if changes[field] ~= nil then target[field] = changes[field] end
                end
            end
        end

        local activeByID = {}
        WalkLayoutItems(self.ActiveLayout, function(item)
            if item._exGridExportID then activeByID[item._exGridExportID] = item end
        end)
        for _, id in ipairs(session.addedOrder or {}) do
            if not session.deleted[id] then
                local item = activeByID[id]
                if item then spec.gui.static[#spec.gui.static + 1] = CopyAddedLayoutItem(item) end
            end
        end
    end

    return { defaults = spec.defaults, gui = spec.gui }
end

function Grid:BuildModuleSpecExport()
    local data, reason = self:BuildModuleSpecExportData()
    if not data then return nil, reason end
    return "local MODULE_SPEC = " .. serializeTable(data, 1)
end

-- SPECIAL 等旧页面可以没有 MODULE_SPEC 和源码 GUI 真源，但只要模块正式声明了
-- 默认值，就仍可安全导出 defaults；绝不从 Grid 工作布局反推或导出它的 layout。
function Grid:BuildDeclaredDefaultsExportData()
    local moduleKey = self.ModuleKey
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error(L["[ExwindGrid] 导出默认值失败：当前页面没有模块标识"], 2)
    end
    local declarations = ExwindTools.ModuleDefaultDeclarations
    if type(declarations) ~= "table" or not declarations[moduleKey] then
        return nil, L["当前页面没有已声明的默认值真源"]
    end
    return { moduleKey = moduleKey, defaults = ExwindTools:ExportModuleDefaults(moduleKey) }
end

function Grid:ExportModuleSpec()
    local moduleSpecStr, reason = self:BuildModuleSpecExport()
    if not moduleSpecStr then
        print("|cffff8080[ExwindGrid]|r " .. (reason or L["当前页面没有可导出的模块定义"]))
        return false
    end
    StaticPopupDialogs["EX_EXPORT_MODULE_SPEC"] = {
        text = L["复制 MODULE_SPEC（当前预设默认值与 GUI 布局）:"],
        button1 = L["好的"],
        hasEditBox = 1,
        OnShow = function(dialog)
            dialog.EditBox:SetText(moduleSpecStr:gsub("|", "||"))
            dialog.EditBox:HighlightText()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("EX_EXPORT_MODULE_SPEC")
end

-- 独立默认值包不读取 MODULE_SPEC.gui，也不读取在线编辑器的工作布局。
-- 因此 SPECIAL 旧页面只要正式声明 defaults，就能安全导出给离线导入器。
function Grid:ExportDefaultsImportPackage()
    local defaultData, reason = self:BuildDeclaredDefaultsExportData()
    if not defaultData then
        print("|cffff8080[ExwindGrid]|r " .. (reason or L["当前页面没有可导出的默认值真源"]))
        return false
    end
    local package = "-- EXWIND_GRID_DEFAULTS_IMPORT v1\n"
        .. "local EXWIND_GRID_DEFAULTS_IMPORT = {\n"
        .. "    moduleKey = " .. string.format("%q", defaultData.moduleKey) .. ",\n"
        .. "    defaults = " .. serializeTable(defaultData.defaults, 2) .. ",\n"
        .. "}\n"
    StaticPopupDialogs["EX_EXPORT_DEFAULTS_IMPORT_PACKAGE"] = {
        text = L["复制默认值导入包（发送给 Codex 验收并导入）:"],
        button1 = L["好的"],
        hasEditBox = 1,
        OnShow = function(dialog)
            dialog.EditBox:SetText(package:gsub("|", "||"))
            dialog.EditBox:HighlightText()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("EX_EXPORT_DEFAULTS_IMPORT_PACKAGE")
    return true
end

-- 标准模块一律导出带模块名的完整包。离线验收脚本会先验证模块名、GUI 白名单
-- 与 defaults 字段形状，全部通过后才允许将这两个区块写回 MODULE_SPEC。
function Grid:ExportImportPackage()
    local moduleKey = self.ModuleKey
    local cardPage = self:BuildCardPageExportData()
    if cardPage then
        -- 目前没有游戏内 Card package importer；这是供复制、审查和源码回填
        -- 的完整导出载荷。名称不得暗示已经实现未授权的配置导入流程。
        local package = "-- EXWIND_GRID_CARD_EXPORT v1\n"
            .. "local EXWIND_GRID_CARD_EXPORT = {\n"
            .. "    moduleKey = " .. string.format("%q", cardPage.moduleKey) .. ",\n"
            .. "    gui = " .. serializeTable(cardPage.gui, 2, true) .. ",\n"
        if cardPage.defaults ~= nil then
            package = package .. "    defaults = " .. serializeTable(cardPage.defaults, 2) .. ",\n"
        end
        package = package .. "}\n"
        StaticPopupDialogs["EX_EXPORT_IMPORT_PACKAGE"] = {
            text = L["复制完整 Card 导出包（发送给 Codex 验收）:"],
            button1 = L["好的"],
            hasEditBox = 1,
            OnShow = function(dialog)
                dialog.EditBox:SetText(package:gsub("|", "||"))
                dialog.EditBox:HighlightText()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("EX_EXPORT_IMPORT_PACKAGE")
        return true
    end

    local moduleSpec, reason = self:BuildModuleSpecExportData()
    local package, dialogText
    if not moduleSpec then
        local defaultData, defaultsReason = self:BuildDeclaredDefaultsExportData()
        if not defaultData then
            print("|cffff8080[ExwindGrid]|r " .. (defaultsReason or reason or L["当前页面没有可导出的正式真源"]))
            return false
        end
        package = "-- EXWIND_GRID_DEFAULTS_IMPORT v1\n"
            .. "local EXWIND_GRID_DEFAULTS_IMPORT = {\n"
            .. "    moduleKey = " .. string.format("%q", defaultData.moduleKey) .. ",\n"
            .. "    defaults = " .. serializeTable(defaultData.defaults, 2) .. ",\n"
            .. "}\n"
        dialogText = L["复制默认值导入包（发送给 Codex 验收并导入）:"]
    else
        package = "-- EXWIND_GRID_IMPORT v1\n"
            .. "local EXWIND_GRID_IMPORT = {\n"
            .. "    moduleKey = " .. string.format("%q", moduleKey) .. ",\n"
            .. "    gui = " .. serializeTable(moduleSpec.gui, 2, true) .. ",\n"
            .. "    defaults = " .. serializeTable(moduleSpec.defaults, 2) .. ",\n"
            .. "}\n"
        dialogText = L["复制完整导入包（发送给 Codex 验收并导入）:"]
    end

    StaticPopupDialogs["EX_EXPORT_IMPORT_PACKAGE"] = {
        text = dialogText,
        button1 = L["好的"],
        hasEditBox = 1,
        OnShow = function(dialog)
            dialog.EditBox:SetText(package:gsub("|", "||"))
            dialog.EditBox:HighlightText()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("EX_EXPORT_IMPORT_PACKAGE")
end

-- 仅导出布局
function Grid:ExportLayoutOnly()
    local cardPage = self:BuildCardPageExportData()
    if cardPage then
        local layoutStr = "gui = " .. serializeTable(cardPage.gui, 1, true)
        StaticPopupDialogs["EX_EXPORT_LAYOUT"] = {
            text = L["复制 Card gui 区块（保留 version/cards 结构）:"],
            button1 = L["好的"],
            hasEditBox = 1,
            OnShow = function(dialog)
                dialog.EditBox:SetText(layoutStr:gsub("|", "||"))
                dialog.EditBox:HighlightText()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("EX_EXPORT_LAYOUT")
        return true
    end

    local moduleSpec, reason = self:BuildModuleSpecExportData()
    local layoutStr, dialogText
    if moduleSpec then
        -- 标准模块必须直接替换 MODULE_SPEC.gui；不能再给它遗留 layout 表，
        -- 否则 fields/static 的声明信息会在粘贴后丢失。
        layoutStr = "gui = " .. serializeTable(moduleSpec.gui, 1, true)
        dialogText = L["复制 gui 区块（替换 MODULE_SPEC 内的 gui）:"]
    else
        layoutStr = self:ExportLayout()
        dialogText = L["复制布局代码 (粘贴到模块结尾):"]
    end

    StaticPopupDialogs["EX_EXPORT_LAYOUT"] = {
        text = dialogText,
        button1 = L["好的"],
        hasEditBox = 1,
        OnShow = function(s)
            s.EditBox:SetText(layoutStr:gsub("|", "||"));
            s.EditBox:HighlightText()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true
    }
    StaticPopup_Show("EX_EXPORT_LAYOUT")
end

-- 仅导出默认值
function Grid:ExportDefaultsOnly()
    local moduleKey = self.ModuleKey
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error(L["[ExwindGrid] 导出默认值失败：当前页面没有模块标识"], 2)
    end

    local moduleSpec = self:BuildModuleSpecExportData()
    local defaultsStr, dialogText
    if moduleSpec then
        -- 标准模块直接替换 MODULE_SPEC.defaults，保留其余 MODULE_SPEC 字段。
        defaultsStr = "defaults = " .. serializeTable(moduleSpec.defaults, 1)
        dialogText = L["复制 defaults 区块（替换 MODULE_SPEC 内的 defaults）:"]
    else
        -- 旧页面（例如 MiniTools）没有 MODULE_SPEC 时，导出当前 Grid 已声明字段的
        -- 预设值，绝不整表搬运 ModuleDB。
        local registered = ExwindTools.ModuleDefaultDeclarations and ExwindTools.ModuleDefaultDeclarations[moduleKey]
        local defaults
        if registered then
            defaults = ExwindTools:ExportModuleDefaults(moduleKey)
        else
            local _, gridDefaults = self:ExportLayout()
            defaults = gridDefaults
        end
        defaultsStr = "local EX_DEFAULTS = " .. serializeTable(defaults, 1)
        dialogText = L["复制默认值代码 (粘贴到模块开头):"]
    end

    StaticPopupDialogs["EX_EXPORT_DEFAULTS"] = {
        text = dialogText,
        button1 = L["好的"],
        hasEditBox = 1,
        OnShow = function(s)
            s.EditBox:SetText(defaultsStr:gsub("|", "||"));
            s.EditBox:HighlightText()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true
    }
    StaticPopup_Show("EX_EXPORT_DEFAULTS")
end

function ExwindTools:ToggleDevMode()
    if not self.UI or not self.UI.ActivePageFrame then
        return
    end
    self.Grid:ToggleLiveEdit(self.UI.ActivePageFrame)
end
