-- Qinglan V33 / AXIS HTML reference: isolated EXUI showcase, no saved data.
-- Retained for the lifetime of this demo; never return these hooked controls
-- to shared pools. Close only hides the root. No shared constructors patched.
local UI = ExwindTools.UI
local MEDIA = "Interface\\AddOns\\ExwindCore\\Textures\\QinglanRoundedLab\\"
local root
local C = {
    panel={.035,.035,.043,1}, card={.068,.068,.078,1}, input={.035,.035,.043,1},
    button={.153,.153,.165,1}, hover={.23,.23,.25,1}, pressed={.10,.10,.12,1},
    border={.153,.153,.165,1}, accent={.23,.51,.96,1}, muted={.44,.44,.48,1},
}
local function Text(parent, text, x, y, width, font)
    local fs=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlight")
    fs:SetPoint("TOPLEFT",x,-y); fs:SetWidth(width); fs:SetJustifyH("LEFT"); fs:SetText(text)
    local path=fs:GetFont(); fs:SetFont(path,font=="GameFontNormalLarge" and 18 or 12,""); fs:SetTextColor(.90,.90,.92,1); fs:SetShadowOffset(0,0)
    return fs
end
local function SuppressSquare(f)
    if f.SetBackdrop then f:SetBackdrop(nil) end
    for _,t in ipairs(f._exFlatSurface or {}) do t:Hide() end
    for _,piece in ipairs(f._exRoundedControlSkin and f._exRoundedControlSkin.pieces or {}) do
        local texture=piece.texture or piece.t
        if texture then texture:Hide() end
    end
    if f.Background then f.Background:SetAlpha(0) end
    for _,method in ipairs({"GetNormalTexture","GetHighlightTexture","GetPushedTexture","GetDisabledTexture"}) do
        local t=f[method] and f[method](f)
        if t then t:SetAlpha(0) end
    end
end
local function PhysicalPixel(frame)
    local scale=frame:GetEffectiveScale()
    scale=type(scale)=="number" and scale>0 and scale or 1
    local pixelUtil=_G.PixelUtil
    return pixelUtil and pixelUtil.GetNearestPixelSize and pixelUtil.GetNearestPixelSize(1,scale,1) or (1/scale)
end
local CHECK_SIZE, CHECK_MARK_SIZE = 22, 20
local INPUT_FONT_SIZE, NUMBER_INPUT_FONT_SIZE = 16, 15
local function StyleInputTypography(input,size)
    if not input or not input.GetFont then return end
    local font,_,flags=input:GetFont()
    if font then input:SetFont(font,size or INPUT_FONT_SIZE,flags or "") end
    for _,placeholder in ipairs({input.placeholder,input.Instructions}) do
        if placeholder and placeholder.GetFont then
            local placeholderFont,_,placeholderFlags=placeholder:GetFont()
            if placeholderFont then placeholder:SetFont(placeholderFont,size or INPUT_FONT_SIZE,placeholderFlags or "") end
        end
    end
end
-- Explicit radius zero is a rectangular surface, with no mask or image padding.
local function SquareSkin(f,fill,border)
    local s=f._qinglanSquare
    if not s then
        s={}; f._qinglanSquare=s
        for i=1,5 do
            s[i]=f:CreateTexture(nil,i==1 and "BACKGROUND" or "BORDER")
            s[i]:SetSnapToPixelGrid(true); s[i]:SetTexelSnappingBias(0)
        end
        s[1]:SetAllPoints(f)
        local function Layout()
            local px=PhysicalPixel(f)
            s[2]:SetPoint("TOPLEFT"); s[2]:SetPoint("TOPRIGHT"); s[2]:SetHeight(px)
            s[3]:SetPoint("BOTTOMLEFT"); s[3]:SetPoint("BOTTOMRIGHT"); s[3]:SetHeight(px)
            s[4]:SetPoint("TOPLEFT"); s[4]:SetPoint("BOTTOMLEFT"); s[4]:SetWidth(px)
            s[5]:SetPoint("TOPRIGHT"); s[5]:SetPoint("BOTTOMRIGHT"); s[5]:SetWidth(px)
        end
        f:HookScript("OnShow",Layout); f:HookScript("OnSizeChanged",Layout)
        Layout()
    end
    for i,t in ipairs(s) do t:SetColorTexture(unpack(i==1 and fill or border)) end
end
-- Nine pieces from the existing padded high-quality texture. The four corners
-- keep their UI dimensions; only edge lengths and center dimensions change.
local function Skin(f, radius, fill, border)
    if radius==0 then return SquareSkin(f,fill,border) end
    local s=f._qinglanSkin
    if not s then
        local sourceRadius = radius
        local fillFile="FillR"..sourceRadius
        local edgeFile=sourceRadius==18 and "BorderR18Thin" or "BorderR"..sourceRadius
        s={pieces={},radius=sourceRadius,fill=fill,border=border}
        f._qinglanSkin=s
        local u={0,(6+sourceRadius)/256,(250-sourceRadius)/256,1}
        local v={0,(23+sourceRadius)/128,(105-sourceRadius)/128,1}
        for layer=1,2 do
            for row=1,3 do for col=1,3 do
                local t=f:CreateTexture(nil,layer==1 and "BACKGROUND" or "BORDER")
                -- These UV regions share a full-panel image. Mipmaps average
                -- adjacent regions when a narrow strip is compressed and can
                -- contaminate its transparent padding (cross-shaped bleed).
                -- Bilinear base-level sampling preserves the authored alpha AA
                -- without sampling the downscaled mip levels of other slices.
                t:SetTexture(MEDIA..(layer==1 and fillFile or edgeFile)..".tga","CLAMP","CLAMP","LINEAR")
                t:SetTexCoord(u[col],u[col+1],v[row],v[row+1])
                t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0)
                s.pieces[#s.pieces+1]={t=t,row=row,col=col,layer=layer}
            end end
        end
        s.Layout=function()
            local w,h=f:GetWidth(),f:GetHeight()
            if w<=0 or h<=0 then return end
            local physicalPixel=PhysicalPixel(f)
            -- Match the shared ControlAppearance contract: one authored border
            -- texel maps to one physical pixel and every seam is pixel-snapped.
            local scale=math.min(physicalPixel,w/(s.radius*2),h/(s.radius*2))
            local corner=s.radius*scale
            local xs={-6*scale,corner,w-corner,w+6*scale}
            local ys={-23*scale,corner,h-corner,h+23*scale}
            local function Snap(value)
                if value>=0 then return math.floor(value/physicalPixel+.5)*physicalPixel end
                return math.ceil(value/physicalPixel-.5)*physicalPixel
            end
            for index=1,4 do xs[index],ys[index]=Snap(xs[index]),Snap(ys[index]) end
            for _,p in ipairs(s.pieces) do
                local pw,ph=xs[p.col+1]-xs[p.col],ys[p.row+1]-ys[p.row]
                p.t:ClearAllPoints()
                p.t:SetPoint("TOPLEFT",f,"TOPLEFT",xs[p.col],-ys[p.row])
                p.t:SetSize(math.max(.001,pw),math.max(.001,ph))
                p.t:SetShown(pw>0 and ph>0)
            end
        end
        f:HookScript("OnSizeChanged",s.Layout)
        f:HookScript("OnShow",s.Layout)
    end
    s.fill,s.border=fill,border
    for _,p in ipairs(s.pieces) do p.t:SetVertexColor(unpack(p.layer==1 and fill or border)) end
    s.Layout()
end
local function Glyph(parent,name,size,layer)
    local texture=parent:CreateTexture(nil,layer or "OVERLAY")
    texture:SetTexture(MEDIA..name..".tga","CLAMP","CLAMP","LINEAR")
    texture:SetSize(size,size); texture:SetSnapToPixelGrid(false); texture:SetTexelSnappingBias(0)
    return texture
end
local function StyleCheckbox(container)
    local box=container.checkbox
    if box._qinglanCheckPaint then box._qinglanCheckPaint(); return end
    -- Enlarge the visual/hit area without shifting the adjacent label anchor.
    box:SetHitRectInsets(-1,-1,-1,-1)
    if container.label then
        container.label:ClearAllPoints()
        container.label:SetPoint("LEFT",box,"RIGHT",6,-1)
        container.label:SetHeight(20)
        container.label:SetJustifyV("MIDDLE")
    end
    local fill=Glyph(box,"CheckFill",CHECK_SIZE,"BACKGROUND"); fill:SetPoint("CENTER")
    local border=Glyph(box,"CheckBorder",CHECK_SIZE,"BORDER"); border:SetPoint("CENTER")
    local mark=Glyph(box,"GlyphCheck",CHECK_MARK_SIZE); mark:SetPoint("CENTER")
    local function LayoutPixelBorder()
        local px=PhysicalPixel(box)
        box:SetSize(CHECK_SIZE*px,CHECK_SIZE*px)
        fill:SetSize(CHECK_SIZE*px,CHECK_SIZE*px); border:SetSize(CHECK_SIZE*px,CHECK_SIZE*px)
        mark:SetSize(CHECK_MARK_SIZE*px,CHECK_MARK_SIZE*px)
    end
    local boxHover,labelHover,pressed=false,false,false
    local function Paint()
        SuppressSquare(box)
        if box:GetCheckedTexture() then box:GetCheckedTexture():SetAlpha(0) end
        if box:GetDisabledCheckedTexture() then box:GetDisabledCheckedTexture():SetAlpha(0) end
        local enabled=box:IsEnabled()
        local selected=box:GetChecked()==true
        local hover=enabled and (boxHover or labelHover)
        local color=selected and {.20,.46,.82,1} or {.075,.08,.095,1}
        if hover then color=selected and {.27,.55,.93,1} or {.13,.145,.17,1} end
        if pressed and enabled then color=selected and {.15,.35,.66,1} or {.055,.06,.07,1} end
        fill:SetVertexColor(unpack(color)); fill:SetAlpha(enabled and 1 or .45)
        border:SetVertexColor(unpack(hover and {.53,.66,.83,1} or selected and {.30,.56,.88,1} or {.32,.34,.39,1}))
        border:SetAlpha(enabled and 1 or .45)
        mark:SetShown(selected); mark:SetVertexColor(.98,.98,1,enabled and 1 or .4)
        if container.label then container.label:SetTextColor(unpack(enabled and {.9,.9,.92,1} or C.muted)) end
    end
    box._qinglanCheckPaint=Paint
    hooksecurefunc(box,"SetChecked",Paint)
    box:HookScript("OnClick",Paint)
    box:HookScript("OnEnable",Paint); box:HookScript("OnDisable",Paint)
    box:HookScript("OnEnter",function() boxHover=true; Paint() end)
    box:HookScript("OnLeave",function() boxHover=false; pressed=false; Paint() end)
    box:HookScript("OnMouseDown",function(_,button) if button=="LeftButton" then pressed=true; Paint() end end)
    box:HookScript("OnMouseUp",function() pressed=false; Paint() end)
    container:EnableMouse(true)
    container:HookScript("OnEnter",function() labelHover=true; Paint() end)
    container:HookScript("OnLeave",function() labelHover=false; pressed=false; Paint() end)
    container:HookScript("OnMouseDown",function(_,button) if button=="LeftButton" then pressed=true; Paint() end end)
    container:HookScript("OnMouseUp",function(_,button)
        local activate=pressed and button=="LeftButton" and box:IsEnabled()
        pressed=false
        if activate then box:Click() end
        Paint()
    end)
    container:HookScript("OnHide",function() boxHover=false; labelHover=false; pressed=false; Paint() end)
    container:HookScript("OnShow",function() LayoutPixelBorder(); Paint() end)
    LayoutPixelBorder(); Paint()
end
local function Control(f,kind,radius)
    local function Paint()
        SuppressSquare(f)
        local enabled=not f.IsEnabled or f:IsEnabled()
        local active=f._qinglanHover or (kind=="input" and f:HasFocus())
        local fill=f._axisFill or (kind=="button" and C.button or C.input)
        if active then fill=f._axisText and {.86,.86,.88,1} or C.hover end
        if f._qinglanDown then fill=f._axisText and {.73,.73,.76,1} or C.pressed end
        Skin(f,radius or 4,enabled and fill or C.input,enabled and (active and C.accent or f._axisEdge or C.border) or C.border)
        local label=f.GetFontString and f:GetFontString()
        if label then label:SetTextColor(unpack(enabled and (f._axisText or {.90,.90,.92,1}) or C.muted)) end
    end
    f:HookScript("OnEnter",function() f._qinglanHover=true; Paint() end)
    f:HookScript("OnLeave",function() f._qinglanHover=false; f._qinglanDown=false; Paint() end)
    if kind=="button" then
        f:HookScript("OnMouseDown",function() f._qinglanDown=true; Paint() end)
        f:HookScript("OnMouseUp",function() f._qinglanDown=false; Paint() end)
    elseif kind=="input" then
        StyleInputTypography(f)
        f:HookScript("OnEditFocusGained",Paint)
        f:HookScript("OnEditFocusLost",Paint)
    end
    if f.IsEnabled then f:HookScript("OnEnable",Paint); f:HookScript("OnDisable",Paint) end
    f:HookScript("OnShow",Paint)
    f._qinglanPaint=Paint
    Paint()
    return f
end
local function Button(parent,label,w,h,x,y,callback)
    local f=UI:CreateFlatButton(parent,w,h,label,callback)
    f:SetPoint("TOPLEFT",x,-y)
    return Control(f,"button",w <= 32 and 0 or 4)
end
local function Input(parent,value,w,x,y,callback)
    local f=UI:CreateFlatEditBox(parent,value,w,32,nil,{onChanged=callback})
    f:SetPoint("TOPLEFT",x,-y)
    return Control(f,"input")
end
local function SkinSlider(f,label,reference)
    -- This is the pre-existing FontGroup Slider appearance and remains the
    -- visual source of truth. Standalone demos opt into this same `reference`
    -- path; the FontGroup is never restyled from a standalone Slider.
    local actual=f.Slider or f
    if actual._exFlatTrack then actual._exFlatTrack:Hide() end
    local track=CreateFrame("Frame",nil,actual)
    track:SetPoint("LEFT",actual,"LEFT"); track:SetPoint("RIGHT",actual,"RIGHT"); track:SetHeight(reference and 3 or 6)
    track:SetFrameLevel(actual:GetFrameLevel())
    if reference then
        local line=track:CreateTexture(nil,"BACKGROUND"); line:SetAllPoints(); line:SetColorTexture(.14,.15,.17,1)
    else Skin(track,0,{.10,.18,.24,1},C.border) end
    local thumb=actual.GetThumbTexture and actual:GetThumbTexture()
    if thumb then
        thumb:SetSize(reference and 16 or 18,reference and 10 or 22); thumb:SetAlpha(0)
        local knob=CreateFrame("Frame",nil,actual)
        knob:SetAllPoints(thumb); knob:SetFrameLevel(actual:GetFrameLevel()+2)
        if reference then
            local dot=knob:CreateTexture(nil,"ARTWORK")
            dot:SetPoint("CENTER"); dot:SetSize(160/9,120/11)
            -- Reuse the antialiased rounded thumb, including one-unit padding.
            dot:SetTexture(MEDIA.."KnobR3.tga","CLAMP","CLAMP","LINEAR")
            dot:SetTexCoord(118/256,138/256,52/128,76/128)
            dot:SetSnapToPixelGrid(false); dot:SetTexelSnappingBias(0)
            dot:SetVertexColor(.68,.71,.76,1)
            actual:HookScript("OnEnter",function() dot:SetVertexColor(.76,.82,.90,1) end)
            actual:HookScript("OnLeave",function() dot:SetVertexColor(.68,.71,.76,1) end)
        else Skin(knob,0,C.accent,C.accent) end
    end
    -- Header row: left title, right editable value. Track is the row below.
    if f.numberInput then
        local input=f.numberInput
        if reference then
            local function PaintValue()
                SuppressSquare(input)
                Skin(input,4,{.133,.137,.145,1},input:HasFocus() and {.36,.40,.46,1} or {.20,.204,.22,1})
                input:SetTextColor(.95,.95,.97,1)
            end
            input:HookScript("OnEditFocusGained",PaintValue); input:HookScript("OnEditFocusLost",PaintValue)
            input:HookScript("OnShow",PaintValue); PaintValue()
        else Control(input,"input",0) end
        input:ClearAllPoints()
        input:SetPoint("BOTTOMRIGHT",reference and track or f,"TOPRIGHT",0,reference and 6 or 8)
        input:SetSize(reference and 44 or 58,reference and 24 or 24)
        StyleInputTypography(input,reference and NUMBER_INPUT_FONT_SIZE or INPUT_FONT_SIZE)
        input:SetTextColor(.95,.95,.97,1)
    end
    if f.Title then
        f.Title:ClearAllPoints()
        f.Title:SetPoint("BOTTOMLEFT",reference and track or f,"TOPLEFT",0,reference and 7 or 8)
        if reference and f.numberInput then
            f.Title:SetPoint("BOTTOMRIGHT",f.numberInput,"BOTTOMLEFT",-12,1)
        else f.Title:SetPoint("BOTTOMRIGHT",f,"TOPRIGHT",-70,8) end
        f.Title:SetHeight(reference and 20 or 24); f.Title:SetJustifyH("LEFT"); f.Title:SetJustifyV("MIDDLE")
        local font=f.Title:GetFont(); f.Title:SetFont(font,reference and 14 or 12,""); f.Title:SetTextColor(.88,.88,.91,1)
        f.Title:SetText(label); f.Title:Show()
    end
    if f.Back then f.Back:Hide() end
    if f.Forward then f.Forward:Hide() end
    return f
end
local function ApplyFontGroupSlider(f,label)
    if UI.ApplyFontGroupSliderAppearance then
        UI:ApplyFontGroupSliderAppearance(f)
        if f.numberInput then
            f.numberInput:SetSize(44,24)
            StyleInputTypography(f.numberInput,NUMBER_INPUT_FONT_SIZE)
        end
        return f
    end
    -- Fallback reproduces the parked FontGroup's reference=true path plus the
    -- four-pixel card lift that its caller applied after SkinSlider.
    SkinSlider(f,label,true)
    if f.numberInput then
        local point,relative,relativePoint,x,y=f.numberInput:GetPoint(1)
        f.numberInput:SetPoint(point,relative,relativePoint,x,y+4)
    end
    if f.Title then
        local point,relative,relativePoint,x,y=f.Title:GetPoint(1)
        f.Title:SetPoint(point,relative,relativePoint,x,y+4)
    end
    return f
end
local function Slider(parent,label,w,x,y,min,max,value,callback,reference)
    local f=UI:CreateFlatSlider(parent,w,label,min,max,value,1,nil,{onLive=callback,onCommit=callback})
    f:SetPoint("TOPLEFT",x,-y)
    return SkinSlider(f,label,reference)
end
-- AXIS reference adaptation. All values belong only to this preview session.
-- Theme adapters for the real GUI composite settings groups. Each instance
-- keeps Core's controls, callbacks, DB binding and popup lifecycle intact.
local Settings = {}
_G.ExwindQinglanRoundedLabSettings = Settings
local function SettingsTitle(fontString,size)
    if not fontString then return end
    local font=fontString:GetFont()
    fontString:SetFont(font,size or 14,""); fontString:SetShadowOffset(0,0)
end
local function StyleSettingsGroup(group)
    local controls,paths={},{}
    for _,entry in ipairs(group._exCompositeControls or {}) do
        controls[entry.control]=entry.kind; paths[entry.control]=entry.path
    end
    local function Visit(frame)
        SettingsTitle(frame.Title); SettingsTitle(frame.labelText); SettingsTitle(frame.label)
        local kind=controls[frame]
        if kind then
            if kind=="slider" then
                local label=frame.Title or frame.labelText
                ApplyFontGroupSlider(frame,label and label:GetText() or "")
                local parent=frame:GetParent()
                if parent:GetHeight()<=70 then
                    -- Identify the content through its real controls, not the
                    -- optional relative frame returned by a shorthand anchor.
                    local content=parent:GetParent()
                    if content and content:GetParent()==group then group._qinglanContent=content end
                    -- Center the visible block, not the native slider frame:
                    -- title top is 32.5 above the track, thumb bottom 5 below.
                    local trackOffset=-(32.5-5)/2
                    frame:ClearAllPoints()
                    frame:SetPoint("LEFT",parent,"LEFT",10,trackOffset)
                    frame:SetPoint("RIGHT",parent,"RIGHT",-10,trackOffset)
                    local actual=frame.Slider
                    if actual then
                        actual:ClearAllPoints(); actual:SetPoint("LEFT",frame,"LEFT",0,0); actual:SetPoint("RIGHT",frame,"RIGHT",0,0)
                    end
                end
            elseif kind=="edit" then
                Control(frame,"input",4)
            elseif kind=="color" then
                Control(frame,"button",4)
                local update=frame.UpdateColor
                frame.UpdateColor=function(self,...)
                    update(self,...); self._qinglanPaint()
                end
                frame:UpdateColor()
            elseif kind=="check" then
                StyleCheckbox(frame)
            elseif kind=="dropdown" then
                Settings.ReplaceDropdown(frame,paths[frame])
            end
            return
        end
        for _,region in ipairs({frame:GetRegions()}) do
            if region:IsObjectType("FontString") then SettingsTitle(region) end
        end
        local objectType=frame:GetObjectType()
        if objectType=="DropdownButton" then
            Settings.ReplaceDropdown(frame); return
        elseif objectType=="Button" then
            -- Keep the native close glyph on texture-only utility buttons.
            if frame:GetNormalTexture() and not frame:GetFontString() then return end
            -- Core utility buttons own a plain FontString; register it so the
            -- theme also restores white text after their native green hover.
            if not frame:GetFontString() then
                for _,region in ipairs({frame:GetRegions()}) do
                    if region:IsObjectType("FontString") then frame:SetFontString(region); break end
                end
            end
            frame._axisFill=C.panel
            frame._axisEdge={.247,.247,.275,1}
            Control(frame,"button",4)
        elseif frame==group then
            SuppressSquare(frame)
            for _,line in ipairs(frame.crispOutline or {}) do line:Hide() end
        elseif frame.GetBackdrop and frame:GetBackdrop() then
            local isGroup=frame==group
            SuppressSquare(frame)
            Skin(frame,isGroup and 8 or 4,isGroup and C.card or C.panel,C.border)
            for _,line in ipairs(frame._exMetricCardPhysicalOutline or frame.crispOutline or {}) do line:Hide() end
        end
        for _,child in ipairs({frame:GetChildren()}) do Visit(child) end
    end
    Visit(group)
    for _,popup in ipairs(group._exCompositePopups or {}) do Visit(popup) end
    if group._exCompositeTitle then
        local header=group._exCompositeTitle:GetParent()
        header:Hide()
        local content=group._qinglanContent
        if content then
            content:ClearAllPoints(); content:SetPoint("TOPLEFT",group,"TOPLEFT",0,0)
        end
        group:SetHeight(group:GetHeight()-40)
    end
    return group
end
local function AlignSettingsActions(group,isTimer)
    local action
    for _,entry in ipairs(group._exCompositeControls or {}) do
        if entry.path=="showIcon" and entry.kind=="check" then action=entry.control:GetParent(); break end
    end
    if not action then return group end
    local buttons,checks={},{}
    for _,child in ipairs({action:GetChildren()}) do
        if child:IsObjectType("Button") and child:GetScript("OnClick") then buttons[#buttons+1]=child end
    end
    for _,entry in ipairs(group._exCompositeControls or {}) do
        if entry.kind=="check" and entry.control:GetParent()==action then checks[#checks+1]=entry.control end
    end
    local function ByRow(a,b) return (select(5,a:GetPoint(1)) or 0)>(select(5,b:GetPoint(1)) or 0) end
    table.sort(buttons,ByRow); table.sort(checks,ByRow)
    for i,button in ipairs(buttons) do
        button:ClearAllPoints(); button:SetPoint("TOPRIGHT",action,"TOPRIGHT",-10,-((isTimer and 17 or 6)+(i-1)*(isTimer and 68 or 32)))
        button:SetHeight(26)
    end
    for i,check in ipairs(checks) do
        check:ClearAllPoints(); check:SetPoint("TOPLEFT",action,"TOPLEFT",12,-((isTimer and 16 or 5)+(i-1)*(isTimer and 68 or 32)))
    end
    if isTimer then
        -- Align the standalone fill label with the other two text rows.
        local function AlignFillLabel(frame)
            for _,region in ipairs({frame:GetRegions()}) do
                if region:IsObjectType("FontString") then
                    local fillText=ExwindTools.L and ExwindTools.L["填充方式"] or "填充方式"
                    if region:GetText()==fillText then
                        region:ClearAllPoints(); region:SetPoint("LEFT",action,"TOPLEFT",12,-166)
                    end
                end
            end
            for _,child in ipairs({frame:GetChildren()}) do AlignFillLabel(child) end
        end
        AlignFillLabel(action)
    end
    return group
end
function Settings:CreateFontGroup(parent,width,label,db,onUpdate,opts)
    width=width or 934
    local group=UI:CreateFontGroup(parent,width,label,db,onUpdate,opts)
    group:SetHeight(268)
    if group._exCompositeReflow then group:_exCompositeReflow(width,268) end
    return StyleSettingsGroup(group)
end
function Settings:CreateIconGroup(parent,width,label,db,key,onUpdate,opts)
    return AlignSettingsActions(StyleSettingsGroup(UI:CreateIconGroup(parent,width,label,db,key,onUpdate,opts)),false)
end
function Settings:CreateTimerBarGroup(parent,width,label,db,key,onUpdate,opts)
    return AlignSettingsActions(StyleSettingsGroup(UI:CreateTimerBarGroup(parent,width,label,db,key,onUpdate,opts)),true)
end

local function Build()
    if root then return end
    root=CreateFrame("Frame","ExwindQinglanRoundedLabRoot",UIParent)
    root:SetSize(1260,800); root:SetPoint("CENTER")
    root:SetScale(math.min(1,UIParent:GetWidth()/1310,UIParent:GetHeight()/850))
    root:SetFrameStrata("DIALOG"); root:SetClampedToScreen(true); root:SetMovable(true)
    UI:SetControlAppearance(root,"flat"); Skin(root,10,C.panel,C.border)
    local resets,sections,navs={},{},{}
    local status=Text(root,"QINGLAN / AXIS · 本地交互预览",226,778,1000)
    status:SetTextColor(.44,.44,.48,1)
    local function Say(s) status:SetText(s) end
    local titleSize=16
    local titleFonts,titleLookup={},setmetatable({},{__mode="k"})
    local function ApplyTitleSize(fontString)
        if not fontString or not fontString.GetFont then return end
        local font,_,flags=fontString:GetFont()
        if font then fontString:SetFont(font,titleSize,flags or "") end
    end
    local function RegisterTitle(fontString)
        if not fontString or titleLookup[fontString] then return fontString end
        titleLookup[fontString]=true; titleFonts[#titleFonts+1]=fontString
        ApplyTitleSize(fontString)
        return fontString
    end
    local function RegisterControlTitles(control)
        if not control then return end
        if control.IsObjectType and control:IsObjectType("FontString") then RegisterTitle(control) end
        for _,field in ipairs({"Title","labelText","label"}) do RegisterTitle(control[field]) end
        for _,entry in ipairs(control._exCompositeControls or {}) do RegisterControlTitles(entry.control) end
    end
    local function SetAllTitleSizes(value,announce)
        titleSize=math.floor((tonumber(value) or titleSize)+.5)
        for _,fontString in ipairs(titleFonts) do ApplyTitleSize(fontString) end
        if announce then Say("所有标题字号："..titleSize) end
    end
    local function Box(p,x,y,w,h,r,fill)
        local f=CreateFrame("Frame",nil,p); f:SetPoint("TOPLEFT",x,-y); f:SetSize(w,h)
        Skin(f,r or 4,fill or C.card,C.border); return f
    end
    local function Label(p,s,x,y,w,muted)
        local t=Text(p,s,x,y,w)
        if muted then t:SetTextColor(.52,.52,.57,1) end
        return t
    end
    local function Btn(p,s,x,y,w,h,variant,fn)
        local b=Button(p,s,w,h,x,y,fn or function() Say("已点击："..s) end)
        local fs=b:GetFontString(); local font=fs:GetFont(); fs:SetFont(font,h<=24 and 11 or 12,""); fs:SetShadowOffset(0,0)
        if variant=="blue" then b._axisFill={.145,.388,.922,1}; b._axisEdge=b._axisFill
        elseif variant=="white" then b._axisFill={.957,.957,.961,1}; b._axisText={.09,.09,.10,1}
        elseif variant=="danger" then b._axisFill={.14,.045,.055,1}; b._axisEdge={.30,.10,.12,1}; b._axisText={.97,.44,.44,1}
        elseif variant=="outline" then b._axisFill=C.panel; b._axisEdge={.247,.247,.275,1}
        elseif variant=="ghost" then b._axisFill=C.card; b._axisEdge=C.card end
        if b._qinglanPaint then b._qinglanPaint() end
        return b
    end
    local function Field(p,value,x,y,w,h,fn)
        local f=UI:CreateFlatEditBox(p,value,w,h or 28,nil,{onChanged=fn})
        f:SetPoint("TOPLEFT",x,-y); Control(f,"input",(h or 28)<=22 and 0 or 4)
        f:SetTextColor(.90,.90,.92,1)
        resets[#resets+1]=function() f:SetText(value) end
        return f
    end
    local function Check(p,label,x,y,initial,disabled,fn)
        local f=UI:CreateFlatCheckbox(p,label,initial,fn)
        f:SetPoint("TOPLEFT",x,-y); f:SetWidth(230)
        local b=f.checkbox
        if f.label then local font=f.label:GetFont(); f.label:SetFont(font,12,""); f.label:SetTextColor(.75,.75,.78,1) end
        StyleCheckbox(f)
        if disabled then b:Disable(); if f.label then f.label:SetAlpha(.45) end end
        resets[#resets+1]=function() b:SetChecked(initial); if fn then fn(initial) end end
        return f
    end
    local function Tabs(p,items,x,y,width,initial,fn)
        local holder=Box(p,x,y,width,34,4,C.panel)
        local buttons={}
        local function Select(v)
            for i,b in ipairs(buttons) do b._axisFill=i==v and C.button or C.panel; b._axisEdge=b._axisFill; b._qinglanPaint() end
            if fn then fn(items[v],v) end
        end
        for i,s in ipairs(items) do local index=i; buttons[i]=Btn(holder,s,3+(i-1)*(width-6)/#items,3,(width-6)/#items-2,28,"ghost",function() Select(index) end) end
        Select(initial); resets[#resets+1]=function() Select(initial) end
        return holder
    end
    local function ResetDropdown(f,value,label)
        resets[#resets+1]=function()
            f._currentValue=value
            if f.OverrideText then f:OverrideText(label) else f:SetText(label) end
            if f._onSelect then f._onSelect(value,label) end
        end
    end
    -- One retained popover shared by this demo's selects; no Blizzard radio menu.
    local menuFill={.125,.125,.133,1}
    local menuHover={.205,.205,.216,1}
    local menuEdge={.225,.225,.24,1}
    local activeSelect,popup,catcher
    local rows={}
    local filteredItems={}
    local highlighted=1
    local rowOffset=0
    local visibleRows=8
    local rowPitch=38
    -- Same normalization and literal substring matching as ExwindGUI.lua's
    -- NormalizeDropdownSearchText / GetDropdownLeafSearchText (local helpers).
    local function NormalizeSearch(text)
        local s=tostring(text or "")
        s=s:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
        s=s:gsub("|T.-|t"," "):gsub("|A.-|a"," "):gsub("%s+"," ")
        return string.lower(strtrim(s))
    end
    local function CloseSelect()
        if popup and popup.search then popup.search:ClearFocus() end
        if catcher then catcher:Hide() end
        if activeSelect then activeSelect._axisOpen=false; activeSelect._searchText=nil; activeSelect._axisPaint() end
        activeSelect=nil
    end
    local function PaintRows()
        if not activeSelect then return end
        local optionsTop=popup._axisOptionsTop or 56
        for i,row in ipairs(rows) do
            local entry=i<=visibleRows and filteredItems[rowOffset+i] or nil
            row:SetShown(entry~=nil)
            if entry then
                row:ClearAllPoints(); row:SetPoint("TOPLEFT",8,-optionsTop-(i-1)*rowPitch)
                row:SetWidth(popup:GetWidth()-16)
                row:SetHeight(rowPitch-2)
                row:SetText(entry[1])
                local label=row:GetFontString()
                label:SetFont(entry.mediaType=="font" and entry.path or row._axisFont,14,"")
                local isSound=entry.mediaType=="sound"
                local textured=entry.path and entry.mediaType and entry.mediaType~="font" and not isSound
                row._axisPreview:SetShown(textured~=nil and textured~=false)
                if textured then row._axisPreview:SetTexture(entry.path) end
                label:ClearAllPoints(); label:SetPoint("LEFT",textured and 84 or 38,0); label:SetPoint("RIGHT",isSound and -48 or -14,0)
                row._axisPlay._entry=isSound and entry or nil
                row._axisPlay:SetShown(isSound)
                SuppressSquare(row)
                local enabled=entry.disabled~=true
                row:SetEnabled(enabled)
                label:SetTextColor(unpack(enabled and {.91,.91,.93,1} or {.43,.45,.50,1}))
                local highlightedRow=enabled and rowOffset+i==highlighted
                Skin(row,8,highlightedRow and menuHover or menuFill,highlightedRow and menuHover or menuFill)
                local selected=activeSelect._axisMultiple and activeSelect._selections[entry[2]]==true
                    or (not activeSelect._axisMultiple and entry[2]==activeSelect._currentValue)
                for _,mark in ipairs(row._axisCheck) do mark:SetShown(selected); mark:SetAlpha(enabled and 1 or .35) end
                row._axisChoiceBorder:SetShown(activeSelect._axisMultiple==true)
                row._axisChoiceFill:SetShown(activeSelect._axisMultiple==true and selected)
                local choicePixel=PhysicalPixel(row)
                for _,mark in ipairs(row._axisCheck) do mark:SetSize(CHECK_MARK_SIZE*choicePixel,CHECK_MARK_SIZE*choicePixel) end
                row._axisChoiceBorder:SetSize(CHECK_SIZE*choicePixel,CHECK_SIZE*choicePixel)
                row._axisChoiceFill:SetSize(CHECK_SIZE*choicePixel,CHECK_SIZE*choicePixel)
                row._axisChoiceBorder:SetVertexColor(unpack(selected and {.30,.56,.88,1} or {.36,.38,.44,1}))
                row._axisChoiceBorder:SetAlpha(enabled and 1 or .35)
                row._axisChoiceFill:SetVertexColor(.20,.46,.82,enabled and 1 or .35)
            end
        end
    end
    local function Choose(index)
        if not activeSelect then return end
        local owner=activeSelect
        local entry=filteredItems[index]
        if not entry or entry.disabled then return end
        if owner._axisMultiple then
            owner._selections[entry[2]]=not owner._selections[entry[2]]
            owner:RefreshSelectionDisplay(); PaintRows()
            return
        end
        owner._currentValue=entry[2]; owner:OverrideText(entry[1])
        CloseSelect()
        if owner._onSelect then owner._onSelect(entry[2],entry[1]) end
    end
    local function MoveSelection(delta)
        if #filteredItems==0 then return end
        local nextIndex=highlighted
        for _=1,#filteredItems do
            nextIndex=(nextIndex-1+delta)%#filteredItems+1
            if not filteredItems[nextIndex].disabled then highlighted=nextIndex; break end
        end
        if highlighted<=rowOffset then rowOffset=highlighted-1
        elseif highlighted>rowOffset+visibleRows then rowOffset=highlighted-visibleRows end
        PaintRows()
        popup.range:SetText(#filteredItems>visibleRows and string.format("%d–%d / %d · 滚轮翻阅",rowOffset+1,math.min(rowOffset+visibleRows,#filteredItems),#filteredItems) or "")
    end
    local function RefreshSearch()
        if not activeSelect then return end
        local query=popup.search:GetText()
        local needle=NormalizeSearch(query)
        activeSelect._searchText=query~="" and query or nil
        filteredItems={}
        for _,entry in ipairs(activeSelect._axisItems) do
            local parts={}
            for _,key in ipairs({"searchText","label","text",1,2}) do
                if entry[key]~=nil then parts[#parts+1]=tostring(entry[key]) end
            end
            if needle=="" or NormalizeSearch(table.concat(parts," ")):find(needle,1,true) then
                filteredItems[#filteredItems+1]=entry
            end
        end
        highlighted=1
        for i,entry in ipairs(filteredItems) do if entry[2]==activeSelect._currentValue then highlighted=i end end
        rowOffset=math.max(0,math.min(highlighted-1,#filteredItems-visibleRows))
        popup.empty:SetShown(#filteredItems==0)
        popup.clear:SetShown(query~="")
        local count=math.max(1,math.min(visibleRows,#filteredItems))
        local hasOverflow=#filteredItems>visibleRows
        local multiple=activeSelect._axisMultiple==true
        local optionsTop=multiple and 100 or 56
        popup._axisOptionsTop=optionsTop
        local listEnd=optionsTop+count*rowPitch
        local contentEnd=listEnd+(hasOverflow and 20 or 0)
        popup:SetHeight(contentEnd+(multiple and 10 or 8))
        popup.range:ClearAllPoints(); popup.range:SetPoint("TOPLEFT",16,-listEnd)
        popup.range:SetText(hasOverflow and string.format("%d–%d / %d · 滚轮翻阅",rowOffset+1,math.min(rowOffset+visibleRows,#filteredItems),#filteredItems) or "")
        popup.clearAll:SetShown(multiple)
        popup.actionRule:SetShown(multiple)
        popup.listEndRule:SetShown(multiple)
        popup.empty:ClearAllPoints(); popup.empty:SetPoint("TOPLEFT",24,-optionsTop-9)
        if multiple then
            popup.clearAll:ClearAllPoints(); popup.clearAll:SetPoint("TOPLEFT",8,-56)
            popup.clearAll:SetWidth(popup:GetWidth()-16)
            popup.actionRule:ClearAllPoints(); popup.actionRule:SetPoint("TOPLEFT",12,-94); popup.actionRule:SetPoint("TOPRIGHT",-12,-94)
            popup.listEndRule:ClearAllPoints(); popup.listEndRule:SetPoint("TOPLEFT",12,-contentEnd-2); popup.listEndRule:SetPoint("TOPRIGHT",-12,-contentEnd-2)
            popup.actionRule:SetHeight(PhysicalPixel(popup)); popup.listEndRule:SetHeight(PhysicalPixel(popup))
        end
        popup:ClearAllPoints()
        local available=(activeSelect:GetBottom() or 0)*activeSelect:GetEffectiveScale()
        if available<(popup:GetHeight()+8)*catcher:GetEffectiveScale() then
            popup:SetPoint("BOTTOMLEFT",activeSelect,"TOPLEFT",0,6)
        else popup:SetPoint("TOPLEFT",activeSelect,"BOTTOMLEFT",0,-6) end
        PaintRows()
    end
    local function OpenSelect(owner)
        if activeSelect==owner then CloseSelect(); return end
        CloseSelect()
        visibleRows=owner._axisVisibleRows or 8
        rowPitch=owner._axisRowPitch or 38
        if owner._axisRefreshItems then owner:_axisRefreshItems() end
        if not catcher then
            catcher=UI:CreateFlatButton(UIParent,1,1,"",CloseSelect)
            catcher:SetScale(root:GetScale()); catcher:SetAllPoints(UIParent)
            catcher:SetFrameStrata("FULLSCREEN_DIALOG"); catcher:SetFrameLevel(100)
            SuppressSquare(catcher)
            catcher:EnableKeyboard(true); catcher:SetPropagateKeyboardInput(false)
            catcher:SetScript("OnKeyDown",function(_,key)
                if not activeSelect then return end
                if key=="ESCAPE" or key=="TAB" then CloseSelect()
                elseif key=="UP" then MoveSelection(-1)
                elseif key=="DOWN" then MoveSelection(1)
                elseif key=="ENTER" or key=="SPACE" then Choose(highlighted) end
            end)
            popup=CreateFrame("Frame",nil,catcher)
            popup:SetFrameLevel(110); popup:SetSize(320,120)
            popup:SetClampedToScreen(true); popup:EnableMouse(true)
            Skin(popup,10,menuFill,menuEdge)
            popup.search=UI:CreateFlatEditBox(popup,"",296,32,nil,{onChanged=RefreshSearch,placeholder=""})
            popup.search:SetPoint("TOPLEFT",12,-10); Control(popup.search,"input",4)
            StyleInputTypography(popup.search)
            popup.search:SetTextColor(.9,.9,.92,1); popup.search:SetMaxLetters(64)
            popup.search:SetTextInsets(34,28,0,0)
            if popup.search.placeholder then
                popup.search.placeholder:ClearAllPoints(); popup.search.placeholder:SetPoint("LEFT",26,0)
            end
            local searchIcon=Glyph(popup.search,"GlyphSearch",20)
            searchIcon:SetPoint("LEFT",7,0); searchIcon:SetVertexColor(.64,.67,.73,1)
            popup.search:HookScript("OnEditFocusGained",function() searchIcon:SetVertexColor(.76,.84,.96,1) end)
            popup.search:HookScript("OnEditFocusLost",function() searchIcon:SetVertexColor(.64,.67,.73,1) end)
            popup.clear=Btn(popup.search,"X",269,5,22,22,"ghost",function() popup.search:SetText(""); popup.search:SetFocus() end)
            popup.clear:ClearAllPoints(); popup.clear:SetPoint("RIGHT",popup.search,"RIGHT",-5,0)
            popup.search:SetScript("OnEnterPressed",function() Choose(highlighted) end)
            popup.search:SetScript("OnEscapePressed",CloseSelect)
            popup.search:SetScript("OnTabPressed",CloseSelect)
            popup.search:SetAltArrowKeyMode(false)
            popup.search:SetScript("OnArrowPressed",function(_,key)
                if key=="UP" then MoveSelection(-1) elseif key=="DOWN" then MoveSelection(1) end
            end)
            -- Do not let the modal frame eat typing or treat spaces as selection.
            popup.search:HookScript("OnEditFocusGained",function() catcher:EnableKeyboard(false) end)
            popup.search:HookScript("OnEditFocusLost",function() catcher:EnableKeyboard(true) end)
            popup.empty=Label(popup,"无匹配结果",24,65,272,true)
            popup.range=Label(popup,"",16,0,288,true)
            popup:EnableMouseWheel(true)
            popup:SetScript("OnMouseWheel",function(_,delta)
                rowOffset=math.max(0,math.min(rowOffset-delta,math.max(0,#filteredItems-visibleRows)))
                PaintRows()
                popup.range:SetText(#filteredItems>visibleRows and string.format("%d–%d / %d · 滚轮翻阅",rowOffset+1,math.min(rowOffset+visibleRows,#filteredItems),#filteredItems) or "")
            end)
            popup.clearAll=UI:CreateFlatButton(popup,296,34,"清除全部",function()
                if activeSelect and activeSelect._axisMultiple then
                    for key in pairs(activeSelect._selections) do activeSelect._selections[key]=nil end
                    activeSelect:RefreshSelectionDisplay(); PaintRows()
                end
            end)
            local clearLabel=popup.clearAll:GetFontString()
            clearLabel:ClearAllPoints(); clearLabel:SetPoint("LEFT",12,0); clearLabel:SetPoint("RIGHT",-12,0); clearLabel:SetJustifyH("LEFT")
            local clearHovered=false
            local function PaintClearAction()
                SuppressSquare(popup.clearAll)
                local fill=clearHovered and menuHover or menuFill
                Skin(popup.clearAll,6,fill,fill)
                clearLabel:SetTextColor(.88,.89,.92,1)
            end
            popup.clearAll:HookScript("OnEnter",function() clearHovered=true; PaintClearAction() end)
            popup.clearAll:HookScript("OnLeave",function() clearHovered=false; PaintClearAction() end)
            popup.clearAll:HookScript("OnShow",PaintClearAction)
            PaintClearAction()
            local rule=popup:CreateTexture(nil,"BORDER")
            rule:SetColorTexture(unpack(menuEdge)); rule:SetPoint("TOPLEFT",12,-49); rule:SetPoint("TOPRIGHT",-12,-49); rule:SetHeight(PhysicalPixel(popup))
            popup.actionRule=popup:CreateTexture(nil,"BORDER")
            popup.actionRule:SetColorTexture(unpack(menuEdge)); popup.actionRule:SetHeight(PhysicalPixel(popup)); popup.actionRule:Hide()
            popup.listEndRule=popup:CreateTexture(nil,"BORDER")
            popup.listEndRule:SetColorTexture(unpack(menuEdge)); popup.listEndRule:SetHeight(PhysicalPixel(popup)); popup.listEndRule:Hide()
        end
        -- Match physical trigger width even for the separate Core popup hosts.
        local triggerWidth=owner:GetWidth()*owner:GetEffectiveScale()/popup:GetEffectiveScale()
        local menuWidth=math.max(owner._axisMinWidth or 220,triggerWidth)
        popup:SetWidth(menuWidth)
        popup.search:SetWidth(menuWidth-24)
        popup.empty:SetWidth(menuWidth-48)
        popup.range:SetWidth(menuWidth-32)
        popup.clearAll:SetWidth(menuWidth-16)
        activeSelect=owner; highlighted=1
        for i,item in ipairs(owner._axisItems) do if item[2]==owner._currentValue then highlighted=i end end
        filteredItems=owner._axisItems
        popup:SetHeight(56+math.min(visibleRows,#owner._axisItems)*rowPitch+8)
        popup:ClearAllPoints()
        -- Flip above the trigger if there is insufficient room underneath.
        local available=(owner:GetBottom() or 0)*owner:GetEffectiveScale()
        if available<(popup:GetHeight()+8)*catcher:GetEffectiveScale() then
            popup:SetPoint("BOTTOMLEFT",owner,"TOPLEFT",0,6)
        else popup:SetPoint("TOPLEFT",owner,"BOTTOMLEFT",0,-6) end
        for i=1,visibleRows do
            if not rows[i] then
                local index=i
                local row=UI:CreateFlatButton(popup,popup:GetWidth()-16,rowPitch-2,"",function() Choose(rowOffset+index) end)
                row:SetPoint("TOPLEFT",8,-56-(i-1)*rowPitch)
                local label=row:GetFontString(); local font=label:GetFont()
                row._axisFont=font
                row._axisPreview=row:CreateTexture(nil,"ARTWORK")
                row._axisPreview:SetSize(38,16); row._axisPreview:SetPoint("LEFT",38,0); row._axisPreview:Hide()
                label:SetFont(font,14,""); label:SetTextColor(.91,.91,.93,1); label:SetShadowOffset(0,0)
                label:ClearAllPoints(); label:SetPoint("LEFT",38,0); label:SetPoint("RIGHT",-14,0); label:SetJustifyH("LEFT")
                local choiceFill=Glyph(row,"CheckFill",CHECK_SIZE,"ARTWORK"); choiceFill:SetPoint("LEFT",9,0); choiceFill:Hide()
                local choiceBorder=Glyph(row,"CheckBorder",CHECK_SIZE,"ARTWORK"); choiceBorder:SetPoint("LEFT",9,0); choiceBorder:Hide()
                local check=Glyph(row,"GlyphCheck",CHECK_MARK_SIZE); check:SetPoint("LEFT",10,0)
                check:SetVertexColor(.88,.9,.94,1); row._axisCheck={check}
                row._axisChoiceFill=choiceFill; row._axisChoiceBorder=choiceBorder
                local play=UI:CreateFlatButton(row,28,24,"",nil)
                play:SetPoint("RIGHT",-5,0); SuppressSquare(play); play:Hide()
                local playGlyph=Glyph(play,"GlyphChevron",16); playGlyph:SetPoint("CENTER"); playGlyph:SetRotation(-math.pi/2)
                playGlyph:SetVertexColor(.68,.72,.80,1)
                play:SetScript("OnClick",function(self)
                    local entry=self._entry
                    if entry and entry.path then
                        PlaySoundFile(entry.path,"Master")
                        Say("试听："..tostring(entry[1]))
                    end
                end)
                play:HookScript("OnEnter",function() playGlyph:SetVertexColor(.92,.94,1,1); GameTooltip:SetOwner(play,"ANCHOR_RIGHT"); GameTooltip:SetText("试听"); GameTooltip:Show() end)
                play:HookScript("OnLeave",function() playGlyph:SetVertexColor(.68,.72,.80,1); if GameTooltip:IsOwned(play) then GameTooltip:Hide() end end)
                play:HookScript("OnHide",function() if GameTooltip:IsOwned(play) then GameTooltip:Hide() end end)
                row._axisPlay=play
                row:HookScript("OnEnter",function()
                    local entry=filteredItems[rowOffset+index]
                    if entry and not entry.disabled then highlighted=rowOffset+index end
                    PaintRows()
                end)
                row:HookScript("OnMouseDown",function() SuppressSquare(row); Skin(row,8,{.255,.255,.27,1},{.255,.255,.27,1}) end)
                row:HookScript("OnMouseUp",PaintRows)
                rows[i]=row
            end
        end
        owner._axisOpen=true; owner._axisPaint()
        catcher:Show(); popup:Show()
        popup.search:SetText(""); RefreshSearch(); popup.search:SetFocus()
    end
    local function SelectControl(parent,width,caption,items,value,onSelect)
        local owner=UI:CreateFlatButton(parent,width,32,"",nil)
        owner._axisItems=items; owner._axisCaption=caption; owner._currentValue=value; owner._onSelect=onSelect
        local label=owner:GetFontString(); local font=label:GetFont()
        label:SetFont(font,13,""); label:SetShadowOffset(0,0); label:SetTextColor(.90,.90,.92,1)
        label:ClearAllPoints(); label:SetPoint("LEFT",12,0); label:SetPoint("RIGHT",-32,0); label:SetJustifyH("LEFT")
        owner.OverrideText=function(self,text) self:SetText(text) end
        for _,item in ipairs(items) do if item[2]==value then owner:OverrideText(item[1]) end end
        local chevron=Glyph(owner,"GlyphChevron",16); chevron:SetPoint("RIGHT",-8,0)
        local hovered=false
        owner._axisPaint=function()
            SuppressSquare(owner)
            local enabled=owner:IsEnabled()
            local active=enabled and (hovered or owner._axisOpen)
            Skin(owner,8,enabled and {.12,.12,.13,1} or {.075,.075,.082,1},active and {.36,.36,.39,1} or menuEdge)
            chevron:SetTexCoord(0,1,owner._axisOpen and 1 or 0,owner._axisOpen and 0 or 1)
            chevron:SetVertexColor(unpack(not enabled and {.34,.36,.40,1} or active and {.88,.9,.94,1} or {.65,.68,.74,1}))
            label:SetTextColor(unpack(enabled and {.90,.90,.92,1} or {.43,.45,.50,1}))
        end
        owner:SetScript("OnClick",function() OpenSelect(owner) end)
        owner:HookScript("OnEnter",function() hovered=true; owner._axisPaint() end)
        owner:HookScript("OnLeave",function() hovered=false; owner._axisPaint() end)
        owner:HookScript("OnEnable",owner._axisPaint)
        owner:HookScript("OnDisable",function() if activeSelect==owner then CloseSelect() end; owner._axisPaint() end)
        owner:HookScript("OnShow",owner._axisPaint)
        owner:HookScript("OnHide",function() if activeSelect==owner then CloseSelect() end end)
        owner._axisPaint()
        return owner
    end
    -- Replace only these retained GUI instances. Original dropdowns remain as
    -- hidden state/callback owners so Core refresh and LSM contracts still work.
    local function AlignmentControl(original,axis)
        local holder=CreateFrame("Frame",nil,original:GetParent())
        holder:SetAllPoints(original)
        original._qinglanReplacement=holder
        Skin(holder,4,C.panel,{.48,.48,.52,1})
        local buttons={}
        local values=axis=="justifyH" and {"LEFT","CENTER","RIGHT"} or {"TOP","MIDDLE","BOTTOM"}
        local labels=axis=="justifyH" and {"左对齐","居中对齐","右对齐"} or {"顶部对齐","垂直居中","底部对齐"}
        local glyphs=axis=="justifyH" and {"Left","Center","Right"} or {"Top","Middle","Bottom"}
        local function Sync()
            for _,button in ipairs(buttons) do
                button:SetEnabled(not original.IsEnabled or original:IsEnabled())
                button:Paint()
            end
        end
        for index,value in ipairs(values) do
            local b=UI:CreateFlatButton(holder,40,24,"",function()
                CloseSelect()
                original._currentValue=value
                if original._onSelect then original._onSelect(value,labels[index]) end
                original:OverrideText(labels[index])
                Sync()
            end)
            buttons[index]=b
            local hovered,pressed=false,false
            local icon=Glyph(b,"GlyphAlign"..glyphs[index],22,"OVERLAY")
            icon:SetPoint("CENTER")
            function b:Paint()
                SuppressSquare(self)
                local selected=original._currentValue==value
                local fill=pressed and C.pressed or hovered and C.hover or selected and C.button or C.panel
                -- One shared outline, with a filled active segment like Tabs.
                Skin(self,3,fill,fill)
                local shade=self:IsEnabled() and (selected or hovered) and .96 or self:IsEnabled() and .68 or .35
                icon:SetVertexColor(shade,shade,shade,1)
            end
            b:HookScript("OnEnter",function()
                hovered=true; b:Paint()
                GameTooltip:SetOwner(b,"ANCHOR_RIGHT"); GameTooltip:SetText(labels[index]); GameTooltip:Show()
            end)
            b:HookScript("OnLeave",function() hovered=false; pressed=false; b:Paint(); GameTooltip:Hide() end)
            b:HookScript("OnMouseDown",function(_,key) if key=="LeftButton" then pressed=true; b:Paint() end end)
            b:HookScript("OnMouseUp",function() pressed=false; b:Paint() end)
            b:HookScript("OnHide",function() hovered=false; pressed=false; if GameTooltip:IsOwned(b) then GameTooltip:Hide() end end)
        end
        local function Layout()
            local width=(holder:GetWidth()-4)/3
            for index,b in ipairs(buttons) do
                b:ClearAllPoints(); b:SetPoint("TOPLEFT",holder,"TOPLEFT",2+(index-1)*width,-2)
                b:SetSize(width,math.max(20,holder:GetHeight()-4))
            end
        end
        holder:SetScript("OnSizeChanged",Layout)
        local override=original.OverrideText
        original.OverrideText=function(self,text) override(self,text); Sync() end
        if original.SetEnabled then hooksecurefunc(original,"SetEnabled",Sync) end
        if original.labelText then
            original.labelText:SetParent(holder); original.labelText:ClearAllPoints()
            original.labelText:SetPoint("BOTTOMLEFT",holder,"TOPLEFT",0,4)
            original.labelText:SetTextColor(.88,.88,.91,1); original.labelText:Show()
        end
        original:Hide(); holder:HookScript("OnShow",function() Layout(); Sync() end)
        Layout(); Sync()
        return holder
    end
    Settings.ReplaceDropdown=function(original,path)
        if original._qinglanReplacement then return original._qinglanReplacement end
        if path=="justifyH" or path=="justifyV" then return AlignmentControl(original,path) end
        local LSM=LibStub("LibSharedMedia-3.0",true)
        local owner=SelectControl(original:GetParent(),original:GetWidth(),"请选择…",{},nil,nil)
        original._qinglanReplacement=owner
        owner._axisVisibleRows=original._mediaType and 12 or 8
        owner._axisRowPitch=original._mediaType and 26 or 38
        owner:SetAllPoints(original)
        local function Sync()
            owner._currentValue=original._mediaType and original._selectedValue or original._currentValue
            local text=owner._currentValue~=nil and tostring(owner._currentValue) or "请选择…"
            for _,entry in ipairs(owner._axisItems) do if entry[2]==owner._currentValue then text=entry[1]; break end end
            owner:OverrideText(text)
            if original.IsEnabled then owner:SetEnabled(original:IsEnabled()) end
        end
        function owner:_axisRefreshItems()
            local items={}
            if original._mediaType then
                local media=original._mediaType
                local paths=LSM:HashTable(media)
                for _,key in ipairs(LSM:List(media)) do
                    items[#items+1]={key,key,mediaType=media,path=paths[key],searchText=key}
                end
            else
                local function Append(list,prefix)
                    for _,entry in ipairs(list or {}) do
                        if type(entry)=="table" and entry.isMenu then
                            Append(entry.menu,prefix..tostring(entry[1] or entry.text or "").." ")
                        elseif type(entry)=="table" then
                            items[#items+1]={entry[1],entry[2],searchText=prefix..tostring(entry[1]),disabled=entry.disabled==true}
                        else items[#items+1]={entry,entry,searchText=prefix..tostring(entry)} end
                    end
                end
                Append(original._items,"")
            end
            self._axisItems=items; Sync()
        end
        owner._onSelect=function(value,text)
            if original._mediaType then
                original._selectedValue=value
                if original._onSelect then original._onSelect(value,LSM:Fetch(original._mediaType,value,true)) end
            else
                original._currentValue=value
                if original._onSelect then original._onSelect(value,text) end
            end
            original:OverrideText(text); Sync()
        end
        local override=original.OverrideText
        original.OverrideText=function(self,text)
            override(self,text); Sync()
        end
        if original.labelText then
            original.labelText:SetParent(owner)
            original.labelText:ClearAllPoints(); original.labelText:SetPoint("BOTTOMLEFT",owner,"TOPLEFT",0,4)
            original.labelText:SetTextColor(.88,.88,.91,1); original.labelText:Show()
        end
        original:Hide()
        owner:HookScript("OnShow",Sync)
        owner:_axisRefreshItems()
        return owner
    end
    local function MultiSelectControl(parent,width,items,selections,onUpdate)
        local owner=SelectControl(parent,width,"多选",items,nil,nil)
        owner._axisMultiple=true; owner._selections=selections; owner._onUpdate=onUpdate
        -- Keep the existing CreateMultiSelectDropdown contract: one referenced
        -- selection table, toggle in place, then notify with that same table.
        function owner:RefreshSelectionDisplay()
            local labels={}
            for _,entry in ipairs(self._axisItems) do
                if self._selections[entry[2]] then labels[#labels+1]=entry[1] end
            end
            self:OverrideText(#labels==0 and "请选择…" or ("已选 "..#labels.." 项  ·  "..table.concat(labels,"、")))
            if self._onUpdate then self._onUpdate(self._selections) end
        end
        owner:RefreshSelectionDisplay()
        return owner
    end
    root:HookScript("OnHide",CloseSelect)

    -- Public GUI creation/wrapper inventory. ExwindGUI.lua entries follow the
    -- effective source-definition order. Independent GUI entry points are then
    -- appended in their ExwindCore.toc load order. A false `available` flag is
    -- intentionally rendered in place as an empty Qinglan slot.
    local catalog={
        {"CreateDropdown","Core/GUI/ExwindGUI.lua:703",true,"dropdown"},
        {"CreateLSMDropdown","Core/GUI/ExwindGUI.lua:812",true,"lsm_font"},
        {"CreateLSMTextureDropdown","Core/GUI/ExwindGUI.lua:884",true,"lsm_texture"},
        {"CreateLSMSoundDropdown","Core/GUI/ExwindGUI.lua:977",true,"lsm_sound"},
        {"CreateMultiSelectDropdown","Core/GUI/ExwindGUI.lua:1088",true,"multiselect"},
        {"CreateButton","Core/GUI/ExwindGUI.lua:1196",true,"button"},
        {"CreatePicButton","Core/GUI/ExwindGUI.lua:1251",false},
        {"CreateCheckbox","Core/GUI/ExwindGUI.lua:1308",true,"checkbox"},
        {"CreateSlider","Core/GUI/ExwindGUI.lua:1374",true,"slider"},
        {"CreateSeparator","Core/GUI/ExwindGUI.lua:1722",false},
        {"CreateHeader","Core/GUI/ExwindGUI.lua:1741",true,"header"},
        {"CreateSettingsCard","Core/GUI/ExwindGUI.lua:1784",false},
        {"CreateColorButton","Core/GUI/ExwindGUI.lua:2026",true,"color"},
        {"CreateFontGroup","Core/GUI/ExwindGUI.lua:2598",true,"fontgroup",330},
        {"CreateSoundGroup","Core/GUI/ExwindGUI.lua:3293",false},
        {"CreateVoiceGroup","Core/GUI/ExwindGUI.lua:3643",false},
        {"CreateEditBox","Core/GUI/ExwindGUI.lua:3891",true,"edit"},
        {"CreatePreviewCanvas","Core/GUI/ExwindGUI.lua:4097",false},
        {"CreateSegmentedControl","Core/GUI/ExwindGUI.lua:4238",false},
        {"CreateItemConfig","Core/GUI/ExwindGUI.lua:4317",false},
        {"CreateIconGroup","Core/GUI/ExwindGUI.lua:4622",true,"icongroup",270},
        {"CreateTimerBarGroup","Core/GUI/ExwindGUI.lua:5346",true,"timerbargroup",330},
        {"CreateGlowSettings","Core/GUI/ExwindGUI.lua:5843 (replaces :4491)",false},
        {"CreateWidgetLayoutGroup","Core/GUI/ExwindGUI.lua:6005",false},
        {"CreateModuleCommonSettingsGroup","Core/GUI/ExwindGUI.lua:6410",false},
        {"CreateAuraDurationBarGroup","Core/GUI/ExwindGUI.lua:6719",false},
        {"CreateAuraApplicationBarGroup","Core/GUI/ExwindGUI.lua:6750",false},
        {"CreateAnchorGroup","Core/GUI/ExwindGUI.lua:6781",false},
        {"CreateTextureGroup","Core/GUI/ExwindGUI.lua:6878",false},
        {"CreateAuraDispelBorderGroup","Core/GUI/ExwindGUI.lua:7043",false},
        {"CreateAuraSortGroup","Core/GUI/ExwindGUI.lua:7055",false},
        {"CreateAuraChildElementsGroup","Core/GUI/ExwindGUI.lua:7074",false},
        {"CreateStandardModulePage","Core/GUI/ExwindGUI.lua:7290",false},
        {"VirtualList:Create","Core/GUI/ExwindVirtualList.lua:28",false},
        {"CreateTabGroup","Core/GUI/ExwindChoiceGroup.lua:373",false},
        {"CreateOptionGroup","Core/GUI/ExwindChoiceGroup.lua:374",false},
        {"Grid:Render","Core/GUI/ExwindGrid.lua:782",false},
        {"ExwindTools:StartFramePicker","Core/GUI/ExwindFramePicker.lua:62",false},
    }
    -- Function symbols are the stable source anchors. The shared formal GUI is
    -- edited independently, so volatile physical line numbers are not shown in
    -- the in-game catalog.
    for index=1,33 do
        catalog[index][2]="Core/GUI/ExwindGUI.lua  ·  EXUI:"..catalog[index][1]
    end
    catalog[34][2]="Core/GUI/ExwindVirtualList.lua  ·  VirtualList:Create"
    catalog[35][2]="Core/GUI/ExwindChoiceGroup.lua  ·  UI:CreateTabGroup"
    catalog[36][2]="Core/GUI/ExwindChoiceGroup.lua  ·  UI:CreateOptionGroup"
    catalog[37][2]="Core/GUI/ExwindGrid.lua  ·  Grid:Render"
    catalog[38][2]="Core/GUI/ExwindFramePicker.lua  ·  ExwindTools:StartFramePicker"

    -- Header and permanent sidebar.
    Box(root,1,1,1258,47,0,C.panel)
    local logo=Box(root,16,12,24,24,4,{.95,.95,.96,1}); local mark=Label(logo,"A",6,4,16); mark:SetTextColor(.04,.04,.05,1)
    RegisterTitle(Label(root,"AXIS UI  /  DESIGN SYSTEM",50,18,285))
    local search=Field(root,"",340,10,310,28)
    search.placeholder:SetText("检索组件：按钮 / 输入 / 面板")
    Label(root,"SPEC V3.5  /  QINGLAN V33",830,18,250,true)
    Btn(root,"重置状态",1092,10,112,28,"outline",function() for _,reset in ipairs(resets) do reset() end; Say("预览状态已重置") end)
    Btn(root,"X",1216,10,28,28,"ghost",function() root:Hide() end)
    local drag=CreateFrame("Frame",nil,root); drag:SetPoint("TOPLEFT",0,0); drag:SetSize(330,46)
    drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart",function() root:StartMoving() end); drag:SetScript("OnDragStop",function() root:StopMovingOrSizing() end)
    local side=Box(root,1,48,206,724,0,C.panel)
    RegisterTitle(Label(side,"UI 规范导航",15,18,120,true)); Label(side,"PRO-KIT",139,18,65,true)
    local names={}
    for i,item in ipairs(catalog) do names[i]=item[1] end
    local scroll=CreateFrame("ScrollFrame",nil,root,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",root,"TOPLEFT",218,-60); scroll:SetSize(1012,700)
    local canvas=CreateFrame("Frame",nil,scroll); canvas:SetSize(992,8000); scroll:SetScrollChild(canvas)
    scroll:HookScript("OnVerticalScroll",CloseSelect)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel",function(self,delta) self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScroll()-delta*55,self:GetVerticalScrollRange()))) end)
    local function Jump(i)
        scroll:SetVerticalScroll(math.min(sections[i].offset,scroll:GetVerticalScrollRange()))
        for j,b in ipairs(navs) do b._axisFill=j==i and C.button or C.panel; b._axisEdge=b._axisFill; b._qinglanPaint() end
    end
    local navScroll=CreateFrame("ScrollFrame",nil,side,"UIPanelScrollFrameTemplate")
    navScroll:SetPoint("TOPLEFT",side,"TOPLEFT",4,-43); navScroll:SetSize(180,565)
    local navCanvas=CreateFrame("Frame",nil,navScroll); navCanvas:SetSize(160,#names*25+4); navScroll:SetScrollChild(navCanvas)
    navScroll:EnableMouseWheel(true)
    navScroll:SetScript("OnMouseWheel",function(self,delta)
        self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScroll()-delta*50,self:GetVerticalScrollRange())))
    end)
    for i,name in ipairs(names) do
        local n=i
        navs[i]=Btn(navCanvas,string.format("%02d. %s",i,name),2,2+(i-1)*25,154,23,"ghost",function() Jump(n) end)
        local fs=navs[i]:GetFontString(); fs:ClearAllPoints(); fs:SetPoint("LEFT",6,0); fs:SetPoint("RIGHT",-4,0); fs:SetJustifyH("LEFT")
    end
    search:SetScript("OnEnterPressed",function(self)
        local q=self:GetText(); self:ClearFocus()
        for i,name in ipairs(names) do if q~="" and string.find(name,q,1,true) then Jump(i); return end end
        Say("请输入左侧导航中的组件名称")
    end)
    local density=Box(side,10,621,186,86,4,C.card)
    Label(density,"THEME DENSITY",10,11,170,true); Label(density,"COMPACT / SHADCN",10,32,170)
    Label(density,"黑灰层级 · 细边框 · 小圆角",10,56,170,true)
    Label(canvas,"TAILWIND UI SPEC   /   SHADCN · RADIX DENSE",10,10,950,true)
    RegisterTitle(Text(canvas,"按公共封装源码顺序的青蓝 GUI 逐项 Demo",10,38,620,"GameFontNormalLarge"))
    local titleSizeSlider=UI:CreateFlatSlider(canvas,250,"标题字号",12,24,titleSize,1,nil,{
        onLive=function(value) SetAllTitleSizes(value,true) end,
        onCommit=function(value) SetAllTitleSizes(value,true) end,
    })
    titleSizeSlider:SetPoint("TOPLEFT",canvas,"TOPLEFT",700,-68)
    ApplyFontGroupSlider(titleSizeSlider,"标题字号")
    RegisterControlTitles(titleSizeSlider)
    resets[#resets+1]=function()
        titleSizeSlider:SetEXUIValue(16,"silent")
        SetAllTitleSizes(16,false)
    end
    Label(canvas,"每个公共入口独立编号；已有青蓝实现放真实控件，未有实现在原顺序留空。",10,67,960,true)
    --[=[ Retained historical category layout. The active catalog below is the
    -- source-ordered first-step correction; this block is intentionally inert.
    local function Section(i,y,h,title)
        local f=Box(canvas,8,y,974,h,8,C.card); f.offset=y; sections[i]=f
        if i>=8 then
            local heading=Label(f,title,20,8,934)
            SettingsTitle(heading,18); heading:SetHeight(24)
            f.heading=heading
        else
            local n=Box(f,16,16,24,24,4,i==1 and {.95,.95,.96,1} or C.accent)
            local t=Label(n,string.format("%02d",i),4,5,22); t:SetTextColor(i==1 and .05 or 1,i==1 and .05 or 1,i==1 and .05 or 1,1)
            Label(f,title,52,22,900)
        end
        local line=f:CreateTexture(nil,"BORDER"); line:SetColorTexture(unpack(C.border)); line:SetPoint("TOPLEFT",16,i>=8 and -40 or -52); line:SetSize(942,1)
        f.divider=line
        return f
    end
    local s1=Section(1,105,365,"按钮系统全规范  /  Buttons, Variants & Groups")
    Label(s1,"语义变体矩阵",16,68,650,true); Label(s1,"XS 24 / SM 28 / DEFAULT 32",650,68,305,true)
    local matrix=Box(s1,16,92,942,58,4,C.panel)
    local variants={{"Primary Blue 高亮主按","blue",190},{"Secondary 次级按钮",nil,184},{"Outline 边框按钮","outline",168},{"Destructive 危险操作","danger",190},{"禁用状态",nil,132}}
    local bx=10
    for i,v in ipairs(variants) do local b=Btn(matrix,v[1],bx,13,v[3],32,v[2]); if i==5 then b:Disable() end; bx=bx+v[3]+9 end
    for i,spec in ipairs({{"标准尺寸 Default",32,"保存配置","white"},{"紧凑尺寸 Compact",28,"应用更改","blue"},{"微型尺寸 Micro",24,"快速同步","white"}}) do
        local box=Box(s1,16+(i-1)*318,166,306,91,4,C.panel)
        Label(box,spec[1],12,12,280,true)
        Btn(box,spec[3],12,40,108,spec[2],spec[4]); Btn(box,i==1 and "取消" or "重置",128,40,90,spec[2],"outline"); Btn(box,"+",226,40,spec[2],spec[2],"outline")
    end
    Label(s1,"并排紧凑按钮组",20,281,250,true)
    Tabs(s1,{"左对齐","居中","右对齐"},18,306,410,3,function(v) Say("文本对齐："..v) end)
    Label(s1,"精密微步进器",514,281,290,true)
    -- One visual surface, three real input regions. No individual button or
    -- EditBox border is painted over the enclosing rounded outline.
    local stepper=CreateFrame("Frame",nil,s1)
    stepper:SetScale(0.68); stepper:SetPoint("TOPLEFT",s1,"TOPLEFT",779/0.68,-307/0.68); stepper:SetSize(174,48)
    Skin(stepper,10,{.094,.094,.106,1},{.247,.247,.275,1})
    for _,x in ipairs({51,122}) do
        local divider=stepper:CreateTexture(nil,"BORDER")
        divider:SetColorTexture(.153,.153,.165,1)
        divider:SetPoint("TOPLEFT",x,-2); divider:SetSize(1,44)
    end
    local step=UI:CreateFlatEditBox(stepper,"16",68,38,nil,{})
    step:SetPoint("CENTER"); step:SetJustifyH("CENTER"); step:SetTextInsets(2,2,0,0)
    local stepFont=step:GetFont(); step:SetFont(stepFont,22,"")
    step:SetTextColor(.95,.95,.97,1); step:SetShadowOffset(0,0)
    local function CleanStep()
        SuppressSquare(step)
        step:SetTextColor(.95,.95,.97,1)
    end
    step:HookScript("OnEditFocusGained",CleanStep)
    step:HookScript("OnEditFocusLost",CleanStep)
    step:HookScript("OnShow",CleanStep); CleanStep()
    local committedStep=16
    local function CommitStep()
        local value=tonumber(step:GetText())
        if not value or value~=value or value==math.huge or value==-math.huge then value=committedStep end
        committedStep=math.max(0,math.min(9999,math.floor(value)))
        step:SetText(tostring(committedStep)); CleanStep()
    end
    step:SetScript("OnEnterPressed",function(self) CommitStep(); self:ClearFocus() end)
    step:HookScript("OnEditFocusLost",CommitStep)
    local function Step(delta)
        CommitStep(); committedStep=math.max(0,math.min(9999,committedStep+delta))
        step:SetText(tostring(committedStep))
    end
    local function StepSide(x,plus)
        local b=UI:CreateFlatButton(stepper,50,46,"",function() Step(plus and 2 or -2) end)
        b:SetPoint("TOPLEFT",x,-1)
        local glyph={}
        for i=1,(plus and 2 or 1) do
            local l=b:CreateLine(nil,"OVERLAY"); l:SetThickness(1.6)
            l:SetStartPoint("CENTER",b,i==1 and -7 or 0,i==1 and 0 or -7)
            l:SetEndPoint("CENTER",b,i==1 and 7 or 0,i==1 and 0 or 7)
            glyph[i]=l
        end
        local hovered,pressed=false,false
        local function Paint()
            SuppressSquare(b)
            local offset=pressed and -1/b:GetEffectiveScale() or 0
            for i,l in ipairs(glyph) do
                if pressed then l:SetColorTexture(.376,.647,.98,1)
                elseif hovered then l:SetColorTexture(1,1,1,1)
                else l:SetColorTexture(.63,.63,.68,1) end
                l:SetThickness((hovered or pressed) and 2 or 1.6)
                l:SetStartPoint("CENTER",b,i==1 and -7 or 0,(i==1 and 0 or -7)+offset)
                l:SetEndPoint("CENTER",b,i==1 and 7 or 0,(i==1 and 0 or 7)+offset)
            end
        end
        b:HookScript("OnEnter",function() hovered=true; Paint() end)
        b:HookScript("OnLeave",function() hovered=false; pressed=false; Paint() end)
        b:HookScript("OnMouseDown",function(_,button) if button=="LeftButton" then pressed=true; Paint() end end)
        b:HookScript("OnMouseUp",function() pressed=false; hovered=b:IsMouseOver(); Paint() end)
        b:HookScript("OnShow",function() hovered=false; pressed=false; Paint() end)
        b:HookScript("OnHide",function() hovered=false; pressed=false; Paint() end)
        Paint()
    end
    StepSide(1,false); StepSide(123,true)
    resets[#resets+1]=function() committedStep=16; step:SetText("16"); step:ClearFocus() end
    local s2=Section(3,708,172,"勾选框规范  /  Checkboxes")
    Label(s2,"INTERACTIVE",20,70,400,true); Check(s2,"自动吸附网格节点",20,96,true,false,function(v) Say("自动吸附："..tostring(v)) end)
    Label(s2,"DISABLED STATES",510,70,400,true); Check(s2,"已禁用勾选（只读）",510,93,true,true); Check(s2,"已禁用未选策略",510,123,false,true)
    local s3=Section(4,898,267,"输入框与精密属性体系  /  Inputs & Numeric Precision")
    Label(s3,"图层名称 (Text Input)",18,70,650,true)
    Field(s3,"HeroBanner_Desktop_V2",18,95,426,32,function(v) Say("图层名称："..v) end)
    Label(s3,"Tailwind JSON 样式定义规则",18,143,900,true)
    local code=Box(s3,18,168,938,80,4,C.panel)
    Label(code,'{\n  "component": "tailwind-shadcn-button",\n  "styles": { "primary": "bg-zinc-100 text-zinc-900 h-8 rounded-md" },\n  "checkbox": { "size": "w-4 h-4", "border": "border-zinc-700" }\n}',12,8,910)
    local s4=Section(5,1183,394,"下拉、颜色与选择控件  /  Dropdown, Color & Selection")
    local menu=Box(s4,18,70,296,298,10,{.098,.098,.11,1})
    Label(menu,"exw081697@gmail.com",14,14,270,true)
    local menuItems={"Settings","Language","Get help","Upgrade plan","Get apps and extensions","Claude Academy     New","Log out"}
    for i,label in ipairs(menuItems) do Btn(menu,label,9,42+(i-1)*34,278,30,"ghost",function() Say("菜单预览："..label) end) end
    Label(s4,"选择模式 / Select",346,73,570,true)
    local mode=SelectControl(s4,592,"选择模式",{{"Normal（正常模式）","Normal"},{"Compact（紧凑模式）","Compact"},{"Advanced（高级模式）","Advanced"}},"Normal",function(v) Say("当前模式："..v) end)
    mode:SetPoint("TOPLEFT",346,-101)
    ResetDropdown(mode,"Normal","Normal（正常模式）")
    Label(s4,"多选下拉 / 规则选项",346,151,560,true)
    local selections={components=true,theme=true}
    local multi=MultiSelectControl(s4,592,{{"组件系统","components"},{"深色规范","theme"},
        {"自动布局","layout"},{"网格吸附","snap"},{"显示标签","labels"}},selections,function()
        Say("多选已更新；可以继续勾选，点击完成或外部收起")
    end)
    multi:SetPoint("TOPLEFT",346,-177)
    resets[#resets+1]=function()
        for key in pairs(selections) do selections[key]=nil end
        selections.components=true; selections.theme=true; multi:RefreshSelectionDisplay()
    end
    Label(s4,"颜色 / 点击色块或标题打开取色器",346,229,570,true)
    local function ColorSample(x,title,initial)
        local color={r=initial[1],g=initial[2],b=initial[3],a=initial[4]}
        local button=UI:CreateFlatColorButton(s4,title,color,"",true,function() Say(title.."已实时更新（含透明度）") end)
        button:SetPoint("TOPLEFT",x,-253); button:SetSize(286,34)
        button.swatch:ClearAllPoints(); button.swatch:SetPoint("LEFT",10,0); button.swatch:SetSize(18,18)
        local font=button.labelText:GetFont(); button.labelText:SetFont(font,12,"")
        button.labelText:SetTextColor(.9,.9,.92,1); button.labelText:SetShadowOffset(0,0)
        local hovered=false
        local function Paint()
            SuppressSquare(button)
            Skin(button,4,hovered and {.16,.16,.18,1} or {.12,.12,.13,1},hovered and {.36,.36,.39,1} or menuEdge)
            button.labelText:SetText(title)
        end
        -- Native UpdateColor still updates the swatch and native picker/Cancel
        -- flow; then restore our neutral button surface and title.
        local originalUpdate=button.UpdateColor
        button.UpdateColor=function(self,...) originalUpdate(self,...); Paint() end
        button:HookScript("OnEnter",function() hovered=true; Paint() end)
        button:HookScript("OnLeave",function() hovered=false; Paint() end)
        button:HookScript("OnShow",Paint)
        -- Checkerboard beneath the color swatch makes alpha visible.
        for cy=0,2 do for cx=0,2 do
            local tile=button:CreateTexture(nil,"BACKGROUND",nil,1)
            local shade=(cx+cy)%2==0 and .25 or .50
            tile:SetColorTexture(shade,shade,shade,1); tile:SetSize(6,6)
            tile:SetPoint("TOPLEFT",button.swatch,"TOPLEFT",cx*6,-cy*6)
        end end
        button:UpdateColor()
        resets[#resets+1]=function()
            color.r,color.g,color.b,color.a=initial[1],initial[2],initial[3],initial[4]; button:UpdateColor()
        end
        return button
    end
    ColorSample(346,"主色",{.145,.388,.922,1})
    ColorSample(652,"背景",{.4,.45,.52,.5})
    local switch=Btn(s4,"自动同步：开启",346,304,180,28,"blue")
    local on=true
    local function SyncSwitch() switch:SetText(on and "自动同步：开启" or "自动同步：关闭"); switch._axisFill=on and {.145,.388,.922,1} or C.button; switch._qinglanPaint() end
    switch:SetScript("OnClick",function() on=not on; SyncSwitch() end)
    resets[#resets+1]=function() on=true; SyncSwitch() end
    local s5=Section(2,488,202,"Slider 滑动条及现有变体  /  Slider & Segments")
    local active=Label(s5,"ACTIVE: 设计",18,71,270,true)
    Tabs(s5,{"设计","原型","检视"},18,100,284,1,function(v) active:SetText("ACTIVE: "..v) end)
    local range=Slider(s5,"文本大小",250,338,118,10,40,14,function(v) Say("文本大小预览："..v) end,true)
    resets[#resets+1]=function() range:SetEXUIValue(14,"commit") end
    Label(s5,"状态徽章与数值角标",656,70,290,true)
    for i,v in ipairs({{"运行正常",{.1,.7,.45,1}},{"待确认",C.accent},{"异常阻断",{.94,.3,.3,1}}}) do
        local badge=Box(s5,656,96+(i-1)*28,126,23,0,C.panel); local t=Label(badge,v[1],9,5,114); t:SetTextColor(unpack(v[2]))
    end
    local s6=Section(6,1595,350,"折叠面板与手风琴体系  /  Collapsible & Accordion")
    local a=Box(s6,18,71,300,255,4,C.panel)
    Label(a,"属性检视器手风琴",12,12,274,true)
    local headers,bodies={},{}
    local labels={"图层排版与对齐","文字排版体系","描边与投影"}
    local descriptions={"主轴：space-between\n交叉轴：center\n自动换行：Enabled","字号：13px / 行高：18px\n字重：500","边框：zinc-800\n投影：Shadow-sm"}
    local expanded=1
    local function LayoutAccordion()
        local y=38
        for i,b in ipairs(headers) do b:ClearAllPoints(); b:SetPoint("TOPLEFT",8,-y); b:SetText((expanded==i and "-  " or "+  ")..labels[i]); y=y+32; bodies[i]:ClearAllPoints(); bodies[i]:SetPoint("TOPLEFT",a,"TOPLEFT",18,-y); bodies[i]:SetShown(expanded==i); if expanded==i then y=y+65 end end
    end
    for i,label in ipairs(labels) do local n=i; headers[i]=Btn(a,label,8,38,284,28,"outline",function() expanded=expanded==n and 0 or n; LayoutAccordion() end); bodies[i]=Label(a,descriptions[i],18,0,265,true) end
    LayoutAccordion(); resets[#resets+1]=function() expanded=1; LayoutAccordion() end
    local card=Box(s6,336,71,300,255,4,C.panel)
    Label(card,"卡片式折叠容器",12,12,270,true)
    Label(card,"高级渲染引擎参数",12,45,270)
    local details=Label(card,"WebGPU · 60 FPS 模式\n\n几何抗锯齿：4x Samples\n高刷缓存：主动就绪\n\npipeline_sync    READY",12,105,274,true)
    local open=true
    local fold=Btn(card,"收起",12,70,76,24,"outline")
    fold:SetScript("OnClick",function() open=not open; details:SetShown(open); fold:SetText(open and "收起" or "展开") end)
    resets[#resets+1]=function() open=true; details:Show(); fold:SetText("收起") end
    local tree=Box(s6,654,71,302,255,4,C.panel)
    Label(tree,"树状层级折叠",12,12,274,true)
    local nodes=Label(tree,"  Solid Primary\n\n  Outline Neutral\n\n  Destructive Red",22,79,265,true)
    local treeOpen=true
    local branch=Btn(tree,"-  按钮变体 (Variants)",10,43,280,28,"ghost",function() treeOpen=not treeOpen; nodes:SetShown(treeOpen) end)
    local formNodes=Label(tree,"Checkbox Groups / Numeric Stepper",18,223,272,true); formNodes:Hide()
    Btn(tree,"+  表单状态",10,186,280,28,"ghost",function() formNodes:SetShown(not formNodes:IsShown()) end)
    resets[#resets+1]=function() treeOpen=true; nodes:Show(); formNodes:Hide() end
    local s7=Section(7,1963,408,"实战面板规范：血量条外观设置面板  /  Healthbar Ribbon Inspector")
    local ribbon=Box(s7,16,70,942,316,8,{.098,.098,.11,1})
    Label(ribbon,"血量条外观   HUD_HP_BAR  /  紧凑属性工具条",14,16,560)
    local hp=CreateFrame("Frame",nil,ribbon); hp:SetPoint("TOPLEFT",640,-17); hp:SetSize(220,15); Skin(hp,0,{0,0,0,1},C.border)
    local hpFill=hp:CreateTexture(nil,"ARTWORK"); hpFill:SetColorTexture(0,.898,1,1); hpFill:SetPoint("TOPLEFT",1,-1)
    local hpText=Label(hp,"1584/2200",4,1,200); hpText:SetJustifyH("RIGHT")
    local hpIcon=Box(hp,-22,0,18,18,0,C.accent)
    Label(hpIcon,"+",5,2,15)
    local w,h,ox,oy=220,15,0,0
    local function RefreshHP()
        hp:SetSize(w,h); hp:ClearAllPoints(); hp:SetPoint("TOPLEFT",ribbon,"TOPLEFT",640+ox,-17+oy)
        hpFill:SetSize(math.max(1,(w-2)*.72),math.max(1,h-2)); hpText:SetWidth(math.max(1,w-8))
    end
    RefreshHP()
    local inspectorBody=CreateFrame("Frame",nil,ribbon); inspectorBody:SetPoint("TOPLEFT",0,-58); inspectorBody:SetSize(942,235)
    local dims={{"宽度 (Width)",50,300,220,function(v) w=v; RefreshHP() end},{"高度 (Height)",4,40,15,function(v) h=v; RefreshHP() end},{"X 偏移 (Offset X)",-50,50,0,function(v) ox=v; RefreshHP() end},{"Y 偏移 (Offset Y)",-10,10,0,function(v) oy=v; RefreshHP() end}}
    for i,d in ipairs(dims) do
        local cell=Box(inspectorBody,12+(i-1)*231,0,219,94,4,C.panel)
        local sl=Slider(cell,d[1],195,12,48,d[2],d[3],d[4],d[5])
        local control,initial=sl,d[4]; resets[#resets+1]=function() control:SetEXUIValue(initial,"commit") end
    end
    Label(inspectorBody,"皮肤：",14,115,65,true)
    local texture=SelectControl(inspectorBody,186,"选择材质",{{"EX_WhiteTexture","EX_WhiteTexture"},{"Soft Grey","Soft Grey"}},"EX_WhiteTexture",function(v) hpFill:SetColorTexture(v=="Soft Grey" and .6 or 0,v=="Soft Grey" and .6 or .898,v=="Soft Grey" and .65 or 1,1) end)
    texture:SetPoint("TOPLEFT",66,-106)
    ResetDropdown(texture,"EX_WhiteTexture","EX_WhiteTexture")
    local swatch=Box(inspectorBody,274,106,107,28,4,C.panel); local st=Label(swatch,"#00E5FF",10,8,96); st:SetTextColor(0,.898,1,1)
    Check(inspectorBody,"图标",14,166,true,false,function(v) hpIcon:SetShown(v) end)
    Check(inspectorBody,"边框",262,166,true,false,function(v) Skin(hp,0,{0,0,0,1},v and C.border or {0,0,0,0}) end)
    Btn(inspectorBody,"图标设置",100,165,90,24,"outline",function() hpIcon:SetAlpha(hpIcon:GetAlpha()==1 and .45 or 1); Say("图标预览：切换透明度") end)
    Btn(inspectorBody,"填充设置",510,165,110,24,"outline",function() hpFill:SetAlpha(hpFill:GetAlpha()==1 and .5 or 1) end)
    local inspectorOpen=true
    local collapse=Btn(ribbon,"收起",868,13,60,24,"outline")
    collapse:SetScript("OnClick",function() inspectorOpen=not inspectorOpen; inspectorBody:SetShown(inspectorOpen); collapse:SetText(inspectorOpen and "收起" or "展开") end)
    resets[#resets+1]=function() inspectorOpen=true; inspectorBody:Show(); collapse:SetText("收起"); hpFill:SetAlpha(1); hpIcon:SetAlpha(1) end
    -- Real GUI settings, backed only by these temporary preview tables.
    local function CopyValues(source)
        local copy={}
        for key,value in pairs(source) do copy[key]=type(value)=="table" and CopyValues(value) or value end
        return copy
    end
    local function RememberGroup(group,db)
        local initial=CopyValues(db)
        resets[#resets+1]=function()
            for key in pairs(db) do db[key]=nil end
            for key,value in pairs(CopyValues(initial)) do db[key]=value end
            UI:RefreshCompositeGroupFromDB(group)
            for _,entry in ipairs(group._exCompositeControls or {}) do
                if entry.kind=="check" then
                    local box=entry.control.checkbox
                    if box._qinglanCheckPaint then box._qinglanCheckPaint() end
                end
            end
        end
        scroll:HookScript("OnVerticalScroll",function()
            for _,popup in ipairs(group._exCompositePopups or {}) do popup:Hide() end
        end)
    end
    local s8=Section(8,2389,284,"文字设置组  /  GUI Font Group")
    local fontDB={}
    local fontGroup=Settings:CreateFontGroup(s8,964,"文字设置",fontDB,function() Say("文字设置已更新（仅本次预览）") end)
    fontGroup:SetPoint("TOPLEFT",5,-44); RememberGroup(fontGroup,fontDB)
    local s9=Section(9,2691,222,"图标设置组  /  GUI Icon Group")
    local iconDB={width=40,height=40,x=0,y=0,alpha=1}
    local iconGroup=Settings:CreateIconGroup(s9,964,"图标设置",iconDB,nil,function() Say("图标设置已更新（仅本次预览）") end)
    iconGroup:SetPoint("TOPLEFT",5,-44); RememberGroup(iconGroup,iconDB)
    local s10=Section(10,2931,284,"计时条设置组  /  GUI Timer Bar Group")
    local timerDB={}
    local timerGroup=Settings:CreateTimerBarGroup(s10,964,"计时条设置",timerDB,nil,function() Say("计时条设置已更新（仅本次预览）") end)
    timerGroup:SetPoint("TOPLEFT",5,-44); RememberGroup(timerGroup,timerDB)
    local gapSection=Section(11,3233,430,"Core GUI 已有、青岚尚未实现  /  Reserved Slots")
    Label(gapSection,"第一步只登记空位，不创建控件、不补皮肤、不接业务。",20,56,930,true)
    local gaps={
        {"基础控件","图片按钮  CreatePicButton","标题  CreateHeader","物品配置行  CreateItemConfig","预览画板  CreatePreviewCanvas"},
        {"选择与容器","Tab / Option ChoiceGroup","框架选择器  CreateFramePicker","虚拟列表  CreateVirtualList","带标题分隔线 / 独立对话框"},
        {"复合设置组","锚点 / 通用模块 / 控件布局","声音 / 材质 / 语音","发光设置  CreateGlowSettings","Aura 设置包装组  CreateAura*Group"},
    }
    for column,items in ipairs(gaps) do
        local box=Box(gapSection,20+(column-1)*312,88,294,304,4,C.panel)
        Label(box,items[1],14,14,266,true)
        for row=2,#items do
            local slot=Box(box,12,48+(row-2)*58,270,44,4,{.075,.078,.09,1})
            local mark=Label(slot,"＋",12,12,22); mark:SetTextColor(.38,.42,.49,1)
            Label(slot,items[row],42,13,216,true)
        end
    end
    local footer=Label(canvas,"AXIS UI / QINGLAN     ·     实线为已有控件，空位等待后续步骤",14,0,950,true)
    local settingSections={{section=s8,body=fontGroup,height=264},{section=s9,body=iconGroup,height=202},{section=s10,body=timerGroup,height=264}}
    local function ReflowSettings()
        local y=2389
        for _,entry in ipairs(settingSections) do
            local section=entry.section
            section.offset=y
            section:ClearAllPoints(); section:SetPoint("TOPLEFT",canvas,"TOPLEFT",8,-y)
            local height=section.collapsed and 40 or entry.height
            section:SetHeight(height)
            entry.body:SetShown(not section.collapsed)
            section.divider:SetShown(not section.collapsed)
            if section.PaintHeader then section.PaintHeader() end
            y=y+height+14
        end
        gapSection.offset=y
        gapSection:ClearAllPoints(); gapSection:SetPoint("TOPLEFT",canvas,"TOPLEFT",8,-y)
        y=y+gapSection:GetHeight()+14
        footer:ClearAllPoints(); footer:SetPoint("TOPLEFT",canvas,"TOPLEFT",14,-y-10)
        canvas:SetHeight(y+50)
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(),math.max(0,y+50-scroll:GetHeight())))
    end
    for _,entry in ipairs(settingSections) do
        local section=entry.section
        local header=UI:CreateFlatButton(section,974,40,"",nil)
        header:SetPoint("TOPLEFT"); SuppressSquare(header)
        section.heading:SetParent(header)
        section.heading:ClearAllPoints(); section.heading:SetPoint("LEFT",header,"LEFT",20,0)
        local hover,pressed=false,false
        section.PaintHeader=function()
            SuppressSquare(header)
            Skin(section,section.collapsed and 4 or 8,section.collapsed and (pressed and C.pressed or hover and C.button or C.panel) or C.card,
                hover and {.36,.38,.42,1} or C.border)
            section.heading:SetTextColor(unpack(hover and {1,1,1,1} or {.90,.90,.92,1}))
        end
        header:HookScript("OnEnter",function() hover=true; section.PaintHeader() end)
        header:HookScript("OnLeave",function() hover=false; pressed=false; section.PaintHeader() end)
        header:HookScript("OnMouseDown",function() pressed=true; section.PaintHeader() end)
        header:HookScript("OnMouseUp",function() pressed=false; section.PaintHeader() end)
        header:SetScript("OnClick",function()
            CloseSelect(); section.collapsed=not section.collapsed; ReflowSettings()
        end)
    end
    resets[#resets+1]=function()
        for _,entry in ipairs(settingSections) do entry.section.collapsed=false end
        ReflowSettings()
    end
    ReflowSettings()
    Jump(1)
    --]=]

    local function CopyValues(source)
        local copy={}
        for key,value in pairs(source) do copy[key]=type(value)=="table" and CopyValues(value) or value end
        return copy
    end
    local function RememberGroup(group,db)
        local initial=CopyValues(db)
        resets[#resets+1]=function()
            for key in pairs(db) do db[key]=nil end
            for key,value in pairs(CopyValues(initial)) do db[key]=value end
            UI:RefreshCompositeGroupFromDB(group)
            for _,entry in ipairs(group._exCompositeControls or {}) do
                if entry.kind=="check" and entry.control.checkbox and entry.control.checkbox._qinglanCheckPaint then
                    entry.control.checkbox._qinglanCheckPaint()
                end
            end
        end
        scroll:HookScript("OnVerticalScroll",function()
            for _,popupHost in ipairs(group._exCompositePopups or {}) do popupHost:Hide() end
        end)
    end
    local function PositionControl(control,x,y)
        control:ClearAllPoints(); control:SetPoint("TOPLEFT",x,-y)
        return control
    end
    local function EmptySlot(card)
        local empty=Box(card,18,68,938,44,4,{.047,.049,.057,1})
        local plus=Label(empty,"＋",14,12,24,true); plus:SetTextColor(.36,.42,.52,1)
        Label(empty,"尚未实现青蓝对应封装（本步骤原位留空）",48,13,850,true)
    end
    local function RenderAvailable(card,item)
        local kind=item[4]
        if kind=="dropdown" then
            local items={{"标准模式","normal"},{"紧凑模式","compact"},{"高级模式","advanced"},{"不可用选项","disabled",disabled=true}}
            local original=UI:CreateFlatDropdown(card,400,"普通下拉",items,"normal",function(value) Say("CreateDropdown: "..value) end)
            PositionControl(original,18,82)
            local control=Settings.ReplaceDropdown(original)
            RegisterControlTitles(original); RegisterControlTitles(control)
            ResetDropdown(original,"normal","标准模式")
            local disabledOriginal=UI:CreateFlatDropdown(card,260,"禁用触发框",items,"compact",nil)
            PositionControl(disabledOriginal,460,82)
            local disabledControl=Settings.ReplaceDropdown(disabledOriginal)
            RegisterControlTitles(disabledOriginal); RegisterControlTitles(disabledControl)
            disabledControl:Disable()
        elseif kind=="lsm_font" then
            local original=UI:CreateFlatLSMDropdown(card,"font",420,"字体媒体",nil,function(value) Say("CreateLSMDropdown: "..tostring(value)) end)
            PositionControl(original,18,82); local control=Settings.ReplaceDropdown(original)
            RegisterControlTitles(original); RegisterControlTitles(control)
        elseif kind=="lsm_texture" then
            local original=UI:CreateFlatLSMTextureDropdown(card,"statusbar",420,"材质媒体",nil,function(value) Say("CreateLSMTextureDropdown: "..tostring(value)) end)
            PositionControl(original,18,82); local control=Settings.ReplaceDropdown(original)
            RegisterControlTitles(original); RegisterControlTitles(control)
        elseif kind=="lsm_sound" then
            local original=UI:CreateFlatLSMSoundDropdown(card,420,"声音媒体",nil,function(value) Say("CreateLSMSoundDropdown: "..tostring(value)) end)
            PositionControl(original,18,82); local control=Settings.ReplaceDropdown(original)
            RegisterControlTitles(original); RegisterControlTitles(control)
        elseif kind=="multiselect" then
            local options={{"选项一","one"},{"选项二","two"},{"选项三","three"},{"不可用选项","disabled",disabled=true}}
            local selected={one=true}
            local original=UI:CreateFlatMultiSelectDropdown(card,520,"多选下拉",options,selected,function() end)
            PositionControl(original,18,82)
            local control=MultiSelectControl(card,520,options,selected,function()
                original:RefreshSelectionDisplay()
                Say("CreateMultiSelectDropdown: 选择已更新")
            end)
            control:SetAllPoints(original)
            RegisterControlTitles(original); RegisterControlTitles(control)
            if original.labelText then
                original.labelText:SetParent(control); original.labelText:ClearAllPoints()
                original.labelText:SetPoint("BOTTOMLEFT",control,"TOPLEFT",0,4); original.labelText:Show()
            end
            original:Hide()
            resets[#resets+1]=function() for key in pairs(selected) do selected[key]=nil end; selected.one=true; control:RefreshSelectionDisplay() end
        elseif kind=="button" then
            local control=UI:CreateFlatButton(card,220,32,"真实 CreateButton",function() Say("CreateButton: 已点击") end)
            PositionControl(control,18,72); Control(control,"button",4)
        elseif kind=="checkbox" then
            local control=UI:CreateFlatCheckbox(card,"真实 CreateCheckbox",true,function(value) Say("CreateCheckbox: "..tostring(value)) end)
            PositionControl(control,18,74); StyleCheckbox(control); RegisterControlTitles(control)
            resets[#resets+1]=function() control:SetChecked(true) end
        elseif kind=="slider" then
            local control=UI:CreateFlatSlider(card,420,"真实 CreateSlider",0,100,42,1,nil,{onLive=function(value) Say("CreateSlider: "..value) end,onCommit=function(value) Say("CreateSlider committed: "..value) end})
            -- Reuse the pre-existing FontGroup Slider appearance verbatim.
            PositionControl(control,18,91); ApplyFontGroupSlider(control,"真实 CreateSlider"); RegisterControlTitles(control)
            resets[#resets+1]=function() control:SetEXUIValue(42,"silent") end
        elseif kind=="header" then
            local control=UI:CreateFlatHeader(card,"真实 CreateHeader 标题",650)
            PositionControl(control,18,67); RegisterControlTitles(control)
        elseif kind=="color" then
            local colorDB={r=.15,g=.45,b=.9,a=1}
            local control=UI:CreateFlatColorButton(card,"真实 CreateColorButton",colorDB,"",true,function() Say("CreateColorButton: 颜色已更新") end)
            PositionControl(control,18,72); Control(control,"button",4); RegisterControlTitles(control)
            resets[#resets+1]=function() colorDB.r,colorDB.g,colorDB.b,colorDB.a=.15,.45,.9,1; control:UpdateColor() end
        elseif kind=="edit" then
            local control=UI:CreateFlatEditBox(card,"青蓝文本",520,32,"真实 CreateEditBox",{placeholder="请输入内容",onChanged=function(value) Say("CreateEditBox: "..value) end})
            PositionControl(control,18,82); Control(control,"input",4); RegisterControlTitles(control)
            resets[#resets+1]=function() control:SetText("青蓝文本") end
        elseif kind=="fontgroup" then
            local db={}
            local group=Settings:CreateFontGroup(card,938,"真实 CreateFontGroup",db,function() Say("CreateFontGroup: 仅预览内更新") end)
            PositionControl(group,18,66); RememberGroup(group,db); RegisterControlTitles(group)
        elseif kind=="icongroup" then
            local db={width=40,height=40,x=0,y=0,alpha=1}
            local group=Settings:CreateIconGroup(card,938,"真实 CreateIconGroup",db,nil,function() Say("CreateIconGroup: 仅预览内更新") end)
            PositionControl(group,18,66); RememberGroup(group,db); RegisterControlTitles(group)
        elseif kind=="timerbargroup" then
            local db={}
            local group=Settings:CreateTimerBarGroup(card,938,"真实 CreateTimerBarGroup",db,nil,function() Say("CreateTimerBarGroup: 仅预览内更新") end)
            PositionControl(group,18,66); RememberGroup(group,db); RegisterControlTitles(group)
        end
    end

    local y=105
    for index,item in ipairs(catalog) do
        local height=item[5] or (item[3] and (item[4]=="slider" and 145 or 132) or 132)
        local card=Box(canvas,8,y,974,height,8,C.card)
        card.offset=y; sections[index]=card
        local badge=Box(card,16,16,34,26,4,item[3] and C.accent or {.16,.18,.22,1})
        local number=Label(badge,string.format("%02d",index),7,6,25); number:SetTextColor(1,1,1,1)
        local title=RegisterTitle(Label(card,item[1],62,17,590)); SettingsTitle(title,titleSize)
        local source=Label(card,item[2],62,40,690,true); source:SetTextColor(.48,.58,.70,1)
        local state=Label(card,item[3] and "IMPLEMENTED · QA PENDING" or "NOT IMPLEMENTED",724,22,228,true)
        state:SetJustifyH("RIGHT"); state:SetTextColor(unpack(item[3] and {.38,.78,1,1} or {.52,.55,.62,1}))
        local line=card:CreateTexture(nil,"BORDER"); line:SetColorTexture(unpack(C.border)); line:SetPoint("TOPLEFT",16,-58); line:SetSize(942,PhysicalPixel(card))
        if item[3] then RenderAvailable(card,item) else EmptySlot(card) end
        y=y+height+12
    end
    local footer=Label(canvas,string.format("AXIS UI / QINGLAN  ·  %d 个公共入口  ·  已有 14  ·  原位空缺 %d",#catalog,#catalog-14),14,y+4,950,true)
    canvas:SetHeight(y+50)
    Jump(1)
    root:Show()
end
local startup=CreateFrame("Frame")
startup:RegisterEvent("PLAYER_LOGIN")
startup:SetScript("OnEvent",function(self) self:UnregisterEvent("PLAYER_LOGIN"); Build() end)
if IsLoggedIn() then startup:UnregisterEvent("PLAYER_LOGIN"); Build() end
SLASH_EXWINDQINGLANROUNDEDLAB1="/qinglan"
SlashCmdList.EXWINDQINGLANROUNDEDLAB=function()
    Build()
    root:SetShown(not root:IsShown())
end
