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

	if protections <= 2  and pSteamID ~= 0 then
        -- return false if steamID set and does not match
		if journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
			return false
		end
        -- set steamID if available
		if pSteamID then
			journalID["steamID"] = pSteamID
		end
	end

	if protections == 1 then
        -- return false if username set and does not match
		if pUsername and journalID["username"] and (journalID["username"] ~= pUsername) then
			return false
		end
        -- set username if available and not set
		if pUsername and (not journalID["username"]) then
			journalID["username"] = pUsername
		end
	end

	return true
end


-- used for isValid. Checking conditions that do not change during action runtime.
function SRJ.checkStaticConditions(player, JMD, doReading)

	-- for reading, check if journal contains writing
	if doReading and (not JMD or not JMD["ID"]) then
		return false, "IGUI_PlayerText_NothingWritten"

	-- check illiterate
	elseif player:hasTrait(CharacterTrait.ILLITERATE) then
		return false, "IGUI_PlayerText_IGUI_PlayerText_Illiterate"
	
	-- check permissions
	elseif not SRJ.handleIdentity(player, JMD) then
		return false, "IGUI_PlayerText_DoesntFeelRightToWrite"
	end
	
	return true
end


function  SRJ.handleKills(durationData, player, journalModData, doReading)
	local readXP = SRJ.modDataHandler.getReadXP(player)
	local zKillGainRate = math.ceil((durationData.kills.Zombie or 0) / (durationData.intervals * 0.5)) -- kill processing will be completed after ~50% or earlier
	local sKillGainRate = math.ceil((durationData.kills.Survivor or 0) / (durationData.intervals * 0.5))
	--if getDebug() then print("--handleKills - Z", zKillGainRate,", S",  sKillGainRate) end

	if (zKillGainRate > 0) then
		local newZKills = 0
		if doReading then
			newZKills = zKillGainRate + player:getZombieKills()
			newZKills = math.min(newZKills, journalModData.kills.Zombies) -- max is stored value
			player:setZombieKills(newZKills) 
			if isServer() then
				-- let the client know about the change
				sendServerCommand(player, "SkillRecoveryJournal", "zKills", {kills = newZKills})
			end
		else
			newZKills = zKillGainRate + (journalModData.kills.Zombie or 0)
			newZKills = math.min(newZKills, player:getZombieKills()) -- max is player value
			journalModData.kills.Zombie = newZKills
		end
		readXP.kills.Zombie = (readXP.kills.Zombie or 0) + zKillGainRate
	end

	if (sKillGainRate > 0) then
		local newSKills = 0
		if doReading then
		 	newSKills = sKillGainRate + (player:getSurvivorKills() or 0)
			newSKills = math.min(newSKills, journalModData.kills.Survivor) -- max is stored value
			player:setSurvivorSKills(newSKills)
			if isServer() then
				-- let the client know about the change
				sendServerCommand(player, "SkillRecoveryJournal", "sKills", {kills = newSKills})
			end
		else
		 	newSKills = sKillGainRate + (journalModData.kills.Survivor or 0)
			newSKills = math.min(newSKills, player:getSurvivorKills()) -- max is player value
			journalModData.kills.Survivor = newSKills
		end
		readXP.kills.Survivor = (readXP.kills.Survivor or 0) + sKillGainRate
	end

	return zKillGainRate, sKillGainRate
end


-- process one valid tick of reading / writing journal
function SRJ.processJournalTick(self, player, JMD, doReading)
    local changesMade = false
    local sayText = nil

    -- RECIPES
    local recipeList = self.gainedRecipes
    if #recipeList > 0 then
        local chunk = self.durationData.recipeChunk
        if chunk > 0 and self.updates % self.durationData.recipeInterval == 0 then
            changesMade = true
            for i = 1, chunk do
                local recipeID = recipeList[#recipeList]
                if not recipeID then break end

                if doReading then
                    player:learnRecipe(recipeID)
                    -- if server, sync recipes with client
                    if isServer() and sendSyncPlayerFields then
                        sendSyncPlayerFields(player, 0x00000001)
                    end
                else
                    -- store recipe in journal
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
                            -- store amount as already read in player data, so it cant be gained again
                            readXP[perkID] = math.max(resulting, currentXP)

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

                            -- store amount already red in player data
                            readXP[perkID] = currentXP + rate
                            -- and in journal for decay
                            usedXP[perkID] = (usedXP[perkID] or 0) + rate

                            local addedXP = SRJ.xpHandler.reBoostXP(player, perk, rate)
                            addXpNoMultiplier(player, perk, addedXP)

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

    -- KILLS
    local killsEnabled = self.durationData.kills.Zombie > 0 or self.durationData.kills.Survivor > 0
    if killsEnabled and JMD.kills then
		-- continue if new kills to write / read
        local cond =
            (not doReading and (
                (player:getZombieKills() or 0) > (JMD.kills.Zombie or 0) or
                (player:getSurvivorKills() or 0) > (JMD.kills.Survivor or 0)
            ))
            or
            (doReading and (
                (JMD.kills.Zombie or 0) > (readXP.kills.Zombie or 0) or
                (JMD.kills.Survivor or 0) > (readXP.kills.Survivor or 0)
            ))

        if cond then
            local zombies, survivors = SRJ.handleKills(self.durationData, player, JMD, doReading)

            if survivors > 0 then
                self.changesBeingMadeIndex.survivors  = (self.changesBeingMadeIndex.survivors or 0) + survivors
                changesMade = true
            end

            if zombies > 0 then
                self.changesBeingMadeIndex.zombies =  (self.changesBeingMadeIndex.zombies or 0) + zombies
                changesMade = true
            end
        end
    end

    -- CUSTOM MOD DATA
    if doReading then
        if not self.modDataReadComplete then
            self.modDataReadComplete = true
            local data = SRJ.modDataHandler.copyDataToPlayer(player, self.item)
            if data then
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
            if data then
                for _, id in pairs(data) do
                    table.insert(self.changesBeingMade, id)
                end
                changesMade = true
            end
        end
    end

    -- FEEDBACK
    if not changesMade then
        if doReading then
            sayText = sayText or "IGUI_PlayerText_KnowSkill"
        else
            sayText = self.wroteNewContent
                and "IGUI_PlayerText_AllDoneWithJournal"
                or  "IGUI_PlayerText_NothingToAddToJournal"
        end
    else
        -- in writing, server needs to sync mod data with client
        if not doReading then
            self.wroteNewContent = true
            if isServer() then
                syncItemModData(player, self.item)
            end
        end
    end

    return changesMade, sayText
end
