-- Disposable, memory-only glass appearance experiment.
-- Remove this file, Textures/GlassDemoCard.tga + GlassDemoCapsule.tga AND its TOC entry to uninstall.
-- Simulated tint / haze / specular rims; no scene blur or refraction.
local EXUI = _G.ExwindTools.UI
local WIDTH, HEIGHT, RADIUS = 540, 230, 36
local window
local mode, haze, shine = "frost", 48, 38
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

    -- Three continuous atlas layers per surface, with the same antialiased edge.
    local function AtlasSurface(asset, height, yOffset)
        local layers = {}
        for index = 1, 3 do
            local texture = EXUI:CreateVisualTexture(frame, EXBACKGROUNDFRAME)
            texture:SetDrawLayer("BACKGROUND", ({ -7, -5, -2 })[index])
            texture:SetTexture("Interface\\AddOns\\ExwindCore\\Textures\\" .. asset, "CLAMP", "CLAMP", "LINEAR")
            texture:SetTexCoord(0, 1, (index - 1) / 4, index / 4)
            texture:SetPoint("TOPLEFT", -2, -yOffset + 2)
            texture:SetSize(WIDTH + 4, height + 4)
            layers[index] = texture
        end
        local function Painted(texture)
            return { Paint = function(_, top, bottom)
                texture:SetGradient("VERTICAL", CreateColor(unpack(bottom)), CreateColor(unpack(top)))
            end }
        end
        return Painted(layers[1]), Painted(layers[3]), layers[2]
    end
    local body, rim, bodyLight = AtlasSurface("GlassDemoCard.tga", HEIGHT, 0)
    local capsuleY, capsuleHeight = HEIGHT + 16, 90
    local capsule, capsuleRim, capsuleLight = AtlasSurface("GlassDemoCapsule.tga", capsuleHeight, capsuleY)
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
    controls:SetSize(WIDTH, 152)
    controls:Hide()
    frame.controls = controls
    local controlBG = RoundedSurface(controls, WIDTH, 152, 16, 0, 0, -7)
    controlBG:Paint({ 0.12, 0.12, 0.12, 0.93 }, { 0.07, 0.07, 0.07, 0.93 })
    local frostButton, liquidButton
    local hovered = false
    local function Refresh()
        local h, s = haze / 100, shine / 100
        local frost = mode == "frost"
        local alpha = (frost and 0.23 or 0.1) + h * 0.53
        body:Paint({ 0.29, 0.29, 0.28, alpha }, { 0.19, 0.19, 0.18, alpha + 0.06 })
        capsule:Paint({ 0.32, 0.32, 0.30, alpha + 0.04 }, { 0.28, 0.28, 0.26, alpha + 0.08 })
        rim:Paint({ 0.94, 0.94, 0.91, 0.07 + s * 0.56 }, { 0.82, 0.82, 0.79, 0.025 + s * 0.24 })
        capsuleRim:Paint({ 0.98, 0.98, 0.94, 0.09 + s * 0.58 }, { 0.9, 0.9, 0.87, 0.05 + s * 0.35 })
        local strength = (0.45 + h * 0.85) * (frost and 1 or 0.65)
        bodyLight:SetVertexColor(0.93, 0.93, 0.89, strength)
        capsuleLight:SetVertexColor(0.93, 0.93, 0.89, strength)
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
    Label(controls, "连续柔光 · 无噪点 · 参数仅本次有效", 20, -125, 12, { 0.76, 0.76, 0.74 })
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
        window:SetHeight(HEIGHT + (window.controls:IsShown() and 280 or 106))
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
