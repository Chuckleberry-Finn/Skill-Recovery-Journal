Events.OnGameBoot.Add(print("Skill Recovery Journal: ver:0.3.3-ingame-time-SNAPSHOT"))

SRJ = {}

function SRJ.getGainedRecipes(player)
	local gainedRecipes = {}

	---@type ArrayList
	local knownRecipes = player:getKnownRecipes()

	for i=0, knownRecipes:size()-1 do
		local recipeID = knownRecipes:get(i)
		gainedRecipes[recipeID] = true
	end

	---@type SurvivorDesc
	local playerDesc = player:getDescriptor()

	---@type TraitCollection
	local playerTraits = player:getTraits()
	for i=0, playerTraits:size()-1 do
		local trait = playerTraits:get(i)
		---@type TraitFactory.Trait
		local traitTrait = TraitFactory.getTrait(trait)
		if traitTrait then
			local traitRecipes = traitTrait:getFreeRecipes()
			for ii=0, traitRecipes:size()-1 do
				local traitRecipe = traitRecipes:get(ii)
				gainedRecipes[traitRecipe] = nil
			end
		end
	end

	---Profession
	local playerProfessionID = playerDesc:getProfession()
	local playerProfession = ProfessionFactory.getProfession(playerProfessionID)
	if playerProfession then
		local profFreeRecipes = playerProfession:getFreeRecipes()
		for i=0, profFreeRecipes:size()-1 do
			local profRecipe = profFreeRecipes:get(i)
			gainedRecipes[profRecipe] = nil
		end
	end

	---return iterable list
	local returnedGainedRecipes = {}
	for recipeID,_ in pairs(gainedRecipes) do
		table.insert(returnedGainedRecipes, recipeID)
	end

	return returnedGainedRecipes
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
				local recoverableXPFactor = (SandboxVars.SkillRecoveryJournal.RecoveryPercentage/100) or 1

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

	if storingSkills then
		return gainedXP
	end
end
