-- Opt-in control appearance. Each variant owns its pools, including retained
-- composite hosts: a flat child must never be borrowed by a default page.
local UI, Factory = _G.ExwindTools.UI, _G.ExwindFactory
local A = {}
UI.ControlAppearance = A
local unpack = unpack or table.unpack
A.colors = {
    text = { .925, .933, .949, 1 }, muted = { .667, .690, .729, 1 },
    disabled = { .44, .44, .48, 1 }, line = { .188, .204, .231, 1 },
    input = { .043, .047, .055, 1 }, button = { .153, .153, .165, 1 },
    hover = { .102, .110, .129, 1 }, pressed = { .075, .082, .098, 1 },
    accent = { .663, .792, 1, 1 },
    neutral = { .76, .81, .85, 1 }, include = { .286, .859, .631, 1 },
    exclude = { .933, .443, .502, 1 },
}
A.metrics = { title = 18, section = 15, text = 13, control = 13, hint = 11, height = 28 }
local C = A.colors
local QINGLAN_MEDIA = "Interface\\AddOns\\ExwindCore\\Textures\\QinglanRoundedLab\\"
-- EXBoss AuraSound typography and dimensions, with semantic color roles for
-- the editor: headings, live facts and editable values are distinct.
A.DungeonAura = {
    row = 42, buttonWidth = 62, buttonHeight = 24, gap = 8,
    text = { .80, .85, .90, 1 }, muted = { .60, .66, .72, 1 },
    title = { .94, .79, .49, 1 }, fact = { .46, .72, .79, 1 },
    value = { .95, .97, 1, 1 }, focus = { .34, .79, .98, 1 },
    success = { .43, .87, .65, 1 }, warning = { .97, .72, .38, 1 }, danger = { .97, .45, .47, 1 },
    input = { .063, .102, .145, 1 }, inputBorder = { .28, .40, .51, 1 },
    inputFocus = { .074, .133, .184, 1 }, header = { .065, .079, .099, 1 },
    panel = { .067, .090, .129, .98 }, panelDeep = { .039, .059, .086, .98 },
    line = { .27, .34, .42, .35 }, lineStrong = { .27, .34, .42, .65 },
    button = { .050, .064, .090, .98 }, hover = { .090, .100, .120, 1 },
    gold = { .953, .788, .424, 1 },
}
-- Load-card palette from the supplied HTML; opt-in, separate from other pages.
A.LoadCard = setmetatable({
    id = "load-card", row = 52, buttonHeight = 26, buttonWidth = 88,
    text = { .80, .80, .80, 1 }, value = { 1, 1, 1, 1 }, title = { 1, 1, 1, 1 },
    muted = { .52, .52, .52, 1 }, fact = { .80, .80, .80, 1 }, focus = { .43, .43, .43, 1 },
    background = { .118, .118, .118, 1 }, header = { .133, .133, .141, 1 },
    panelDeep = { .106, .106, .110, 1 }, panel = { .078, .078, .078, 1 },
    input = { .094, .094, .094, 1 }, inputFocus = { .118, .118, .118, 1 },
    inputBorder = { .20, .20, .20, 1 }, button = { .145, .145, .149, 1 },
    hover = { .176, .176, .176, 1 }, line = { .157, .157, .157, 1 },
    lineStrong = { .220, .220, .227, 1 }, gold = { 1, .784, 0, 1 },
    choiceFill = { 1, 1, 1, 1 }, choiceText = { .059, .067, .082, 1 },
}, { __index = A.DungeonAura })
function A.GetReference(frame)
    local style = UI:GetControlFontStyle(frame)
    return style == "load-card" and A.LoadCard or (style == "dungeon-aura" and A.DungeonAura or nil)
end
function A.ReferenceText(region, template, color)
    if not region then return end
    local font = _G[template] or template
    region:SetFontObject(font)
    -- Pooled regions can retain direct overrides from their previous owner.
    -- Copy the live template's attributes as well as its inheritance link.
    if font.GetFont then
        local path, size, flags = font:GetFont()
        region:SetFont(path, size, flags)
        if font.GetShadowOffset and region.SetShadowOffset then region:SetShadowOffset(font:GetShadowOffset()) end
        if font.GetShadowColor and region.SetShadowColor then region:SetShadowColor(font:GetShadowColor()) end
    end
    region:SetTextColor(unpack(color or A.DungeonAura.text))
end
local originalFontPaths = setmetatable({}, { __mode = "k" })

function A.Font(region, size, color, flags, template)
    if not region or not region.SetFont then return end
    local reference = A.GetReference(region)
    if reference then
        originalFontPaths[region] = originalFontPaths[region] or region:GetFont() or GameFontHighlight:GetFont()
        A.ReferenceText(region, template or "GameFontHighlight", color or reference.text)
        return
    end
    local settings = UI:GetControlFontStyle(region) == "settings"
    local path = region:GetFont()
    if settings then
        originalFontPaths[region] = originalFontPaths[region] or path or GameFontHighlight:GetFont()
        path = _G.ExwindTools.MAIN_FONT or path
    elseif originalFontPaths[region] then
        path, originalFontPaths[region] = originalFontPaths[region], nil
    end
    path = path or GameFontHighlight:GetFont()
    region:SetFont(path, size or A.metrics.text, flags or (settings and "OUTLINE" or ""))
    region:SetTextColor(unpack(color or C.text))
    if region.SetShadowOffset then region:SetShadowOffset(0, 0) end
end

function UI:SetControlAppearance(root, appearance)
    assert(appearance == "flat" or appearance == "default" or appearance == nil, "Unknown control appearance")
    root._exControlAppearance = appearance
end

function UI:GetControlAppearance(root)
    while root do
        if root._exControlAppearance then return root._exControlAppearance end
        if root._exFlatControl then return "flat" end
        root = root.GetParent and root:GetParent()
    end
end

-- Typography is scoped to an opt-in page, never to shared game FontObjects.
-- Set before constructing children; state repaints resolve the current owner.
function UI:SetControlFontSize(root, size)
    assert(size == nil or (type(size) == "number" and size >= 10 and size <= 24), "Invalid control font size")
    root._exControlFontSize = size
end

function UI:GetControlFontSize(root)
    while root do
        if root._exControlFontSize then return root._exControlFontSize end
        root = root.GetParent and root:GetParent()
    end
end

-- Same font family and thin outline as the standard settings Grid.
-- Hints and editable values explicitly opt out of the outline at paint time.
function UI:SetControlFontStyle(root, style)
    assert(style == nil or style == "settings" or style == "dungeon-aura" or style == "load-card", "Unknown control font style")
    root._exControlFontStyle = style
end

function UI:GetControlFontStyle(root)
    while root do
        if root._exControlFontStyle then return root._exControlFontStyle end
        root = root.GetParent and root:GetParent()
    end
end

function UI:ResolveControlPool(poolType, parent, appearance)
    if poolType:match("^EXUI.Flat%.") then return poolType end
    if (appearance or self:GetControlAppearance(parent)) ~= "flat" then return poolType end
    local source = Factory.Pools[poolType]
    if not source then return poolType end
    -- EXAura-owned pools already have one appearance. Shared hosts need their
    -- own variant even when the host itself has no visible artwork.
    if not (poolType:match("^Grid") or source.exComposite) then return poolType end
    if poolType:match("^EXAura%.") or poolType:match("^EXUI%.Choice") then return poolType end
    local name = "EXUI.Flat." .. poolType
    if not Factory.Pools[name] then
        local template = poolType == "GridButton" and "BackdropTemplate" or source.exTemplate
        Factory:InitPool(name, source.exFrameType, template, function(frame)
            frame._exFlatControl = true
            if source.customInit then source.customInit(frame) end
            if poolType == "GridButton" then
                local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                frame:SetFontString(label)
                label:SetPoint("LEFT", 6, 0); label:SetPoint("RIGHT", -6, 0)
                label:SetWordWrap(false)
                frame.label = label
            end
        end)
        Factory.Pools[name].exComposite = source.exComposite
    end
    return name
end

function UI:AcquireControl(poolType, parent)
    return Factory:Acquire(poolType, parent, self._requestedAppearance)
end

local function Surface(frame, fill, edge, forceRounded)
    local settings = forceRounded or UI:GetControlFontStyle(frame) == "settings"
    if settings then
        local media = QINGLAN_MEDIA
        local surfaceFill = fill or C.input
        local surfaceEdge = edge or C.line
        local skin = frame._exRoundedControlSkin
        if not skin then
            local radius = frame._exRoundedRadius or 4
            local u = { 0, (6 + radius) / 256, (250 - radius) / 256, 1 }
            local v = { 0, (23 + radius) / 128, (105 - radius) / 128, 1 }
            skin = { radius = radius, pieces = {} }
            frame._exRoundedControlSkin = skin
            for layer = 1, 2 do
                for row = 1, 3 do
                    for col = 1, 3 do
                        local texture = frame:CreateTexture(nil, layer == 1 and "BACKGROUND" or "BORDER")
                        texture:SetTexture(media .. (layer == 1 and ("FillR" .. radius .. ".tga") or ("BorderR" .. radius .. ".tga")),
                            "CLAMP", "CLAMP", "LINEAR")
                        texture:SetTexCoord(u[col], u[col + 1], v[row], v[row + 1])
                        if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
                        if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
                        skin.pieces[#skin.pieces + 1] = { texture = texture, layer = layer, row = row, col = col }
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
                -- One authored border texel maps to exactly one physical pixel.
                -- Radius/padding and all nine-slice seams use the same unit so
                -- hover/focus only recolor the outline; they never thicken it.
                local scale = math.min(physicalPixel, width / (radius * 2), height / (radius * 2))
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
                    piece.texture:SetSize(math.max(.001, pieceWidth), math.max(.001, pieceHeight))
                    piece.texture:SetShown(skin.enabled ~= false and pieceWidth > 0 and pieceHeight > 0)
                end
            end
            frame:HookScript("OnSizeChanged", skin.Layout)
            frame:HookScript("OnShow", skin.Layout)
        end
        skin.enabled = true
        if frame.SetBackdrop and not frame._exPreserveBackdrop then frame:SetBackdrop(nil) end
        for _, texture in ipairs(frame._exFlatSurface or {}) do texture:Hide() end
        for _, piece in ipairs(skin.pieces) do
            piece.texture:SetTexture(media .. (piece.layer == 1 and ("FillR" .. skin.radius .. ".tga") or ("BorderR" .. skin.radius .. ".tga")),
                "CLAMP", "CLAMP", "LINEAR")
            piece.texture:SetVertexColor(unpack(piece.layer == 1 and surfaceFill or surfaceEdge))
            piece.texture:Show()
        end
        skin.Layout()
        return
    end
    if frame._exRoundedControlSkin then frame._exRoundedControlSkin.enabled = false end
    for _, piece in ipairs(frame._exRoundedControlSkin and frame._exRoundedControlSkin.pieces or {}) do
        piece.texture:Hide()
    end
    local skin = frame._exFlatSurface
    if not skin then
        skin = {}
        frame._exFlatSurface = skin
        for i = 1, 5 do skin[i] = frame:CreateTexture(nil, i == 1 and "BACKGROUND" or "BORDER") end
        skin[1]:SetAllPoints()
        skin[2]:SetPoint("TOPLEFT"); skin[2]:SetPoint("TOPRIGHT")
        skin[3]:SetPoint("BOTTOMLEFT"); skin[3]:SetPoint("BOTTOMRIGHT")
        skin[4]:SetPoint("TOPLEFT"); skin[4]:SetPoint("BOTTOMLEFT")
        skin[5]:SetPoint("TOPRIGHT"); skin[5]:SetPoint("BOTTOMRIGHT")
        skin.Layout = function()
            local effectiveScale = frame:GetEffectiveScale()
            effectiveScale = type(effectiveScale) == "number" and effectiveScale > 0 and effectiveScale or 1
            local pixelUtil = _G.PixelUtil
            local pixel = pixelUtil and pixelUtil.GetNearestPixelSize
                and pixelUtil.GetNearestPixelSize(1, effectiveScale, 1) or (1 / effectiveScale)
            skin[2]:SetHeight(pixel); skin[3]:SetHeight(pixel)
            skin[4]:SetWidth(pixel); skin[5]:SetWidth(pixel)
        end
        frame:HookScript("OnSizeChanged", skin.Layout)
        frame:HookScript("OnShow", skin.Layout)
    end
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    for _, texture in ipairs(skin) do texture:Show() end
    local reference = A.GetReference(frame)
    skin[1]:SetColorTexture(unpack(fill or (reference and reference.panelDeep) or C.input))
    for i = 2, 5 do skin[i]:SetColorTexture(unpack(edge or (reference and reference.lineStrong) or C.line)) end
    skin.Layout()
end

local function InputFocus(frame)
    if not frame._exFlatControl then return end
    local reference = A.GetReference(frame)
    Surface(frame, reference and (frame:HasFocus() and reference.inputFocus or reference.input) or C.input,
        frame:HasFocus() and (reference and reference.focus or C.accent) or (reference and reference.inputBorder or C.line))
end

-- Backdrop-backed wrapped controls (currently the color picker button and its
-- swatch) keep their live SetBackdropBorderColor behavior. Rebuild only their
-- existing edge at one physical pixel; do not add a second outline.
local function PhysicalWrappedBackdrop(frame)
    if not frame or not frame.GetBackdrop or not frame.SetBackdrop then return end
    local backdrop = frame:GetBackdrop()
    if not backdrop or not backdrop.edgeFile then return end
    local effectiveScale = frame:GetEffectiveScale()
    effectiveScale = type(effectiveScale) == "number" and effectiveScale > 0 and effectiveScale or 1
    local pixelUtil = _G.PixelUtil
    local pixel = pixelUtil and pixelUtil.GetNearestPixelSize
        and pixelUtil.GetNearestPixelSize(1, effectiveScale, 1) or (1 / effectiveScale)
    local copy = {}
    for key, value in pairs(backdrop) do
        if key == "insets" and type(value) == "table" then
            copy.insets = { left = value.left, right = value.right, top = value.top, bottom = value.bottom }
        else
            copy[key] = value
        end
    end
    copy.edgeFile = "Interface\\Buttons\\WHITE8X8"
    copy.edgeSize = pixel
    local fill = frame.GetBackdropColor and { frame:GetBackdropColor() } or nil
    local edge = frame.GetBackdropBorderColor and { frame:GetBackdropBorderColor() } or nil
    frame:SetBackdrop(copy)
    if fill and frame.SetBackdropColor then frame:SetBackdropColor(unpack(fill)) end
    if edge and frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(unpack(edge)) end
end

local function DropdownState(frame)
    local reference = A.GetReference(frame)
    local native = reference == A.DungeonAura
    local enabled = frame:IsEnabled()
    local active = enabled and (frame._exDropdownHover or frame._exDropdownOpen)
    if frame.Background then frame.Background:SetAlpha(native and 1 or 0) end
    if frame.Arrow then frame.Arrow:SetAlpha(native and 1 or 0) end
    if frame._exFlatArrow then frame._exFlatArrow:Hide() end
    if frame._exFlatChevron then frame._exFlatChevron:SetShown(not native and reference ~= A.LoadCard) end
    for _, texture in ipairs(frame._exLoadChevron or {}) do
        texture:SetShown(reference == A.LoadCard)
        texture:SetVertexColor(unpack(frame:IsEnabled() and A.LoadCard.muted or C.disabled))
    end
    if not native then
        local pressed = enabled and frame._exDropdownPressed
        local fill = reference and reference.input or C.input
        if active then fill = reference and reference.inputFocus or C.hover end
        if pressed then fill = C.pressed end
        Surface(frame, enabled and fill or C.input,
            enabled and (active and (reference and reference.focus or C.accent) or (reference and reference.inputBorder or C.line)) or C.line)
    end
    local color = frame:IsEnabled() and (reference and reference.value or C.text) or C.disabled
    A.Font(frame.Text, UI:GetControlFontSize(frame) or A.metrics.control, color, "")
    if frame._exFlatChevron then
        frame._exFlatChevron:SetTexCoord(0, 1, frame._exDropdownOpen and 1 or 0, frame._exDropdownOpen and 0 or 1)
        frame._exFlatChevron:SetVertexColor(unpack(frame:IsEnabled() and (active and C.text or C.muted) or C.disabled))
    end
end

function UI:RefreshDropdownAppearance(frame)
    if frame and self:GetControlAppearance(frame) == "flat" then DropdownState(frame) end
end

function UI:ApplyQinglanRoundedSurface(frame, radius, fill, edge)
    if not frame then return end
    frame._exControlFontStyle = "settings"
    frame._exControlAppearance = "flat"
    frame._exRoundedRadius = radius or 4
    Surface(frame, fill or C.input, edge or C.line)
end

function UI:ApplyDropdownMenuAppearance(owner, menu)
    local proxy = menu and menu.ToProxy and menu:ToProxy() or menu
    if not proxy or not proxy.CreateTexture then return end
    local qinglan = owner and self:GetControlAppearance(owner) == "flat" and self:GetControlFontStyle(owner) == "settings"
    if not qinglan then
        if proxy._exMenuNativeSuppressed then
            if proxy.NineSlice and proxy.NineSlice.SetAlpha then proxy.NineSlice:SetAlpha(proxy._exMenuNineSliceAlpha or 1) end
            if proxy.Background and proxy.Background.SetAlpha then proxy.Background:SetAlpha(proxy._exMenuBackgroundAlpha or 1) end
            for region, alpha in pairs(proxy._exMenuNativeRegions or {}) do
                if region and region.SetAlpha then region:SetAlpha(alpha) end
            end
            if proxy._exRoundedControlSkin then proxy._exRoundedControlSkin.enabled = false end
            for _, piece in ipairs(proxy._exRoundedControlSkin and proxy._exRoundedControlSkin.pieces or {}) do piece.texture:Hide() end
            proxy._exControlFontStyle = nil
            proxy._exControlAppearance = nil
        end
        return
    end
    if not proxy._exMenuNativeSuppressed then
        proxy._exMenuNativeSuppressed = true
        proxy._exPreserveBackdrop = true
        proxy._exMenuNineSliceAlpha = proxy.NineSlice and proxy.NineSlice.GetAlpha and proxy.NineSlice:GetAlpha() or 1
        proxy._exMenuBackgroundAlpha = proxy.Background and proxy.Background.GetAlpha and proxy.Background:GetAlpha() or 1
        proxy._exMenuNativeRegions = {}
        if proxy.NineSlice and proxy.NineSlice.SetAlpha then proxy.NineSlice:SetAlpha(0) end
        if proxy.Background and proxy.Background.SetAlpha then proxy.Background:SetAlpha(0) end
        if proxy.GetRegions then
            for _, region in ipairs({ proxy:GetRegions() }) do
                if region.IsObjectType and region:IsObjectType("Texture") then
                    proxy._exMenuNativeRegions[region] = region:GetAlpha()
                    region:SetAlpha(0)
                end
            end
        end
    end
    if proxy.NineSlice and proxy.NineSlice.SetAlpha then proxy.NineSlice:SetAlpha(0) end
    if proxy.Background and proxy.Background.SetAlpha then proxy.Background:SetAlpha(0) end
    for region in pairs(proxy._exMenuNativeRegions or {}) do
        if region and region.SetAlpha then region:SetAlpha(0) end
    end
    self:ApplyQinglanRoundedSurface(proxy, 10, { .055, .059, .067, .985 }, { .235, .251, .278, 1 })
    owner._exDropdownOpen = true
    DropdownState(owner)
end

function UI:ApplyDropdownMenuItemAppearance(owner, button, selectedResolver, reserveRight, checkMode)
    if not owner or not button or self:GetControlAppearance(owner) ~= "flat" or self:GetControlFontStyle(owner) ~= "settings" then return end
    button._exControlFontStyle = "settings"
    button._exControlAppearance = "flat"
    button._exRoundedRadius = 8
    button._exMenuAppearanceActive = true
    button._exMenuSelectedResolver = selectedResolver
    button._exMenuReserveRight = reserveRight or 28
    button._exMenuCheckMode = checkMode
    if not button._exMenuCheck then
        local checkFill = button:CreateTexture(nil, "ARTWORK")
        checkFill:SetTexture(QINGLAN_MEDIA .. "CheckFill.tga", "CLAMP", "CLAMP", "LINEAR")
        checkFill:SetSize(22, 22)
        checkFill:SetPoint("LEFT", 9, 0)
        local checkBorder = button:CreateTexture(nil, "OVERLAY")
        checkBorder:SetTexture(QINGLAN_MEDIA .. "CheckBorder.tga", "CLAMP", "CLAMP", "LINEAR")
        checkBorder:SetSize(22, 22)
        checkBorder:SetPoint("LEFT", 9, 0)
        local check = button:CreateTexture(nil, "OVERLAY")
        check:SetTexture(QINGLAN_MEDIA .. "GlyphCheck.tga", "CLAMP", "CLAMP", "LINEAR")
        check:SetSize(20, 20)
        if check.SetSnapToPixelGrid then check:SetSnapToPixelGrid(false) end
        if check.SetTexelSnappingBias then check:SetTexelSnappingBias(0) end
        button._exMenuCheck = check
        button._exMenuCheckFill = checkFill
        button._exMenuCheckBorder = checkBorder
        button:HookScript("OnEnter", function(self) self._exMenuHover = true; UI:RefreshDropdownMenuItemAppearance(self) end)
        button:HookScript("OnLeave", function(self) self._exMenuHover = false; self._exMenuPressed = false; UI:RefreshDropdownMenuItemAppearance(self) end)
        button:HookScript("OnMouseDown", function(self) self._exMenuPressed = true; UI:RefreshDropdownMenuItemAppearance(self) end)
        button:HookScript("OnMouseUp", function(self) self._exMenuPressed = false; UI:RefreshDropdownMenuItemAppearance(self) end)
        button:HookScript("OnShow", function(self) UI:RefreshDropdownMenuItemAppearance(self) end)
        button:HookScript("OnEnable", function(self) UI:RefreshDropdownMenuItemAppearance(self) end)
        button:HookScript("OnDisable", function(self) UI:RefreshDropdownMenuItemAppearance(self) end)
    end
    self:RefreshDropdownMenuItemAppearance(button)
end

function UI:RefreshDropdownMenuItemAppearance(button)
    if not button or not button._exMenuCheck or not button._exMenuAppearanceActive then return end
    local enabled = not button.IsEnabled or button:IsEnabled()
    local selected = type(button._exMenuSelectedResolver) == "function" and button._exMenuSelectedResolver() == true
    local effectiveScale = button:GetEffectiveScale()
    effectiveScale = type(effectiveScale) == "number" and effectiveScale > 0 and effectiveScale or 1
    local pixelUtil = _G.PixelUtil
    local physicalPixel = pixelUtil and pixelUtil.GetNearestPixelSize
        and pixelUtil.GetNearestPixelSize(1, effectiveScale, 1) or (1 / effectiveScale)
    local fill = selected and { .105, .122, .153, 1 } or { .055, .059, .067, 1 }
    local edge = fill
    if enabled and button._exMenuHover then fill = C.hover; edge = { .25, .28, .33, 1 } end
    if enabled and button._exMenuPressed then fill = C.pressed; edge = C.pressed end
    Surface(button, fill, edge)
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
    local label = button.GetFontString and button:GetFontString()
    if label then
        A.Font(label, A.metrics.control, enabled and C.text or C.disabled, "")
        label:SetJustifyH("LEFT")
    end
    button._exMenuCheck:ClearAllPoints()
    button._exMenuCheck:SetPoint("LEFT", 10, 0)
    button._exMenuCheck:SetSize(20 * physicalPixel, 20 * physicalPixel)
    button._exMenuCheck:SetShown(selected)
    button._exMenuCheck:SetVertexColor(1, 1, 1, enabled and 1 or .35)
    local checkbox = button._exMenuCheckMode == "checkbox"
    button._exMenuCheckFill:SetSize(22 * physicalPixel, 22 * physicalPixel)
    button._exMenuCheckBorder:SetSize(22 * physicalPixel, 22 * physicalPixel)
    button._exMenuCheckFill:SetShown(checkbox)
    button._exMenuCheckBorder:SetShown(checkbox)
    button._exMenuCheckFill:SetVertexColor(unpack(selected and { .20, .46, .82, enabled and 1 or .35 }
        or { .075, .080, .095, enabled and 1 or .35 }))
    button._exMenuCheckBorder:SetVertexColor(unpack(button._exMenuHover and { .53, .66, .83, enabled and 1 or .35 }
        or { .32, .34, .39, enabled and 1 or .35 }))
    if label then
        label:ClearAllPoints()
        label:SetPoint("LEFT", 38, 0)
        label:SetPoint("RIGHT", -(button._exMenuReserveRight or 28), 0)
    end
end

function UI:ResetDropdownMenuItemAppearance(button)
    if not button or not button._exMenuCheck then return end
    button._exMenuAppearanceActive = false
    button._exMenuSelectedResolver = nil
    button._exMenuCheckMode = nil
    button._exMenuCheck:Hide()
    button._exMenuCheckFill:Hide()
    button._exMenuCheckBorder:Hide()
    if button._exRoundedControlSkin then button._exRoundedControlSkin.enabled = false end
    for _, piece in ipairs(button._exRoundedControlSkin and button._exRoundedControlSkin.pieces or {}) do piece.texture:Hide() end
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(1) end
    button._exControlFontStyle = nil
    button._exControlAppearance = nil
end

local fontObjects = {}
local fontObjectSerial = 0
local function ButtonFont(role, size, settings, reference)
    local path = settings and _G.ExwindTools.MAIN_FONT or GameFontHighlight:GetFont()
    path = path or GameFontHighlight:GetFont()
    local flags = settings and "OUTLINE" or ""
    local key = role .. size .. flags .. path .. (reference and (reference.id or "DungeonAura") or "")
    if not fontObjects[key] then
        fontObjectSerial = fontObjectSerial + 1
        local font = CreateFont("EXUIFlatButtonFont" .. fontObjectSerial)
        if reference then font:SetFontObject(GameFontNormalSmall)
        else font:SetFont(path, size, flags); font:SetShadowOffset(0, 0) end
        font:SetTextColor(unpack(reference and (reference[role] or C[role]) or C[role] or C.text))
        fontObjects[key] = font
    end
    return fontObjects[key]
end

local function ButtonTexture(frame, method, color, alpha)
    local texture = frame[method](frame)
    if texture then
        texture:SetColorTexture(color[1], color[2], color[3], alpha)
        texture:ClearAllPoints(); texture:SetAllPoints()
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

local function ReferenceButtonHover(frame, hovered)
    local reference = A.GetReference(frame)
    if not reference then return end
    if not frame:IsEnabled() then return end
    Surface(frame, hovered and reference.inputFocus or reference.button,
        hovered and reference.focus or reference.lineStrong)
    frame:GetFontString():SetTextColor(unpack(hovered and reference.value or reference.text))
end

local function Checkbox(frame)
    local box = frame.checkbox
    box:SetSize(22, 22)
    Surface(box)
    ButtonTexture(box, "GetNormalTexture", C.input, 0)
    ButtonTexture(box, "GetPushedTexture", C.accent, .24)
    ButtonTexture(box, "GetHighlightTexture", C.accent, .13)
    for _, entry in ipairs({ { box:GetCheckedTexture(), C.accent }, { box:GetDisabledCheckedTexture(), C.disabled } }) do
        local texture, color = entry[1], entry[2]
        if texture then
            texture:SetDesaturated(true)
            texture:SetVertexColor(unpack(color))
            texture:ClearAllPoints(); texture:SetPoint("CENTER"); texture:SetSize(20, 20)
        end
    end
end

-- Extracted from the validated FontGroup/text-settings slider. FontGroup is the
-- visual source of truth; standalone sliders only reuse this appearance.
local function FontGroupSliderAppearance(frame)
    local slider = frame.Slider or frame
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        if slider[key] then slider[key]:SetAlpha(0) end
    end
    if slider._exFlatTrack then slider._exFlatTrack:Hide() end

    if not slider._exFontGroupTrack then
        local track = CreateFrame("Frame", nil, slider)
        track:SetFrameLevel(slider:GetFrameLevel())
        local line = track:CreateTexture(nil, "BACKGROUND")
        line:SetAllPoints()
        slider._exFontGroupTrack = track
        slider._exFontGroupTrackLine = line
    end
    local track = slider._exFontGroupTrack
    track:ClearAllPoints()
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(3)
    track:Show()
    slider._exFontGroupTrackLine:SetColorTexture(.14, .15, .17, 1)
    slider._exFontGroupTrackLine:Show()

    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    if thumb then
        thumb:SetSize(16, 10)
        thumb:SetAlpha(0)
        if not slider._exFontGroupKnob then
            local knob = CreateFrame("Frame", nil, slider)
            knob:SetAllPoints(thumb)
            knob:SetFrameLevel(slider:GetFrameLevel() + 2)
            local texture = knob:CreateTexture(nil, "ARTWORK")
            texture:SetPoint("CENTER")
            slider._exFontGroupKnob = knob
            slider._exFontGroupKnobTexture = texture
        end
        local knobTexture = slider._exFontGroupKnobTexture
        knobTexture:SetTexture(QINGLAN_MEDIA .. "KnobR3.tga", "CLAMP", "CLAMP", "LINEAR")
        knobTexture:SetTexCoord(118 / 256, 138 / 256, 52 / 128, 76 / 128)
        knobTexture:SetSize(160 / 9, 120 / 11)
        knobTexture:SetVertexColor(.68, .71, .76, 1)
        knobTexture:Show()
        if knobTexture.SetSnapToPixelGrid then knobTexture:SetSnapToPixelGrid(false) end
        if knobTexture.SetTexelSnappingBias then knobTexture:SetTexelSnappingBias(0) end
        if not slider._exFontGroupHoverHook then
            slider._exFontGroupHoverHook = true
            slider:HookScript("OnEnter", function(self)
                if self._exFontGroupKnobTexture then
                    self._exFontGroupKnobTexture:SetVertexColor(.76, .82, .90, 1)
                end
            end)
            slider:HookScript("OnLeave", function(self)
                if self._exFontGroupKnobTexture then
                    self._exFontGroupKnobTexture:SetVertexColor(.68, .71, .76, 1)
                end
            end)
        end
    end

    local input = frame.numberInput
    if input then
        local function PaintValue(editBox)
            local focused = editBox.HasFocus and editBox:HasFocus()
            Surface(editBox, { .133, .137, .145, 1 }, focused and { .36, .40, .46, 1 } or { .20, .204, .22, 1 }, true)
            A.Font(editBox, 15, { .95, .95, .97, 1 }, "")
        end
        input:ClearAllPoints()
        -- FontGroup's final validated placement includes its four-pixel card lift.
        input:SetPoint("BOTTOMRIGHT", track, "TOPRIGHT", 0, 10)
        input:SetSize(44, 24)
        PaintValue(input)
        if not input._exFontGroupFocusHook then
            input._exFontGroupFocusHook = true
            input:HookScript("OnEditFocusGained", PaintValue)
            input:HookScript("OnEditFocusLost", PaintValue)
            input:HookScript("OnShow", PaintValue)
        end
    end

    local title = frame.Title
    if title then
        title:ClearAllPoints()
        title:SetPoint("BOTTOMLEFT", track, "TOPLEFT", 0, 11)
        if input then title:SetPoint("BOTTOMRIGHT", input, "BOTTOMLEFT", -12, 1) end
        title:SetHeight(20)
        title:SetJustifyH("LEFT")
        title:SetJustifyV("MIDDLE")
        A.Font(title, 14, { .88, .88, .91, 1 })
        title:Show()
    end
    for _, key in ipairs({ "Back", "Forward" }) do
        if frame[key] then frame[key]:Hide() end
    end
end

function UI:ApplyFontGroupSliderAppearance(frame)
    FontGroupSliderAppearance(frame)
    return frame
end

local function CapturePopupChildNative(control)
    if control._exPopupChildNative then return control._exPopupChildNative end
    local native = { textures = {} }
    for _, method in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local texture = control[method] and control[method](control)
        if texture then native.textures[texture] = texture:GetAlpha() end
    end
    if control.Flash then native.textures[control.Flash] = control.Flash:GetAlpha() end
    if control.GetBackdrop then native.backdrop = control:GetBackdrop() end
    if control.GetBackdropColor then native.backdropColor = { control:GetBackdropColor() } end
    if control.GetBackdropBorderColor then native.backdropBorderColor = { control:GetBackdropBorderColor() } end
    local label = control.GetFontString and control:GetFontString()
    if label then
        native.label = label
        native.fontObject = label.GetFontObject and label:GetFontObject() or nil
        native.textColor = { label:GetTextColor() }
    end
    if control.GetFontObject then native.controlFontObject = control:GetFontObject() end
    if control.GetTextColor then native.controlTextColor = { control:GetTextColor() } end
    if control.Instructions then
        native.instructions = control.Instructions
        native.instructionsFontObject = control.Instructions.GetFontObject and control.Instructions:GetFontObject() or nil
        native.instructionsTextColor = { control.Instructions:GetTextColor() }
    end
    if control.GetNormalFontObject then native.normalFontObject = control:GetNormalFontObject() end
    if control.GetHighlightFontObject then native.highlightFontObject = control:GetHighlightFontObject() end
    if control.GetDisabledFontObject then native.disabledFontObject = control:GetDisabledFontObject() end
    control._exPopupChildNative = native
    return native
end

local function GetPopupButtons(popup)
    local buttons, seen = {}, {}
    local function Add(button)
        if button and not seen[button] then seen[button] = true; buttons[#buttons + 1] = button end
    end
    if popup.GetButtons then
        for _, button in ipairs(popup:GetButtons() or {}) do Add(button) end
    else
        -- Legacy StaticPopup layouts exposed lowercase keys directly.
        for _, key in ipairs({ "Button1", "Button2", "Button3", "Button4", "button1", "button2", "button3", "button4" }) do
            Add(popup[key])
        end
    end
    Add(popup.ExtraButton or popup.extraButton)
    return buttons
end

local function GetPopupEditBox(popup)
    return popup.GetEditBox and popup:GetEditBox() or popup.EditBox or popup.editBox
end

local function PaintPopupButton(button)
    if not button._exPopupChildActive then return end
    local enabled = not button.IsEnabled or button:IsEnabled()
    local fill = enabled and (button._exPopupChildPressed and C.pressed
        or button._exPopupChildHover and C.hover or C.button) or C.input
    local edge = enabled and (button._exPopupChildHover and C.accent or C.line) or C.line
    Surface(button, fill, edge)
    local label = button.GetFontString and button:GetFontString()
    A.Font(label, A.metrics.control, enabled and C.text or C.disabled, "")
end

local function PaintPopupEditBox(editBox)
    if not editBox._exPopupChildActive then return end
    local focused = editBox.HasFocus and editBox:HasFocus()
    Surface(editBox, focused and C.hover or C.input, focused and C.accent or C.line)
    A.Font(editBox, 16, C.text, "")
end

function UI:RestorePopupChildControls(popup)
    if not popup then return end
    local controls = GetPopupButtons(popup)
    controls[#controls + 1] = GetPopupEditBox(popup)
    for _, control in ipairs(controls) do
        local native = control and control._exPopupChildNative
        if control and native and control._exPopupChildActive then
            control._exPopupChildActive = false
            control._exPopupChildHover = false
            control._exPopupChildPressed = false
            if control._exRoundedControlSkin then control._exRoundedControlSkin.enabled = false end
            for _, piece in ipairs(control._exRoundedControlSkin and control._exRoundedControlSkin.pieces or {}) do
                piece.texture:Hide()
            end
            for texture, alpha in pairs(native.textures or {}) do
                if texture and texture.SetAlpha then texture:SetAlpha(alpha) end
            end
            if control.SetBackdrop and native.backdrop ~= nil then
                control:SetBackdrop(native.backdrop)
                if native.backdropColor then control:SetBackdropColor(unpack(native.backdropColor)) end
                if native.backdropBorderColor then control:SetBackdropBorderColor(unpack(native.backdropBorderColor)) end
            end
            if native.label then
                if native.fontObject then native.label:SetFontObject(native.fontObject) end
                if native.textColor then native.label:SetTextColor(unpack(native.textColor)) end
            end
            if native.controlFontObject and control.SetFontObject then control:SetFontObject(native.controlFontObject) end
            if native.controlTextColor and control.SetTextColor then control:SetTextColor(unpack(native.controlTextColor)) end
            if native.instructions then
                if native.instructionsFontObject then native.instructions:SetFontObject(native.instructionsFontObject) end
                if native.instructionsTextColor then native.instructions:SetTextColor(unpack(native.instructionsTextColor)) end
            end
            if native.normalFontObject and control.SetNormalFontObject then control:SetNormalFontObject(native.normalFontObject) end
            if native.highlightFontObject and control.SetHighlightFontObject then control:SetHighlightFontObject(native.highlightFontObject) end
            if native.disabledFontObject and control.SetDisabledFontObject then control:SetDisabledFontObject(native.disabledFontObject) end
            control._exControlFontStyle = nil
            control._exControlAppearance = nil
        end
    end
end

function UI:ApplyPopupChildControls(popup, options)
    if not popup then return nil end
    options = type(options) == "table" and options or {}
    for _, button in ipairs(GetPopupButtons(popup)) do
        if button then
            local native = CapturePopupChildNative(button)
            button._exControlFontStyle = "settings"
            button._exControlAppearance = "flat"
            button._exRoundedRadius = 4
            button._exPopupChildActive = true
            for texture in pairs(native.textures) do texture:SetAlpha(0) end
            button:SetNormalFontObject(ButtonFont("text", A.metrics.control, true))
            button:SetHighlightFontObject(ButtonFont("text", A.metrics.control, true))
            button:SetDisabledFontObject(ButtonFont("disabled", A.metrics.control, true))
            if not button._exPopupChildHooks then
                button._exPopupChildHooks = true
                button:HookScript("OnEnter", function(self) self._exPopupChildHover = true; PaintPopupButton(self) end)
                button:HookScript("OnLeave", function(self) self._exPopupChildHover = false; self._exPopupChildPressed = false; PaintPopupButton(self) end)
                button:HookScript("OnMouseDown", function(self) self._exPopupChildPressed = true; PaintPopupButton(self) end)
                button:HookScript("OnMouseUp", function(self) self._exPopupChildPressed = false; PaintPopupButton(self) end)
                button:HookScript("OnEnable", PaintPopupButton)
                button:HookScript("OnDisable", PaintPopupButton)
            end
            PaintPopupButton(button)
        end
    end
    local editBox = GetPopupEditBox(popup)
    if editBox then
        CapturePopupChildNative(editBox)
        editBox._exControlFontStyle = "settings"
        editBox._exControlAppearance = "flat"
        editBox._exRoundedRadius = 4
        editBox._exPopupChildActive = true
        if editBox.Instructions then A.Font(editBox.Instructions, A.metrics.hint, C.muted, "") end
        if not editBox._exPopupChildHooks then
            editBox._exPopupChildHooks = true
            editBox:HookScript("OnEditFocusGained", PaintPopupEditBox)
            editBox:HookScript("OnEditFocusLost", PaintPopupEditBox)
            editBox:HookScript("OnShow", PaintPopupEditBox)
        end
        PaintPopupEditBox(editBox)
    end
    popup._exPopupChildrenRestoreOnHide = options.restoreOnHide == true
    if not popup._exPopupChildrenHideHook then
        popup._exPopupChildrenHideHook = true
        popup:HookScript("OnHide", function(self)
            if self._exPopupChildrenRestoreOnHide then UI:RestorePopupChildControls(self) end
        end)
    end
    return popup
end

local function PaintNativePanelTab(tab)
    if not tab or not tab._exNativeTabAppearance then return end
    local selected = tab.LeftActive and tab.LeftActive:IsShown()
    local available = not tab.isDisabled
    local hovered = available and tab._exNativeTabHover and not selected
    local pressed = available and tab._exNativeTabPressed and not selected
    local fill = selected and { .105, .122, .153, 1 }
        or pressed and C.pressed or hovered and C.hover or C.input
    local edge = selected and C.accent or hovered and { .25, .28, .33, 1 } or C.line
    Surface(tab, fill, edge)
    for _, texture in ipairs(tab.TabTextures or {}) do texture:SetAlpha(0) end
    local label = tab.Text or (tab.GetFontString and tab:GetFontString())
    A.Font(label, A.metrics.control, not available and C.disabled or selected and C.text or C.muted, "")
end

-- Instance-only adapter for Blizzard PanelTabButtonTemplate descendants. The
-- template's texture visibility remains the selection state used by
-- PanelTemplates_*; only alpha is suppressed, so IDs, resizing, anchors and
-- Select/Deselect/Disable behavior continue to run unchanged.
function UI:ApplyNativePanelTabAppearance(tab)
    if not tab then return nil end
    tab._exControlFontStyle = "settings"
    tab._exControlAppearance = "flat"
    tab._exRoundedRadius = 4
    tab._exNativeTabAppearance = true
    if not tab._exNativeTabHooks then
        tab._exNativeTabHooks = true
        tab:HookScript("OnEnter", function(self) self._exNativeTabHover = true; PaintNativePanelTab(self) end)
        tab:HookScript("OnLeave", function(self) self._exNativeTabHover = false; self._exNativeTabPressed = false; PaintNativePanelTab(self) end)
        tab:HookScript("OnMouseDown", function(self) self._exNativeTabPressed = true; PaintNativePanelTab(self) end)
        tab:HookScript("OnMouseUp", function(self) self._exNativeTabPressed = false; PaintNativePanelTab(self) end)
        tab:HookScript("OnClick", PaintNativePanelTab)
        tab:HookScript("OnEnable", PaintNativePanelTab)
        tab:HookScript("OnDisable", PaintNativePanelTab)
        tab:HookScript("OnShow", PaintNativePanelTab)
        -- PanelTemplates_SelectTab/DeselectTab express state by showing or
        -- hiding the active slices. Hook those regions on this tab instance so
        -- programmatic PanelTemplates_SetTab calls repaint without a global hook.
        for _, texture in ipairs({ tab.LeftActive, tab.MiddleActive, tab.RightActive }) do
            if texture then
                hooksecurefunc(texture, "Show", function() PaintNativePanelTab(tab) end)
                hooksecurefunc(texture, "Hide", function() PaintNativePanelTab(tab) end)
            end
        end
    end
    PaintNativePanelTab(tab)
    return tab
end

function UI:RefreshNativePanelTabAppearance(tab)
    PaintNativePanelTab(tab)
end

function UI:ApplyControlAppearance(frame, appearance)
    if not frame or (appearance or self:GetControlAppearance(frame)) ~= "flat" then return frame end
    local kind = frame._gridType
    local scopedSize = self:GetControlFontSize(frame)
    local controlSize = scopedSize or A.metrics.control
    local reference = A.GetReference(frame)
    if kind == "GridButton" then
        Surface(frame, reference and reference.button or C.button, reference and reference.lineStrong)
        local size = scopedSize or ((frame:GetWidth() < 38 or frame:GetHeight() < 24) and 11 or A.metrics.control)
        local settings = self:GetControlFontStyle(frame) == "settings"
        frame:SetNormalFontObject(ButtonFont("text", size, settings, reference))
        frame:SetHighlightFontObject(ButtonFont(reference and "value" or "text", size, settings, reference))
        frame:SetDisabledFontObject(ButtonFont("disabled", size, settings, reference))
        ButtonTexture(frame, "GetNormalTexture", C.button, 0)
        ButtonTexture(frame, "GetHighlightTexture", reference and reference.focus or C.accent, .13)
        ButtonTexture(frame, "GetPushedTexture", reference and reference.focus or C.accent, .24)
        ButtonTexture(frame, "GetDisabledTexture", C.input, .4)
        frame:SetPushedTextOffset(0, -1)
        A.Font(frame:GetFontString(), size, reference and reference.text or C.text, nil, "GameFontNormalSmall")
        if reference and not frame._exReferenceButtonHover then
            frame._exReferenceButtonHover = true
            frame:HookScript("OnEnter", function(self) ReferenceButtonHover(self, true) end)
            frame:HookScript("OnLeave", function(self) ReferenceButtonHover(self, false) end)
        end
    elseif kind == "GridDropdown" or kind == "GridLSMDropdown" then
        if reference == A.DungeonAura then
            for _, texture in ipairs(frame._exFlatSurface or {}) do texture:Hide() end
        else Surface(frame, reference and reference.input, reference and reference.inputBorder) end
        if reference == A.LoadCard and not frame._exLoadChevron then
            frame._exLoadChevron = {}
            for index = 1, 2 do
                local texture = frame:CreateTexture(nil, "OVERLAY")
                texture:SetColorTexture(1, 1, 1, 1)
                texture:SetSize(7, 2)
                texture:SetPoint("RIGHT", index == 1 and -15 or -11, 0)
                texture:SetRotation(index == 1 and -math.pi / 4 or math.pi / 4)
                frame._exLoadChevron[index] = texture
            end
        end
        if not frame._exFlatChevron then
            frame._exFlatChevron = frame:CreateTexture(nil, "OVERLAY")
            frame._exFlatChevron:SetTexture(QINGLAN_MEDIA .. "GlyphChevron.tga", "CLAMP", "CLAMP", "LINEAR")
            frame._exFlatChevron:SetSize(16, 16)
            frame._exFlatChevron:SetPoint("RIGHT", -7, 0)
            if frame._exFlatChevron.SetSnapToPixelGrid then frame._exFlatChevron:SetSnapToPixelGrid(false) end
            if frame._exFlatChevron.SetTexelSnappingBias then frame._exFlatChevron:SetTexelSnappingBias(0) end
            frame:HookScript("OnEnable", DropdownState)
            frame:HookScript("OnDisable", DropdownState)
            frame:HookScript("OnEnter", function(self) self._exDropdownHover = true; DropdownState(self) end)
            frame:HookScript("OnLeave", function(self) self._exDropdownHover = false; self._exDropdownPressed = false; DropdownState(self) end)
            frame:HookScript("OnMouseDown", function(self) self._exDropdownPressed = true; DropdownState(self) end)
            frame:HookScript("OnMouseUp", function(self) self._exDropdownPressed = false; DropdownState(self) end)
        end
        frame.Text:ClearAllPoints()
        frame.Text:SetPoint("LEFT", 9, 0); frame.Text:SetPoint("RIGHT", -27, 0)
        frame.Text:SetHeight(controlSize + 5)
        frame:SetHeight(A.metrics.height)
        frame._exGridFixedHeight = A.metrics.height
        DropdownState(frame)
    elseif kind == "GridInput" then
        A.Font(frame, math.max(16, controlSize), reference and reference.value, "")
        frame:SetTextInsets(9, 9, 0, 0)
        InputFocus(frame)
        if not frame._exFlatFocusHook then
            frame._exFlatFocusHook = true
            frame:HookScript("OnEditFocusGained", InputFocus)
            frame:HookScript("OnEditFocusLost", InputFocus)
        end
        A.Font(frame.placeholder, scopedSize and math.max(14, scopedSize - 2) or A.metrics.hint, reference == A.LoadCard and reference.muted or C.muted, "")
        if frame.placeholder then
            frame.placeholder:ClearAllPoints()
            frame.placeholder:SetPoint("LEFT", frame, "LEFT", 9, 0)
            frame.placeholder:SetPoint("RIGHT", frame, "RIGHT", -9, 0)
            frame.placeholder:SetJustifyH("LEFT")
            frame.placeholder:SetWordWrap(false)
        end
    elseif kind == "GridHeader" then
        A.Font(frame.Title, A.metrics.section)
        if frame.Line then frame.Line:SetColorTexture(unpack(C.line)) end
    elseif kind == "GridSubheader" then
        A.Font(frame.text, A.metrics.section)
    elseif kind == "GridDescription" then
        A.Font(frame.text, A.metrics.hint, C.muted)
    elseif kind == "GridCheckbox" then
        Checkbox(frame)
    elseif kind == "GridSlider" then
        self:ApplyFontGroupSliderAppearance(frame)
    elseif kind == "GridColorButton" then
        PhysicalWrappedBackdrop(frame)
        PhysicalWrappedBackdrop(frame.swatchBorder)
    elseif frame.editBox and frame.editBox ~= frame then
        -- A multiline editor is an exclusive retained subtree of its caller.
        Surface(frame)
        A.Font(frame.editBox, controlSize, nil, "")
    end
    if kind ~= "GridSubheader" and kind ~= "GridDescription" then A.Font(frame.labelText, scopedSize or A.metrics.text) end
    if kind ~= "GridButton" then A.Font(frame.label, scopedSize or A.metrics.text) end
    return frame
end

-- Entry points use the existing constructors, menu/search and commit contracts.
-- Explicit Flat APIs also work under shared hosts without marking that host.
local flatAPI = setmetatable({ _requestedAppearance = "flat" }, { __index = UI })
for _, suffix in ipairs({ "Button", "EditBox", "Dropdown", "MultiSelectDropdown",
    "LSMDropdown", "LSMTextureDropdown", "LSMSoundDropdown", "Checkbox", "Slider", "Header", "ColorButton" }) do
    local original = UI["Create" .. suffix]
    UI["Create" .. suffix] = function(self, parent, ...)
        local frame = original(self, parent, ...)
        return UI:ApplyControlAppearance(frame, self._requestedAppearance or UI:GetControlAppearance(parent))
    end
    UI["CreateFlat" .. suffix] = function(_, parent, ...)
        return UI["Create" .. suffix](flatAPI, parent, ...)
    end
end
