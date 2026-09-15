-- Settings page declaration registry.  This file owns GUI identity only; it
-- never registers a business module, value controller, display owner or DB.
local ExwindTools = _G.ExwindTools
if type(ExwindTools) ~= "table" or type(ExwindTools.UI) ~= "table" then
    error("ExwindSettingsPages requires initialized EXUI", 0)
end

local EXUI = ExwindTools.UI
if EXUI.SettingsPageRegistryInitialized then
    error("ExwindSettingsPages already initialized", 0)
end
EXUI.SettingsPageRegistryInitialized = true

local pages = {}
local modulePages = {}
local inventories = {}
local settingsBindings = {}
EXUI.SettingsPages = pages

local function RequireID(value, name, level)
    if type(value) ~= "string" or value:match("^%s*$") then
        error(name .. " must be a non-empty string", level or 3)
    end
    return value
end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error("settings declaration cannot be cyclic", 4) end
    local result = {}
    seen[value] = true
    for key, child in pairs(value) do result[Copy(key, seen)] = Copy(child, seen) end
    seen[value] = nil
    return result
end

local function IsDenseArray(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
    end
    return count == #value
end

local function ValidateGridItem(item, location)
    if type(item) ~= "table" then error(location .. " must be a table", 4) end
    RequireID(item.type, location .. ".type", 4)
    RequireID(item.key, location .. ".key", 4)
    for _, field in ipairs({ "x", "y", "w", "h" }) do
        if type(item[field]) ~= "number" then error(location .. " requires numeric " .. field, 4) end
    end
    if item.x < 1 or item.y < 1 or item.w <= 0 or item.h <= 0 or item.x + item.w - 1 > 200 then
        error(location .. " has invalid body-local geometry", 4)
    end
    if item.type == "TableGroup" then
        error(location .. " cannot use TableGroup as a visual card container", 4)
    end
end

local function ValidateCard(pageID, card, index, ids)
    local location = "settings page " .. pageID .. " card[" .. index .. "]"
    if type(card) ~= "table" then error(location .. " must be a table", 4) end
    local cardID = RequireID(card.id, location .. ".id", 4)
    if ids[cardID] then error("settings page " .. pageID .. " has duplicate card id " .. cardID, 4) end
    ids[cardID] = true
    if card.x ~= nil or card.y ~= nil or card.w ~= nil or card.h ~= nil or card.top ~= nil or card.order ~= nil then
        error(location .. " cannot declare outer card geometry", 4)
    end
    if card.collapsed == true and card.collapsible ~= true then
        error(location .. " collapsed=true requires collapsible=true", 4)
    end
    if card.collapsible == true and (card.title == nil or card.title == "") then
        error(location .. " collapsible card requires a title", 4)
    end
    local minHeight = tonumber(card.minBodyHeight) or 0
    local maxHeight = card.maxBodyHeight ~= nil and tonumber(card.maxBodyHeight) or nil
    if minHeight < 0 or (maxHeight and maxHeight < 0) or (maxHeight and minHeight > maxHeight) then
        error(location .. " has invalid minBodyHeight/maxBodyHeight", 4)
    end

    local content = card.content
    if type(content) ~= "table" then error(location .. ".content must be a table", 4) end
    local kind = content.kind
    if kind ~= "grid" and kind ~= "composite" and kind ~= "custom" then
        error(location .. ".content.kind must be grid, composite or custom", 4)
    end
    if kind == "grid" then
        if not IsDenseArray(content.items) then error(location .. ".content.items must be a dense array", 4) end
        if content.component ~= nil or content.renderer ~= nil then error(location .. " grid content mixes content kinds", 4) end
        local itemIDs = {}
        for itemIndex, item in ipairs(content.items) do
            ValidateGridItem(item, location .. ".content.items[" .. itemIndex .. "]")
            if itemIDs[item.key] then error(location .. " has duplicate widget key " .. item.key, 4) end
            itemIDs[item.key] = true
        end
    elseif kind == "composite" then
        RequireID(content.component, location .. ".content.component", 4)
        RequireID(content.key, location .. ".content.key", 4)
        if content.items ~= nil or content.renderer ~= nil then error(location .. " composite content mixes content kinds", 4) end
        if _G.ExwindGrid and type(_G.ExwindGrid.IsCompositeTypeSupported) == "function"
            and not _G.ExwindGrid:IsCompositeTypeSupported(content.component) then
            error(location .. " references unregistered composite " .. content.component, 4)
        end
    else
        RequireID(content.renderer, location .. ".content.renderer", 4)
        if content.items ~= nil or content.component ~= nil then error(location .. " custom content mixes content kinds", 4) end
        local renderer = _G.ExwindGrid and _G.ExwindGrid:GetCustomRenderer(content.renderer)
        if type(renderer) ~= "table" then error(location .. " references unregistered custom renderer " .. content.renderer, 4) end
        if renderer.mount ~= nil and type(renderer.mount) ~= "function" then error(location .. " custom mount must be a function", 4) end
        if renderer.update ~= nil and type(renderer.update) ~= "function" then error(location .. " custom update must be a function", 4) end
        if renderer.render ~= nil and type(renderer.render) ~= "function" then error(location .. " custom render must be a function", 4) end
        if renderer.release ~= nil and type(renderer.release) ~= "function" then error(location .. " custom release must be a function", 4) end
        if renderer.mount ~= nil and renderer.release == nil then error(location .. " custom mount requires release", 4) end
        if content.height ~= nil and (type(content.height) ~= "number" or content.height < 0) then
            error(location .. " custom height must be non-negative", 4)
        end
    end
end

function EXUI:ValidateSettingsPageDeclaration(pageID, declaration)
    RequireID(pageID, "settings page id", 3)
    if type(declaration) ~= "table" then error("settings page " .. pageID .. " declaration must be a table", 3) end
    if declaration.version ~= 1 then error("settings page " .. pageID .. " requires gui.version=1", 3) end
    if declaration.static ~= nil or declaration.fields ~= nil or declaration.groups ~= nil then
        error("settings page " .. pageID .. " mixes retired gui.static/fields/groups", 3)
    end
    if not IsDenseArray(declaration.cards) then error("settings page " .. pageID .. ".cards must be a dense array", 3) end
    local ids = {}
    for index, card in ipairs(declaration.cards) do ValidateCard(pageID, card, index, ids) end
    return true
end

function EXUI:RegisterSettingsPage(pageID, declaration, metadata)
    RequireID(pageID, "RegisterSettingsPage pageID", 2)
    if pages[pageID] then error("duplicate settings page id " .. pageID, 2) end
    self:ValidateSettingsPageDeclaration(pageID, declaration)
    metadata = metadata or {}
    if type(metadata) ~= "table" then error("settings page metadata must be a table: " .. pageID, 2) end
    local aliases = metadata.bindings or {}
    if type(aliases) ~= "table" then error("settings page metadata.bindings must be a table: " .. pageID, 2) end
    for alias, bindingID in pairs(aliases) do
        RequireID(alias, "settings page binding alias", 2)
        RequireID(bindingID, "settings page binding id", 2)
    end
    for _, card in ipairs(declaration.cards) do
        if card.binding ~= nil then
            if type(card.binding) ~= "string" or card.binding == "" then
                error("settings page card.binding must be a named metadata alias: " .. pageID .. "/" .. card.id, 2)
            end
            if aliases[card.binding] == nil then
                error("settings page card references undeclared binding alias: " .. pageID .. "/" .. card.id .. "/" .. card.binding, 2)
            end
        end
    end
    pages[pageID] = { declaration = Copy(declaration), metadata = Copy(metadata) }
    return pageID
end

function EXUI:GetSettingsPage(pageID)
    local entry = pages[pageID]
    return entry and Copy(entry.declaration) or nil
end

-- 跨 owner 卡片只能引用具名 binding。owner 注册真实 binding，页面 metadata
-- 只保存 alias -> bindingID；因此消费页不会复制另一模块的 DB 或持有私有回调副本。
function EXUI:RegisterSettingsBinding(bindingID, binding)
    bindingID = RequireID(bindingID, "RegisterSettingsBinding bindingID", 2)
    if settingsBindings[bindingID] then error("duplicate settings binding id " .. bindingID, 2) end
    if type(binding) ~= "table" or type(binding.getConfig) ~= "function" then
        error("settings binding requires a table with getConfig: " .. bindingID, 2)
    end
    RequireID(binding.moduleKey, "settings binding moduleKey", 2)
    settingsBindings[bindingID] = binding
    return binding
end

function EXUI:GetSettingsBinding(bindingID)
    return settingsBindings[RequireID(bindingID, "GetSettingsBinding bindingID", 2)]
end

function EXUI:ResolveSettingsPageBindings(pageID)
    local entry = pages[RequireID(pageID, "ResolveSettingsPageBindings pageID", 2)]
    if not entry then return nil end
    local resolved = {}
    for alias, bindingID in pairs(entry.metadata.bindings or {}) do
        local binding = settingsBindings[bindingID]
        if not binding then error("settings page binding owner is not registered: " .. pageID .. "/" .. alias .. " -> " .. bindingID, 2) end
        resolved[alias] = binding
    end
    return resolved
end

function EXUI:RegisterModuleSettingsPage(moduleKey, pageID)
    RequireID(moduleKey, "RegisterModuleSettingsPage moduleKey", 2)
    RequireID(pageID, "RegisterModuleSettingsPage pageID", 2)
    if not pages[pageID] then error("module settings page is not registered: " .. pageID, 2) end
    if modulePages[moduleKey] and modulePages[moduleKey] ~= pageID then
        error("module already has a settings page: " .. moduleKey, 2)
    end
    modulePages[moduleKey] = pageID
    return pageID
end

function EXUI:GetModuleSettingsPageID(moduleKey)
    return modulePages[moduleKey]
end

function EXUI:DeclareSettingsPageInventory(addonName, entries)
    RequireID(addonName, "DeclareSettingsPageInventory addonName", 2)
    if inventories[addonName] then error("settings page inventory already declared: " .. addonName, 2) end
    if not IsDenseArray(entries) then error("settings page inventory must be a dense array", 2) end
    local inventory = {}
    for index, source in ipairs(entries) do
        if type(source) ~= "table" then error("settings page inventory entry " .. index .. " must be a table", 2) end
        local id = RequireID(source.id, "settings page inventory entry id", 2)
        if inventory[id] then error("duplicate settings inventory id " .. id, 2) end
        local mode = source.mode or "gui"
        if mode ~= "gui" and mode ~= "no-gui" and mode ~= "deferred" then
            error("settings inventory " .. id .. " has invalid mode", 2)
        end
        inventory[id] = Copy(source)
    end
    inventories[addonName] = inventory
end

function EXUI:ValidateSettingsPageInventory(addonName)
    local inventory = inventories[addonName]
    if not inventory then error("settings page inventory is not declared: " .. tostring(addonName), 2) end
    local missing = {}
    for id, expected in pairs(inventory) do
        if expected.mode == "gui" then
            local pageID = expected.pageID or modulePages[id]
            if not pageID or not pages[pageID] then missing[#missing + 1] = id end
        end
    end
    table.sort(missing)
    if #missing > 0 then
        error("[EXUI Settings] " .. addonName .. " loaded with missing GUI registrations: " .. table.concat(missing, ", "), 2)
    end
    return true
end

-- The Tools catalog is the authoritative expected-page list, not the set of
-- successful registrations.  The one internal data module is an explicit
-- no-GUI exception; hidden settings pages remain required.
local toolsInventory = {}
for _, meta in ipairs(ExwindTools.ModuleList or {}) do
    toolsInventory[#toolsInventory + 1] = {
        id = meta.Key,
        mode = meta.Key == "ExM+InfoSpellData" and "no-gui" or "gui",
        reason = meta.Key == "ExM+InfoSpellData" and "internal spell data" or nil,
    }
end
EXUI:DeclareSettingsPageInventory("ExwindTools", toolsInventory)

local inventoryFrame = CreateFrame("Frame")
inventoryFrame:RegisterEvent("ADDON_LOADED")
inventoryFrame:SetScript("OnEvent", function(_, _, addonName)
    if inventories[addonName] then EXUI:ValidateSettingsPageInventory(addonName) end
end)
