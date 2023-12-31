require "XpSystem/ISUI/ISSkillProgressBar"

local totalXPText = getText("IGUI_Total").." "..getText("IGUI_XP_xp")

local xpHandler = require "Skill Recovery Journal XP"

local function clipNumberToString(n)
    return string.format("%.2f", n):gsub(".00","")
end

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
        self.message = self.message .. " <LINE><LINE> "..totalXPText..": "..clipNumberToString(self.char:getXp():getXP(self.perk:getType()))

        local multipliers = xpHandler.getOrStoreXPMultipliers(self.char)
        local currentPerkMulti = self.perk:getType()
    end
end