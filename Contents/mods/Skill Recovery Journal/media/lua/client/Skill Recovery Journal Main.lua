Events.OnGameBoot.Add(function() print("Skill Recovery Journal: ver:0.4-JUL12") end)

SRJ = {}

---@param player IsoPlayer|IsoGameCharacter
function SRJ.getListenedToMedia(player)

	local knownMediaLines = {}

	local ZR = getZomboidRadio():getRecordedMedia()
	local categories = ZR:getCategories()
	for i=1,categories:size() do
		local category = categories:get(i-1)
		local mediaType = RecordedMedia.getMediaTypeForCategory(category)
		local list = ZR:getAllMediaForType(mediaType)
		for j=1,list:size() do
			---@type MediaData
			local mediaData = list:get(j-1)
			local mediaDataId = mediaData:getId()

			for jj=1, mediaData:getLineCount() do
				---@type MediaData.MediaLineData
				local mediaLineData = mediaData:getLine(jj-1)
				if mediaLineData then

					--TODO: Bother Nasko about adding: this.setExposed(MediaData.MediaLineData.class); in LuaManager.java
					local lineGuid--= mediaLineData:getTextGuid()

					for i = 0, getNumClassFields(mediaLineData) - 1 do
						---@type Field
						local field = getClassField(mediaLineData, i)
						if string.find(tostring(field), "%.text") then
							lineGuid = getClassFieldVal(mediaLineData, field)
						end
					end

					if lineGuid then
						if player:isKnownMediaLine(lineGuid) then
							knownMediaLines[mediaDataId] = knownMediaLines[mediaDataId] or {}
							table.insert(knownMediaLines[mediaDataId], lineGuid)
						end
					end
				end
			end
		end
	end

	for k,v in pairs(knownMediaLines) do
		print(" -- knownMedia: "..k.."  lines: "..#v)
	end
	return knownMediaLines
end


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


function SRJ.getFreeLevelsFromProfession(player)
	local bonusLevels = {}

	local playerDesc = player:getDescriptor()
	local playerProfessionID = playerDesc:getProfession()
	local playerProfession = ProfessionFactory.getProfession(playerProfessionID)
	if playerProfession then
		local professionXpMap = transformIntoKahluaTable(playerProfession:getXPBoostMap())
		if professionXpMap then
			for perk,level in pairs(professionXpMap) do
				local perky = tostring(perk)
				local levely = tonumber(tostring(level))
				bonusLevels[perky] = levely
			end
		end
	end

	return bonusLevels
end


function SRJ.getFreeLevelsFromTraits(player)
	local bonusLevels = {}

	local playerTraits = player:getTraits()
	for i=0, playerTraits:size()-1 do
		local trait = playerTraits:get(i)
		---@type TraitFactory.Trait
		local traitTrait = TraitFactory.getTrait(trait)
		if traitTrait then
			local traitXpMap = transformIntoKahluaTable(traitTrait:getXPBoostMap())
			if traitXpMap then
				for perk,level in pairs(traitXpMap) do
					local perky = tostring(perk)
					local levely = tonumber(tostring(level))
					bonusLevels[perky] = (bonusLevels[perky] or 0) + levely
				end
			end
		end
	end

	return bonusLevels
end


---@param player IsoGameCharacter
function SRJ.calculateGainedSkills(player)

	-- calc professtion skills
	local bonusProfessionLevels = SRJ.getFreeLevelsFromProfession(player)

	--calc trait skills
	local bonusTraitLevels = SRJ.getFreeLevelsFromTraits(player)

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
				local bonusLevels = (bonusProfessionLevels[perkType] or 0) + (bonusTraitLevels[perkType] or 0)
				local recoverableXPFactor = (SandboxVars.SkillRecoveryJournal.RecoveryPercentage/100) or 1

				if perk:isPassiv() and tostring(perk:getParent():getType())~="None" then
					local pMD = player:getModData()
					if pMD.recoveryJournalPassiveSkillsInit then
						bonusLevels = pMD.recoveryJournalPassiveSkillsInit[perkType] or 0
					end
				end

				local recoverableXP = math.floor(((currentXP-perk:getTotalXpForLevel(bonusLevels))*recoverableXPFactor)*1000)/1000

				if perk:isPassiv() and (SandboxVars.SkillRecoveryJournal.RecoverPassiveSkills == false) then
					recoverableXP = 0
				elseif perk:getParent():getId()=="Combat" and (SandboxVars.SkillRecoveryJournal.RecoverCombatSkills == false) then
					recoverableXP = 0
				elseif perk:getParent():getId()=="Firearm" and (SandboxVars.SkillRecoveryJournal.RecoverFirearmSkills == false) then
					recoverableXP = 0
				elseif perk:getParent():getId()=="Crafting" and (SandboxVars.SkillRecoveryJournal.RecoverCraftingSkills == false) then
					recoverableXP = 0
				elseif perk:getParent():getId()=="Survivalist" and (SandboxVars.SkillRecoveryJournal.RecoverSurvivalistSkills == false) then
					recoverableXP = 0
				elseif perk:getParent():getId()=="Agility" and (SandboxVars.SkillRecoveryJournal.RecoverAgilitySkills == false) then
					recoverableXP = 0
				end

				if recoverableXP > 0 then
					--[DEBUG]] print(" - "..perkType.." = "..tostring(recoverableXP).."xp  current:"..currentXP.." - "..bonusLevels.." ("..perk:getTotalXpForLevel(bonusLevels).."xp)")
					gainedXP[perkType] = recoverableXP
					storingSkills = true
				end
			end
		end
	end

	if not storingSkills then
		return
	end

	return gainedXP
end