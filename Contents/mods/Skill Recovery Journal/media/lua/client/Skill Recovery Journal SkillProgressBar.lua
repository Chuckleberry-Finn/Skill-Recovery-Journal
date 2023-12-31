require "XpSystem/ISUI/ISSkillProgressBar"

local totalXPText = getText("IGUI_Total").." "..getText("IGUI_XP_xp")
local gainedXPText = getText("IGUI_GainedXPText")
local SRJ = require "Skill Recovery Journal Main"

local function clipNumberToString(n) return string.format("%.2f", n):gsub(".00","") end

--SRJ.calculateGainedSkills(player)

local ISSkillProgressBar_updateTooltip = ISSkillProgressBar.updateTooltip
function ISSkillProgressBar:updateTooltip(lvlSelected)
    ISSkillProgressBar_updateTooltip(self, lvlSelected)
    ---Show XP even when unlocked - helpful for tracking XP values

    if self.level ~= lvlSelected then
        local xpForLvl = ISSkillProgressBar.getXpForLvl(self.perk, lvlSelected)

        local state
        local xp

        if (lvlSelected < self.level) then
            state = xpSystemText.unlocked
            xp = xpForLvl
        else
            state = xpSystemText.locked
            xp = 0
        end

        local xpText = getText("IGUI_XP_tooltipxp", clipNumberToString(xp), xpForLvl)
        self.message = self.message:gsub(" <LINE> "..state, " <LINE> "..state.." ("..xpText..")")
    end

    if lvlSelected <= self.level then
        local perkID = self.perk:getType()
        local multipliers = SRJ.xpHandler.getOrStoreXPMultipliers(self.char)
        local gainedXP = SRJ.calculateGainedSkills(self.char)

        local gainedText = ""
        if gainedXP[perkID] then
            print("?")
            local currentSkillGainedXP = gainedXP[perkID] * (multipliers[perkID] or 1)
            gainedText = "<LINE> "..gainedXPText.." "..clipNumberToString(currentSkillGainedXP)
        end

        self.message = self.message .. " <LINE><LINE> "..totalXPText..": "..clipNumberToString(self.char:getXp():getXP(perkID))..gainedText

    end
end