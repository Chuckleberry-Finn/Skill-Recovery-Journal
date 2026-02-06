require "XpSystem/ISUI/ISSkillProgressBar"

local totalXPText = getText("IGUI_Total").." "..getText("IGUI_XP_xp")
local gainedXPText = getText("IGUI_GainedXPText")
local startingLevelText = getText("IGUI_StartingLevelText")
local deductedXPText = getText("IGUI_DeductedXP")
local untranscribedXPText = getText("IGUI_UntranscribedXP")

local SRJ = require "Skill Recovery Journal Main"


local ISSkillProgressBar_updateTooltip = ISSkillProgressBar.updateTooltip
function ISSkillProgressBar:updateTooltip(lvlSelected)
    ISSkillProgressBar_updateTooltip(self, lvlSelected)
    ---Show XP even when unlocked - helpful for tracking XP values

    local xpForLvl = ISSkillProgressBar.getXpForLvl(self.perk, lvlSelected)
    if self.level ~= lvlSelected then

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

        self.message = self.message.." <LINE><LINE> <RGB:0.3,0.3,0.3> Skill Recovery Journal"

        -- show starting level
        local traitLevels = SRJ.modDataHandler.getFreeLevelsFromTraitsAndProfession(self.char)
        local passiveLevels = SRJ.modDataHandler.getPassiveLevels(self.char)
        local startingLevel = passiveLevels[perkID] or traitLevels[perkID] or 0
        if startingLevel then
            self.message = self.message.." <LINE> <RGB:0.8,0.8,0.8> "..startingLevelText..": "..startingLevel
        end

        -- show total xp
        local currentXP = tostring(self.char:getXp():getXP(self.perk))
        self.message = self.message .. " <LINE> <RGB:1,1,1> "..totalXPText..": "..round(currentXP, 2)

        -- show mod data values on SP only (in MP client does not have up2date info)
        if getDebug() and not isClient() then 
            -- show gained xp
            if gainedXP then
                local currentSkillGainedXP = tostring(gainedXP * (multipliers[perkID] or 1))
                self.message = self.message.." <LINE> <GREEN> "..gainedXPText..": "..round(currentSkillGainedXP, 2)
            end

            -- show deducted xp
            local charDeductedXP = SRJ.modDataHandler.getDeductedXP(self.char)
            local deductedXP = charDeductedXP and charDeductedXP[perkID]

            if deductedXP then
                self.message = self.message .. " <LINE> <ORANGE> "..deductedXPText..": "..round(deductedXP, 2)
            end

            -- show untranscribed xp
            local charReadXP = SRJ.modDataHandler.getReadXP(self.char)
            local readXP = charReadXP and charReadXP[perkID]
            local startingLevelXP = startingLevel and self.perk:getXpForLevel(startingLevel)
            local looseXP = currentXP - (startingLevelXP or 0) - (deductedXP or 0) - (readXP or 0) --untranscribed XP
            if looseXP then
                self.message = self.message .. " <LINE> <RED> "..untranscribedXPText..": "..round(looseXP, 2)
            end
        end
    end
end