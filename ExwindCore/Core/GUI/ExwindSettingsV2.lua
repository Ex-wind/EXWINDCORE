-- V2 owns presentation. control/component nodes that declare `path` are bound by
-- the standard layer below (read, write, NotifyModuleValueChanged); nodes that
-- declare `ref` keep their owner adapters, records and writes.
local UI, Factory = _G.ExwindTools.UI, _G.ExwindFactory
local Pages, Session = {}, {}
UI.SettingsDeclarationSchemaRevision = 12 -- Static declaration rules; bump when accepted schema changes.
local GM = _G.ExwindTools.GUIMetrics
if not GM then error("ExwindGUIMetrics.lua must load before ExwindSettingsV2.lua") end
local POOL, GAP, PAD = "EXUI.SettingsV2.Node", GM.space.settingsV2Gap, GM.space.settingsV2Padding
Factory:InitCompositePool(POOL)

local Fields = {
    -- note = 页面写了 style 时标题条右侧的灰字（texts 引用名）；不写时显示“N 项”。
    card = "title titleSource titlePosition titleAlign collapsible collapsed help note children row column span gapBefore minBodyHeight bodyHeight overflow surface",
    group = "title children", row = "children separator", cell = "children",
    actions = "children position align", columns = "columns children",
    -- 普通设置页的两种语义节点：setting = 左标签右控件；table = 列标题 + 每格控件。
    -- setting 左侧可选 toggle（勾选框，绑定存档 path，没勾时右侧控件变灰）或 icon（标签前的图标）。
    -- help = 页面写了 style 时标签后的小问号，悬停显示这段说明。
    setting = "label description toggle icon help children",
    -- table 可选记录操作：rowActions = 每行末尾按钮，addAction = 首行新增按钮（input 给出时，同一行首格放该输入框），
    -- selected = 高亮当前行的判断。
    table = "columns children rowActions addAction selected",
    ["repeat"] = "source template",
    -- placeholder = 输入框（controlType="input"，path 控件或 owner 用 CreateSettingsV2Control 建的记录控件）的占位字，
    -- 输入框为空时显示、占位灰；不写时没有占位字。
    -- allowEmpty = true 只用在分段（controlType="segment"）：值为空或不在选项里时不高亮任何一项；不写时照旧选第一项。
    control = "ref custom controlType mode path label description options optionsSource media multiple search min max step inputWidthPercent size items placeholder allowEmpty",
    component = "ref custom component path label opts optionsRef",
    text = "text textSource", hint = "text textSource",
    -- icon = 页面写了 style 时的图标按钮（GUIIcons ID，text 必须为空）：宽 = 高，不受按钮最小宽限制。
    button = "text action clickKey presentation icon",
}
local Common = "id kind visible enabled width weight height"
local ControlTypes = { input=true, multiline=true, checkbox=true, switch=true, card=true,
    choice=true, tristate=true, select=true, slider=true, color=true, field=true }
-- Standard binding layer: the control types and composite components a `path`
-- node may declare. Records, choice groups and custom content stay on owners.
-- segment = 单选分段（path 存所选 value）；toggles = 多选（角标勾小块，items 每项一个 boolean path，节点本身不写 path）。
-- multiline = 多行文字（导入导出字符串、备注），高度只能选标准或 size="tall"。
-- optionlist = 单选卡片列表（竖排，每项标题 + 可选说明），path 存所选 value。
local PathControlTypes = { switch=true, checkbox=true, card=true, input=true, select=true, slider=true, color=true,
    segment=true, toggles=true, multiline=true, optionlist=true }
local RowControlTypes = { switch=true, input=true, select=true, slider=true, color=true, segment=true, toggles=true,
    multiline=true, optionlist=true }
local SelectMedia = { font=true, sound=true, statusbar=true, border=true, background=true }
-- soundselector = 连体声音选择（来源 | 内容 | ▶），path 是字段前缀：<path>Source/Label/LSM/Path/TtsText。
local StandardComponents = { fontgroup=true, icongroup=true, timerbargroup=true, anchorgroup=true,
    soundgroup=true, widgetlayout=true, modulecommonsettings=true, glow_settings=true, texturegroup=true,
    soundselector=true }
local PathControlFields = "controlType label description options optionsSource media multiple search min max step inputWidthPercent size items placeholder allowEmpty"
local PathOnlyFields = { "label", "description", "options", "optionsSource", "media", "multiple", "search",
    "min", "max", "step", "inputWidthPercent", "size", "items", "component", "opts", "optionsRef", "placeholder", "allowEmpty" }
-- 控件宽度档位：页面不写像素，只能选档位（省略 = 标准宽）。
local ControlSizes = { short=true, wide=true, tall=true }

-- =========================================================
-- 普通页规则（10-13 用户定）：页面标题 → 卡片 → 只有四种内容。
--   1 标准行（setting / 带 label 的 path 控件）  2 表格（table）
--   3 Core 封装控件（component）              4 自定义（只给下面两张名单）
-- 普通页不准写尺寸、灰字、手拼零件、卡片里悬空的按钮；卡片只有一种外观（标题在上）。
-- 名单只在这里改：FreeformPages = 整页自由布局；CustomParts = 普通页里允许的自定义件（节点写 custom="键"）。
-- =========================================================
local FreeformPages = {
    ["ExTools.SpellQueue"] = true,          -- Tools 全职业延迟容限
    ["ExClass.SpellEffectAlpha"] = true,    -- Tools 法术触发透明度
}
local CustomParts = {
    ["EXBoss.VoiceTimeline"] = true,        -- 首领 / 小怪语音时间轴预览
    ["EXBoss.AuraSoundList"] = true,        -- 副本通用光环声音列表（虚拟滚动）
    ["EXBoss.HomeBrand"] = true,            -- 首页品牌与联系资料（非设置项）
    ["EXBoss.HomePeople"] = true,           -- 首页感谢人物卡（非设置项）
    ["EXAura.AuthorInfo"] = true,           -- 设置页顶部资料区
    ["EXAura.GlowStyles"] = true,           -- 发光样式卡片
    ["EXAura.AnimationCards"] = true,       -- 条件二级面板的动画卡片
    ["EXAura.ExpressionEditor"] = true,     -- 附加触发器组合编辑
    ["EXAura.LuaEditor"] = true,            -- 代码编辑器
    ["EXAura.ConditionList"] = true,        -- 条件页已有条件卡
    ["EXAura.SpellList"] = true,            -- 触发页指定法术
    ["EXAura.TopCell"] = true,              -- 右侧面板顶部格
    ["EXAura.FilterCards"] = true,          -- 触发页过滤卡片
    ["EXAura.AddCards"] = true,             -- 新增卡片
}
local StrictCardFields = { "titlePosition", "titleAlign", "help",
    "minBodyHeight", "bodyHeight", "overflow", "surface", "gapBefore" }
local StrictSizeFields = { "width", "weight", "height", "inputWidthPercent" }
-- 普通页里每种位置能放的节点。
-- group = 样式页里的“块”：一组行合成一块（常作 repeat 的 template，每条记录一块），块内行之间不画线、块与块之间一条线。
local StrictChildren = {
    card = { setting=true, control=true, component=true, table=true, ["repeat"]=true, group=true },
    group = { setting=true, control=true, component=true, table=true },
    setting = { control=true, button=true, component=true, text=true },
    table = { row=true, ["repeat"]=true },
    row = { cell=true },
    cell = { control=true, button=true, text=true },
}
local MaxSettingControls = 3
local AdapterMethods = { "mount", "update", "measure", "layout", "setEnabled", "setVisible", "release" }
local ControlMethods = { "mount", "release" }
local Build, MountNode, ReleaseNode, RefreshNode, LayoutNode
local Mounted = setmetatable({}, { __mode = "k" }) -- parent -> 存活的 V2 会话

local function Check(ok, message)
    if not ok then error("SettingsV2: " .. message, 3) end
end

local function Name(value)
    return type(value) == "string" and value ~= ""
end

local function Number(value)
    return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function Keys(value, fields, where)
    Check(type(value) == "table" and getmetatable(value) == nil, where .. " must be a plain table")
    local allowed = {}
    for field in fields:gmatch("%S+") do allowed[field] = true end
    for field in pairs(value) do Check(allowed[field], where .. ": unknown field " .. tostring(field)) end
end

local function Array(value, where)
    Check(type(value) == "table" and getmetatable(value) == nil, where .. " must be an array")
    local count = 0
    for key in pairs(value) do
        Check(type(key) == "number" and key >= 1 and key % 1 == 0, where .. ": invalid array index")
        count = count + 1
    end
    for i = 1, count do Check(value[i] ~= nil, where .. ": sparse array") end
    return count
end

-- Copy declarations only; never used for owner data or records.
local function DeclarationCopy(value, seen)
    local kind = type(value)
    Check(kind == "table" or kind == "string" or kind == "number" or kind == "boolean" or kind == "nil",
        "declarations must contain only data")
    if kind ~= "table" then return value end
    Check(not seen[value] and getmetatable(value) == nil, "cyclic/metatable declaration")
    seen[value] = true
    local copy = {}
    for key, entry in pairs(value) do
        Check(type(key) == "string" or type(key) == "number", "invalid declaration key")
        copy[key] = DeclarationCopy(entry, seen)
    end
    seen[value] = nil
    return copy
end

local function Reference(owner, bucket, name, where)
    Check(Name(name), where .. " requires a named reference")
    if not owner then return end
    local value = owner[bucket] and owner[bucket][name]
    Check(type(value) == "function", where .. ": missing " .. bucket .. "." .. name)
end

-- All expected declaration failures travel as data. No callbacks or metamethods
-- are evaluated during preflight, including owner reference lookup.
local function Issue(path, message, nodeId, code)
    return false, { code=code or "INVALID_SCHEMA", path=path, nodeId=nodeId, message=message }
end

local function Pure(value, path, seen)
    local kind = type(value)
    if kind ~= "table" then
        if kind == "nil" or kind == "string" or kind == "boolean"
            or (kind == "number" and value == value and math.abs(value) < math.huge) then return true end
        return Issue(path, "declarations must contain finite plain data")
    end
    if getmetatable(value) ~= nil or seen[value] then return Issue(path, "cyclic/metatable declaration") end
    seen[value] = true
    for key, entry in next, value do
        if type(key) ~= "string" and type(key) ~= "number" then return Issue(path, "invalid declaration key") end
        local ok, issue = Pure(entry, path .. "." .. tostring(key), seen)
        if not ok then return false, issue end
    end
    seen[value] = nil
    return true
end

local function SchemaKeys(value, fields, path, id)
    if type(value) ~= "table" then return Issue(path, "expected a plain table", id) end
    local allowed = {}
    for field in fields:gmatch("%S+") do allowed[field] = true end
    for field in next, value do
        if not allowed[field] then return Issue(path .. "." .. tostring(field), "unknown field", id) end
    end
    return true
end

local function SchemaArray(value, path, id)
    if type(value) ~= "table" then return Issue(path, "expected an array", id) end
    local count = 0
    for key in next, value do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return Issue(path, "invalid array index", id) end
        count = count + 1
    end
    for i = 1, count do
        if rawget(value, i) == nil then return Issue(path .. "[" .. i .. "]", "sparse array", id) end
    end
    return true, count
end

local function SchemaReference(owner, bucket, name, path, id)
    if not Name(name) then return Issue(path, "named reference required", id) end
    if owner == nil then return true end
    local refs = rawget(owner, bucket)
    if type(refs) ~= "table" or type(rawget(refs, name)) ~= "function" then
        return Issue(path, "missing " .. bucket .. "." .. name, id)
    end
    return true
end

local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- path/clickKey nodes write through owner.binding = { moduleKey, config }.
local function SchemaBinding(owner, path, id)
    if owner == nil then return true end
    local binding = rawget(owner, "binding")
    if type(binding) ~= "table" or not Name(rawget(binding, "moduleKey")) or type(rawget(binding, "config")) ~= "table" then
        return Issue(path, "path binding requires owner.binding { moduleKey, config }", id)
    end
    return true
end

-- Shared by declaration nodes and owner-built standard controls.
local function SchemaPathControl(spec, path, id)
    local function fail(field, message) return Issue(path .. "." .. field, message, id) end
    local kind = spec.controlType
    if not PathControlTypes[kind] then return fail("controlType", "path control requires switch/checkbox/card/input/select/slider/color/segment/toggles") end
    if spec.mode ~= nil then return fail("mode", "mode belongs to owner choice controls") end
    for _, field in ipairs({ "label", "description" }) do
        if spec[field] ~= nil and type(spec[field]) ~= "string" then return fail(field, "expected string") end
    end
    if kind == "card" and type(spec.label) ~= "string" then
        return fail("label", "label required")
    end
    if kind ~= "select" and kind ~= "segment" and kind ~= "optionlist" and (spec.options ~= nil or spec.optionsSource ~= nil) then
        return fail("options", "options require select, segment or optionlist")
    end
    if kind ~= "select" and (spec.media ~= nil or spec.multiple ~= nil or spec.search ~= nil) then
        return fail("media", "media/multiple/search require select")
    end
    if kind ~= "slider" and (spec.min ~= nil or spec.max ~= nil or spec.step ~= nil) then return fail("min", "bounds require slider") end
    if kind ~= "input" and spec.inputWidthPercent ~= nil then return fail("inputWidthPercent", "requires input") end
    if spec.placeholder ~= nil and (kind ~= "input" or not Name(spec.placeholder)) then
        return fail("placeholder", "placeholder is a non-empty string on input")
    end
    if spec.allowEmpty ~= nil and (kind ~= "segment" or spec.allowEmpty ~= true) then
        return fail("allowEmpty", "allowEmpty = true only on segment")
    end
    if spec.size ~= nil and (not ControlSizes[spec.size]
        or (spec.size == "tall") ~= (kind == "multiline") or (kind ~= "input" and kind ~= "select" and kind ~= "multiline")) then
        return fail("size", "size is short/wide on input or select, tall on multiline")
    end
    if (spec.items ~= nil) ~= (kind == "toggles") then return fail("items", "items belong to toggles") end
    if kind == "toggles" then
        local ok, issue = SchemaArray(spec.items, path .. ".items", id)
        if not ok then return false, issue end
        if issue == 0 then return fail("items", "toggles requires items") end
        for i, item in ipairs(spec.items) do
            local at = path .. ".items[" .. i .. "]"
            ok, issue = SchemaKeys(item, "label path", at, id)
            if not ok then return false, issue end
            if type(item.label) ~= "string" or not Name(item.path) then return Issue(at, "toggle item requires label and path", id) end
        end
    elseif kind == "segment" or kind == "optionlist" then
        if spec.options == nil then return fail("options", kind .. " requires options") end
        local ok, issue = SchemaArray(spec.options, path .. ".options", id)
        if not ok then return false, issue end
        for i, option in ipairs(spec.options) do
            local at = path .. ".options[" .. i .. "]"
            ok, issue = SchemaKeys(option, kind == "optionlist" and "value label description" or "value label", at, id)
            if not ok then return false, issue end
            if type(option.label) ~= "string" then return Issue(at .. ".label", "expected string", id) end
            if option.description ~= nil and type(option.description) ~= "string" then return Issue(at .. ".description", "expected string", id) end
            if type(option.value) ~= "string" and type(option.value) ~= "boolean" and not Finite(option.value) then
                return Issue(at .. ".value", "expected string, number or boolean", id)
            end
        end
    end
    if kind == "select" then
        local sources = (spec.options ~= nil and 1 or 0) + (spec.optionsSource ~= nil and 1 or 0) + (spec.media ~= nil and 1 or 0)
        if sources ~= 1 then return fail("options", "select requires exactly one of options, optionsSource, media") end
        if spec.multiple ~= nil and type(spec.multiple) ~= "boolean" then return fail("multiple", "expected boolean") end
        if spec.search ~= nil and type(spec.search) ~= "boolean" then return fail("search", "expected boolean") end
        if spec.media ~= nil and (not SelectMedia[spec.media] or spec.multiple ~= nil) then
            return fail("media", "media requires a single font/sound/statusbar/border/background select")
        end
        if spec.optionsSource ~= nil and (type(spec.optionsSource) ~= "string"
            or not spec.optionsSource:match("^[%a_][%w_%.]*$")) then
            return fail("optionsSource", "expected a global provider name")
        end
        if spec.options ~= nil then
            local ok, issue = SchemaArray(spec.options, path .. ".options", id)
            if not ok then return false, issue end
            local seen = {}
            for i, option in ipairs(spec.options) do
                local at = path .. ".options[" .. i .. "]"
                ok, issue = SchemaKeys(option, "value label", at, id)
                if not ok then return false, issue end
                if type(option.label) ~= "string" then return Issue(at .. ".label", "expected string", id) end
                local valueType = type(option.value)
                if valueType ~= "string" and valueType ~= "boolean" and not Finite(option.value) then
                    return Issue(at .. ".value", "expected string, number or boolean", id)
                end
                if seen[option.value] then return Issue(at .. ".value", "duplicate option value", id) end
                seen[option.value] = true
            end
        end
    elseif kind == "slider" then
        for _, field in ipairs({ "min", "max", "step" }) do
            if spec[field] ~= nil and not Finite(spec[field]) then return fail(field, "expected a finite number") end
        end
        if (spec.min or 0) > (spec.max or 100) or (spec.step or 1) <= 0 then return fail("step", "invalid slider bounds or step") end
    elseif kind == "input" and spec.inputWidthPercent ~= nil and not Number(spec.inputWidthPercent) then
        return fail("inputWidthPercent", "expected a positive finite number")
    end
    return true
end

-- styled = 页面 style 对应的 GM.settings.styles 预设表（没写 style 为 nil）；note、help 只在样式页里允许。
local function ValidateNode(node, owner, ids, depth, location, columnCount, path, styled)
    if type(node) ~= "table" or not Fields[node.kind] then return Issue(path, "unknown node kind") end
    local kind, id = node.kind, node.id
    local function fail(field, message) return Issue(path .. (field and "." .. field or ""), message, id) end
    local ok, issue = SchemaKeys(node, Common .. " " .. Fields[kind], path, id)
    if not ok then return false, issue end
    if not Name(id) or ids[id] then return fail("id", "missing/duplicate node id") end
    ids[id] = true
    local top = location == "page"
    if top and kind ~= "card" and kind ~= "repeat" then return fail("kind", "page accepts card/repeat") end
    if not top and kind == "card" then return fail("kind", "card must be at page level") end
    if kind == "actions" and (location ~= "row" or columnCount) then return fail("kind", "actions requires a flow row") end
    if kind == "cell" and (location ~= "row" or not columnCount) then return fail("kind", "cell requires a shared-column row") end
    for _, field in ipairs({ "width", "weight", "height" }) do
        if node[field] ~= nil and not Number(node[field]) then return fail(field, "expected a positive finite number") end
    end
    if node.width and node.weight then return fail("weight", "width and weight are exclusive") end
    if (node.width or node.weight) and not ((location == "row" or location == "actions") and not columnCount) then
        return fail("width", "width/weight require a flow item")
    end
    if node.height and kind ~= "control" and kind ~= "component" and kind ~= "button" and kind ~= "text" and kind ~= "hint" then
        return fail("height", "height is leaf-only")
    end
    for _, field in ipairs({ "visible", "enabled" }) do
        if node[field] ~= nil then
            ok, issue = SchemaReference(owner, "predicates", node[field], path .. "." .. field, id)
            if not ok then return false, issue end
        end
    end
    if kind == "card" or kind == "group" then
        if kind == "card" and node.titleSource ~= nil then
            if node.title ~= nil then return fail("title", "use title or titleSource") end
            ok, issue = SchemaReference(owner, "texts", node.titleSource, path .. ".titleSource", id)
            if not ok then return false, issue end
        elseif type(node.title) ~= "string" then return fail("title", "title required") end
        if kind == "card" then
            if node.bodyHeight ~= nil and not Number(node.bodyHeight) then return fail("bodyHeight", "positive finite height required") end
            if node.bodyHeight ~= nil and node.minBodyHeight ~= nil then return fail("minBodyHeight", "bodyHeight and minBodyHeight are exclusive") end
            if node.overflow ~= nil and node.overflow ~= "scroll" then return fail("overflow", "expected scroll") end
            if (node.bodyHeight ~= nil) ~= (node.overflow ~= nil) then return fail("bodyHeight", "bodyHeight and overflow=scroll required together") end
            if node.surface ~= nil and node.surface ~= "none" then return fail("surface", "expected none") end
            for _, field in ipairs({ "row", "column", "span" }) do
                if node[field] ~= nil and (not Number(node[field]) or node[field] % 1 ~= 0) then
                    return fail(field, "expected a positive integer")
                end
            end
            for _, field in ipairs({ "gapBefore", "minBodyHeight" }) do
                if node[field] ~= nil and (not Finite(node[field]) or node[field] < 0) then
                    return fail(field, "expected a non-negative finite number")
                end
            end
            if node.titlePosition ~= nil and node.titlePosition ~= "top" and node.titlePosition ~= "bottom"
                and node.titlePosition ~= "legend" then return fail("titlePosition", "invalid title position") end
            if node.titleAlign ~= nil and node.titleAlign ~= "start" and node.titleAlign ~= "center" then return fail("titleAlign", "invalid title alignment") end
            for _, field in ipairs({ "collapsible", "collapsed" }) do
                if node[field] ~= nil and type(node[field]) ~= "boolean" then return fail(field, "expected boolean") end
            end
            if node.collapsed and not node.collapsible then return fail("collapsed", "collapsed requires collapsible") end
            if node.help ~= nil and not Name(node.help) then return fail("help", "expected non-empty help") end
            if node.note ~= nil then
                if not styled then return fail("note", "note requires a page style") end
                ok, issue = SchemaReference(owner, "texts", node.note, path .. ".note", id)
                if not ok then return false, issue end
            end
        end
    elseif (kind == "control" or kind == "component") and (node.path ~= nil or node.controlType == "toggles") then
        if node.ref ~= nil or node.custom ~= nil then return fail("ref", "use ref or path") end
        if node.controlType == "toggles" then
            if node.path ~= nil then return fail("path", "toggles writes items[].path, not path") end
        elseif not Name(node.path) then return fail("path", "expected a non-empty path") end
        if kind == "control" then
            ok, issue = SchemaPathControl(node, path, id)
            if not ok then return false, issue end
        else
            if not StandardComponents[node.component] then return fail("component", "unknown standard component") end
            if node.label ~= nil and type(node.label) ~= "string" then return fail("label", "expected string") end
            if node.opts ~= nil and type(node.opts) ~= "table" then return fail("opts", "expected a plain table") end
            -- optionsRef names owner.options[ref]: runtime options (callbacks) merged over opts.
            if node.optionsRef ~= nil then
                if not Name(node.optionsRef) then return fail("optionsRef", "expected a named reference") end
                if owner then
                    local options = rawget(owner, "options")
                    if type(options) ~= "table" or type(rawget(options, node.optionsRef)) ~= "table" then
                        return fail("optionsRef", "missing options." .. node.optionsRef)
                    end
                end
            end
        end
        ok, issue = SchemaBinding(owner, path .. ".path", id)
        if not ok then return false, issue end
    elseif kind == "control" or kind == "component" then
        if not Name(node.ref) then return fail("ref", "reference required") end
        if node.custom ~= nil and not CustomParts[node.custom] then return fail("custom", "not in the Core custom list") end
        for _, field in ipairs(PathOnlyFields) do
            if node[field] ~= nil then return fail(field, "requires path") end
        end
        if kind == "control" and not ControlTypes[node.controlType] then return fail("controlType", "invalid control type") end
        if node.mode ~= nil and (node.controlType ~= "choice" or (node.mode ~= "single" and node.mode ~= "multiple")) then return fail("mode", "invalid choice mode") end
        if owner then
            local bucket = rawget(owner, kind == "control" and "controls" or "components")
            local adapter = type(bucket) == "table" and rawget(bucket, node.ref)
            if type(adapter) ~= "table" then return fail("ref", "missing owner adapter " .. node.ref) end
            for _, method in ipairs(kind == "control" and ControlMethods or AdapterMethods) do
                if type(rawget(adapter, method)) ~= "function" then return fail("ref", "adapter missing " .. method) end
            end
            for _, method in ipairs(AdapterMethods) do
                if rawget(adapter, method) ~= nil and type(rawget(adapter, method)) ~= "function" then return fail("ref", "invalid adapter " .. method) end
            end
        end
    elseif kind == "button" then
        if type(node.text) ~= "string" then return fail("text", "text required") end
        if (node.action ~= nil) == (node.clickKey ~= nil) then return fail("action", "use action or clickKey") end
        if node.clickKey ~= nil then
            if not Name(node.clickKey) then return fail("clickKey", "expected a non-empty key") end
            ok, issue = SchemaBinding(owner, path .. ".clickKey", id)
        else
            ok, issue = SchemaReference(owner, "actions", node.action, path .. ".action", id)
        end
        if not ok then return false, issue end
        if node.presentation ~= nil and node.presentation ~= "primary" and node.presentation ~= "secondary" and node.presentation ~= "danger" then return fail("presentation", "invalid button presentation") end
        if node.icon ~= nil then
            if not styled then return fail("icon", "icon requires a page style") end
            if not (type(node.icon) == "string" and _G.ExwindTools.GUIIcons.ids[node.icon]) then
                return fail("icon", "expected a registered GUIIcons id")
            end
            if node.text ~= "" then return fail("text", "icon button requires empty text") end
            if node.presentation ~= nil then return fail("presentation", "icon button has one appearance") end
        end
    elseif kind == "text" or kind == "hint" then
        if (node.text ~= nil) == (node.textSource ~= nil) then return fail("text", "use text or textSource") end
        if node.text ~= nil and type(node.text) ~= "string" then return fail("text", "expected string") end
        if node.textSource ~= nil then
            ok, issue = SchemaReference(owner, "texts", node.textSource, path .. ".textSource", id)
            if not ok then return false, issue end
        end
    elseif kind == "actions" then
        for _, field in ipairs({ "position", "align" }) do
            local value = node[field]
            if value ~= nil and value ~= "start" and value ~= "center" and value ~= "end" then return fail(field, "invalid alignment") end
        end
    elseif kind == "setting" then
        if not Name(node.label) then return fail("label", "label required") end
        if node.description ~= nil and type(node.description) ~= "string" then return fail("description", "expected string") end
        if node.toggle ~= nil and node.icon ~= nil then return fail("icon", "toggle and icon share the leading slot") end
        if node.help ~= nil then
            if not (styled and styled.helpIconSize) then return fail("help", "help requires a page style with helpIconSize") end
            if not Name(node.help) then return fail("help", "expected non-empty help") end
        end
        if node.toggle ~= nil then
            if not Name(node.toggle) then return fail("toggle", "expected a path") end
            ok, issue = SchemaBinding(owner, path .. ".toggle", id)
            if not ok then return false, issue end
        end
        if node.icon ~= nil and not ((type(node.icon) == "string" and _G.ExwindTools.GUIIcons.ids[node.icon])
            or (Number(node.icon) and node.icon % 1 == 0)) then
            return fail("icon", "expected a registered GUIIcons id or a texture file id")
        end
    elseif kind == "columns" or kind == "table" then
        if kind == "table" then
            if node.rowActions ~= nil then
                ok, issue = SchemaArray(node.rowActions, path .. ".rowActions", id)
                if not ok then return false, issue end
                for i, action in ipairs(node.rowActions) do
                    local at = path .. ".rowActions[" .. i .. "]"
                    ok, issue = SchemaKeys(action, "id text action enabled presentation", at, id)
                    if not ok then return false, issue end
                    if not Name(action.id) or ids[action.id] then return Issue(at .. ".id", "missing/duplicate node id", id) end
                    ids[action.id] = true
                    if type(action.text) ~= "string" then return Issue(at .. ".text", "text required", id) end
                    ok, issue = SchemaReference(owner, "actions", action.action, at .. ".action", id)
                    if ok and action.enabled ~= nil then ok, issue = SchemaReference(owner, "predicates", action.enabled, at .. ".enabled", id) end
                    if not ok then return false, issue end
                    if action.presentation ~= nil and action.presentation ~= "danger" then return Issue(at .. ".presentation", "expected danger", id) end
                end
            end
            if node.addAction ~= nil then
                local at = path .. ".addAction"
                ok, issue = SchemaKeys(node.addAction, "id text action clickKey input", at, id)
                if not ok then return false, issue end
                local add = node.addAction
                if not Name(add.id) or ids[add.id] then return Issue(at .. ".id", "missing/duplicate node id", id) end
                ids[add.id] = true
                if type(add.text) ~= "string" then return Issue(at .. ".text", "text required", id) end
                if (add.action ~= nil) == (add.clickKey ~= nil) then return Issue(at, "use action or clickKey", id) end
                if add.action ~= nil then ok, issue = SchemaReference(owner, "actions", add.action, at .. ".action", id)
                else ok, issue = SchemaBinding(owner, at .. ".clickKey", id) end
                if ok and add.input ~= nil and not (Name(add.input) and (owner == nil
                    or type(rawget(rawget(owner, "controls") or {}, add.input)) == "table")) then
                    ok, issue = Issue(at .. ".input", "missing controls." .. tostring(add.input), id)
                end
                if not ok then return false, issue end
            end
            if node.selected ~= nil then
                ok, issue = SchemaReference(owner, "predicates", node.selected, path .. ".selected", id)
                if not ok then return false, issue end
            end
        end
        ok, issue = SchemaArray(node.columns, path .. ".columns", id)
        if not ok then return false, issue end
        columnCount = issue
        if columnCount == 0 then return fail("columns", "empty columns") end
        for i, column in ipairs(node.columns) do
            local columnPath = path .. ".columns[" .. i .. "]"
            ok, issue = SchemaKeys(column, kind == "table" and "title width weight" or "width weight", columnPath, id)
            if not ok then return false, issue end
            if kind == "table" and type(column.title) ~= "string" then return Issue(columnPath, "table column title required", id) end
            if (column.width and column.weight) or (column.width ~= nil and not Number(column.width))
                or (column.weight ~= nil and not Number(column.weight)) then return Issue(columnPath, "invalid column width/weight", id) end
        end
    elseif kind == "repeat" then
        if depth >= 2 then return fail("template", "at most two nested repeats") end
        ok, issue = SchemaReference(owner, "sources", node.source, path .. ".source", id)
        if not ok then return false, issue end
        if type(node.template) ~= "table" then return fail("template", "template required") end
        if top and node.template.kind ~= "card" then return fail("template", "page repeat template must be card") end
        if columnCount and node.template.kind ~= "row" then return fail("template", "column repeat template must be row") end
        return ValidateNode(node.template, owner, ids, depth + 1, location, columnCount, path .. ".template", styled)
    end
    if kind == "row" and node.separator ~= nil and type(node.separator) ~= "boolean" then return fail("separator", "expected boolean") end
    if node.children ~= nil then
        ok, issue = SchemaArray(node.children, path .. ".children", id)
        if not ok then return false, issue end
        if kind == "row" and columnCount and issue ~= columnCount then return fail("children", "cell count differs from columns") end
        local actions = 0
        for i, child in ipairs(node.children) do
            local childPath = path .. ".children[" .. i .. "]"
            if type(child) ~= "table" then return Issue(childPath, "expected node", id) end
            if (kind == "columns" or kind == "table") and child.kind ~= "row" and child.kind ~= "repeat" then return Issue(childPath, kind .. " accepts row/repeat", id) end
            if kind == "row" and columnCount and child.kind ~= "cell" then return Issue(childPath, "expected cell", id) end
            if child.kind == "actions" then
                actions = actions + 1
                if actions > 1 or i ~= #node.children then return Issue(childPath, "actions must be unique and last", id) end
            end
            -- setting 右侧按横排处理：子节点与 row 内的流式项同规则。
            ok, issue = ValidateNode(child, owner, ids, depth, kind == "setting" and "row" or kind,
                (kind == "columns" or kind == "table" or kind == "row") and columnCount or nil, childPath, styled)
            if not ok then return false, issue end
        end
    elseif kind == "card" or kind == "group" or kind == "row" or kind == "cell" or kind == "actions" or kind == "columns"
        or kind == "setting" or kind == "table" then
        return fail("children", "children required")
    end
    return true
end

-- 普通页规则的第二道校验：只看结构与是否写了尺寸，字段合法性已由 ValidateNode 保证。
local function IsStandardAdapter(owner, node)
    if owner == nil then return true end -- 登记时还没有 owner，挂载时再查
    local bucket = rawget(owner, node.kind == "control" and "controls" or "components")
    local adapter = type(bucket) == "table" and rawget(bucket, node.ref)
    return type(adapter) == "table" and rawget(adapter, "_exStandard") == true
end

local function StrictNode(node, owner, parentKind, path, out, styled)
    local kind = node.kind
    local function fail(field, message)
        local _, issue = Issue(path .. (field and "." .. field or ""), message, node.id, "NOT_STANDARD")
        out[#out + 1] = issue
        return true
    end
    local allowed = StrictChildren[parentKind]
    if allowed and not allowed[kind] then
        return fail("kind", "普通页的 " .. parentKind .. " 里不能放 " .. tostring(kind) .. "（只允许标准行、表格、封装控件，或登记过的自定义）")
    end
    for _, field in ipairs(StrictSizeFields) do
        if node[field] ~= nil then fail(field, "普通页不准写尺寸；宽度用 size 档位，其余由 Core 决定"); break end
    end
    if kind == "card" then
        for _, field in ipairs(StrictCardFields) do
            if node[field] ~= nil then fail(field, "普通页卡片只有一种外观（标题在上）"); break end
        end
    elseif kind == "group" then
        if not styled then return fail("kind", "块（group）只用在写了 style 的普通页") end
        if node.title ~= "" then return fail("title", "块（group）不写标题，title 写空字串") end
    elseif kind == "control" or kind == "component" then
        if node.ref ~= nil and node.custom == nil and not IsStandardAdapter(owner, node) then
            return fail("ref", "自定义件必须写 custom=<Core 名单键>；标准控件用 CreateSettingsV2Control/Component 建")
        end
        if kind == "control" and node.path ~= nil then
            if node.controlType == "card" then return fail("controlType", "普通页不用大方块勾选；用开关或 toggles") end
            if node.controlType == "checkbox" and parentKind ~= "cell" then return fail("controlType", "勾选框只用在表格里；设置行用开关或 setting.toggle") end
        end
        if kind == "control" and node.ref ~= nil and node.custom == nil and node.controlType == "card" then
            return fail("controlType", "普通页不用大方块勾选；用开关或 toggles")
        end
        if parentKind == "setting" and node.label ~= nil then return fail("label", "设置行右侧控件不写 label") end
    elseif kind == "setting" then
        local controls = 0
        for _, child in ipairs(node.children or {}) do
            -- 单位文字（秒、%）与样式页的图标按钮（上移、下移、删除）不算控件
            if child.kind ~= "text" and not (child.kind == "button" and child.icon ~= nil) then controls = controls + 1 end
        end
        if controls > MaxSettingControls then fail("children", "设置行右侧最多 3 个控件") end
    elseif kind == "repeat" then
        return StrictNode(node.template, owner, parentKind, path .. ".template", out, styled)
    end
    for i, child in ipairs(node.children or {}) do
        StrictNode(child, owner, kind, path .. ".children[" .. i .. "]", out, styled)
    end
    return true
end

-- 普通页违规照样报 Lua 错误（游戏里弹出、测试工具记录），但不打断加载：
-- 一次能看到全部违规，它们就是迁移清单。同一条只报一次。
local ReportedStrict = {}
local function ReportStrict(where, issues)
    for _, issue in ipairs(issues or {}) do
        local message = "SettingsV2 普通页规则: " .. tostring(where) .. " " .. issue.path .. ": " .. issue.message
        if not ReportedStrict[message] then
            ReportedStrict[message] = true
            geterrorhandler()(message)
        end
    end
end

local function Validate(declaration, owner)
    local ok, issue = Pure(declaration, "page", {})
    if not ok then return false, issue end
    ok, issue = SchemaKeys(declaration, "version layout cards columns columnGap rowGap freeform style", "page")
    if not ok then return false, issue end
    if declaration.version ~= 2 then return Issue("page.version", "version must be 2") end
    -- style：可选页面样式，只能写 GM.settings.styles 登记的预设名；不写时一切照旧。
    if declaration.style ~= nil then
        if type(declaration.style) ~= "string" or type(GM.settings.styles[declaration.style]) ~= "table" then
            return Issue("page.style", "not a registered GM.settings.styles preset")
        end
    end
    if declaration.freeform ~= nil and not FreeformPages[declaration.freeform] then
        return Issue("page.freeform", "not in the Core freeform list", nil, "NOT_STANDARD")
    end
    if declaration.layout ~= nil and declaration.layout ~= "stack" and declaration.layout ~= "grid" then return Issue("page.layout", "invalid layout") end
    local grid = declaration.layout == "grid"
    if not grid and (declaration.columns or declaration.columnGap or declaration.rowGap) then
        return Issue("page.columns", "columns and gaps require grid layout")
    end
    if grid then
        ok, issue = SchemaArray(declaration.columns, "page.columns")
        if not ok then return false, issue end
        if #declaration.columns == 0 then return Issue("page.columns", "columns required") end
        for i, column in ipairs(declaration.columns) do
            local at = "page.columns[" .. i .. "]"
            ok, issue = SchemaKeys(column, "weight", at)
            if not ok then return false, issue end
            if not Number(column.weight) then return Issue(at .. ".weight", "positive finite weight required") end
        end
        for _, field in ipairs({ "columnGap", "rowGap" }) do
            if declaration[field] ~= nil and (not Finite(declaration[field]) or declaration[field] < 0) then
                return Issue("page." .. field, "expected a non-negative finite number")
            end
        end
    end
    if owner ~= nil and type(owner) ~= "table" then return Issue("owner", "owner must be a table", nil, "INVALID_ARGUMENT") end
    for _, name in ipairs({ "onHeightChanged", "onContentWidthChanged" }) do
        if owner and rawget(owner, name) ~= nil and type(rawget(owner, name)) ~= "function" then return Issue("owner." .. name, "expected callback", nil, "INVALID_ARGUMENT") end
    end
    ok, issue = SchemaArray(declaration.cards, "page.cards")
    if not ok then return false, issue end
    local ids, occupied = {}, {}
    for i, node in ipairs(declaration.cards) do
        ok, issue = ValidateNode(node, owner, ids, 0, "page", nil, "page.cards[" .. i .. "]",
            declaration.style and GM.settings.styles[declaration.style])
        if not ok then return false, issue end
        local at = "page.cards[" .. i .. "]"
        if grid then
            if node.kind ~= "card" or not node.row or not node.column then
                return Issue(at, "grid requires cards with row and column", node.id)
            end
            local last = node.column + (node.span or 1) - 1
            if last > #declaration.columns then return Issue(at .. ".span", "card exceeds page columns", node.id) end
            occupied[node.row] = occupied[node.row] or {}
            for column = node.column, last do
                if occupied[node.row][column] then return Issue(at, "overlapping cards", node.id) end
                occupied[node.row][column] = true
            end
        elseif node.row or node.column or node.span or node.gapBefore then
            return Issue(at, "row/column/span/gapBefore require grid layout", node.id)
        end
    end
    local strict = {}
    if declaration.freeform == nil then
        if declaration.columnGap ~= nil or declaration.rowGap ~= nil then
            local _, gapIssue = Issue("page.columnGap", "普通页不准写尺寸；列间距由 Core 决定", nil, "NOT_STANDARD")
            strict[#strict + 1] = gapIssue
        end
        for i, node in ipairs(declaration.cards) do
            StrictNode(node, owner, "page", "page.cards[" .. i .. "]", strict, declaration.style ~= nil)
        end
    end
    return true, nil, strict
end

function UI:ValidateSettingsDeclarationV2(declaration, owner)
    return Validate(declaration, owner)
end

function UI:RegisterSettingsPageV2(pageId, declaration)
    Check(Name(pageId) and Pages[pageId] == nil, "missing/duplicate page id")
    local ok, issue, strict = Validate(declaration)
    Check(ok, issue and (issue.path .. ": " .. issue.message))
    ReportStrict(pageId, strict)
    Pages[pageId] = DeclarationCopy(declaration, {})
end

-- 表格行：直接挂在 table 下，或挂在 table 下的 repeat 里。
local function TableOf(node)
    local parent = node.parent
    if parent and parent.spec.kind == "repeat" then parent = parent.parent end
    return parent and parent.spec.kind == "table" and parent or nil
end

local function Acquire(parent)
    local host = Factory:AcquireCompositeHost(POOL, parent)
    UI:ClearControlSurface(host)
    if host._v2Label then host._v2Label:Hide() end
    if host._v2SettingsSeparator then host._v2SettingsSeparator:Hide() end
    if host._v2RowHelp then host._v2RowHelp:Hide(); host._v2RowHelp._v2Text = nil end
    host:SetScript("OnMouseWheel", nil)
    host:EnableMouseWheel(false)
    host:SetSize(1, 1)
    host:Show()
    return host
end

-- Settings GUI lands on whole physical pixels (UI scale is usually fractional);
-- otherwise nine-slice surfaces such as switch knobs show their seams.
local function Place(frame, parent, x, y, width, height)
    frame:ClearAllPoints()
    PixelUtil.SetPoint(frame, "TOPLEFT", parent, "TOPLEFT", x, -y, 0, 0)
    PixelUtil.SetSize(frame, math.max(1, width), math.max(1, height), 1, 1)
    -- 页面显示前就改过尺寸的控件，游戏里不会补发 OnSizeChanged，外观底板会停在创建时的宽度；
    -- 摆放后按新尺寸重排一次。
    for _, skin in pairs(frame._exModernSurfaces or {}) do
        if skin.active == true and skin.Layout then skin.Layout() end
    end
end

local function Records(node)
    local records = node.session.owner.sources[node.spec.source](node.scope)
    Array(records, node.spec.id .. " source")
    local seen = {}
    for _, record in ipairs(records) do
        Check(type(record) == "table" and not seen[record], node.spec.id .. ": records must be unique original tables")
        seen[record] = true
    end
    return records
end

local function Current(node)
    if not node.alive or not node.session.alive or node.session.cleanupFailed then return false end
    local scope = node.scope
    while scope do
        local repeatNode = scope._repeatNode
        if not repeatNode.alive then return false end
        local records = Records(repeatNode)
        if records[scope.index] ~= scope.item then return false end
        scope = scope.parent
    end
    return true
end

local function Interactive(node)
    if not Current(node) or not node.session.root:IsVisible() then return false end
    while node do
        if node.visible == false or node.enabled == false then return false end
        if node.spec.kind == "card" and node.frame._exSettingsCardCollapsed then return false end
        node = node.parent
    end
    return true
end

local function Context(node)
    local generation = node.generation
    local function valid() return node.generation == generation and Current(node) end
    -- _exStyle：页面样式预设（没写 style 时为 nil），标准控件自建设置行时一并传给行。
    local ctx = { scope = node.scope, _exStyle = node.session.style }
    function ctx:IsCurrent() return valid() end
    function ctx:Guard(callback)
        Check(type(callback) == "function", "Guard expects a callback")
        return function(...)
            if valid() and Interactive(node) then return callback(...) end
        end
    end
    -- [决定] 测量世代：异步高度必须带上“测量它时使用的宽度”（measure 收到的 width）。
    -- 宽度与当前布局宽不一致（旧宽度的迟到报告）一律拒绝并返回 false；同步在 measure 内
    -- 返回高度的 owner 不需要调用。省略 width 表示 owner 保证它按当前宽度测量。
    function ctx:ReportHeight(height, requestedWidth)
        if not valid() then return false end
        Check(type(height) == "number" and height >= 0 and height < math.huge, "invalid reported height")
        Check(requestedWidth == nil or (type(requestedWidth) == "number" and requestedWidth == requestedWidth),
            "invalid reported width")
        if requestedWidth ~= nil and (node.width == nil or math.abs(node.width - requestedWidth) > 0.01) then
            return false
        end
        if node.reportedHeight ~= height then
            node.reportedHeight = height
            node.session:Invalidate()
        end
        return true
    end
    function ctx:Invalidate()
        if not valid() then return false end
        node.reportedHeight = nil
        node.session:Invalidate()
        return true
    end
    -- After a committed write: re-read every bound value and re-evaluate predicates.
    function ctx:RefreshPage()
        if not valid() then return false end
        node.session:Refresh()
        return true
    end
    -- 当前分配宽度（最近一次 measure 收到的 width）；尚未布局时为 nil。
    function ctx:GetRequestedWidth() return valid() and node.width or nil end
    return ctx
end

local function Text(node)
    local text = node.spec.text
    if node.spec.textSource then text = node.session.owner.texts[node.spec.textSource](node.scope) end
    Check(type(text) == "string", node.spec.id .. ": text source must return string")
    node.label:SetText(text)
end

-- Defaults operate on an existing EXUI control, never a value/configuration.
local ControlDefaults = {}
function ControlDefaults.update() end
function ControlDefaults.measure(widget, context, width)
    widget:SetWidth(width)
    return widget:GetHeight()
end
function ControlDefaults.layout(widget, context, width, height)
    Place(widget, widget:GetParent(), 0, 0, width, height)
end
function ControlDefaults.setEnabled(widget, context, enabled)
    local target = widget.checkbox or widget.editBox or widget
    if widget.SetDisabled then widget:SetDisabled(not enabled)
    elseif target.SetEnabled then target:SetEnabled(enabled)
    else Check(enabled, "control needs an owner setEnabled implementation") end
end
function ControlDefaults.setVisible(widget, context, visible)
    if not visible then
        if widget.CloseMenu then widget:CloseMenu() end
        local editBox = widget.editBox or widget
        if editBox.ClearFocus then editBox:ClearFocus() end
    end
    widget:SetShown(visible)
end

-- “?” 说明钮：卡片标题旁（help）与样式页设置行标签后（setting.help）共用这一种画法，悬停用 GameTooltip 显示 _v2Text。
local function HelpGlyph(parent, size)
    local help = CreateFrame("Button", nil, parent)
    help:SetSize(size, size)
    help.glyph = UI:CreateVisualFontString(help, _G.EXFONTFRAME, "GameFontHighlight")
    help.glyph:SetPoint("CENTER", 0, 1)
    help.glyph:SetText("?")
    UI.ControlAppearance.ApplyTextRole(help.glyph, "title", UI.ControlAppearance.colors.muted)
    help:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self._v2Text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    help:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return help
end

-- Card accessories live on the pooled card frame and are created once: a "?" beside the title
-- that shows `help` as a tooltip, and a hairline under a folded card's title.
local function CardAccessories(card)
    if card._v2Help then return end
    local header = card._exSettingsCardHeader
    local help = HelpGlyph(header, 22)
    card._v2Help = help
    local divider = header:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(unpack(UI.ControlAppearance.DungeonAura.line))
    card._v2CollapsedDivider = divider
end

-- 页面样式（session.style）的卡片附件，只在样式页第一次用到这张池化卡片时建：
-- 标题条底板（卡片的子 Frame，层级压在表头下面，表头悬停重画不会擦掉它）和右侧灰字。
local function StyleAccessories(card)
    if card._v2StyleBar then return end
    local bar = CreateFrame("Frame", nil, card)
    bar:EnableMouse(false)
    bar:Hide()
    card._v2StyleBar = bar
    local note = UI:CreateVisualFontString(card._exSettingsCardHeader, _G.EXFONTFRAME, "GameFontHighlightSmall")
    note:SetJustifyH("RIGHT")
    note:Hide()
    card._v2StyleNote = note
end

local STYLE_HELP_GAP = 4                -- 问号与标签文字的间距（与卡片标题旁的 ? 相同）

local function ControlAdapter(provider)
    return setmetatable({}, { __index=function(_, method) return rawget(provider, method) or ControlDefaults[method] end })
end

-- =========================================================
-- Standard binding layer
-- =========================================================
-- A binding addresses one value under a module DB root by a dot path; numeric
-- segments are numeric keys. Writes create missing intermediate tables, skip
-- equal values and notify through the single ValueController entry.
local Binding = {}
Binding.__index = Binding

function Binding:Read()
    local value = self.root
    for _, key in ipairs(self.segments) do
        if type(value) ~= "table" then return nil end
        value = value[key]
    end
    return value
end

function Binding:Parent(create)
    local parent = self.root
    for i = 1, #self.segments - 1 do
        local key = self.segments[i]
        local child = parent[key]
        if child == nil and create then
            child = {}
            parent[key] = child
        end
        if type(child) ~= "table" then
            Check(child == nil, self.path .. ": segment " .. tostring(key) .. " is not a table")
            return nil
        end
        parent = child
    end
    return parent
end

function Binding:Key()
    return self.segments[#self.segments]
end

function Binding:Notify(phase)
    UI:NotifyModuleValueChanged(self.moduleKey, self.path, phase == "live" and "changing" or "committed")
end

-- phase: "live" (dragging), "commit", or "silent" (no notification).
function Binding:Write(value, phase)
    local parent, key = self:Parent(true), self:Key()
    if parent[key] == value then return false end
    parent[key] = value
    if phase ~= "silent" then self:Notify(phase) end
    return true
end

local function CreateBinding(moduleKey, root, path)
    Check(Name(moduleKey), "binding requires moduleKey")
    Check(type(root) == "table", "binding requires a root table")
    Check(Name(path), "binding requires a path")
    local segments = {}
    for part in path:gmatch("[^%.]+") do segments[#segments + 1] = tonumber(part) or part end
    Check(#segments > 0, "binding requires a path")
    return setmetatable({ moduleKey=moduleKey, root=root, path=path, segments=segments,
        parentPath=path:match("^(.*)%.[^%.]+$") }, Binding)
end

local function ReleaseBoundWidget(widget)
    UI:RestoreSettingsListControl(widget)
    if widget._exGridOwnedControls then
        for index = #widget._exGridOwnedControls, 1, -1 do
            Factory:ReleaseGridWidget(widget._exGridOwnedControls[index])
            widget._exGridOwnedControls[index] = nil
        end
        widget._exGridOwnedControls = nil
    end
    if widget._isCompositeHost then
        Factory:ReleaseCompositeHost(widget)
    elseif widget._fromPool then
        Factory:Release(widget._fromPool, widget)
    else
        widget:Hide()
        widget:SetParent(nil)
    end
end

-- optionsSource names a global provider (resolved at every mount). A table result
-- is used as-is; a string result keeps the "value:display,..." inline form.
local function SelectItems(spec)
    if spec.options then
        local items = {}
        for i, option in ipairs(spec.options) do items[i] = { option.label, option.value } end
        return items
    end
    local provider = _G
    for part in spec.optionsSource:gmatch("[^%.]+") do
        provider = type(provider) == "table" and provider[part] or nil
    end
    Check(type(provider) == "function", "optionsSource is not a function: " .. spec.optionsSource)
    local data = provider()
    if type(data) == "table" then return data end
    local items = {}
    for entry in tostring(data or ""):gmatch("([^,]+)") do
        local value, display = entry:match("^([^:]+):(.+)$")
        items[#items + 1] = (value and not spec.multiple) and { display, value } or entry
    end
    return items
end

local function IsOrdinaryRowControl(widget)
    local kind = widget._gridType
    if kind == "GridInput" then return widget.IsMultiLine and not widget:IsMultiLine() end
    return kind == "GridDropdown" or kind == "GridLSMDropdown" or kind == "GridMultiselect"
        or kind == "GridColorButton" or kind == "GridSlider"
end

-- ChoiceGroup（choice/tristate/segment/toggles）按选项文字算出的自然宽。
local function ChoiceNaturalWidth(widget)
    if widget.NaturalWidth then return widget:NaturalWidth() end
    if not (widget.buttons and widget.minItemWidth) then return nil end
    -- The existing ChoiceGroup uses these label/icon insets and item gap.
    local width, rowWidth, count, maximum = 0, 0, 0, 0
    for _, button in ipairs(widget.buttons) do
        local itemWidth = math.max(widget.minItemWidth,
            button.label:GetUnboundedStringWidth() + (button._choiceItem.icon and GM.space.choiceIconItemPadX or GM.space.choiceItemPadX))
        maximum = math.max(maximum, itemWidth)
        if count > 0 then rowWidth = rowWidth + widget.gap end
        rowWidth, count = rowWidth + itemWidth, count + 1
        if widget.columns and count == widget.columns then
            width, rowWidth, count = math.max(width, rowWidth), 0, 0
        end
    end
    width = math.max(width, rowWidth)
    if widget.sizing ~= "content" then
        count = math.min(#widget.buttons, widget.columns or #widget.buttons)
        width = count * maximum + math.max(0, count - 1) * widget.gap
    end
    -- 轨道两侧内距，与 ExwindChoiceGroup 的 Layout 同一组数。
    local trackPad = (widget.choiceStyle == "segmented" and widget.mode == "single")
        and (widget.darkTrack and GM.space.segmentedDarkTrackPad or GM.space.segmentedTrackPad)
        or ((widget.choiceStyle == "segmented" or widget.choiceStyle == "connected") and GM.space.connectedTrackPad or 0)
    return math.max(1, width + trackPad * 2)
end

-- 样式页的单行控件高（预设 controlHeight）；没写样式或预设没写时取 GM.size.controlHeight。
local function StyledControlHeight(style)
    return style and style.controlHeight or GM.size.controlHeight
end

-- 样式页图标按钮（button.icon）的边长：预设 iconButtonSize，没写时取控件高。
local function IconButtonSize(style)
    return style and style.iconButtonSize or StyledControlHeight(style)
end

-- 控件宽度档位（size）：页面只能选档位，像素在 GM。
-- style（可选页面样式预设）：没写 size 的输入框、下拉用预设 controlWidth，size="short" 用预设 shortWidth；
-- 分段只有预设写了 segmentEqualWidth 才用 controlWidth（每段平分整列宽）。
local function SizeWidth(spec, style)
    if style then
        if spec.size == "short" and style.shortWidth then return style.shortWidth end
        if not spec.size and style.controlWidth and (spec.controlType == "input" or spec.controlType == "select"
            or (spec.controlType == "segment" and style.segmentEqualWidth)) then
            return style.controlWidth
        end
    end
    if spec.size == "short" then return GM.settings.controlShortWidth end
    if spec.size == "wide" then return GM.settings.controlWideWidth end
end

-- bindingFor(context) returns the binding of one mounted control.  A labelled
-- switch/input/select/slider/color is presented as a settings row: label and
-- description on the left, the control on the right, a divider between rows.
local function StandardControl(spec, bindingFor)
    local states = setmetatable({}, { __mode = "k" })
    local kind = spec.controlType
    local adapter = {}
    function adapter.mount(host, context)
        local binding = bindingFor(context)
        -- 样式页：单行控件高取预设 controlHeight；没写样式时为 nil，一律走原值。
        local style = context._exStyle
        local styledHeight = style and style.controlHeight
        local function Commit(value)
            if not context:IsCurrent() then return end
            binding:Write(value, "commit")
            context:RefreshPage()
        end
        local width, widget, fallback = GM.size.controlDefaultWidth, nil, nil
        local value = kind ~= "toggles" and binding:Read() or nil
        local search = { search = spec.search }
        if kind == "toggles" then
            -- binding 是每项一个的列表；勾掉全部也合法。
            local items, selection = {}, {}
            for i, item in ipairs(spec.items) do
                items[i] = { id = i, label = item.label }
                if binding[i]:Read() == true then selection[i] = true end
            end
            widget = UI:CreateToggleGroup(host, { items = items, value = selection, onChange = function(next)
                if not context:IsCurrent() then return end
                for i, itemBinding in ipairs(binding) do itemBinding:Write(next[i] == true, "commit") end
                context:RefreshPage()
            end })
        elseif kind == "multiline" then
            -- 输入时静默写入（不通知），离开焦点时提交通知；按钮读值时拿到的总是最新文字。
            widget = UI:CreateEditBox(host, value or "", width, spec.size == "tall" and GM.settings.multilineTallHeight
                or GM.settings.multilineHeight, nil, {
                onChanged = function(text, userInput)
                    if userInput and context:IsCurrent() then binding:Write(text, "silent") end
                end,
                onEditFocusLost = function(text)
                    if not context:IsCurrent() then return end
                    binding:Write(text, "silent")
                    binding:Notify("committed")
                end,
            })
        elseif kind == "segment" then
            local items = {}
            for i, option in ipairs(spec.options) do items[i] = { option.label, option.value } end
            -- 写了 allowEmpty 才传：值为空时不高亮任何一项；不写时参数与原来一样。
            local segmentOptions = (styledHeight or spec.allowEmpty) and
                { height = styledHeight, allowEmpty = spec.allowEmpty } or nil
            widget = UI:CreateSegmentedControl(host, width, items, value, Commit, segmentOptions)
            -- 给到的宽度放不下全部选项文字时，改用同一组选项的下拉（不截断文字）。
            fallback = UI:CreateDropdown(host, width, nil, items, value, Commit)
            UI:PrepareSettingsListControl(fallback, { ordinaryControl = true, hideLabel = true })
            fallback:Hide()
        elseif kind == "optionlist" then
            local items = {}
            for i, option in ipairs(spec.options) do
                items[i] = { id = option.value, label = option.label, description = option.description }
            end
            widget = UI:CreateOptionList(host, { items = items, value = value, width = width, onChange = Commit })
        elseif kind == "switch" or kind == "checkbox" or kind == "card" then
            widget = UI:CreateCheckbox(host, spec.label or "", value == true, function(checked) Commit(checked == true) end)
            if kind == "switch" and not spec.label then
                -- 设置行右侧的开关不带文字，宽度就是开关本身。
                UI:PrepareSettingsListControl(widget, { presentation = "switch", hideLabel = true })
                widget:SetSize(GM.size.switchTrackWidth, styledHeight or GM.size.controlHeight)
            end
        elseif kind == "slider" then
            widget = UI:CreateSlider(host, width, spec.label or "", spec.min or 0, spec.max or 100, value or 0,
                spec.step or 1, nil, {
                    onLive = function(live)
                        if context:IsCurrent() then binding:Write(live, "live") end
                    end,
                    onCommit = Commit,
                })
        elseif kind == "input" then
            -- 写了 placeholder 才有占位字（占位灰）；不写时与原来一样。
            widget = UI:CreateEditBox(host, value or "", width, styledHeight or GM.size.controlHeight, spec.label,
                { onEnter = Commit, onEditFocusLost = Commit,
                    placeholder = spec.placeholder, placeholderDim = spec.placeholder ~= nil or nil })
        elseif kind == "color" then
            -- 预设写了 colorWidth：不带 label 的颜色控件只画色块（swatchOnly），宽取 colorWidth。
            local swatch = style and style.colorWidth and not spec.label
            widget = UI:CreateColorButton(host, spec.label or "", binding:Parent(false) or binding.root, binding:Key(), true,
                function()
                    if not context:IsCurrent() then return end
                    binding:Notify("committed")
                    context:RefreshPage()
                end, swatch and { swatchOnly = true } or nil)
            if swatch then widget:SetWidth(style.colorWidth) end
        elseif spec.media == "font" then
            widget = UI:CreateLSMDropdown(host, "font", width, spec.label, value, Commit, search)
        elseif spec.media == "sound" then
            widget = UI:CreateLSMSoundDropdown(host, width, spec.label, value, Commit, search)
        elseif spec.media then
            widget = UI:CreateLSMTextureDropdown(host, spec.media, width, spec.label, value, Commit, search)
        elseif spec.multiple then
            if type(value) ~= "table" then
                value = {}
                binding:Write(value, "silent")
            end
            widget = UI:CreateMultiSelectDropdown(host, width, spec.label, SelectItems(spec), value, function()
                if not context:IsCurrent() then return end
                binding:Notify("committed")
                context:RefreshPage()
            end, search)
        else
            widget = UI:CreateDropdown(host, width, spec.label, SelectItems(spec), value, Commit, search)
        end
        -- 预设写了 overlayControls（设置条）：控件用浮层外观；对象池归还时标记自动清掉。
        if style and style.overlayControls then
            UI:SetControlOverlayAppearance(widget, true)
            if fallback then UI:SetControlOverlayAppearance(fallback, true) end
        end
        local state = { binding = binding, host = host, context = context, fallback = fallback,
            styledHeight = styledHeight }
        if spec.label and RowControlTypes[kind] then
            local ordinary = kind ~= "switch" and IsOrdinaryRowControl(widget)
            state.ordinary = ordinary
            state.valuePosition = kind == "slider" and "right" or nil
            -- 分段按选项文字定宽，档位控件按档位定宽；放不下时设置行自己转上下排，不压窄。
            local fixed
            if kind == "segment" and style and style.segmentEqualWidth and not spec.size then
                fixed = SizeWidth(spec, style) -- 样式页的平分分段占整列宽
            else
                fixed = (kind == "segment" or kind == "toggles") and ChoiceNaturalWidth(widget) or SizeWidth(spec, style)
            end
            local minWidth = fixed or (ordinary and (kind == "slider" and GM.size.settingsRowSliderMinWidth
                or GM.settings.controlMinWidth) or nil)
            -- 样式页按预设定宽的输入框、下拉、颜色，放不下时仍可收窄到 controlMinWidth。
            if style and ordinary and fixed and not spec.size then minWidth = math.min(fixed, GM.settings.controlMinWidth) end
            state.row = UI:CreateSettingsRow(host, {
                label = spec.label, description = spec.description,
                fullWidth = kind == "multiline" or kind == "optionlist", -- 多行文字、单选卡片：标签在上，控件占满整行
                controlKind = ordinary and "ordinary" or nil,
                controlWidth = fixed,
                controlMinWidth = minWidth,
                inputWidthPercent = spec.inputWidthPercent,
                style = context._exStyle,
            })
            UI:PrepareSettingsListControl(widget, {
                ordinaryControl = ordinary, hideLabel = true,
                presentation = kind == "switch" and "switch" or nil,
                valuePosition = state.valuePosition,
            })
            context._exSettingsRow = true
        end
        states[widget] = state
        return widget
    end
    function adapter.update(widget)
        if kind == "toggles" then
            local selection = {}
            for i, itemBinding in ipairs(states[widget].binding) do
                if itemBinding:Read() == true then selection[i] = true end
            end
            widget:SetValue(selection)
            return
        end
        local value = states[widget].binding:Read()
        if kind == "multiline" then
            if not widget.editBox:HasFocus() then widget.editBox:SetText(value == nil and "" or tostring(value)) end
        elseif kind == "segment" then
            widget:SetValue(value)
            UI:SetDropdownValue(states[widget].fallback, value)
        elseif kind == "optionlist" then
            widget:SetValue(value)
        elseif kind == "switch" or kind == "checkbox" or kind == "card" then
            widget:SetChecked(value == true)
            UI:ApplyControlAppearance(widget)
        elseif kind == "slider" then
            if tonumber(value) then widget:SetEXUIValue(tonumber(value), "silent") end
        elseif kind == "input" then
            if not widget:HasFocus() then widget:SetText(value == nil and "" or tostring(value)) end
        elseif kind == "color" then
            widget:UpdateColor()
        elseif spec.multiple then
            widget._selections = type(value) == "table" and value or {}
            widget:RefreshSelectionDisplay()
        else
            UI:SetDropdownValue(widget, value)
        end
    end
    function adapter.measure(widget, context, width)
        local state = states[widget]
        local row = state.row
        if kind == "multiline" then
            -- 文字区在滚动框里，宽度跟随外框（扣掉滚动留位）。
            widget.editBox:GetParent():SetWidth(math.max(1, width - GM.settings.multilineScrollReserve))
        end
        if not row then
            widget:SetWidth(width)
            if kind == "segment" then
                local natural = ChoiceNaturalWidth(widget)
                state.useFallback = natural ~= nil and width + 0.5 < natural
                if state.useFallback then
                    state.fallback:SetWidth(width)
                    return state.styledHeight or GM.size.controlHeight
                end
            end
            if kind == "optionlist" then
                -- 卡片高度随宽度换行变化：立即按新宽度排一次再读高度。
                local onSize = widget:GetScript("OnSizeChanged")
                if onSize then onSize(widget) end
            end
            if kind == "slider" or kind == "segment" or kind == "toggles" or kind == "multiline" or kind == "optionlist" then
                return widget:GetHeight()
            end
            return spec.height or state.styledHeight or GM.size.controlHeight
        end
        UI:SetSettingsRowLast(row, context._exRowLast ~= false)
        local height, x, y, controlWidth = UI:UpdateSettingsRowLayout(row, width, math.max(1, widget:GetHeight()), nil)
        -- 样式页的行左右内距取预设。
        local rowPaddingX = context._exStyle and context._exStyle.rowPaddingX or GM.settings.rowPaddingX
        if kind == "multiline" or kind == "optionlist" then
            -- 整行控件与标签左缘对齐，左右留行内边距。
            controlWidth = math.max(1, width - rowPaddingX * 2)
            if kind == "multiline" then
                widget.editBox:GetParent():SetWidth(math.max(1, controlWidth - GM.settings.multilineScrollReserve))
            end
        end
        widget:SetWidth(controlWidth)
        if kind == "optionlist" then
            local onSize = widget:GetScript("OnSizeChanged")
            if onSize then onSize(widget) end
        end
        if kind == "segment" then
            local natural = ChoiceNaturalWidth(widget)
            state.useFallback = natural ~= nil and controlWidth + 0.5 < natural
            if state.useFallback then
                state.fallback:SetWidth(controlWidth)
                -- 样式页：顶替分段的下拉也取预设控件高。
                if state.styledHeight then
                    UI:UpdateSettingsListControlLayout(state.fallback, controlWidth, state.styledHeight)
                end
            end
        end
        if state.ordinary or state.valuePosition then
            UI:UpdateSettingsListControlLayout(widget, controlWidth, state.styledHeight)
        end
        height, x, y = UI:UpdateSettingsRowLayout(row, width, math.max(1, widget:GetHeight()), nil)
        if kind == "multiline" or kind == "optionlist" then x = rowPaddingX end
        state.x, state.y = x, y
        return height
    end
    function adapter.layout(widget, context, width, height)
        local state = states[widget]
        -- 分段放不下时显示同一组选项的下拉，摆在分段原本的位置。
        local shown = state.useFallback and state.fallback or widget
        if state.fallback then
            widget:SetShown(not state.useFallback)
            state.fallback:SetShown(state.useFallback == true)
        end
        if not state.row then
            Place(shown, state.host, 0, 0, width, state.useFallback and (state.styledHeight or GM.size.controlHeight) or height)
            return
        end
        state.row:ClearAllPoints()
        state.row:SetPoint("TOPLEFT", state.host, "TOPLEFT", 0, 0)
        shown:ClearAllPoints()
        PixelUtil.SetPoint(shown, "TOPLEFT", state.row, "TOPLEFT", state.x, -state.y, 0, 0)
    end
    function adapter.release(widget, context)
        local state = states[widget]
        states[widget] = nil
        context._exSettingsRow, context._exRowLast = nil, nil
        ReleaseBoundWidget(widget)
        if state and state.fallback then ReleaseBoundWidget(state.fallback) end
        if state and state.row then state.row:Release() end
    end
    function adapter.setEnabled(widget, context, enabled)
        ControlDefaults.setEnabled(widget, context, enabled)
        local fallback = states[widget] and states[widget].fallback
        if fallback then ControlDefaults.setEnabled(fallback, context, enabled) end
    end
    function adapter.setVisible(widget, context, visible)
        local state = states[widget]
        if state and state.fallback then
            ControlDefaults.setVisible(state.fallback, context, visible and state.useFallback == true)
            ControlDefaults.setVisible(widget, context, visible and not state.useFallback)
            return
        end
        ControlDefaults.setVisible(widget, context, visible)
    end
    return adapter
end

local DEFAULT_FONT_GROUP = { font = "Friz Quadrata TT", size = 14, r = 1, g = 1, b = 1, a = 1,
    outline = "", shadow = false, x = 0, y = 0 }
local DEFAULT_TIMER_BAR_GROUP = { width = 240, height = 24, texture = "Clean",
    barColorR = 1, barColorG = 0.7, barColorB = 0, barColorA = 1,
    barBgColorR = 0, barBgColorG = 0, barBgColorB = 0, barBgColorA = 0.5,
    showIcon = true, iconSide = "LEFT", iconWidth = 24, iconHeight = 24, iconOffsetX = -5, iconOffsetY = 0 }

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

-- Composite groups bind exactly as the settings-section page did: `path` is the
-- section path plus the component key; opts.bindRoot / opts.bindValue keep
-- their meaning. Components inside a card render body-only.
local function StandardComponent(spec, bindingFor, runtimeOpts)
    local states = setmetatable({}, { __mode = "k" })
    local kind = spec.component
    local adapter = { component = kind }
    function adapter.mount(host, context)
        local binding = bindingFor(context)
        local opts = CopyTable(spec.opts)
        for key, value in pairs(runtimeOpts or {}) do opts[key] = value end
        if opts.bodyOnly == nil then opts.bodyOnly = true end
        if kind == "modulecommonsettings" then
            opts.presentation = opts.presentation or "settings-list"
            opts._exTypedSettings = true
        end
        local key, parentPath, root, fullPath = binding:Key(), binding.parentPath, binding.root, binding.path
        local scoped = parentPath and binding:Parent(false) or root
        local width = math.max(GM.size.controlDefaultWidth, host:GetWidth())
        local function Options(pathPrefix)
            local result = CopyTable(opts)
            result._exWriteContext = { moduleKey = binding.moduleKey, pathPrefix = pathPrefix }
            return result
        end
        local function Notifier(notifyPath)
            return function()
                UI:NotifyModuleValueChanged(binding.moduleKey, notifyPath, "committed")
                context:RefreshPage()
            end
        end
        local widget
        if kind == "fontgroup" then
            local value = binding:Read()
            if not value then
                value = CopyTable(DEFAULT_FONT_GROUP)
                binding:Write(value, "commit")
            end
            widget = UI:CreateFontGroup(host, width, spec.label, value, Notifier(fullPath), Options(fullPath))
        elseif kind == "glow_settings" then
            widget = UI:CreateGlowSettings(host, width, spec.label, scoped, key, Notifier(fullPath), Options(fullPath))
        elseif kind == "widgetlayout" then
            widget = UI:CreateWidgetLayoutGroup(host, width, spec.label, scoped, key, Notifier(fullPath), Options(fullPath))
        elseif kind == "soundgroup" then
            widget = UI:CreateSoundGroup(host, width, spec.label, scoped, key, Notifier(fullPath), Options(fullPath))
        elseif kind == "modulecommonsettings" then
            local bindKey = opts.bindRoot ~= true and key or nil
            local commonPath = bindKey and fullPath or (parentPath or "")
            widget = UI:CreateModuleCommonSettingsGroup(host, width, spec.label, scoped, bindKey,
                Notifier(commonPath), Options(commonPath))
        elseif kind == "anchorgroup" then
            local bindKey = opts.bindRoot ~= true and key or nil
            local anchorPath = bindKey and fullPath or (parentPath or "")
            widget = UI:CreateAnchorGroup(host, width, spec.label, scoped, bindKey, function(_, field)
                local changedPath = anchorPath ~= "" and (anchorPath .. "." .. field) or field
                UI:NotifyModuleValueChanged(binding.moduleKey, changedPath, "committed")
                context:RefreshPage()
            end, Options(anchorPath))
        elseif kind == "texturegroup" then
            local bindValue = opts.bindValue == true
            widget = UI:CreateTextureGroup(host, width, spec.label, bindValue and binding:Read() or scoped,
                not bindValue and key or nil, Notifier(fullPath), Options(fullPath))
        elseif kind == "icongroup" then
            local bindRoot, bindValue = opts.bindRoot == true, opts.bindValue == true
            local source = bindValue and binding:Read() or (bindRoot and root or scoped)
            local bindKey = (not bindRoot and not bindValue) and key or nil
            local iconPath = (bindValue or bindKey) and fullPath or (parentPath or "")
            widget = UI:CreateIconGroup(host, width, spec.label, source, bindKey, Notifier(iconPath), Options(iconPath))
        else -- timerbargroup
            local bindRoot = opts.bindRoot == true
            local value = bindRoot and root or binding:Read()
            if not value then
                value = CopyTable(DEFAULT_TIMER_BAR_GROUP)
                binding:Write(value, "commit")
            end
            local timerPath = bindRoot and (parentPath or "") or fullPath
            widget = UI:CreateTimerBarGroup(host, width, spec.label, value, nil, Notifier(timerPath), Options(timerPath))
        end
        states[widget] = { host = host, opts = opts, scoped = scoped,
            item = { type = kind, key = key, label = spec.label, opts = opts } }
        -- 锚点组本身就是一行设置行，与相邻设置行连成同一列表。
        if widget._exAnchorRow then context._exSettingsRow = true end
        return widget
    end
    function adapter.update(widget)
        UI:RefreshCompositeGroupFromDB(widget)
    end
    function adapter.measure(widget, context, width)
        local state = states[widget]
        if widget._exAnchorRow then UI:SetSettingsRowLast(widget._exAnchorRow, context._exRowLast ~= false) end
        local measured = UI:MeasureGridComponent(kind, width, state.opts, state.scoped, state.item)
        if type(measured) == "table" then
            local preferred = tonumber(measured.preferredHeight or measured.height)
            local minimum = tonumber(measured.minHeight)
            measured = preferred and minimum and math.max(preferred, minimum) or preferred or minimum
        end
        return tonumber(measured) or widget:GetHeight()
    end
    function adapter.layout(widget, context, width, height)
        Place(widget, states[widget].host, 0, 0, width, height)
        widget._exGridWidth = width
        UI:LayoutCompositeGroup(widget, width, height)
    end
    function adapter.release(widget, context)
        states[widget] = nil
        if widget._exAnchorRow then context._exSettingsRow, context._exRowLast = nil, nil end
        ReleaseBoundWidget(widget)
    end
    adapter.setEnabled, adapter.setVisible = ControlDefaults.setEnabled, ControlDefaults.setVisible
    return adapter
end

-- 连体声音选择：来源 | 内容（语音包 / LSM / 路径 / TTS）| ▶，用 Core 的 LayoutSoundSelector 拼成一段。
-- path 是字段前缀，读写 <path>Source / Label / LSM / Path / TtsText；挂载时不写任何默认值。
-- opts.sources = 可选来源（pack/lsm/file/tts，按顺序）；opts.labelSource = 语音包条目的全局 provider 名；
-- opts.test = ▶ 发出的 clickKey（<moduleKey>.ButtonClicked，播放仍由模块自己做）。
local SoundSources = { pack = "语音包", lsm = "LSM音效", file = "自定义路径", tts = "TTS语音" }
local SoundSuffix = { source = "Source", pack = "Label", lsm = "LSM", file = "Path", tts = "TtsText" }

local function SoundSelectorComponent(spec, bindingFor, runtimeOpts)
    local opts = spec.opts or {}
    Check(type(opts.sources) == "table" and #opts.sources > 0, spec.component .. ": opts.sources required")
    for _, source in ipairs(opts.sources) do Check(SoundSources[source] ~= nil, "unknown sound source " .. tostring(source)) end
    Check(opts.labelSource == nil or type(opts.labelSource) == "string", "opts.labelSource must be a provider name")
    Check(opts.test == nil or Name(opts.test), "opts.test must be a clickKey")
    local states = setmetatable({}, { __mode = "k" })
    local adapter = { component = spec.component }
    function adapter.mount(host, context)
        local base = bindingFor(context)
        local fields = {}
        for name, suffix in pairs(SoundSuffix) do fields[name] = CreateBinding(base.moduleKey, base.root, base.path .. suffix) end
        local widget = Acquire(host)
        local height, L = GM.size.controlHeight, _G.ExwindTools.L
        local function Commit(name)
            return function(value)
                if not context:IsCurrent() then return end
                fields[name]:Write(value, "commit")
                context:RefreshPage()
            end
        end
        local sourceItems = {}
        for i, source in ipairs(opts.sources) do sourceItems[i] = { L[SoundSources[source]], source } end
        local parts = {
            source = UI:CreateDropdown(widget, GM.size.controlDefaultWidth, nil, sourceItems, fields.source:Read(),
                Commit("source"), { widthFromOptions = true }),
            lsm = UI:CreateLSMSoundDropdown(widget, GM.size.controlDefaultWidth, nil, fields.lsm:Read(), Commit("lsm"), { search = true }),
            file = UI:CreateEditBox(widget, fields.file:Read() or "", GM.size.controlDefaultWidth, height, nil,
                { onEnter = Commit("file"), onEditFocusLost = Commit("file") }),
            tts = UI:CreateEditBox(widget, fields.tts:Read() or "", GM.size.controlDefaultWidth, height, nil,
                { onEnter = Commit("tts"), onEditFocusLost = Commit("tts") }),
        }
        if opts.labelSource then
            parts.pack = UI:CreateDropdown(widget, GM.size.controlDefaultWidth, nil, SelectItems({ optionsSource = opts.labelSource }),
                fields.pack:Read(), Commit("pack"), { search = true })
        end
        local sourceNatural = parts.source:GetWidth()
        local preview
        preview = UI:CreateButton(widget, height, height, "", function()
            if not context:IsCurrent() then return end
            -- optionsRef 给的 onTest(context, button) 优先：模块自己播放并显示播放状态。
            if runtimeOpts and runtimeOpts.onTest then return runtimeOpts.onTest(context, preview) end
            if not opts.test then return end
            _G.ExwindTools:UpdateState(base.moduleKey .. ".ButtonClicked", { key = opts.test, fullPath = base.path, ts = GetTime() })
        end, { compact = true })
        UI:ApplySoundPreviewAppearance(preview)
        for _, part in pairs(parts) do UI:PrepareSettingsListControl(part, { ordinaryControl = true, hideLabel = true }) end
        local contents = {}
        for _, source in ipairs(opts.sources) do contents[source] = parts[source] end
        widget:SetSize(GM.settings.soundSelectorWidth, height)
        states[widget] = { host = host, fields = fields, parts = parts, preview = preview, contents = contents,
            sourceNatural = sourceNatural, enabled = true }
        return widget
    end
    -- 来源字段为空或不在可选来源里（例如只有一个来源、存档本来就没有来源字段）时按第一个来源显示，不写存档。
    local function SourceOf(state)
        local value = state.fields.source:Read()
        return state.contents[value] and value or opts.sources[1]
    end
    local function Refresh(widget)
        local state = states[widget]
        UI:RefreshSoundSelector({ contents = state.contents, preview = state.preview,
            value = SourceOf(state), enabled = state.enabled,
            setUsable = function(control, usable) ControlDefaults.setEnabled(control, nil, usable) end })
    end
    function adapter.update(widget)
        local state = states[widget]
        UI:SetDropdownValue(state.parts.source, SourceOf(state))
        UI:SetDropdownValue(state.parts.lsm, state.fields.lsm:Read())
        if state.parts.pack then UI:SetDropdownValue(state.parts.pack, state.fields.pack:Read()) end
        for _, name in ipairs({ "file", "tts" }) do
            local box = state.parts[name]
            if not box:HasFocus() then box:SetText(state.fields[name]:Read() or "") end
        end
        Refresh(widget)
    end
    function adapter.measure() return GM.size.controlHeight end
    function adapter.layout(widget, context, width, height)
        local state = states[widget]
        Place(widget, state.host, 0, 0, width, height)
        -- 只有一个来源时不显示来源下拉，内容段从左缘开始。
        local single = #opts.sources == 1
        UI:LayoutSoundSelector(widget, { source = state.parts.source, preview = state.preview, contents = state.contents,
            left = 0, right = 0, top = 0, height = GM.size.controlHeight,
            sourceWidth = single and 1 or math.min(state.sourceNatural, width * GM.settings.soundSourceMaxRatio),
            previewWidth = GM.size.controlHeight,
            paintPreview = function(button) UI:ApplySoundPreviewAppearance(button) end })
        state.parts.source:SetShown(not single)
        Refresh(widget)
    end
    function adapter.setEnabled(widget, context, enabled)
        local state = states[widget]
        state.enabled = enabled
        ControlDefaults.setEnabled(state.parts.source, context, enabled)
        Refresh(widget)
    end
    adapter.setVisible = ControlDefaults.setVisible
    function adapter.release(widget)
        local state = states[widget]
        states[widget] = nil
        for _, part in pairs(state.parts) do ReleaseBoundWidget(part) end
        Factory:Release(state.preview._fromPool, state.preview)
        Factory:ReleaseCompositeHost(widget)
    end
    return adapter
end

local PathControlSpecFields = PathControlFields .. " height"

function UI:CreateSettingsV2Binding(moduleKey, root, path)
    return CreateBinding(moduleKey, root, path)
end

-- Owner helpers: the same standard controls for records and other owner data.
-- bindingFor(context) returns UI:CreateSettingsV2Binding(...) for that mount.
function UI:CreateSettingsV2Control(spec, bindingFor)
    local ok, issue = SchemaKeys(spec, PathControlSpecFields, "control")
    if ok then ok, issue = SchemaPathControl(spec, "control") end
    Check(ok, issue and (issue.path .. ": " .. issue.message))
    Check(type(bindingFor) == "function", "CreateSettingsV2Control requires bindingFor")
    Check(spec.controlType ~= "toggles", "toggles binds items[].path; declare it as a path node")
    local copy = DeclarationCopy(spec, {})
    local adapter = StandardControl(copy, bindingFor)
    adapter._exStandard = true
    adapter._exSpec = copy -- 样式页按它的 size 档位定自然宽（见 Natural）
    return adapter
end

-- runtimeOpts (optional) may carry callbacks; it is merged over spec.opts at mount.
function UI:CreateSettingsV2Component(spec, bindingFor, runtimeOpts)
    local ok, issue = SchemaKeys(spec, "component label opts", "component")
    Check(ok, issue and (issue.path .. ": " .. issue.message))
    Check(StandardComponents[spec.component], "unknown standard component " .. tostring(spec.component))
    Check(type(bindingFor) == "function", "CreateSettingsV2Component requires bindingFor")
    Check(runtimeOpts == nil or type(runtimeOpts) == "table", "runtimeOpts must be a table")
    local adapter = spec.component == "soundselector" and SoundSelectorComponent(DeclarationCopy(spec, {}), bindingFor, runtimeOpts)
        or StandardComponent(DeclarationCopy(spec, {}), bindingFor, runtimeOpts)
    adapter._exStandard = true
    return adapter
end

Build = function(session, spec, parentFrame, scope, parent)
    local node = { session=session, spec=spec, scope=scope, parent=parent, alive=true, generation=1, children={} }
    local list = parent and parent.children or session.nodes
    list[#list + 1] = node
    MountNode(node, parentFrame)
    return node
end

MountNode = function(node, parentFrame)
    local session, spec, scope = node.session, node.spec, node.scope
    node.alive = true
    if spec.kind == "card" then
        node.frame = UI:CreateSettingsCard(parentFrame, spec)
        UI:PrepareSettingsListCard(node.frame, {
            preserveHeader=true, externalCollapsible=spec.collapsible == true, collapsed=spec.collapsed,
        })
        CardAccessories(node.frame)
        if node.frame._v2BodyScroll then node.frame._v2BodyScroll:Hide() end
        if node.frame._v2LegendBacking then node.frame._v2LegendBacking:Hide() end
        if spec.titlePosition == "legend" then
            local colors = _G.ExwindTools.GUIColors
            UI:SetControlSurface(node.frame, GM.radius.card, colors.panel, colors.cardBorder)
            local surface = node.frame._exModernSurfaces and node.frame._exModernSurfaces[GM.radius.card]
            for _, piece in ipairs(surface and surface.pieces or {}) do piece.texture:SetAlpha(1) end
            UI:ClearControlSurface(node.frame:GetBody())
        end
        if spec.surface == "none" then
            UI:ClearControlSurface(node.frame)
            UI:ClearControlSurface(node.frame:GetBody())
            UI:ClearControlSurface(node.frame._exSettingsCardHeader)
        end
        node.frame._v2Help._v2Text = spec.help
        -- 样式附件每次借出都先收起；只有样式页再按预设画（清掉卡片与正文表面，标题区改画圆角条）。
        local card = node.frame
        if card._v2StyleBar then
            card._v2StyleBar:Hide()
            card._v2StyleNote:Hide()
            card._v2StyleNote:SetText("")
        end
        local style = session.style
        if style then
            StyleAccessories(card)
            UI:ClearControlSurface(card)
            UI:ClearControlSurface(card:GetBody())
            UI:ClearControlSurface(card._exSettingsCardHeader)
            UI:SetControlSurface(card._v2StyleBar, style.headerRadius, style.headerFill, _G.ExwindTools.GUIColors.transparent) -- 标题条不画边
            local colors = UI.ControlAppearance.colors
            card._exSettingsListExternalHeader.titleColor = style.headerText or colors.text
            card._exSettingsListExternalHeader.glyphColor = colors.text
            card._exSettingsCardPaintHeader()
        end
        if spec.bodyHeight then
            local scrollFrame = node.frame._v2BodyScroll
            if not scrollFrame then
                scrollFrame = UI:CreateScrollFrame(node.frame:GetBody())
                -- The native scroll child stays with this pooled card. Only the
                -- declaration content beneath it is leased and released.
                local content = CreateFrame("Frame", nil, scrollFrame)
                content:SetSize(1, 1)
                scrollFrame:SetScrollChild(content)
                scrollFrame._v2Content = content
                node.frame._v2BodyScroll = scrollFrame
            end
            node.scrollFrame = scrollFrame
            node.body = Acquire(scrollFrame._v2Content)
            node.body:SetPoint("TOPLEFT")
            node.body:SetPoint("TOPRIGHT")
            scrollFrame:SetVerticalScroll(0)
            scrollFrame:Show()
        else
            node.body = Acquire(node.frame:GetBody())
            PixelUtil.SetPoint(node.body, "TOPLEFT", node.frame:GetBody(), "TOPLEFT", PAD, -PAD, 0, 0)
            PixelUtil.SetPoint(node.body, "TOPRIGHT", node.frame:GetBody(), "TOPRIGHT", -PAD, -PAD, 0, 0)
        end
        node.headerPoints = {}
        for i = 1, node.frame._exSettingsCardHeader:GetNumPoints() do
            node.headerPoints[i] = { node.frame._exSettingsCardHeader:GetPoint(i) }
        end
        if spec.collapsible then
            node.toggleFont = { node.frame._exSettingsCardToggle._exGlyph:GetFont() }
            node.toggleSize = { node.frame._exSettingsCardToggle:GetSize() }
        end
        node.frame:SetLayoutInvalidationHandler(function(card)
            if spec.collapsible then
                card._exSettingsCardToggle._exGlyph:SetText(card._exSettingsCardCollapsed and "+" or "−")
            end
            session:Refresh()
        end)
    else
        node.frame = Acquire(parentFrame)
        node.body = node.frame
        if spec.kind == "setting" then
            -- 标签、说明与分隔线由共享设置行画；右侧子节点挂在独立的控件区里。
            local style = session.style
            node.settingRow = UI:CreateSettingsRow(node.frame, { label = spec.label, description = spec.description,
                lead = spec.toggle and "checkbox" or (spec.icon and "icon") or nil, icon = spec.icon, style = style,
                autoWidth = style and style.settingAutoWidth or nil, -- 预设 settingAutoWidth：setting 行文字列自适应
                trailingWidth = spec.help and (style.helpIconSize + STYLE_HELP_GAP) or nil })
            if spec.help then
                -- 标签后的小问号（校验保证只出现在样式页）；挂在本节点宿主上，宿主借出时 Acquire 会收起。
                if not node.frame._v2RowHelp then node.frame._v2RowHelp = HelpGlyph(node.frame, style.helpIconSize) end
                node.rowHelp = node.frame._v2RowHelp
                node.rowHelp:SetSize(style.helpIconSize, style.helpIconSize)
                node.rowHelp._v2Text = spec.help
                node.rowHelp:Show()
            end
            node.body = Acquire(node.frame)
            if spec.toggle then
                -- 勾选框写原有 enabled 字段；没勾时右侧控件由 RefreshNode 统一变灰。
                local binding = session.owner.binding
                node.toggleBinding = CreateBinding(binding.moduleKey, binding.config, spec.toggle)
                node.toggleBox = UI:CreateCheckbox(node.frame, "", node.toggleBinding:Read() == true, function(checked)
                    if not (node.context and node.context:IsCurrent()) then return end
                    node.toggleBinding:Write(checked == true, "commit")
                    node.context:RefreshPage()
                end)
                node.toggleBox:SetSize(GM.size.checkboxRowHeight, GM.size.checkboxRowHeight)
            end
        elseif spec.kind == "table" then
            node.tableHeader = UI:CreateSettingsTableHeader(node.frame, { columns = spec.columns })
        elseif spec.kind == "row" and TableOf(node) then
            node.tableRow = UI:CreateSettingsTableRow(node.frame, {})
        end
    end
    node.context = Context(node)
    -- 设置行与表格同属“设置列表”：铺满卡宽、相邻时不加间距，由行自己的分隔线隔开。
    if spec.kind == "setting" or spec.kind == "table" then node.context._exSettingsRow = true end
    -- 样式页的块（group）和每条记录一块的 repeat 也算设置列表：与相邻行之间不留间距，用行线隔开（见 Stack）。
    if session.style and (spec.kind == "group" or (spec.kind == "repeat" and spec.template.kind == "group")) then
        node.context._exSettingsRow = true
    end
    if spec.kind == "row" and spec.separator then
        if not node.frame._v2SettingsSeparator then
            node.frame._v2SettingsSeparator = UI:CreateSettingsSeparator(node.frame, 1)
        end
        node.separator = node.frame._v2SettingsSeparator
        node.separator:Show()
    end
    if spec.kind == "control" or spec.kind == "component" then
        if spec.path or spec.controlType == "toggles" then
            local binding = session.owner.binding
            local function BindingFor()
                if spec.controlType ~= "toggles" then return CreateBinding(binding.moduleKey, binding.config, spec.path) end
                local list = {}
                for i, item in ipairs(spec.items) do list[i] = CreateBinding(binding.moduleKey, binding.config, item.path) end
                return list
            end
            if spec.kind == "control" then node.adapter = StandardControl(spec, BindingFor)
            elseif spec.component == "soundselector" then
                node.adapter = SoundSelectorComponent(spec, BindingFor, spec.optionsRef and session.owner.options[spec.optionsRef])
            else node.adapter = StandardComponent(spec, BindingFor, spec.optionsRef and session.owner.options[spec.optionsRef]) end
        else
            local provider = (spec.kind == "control" and session.owner.controls or session.owner.components)[spec.ref]
            node.adapter = spec.kind == "control" and ControlAdapter(provider) or provider
        end
        node.mountPending = true
        node.instance = node.adapter.mount(node.frame, node.context, spec)
        Check(node.instance ~= nil, spec.id .. ": mount must return instance")
        node.mountPending = false
        -- Keep the owner's original GUI width, not the width assigned by a prior layout.
        node.naturalWidth = node.instance.GetWidth and node.instance:GetWidth() or nil
        if spec.kind == "control" then
            Check(node.instance.GetParent and node.instance:GetParent() == node.frame,
                spec.id .. ": return original control hosted in the supplied GUI host")
            if node.instance.SetPageScroll then node.instance:SetPageScroll() end
            if spec.mode then
                Check(node.instance.mode == spec.mode, spec.id .. ": original choice mode differs")
            end
            if spec.controlType == "card" then
                Check(node.instance.checkbox ~= nil, spec.id .. ": card requires existing Checkbox")
                UI:PrepareSettingsListControl(node.instance, { presentation="card", hideLabel=false })
            end
        end
    elseif spec.kind == "button" then
        local onClick
        if spec.clickKey then
            -- Same State contract the settings-section buttons published.
            local moduleKey = session.owner.binding.moduleKey
            onClick = function()
                _G.ExwindTools:UpdateState(moduleKey .. ".ButtonClicked",
                    { key = spec.clickKey, fullPath = spec.clickKey, ts = GetTime() })
            end
        else
            onClick = function(_, mouseButton) session.owner.actions[spec.action](node.context, mouseButton) end
        end
        if spec.icon then
            -- 样式页图标按钮：池化 CreateIconButton，只响应左键（与文字按钮相同）。
            -- 预设写了 iconButtonSize / iconButtonIconSize / iconButtonAppearance 就用它们，否则边长取控件高。
            local guarded = node.context:Guard(onClick)
            local style = session.style
            local size = IconButtonSize(style)
            node.button = UI:CreateIconButton(node.frame, size, size, { icon = spec.icon,
                iconSize = style.iconButtonIconSize, appearance = style.iconButtonAppearance,
                onClick = function(button, mouseButton)
                    if mouseButton == "LeftButton" then guarded(button, mouseButton) end
                end })
        else
            node.button = UI:CreateButton(node.frame, spec.width or GM.size.controlDefaultWidth,
                spec.height or GM.size.controlHeight, spec.text,
                node.context:Guard(onClick), { variant=spec.presentation or "secondary", compact=true })
        end
    elseif spec.kind == "text" or spec.kind == "hint" or spec.kind == "group" then
        if not node.frame._v2Label then
            node.frame._v2Label = UI:CreateVisualFontString(node.frame, _G.EXFONTFRAME, "GameFontHighlight")
        end
        node.label = node.frame._v2Label
        node.label:SetFontObject(spec.kind == "group" and "GameFontNormal" or "GameFontHighlight")
        node.label:SetJustifyH("LEFT")
        node.label:SetJustifyV("TOP")
        node.label:SetWordWrap(true)
        node.label:Show()
        local colors = UI.ControlAppearance.colors
        node.label:SetTextColor(unpack(spec.kind == "hint" and colors.muted or colors.text))
        if spec.kind == "group" then node.label:SetText(spec.title) else Text(node) end
    end
    if spec.kind ~= "repeat" then
        for _, child in ipairs(spec.children or {}) do Build(session, child, node.body, scope, node) end
    end
    return node
end

local function Retire(node)
    node.alive = false
    node.generation = (node.generation or 0) + 1
    for _, child in ipairs(node.children) do Retire(child) end
end

-- [决定] 释放必须“继续必要清理，最后报告原错”：任一节点的 owner.release 或清理步骤抛错，
-- 不得中断剩余节点与 root 回池；第一个错误被记录，清理全部完成后用原样重新抛出（对齐 V1 CardSession:Release）。
local function Capture(failures, ok, failure)
    if not ok and not failures.failed then failures.failed, failures.reason = true, failure end
end

local function Rethrow(failures)
    if failures.failed then error(failures.reason, 0) end
end

-- The existing protected release boundary is shared by nodes and overflow.
local function Cleanup(failures, callback, ...)
    Capture(failures, pcall(callback, ...))
end

ReleaseNode = function(node, failures)
    Retire(node)
    local own = {}
    if node.mountPending then Capture(own, false, "SettingsV2: incomplete adapter mount " .. node.spec.id) end
    for _, child in ipairs(node.children) do ReleaseNode(child, own) end
    node.children = {}
    if node.frame then Cleanup(own, node.frame.Hide, node.frame) end
    if node.adapter and node.instance ~= nil then
        if node.spec.kind == "control" and node.spec.controlType == "card" then
            Cleanup(own, UI.RestoreSettingsListControl, UI, node.instance)
        end
        Cleanup(own, node.adapter.release, node.instance, node.context)
    end
    if node.button and node.spec.icon then Cleanup(own, node.button.Release, node.button)
    elseif node.button then Cleanup(own, Factory.Release, Factory, node.button._fromPool, node.button) end
    if node.toggleBox then Cleanup(own, ReleaseBoundWidget, node.toggleBox) end
    if node.rowHelp then
        local help = node.rowHelp
        Cleanup(own, function() help:Hide(); help._v2Text = nil end)
    end
    if node.label then Cleanup(own, function() node.label:Hide(); node.label:SetText("") end) end
    for _, field in ipairs({ "settingRow", "tableHeader", "tableRow" }) do
        local decoration = node[field]
        if decoration then Cleanup(own, decoration.Release, decoration) end
    end
    if node.settingRow and node.body and not own.failed then Cleanup(own, Factory.ReleaseCompositeHost, Factory, node.body) end
    if node.frame and not own.failed then
        if node.spec.kind == "card" then
            local card = node.frame
            Cleanup(own, function()
                if node.scrollFrame then
                    node.scrollFrame:Hide()
                    node.scrollFrame:SetVerticalScroll(0)
                    node.scrollFrame._v2Content:SetSize(1, 1)
                end
                if card._v2LegendBacking then
                    card._v2LegendBacking:Hide()
                    card._v2LegendBacking:ClearAllPoints()
                end
                if card._v2StyleBar then
                    card._v2StyleBar:Hide()
                    card._v2StyleNote:Hide()
                    card._v2StyleNote:SetText("")
                end
                if card._v2Help then
                    card._v2Help:Hide()
                    card._v2Help._v2Text = nil
                    card._v2CollapsedDivider:Hide()
                end
                if node.toggleFont then
                    card._exSettingsCardToggle._exGlyph:SetFont(unpack(node.toggleFont))
                    card._exSettingsCardToggle:SetSize(unpack(node.toggleSize))
                end
                UI:RestoreSettingsListCard(card)
                if node.headerPoints and #node.headerPoints > 0 then
                    card._exSettingsCardHeader:ClearAllPoints()
                    for _, point in ipairs(node.headerPoints) do card._exSettingsCardHeader:SetPoint(unpack(point)) end
                end
            end)
            if not own.failed and node.body then Cleanup(own, Factory.ReleaseCompositeHost, Factory, node.body) end
            if not own.failed then Cleanup(own, card.Release, card) end
        else Cleanup(own, Factory.ReleaseCompositeHost, Factory, node.frame) end
    end
    -- A dirty ancestor is quarantined, never returned around a failed child.
    Capture(failures, not own.failed, own.reason)
    if own.failed then node.session.cleanupFailed, node.session.cleanupFailure = true, own.reason end
    node.mountPending = nil
    node.instance, node.frame, node.body, node.context, node.scrollFrame = nil, nil, nil, nil, nil
    node.adapter, node.button, node.label, node.separator = nil, nil, nil, nil
    node.width, node.reportedHeight, node.naturalWidth = nil, nil, nil
    node.headerPoints, node.toggleFont, node.toggleSize = nil, nil, nil
    node.settingRow, node.tableHeader, node.tableRow = nil, nil, nil
    node.toggleBox, node.toggleBinding, node.rowHelp = nil, nil, nil
end

local function SyncRepeat(node)
    local records = Records(node)
    local changed = #records ~= #node.children
    if not changed then
        for i, child in ipairs(node.children) do
            if child.scope.item ~= records[i] then changed = true; break end
        end
    end
    if not changed then return end
    -- No index-based reuse: reset only this repeat region, preserving other nodes.
    local failures = {}
    for _, child in ipairs(node.children) do Retire(child) end
    for _, child in ipairs(node.children) do ReleaseNode(child, failures) end
    node.children = {}
    -- 旧成员清理出错：区域保持为空（下次 Refresh 会重建），先报告原错，不在脏状态上继续建新成员。
    Rethrow(failures)
    for i, record in ipairs(records) do
        local scope = { item=record, index=i, parent=node.scope, _repeatNode=node }
        Build(node.session, node.spec.template, node.body, scope, node)
    end
end

local function Predicate(node, field)
    local ref = node.spec[field]
    if not ref then return true end
    local result = node.session.owner.predicates[ref](node.scope)
    Check(type(result) == "boolean", node.spec.id .. ": predicate must return ordinary boolean")
    return result
end

-- 样式标题条右侧灰字：写了 note 显示 owner.texts[note]()；没写显示“N 项”
-- （可见的直接子节点数，repeat 按展开后的成员计，折叠不影响计数）。空字串不显示。
local function StyleNote(node)
    local text
    if node.spec.note then
        text = node.session.owner.texts[node.spec.note](node.scope)
        Check(type(text) == "string", node.spec.id .. ": note text must return string")
    else
        local count = 0
        for _, child in ipairs(node.children) do
            if child.spec.kind == "repeat" then
                if Predicate(child, "visible") then
                    for _, member in ipairs(child.children) do
                        if Predicate(member, "visible") then count = count + 1 end
                    end
                end
            elseif Predicate(child, "visible") then
                count = count + 1
            end
        end
        text = string.format(_G.ExwindTools.L["%d 项"], count)
    end
    local note = node.frame._v2StyleNote
    note:SetText(text)
    note:SetShown(text ~= "" and node.session.style.showHeader ~= false)
end

RefreshNode = function(node, parentVisible, parentEnabled)
    node.visible = parentVisible and Predicate(node, "visible")
    node.enabled = parentEnabled and Predicate(node, "enabled")
    node.managesEnabled = node.spec.enabled ~= nil or (node.parent and node.parent.managesEnabled)
    node.frame:SetShown(node.visible)
    if node.spec.kind == "repeat" then SyncRepeat(node) end
    if node.adapter then
        node.reportedHeight = nil
        node.adapter.update(node.instance, node.context, node.spec)
        if node.managesEnabled then node.adapter.setEnabled(node.instance, node.context, node.enabled) end
        node.adapter.setVisible(node.instance, node.context, node.visible)
    elseif node.button then
        node.button:SetEnabled(node.enabled)
    elseif node.spec.kind == "text" or node.spec.kind == "hint" then Text(node) end
    local childrenEnabled = node.enabled
    if node.toggleBox then
        -- 勾选标签行：勾选框跟随本行可用状态，右侧控件只在勾上时可用。
        local checked = node.toggleBinding:Read() == true
        node.toggleBox:SetChecked(checked)
        UI:ApplyControlAppearance(node.toggleBox)
        ControlDefaults.setEnabled(node.toggleBox, node.context, node.enabled)
        childrenEnabled = node.enabled and checked
        node.managesEnabled = true
    end
    if node.spec.kind == "card" and node.spec.titleSource then
        node.frame._exSettingsCardTitle:SetText(node.session.owner.texts[node.spec.titleSource](node.scope))
    end
    local childrenVisible = node.visible and not (node.spec.kind == "card" and node.frame._exSettingsCardCollapsed)
    for _, child in ipairs(node.children) do RefreshNode(child, childrenVisible, childrenEnabled) end
    if node.spec.kind == "card" and node.session.style then StyleNote(node) end
end

local function HideNode(node)
    node.visible = false
    if node.frame then node.frame:Hide() end
    if node.adapter then node.adapter.setVisible(node.instance, node.context, false) end
    for _, child in ipairs(node.children) do HideNode(child) end
end

local function Align(value, spare)
    if value == "end" then return math.max(0, spare) end
    if value == "center" then return math.max(0, spare) / 2 end
    return 0
end

local function ButtonTextWidth(node)
    local label = node.button and node.button.GetFontString and node.button:GetFontString()
    return math.ceil(label and label:GetUnboundedStringWidth() or 0) + GM.space.buttonPaddingX * 2
end

local function Natural(node)
    local kind = node.spec.kind
    -- 声明的宽度只是下限：按钮文字放不下时撑宽，不压窄。
    if node.spec.width then
        return kind == "button" and math.max(node.spec.width, ButtonTextWidth(node)) or node.spec.width
    end
    if kind == "button" then
        -- 记录表格的行操作按钮（Core 展开时标记 _compact）只按文字宽。
        if node.spec._compact then return ButtonTextWidth(node) end
        -- 没有文字的按钮是图标按钮（如 ▶ 试听），宽 = 高（样式页取预设控件高；写了 icon 的取预设图标按钮边长）。
        if node.spec.icon then return IconButtonSize(node.session.style) end
        if node.spec.text == "" then return StyledControlHeight(node.session.style) end
        return math.max(GM.size.buttonMinWidth, ButtonTextWidth(node))
    end
    if kind == "text" or kind == "hint" then
        return math.max(1, node.label:GetUnboundedStringWidth())
    end
    local controlType = kind == "control" and node.spec.controlType
    local style = node.session.style
    -- 样式页的平分分段占预设整列宽，不按文字自然宽。
    if style and controlType == "segment" and style.segmentEqualWidth and SizeWidth(node.spec, style) then
        return SizeWidth(node.spec, style)
    end
    if controlType == "choice" or controlType == "tristate" or controlType == "segment" or controlType == "toggles" then
        local width = ChoiceNaturalWidth(node.instance)
        if width then return width end
    end
    if kind == "control" and SizeWidth(node.spec, style) then return SizeWidth(node.spec, style) end
    -- 预设写了 colorWidth：不带 label 的颜色控件（path 或记录控件）只画色块，宽取 colorWidth。
    if style and style.colorWidth and controlType == "color" then
        local colorSpec = node.adapter and node.adapter._exSpec or node.spec
        if not colorSpec.label then return style.colorWidth end
    end
    -- 样式页的记录控件（owner 用 CreateSettingsV2Control 建）：owner 写了 size 档位就按档位宽（预设 shortWidth 等）。
    local ownerSpec = style and kind == "control" and node.adapter and node.adapter._exSpec
    if ownerSpec and ownerSpec.size and SizeWidth(ownerSpec, style) then return SizeWidth(ownerSpec, style) end
    -- Bound card checkboxes are as wide as their title (same metrics as the settings list);
    -- owner cards keep the width their owner gave them.
    if kind == "control" and node.spec.controlType == "card" and node.spec.path then
        local card = node.instance.checkbox._exSettingsCardSurface
        if card then
            return 14 + (node.instance._exSettingsCardIcon and 24 or 0)
                + math.ceil(card.Title:GetUnboundedStringWidth()) + 30
        end
    end
    -- The owner's original control width is its natural size. Explicit DSL
    -- widths still take precedence above; do not force every control to 160.
    if node.adapter then
        return math.max(kind == "control" and GM.size.buttonMinWidth or 1, node.naturalWidth or 0)
    end
    if kind == "columns" or kind == "table" then
        local width = 0
        for _, column in ipairs(node.spec.columns) do width = width + (column.width or 160) + GAP end
        return math.max(1, width - GAP)
    end
    if node.spec.children or kind == "repeat" then
        local width, count = 0, 0
        local horizontal = kind == "row" or kind == "actions" or kind == "setting"
        for _, child in ipairs(node.children) do
            if child.visible then
                local childWidth = Natural(child)
                if horizontal then
                    width = width + childWidth + (count > 0 and GAP or 0)
                else width = math.max(width, childWidth) end
                count = count + 1
            end
        end
        if kind == "group" and node.spec.title ~= "" then
            width = math.max(width, node.label:GetUnboundedStringWidth())
        end
        if kind == "card" then
            -- [WEB-REQ 03/64-67] 卡片自然宽是“外宽”：内容自然宽 + 自身左右 padding（LayoutNode 会再扣一次 PAD*2），
            -- 并不小于标题（含折叠钮/帮助钮）所需宽度；否则无显式 width 的卡内容会被二次挤窄。
            local spec, title = node.spec, node.frame._exSettingsCardTitle
            local titleWidth = title and title:GetUnboundedStringWidth() or 0
            if spec.titleAlign == "center" then titleWidth = titleWidth + 8
            else titleWidth = titleWidth + (spec.collapsible and 36 or 0) + (spec.help and 26 or 0) end
            return math.max(1, width + PAD * 2, titleWidth)
        end
        return math.max(1, width)
    end
    return 160
end

local function Flexible(node)
    if node.spec.width then return false end
    local kind = node.spec.kind
    return node.spec.weight ~= nil or kind == "group" or kind == "row" or kind == "actions"
        or kind == "columns" or kind == "repeat" or kind == "component" or kind == "hint"
        or kind == "setting" or kind == "table"
        or (kind == "control" and (node.spec.controlType == "choice" or node.spec.controlType == "multiline"))
end

local function Grow(node)
    if node.spec.width then return 0 end
    if node.spec.weight then return node.spec.weight end
    local kind = node.spec.kind
    -- Action regions keep their requested placement; their child containers may grow.
    if kind == "group" or kind == "row" or kind == "columns" or kind == "repeat"
        or kind == "component" or kind == "hint" or kind == "setting" or kind == "table" then return 1 end
    return 0
end

local function IsSettingsRow(node)
    return node ~= nil and node.context ~= nil and node.context._exSettingsRow == true
end

-- 设置行规格（GM.settings）：设置卡片左右内边距统一 16，卡内所有内容左缘对齐。
-- 设置行与自带左右内边距的组合控件铺满卡片宽度，由它们自己的 16 内边距对齐同一左缘。
local SETTINGS = GM.settings
local BleedComponents = { fontgroup=true, icongroup=true, timerbargroup=true, modulecommonsettings=true, widgetlayout=true,
    glow_settings=true }

local function IsSettingsCard(node)
    return node.spec.kind == "card" and not node.spec.bodyHeight
end

local function Bleeds(node)
    return IsSettingsRow(node) or (node.spec.kind == "component" and BleedComponents[node.spec.component] == true)
end

-- 返回卡片正文的左右、上、下内边距：只有设置行的边用 cardPaddingY，使单行卡 = 8 + 52 + 8 = 68。
local function CardPadding(node)
    -- 样式页：行左右不留白、行线通栏，标题条到第一行取预设（G3 为 0），卡片底不留白。
    local style = node.session.style
    if style then return 0, style.headerToFirstRow or 0, 0 end
    if not IsSettingsCard(node) then return PAD, PAD, PAD end
    local first, last
    for _, child in ipairs(node.children) do
        if child.visible then
            first = first or child
            last = child
        end
    end
    -- 铺满卡宽的组合控件（模块通用设置、字体组等）自带上下留白，首尾留白与设置行相同。
    local function RowEdge(child)
        return child ~= nil and Bleeds(child)
    end
    return SETTINGS.cardPaddingX, RowEdge(first) and SETTINGS.cardPaddingY or PAD,
        RowEdge(last) and SETTINGS.cardPaddingY or PAD
end

local function Stack(node, width, columns, offset)
    local y = offset or 0
    local visible = {}
    for _, child in ipairs(node.children) do
        if child.visible then visible[#visible + 1] = child end
    end
    local style = node.session.style
    -- 样式页卡片正文没有左右内距，设置行不用外伸。
    local bleed = (IsSettingsCard(node) and not style) and SETTINGS.cardPaddingX or 0
    -- 样式页的块（group）：块内行之间不画线；块与只放块的 repeat 的最后一项沿用自己“是不是最后”，
    -- 于是块与块、块与前后行之间各一条线。
    local block = style and node.spec.kind == "group"
    local passThrough = style and IsSettingsRow(node) and (block or node.spec.kind == "repeat")
    for index, child in ipairs(visible) do
        local previous, nextChild = visible[index - 1], visible[index + 1]
        child.hideTrailingSeparator = node.spec.kind == "repeat" and nextChild == nil
        -- Consecutive settings rows form one list: no gap, divider only between rows.
        local row = IsSettingsRow(child)
        if row then
            if passThrough and nextChild == nil then child.context._exRowLast = node.context._exRowLast ~= false
            elseif block then child.context._exRowLast = true
            else child.context._exRowLast = not IsSettingsRow(nextChild) end
        end
        if previous and not (row and IsSettingsRow(previous)) then
            -- 卡片与卡片之间按 SettingsCardSpacing；其余节点保持原间距。
            -- 样式页：组与组之间取预设 groupGap。
            y = y + ((child.spec.kind == "card" and previous.spec.kind == "card")
                and (style and style.groupGap or SETTINGS.cardGap) or GAP)
        end
        local inset = Bleeds(child) and bleed or 0
        local height = LayoutNode(child, width + inset * 2, columns)
        Place(child.frame, node.body, -inset, y, width + inset * 2, height)
        y = y + height
    end
    return y
end

local function ColumnWidths(specs, width)
    local gap = math.min(GAP, width / (#specs * 2))
    local room = math.max(1, width - gap * (#specs - 1))
    local fixed, weight, flexible = 0, 0, 0
    for _, spec in ipairs(specs) do
        if spec.width then fixed = fixed + spec.width
        else weight = weight + (spec.weight or 1); flexible = flexible + 1 end
    end
    local fixedBudget = room - flexible * math.min(80, room / #specs)
    local scale = fixed > fixedBudget and fixedBudget / fixed or 1
    local widths = { gap=gap }
    for i, spec in ipairs(specs) do
        widths[i] = spec.width and spec.width * scale
            or math.max(1, room - fixed * scale) * (spec.weight or 1) / math.max(1, weight)
    end
    return widths
end

-- 设置行控件区的最小宽：输入框、下拉、颜色（未选档位）可收窄到 controlMinWidth，
-- 其余控件（分段、多选、按钮等）按自然宽，不压窄。
local SHRINKABLE_CONTROLS = { input=true, select=true, color=true }

local function Flow(node, width)
    local lines, line, used = {}, {}, 0
    local style = node.session.style
    for _, child in ipairs(node.children) do
        if child.visible then
            -- 非弹性项按自然宽占位：本行放不下就整项挪到下一行，不压窄。
            -- 自然宽超过整行时只能给满整行，按钮文字随之换行增高（见 LayoutNode）。
            local wanted = math.min(width, Natural(child))
            if child.spec.kind == "actions" and not child.spec.width then
                wanted = math.min(width, math.max(wanted, width * 0.55))
            end
            local minimum = Flexible(child) and math.min(wanted, 160) or wanted
            if style then
                -- 样式页不守 160：弹性项和未选档位的输入框、下拉、颜色都可收窄到 controlMinWidth。
                local spec = child.spec
                local shrink = Flexible(child)
                    or (spec.kind == "control" and SHRINKABLE_CONTROLS[spec.controlType] and not spec.size)
                minimum = shrink and math.min(wanted, GM.settings.controlMinWidth) or wanted
            end
            -- 0.01 容差：自然宽（逐项相加）与这里的累计宽浮点舍入顺序不同，刚好排满的一行不能因 1ulp 误差而换行。
            if #line > 0 and used + GAP + minimum > width + 0.01 then
                lines[#lines + 1], line, used = line, {}, 0
            end
            if #line > 0 then used = used + GAP end
            line[#line + 1] = { node=child, width=minimum, preferred=wanted }
            used = used + minimum
        end
    end
    if #line > 0 then lines[#lines + 1] = line end
    local y = 0
    for _, entries in ipairs(lines) do
        local occupied, demand, weight, height = GAP * (#entries - 1), 0, 0, 0
        for _, entry in ipairs(entries) do
            occupied = occupied + entry.width
            demand = demand + entry.preferred - entry.width
            weight = weight + Grow(entry.node)
        end
        local available = math.max(0, width - occupied)
        local preferredSpace = math.min(available, demand)
        local extra = available - preferredSpace
        local x = Align(node.spec.align, weight == 0 and extra or 0)
        for _, entry in ipairs(entries) do
            local child = entry.node
            local childWidth = entry.width
                + (demand > 0 and preferredSpace * (entry.preferred - entry.width) / demand or 0)
                + (weight > 0 and extra * Grow(child) / weight or 0)
            -- Position the actions region independently of its internal alignment.
            if child.spec.kind == "actions" and weight == 0 then
                local free = math.max(0, width - x - childWidth)
                x = x + Align(child.spec.position, free)
            end
            entry.x, entry.width = x, childWidth
            entry.height = LayoutNode(child, childWidth)
            height = math.max(height, entry.height)
            x = x + childWidth + GAP
        end
        for _, entry in ipairs(entries) do
            Place(entry.node.frame, node.body, entry.x, y + (height - entry.height) / 2, entry.width, entry.height)
        end
        y = y + height + GAP
    end
    return math.max(0, y - GAP)
end

-- 表格列宽：声明了 width/weight 照用；没声明的按该列第一个控件定（沿用旧版表格规则：
-- 勾选/开关 64、按钮 96 起、其余按权重 1 分剩余宽）。
local TABLE_SWITCH_WIDTH, TABLE_BUTTON_WIDTH = 64, 96

local function TableRows(node)
    local rows = {}
    for _, child in ipairs(node.children) do
        if child.spec.kind == "repeat" then
            for _, row in ipairs(child.children) do rows[#rows + 1] = row end
        else rows[#rows + 1] = child end
    end
    return rows
end

local function TableColumns(node)
    local rows = TableRows(node)
    local columns = {}
    for i, column in ipairs(node.spec.columns) do
        local resolved = { title = column.title, width = column.width, weight = column.weight }
        if column.actions then
            -- Core 追加的操作列：按最宽一行按钮的自然宽定宽。
            local widest = 0
            for _, row in ipairs(rows) do
                local cell = row.children[i]
                local line = cell and cell.children[1]
                if line then widest = math.max(widest, Natural(line)) end
            end
            resolved.width = widest + GM.settings.tableCellPadX * 2
        elseif not column.width and not column.weight then
            -- 取该列第一个控件或按钮（跳过空白占位文字）决定列宽。
            local leaf
            for _, row in ipairs(rows) do
                local cell = row.children[i]
                local candidate = cell and cell.children[1]
                local candidateKind = candidate and candidate.spec.kind
                if candidateKind == "control" or candidateKind == "button" then leaf = candidate; break end
            end
            local kind = leaf and leaf.spec.kind
            local controlType = leaf and leaf.spec.controlType
            if kind == "control" and (controlType == "switch" or controlType == "checkbox" or controlType == "card") then
                resolved.width = TABLE_SWITCH_WIDTH
            elseif kind == "button" then
                resolved.width = math.max(TABLE_BUTTON_WIDTH, Natural(leaf) + 8)
            else
                resolved.weight = 1
            end
        end
        columns[i] = resolved
    end
    return columns
end

-- 一个表格行：每格按列宽排，行高至少 48，格内控件垂直居中，行间分隔线由共享表格行画。
local function LayoutTableRow(row, width, rects, isLast)
    local metrics = {}
    for i, cell in ipairs(row.children) do
        local cellWidth = math.max(1, rects[i].width - 8)
        metrics[i] = { visible = cell.visible, height = cell.visible and LayoutNode(cell, cellWidth) or 0 }
    end
    row.tableRow._exSettingsTableIsLast = isLast
    local height, cellRects = UI:UpdateSettingsTableRowLayout(row.tableRow, width, rects, metrics)
    row.tableRow:ClearAllPoints()
    row.tableRow:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, 0)
    for i, cell in ipairs(row.children) do
        if cell.visible then
            local rect = cellRects[i]
            Place(cell.frame, row.body, rect.x, rect.y, rect.width, metrics[i].height)
        end
    end
    if row.separator then row.separator:Hide() end
    row.frame:SetSize(math.max(1, width), math.max(1, height))
    -- 记录表格的当前行高亮（table.selected 判断）。
    local tableNode = TableOf(row)
    if tableNode and tableNode.spec.selected and row.parent.spec.kind == "repeat"
        and Predicate({ spec = { id = row.spec.id, selected = tableNode.spec.selected }, session = row.session, scope = row.scope }, "selected") then
        local colors = _G.ExwindTools.GUIColors
        UI:SetControlSurface(row.frame, GM.radius.control, colors.optionRowSelected, colors.optionRowSelectedBorder)
    else
        UI:ClearControlSurface(row.frame)
    end
    return height
end

local function LayoutTable(node, width)
    node.tableHeader._exSettingsTableColumns = TableColumns(node)
    local headerHeight, rects = UI:UpdateSettingsTableHeaderLayout(node.tableHeader, width)
    node.tableHeader:ClearAllPoints()
    node.tableHeader:SetPoint("TOPLEFT", node.frame, "TOPLEFT", 0, 0)
    local visible = {}
    for _, row in ipairs(TableRows(node)) do
        if row.visible then visible[#visible + 1] = row end
    end
    local last = visible[#visible]
    local y = headerHeight
    for _, child in ipairs(node.children) do
        if child.visible then
            if child.spec.kind == "repeat" then
                local inner = 0
                for _, row in ipairs(child.children) do
                    if row.visible then
                        local height = LayoutTableRow(row, width, rects, row == last)
                        Place(row.frame, child.body, 0, inner, width, height)
                        inner = inner + height
                    end
                end
                Place(child.frame, node.body, 0, y, width, inner)
                y = y + inner
            else
                local height = LayoutTableRow(child, width, rects, child == last)
                Place(child.frame, node.body, 0, y, width, height)
                y = y + height
            end
        end
    end
    return y
end

-- 设置行：左标签（可带说明）右控件区；控件区按子节点自然宽占位，放不下时设置行自己转为上下排列。
local function SettingMinWidth(node)
    local width, count = 0, 0
    for _, child in ipairs(node.children) do
        if child.visible then
            local spec = child.spec
            local childWidth = Natural(child)
            if spec.kind == "control" and SHRINKABLE_CONTROLS[spec.controlType] and not spec.size then
                childWidth = math.min(childWidth, GM.settings.controlMinWidth)
            end
            width, count = width + childWidth + (count > 0 and GAP or 0), count + 1
        end
    end
    return math.max(1, width)
end

local function LayoutSetting(node, width)
    local row = node.settingRow
    UI:SetSettingsRowLast(row, node.context._exRowLast ~= false)
    -- 控件区按自然宽请求；放不下时先收窄标签列（不小于窄版文字宽），再把输入框/下拉收窄到最小宽，
    -- 仍放不下才上标签、下控件。
    row._exSettingsRowControlWidth = math.max(1, Natural(node))
    row._exSettingsRowMinControlWidth = SettingMinWidth(node)
    local _, _, _, controlWidth = UI:UpdateSettingsRowLayout(row, width, StyledControlHeight(node.session.style))
    local controlHeight = math.max(1, Flow(node, controlWidth))
    local height, x, y, _, _, leadX, leadTop = UI:UpdateSettingsRowLayout(row, width, controlHeight)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", node.frame, "TOPLEFT", 0, 0)
    if node.rowHelp then
        -- 小问号紧跟标签文字第一行；行已为它在文字列里留出位置（trailingWidth）。
        local title = row._exSettingsRowTitle
        local lineHeight = select(2, title:GetFont()) or node.session.style.helpIconSize
        local textWidth = math.min(math.ceil(title:GetUnboundedStringWidth()), title:GetWidth())
        -- 标签靠右（定宽标签列）时文字右缘就是标签列右缘。
        if title:GetJustifyH() == "RIGHT" then textWidth = title:GetWidth() end
        node.rowHelp:ClearAllPoints()
        node.rowHelp:SetPoint("LEFT", title, "TOPLEFT", textWidth + STYLE_HELP_GAP, -lineHeight / 2)
    end
    Place(node.body, node.frame, x, y, controlWidth, controlHeight)
    if node.toggleBox then
        -- 勾选框容器比方框大一圈，方框居中；让方框左上角落在行给出的位置。
        local inset = (GM.size.checkboxRowHeight - GM.size.checkboxBoxSize) / 2
        Place(node.toggleBox, node.frame, leadX - inset, leadTop - inset,
            GM.size.checkboxRowHeight, GM.size.checkboxRowHeight)
    end
    return height
end

-- 样式页的卡片（G3+H1）：整条圆角标题条，左折叠号、组名，最右灰字；条和第一行之间不留白；
-- 标题条（连同点击区）左右各外伸预设 headerOutset，比下面的行宽；预设 showHeader=false 时不画标题条。原有卡片算法（节标题上移、sectionHeaderBottom）不经过这里。
local function LayoutStyledCard(node, width)
    local style, card = node.session.style, node.frame
    local padX, padTop, padBottom = CardPadding(node)
    local scrollInset = node.scrollFrame and node.scrollFrame:GetVerticalScrollInset() or 0
    local innerWidth = math.max(1, width - padX * 2 - scrollInset)
    local height = math.max(node.spec.minBodyHeight or 0, Stack(node, innerWidth))
    if not node.scrollFrame then
        node.body:ClearAllPoints()
        PixelUtil.SetPoint(node.body, "TOPLEFT", card:GetBody(), "TOPLEFT", padX, -padTop, 0, 0)
        PixelUtil.SetPoint(node.body, "TOPRIGHT", card:GetBody(), "TOPRIGHT", -padX, -padTop, 0, 0)
    end
    node.body:SetHeight(math.max(1, height))
    local header, title, toggle = card._exSettingsCardHeader, card._exSettingsCardTitle, card._exSettingsCardToggle
    local bar, note, help = card._v2StyleBar, card._v2StyleNote, card._v2Help
    local collapsible = node.spec.collapsible == true
    local showHeader = style.showHeader ~= false and ((title:GetText() or "") ~= "" or collapsible)
    card._v2CollapsedDivider:Hide()
    help:SetShown(showHeader and node.spec.help ~= nil)
    local headerHeight, outset = 0, showHeader and style.headerOutset or 0
    if showHeader then
        local colors = UI.ControlAppearance.colors
        local x = style.headerPaddingLeft
        if collapsible then
            toggle:ClearAllPoints()
            toggle:SetPoint("LEFT", header, "LEFT", x, 0)
            toggle:SetSize(style.foldWidth, style.headerHeight)
            UI.ControlAppearance.Font(toggle._exGlyph, style.headerFont, colors.text, "", "GameFontHighlight")
            toggle._exGlyph:SetText(card._exSettingsCardCollapsed and "+" or "−")
            x = x + style.foldWidth + style.foldNameGap
        end
        UI.ControlAppearance.Font(title, style.headerFont, style.headerText or colors.text, "", "GameFontHighlight")
        UI.ControlAppearance.Font(note, style.noteFont, colors.muted, "", "GameFontHighlightSmall")
        local noteWidth = note:IsShown() and math.ceil(note:GetUnboundedStringWidth()) or 0
        local helpWidth = node.spec.help and (help:GetWidth() + STYLE_HELP_GAP) or 0
        local room = width + outset * 2 - x - style.headerPaddingRight - helpWidth - (noteWidth > 0 and noteWidth + GAP or 0)
        -- 组名放不下就换行，标题条随行数增高（不截断）。
        title:SetWordWrap(true)
        title:SetJustifyH("LEFT")
        title:SetJustifyV("MIDDLE")
        title:SetWidth(math.max(1, math.min(math.ceil(title:GetUnboundedStringWidth()) + 1, room)))
        headerHeight = math.max(style.headerHeight,
            math.ceil(title:GetStringHeight()) + style.headerHeight - style.headerFont)
        title:ClearAllPoints()
        title:SetPoint("LEFT", header, "LEFT", x, 0)
        note:ClearAllPoints()
        note:SetPoint("RIGHT", header, "RIGHT", -style.headerPaddingRight, 0)
        if node.spec.help then
            help:ClearAllPoints()
            help:SetPoint("LEFT", title, "RIGHT", STYLE_HELP_GAP, 0)
        end
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", header, "TOPLEFT")
        bar:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")
        bar:SetFrameLevel(math.max(card:GetFrameLevel(), header:GetFrameLevel() - 1))
    end
    bar:SetShown(showHeader)
    card._exSettingsListExternalHeader.height = headerHeight
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", card, "TOPLEFT", -outset, 0)
    header:SetPoint("TOPRIGHT", card, "TOPRIGHT", outset, 0)
    header:SetHeight(math.max(1, headerHeight))
    header:SetShown(showHeader)
    card:GetBody():ClearAllPoints()
    PixelUtil.SetPoint(card:GetBody(), "TOPLEFT", card, "TOPLEFT", 0, -headerHeight, 0, 0)
    PixelUtil.SetPoint(card:GetBody(), "TOPRIGHT", card, "TOPRIGHT", 0, -headerHeight, 0, 0)
    card:SetContentHeight((node.spec.bodyHeight or height) + padTop + padBottom)
    if node.scrollFrame then
        local scrollFrame = node.scrollFrame
        Place(scrollFrame, card:GetBody(), padX, padTop, innerWidth, node.spec.bodyHeight)
        scrollFrame._v2Content:SetSize(innerWidth, math.max(1, height))
        scrollFrame:UpdateScrollChildRect()
        scrollFrame:SetVerticalScroll(math.max(0, math.min(scrollFrame:GetVerticalScroll(),
            scrollFrame:GetVerticalScrollRange())))
        scrollFrame:SetShown(not card._exSettingsCardCollapsed)
    end
    return card:GetPreferredHeight()
end

LayoutNode = function(node, width, columns)
    width = math.max(1, width)
    node.frame:SetWidth(width)
    local kind, height = node.spec.kind, 0
    if node.adapter then
        if node.width ~= width then node.reportedHeight = nil end
        node.width = width
        local measured = node.adapter.measure(node.instance, node.context, width)
        -- Default single-line controls share one height. Owner measurements
        -- still describe multiline/custom content and explicit size contracts.
        local controlType = node.spec.controlType
        if node.adapter.measure == ControlDefaults.measure
            and (controlType == "input" or controlType == "checkbox" or controlType == "card"
                or controlType == "select" or controlType == "color") then
            measured = node.spec.height or StyledControlHeight(node.session.style)
        end
        Check(type(measured) == "number" and measured >= 0 and measured < math.huge, node.spec.id .. ": invalid measure")
        height = math.max(node.spec.height or 0, node.reportedHeight or measured)
        node.adapter.layout(node.instance, node.context, width, height)
    elseif node.button then
        height = node.spec.height or (node.spec.icon and IconButtonSize(node.session.style))
            or StyledControlHeight(node.session.style)
        Place(node.button, node.frame, 0, 0, width, height)
        -- 给不到文字所需宽度时换行并增高，不出省略号（图标按钮没有文字）。
        local label = not node.spec.icon and node.button:GetFontString()
        if label and ButtonTextWidth(node) > width + 0.5 then
            label:SetWordWrap(true)
            local wrapped = math.ceil(label:GetStringHeight()) + GM.space.buttonPaddingY * 2
            if wrapped > height then
                height = wrapped
                Place(node.button, node.frame, 0, 0, width, height)
            end
        end
    elseif kind == "text" or kind == "hint" then
        node.label:ClearAllPoints()
        node.label:SetPoint("TOPLEFT")
        node.label:SetWidth(width)
        height = math.max(node.spec.height or 0, node.label:GetStringHeight())
    elseif kind == "setting" then
        height = LayoutSetting(node, width)
    elseif kind == "table" then
        height = LayoutTable(node, width)
    elseif kind == "row" and columns then
        local x, heights = 0, {}
        for i, child in ipairs(node.children) do
            heights[i] = child.visible and LayoutNode(child, columns[i]) or 0
            height = math.max(height, heights[i])
        end
        for i, child in ipairs(node.children) do
            Place(child.frame, node.body, x, (height - heights[i]) / 2, columns[i], heights[i])
            x = x + columns[i] + columns.gap
        end
    elseif kind == "row" or kind == "actions" then
        height = Flow(node, width)
    elseif kind == "card" and node.session.style then
        return LayoutStyledCard(node, width)
    elseif kind == "card" then
        local padX, padTop, padBottom = CardPadding(node)
        local scrollInset = node.scrollFrame and node.scrollFrame:GetVerticalScrollInset() or 0
        local innerWidth = math.max(1, width - padX * 2 - scrollInset)
        height = math.max(node.spec.minBodyHeight or 0, Stack(node, innerWidth))
        if not node.scrollFrame then
            node.body:ClearAllPoints()
            PixelUtil.SetPoint(node.body, "TOPLEFT", node.frame:GetBody(), "TOPLEFT", padX, -padTop, 0, 0)
            PixelUtil.SetPoint(node.body, "TOPRIGHT", node.frame:GetBody(), "TOPRIGHT", -padX, -padTop, 0, 0)
        end
        node.body:SetHeight(math.max(1, height))
        local card, title = node.frame, node.frame._exSettingsCardTitle
        -- 下置标题：用小号说明字，页脚更矮；titleAlign="center" 让它居中。
        local caption = node.spec.titlePosition == "bottom"
        local legend = node.spec.titlePosition == "legend"
        -- 设置卡片的上置标题即节标题：离上方卡片远（30）、离下方卡片近（6），字号 BodyStrong。
        local section = not caption and not legend and IsSettingsCard(node)
        local captionTop, captionBottom = 5, 7
        local titleTop = section and (SETTINGS.sectionHeaderTop - SETTINGS.cardGap) or (caption and captionTop or 8)
        if caption then UI.ControlAppearance.ApplyTextRole(title, "hint") end
        if section then UI.ControlAppearance.ApplyTextRole(title, "settingsSection") end
        if legend then
            UI.ControlAppearance.ApplyTextRole(title, "cardTitle")
            title:SetJustifyV("TOP")
        end
        -- 标题放不下一律换行，表头随行数增高。
        title:SetWordWrap(true)
        title:ClearAllPoints()
        local legendExtra = 0
        if legend then
            local inset = GM.space.exboss.contentPaddingX
            local titleWidth = math.max(1, math.min(math.ceil(title:GetUnboundedStringWidth()) + 2,
                width - inset * 2 - (node.spec.collapsible and 36 or 0)))
            -- 首行骑在上边框（与单行时位置相同），多出的行向下排，正文随之下移。
            local lineHeight = select(2, title:GetFont()) or 0
            title:SetWidth(titleWidth)
            legendExtra = math.max(0, math.ceil(title:GetStringHeight() - lineHeight))
            if node.spec.titleAlign == "center" then
                title:SetPoint("TOP", card._exSettingsCardHeader, "TOP", 0, lineHeight / 2)
                title:SetJustifyH("CENTER")
            else
                title:SetPoint("TOPLEFT", card._exSettingsCardHeader, "TOPLEFT", inset, lineHeight / 2)
                title:SetJustifyH("LEFT")
            end
            if not card._v2LegendBacking then
                card._v2LegendBacking = UI:CreateVisualTexture(card._exSettingsCardHeader, _G.EXBASEFRAME)
            end
            local backing = card._v2LegendBacking
            backing:ClearAllPoints()
            backing:SetPoint("CENTER", title, "TOP", 0, -lineHeight / 2)
            backing:SetSize(titleWidth + 12,
                PixelUtil.GetNearestPixelSize(2, card._exSettingsCardHeader:GetEffectiveScale(), 1))
            backing:SetColorTexture(unpack(_G.ExwindTools.GUIColors.panel))
            backing:SetShown(node.spec.surface ~= "none" and node.spec.title ~= "")
        elseif node.spec.titleAlign == "center" then
            title:SetPoint("TOP", card._exSettingsCardHeader, "TOP", 0, -titleTop)
            title:SetWidth(math.max(1, width - 8))
            title:SetJustifyH("CENTER")
        else
            title:SetPoint("TOPLEFT", card._exSettingsCardHeader, "TOPLEFT", 0, -titleTop)
            title:SetWidth(math.max(1, math.min(title:GetUnboundedStringWidth(), width - (node.spec.collapsible and 36 or 0))))
        end
        if node.spec.collapsible then
            local toggle = card._exSettingsCardToggle
            toggle:ClearAllPoints()
            toggle:SetPoint("LEFT", title, "RIGHT", 8, 0)
            toggle:SetSize(28, 28)
            UI.ControlAppearance.ApplyTextRole(toggle._exGlyph, "pageTitle")
            toggle._exGlyph:SetText(card._exSettingsCardCollapsed and "+" or "−")
        end
        local help, divider = card._v2Help, card._v2CollapsedDivider
        help:SetShown(node.spec.help ~= nil)
        if node.spec.help then
            help:ClearAllPoints()
            help:SetPoint("LEFT", node.spec.collapsible and card._exSettingsCardToggle or title, "RIGHT", 4, 0)
        end
        divider:ClearAllPoints()
        divider:SetPoint("BOTTOMLEFT", card._exSettingsCardHeader, "BOTTOMLEFT", 12, 0)
        divider:SetPoint("BOTTOMRIGHT", card._exSettingsCardHeader, "BOTTOMRIGHT", -12, 0)
        divider:SetHeight(1)
        divider:SetShown(node.spec.collapsible == true and card._exSettingsCardCollapsed == true)
        local hasHeader = (title:GetText() or "") ~= "" or node.spec.collapsible == true
        -- Legend titles straddle the border: the frame stays 24px tall so its
        -- center + 12 lands on the top edge; the body retains the original 13px inset.
        local headerHeight = hasHeader and (legend and (13 + legendExtra)
            or (titleTop + title:GetStringHeight() + (section and SETTINGS.sectionHeaderBottom or (caption and captionBottom or 18)))) or 0
        card._exSettingsListExternalHeader.height = headerHeight
        card._exSettingsCardHeader:SetShown(hasHeader)
        card._exSettingsCardHeader:SetHeight(math.max(1, legend and PAD * 2 or headerHeight))
        card:GetBody():ClearAllPoints()
        PixelUtil.SetPoint(card:GetBody(), "TOPLEFT", card, "TOPLEFT", 0, -headerHeight, 0, 0)
        PixelUtil.SetPoint(card:GetBody(), "TOPRIGHT", card, "TOPRIGHT", 0, -headerHeight, 0, 0)
        node.frame:SetContentHeight((node.spec.bodyHeight or height) + padTop + padBottom)
        if node.spec.titlePosition == "bottom" then
            card:GetBody():ClearAllPoints()
            card:GetBody():SetPoint("TOPLEFT", card, "TOPLEFT")
            card:GetBody():SetPoint("TOPRIGHT", card, "TOPRIGHT")
            card._exSettingsCardHeader:ClearAllPoints()
            card._exSettingsCardHeader:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT")
            card._exSettingsCardHeader:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT")
        else
            card._exSettingsCardHeader:ClearAllPoints()
            card._exSettingsCardHeader:SetPoint("TOPLEFT", card, "TOPLEFT")
            card._exSettingsCardHeader:SetPoint("TOPRIGHT", card, "TOPRIGHT")
        end
        if node.scrollFrame then
            local scrollFrame = node.scrollFrame
            Place(scrollFrame, card:GetBody(), PAD, PAD, innerWidth, node.spec.bodyHeight)
            scrollFrame._v2Content:SetSize(innerWidth, math.max(1, height))
            scrollFrame:UpdateScrollChildRect()
            scrollFrame:SetVerticalScroll(math.max(0, math.min(scrollFrame:GetVerticalScroll(),
                scrollFrame:GetVerticalScrollRange())))
            scrollFrame:SetShown(not card._exSettingsCardCollapsed)
        end
        return node.frame:GetPreferredHeight()
    elseif kind == "columns" then
        height = Stack(node, width, ColumnWidths(node.spec.columns, width))
    elseif kind == "group" then
        node.label:ClearAllPoints()
        node.label:SetPoint("TOPLEFT")
        node.label:SetWidth(width)
        local hasTitle = node.spec.title ~= ""
        node.label:SetShown(hasTitle)
        height = Stack(node, width, nil, hasTitle and (node.label:GetStringHeight() + GAP) or 0)
    else
        height = Stack(node, width, columns)
    end
    if node.separator then
        node.separator:SetShown(not node.hideTrailingSeparator)
        if not node.hideTrailingSeparator then
            node.separator:ClearAllPoints()
            node.separator:SetPoint("TOPLEFT", node.frame, "TOPLEFT", 0, -(height + GAP / 2))
            node.separator:SetWidth(width)
            height = height + GAP
        end
    end
    node.frame:SetHeight(math.max(1, height))
    return height
end

-- Mounted-node lookup for page services (preview focus, style presets). Repeat
-- templates share one id; the first mounted record wins.
function Session:ForEachNode(callback)
    local function Walk(nodes)
        for _, node in ipairs(nodes) do
            if node.alive then
                if callback(node) == true then return true end
                if Walk(node.children) then return true end
            end
        end
    end
    if self.alive then Walk(self.nodes) end
end

function Session:FindNode(id)
    local found
    self:ForEachNode(function(node)
        if node.spec.id == id then found = node; return true end
    end)
    return found
end

-- 卡片当前是否折叠（重建页面前记下用户的折叠，再写回声明的 collapsed）。
-- id 不是已挂载的卡片时返回 nil；重复模板里同 id 的卡片取第一张。
function Session:IsCardCollapsed(id)
    local node = self:FindNode(id)
    if not node or node.spec.kind ~= "card" then return nil end
    return node.frame:IsCollapsed()
end

function Session:GetHeight() return self.height or 0 end
function Session:GetContentWidth() return self.contentWidth or 0 end

-- Page rows are measured together; the next row always follows the tallest card.
-- 同一排的卡片拉到一样高：矮的卡片把主体加高，多出的空间留在卡片底部，行仍从顶部排。
-- This is a card layout, with no arbitrary frame targets or authored coordinates.
local function ArrangePageGrid(session, width)
    local columns, total = session.columns, 0
    for _, column in ipairs(columns) do total = total + column.weight end
    local gap = math.min(session.columnGap or GAP, width / (#columns * 2))
    local room = math.max(1, width - gap * (#columns - 1))
    local widths, offsets, x = {}, {}, PAD
    for i, column in ipairs(columns) do
        offsets[i], widths[i] = x, room * column.weight / total
        x = x + widths[i] + gap
    end
    local rows, order = {}, {}
    for _, node in ipairs(session.nodes) do
        if node.visible then
            local row = node.spec.row
            if not rows[row] then rows[row] = {}; order[#order + 1] = row end
            rows[row][#rows[row] + 1] = node
        end
    end
    table.sort(order)
    local y = PAD
    for index, row in ipairs(order) do
        local height, before, entries = 0, 0, {}
        for _, node in ipairs(rows[row]) do
            local column, span = node.spec.column, node.spec.span or 1
            local cardWidth = gap * (span - 1)
            for i = column, column + span - 1 do cardWidth = cardWidth + widths[i] end
            local nodeHeight = LayoutNode(node, cardWidth)
            height = math.max(height, nodeHeight)
            before = math.max(before, node.spec.gapBefore or 0)
            entries[#entries + 1] = { node=node, width=cardWidth, x=offsets[column], height=nodeHeight }
        end
        if index > 1 then y = y + (session.rowGap or GAP) end
        y = y + before
        for _, entry in ipairs(entries) do
            local frame = entry.node.frame
            if entry.height < height and frame.SetContentHeight and not frame._exSettingsCardCollapsed then
                frame:SetContentHeight(frame._exSettingsCardContentHeight + height - entry.height)
            end
            Place(frame, session.root, entry.x, y, entry.width, height)
        end
        y = y + height
    end
    return y + PAD
end

-- [决定] Layout 出错恢复：测量/布局阶段抛错时必须清除 layingOut 锁，再原样报告原错，
-- 否则之后的所有 Invalidate/Refresh 都会在入口直接返回、页面永远不再重排（对齐 V1/网页 renderer 的 finally）。
function Session:Layout()
    if not self.alive or self.cleanupFailed or self.layingOut then return end
    self.layingOut = true
    -- 样式页：页面四周留白取 pagePadding，第一组离顶取 firstGroupTop，组间取 groupGap（预设没写的项用原值）。
    local style, pageGap, pad = self.style, GAP, PAD
    if style then pad = style.pagePadding or PAD end
    local width, y = math.max(1, self.root:GetWidth() - pad * 2), pad
    if style then y, pageGap = style.firstGroupTop or pad, style.groupGap or GAP end
    local function Arrange(node)
        if node.visible then
            local height = LayoutNode(node, width)
            Place(node.frame, self.root, pad, y, width, height)
            y = y + height + pageGap
        end
    end
    local gridHeight
    local ok, failure = pcall(function()
        if self.layout == "grid" then gridHeight = ArrangePageGrid(self, width)
        else for _, node in ipairs(self.nodes) do Arrange(node) end end
    end)
    self.layingOut = false
    if not ok then error(failure, 0) end
    local contentWidth = width + pad * 2
    local height = gridHeight or math.max(pad * 2, y - pageGap + pad)
    self.root:SetHeight(height)
    -- 宿主回调：onHeightChanged(height) 报告真实高度；onContentWidthChanged(width) 报告真实内容宽。
    -- 两者都在布局锁释放、本次结果已落定之后才调用，回调里读 GetHeight/GetContentWidth 得到的就是这次结果。
    local heightChanged, widthChanged = self.height ~= height, self.contentWidth ~= contentWidth
    self.height, self.contentWidth = height, contentWidth
    if heightChanged and self.owner.onHeightChanged then self.owner.onHeightChanged(height) end
    if not self.alive then return end
    if widthChanged and self.owner.onContentWidthChanged then self.owner.onContentWidthChanged(contentWidth) end
end

function Session:Invalidate()
    if not self.alive or self.cleanupFailed or self.pending then return end
    self.pending = true
    C_Timer.After(0, function()
        if not self.alive then return end
        self.pending = false
        self:Layout()
    end)
end

function Session:Refresh()
    if not self.alive or self.cleanupFailed then return false end
    for _, node in ipairs(self.nodes) do RefreshNode(node, true, true) end
    self:Invalidate()
end

-- Keep parent occupancy until all owned resources have been cleaned successfully.
function Session:Release()
    if not self.alive then return end
    self.alive = false
    local failures, root = {}, self.root
    if self.cleanupFailed then Capture(failures, false, self.cleanupFailure) end
    for _, node in ipairs(self.nodes) do Retire(node) end
    Cleanup(failures, function()
        root:SetScript("OnSizeChanged", nil)
        root:SetScript("OnHide", nil)
        root:SetScript("OnShow", nil)
    end)
    for _, node in ipairs(self.nodes) do ReleaseNode(node, failures) end
    self.nodes = {}
    Cleanup(failures, root.Hide, root)
    if not failures.failed then Cleanup(failures, Factory.ReleaseCompositeHost, Factory, root) end
    if not failures.failed and Mounted[self.parent] == self then Mounted[self.parent] = nil end
    self.root = nil
    Rethrow(failures)
end

-- 记录表格：把 rowActions / addAction 展开成普通的格与按钮（校验已在展开前做完）。
-- 操作列由 Core 追加在最后，宽度按按钮文字算；新增按钮放在首行的最后一格，
-- addAction.input 给出时，同一行第一格放这个输入框（输入和添加在同一行）。
local function ActionCell(id, buttons)
    return { kind = "cell", id = id, children = { { kind = "row", id = id .. ".line", children = buttons } } }
end

local function ExpandTables(node)
    if type(node) ~= "table" then return end
    if node.kind == "table" and (node.rowActions or node.addAction) then
        local hasActions = node.rowActions ~= nil
        if hasActions then node.columns[#node.columns + 1] = { title = _G.ExwindTools.L["操作"], actions = true } end
        local function Extend(row)
            local buttons = {}
            for i, action in ipairs(node.rowActions) do
                buttons[i] = { kind = "button", id = action.id, text = action.text, action = action.action,
                    enabled = action.enabled, presentation = action.presentation, _compact = true }
            end
            row.children[#row.children + 1] = ActionCell(node.id .. ".actions", buttons)
        end
        for _, child in ipairs(node.children) do
            if hasActions then Extend(child.kind == "repeat" and child.template or child) end
        end
        if node.addAction then
            local add = node.addAction
            local cells = {}
            for i = 1, #node.columns - 1 do
                cells[i] = { kind = "cell", id = node.id .. ".add." .. i, children = { { kind = "text", id = node.id .. ".add." .. i .. ".text", text = "" } } }
            end
            if add.input then
                cells[1].children[1] = { kind = "control", id = add.id .. ".input", controlType = "input", ref = add.input }
            end
            cells[#node.columns] = ActionCell(node.id .. ".add", { { kind = "button", id = add.id, text = add.text,
                action = add.action, clickKey = add.clickKey, presentation = "primary", _compact = true } })
            table.insert(node.children, 1, { kind = "row", id = node.id .. ".add.row", children = cells })
        end
        node.rowActions, node.addAction = nil, nil
    end
    for _, field in ipairs({ "children", "cards" }) do
        for _, child in ipairs(type(node[field]) == "table" and node[field] or {}) do ExpandTables(child) end
    end
    if node.template then ExpandTables(node.template) end
end

function UI:MountSettingsDeclarationV2(parent, declaration, owner)
    local ok, issue, strict = Validate(declaration, owner)
    if not ok then return nil, issue end
    ReportStrict(owner and owner.binding and owner.binding.moduleKey or "page", strict)
    if (type(parent) ~= "table" and type(parent) ~= "userdata") or type(parent.GetWidth) ~= "function" or type(owner) ~= "table" then
        local _, invalid = Issue("parent", "parent and owner required", nil, "INVALID_ARGUMENT")
        return nil, invalid
    end
    if Mounted[parent] then
        local _, invalid = Issue("parent", "parent already owns a V2 session or failed cleanup", nil, "INVALID_ARGUMENT")
        return nil, invalid
    end
    declaration = DeclarationCopy(declaration, {})
    ExpandTables(declaration)
    local session = setmetatable({ alive=true, owner=owner, nodes={}, layout=declaration.layout, parent=parent,
        columns=declaration.columns, columnGap=declaration.columnGap, rowGap=declaration.rowGap,
        style=declaration.style and GM.settings.styles[declaration.style] }, { __index=Session })
    session.root = Acquire(parent)
    Mounted[parent] = session
    session.root:SetPoint("TOPLEFT")
    session.root:SetPoint("TOPRIGHT")
    session.root:SetScript("OnSizeChanged", function(_, width)
        if session.width ~= width then session.width = width; session:Invalidate() end
    end)
    session.root:SetScript("OnHide", function()
        if not session.alive then return end
        for _, node in ipairs(session.nodes) do HideNode(node) end
    end)
    session.root:SetScript("OnShow", function() session:Refresh() end)
    local mounted, failure = pcall(function()
        for _, spec in ipairs(declaration.cards) do Build(session, spec, session.root) end
        session:Refresh()
        session:Layout()
    end)
    if not mounted then
        local released, releaseFailure = pcall(function() session:Release() end)
        error(tostring(failure) .. (released and "" or "\nRelease: " .. tostring(releaseFailure)), 0)
    end
    return session
end

function UI:MountSettingsPageV2(parent, pageId, owner)
    local declaration = Pages[pageId]
    Check(declaration ~= nil, "unregistered page " .. tostring(pageId))
    local session, issue = self:MountSettingsDeclarationV2(parent, declaration, owner)
    Check(session ~= nil, issue and (issue.path .. ": " .. issue.message))
    return session
end

-- Context menus share the page reference/record rules and the existing menu painter.
local Menus, MenuSession = {}, {}
local MenuFields = {
    button = "text textSource action presentation", menu = "text textSource children",
    separator = "", ["repeat"] = "source template",
}

local function ValidateMenuNode(node, owner, ids, depth, submenuDepth)
    Check(type(node) == "table" and MenuFields[node.kind], "unknown menu node kind")
    Keys(node, "id kind visible enabled " .. MenuFields[node.kind], "menu node")
    Check(Name(node.id) and not ids[node.id], "missing/duplicate menu id " .. tostring(node.id))
    ids[node.id] = true
    for _, field in ipairs({ "visible", "enabled" }) do
        if node[field] ~= nil then Reference(owner, "predicates", node[field], node.id) end
    end
    if node.kind == "repeat" then
        Check(depth < 2, "at most two nested menu repeats")
        Reference(owner, "sources", node.source, node.id)
        ValidateMenuNode(node.template, owner, ids, depth + 1, submenuDepth)
    elseif node.kind ~= "separator" then
        Check((node.text ~= nil) ~= (node.textSource ~= nil), node.id .. ": use text or textSource")
        if node.text ~= nil then Check(type(node.text) == "string", "menu text must be string") end
        if node.textSource ~= nil then Reference(owner, "texts", node.textSource, node.id) end
        if node.kind == "button" then
            Reference(owner, "actions", node.action, node.id)
            Check(node.presentation == nil or node.presentation == "primary" or node.presentation == "secondary"
                or node.presentation == "danger", "invalid menu presentation")
        else
            Check(submenuDepth < 1, "context menu supports one submenu level")
            Array(node.children, node.id .. ".children")
            for _, child in ipairs(node.children) do
                ValidateMenuNode(child, owner, ids, depth, submenuDepth + 1)
            end
        end
    end
end

local function ValidateMenu(declaration, owner)
    Keys(declaration, "version items", "menu")
    Check(declaration.version == 2, "menu version must be 2")
    Array(declaration.items, "menu items")
    local ids = {}
    for _, node in ipairs(declaration.items) do ValidateMenuNode(node, owner, ids, 0, 0) end
end

function UI:RegisterContextMenuV2(menuId, declaration)
    Check(Name(menuId) and Menus[menuId] == nil, "missing/duplicate menu id")
    local copy = DeclarationCopy(declaration, {})
    ValidateMenu(copy)
    Menus[menuId] = copy
end

function MenuSession:Release()
    if not self.alive then return end
    self.alive = false
    if self.frame and UI._contextMenu == self.frame and self.frame._v2Session == self then
        UI:HideContextMenu()
        self.frame._v2Session = nil
    end
end

function UI:ShowContextMenuV2(menuId, owner, options)
    Check(Menus[menuId] ~= nil, "unregistered menu " .. tostring(menuId))
    Check(type(owner) == "table" and type(owner.isCurrent) == "function", "menu owner requires isCurrent")
    options = options or {}
    ValidateMenu(Menus[menuId], owner)
    local previous = self._contextMenu and self._contextMenu._v2Session
    if previous then previous:Release() end
    local session = setmetatable({ alive=true, owner=owner }, { __index=MenuSession })
    local function predicate(name, scope)
        if name == nil then return true end
        local value = owner.predicates[name](scope)
        Check(type(value) == "boolean", "menu predicate must return ordinary boolean")
        return value
    end
    local function current(scope)
        if not session.alive or owner.isCurrent(scope) ~= true then return false end
        while scope do
            local records = owner.sources[scope._source](scope.parent)
            if records[scope.index] ~= scope.item then return false end
            scope = scope.parent
        end
        return true
    end
    local expand
    expand = function(nodes, scope, ancestors)
        local items = {}
        for _, node in ipairs(nodes) do
            if predicate(node.visible, scope) then
                local chain = {}
                for i, entry in ipairs(ancestors or {}) do chain[i] = entry end
                chain[#chain + 1] = { spec=node, scope=scope }
                if node.kind == "repeat" then
                    local records = owner.sources[node.source](scope)
                    Array(records, node.id .. " source")
                    local seen = {}
                    for i, record in ipairs(records) do
                        Check(type(record) == "table" and not seen[record], "menu requires unique original records")
                        seen[record] = true
                        local childScope = { item=record, index=i, parent=scope, _source=node.source }
                        for _, item in ipairs(expand({ node.template }, childScope, chain)) do
                            items[#items + 1] = item
                        end
                    end
                elseif node.kind == "separator" then
                    items[#items + 1] = { divider=true }
                else
                    local text = node.text or owner.texts[node.textSource](scope)
                    Check(type(text) == "string", "menu text source must return string")
                    local ctx = { scope=scope }
                    function ctx:IsCurrent() return current(scope) end
                    function ctx:Guard(callback)
                        Check(type(callback) == "function", "Guard expects a callback")
                        return function(...)
                            if not current(scope) then return end
                            for _, entry in ipairs(chain) do
                                if not predicate(entry.spec.visible, entry.scope)
                                    or not predicate(entry.spec.enabled, entry.scope) then return end
                            end
                            return callback(...)
                        end
                    end
                    local enabled = true
                    for _, entry in ipairs(chain) do enabled = enabled and predicate(entry.spec.enabled, entry.scope) end
                    local item = { text=text, disabled=not enabled, danger=node.presentation == "danger" }
                    if node.kind == "menu" then
                        item.submenu = expand(node.children, scope, chain)
                    else
                        item.onClick = ctx:Guard(function()
                            local ok, failure = pcall(owner.actions[node.action], ctx, "LeftButton")
                            session:Release()
                            if not ok then error(failure, 0) end
                        end)
                    end
                    items[#items + 1] = item
                end
            end
        end
        return items
    end
    local items = expand(Menus[menuId].items)
    if #items == 0 or owner.isCurrent(nil) ~= true then session.alive=false; return session end
    session.frame = self:ShowContextMenu({ items=items, x=options.x, y=options.y, title=options.title })
    session.frame._v2Session = session
    return session
end
