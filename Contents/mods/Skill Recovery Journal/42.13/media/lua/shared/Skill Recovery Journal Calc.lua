local SRJ = require "Skill Recovery Journal Main"

-- returns all gained skills as per config or false if no valid skill xp gained
function SRJ.calculateGainedSkill(player, perk, passiveSkillsInit, startingLevels, deductibleXP)

	if not passiveSkillsInit then
		passiveSkillsInit = SRJ.modDataHandler.getPassiveLevels(player)
	end

	if not startingLevels then
		startingLevels = SRJ.modDataHandler.getFreeLevelsFromTraitsAndProfession(player)
	end

	if not deductibleXP then
		deductibleXP = SRJ.modDataHandler.getDeductedXP(player)
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

	local passiveSkillsInit = SRJ.modDataHandler.getPassiveLevels(player)
	local startingLevels = SRJ.modDataHandler.getFreeLevelsFromTraitsAndProfession(player)
	local deductibleXP = SRJ.modDataHandler.getDeductedXP(player)

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


function SRJ.getGainedRecipes(player, exclude)
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
		if not exclude or exclude[recipeID] ~= true then
			-- TODO: remove auto learned recipes from skills (maybe we had higher level/xpBoost last life)
			table.insert(returnedGainedRecipes, recipeID)
			--if getDebug() then print("Resulting gained recipe " .. tostring(recipeID) .. " -> " .. tostring(_)) end
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
       -- read journal kills
        zKills = journalModData.kills and journalModData.kills.Zombie or 0
        sKills = journalModData.kills and journalModData.kills.Survivor or 0

        -- dont count kills already read 
        accountedZombieKills = readXP.kills and readXP.kills.Zombie or 0
        accountedSurvivorKills = readXP.kills and readXP.kills.Survivor or 0

    else
        -- write player kills
	    zKills = math.floor(player:getZombieKills() * (killsRecoveryPercentage / 100))
	    sKills = math.floor(player:getSurvivorKills() * (killsRecoveryPercentage / 100))

        -- dont count kills already transcribed 
        accountedZombieKills = (journalModData.kills.Zombie or 0)
        accountedSurvivorKills = (journalModData.kills.Survivor or 0)
    end

    local unaccountedZKills = math.max(0, (zKills - accountedZombieKills))
    local unaccountedSKills = math.max(0, (sKills - accountedSurvivorKills))

	return unaccountedZKills, unaccountedSKills
end


function SRJ.calculateXpRate(perkID, xpToProcess, perkLevelPlusOne, durationData, actionTimeMulti, timeFactor)
    local differential = SRJ.xpHandler.getMaxXPDifferential(perkID) or 1

    if getDebug() then print("XP ", xpToProcess, " PlPO ", perkLevelPlusOne, " - multi ", actionTimeMulti, " - time factor ", timeFactor, " - diff ", differential) end

    local xpRate = round((math.sqrt(xpToProcess * perkLevelPlusOne) / 25) * actionTimeMulti * timeFactor / differential, 2)

    if xpRate and xpRate > 0 then
        durationData.rates[perkID] = xpRate
        local intervalsNeeded = math.ceil(xpToProcess / xpRate)
        if getDebug() then print(" - ", perkID, "- xprate = ", xpRate, ", ", xpToProcess, " (", intervalsNeeded, ")") end
        durationData.intervals = math.max(intervalsNeeded, durationData.intervals)
    end
end


-- Calculate rates and duration for read / writing
function SRJ.calculateReadWriteRates(player, item, timeFactor, gainedRecipes, gainedSkills, doReading, updateInterval)

    local durationData = {
		rates = {},
		intervals = 0,
		recipeChunk = 0,
        recipeInterval = 4, -- update recipes every 4th update
		kills = {},
	}

    local journalModData = SRJ.modDataHandler.getItemModData(item)
    local readXP = SRJ.modDataHandler.getReadXP(player)
	local storedJournalXP = journalModData["gainedXP"] or {}

	local actionTimeMulti = SandboxVars.SkillRecoveryJournal.TranscribeSpeed or 1

	-- recipes
	if gainedRecipes and #gainedRecipes > 0 then
		durationData.recipeChunk = math.min(#gainedRecipes, math.floor(1.09^math.sqrt(#gainedRecipes))) * actionTimeMulti
		local intervalsNeeded = math.ceil((#gainedRecipes / (durationData.recipeChunk / durationData.recipeInterval)))
        if getDebug() then print("New Recipes ", #gainedRecipes, " recipeChunk ", durationData.recipeChunk, " neededI ", intervalsNeeded) end
		durationData.intervals = math.max(intervalsNeeded,durationData.intervals)
	end

	-- modData
    local modDataStored
    if doReading then
        --- the CopyData function actually does the copying - we need a function to JUST check if the data exists for this step
	    modDataStored = SRJ.modDataHandler.copyDataToPlayer(player, item)
    else
	    modDataStored = SRJ.modDataHandler.copyDataToJournal(player, item)
    end
	if modDataStored then durationData.intervals = durationData.intervals+1 end

    -- xp
    if gainedSkills and not doReading then
        -- write gainedSkills
        for perkID, xp in pairs(gainedSkills) do
            local xpToWrite = xp - (storedJournalXP[perkID] or 0)

            if xpToWrite > 0 then
                local perkLevelPlusOne = player:getPerkLevel(Perks[perkID]) + 1
                SRJ.calculateXpRate(perkID, xpToWrite, perkLevelPlusOne, durationData, actionTimeMulti, timeFactor)
            end
        end
    elseif doReading then
        -- read journal
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

                readXP[perkID] = readXP[perkID] or 0
                local currentlyReadXP = readXP[perkID]

                if oneTimeUse and jmdUsedXP[perkID] then
                    currentlyReadXP = math.max(currentlyReadXP, jmdUsedXP[perkID])
                end

                if currentlyReadXP < journalXP then
                    local xpToRead = journalXP - currentlyReadXP
                    local multi = multipliers[perkID] or 1

					-- for perkLevelPlusOne assume we have acquired the skill xp we are heading for (max 10 +1)
                    local perkLevelPlusOne = math.min(11, SRJ.xpHandler.getPerkLevelAfterJournalRead(SRJ, player, perkID, multi, journalXP) + 1)
                    SRJ.calculateXpRate(perkID, xpToRead, perkLevelPlusOne, durationData, actionTimeMulti, timeFactor)
                end
            end
        end
    end

	-- kills
    local gainedZombieKills, gainedSurvivorKills = SRJ.calculateGainedKills(journalModData, player, doReading)
    durationData.kills.Zombie = gainedZombieKills
    durationData.kills.Survivor = gainedSurvivorKills
    
    if gainedZombieKills > 0 or gainedSurvivorKills > 0 then
        durationData.rates.zKills = math.min(gainedZombieKills, math.floor(1.05^math.sqrt(gainedZombieKills))) * actionTimeMulti
        durationData.rates.sKills = math.min(gainedSurvivorKills, math.floor(1.05^math.sqrt(gainedSurvivorKills))) * actionTimeMulti
        -- interval is either old interval or kills per rate
        durationData.intervals = math.max(durationData.intervals, math.max(math.ceil(gainedZombieKills / durationData.rates.zKills), math.ceil(gainedSurvivorKills / durationData.rates.sKills)))
    end

    durationData.durationTime = durationData.intervals * updateInterval * 60 * 60 * 3

	if getDebug() then print("SRJ DEBUG DURATION (in ticks) ", durationData.intervals, " (in in-game time) ", durationData.durationTime) for k,v in pairs(durationData.rates) do print(" - ",k," = ",v) end end

	return durationData
end