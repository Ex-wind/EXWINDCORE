local ADDON_NAME = ...
local SPELL_ID = 1265982
local ICON_SPELL_ID = 50842
local DISPLAY_DURATION = 3
local ICON_WIDTH = 38
local ICON_HEIGHT = 32

local defaults = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 0,
    locked = true,
}

local function CopyDefaults()
    for key, value in pairs(defaults) do
        if EXDKDB[key] == nil then
            EXDKDB[key] = value
        end
    end
end

local frame = CreateFrame("Frame", "EXDKCooldownIcon", UIParent, "BackdropTemplate")
frame:SetSize(ICON_WIDTH, ICON_HEIGHT)
frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame:EnableMouse(false)
frame:RegisterForDrag("LeftButton")

frame.icon = frame:CreateTexture(nil, "ARTWORK")
frame.icon:SetAllPoints()

frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
frame.cooldown:SetAllPoints(frame.icon)
frame.cooldown:SetDrawBling(false)
frame.cooldown:SetDrawEdge(false)
frame.cooldown:SetHideCountdownNumbers(true)
frame.cooldown:SetSwipeColor(0, 0, 0, 0.65)
frame.cooldown:Hide()

frame.textLayer = CreateFrame("Frame", nil, frame)
frame.textLayer:SetAllPoints()
frame.textLayer:SetFrameLevel(frame.cooldown:GetFrameLevel() + 1)

local function CreateBorder()
    local border = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    border:SetColorTexture(0, 0, 0, 1)
    return border
end

local topBorder = CreateBorder()
topBorder:SetPoint("TOPLEFT")
topBorder:SetPoint("TOPRIGHT")
topBorder:SetHeight(1)

local bottomBorder = CreateBorder()
bottomBorder:SetPoint("BOTTOMLEFT")
bottomBorder:SetPoint("BOTTOMRIGHT")
bottomBorder:SetHeight(1)

local leftBorder = CreateBorder()
leftBorder:SetPoint("TOPLEFT")
leftBorder:SetPoint("BOTTOMLEFT")
leftBorder:SetWidth(1)

local rightBorder = CreateBorder()
rightBorder:SetPoint("TOPRIGHT")
rightBorder:SetPoint("BOTTOMRIGHT")
rightBorder:SetWidth(1)

frame.countdown = frame.textLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.countdown:SetPoint("CENTER", 0, 0)
local fontPath, fontSize = frame.countdown:GetFont()
frame.countdown:SetFont(fontPath, fontSize, "THINOUTLINE")
frame.countdown:SetTextColor(1, 1, 1, 1)
frame.countdown:SetShadowColor(0, 0, 0, 1)
frame.countdown:SetShadowOffset(1, -1)

frame.unlockHint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.unlockHint:SetPoint("TOP", frame, "BOTTOM", 0, -3)
frame.unlockHint:SetText("EXDK")
frame.unlockHint:SetTextColor(1, 0.82, 0, 1)

local function SetPosition()
    frame:ClearAllPoints()
    frame:SetPoint(EXDKDB.point, UIParent, EXDKDB.relativePoint, EXDKDB.x, EXDKDB.y)
end

local function SetLocked(locked)
    EXDKDB.locked = locked
    frame:EnableMouse(not locked)
    frame:SetMovable(not locked)
    frame.unlockHint:SetShown(not locked)

    if not locked and not frame:IsShown() then
        frame.icon:SetTexture(C_Spell.GetSpellTexture(ICON_SPELL_ID) or 134400)
        frame.cooldown:Hide()
        frame.countdown:SetText("拖动")
        frame:Show()
    elseif locked and not frame.active then
        frame:Hide()
    end
end

frame:SetScript("OnDragStart", function(self)
    if not EXDKDB.locked then
        self:StartMoving()
    end
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    EXDKDB.point = point
    EXDKDB.relativePoint = relativePoint
    EXDKDB.x = x
    EXDKDB.y = y
end)

local function ShowCountdown()
    local texture = C_Spell.GetSpellTexture(ICON_SPELL_ID)
    frame.icon:SetTexture(texture or 134400)
    frame.active = true
    frame.endsAt = GetTime() + DISPLAY_DURATION
    frame.cooldown:SetCooldown(GetTime(), DISPLAY_DURATION)
    frame.cooldown:Show()
    frame:Show()
end

frame:SetScript("OnUpdate", function(self)
    if not self.active then
        return
    end

    local remaining = self.endsAt - GetTime()
    if remaining <= 0 then
        self.active = false
        self.cooldown:Hide()
        self.countdown:SetText("")
        if EXDKDB.locked then
            self:Hide()
        else
            self.countdown:SetText("拖动")
        end
        return
    end

    self.countdown:SetText(math.ceil(remaining))
end)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then
            return
        end

        EXDKDB = EXDKDB or {}
        CopyDefaults()
        SetPosition()
        SetLocked(EXDKDB.locked)
        return
    end

    local spellID = ...
    if spellID == SPELL_ID then
        ShowCountdown()
    end
end)

SLASH_EXDK1 = "/exdk"
SlashCmdList.EXDK = function(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")

    if command == "unlock" or command == "解锁" then
        SetLocked(false)
        print("|cff00ff00EXDK: 已解锁，可拖动图标。|r")
    elseif command == "lock" or command == "锁定" then
        SetLocked(true)
        print("|cff00ff00EXDK: 已锁定。|r")
    else
        print("|cffffd100EXDK 命令：|r /exdk unlock（解锁拖动）  /exdk lock（锁定）")
    end
end
