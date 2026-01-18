require "XpSystem/ISUI/ISSkillProgressBar"

local totalXPText = getText("IGUI_Total").." "..getText("IGUI_XP_xp")
local gainedXPText = getText("IGUI_GainedXPText")
local startingLevelText = getText("IGUI_StartingLevelText")
local deductedXPText = getText("IGUI_DeductedXP")
local untranscribedXPText = getText("IGUI_UntranscribedXP")

local SRJ = require "Skill Recovery Journal Main"
local SRJ_ModDataHandler = require "Skill Recovery Journal ModData"


function ISSkillProgressBar:registerStartingLevels()
    if ISSkillProgressBar.registeredStartingLevels then return ISSkillProgressBar.registeredStartingLevels end
    local progressBarLevels = {}
    local startingLevels = SRJ.getFreeLevelsFromTraitsAndProfession(self.char)
    if startingLevels then for perkID, level in pairs(startingLevels) do progressBarLevels[perkID] = level end end
    local passiveSkillsInit = SRJ.modDataHandler.getPassiveLevels(self.char)
    if passiveSkillsInit then for perkID, level in pairs(passiveSkillsInit) do progressBarLevels[perkID] = level end end
    ISSkillProgressBar.registeredStartingLevels = progressBarLevels
end


local ISSkillProgressBar_updateTooltip = ISSkillProgressBar.updateTooltip
function ISSkillProgressBar:updateTooltip(lvlSelected)
    ISSkillProgressBar_updateTooltip(self, lvlSelected)
    ---Show XP even when unlocked - helpful for tracking XP values

    if self.level ~= lvlSelected then
        local xpForLvl = ISSkillProgressBar.getXpForLvl(self.perk, lvlSelected)

        local state = xpSystemText.locked
        local xp = 0

        if (lvlSelected < self.level) then
            state = xpSystemText.unlocked
            xp = xpForLvl
        end

        local xpText = getText("IGUI_XP_tooltipxp", round(xp, 2), xpForLvl)
        self.message = self.message:gsub(" <LINE> "..state, " <LINE> "..state.." ("..xpText..")")
    end

    if lvlSelected <= self.level and instanceof(self.char,"IsoPlayer") then
        local perkID = self.perk:getId()
        local multipliers = SRJ.xpHandler.getOrStoreXPMultipliers(self.char)
        local gainedXP = SRJ.calculateGainedSkill(self.char, self.perk)

        self.message = self.message.."\n\n<RGB:0.3,0.3,0.3> Skill Recovery Journal"

        self:registerStartingLevels()
        if ISSkillProgressBar.registeredStartingLevels and ISSkillProgressBar.registeredStartingLevels[perkID] then
            self.message = self.message.."\n<RGB:0.8,0.8,0.8> "..startingLevelText..": "..ISSkillProgressBar.registeredStartingLevels[perkID]
        end

        local currentXP = tostring(self.char:getXp():getXP(self.perk))
        self.message = self.message .. "\n<WHITE> "..totalXPText..": "..round(currentXP, 2)

        if gainedXP then
            local currentSkillGainedXP = tostring(gainedXP * (multipliers[perkID] or 1))
            self.message = self.message.."\n<GREEN> "..gainedXPText..": "..round(currentSkillGainedXP, 2)
        end

        local deductedXP = SRJ_ModDataHandler.getDeductedXP(self.char)
        if deductedXP and deductedXP[perkID] then
            self.message = self.message .. "\n<RED> "..deductedXPText..": "..round(deductedXP[perkID], 2)
        end

    end
end