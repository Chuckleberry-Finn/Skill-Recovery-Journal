Events.OnGameBoot.Add(print("Skill Recovery Journal: ver:0.3.4-no-progress-SNAPSHOT"))

SRJ = {}

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
