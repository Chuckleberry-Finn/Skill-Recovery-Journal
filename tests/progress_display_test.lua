-- Run from the repository root with Lua 5.1 or later.
local root = "Contents/mods/Skill Recovery Journal/42.20.1/media/lua/"
local function loadShared(name) return dofile(root .. "shared/Skill Recovery Journal " .. name .. ".lua") end

local translations = {
    IGUI_Total = "Total", IGUI_XP_xp = "XP",
    IGUI_GainedXPText = "Recoverable XP", IGUI_StartingLevelText = "Starting Level",
    IGUI_DeductedXP = "Unrecoverable XP", IGUI_UntranscribedXP = "Untranscribed XP",
}
function getText(key) return translations[key] or key end
function getDebug() return false end
function round(n, places) local m = 10 ^ places; return math.floor(n * m + 0.5) / m end
function instanceof() return true end
function copyTable(t) local result = {}; for k, v in pairs(t) do result[k] = v end; return result end
UIFont = { Small = 1, Medium = 1, NewSmall = 1 }
local textManager = {
    getFontHeight = function() return 12 end,
    MeasureStringX = function(_, _, text) return #text * 6 end,
    MeasureStringY = function(_, _, text) local _, n = text:gsub("\n", ""); return (n + 1) * 12 end,
}
function getTextManager() return textManager end
function getCore() return {
    getOptionFontSizeReal = function() return 1 end,
    getOptionTooltipFont = function() return "Small" end,
    getScreenWidth = function() return 1920 end,
    getScreenHeight = function() return 1080 end,
} end
function getMouseX() return 100 end
function getMouseY() return 100 end
ISContextMenu = {}

local category = { getId = function() return "Crafting" end }
local perk = {
    getId = function() return "Woodwork" end,
    getName = function() return "Carpentry" end,
    getParent = function() return category end,
    getTotalXpForLevel = function(_, level) return level == 10 and 32775 or 75 end,
}
Perks = { Woodwork = perk }
local SRJ = {
    modDataHandler = {
        getFreeLevelsFromTraitsAndProfession = function(char) return char.startingLevels end,
        getDeductedXP = function(char) return char.deductedXP end,
        getFlatXP = function(char) return char.flatXP end,
        getDisplayData = function(item) return item.display end,
        returnCapturedKeys = function() return nil end,
    },
    ledger = { getReadXPAny = function(char) return char.readXP end },
    bSkillValid = function() local pct = SandboxVars.SkillRecoveryJournal.RecoveryPercentage / 100; return pct > 0, pct end,
}
package.loaded["Skill Recovery Journal Main"] = SRJ
SRJ.xpHandler = loadShared("XP")
SRJ.xpHandler.fetchMultipliers = function(char) return 1, char.multiplier end
SRJ.xpHandler.getOrStoreXPMultipliers = function(char) return { Woodwork = char.multiplier } end
loadShared("Calc")

ISSkillProgressBar = {
    updateTooltip = function(self) self.message = "Base tooltip" end,
    getXpForLvl = function() return 75 end,
    render = function() end,
}
package.loaded["XpSystem/ISUI/ISSkillProgressBar"] = true
dofile(root .. "client/Skill Recovery Journal SkillProgressBar.lua")

local function character(total, flat, read, readFlat, multiplier)
    return {
        multiplier = multiplier or 0.25,
        startingLevels = {}, deductedXP = {}, flatXP = { Woodwork = flat or 0 },
        readXP = { Woodwork = read or 0, flat = { Woodwork = readFlat or 0 } },
        getXp = function() return { getXP = function() return total end } end,
    }
end
local function reset(percentage)
    SandboxVars = { SkillRecoveryJournal = { RecoveryPercentage = percentage or 100, TranscribeTVXP = true } }
    SRJ.xpHandler.skillXPNormalizeScale.Woodwork = 1
end
local function progress(char, expected)
    local bar = setmetatable({ char = char, perk = perk, level = 1 }, { __index = ISSkillProgressBar })
    bar:updateTooltip(1)
    for label, amount in pairs(expected) do
        local actual = tonumber(bar.message:match(label .. ": ([%d.]+)")) or 0
        assert(math.abs(actual - amount) < 0.01, label .. ": expected " .. amount .. ", got " .. actual .. "\n" .. bar.message)
    end
end

reset()
-- 300 earned XP is stored as 1200 normalized XP for a default 0.25 boost.
-- Earning another 300 must not turn that unrecorded XP green.
progress(character(600, 0, 1200), { ["Recoverable XP"] = 300, ["Untranscribed XP"] = 300 })
progress(character(130, 0, 100, 0, 1.3), { ["Recoverable XP"] = 130, ["Untranscribed XP"] = 0 })
progress(character(250, 250, 0, 200), { ["Recoverable XP"] = 200, ["Untranscribed XP"] = 50 })
-- A high boosted-XP watermark must not conceal unrecorded flat XP.
progress(character(600, 200, 2400, 100), { ["Recoverable XP"] = 500, ["Untranscribed XP"] = 100 })

reset(80)
progress(character(600, 0, 1920), { ["Recoverable XP"] = 480, ["Untranscribed XP"] = 0, ["Unrecoverable XP"] = 120 })
progress(character(600, 0, 1200), { ["Recoverable XP"] = 300, ["Untranscribed XP"] = 180, ["Unrecoverable XP"] = 120 })
-- XP already restored from a previous life is still accounted for, even if
-- the next transcription target is smaller because of the recovery setting.
progress(character(480, 0, 1920), { ["Recoverable XP"] = 480, ["Untranscribed XP"] = 0, ["Unrecoverable XP"] = 0 })
reset()
SRJ.xpHandler.skillXPNormalizeScale.Woodwork = 0.25
progress(character(600, 0, 600), { ["Recoverable XP"] = 150, ["Untranscribed XP"] = 0, ["Unrecoverable XP"] = 450 })

reset()
SandboxVars.SkillRecoveryJournal.TranscribeTVXP = false
local withDeductions = character(1000, 200, 1000, 100)
withDeductions.startingLevels.Woodwork = 1
withDeductions.deductedXP.Woodwork = 100
progress(withDeductions, { ["Recoverable XP"] = 350, ["Untranscribed XP"] = 475, ["Unrecoverable XP"] = 100 })

ISToolTipInv = { render = function() end }
package.loaded["ISUI/ISToolTipInv"] = true
dofile(root .. "client/Skill Recovery Journal Tooltip.lua")
local function journalTooltip(display)
    local char = character(0)
    local item = {
        display = display,
        getModData = function() return {} end,
        getType = function() return "SkillRecoveryBoundJournal" end,
        DoTooltip = function(_, tooltip) tooltip.width = 100; tooltip.height = 30 end,
    }
    local function geometry(obj)
        for _, axis in ipairs({ "X", "Y", "Width", "Height" }) do
            local field = axis:lower()
            obj["set" .. axis] = function(self, value) self[field] = value end
            obj["get" .. axis] = function(self) return self[field] end
        end
        return obj
    end
    local drawn = {}
    local view = geometry(setmetatable({
        item = item, x = 100, y = 100,
        tooltip = geometry({ getCharacter = function() return char end, setMeasureOnly = function() end }),
        backgroundColor = { a = 1, r = 0, g = 0, b = 0 },
        borderColor = { a = 1, r = 1, g = 1, b = 1 },
        drawRect = function() end, drawRectBorder = function() end,
        drawText = function(_, text) drawn[#drawn + 1] = text end,
    }, { __index = ISToolTipInv }))
    view:render()
    return table.concat(drawn, "\n")
end
local function expectJournal(gained, flat, used, expected)
    local text = journalTooltip({ author = "Test", renamedJournal = true, gainedXP = gained, flatGainedXP = flat, usedXP = used })
    assert(text:find(expected, 1, true), "Expected " .. expected .. " in journal tooltip:\n" .. text)
end
reset()
expectJournal({}, { Woodwork = 120 }, nil, "Carpentry (120 xp)")
expectJournal({ Woodwork = 400 }, { Woodwork = 120 }, nil, "Carpentry (220 xp)")
SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed = true
expectJournal({ Woodwork = 400 }, { Woodwork = 120 }, { Woodwork = 100, flat = { Woodwork = 20 } }, "Carpentry (175/220 xp)")
expectJournal({}, { Woodwork = 120 }, { flat = { Woodwork = 120 } }, "Carpentry (0/120 xp)")
print("progress_display_test.lua: passed")
