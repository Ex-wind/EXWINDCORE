-- Disposable, memory-only glass appearance experiment.
-- Remove this file, Textures/GlassDemoNoise.tga AND its TOC entry to uninstall.
-- Simulated tint / haze / specular rims; no scene blur or refraction.
local EXUI = _G.ExwindTools.UI
local WIDTH, HEIGHT, RADIUS = 540, 230, 36
local window
local mode, haze, shine = "frost", 48, 38
local grain = 5
local NOISE = "Interface\\AddOns\\ExwindCore\\Textures\\GlassDemoNoise.tga"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Mix(a, b, t)
    return a + (b - a) * t
end

-- Geometry is allocated once. The middle uses one quad; only rounded ends
-- need thin strips. Gradients use the same full-surface coordinates.
local function RoundedSurface(parent, width, height, radius, x, y, sublevel, ring)
    local pieces = {}
    local function Quad(left, top, w, h)
        if w <= 0 or h <= 0 then return end
        local texture = EXUI:CreateVisualTexture(parent, EXBACKGROUNDFRAME)
        texture:SetDrawLayer("BACKGROUND", sublevel)
        texture:SetTexture(WHITE)
        texture:SetPoint("TOPLEFT", parent, "TOPLEFT", x + left, y - top)
        texture:SetSize(w, h)
        pieces[#pieces + 1] = { texture = texture, top = top / height, bottom = (top + h) / height,
            left = left, y = top, width = w, height = h }
    end
    local function Span(top, h, inset, innerInset)
        if ring then
            local edge = math.max(1, innerInset - inset)
            Quad(inset, top, edge, h)
            Quad(width - inset - edge, top, edge, h)
        else
            Quad(inset, top, width - 2 * inset, h)
        end
    end
    for row = 0, radius - 1 do
        local dy = radius - row - 0.5
        local inset = radius - math.sqrt(math.max(0, radius * radius - dy * dy))
        local innerRadius = radius - 1.5
        local innerInset = radius - math.sqrt(math.max(0, innerRadius * innerRadius - dy * dy))
        Span(row, 1, inset, innerInset)
        Span(height - row - 1, 1, inset, innerInset)
    end
    if ring then
        Quad(0, radius, 1.5, height - 2 * radius)
        Quad(width - 1.5, radius, 1.5, height - 2 * radius)
    else
        Quad(0, radius, width, height - 2 * radius)
    end
    local surface = {}
    function surface:TileNoise()
        for _, piece in ipairs(pieces) do
            piece.texture:SetTexture(NOISE, "REPEAT", "REPEAT", "NEAREST")
            -- Shared surface coordinates keep every strip and tile continuous.
            piece.texture:SetTexCoord(piece.left / 256, (piece.left + piece.width) / 256,
                piece.y / 256, (piece.y + piece.height) / 256)
        end
    end
    function surface:SetOpacity(alpha)
        for _, piece in ipairs(pieces) do piece.texture:SetAlpha(alpha) end
    end
    function surface:Paint(top, bottom)
        for _, piece in ipairs(pieces) do
            local function Color(t)
                return CreateColor(Mix(top[1], bottom[1], t), Mix(top[2], bottom[2], t),
                    Mix(top[3], bottom[3], t), Mix(top[4], bottom[4], t))
            end
            piece.texture:SetGradient("VERTICAL", Color(piece.bottom), Color(piece.top))
        end
    end
    return surface
end

local function Label(parent, text, x, y, size, color)
    local label = EXUI:CreateVisualFontString(parent, EXFONTFRAME, "GameFontHighlight")
    local font = label:GetFont()
    label:SetFont(font, size, "")
    label:SetPoint("TOPLEFT", x, y)
    label:SetTextColor(color[1], color[2], color[3], 1)
    label:SetShadowColor(0, 0, 0, 0.7)
    label:SetShadowOffset(0, -1)
    label:SetText(text)
    return label
end

local function BuildWindow()
    -- Independent transparent host; never change the shared panel theme.
    local frame = CreateFrame("Frame", "ExwindGlassDemoWindow", UIParent)
    frame:Hide()
    frame:SetSize(WIDTH, HEIGHT + 106)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", frame.StopMovingOrSizing)
    table.insert(UISpecialFrames, "ExwindGlassDemoWindow")

    local body = RoundedSurface(frame, WIDTH, HEIGHT, RADIUS, 0, 0, -7)
    local rim = RoundedSurface(frame, WIDTH, HEIGHT, RADIUS, 0, 0, -2, true)
    local capsuleY, capsuleHeight = HEIGHT + 16, 90
    local capsule = RoundedSurface(frame, WIDTH, capsuleHeight, 45, 0, -capsuleY, -7)
    local capsuleRim = RoundedSurface(frame, WIDTH, capsuleHeight, 45, 0, -capsuleY, -2, true)
    local bodyNoise = RoundedSurface(frame, WIDTH, HEIGHT, RADIUS, 0, 0, -3)
    local capsuleNoise = RoundedSurface(frame, WIDTH, capsuleHeight, 45, 0, -capsuleY, -3)
    bodyNoise:TileNoise()
    capsuleNoise:TileNoise()

    -- Soft, fixed light fields imitate the reference's broad blurred highlights.
    -- Each small quad samples one smooth field. This is NOT sampled game imagery.
    -- Everything is allocated once, clipped geometrically to the rounded surface.
    local lightPieces = {}
    local function LightField(height, radius, yOffset, phase)
        local step = 16
        for y = 0, height - 1, step do
            local band = math.min(step, height - y)
            -- Use the narrower end of the band so the field stays inside the rim.
            local edgeY = math.min(y, height - y - band)
            local dy = math.max(0, radius - edgeY)
            local inset = radius - math.sqrt(math.max(0, radius * radius - dy * dy))
            for x = inset + 2, WIDTH - inset - 3, 24 do
                local width = math.min(24, WIDTH - inset - 2 - x)
                if width > 0 then
                    local texture = EXUI:CreateVisualTexture(frame, EXBACKGROUNDFRAME)
                    texture:SetDrawLayer("BACKGROUND", -5)
                    texture:SetTexture(WHITE)
                    texture:SetPoint("TOPLEFT", x, -yOffset - y)
                    texture:SetSize(width, band)
                    local function Light(atX, atY)
                        local u, v = atX / WIDTH, atY / height
                        local glow = math.exp(-((u - 0.47) / 0.16)^2) * 0.30
                        glow = glow + math.exp(-((u - 0.89) / 0.25)^2 - ((v - 0.86) / 0.42)^2) * 0.21
                        return glow * (phase or 1)
                    end
                    lightPieces[#lightPieces + 1] = {
                        texture = texture,
                        left = Light(x, y + band / 2),
                        right = Light(x + width, y + band / 2),
                    }
                end
            end
        end
    end
    LightField(HEIGHT, RADIUS, 0, 1)
    LightField(capsuleHeight, 45, capsuleY, 1.25)

    Label(frame, "Good Morning", 34, -32, 21, { 0.9, 0.9, 0.89 })
    local message = Label(frame, "慢下来，看看眼前的风景。\n把这块玻璃移到不同背景前，\n感受光线与层次。", 34, -80, 27, { 0.97, 0.97, 0.96 })
    message:SetWidth(WIDTH - 68)
    message:SetJustifyH("LEFT")
    message:SetSpacing(7)
    message:SetShadowColor(0, 0, 0, 0.18)

    -- Keep EXUI's button interaction; draw the special glass skin on the host.
    -- A transparent button remains mouse-enabled and cannot repaint this skin.
    local dismiss = EXUI:CreateButton(frame, WIDTH, capsuleHeight, "", function() frame:Hide() end)
    dismiss:SetPoint("TOPLEFT", 0, -capsuleY)
    dismiss:SetAlpha(0)
    dismiss:Show()
    local dismissText = Label(frame, "关闭", 0, 0, 22, { 0.95, 0.95, 0.94 })
    dismissText:ClearAllPoints()
    dismissText:SetPoint("CENTER", frame, "TOPLEFT", WIDTH / 2, -capsuleY - capsuleHeight / 2)

    -- Hidden by default so the initial view matches the two-piece reference.
    local controls = CreateFrame("Frame", nil, frame)
    controls:SetPoint("TOPLEFT", 0, -HEIGHT - 128)
    controls:SetSize(WIDTH, 218)
    controls:Hide()
    frame.controls = controls
    local controlBG = RoundedSurface(controls, WIDTH, 218, 16, 0, 0, -7)
    controlBG:Paint({ 0.12, 0.12, 0.12, 0.93 }, { 0.07, 0.07, 0.07, 0.93 })
    local frostButton, liquidButton
    local hovered = false
    local function Refresh()
        local h, s = haze / 100, shine / 100
        bodyNoise:SetOpacity(grain / 100)
        capsuleNoise:SetOpacity(grain / 100)
        local frost = mode == "frost"
        local alpha = (frost and 0.23 or 0.1) + h * 0.53
        body:Paint({ 0.29, 0.29, 0.28, alpha }, { 0.19, 0.19, 0.18, alpha + 0.06 })
        capsule:Paint({ 0.32, 0.32, 0.30, alpha + 0.04 }, { 0.28, 0.28, 0.26, alpha + 0.08 })
        rim:Paint({ 0.94, 0.94, 0.91, 0.07 + s * 0.56 }, { 0.82, 0.82, 0.79, 0.025 + s * 0.24 })
        capsuleRim:Paint({ 0.98, 0.98, 0.94, 0.09 + s * 0.58 }, { 0.9, 0.9, 0.87, 0.05 + s * 0.35 })
        for _, piece in ipairs(lightPieces) do
            local strength = (0.45 + h * 0.85) * (frost and 1 or 0.65)
            piece.texture:SetGradient("HORIZONTAL",
                CreateColor(0.93, 0.93, 0.89, piece.left * strength),
                CreateColor(0.93, 0.93, 0.89, piece.right * strength))
        end
        dismissText:SetTextColor(1, 1, 0.98, hovered and 1 or 0.92)
        if hovered then
            capsule:Paint({ 0.44, 0.44, 0.42, alpha + 0.04 }, { 0.36, 0.36, 0.34, alpha + 0.08 })
        end
        frostButton:SetText(frost and "磨砂 · 已选" or "磨砂")
        liquidButton:SetText(frost and "清透" or "清透 · 已选")
    end
    dismiss:HookScript("OnEnter", function() hovered = true; Refresh() end)
    dismiss:HookScript("OnLeave", function() hovered = false; Refresh() end)
    frostButton = EXUI:CreateButton(controls, 118, 28, "磨砂", function() mode = "frost"; Refresh() end)
    frostButton:SetPoint("TOPLEFT", 20, -14)
    frostButton:Show()
    liquidButton = EXUI:CreateButton(controls, 118, 28, "清透", function() mode = "liquid"; Refresh() end)
    liquidButton:SetPoint("TOPLEFT", 150, -14)
    liquidButton:Show()
    local function Percent(value) return string.format("%d%%", value) end
    local hazeSlider = EXUI:CreateSlider(controls, 232, "雾面浓度", 0, 100, haze, 1, Percent, function(value)
        haze = value; Refresh()
    end)
    hazeSlider:SetPoint("TOPLEFT", 20, -57)
    hazeSlider:Show()
    local shineSlider = EXUI:CreateSlider(controls, 232, "细边亮度", 0, 100, shine, 1, Percent, function(value)
        shine = value; Refresh()
    end)
    shineSlider:SetPoint("TOPLEFT", 288, -57)
    shineSlider:Show()
    local grainSlider = EXUI:CreateSlider(controls, 232, "颗粒强度（0 为关闭）", 0, 30, grain, 1, Percent, function(value)
        grain = value; Refresh()
    end)
    grainSlider:SetPoint("TOPLEFT", 20, -123)
    grainSlider:Show()
    Label(controls, "白色细噪点 · 默认 5%", 288, -136, 13, { 0.86, 0.86, 0.84 })
    Label(controls, "模拟柔光，不含真实背景模糊  ·  参数仅本次有效", 20, -191, 12, { 0.76, 0.76, 0.74 })
    Refresh()
    return frame
end
local function ShowDemo()
    if not window then window = BuildWindow() end
    window:Show()
end

SLASH_EXWINDGLASSDEMO1 = "/exglass"
SlashCmdList.EXWINDGLASSDEMO = function(message)
    if message and message:lower():match("^%s*settings%s*$") then
        ShowDemo()
        window.controls:SetShown(not window.controls:IsShown())
        window:SetHeight(HEIGHT + (window.controls:IsShown() and 346 or 106))
        return
    end
    if window and window:IsShown() then window:Hide() else ShowDemo() end
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    ShowDemo()
end)
