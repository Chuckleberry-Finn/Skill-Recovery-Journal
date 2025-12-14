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


function SRJ.setOrGetDeductedXP(player)
	local pMD = player:getModData()
	pMD.deductedXP = pMD.deductedXP or {}
	return pMD.deductedXP
end


SRJ.maxXPDifferential = {}
function SRJ.getMaxXPDifferential(perk)
	if SRJ.maxXPDifferential[perk] then return SRJ.maxXPDifferential[perk] end
	local maxXPDefault = Perks.PhysicalCategory:getTotalXpForLevel(10)
	local maxXPPerk = Perks[perk]:getTotalXpForLevel(10)

	SRJ.maxXPDifferential[perk] =maxXPDefault/maxXPPerk
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


---@param player IsoGameCharacter|IsoPlayer
function SRJ.checkFitnessCanAddXp(player)
	if player:getNutrition():canAddFitnessXp() then return end

	local fitness = player:getPerkLevel(Perks.Fitness)

	local under, extremeUnder = player:hasTrait(CharacterTrait.UNDERWEIGHT), (player:hasTrait(CharacterTrait.EMACIATED) or player:hasTrait(CharacterTrait.VERY_UNDERWEIGHT))
	local over, extremeOver = player:hasTrait(CharacterTrait.OVERWEIGHT), player:hasTrait(CharacterTrait.OBESE)

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

	-- xp granted by profession
	local playerDesc = player:getDescriptor()
	local playerProfessionID = playerDesc:getCharacterProfession()
	local profDef = CharacterProfessionDefinition.getCharacterProfessionDefinition(playerProfessionID)
	local profXpBoost = transformIntoKahluaTable(profDef:getXpBoosts())
	if profXpBoost then
		for perk,level in pairs(profXpBoost) do
			local perky = tostring(perk)
			local levely = tonumber(tostring(level))
			bonusLevels[perky] = levely
		end
	end

	-- xp granted by trait
	local playerTraits = player:getCharacterTraits()
	for i=0, playerTraits:getKnownTraits():size()-1 do
		local traitTrait = playerTraits:getKnownTraits():get(i)
		local traitDef = CharacterTraitDefinition.getCharacterTraitDefinition(traitTrait)
		local traitXpBoost = transformIntoKahluaTable(traitDef:getXpBoosts())
		if traitXpBoost then
			for perk,level in pairs(traitXpBoost) do
				local perky = tostring(perk)
				local levely = tonumber(tostring(level))
				bonusLevels[perky] = (bonusLevels[perky] or 0) + levely
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
	
	--if getDebug() then print("bSkillValid check sandbox option 'SkillRecoveryJournal.Recover"..ID.."Skills' -> ".. tostring(specific)) end
	if specific and type(specific)~="number" then specific = correction end

	local default = SandboxVars.SkillRecoveryJournal.RecoveryPercentage or 100

	local recoverPercentage = ((specific==nil) or (specific==-1)) and default or specific

	return (not (recoverPercentage <= 0)), (recoverPercentage/100)
end

-- returns all gained skills as per config or false if no valid skill xp gained
function SRJ.calculateGainedSkill(player, perk, passiveSkillsInit, startingLevels, deductibleXP)

	if not passiveSkillsInit then
		passiveSkillsInit = SRJ.getPassiveLevels(player)
	end

	if not startingLevels then
		startingLevels = SRJ.getFreeLevelsFromTraitsAndProfession(player)
	end

	if not deductibleXP then
		deductibleXP = SRJ.setOrGetDeductedXP(player)
	end

	if perk and perk:getParent():getId()~="None" then
		local perkXP = player:getXp():getXP(perk)
		if perkXP > 0 then
			local perkID = perk:getId()
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

			if recoverableXP > 0 then

				--local deductBonusXP = SandboxVars.SkillRecoveryJournal.RecoverProfessionAndTraitsBonuses ~= true
				--if deductBonusXP then
				recoverableXP = SRJ.xpHandler.unBoostXP(player,perk,recoverableXP)
				--if getDebug() then print(" recoverableXP-unboosted: ",recoverableXP) end
				--end
				local gainedXP = recoverableXP * recoveryPercentage
				--if getDebug() then print(" FINAL: ", gainedXP) end
				return gainedXP
			end
		end
	end

	return false
end

-- returns all gained skills as per config or nil if no valid skill xp gained
function SRJ.calculateAllGainedSkills(player)
	local gainedXP

	local passiveSkillsInit = SRJ.getPassiveLevels(player)
	local startingLevels = SRJ.getFreeLevelsFromTraitsAndProfession(player)
	local deductibleXP = SRJ.setOrGetDeductedXP(player)

	for i=1, Perks.getMaxIndex()-1 do
		---@type PerkFactory.Perk
		local perk = Perks.fromIndex(i)
		local gained = SRJ.calculateGainedSkill(player, perk, passiveSkillsInit, startingLevels, deductibleXP)
		if gained then
			--if getDebug() then print("calculateAllGainedSkills gained " .. gained) end
			gainedXP = gainedXP or {}
			gainedXP[perk:getId()] = gained
		end
	end

	return gainedXP
end


function SRJ.getGainedRecipes(player)
	local gainedRecipes = {}

	-- get all recipes known by player
	---@type ArrayList
	local knownRecipes = player:getKnownRecipes()
	for i=0, knownRecipes:size()-1 do
		local recipeID = knownRecipes:get(i)
		gainedRecipes[recipeID] = true
		
		--if getDebug() then print("Adding known recipe " .. tostring(recipeID)) end
	end

	---@type SurvivorDesc
	local playerDesc = player:getDescriptor()

	-- remove freebies granted by profession
	local playerProfessionID = playerDesc:getCharacterProfession()
	local profDef = CharacterProfessionDefinition.getCharacterProfessionDefinition(playerProfessionID)
	local profFreeRecipes = profDef:getGrantedRecipes() 
	for i=0, profFreeRecipes:size()-1 do
		local profRecipe = profFreeRecipes:get(i)
		gainedRecipes[profRecipe] = nil
		--if getDebug() then print("Removing gained prof recipe " .. tostring(profRecipe)) end
	end

	-- remove freebies granted by trait
	local playerTraits = player:getCharacterTraits()
	for i=0, playerTraits:getKnownTraits():size()-1 do
		local traitTrait = playerTraits:getKnownTraits():get(i)
		local traitDef = CharacterTraitDefinition.getCharacterTraitDefinition(traitTrait)
		local traitRecipes = traitDef:getGrantedRecipes()
		for ii=0, traitRecipes:size()-1 do
			local traitRecipe = traitRecipes:get(ii)
			gainedRecipes[traitRecipe] = nil
			--if getDebug() then print("Removing gained trait recipe " .. tostring(traitRecipe)) end
		end
	end

	--- return iterable list
	local returnedGainedRecipes = {}
	for recipeID,_ in pairs(gainedRecipes) do
		-- TODO: remove auto learned recipes from skills (maybe we had higher level/xpBoost last life)
		table.insert(returnedGainedRecipes, recipeID)
		--if getDebug() then print("Resulting gained recipe " .. tostring(recipeID) .. " -> " .. tostring(_)) end
	end

	return returnedGainedRecipes
end


return SRJ