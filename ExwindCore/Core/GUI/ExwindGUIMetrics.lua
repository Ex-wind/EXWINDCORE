-- ExwindCore 设置界面的固定数值表：字号、间距、尺寸。
-- 只放纯数据；通用控件与页面专用字号均从本表读取。
-- 必须在 ExwindGUIColor.lua 之后、ExwindGUI.lua 之前加载。
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

-- 默认控件高度：按钮、输入框、下拉触发器、颜色按钮、设置列表普通控件共用这一个值。
-- 只有声明里明确写了 height 的控件才可以不同。
local CONTROL_HEIGHT = 30

ExwindTools.GUIMetrics = {
    -- 设置行规格：照 V1 设置页定案的数值（用户 2026-10-12：原本都调好了，照抄）。
    -- 只有一种设置行：左标签（可带一行说明），右控件，控件列右对齐。
    settings = {
        rowMinHeight = 50,        -- 卡内一行的最小高度（V1 standardRowHeight）
        rowPaddingX = 20,         -- 行左右内边距（V1 rowPaddingX）
        rowPaddingY = 8,          -- 行上下内边距（V1 rowPaddingY）
        cardPaddingX = 20,        -- 卡片左右内边距，与行内边距相同，卡内所有内容左缘统一
        cardPaddingY = 0,         -- 只有设置行的卡片上下内边距：V1 行直接贴卡片，单行卡 = 一行高
        cardGap = 4,              -- 同组卡片之间的间距
        sectionHeaderTop = 20,    -- 节标题上移量：加页面卡片间距 8 后，离上方卡片 24（V1 sectionGroupGap 16 + sectionTop 8）
        sectionHeaderBottom = 8,  -- 节标题离下方卡片（V1 sectionTitleToCardGap）
        labelFont = 15,           -- 标签字号（V1 行标题 title 15）
        descriptionFont = 13,     -- 说明字号（V1 正文 text 13）
        sectionFont = 18,         -- 节标题字号（V1 节标题 cardTitle 18）
        labelDescriptionGap = 6,  -- 标签与说明的间距（V1 descriptionGap）
        controlHeight = 30,       -- 行内控件高度（V1 ordinaryControlHeight）
        controlMinWidth = 104,    -- 控件列最小宽（V1 settingsRowControlMinWidth）
        labelControlGap = 20,     -- 标签列与控件列的间距（V1 columnGap）
        stackGap = 8,             -- 窄时控件换到标签下方的间距（SettingsCardVerticalHeaderContentSpacing 8）
        leadGap = 8,              -- 标签前勾选框 / 图标与标签文字的间距
        leadIconSize = 20,        -- 标签前图标边长（勾选框用 size.checkboxBoxSize）
        controlShortWidth = 72,   -- 控件宽度档位 size="short"（短数字、秒数）
        controlWideWidth = 320,   -- 控件宽度档位 size="wide"（长文字、路径）
        soundSelectorWidth = 320, -- 连体声音选择（来源 | 内容 | ▶）的自然宽
        toggleItemPadX = 44,      -- 多选（角标勾小块）：文字左 14 + 右侧角标区 30
        toggleItemGap = 4,        -- 多选：小块之间的间距
        soundSourceMaxRatio = 0.4, -- 声音选择里“来源”段最多占整段宽的比例
        tableCellPadX = 4,        -- 表格单元格左右内距
        multilineHeight = 120,    -- 多行文字框标准高度
        multilineTallHeight = 240, -- 多行文字框 size="tall"（导入导出字符串）
        multilineScrollReserve = 20, -- 多行文字区给滚动留的宽度
        -- 可选页面样式预设（EXAura 编辑器新版）：页面声明只写预设名，不写像素。
        -- 颜色直接引用 Core 色表 GUIColors 里的项。styles 在下方表外填入。
        styles = {},
    },

    -- 圆角角色（视觉半径，像素；必须是 SetControlSurface 白名单 3/4/5/6/8/10 之一；白名单里的 21 只给胶囊按钮组）。
    -- thumb：滑块拖块等小件；control：按钮/输入框/下拉/复选框/选项块；
    -- popup：下拉与右键菜单、预览外壳；dialog：确认框等对话框；card：卡片与面板。
    -- Switch 的轨道是整圆胶囊，半径由轨道高度推算，不占用角色。
    radius = { thumb = 3, control = 4, popup = 6, dialog = 8, card = 10 },

    -- 字号（像素）。
    font = {
        tools = { moduleTitle=20, profileTitle=23, profileLabel=14 },
        exboss = { micro=9, chipLabel=10, previewText=14, navigationTitle=16, spellListTitle=17, spellDetailTitle=21 },
        mythicStats = { caption=12, small=14, label=15, column=16, heading=18, row=20, stat=24, summary=32, playerName=44, score=72 },
        pageTitle = 24,   -- 页面大标题；ExwindGUI.lua MODERN.metrics.pageTitle
        title = 15,       -- 一般标题；MODERN.metrics.title
        cardTitle = 18,   -- 卡片标题；MODERN.metrics.cardTitle
        section = 15,     -- 分区标题；MODERN.metrics.section
        text = 13,        -- 正文；MODERN.metrics.text
        control = 13,     -- 控件文字；MODERN.metrics.control
        fieldValue = 15,  -- 输入框/字段值；MODERN.metrics.fieldValue
        button = 15,      -- 按钮文字；MODERN.metrics.button
        hint = 11,        -- 提示/说明小字；MODERN.metrics.hint
        moduleDescription = 12, -- Module management descriptions retain their current size.
        sliderInput = 13, -- 滑条数值框字号（用户 2026-10-05：11 太小）。加大后框宽同批放到 48，
                          -- 让 "100.5" 这类四位带小数的值仍能整体显示。
        small = 12,       -- 次要小字（对话框来源行、模块说明等）。
        label = 14,       -- 表头、弹层内小标题。
        dialogTitle = 22, -- 对话框/提示卡片标题。
    },

    -- 间距 / 内边距 / 圆角前的留白（像素）。
    space = {
        buttonPaddingX = 14,           -- 按钮文字左右内边距；ExwindGUI.lua BUTTON_STYLE.paddingX
        buttonPaddingY = 6,            -- 按钮文字上下内边距；BUTTON_STYLE.paddingY
        compactButtonPaddingX = 4,     -- 紧凑按钮文字左右内边距：文字限制在按钮内，放不下按钮撑宽
        sliderInputInset = 3,          -- 滑条数值框文字左右内缩；SLIDER_NUMBER_INPUT_INSET
        cardBodyPadding = 12,          -- 设置卡片正文四周留白；ExwindGUISettingsList.lua SETTINGS_CARD_BODY_PADDING
        columnGap = 20,                -- 通用左右两列的列间距（设置行用 settings.labelControlGap）
        descriptionGap = 6,            -- 标题与说明文字的间距；SETTINGS_LIST_DESCRIPTION_GAP
        sectionTop = 8,                -- 分区顶部留白；SETTINGS_LIST_SECTION_TOP
        sectionGroupGap = 16,          -- 分区组之间的间距；SETTINGS_LIST_SECTION_GROUP_GAP
        narrowControlIndent = 28,      -- 窄宽度下控件的缩进；SETTINGS_LIST_NARROW_CONTROL_INDENT
        settingsRowStackGap = 8,       -- 窄版设置行：文字与换到下一行的控件之间的间距
        settingsV2Gap = 8,             -- 设置页 V2 节点间距；ExwindSettingsV2.lua 的 GAP
        settingsV2Padding = 12,        -- 设置页 V2 页面内边距；ExwindSettingsV2.lua 的 PAD
        -- 以下几项原来各处写了不同的数，统一在这里（10-13）。
        sliderInputGap = 10,           -- 滑条轨道与数值框的间距（独立滑条与设置行滑条共用）
        inputTextPadX = 9,             -- 输入框文字与占位文字的左内距
        choiceItemPadX = 20,           -- 选项块：文字宽 + 该值 = 块宽
        choiceIconItemPadX = 42,       -- 带图标的选项块：文字宽 + 该值 = 块宽
        segmentedTrackPad = 3,         -- segmented 轨道四周内距
        segmentedDarkTrackPad = 2,     -- segmented 黑色轨道（options.track = "dark"）四周内距
        connectedTrackPad = 2,         -- connected 轨道四周内距

        -- 树控件（ExwindGUITree.lua CreateTree）。
        treeIndent = 18,               -- 每层缩进
        treePadding = 6,               -- 行左右内边距
        treeSlotGap = 8,               -- 行内相邻元素（折叠箭头/图标/徽标/名称）之间的间距
        treeRowGap = 2,                -- 行与行之间的间距
        -- 群组方向图示与每行个数选择（CreateFlowDirectionPicker / CreatePerLineSelector）。
        flowThumbGap = 6,              -- 方向图示选择格之间的间距
        flowCellGap = 2,               -- 方向图示缩略图里小方块之间的间距
        perLineGap = 4,                -- 每行个数方块之间的间距
        toggleDropdownGap = 8,         -- 开关加下拉合一按钮：开关指示方框与文字的间距
        playIndicatorBarGap = 3,       -- 播放指示器相邻竖线的中心间距（AcquirePlayingIndicator）

        -- 专精选择器浮层（ExwindChoiceGroup.lua CreateSpecPicker）。
        specPopupInset = 12,           -- 浮层四周内缩
        specColumnGap = 10,            -- 四个护甲列之间的间距
        specClassGap = 8,              -- 职业块之间的纵向间距
        specTileGap = 4,               -- 同职业内相邻图标格的间距
        specTilePadding = 2,           -- 图标格到选项格边缘的留白；格高 = specTileSize + 2 × 该值
        specHeaderDividerGap = 6,      -- 护甲标题下的分隔线到列内容的间距；线位置 = specColumnHeaderHeight - 该值

        -- 菜单行（下拉菜单的 initializer 与行高亮、右键菜单的自绘行共用这三个键）。
        menuRowPaddingX = 8,           -- 行左右内边距：勾号/图标起点，也是无标记时文字的左内距
        menuRowSlotGap = 6,            -- 行内图标、勾号、箭头与文字之间的间隙
        menuRowHighlightInset = 1,     -- 行高亮块相对行框的左右内缩；菜单外框 inset 已有 6，这里不再叠大留白
        menuEdgePadding = 4,           -- 右键菜单四周外边距，以及行到菜单边的留白
        menuDividerGap = 3,            -- 右键菜单分隔线上下留白

        -- 页内状态提示与浮动 Toast（ExwindGUIComposite.lua）。
        statusPaddingX = 14,           -- 状态提示左右内边距
        statusPaddingY = 11,           -- 状态提示上内边距
        statusTextIndent = 40,         -- 标题/说明相对左缘的文字起点（图标槽 + 间隙）
        statusDescGap = 4,             -- 标题到说明的间距
        toastScreenMargin = 20,        -- Toast 距屏幕右下的边距
        toastStackGap = 8,             -- 多个 Toast 之间的堆叠间距

        -- 对话框（ShowDialog / ShowConfirmDialog）。
        dialogPaddingX = 20,           -- 左右内边距
        dialogPaddingY = 18,           -- 标题顶部内边距
        dialogSectionGap = 14,         -- 正文、输入、勾选、自定义内容之间的间距
        dialogButtonGap = 8,           -- 按钮间距，也是按钮换行行距的基数

        -- 颜色按钮（CreateColorButton）。
        colorSwatchPaddingX = 10,      -- 色块到按钮左缘的内边距
        colorSwatchGap = 8,            -- 色块到标签的间隙
        colorButtonTextPaddingRight = 8, -- 标签右内边距

        -- 复合设置组（ExwindGUIComposite.lua 的 COMPOSITE_* 常量真源）。
        compositePadX = 10,            -- 复合组左右内边距；加上列内控件内缩 10 后与设置行左缘 20 对齐（settings.rowPaddingX）
        compositePadY = 8,             -- 复合组上下内边距
        compositeGap = 12,             -- 复合组列间距
        compositeMinSlotGap = 8,       -- 槽位最小间距
        compositeActionPad = 10,       -- 功能区左右内边距
        compositeActionInnerGap = 16,  -- 功能区中线内间距
        compositeControlInset = 20,    -- 列内控件两侧内缩

        -- EXBoss 技能设置列表专用（ExwindGUISettingsList.lua 的 SETTINGS_LIST_EXBOSS_*）。
        tools = { moduleTitle=20, profileTitle=23, profileLabel=14 },
        exboss = {
            contentPaddingX = 18,  -- 内容左右内边距；SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
            footerPadding = 16,    -- 底部留白；SETTINGS_LIST_EXBOSS_FOOTER_PADDING
            simplePaddingY = 9,    -- 简单行上下内边距；SETTINGS_LIST_EXBOSS_SIMPLE_PADDING_Y
            fieldPaddingY = 7,     -- 字段行上下内边距；SETTINGS_LIST_EXBOSS_FIELD_PADDING_Y
            fieldColumnGap = 14,   -- 字段行列间距；SETTINGS_LIST_EXBOSS_FIELD_COLUMN_GAP
            voicePaddingY = 10,    -- 语音行上下内边距；SETTINGS_LIST_EXBOSS_VOICE_PADDING_Y
            voiceColumnGap = 10,   -- 语音行列间距；SETTINGS_LIST_EXBOSS_VOICE_COLUMN_GAP
            voiceControlGap = 6,   -- 语音行控件间距；SETTINGS_LIST_EXBOSS_VOICE_CONTROL_GAP
            cardGap = 7,           -- 卡片选项间距；SETTINGS_LIST_EXBOSS_CARD_GAP
        },
    },

    -- 控件/行高/宽度/断点/圆角（像素）。
    size = {
        controlHeight = CONTROL_HEIGHT,    -- 通用控件高度；ExwindGUI.lua MODERN.metrics.height
        buttonHeight = CONTROL_HEIGHT,     -- 按钮默认高度
        inputHeight = CONTROL_HEIGHT,      -- 输入框默认高度
        dropdownHeight = CONTROL_HEIGHT,   -- 下拉触发器默认高度（箭头与背景切片按 30px 固定几何）
        colorButtonHeight = CONTROL_HEIGHT, -- 颜色按钮默认高度
        checkboxRowHeight = CONTROL_HEIGHT, -- 复选框行高（方框本体在其中居中）
        checkboxBoxSize = 20,              -- 复选框方框本体边长（PaintModernCheckbox / 三态勾选框 / 树行内勾选共用）
        switchTrackWidth = 35,             -- Switch 轨道宽
        switchTrackHeight = 20,            -- Switch 轨道高；轨道圆角 = 高度/2
        switchKnobSize = 16,               -- Switch 圆钮直径
        switchKnobInset = 2,               -- Switch 圆钮到轨道边缘的留白；开启位置 = 轨道宽 - 圆钮 - 留白
        chipHeight = CONTROL_HEIGHT,       -- 选项块（chip）高度
        pillHeight = CONTROL_HEIGHT,       -- Pill 高度
        -- [WEB-REQ 38/40] 分段选项整体高度（轨道）：略高于默认控件高度，34；内部选中块 = 高度 - 6 = 28。
        -- 网页原型按 ×1.25 换算为轨道 42 / 选项 36，Core 以此值为准。
        segmentedItemHeight = 34,
        tabHeight = 38,                    -- 顶部 Tab 高度
        tabIndicatorHeight = 2,            -- Tab 选中下划线高度；两端半圆半径 = 该值 / 2。
                                           -- 下划线走"只填充、不描边"的路径（PaintTabIndicator 把 border 传成
                                           -- 透明），所以不受描边退化影响：2 物理像素仍能取到半径 1 的圆头。
                                           -- 2 物理像素就是下限，再细只剩 1 像素、半径被夹成 0。
        tabIndicatorInset = 12,            -- 下划线相对单个 Tab 两侧的内缩

        -- 专精选择器浮层（ExwindChoiceGroup.lua CreateSpecPicker）。
        specPopupWidth = 680,              -- 浮层目标宽；由"4 专精一行 × specTileSize"反推，改它会改变图标实际边长
        specTileSize = 32,                 -- 专精图标格边长
        specTileMinSize = 24,              -- 列被挤窄时图标格的下限
        specClassHeaderHeight = 20,        -- 职业标题行高
        specColumnHeaderHeight = 40,       -- 护甲列头区高（护甲标题 + 分隔线）
        sliderHeight = 54,                 -- Slider 整体高度（标题行 + 轨道）
        sliderTrackHeight = 4,             -- Slider 轨道粗细；两端圆角由 surface 按高度/2 自动取半圆。
                                           -- 轨道是空的灰条，不再画已走过那一段的填充（用户 2026-10-05）
        timelineTrackHeight = 4,           -- 时间轴滑条轨道粗细（保持原样）
        sliderThumbWidth = 26,             -- Slider 拖块宽
        sliderThumbHeight = 12,            -- Slider 拖块高；与轨道高度同奇偶
        controlDefaultWidth = 200,
        buttonMinWidth = 104,              -- 按钮最小宽度；BUTTON_STYLE.minWidth
        buttonRadius = 4,                  -- 按钮圆角，等于 radius.control
        buttonPressOffset = 1,             -- 按钮按下时文字向右下移动的像素
        picButtonPressInset = 2,           -- 图片按钮按下时贴图四周内缩的像素（按下反馈）
        -- 滑条数值框：13 号字下 "100.5"（5 个字符）加上左右各 sliderInputInset(3) 的内缩
        -- 需要约 42px 可用宽，所以框宽 48；高度仍是 20 的具名例外。
        sliderInputWidth = 48,
        sliderInputHeight = 20,
        -- 播放指示器（唯一公共入口 EXUI:AcquirePlayingIndicator）：待播时的播放图标，
        -- 播放中换成 5 条竖线（只有中间 3 条跳动）。所有播放入口共用这一组尺寸。
        playIndicatorIconSize = 16,        -- 待播状态的播放图标边长
        playIndicatorBarWidth = 2,         -- 单条竖线宽
        playIndicatorBarMaxHeight = 11,    -- 中间那条竖线的静止高度，也是跳动的上限基数

        menuRowHeight = 30,                -- 菜单行高与勾标尺寸独立。
        menuSearchHeight = 42,             -- 下拉菜单搜索栏高度；EXTERNAL_DROPDOWN_SEARCH_HEIGHT
        menuCheckSize = 16,                -- 菜单勾号边长（用户 2026-10-04：原 14 太小）
        menuScrollBarWidth = 8,
        menuScrollThumbWidth = 4,
        numberStepperWidth = 20,
        menuMaxHeight = 400,               -- [WEB-REQ 57] 右键菜单最大高度，对齐 Dropdown 的 SetScrollMode(400)；更长则滚动
        menuMaxWidth = 420,                -- 右键菜单最大宽度（按真实文字测宽，超过则单行截断）
        menuMinWidth = 190,                -- 右键菜单最小宽度
        menuIconSize = 16,                 -- 右键菜单行图标边长（与 treeIconSize 同值）
        menuArrowSize = 14,                -- 右键菜单子菜单箭头边长
        menuTitleHeight = 26,              -- 右键菜单标题槽高

        -- 页内状态提示与浮动 Toast。
        statusIconSize = 16,               -- 左侧状态图标边长
        statusNoticeHeight = 44,           -- 只有标题时的高度
        statusNoticeHeightWithDesc = 68,   -- 带说明时的高度
        toastWidth = 320,                  -- 浮动 Toast 宽度
        toastCloseSize = 18,               -- Toast 关闭按钮边长
        toastCloseGlyphSize = 14,          -- Toast 关闭图标边长

        dialogCloseSize = 28,              -- 对话框关闭按钮边长（与 floatingCloseSize 同值，但各自独立）
        dialogCloseGlyphSize = 16,         -- 对话框关闭图标边长；比 Toast 的 14 大一档，对应更大的按钮
        colorButtonDefaultWidth = 225,     -- 颜色按钮默认宽度
        colorSwatchSize = 16,              -- 颜色按钮左侧色块边长
        cardHeaderHeight = 32,             -- 设置卡片标题栏高度；ExwindGUISettingsList.lua SETTINGS_CARD_HEADER_HEIGHT
        personPortraitAvatar = 56,         -- 人物卡竖排默认圆形头像直径
        homeContactIcon = 48,              -- 首页顶部联系图标
        homeResourceIcon = 24,             -- 首页官方资源图标
        homeThanksAvatar = 72,             -- 首页感谢人物圆形头像直径
        personPortraitRing = 3,            -- 竖排头像外圈：彩环宽 2 + 与头像之间的留缝 1
        personChipAvatar = 20,             -- 人物胶囊（PersonCards layout="chip"）圆形头像直径
        personBadgeSize = 20,              -- 头像右下角的平台角标直径（图标按其 0.7 倍显示）
        personPlatformIcon = 24,           -- 人物卡平台辅助角标，与头像保持主次比例
        floatingHeaderHeight = 32,         -- 非模态浮动窗口（CreateFloatingWindow）标题栏高度，也是拖动条高度
        floatingCloseSize = 28,            -- 浮动窗口关闭按钮边长，与 ShowDialog 的关闭按钮同尺寸
        toggleDropdownArrowWidth = 26,     -- 开关加下拉合一按钮：右半（展开）区域宽度
        toggleDropdownBoxSize = 16,        -- 开关加下拉合一按钮：左侧开关指示方框边长
        iconGlyphSize = 18,                -- 图标按钮、只显示图标的分段里的图标边长（默认）
        flowThumbWidth = 58,               -- 群组方向图示选择格宽度
        flowThumbHeight = 46,              -- 群组方向图示选择格高度
        perLineInputWidth = 90,            -- 每行个数选择：数字输入框宽度
        treeRowHeight = CONTROL_HEIGHT,    -- 树行高度（默认，CreateTree 可用 options.rowHeight 覆盖）
        treeFoldSize = 12,                 -- 树折叠箭头边长
        treeIconSize = 16,                 -- 树行图标边长
        treeBadgeSize = 22,                -- 树行徽标方块边长
        treePillHeight = 18,               -- 树行右侧数量胶囊高度
        treeEyeSize = 22,                  -- 树行最右眼睛按钮边长（行数据写了 eye 才有）
        treeEyeIconSize = 16,              -- 眼睛按钮里的图标边长
        minTextWidth = 160,                -- 设置列表文字列最小宽度；SETTINGS_LIST_MIN_TEXT_WIDTH
        -- [WEB-REQ 28] 设置列表普通行（按钮/输入/下拉/颜色/滑条）右侧控件的最小可用宽与窄版阈值：
        -- 文字列 >= minTextWidth 放不下时，文字列可收窄到 settingsRowCompactTextWidth，仍放不下才把控件换到下一行。
        settingsRowSliderMinWidth = 154,   -- 滑条（数值框 sliderInputWidth 48 + 间距 10 + 轨道 >= 96）
        sliderTrackMinWidth = 96,          -- 滑条轨道最小宽（与上一行同一组数）
        settingsRowCompactTextWidth = 112, -- 窄版时文字列最小宽度
        externalHeaderHeight = 56,         -- 外置卡片头高度；SETTINGS_LIST_EXTERNAL_HEADER_HEIGHT
        fieldRowBreakpoint = 440,          -- 字段行换行断点宽度；SETTINGS_LIST_FIELD_ROW_BREAKPOINT
        compactVoiceBreakpoint = 510,      -- 语音行紧凑布局断点；SETTINGS_LIST_COMPACT_VOICE_BREAKPOINT
        compactVoiceSourceBreakpoint = 360, -- 语音来源紧凑断点；SETTINGS_LIST_COMPACT_VOICE_SOURCE_BREAKPOINT

        -- 胶囊按钮组（EXAura 编辑器顶部全局按钮）。
        capsuleHeight = 42,                -- 整条高度
        capsuleRadius = 21,                -- 圆角 = 高度 / 2（SetControlSurface 白名单 21）
        capsuleSegmentPadX = 14,           -- 段内左右内距
        capsuleEdgePadX = 18,              -- 首尾段外侧内距
        capsuleIconSize = 18,              -- 段内图标边长
        capsuleFont = 15,                  -- 段内文字字号
        capsuleAddFont = 18,               -- “新增”段文字字号
        capsuleAddIconSize = 22,           -- “新增”段图标边长
        capsuleDividerInset = 11,          -- 段间竖线上下各缩
        capsuleIconTextGap = 7,            -- 段内图标与文字的间距
        capsuleSegmentMinWidth = 52,       -- 每段最小宽
        capsuleTooltipGap = 8,             -- tooltipAnchor = "below" 时提示上沿离段下沿的距离

        -- EXBoss 技能设置列表专用（ExwindGUISettingsList.lua 的 SETTINGS_LIST_EXBOSS_*）。
        tools = { moduleTitle=20, profileTitle=23, profileLabel=14 },
        exboss = {
            headerHeight = 53,         -- 头部高度；SETTINGS_LIST_EXBOSS_HEADER_HEIGHT
            simpleRowHeight = 46,      -- 简单行高；SETTINGS_LIST_EXBOSS_SIMPLE_ROW_HEIGHT
            fieldRowHeight = 47,       -- 字段行高；SETTINGS_LIST_EXBOSS_FIELD_ROW_HEIGHT
            voiceRowHeight = 48,       -- 语音行高；SETTINGS_LIST_EXBOSS_VOICE_ROW_HEIGHT
            cardStackBreakpoint = 365, -- 卡片选项改为竖排的断点宽度；SETTINGS_LIST_EXBOSS_CARD_STACK_BREAKPOINT
        },
    },
}

-- 页面样式预设的数值。派生预设 = 基础预设整份复制后改几项，结果仍是普通数据表。
do
    local GC = ExwindTools.GUIColors
    local styles = ExwindTools.GUIMetrics.settings.styles

    local function Derive(base, changes)
        local style = {}
        for key, value in pairs(base) do style[key] = value end
        for key, value in pairs(changes) do style[key] = value end
        return style
    end

    -- 标题条分组 + 无框行（G3+H1）。
    styles.exaura = {
        headerHeight = 36,              -- 标题条高
        headerRadius = 6,               -- 标题条圆角
        headerFill = GC.shell.borderSoft, -- 标题条底（bSubtle），不画边
        headerPaddingLeft = 12,         -- 折叠号离标题条左缘
        foldWidth = 12,                 -- 折叠号宽
        foldNameGap = 9,                -- 折叠号与组名间距
        headerFont = 18,                -- 组名字号
        headerText = GC.white,          -- 组名颜色
        noteFont = 13,                  -- 标题条右侧字字号
        headerPaddingRight = 14,        -- 右侧字离标题条右缘
        headerOutset = 10,              -- 标题条左右各比下面的行宽出（游戏实测：内容比标题宽，要条再宽一点）
        groupGap = 20,                  -- 组与组之间（游戏实测 36 留白太大）
        firstGroupTop = 16,             -- 第一组离页签
        headerToFirstRow = 0,           -- 标题条到第一行
        rowMinHeight = 44,              -- 最小行高
        rowPaddingX = 0,                -- 行左右内距
        rowPaddingY = 6,                -- 行上下内距（控件 30 高时一行正好 44）
        dividerInset = 0,               -- 行线不缩进（通栏）
        helpIconSize = 16,              -- 行尾小问号边长
        settingAutoWidth = true,        -- setting 行（左标签 + 多个子控件）文字列按标签实际字宽；单控件标准行照原算法
        iconButtonSize = 22,            -- 图标按钮（button 写 icon、text 为空）边长
        iconButtonIconSize = 13,        -- 图标按钮里的图标边长
        colorWidth = 46,                -- 不带 label 的颜色控件只画色块，宽 46
    }

    -- 紧凑行：触发页等控件密集的页面。
    styles.exauraCompact = Derive(styles.exaura, {
        rowMinHeight = 40,
        controlHeight = 28,
        controlWidth = 156,             -- 没写 size 的输入框、下拉、分段的宽
        segmentEqualWidth = true,       -- 分段每段平分
        iconButtonSize = 24,            -- 图标按钮边长（附加触发器块的上移、下移、删除）
        iconButtonIconSize = 14,
        iconButtonAppearance = "ghost", -- 图标按钮不画底和边
    })

    -- 载入页：文字列按标签实际字宽。
    styles.exauraLoad = Derive(styles.exaura, {
        labelAutoWidth = true,
        controlWidth = 150,             -- 标准控件宽
        shortWidth = 60,                -- size="short" 的宽
    })

    -- 跟随光环设置条：不画标题条，浮在画布上。
    styles.exauraBar = {
        showHeader = false,
        rowMinHeight = 34,              -- 游戏实测：行距要小一点
        rowPaddingX = 0,
        rowPaddingY = 3,                -- 控件 28 高时一行正好 34
        controlHeight = 28,
        labelFont = 15,
        labelText = GC.white,
        labelOutline = true,            -- 标签加描边
        dividerColor = GC.settingsBarDivider, -- 行线用设置条行线色
        labelAutoWidth = true,          -- 文字列自适应（没有标签的行）
        labelColumnWidth = 72,          -- 有标签的行共用定宽标签列，文字靠右；控件紧跟标签列右边。理由：哪种语言的标签都顶不到控件；
                                        -- 72 放得下四个汉字加描边（如“混合模式”“水平对齐”），控件列仍够四段分段
        labelColumnGap = 12,            -- 标签列与控件的间距
        noWrap = true,                  -- 永不换行
        controlFloorWidth = 32,         -- 永不换行时控件最窄压到（数字框宽）
        overlayControls = true,         -- 控件用浮层外观
        pagePadding = 0,                -- 页面四周不留白（设置条宿主自己留内距）
    }
end
