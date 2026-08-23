local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

-- [[ ExwindTools Metadata ]]
-- 此文件由打包脚本自动生成或修改，用于控制版本号。
-- 请勿手动通过 Git 提交修改此文件中的版本号，除非你是为了测试。

ExwindTools_MetaData = {
    version = "v26.8.23.0307",
    gridEngineVersion = "2.0",
    changelog = {
        version = "v26.6.24.0200",
        title = L["v26.6.24.0200 更新日志"],
        publishedAt = "2026-06-24 02:00",
        fontSize = 14,
        content = [[

        ]],
    },
}
