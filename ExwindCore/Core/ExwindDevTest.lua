-- =========================================================
-- ExwindDevTest.lua - 开发调试工具套件
-- 集成性能分析、实时监控
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local M = {}
ExwindTools.DevTest = M
M.name = "DevTest"

-- =========================================================
-- 性能记录
-- =========================================================

-- 记录性能统计
local function RecordPerfStats(tag)
    if not ExwindTools.DevTestMode then return end

    UpdateAddOnCPUUsage()
    UpdateAddOnMemoryUsage()

    local name = "ExwindCore"
    local cpuRaw = GetAddOnCPUUsage(name)
    local memRaw = GetAddOnMemoryUsage(name)

    local cpuVal = cpuRaw        -- 秒
    local memVal = memRaw / 1024 -- MB

    local memStr = string.format("%.2f MB", memVal)
    local cpuStr = string.format("%.2f s", cpuVal)

    return "CPU: " .. cpuStr .. " 内存: " .. memStr
end

-- 暴露给外部调用
ExwindTools.RecordPerfStats = RecordPerfStats

-- =========================================================
-- GC 测试工具
-- =========================================================

function ExwindDevGC()
    if not ExwindTools.DevTestMode then
        print("|cffff5555请先输入 |cff00ff00/ex devtestmode|r |cffff5555开启调试模式|r")
        return
    end

    local statsHistory = {}

    local function GetMem()
        UpdateAddOnMemoryUsage()
        return GetAddOnMemoryUsage("ExwindCore") / 1024
    end

    local function RunStep(step)
        local before = GetMem()
        collectgarbage("collect")
        local after = GetMem()

        table.insert(statsHistory, { step = step, before = before, after = after })

        print(string.format(
            "|cffA330C9ExwindDev:|r [Step %d] GC Before: |cffffaa55%.2fMB|r -> After: |cff55ff55%.2fMB|r",
            step, before, after))
    end

    print("|cffA330C9ExwindDev:|r 开始 GC 性能测试 (共 5 次)")
    RunStep(1)

    local count = 1
    C_Timer.NewTicker(1, function()
        count = count + 1
        RunStep(count)

        if count >= 5 then
            print("|cffA330C9ExwindDev:|r 测试完成。")
            print("|cff00ffff=== GC 测试结果汇总 ===|r")
            print("次数 | GC前(MB) | GC后(MB) | 回收量(MB)")
            for _, s in ipairs(statsHistory) do
                local diff = s.before - s.after
                print(string.format("  %d   |   %.2f   |   %.2f   |   %.2f",
                    s.step, s.before, s.after, diff))
            end
            print("|cff00ffff=======================|r")

        end
    end, 4)
end

-- =========================================================
-- Hook 系统
-- =========================================================

local hooksInitialized = false

local function InitHooks()
    if hooksInitialized then return end
    hooksInitialized = true

    -- Hook 主界面操作
    local EXUI = ExwindTools.UI
    if EXUI then
        if EXUI.MainFrame then
            EXUI.MainFrame:HookScript("OnShow", function()
                RecordPerfStats("界面打开")
            end)
            EXUI.MainFrame:HookScript("OnHide", function()
                RecordPerfStats("界面关闭")
            end)
        end

        -- Hook 模块切换
        if EXUI.ShowModuleSettingsPage then
            hooksecurefunc(EXUI, "ShowModuleSettingsPage", function(self)
                local currentModule = ExwindTools.State.SelectedModule or "Unknown"
                RecordPerfStats("切换模块: " .. currentModule)
            end)
        end
    end
end

-- =========================================================
-- 命令处理
-- =========================================================

local function HookExCommand()
    local oldFunc = SlashCmdList["EX"]
    if not oldFunc then return end

    SlashCmdList["EX"] = function(msg)
        local arg = (msg or ""):trim():lower()

        -- 调试模式开关
        if arg == "devtestmode" then
            ExwindTools.DevTestMode = not ExwindTools.DevTestMode

            local status = ExwindTools.DevTestMode and "|cff55ff55开启|r" or "|cffff5555关闭|r"
            print("|cffA330C9Exwind 工具调试模式:|r " .. status)

            if ExwindTools.DevTestMode then
                InitHooks()
                RecordPerfStats("初始化")

                -- 自动打开监控面板
                if ExwindTools.DevMonitor then
                    C_Timer.After(0.1, function()
                        ExwindTools.DevMonitor:Show()
                    end)
                end
            else
                -- 关闭监控面板
                if ExwindTools.DevMonitor then
                    ExwindTools.DevMonitor:Hide()
                end
            end
            return
        end

        -- 性能快照
        if arg == "devstats" or arg == "devperf" then
            local stats = RecordPerfStats("手动快照")
            print("|cffA330C9ExwindDev:|r " .. stats)
            return
        end

        -- GC 测试
        if arg == "devgc" then
            ExwindDevGC()
            return
        end

        -- 帮助信息
        if arg == "devhelp" then
            print("|cffA330C9=== ExwindDev 调试工具 ===|r")
            print("|cff00ff00/ex devtestmode|r - 开启/关闭调试模式")
            print("|cff00ff00/ex devmonitor|r 或 |cff00ff00/ex dm|r - 打开实时监控面板")
            print("|cff00ff00/ex devstats|r - 显示性能快照")
            print("|cff00ff00/ex devgc|r - 运行 GC 测试")
            return
        end

        -- 调用原有的处理逻辑
        oldFunc(msg)
    end
end

-- 延迟 Hook
C_Timer.After(1, HookExCommand)

-- =========================================================
-- 导出
-- =========================================================
