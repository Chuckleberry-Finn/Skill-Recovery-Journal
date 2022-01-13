SRJ = {}

Events.OnGameBoot.Add(print("Skill Recovery Journal: ver:0.3.3-NewSandBoxSettings"))

function SRJ.CleanseFalseSkills(gainedXP)
	for skill,xp in pairs(gainedXP) do

		local perkList = PerkFactory.PerkList
		local junk = true

		if xp>1 then
			for i=0, perkList:size()-1 do
				---@type PerkFactory.Perk
				local perk = perkList:get(i)
				if perk and tostring(perk:getType()) == skill then
					junk = false
				end
			end
		end

		if junk then
			gainedXP[skill] = nil
		end
	end
end


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
	else
		SRJ.CleanseFalseSkills(JMD["gainedXP"])
	end

	local skillsRecord = ""
	for skill,xp in pairs(gainedXP) do
		local perk = PerkFactory.getPerk(Perks[skill])
		local perkName = perk:getName()
		local xpBasedOnPlayer = xp
		skillsRecord = skillsRecord..perkName.." ("..xpBasedOnPlayer.." xp)".."\n"
	end

	local learnedRecipes = JMD["learnedRecipes"] or {}
	local recipeNum = 0
	for k,v in pairs(learnedRecipes) do
		recipeNum = recipeNum+1
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


ISToolTipInv_setItem = ISToolTipInv.setItem
function ISToolTipInv:setItem(item)
	if item:getType() == "SkillRecoveryJournal" then
		item:setTooltip(SRJ.generateTooltip(item, self.tooltip:getCharacter()))
	end
	ISToolTipInv_setItem(self, item)
end


---@param player IsoGameCharacter
function SRJ.calculateGainedSkills(player)

	local bonusLevels = {}

	---@type SurvivorDesc
	local playerDesc = player:getDescriptor()
	local descXpMap = transformIntoKahluaTable(playerDesc:getXPBoostMap())

	for perk,level in pairs(descXpMap) do
		local perky = tostring(perk)
		local levely = tonumber(tostring(level))
		bonusLevels[perky] = levely
	end

	local gainedXP = {}
	local storingSkills = false

	--print("INFO: SkillRecoveryJournal: calculating gained skills:  total skills: "..Perks.getMaxIndex())
	for i=1, Perks.getMaxIndex()-1 do
		---@type PerkFactory.Perks
		local perks = Perks.fromIndex(i)
		if perks then
			---@type PerkFactory.Perk
			local perk = PerkFactory.getPerk(perks)
			if perk then
				local currentXP = player:getXp():getXP(perk)
				local perkType = tostring(perk:getType())

				local bonusLevelsFromTrait = bonusLevels[perkType] or 0
				local recoverableXPFactor = (SandboxVars.Character.RecoveryPercentage/100) or 1

				local recoverableXP = currentXP

				recoverableXP = math.floor(((recoverableXP-perk:getTotalXpForLevel(bonusLevelsFromTrait))*recoverableXPFactor)*1000)/1000
				if perkType == "Strength" or perkType == "Fitness" or recoverableXP==1 then
					recoverableXP = 0
				end

				--print("  "..i.." "..perkType.." = "..tostring(recoverableXP).."xp  (current:"..currentXP.." - "..perk:getTotalXpForLevel(bonusLevelsFromTrait))

				if recoverableXP > 0 then
					gainedXP[perkType] = recoverableXP
					storingSkills = true
				end
				--end
			end
		end
	end

	if not storingSkills then
		return
	end

	return gainedXP
end
