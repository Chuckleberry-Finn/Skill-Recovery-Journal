local SRJ = {}

SRJ.xpPatched = false

SRJ.xpHandler = require "Skill Recovery Journal XP"


function SRJ.backgroundFix(journalModData, journal)
	---background fixes / changes / updates to how journals work
	local backgroundFix = journalModData.backgroundFix or 0
	local currentBackgroundFix = 1

	if journal:getType() == "SkillRecoveryBoundJournal" and (backgroundFix ~= currentBackgroundFix) then
		journalModData.backgroundFix = currentBackgroundFix

		---fix name issues where decayed was added incorrectly -DEC23
		local currentName = journal:getName()
		currentName=currentName:gsub("%s+%(Decayed%)","")
		journal:setName(currentName)

		local JMD = journalModData["SRJ"]
		if JMD and (not journalModData.oldXP) then
			journalModData.oldXP = {}
			local XpStoredInJournal = JMD["gainedXP"]
			for skill,xp in pairs(XpStoredInJournal) do
				journalModData.oldXP[skill] = xp
			end
		end
	end
end



---@param itemObj InventoryItem
---@param player IsoPlayer|IsoGameCharacter|IsoMovingObject|IsoObject
function SRJ.convertJournal(itemObj, player)
	if itemObj:getType() == "SkillRecoveryJournal" and (not itemObj:getModData().SRJ_kludge) then
		---@type ItemContainer
		local container = itemObj:getContainer()
		if container and container:isInCharacterInventory(player) then
			itemObj:getModData().SRJ_kludge = true
			local newJournal = InventoryItemFactory.CreateItem("SkillRecoveryBoundJournal")
			local oldModData = itemObj:getModData()["SRJ"]
			newJournal:getModData()["SRJ"] = copyTable(oldModData)
			container:AddItem(newJournal)
			container:Remove(itemObj)
		end
	end
end


function SRJ.setOrGetDeductedXP(player)
	local pMD = player:getModData()
	pMD.deductedXP = pMD.deductedXP or {}
	return pMD.deductedXP
end


SRJ.maxXPDifferential = {}
function SRJ.getMaxXPDifferential(perk)
	if SRJ.maxXPDifferential[perk] then return SRJ.maxXPDifferential[perk] end
	local maxXPDefault = Perks.Passiv:getTotalXpForLevel(10)
	local maxXPPerk = Perks[perk]:getTotalXpForLevel(10)
	SRJ.maxXPDifferential[perk] = maxXPDefault/maxXPPerk
	return SRJ.maxXPDifferential[perk]
end


function SRJ.checkForDeductedXP(player,perksType,XP)
	local fN, lCF = nil, getCoroutineCallframeStack(getCurrentCoroutine(),0)
	local fD = lCF ~= nil and lCF and getFilenameOfCallframe(lCF)
	local i = fD and fD:match('^.*()/')
	fN = i and fD:sub(i+1):gsub(".lua", "")

	if fN and fN=="ISRadioInteractions" then
		--if getDebug() then print("deductibleXP: `",fN,"` \n (",perksType,", ",XP," )") end
		local perkID = perksType:getId()
		local deductibleXP = SRJ.setOrGetDeductedXP(player)
		deductibleXP[perkID] = (deductibleXP[perkID] or 0) + XP
	end
end


function SRJ.clearOldXPParams(pMD)
	---Clear out old variable
	pMD.bSyncedOldXP = nil
	pMD.bRolledOverOldXP = nil
	pMD.recoverableXP = nil
	pMD.recoveryJournalPassiveSkillsInit = nil
end


function SRJ.getPassiveLevels(player)
	local pMD = player:getModData()
	return pMD.SRJPassiveSkillsInit
end


function SRJ.setPassiveLevels(id, player)
	local pMD = player:getModData()

	SRJ.clearOldXPParams(pMD)

	if not pMD.SRJPassiveSkillsInit then
		for i=1, Perks.getMaxIndex()-1 do
			---@type PerkFactory.Perks
			local perks = Perks.fromIndex(i)
			if perks then
				---@type PerkFactory.Perk
				local perk = PerkFactory.getPerk(perks)
				if perk and perk:isPassiv() and tostring(perk:getParent():getType())~="None" then
					local currentLevel = (player:getHoursSurvived() > 0 and 5) or player:getPerkLevel(perk)
					if currentLevel > 0 then
						local perkType = tostring(perk:getType())
						pMD.SRJPassiveSkillsInit = pMD.SRJPassiveSkillsInit or {}
						pMD.SRJPassiveSkillsInit[perkType] = currentLevel
					end
				end
			end
		end
	end
	--if getDebug() then for k,v in pairs(pMD.SRJPassiveSkillsInit) do print(" -- PASSIVE-INIT: "..k.." = "..v) end end
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


function SRJ.getReadXP(player)
	local pMD = player:getModData()

	pMD.recoveryJournalXpLog = pMD.recoveryJournalXpLog or {}
	return pMD.recoveryJournalXpLog
end


function SRJ.correctSandBoxOptions(ID)
	if SandboxVars.SkillRecoveryJournal[ID] == false then
		SandboxVars.SkillRecoveryJournal[ID] = 0
		return 0
	elseif SandboxVars.SkillRecoveryJournal[ID] == true then
		local recoverRate = SandboxVars.SkillRecoveryJournal.RecoveryPercentage or 100
		SandboxVars.SkillRecoveryJournal[ID] = recoverRate
		return recoverRate
	end
end


function SRJ.bSkillValid(perk)
	local ID = perk and perk:isPassiv() and "Passive" or perk:getParent():getId()

	local correction = SRJ.correctSandBoxOptions("Recover"..ID.."Skills")

	local specific = SandboxVars.SkillRecoveryJournal["Recover"..ID.."Skills"]
	if specific and type(specific)~="number" then specific = correction end

	local default = SandboxVars.SkillRecoveryJournal.RecoveryPercentage or 100

	local recoverPercentage = ((specific==nil) or (specific==-1)) and default or specific

	return (not (recoverPercentage <= 0)), (recoverPercentage/100)
end


function SRJ.calculateGainedSkills(player)

	local gainedXP-- = {}
	local deductibleXP = SRJ.setOrGetDeductedXP(player)
	local passiveSkillsInit = SRJ.getPassiveLevels(player)

	local pXP = player:getXp()
	local startingLevels = SRJ.getFreeLevelsFromTraitsAndProfession(player)

	for i=1, Perks.getMaxIndex()-1 do
		---@type PerkFactory.Perk
		local perk = Perks.fromIndex(i)
		if perk and perk:getParent():getId()~="None" then
			local perkID = perk:getId()
			local perkXP = pXP:getXP(perk)
			if perkXP > 0 then
				--if getDebug() then print("perkXP: ",perkID," = ",perkXP) end

				---figure out how much XP was present at player start
				local passivePerkFixLevel = passiveSkillsInit and passiveSkillsInit[perkID]
				local passiveFixXP = passivePerkFixLevel and perk:getTotalXpForLevel(passivePerkFixLevel)
				--if getDebug() then print(" -passiveFixXP:",passiveFixXP,"  (",passivePerkFixLevel,")") end

				local startingPerkLevel = startingLevels[perkID]
				local startingPerkXP = startingPerkLevel and perk:getTotalXpForLevel(startingPerkLevel) or 0
				--if getDebug() then print(" -startingPerkXP:",startingPerkXP,  "(",startingPerkLevel,")") end

				local deductedXP = (SandboxVars.SkillRecoveryJournal.TranscribeTVXP==false) and deductibleXP[perkID] or 0
				--if getDebug() then print(" -deductedXP:",deductedXP) end

				local sandboxOptionRecover, recoveryPercentage = SRJ.bSkillValid(perk)

				local recoverableXP = sandboxOptionRecover and perkXP-(passiveFixXP or startingPerkXP)-deductedXP or 0
				--if getDebug() then print(" -recoverableXP-deductions: ",recoverableXP) end

				if recoverableXP>0 then

					--local deductBonusXP = SandboxVars.SkillRecoveryJournal.RecoverProfessionAndTraitsBonuses ~= true
					--if deductBonusXP then
					recoverableXP = SRJ.xpHandler.unBoostXP(player,perk,recoverableXP)
					--if getDebug() then print(" recoverableXP-unboosted: ",recoverableXP) end
					--end

					gainedXP = gainedXP or {}
					gainedXP[perkID] = recoverableXP*recoveryPercentage

					--if getDebug() then print(" FINAL: ", gainedXP[perkID]) end
				end
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


return SRJ