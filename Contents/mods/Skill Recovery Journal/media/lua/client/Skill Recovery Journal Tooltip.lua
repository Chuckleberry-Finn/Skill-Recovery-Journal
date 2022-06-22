require "ISUI/ISToolTipInv"

---@param journal InventoryItem | Literature
---@param player IsoGameCharacter | IsoPlayer
function SRJ.generateTooltip(journal, player)

	journal:setNumberOfPages(-1)
	journal:setCanBeWrite(false)

	local journalModData = journal:getModData()
	local JMD = journalModData["SRJ"]

	local blankJournalTooltip = getText("IGUI_Tooltip_Empty")

	if not JMD or not JMD["author"] then
		return blankJournalTooltip
	end

	local gainedXP = JMD["gainedXP"]
	if not gainedXP then
		return blankJournalTooltip
	end

	local skillsRecord = ""
	for skill,xp in pairs(gainedXP) do
		local perk = PerkFactory.getPerk(Perks[skill])
		if perk then

			local journalXP = xp

			journalModData.recoveryJournalXpLog = journalModData.recoveryJournalXpLog or {}
			local jmdUsedXP = journalModData.recoveryJournalXpLog

			if SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true and jmdUsedXP[skill] then
				journalXP = journalXP-jmdUsedXP[skill]
			end

			local perkName = perk:getName()
			local xpBasedOnPlayer = math.floor(journalXP*100)/100
			skillsRecord = skillsRecord..perkName.." ("..xpBasedOnPlayer

			if SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true and jmdUsedXP[skill] then
				skillsRecord = skillsRecord.."/"..xp
			end

			skillsRecord = skillsRecord.." xp)".."\n"
		end
	end

	local learnedRecipes = JMD["learnedRecipes"] or {}
	local recipeNum = 0

	if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then
		for k,v in pairs(learnedRecipes) do
			recipeNum = recipeNum+1
		end
	end

	if recipeNum>0 then
		local properPlural = getText("IGUI_Tooltip_Recipe")
		if recipeNum>1 then
			properPlural = getText("IGUI_Tooltip_Recipes")
		end
		skillsRecord = skillsRecord..recipeNum.." "..properPlural..".".."\n"
	end

	skillsRecord = "\n"..getText("IGUI_Tooltip_Start").." "..JMD["author"]..getText("IGUI_Tooltip_End").."\n"..skillsRecord

	return skillsRecord
end


local ISToolTipInv_setItem = ISToolTipInv.setItem
function ISToolTipInv:setItem(item)
	ISToolTipInv_setItem(self, item)
	if item:getType() == "SkillRecoveryJournal" then
		item:setTooltip(SRJ.generateTooltip(item, self.tooltip:getCharacter()))
	end
end