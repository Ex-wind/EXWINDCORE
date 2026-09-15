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
        SETTINGS_CARD_TITLE_HEIGHT = 38,
        SETTINGS_CARD_PADDING_TOP = 12,
        SETTINGS_CARD_PADDING_BOTTOM = 14,
        SETTINGS_CARD_PADDING_X = 14,
        SETTINGS_CARD_GAP = 12,
        SETTINGS_CARD_BOTTOM_GUTTER = 12,
        SPLIT_CONTENT_GRID_COLS = 200,
        FULL_CONTENT_GRID_COLS = 64,
        DEFAULT_WIDTH = 1440,
        DEFAULT_HEIGHT = 900,
        MIN_WIDTH = 1100,
        MIN_HEIGHT = 700,
    },

    Color = {
        panel = { 0.043, 0.047, 0.055, 0.985 },
        rail = { 0.043, 0.047, 0.055, 1 },
        header = { 0.043, 0.047, 0.055, 0.98 },
        nav = { 0.063, 0.067, 0.075, 1 },
        content = { 0.043, 0.047, 0.055, 1 },
        card = { 0.082, 0.090, 0.102, 1 },
        cardAlt = { 0.082, 0.090, 0.102, 1 },
        border = { 0.188, 0.204, 0.231, 1 },
        borderSoft = { 0.188, 0.204, 0.231, 0.86 },
        text = { 0.925, 0.933, 0.949, 1 },
        muted = { 0.667, 0.690, 0.729, 1 },
        quiet = { 0.44, 0.44, 0.48, 1 },
        cyan = { 0.663, 0.792, 1.00, 1 },
        violet = { 0.62, 0.55, 1.00, 1 },
        gold = { 0.95, 0.77, 0.35, 1 },
        success = { 0.23, 0.85, 0.61, 1 },
        danger = { 0.95, 0.40, 0.47, 1 },
    },

    -- gui.version=1 SettingsCard shell. These values describe shared settings
    -- chrome only; runtime presentation colors continue to come from ModuleDB.
    SettingsCard = {
        radius = 10,
        background = { 0.082, 0.090, 0.102, 1 }, -- #15171A
        hover = { 0.145, 0.169, 0.208, 1 },      -- #252B35
        border = { 0.188, 0.204, 0.231, 1 },     -- #30343B
        text = { 0.925, 0.933, 0.949, 1 },       -- #ECEEF2
        muted = { 0.667, 0.690, 0.729, 1 },      -- #AAB0BA
        accent = { 0.663, 0.792, 1.000, 1 },     -- #A9CAFF
    },

    -- Grid 卡片的唯一外观规格。卡片可传入 accentColor / borderColor，
    -- 但结构（正方形卡片、左侧强调线）不能由业务页面各自发明。
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

local QINGLAN_MEDIA = "Interface\\AddOns\\ExwindCore\\Textures\\QinglanRoundedLab\\"
local unpack = unpack or table.unpack

-- The Qinglan source images include padding around the authored rounded
-- rectangle. Split them into nine regions so corners retain their radius while
-- the centre and edges stretch without blurring.
local function EnsureRoundedSurface(frame, radius)
    local skin = frame._exSettingsCardSkin
    if skin then return skin end

    local u = { 0, (6 + radius) / 256, (250 - radius) / 256, 1 }
    local v = { 0, (23 + radius) / 128, (105 - radius) / 128, 1 }
    skin = { radius = radius, pieces = {} }
    frame._exSettingsCardSkin = skin

    for layer = 1, 2 do
        local file = layer == 1 and ("FillR" .. radius) or ("BorderR" .. radius)
        for row = 1, 3 do
            for col = 1, 3 do
                local texture = frame:CreateTexture(nil, layer == 1 and "BACKGROUND" or "BORDER")
                texture:SetTexture(QINGLAN_MEDIA .. file .. ".tga", "CLAMP", "CLAMP", "LINEAR")
                texture:SetTexCoord(u[col], u[col + 1], v[row], v[row + 1])
                if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
                if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
                skin.pieces[#skin.pieces + 1] = { texture = texture, file = file, layer = layer, row = row, col = col }
            end
        end
    end

    skin.Layout = function()
        local width, height = frame:GetWidth(), frame:GetHeight()
        if width <= 0 or height <= 0 then return end
        local effectiveScale = frame:GetEffectiveScale()
        effectiveScale = type(effectiveScale) == "number" and effectiveScale > 0 and effectiveScale or 1
        local pixelUtil = _G.PixelUtil
        local physicalPixel = pixelUtil and pixelUtil.GetNearestPixelSize
            and pixelUtil.GetNearestPixelSize(1, effectiveScale, 1) or (1 / effectiveScale)
        local scale = math.min(physicalPixel, width / (2 * radius), height / (2 * radius))
        local corner = radius * scale
        local xs = { -6 * scale, corner, width - corner, width + 6 * scale }
        local ys = { -23 * scale, corner, height - corner, height + 23 * scale }
        local function Snap(value)
            if value >= 0 then return math.floor(value / physicalPixel + .5) * physicalPixel end
            return math.ceil(value / physicalPixel - .5) * physicalPixel
        end
        for index = 1, 4 do xs[index], ys[index] = Snap(xs[index]), Snap(ys[index]) end
        for _, piece in ipairs(skin.pieces) do
            local pieceWidth = xs[piece.col + 1] - xs[piece.col]
            local pieceHeight = ys[piece.row + 1] - ys[piece.row]
            piece.texture:ClearAllPoints()
            piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", xs[piece.col], -ys[piece.row])
            piece.texture:SetSize(math.max(0.001, pieceWidth), math.max(0.001, pieceHeight))
            piece.texture:SetShown(skin.enabled ~= false and pieceWidth > 0 and pieceHeight > 0)
        end
    end
    frame:HookScript("OnSizeChanged", skin.Layout)
    frame:HookScript("OnShow", skin.Layout)
    return skin
end

function ExwindTools.PanelTheme.ApplySettingsCardStyle(frame, hovered)
    if not frame then return end
    local spec = ExwindTools.PanelTheme.SettingsCard
    local skin = EnsureRoundedSurface(frame, spec.radius)
    skin.enabled = true
    local fill = hovered and spec.hover or spec.background
    for _, piece in ipairs(skin.pieces) do
        -- FramePool reset clears texture paths; reapply the authored source on
        -- every borrow instead of assuming a retained Texture is still painted.
        piece.texture:SetTexture(QINGLAN_MEDIA .. piece.file .. ".tga", "CLAMP", "CLAMP", "LINEAR")
        piece.texture:SetVertexColor(unpack(piece.layer == 1 and fill or spec.border))
        piece.texture:Show()
    end
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    skin.Layout()
end

-- Lightweight visual adapter for addon-owned utility windows and explicitly
-- targeted StaticPopup instances. It never creates window behavior: buttons,
-- edit boxes, Escape handling, focus and confirmation remain on the owner.
function ExwindTools.PanelTheme.RestoreWindowChrome(frame)
    if not frame or not frame._exWindowChromeActive then return end
    frame._exWindowChromeActive = false
    if frame._exSettingsCardSkin then frame._exSettingsCardSkin.enabled = false end
    for _, piece in ipairs(frame._exSettingsCardSkin and frame._exSettingsCardSkin.pieces or {}) do
        piece.texture:Hide()
    end
    local native = frame._exWindowChromeNative
    if not native then return end
    if frame.NineSlice and frame.NineSlice.SetAlpha then frame.NineSlice:SetAlpha(native.nineSliceAlpha or 1) end
    if frame.Background and frame.Background.SetAlpha then frame.Background:SetAlpha(native.backgroundAlpha or 1) end
    for region, alpha in pairs(native.regions or {}) do
        if region and region.SetAlpha then region:SetAlpha(alpha) end
    end
    if frame.SetBackdrop and native.backdrop ~= nil then
        frame:SetBackdrop(native.backdrop)
        if native.backdropColor then frame:SetBackdropColor(unpack(native.backdropColor)) end
        if native.backdropBorderColor then frame:SetBackdropBorderColor(unpack(native.backdropBorderColor)) end
    end
end

function ExwindTools.PanelTheme.ApplyWindowChrome(frame, options)
    if not frame then return nil end
    options = type(options) == "table" and options or {}
    local suppressNative = options.suppressNative ~= false
    if suppressNative and not frame._exWindowChromeNative then
        local native = { regions = {} }
        native.nineSliceAlpha = frame.NineSlice and frame.NineSlice.GetAlpha and frame.NineSlice:GetAlpha() or nil
        native.backgroundAlpha = frame.Background and frame.Background.GetAlpha and frame.Background:GetAlpha() or nil
        if frame.GetBackdrop then native.backdrop = frame:GetBackdrop() end
        if frame.GetBackdropColor then native.backdropColor = { frame:GetBackdropColor() } end
        if frame.GetBackdropBorderColor then native.backdropBorderColor = { frame:GetBackdropBorderColor() } end
        if frame.GetRegions then
            for _, region in ipairs({ frame:GetRegions() }) do
                if region.IsObjectType and region:IsObjectType("Texture") then native.regions[region] = region:GetAlpha() end
            end
        end
        frame._exWindowChromeNative = native
    end
    local native = frame._exWindowChromeNative
    if suppressNative and native then
        if frame.NineSlice and frame.NineSlice.SetAlpha then frame.NineSlice:SetAlpha(0) end
        if frame.Background and frame.Background.SetAlpha then frame.Background:SetAlpha(0) end
        for region in pairs(native.regions) do if region and region.SetAlpha then region:SetAlpha(0) end end
        if frame.SetBackdrop then frame:SetBackdrop(nil) end
    end

    local radius = tonumber(options.radius) or ExwindTools.PanelTheme.SettingsCard.radius
    local fill = options.background or ExwindTools.PanelTheme.Color.panel
    local border = options.border or ExwindTools.PanelTheme.Color.border
    local skin = EnsureRoundedSurface(frame, radius)
    skin.enabled = true
    for _, piece in ipairs(skin.pieces) do
        piece.texture:SetTexture(QINGLAN_MEDIA .. piece.file .. ".tga", "CLAMP", "CLAMP", "LINEAR")
        piece.texture:SetVertexColor(unpack(piece.layer == 1 and fill or border))
        piece.texture:Show()
    end
    skin.Layout()
    frame._exWindowChromeActive = true
    frame._exWindowChromeRestoreOnHide = options.restoreOnHide == true
    if not frame._exWindowChromeHideHook then
        frame._exWindowChromeHideHook = true
        frame:HookScript("OnHide", function(self)
            if self._exWindowChromeRestoreOnHide then
                ExwindTools.PanelTheme.RestoreWindowChrome(self)
            end
        end)
    end
    return frame
end

local function EnsureCardTexture(frame, key, profile)
    local texture = frame[key]
    if not texture then
        texture = ExwindTools.UI:CreateVisualTexture(frame, profile or _G.EXBASEFRAME)
        frame[key] = texture
    end
    -- PanelTheme 在 VisualLayers 之前载入；调用发生在运行期，因此这里再取
    -- EXUI，避免加载顺序把 Theme 绑定到一套旧层级。
    local EXUI = ExwindTools.UI
    if EXUI and EXUI.ApplyVisualLayer then
        EXUI:ApplyVisualLayer(texture, profile or _G.EXBASEFRAME, frame)
    end
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    return texture
end

local function ApplyPhysicalOutline(frame, color)
    local outline = frame._exPhysicalOutline
    if not outline then
        outline = { lines = {} }
        frame._exPhysicalOutline = outline
        for index = 1, 4 do
            local line = frame:CreateTexture(nil, "BORDER", nil, 7)
            line:SetTexture("Interface\\Buttons\\WHITE8X8")
            if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(true) end
            if line.SetTexelSnappingBias then line:SetTexelSnappingBias(0) end
            outline.lines[index] = line
        end
        outline.Layout = function()
            local effectiveScale = frame:GetEffectiveScale()
            effectiveScale = type(effectiveScale) == "number" and effectiveScale > 0 and effectiveScale or 1
            local pixelUtil = _G.PixelUtil
            local pixel = pixelUtil and pixelUtil.GetNearestPixelSize
                and pixelUtil.GetNearestPixelSize(1, effectiveScale, 1) or (1 / effectiveScale)
            local top, bottom, left, right = unpack(outline.lines)
            top:ClearAllPoints(); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(pixel)
            bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(pixel)
            left:ClearAllPoints(); left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(pixel)
            right:ClearAllPoints(); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(pixel)
        end
        frame:HookScript("OnSizeChanged", outline.Layout)
        frame:HookScript("OnShow", outline.Layout)
    end
    outline.color = color
    for _, line in ipairs(outline.lines) do
        line:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        line:Show()
    end
    outline.Layout()
end

-- Grid 的 card 元素从对象池取出后在此重新套用视觉。纹理属于卡片对象本身，
-- 因此复用时不会额外创建 Frame，也不会形成每次渲染新增的对象树。
function ExwindTools.PanelTheme.ApplyGridCardStyle(frame, style)
    if not frame then return end

    style = style or {}
    local spec = ExwindTools.PanelTheme.GridCard
    local bg = style.background or ExwindTools.PanelTheme.Color.cardAlt
    local border = style.border or ExwindTools.PanelTheme.Color.borderSoft
    local accent = style.accent or ExwindTools.PanelTheme.Color.cyan

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    end
    ApplyPhysicalOutline(frame, border)

    -- 正方形卡片：仅左侧保留粗强调线；不要使用整圈外框或 glow。
    if frame.Accent then
        frame.Accent:ClearAllPoints()
        local EXUI = ExwindTools.UI
        if EXUI and EXUI.ApplyVisualLayer then
            EXUI:ApplyVisualLayer(frame.Accent, _G.EXBASEFRAME, frame)
        end
        frame.Accent:SetColorTexture(accent[1], accent[2], accent[3], accent[4] or 1)
        frame.Accent:SetWidth(spec.accentWidth)
        frame.Accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.Accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.Accent:Show()
    end

    -- 停用前一版整圈发光边框与拆分边线，避免对象池复用时残留。
    if frame._exCardFrameGlow then frame._exCardFrameGlow:Hide() end
    if frame._exCardTopEdge then frame._exCardTopEdge:Hide() end
    if frame._exCardRightEdge then frame._exCardRightEdge:Hide() end
    if frame._exCardBottomEdge then frame._exCardBottomEdge:Hide() end
    if frame._exCardGlowHost then frame._exCardGlowHost:Hide() end
    if frame._exCardTopGlow then frame._exCardTopGlow:Hide() end
    if frame._exCardRightGlow then frame._exCardRightGlow:Hide() end
    if frame._exCardBottomGlow then frame._exCardBottomGlow:Hide() end
end
