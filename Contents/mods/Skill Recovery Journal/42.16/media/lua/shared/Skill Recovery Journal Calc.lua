local SRJ = require "Skill Recovery Journal Main"

-- returns all gained skills as per config or false if no valid skill xp gained
function SRJ.calculateGainedSkill(player, perk, startingLevels, deductibleXP, flatXP)
	
	if not startingLevels then
		startingLevels = SRJ.modDataHandler.getFreeLevelsFromTraitsAndProfession(player)
	end

	if not deductibleXP then
		deductibleXP = SRJ.modDataHandler.getDeductedXP(player)
	end

	if not flatXP then
		flatXP = SRJ.modDataHandler.getFlatXP(player)
	end

	if perk and perk:getParent():getId()~="None" then
		local perkXP = player:getXp():getXP(perk)
		if perkXP > 0 then
			local perkID = perk:getId()

			local startingPerkLevel = startingLevels[perkID]
			local startingPerkXP = startingPerkLevel and perk:getTotalXpForLevel(startingPerkLevel) or 0

			local deductedXP = (SandboxVars.SkillRecoveryJournal.TranscribeTVXP==false) and deductibleXP[perkID] or 0

			local sandboxOptionRecover, recoveryPercentage = SRJ.bSkillValid(perk)

			local recoverableXP = sandboxOptionRecover and perkXP-startingPerkXP-deductedXP or 0

			if recoverableXP > 0 then
				local normalizedScale = SRJ.xpHandler.getSkillXPNormalizeScale(perkID) or 1
				local flatPortion = math.min(flatXP[perkID] or 0, recoverableXP)
				local boostedPortion = recoverableXP - flatPortion
				local gainedXP = boostedPortion > 0 and (SRJ.xpHandler.unBoostXP(player, perk, boostedPortion) * recoveryPercentage * normalizedScale) or nil
				local flatGained = flatPortion > 0 and (flatPortion * recoveryPercentage) or nil
				return gainedXP, flatGained
			end
		end
	end

	return false
end



function SRJ.calculateAllGainedSkills(player)
	local gainedXP
	local flatGainedXP

	local startingLevels = SRJ.modDataHandler.getFreeLevelsFromTraitsAndProfession(player)
	local deductibleXP = SRJ.modDataHandler.getDeductedXP(player)
	local flatXP = SRJ.modDataHandler.getFlatXP(player)

	for i=1, Perks.getMaxIndex()-1 do
		---@type PerkFactory.Perk
		local perk = Perks.fromIndex(i)
		local gained, flatGained = SRJ.calculateGainedSkill(player, perk, startingLevels, deductibleXP, flatXP)
		if gained then
			gainedXP = gainedXP or {}
			gainedXP[perk:getId()] = gained
		end
		if flatGained then
			flatGainedXP = flatGainedXP or {}
			flatGainedXP[perk:getId()] = flatGained
		end
	end

	return gainedXP, flatGainedXP
end


function SRJ.getGainedRecipes(player, exclude)
	local gainedRecipes = {}

	-- get all recipes known by player
	---@type ArrayList
	local knownRecipes = player:getKnownRecipes()
	for i=0, knownRecipes:size()-1 do
		local recipeID = knownRecipes:get(i)
		gainedRecipes[recipeID] = true
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
		end
	end

	--- return iterable list
	local returnedGainedRecipes = {}
	for recipeID,_ in pairs(gainedRecipes) do
		if not exclude or exclude[recipeID] ~= true then
			table.insert(returnedGainedRecipes, recipeID)
		end
	end

	return returnedGainedRecipes
end


function SRJ.calculateGainedKills(journalModData, player, doReading)
	local killsRecoveryPercentage = SandboxVars.SkillRecoveryJournal.KillsTrack or 0
	if killsRecoveryPercentage < 0 then
		killsRecoveryPercentage = SandboxVars.SkillRecoveryJournal.RecoveryPercentage
	end
	
	if killsRecoveryPercentage == 0 then 
		return 0,0
 	end

    local zKills = 0
	local sKills = 0
	local accountedZombieKills = 0
	local accountedSurvivorKills = 0

    if doReading then
		local readXP = SRJ.modDataHandler.getReadXP(player)
        zKills = journalModData.kills and journalModData.kills.Zombie or 0
        sKills = journalModData.kills and journalModData.kills.Survivor or 0
        accountedZombieKills = readXP.kills and readXP.kills.Zombie or 0
        accountedSurvivorKills = readXP.kills and readXP.kills.Survivor or 0
    else
	    zKills = math.floor(player:getZombieKills() * (killsRecoveryPercentage / 100))
	    sKills = math.floor(player:getSurvivorKills() * (killsRecoveryPercentage / 100))
        accountedZombieKills = (journalModData.kills.Zombie or 0)
        accountedSurvivorKills = (journalModData.kills.Survivor or 0)
    end

    local unaccountedZKills = math.max(0, (zKills - accountedZombieKills))
    local unaccountedSKills = math.max(0, (sKills - accountedSurvivorKills))

	return unaccountedZKills, unaccountedSKills
end


function SRJ.calculateXpRate(perkID, xpToProcess, perkLevelPlusOne, durationData, actionTimeMulti, timeFactor, ratesTable)
    local differential = SRJ.xpHandler.getMaxXPDifferential(perkID) or 1

    if getDebug() then print("XP ", xpToProcess, " PlPO ", perkLevelPlusOne, " - multi ", actionTimeMulti, " - time factor ", timeFactor, " - diff ", differential) end

    local xpRate = round((math.sqrt(xpToProcess * perkLevelPlusOne) / 25) * actionTimeMulti * timeFactor / differential, 2)

    if xpRate and xpRate > 0 then
        local targetRates = ratesTable or durationData.rates
        targetRates[perkID] = xpRate
        local intervalsNeeded = math.ceil(xpToProcess / xpRate)
        if getDebug() then print(" - ", perkID, "- xprate = ", xpRate, ", ", xpToProcess, " (", intervalsNeeded, ")") end
        durationData.intervals = math.max(intervalsNeeded, durationData.intervals)
    end
end


-- Calculate rates and duration for read / writing
function SRJ.calculateReadWriteRates(player, item, timeFactor, gainedRecipes, gainedSkills, flatGainedSkills, doReading, updateInterval)

    local durationData = {
		rates = {},
		flatRates = {},
		intervals = 0,
		recipeChunk = 0,
        recipeInterval = 4,
		kills = {},
	}

    local journalModData = SRJ.modDataHandler.getItemModData(item)
    local readXP = SRJ.modDataHandler.getReadXP(player)
	local storedJournalXP = journalModData["gainedXP"] or {}

	local actionTimeMulti = SandboxVars.SkillRecoveryJournal.TranscribeSpeed or 1

	-- recipes
	if gainedRecipes and #gainedRecipes > 0 then
		durationData.recipeChunk = math.max(1, math.min(#gainedRecipes, math.floor(1.09^math.sqrt(#gainedRecipes)))) * actionTimeMulti
		local intervalsNeeded = math.ceil((#gainedRecipes / (durationData.recipeChunk / durationData.recipeInterval)))
        if getDebug() then print("New Recipes ", #gainedRecipes, " recipeChunk ", durationData.recipeChunk, " neededI ", intervalsNeeded) end
		durationData.intervals = math.max(intervalsNeeded,durationData.intervals)
	end

	if SRJ.modDataHandler.hasModDataToTransfer(player, item, doReading) then
		durationData.intervals = durationData.intervals + 1
	end

    -- xp
    if gainedSkills and not doReading then
        for perkID, xp in pairs(gainedSkills) do
            local xpToWrite = xp - (storedJournalXP[perkID] or 0)
            if xpToWrite > 0 then
                local perkLevelPlusOne = player:getPerkLevel(Perks[perkID]) + 1
                SRJ.calculateXpRate(perkID, xpToWrite, perkLevelPlusOne, durationData, actionTimeMulti, timeFactor)
            end
        end
    end

    if flatGainedSkills and not doReading then
        local storedFlatXP = journalModData.flatGainedXP or {}
        for perkID, xp in pairs(flatGainedSkills) do
            local xpToWrite = xp - (storedFlatXP[perkID] or 0)
            if xpToWrite > 0 then
                local perkLevelPlusOne = player:getPerkLevel(Perks[perkID]) + 1
                SRJ.calculateXpRate(perkID, xpToWrite, perkLevelPlusOne, durationData, actionTimeMulti, timeFactor, durationData.flatRates)
            end
        end
    end

    if doReading then
        local validSkills = {}
        local greatestXp = 0

        for skill, xp in pairs(storedJournalXP) do
            local perk = Perks[skill]
            if perk then
                local valid = SRJ.bSkillValid(perk)
                if valid then
                    validSkills[skill] = true
                    if skill == "NONE" or skill == "MAX" then
                        storedJournalXP[skill] = nil
                    else
                        if xp > greatestXp then greatestXp = xp end
                    end
                end
            end
        end

        journalModData.recoveryJournalXpLog = journalModData.recoveryJournalXpLog or {}
        local jmdUsedXP = journalModData.recoveryJournalXpLog
        local oneTimeUse = SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true
        local multipliers = SRJ.xpHandler.getOrStoreXPMultipliers(player)

        for perkID, journalXP in pairs(storedJournalXP) do
            if Perks[perkID] and validSkills[perkID] then
                local currentlyReadXP = readXP[perkID] or 0
                if oneTimeUse and jmdUsedXP[perkID] then
                    currentlyReadXP = math.max(currentlyReadXP, jmdUsedXP[perkID])
                end
                if currentlyReadXP < journalXP then
                    local xpToRead = journalXP - currentlyReadXP
                    local multi = multipliers[perkID] or 1
                    local perkLevelPlusOne = math.min(11, SRJ.xpHandler.getPerkLevelAfterJournalRead(SRJ, player, perkID, multi, journalXP) + 1)
                    SRJ.calculateXpRate(perkID, xpToRead, perkLevelPlusOne, durationData, actionTimeMulti, timeFactor)
                end
            end
        end

        local storedFlatJournalXP = journalModData.flatGainedXP or {}
        local readFlatXP = SRJ.modDataHandler.getReadFlatXP(player)
        for perkID, journalFlatXP in pairs(storedFlatJournalXP) do
            local perk = Perks[perkID]
            if perk and SRJ.bSkillValid(perk) then
                local currentlyReadFlatXP = readFlatXP[perkID] or 0
                if currentlyReadFlatXP < journalFlatXP then
                    local xpToRead = journalFlatXP - currentlyReadFlatXP
                    local perkLevelPlusOne = math.min(11, SRJ.xpHandler.getPerkLevelFromXP(perkID, journalFlatXP) + 1)
                    SRJ.calculateXpRate(perkID, xpToRead, perkLevelPlusOne, durationData, actionTimeMulti, timeFactor, durationData.flatRates)
                end
            end
        end
    end

	-- kills
    local gainedZombieKills, gainedSurvivorKills = SRJ.calculateGainedKills(journalModData, player, doReading)
    durationData.kills.Zombie = gainedZombieKills
    durationData.kills.Survivor = gainedSurvivorKills
    
    if gainedZombieKills > 0 or gainedSurvivorKills > 0 then
        durationData.rates.zKills = math.max(1, math.min(gainedZombieKills, math.floor(1.05^math.sqrt(gainedZombieKills)))) * actionTimeMulti
        durationData.rates.sKills = math.max(1, math.min(gainedSurvivorKills, math.floor(1.05^math.sqrt(gainedSurvivorKills)))) * actionTimeMulti
        durationData.intervals = math.max(durationData.intervals, math.max(math.ceil(gainedZombieKills / durationData.rates.zKills), math.ceil(gainedSurvivorKills / durationData.rates.sKills)))
    end

    durationData.durationTime = durationData.intervals * updateInterval * 60 * 60 * 3

	if getDebug() then print("SRJ DEBUG DURATION (in ticks) ", durationData.intervals, " (in in-game time) ", durationData.durationTime) for k,v in pairs(durationData.rates) do print(" - ",k," = ",v) end end

	return durationData
end