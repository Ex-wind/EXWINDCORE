-- =========================================================
-- ExwindDevMonitor.lua - 实时性能监控面板
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
if not EXUI then return end

local M = {}
ExwindTools.DevMonitor = M
M.name = "DevMonitor"

-- =========================================================
-- 配置常量
-- =========================================================
local THEME = {
    BG_DARK = { 0.02, 0.02, 0.03, 0.95 },
    BG_PANEL = { 0.08, 0.08, 0.12, 0.9 },
    BORDER = { 0.4, 0.15, 0.6, 1 },
    PRIMARY = { 0.64, 0.19, 0.79, 1 },
    SUCCESS = { 0.2, 0.9, 0.4, 1 },
    WARNING = { 1, 0.8, 0.2, 1 },
    DANGER = { 1, 0.3, 0.3, 1 },
    TEXT_BRIGHT = { 0.95, 0.95, 1, 1 },
    TEXT_DIM = { 0.5, 0.5, 0.6, 1 },
}

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

local UPDATE_INTERVAL = 0.5 -- 仪表盘刷新间隔（秒）
local MAX_HISTORY = 60      -- 性能历史记录点数
local MAX_POOL_ROWS = 40    -- 池行预创建上限
local ROW_HEIGHT = 50       -- 每行池监控高度

-- =========================================================
-- 数据存储
-- =========================================================
local MonitorFrame = nil
local isMinimized = false
local updateTimer = 0

-- 性能历史数据
local perfHistory = {
    cpu = {},
    mem = {},
}

-- 池总量峰值快照（用于算出空闲数）
local poolPeakTotal = {}

-- 上次展开的地址弹窗
local activePopup = nil

-- =========================================================
-- 工具函数
-- =========================================================

-- 格式化地址（去除 "table: " 前缀）
local function FormatAddress(obj)
    return tostring(obj):gsub("table: ", ""):sub(1, 14)
end

-- 获取颜色（根据使用率）
local function GetUsageColor(usage)
    if usage < 0.5 then
        return THEME.SUCCESS
    elseif usage < 0.8 then
        return THEME.WARNING
    else
        return THEME.DANGER
    end
end

-- 创建渐变背景纹理
local function CreateGradientBG(parent)
    local tex = EXUI:CreateVisualTexture(parent, EXBACKGROUNDFRAME)
    tex:SetAllPoints()
    tex:SetColorTexture(1, 1, 1)
    tex:SetGradient("VERTICAL",
        CreateColor(0.08, 0.08, 0.12, 0.95),
        CreateColor(0.04, 0.04, 0.06, 0.98))
    return tex
end

-- =========================================================
-- 数据采集
-- =========================================================

-- 采集当前性能数据
local function CollectPerfData()
    UpdateAddOnCPUUsage()
    UpdateAddOnMemoryUsage()

    local cpu = GetAddOnCPUUsage("ExwindCore") or 0
    local mem = GetAddOnMemoryUsage("ExwindCore") or 0

    table.insert(perfHistory.cpu, cpu)
    table.insert(perfHistory.mem, mem)
    if #perfHistory.cpu > MAX_HISTORY then table.remove(perfHistory.cpu, 1) end
    if #perfHistory.mem > MAX_HISTORY then table.remove(perfHistory.mem, 1) end

    return cpu, mem
end

-- 采集框架池状态
-- WoW 原生 CreateFramePool 只公开 GetNumActive()，
-- 用 poolPeakTotal 追踪峰值总量推算空闲数。
-- 活跃对象地址由 EXFactory.ActiveTracker 维护（见 ExwindFramePool.lua）。
local function CollectPoolStats()
    local EXFactory = _G.ExwindFactory
    if not EXFactory or not EXFactory.Pools then return {} end

    local stats = {}

    for poolType, pool in pairs(EXFactory.Pools) do
        local activeCount = pool:GetNumActive() or 0

        -- 更新峰值总量（总量只增不减，池不会销毁已创建的 Frame）
        poolPeakTotal[poolType] = math.max(poolPeakTotal[poolType] or 0, activeCount)
        local totalCount = poolPeakTotal[poolType]
        local inactiveCount = totalCount - activeCount

        -- 收集活跃对象地址（来自追踪表）
        local activeObjects = {}
        if EXFactory.ActiveTracker and EXFactory.ActiveTracker[poolType] then
            for obj in pairs(EXFactory.ActiveTracker[poolType]) do
                table.insert(activeObjects, obj)
            end
        end

        stats[poolType] = {
            active = activeCount,
            inactive = inactiveCount,
            total = totalCount,
            usage = totalCount > 0 and (activeCount / totalCount) or 0,
            objects = activeObjects,
        }
    end

    return stats
end

-- =========================================================
-- UI 组件创建
-- =========================================================

-- 创建标题栏
local function CreateTitleBar(parent)
    local titleBar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    titleBar:SetSize(parent:GetWidth(), 34)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    titleBar:SetBackdropColor(0.05, 0.05, 0.08, 1)

    -- 标题文字
    local title = EXUI:CreateVisualFontString(titleBar, EXFONTFRAME, "GameFontNormalLarge")
    title:SetPoint("LEFT", 15, 0)
    title:SetText("|cffA330C9ExwindTools|r |cff666666Dev Monitor|r")

    -- 状态指示灯（闪烁）
    local indicator = EXUI:CreateVisualTexture(titleBar, EXBORDERFRAME)
    indicator:SetSize(8, 8)
    indicator:SetPoint("LEFT", title, "RIGHT", 10, 0)
    indicator:SetTexture("Interface\\Buttons\\WHITE8X8")
    indicator:SetVertexColor(0.2, 0.9, 0.4, 1)

    local flash = titleBar:CreateAnimationGroup()
    local a1 = flash:CreateAnimation("Alpha")
    a1:SetFromAlpha(1); a1:SetToAlpha(0.2); a1:SetDuration(0.8); a1:SetSmoothing("IN_OUT")
    local a2 = flash:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.2); a2:SetToAlpha(1); a2:SetDuration(0.8); a2:SetSmoothing("IN_OUT")
    a2:SetStartDelay(0.8)
    flash:SetLooping("REPEAT")
    flash:Play()

    -- 最小化按钮
    local minBtn = CreateFrame("Button", nil, titleBar)
    minBtn:SetSize(24, 24)
    minBtn:SetPoint("RIGHT", -35, 0)
    minBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    minBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    minBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    minBtn:SetScript("OnClick", function() M:ToggleMinimize() end)

    -- 关闭按钮
    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", -5, 0)
    closeBtn:SetSize(24, 24)
    closeBtn:SetScript("OnClick", function() M:Hide() end)

    -- 拖拽
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() parent:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() parent:StopMovingOrSizing() end)

    return titleBar
end

-- 创建按钮区（标题栏下方一排功能按钮）
local function CreateButtonBar(parent)
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetSize(parent:GetWidth() - 20, 32)
    bar:SetPoint("TOPLEFT", 10, -40)
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    bar:SetBackdropColor(0.06, 0.06, 0.09, 0.95)

    -- 通用小按钮工厂
    local function MakeBtn(text, x, onClick)
        local btn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        btn:SetSize(100, 24)
        btn:SetPoint("LEFT", x, 0)
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    -- GC 测试
    MakeBtn("GC 测试", 8, function()
        if ExwindDevGC then ExwindDevGC() end
    end)

    -- 性能快照
    MakeBtn("性能快照", 114, function()
        if ExwindTools.RecordPerfStats then
            local s = ExwindTools.RecordPerfStats("手动快照")
            print("|cffA330C9ExwindDev:|r " .. (s or "无数据"))
        end
    end)

    -- 重置峰值统计
    MakeBtn("重置峰值", 220, function()
        wipe(poolPeakTotal)
    end)

    return bar
end

-- 创建性能仪表盘
local function CreatePerfDashboard(parent)
    local dashboard = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    dashboard:SetSize(parent:GetWidth() - 20, 90)
    dashboard:SetPoint("TOPLEFT", 10, -78)
    dashboard:SetBackdrop(BACKDROP)
    dashboard:SetBackdropColor(unpack(THEME.BG_PANEL))
    dashboard:SetBackdropBorderColor(unpack(THEME.BORDER))

    -- 标题
    local title = EXUI:CreateVisualFontString(dashboard, EXFONTFRAME, "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("|cffA330C9性能监控|r")

    -- CPU
    local cpuLabel = EXUI:CreateVisualFontString(dashboard, EXFONTFRAME, "GameFontHighlightSmall")
    cpuLabel:SetPoint("TOPLEFT", 10, -28)
    cpuLabel:SetText("CPU:")
    local cpuValue = EXUI:CreateVisualFontString(dashboard, EXFONTFRAME, "GameFontNormalLarge")
    cpuValue:SetPoint("LEFT", cpuLabel, "RIGHT", 5, 0)
    cpuValue:SetText("0.00s")
    cpuValue:SetTextColor(unpack(THEME.SUCCESS))
    dashboard.cpuValue = cpuValue

    local cpuBar = CreateFrame("StatusBar", nil, dashboard)
    cpuBar:SetSize(140, 10)
    cpuBar:SetPoint("TOPLEFT", 10, -52)
    cpuBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    cpuBar:SetStatusBarColor(0.64, 0.19, 0.79, 0.8)
    cpuBar:SetMinMaxValues(0, 100)
    cpuBar:SetValue(0)
    local cpuBarBg = EXUI:CreateVisualTexture(cpuBar, EXBACKGROUNDFRAME)
    cpuBarBg:SetAllPoints(); cpuBarBg:SetColorTexture(0.1, 0.1, 0.15, 0.5)
    dashboard.cpuBar = cpuBar

    -- 内存
    local memLabel = EXUI:CreateVisualFontString(dashboard, EXFONTFRAME, "GameFontHighlightSmall")
    memLabel:SetPoint("TOPLEFT", 190, -28)
    memLabel:SetText("内存:")
    local memValue = EXUI:CreateVisualFontString(dashboard, EXFONTFRAME, "GameFontNormalLarge")
    memValue:SetPoint("LEFT", memLabel, "RIGHT", 5, 0)
    memValue:SetText("0 MB")
    memValue:SetTextColor(unpack(THEME.SUCCESS))
    dashboard.memValue = memValue

    local memBar = CreateFrame("StatusBar", nil, dashboard)
    memBar:SetSize(140, 10)
    memBar:SetPoint("TOPLEFT", 190, -52)
    memBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    memBar:SetStatusBarColor(0.2, 0.9, 0.4, 0.8)
    memBar:SetMinMaxValues(0, 50)
    memBar:SetValue(0)
    local memBarBg = EXUI:CreateVisualTexture(memBar, EXBACKGROUNDFRAME)
    memBarBg:SetAllPoints(); memBarBg:SetColorTexture(0.1, 0.1, 0.15, 0.5)
    dashboard.memBar = memBar

    -- FPS
    local fpsLabel = EXUI:CreateVisualFontString(dashboard, EXFONTFRAME, "GameFontHighlightSmall")
    fpsLabel:SetPoint("TOPLEFT", 370, -28)
    fpsLabel:SetText("FPS:")
    local fpsValue = EXUI:CreateVisualFontString(dashboard, EXFONTFRAME, "GameFontNormalLarge")
    fpsValue:SetPoint("LEFT", fpsLabel, "RIGHT", 5, 0)
    fpsValue:SetText("60")
    fpsValue:SetTextColor(unpack(THEME.SUCCESS))
    dashboard.fpsValue = fpsValue

    -- 延迟
    local latencyLabel = EXUI:CreateVisualFontString(dashboard, EXFONTFRAME, "GameFontHighlightSmall")
    latencyLabel:SetPoint("TOPLEFT", 370, -52)
    latencyLabel:SetText("延迟:")
    local latencyValue = EXUI:CreateVisualFontString(dashboard, EXFONTFRAME, "GameFontNormal")
    latencyValue:SetPoint("LEFT", latencyLabel, "RIGHT", 5, 0)
    latencyValue:SetText("0ms")
    latencyValue:SetTextColor(unpack(THEME.SUCCESS))
    dashboard.latencyValue = latencyValue

    return dashboard
end

-- 预创建单个池监控行（含 StatusBar，一次性创建后复用）
local function CreatePoolRow(content)
    local row = CreateFrame("Button", nil, content, "BackdropTemplate")
    row:SetSize(content:GetWidth() - 10, ROW_HEIGHT)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    row:SetBackdropColor(0.1, 0.1, 0.15, 0.6)
    row:Hide()

    -- 类型名
    row.typeName = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontNormalSmall")
    row.typeName:SetPoint("TOPLEFT", 8, -5)

    -- 状态统计文字
    row.statusText = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlightSmall")
    row.statusText:SetPoint("TOPLEFT", 8, -20)

    -- 使用率进度条（预创建，值为0，不闪烁）
    row.usageBar = CreateFrame("StatusBar", nil, row)
    row.usageBar:SetSize(180, 10)
    row.usageBar:SetPoint("TOPLEFT", 8, -36)
    row.usageBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.usageBar:SetMinMaxValues(0, 1)
    row.usageBar:SetValue(0)
    row.usageBar:SetStatusBarColor(unpack(THEME.SUCCESS))
    local bg = EXUI:CreateVisualTexture(row.usageBar, EXBACKGROUNDFRAME)
    bg:SetAllPoints(); bg:SetColorTexture(0.1, 0.1, 0.12, 0.8)

    -- 使用率百分比文字
    row.usageText = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlightSmall")
    row.usageText:SetPoint("LEFT", row.usageBar, "RIGHT", 5, 0)

    -- 活跃对象地址文字（点击可展开）
    row.addrText = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlightSmall")
    row.addrText:SetPoint("LEFT", row.usageText, "RIGHT", 12, 0)
    row.addrText:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    row.addrText:SetJustifyH("LEFT")
    row.addrText:SetWordWrap(false)
    row.addrText:SetText("")

    -- 点击地址文字弹出详细列表
    row:EnableMouse(true)
    row:SetScript("OnClick", function(self)
        local poolType = self._poolType
        if not poolType then return end
        -- 关闭旧弹窗
        if activePopup then
            activePopup:Hide(); activePopup = nil
        end

        local EXFactory = _G.ExwindFactory
        if not EXFactory or not EXFactory.ActiveTracker or not EXFactory.ActiveTracker[poolType] then
            return
        end
        local objects = EXFactory.ActiveTracker[poolType]
        local count = 0
        for _ in pairs(objects) do count = count + 1 end
        if count == 0 then return end

        -- 创建弹窗
        local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        popup:SetSize(280, math.min(count * 18 + 30, 300))
        popup:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -4)
        popup:SetFrameStrata("TOOLTIP")
        popup:SetBackdrop(BACKDROP)
        popup:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
        popup:SetBackdropBorderColor(unpack(THEME.BORDER))

        local header = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", 8, -6)
        header:SetText("|cffA330C9" .. poolType .. "|r 活跃对象 (" .. count .. ")")

        -- 滚动区域
        local sf = CreateFrame("ScrollFrame", nil, popup, "ScrollFrameTemplate")
        sf:EnableMouseWheel(true)
        sf:SetPoint("TOPLEFT", 6, -24)
        sf:SetPoint("BOTTOMRIGHT", -24, 4)
        local sc = CreateFrame("Frame", nil, sf)
        sc:SetSize(sf:GetWidth(), 1)
        sf:SetScrollChild(sc)

        local y = 0
        for obj in pairs(objects) do
            local fs = EXUI:CreateVisualFontString(sc, EXFONTFRAME, "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", 4, -y)
            fs:SetText("|cff88aaff" .. tostring(obj) .. "|r")
            y = y + 16
        end
        sc:SetHeight(math.max(y, sf:GetHeight()))

        activePopup = popup
    end)

    return row
end

-- 创建框架池监控面板（预创建所有行）
local function CreatePoolMonitor(parent)
    local monitor = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    monitor:SetPoint("TOPLEFT", 10, -175)
    monitor:SetPoint("BOTTOMRIGHT", -10, 10)
    monitor:SetBackdrop(BACKDROP)
    monitor:SetBackdropColor(unpack(THEME.BG_PANEL))
    monitor:SetBackdropBorderColor(unpack(THEME.BORDER))

    -- 标题
    local title = EXUI:CreateVisualFontString(monitor, EXFONTFRAME, "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("|cffA330C9框架池状态|r |cff666666(实时，点击查看地址)|r")

    -- 滚动框架
    local scrollFrame = CreateFrame("ScrollFrame", nil, monitor, "ScrollFrameTemplate")
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetPoint("TOPLEFT", 10, -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 8)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(content)

    monitor.scrollFrame = scrollFrame
    monitor.content = content

    -- 预创建行
    monitor.poolRows = {}
    for i = 1, MAX_POOL_ROWS do
        monitor.poolRows[i] = CreatePoolRow(content)
    end

    return monitor
end

-- =========================================================
-- 更新函数
-- =========================================================

-- 更新性能仪表盘（每周期调用，只更新文字和 SetValue，无闪烁）
function M:UpdateDashboard()
    if not MonitorFrame or not MonitorFrame.dashboard then return end

    local cpu, mem = CollectPerfData()
    local d = MonitorFrame.dashboard

    -- CPU
    d.cpuValue:SetFormattedText("%.2fs", cpu)
    d.cpuBar:SetValue(math.min(100, (cpu / 10) * 100))
    if cpu < 1 then
        d.cpuValue:SetTextColor(unpack(THEME.SUCCESS))
    elseif cpu < 5 then
        d.cpuValue:SetTextColor(unpack(THEME.WARNING))
    else
        d.cpuValue:SetTextColor(unpack(THEME.DANGER))
    end

    -- 内存
    local memMB = mem / 1024
    d.memValue:SetFormattedText("%.2f MB", memMB)
    d.memBar:SetValue(memMB)
    if memMB < 10 then
        d.memValue:SetTextColor(unpack(THEME.SUCCESS))
    elseif memMB < 30 then
        d.memValue:SetTextColor(unpack(THEME.WARNING))
    else
        d.memValue:SetTextColor(unpack(THEME.DANGER))
    end

    -- FPS
    local fps = GetFramerate()
    d.fpsValue:SetFormattedText("%d", fps)
    if fps >= 60 then
        d.fpsValue:SetTextColor(unpack(THEME.SUCCESS))
    elseif fps >= 30 then
        d.fpsValue:SetTextColor(unpack(THEME.WARNING))
    else
        d.fpsValue:SetTextColor(unpack(THEME.DANGER))
    end

    -- 延迟
    local _, _, latency = GetNetStats()
    latency = latency or 0
    d.latencyValue:SetFormattedText("%dms", latency)
    if latency < 50 then
        d.latencyValue:SetTextColor(unpack(THEME.SUCCESS))
    elseif latency < 150 then
        d.latencyValue:SetTextColor(unpack(THEME.WARNING))
    else
        d.latencyValue:SetTextColor(unpack(THEME.DANGER))
    end
end

-- 更新框架池监控（复用预创建行，只修改文字和 SetValue）
function M:UpdatePoolMonitor()
    if not MonitorFrame or not MonitorFrame.poolMonitor then return end

    local monitor = MonitorFrame.poolMonitor
    local stats = CollectPoolStats()

    -- 按池总量由大到小排序；同量时按类型名稳定排序。
    local sortedTypes = {}
    for poolType in pairs(stats) do
        table.insert(sortedTypes, poolType)
    end
    table.sort(sortedTypes, function(a, b)
        local totalA = stats[a].total or 0
        local totalB = stats[b].total or 0
        if totalA == totalB then
            return a < b
        end
        return totalA > totalB
    end)

    local yOffset = 0
    for idx, poolType in ipairs(sortedTypes) do
        local stat = stats[poolType]
        local row = monitor.poolRows[idx]
        if not row then break end -- 超出预创建数量

        -- 定位和显示
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", monitor.content, "TOPLEFT", 5, -yOffset)
        row:Show()
        row._poolType = poolType

        -- 更新文字
        row.typeName:SetText("|cffA330C9" .. poolType .. "|r")
        row.statusText:SetFormattedText("活跃: |cff00ff00%d|r  空闲: |cff888888%d|r  总计: |cffffffff%d|r",
            stat.active, stat.inactive, stat.total)

        -- 更新进度条（直接 SetValue，无闪烁）
        row.usageBar:SetValue(stat.usage)
        local color = GetUsageColor(stat.usage)
        row.usageBar:SetStatusBarColor(unpack(color))

        -- 更新百分比
        row.usageText:SetFormattedText("%.0f%%", stat.usage * 100)

        -- 更新地址预览（最多显示3个，点击可展开全部）
        if #stat.objects > 0 then
            local addrs = {}
            for i = 1, math.min(3, #stat.objects) do
                table.insert(addrs, FormatAddress(stat.objects[i]))
            end
            local suffix = #stat.objects > 3 and (" +" .. (#stat.objects - 3)) or ""
            row.addrText:SetText("|cff888888" .. table.concat(addrs, " ") .. suffix .. "|r")
        else
            row.addrText:SetText("")
        end

        yOffset = yOffset + ROW_HEIGHT + 4
    end

    -- 隐藏多余的预创建行
    for idx = #sortedTypes + 1, #monitor.poolRows do
        monitor.poolRows[idx]:Hide()
    end

    -- 调整内容高度
    monitor.content:SetHeight(math.max(yOffset, monitor.scrollFrame:GetHeight()))
end

-- =========================================================
-- 主框架创建
-- =========================================================

function M:CreateMonitorFrame()
    if MonitorFrame then return end

    local f = CreateFrame("Frame", "ExwindDevMonitorFrame", UIParent, "BackdropTemplate")
    f:SetSize(1100, 900)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)

    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(unpack(THEME.BG_DARK))
    f:SetBackdropBorderColor(unpack(THEME.BORDER))

    CreateGradientBG(f)

    -- 子组件（顺序决定布局）
    f.titleBar    = CreateTitleBar(f)
    f.buttonBar   = CreateButtonBar(f)
    f.dashboard   = CreatePerfDashboard(f)
    f.poolMonitor = CreatePoolMonitor(f)

    -- 更新循环
    f:SetScript("OnUpdate", function(_, elapsed)
        updateTimer = updateTimer + elapsed
        if updateTimer >= UPDATE_INTERVAL then
            updateTimer = 0
            M:UpdateDashboard()
            M:UpdatePoolMonitor()
        end
    end)

    f:Hide()
    MonitorFrame = f
end

-- =========================================================
-- 公共接口
-- =========================================================

function M:Show()
    if not MonitorFrame then self:CreateMonitorFrame() end
    MonitorFrame:Show()
    M:UpdateDashboard()
    M:UpdatePoolMonitor()
end

function M:Hide()
    if MonitorFrame then MonitorFrame:Hide() end
end

function M:Toggle()
    if not MonitorFrame then self:CreateMonitorFrame() end
    if MonitorFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function M:ToggleMinimize()
    if not MonitorFrame then return end
    isMinimized = not isMinimized
    if isMinimized then
        MonitorFrame:SetHeight(34)
        MonitorFrame.buttonBar:Hide()
        MonitorFrame.dashboard:Hide()
        MonitorFrame.poolMonitor:Hide()
    else
        MonitorFrame:SetHeight(900)
        MonitorFrame.buttonBar:Show()
        MonitorFrame.dashboard:Show()
        MonitorFrame.poolMonitor:Show()
    end
end

-- =========================================================
-- 命令注册
-- =========================================================

local oldExCommand = SlashCmdList["EX"]
if oldExCommand then
    SlashCmdList["EX"] = function(msg)
        local arg = (msg or ""):trim():lower()
        if arg == "devmonitor" or arg == "dm" then
            M:Toggle()
            return
        end
        oldExCommand(msg)
    end
end
