local SRJ = {}

function SRJ.setOrGetRecoverableXP(player)
	local pMD = player:getModData()
	pMD.recoverableXP = pMD.recoverableXP or {}
	return pMD.recoverableXP
end


---@param player IsoPlayer|IsoGameCharacter
local function applyOldXP(id, player)
	local pMD = player:getModData()
	if pMD.bRolledOverOldXP then return end
	---Clear out old variable
	pMD.bSyncedOldXP = nil
	pMD.bRolledOverOldXP = true

	if player:getHoursSurvived() > 1 then
		---@type IsoGameCharacter.XP
		local pXP = player:getXp()
		local startingLevels = SRJ.getFreeLevelsFromTraitsAndProfession(player)
		local recoverableXP = SRJ.setOrGetRecoverableXP(player)
		for i=1, Perks.getMaxIndex()-1 do
			---@type PerkFactory.Perk
			local perk = Perks.fromIndex(i)
			if perk and perk:getParent():getId()~="None" then
				local perkID = perk:getId()
				local oldPassiveFixXP = pMD.recoveryJournalPassiveSkillsInit and pMD.recoveryJournalPassiveSkillsInit[perkID]
				local currentRecoverableXP = oldPassiveFixXP or recoverableXP[perkID] or 0

				local actualCurrentXP = pXP:getXP(perk)
				if perk:isPassiv() then
					if player:getHoursSurvived()>1 then
						actualCurrentXP = math.max(0,actualCurrentXP-perk:getTotalXpForLevel(5))
					else
						actualCurrentXP = 0
					end
				else
					local startingPerkLevel = startingLevels[perkID]
					if startingPerkLevel then actualCurrentXP = actualCurrentXP-perk:getTotalXpForLevel(startingPerkLevel) end
				end

				local appliedXP = math.max(actualCurrentXP,currentRecoverableXP)
				if appliedXP and appliedXP>0 then recoverableXP[perkID] = appliedXP end
			end
		end
	end
	pMD.recoveryJournalPassiveSkillsInit = nil
end
Events.OnCreatePlayer.Add(applyOldXP)

SRJ.exceptions = {"berserkBeaver - main"}
SRJ.fileFuncNoTVXP = "ISRadioInteractions"
function SRJ.recordXPGain(player, perksType, XP, info, maxLevelXP)
	if info then
		for n,exception in pairs(SRJ.exceptions) do if info[exception] then return end end
		---checking if it's false instead of 'not true' because I want older saves before this sandbox option to get what they expect to occur
		if SandboxVars.SkillRecoveryJournal.TranscribeTVXP==false and info[SRJ.fileFuncNoTVXP] then return end
	end

	local perkID = perksType:getId()
	local recoverableXP = SRJ.setOrGetRecoverableXP(player)

	recoverableXP[perkID] = (recoverableXP[perkID] or 0) + XP
	recoverableXP[perkID] = math.max(recoverableXP[perkID],0)
	if maxLevelXP then recoverableXP[perkID] = math.min(recoverableXP[perkID],maxLevelXP) end
end

function SRJ.getReadXP(player)
	local pMD = player:getModData()

	pMD.recoveryJournalXpLog = pMD.recoveryJournalXpLog or {}
	return pMD.recoveryJournalXpLog
end


function SRJ.calculateGainedSkills(player)

	local gainedXP-- = {}
	local recoverableXP = SRJ.setOrGetRecoverableXP(player)
	local recoverableXPFactor = (SandboxVars.SkillRecoveryJournal.RecoveryPercentage/100) or 1

	for perkID,XP in pairs(recoverableXP) do

		---@type PerkFactory.Perk
		local perkActual = Perks.FromString(perkID)
		if perkActual then

			local notRecoverPassive = perkActual:isPassiv() and (SandboxVars.SkillRecoveryJournal.RecoverPassiveSkills == false)
			local notRecoverParent = SandboxVars.SkillRecoveryJournal["Recover"..perkActual:getParent():getId().."Skills"]==false

			if perkActual and (not notRecoverPassive) and (not notRecoverParent) then
				gainedXP = gainedXP or {}
				gainedXP[perkID] = XP*recoverableXPFactor
			end

		end
	end
	return gainedXP
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


function SRJ.getFreeLevelsFromTraitsAndProfession(player)
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
				bonusLevels[perky] = (bonusLevels[perky] or 0) + levely
			end
		end
	end

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


return SRJ

--[[
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

					if lineGuid and player.isKnownMediaLine and player:isKnownMediaLine(lineGuid) then
						knownMediaLines[mediaDataId] = knownMediaLines[mediaDataId] or {}
						table.insert(knownMediaLines[mediaDataId], lineGuid)
					end
				end
			end
		end
	end

	if getDebug() then for k,v in pairs(knownMediaLines) do print(" -- knownMedia: "..k.."  lines: "..#v) end end
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
					--print(" - "..perkType.." = "..tostring(recoverableXP).."xp  current:"..currentXP.." - "..bonusLevels.." ("..perk:getTotalXpForLevel(bonusLevels).."xp)")
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
--]]