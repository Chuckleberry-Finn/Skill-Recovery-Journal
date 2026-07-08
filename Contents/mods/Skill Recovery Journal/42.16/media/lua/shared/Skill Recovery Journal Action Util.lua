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


function  SRJ.handleKills(durationData, player, journalModData, doReading, serverReadXP)

	local readXP = (isServer() and doReading and serverReadXP) or SRJ.modDataHandler.getReadXP(player)
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
		readXP.kills.Zombie = (readXP.kills.Zombie or 0) + zKillsAdded
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
		readXP.kills.Survivor = (readXP.kills.Survivor or 0) + sKillsAdded
	end

	return zKillsAdded, sKillsAdded
end


-- process one valid tick of reading / writing journal
function SRJ.processJournalTick(self, player, JMD, doReading)
    local changesMade = false
    local sayText = nil

    local ledgerKey   = isServer() and SRJ.modDataHandler.getLedgerKey(player) or nil
    local journalID = isServer() and SRJ.modDataHandler.buildJournalID(JMD) or nil
    local serverReadXP = (isServer() and doReading)
        and SRJ.modDataHandler.getServerReadXP(ledgerKey, journalID)
        or nil

    if serverReadXP then
        SRJ.modDataHandler.reconcileLedgerAge(player, serverReadXP)
    end

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

    -- readXP used for gating:
    local readXP = serverReadXP or SRJ.modDataHandler.getReadXP(player)

    if processXpMap then
        if doReading then
            JMD.recoveryJournalXpLog = JMD.recoveryJournalXpLog or {}
        end

        for perkID, perkXP in pairs(processXpMap) do
            local perk = Perks[perkID]
            if perk and SRJ.bSkillValid(perk) then

                local currentXP = readXP[perkID] or 0
                local rate = self.durationData.rates[perkID] or 0

                -- WRITE MODE: processXP → storedXP
                if not doReading then
                    local gained = perkXP
                    -- if gained xp is higher than stored xp
                    JMD.gainedXP[perkID] = JMD.gainedXP[perkID] or 0
                    if gained and gained > JMD.gainedXP[perkID] then
                        if rate > 0 then
                            changesMade = true

                            local resulting = math.min(gained, JMD.gainedXP[perkID] + rate)
                            JMD.gainedXP[perkID] = resulting
                            -- client-visible readXP so the UI is consistent
                            readXP[perkID] = math.max(resulting, currentXP)

                            -- server ledger to match, so that a read action cannot re-grant XP that was just written
                            if isServer() and ledgerKey and journalID then
                                local ledger = SRJ.modDataHandler.getServerReadXP(ledgerKey, journalID)
                                ledger[perkID] = math.max(resulting, ledger[perkID] or 0)
                            end

                            -- build halo text
                            local skillName = "IGUI_perks_" .. perkID
                            if not self.changesBeingMadeIndex[skillName] then
                                self.changesBeingMadeIndex[skillName] = true
                                table.insert(self.changesBeingMade, skillName)
                            end
                        end
                    end

                -- READ MODE: processXP → player XP
                else
                    local usedXP = JMD.recoveryJournalXpLog
                    local oneTimeUse = SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true

                    if oneTimeUse and usedXP[perkID] then
                        currentXP = math.max(currentXP, usedXP[perkID])
                    end

                    if currentXP < perkXP then
                        -- abort if max level
                        if player:getPerkLevel(perk) == 10 then
                            rate = false
                        end

                        -- if reading fitness, we have additional requirements
                        if perkID == "Fitness" then
                            local cannot, msg = SRJ.checkFitnessCanAddXp(player)
                            if cannot then
                                sayText = msg
                                rate = false
                            end
                        end

                        if rate and rate > 0 then
                            -- normalize rate
                            if currentXP + rate > perkXP then
                                rate = math.max(perkXP - currentXP, 0.001)
                            end

                            -- advance the authoritative ledger (server read path)
                            readXP[perkID] = currentXP + rate
                            -- and in journal for decay / oneTimeUse tracking
                            usedXP[perkID] = (usedXP[perkID] or 0) + rate

                            local addedXP = SRJ.xpHandler.reBoostXP(player, perk, rate)
                            SRJ.modDataHandler.setSRJAddingFlatXP(true)
                            addXpNoMultiplier(player, perk, addedXP)
                            SRJ.modDataHandler.setSRJAddingFlatXP(false)

                            changesMade = true

                            -- build halo text
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

                    -- stamp server ledger for flat XP as well (write path)
                    if isServer() and ledgerKey and journalID then
                        local ledger = SRJ.modDataHandler.getServerReadXP(ledgerKey, journalID)
                        -- flat XP is keyed separately; use a prefix to avoid collision with gainedXP keys
                        local flatKey = "flat|" .. perkID
                        ledger[flatKey] = math.max(resulting, ledger[flatKey] or 0)
                    end

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
        local serverReadFlatXP = serverReadXP
        local readFlatXP = SRJ.modDataHandler.getReadFlatXP(player)

        for perkID, journalFlatXP in pairs(JMD.flatGainedXP) do
            local perk = Perks[perkID]
            if perk and SRJ.bSkillValid(perk) then

                local flatKey = "flat|" .. perkID
                local currentFlatXP
                if isServer() and serverReadFlatXP then
                    currentFlatXP = serverReadFlatXP[flatKey] or 0
                else
                    currentFlatXP = readFlatXP[perkID] or 0
                end

                local flatRate = self.durationData.flatRates[perkID] or 0
                if currentFlatXP < journalFlatXP then
                    if player:getPerkLevel(perk) == 10 then flatRate = false end
                    if flatRate and flatRate > 0 then
                        if currentFlatXP + flatRate > journalFlatXP then
                            flatRate = math.max(journalFlatXP - currentFlatXP, 0.001)
                        end

                        if isServer() and serverReadFlatXP then
                            serverReadFlatXP[flatKey] = currentFlatXP + flatRate
                        end
                        readFlatXP[perkID] = currentFlatXP + flatRate
                        addXpNoMultiplier(player, perk, flatRate)
                        changesMade = true
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
        local zombies, survivors = SRJ.handleKills(self.durationData, player, JMD, doReading, serverReadXP)

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
