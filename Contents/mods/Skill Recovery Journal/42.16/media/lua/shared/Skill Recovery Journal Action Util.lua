local SRJ = require "Skill Recovery Journal Main"


function SRJ.handleIdentity(player, JMD)

	local journalID = JMD["ID"]
	if journalID == nil then return true end
	local pSteamID = player:getSteamID()
	local pUsername = player:getUsername()

	local protections = SandboxVars.SkillRecoveryJournal.SecurityFeatures or 1
	---1 = "Prevent Username/SteamID Mismatch"
	---2 = "Only Prevent SteamID Mismatch",
	---3 = "Don't Prevent Mismatches",

	if protections <= 2 and pSteamID ~= 0 then
		if journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
			return false
		end
		journalID["steamID"] = pSteamID
	end

	if protections == 1 then
		if pUsername and journalID["username"] and (journalID["username"] ~= pUsername) then
			return false
		end
		if pUsername and (not journalID["username"]) then
			journalID["username"] = pUsername
		end
	end

	return true
end


function SRJ.checkStaticConditions(player, JMD, doReading)

	if doReading and (not JMD or not JMD["ID"]) then
		return false, "IGUI_PlayerText_NothingWritten"

	elseif player:hasTrait(CharacterTrait.ILLITERATE) then
		return false, "IGUI_PlayerText_Illiterate"

	elseif (isClient() or isServer()) and not SRJ.handleIdentity(player, JMD) then
		return false, (doReading and "IGUI_PlayerText_DoesntFeelRightToRead") or "IGUI_PlayerText_DoesntFeelRightToWrite"
	end
	
	return true
end


function  SRJ.handleKills(durationData, player, journalModData, doReading)

    local zKillGainRate = durationData.rates.zKills
    local sKillGainRate = durationData.rates.sKills
	--if getDebug() then print("--handleKills - Z", zKillGainRate,", S",  sKillGainRate) end

    local zKillsAdded, sKillsAdded = 0, 0

	if (zKillGainRate > 0) then
        local oldZKills = 0
		local newZKills = 0
		if doReading then
            oldZKills = player:getZombieKills() or 0
			newZKills = zKillGainRate + oldZKills
			newZKills = math.min(newZKills, journalModData.kills.Zombie)
			player:setZombieKills(newZKills) 
			if isServer() then
				sendServerCommand(player, "SkillRecoveryJournal", "zKills", {kills = newZKills})
			end
		else
            oldZKills = journalModData.kills.Zombie or 0
			newZKills = zKillGainRate + oldZKills
			newZKills = math.min(newZKills, player:getZombieKills())
			journalModData.kills.Zombie = newZKills
		end
        zKillsAdded = newZKills - oldZKills
	end

	if (sKillGainRate > 0) then
        local oldSKills = 0
		local newSKills = 0
		if doReading then
            oldSKills = player:getSurvivorKills() or 0
		 	newSKills = sKillGainRate + oldSKills
			newSKills = math.min(newSKills, journalModData.kills.Survivor)
			player:setSurvivorKills(newSKills)
			if isServer() then
				sendServerCommand(player, "SkillRecoveryJournal", "sKills", {kills = newSKills})
			end
		else
            oldSKills = journalModData.kills.Survivor or 0
		 	newSKills = sKillGainRate + oldSKills
			newSKills = math.min(newSKills, player:getSurvivorKills())
			journalModData.kills.Survivor = newSKills
		end
        sKillsAdded = newSKills - oldSKills
	end

	return zKillsAdded, sKillsAdded
end


-- process one valid tick of reading / writing journal
function SRJ.processJournalTick(self, player, JMD, doReading)
    local changesMade = false
    local sayText = nil

    -- RECIPES
    local recipeList = self.gainedRecipes
    if #recipeList > 0 then
        changesMade = true
        local chunk = self.durationData.recipeChunk
        if chunk > 0 and self.updates % self.durationData.recipeInterval == 0 then
            for i = 1, chunk do
                local recipeID = recipeList[#recipeList]
                if not recipeID then break end

                if doReading then
                    player:learnRecipe(recipeID)
                    if isServer() and sendSyncPlayerFields then
                        sendSyncPlayerFields(player, 0x00000001)
                    end
                else
                    JMD.learnedRecipes[recipeID] = true
                end

                table.remove(recipeList)
                self.changesBeingMadeIndex.recipes =
                    (self.changesBeingMadeIndex.recipes or 0) + 1
            end
        end
    end

    -- XP - on read process journal xp, otherwise player xp
    local processXpMap = (doReading and JMD.gainedXP) or self.gainedSkills

    local readXP = SRJ.modDataHandler.getReadXP(player)

    if processXpMap then
        for perkID, perkXP in pairs(processXpMap) do
            local perk = Perks[perkID]
            if perk and SRJ.bSkillValid(perk) then

                local rate = self.durationData.rates[perkID] or 0

                -- WRITE MODE: processXP → storedXP
                if not doReading then
                    local currentXP = readXP[perkID] or 0
                    local gained = perkXP
                    JMD.gainedXP[perkID] = JMD.gainedXP[perkID] or 0
                    if gained and gained > JMD.gainedXP[perkID] then
                        if rate > 0 then
                            changesMade = true
                            local resulting = math.min(gained, JMD.gainedXP[perkID] + rate)
                            JMD.gainedXP[perkID] = resulting
                            readXP[perkID] = math.max(resulting, currentXP)

                            local skillName = "IGUI_perks_" .. perkID
                            if not self.changesBeingMadeIndex[skillName] then
                                self.changesBeingMadeIndex[skillName] = true
                                table.insert(self.changesBeingMade, skillName)
                            end
                        end
                    end

                else
                    local cap = isServer() and SRJ.ledger.getRedemptionRecord(self.item, player, perkID, false) or nil
                    local currentXP = cap and cap.granted or (readXP[perkID] or 0)

                    if currentXP < perkXP then
                        if player:getPerkLevel(perk) == 10 then
                            rate = false
                        end

                        if perkID == "Fitness" then
                            local cannot, msg = SRJ.checkFitnessCanAddXp(player)
                            if cannot then
                                sayText = msg
                                rate = false
                            end
                        end

                        if rate and rate > 0 then
                            if currentXP + rate > perkXP then
                                rate = math.max(perkXP - currentXP, 0.001)
                            end

                            if cap then cap.granted = currentXP + rate end
                            readXP[perkID] = currentXP + rate

                            local addedXP = SRJ.xpHandler.reBoostXP(player, perk, rate)
                            SRJ.modDataHandler.setSRJAddingFlatXP(true)
                            addXpNoMultiplier(player, perk, addedXP)
                            SRJ.modDataHandler.setSRJAddingFlatXP(false)

                            changesMade = true

                            if isServer() then SRJ.ledger.sealIfOneTimeUse(self.item, player) end

                            local skillName = "IGUI_perks_" .. perkID
                            if not self.changesBeingMadeIndex[skillName] then
                                self.changesBeingMadeIndex[skillName] = true
                                table.insert(self.changesBeingMade, skillName)
                            end
                        end
                    end
                end
            end
        end
    end

    -- FLAT XP
    local processFlatXpMap = (not doReading) and self.flatGainedSkills
    if processFlatXpMap then
        JMD.flatGainedXP = JMD.flatGainedXP or {}
        local readFlatXP = SRJ.modDataHandler.getReadFlatXP(player)
        for perkID, perkFlatXP in pairs(processFlatXpMap) do
            local perk = Perks[perkID]
            if perk and SRJ.bSkillValid(perk) then
                local currentFlatXP = readFlatXP[perkID] or 0
                local flatRate = self.durationData.flatRates[perkID] or 0
                JMD.flatGainedXP[perkID] = JMD.flatGainedXP[perkID] or 0
                if perkFlatXP > JMD.flatGainedXP[perkID] and flatRate > 0 then
                    changesMade = true
                    local resulting = math.min(perkFlatXP, JMD.flatGainedXP[perkID] + flatRate)
                    JMD.flatGainedXP[perkID] = resulting
                    readFlatXP[perkID] = math.max(resulting, currentFlatXP)

                    local skillName = "IGUI_perks_" .. perkID
                    if not self.changesBeingMadeIndex[skillName] then
                        self.changesBeingMadeIndex[skillName] = true
                        table.insert(self.changesBeingMade, skillName)
                    end
                end
            end
        end
    end

    if doReading and JMD.flatGainedXP then
        local readFlatXP = SRJ.modDataHandler.getReadFlatXP(player)

        for perkID, journalFlatXP in pairs(JMD.flatGainedXP) do
            local perk = Perks[perkID]
            if perk and SRJ.bSkillValid(perk) then

                local cap = isServer() and SRJ.ledger.getRedemptionRecord(self.item, player, perkID, true) or nil
                local currentFlatXP = cap and cap.granted or (readFlatXP[perkID] or 0)

                local flatRate = self.durationData.flatRates[perkID] or 0
                if currentFlatXP < journalFlatXP then
                    if player:getPerkLevel(perk) == 10 then flatRate = false end
                    if flatRate and flatRate > 0 then
                        if currentFlatXP + flatRate > journalFlatXP then
                            flatRate = math.max(journalFlatXP - currentFlatXP, 0.001)
                        end

                        if cap then cap.granted = currentFlatXP + flatRate end
                        readFlatXP[perkID] = currentFlatXP + flatRate
                        addXpNoMultiplier(player, perk, flatRate)
                        changesMade = true

                        if isServer() then SRJ.ledger.sealIfOneTimeUse(self.item, player) end

                        local skillName = "IGUI_perks_" .. perkID
                        if not self.changesBeingMadeIndex[skillName] then
                            self.changesBeingMadeIndex[skillName] = true
                            table.insert(self.changesBeingMade, skillName)
                        end
                    end
                end
            end
        end
    end

    -- KILLS
    local killsEnabled = self.durationData.kills.Zombie > 0 or self.durationData.kills.Survivor > 0
    if killsEnabled and not self.killsComplete then
        local zombies, survivors = SRJ.handleKills(self.durationData, player, JMD, doReading)

        if survivors > 0 then
            self.changesBeingMadeIndex.survivors = (self.changesBeingMadeIndex.survivors or 0) + survivors
            changesMade = true
        end

        if zombies > 0 then
            self.changesBeingMadeIndex.zombies = (self.changesBeingMadeIndex.zombies or 0) + zombies
            changesMade = true
        end

        if zombies == 0 and survivors == 0 then
            self.killsComplete = true
        end
    end

    -- CUSTOM MOD DATA
    if doReading then
        if not self.modDataReadComplete then
            self.modDataReadComplete = true
            local data = SRJ.modDataHandler.copyDataToPlayer(player, self.item)
            if data and #data > 0 then
                for _, id in pairs(data) do
                    table.insert(self.changesBeingMade, id)
                end
                changesMade = true
            end
        end
    else
        if not self.modDataStoredComplete then
            self.modDataStoredComplete = true
            local data = SRJ.modDataHandler.copyDataToJournal(player, self.item)
            if data and #data > 0 then
                for _, id in pairs(data) do
                    table.insert(self.changesBeingMade, id)
                end
                changesMade = true
            end
        end
    end

    if not changesMade then
        if doReading then
            sayText = sayText or "IGUI_PlayerText_KnowSkill"
        else
            sayText = self.wroteNewContent
                and "IGUI_PlayerText_AllDoneWithJournal"
                or  "IGUI_PlayerText_NothingToAddToJournal"
        end
    else
        if not doReading then
            self.wroteNewContent = true
            if isServer() then
                syncItemModData(player, self.item)
            end
        end
    end

    return changesMade, sayText
end
