local SRJ = {}

SRJ.xpPatched = false

SRJ.xpHandler = require "Skill Recovery Journal XP"


function SRJ.getPerk(perk)
	if not perk then return nil end
	if type(perk) == "table" or type(perk) == "userdata" then return perk end
	if type(perk) == "string" then
		local perkObj = Perks[perk]
		if not perkObj and PerkFactory then
			perkObj = PerkFactory.getPerk(perk)
			if not perkObj and Perks.FromString then
				perkObj = Perks.FromString(perk)
			end
			if not perkObj and Perks.fromSymbol then
				perkObj = Perks.fromSymbol(perk)
			end
		end
		return perkObj
	end
	return nil
end


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


function SRJ.setOrGetDeductedXP(player)
	local pMD = player:getModData()
	pMD.deductedXP = pMD.deductedXP or {}
	return pMD.deductedXP
end


SRJ.maxXPDifferential = {}
function SRJ.getMaxXPDifferential(perk)
	local perkObj = SRJ.getPerk(perk)
	local perkID = perkObj and perkObj:getId() or tostring(perk)
	if SRJ.maxXPDifferential[perkID] then return SRJ.maxXPDifferential[perkID] end
	local maxXPDefault = Perks.Passiv and Perks.Passiv:getTotalXpForLevel(10) or 32775
	local maxXPPerk = perkObj and perkObj:getTotalXpForLevel(10) or 32775
	if not maxXPPerk or maxXPPerk == 0 then maxXPPerk = 32775 end
	SRJ.maxXPDifferential[perkID] = maxXPDefault / maxXPPerk
	return SRJ.maxXPDifferential[perkID]
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


function SRJ.setPassiveLevels(id, playerObj)
	if not playerObj then return end
	local pMD = playerObj:getModData()

	SRJ.clearOldXPParams(pMD)

	if not pMD.SRJPassiveSkillsInit then
		for i=1, Perks.getMaxIndex()-1 do
			---@type PerkFactory.Perks
			local perks = Perks.fromIndex(i)
			if perks then
				---@type PerkFactory.Perk
				local perk = PerkFactory.getPerk(perks)
				if perk and perk:isPassiv() and tostring(perk:getParent():getType())~="None" then
					local currentLevel = playerObj:getPerkLevel(perk)
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


---@param player IsoGameCharacter|IsoPlayer
function SRJ.checkFitnessCanAddXp(player)
	if player:getNutrition():canAddFitnessXp() then return end

	local fitness = player:getPerkLevel(Perks.Fitness)

	local under, extremeUnder = player:HasTrait("Underweight"), (player:HasTrait("Emaciated") or player:HasTrait("Very Underweight"))
	local over, extremeOver = player:HasTrait("Overweight"), player:HasTrait("Obese")

	local mildIssue = under or over
	local extremeIssue = extremeUnder or extremeOver

	local blockAddXp = false

	if ( fitness >= 9 and (extremeIssue or mildIssue) ) then
		blockAddXp = true

	elseif ( fitness < 6 ) then
		--blockAddXp = false

	elseif extremeIssue then
		blockAddXp = true
	end

	local message = ((under or extremeUnder) and "IGUI_PlayerText_NeedGainWeight") or ((over or extremeOver) and "IGUI_PlayerText_NeedLoseWeight")

	return blockAddXp, message
end


--TODO: Implement this
function SRJ.checkProteinLevelMulti(player)
	local multi = 1
	if player:getNutrition():getProteins() > 50 and player:getNutrition():getProteins() < 300 then multi = 1.5
	elseif player:getNutrition():getProteins() < -300 then multi = 0.7
	end
	return multi
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
	perk = SRJ.getPerk(perk)
	if not perk then return false, 0 end
	local ID = perk:isPassiv() and "Passive" or (perk:getParent() and perk:getParent():getId() or "None")

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


---Dynamic check to determine if a trait should be excluded from journal transcription.
---Excludes negative traits, profession free traits, and traits that grant skill boosts/levels (skill-derived traits).
---@param traitID string
---@param player IsoGameCharacter|IsoPlayer
---@param profFreeTraitsLookup table|nil
function SRJ.isTraitExcluded(traitID, player, profFreeTraitsLookup)
	if not traitID then return true end

	local traitObj = TraitFactory.getTrait(traitID)
	if not traitObj then return true end

	-- Exclude negative traits
	if (traitObj.isCostNegative and traitObj:isCostNegative()) or (traitObj.getCost and traitObj:getCost() < 0) then
		return true
	end

	-- Exclude free profession traits
	if profFreeTraitsLookup and profFreeTraitsLookup[traitID] then
		return true
	end

	-- Dynamic check: Exclude traits that provide XP boosts or starting skill levels
	-- This catches Stout, Strong, Fit, Athletic, Handy, etc., plus any modded skill-derived traits.
	local xpBoostMap = traitObj:getXPBoostMap()
	if xpBoostMap then
		if type(xpBoostMap.isEmpty) == "function" and not xpBoostMap:isEmpty() then
			return true
		elseif type(xpBoostMap.size) == "function" and xpBoostMap:size() > 0 then
			return true
		elseif type(xpBoostMap) == "table" and next(xpBoostMap) ~= nil then
			return true
		end
	end

	return false
end


function SRJ.getGainedTraits(player)
	local gainedTraits = {}
	local playerTraits = player:getTraits()

	-- Build lookup of profession free traits to strictly exclude
	local profFreeTraitsLookup = {}
	local playerDesc = player:getDescriptor()
	local playerProfessionID = playerDesc and playerDesc:getProfession()
	local playerProfession = playerProfessionID and ProfessionFactory.getProfession(playerProfessionID)
	if playerProfession then
		local profFreeTraits = playerProfession:getFreeTraits()
		if profFreeTraits then
			for i = 0, profFreeTraits:size() - 1 do
				local profTrait = profFreeTraits:get(i)
				if profTrait then
					profFreeTraitsLookup[tostring(profTrait)] = true
				end
			end
		end
	end

	for i = 0, playerTraits:size() - 1 do
		local traitID = tostring(playerTraits:get(i))
		if traitID and not SRJ.isTraitExcluded(traitID, player, profFreeTraitsLookup) then
			gainedTraits[traitID] = true
		end
	end

	local returnedGainedTraits = {}
	for traitID, _ in pairs(gainedTraits) do
		table.insert(returnedGainedTraits, traitID)
	end

	return returnedGainedTraits
end


function SRJ.isJournalFullyDrained(JMD, player)
	if not JMD then return true end

	-- Check unlearned recipes
	if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true and JMD["learnedRecipes"] then
		for recipeID, _ in pairs(JMD["learnedRecipes"]) do
			if not player:isRecipeKnown(recipeID) then
				return false
			end
		end
	end

	-- Check unlearned traits
	if SandboxVars.SkillRecoveryJournal.RecoverTraits ~= false and JMD["learnedTraits"] then
		for traitID, _ in pairs(JMD["learnedTraits"]) do
			if not player:HasTrait(traitID) then
				return false
			end
		end
	end

	-- Check unread XP
	local storedJournalXP = JMD["gainedXP"]
	if storedJournalXP then
		local readXP = SRJ.getReadXP(player)
		local journalModData = player:getModData()
		local jmdUsedXP = journalModData and journalModData.recoveryJournalXpLog or {}
		local oneTimeUse = (SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true)

		for skill, xp in pairs(storedJournalXP) do
			local perk = SRJ.getPerk(skill)
			if perk and SRJ.bSkillValid(perk) then
				local currentlyRead = readXP and readXP[skill] or 0
				if oneTimeUse and jmdUsedXP[skill] then
					currentlyRead = math.max(currentlyRead, jmdUsedXP[skill])
				end
				if currentlyRead < (xp - 0.01) then
					return false
				end
			end
		end
	end

	-- Check unadded kills
	if (SandboxVars.SkillRecoveryJournal.KillsTrack or 0) > 0 and JMD.kills then
		local readXP = SRJ.getReadXP(player)
		local readZKills = readXP and readXP.kills and readXP.kills.Zombie or 0
		local readSKills = readXP and readXP.kills and readXP.kills.Survivor or 0
		if JMD.kills.Zombie and JMD.kills.Zombie > readZKills then return false end
		if JMD.kills.Survivor and JMD.kills.Survivor > readSKills then return false end
	end

	return true
end


return SRJ
