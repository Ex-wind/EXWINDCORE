-- =========================================================
-- ExwindPanelTheme.lua
-- 三合一面板的唯一视觉与几何真源。
-- 本文件只定义 Shell token；不读取 Provider 数据、不创建业务控件。
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExwindTools.PanelTheme = ExwindTools.PanelTheme or {
    Layout = {
        APP_RAIL_WIDTH = 58,
        HEADER_HEIGHT = 26,
        -- Tab 只是路由切换，不应占用接近一列控件的垂直空间。
        TOP_TAB_HEIGHT = 32,
        TOP_TAB_FONT_SIZE = 14,
        CONTENT_GUTTER = 12,
        -- 所有 B+C 左右布局的唯一比例：B=25%，C=75%。不得由 Provider 覆写。
        NAV_RATIO = 0.25,
        PREVIEW_DOCK_HEIGHT = 160,
        SPLIT_CONTENT_GRID_COLS = 200,
        FULL_CONTENT_GRID_COLS = 64,
        DEFAULT_WIDTH = 1440,
        DEFAULT_HEIGHT = 900,
        MIN_WIDTH = 1100,
        MIN_HEIGHT = 700,
    },

    Color = {
        panel = { 0.055, 0.070, 0.095, 0.985 },
        rail = { 0.065, 0.080, 0.110, 1 },
        header = { 0.055, 0.070, 0.095, 0.96 },
        nav = { 0.070, 0.090, 0.120, 1 },
        content = { 0.045, 0.058, 0.080, 1 },
        card = { 0.085, 0.105, 0.140, 0.96 },
        cardAlt = { 0.070, 0.086, 0.118, 0.94 },
        border = { 0.185, 0.225, 0.290, 1 },
        borderSoft = { 0.125, 0.155, 0.205, 0.92 },
        text = { 0.89, 0.92, 0.96, 1 },
        muted = { 0.56, 0.62, 0.70, 1 },
        quiet = { 0.34, 0.40, 0.48, 1 },
        cyan = { 0.28, 0.80, 0.91, 1 },
        violet = { 0.62, 0.55, 1.00, 1 },
        gold = { 0.95, 0.77, 0.35, 1 },
        success = { 0.23, 0.85, 0.61, 1 },
        danger = { 0.95, 0.40, 0.47, 1 },
    },

    -- Compatibility geometry token. Runtime card appearance is owned by
    -- EXUI:ApplyControlAppearance so Grid and PanelTheme cannot compete.
    GridCard = {
        accentWidth = 4,
        contentInsetLeft = 8,
    },

    Backdrop = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    },
}

-- Legacy entrypoint retained for callers outside Grid. `style` is deliberately
-- ignored: the shared control appearance is the sole visual authority.
function ExwindTools.PanelTheme.ApplyGridCardStyle(frame, style)
    if not frame then return end
    local EXUI = ExwindTools.UI
    if EXUI and EXUI.ApplyControlAppearance then
        return EXUI:ApplyControlAppearance(frame)
    end
end
