require "XpSystem/ISUI/ISSkillProgressBar"

local totalXPText = getText("IGUI_Total").." "..getText("IGUI_XP_xp")
local gainedXPText = getText("IGUI_GainedXPText")
local SRJ = require "Skill Recovery Journal Main"

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

        local xpText = getText("IGUI_XP_tooltipxp", round(xp, 2), xpForLvl)
        self.message = self.message:gsub(" <LINE> "..state, " <LINE> "..state.." ("..xpText..")")
    end

    if lvlSelected <= self.level and instanceof(self.char,"IsoPlayer") then
        local perkID = self.perk:getId()
        local multipliers = SRJ.xpHandler.getOrStoreXPMultipliers(self.char)
        local gainedXP = SRJ.calculateGainedSkills(self.char)

        local currentXP = tostring(self.char:getXp():getXP(self.perk))
        self.message = self.message .. "\n\n"..totalXPText..": "..round(currentXP, 2)

        if gainedXP and gainedXP[perkID] then
            
            local currentSkillGainedXP = tostring(gainedXP[perkID] * (multipliers[perkID] or 1))
            self.message = self.message.."\n"..gainedXPText..": "..round(currentSkillGainedXP, 2)
        end
    end
end